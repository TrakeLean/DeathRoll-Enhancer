#!/usr/bin/env python3
"""Prepare release metadata locally; never commit, tag, or publish."""
import argparse
from datetime import date
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def prepare(version, root=ROOT):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?', version):
        raise ValueError('Version must be major.minor.patch with an optional prerelease suffix')
    root = Path(root)
    if (root / 'VERSION').read_text(encoding='utf-8').strip() == version:
        raise ValueError(f'Version {version} is already prepared; edit its changelog instead')

    def replace_once(pattern, replacement, text):
        updated, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f'Expected exactly one metadata field matching {pattern}')
        return updated

    # Validate every input before changing any file. Preserve the packaging tokens.
    core = replace_once(r'^local localFallbackVersion = "[^"]+"$',
                        f'local localFallbackVersion = "{version}"',
                        (root / 'Core.lua').read_text(encoding='utf-8'))
    readme = replace_once(r'^# DeathRoll Enhancer v\S+',
                          f'# DeathRoll Enhancer v{version}',
                          (root / 'README.md').read_text(encoding='utf-8'))
    readme = replace_once(r'(?<=badge/Version-)[^\n]+?(?=-brightgreen\))',
                          version, readme)
    changelog = (f'## {version} — 2SChoppy Edition ({date.today().isoformat()})\n\n'
                 '- [Describe the changes before publishing.]\n\n'
                 + (root / 'CHANGELOG.md').read_text(encoding='utf-8'))
    for name, content in {'VERSION': version + '\n', 'Core.lua': core,
                          'README.md': readme, 'CHANGELOG.md': changelog}.items():
        (root / name).write_text(content, encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    args = parser.parse_args()
    try:
        prepare(args.version)
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
    print(f'Prepared {args.version}. Complete the changelog, run tests, then commit and push to main.')
    print('The GitHub workflow creates the tag and release after verification passes.')
