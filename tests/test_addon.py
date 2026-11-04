"""Run with python -m unittest discover -s tests -v (requires lupa==2.8)."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MODULES = ['Core.lua', 'Database.lua', 'UI.lua', 'Dialogs.lua', 'Events.lua', 'Group.lua']


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / 'tests/wow_mock.lua').read_text())
    for name in MODULES:
        lua.execute((ROOT / name).read_text())
    lua.execute('''
        DRE.db={profile={history={},goldTracking={totalWon=0,totalLost=0,currentStreak=0,bestWinStreak=0,worstLossStreak=0},
          gameplay={},challengeSystem={enabled=true,minRollThreshold=100},ui={scale=1,frameStatus={}},funStats={},minimap={}}}
        DRE.UI.currentTab='deathroll'
    ''')
    return lua


class AddonRegressionTests(unittest.TestCase):
    def check(self, code):
        runtime().execute(code)

    def test_all_lua_compiles(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        for path in list(ROOT.glob('*.lua')) + list((ROOT / 'Libs').rglob('*.lua')):
            with self.subTest(file=str(path.relative_to(ROOT))):
                lua.execute('assert(loadstring(...))', path.read_text(encoding='utf-8-sig'))

    def test_emotes_cannot_forge_results(self):
        self.check('''
            DRE:StartActualGame('Alice',100,0)
            DRE:CHAT_MSG_EMOTE('CHAT_MSG_EMOTE','Me rolls 1 (1-100)','Mallory')
            DRE:CHAT_MSG_TEXT_EMOTE('CHAT_MSG_TEXT_EMOTE','Alice rolls 1 (1-100)','Mallory')
            assert(DRE.gameState.isActive and not next(DRE.db.profile.history))
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Me rolls 1 (1-100)')
            assert(not DRE.gameState and DRE.db.profile.history.Alice.losses==1)
        ''')

    def test_turn_and_range_enforcement(self):
        self.check('''
            DRE:StartActualGame('Alice',100,0)
            DRE:HandleGameRoll('Alice',1,100)
            DRE:HandleGameRoll('Alice',50,200)
            assert(DRE.gameState.playerTurn and DRE.gameState.currentRoll==100)
            assert(not next(DRE.db.profile.suspiciousRolls or {}))
            DRE:HandleGameRoll('Me',50,100)
            DRE:HandleGameRoll('Me',1,50)
            assert(DRE.gameState.currentRoll==50 and not DRE.gameState.playerTurn)
            assert(not DRE:PerformRoll())
            DRE:HandleGameRoll('Alice',1,100)
            assert(DRE.gameState.currentRoll==50 and DRE.db.profile.suspiciousRolls.Alice.count==1)
            DRE:HandleGameRoll('Alice',1,50)
            assert(DRE.db.profile.history.Alice.wins==1)
        ''')

    def test_self_duel_identical_rolls_are_not_deduplicated(self):
        self.check('''
            DRE:StartActualGame('Me',2,0)
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Me rolls 2 (1-2)')
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Me rolls 2 (1-2)')
            assert(DRE.gameState.rollCount==2)
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Me rolls 1 (1-2)')
            assert(DRE.db.profile.history.Me.losses==1)
        ''')

    def test_localized_and_positional_roll_formats(self):
        self.check('''
            local roll=DRE:ParseRollMessage('Alice rolls 40 (1-100)')
            assert(roll.roll==40 and roll.maxRoll==100)
            RANDOM_ROLL_RESULT='%s würfelt. Ergebnis: %d (%d-%d)'
            assert(DRE:ParseRollMessage('Élodie würfelt. Ergebnis: 40 (1-100)').playerName=='Élodie')
            RANDOM_ROLL_RESULT='%2$d pour %1$s [%3$d à %4$d] %%'
            roll=DRE:ParseRollMessage('40 pour Alice Smith [1 à 100] %')
            assert(roll.playerName=='Alice Smith' and roll.roll==40)
            RANDOM_ROLL_RESULT='%s rolls %d (%d-%d)'
            assert(not DRE:ParseRollMessage('Alice rolls 0 (1-100)'))
            assert(not DRE:ParseRollMessage('Alice rolls 101 (1-100)'))
            assert(not DRE:ParseRollMessage('Alice rolls 50 (50-100)'))
            assert(not DRE:ParseRollMessage('Alice rolls 50 (1-1000000)'))
        ''')

    def test_full_player_identity(self):
        self.check('''
            assert(DRE:IsSamePlayer('Alice','Alice-LocalRealm'))
            assert(not DRE:IsSamePlayer('Alice','Alice-OtherRealm'))
            assert(DRE:NormalizePlayerName('Alice-Area52')=='Alice-Area52')
            units.target={'Élodie','Area52'}
            assert(DRE:GetUnitPlayerName('target')=='Élodie-Area52')
            regionalNames=true
            units.target={'Alice','Smith'}
            assert(DRE:GetUnitPlayerName('target')=='Alice Smith')
            assert(not DRE:IsSamePlayer('Alice Smith','Alice Jones'))
            assert(DRE:IsValidPlayerName('Élodie Longsurname'))
        ''')

    def test_secret_values_rejected_before_use(self):
        self.check('''
            local secret=setmetatable({}, {__concat=function() error('secret concat') end,
              __tostring=function() error('secret stringify') end,__index=function() error('secret indexing') end})
            issecretvalue=function(value) return rawequal(value,secret) end
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM',secret)
            DRE:CHAT_MSG_WHISPER('CHAT_MSG_WHISPER',secret,'Alice')
            DRE:CHAT_MSG_WHISPER('CHAT_MSG_WHISPER','DEATHROLL_ACCEPT',secret)
            DRE:AddToDebugBuffer('SYSTEM',secret)
            units.target={secret,'Smith'}
            assert(not DRE:GetUnitPlayerName('target'))
            assert(not DRE.pendingChallenge)
        ''')

    def test_accept_opener_preserves_maximum_and_records_one(self):
        self.check('''
            DRE:SetWagerInputs(500)
            DRE.UI.goldEdit=AceGUI:Create('EditBox');DRE.UI.goldEdit:SetText('0')
            DRE.UI.silverEdit=AceGUI:Create('EditBox');DRE.UI.silverEdit:SetText('5')
            local observed={playerName='Alice',roll=40,maxRoll=100,timestamp=clock}
            assert(DRE:AcceptObservedChallenge(observed))
            assert(DRE.gameState.initialRoll==100 and DRE.gameState.currentRoll==40)
            assert(#DRE.UI.rollHistory>=1)
            DRE:HandleGameRoll('Me',1,40)
            assert(DRE.db.profile.history.Alice.recentGames[1].initialRoll==100)
            observed.roll=1
            assert(DRE:AcceptObservedChallenge(observed))
            assert(not DRE.gameState and DRE.db.profile.history.Alice.wins==1)
        ''')

    def test_expired_and_changed_target_challenges_rejected(self):
        self.check('''
            local observed={playerName='Alice',roll=40,maxRoll=100,timestamp=clock-61}
            assert(not DRE:AcceptObservedChallenge(observed) and not DRE.gameState)
            observed.timestamp=clock; units.target={'Bob','LocalRealm'}
            assert(not DRE:AcceptObservedChallenge(observed) and not DRE.gameState)
        ''')

    def test_challenge_popup_contract_and_stale_callback(self):
        self.check('''
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:500:2.3.9','Alice')
            local first=DRE.pendingChallenge
            local firstDialog=DRE.activeDialog
            assert(firstDialog.data==first and firstDialog.textValue:find('Alice'))
            assert(#popups==0)
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.9','Bob')
            local second=DRE.pendingChallenge
            DRE:CloseDialog(firstDialog,false,'override')
            assert(DRE.pendingChallenge==second)
            DRE:CloseDialog(DRE.activeDialog,false,'timeout')
            assert(not DRE.pendingChallenge)
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:1000000:0:2.3.9','Alice')
            assert(not DRE.pendingChallenge)
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:999999999999999999999:2.3.9','Alice')
            assert(not DRE.pendingChallenge)
        ''')

    def test_zero_wager_and_displayed_terms(self):
        self.check('''
            DRE.ShowMainWindow=function() end
            DRE.UI.goldEdit=AceGUI:Create('EditBox'); DRE.UI.goldEdit:SetText('10')
            DRE.pendingChallenge={sender='Alice',roll=100,wager=0,timestamp=now}
            assert(DRE:AcceptChallenge())
            assert(DRE.UI.goldEdit:GetText()=='0')
            DRE.UI.goldEdit:SetText('3')
            assert(DRE:AcceptObservedChallenge({playerName='Alice',roll=40,maxRoll=100,timestamp=clock}))
            assert(DRE.gameState.wager==30000)
        ''')

    def test_pending_roll_timers_belong_to_request(self):
        self.check('''
            DRE:StartActualGame('Alice',100,0); DRE:PerformRoll()
            local oldRoll,oldTimeout=timers[1],timers[2]
            DRE.gameState=nil
            DRE:StartActualGame('Bob',200,0); DRE:PerformRoll()
            local pending=DRE.gameState.pendingRoll
            oldRoll.callback();oldTimeout.callback()
            assert(#rolls==0 and DRE.gameState.pendingRoll==pending)
            timers[#timers-1].callback()
            assert(#rolls==1 and rolls[1][2]==200)
            DRE:HandleGameRoll('Me',100,200)
            assert(not DRE.gameState.pendingRoll)
        ''')

    def test_old_timeout_does_not_reset_next_turn(self):
        self.check('''
            DRE:StartActualGame('Alice',100,0);DRE:PerformRoll()
            local oldTimeout=timers[2]
            DRE:HandleGameRoll('Me',50,100);DRE:HandleGameRoll('Alice',30,50);DRE:PerformRoll()
            local pending=DRE.gameState.pendingRoll
            oldTimeout.callback()
            assert(DRE.gameState.pendingRoll==pending and DRE.UI.gameState=='WAITING_FOR_ROLL_RESULT')
        ''')

    def test_editor_identity_survives_insertion_and_merge(self):
        self.check('''
            local _,id=DRE:AddGameToHistory('Alice','Won',100,100)
            DRE:AddGameToHistory('Alice','Lost',200,100)
            assert(DRE:EditGameRecordById(id,'Won',999,100))
            assert(DRE.db.profile.history.Alice.recentGames[1].goldAmount==200)
            assert(DRE:MergePlayerHistory('Alice','Alice Smith'))
            assert(DRE:DeleteGameRecordById(id))
            assert(#DRE.db.profile.history['Alice Smith'].recentGames==1)
            assert(not DRE:EditGameRecordById(id,'Won',1,100))
        ''')

    def test_reset_cannot_reuse_editor_identity(self):
        self.check('''
            local _,old=DRE:AddGameToHistory('Alice','Won',100,100)
            DRE:ResetAllData()
            local _,new=DRE:AddGameToHistory('Alice','Won',100,100)
            assert(new~=old and not DRE:DeleteGameRecordById(old))
        ''')

    def test_legacy_deduplication_preserves_ambiguous_games(self):
        self.check('''
            DRE.db.profile.history.Alice={wins=2,losses=0,gamesPlayed=2,goldWon=200,goldLost=0,recentGames={
              {date='2026-11-04 12:00',result='Won',goldAmount=100,initialRoll=100},
              {date='2026-11-04 12:00',result='Won',goldAmount=100,initialRoll=100}}}
            DRE:DeduplicateHistoryData()
            local p=DRE.db.profile.history.Alice
            assert(#p.recentGames==2 and p.goldWon==200 and p.wins==2)
            local first=p.recentGames[1].id
            DRE.historySchemaProfile=nil;DRE:EnsureHistorySchema()
            assert(p.recentGames[1].id==first)
            local duplicate={};for k,v in pairs(p.recentGames[1]) do duplicate[k]=v end
            table.insert(p.recentGames,duplicate)
            DRE:DeduplicateHistoryData()
            assert(#p.recentGames==2 and p.wins==2)
        ''')

    def test_same_second_games_and_streaks_have_stable_order(self):
        self.check('''
            DRE:AddGameToHistory('Alice','Won',100,100)
            DRE:AddGameToHistory('Bob','Lost',100,100)
            DRE:AddGameToHistory('Alice','Won',100,100)
            DRE:DeduplicateHistoryData()
            assert(DRE.db.profile.history.Alice.wins==2)
            assert(DRE.db.profile.goldTracking.currentStreak==1 and DRE.db.profile.goldTracking.bestWinStreak==1)
            assert(not DRE:FindGameRecordIndexByTimestamp('Alice',now))
        ''')

    def test_legacy_totals_and_streak_checkpoint_survive_repair(self):
        self.check('''
            DRE.db.profile.history.Old={wins=10,losses=0,gamesPlayed=10,goldWon=1000,goldLost=0,recentGames={}}
            DRE.db.profile.goldTracking={totalWon=1000,totalLost=0,currentStreak=10,bestWinStreak=10,worstLossStreak=0}
            DRE:EnsureHistorySchema()
            local _,id=DRE:AddGameToHistory('Alice','Won',0,100)
            assert(DRE:UpdateGameWagerById(id,500))
            assert(DRE.db.profile.history.Old.wins==10 and DRE.db.profile.goldTracking.totalWon==1500)
            assert(DRE.db.profile.goldTracking.currentStreak==11 and DRE.db.profile.goldTracking.bestWinStreak==11)
            DRE:DeduplicateHistoryData()
            assert(DRE.db.profile.history.Old.goldWon==1000)
        ''')

    def test_trade_persistence_and_full_identity(self):
        self.check('''
            local _,id=DRE:AddGameToHistory('Alice-RealmA','Won',0,100)
            DRE.db.profile.pendingTradeWagers={{gameId=id,playerName='Alice-RealmA',recordedAt=now,result='Won'}}
            DRE.historySchemaProfile=nil;DRE:EnsureHistorySchema();DRE:PrunePendingTradeWagers()
            DRE.tradeTracking={partner='Alice-RealmB',theirGold=500,myGold=0}
            DRE:HandleTrackedTradeCompletion()
            assert(DRE.db.profile.history['Alice-RealmA'].recentGames[1].goldAmount==0)
            DRE.tradeTracking={partner='Alice-RealmA',theirGold=500,myGold=0}
            DRE:HandleTrackedTradeCompletion()
            assert(DRE.db.profile.history['Alice-RealmA'].recentGames[1].goldAmount==500)
            assert(#DRE.db.profile.pendingTradeWagers==0)
        ''')

    def test_manual_trade_assignment_resolves_ambiguity(self):
        self.check('''
            local _,a=DRE:AddGameToHistory('Alice','Won',0,100)
            local _,b=DRE:AddGameToHistory('Alice','Won',0,100)
            DRE.db.profile.pendingTradeWagers={
              {gameId=a,playerName='Alice',recordedAt=now,result='Won'},
              {gameId=b,playerName='Alice',recordedAt=now,result='Won'}}
            DRE.tradeTracking={partner='Alice',theirGold=500,myGold=0}
            DRE:HandleTrackedTradeCompletion()
            assert(#DRE.db.profile.pendingTradeWagers==2)
            assert(DRE:EditGameRecordById(a,'Won',500,100))
            assert(#DRE.db.profile.pendingTradeWagers==1)
            DRE:HandleTrackedTradeCompletion()
            assert(#DRE.db.profile.pendingTradeWagers==1) -- cannot reuse the ambiguous payment
            DRE.tradeTracking={partner='Alice',theirGold=600,myGold=0}
            DRE:HandleTrackedTradeCompletion()
            assert(#DRE.db.profile.pendingTradeWagers==0)
        ''')

    def test_secondary_windows_release_and_main_keeps_draft(self):
        self.check('''
            DRE:AddGameToHistory('Alice','Won',100,100)
            for i=1,20 do
              DRE:ShowHistory('Alice')
              local windows={};for window in pairs(DRE.transientWindows) do windows[#windows+1]=window end
              for _,window in ipairs(windows) do window:Hide() end
            end
            assert(AceGUI.created==2 and AceGUI.released==40)
            DRE.UI.mainWindow=AceGUI:Create('Frame')
            DRE.UI.goldEdit=AceGUI:Create('EditBox');DRE.UI.goldEdit:SetText('5')
            DRE.UI.rollEdit=AceGUI:Create('EditBox');DRE.UI.rollEdit:SetText('500')
            DRE.UI.inputWager=0;DRE.UI.inputRoll=100
            DRE.UI.mainWindow:Hide();DRE:ShowMainWindow()
            assert(DRE.UI.goldEdit:GetText()=='5' and DRE.UI.rollEdit:GetText()=='500')
        ''')

    def test_stale_ui_callback_does_not_touch_reused_widget(self):
        self.check('''
            local widget=AceGUI:Create('Label')
            DRE:AfterUI(0,function() widget:SetText('stale') end)
            UI=DRE.UI;UI.tabGeneration=(UI.tabGeneration or 0)+1
            AceGUI:Release(widget)
            local reused=AceGUI:Create('Label');assert(reused==widget)
            reused:SetText('new')
            timers[1].callback()
            assert(reused:GetText()=='new')
        ''')

    def test_restored_controls_follow_authoritative_turn(self):
        self.check('''
            DRE:StartActualGame('Alice',100,500)
            DRE:HandleGameRoll('Me',35,100)
            DRE.UI.gameButton=AceGUI:Create('Button')
            DRE.UI.rollEdit=AceGUI:Create('EditBox')
            DRE:RestoreGameControls()
            assert(DRE.UI.gameButton.disabled and DRE.UI.rollEdit:GetText()=='35')
            DRE:HandleGameRoll('Alice',20,35)
            DRE:RestoreGameControls()
            assert(not DRE.UI.gameButton.disabled and DRE.UI.gameButton:GetText()=='Roll 1-20')
        ''')

    def test_invalid_start_keeps_ui_usable(self):
        self.check('''
            assert(not DRE:StartDeathRoll('Alice',0/0,0))
            assert(not DRE:StartDeathRoll('Alice',100,math.huge))
            assert(not DRE:StartDeathRoll('Alice',10.5,0))
            assert(not DRE.gameState and DRE.UI.gameState=='WAITING')
            assert(DRE:StartDeathRoll('Élodie',100,0))
        ''')

    def test_full_name_commands(self):
        self.check('''
            DRE:AddGameToHistory('Alice Smith','Won',100,100)
            DRE:SlashCommand('merge "Alice Smith" "Alice Jones"')
            assert(DRE.db.profile.history['Alice Jones'] and not DRE.db.profile.history['Alice Smith'])
            DRE:SlashCommand('setsuspicious Alice Jones 3')
            assert(DRE.db.profile.suspiciousRolls['Alice Jones'].count==3)
            DRE:SlashCommand('clearsuspicious "Alice Jones"')
            assert(not DRE.db.profile.suspiciousRolls['Alice Jones'])
            local player,channel
            DRE.SendPlayerStatsBroadcast=function(_,p,c) player=p;channel=c;return true,'sent' end
            DRE:SlashCommand('sendstats Alice Jones party')
            assert(player=='Alice Jones' and channel=='PARTY')
            assert(not DRE:ParseCommandArguments('merge "Alice Smith'))
        ''')

    def test_editor_close_refresh_and_delete_confirmation(self):
        self.check('''
            local _,id=DRE:AddGameToHistory('Alice','Won',100,100)
            DRE:ShowEditGameDialog()
            local frame=DRE.editGameFrame
            assert(frame)
            DRE:RefreshEditDialog()
            assert(DRE.editGameFrame)
            DRE.editGameFrame:Hide()
            assert(not DRE.editGameFrame)
            DRE:RefreshEditDialog()
            assert(not DRE.editGameFrame)
            DRE:AddGameToHistory('Alice','Lost',200,100)
            DRE:ShowDialog('DEATHROLL_DELETE_GAME_CONFIRM',nil,nil,id)
            DRE:CloseDialog(DRE.activeDialog,true)
            assert(#DRE.db.profile.history.Alice.recentGames==1)
            assert(DRE.db.profile.history.Alice.recentGames[1].goldAmount==200)
        ''')

    def test_window_tab_roundtrip_during_game(self):
        self.check('''
            DRE:ShowMainWindow()
            DRE:StartActualGame('Alice',100,500)
            DRE:HandleGameRoll('Me',35,100)
            DRE.UI.tabGroup:SelectTab('statistics')
            DRE.UI.tabGroup:SelectTab('deathroll')
            assert(DRE.UI.gameButton.disabled and DRE.UI.rollEdit:GetText()=='35')
            DRE:HandleGameRoll('Alice',20,35)
            DRE.UI.tabGroup:SelectTab('history')
            DRE.UI.tabGroup:SelectTab('deathroll')
            assert(not DRE.UI.gameButton.disabled and DRE.UI.gameButton:GetText()=='Roll 1-20')
        ''')

    def test_disable_cancels_game_and_reopen_is_usable(self):
        self.check('''
            DRE:ShowMainWindow()
            DRE:StartActualGame('Alice',100,0);DRE:PerformRoll()
            DRE:OnDisable()
            for _,timer in ipairs(timers) do timer.callback() end
            assert(#rolls==0 and not DRE.gameState)
            DRE.disabled=false
            DRE:ShowMainWindow()
            assert(not DRE.UI.gameButton.disabled and DRE.UI.gameState=='WAITING')
        ''')

    def test_editing_legacy_outcome_invalidates_current_streak_snapshot(self):
        self.check('''
            DRE.db.profile.history.Alice={wins=10,losses=1,gamesPlayed=11,goldWon=1000,goldLost=100,recentGames={
              {date='2026-11-04 12:00',result='Lost',goldAmount=100,initialRoll=100}}}
            DRE.db.profile.goldTracking={totalWon=1000,totalLost=100,currentStreak=-1,bestWinStreak=10,worstLossStreak=-1}
            DRE:EnsureHistorySchema()
            local game=DRE.db.profile.history.Alice.recentGames[1]
            assert(DRE:EditGameRecordById(game.id,'Won',100,100))
            assert(DRE.db.profile.goldTracking.currentStreak==1)
            assert(DRE.db.profile.goldTracking.bestWinStreak==10)
            assert(DRE.db.profile.legacyStreaks.rebuiltFromRetainedHistory)
        ''')

    def test_deleting_legacy_outcome_does_not_keep_impossible_current_streak(self):
        self.check('''
            DRE.db.profile.history.Alice={wins=11,losses=1,gamesPlayed=12,goldWon=1100,goldLost=100,recentGames={
              {date='2026-11-04 12:01',result='Lost',goldAmount=100,initialRoll=100},
              {date='2026-11-04 12:00',result='Won',goldAmount=100,initialRoll=100}}}
            DRE.db.profile.goldTracking={totalWon=1100,totalLost=100,currentStreak=-1,bestWinStreak=11,worstLossStreak=-1}
            DRE:EnsureHistorySchema()
            assert(DRE:DeleteGameRecordById(DRE.db.profile.history.Alice.recentGames[1].id))
            assert(DRE.db.profile.goldTracking.currentStreak==1)
        ''')

    def test_private_dialog_timeout_and_replacement_ownership(self):
        self.check('''
            StaticPopup_Show=function() error('protected popup stack entered') end
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Alice')
            local first=DRE.activeDialog
            local staleAccept=DRE.dialogWindow.acceptButton.callbacks.OnClick
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:200:0:2.3.10','Bob')
            local second=DRE.activeDialog
            staleAccept();timers[1].callback()
            assert(DRE.activeDialog==second and DRE.pendingChallenge.sender=='Bob')
            timers[2].callback()
            assert(not DRE.activeDialog and not DRE.pendingChallenge and #sent==0)
            assert(not DRE.dialogWindow:IsShown())
        ''')

    def test_dialog_escape_controller_and_close_decline_once(self):
        self.check('''
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Alice')
            local window=DRE.dialogWindow
            local onPad=window.frame.callbacks.OnGamePadButtonDown
            assert(onPad(window.frame,'PAD1')==true and DRE.pendingChallenge)
            assert(onPad(window.frame,'PAD2')==false)
            assert(not DRE.pendingChallenge and #sent==1 and sent[1][1]=='DEATHROLL_DECLINE')
            onPad(window.frame,'PAD2');assert(#sent==1)
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Bob')
            window.frame.callbacks.OnKeyDown(window.frame,'ESCAPE')
            assert(not DRE.pendingChallenge and #sent==2)
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Bob')
            window:Hide()
            assert(not DRE.pendingChallenge and #sent==3)
        ''')

    def test_combat_deferred_dialog_expires_without_resurrection(self):
        self.check('''
            local combat=true
            InCombatLockdown=function() return combat end
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Alice')
            assert(not DRE.dialogWindow and DRE.activeDialog)
            now=now+31;combat=false
            DRE.dialogEventFrame.callbacks.OnEvent()
            assert(not DRE.activeDialog and not DRE.pendingChallenge and not DRE.dialogWindow)
            combat=true
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Bob')
            combat=false;DRE.dialogEventFrame.callbacks.OnEvent()
            assert(DRE.dialogWindow:IsShown())
            DRE.dialogWindow.acceptButton.callbacks.OnClick()
            assert(not DRE.activeDialog and DRE.acceptedChallenge.sender=='Bob')
        ''')

    def test_disable_retires_deferred_and_visible_dialogs(self):
        self.check('''
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Alice')
            local staleAccept=DRE.dialogWindow.acceptButton.callbacks.OnClick
            DRE:OnDisable();staleAccept()
            assert(not DRE.activeDialog and not DRE.pendingChallenge and #sent==0)
            assert(not DRE.dialogWindow:IsShown())
            DRE.disabled=false;InCombatLockdown=function() return true end
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Bob')
            DRE:OnDisable();DRE.disabled=false;InCombatLockdown=function() return false end
            DRE.dialogEventFrame.callbacks.OnEvent()
            for _,timer in ipairs(timers) do timer.callback() end
            assert(not DRE.activeDialog and not DRE.dialogWindow:IsShown())
        ''')

    def test_chat_lockdown_prevents_send_and_reports_challenge_failure(self):
        self.check('''
            local blocked=true
            C_ChatInfo={InChatMessagingLockdown=function() return blocked end,
              SendChatMessage=function(...) sent[#sent+1]={...} end}
            local ok,reason=DRE:SendChatSafely('test','PARTY')
            assert(not ok and reason:find('locked') and #sent==0)
            DRE.db.profile.challengeSystem.sendWhisper=true
            local printed
            DRE.Print=function(_,text) printed=text end
            assert(not DRE:SendChallengeWhisper('Alice',100,0))
            assert(printed:find('not sent') and #sent==0)
            blocked=false
            assert(DRE:SendChatSafely('test','PARTY') and #sent==1)
            C_ChatInfo=nil
            assert(DRE:SendChatSafely('fallback','PARTY') and #sent==2)
        ''')

    def test_dead_challenge_cancels_but_data_confirmation_is_available(self):
        self.check('''
            UnitIsDeadOrGhost=function() return true end
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.10','Alice')
            assert(not DRE.activeDialog and not DRE.pendingChallenge and #sent==0)
            DRE:ShowDialog('DEATHROLL_RESET_CONFIRM')
            assert(DRE.activeDialog and DRE.dialogWindow:IsShown())
            DRE:CloseDialog(DRE.activeDialog,false)
        ''')


if __name__ == '__main__':
    unittest.main()
