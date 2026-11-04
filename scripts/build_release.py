#!/usr/bin/env python3
"""Build a deterministic installable ZIP; no publication or network access."""
import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def runtime_files(root=ROOT):
    root = root.resolve()
    files = set()

    def add(path):
        path = path.resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError(f'Missing or unsafe package reference: {path}')
        if path in files:
            return
        files.add(path)
        if path.suffix == '.xml':
            for element in ET.parse(path).iter():
                if element.tag.rsplit('}', 1)[-1] in ('Include', 'Script'):
                    add(path.parent / element.attrib['file'].replace('\\', '/'))

    for toc in sorted(root.glob('DeathRollEnhancer*.toc')):
        add(toc)
        for line in toc.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith('#'):
                add(root / line.replace('\\', '/'))
    for path in (root / 'Media').rglob('*'):
        if path.is_file():
            add(path)
    add(root / 'Libs' / 'Ace3-LICENSE.txt')
    add(root / 'Libs' / 'SOURCES.txt')
    add(root / 'LICENSE')
    add(root / 'README.md')
    add(root / 'TESTING.md')
    return sorted(files)


def build(output, version, root=ROOT):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version):
        raise ValueError('Version must be numeric major.minor.patch with an optional prerelease suffix')
    root = root.resolve()
    files = runtime_files(root)
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            relative = path.relative_to(root)
            if relative.as_posix() == 'LICENSE':
                relative = Path('LICENSE.txt')
            contents = path.read_bytes()
            if path.suffix in ('.lua', '.toc'):
                contents = contents.replace(b'@project-version@', version.encode())
            entry = zipfile.ZipInfo('DeathRollEnhancer/' + relative.as_posix(), (2020, 1, 1, 0, 0, 0))
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, contents)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(build(args.output, args.version))
