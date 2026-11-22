from pathlib import Path
import importlib.util
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_release', ROOT / 'scripts/build_release.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PackageTests(unittest.TestCase):
    def test_fresh_install_of_packaged_clients(self):
        version = '3.0.0'
        with tempfile.TemporaryDirectory() as directory:
            for manifest_name in ('DeathRollEnhancer_Forever.toc', 'DeathRollEnhancer_Camelot.toc', 'DeathRollEnhancer.toc'):
                with self.subTest(manifest=manifest_name), zipfile.ZipFile(builder.build(
                        Path(directory) / 'addon.zip', version)) as archive:
                    def read(path):
                        return archive.read('DeathRollEnhancer/' + path.as_posix()).decode('utf-8-sig')

                    media = {n.split('/')[-1] for n in archive.namelist() if '/Media/' in n}
                    expected = {'Logo.tga'}
                    expected.update(name + '.tga' for name in (
                            'DuelHeart', 'GoldTable', 'GoldTableGlints', 'GroupSeatRim', 'GroupTurnGlow',
                            'GroupFeltTable', 'GroupGoblinArm', 'GroupPortraitCorners'))
                    self.assertEqual(media, expected)
                    lua = LuaRuntime()
                    for fixture in ('wow_mock.lua', 'packaged_client.lua'):
                        lua.execute((ROOT / 'tests' / fixture).read_text(encoding='utf-8'))
                    manifest = read(Path(manifest_name)).splitlines()
                    metadata = dict(line[3:].split(': ', 1) for line in manifest if line.startswith('## '))
                    self.assertNotIn('(Dev)', metadata['Title'])
                    lua.globals().tocMetadata = lua.table_from(metadata)
                    namespace = lua.table()

                    def load(path):
                        if path.suffix == '.xml':
                            for element in ET.fromstring(read(path)).iter():
                                if element.tag.rsplit('}', 1)[-1] in ('Include', 'Script'):
                                    load(path.parent / element.attrib['file'].replace('\\', '/'))
                        else:
                            lua.execute(read(path), 'DeathRollEnhancer', namespace, name=path.as_posix())

                    for line in manifest:
                        if line and not line.startswith('#'):
                            load(Path(line))
                    lua.execute("""
                        DRE = LibStub('AceAddon-3.0'):GetAddon('DeathRollEnhancer')
                        assert(not DeathRollEnhancerDB)
                        DRE:OnInitialize()
                        local registry = LibStub('AceConfigRegistry-3.0')
                        local options = registry:GetOptionsTable('DeathRollEnhancer', 'dialog', 'AceConfigDialog-3.0')
                        for _, page in pairs(options.args) do
                            for key, control in pairs(page.args) do
                                assert(control.width == 'full', key)
                            end
                        end
                        local root = Settings.root
                        assert(root.name == DRE.displayName and root.frame.obj:GetUserData('path')[1] == 'gameplay')
                        local pages = {'challenges', 'interface', 'statistics', 'data'}
                        assert(#root.children == #pages)
                        for i, child in ipairs(root.children) do
                            assert(child.frame.obj:GetUserData('path')[1] == pages[i])
                        end
                        DRE:OnEnable()
                        assert(DRE.db.profile.ui.scale and LibStub('LibDBIcon-1.0'):IsRegistered('DeathRollEnhancer'))
                    """)
                    self.assertEqual(lua.eval('DRE.version'), version)
                    self.assertEqual(lua.eval('DRE.displayName'), 'DeathRoll Enhancer')
                    uses_table = manifest_name != 'DeathRollEnhancer.toc'
                    self.assertEqual(bool(lua.eval('DRE.devDuel')), uses_table)
                    if uses_table:
                        lua.execute("""
                            local parent = LibStub('AceGUI-3.0'):Create('SimpleGroup')
                            local child = DRE:CreateTableDropdownField(parent, 'Channel', 1)
                            local field = parent.children[1]
                            field.content:SetWidth(136)
                            field:DoLayout()
                            assert(child.frame:GetWidth() == 136)
                            child:SetList({[2]='Gold', [7]='Player Relationships'}, {7, 2})
                            child:SetValue(7)
                            local picked
                            child:SetCallback('OnValueChanged', function(_, _, key) picked = key end)
                            local click = child.control:GetScript('OnClick')
                            click()
                            local menu = assert(child.menu)
                            assert(menu.items[1]:GetText() == 'Player Relationships' and menu.items[1]:GetValue())
                            menu.items[2]:Fire('OnValueChanged', true)
                            assert(picked == 2 and child:GetValue() == 2 and not child.menu)
                            click()
                            LibStub('AceGUI-3.0'):Release(parent)
                            assert(not child.menu and not menu.frame:IsShown())
                        """)
                    self.assertEqual(lua.eval("table.concat(clientErrors, '\\n')"), '')

    def test_runtime_references_exist_and_required_libraries_load_first(self):
        files = {p.relative_to(ROOT).as_posix() for p in builder.runtime_files()}
        ignored = {line.strip()[2:] for line in (ROOT / '.pkgmeta').read_text().splitlines()
                   if line.strip().startswith('- ')}
        self.assertTrue(files.isdisjoint(ignored))
        self.assertIn('GroupSync.lua', files)
        for library in ('LibStub/LibStub.lua', 'AceAddon-3.0/AceAddon-3.0.lua',
                        'AceDB-3.0/AceDB-3.0.lua', 'AceGUI-3.0/AceGUI-3.0.lua',
                        'LibDataBroker-1.1/LibDataBroker-1.1.lua', 'LibDBIcon-1.0/LibDBIcon-1.0.lua',
                        'AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua'):
            self.assertIn('Libs/' + library, files)
        toc = (ROOT / 'DeathRollEnhancer.toc').read_text(encoding='utf-8')
        self.assertLess(toc.index('embeds.xml'), toc.index('Core.lua'))
        self.assertIn('Media/Logo.tga', files)
        self.assertIn('Media/GroupSeatRim.tga', files)
        self.assertIn('Media/GroupTurnGlow.tga', files)
        for texture in ('GroupFeltTable', 'GroupGoblinArm', 'GroupPortraitCorners'):
            self.assertIn(f'Media/{texture}.tga', files)
        self.assertIn('Dialogs.lua', files)
        self.assertIn('Group.lua', files)
        load_lines = lambda text: [line for line in text.splitlines() if line and not line.startswith('#')]
        for suffix in ('Forever', 'Camelot'):
            name = f'DeathRollEnhancer_{suffix}.toc'
            self.assertIn(name, files)
            specialized = (ROOT / name).read_text(encoding='utf-8')
            self.assertIn('## Interface: 16001', specialized)
            self.assertIn('## X-DRE-DuelUI: 1', specialized)
            self.assertEqual([line for line in specialized.splitlines() if line.startswith('## Title:')],
                             [line for line in toc.splitlines() if line.startswith('## Title:')])
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
                self.assertIn('DeathRollEnhancer/Libs/LibDBIcon-LICENSE.txt', names)
                self.assertIn('DeathRollEnhancer/LICENSE.txt', names)
                self.assertIn('DeathRollEnhancer/Group.lua', names)
                toc = archive.read('DeathRollEnhancer/DeathRollEnhancer.toc')
                titles = lambda data: [line for line in data.splitlines() if line.startswith(b'## Title:')]
                self.assertEqual(titles(toc), [b'## Title: |cFFFF0000Death|r|cffffffffRoll|r Enhancer'])
                self.assertIn(b'## Version: 2.3.10-dev', toc)
                self.assertNotIn(b'@project-version@', toc)
                interfaces = next(line.split(':', 1)[1] for line in toc.decode().splitlines()
                                  if line.startswith('## Interface:'))
                self.assertTrue({16001, 120105, 11509, 20506, 30405, 38002, 40402, 50504}
                                <= {int(value.strip()) for value in interfaces.split(',')})
                modules = lambda data: [line for line in data.decode().splitlines()
                                        if line and not line.startswith('#')]
                for name in names:
                    if name.endswith('.toc') and name.count('/') == 1:
                        manifest = archive.read(name)
                        self.assertIn(b'## Version: 2.3.10-dev', manifest)
                        self.assertEqual(titles(manifest), titles(toc))
                        self.assertNotIn(b'(Dev)', manifest)
                        self.assertEqual(b'## X-DRE-DuelUI: 1' in manifest, name.endswith(('_Forever.toc', '_Camelot.toc')))
                        self.assertNotIn(b'@project-version@', manifest)
                        self.assertEqual(modules(toc), modules(manifest))
