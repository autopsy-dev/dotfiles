#!/usr/bin/env python3
"""Check the portable boot folder before publication; never collect host state."""
import hashlib
import argparse
import json
from pathlib import Path
import re
import sys

SOURCE_FILES = {
    '.gitignore', 'README.md', 'install.py', 'check-public.py',
    'graphical/mkinitcpio.conf', 'graphical/graphical-unlock',
    'graphical/99-graphical-unlock', 'graphical/update-graphical-unlock',
    'refind/SOURCE.md', 'refind/assets.json', 'refind/calm/theme.conf',
    'tests/test_install.py',
}
PATTERNS = {
    'disk identifier': r'\b[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\b',
    'personal home path': r'/(?:home|Users)/[A-Za-z0-9_.-]+',
    'email address': r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
    'IPv4 address': r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b',
    'MAC address': r'\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b',
    'credential': r'(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)',
}


def text_errors(name, data):
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        return [f'{name}: unexpected binary content']
    return [f'{name}: possible {label} (value withheld)'
            for label, pattern in PATTERNS.items() if re.search(pattern, text)]


def check(root):
    root = Path(root)
    assets = json.loads((root / 'refind/assets.json').read_text())
    expected = SOURCE_FILES | set(assets)
    seen = set()
    errors = []
    for path in root.rglob('*'):
        name = path.relative_to(root).as_posix()
        if path.is_symlink():
            errors.append(f'{name}: symlink')
            continue
        if path.is_dir():
            continue
        if '__pycache__' in path.parts or path.suffix == '.pyc':
            continue  # Also excluded by rsync and Git.
        seen.add(name)
        if name not in expected:
            errors.append(f'{name}: unexpected file')
            continue
        data = path.read_bytes()
        if name in assets:
            if hashlib.sha256(data).hexdigest() != assets[name]:
                errors.append(f'{name}: differs from pinned upstream asset')
            continue
        errors.extend(text_errors(name, data))
    errors.extend(f'{name}: missing expected source/asset' for name in sorted(expected - seen))
    if errors:
        raise ValueError('\n'.join(errors))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path, nargs='?', default=Path(__file__).resolve().parent)
    parser.add_argument('--extra', type=Path, nargs='*', default=[])
    args = parser.parse_args()
    try:
        check(args.root)
        for path in args.extra:
            if path.is_symlink():
                raise ValueError(f'{path.name}: symlink')
            errors = text_errors(path.name, path.read_bytes())
            if errors:
                raise ValueError('\n'.join(errors))
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
    print('Portable boot publication check passed: source allowlist, identifiers and asset hashes.')
