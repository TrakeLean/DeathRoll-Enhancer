from pathlib import Path
import importlib.util
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_release', ROOT / 'scripts/build_release.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PackageTests(unittest.TestCase):
    def test_runtime_references_exist_and_required_libraries_load_first(self):
        files = {str(p.relative_to(ROOT)) for p in builder.runtime_files()}
        for library in ('LibStub/LibStub.lua', 'AceAddon-3.0/AceAddon-3.0.lua',
                        'AceDB-3.0/AceDB-3.0.lua', 'AceGUI-3.0/AceGUI-3.0.lua',
                        'AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua'):
            self.assertIn('Libs/' + library, files)
        toc = (ROOT / 'DeathRollEnhancer.toc').read_text()
        self.assertLess(toc.index('embeds.xml'), toc.index('Core.lua'))
        self.assertIn('Media/Logo.tga', files)
        self.assertIn('Dialogs.lua', files)
        self.assertIn('Group.lua', files)
        load_lines = lambda text: [line for line in text.splitlines() if line and not line.startswith('#')]
        for suffix in ('Forever', 'Camelot'):
            name = f'DeathRollEnhancer_{suffix}.toc'
            self.assertIn(name, files)
            specialized = (ROOT / name).read_text()
            self.assertIn('## Interface: 16001', specialized)
            self.assertEqual(load_lines(toc), load_lines(specialized))

    def test_installable_deterministic_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            first = builder.build(Path(directory) / 'first.zip', '2.3.10-dev')
            second = builder.build(Path(directory) / 'second.zip', '2.3.10-dev')
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                names = archive.namelist()
                self.assertTrue(all(n.startswith('DeathRollEnhancer/') for n in names))
                self.assertFalse(any('/tests/' in n or '/.qa/' in n or '/.git/' in n for n in names))
                self.assertIn('DeathRollEnhancer/Libs/Ace3-LICENSE.txt', names)
                self.assertIn('DeathRollEnhancer/LICENSE.txt', names)
                self.assertIn('DeathRollEnhancer/Group.lua', names)
                toc = archive.read('DeathRollEnhancer/DeathRollEnhancer.toc')
                self.assertIn(b'## Version: 2.3.10-dev', toc)
                self.assertNotIn(b'@project-version@', toc)
