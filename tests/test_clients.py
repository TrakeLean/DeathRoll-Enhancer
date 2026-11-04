"""Feature profiles exercise modern and legacy client API boundaries, not live clients."""
import unittest
from lupa.lua51 import LuaRuntime
from test_addon import ROOT, runtime


class ClientCompatibilityTests(unittest.TestCase):
    def test_optional_emote_apis_cannot_interrupt_results(self):
        profiles = {
            'modern': "DoEmote=nil; C_ChatInfo={PerformEmote=react}",
            'legacy': "C_ChatInfo=nil; DoEmote=react",
            'missing': "DoEmote=nil; C_ChatInfo=nil",
            'restricted': "DoEmote=nil; C_ChatInfo={PerformEmote=function() error('restricted') end}",
        }
        for profile, setup in profiles.items():
            for won in (False, True):
                with self.subTest(profile=profile, won=won):
                    lua = runtime()
                    lua.execute('''
                        reactions=0
                        function react(emote)
                            assert(type(emote)=='string' and #emote>0)
                            assert(not DRE.gameState and DRE.db.profile.history.Alice)
                            reactions=reactions+1
                        end
                        DRE.db.profile.gameplay.autoEmote=true
                    ''' + setup)
                    lua.execute('''
                        DRE:StartActualGame('Alice',100,0)
                        if ... then
                            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Me rolls 50 (1-100)')
                            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Alice rolls 1 (1-50)')
                        else
                            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Me rolls 1 (1-100)')
                        end
                        assert(not DRE.gameState and #DRE.db.profile.history.Alice.recentGames==1)
                    ''', won)
                    self.assertEqual(lua.eval('reactions'), 1 if profile in ('modern', 'legacy') else 0)

    def test_addon_only_restriction_does_not_block_ordinary_chat(self):
        runtime().execute('''
            SendChatMessage=nil
            C_ChatInfo={AreOutgoingAddonChatMessagesRestricted=function() return true end,
              InChatMessagingLockdown=function() return false end,
              SendChatMessage=function(...) sent[#sent+1]={...} end}
            assert(DRE:SendChatSafely('hello','WHISPER',nil,'Alice'))
            assert(#sent==1 and sent[1][4]=='Alice')
            C_ChatInfo.InChatMessagingLockdown=function() return true end
            assert(not DRE:SendChatSafely('hello','WHISPER',nil,'Alice') and #sent==1)
        ''')

    def test_challenge_uses_readable_identity_without_secret_unit_comparison(self):
        runtime().execute('''
            UnitIsUnit=function() error('restricted comparison must not be called') end
            DRE.UI.rollEdit=AceGUI:Create('EditBox');DRE.UI.rollEdit:SetText('100')
            DRE.StartDeathRoll=function(_,target) started=target;return true end
            DRE:StartChallengeFlow();assert(started=='Alice')
            units.target={'Me','LocalRealm'}
            DRE:StartChallengeFlow();assert(started=='Me')
            local secret={}
            issecretvalue=function(value) return rawequal(secret,value) end
            units.target={secret,'LocalRealm'};started=nil
            assert(not DRE:StartChallengeFlow() and not started and not DRE.gameState)
            units.target=nil
            assert(not DRE:StartChallengeFlow() and not started)
        ''')

    def test_settings_registration_does_not_block_legacy_initialization(self):
        for modern in (True, False):
            with self.subTest(modern=modern):
                lua = runtime('''
                    local original=LibStub
                    local config={RegisterOptionsTable=function() optionsRegistered=true end}
                    local dialog={
                      AddToBlizOptions=function()
                        assert(Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory)
                        settingsRegistered=true;return {}
                      end,
                      Open=function() optionsOpened=true end}
                    local db={New=function(_,_,defaults) return defaults end}
                    LibStub=function(name,...)
                        if name=='AceConfig-3.0' then return config end
                        if name=='AceConfigDialog-3.0' then return dialog end
                        if name=='AceDB-3.0' then return db end
                        return original(name,...)
                    end
                    commands={}
                    DRE.RegisterChatCommand=function(_,name) commands[name]=true end
                ''')
                lua.execute('Settings=... and {RegisterCanvasLayoutCategory=function() end, RegisterAddOnCategory=function() end} or nil', modern)
                lua.execute('''
                    DRE:OnInitialize()
                    assert(optionsRegistered and commands.dr and commands.deathroll)
                    DRE:OpenOptions();assert(optionsOpened)
                ''')
                self.assertEqual(bool(lua.eval('settingsRegistered')), modern)

    def test_actual_bundled_heading_with_legacy_and_modern_secret_apis(self):
        for modern in (True, False):
            with self.subTest(modern=modern):
                lua = LuaRuntime(unpack_returned_tuples=True)
                lua.execute((ROOT / 'tests/wow_mock.lua').read_text())
                lua.execute('''
                    local create=CreateFrame
                    CreateFrame=function(...)
                        local frame=create(...)
                        frame.CreateTexture=function() return create() end
                        return frame
                    end
                    -- An older addon may register upstream widget 21 first.
                    AceGUI.GetWidgetVersion=function() return 21 end
                    AceGUI.RegisterWidgetType=function(_,kind,constructor,version)
                        assert(kind=='Heading' and version>21 and version<22)
                        headingConstructor=constructor
                    end
                    AceGUI.RegisterAsWidget=function(_,widget)
                        widget.SetFullWidth=function() end;widget.SetHeight=function() end
                        return widget
                    end
                ''')
                lua.execute('issecretvalue=... and function() return false end or nil', modern)
                lua.execute((ROOT / 'Libs/AceGUI-3.0/widgets/AceGUIWidget-Heading.lua').read_text())
                lua.execute('''
                    local widget=headingConstructor()
                    widget:OnAcquire();widget:SetText('Start DeathRoll')
                    assert(widget.label:GetText()=='Start DeathRoll' and widget.right:IsShown())
                    widget:SetText('');assert(not widget.right:IsShown())
                    widget:OnRelease()
                ''')

    def test_legacy_name_api_and_modern_surname_profiles(self):
        profiles = {
            'legacy': "UnitNameUnmodified=nil;UnitFullName=nil;RegionalUniqueNamesEnabled=nil;NameUtil=nil",
            'modern': "regionalNames=false",
            'forever': "regionalNames=true;units.player={'Me','Smith'};units.target={'Alice','Jones'}",
        }
        for profile, setup in profiles.items():
            with self.subTest(profile=profile):
                lua = runtime(setup)
                player = 'Me Smith' if profile == 'forever' else 'Me'
                target = 'Alice Jones' if profile == 'forever' else 'Alice'
                lua.execute('''
                    local player,target=...
                    assert(DRE:GetUnitPlayerName('player')==player)
                    assert(DRE:GetUnitPlayerName('target')==target)
                    DRE:StartActualGame(target,100,0)
                    DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM',player..' rolls 1 (1-100)')
                    assert(not DRE.gameState and DRE.db.profile.history[target].losses==1)
                ''', player, target)

    def test_automatic_say_is_deferred_but_manual_announcement_sends(self):
        runtime().execute('''
            local hardware=true
            SendChatMessage=function(...)
                assert(hardware,'protected event-driven Say')
                sent[#sent+1]={...}
            end
            assert(DRE:StartGroupRound('Me\\nAlice',100,'SAY'))
            hardware=false
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Me rolls 50 (1-100)')
            assert(#sent==1 and DRE.groupRound.turn==2 and DRE.groupRound.chatError:find('Click Announce'))
            hardware=true
            assert(DRE:AnnounceGroupRound() and #sent==2 and not DRE.groupRound.chatError)
            assert(sent[2][1]:find('Alice, /roll 50',1,true))
            hardware=false
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Alice rolls 1 (1-50)')
            assert(#sent==2 and DRE.groupRound.status=='finished')
            hardware=true
            assert(DRE:AnnounceGroupRound() and #sent==3 and sent[3][1]:find('Alice rolled 1',1,true))
        ''')
