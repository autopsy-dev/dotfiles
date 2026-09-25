# Boot

rEFInd with the Calm theme and a graphical LUKS unlock screen powered by Plymouth.
Disk, kernel, and graphics settings are detected during installation.

## Requirements

- Arch Linux or CachyOS on x86_64 UEFI, with Secure Boot disabled.
- rEFInd installed on a mounted, writable FAT EFI partition.
- An ext4 or single-device Btrfs root directly inside LUKS. LVM, RAID,
  detached headers, and remote unlock are unsupported.
- Python 3.11+, mkinitcpio with UKI and `--nopost` support, systemd's x64 EFI
  stub, cryptsetup, Plymouth, binutils, and util-linux.
- An installed `/boot/vmlinuz-*` kernel and the `cachyos` or `spinner` Plymouth theme.

## Install

Preview the detected setup, then install:

```sh
sudo python3 ~/.config/boot/install.py
sudo python3 ~/.config/boot/install.py --apply
```

Use `--kernel /boot/vmlinuz-linux` to select a kernel or `--refind-dir` to select
an EFI installation. Pass the same options to both commands.

The installer builds and verifies a separate boot image, backs up existing files,
and adds the graphical entry. Existing boot entries and firmware boot order are
preserved. Settings are stored locally in `/etc/graphical-unlock`.

Reboot and test the new entry. Once it works, hide the old entry with **Delete**
or **minus** in rEFInd. Keep its bootloader files available as a fallback.
Hidden entries and monitor-port selection are configured on each machine.

## Maintenance

The image rebuilds automatically when the selected kernel is updated. To rebuild
manually:

```sh
sudo /usr/local/sbin/update-graphical-unlock
```

Re-run the installer after changing disks, kernels, graphics hardware, or EFI mounts.
To restore an installation, use the backup path printed during setup:

```sh
sudo python3 ~/.config/boot/install.py --restore /var/backups/graphical-unlock/portable-TIMESTAMP
```

Restore stops if installed files have changed since the backup, including after
a kernel update.

## Publish

```sh
~/.config/update-dotfiles.sh --boot-only "Update boot setup"
```

Publishes the boot sources and shared README/install/sync scripts using a GitHub
noreply address. Desktop configs and screenshots are excluded.

Publication checks flag common personal identifiers, credentials, unexpected files,
and modified theme assets. Review changes before publishing. Disk IDs, keys,
generated images, and backups stay local.

Restoring dotfiles downloads this folder; boot installation remains a separate step.

## Development

```sh
python3 -m unittest discover -s ~/.config/boot/tests -v
python3 ~/.config/boot/check-public.py
```

Hardware still needs a real boot test after installation.

[Theme source & license](refind/SOURCE.md) ·
[rEFInd configuration](https://www.rodsbooks.com/refind/configfile.html) ·
[mkinitcpio](https://man.archlinux.org/man/mkinitcpio.8)
