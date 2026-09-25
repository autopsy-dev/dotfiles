#!/usr/bin/env python3
"""Plan or install portable rEFInd + graphical LUKS settings on Arch/CachyOS."""
import argparse
import configparser
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parent
CONFIG = Path('/etc/graphical-unlock')
BUILDER = Path('/usr/local/sbin/update-graphical-unlock')
HOOK = Path('/etc/initcpio/install/graphical-unlock')
POST = Path('/etc/initcpio/post/99-graphical-unlock')
BACKUPS = Path('/var/backups/graphical-unlock')
MARKER = 'graphical-unlock managed entry'


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def token(value):
    if not value or not re.fullmatch(r'[A-Za-z0-9_/@.:+-]+', value):
        raise ValueError('Unsupported characters in a detected disk identifier or path.')
    return value


def storage(root, tree):
    """Accept a filesystem directly inside one LUKS container, never guess stacks."""
    if root['fstype'] not in {'ext4', 'btrfs'}:
        raise ValueError('Supported root filesystems: ext4 and single-device Btrfs.')
    if tree['type'] != 'crypt' or len(tree.get('children', [])) != 1:
        raise ValueError('Root must be directly inside LUKS; LVM/RAID stacks are unsupported.')
    parent = tree['children'][0]
    if parent['type'] not in {'part', 'disk'} or parent['fstype'] != 'crypto_LUKS':
        raise ValueError('Expected a single LUKS partition or disk immediately below root.')
    root_uuid = token(root.get('uuid') or tree.get('uuid'))
    luks_uuid = token(parent.get('uuid'))
    subvol = token(root.get('fsroot') or '/') if root['fstype'] == 'btrfs' else None
    return root_uuid, luks_uuid, subvol


def command_line(root_uuid, luks_uuid, subvol, nvidia):
    args = [f'root=UUID={token(root_uuid)}', 'rw']
    if subvol:
        args.append(f'rootflags=subvol={token(subvol)}')
    args += [f'rd.luks.uuid={token(luks_uuid)}', 'quiet', 'splash', 'loglevel=3',
             'plymouth.use-simpledrm']
    if nvidia:
        args += ['nvidia_drm.modeset=1', 'nvidia_drm.fbdev=1']
    return ' '.join(args)


def detect(args):
    if platform.machine() != 'x86_64' or not Path('/sys/firmware/efi').is_dir():
        raise ValueError('Requires x86_64 UEFI boot.')
    os_release = platform.freedesktop_os_release()
    if os_release.get('ID') not in {'arch', 'cachyos'}:
        raise ValueError('This installer supports Arch Linux and CachyOS with mkinitcpio.')
    secure = list(Path('/sys/firmware/efi/efivars').glob('SecureBoot-*'))
    if len(secure) != 1 or secure[0].read_bytes()[4:] != b'\x00':
        raise ValueError('Secure Boot must already be disabled; signing is not implemented.')
    for executable in ['mkinitcpio', 'lsinitcpio', 'objcopy', 'findmnt', 'lsblk', 'blkid', 'plymouth-set-default-theme']:
        if not shutil.which(executable):
            raise ValueError(f'Missing required command: {executable}')
    root = json.loads(output('findmnt', '-J', '-o', 'SOURCE,UUID,FSTYPE,FSROOT', '--target', '/'))['filesystems'][0]
    device = root['source'].split('[', 1)[0]
    trees = json.loads(output('lsblk', '-s', '-J', '-p', '-o', 'NAME,TYPE,FSTYPE,UUID', device))['blockdevices']
    if len(trees) != 1:
        raise ValueError('Ambiguous root block-device ancestry.')
    if not root.get('uuid'):
        root['uuid'] = output('blkid', '-s', 'UUID', '-o', 'value', device)
    root_uuid, luks_uuid, subvol = storage(root, trees[0])
    if root['fstype'] == 'btrfs':
        if not shutil.which('btrfs') or not re.search(r'Total devices\s+1\b', output('btrfs', 'filesystem', 'show', '/')):
            raise ValueError('Only single-device Btrfs is supported.')
    mounts = json.loads(output('findmnt', '-J', '-l', '-t', 'vfat', '-o', 'TARGET,FSTYPE,OPTIONS'))['filesystems']
    candidates = []
    for mount in mounts:
        esp = Path(mount['target'])
        for efi in esp.iterdir():
            if efi.name.lower() != 'efi' or not efi.is_dir():
                continue
            for directory in efi.iterdir():
                if not directory.is_dir():
                    continue
                names = {p.name.lower(): p for p in directory.iterdir()}
                if 'refind.conf' in names and 'refind_x64.efi' in names:
                    candidates.append((esp, directory, names['refind.conf'], mount['options']))
    if args.refind_dir:
        candidates = [c for c in candidates if c[1].resolve() == args.refind_dir.resolve()]
    if len(candidates) != 1:
        raise ValueError('Expected one mounted rEFInd installation; specify --refind-dir if ambiguous.')
    esp, refind, menu, mount_options = candidates[0]
    if 'rw' not in mount_options.split(','):
        raise ValueError('The EFI partition must be mounted read-write.')
    # Choose the running kernel package, not whichever filename sorts first.
    pkgfile = Path('/usr/lib/modules') / platform.release() / 'pkgbase'
    kernel = args.kernel
    if not kernel and pkgfile.is_file():
        kernel = Path('/boot/vmlinuz-' + token(pkgfile.read_text().strip()))
    if not kernel or not kernel.is_file():
        raise ValueError('Cannot identify the installed kernel; supply --kernel /boot/vmlinuz-...')
    vendors = set()
    for pci in Path('/sys/bus/pci/devices').iterdir():
        if (pci / 'class').read_text().strip().startswith('0x03'):
            vendors.add((pci / 'vendor').read_text().strip())
    theme = next((name for name in ['cachyos', 'spinner']
                  if (Path('/usr/share/plymouth/themes') / name / (name + '.plymouth')).is_file()), None)
    if not theme:
        raise ValueError('Install a CachyOS or spinner Plymouth theme first.')
    theme_file = Path('/usr/share/plymouth/themes') / theme / (theme + '.plymouth')
    parsed = configparser.ConfigParser()
    parsed.read(theme_file)
    if parsed.get('Plymouth Theme', 'ModuleName') != 'two-step':
        raise ValueError('The selected Plymouth theme must use the two-step plugin.')
    # A dedicated key-free crypttab is generated; existing key paths only feed a local leakage check.
    key_paths = set()
    if Path('/crypto_keyfile.bin').is_file():
        key_paths.add('/crypto_keyfile.bin')
    for table in [Path('/etc/crypttab'), Path('/etc/crypttab.initramfs')]:
        if table.exists():
            for line in table.read_text().splitlines():
                fields = line.split('#', 1)[0].split()
                if len(fields) >= 3 and fields[2] not in {'none', '-'}:
                    key = fields[2]
                    if not key.startswith('/') or not Path(key).is_file():
                        raise ValueError('An existing crypttab key source needs manual review.')
                    key_paths.add(key)
    return dict(root_uuid=root_uuid, luks_uuid=luks_uuid, subvol=subvol,
                kernel=str(kernel.resolve()), esp=str(esp), refind=str(refind), menu=str(menu),
                target=str(refind / 'graphical-unlock/cachyos.efi'), theme=theme,
                title=('CachyOS' if os_release['ID'] == 'cachyos' else 'Arch Linux') + ' - graphical unlock',
                graphics=sorted(vendors), key_paths=sorted(key_paths),
                cmdline=command_line(root_uuid, luks_uuid, subvol, '0x10de' in vendors))


def menu_text(original, state):
    pattern = r'\n?# BEGIN ' + MARKER + r'\n.*?# END ' + MARKER + r'\n?'
    if original.count('# BEGIN ' + MARKER) != original.count('# END ' + MARKER):
        raise ValueError('Malformed existing managed entry.')
    clean, count = re.subn(pattern, '\n', original, flags=re.S)
    if count > 1:
        raise ValueError('Multiple managed entries; refusing to guess.')
    scans = re.findall(r'(?mi)^\s*scanfor\s+([^#\n]+)', clean)
    if scans and 'manual' not in re.split(r'[\s,]+', scans[-1].strip().lower()):
        raise ValueError('The current scanfor setting excludes manual entries; enable manual first.')
    # The theme include must live in the main file (rEFInd disallows nested includes).
    clean = re.sub(r'(?m)^\s*include\s+themes/refind-calm/theme\.conf\s*$', '', clean)
    relative = Path(state['target']).relative_to(state['esp']).as_posix()
    icon = (Path(state['refind']).relative_to(state['esp']) / 'themes/refind-calm/icons/os_linux.png').as_posix()
    return clean.rstrip() + f'''\n\n# BEGIN {MARKER}
textonly 0
include themes/refind-calm/theme.conf
showtools hidden_tags
menuentry "{state['title']}" {{
    loader /{relative}
    icon /{icon}
    ostype Linux
    graphics off
    options "{state['cmdline']}"
}}
# END {MARKER}
'''


def generate(directory, state):
    directory.mkdir()
    for name in ['mkinitcpio.conf']:
        shutil.copyfile(SOURCE / 'graphical' / name, directory / name)
    (directory / 'state.json').write_text(json.dumps(state, indent=2) + '\n')
    (directory / 'kernel-cmdline').write_text(state['cmdline'] + '\n')
    (directory / 'crypttab').write_text(f"luks-{state['luks_uuid']} UUID={state['luks_uuid']} none luks,x-initrd.attach\n")
    (directory / 'theme-name').write_text(state['theme'] + '\n')
    (directory / 'plymouthd.conf').write_text(f"[Daemon]\nTheme={state['theme']}\nShowDelay=0\nUseSimpledrm=1\n")
    theme = configparser.ConfigParser(interpolation=None)
    theme.optionxform = str
    theme.read(Path('/usr/share/plymouth/themes') / state['theme'] / (state['theme'] + '.plymouth'))
    for section in ['boot-up', 'shutdown', 'reboot']:
        if not theme.has_section(section):
            theme.add_section(section)
        theme.set(section, 'UseEndAnimation', 'false')
    with (directory / 'theme.plymouth').open('w') as stream:
        theme.write(stream, space_around_delimiters=False)
    hooks = directory / 'hooks/install'
    hooks.mkdir(parents=True)
    shutil.copyfile(SOURCE / 'graphical/graphical-unlock', hooks / 'graphical-unlock')


def fingerprint(path):
    if not path.exists():
        return None
    if path.is_symlink():
        raise ValueError(f'Refusing symlink: {path}')
    if path.is_dir():
        return {str(p.relative_to(path)): fingerprint(p) for p in sorted(path.iterdir())}
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, destination):
    if source.is_dir():
        shutil.copytree(source, destination)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def remove(path):
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def restore(backup, verify=True):
    records = json.loads((backup / 'manifest.json').read_text())
    if verify:
        for record in records:
            if fingerprint(Path(record['path'])) != record['after']:
                raise ValueError('Installed files changed since installation; automatic rollback stopped.')
    # Hide the new menu first, then restore the underlying files.
    for record in reversed(records):
        path = Path(record['path'])
        remove(path)
        if record['existed']:
            copy(backup / record['saved'], path)
    os.sync()


def commit(items, backup):
    backup.mkdir(parents=True, mode=0o700)
    records = []
    for index, (source, destination) in enumerate(items):
        fingerprint(destination)  # Reject symlinks before changing anything.
        record = dict(path=str(destination), existed=destination.exists(), saved=str(index))
        if destination.exists():
            copy(destination, backup / str(index))
        records.append(record)
    manifest = backup / 'manifest.json'
    manifest.write_text(json.dumps(records, indent=2))
    try:
        for source, destination in items:
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                remove(destination)
                copy(source, destination)
            else:
                pending = destination.with_name(destination.name + '.dotfiles-pending')
                if pending.exists() or pending.is_symlink():
                    raise ValueError(f'Pending file already exists: {pending}')
                copy(source, pending)
                with pending.open('rb') as stream:
                    os.fsync(stream.fileno())
                pending.replace(destination)
            if fingerprint(source) != fingerprint(destination):
                raise ValueError('Installed file verification failed.')
        for record in records:
            record['after'] = fingerprint(Path(record['path']))
        manifest.write_text(json.dumps(records, indent=2))
        os.sync()
    except BaseException:
        restore(backup, verify=False)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='Build, verify, back up and install; default is a read-only plan.')
    mode.add_argument('--restore', type=Path, help='Restore a backup, only if installed files have not changed.')
    parser.add_argument('--kernel', type=Path)
    parser.add_argument('--refind-dir', type=Path)
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('Run with sudo python3 boot/install.py (read-only plan), or add --apply.')
    os.umask(0o077)
    with Path('/run/lock/graphical-unlock-install.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.restore:
            backup = args.restore.resolve()
            if backup.parent != BACKUPS or not (backup / 'manifest.json').is_file():
                raise ValueError('Select a portable installer backup under ' + str(BACKUPS))
            with Path('/run/lock/graphical-unlock.lock').open('w') as build_lock:
                fcntl.flock(build_lock, fcntl.LOCK_EX)
                restore(backup)
            print('Previous boot configuration restored.')
            return
        state = detect(args)
        original = Path(state['menu']).read_text()
        new_menu = menu_text(original, state)
        print('Detected local settings (do not commit this output):')
        print(json.dumps({k: state[k] for k in ['kernel', 'esp', 'refind', 'theme', 'graphics']}, indent=2))
        print('Root and LUKS identifiers detected locally. Theme: Calm; icon: white Linux penguin.')
        print('Existing boot entries remain available. Hide the CLI entry only after a successful boot.')
        if not args.apply:
            print('Plan only. Add --apply to build and install.')
            return
        with tempfile.TemporaryDirectory(prefix='portable-boot-') as work:
            stage = Path(work)
            config = stage / 'config'
            generate(config, state)
            image = stage / 'cachyos.efi'
            subprocess.run(['python3', str(SOURCE / 'graphical/update-graphical-unlock'),
                            '--config-dir', str(config), '--output', str(image)], check=True)
            if Path(state['menu']).read_text() != original:
                raise ValueError('rEFInd configuration changed during the build; retry.')
            staged_menu = stage / 'refind.conf'
            staged_menu.write_text(new_menu)
            builder = stage / 'update-graphical-unlock'
            shutil.copyfile(SOURCE / 'graphical/update-graphical-unlock', builder)
            builder.chmod(0o755)
            post = stage / '99-graphical-unlock'
            shutil.copyfile(SOURCE / 'graphical/99-graphical-unlock', post)
            post.chmod(0o755)
            backup = BACKUPS / ('portable-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
            with Path('/run/lock/graphical-unlock.lock').open('w') as build_lock:
                fcntl.flock(build_lock, fcntl.LOCK_EX)
                commit([(config, CONFIG), (builder, BUILDER),
                        (SOURCE / 'graphical/graphical-unlock', HOOK), (post, POST),
                        (SOURCE / 'refind/calm', Path(state['refind']) / 'themes/refind-calm'),
                        (image, Path(state['target'])), (staged_menu, Path(state['menu']))], backup)
            print('Installed and verified. Backup:', backup)
            print('No reboot initiated. Test the graphical entry at your next boot.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
