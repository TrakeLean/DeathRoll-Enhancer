"""Trade event sequences against actual addon capture and settlement code."""
import unittest
from test_addon import runtime


class TradeEventTests(unittest.TestCase):
    def check(self, code):
        lua = runtime()
        lua.execute('''
            offeredMine,offeredTheirs=0,0
            GetPlayerTradeMoney=function() return offeredMine end
            GetTargetTradeMoney=function() return offeredTheirs end
            tradeVisible=true
            TradeFrame={IsShown=function() return tradeVisible end}
            regionalNames=true;units.NPC={'Alice','Smith'}
            function pendingGame(result, wager)
                local _,id=DRE:AddGameToHistory('Alice Smith',result,wager or 0,100)
                DRE.db.profile.pendingTradeWagers=DRE.db.profile.pendingTradeWagers or {}
                table.insert(DRE.db.profile.pendingTradeWagers,
                  {ownerGUID=playerGUID,gameId=id,playerName='Alice Smith',recordedAt=now,result=result})
                return id
            end
            function amount()
                return DRE.db.profile.history['Alice Smith'].recentGames[1].goldAmount
            end
            function success()
                DRE:UI_INFO_MESSAGE('UI_INFO_MESSAGE',123,ERR_TRADE_COMPLETE)
            end
        ''')
        lua.execute(code)

    def test_settlements_apply_only_the_gold_difference_without_history_replay(self):
        self.check('''
            local g = 10000
            local win = pendingGame('Won', 4*g)
            DRE:AddGameToHistory('Bob','Won',2*g,100)
            local loss = pendingGame('Lost', 9*g)
            DRE:AddGameToHistory('Bob','Lost',3*g,100)
            DRE:AddGameToHistory('Alice Smith','Won',g,100)
            local profile = DRE.db.profile
            local alice, bob = profile.history['Alice Smith'], profile.history.Bob
            local totals = profile.goldTracking
            local _, _, wonGame = DRE:FindGameRecordById(win)
            local _, _, lostGame = DRE:FindGameRecordById(loss)
            assert(totals.currentStreak == 1 and totals.bestWinStreak == 2 and totals.worstLossStreak == -2)

            function DRE:RecalculateGoldTracking() error('rebuilt lifetime totals') end
            function DRE:RecalculateStreaks() error('replayed outcomes') end
            table.sort = function() error('sorted history during payment') end
            local function settle(mine, theirs)
                offeredMine, offeredTheirs = mine, theirs
                DRE:TRADE_SHOW()
                DRE:TRADE_MONEY_CHANGED()
                DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',1,1)
                DRE:TRADE_CLOSED()
                success()
                success()
                assert(totals.currentStreak == 1 and totals.bestWinStreak == 2 and totals.worstLossStreak == -2)
                assert(alice.wins == 2 and alice.losses == 1 and alice.gamesPlayed == 3)
                assert(bob.goldWon == 2*g and bob.goldLost == 3*g)
            end
            settle(0, 15*g)
            assert(wonGame.goldAmount == 15*g and lostGame.goldAmount == 9*g)
            assert(alice.goldWon == 16*g and alice.goldLost == 9*g)
            assert(totals.totalWon == 18*g and totals.totalLost == 12*g)
            settle(7*g, 0)
            assert(lostGame.goldAmount == 7*g and wonGame.goldAmount == 15*g)
            assert(alice.goldWon == 16*g and alice.goldLost == 7*g)
            assert(totals.totalWon == 18*g and totals.totalLost == 10*g)
            assert(#profile.pendingTradeWagers == 0)
        ''')

    def test_many_unpaid_games_share_one_history_search_per_settlement(self):
        self.check('''
            local profile = DRE.db.profile
            local function owe(name, result, owner)
                local _, id = DRE:AddGameToHistory(name, result, 0, 100)
                table.insert(profile.pendingTradeWagers, {
                    gameId=id, playerName=name, result=result, recordedAt=now, ownerGUID=owner or playerGUID
                })
                return profile.history[name].recentGames[1]
            end
            local incoming = owe('Alice Smith','Won')
            local outgoing = owe('Alice Smith','Lost')
            local alt = owe('Alice Smith','Won','another character')
            local others = {}
            for i = 1, 29 do
                others[i] = owe(i % 2 == 0 and 'Bob Stone' or 'Eve Jones', 'Won')
            end
            assert(#profile.pendingTradeWagers == 32)

            local function settle(mine, theirs)
                offeredMine, offeredTheirs = mine, theirs
                DRE:TRADE_SHOW()
                DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',1,1)
                DRE:TRADE_CLOSED()
                local pairsBefore, scans = pairs, 0
                pairs = function(t)
                    if t == profile.history then scans = scans + 1 end
                    return pairsBefore(t)
                end
                success()
                success()
                pairs = pairsBefore
                assert(scans <= 1, 'settlement searched all history ' .. scans .. ' times')
            end
            settle(0, 150000)
            assert(incoming.goldAmount == 150000 and outgoing.goldAmount == 0 and alt.goldAmount == 0)
            assert(#profile.pendingTradeWagers == 31)
            settle(70000, 0)
            assert(outgoing.goldAmount == 70000 and #profile.pendingTradeWagers == 30)
            assert(profile.goldTracking.totalWon == 150000 and profile.goldTracking.totalLost == 70000)
            for i, game in ipairs(others) do
                assert(profile.pendingTradeWagers[i+1].gameId == game.id and game.goldAmount == 0)
            end
            local first = owe('Alice Smith','Won')
            local second = owe('Alice Smith','Won')
            settle(0, 90000)
            assert(first.goldAmount == 0 and second.goldAmount == 0 and alt.goldAmount == 0)
            assert(#profile.pendingTradeWagers == 32 and profile.goldTracking.totalWon == 150000)
        ''')

    def test_forever_surname_incoming_gold_close_before_success(self):
        self.check('''
            pendingGame('Won')
            DRE:TRADE_SHOW();offeredTheirs=123456;DRE:TRADE_MONEY_CHANGED()
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',0,1)
            assert(amount()==0)
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',1,1)
            DRE:TRADE_CLOSED();tradeVisible=false;offeredTheirs=0;units.NPC=nil
            success()
            assert(amount()==123456 and #DRE.db.profile.pendingTradeWagers==0)
            assert(DRE.db.profile.goldTracking.totalWon==123456)
        ''')

    def test_opponent_edits_incoming_gold_before_acceptance(self):
        self.check('''
            local gold = 10000 -- copper per gold
            pendingGame('Won')
            DRE:TRADE_SHOW()
            offeredTheirs = 10 * gold
            DRE:TRADE_MONEY_CHANGED()
            assert(DRE.tradeTracking.theirGold == 10 * gold)
            offeredTheirs = 15 * gold
            DRE:TRADE_MONEY_CHANGED()
            assert(DRE.tradeTracking.theirGold == 15 * gold and amount() == 0)
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',0,1)
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',1,1)
            assert(amount() == 0 and DRE.db.profile.goldTracking.totalWon == 0)
            DRE:TRADE_CLOSED();tradeVisible=false;offeredTheirs=0;units.NPC=nil
            success()
            success()
            assert(amount() == 15 * gold and #DRE.db.profile.pendingTradeWagers == 0)
            assert(DRE.db.profile.goldTracking.totalWon == 15 * gold)
            assert(DRE.db.profile.goldTracking.totalLost == 0)
        ''')

    def test_player_trade_money_captures_edited_offer_before_acceptance(self):
        self.check('''
            local handlers = {}
            function DRE:RegisterEvent(event, method)
                handlers[event] = self[method or event]
            end
            DRE:OnEnable()
            local function fire(event, ...)
                local handle = assert(handlers[event], event .. ' is not registered')
                handle(DRE, event, ...)
            end

            local gold = 10000 -- copper per gold
            pendingGame('Lost')
            fire('TRADE_SHOW')
            offeredMine = 10 * gold
            fire('PLAYER_TRADE_MONEY')
            assert(DRE.tradeTracking.myGold == 10 * gold)
            offeredMine = 15 * gold
            fire('PLAYER_TRADE_MONEY')
            assert(DRE.tradeTracking.myGold == 15 * gold and amount() == 0)
            fire('TRADE_ACCEPT_UPDATE', 1, 1)
            assert(amount() == 0)
            fire('TRADE_CLOSED')
            offeredMine = 0
            fire('PLAYER_TRADE_MONEY')
            success()
            success()
            assert(amount() == 15 * gold and DRE.db.profile.goldTracking.totalLost == 15 * gold)
            assert(#DRE.db.profile.pendingTradeWagers == 0)

            pendingGame('Lost')
            fire('TRADE_SHOW')
            offeredMine = 15 * gold
            fire('PLAYER_TRADE_MONEY')
            fire('TRADE_REQUEST_CANCEL')
            fire('TRADE_CLOSED')
            assert(amount() == 0 and #DRE.db.profile.pendingTradeWagers == 1)
        ''')

    def test_outgoing_gold_success_before_close_and_duplicate_success(self):
        self.check('''
            pendingGame('Lost');DRE:TRADE_SHOW()
            offeredMine=50000;DRE:TRADE_MONEY_CHANGED()
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',1,0)
            success();DRE:TRADE_CLOSED();success()
            assert(amount()==50000 and DRE.db.profile.goldTracking.totalLost==50000)
            assert(#DRE.db.profile.pendingTradeWagers==0)
            pendingGame('Lost');DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',0,0)
            success()
            assert(amount()==0 and #DRE.db.profile.pendingTradeWagers==1)
        ''')

    def test_offer_edits_and_zero_are_respected_while_trade_is_open(self):
        self.check('''
            pendingGame('Won');DRE:TRADE_SHOW()
            offeredTheirs=10000;DRE:TRADE_MONEY_CHANGED()
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',1,0)
            offeredTheirs=0;DRE:TRADE_MONEY_CHANGED()
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',0,0)
            DRE:TRADE_CLOSED();success()
            assert(amount()==0 and #DRE.db.profile.pendingTradeWagers==1)
            DRE:TRADE_SHOW();offeredTheirs=5000;DRE:TRADE_MONEY_CHANGED()
            success();assert(amount()==5000)
        ''')

    def test_cancelled_trade_and_different_partner_cannot_settle(self):
        self.check('''
            pendingGame('Won');DRE:TRADE_SHOW()
            offeredTheirs=10000;DRE:TRADE_MONEY_CHANGED()
            DRE:TRADE_REQUEST_CANCEL();DRE:TRADE_CLOSED()
            DRE:TRADE_MONEY_CHANGED();success()
            assert(amount()==0 and not DRE.tradeTracking)
            units.NPC={'Alice','Jones'};DRE:TRADE_SHOW()
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',1,1);success()
            assert(amount()==0 and #DRE.db.profile.pendingTradeWagers==1)
        ''')

    def test_unidentified_second_trade_cannot_settle_previous_players_debt(self):
        self.check('''
            local restricted = {}
            issecretvalue = function(value) return rawequal(value, restricted) end
            TradeFrameRecipientNameText = {GetText=function() return 'Alice Smith' end}
            for _, won in ipairs({true, false}) do
                local id = pendingGame(won and 'Won' or 'Lost')
                local _, _, record = DRE:FindGameRecordById(id)
                units.NPC = {'Alice','Smith'}
                offeredMine, offeredTheirs = 0, 0
                DRE:TRADE_SHOW()
                DRE:TRADE_CLOSED()
                success()
                local debts = DRE.db.profile.pendingTradeWagers
                for _, identity in ipairs({false, {restricted, 'Smith'}}) do
                    units.NPC = identity or nil
                    tradeVisible = false
                    DRE:TRADE_SHOW()
                    tradeVisible = true
                    offeredMine, offeredTheirs = won and 0 or 20000, won and 20000 or 0
                    DRE:TRADE_MONEY_CHANGED()
                    DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE', 1, 1)
                    DRE:TRADE_CLOSED()
                    units.NPC = {'Alice','Smith'}
                    success()
                    success()
                    assert(record.goldAmount == 0 and #debts == 1 and debts[1].gameId == id)
                    assert(not debts[1].duelPaymentReview)
                end
                -- A new trade with the verified opponent can still pay the same debt.
                DRE:TRADE_SHOW()
                DRE:TRADE_CLOSED()
                success()
                assert(record.goldAmount == 20000 and #debts == 0)
            end
            local totals = DRE.db.profile.goldTracking
            assert(totals.totalWon == 20000 and totals.totalLost == 20000)
        ''')

    def test_unreadable_partner_on_final_offer_keeps_payment_pending(self):
        self.check('''
            pendingGame('Won')
            DRE:TRADE_SHOW()
            offeredTheirs = 70000
            DRE:TRADE_MONEY_CHANGED()
            units.NPC = nil
            offeredTheirs = 150000
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE', 1, 1)
            success()
            assert(amount() == 0 and #DRE.db.profile.pendingTradeWagers == 1)
        ''')

    def test_conflicting_partner_cannot_rebind_until_next_trade(self):
        self.check('''
            pendingGame('Won')
            units.NPC = {'Alice','Jones'}
            DRE:TRADE_SHOW()
            units.NPC = nil
            DRE:TRADE_MONEY_CHANGED()
            units.NPC = {'Alice','Smith'}
            offeredTheirs = 150000
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE', 1, 1)
            DRE:TRADE_MONEY_CHANGED()
            success()
            assert(amount() == 0 and #DRE.db.profile.pendingTradeWagers == 1)
            -- The partner can become readable after the next trade opens.
            units.NPC = nil
            DRE:TRADE_SHOW()
            units.NPC = {'Alice','Smith'}
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE', 1, 1)
            DRE:TRADE_CLOSED()
            success()
            assert(amount() == 150000 and #DRE.db.profile.pendingTradeWagers == 0)
        ''')

    def test_conflicting_guid_stays_ineligible_if_original_partner_returns(self):
        self.check('''
            local getGuid = UnitGUID
            local partnerGUID = 'Player-1-00000002'
            UnitGUID = function(unit)
                if unit == 'NPC' then return partnerGUID end
                return getGuid(unit)
            end
            pendingGame('Lost')
            DRE:TRADE_SHOW()
            offeredMine = 150000
            partnerGUID = 'Player-1-00000003'
            DRE:TRADE_MONEY_CHANGED()
            partnerGUID = 'Player-1-00000002'
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE', 1, 1)
            DRE:TRADE_CLOSED()
            success()
            assert(amount() == 0 and #DRE.db.profile.pendingTradeWagers == 1)
            DRE:TRADE_SHOW()
            success()
            assert(amount() == 150000 and #DRE.db.profile.pendingTradeWagers == 0)
        ''')

    def test_unverified_player_token_cannot_identify_trade(self):
        self.check('''
            pendingGame('Won')
            local restricted = {}
            issecretvalue = function(value) return rawequal(value, restricted) end
            for _, flag in ipairs({false, restricted}) do
                UnitIsPlayer = function() return flag end
                offeredTheirs = 150000
                DRE:TRADE_SHOW()
                DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE', 1, 1)
                success()
                assert(amount() == 0 and #DRE.db.profile.pendingTradeWagers == 1)
            end
        ''')

    def test_late_updates_cannot_erase_closed_or_hidden_trade_snapshot(self):
        self.check('''
            pendingGame('Won');DRE:TRADE_SHOW()
            offeredTheirs=10000;DRE:TRADE_MONEY_CHANGED()
            DRE:TRADE_CLOSED();offeredTheirs=0
            DRE:TRADE_MONEY_CHANGED();DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',0,0)
            success();assert(amount()==10000)
            pendingGame('Won');DRE:TRADE_SHOW()
            offeredTheirs=20000;DRE:TRADE_MONEY_CHANGED()
            tradeVisible=false;offeredTheirs=0
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE',0,0)
            success();assert(amount()==20000)
        ''')

    def test_two_sided_gold_requires_manual_assignment_and_is_consumed_once(self):
        self.check('''
            pendingGame('Won');DRE:TRADE_SHOW()
            offeredMine=20000;offeredTheirs=10000;DRE:TRADE_MONEY_CHANGED()
            local warning
            DRE.Print=function(_,message) warning=message end
            success()
            assert(amount()==0 and warning:find('Both players traded gold'))
            assert(#DRE.db.profile.pendingTradeWagers==1)
            offeredMine=0;DRE:TRADE_MONEY_CHANGED();success()
            assert(amount()==0) -- cannot reuse the completed ambiguous payment
            DRE:TRADE_SHOW();offeredMine=10000;offeredTheirs=20000
            DRE:TRADE_MONEY_CHANGED();success()
            assert(amount()==0 and #DRE.db.profile.pendingTradeWagers==1)
        ''')

    def test_unreadable_offer_does_not_reuse_previous_money(self):
        self.check('''
            pendingGame('Won');DRE:TRADE_SHOW()
            offeredTheirs=10000;DRE:TRADE_MONEY_CHANGED()
            local secret=setmetatable({}, {__tostring=function() error('secret tostring') end})
            issecretvalue=function(value) return rawequal(value,secret) end
            offeredTheirs=secret;DRE:TRADE_MONEY_CHANGED()
            DRE:TRADE_CLOSED();success()
            assert(amount()==0 and #DRE.db.profile.pendingTradeWagers==1)
            DRE:TRADE_SHOW();offeredTheirs=-1;DRE:TRADE_MONEY_CHANGED()
            success();assert(amount()==0)
        ''')

    def test_trade_requires_same_readable_character_at_open_and_completion(self):
        self.check('''
            pendingGame('Won')
            local original = playerGUID
            local restricted = {}
            issecretvalue = function(value) return rawequal(value, restricted) end
            offeredTheirs = 150000
            for _, unavailable in ipairs({false, restricted, 'Player-1-00000002'}) do
                playerGUID = original
                DRE:TRADE_SHOW()
                playerGUID = unavailable
                success()
                assert(amount() == 0)
                DRE:TRADE_SHOW()
                playerGUID = original
                success()
                assert(amount() == 0 and #DRE.db.profile.pendingTradeWagers == 1)
            end
            DRE:TRADE_SHOW()
            success()
            assert(amount() == 150000 and #DRE.db.profile.pendingTradeWagers == 0)
        ''')

    def test_expired_pending_and_disabled_trade_are_not_settled(self):
        self.check('''
            pendingGame('Won');now=now+301;DRE:TRADE_SHOW()
            offeredTheirs=10000;DRE:TRADE_MONEY_CHANGED();success()
            assert(amount()==0 and #DRE.db.profile.pendingTradeWagers==0)
            pendingGame('Won');DRE:TRADE_SHOW();DRE:TRADE_MONEY_CHANGED()
            DRE:OnDisable();DRE:TRADE_MONEY_CHANGED();success()
            assert(amount()==0 and not DRE.tradeTracking)
        ''')
