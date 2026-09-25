import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


installer = module('installer', ROOT / 'install.py')
privacy = module('privacy', ROOT / 'check-public.py')


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.root = dict(fstype='btrfs', uuid='root-test', fsroot='/@')
        self.tree = dict(type='crypt', uuid='root-test', children=[
            dict(type='part', fstype='crypto_LUKS', uuid='luks-test')])

    def test_btrfs_and_nvidia(self):
        values = installer.storage(self.root, self.tree)
        cmdline = installer.command_line(*values, True)
        self.assertIn('rootflags=subvol=/@', cmdline)
        self.assertIn('rd.luks.uuid=luks-test', cmdline)
        self.assertIn('nvidia_drm.modeset=1', cmdline)
        self.assertNotIn('rd.luks.key', cmdline)

    def test_ext4_intel_or_amd(self):
        self.root['fstype'] = 'ext4'
        cmdline = installer.command_line(*installer.storage(self.root, self.tree), False)
        self.assertNotIn('rootflags', cmdline)
        self.assertNotIn('nvidia', cmdline)
        self.assertIn('plymouth.use-simpledrm', cmdline)

    def test_lvm_and_unencrypted_roots_rejected(self):
        for kind in ['lvm', 'part', 'raid1']:
            self.tree['type'] = kind
            with self.assertRaises(ValueError):
                installer.storage(self.root, self.tree)

    def test_ambiguous_luks_rejected(self):
        self.tree['children'] *= 2
        with self.assertRaises(ValueError):
            installer.storage(self.root, self.tree)

    def test_unsafe_subvolume_rejected(self):
        self.root['fsroot'] = '/subvolume with spaces'
        with self.assertRaises(ValueError):
            installer.storage(self.root, self.tree)


class MenuTests(unittest.TestCase):
    state = dict(esp='/efi', refind='/efi/EFI/refind', target='/efi/EFI/refind/graphical-unlock/cachyos.efi',
                 title='Arch Linux - graphical unlock', cmdline='root=UUID=root-test rw')

    def test_preserves_existing_entries_and_is_repeatable(self):
        original = 'timeout 20\ninclude themes/refind-calm/theme.conf\nmenuentry "Windows" {\n loader /EFI/Microsoft/Boot/bootmgfw.efi\n}\n'
        result = installer.menu_text(original, self.state)
        self.assertEqual(installer.menu_text(result, self.state), result)
        self.assertIn('menuentry "Windows"', result)
        self.assertEqual(result.count('include themes/refind-calm/theme.conf'), 1)
        self.assertIn('showtools hidden_tags', result)
        self.assertIn('icon /EFI/refind/themes/refind-calm/icons/os_linux.png', result)
        self.assertNotIn('dont_scan', result)

    def test_replaces_legacy_entry(self):
        original = '# BEGIN graphical-unlock managed entry\nmenuentry "Old" {\n}\n# END graphical-unlock managed entry\n'
        result = installer.menu_text(original, self.state)
        self.assertNotIn('"Old"', result)
        self.assertEqual(result.count('menuentry'), 1)

    def test_malformed_managed_block_rejected(self):
        with self.assertRaises(ValueError):
            installer.menu_text('# BEGIN graphical-unlock managed entry\n', self.state)

    def test_manual_scanning_required(self):
        with self.assertRaisesRegex(ValueError, 'excludes manual'):
            installer.menu_text('scanfor internal,external\n', self.state)


class TransactionTests(unittest.TestCase):
    def test_install_restore_and_changed_file_guard(self):
        with tempfile.TemporaryDirectory() as work:
            base = Path(work)
            source, target, backup = base / 'source', base / 'target', base / 'backup'
            source.write_text('new')
            target.write_text('old')
            installer.commit([(source, target)], backup)
            self.assertEqual(target.read_text(), 'new')
            target.write_text('subsequent update')
            with self.assertRaises(ValueError):
                installer.restore(backup)
            target.write_text('new')
            installer.restore(backup)
            self.assertEqual(target.read_text(), 'old')

    def test_failure_rolls_back_all_changes(self):
        with tempfile.TemporaryDirectory() as work:
            base = Path(work)
            first, second = base / 'first', base / 'second'
            first.write_text('original')
            source = base / 'source'
            source.write_text('replacement')
            # Block the second replacement after the first succeeds.
            (base / 'second.dotfiles-pending').write_text('busy')
            with self.assertRaises(ValueError):
                installer.commit([(source, first), (source, second)], base / 'backup')
            self.assertEqual(first.read_text(), 'original')
            self.assertFalse(second.exists())


class PrivacyTests(unittest.TestCase):
    def test_current_tree(self):
        privacy.check(ROOT)

    def test_rejects_extra_state_and_personal_identifiers(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work) / 'boot'
            shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns('__pycache__'))
            (root / 'state.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'unexpected file'):
                privacy.check(root)
            (root / 'state.json').unlink()
            # Construct synthetic identifiers so none are present in tracked sources.
            synthetic_uuid = '-'.join(['a' * 8, 'b' * 4, 'c' * 4, 'd' * 4, 'e' * 12])
            with (root / 'README.md').open('a') as stream:
                stream.write('\n' + synthetic_uuid)
            with self.assertRaisesRegex(ValueError, 'disk identifier'):
                privacy.check(root)

    def test_rejects_modified_asset(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work) / 'boot'
            shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns('__pycache__'))
            (root / 'refind/calm/background.png').write_bytes(b'personal image')
            with self.assertRaisesRegex(ValueError, 'pinned upstream'):
                privacy.check(root)


if __name__ == '__main__':
    unittest.main()
