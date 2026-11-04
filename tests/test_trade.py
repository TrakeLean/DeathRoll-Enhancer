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
            function pendingGame(result)
                local _,id=DRE:AddGameToHistory('Alice Smith',result,0,100)
                DRE.db.profile.pendingTradeWagers=DRE.db.profile.pendingTradeWagers or {}
                table.insert(DRE.db.profile.pendingTradeWagers,
                  {gameId=id,playerName='Alice Smith',recordedAt=now,result=result})
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

    def test_expired_pending_and_disabled_trade_are_not_settled(self):
        self.check('''
            pendingGame('Won');now=now+301;DRE:TRADE_SHOW()
            offeredTheirs=10000;DRE:TRADE_MONEY_CHANGED();success()
            assert(amount()==0 and #DRE.db.profile.pendingTradeWagers==0)
            pendingGame('Won');DRE:TRADE_SHOW();DRE:TRADE_MONEY_CHANGED()
            DRE:OnDisable();DRE:TRADE_MONEY_CHANGED();success()
            assert(amount()==0 and not DRE.tradeTracking)
        ''')
