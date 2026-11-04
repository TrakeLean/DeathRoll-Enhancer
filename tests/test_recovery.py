"""Regression coverage for abandoned games, safe edits, and live history updates."""
import unittest
from test_addon import ROOT, runtime


class RecoveryTests(unittest.TestCase):
    def test_cancel_abandoned_game_without_result_or_payment(self):
        lua = runtime()
        lua.execute('''
            DRE:ShowMainWindow()
            assert(DRE.UI.cancelGameButton.disabled)
            DRE.db.profile.pendingTradeWagers={{gameId='previous',recordedAt=now}}
            DRE:StartDeathRoll('Alice',100,500000,true)
            DRE:HandleGameRoll('Me',50,100)
            DRE:CHAT_MSG_WHISPER('CHAT_MSG_WHISPER','DEATHROLL_DECLINE','Alice')
            assert(DRE.gameState and DRE.UI.gameButton.disabled)
            assert(not DRE:StartDeathRoll('Bob',200,0))
            DRE.UI.tabGroup:SelectTab('history')
            DRE.UI.tabGroup:SelectTab('deathroll')
            assert(not DRE.UI.cancelGameButton.disabled)
            DRE.UI.cancelGameButton.callbacks.OnClick()
            assert(not DRE.gameState and not DRE.UI.isGameActive)
            assert(DRE.UI.cancelGameButton.disabled and not DRE.UI.gameButton.disabled)
            assert(not next(DRE.db.profile.history))
            assert(#DRE.db.profile.pendingTradeWagers==1)
            assert(DRE.db.profile.pendingTradeWagers[1].gameId=='previous')
            assert(DRE.UI.rollEdit:GetText()=='100')
            assert(DRE:StartDeathRoll('Bob',200,0))
            -- A late remote decline must not cancel the new game.
            DRE:CHAT_MSG_WHISPER('CHAT_MSG_WHISPER','DEATHROLL_DECLINE','Alice')
            assert(DRE.gameState.target=='Bob')
        ''')

    def test_cancel_retires_roll_timers_and_works_off_tab(self):
        runtime().execute('''
            DRE:StartActualGame('Alice',100,0)
            DRE:PerformRoll()
            local oldRoll,oldTimeout=timers[1],timers[2]
            DRE:ShowMainWindow()
            DRE.UI.tabGroup:SelectTab('statistics')
            DRE:SlashCommand('cancel')
            assert(not DRE.gameState)
            assert(not DRE:CancelCurrentGame())
            DRE:StartDeathRoll('Bob',200,0)
            local pending=DRE.gameState.pendingRoll
            oldRoll.callback();oldTimeout.callback()
            assert(#rolls==0 and DRE.gameState.pendingRoll==pending)
            assert(not next(DRE.db.profile.history))
            DRE.UI.tabGroup:SelectTab('deathroll')
            assert(not DRE.UI.cancelGameButton.disabled)
        ''')

    def test_editor_rejects_malformed_fields_without_clearing_settlement(self):
        runtime().execute('''
            local _,id=DRE:AddGameToHistory('Alice','Won',500000,100)
            DRE.db.profile.pendingTradeWagers={{gameId=id,playerName='Alice',recordedAt=now,result='Won'}}
            DRE:ShowEditGameDialog()
            local frame=DRE.editGameFrame
            local inputs,save={},nil
            local function visit(widget)
                if widget.kind=='EditBox' then table.insert(inputs,widget) end
                if widget.text=='Save Changes' then save=widget end
                for _,child in ipairs(widget.children) do visit(child) end
            end
            visit(frame)
            assert(#inputs==5 and save)
            for i=2,5 do
                local original=inputs[i]:GetText()
                for _,invalid in ipairs({'abc','1,000','1.5','nan','1e309','-1','1000000'}) do
                    inputs[i]:SetText(invalid)
                    save.callbacks.OnClick()
                    local game=DRE.db.profile.history.Alice.recentGames[1]
                    assert(game.goldAmount==500000 and game.initialRoll==100)
                    assert(#DRE.db.profile.pendingTradeWagers==1)
                    assert(DRE.editGameFrame==frame and frame:IsShown())
                end
                inputs[i]:SetText(original)
            end
            inputs[2]:SetText('12');inputs[3]:SetText('34');inputs[4]:SetText('56')
            inputs[5]:SetText('200')
            save.callbacks.OnClick()
            local game=DRE.db.profile.history.Alice.recentGames[1]
            assert(game.goldAmount==123456 and game.initialRoll==200)
            assert(#DRE.db.profile.pendingTradeWagers==0 and not DRE.editGameFrame)
        ''')

    def test_visible_history_updates_and_clears_deleted_selection(self):
        runtime().execute('''
            DRE:ShowMainWindow()
            DRE.UI.tabGroup:SelectTab('history')
            assert(DRE.UI.historyBox:GetText()=='No players in history yet!')
            local _,id=DRE:AddGameToHistory('Bob','Won',500000,100)
            assert(DRE.UI.selectedHistoryPlayer=='Bob')
            local before=DRE.UI.historyBox:GetText()
            assert(DRE:EditGameRecordById(id,'Won',100000,100))
            assert(DRE.UI.historyBox:GetText()~=before)
            assert(DRE.UI.historyBox:GetText():find(DRE:FormatGold(100000),1,true))
            local _,alice=DRE:AddGameToHistory('Alice','Lost',0,100)
            assert(DRE.UI.selectedHistoryPlayer=='Bob')
            assert(DRE:DeleteGameRecordById(id))
            assert(DRE.UI.selectedHistoryPlayer=='Alice' and DRE.UI.historyDropdown:GetValue()=='Alice')
            assert(DRE:DeleteGameRecordById(alice))
            assert(not DRE.UI.selectedHistoryPlayer and not DRE.UI.historyDropdown:GetValue())
            assert(DRE.UI.historyBox:GetText()=='No players in history yet!')
        ''')

    def test_merge_keeps_selected_source_mapped_to_destination(self):
        runtime().execute('''
            DRE:AddGameToHistory('Alice','Won',0,100)
            DRE:AddGameToHistory('Bob','Won',0,100)
            DRE:ShowMainWindow()
            DRE.UI.tabGroup:SelectTab('history')
            DRE.UI.historyDropdown:SetValue('Bob')
            DRE:UpdateHistoryDisplay('Bob')
            DRE:SlashCommand('merge Bob Zed')
            assert(DRE.UI.selectedHistoryPlayer=='Zed')
            assert(DRE.UI.historyDropdown:GetValue()=='Zed')
            assert(DRE.UI.historyBox:GetText():find('ZED',1,true))
        ''')

    def test_minimap_unlock_calls_library_unlock(self):
        lua = runtime()
        lua.execute('''
            local original=LibStub
            iconCalls={}
            LibStub=function(name,silent)
                if name=='LibDBIcon-1.0' then return {
                    Lock=function(_,addon) table.insert(iconCalls,'lock:'..addon) end,
                    Unlock=function(_,addon) table.insert(iconCalls,'unlock:'..addon) end,
                } end
                return original(name,silent)
            end
        ''')
        lua.execute((ROOT / 'Minimap.lua').read_text())
        lua.execute('''
            DRE:HandleMinimapSlashCommand('lock')
            assert(DRE.db.profile.minimap.lock)
            DRE:HandleMinimapSlashCommand('unlock')
            assert(not DRE.db.profile.minimap.lock)
            assert(iconCalls[1]=='lock:DeathRollEnhancer')
            assert(iconCalls[2]=='unlock:DeathRollEnhancer')
        ''')
