"""Host-only group rounds exercised through real system events and UI callbacks."""
import unittest
from test_addon import runtime


class GroupTests(unittest.TestCase):
    def check(self, code):
        lua = runtime()
        lua.execute('''
            function groupRoll(name,value,maximum)
                DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM',string.format('%s rolls %d (1-%d)',name,value,maximum))
            end
            function startGroup(roster,maximum,channel)
                local ok,reason=DRE:StartGroupRound(roster or 'Me\\nAlice\\nBob',maximum or 100,channel or 'SAY')
                assert(ok,reason)
                return DRE.groupRound
            end
        ''')
        lua.execute(code)

    def test_complete_round_wraps_turns_and_keeps_equal_rolls(self):
        self.check('''
            IsInGroup=function() return true end
            local round=startGroup(nil,nil,'PARTY')
            groupRoll('Me',100,100);groupRoll('Alice',100,100);groupRoll('Bob',100,100)
            assert(round.turn==1 and round.currentRoll==100 and round.rollCount==3)
            groupRoll('Me',50,100);groupRoll('Alice',25,50);groupRoll('Bob',1,25)
            assert(round.status=='finished' and round.loser=='Bob' and round.rollCount==6)
            assert(not DRE:HandleGroupRoll('Bob',1,25))
            assert(not next(DRE.db.profile.history))
            assert(not next(DRE.db.profile.pendingTradeWagers or {}))
            assert(DRE.db.profile.goldTracking.totalWon==0)
            assert(not next(DRE.recentRolls))
            assert(#sent==7 and sent[7][1]:find('Bob rolled 1',1,true))
        ''')

    def test_untrusted_wrong_turn_and_invalid_ranges_cannot_advance(self):
        self.check('''
            local round=startGroup()
            DRE:CHAT_MSG_EMOTE('CHAT_MSG_EMOTE','Me rolls 1 (1-100)','Me')
            DRE:CHAT_MSG_TEXT_EMOTE('CHAT_MSG_TEXT_EMOTE','Me rolls 1 (1-100)','Me')
            DRE:ProcessPotentialRoll('Me rolls 1 (1-100)','Me','WHISPER')
            groupRoll('Mallory',1,100);groupRoll('Alice',1,100)
            groupRoll('Me',1,99);groupRoll('Me',0,100);groupRoll('Me',101,100)
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Me rolls 1 (0-100)')
            assert(round.turn==1 and round.rollCount==0 and #sent==1)
            groupRoll('Me',30,100)
            groupRoll('Me',1,30);groupRoll('Alice',1,100)
            assert(round.turn==2 and round.currentRoll==30 and round.rollCount==1)
            assert(not next(DRE.db.profile.suspiciousRolls or {}))
        ''')

    def test_forever_full_names_and_localized_system_rolls(self):
        self.check('''
            regionalNames=true;units.player={'Élodie','Smith'}
            local round=startGroup('Élodie Smith\\nAlice Smith\\nAlice Jones')
            RANDOM_ROLL_RESULT='%s würfelt. Ergebnis: %d (%d-%d)'
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Élodie Smith würfelt. Ergebnis: 40 (1-100)')
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','Alice Jones würfelt. Ergebnis: 1 (1-40)')
            assert(round.turn==2)
            RANDOM_ROLL_RESULT='%2$d pour %1$s [%3$d à %4$d] %%'
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','20 pour Alice Smith [1 à 40] %')
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','1 pour Alice Jones [1 à 20] %')
            assert(round.status=='finished' and round.loser=='Alice Jones')
        ''')

    def test_roster_and_start_validation_before_any_mutation(self):
        self.check('''
            for _,roster in ipairs({'Me','Me\\nMe-LocalRealm','Me\\n|Hbad','Me\\n',string.rep('A',256)..'\\nBob'}) do
                assert(not DRE:StartGroupRound(roster,100,'SAY'))
            end
            local names={}
            for i=1,41 do names[i]='Player '..string.rep('a',i) end
            assert(not DRE:StartGroupRound(table.concat(names,'\\n'),100,'SAY'))
            for _,maximum in ipairs({1,0,-1,2.5,1000000,math.huge}) do
                assert(not DRE:StartGroupRound('Me\\nAlice',maximum,'SAY'))
            end
            assert(not DRE:StartGroupRound('Me\\nAlice',100,'GUILD'))
            assert(not DRE:StartGroupRound('Me\\nAlice',100,'RAID'))
            assert(not DRE.groupRound and #sent==0)
            local round=startGroup('Alice-OtherRealm\\nAlice-LocalRealm')
            assert(round.players[1]=='Alice-OtherRealm' and round.players[2]=='Alice')
            groupRoll('Alice',1,100)
            assert(round.rollCount==0)
        ''')

    def test_modes_are_exclusive_and_stale_challenge_cannot_record_win(self):
        self.check('''
            DRE:ShowMainWindow()
            DRE.pendingChallenge={sender='Alice',roll=100,wager=0,timestamp=now}
            local challenge=DRE.pendingChallenge
            DRE:ShowDialog('DEATHROLL_CHALLENGE_POPUP','Alice',nil,challenge)
            local accept=DRE.dialogWindow.acceptButton.callbacks.OnClick
            DRE.recentRolls={{playerName='Alice',roll=1,maxRoll=100,timestamp=clock}}
            local round=startGroup()
            accept()
            DRE:HandleChallengeWhisper('DEATHROLL_CHALLENGE:100:0:2.3.13','Alice')
            assert(not DRE.pendingChallenge and not DRE.activeDialog)
            assert(not DRE:AcceptChallenge(challenge))
            assert(not DRE:StartDeathRoll('Alice',100,0))
            assert(not DRE:StartActualGame('Alice',100,0))
            assert(not DRE:StartSpicyDuel('Alice'))
            assert(not DRE:AcceptObservedChallenge({playerName='Alice',roll=1,maxRoll=100,timestamp=clock}))
            DRE:ShowChallengeNotification('Alice',1,100)
            DRE:CheckUIAutoChallenge('Alice',1,100)
            assert(not DRE.gameState and not DRE.spicyDuel and not DRE.UI.incomingChallenge)
            assert(not next(DRE.db.profile.history) and not next(DRE.recentRolls))
            assert(DRE.UI.gameButton.disabled and not DRE.UI.cancelGameButton.disabled)
            assert(not DRE:StartGroupRound('Me\\nBob',100,'SAY'))
            assert(DRE.groupRound==round)
            DRE:CancelGroupRound()
            DRE:StartActualGame('Alice',100,0)
            assert(not DRE:StartGroupRound('Me\\nBob',100,'SAY'))
            DRE:CancelCurrentGame()
            DRE:StartSpicyDuel('Alice')
            assert(not DRE:StartGroupRound('Me\\nBob',100,'SAY'))
        ''')

    def test_cancel_restart_and_delayed_timeout_ownership(self):
        self.check('''
            local round=startGroup()
            assert(DRE:RollGroupTurn())
            assert(#rolls==1 and not DRE:RollGroupTurn())
            local oldTimeout=timers[#timers]
            DRE:SlashCommand('cancel')
            assert(round.status=='cancelled' and not round.pendingRoll)
            assert(DRE:RestartGroupRound())
            local current=DRE.groupRound
            assert(current~=round and current.turn==1 and current.currentRoll==100)
            assert(DRE:RollGroupTurn())
            local pending=current.pendingRoll
            oldTimeout.callback()
            assert(current.pendingRoll==pending)
            timers[#timers].callback()
            assert(not current.pendingRoll)
            groupRoll('Me',50,100)
            assert(not DRE:RollGroupTurn())
            assert(not next(DRE.db.profile.history))
        ''')

    def test_old_timeout_does_not_clear_a_later_turn(self):
        self.check('''
            local round=startGroup('Me\\nAlice',100)
            assert(DRE:RollGroupTurn())
            local old=timers[#timers]
            groupRoll('Me',100,100);groupRoll('Alice',100,100)
            assert(DRE:RollGroupTurn())
            local pending=round.pendingRoll
            old.callback()
            assert(round.pendingRoll==pending)
        ''')

    def test_ui_roundtrip_immutable_roster_and_restart_uses_original_setup(self):
        self.check('''
            DRE:SlashCommand('group')
            assert(DRE.UI.currentTab=='group')
            local w=DRE.UI.groupWidgets
            w.addTarget.callbacks.OnClick()
            assert(DRE:GetGroupDraft().roster=='Me\\nAlice')
            w.start.callbacks.OnClick()
            local round=DRE.groupRound
            assert(w.roster.disabled and w.start.disabled and not w.roll.disabled)
            w.roster.callbacks.OnTextChanged(w,'OnTextChanged','Mallory\\nBob')
            DRE:AddGroupPlayerFromUnit('target')
            assert(round.players[1]=='Me' and #round.players==2)
            groupRoll('Me',50,100)
            DRE.UI.tabGroup:SelectTab('history')
            assert(not DRE.UI.groupWidgets)
            groupRoll('Alice',25,50)
            DRE.UI.tabGroup:SelectTab('group')
            w=DRE.UI.groupWidgets
            assert(w.status:GetText():find('/roll 25',1,true) and not w.roll.disabled)
            DRE.UI.mainWindow:Hide();DRE:ShowMainWindow()
            assert(DRE.groupRound==round)
            w.cancel.callbacks.OnClick()
            w.roster:SetText('Bob\\nAlice')
            w.roster.callbacks.OnTextChanged(w.roster,'OnTextChanged','Bob\\nAlice')
            w.restart.callbacks.OnClick()
            assert(DRE.groupRound.players[1]=='Me' and DRE.groupRound.currentRoll==100)
            assert(w.roster:GetText()=='Me\\nAlice')
        ''')

    def test_disable_retires_round_and_pending_timeout(self):
        self.check('''
            DRE:SlashCommand('group')
            local round=startGroup()
            DRE:RollGroupTurn()
            DRE:OnDisable()
            assert(round.status=='cancelled' and not round.pendingRoll)
            for _,timer in ipairs(timers) do timer.callback() end
            assert(not DRE:StartGroupRound('Me\\nAlice',100,'SAY'))
            assert(not DRE:RollGroupTurn())
            DRE.disabled=false;DRE:ShowMainWindow()
            assert(not DRE.UI.groupWidgets.start.disabled)
            assert(DRE:RestartGroupRound())
        ''')

    def test_chat_failure_does_not_rollback_roll_and_manual_retry_recovers(self):
        self.check('''
            C_ChatInfo={InChatMessagingLockdown=function() return true end}
            DRE:SlashCommand('group')
            local round=startGroup()
            assert(round.chatError and #sent==0)
            groupRoll('Me',50,100)
            assert(round.turn==2 and round.currentRoll==50 and round.chatError)
            assert(DRE.UI.groupWidgets.error:GetText()~='')
            C_ChatInfo=nil
            DRE.UI.groupWidgets.announce.callbacks.OnClick()
            assert(not round.chatError and #sent==1)
            assert(sent[1][1]:find('Alice, /roll 50',1,true))
            SendChatMessage=function() error('blocked') end
            groupRoll('Alice',1,50)
            assert(round.status=='finished' and round.chatError)
        ''')

    def test_chat_audience_is_fixed_and_messages_and_log_are_bounded(self):
        self.check('''
            IsInGroup=function() return true end
            local round=startGroup('Me\\nAlice',100,'PARTY')
            assert(sent[1][2]=='PARTY')
            IsInRaid=function() return true end
            groupRoll('Me',50,100)
            assert(round.chatError and #sent==1)
            IsInRaid=function() return false end
            assert(DRE:AnnounceGroupRound())
            for i=1,50 do
                groupRoll(round.players[round.turn],50,50)
            end
            assert(#round.log==20)
            for _,message in ipairs(sent) do assert(#message[1]<=255 and message[2]=='PARTY') end
        ''')

    def test_roll_failure_reenables_host_control(self):
        self.check('''
            local round=startGroup()
            RandomRoll=function() error('restricted') end
            assert(not DRE:RollGroupTurn())
            assert(not round.pendingRoll and round.rollCount==0)
        ''')

    def test_party_selection_never_silently_broadcasts_to_raid_or_instance(self):
        self.check('''
            IsInGroup=function() return true end
            IsInRaid=function() return true end
            assert(not DRE:StartGroupRound('Me\\nAlice',100,'PARTY'))
            assert(not DRE.groupRound and #sent==0)
            IsInRaid=function() return false end
            LE_PARTY_CATEGORY_INSTANCE=2
            assert(not DRE:StartGroupRound('Me\\nAlice',100,'PARTY'))
            assert(not DRE.groupRound and #sent==0)
            assert(DRE:StartGroupRound('Me\\nAlice',100,'INSTANCE_CHAT'))
            assert(sent[1][2]=='INSTANCE_CHAT')
        ''')

    def test_group_payout_cannot_settle_earlier_1v1_debt_after_finish_or_reload(self):
        self.check('''
            local _,id=DRE:AddGameToHistory('Alice','Won',0,100)
            local debt={gameId=id,playerName='Alice',recordedAt=now,result='Won'}
            DRE.db.profile.pendingTradeWagers={debt}
            local round=startGroup('Alice\\nMe')
            groupRoll('Alice',1,100)
            assert(round.status=='finished' and debt.manualAssignmentRequired)
            -- Only persistent profile data remains after reload.
            DRE.groupRound=nil;DRE.groupDraft=nil
            units.NPC={'Alice','LocalRealm'}
            GetTargetTradeMoney=function() return 54321 end
            DRE:TRADE_SHOW();DRE:TRADE_ACCEPT_UPDATE();DRE:TRADE_CLOSED()
            DRE:UI_INFO_MESSAGE('UI_INFO_MESSAGE',123,ERR_TRADE_COMPLETE)
            assert((select(3,DRE:FindGameRecordById(id))).goldAmount==0)
            assert(#DRE.db.profile.pendingTradeWagers==1)
            assert(DRE.db.profile.goldTracking.totalWon==0)
            assert(DRE:EditGameRecordById(id,'Won',10000,100))
            assert(#DRE.db.profile.pendingTradeWagers==0)
        ''')

    def test_cancellation_preserves_debts_and_unrelated_trade_still_settles(self):
        self.check('''
            local _,alice=DRE:AddGameToHistory('Alice','Lost',0,100)
            local _,carol=DRE:AddGameToHistory('Carol','Won',0,100)
            DRE.db.profile.pendingTradeWagers={
                {gameId=alice,playerName='Alice',recordedAt=now,result='Lost'},
                {gameId=carol,playerName='Carol',recordedAt=now,result='Won'}}
            startGroup('Me\\nAlice');DRE:CancelGroupRound()
            DRE.tradeTracking={partner='Alice',myGold=9000,theirGold=0}
            DRE:HandleTrackedTradeCompletion()
            assert((select(3,DRE:FindGameRecordById(alice))).goldAmount==0)
            assert(#DRE.db.profile.pendingTradeWagers==2)
            DRE.tradeTracking={partner='Carol',myGold=0,theirGold=5000}
            DRE:HandleTrackedTradeCompletion()
            assert((select(3,DRE:FindGameRecordById(carol))).goldAmount==5000)
            assert(#DRE.db.profile.pendingTradeWagers==1)
        ''')

    def test_forty_player_round_and_observer_host(self):
        self.check('''
            local names={}
            for i=1,40 do names[i]='Player '..string.rep('a',i) end
            local round=startGroup(table.concat(names,'\\n'),999999)
            assert(#round.players==40 and not DRE:RollGroupTurn())
            groupRoll('Me',1,999999)
            assert(round.rollCount==0)
            for i=1,40 do groupRoll(names[i],999999,999999) end
            assert(round.turn==1 and round.rollCount==40)
            groupRoll(names[1],1,999999)
            assert(round.status=='finished' and round.loser==names[1])
            for _,message in ipairs(sent) do assert(#message[1]<=255) end
        ''')
