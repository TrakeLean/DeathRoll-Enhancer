"""Exercise the release preparation entry point and actual workflow note extraction."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
FILES = ['VERSION', 'Core.lua', 'README.md', 'CHANGELOG.md',
         'scripts/prepare_version.py', 'update-version.sh']


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'addon with spaces'
        for name in FILES:
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)

    def prepare(self, version):
        return subprocess.run(['bash', str(self.root / 'update-version.sh'), version],
                              cwd=self.temp.name, capture_output=True, text=True)

    def test_preparation_keeps_versions_consistent_and_history_intact(self):
        old_changes = (self.root / 'CHANGELOG.md').read_text()
        historical_readme = (self.root / 'README.md').read_text().splitlines()[5:]
        result = self.prepare('9.8.7-beta.1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'VERSION').read_text(), '9.8.7-beta.1\n')
        self.assertIn('local localFallbackVersion = "9.8.7-beta.1"', (self.root / 'Core.lua').read_text())
        self.assertIn('@project-version@', (self.root / 'Core.lua').read_text())
        readme = (self.root / 'README.md').read_text()
        self.assertTrue(readme.startswith('# DeathRoll Enhancer v9.8.7-beta.1 - 2SChoppy Edition'))
        self.assertIn('Version-9.8.7-beta.1-brightgreen', readme)
        self.assertEqual(readme.splitlines()[5:], historical_readme)
        changes = (self.root / 'CHANGELOG.md').read_text()
        self.assertTrue(changes.startswith('## 9.8.7-beta.1 '))
        self.assertTrue(changes.endswith(old_changes))
        prepared = {name: (self.root / name).read_bytes() for name in FILES}
        self.assertNotEqual(self.prepare('9.8.7-beta.1').returncode, 0)
        self.assertEqual(prepared, {name: (self.root / name).read_bytes() for name in FILES})

    def test_invalid_version_or_missing_metadata_does_not_partially_update(self):
        original = {name: (self.root / name).read_bytes() for name in FILES}
        for version in ['nope', '1.2', '1.2.3\n## Fake', '1.2.3;echo surprise']:
            self.assertNotEqual(self.prepare(version).returncode, 0)
            self.assertEqual(original, {name: (self.root / name).read_bytes() for name in FILES})
        (self.root / 'README.md').write_text('Unexpected README structure\n')
        before = {name: (self.root / name).read_bytes() for name in FILES}
        self.assertNotEqual(self.prepare('9.8.7').returncode, 0)
        self.assertEqual(before, {name: (self.root / name).read_bytes() for name in FILES})

    def test_preparation_uses_utf8_under_non_utf8_locale(self):
        old_changes = (self.root / 'CHANGELOG.md').read_text(encoding='utf-8')
        result = subprocess.run(
            [sys.executable, '-X', 'utf8=0', str(self.root / 'scripts/prepare_version.py'), '9.8.7'],
            cwd=self.temp.name, capture_output=True, text=True,
            env={**os.environ, 'LC_ALL': 'C', 'PYTHONUTF8': '0', 'PYTHONCOERCECLOCALE': '0'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'CHANGELOG.md').read_text(encoding='utf-8').endswith(old_changes))

    def test_workflow_extracts_only_current_release_and_rejects_mismatch(self):
        self.assertEqual(self.prepare('9.8.7').returncode, 0)
        self.assertEqual(self.prepare('9.8.8').returncode, 0)
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        script = textwrap.dedent(workflow.split("python3 - <<'PY'\n", 1)[1].split('\n          PY', 1)[0])
        (self.root / 'dist').mkdir()
        result = subprocess.run([sys.executable, '-c', script], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        notes = (self.root / 'dist/release-notes.md').read_text()
        self.assertTrue(notes.startswith('## 9.8.8 '))
        self.assertNotIn('9.8.7', notes)
        (self.root / 'VERSION').write_text('9.8.9\n')
        result = subprocess.run([sys.executable, '-c', script], cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
