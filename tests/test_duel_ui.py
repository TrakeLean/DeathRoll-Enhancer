"""Exercise the Forever dev window through its buttons and registered game events."""
import unittest
from lupa.lua51 import lua_type

from test_addon import ROOT, MODULES, LuaRuntime, runtime


class ForeverDuelTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime("""
            GetAddOnMetadata = function(_, key)
                if key == 'X-DRE-DuelUI' then return '1' end
                if key == 'Title' then return 'DeathRoll Enhancer (Dev)' end
            end
        """)
        self.check("""
            local events = {}
            function DRE:RegisterEvent(name, method) events[name] = assert(self[method or name]) end
            function fire(name, ...) events[name](DRE, name, ...) end
            function receiveOffer(wager, mode)
                local payload = string.rep('a', 22) .. ':Alice Jones:DEATHROLL_CHALLENGE:100:' .. wager .. ':' .. mode
                fire('CHAT_MSG_ADDON', 'DREInvite2', payload, 'WHISPER', 'Alice Jones')
            end
            addonPackets = {}
            C_ChatInfo = {
                RegisterAddonMessagePrefix = function(prefix) return prefix == 'DREInvite2' and 0 or 3 end,
                SendAddonMessage = function(prefix, payload, channel, target)
                    table.insert(addonPackets, {prefix, payload, channel, target})
                    return 0
                end,
            }
            DRE:OnEnable()
            DRE.db.profile.challengeSystem.trackWagerByTrade = true
            regionalNames = true
            units.player, units.target = {'Me','Smith'}, {'Alice','Jones'}
            units.NPC = units.target
            models, frames, fontStrings = {}, {}, {}
            local create = CreateFrame
            CreateFrame = function(kind, name, parent, ...)
                local frame = create(kind, name, parent, ...)
                frames[#frames+1] = frame
                frame.parent = parent
                local createText = frame.CreateFontString
                function frame:CreateFontString(...)
                    local text = createText(self,...)
                    text.parent = self
                    fontStrings[#fontStrings+1] = text
                    return text
                end
                if kind == 'PlayerModel' then
                    models[#models+1] = frame
                    frame.sequences = {}
                    function frame:HasAnimation(id) return id ~= missingSequence end
                    function frame:SetAnimation(id)
                        assert(type(id) == 'number')
                        table.insert(self.sequences, id)
                    end
                    function frame:SetUnit(unit)
                        self.bound = unit
                        self.binds = (self.binds or 0) + 1
                        if loadImmediately then self:GetScript('OnModelLoaded')(self) end
                        return not rejectModel
                    end
                    function frame:SetAlpha(alpha) self.alpha = alpha end
                    function frame:ClearModel() self.bound = nil end
                end
                return frame
            end
            SetPortraitTexture = function(texture, unit) texture.lastPortraitUnit = unit end
            mine, theirs = 0, 0
            GetPlayerTradeMoney = function() return mine end
            GetTargetTradeMoney = function() return theirs end
            function widgets() return DRE.UI.duelWidgets end
            function click(widget)
                assert(not widget.disabled, widget.text)
                widget.callbacks.OnClick(widget)
            end
            function action() click(widgets().action) end
            function roll(who, value, high)
                fire('CHAT_MSG_SYSTEM', who .. ' rolls ' .. value .. ' (1-' .. high .. ')')
            end
            function success() fire('UI_INFO_MESSAGE', 123, ERR_TRADE_COMPLETE) end
            function payment() return widgets().payment:GetText() end
            function finish(win)
                action()
                assert(widgets().phase == 'active' and DRE.gameState.pendingRoll)
                if win then
                    roll('Me Smith',20,100)
                    assert(widgets().action.disabled)
                    assert(widgets().heading.text == 'Their turn' and DRE.UI.tableHero.opponent == 'Alice Jones')
                    assert(widgets().log.text:find('5%% chance'))
                    roll('Alice Jones',1,20)
                else
                    roll('Me Smith',1,100)
                end
                assert(widgets().phase == 'result')
            end
            DRE:ShowMainWindow()
            assert(DRE.devDuel and DRE.UI.mainWindow.kind == 'DRETableWindow' and DRE.UI.tabGroup.kind == 'SimpleGroup')
        """)

    def check(self, code):
        self.lua.execute(code)

    def test_gold_table_is_only_on_the_duel_tab(self):
        lua = runtime("""
            GetAddOnMetadata = function(_, key) if key == 'X-DRE-DuelUI' then return '1' end end
            local create = CreateFrame
            CreateFrame = function(...)
                local frame = create(...)
                local texture = frame.CreateTexture
                function frame:CreateTexture(...)
                    local region = texture(self, ...)
                    function region:SetTexture(path)
                        self.image, self.color = path, nil
                        if path and type(path) == 'string' and path:match('GoldTable$') then banner = self end
                    end
                    function region:SetColorTexture(...) self.image, self.color = nil, {...} end
                    return region
                end
                return frame
            end
        """)
        lua.execute("""
            DRE:ShowMainWindow()
            local art = assert(banner)
            for _, tab in ipairs({'group', 'history', 'statistics', 'settings'}) do
                DRE:SelectMainSection(tab)
                assert(not art.image and art.color and art.color[4] == 1, tab)
                DRE:SelectMainSection('deathroll')
                assert(art.image:match('GoldTable$') and not art.color)
            end
        """)

    def test_variant_practice_uses_seats_without_recording_matches(self):
        self.check("""
            units.target = units.player
            fire('PLAYER_TARGET_CHANGED')
            local function start(mode)
                widgets().mode:SetValue(mode)
                widgets().mode.callbacks.OnValueChanged(widgets().mode, nil, mode)
                action()
                assert(DRE.gameState.mode == mode)
            end
            local left, right = models[1].parent.score, models[2].parent.score
            for _, badge in ipairs({left, right}) do
                for _, pip in ipairs(badge.pips) do
                    function pip:SetTexture(path) self.path = path end
                    function pip:SetAlpha(alpha) self.alpha = alpha end
                end
            end
            start('twoLives')
            assert(left.pips[2].path:match('DuelHeart$') and left.pips[2].alpha == 1)
            assert(left.caption:GetText() == '2 lives' and right.caption:GetText() == '2 lives')
            roll('Me Smith',1,100)
            assert(left.caption:GetText() == '1 life' and right.caption:GetText() == '2 lives')
            assert(left.pips[1].alpha == 1 and left.pips[2].alpha < 1 and right.pips[2].alpha == 1)
            assert(DRE.gameState.score.player == 1 and DRE.gameState.currentRoll == 100)
            assert(not next(DRE.db.profile.history))
            roll('Me Smith',9,100)
            roll('Me Smith',1,9)
            assert(DRE.UI.duelResult.result == 'Lost' and DRE.UI.duelResult.score.player == 0)
            action()
            start('cursed7')
            assert(not left:IsShown() and not right:IsShown())
            roll('Me Smith',20,100)
            local odds
            for _, text in ipairs(fontStrings) do
                if text:GetText() == '10% to lose' then odds = text end
            end
            assert(odds and odds.parent:IsShown())
            roll('Me Smith',7,20)
            assert(DRE.UI.duelResult.result == 'Won' and widgets().detail:GetText() == 'Final roll 7')
            action()
            start('highRoller')
            assert(right.pips[1].path:match('UI%-GoldIcon$') and right.pips[1].alpha < 1)
            assert(left:IsShown() and left.caption:GetText() == '0 points' and right.caption:GetText() == '0 points')
            roll('Me Smith',1,100)
            roll('Me Smith',1,100)
            assert(DRE.gameState.score.player == 0 and DRE.gameState.score.opponent == 0)
            for i = 1, 2 do
                roll('Me Smith',5,100)
                roll('Me Smith',9,100)
                assert(right.caption:GetText() == (i == 1 and '1 point' or '2 points'))
                assert(right.pips[i].alpha == 1)
            end
            assert(DRE.UI.duelResult.result == 'Lost' and DRE.UI.duelResult.score.opponent == 2)
            assert(not next(DRE.db.profile.history) and not DRE.UI.duelResult.gameId)
            local high = DRE:GetDuelModeStats('highRoller')
            assert(high.points == 0 and high.tiebreaks == 0 and high.tiebreakWins == 0)
            action()
            start('highRoller')
            for i = 1, 2 do
                roll('Me Smith',12,100); roll('Me Smith',12,100)
            end
            roll('Me Smith',15,100); roll('Me Smith',4,100)
            roll('Me Smith',8,100); roll('Me Smith',5,100)
            high = DRE:GetDuelModeStats('highRoller')
            assert(DRE.UI.duelResult.result == 'Won' and high.points == 0 and high.tiebreaks == 0)
            action()
            start('twoLives')
            roll('Me Smith',1,100); roll('Me Smith',1,100)
            roll('Me Smith',9,100); roll('Me Smith',1,9)
            local lives = DRE:GetDuelModeStats('twoLives')
            assert(lives.comebacks == 0 and lives.flawless == 0 and not next(DRE.db.profile.history))
        """)

    def test_wagered_practice_rematch_keeps_gold_and_streaks(self):
        self.check("""
            DRE:AddGameToHistory('Alice Jones', 'Won', 700, 100)
            units.target = units.player
            fire('PLAYER_TARGET_CHANGED')
            DRE:SetTradeWagerModeEnabled(false)
            DRE.UI.goldEdit:SetText('2')
            action()
            roll('Me Smith',1,100)
            DRE:RefreshDuelResultFromHistory()
            click(widgets().double)
            assert(DRE.gameState and DRE.gameState.double)
            roll('Me Smith',1,100)
            local totals = DRE.db.profile.goldTracking
            assert(totals.totalWon == 700 and totals.totalLost == 0 and totals.currentStreak == 1)
            assert(DRE.db.profile.history['Alice Jones'].wins == 1 and not DRE.db.profile.history['Me Smith'])
            assert(#(DRE.db.profile.pendingTradeWagers or {}) == 0)
        """)

    def test_invited_variant_openers_follow_the_match_rules(self):
        for mode, face in [('twoLives', 1), ('cursed7', 7), ('highRoller', 1)]:
            with self.subTest(mode=mode):
                client = ForeverDuelTests()
                client.setUp()
                client.check(f"""
                    receiveOffer(0, 'fixed:unknown')
                    assert(not DRE.pendingChallenge)
                    receiveOffer(0, 'fixed:{mode}')
                    assert(DRE.pendingChallenge.mode == '{mode}')
                    click(DRE.dialogWindow.acceptButton)
                    assert(widgets().mode.disabled and widgets().mode:GetValue() == '{mode}')
                    roll('Alice Jones',{face},100)
                    action()
                    if '{mode}' == 'cursed7' then
                        assert(DRE.UI.duelResult.result == 'Won' and not DRE.gameState)
                    else
                        local g = DRE.gameState
                        assert(g.mode == '{mode}' and g.currentRoll == 100 and g.playerTurn and g.pendingRoll)
                        if '{mode}' == 'twoLives' then assert(g.score.opponent == 1)
                        else assert(g.firstFace == 1 and g.score.player == 0) end
                        assert(not next(DRE.db.profile.history))
                    end
                """)

    def test_double_or_nothing_two_clients_chain_and_break_even(self):
        peer = ForeverDuelTests()
        peer.setUp()
        peer.check("units.player, units.target = {'Alice','Jones'}, {'Me','Smith'}")

        def deliver(src, dst):
            packet = src.lua.eval('table.remove(addonPackets, 1)')
            self.assertIsNotNone(packet)
            sender = src.lua.eval("DRE:GetUnitPlayerName('player')")
            dst.lua.globals().fire('CHAT_MSG_ADDON', packet[1], packet[2], packet[3], sender)

        def opener(face):
            for client in (self, peer):
                client.check(f"roll('Me Smith',{face},100)")
            peer.check("action()")

        self.check("""
            DRE:SetTradeWagerModeEnabled(false)
            DRE.UI.goldEdit:SetText('10')
            widgets().mode:SetValue('cursed7')
            widgets().mode.callbacks.OnValueChanged(widgets().mode,nil,'cursed7')
            action()
            assert(DRE.outgoingChallenge.mode == 'cursed7')
        """)
        deliver(self, peer)
        peer.check("click(DRE.dialogWindow.acceptButton)")
        deliver(peer, self)
        opener(7)
        self.check("assert(widgets().double and DRE.db.profile.goldTracking.totalLost == 100000)")
        peer.check("assert(not widgets().double)")

        for outcome, amount in [('decline', 100000), ('loss', 100000), ('comeback', 200000)]:
            series = f"Series wager  {amount * 2 // 10000}g"
            self.check("click(widgets().double)")
            self.assertEqual(self.lua.eval("widgets().detail:GetText()"), series)
            deliver(self, peer)
            peer.check(f"""
                assert(DRE.pendingChallenge.double and DRE.pendingChallenge.wager == {amount})
                assert(DRE.dialogWindow.message:GetText():find('Double or Nothing',1,true))
                assert(DRE.dialogWindow.message:GetText():find('{series}',1,true))
            """)
            if outcome == 'decline':
                peer.check("click(DRE.dialogWindow.cancelButton)")
                deliver(peer, self)
                self.check("assert(widgets().double and DRE.db.profile.goldTracking.totalLost == 100000)")
                continue
            peer.check("click(DRE.dialogWindow.acceptButton)")
            self.assertEqual(peer.lua.eval("widgets().detail:GetText()"), series)
            deliver(peer, self)
            self.assertEqual(self.lua.eval("widgets().detail:GetText()"), series)
            self.check(f"assert(DRE.gameState.mode == 'cursed7' and DRE.gameState.wager == {amount})")
            opener(7 if outcome == 'loss' else 20)
            if outcome == 'loss':
                self.assertEqual(self.lua.eval('payment()'), 'Series loss  20g')
                self.assertEqual(peer.lua.eval('payment()'), 'Series win  20g')
            if outcome == 'comeback':
                for client in (self, peer):
                    self.assertEqual(client.lua.eval("widgets().detail:GetText()"), series)
                    client.check("roll('Alice Jones',7,20)")
        for client in (self, peer):
            client.check("""
                local gold = DRE.db.profile.goldTracking
                assert(gold.totalWon == 200000 and gold.totalLost == 200000 and not widgets().double)
                assert(#DRE.db.profile.pendingTradeWagers == 0)
                assert(payment() == 'Series even  ·  0g')
            """)
        self.check("""
            local stats = DRE:GetDuelModeStats('cursed7')
            assert(stats.offers == 2 and stats.breakEvens == 1 and stats.sevens == 2)
        """)
        peer.check("""
            local stats = DRE:GetDuelModeStats('all')
            assert(stats.offers == 0 and stats.breakEvens == 0)
            local result = DRE.UI.duelResult
            assert(DRE:EditGameRecordById(result.gameId, 'Lost', 50000, 100))
            assert(payment() == 'Wager  5g')
        """)

    def test_double_or_nothing_waits_for_registered_trade(self):
        self.check("""
            finish(false)
            assert(not widgets().double)
            mine = 50000
            fire('TRADE_SHOW')
            fire('TRADE_ACCEPT_UPDATE',1,1)
            success()
            assert(widgets().doubleStake == 50000)
            click(widgets().double)
            assert(DRE.outgoingChallenge.wager == 50000 and not DRE.outgoingChallenge.trackTrade)
            assert(DRE.db.profile.goldTracking.totalLost == 50000)
        """)

    def test_range_edit_keeps_paid_receipt_and_disables_old_rematch(self):
        self.check("""
            finish(false)
            mine = 50000
            fire('TRADE_SHOW')
            fire('TRADE_ACCEPT_UPDATE',1,1)
            success()
            local result = DRE.UI.duelResult
            assert(widgets().doubleStake == 50000)
            assert(DRE:EditGameRecordById(result.gameId, 'Lost', 50000, 250))
            assert(result.initialRoll == 250 and result.rematchInvalid and not widgets().double)
            assert(payment() == 'Paid 5g to Alice Jones')
            assert(DRE:EditGameRecordById(result.gameId, 'Won', 50000, 250))
            assert(result.outcomeEdited and not result.lastFace and not result.score and not next(result.rolls))
            assert(widgets().heading.text == 'You won')
        """)

    def test_dismissed_winner_can_accept_rematch_after_trade_settles(self):
        self.check("""
            finish(true)
            action()
            theirs = 50000
            fire('TRADE_SHOW')
            fire('TRADE_ACCEPT_UPDATE',1,1)
            success()
            receiveOffer(100000, 'fixed:classic:double:manual')
            assert(not DRE.pendingChallenge)
            receiveOffer(50000, 'fixed:cursed7:double:manual')
            assert(not DRE.pendingChallenge)
            receiveOffer(50000, 'fixed:classic:double:manual')
            assert(DRE.pendingChallenge and DRE.pendingChallenge.double)
            click(DRE.dialogWindow.acceptButton)
            assert(DRE.acceptedChallenge and not DRE.gameState)
        """)

    def test_high_roller_restores_the_actual_faces_after_reload(self):
        self.check("""
            receiveOffer(0,'trade:highRoller')
            click(DRE.dialogWindow.acceptButton)
            roll('Alice Jones',85,100)
            action()
            roll('Me Smith',99,100)
            roll('Alice Jones',11,100)
            roll('Me Smith',90,100)
            assert(DRE.UI.duelResult.result == 'Won')
            DRE:ShowMainWindow('group')
            DRE.UI.duelRestored, DRE.UI.duelResult, DRE.UI.lastDuelResult = nil,nil,nil
            DRE:ShowMainWindow('deathroll')
            local result = DRE.UI.duelResult
            assert(result.rolls.opponent == 11 and result.rolls.player == 90)
            assert(result.score.player == 2 and result.score.opponent == 0)
        """)

    def test_active_turn_stays_at_the_top_and_next_roll_odds_end_with_the_duel(self):
        self.check("""
            DAMAGE_TEXT_FONT = 'test-display-font'
            local heading = widgets().heading
            function heading:SetPoint(point, target, edge, x, y)
                if point == 'TOPLEFT' then self.topInset = y end
            end
            function heading:SetFont(_, size) self.fontSize = size end
            units.target = units.player
            fire('PLAYER_TARGET_CHANGED')
            action()
            assert(heading:GetText() == 'Practice turn 1' and heading.topInset == -8 and heading.fontSize == 17)
            roll('Me Smith',32,100)
            assert(heading:GetText() == 'Practice turn 2')
            assert(widgets().log:GetText():find('3.12% chance to roll 1 next',1,true))
            local odds
            for _, text in ipairs(fontStrings) do
                if text:GetText() == '3.12% to roll a 1' then odds = text end
            end
            assert(odds and odds.parent:IsShown())
            DRE.UI.tableHero:SetNextRollOdds(100)
            assert(odds:GetText() == '3.12% to roll a 1')
            roll('Me Smith',1,32)
            assert(widgets().phase == 'result' and heading.topInset == -49 and heading.fontSize == 31)
            assert(not odds.parent:IsShown())
        """)

    def emote_peer(self):
        peer = runtime("""
            GetAddOnMetadata = function(_, key) if key == 'X-DRE-DuelUI' then return '1' end end
        """)
        peer.execute("""
            regionalNames = true
            units.player, units.target = {'Alice', 'Jones'}, {'Me', 'Smith'}
            DRE:OnEnable()
        """)
        for lua in (self.lua, peer):
            lua.execute("""
                packets = {}
                C_ChatInfo = {
                    RegisterAddonMessagePrefix = function(prefix) registered = prefix; return 0 end,
                    SendAddonMessage = function(prefix, msg, channel, target)
                        assert(prefix == registered and channel == 'WHISPER' and target == DRE:GetUnitPlayerName('target'))
                        table.insert(packets, msg)
                        return 0
                    end,
                    PerformEmote = function(token) performed = token; return not emoteBlocked end,
                }
                DRE:EnableDuelMessages()
                DRE.db.profile.gameplay.autoEmote = true
                function receive(msg, sender) DRE:ReceiveDuelMessage('CHAT_MSG_ADDON', registered, msg, 'WHISPER', sender) end
            """)
        return peer

    def test_two_clients_exchange_the_actual_world_emotes(self):
        peer = self.emote_peer()
        self.check("""
            function DRE:GetRandomHappyEmote() return 'SALUTE' end
            function DRE:GetRandomSadEmote() return 'SURRENDER' end
            for _, model in ipairs(models) do model:GetScript('OnModelLoaded')() end
            action()
            roll('Me Smith', 50, 100)
        """)
        peer.execute("""
            function DRE:GetRandomSadEmote() return 'CRY' end
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM', 'Me Smith rolls 50 (1-100)')
            assert(DRE:AcceptObservedChallenge(DRE:FindRecentTargetRoll('Me Smith')))
            assert(not DRE.UI.tableHero)
        """)
        def deliver(source, index, dest, sender):
            msg = source.eval(f'assert(packets[{index}])')
            dest.globals().receive(msg, sender)
            return msg

        deliver(peer, 1, self.lua, 'Alice Jones')
        deliver(self.lua, 1, peer, 'Me Smith')
        deliver(peer, 2, self.lua, 'Alice Jones')
        peer.execute("DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM', 'Alice Jones rolls 1 (1-50)'); assert(performed == 'CRY')")
        msg = peer.eval('assert(packets[3])')
        self.lua.globals().receive(msg, 'Alice Smith')
        self.lua.globals().receive(msg, 'Alice Jones-OtherRealm')
        self.check("assert(not DRE.gameState.emoteRound.received)")
        self.check("""
            roll('Alice Jones', 1, 50)
            for _, t in ipairs(timers) do if t.delay == 0.75 then t.callback() end end
            assert(performed == 'SALUTE' and models[2].sequences[#models[2].sequences] == 79)
        """)
        deliver(peer, 3, self.lua, 'Alice Jones-LocalRealm')
        self.check("assert(models[2].sequences[#models[2].sequences] == 77); count = #models[2].sequences")
        deliver(peer, 3, self.lua, 'Alice Jones')
        self.check("assert(#models[2].sequences == count)")
        deliver(self.lua, 2, peer, 'Me Smith')
        peer.execute("assert(DRE.UI.duelResult.emoteRound.received == 'SALUTE')")
        self.check("action(); action(); roll('Me Smith', 50, 100)")
        self.lua.globals().receive(msg, 'Alice Jones')
        self.check("assert(not DRE.gameState.emoteRound.received)")

    def test_opening_one_syncs_after_completion_and_failed_emotes_remain_local(self):
        peer = self.emote_peer()
        self.check("""
            function DRE:GetRandomSadEmote() return 'SIGH' end
            for _, model in ipairs(models) do model:GetScript('OnModelLoaded')() end
            action()
            roll('Me Smith', 1, 100)
            assert(performed == 'SIGH')
        """)
        peer.execute("""
            emoteBlocked = true
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM', 'Me Smith rolls 1 (1-100)')
            assert(DRE:AcceptObservedChallenge(DRE:FindRecentTargetRoll('Me Smith')))
            assert(DRE.UI.duelResult.result == 'Won' and not DRE.UI.duelResult.emoteRound.performed)
        """)
        self.lua.globals().receive(peer.eval('packets[1]'), 'Alice Jones')
        peer.globals().receive(self.lua.eval('packets[1]'), 'Me Smith')
        self.lua.globals().receive(peer.eval('packets[2]'), 'Alice Jones')
        peer.globals().receive(self.lua.eval('packets[2]'), 'Me Smith')
        peer.execute("assert(#packets == 2 and DRE.UI.duelResult.emoteRound.received == 'SIGH')")
        self.check("assert(not DRE.UI.duelResult.emoteRound.received)")

    def test_early_synced_sigh_keeps_the_opponent_idle(self):
        self.emote_peer()
        self.check("""
            for _, model in ipairs(models) do model:GetScript('OnModelLoaded')() end
            action()
            roll('Me Smith', 20, 100)
            local round = DRE.gameState.emoteRound
            local peer = string.rep('b', 22)
            receive('J:' .. peer .. ':100:20', 'Alice Jones')
            receive('A:' .. round.id .. ':' .. peer, 'Alice Jones')
            local packet = 'E:' .. round.id .. ':' .. peer .. ':'
            DRE:ReceiveEmoteSync(nil, registered, packet .. 'SIGH', 'PARTY', 'Alice Jones')
            DRE:ReceiveEmoteSync(nil, 'other', packet .. 'SIGH', 'WHISPER', 'Alice Jones')
            receive(packet .. 'DUMMY', 'Alice Jones')
            assert(not round.received)
            receive(packet .. 'SIGH', 'Alice Jones')
            assert(round.received == 'SIGH' and DRE.gameState.isActive and not next(DRE.db.profile.history))
            roll('Alice Jones', 1, 20)
            for _, t in ipairs(timers) do if t.delay == 0.75 then t.callback() end end
            local them = models[2].sequences
            assert(#them == 2 and them[1] == 107 and them[2] == 0)
        """)

    def test_matchup_keeps_the_opponent_through_retarget_and_payout(self):
        self.check("""
            local me, them = unpack(models)
            local slot, banner = them.parent, them.parent.parent
            local event = banner:GetScript('OnEvent')
            assert(me.parent.nameLabel:GetText() == 'Me Smith' and me.bound == 'player')
            assert(slot.nameLabel:GetText() == 'Alice Jones' and them.bound == 'target')
            local loaded = them:GetScript('OnModelLoaded')
            assert(slot.portrait:IsShown() and slot.portrait.lastPortraitUnit == 'target')
            loaded(them)
            assert(them.alpha == 1 and not slot.portrait:IsShown())
            action()
            local count = them.binds
            DRE:RefreshDuel()
            assert(them.binds == count)
            units.target = {'Alice', 'Smith'}
            event(banner, 'PLAYER_TARGET_CHANGED')
            loaded(them)
            assert(slot.nameLabel:GetText() == 'Alice Jones' and slot.standIn and them.alpha == 0 and slot.portrait:IsShown())
            units.focus = {'Alice', 'Jones'}
            event(banner, 'PLAYER_FOCUS_CHANGED')
            assert(them.bound == 'focus' and them.alpha == 0)
            loaded(them)
            assert(them.alpha == 0 and slot.portrait:IsShown())
            them:GetScript('OnModelLoaded')(them)
            roll('Me Smith',1,100)
            assert(widgets().phase == 'result' and them.bound == 'focus' and them.alpha == 1)
            assert(slot.nameLabel:GetText() == 'Alice Jones')
            action()
            assert(slot.nameLabel:GetText() == 'Alice Smith' and them.bound == 'target')
        """)

    def test_matchup_handles_missing_models_practice_and_leaving_duel(self):
        self.check("""
            local them = models[2]
            local slot, banner = them.parent, them.parent.parent
            rejectModel, loadImmediately = true, true
            banner:GetScript('OnEvent')(banner, 'UNIT_MODEL_CHANGED', 'target')
            assert(slot.portrait:IsShown() and slot.portrait.lastPortraitUnit == 'target' and not them:IsShown())
            rejectModel = false
            units.target = units.player
            fire('PLAYER_TARGET_CHANGED')
            assert(slot.nameLabel:GetText() == 'Me Smith' and them.bound == 'player')
            assert(them.alpha == 1 and not slot.portrait:IsShown())
            DRE:ShowMainWindow('history')
            assert(not banner:IsShown() and not them.bound)
            units.target = nil
            DRE:ShowMainWindow()
            assert(not banner:IsShown() and widgets().heading:GetText() == 'Target a player')
        """)

    def test_die_tracks_confirmed_turns_across_tabs_and_payout(self):
        self.check("""
            local left, right = models[1].parent.badge, models[2].parent.badge
            local lspin, rspin = unpack(animationGroups)
            local lg, rg = models[1].parent.turnGlow, models[2].parent.turnGlow
            local board = models[1].parent.parent
            local function recordLight(texture, r, g, b)
                assert(r == g and g == b)
                texture.light = r
            end
            lg.SetVertexColor, rg.SetVertexColor = recordLight, recordLight
            assert(not left:IsShown() and not right:IsShown())
            assert(not lg:IsShown() and not rg:IsShown())
            action()
            assert(lg:IsShown() and not rg:IsShown())
            assert(lspin:IsPlaying() and not right:IsShown() and not left.value)
            roll('Alice Jones', 7, 100)
            roll('Me Smith', 4, 99)
            assert(lg:IsShown() and not rg:IsShown())
            assert(lspin:IsPlaying() and not left.value and not right.value)
            roll('Me Smith', 83, 100)
            assert(left.value == 83 and left:IsShown() and not lspin:IsPlaying() and rspin:IsPlaying())
            local update = assert(board:GetScript('OnUpdate'))
            update(board, 0.275)
            assert(lg.light == 0.5 and rg.light == 0.5 and lg:IsShown() and rg:IsShown())
            roll('Alice Jones', 45, 90)
            DRE:RefreshDuel()
            update(board, 0.275)
            assert(not board:GetScript('OnUpdate') and rg.light == 1 and lg.light == 0)
            assert(rg:IsShown() and not lg:IsShown())
            assert(rspin:IsPlaying() and not right.value)
            DRE:ShowMainWindow('history')
            assert(not rspin:IsPlaying())
            assert(not lg:IsShown() and not rg:IsShown())
            roll('Alice Jones', 55, 83)
            DRE:ShowMainWindow()
            assert(lspin:IsPlaying() and right:IsShown() and right.value == 55)
            assert(lg:IsShown() and not rg:IsShown())
            roll('Me Smith', 1, 55)
            assert(not lg:IsShown() and not rg:IsShown())
            assert(left.value == 1 and right.value == 55 and not lspin:IsPlaying() and not rspin:IsPlaying())
            action()
            assert(not left:IsShown() and not right:IsShown())
        """)

    def test_live_roll_holds_below_the_turn_then_lands_in_the_correct_scaled_badge(self):
        self.check("""
            units.target = units.player
            fire('PLAYER_TARGET_CHANGED')
            DRE.UI.rollEdit:SetText('999999')
            action()
            local left, right = models[1].parent.badge, models[2].parent.badge
            local fighters = models[1].parent.parent
            local hero = fighters.parent
            local odds
            for _, text in ipairs(fontStrings) do
                if text:GetText() == DRE:FormatRollOneChance(999999)..' to roll a 1' then odds = text end
            end
            local label = assert(odds).parent
            function label:SetPoint() error('Roll animation moved the odds label') end
            function label:SetScale() error('Roll animation resized the odds label') end
            function DRE.UI.tableHero.stage:GetTop() return 362 end
            function hero:GetCenter() return 500,400 end
            function left:GetCenter() return 325/self:GetScale(),360/self:GetScale() end
            function right:GetCenter() return 675/self:GetScale(),360/self:GetScale() end
            function left.number:SetAlpha(value) self.alpha = value end
            function right.number:SetAlpha(value) self.alpha = value end
            fighters:GetScript('OnSizeChanged')(fighters,1200,580)
            local scale = left:GetScale()
            assert(scale > 1 and scale == right:GetScale())
            local flight
            for _, frame in ipairs(frames) do
                if frame.parent == fighters and frame ~= left.parent and frame ~= right.parent then
                    flight = frame
                end
            end
            function flight:SetPoint(_, _, _, x, y) self.x,self.y=x,y end
            local function near(x,y) assert(math.abs(x-y)<0.00001) end
            for _, text in ipairs(fontStrings) do
                local measure = text.GetStringWidth
                function text:GetStringWidth()
                    if tonumber(self:GetText()) then return #self:GetText()*13 end
                    return measure(self)
                end
            end
            roll('Me Smith',57,99)
            assert(not flight:GetScript('OnUpdate'))
            roll('Me Smith',654321,999999)
            assert(flight.badge == left and left.number.alpha == 0 and left.value == 654321)
            local step = assert(flight:GetScript('OnUpdate'))
            assert(hero:GetHeight() < 250)
            near(flight:GetScale(),2.4)
            fighters:GetScript('OnSizeChanged')(fighters,498,190)
            step(flight,0)
            near(flight:GetScale()*flight.textWidth,498-2*models[1].parent:GetWidth()-16)
            fighters:GetScript('OnSizeChanged')(fighters,1200,580)
            step(flight,0)
            local y = flight.y*flight:GetScale()
            near(hero:GetHeight()/2-y,74)
            DRE:RefreshDuel()
            step(flight,1)
            near(flight.elapsed,1); near(flight.y*flight:GetScale(),y)
            step(flight,0.15)
            near(flight.x*flight:GetScale(),-87.5)
            near(flight.y*flight:GetScale(),(y-40)/2)
            roll('Me Smith',57,654321)
            assert(flight.badge == right and left.number.alpha == 1 and right.number.alpha == 0)
            local window = DRE.UI.mainWindow.frame
            window:SetWidth(1200); window:SetHeight(900)
            window:GetScript('OnSizeChanged')(window,1200,900)
            step(flight,1)
            near(flight:GetScale(),5.4)
            local start = flight.y*flight:GetScale()
            near(start,hero:GetHeight()*0.15)
            assert(flight.x == 0)
            step(flight,0.15)
            near(flight.x*flight:GetScale(),87.5)
            near(flight.y*flight:GetScale(),(start-40)/2)
            step(flight,0.16)
            assert(not flight:IsShown() and not flight:GetScript('OnUpdate') and right.number.alpha == 1)
            assert(odds:GetText() == '1.75% to roll a 1' and label:IsShown())
            roll('Me Smith',1,57)
            assert(widgets().phase == 'result' and flight.badge == left)
            DRE:SelectMainSection('history')
            assert(not flight:GetScript('OnUpdate') and left.number.alpha == 1)
            DRE:SelectMainSection('deathroll')
            assert(not flight:IsShown())
        """)

    def test_die_alternates_practice_sides_and_handles_incoming_openers(self):
        self.check("""
            local left, right = models[1].parent.badge, models[2].parent.badge
            units.target = units.player
            fire('PLAYER_TARGET_CHANGED')
            action()
            assert(left.rolling and not right.rolling)
            roll('Me Smith', 73, 100)
            assert(left.value == 73 and right.rolling)
            local board = models[1].parent.parent
            board:GetScript('OnUpdate')(board, 1)
            assert(models[2].parent.turnGlow:IsShown() and not models[1].parent.turnGlow:IsShown())
            roll('Me Smith', 1, 73)
            assert(left.value == 73 and right.value == 1 and not right.rolling)
            action()
            units.target = {'Alice','Jones'}
            fire('PLAYER_TARGET_CHANGED')
            roll('Alice Jones', 100, 100)
            assert(right.value == 100 and not right.rolling and not left:IsShown())
            action()
            assert(left.rolling and right.value == 100)
            DRE:CancelCurrentGame()
            roll('Alice Jones', 1, 100)
            action()
            assert(widgets().phase == 'result' and right.value == 1 and not left:IsShown())
        """)

    def test_duel_table_eases_from_its_displayed_size_and_preserves_window_geometry(self):
        self.check("""
            local window = DRE.UI.mainWindow
            local tableFrame = models[1].parent.parent.parent
            local function tick(elapsed)
                assert(tableFrame:GetScript('OnUpdate'))(tableFrame, elapsed)
            end
            local function idleAt(height)
                assert(tableFrame:GetHeight() == height and not tableFrame:GetScript('OnUpdate'))
            end
            idleAt(190)
            action()
            assert(widgets().phase == 'active' and tableFrame:GetHeight() == 190)
            tick(0.07)
            local first = tableFrame:GetHeight()
            assert(first > 190 and first < 209)
            roll('Me Smith', 50, 100)
            tick(0.07)
            local midway = tableFrame:GetHeight()
            assert(math.abs(midway - 228) < 0.001)
            DRE:CancelCurrentGame()
            assert(tableFrame:GetHeight() == 223) -- reserve both setup rows immediately
            tick(0.14)
            assert(tableFrame:GetHeight() < midway and tableFrame:GetHeight() > 190)
            tick(1)
            idleAt(190)
            action()
            tick(0.07)
            roll('Me Smith', 1, 100)
            assert(widgets().phase == 'result')
            tick(0.28)
            idleAt(216) -- leave the settlement and rematch terms visible
            assert(window:GetWidth() == 568 and window:GetHeight() == 516)
            assert(not DRE.db.profile.ui.frameStatus.height)
            action()
            tick(0.07)
            DRE:ShowMainWindow('history')
            idleAt(78)
        """)

    def test_large_duel_windows_resize_both_fighters_and_fallback_portraits(self):
        self.check("""
            local window = DRE.UI.mainWindow.frame
            local left, right = models[1].parent, models[2].parent
            local fighters, board = left.parent, left.parent.parent
            for _, slot in ipairs({left, right}) do
                function slot.portrait:SetSize(w,h) self.width,self.height = w,h end
            end
            local function resize(w,h)
                local binds = models[1].binds
                window:SetWidth(w); window:SetHeight(h)
                window:GetScript('OnSizeChanged')(window,w,h)
                local height = board:GetHeight()
                -- WoW propagates the banner dimensions through SetAllPoints.
                fighters:GetScript('OnSizeChanged')(fighters,w-2,height)
                assert(left:GetWidth() == right:GetWidth() and w-2-2*left:GetWidth() >= 168)
                assert(left.portrait.width == left.portrait.height and left.portrait.width == right.portrait.width)
                assert(left.portrait.height < height-41 and right.portrait.width < right:GetWidth())
                assert(models[1].binds == binds)
                return height,left:GetWidth(),left.portrait.width
            end
            for _, phase in ipairs({'setup','active','result'}) do
                assert(widgets().phase == phase)
                local h1,w1,p1 = resize(1000,800)
                local h2,w2,p2 = resize(1400,1000)
                assert(h2 > h1 and w2 > w1 and p2 > p1)
                assert(h2 <= 1000-250)
                local short,sw,sp = resize(1400,440)
                assert(short == 190 and sw < w2 and sp < p2)
                local tall,tw,tp = resize(500,1000)
                assert(tall < h2 and tw < w2 and tp < p2)
                if phase == 'setup' then action()
                elseif phase == 'active' then roll('Me Smith',1,100) end
            end
        """)

    def test_manual_size_and_visibility_take_precedence_over_duel_animation(self):
        self.check("""
            local frame = DRE.UI.mainWindow.frame
            local board = models[1].parent.parent.parent
            action()
            board:GetScript('OnUpdate')(board, 0.07)
            frame:Hide()
            assert(board:GetHeight() == 266 and not board:GetScript('OnUpdate'))
            DRE:ShowMainWindow()
            DRE:SelectMainSection('history')
            DRE:SelectMainSection('deathroll')
            assert(board:GetHeight() == 266 and not board:GetScript('OnUpdate'))
            DRE:CancelCurrentGame()
            board:GetScript('OnUpdate')(board, 0.07)
            frame:SetHeight(440)
            frame:GetScript('OnSizeChanged')(frame, 568, 440)
            assert(board:GetHeight() == 190 and not board:GetScript('OnUpdate'))
            action()
            assert(board:GetHeight() == 190 and not board:GetScript('OnUpdate'))
        """)

    def test_gold_fade_reverses_from_visible_brightness_and_stops_on_exit(self):
        self.check("""
            local board = models[1].parent.parent
            local left = models[1].parent.turnGlow
            function left:SetVertexColor(r) self.light = r end
            action()
            roll('Me Smith', 70, 100)
            board:GetScript('OnUpdate')(board, 0.2)
            local midway = left.light
            assert(midway > 0.5 and midway < 1)
            roll('Alice Jones', 32, 70)
            assert(left.light == midway)
            board:GetScript('OnUpdate')(board, 0.1)
            assert(left.light > midway and left.light < 1)
            DRE:ShowMainWindow('history')
            assert(not board:GetScript('OnUpdate') and not left:IsShown())
            DRE:ShowMainWindow()
            assert(left.light == 1 and left:IsShown() and not board:GetScript('OnUpdate'))
        """)

    def test_models_throw_on_confirmed_roll_then_share_the_world_emote(self):
        self.check("""
            local me, them = unpack(models)
            me:GetScript('OnModelLoaded')()
            them:GetScript('OnModelLoaded')()
            function DRE:GetRandomHappyEmote() return 'SALUTE' end
            function DRE:GetRandomSadEmote() return 'SURRENDER' end
            DRE.db.profile.gameplay.autoEmote = true
            DoEmote = function(token) worldEmote = token end
            action()
            assert(not me.sequences[1] and not them.sequences[1])
            assert(DRE.UI.tableHero.stage:GetText() == 'Next roll  1–100')
            assert(widgets().detail:GetText() == 'Wager from trade')
            assert(#DRE.UI.duelPane.children == 2)
            roll('Me Smith', 20, 100)
            assert(me.sequences[1] == 107 and not them.sequences[1])
            assert(DRE.UI.tableHero.stage:GetText() == 'Next roll  1–20')
            roll('Alice Jones', 4, 99)
            DRE:RefreshDuel()
            assert(#me.sequences == 1 and #them.sequences == 0)
            roll('Alice Jones', 1, 20)
            assert(them.sequences[1] == 107 and worldEmote == 'SALUTE')
            assert(widgets().phase == 'result' and #me.sequences == 1)
            for _, t in ipairs(timers) do if t.delay == 0.75 then t.callback() end end
            assert(me.sequences[#me.sequences] == 113 and them.sequences[#them.sequences] == 79)
            for _, t in ipairs(timers) do if t.delay == 1 then t.callback() end end
            assert(me.sequences[#me.sequences] == 113)
            DRE:RefreshDuel()
            for _, t in ipairs(timers) do if t.delay == 3 then t.callback() end end
            assert(me.sequences[#me.sequences] == 0 and them.sequences[#them.sequences] == 0)
        """)

    def test_throw_can_wait_for_a_model_and_old_outcomes_do_not_replay(self):
        self.check("""
            local me, them = unpack(models)
            missingSequence = 107
            DRE.db.profile.gameplay.autoEmote = false
            DoEmote = function() error('world emote disabled') end
            function DRE:GetRandomSadEmote() return 'CRY' end
            function DRE:GetRandomHappyEmote() return 'CHEER' end
            action()
            roll('Me Smith', 1, 100)
            assert(#me.sequences == 0)
            me:GetScript('OnModelLoaded')()
            them:GetScript('OnModelLoaded')()
            assert(me.sequences[1] == 63)
            for _, t in ipairs(timers) do if t.delay == 0.75 then t.callback() end end
            assert(me.sequences[#me.sequences] == 77 and them.sequences[#them.sequences] == 68)
            action()
            action()
            roll('Me Smith', 1, 100)
            action()
            local n, m = #me.sequences, #them.sequences
            for _, t in ipairs(timers) do if t.delay == 0.75 then t.callback() end end
            assert(#me.sequences == n and #them.sequences == m)
        """)

    def test_minimap_retries_interrupted_window_construction(self):
        lua = runtime("""
            GetAddOnMetadata = function(_, key) if key == 'X-DRE-DuelUI' then return '1' end end
            local stub = LibStub
            LibStub = function(key, ...)
                if key == 'LibDataBroker-1.1' then
                    return {NewDataObject = function(_, _, data) launcher = data; return data end}
                end
                return stub(key, ...)
            end
        """)
        lua.execute((ROOT / 'Minimap.lua').read_text(encoding='utf-8'))
        lua.execute("""
            local create = AceGUI.Create
            local interrupt = true
            function AceGUI:Create(kind)
                local widget = create(self, kind)
                if kind == 'SimpleGroup' then
                    local setHeight = widget.SetHeight
                    widget.SetHeight = function(w, h)
                        if interrupt and h == 44 then
                            interrupt = false
                            error('interrupted footer setup')
                        end
                        return setHeight(w, h)
                    end
                end
                return widget
            end
            local ok, reason = pcall(launcher.OnClick, nil, 'LeftButton')
            assert(not ok and reason:find('interrupted footer setup'))
            assert(not DRE.UI.mainWindow and not DRE.UI.tabGroup)
            assert(not DRE.UI.tableHero and not DRE.UI.tableFooter)
            launcher.OnClick(nil, 'LeftButton')
            local window = DRE.UI.mainWindow
            assert(window.frame:IsShown() and DRE.UI.duelWidgets.phase == 'setup')
            DRE:SelectMainSection('group')
            window:Hide()
            launcher.OnClick(nil, 'LeftButton')
            assert(DRE.UI.mainWindow == window and window.frame:IsShown())
            assert(DRE.UI.currentTab == 'deathroll' and DRE.UI.tableFooter)
            -- Recover the half-built state seen in the client trace, even if it is visible.
            DRE.UI.tabGroup, DRE.UI.tableFooter = nil, nil
            DRE:SelectMainSection('group')
            assert(not window.frame:IsShown() and DRE.UI.mainWindow ~= window)
            assert(DRE.UI.tabGroup and DRE.UI.currentTab == 'group')
        """)

    def test_native_clicks_and_resizing(self):
        self.check("""
            local window = DRE.UI.mainWindow
            assert(window:GetWidth() == 568 and window:GetHeight() == 516)
            local field = DRE.UI.rollEdit
            field.editbox:GetScript('OnEditFocusGained')()
            field.editbox:SetText('250')
            field.editbox:GetScript('OnTextChanged')(field.editbox, true)
            local button = widgets().action.control
            button:GetScript('OnClick')(button, 'LeftButton')
            assert(DRE.gameState.initialRoll == 250 and not AceGUI.focus)
            local toggle = DRE:CreateWindowWidget('CheckBox')
            local setting
            toggle:SetCallback('OnValueChanged', function(_, _, value) setting=value end)
            toggle.frame:GetScript('OnClick')()
            assert(setting and toggle:GetValue())
            DRE.db.profile.ui.frameStatus = {width=510, height=450}
            window:Hide()
            DRE.UI.mainWindow = nil
            DRE:ShowMainWindow()
            assert(DRE.UI.mainWindow:GetWidth() == 510 and DRE.UI.mainWindow:GetHeight() == 450)
            DRE:ResetWindowSize()
            assert(DRE.UI.mainWindow:GetWidth() == 568 and DRE.UI.mainWindow:GetHeight() == 516)
        """)

    def test_small_window_expands_only_when_the_duel_setup_form_opens(self):
        self.check("""
            local window = DRE.UI.mainWindow
            DRE:SelectMainSection('history')
            window:SetWidth(510)
            window:SetHeight(440)
            DRE:SelectMainSection('deathroll')
            assert(widgets().phase == 'setup' and window:GetWidth() == 510 and window:GetHeight() == 483)
            action()
            DRE:SelectMainSection('history')
            window:SetHeight(440)
            DRE:SelectMainSection('deathroll')
            assert(widgets().phase == 'active' and window:GetHeight() == 440)
            DRE:CancelCurrentGame()
            assert(widgets().phase == 'setup' and window:GetHeight() == 483)
        """)

    def test_bundled_ace_layout_and_widget_pool(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute((ROOT / 'tests/wow_mock.lua').read_text(encoding='utf-8'))
        lua.execute("""
            local stub, protected = LibStub, xpcall
            AceGUI = {}
            LibStub = setmetatable({NewLibrary = function() return AceGUI end},
                {__call = function(_, key, ...)
                    if key == 'AceGUI-3.0' then return AceGUI end
                    return stub(key, ...)
                end})
            -- The client extends Lua 5.1 xpcall to pass through callback arguments.
            xpcall = function(f, onError, ...)
                local args, count = {...}, select('#', ...)
                return protected(function() return f(unpack(args,1,count)) end, onError)
            end
            errors = {}
            geterrorhandler = function() return function(e) errors[#errors+1] = e end end
            table.wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
            GetAddOnMetadata = function(_,key) if key=='X-DRE-DuelUI' then return '1' end end
            local newFrame = CreateFrame
            CreateFrame = function(...)
                local frame = newFrame(...)
                local _, name, _, template = ...
                function frame:GetName() return name end
                if template == 'UIDropDownMenuTemplate' then
                    for _, part in ipairs({'Left', 'Middle', 'Right', 'Text', 'Button'}) do
                        _G[name .. part] = newFrame()
                    end
                end
                frame.points = {}
                function frame:SetPoint(point, ...) self.points[point] = {...} end
                function frame:ClearAllPoints() self.points = {} end
                frame.SetFrameStrata = function(_, strata)
                    assert(strata ~= 'PARENT', 'Use a concrete frame strata or the native default')
                end
                function frame:SetResizeBounds(w,h) self.minWidth,self.minHeight = w,h end
                return frame
            end
        """)
        lib = ROOT / 'Libs/AceGUI-3.0'
        lua.execute((lib / 'AceGUI-3.0.lua').read_text(encoding='utf-8'))
        for name in ('AceGUIContainer-SimpleGroup', 'AceGUIContainer-ScrollFrame', 'AceGUIWidget-Label',
                     'AceGUIWidget-DropDown', 'AceGUIWidget-DropDown-Items'):
            lua.execute((lib / 'widgets' / (name + '.lua')).read_text(encoding='utf-8'))
        for filename in MODULES:
            lua.execute((ROOT / filename).read_text(encoding='utf-8'))
        lua.execute("""
            DRE.db={profile={history={}, gameplay={}, challengeSystem={}, ui={scale=1,frameStatus={}},
                goldTracking={totalWon=0,totalLost=0,currentStreak=0,bestWinStreak=0,worstLossStreak=0}}}
            DRE:ShowMainWindow()
            assert(#errors==0, table.concat(errors,' / '))
            local function checkGoldButton()
                local input, button = DRE.UI.rollEdit, DRE.UI.duelWidgets.useGold
                local mode = DRE.UI.duelPane.children[3]
                local anchor = button.frame.points.TOPLEFT
                assert(mode.frame.points.TOPLEFT[1] == button.frame and mode.children[1]:GetValue() == 'classic')
                assert(anchor[1] == input.frame and anchor[2] == 'TOPRIGHT')
                assert(anchor[4] + button.control.points.TOPLEFT[2] == input.editbox.points.TOPLEFT[2])
                assert(anchor[4] - button.frame:GetHeight() + button.control.points.BOTTOMRIGHT[2]
                    == -input.frame:GetHeight() + input.editbox.points.BOTTOMRIGHT[2])
            end
            checkGoldButton()
            local win, pane = DRE.UI.mainWindow, DRE.UI.duelPane
            local limit = win.frame.minHeight
            local available = limit - 41 - 190 - 13 - 107
            pane.scrollframe:SetHeight(available)
            for _, width in ipairs({win.frame.minWidth-36, 511.375, 997.625}) do
                pane:OnWidthSet(width)
                pane:DoLayout()
                checkGoldButton()
                assert(DRE.UI.copperEdit.frame.points.TOPLEFT[1] == DRE.UI.silverEdit.frame)
                assert(pane.content:GetHeight() + 2 < available and not pane.scrollBarShown,
                    string.format('Setup at width %g needs %g, available %g', width, pane.content:GetHeight(), available))
            end
            local c=DRE.UI.duelWidgets.action.control
            c:GetScript('OnClick')(c,'LeftButton')
            assert(DRE.gameState and DRE.UI.duelWidgets.phase=='active')
            assert(win.frame.minHeight == DRE.tableMinHeight)
            local content = DRE.UI.mainWindow.content
            local anchor = content.points.TOPLEFT
            local tableFrame = anchor[1]
            assert(anchor[2] == 'BOTTOMLEFT' and anchor[3] == 17 and anchor[4] == -13)
            assert(content.points.BOTTOMRIGHT[1] == DRE.UI.mainWindow.frame)
            tableFrame:GetScript('OnUpdate')(tableFrame, 0.14)
            assert(tableFrame:GetHeight() > 190 and tableFrame:GetHeight() < 266)
            assert(content.points.TOPLEFT == anchor)
            DRE:CancelCurrentGame()
            assert(DRE.UI.duelWidgets.phase=='setup' and #DRE.UI.tableFooter.children==1)
            checkGoldButton()
            DRE:SelectMainSection('group')
            local form = assert(DRE.UI.groupWidgets.form)
            for _, width in ipairs({444, 512}) do
                form.content.width = width
                form:DoLayout()
                local range, mode, channel = form.children[5], form.children[6], form.children[7]
                local anchor = channel.frame.points.TOPLEFT
                assert(anchor[1] == mode.frame and anchor[2] == 'TOPRIGHT' and anchor[4] == 0)
                assert(mode.frame.points.TOPLEFT[1] == range.frame and mode.children[1]:GetValue() == 'classic')
                assert(range.frame.width + mode.frame.width + channel.frame.width == width)
                assert(channel.children[1]:GetValue() == 'NONE')
                local total = 0
                for index = 1, 4 do total = total + form.children[index].frame.width end
                assert(total == width)
            end
            local _, id = DRE:AddGameToHistory('Alice', 'Won', 10000, 100)
            DRE:ShowEditGameDialog(id)
            local editor = DRE.editGameFrame.children[1].children[2]
            local actions = editor.children[#editor.children]
            for _, width in ipairs({294, 444}) do
                editor.content.width, actions.content.width = width, width
                editor:DoLayout()
                actions:DoLayout()
                local currency = 0
                for _, field in ipairs(editor.children) do
                    if field.type == 'DRETableInput' and field.relWidth == 0.25 then
                        assert(field.frame.width == width/4)
                        if currency > 0 then assert(field.frame.points.TOPLEFT[2] == 'TOPRIGHT') end
                        currency = currency + 1
                    end
                end
                assert(currency == 4)
                for i, action in ipairs(actions.children) do
                    assert(action.frame.width == width/2)
                    if i % 2 == 0 then assert(action.frame.points.TOPLEFT[2] == 'TOPRIGHT') end
                end
            end
            DRE:SlashCommand('testpopup')
            local popup = DRE.dialogWindow
            popup.content.width = 394
            local measured = 45
            function popup.message.label:GetStringHeight() return measured end
            popup:DoLayout()
            local short = popup:GetHeight()
            assert(short < 278 and short >= 200)
            measured = measured + 24
            popup:DoLayout()
            assert(popup:GetHeight() == short + 24)
            DRE:ShowDialog('DEATHROLL_RESET_CONFIRM')
            assert(popup:GetHeight() == 330 and not popup.inviteBanner:IsShown())
            assert(#errors==0, table.concat(errors,' / '))
        """)

    def test_changed_offers_and_receipt_in_both_directions(self):
        self.check("""
            for _, won in ipairs({true, false}) do
                finish(won)
                assert(widgets().heading.text == (won and 'You won' or 'You lost'))
                assert(payment() == 'Awaiting payment')
                local id = DRE.UI.duelResult.gameId
                mine, theirs = 0, 0
                fire('TRADE_SHOW')
                for _, amount in ipairs({100000, 150000}) do
                    if won then theirs = amount else mine = amount end
                    fire(won and 'TRADE_MONEY_CHANGED' or 'PLAYER_TRADE_MONEY')
                    assert(payment():find((won and 'They offer  ' or 'You offer  ') .. amount/10000 .. 'g'))
                end
                fire('TRADE_ACCEPT_UPDATE',1,1)
                local _, _, record = DRE:FindGameRecordById(id)
                assert(record.goldAmount == 0 and not DRE.UI.duelResult.paid)
                DRE:ShowMainWindow('history')
                fire('TRADE_CLOSED')
                success()
                success()
                DRE:ShowMainWindow()
                assert(record.goldAmount == 150000)
                assert(payment() == (won and 'Received 15g from Alice Jones' or 'Paid 15g to Alice Jones'))
                DRE.UI.mainWindow:Hide()
                DRE:ShowMainWindow()
                assert(DRE.UI.duelResult.gameId == id)
                action()
            end
            local totals = DRE.db.profile.goldTracking
            assert(totals.totalWon == 150000 and totals.totalLost == 150000)
        """)

    def test_duel_payment_follows_merged_opponent_history(self):
        self.check("""
            for _, won in ipairs({true, false}) do
                units.target = {'Alice', 'Jones'}
                fire('PLAYER_TARGET_CHANGED')
                finish(won)
                local result = DRE.UI.duelResult
                local _, existingId = DRE:AddGameToHistory('Alice Stone', 'Won', 20000, 100)
                if not won then DRE:ShowMainWindow('history') end
                DRE:SlashCommand('merge "Alice Jones" "Alice Stone"')
                if not won then DRE:ShowMainWindow('deathroll') end
                assert(DRE.UI.duelResult == result and DRE.UI.tableHero.opponent == 'Alice Stone')
                assert(payment() == 'Awaiting payment')
                local _, _, record = DRE:FindGameRecordById(result.gameId)
                mine, theirs = won and 0 or 150000, won and 150000 or 0
                units.NPC = {'Alice','Jones'}
                fire('TRADE_SHOW')
                success()
                assert(record.goldAmount == 0 and payment() == 'Awaiting payment')
                units.NPC = {'Alice','Stone'}
                fire('TRADE_SHOW')
                assert(payment():find('15g', 1, true))
                fire('TRADE_ACCEPT_UPDATE', 1, 1)
                fire('TRADE_CLOSED')
                if not won then DRE:ShowMainWindow('history') end
                success()
                success()
                if not won then DRE:ShowMainWindow('deathroll') end
                local _, _, existing = DRE:FindGameRecordById(existingId)
                assert(record.goldAmount == 150000 and result.paid == 150000 and existing.goldAmount == 20000)
                assert(payment() == (won and 'Received 15g from Alice Stone' or 'Paid 15g to Alice Stone'))
                assert(#DRE.db.profile.pendingTradeWagers == 0)
                if won then
                    DRE:SlashCommand('merge "Alice Stone" "Alice Green"')
                    assert(payment() == 'Received 15g from Alice Green' and DRE.UI.duelResult == result)
                    DRE:AddGameToHistory('Bob Wells', 'Won', 0, 100)
                    DRE:SlashCommand('merge "Bob Wells" "Bob Dale"')
                    assert(payment() == 'Received 15g from Alice Green' and DRE.UI.duelResult == result)
                end
                action()
                clock = clock + 6
            end
        """)

    def test_confirmed_reset_clears_paid_and_pending_duel_results(self):
        self.check("""
            for _, paid in ipairs({true, false}) do
                finish(true)
                theirs = 70000
                fire('TRADE_SHOW')
                fire('TRADE_ACCEPT_UPDATE', 1, 1)
                if paid then success() end
                local result = DRE.UI.duelResult
                local previousPayment = payment()
                DRE:ShowDialog('DEATHROLL_RESET_CONFIRM')
                click(DRE.dialogWindow.cancelButton)
                assert(DRE.UI.duelResult == result and payment() == previousPayment)
                if not paid then DRE:ShowMainWindow('settings') end
                DRE:ShowDialog('DEATHROLL_RESET_CONFIRM')
                click(DRE.dialogWindow.acceptButton)
                assert(not DRE.UI.duelResult and not DRE:FindGameRecordById(result.gameId))
                if not paid then DRE:ShowMainWindow('deathroll') end
                assert(widgets().phase == 'setup' and not widgets().payment)
                assert(not next(DRE.db.profile.history) and #DRE.db.profile.pendingTradeWagers == 0)
                for _, timer in ipairs(timers) do if timer.delay == 301 then timer.callback() end end
                assert(not DRE.UI.duelResult)
                clock = clock + 6
            end
            finish(true)
            fire('TRADE_CLOSED')
            success() -- late completion from the trade that was open at reset
            assert(payment() == 'Awaiting payment' and not DRE.UI.duelResult.paid)
            fire('TRADE_SHOW')
            fire('TRADE_ACCEPT_UPDATE', 1, 1)
            fire('TRADE_CLOSED')
            success()
            assert(payment() == 'Received 7g from Alice Jones' and #DRE.db.profile.pendingTradeWagers == 0)
        """)

    def test_cancellation_wrong_partner_and_manual_review(self):
        self.check("""
            finish(true)
            local id = DRE.UI.duelResult.gameId
            units.NPC = {'Alice', 'Smith'}
            fire('TRADE_SHOW')
            theirs = 100000
            fire('TRADE_MONEY_CHANGED')
            assert(payment() == 'Awaiting payment')
            success()
            units.NPC = units.target
            fire('TRADE_SHOW')
            fire('TRADE_REQUEST_CANCEL')
            fire('TRADE_CLOSED')
            success()
            assert(payment() == 'Awaiting payment')
            fire('TRADE_SHOW')
            mine = 150000
            fire('PLAYER_TRADE_MONEY')
            success()
            assert(payment() == 'Review payment' and not DRE.UI.duelResult.paid)
            DRE:AddGameToHistory('Other Player','Won',0,100)
            for _, child in ipairs(DRE.UI.tableFooter.children) do
                if child:GetText() == 'Review payment' and child.kind == 'DRETableButton' then click(child) end
            end
            local editor = DRE.editGameFrame.children[1]
            assert(editor.kind == 'ScrollFrame' and editor.children[2].children[1].text:find('Alice Jones'))
            assert(DRE:EditGameRecordById(id,'Lost',150000,100))
            assert(widgets().heading.text == 'You lost' and payment():find('15g'))
            assert(not DRE.UI.duelResult.paid and #DRE.db.profile.pendingTradeWagers == 0)
            assert(DRE:DeleteGameRecordById(id))
            assert(widgets().phase == 'setup')
        """)

    def test_pending_restoration_and_expiry(self):
        self.check("""
            finish(false)
            local id = DRE.UI.duelResult.gameId
            DRE:ShowMainWindow('group')
            DRE.UI.duelRestored, DRE.UI.duelResult = nil, nil
            DRE:ShowMainWindow()
            assert(DRE.UI.duelResult.gameId == id and payment() == 'Awaiting payment')
            assert(models[1].parent.badge.value == 1 and not models[2].parent.badge:IsShown())
            now = now + 301
            for _, timer in ipairs(timers) do if timer.delay == 301 then timer.callback() end end
            assert(payment() == 'Payment window expired')
            action()
            DRE:ShowMainWindow('group')
            DRE:ShowMainWindow()
            assert(widgets().phase == 'setup')
        """)

    def test_restore_newest_valid_debt_with_one_history_search(self):
        self.check("""
            finish(false)
            local profile = DRE.db.profile
            local pending = profile.pendingTradeWagers
            local valid = pending[1]
            local function addPending(id, opponent, outcome, recordedAt)
                table.insert(pending, {gameId=id, ownerGUID=valid.ownerGUID, playerName=opponent,
                    result=outcome, recordedAt=recordedAt})
            end
            local _, older = DRE:AddGameToHistory('Older','Lost',0,100)
            table.insert(pending, 1, {gameId=older, ownerGUID=valid.ownerGUID, playerName='Older',
                result='LOSS', recordedAt=now-1})
            local _, duplicate = DRE:AddGameToHistory('One','Won',0,100)
            for _, name in ipairs({'Two','Three'}) do
                DRE:AddGameToHistory(name,'Won',0,100)
                profile.history[name].recentGames[1].id = duplicate
            end
            addPending(duplicate, 'One', 'Won', now)
            addPending('missing', valid.playerName, valid.result, now)
            addPending(valid.gameId, 'Wrong opponent', valid.result, now)
            addPending(valid.gameId, valid.playerName, 'Won', now) -- the recorded game was lost
            addPending(valid.gameId, valid.playerName, valid.result, now-301)
            DRE:ShowMainWindow('group')
            DRE.UI.duelRestored, DRE.UI.duelResult = nil, nil
            local originalPairs, scans = pairs, 0
            pairs = function(t)
                if t == profile.history then scans = scans + 1 end
                return originalPairs(t)
            end
            DRE:ShowMainWindow('deathroll')
            pairs = originalPairs
            assert(scans <= 1, 'Duel restoration searched history ' .. scans .. ' times')
            assert(#pending == 2 and pending[1].gameId == older and pending[2] == valid)
            assert(DRE.UI.duelResult.gameId == valid.gameId and payment() == 'Awaiting payment')
        """)

    def test_two_characters_pay_same_opponent_from_a_shared_profile(self):
        def saved_value(value):
            if lua_type(value) == 'table':
                return {key: saved_value(item) for key, item in value.items()}
            return value

        def log_in(previous, surname, guid):
            # A new Lua session gets only the persisted profile, as on character select.
            profile = saved_value(previous.lua.eval('DRE.db.profile'))
            client = ForeverDuelTests()
            client.setUp()
            client.lua.globals().savedProfile = client.lua.table_from(profile, recursive=True)
            client.lua.globals().surname = surname
            client.lua.globals().playerGUID = guid
            client.check("""
                units.player = {'Me', surname}
                DRE.db.profile = savedProfile
                DRE:EnsureHistorySchema()
                DRE:PrunePendingTradeWagers()
                DRE:ShowMainWindow('history')
                DRE.UI.duelRestored = nil
                DRE:ShowMainWindow('deathroll')
            """)
            return client

        main_guid = self.lua.globals().playerGUID
        self.check("finish(false)")
        main_game = self.lua.eval('DRE.UI.duelResult.gameId')
        alt = log_in(self, 'Stone', 'Player-1-00000002')
        alt.lua.globals().mainGame = main_game
        alt.check(r"""
            local debts = DRE.db.profile.pendingTradeWagers
            local _, _, mainRecord = DRE:FindGameRecordById(mainGame)
            assert(#debts == 1 and not DRE.UI.duelResult and widgets().phase == 'setup')
            local function pay(amount)
                mine = amount
                fire('TRADE_SHOW')
                fire('PLAYER_TRADE_MONEY')
                fire('TRADE_ACCEPT_UPDATE', 1, 1)
                fire('TRADE_CLOSED')
                success()
            end
            pay(70000)
            assert(mainRecord.goldAmount == 0 and #debts == 1 and DRE.db.profile.goldTracking.totalLost == 0)
            assert(DRE:StartGroupRound('Me Stone\nAlice Jones', 100, 'SAY'))
            DRE:CancelGroupRound()
            assert(not debts[1].manualAssignmentRequired)
            action()
            roll('Me Stone', 1, 100)
            assert(#debts == 2 and debts[1].ownerGUID ~= debts[2].ownerGUID)
            local _, _, altRecord = DRE:FindGameRecordById(DRE.UI.duelResult.gameId)
            pay(150000)
            assert(altRecord.goldAmount == 150000 and payment() == 'Paid 15g to Alice Jones')
            assert(#debts == 1 and debts[1].gameId == mainGame and mainRecord.goldAmount == 0)
            assert(DRE.db.profile.goldTracking.totalLost == 150000)
        """)
        main = log_in(alt, 'Smith', main_guid)
        main.lua.globals().mainGame = main_game
        main.check("""
            assert(DRE.UI.duelResult.gameId == mainGame and payment() == 'Awaiting payment')
            fire('TRADE_SHOW')
            mine = 70000
            fire('PLAYER_TRADE_MONEY')
            fire('TRADE_ACCEPT_UPDATE', 1, 1)
            fire('TRADE_CLOSED')
            success()
            local _, _, record = DRE:FindGameRecordById(mainGame)
            assert(record.goldAmount == 70000 and payment() == 'Paid 7g to Alice Jones')
            assert(#DRE.db.profile.pendingTradeWagers == 0 and DRE.db.profile.goldTracking.totalLost == 220000)
        """)

    def test_cancel_pending_roll_no_result_and_fixed_wager(self):
        self.check("""
            DRE.db.profile.challengeSystem.trackWagerByTrade = false
            DRE:RefreshDuel()
            DRE.UI.goldEdit:SetText('12')
            action()
            local pending = DRE.gameState.pendingRoll
            widgets().action.callbacks.OnClick()
            assert(DRE.gameState.pendingRoll == pending)
            for _, child in ipairs(DRE.UI.tableFooter.children) do
                if child:GetText() == 'Cancel duel' then click(child); break end
            end
            for _, timer in ipairs(timers) do if timer.delay == 0.1 then timer.callback() end end
            assert(#rolls == 0 and not next(DRE.db.profile.history))
            assert(widgets().phase == 'setup' and DRE.UI.goldEdit:GetText() == '12')
            finish(false)
            assert(payment() == 'Wager  12g')
            assert(DRE.db.profile.history['Alice Jones'].recentGames[1].goldAmount == 120000)
        """)

    def test_review_and_received_gold_are_scoped_to_the_character(self):
        self.check("""
            finish(true)
            local debts = DRE.db.profile.pendingTradeWagers
            local mineOnly = debts[1]
            local _, foreignId = DRE:AddGameToHistory('Alice Jones', 'Won', 0, 100)
            local foreign = {gameId=foreignId, ownerGUID='Player-1-00000002', playerName='Alice Jones',
                result='Won', recordedAt=now, manualAssignmentRequired=true}
            table.insert(debts, foreign)
            mine, theirs = 10000, 150000
            fire('TRADE_SHOW')
            success()
            assert(mineOnly.duelPaymentReview and not foreign.duelPaymentReview)
            mine = 0
            fire('TRADE_SHOW')
            success()
            assert(#debts == 1 and debts[1] == foreign and payment() == 'Received 15g from Alice Jones')
            local _, _, record = DRE:FindGameRecordById(foreignId)
            assert(record.goldAmount == 0 and DRE.db.profile.goldTracking.totalWon == 150000)
        """)

    def test_legacy_payment_stays_available_for_manual_edit(self):
        self.check("""
            finish(true)
            local debt = DRE.db.profile.pendingTradeWagers[1]
            debt.ownerGUID = nil -- saved by the previous version
            DRE:ShowMainWindow('history')
            DRE.UI.duelRestored, DRE.UI.duelResult = nil, nil
            DRE:ShowMainWindow('deathroll')
            assert(not DRE.UI.duelResult)
            theirs = 70000
            fire('TRADE_SHOW')
            success()
            local _, _, record = DRE:FindGameRecordById(debt.gameId)
            assert(record.goldAmount == 0 and #DRE.db.profile.pendingTradeWagers == 1 and not debt.ownerGUID)
            assert(DRE:EditGameRecordById(debt.gameId, 'Won', 70000, 100))
            assert(record.goldAmount == 70000 and #DRE.db.profile.pendingTradeWagers == 0)
        """)

    def test_self_duel_and_stale_observed_opener(self):
        self.check("""
            roll('Alice Jones',50,100)
            assert(widgets().action:GetText() == 'Accept opening roll')
            clock = clock + 61
            for _, timer in ipairs(timers) do if timer.delay == 61 then timer.callback() end end
            assert(widgets().action:GetText() == 'Challenge')
            units.target = nil
            fire('PLAYER_TARGET_CHANGED')
            assert(widgets().action.disabled)
            units.target = units.player
            fire('PLAYER_TARGET_CHANGED')
            action()
            assert(not widgets().action.disabled)
            action()
            assert(widgets().action.disabled)
            roll('Me Smith',1,100)
            assert(payment() == 'Practice duel')
            assert(#(DRE.db.profile.pendingTradeWagers or {}) == 0)
        """)

    def test_fixed_invite_then_opening_roll(self):
        self.check("""
            DRE.db.profile.challengeSystem.trackWagerByTrade = false
            DRE:ShowMainWindow('group')
            receiveOffer(500, 'fixed')
            click(DRE.dialogWindow.acceptButton)
            assert(widgets().action.disabled and DRE.UI.silverEdit:GetText() == '5')
            roll('Alice Jones',40,100)
            assert(widgets().action:GetText() == 'Accept opening roll')
            action()
            assert(DRE.gameState.currentRoll == 40 and DRE.gameState.wager == 500)
            roll('Me Smith',1,40)
            assert(widgets().phase == 'result' and payment():find('5s'))
        """)

    def test_accepted_invite_keeps_its_original_opening_roll(self):
        self.check("""
            local id = string.rep('a', 22)
            fire('CHAT_MSG_ADDON', 'DREInvite2', id .. ':Alice Jones:DEATHROLL_CHALLENGE:100:0:trade', 'WHISPER', 'Alice Jones')
            click(DRE.dialogWindow.acceptButton)
            roll('Alice Jones', 39, 100)
            roll('Alice Jones', 12, 50)
            assert(not widgets().action.disabled and widgets().observed.roll == 39, 'the later 1-50 roll hid the opener')
            DRE:SelectMainSection('history')
            units.target = {'Alice', 'Smith'}
            for maximum = 20, 35 do roll('Alice Jones', 2, maximum) end
            roll('Alice Smith', 1, 100)
            roll('Alice Jones', 1, 100)
            DRE:SelectMainSection('deathroll')
            assert(widgets().observed.roll == 39 and widgets().detail.text:find('Alice Jones', 1, true))
            action()
            assert(DRE.gameState.target == 'Alice Jones' and DRE.gameState.initialRoll == 100)
            assert(DRE.gameState.currentRoll == 39 and DRE.gameState.pendingRoll and not next(DRE.db.profile.history))
        """)

    def test_slash_responses_close_the_invite_and_reply_once(self):
        for command in ('decline', 'accept'):
            with self.subTest(command=command):
                self.lua.globals().response = command
                self.check("""
                    local id = string.rep(response == 'accept' and 'a' or 'b', 22)
                    fire('CHAT_MSG_ADDON', 'DREInvite2', id .. ':Alice Jones:DEATHROLL_CHALLENGE:100:0:trade', 'WHISPER', 'Alice Jones')
                    local dialog, window = DRE.activeDialog, DRE.dialogWindow
                    local staleClick = window.acceptButton.callbacks.OnClick
                    local count = #addonPackets
                    assert(window.frame:IsShown() and dialog.data == DRE.pendingChallenge)
                    DRE:SlashCommand(response)
                    assert(not DRE.activeDialog and not window.frame:IsShown() and not DRE.pendingChallenge, 'popup still open')
                    assert((DRE.acceptedChallenge == dialog.data) == (response == 'accept'))
                    assert(#addonPackets == count + 1 and addonPackets[#addonPackets][2] == id .. ':Me Smith:DEATHROLL_' .. response:upper())
                    assert(addonPackets[#addonPackets][4] == 'Alice Jones' and #sent == 0)
                    DRE:SlashCommand(response)
                    DRE:ShowDialog('DEATHROLL_RESET_CONFIRM')
                    staleClick()
                    DRE:CloseDialog(dialog, false, 'timeout')
                    DRE:SlashCommand(response)
                    assert(DRE.activeDialog.definition == DRE.Dialogs.DEATHROLL_RESET_CONFIRM and #addonPackets == count + 1)
                    click(window.cancelButton)
                """)

    def test_accepted_opener_survives_wrong_range_and_expires(self):
        self.check("""
            receiveOffer(0, 'fixed')
            DRE:SlashCommand('accept')
            roll('Alice Jones', 39, 100)
            clock = clock + 1
            roll('Alice Jones', 12, 50)
            local opener = assert(widgets().observed)
            assert(opener.roll == 39 and not widgets().action.disabled)
            clock = opener.timestamp + 61
            DRE:RefreshDuel()
            assert(not widgets().observed and widgets().action.disabled)
            assert(not DRE:AcceptObservedChallenge(opener) and not DRE.gameState)
        """)

    def test_slash_reply_retires_combat_deferred_popup(self):
        self.check("""
            for _, response in ipairs({'decline', 'accept'}) do
                InCombatLockdown = function() return true end
                local count = #addonPackets
                local id = string.rep(response == 'accept' and 'a' or 'b', 22)
                fire('CHAT_MSG_ADDON', 'DREInvite2', id .. ':Alice Jones:DEATHROLL_CHALLENGE:100:0:trade', 'WHISPER', 'Alice Jones')
                assert(DRE.activeDialog and not DRE.dialogWindow)
                DRE:SlashCommand(response)
                InCombatLockdown = function() return false end
                DRE.dialogEventFrame:GetScript('OnEvent')()
                assert(not DRE.activeDialog and not DRE.dialogWindow and not DRE.pendingChallenge)
                assert(#addonPackets == count + 1 and addonPackets[#addonPackets][2]:match(':DEATHROLL_' .. response:upper() .. '$'))
            end
        """)

    def test_slash_accept_at_invite_deadline_closes_without_reply(self):
        self.check("""
            receiveOffer(0, 'fixed')
            now = DRE.activeDialog.expires
            DRE:SlashCommand('accept')
            assert(not DRE.activeDialog and not DRE.dialogWindow.frame:IsShown())
            assert(not DRE.acceptedChallenge and not DRE.pendingChallenge and #addonPackets == 0)
        """)

    def test_two_clients_invite_accept_and_decline_without_chat_whispers(self):
        other = ForeverDuelTests()
        other.setUp()
        other.check("""
            units.player, units.target = {'Alice', 'Jones'}, nil
            DRE:SetTradeWagerModeEnabled(false)
            DRE.UI.mainWindow:Hide()
        """)
        self.check("""
            DRE.db.profile.challengeSystem.sendWhisper = true
            DRE.Print = function(_, text) lastNotice = text end
        """)

        def deliver(source, dest, sender, target):
            packet = source.lua.eval('table.remove(addonPackets, 1)')
            self.assertIsNotNone(packet)
            self.assertEqual((packet[1], packet[3], packet[4]), ('DREInvite2', 'WHISPER', target))
            dest.lua.globals().fire('CHAT_MSG_ADDON', packet[1], packet[2], packet[3], sender + '-LocalRealm')
            return packet[2]

        for button, notice in [('cancelButton', 'declined'), ('acceptButton', 'accepted')]:
            self.check("""
                action()
                assert(#addonPackets == 1 and DRE.outgoingChallenge.id and widgets().phase == 'inviting')
                for _, timer in ipairs(timers) do if timer.delay < 1 then timer.callback() end end
                assert(not DRE.gameState and #rolls == 0)
            """)
            packet = self.lua.eval('addonPackets[1][2]')
            for prefix, channel, sender in [('DREInvite2', 'PARTY', 'Me Smith'),
                                             ('DREInvite2', 'WHISPER', 'Me Jones'),
                                             ('OtherPrefix', 'WHISPER', 'Me Smith')]:
                other.lua.globals().fire('CHAT_MSG_ADDON', prefix, packet, channel, sender)
                other.check('assert(not DRE.pendingChallenge and not DRE.activeDialog)')
            deliver(self, other, 'Me Smith', 'Alice Jones')
            other.check("""
                assert(DRE.dialogWindow.frame:IsShown() and DRE.dialogWindow.inviteBanner:IsShown())
                assert(DRE.pendingChallenge.sender == 'Me Smith' and DRE.pendingChallenge.roll == 100)
            """)
            if notice == 'declined':
                self.check("roll('Me Smith', 1, 100)")
                other.check("""
                    units.target = {'Me', 'Smith'}
                    DRE:ShowMainWindow('deathroll')
                    roll('Me Smith', 1, 100)
                    assert(widgets().action.disabled and not DRE:FindRecentTargetRoll('Me Smith'))
                """)
            other.check(f"click(DRE.dialogWindow.{button}); assert(#addonPackets == 1)")
            reply = other.lua.eval('addonPackets[1][2]')
            deliver(other, self, 'Alice Jones', 'Me Smith')
            self.assertEqual(self.lua.eval('lastNotice'), f'Alice Jones {notice} your DeathRoll challenge' + ('!' if notice == 'accepted' else '.'))
            self.check('assert(not DRE.outgoingChallenge and #sent == 0 and #addonPackets == 0)')
            other.check('assert(not DRE.dialogWindow.frame:IsShown() and #sent == 0 and #addonPackets == 0)')
            if notice == 'declined':
                self.check("clock = clock + 6; roll('Me Smith', 1, 100)")
                for client in (self, other):
                    client.check("""
                        assert(not DRE.gameState and widgets().phase == 'setup' and not widgets().observed)
                        assert(not next(DRE.db.profile.history) and #(DRE.db.profile.pendingTradeWagers or {}) == 0)
                    """)
            else:
                self.lua.globals().fire('CHAT_MSG_ADDON', 'DREInvite2', reply, 'WHISPER', 'Alice Jones')
                self.check("""
                    for _, timer in ipairs(timers) do if timer.delay == 0.1 then timer.callback() end end
                    assert(DRE.gameState.pendingRoll and #rolls == 1 and rolls[1][2] == 100)
                """)
                other.check("""
                    assert(DRE.acceptedChallenge.sender == 'Me Smith' and DRE.UI.mainWindow.frame:IsShown())
                    units.target = {'Me', 'Smith'}
                    fire('PLAYER_TARGET_CHANGED')
                    roll('Me Smith', 40, 100)
                    action()
                    assert(DRE.gameState.currentRoll == 40 and #sent == 0)
                """)
                self.check("roll('Me Smith', 40, 100); roll('Alice Jones', 1, 40)")
                other.check("roll('Alice Jones', 1, 40)")
                for client, outcome in [(self, 'Won'), (other, 'Lost')]:
                    client.check(f"""
                        assert(widgets().phase == 'result' and DRE.UI.duelResult.result == '{outcome}')
                        assert(#DRE.db.profile.pendingTradeWagers == 1)
                    """)

    def test_cancel_expiry_and_stale_replies_cannot_start_a_duel(self):
        self.check("""
            DRE.db.profile.challengeSystem.sendWhisper = true
            action()
            local first = DRE.outgoingChallenge
            local timeout = timers[#timers].callback
            action()
            assert(not DRE.outgoingChallenge and addonPackets[2][2]:match(':DEATHROLL_WITHDRAW$'))
            action()
            local second = DRE.outgoingChallenge
            local function accept(id, name)
                fire('CHAT_MSG_ADDON', 'DREInvite2', id .. ':' .. name .. ':DEATHROLL_ACCEPT', 'WHISPER', name)
            end
            timeout()
            accept(first.id, first.target)
            accept(second.id, 'Other Player')
            assert(DRE.outgoingChallenge == second and not DRE.gameState)
            clock = second.expires
            accept(second.id, second.target)
            assert(not DRE:HasActiveGame() and #rolls == 0 and not next(DRE.db.profile.history))
        """)

    def test_withdrawal_retires_only_its_own_popup_or_accepted_invite(self):
        self.check("""
            local id = string.rep('a', 22)
            local function packet(key, message)
                fire('CHAT_MSG_ADDON', 'DREInvite2', key .. ':Alice Jones:' .. message, 'WHISPER', 'Alice Jones')
            end
            for _, acceptFirst in ipairs({false, true}) do
                packet(id, 'DEATHROLL_CHALLENGE:100:0:trade')
                packet(string.rep('b', 22), 'DEATHROLL_WITHDRAW')
                assert(DRE.activeDialog and DRE.pendingChallenge.inviteId == id)
                if acceptFirst then
                    click(DRE.dialogWindow.acceptButton)
                    assert(DRE.acceptedChallenge.inviteId == id)
                end
                packet(id, 'DEATHROLL_WITHDRAW')
                assert(not DRE.activeDialog and not DRE.pendingChallenge and not DRE.acceptedChallenge)
                assert(not DRE:HasActiveGame() and not next(DRE.db.profile.history))
            end
        """)

    def test_silent_invite_rejected_by_client_never_falls_back_to_chat(self):
        self.check("""
            DRE.db.profile.challengeSystem.sendWhisper = true
            DRE.Print = function(_, text) lastNotice = text end
            C_ChatInfo.SendAddonMessage = function() return 3 end
            action()
            assert(not DRE:HasActiveGame() and #rolls == 0 and not next(DRE.db.profile.history))
            assert(not DRE:SendChallengeWhisper('Alice Jones', 100, 0) and lastNotice:find('not sent'))
            C_ChatInfo.RegisterAddonMessagePrefix = function() return 2 end
            DRE:EnableDuelMessages()
            assert(not DRE:SendChallengeWhisper('Alice Jones', 100, 0) and #sent == 0)
        """)

    def test_challenge_banner_and_buttons_on_reused_dialog(self):
        self.check("""
            local function invite()
                receiveOffer(20000, 'fixed')
                local window = assert(DRE.dialogWindow)
                assert(window.frame:IsShown() and window.inviteBanner:IsShown())
                assert(window.message:GetText():find('Alice Jones challenges you', 1, true))
                assert(window.message:GetText():find('Fixed wager 2g', 1, true))
                return window
            end
            local function press(button)
                local control = button.control
                control:GetScript('OnClick')(control, 'LeftButton')
            end
            local window = invite()
            local banner = window.inviteBanner
            press(window.cancelButton)
            assert(not DRE.pendingChallenge and not DRE.acceptedChallenge and not window.frame:IsShown())
            assert(#sent == 0 and addonPackets[1][2]:match(':DEATHROLL_DECLINE$') and addonPackets[1][4] == 'Alice Jones')
            DRE:ShowDialog('DEATHROLL_RESET_CONFIRM')
            assert(not banner:IsShown())
            press(window.cancelButton)
            assert(invite() == window and window.inviteBanner == banner)
            press(window.acceptButton)
            assert(not window.frame:IsShown() and DRE.acceptedChallenge.sender == 'Alice Jones')
            assert(#sent == 0 and addonPackets[2][2]:match(':DEATHROLL_ACCEPT$') and addonPackets[2][4] == 'Alice Jones')
            roll('Alice Jones', 48, 100)
            action()
            assert(DRE.gameState.currentRoll == 48 and DRE.gameState.isActive)
        """)

    def test_solo_challenge_preview_from_command_and_settings(self):
        self.check("""
            local function findButton(widget)
                if widget.type == 'DRETableButton' and widget:GetText() == 'Test Challenge Popup' then return widget end
                for _, child in ipairs(widget.children or {}) do
                    local found = findButton(child)
                    if found then return found end
                end
            end
            local function press(button)
                button.control:GetScript('OnClick')(button.control, 'LeftButton')
            end
            DRE.Print = function(_, text) lastPrint = text end
            DRE.db.profile.challengeSystem.enabled = false
            DRE:SelectMainSection('settings')
            press(assert(findButton(DRE.UI.tabGroup)))
            local window = DRE.dialogWindow
            assert(window.inviteBanner:IsShown() and window.message:GetText():find('(preview)', 1, true))
            assert(window.message:GetText():find('final gold trade') and not DRE.pendingChallenge)
            press(window.acceptButton)
            assert(lastPrint == 'Challenge preview accepted.' and not window.frame:IsShown())
            assert(DRE.UI.currentTab == 'deathroll' and DRE.UI.mainWindow.frame:IsShown())
            DRE.UI.mainWindow:Hide()
            DRE:SlashCommand('testpopup')
            press(window.acceptButton)
            assert(DRE.UI.currentTab == 'deathroll' and DRE.UI.mainWindow.frame:IsShown())
            DRE.db.profile.challengeSystem.trackWagerByTrade = false
            DRE.UI.mainWindow:Hide()
            DRE:SlashCommand('testpopup')
            assert(not window.message:GetText():find('final gold trade'))
            press(window.cancelButton)
            assert(lastPrint == 'Challenge preview declined.' and not window.frame:IsShown())
            assert(not DRE.UI.mainWindow.frame:IsShown())
            assert(not DRE.pendingChallenge and not DRE.acceptedChallenge and not DRE:HasActiveGame())
            assert(#sent == 0 and not next(DRE.db.profile.history))
        """)

    def test_real_invite_supersedes_solo_preview(self):
        self.check("""
            DRE:SlashCommand('testpopup')
            local expire = timers[#timers].callback
            local staleAccept = DRE.dialogWindow.acceptButton.callbacks.OnClick
            receiveOffer(20000, 'fixed')
            local real = assert(DRE.pendingChallenge)
            local other = string.rep('b',22) .. ':Beth Dawn:DEATHROLL_CHALLENGE:100:90000:fixed'
            fire('CHAT_MSG_ADDON','DREInvite2',other,'WHISPER','Beth Dawn')
            assert(DRE.pendingChallenge == real and real.wager == 20000)
            DRE:SlashCommand('testpopup')
            expire()
            staleAccept()
            assert(DRE.activeDialog.data == real and DRE.pendingChallenge == real and #sent == 0)
            click(DRE.dialogWindow.acceptButton)
            assert(DRE.acceptedChallenge == real and #sent == 0 and #addonPackets == 1)
            assert(addonPackets[1][2]:match(':DEATHROLL_ACCEPT$') and addonPackets[1][4] == 'Alice Jones')
        """)

    def test_invite_flex_uses_the_current_challenger(self):
        self.check("""
            DRE:SlashCommand('testpopup')
            local banner = DRE.dialogWindow.inviteBanner
            local model = assert(banner.model)
            assert(model.bound == 'player' and banner.name == 'Me Smith')
            model:GetScript('OnModelLoaded')()
            assert(model.sequences[1] == 82 and not banner.portrait:IsShown())
            local stale = model:GetScript('OnModelLoaded')
            units.target = {'Alice', 'Smith'}
            receiveOffer(20000, 'fixed')
            stale()
            assert(banner.standIn and model.alpha == 0 and banner.portrait:IsShown() and not banner.unit)
            banner:GetScript('OnEvent')(banner, 'NAME_PLATE_UNIT_ADDED', 'nameplate9')
            assert(not banner.unit)
            units.nameplate9 = {'Alice', 'Jones'}
            banner:GetScript('OnEvent')(banner, 'UNIT_NAME_UPDATE', 'nameplate9')
            assert(model.bound == 'nameplate9')
            missingSequence = 82
            model:GetScript('OnModelLoaded')()
            assert(model.sequences[#model.sequences] == 68)
            units.party2 = units.nameplate9
            banner:GetScript('OnEvent')(banner, 'NAME_PLATE_UNIT_REMOVED', 'nameplate9')
            assert(model.bound == 'party2')
            stale = model:GetScript('OnModelLoaded')
            click(DRE.dialogWindow.cancelButton)
            stale()
            assert(not model.bound and not model:IsShown() and not banner.challenger)
        """)

    def test_active_opponent_survives_retarget_and_recycled_nameplate(self):
        self.check("""
            action()
            local model = models[2]
            local frame = model.parent.parent
            local function event(name, unit) frame:GetScript('OnEvent')(frame, name, unit) end
            units.party3 = units.target
            units.target = {'Alice', 'Smith'}
            event('PLAYER_TARGET_CHANGED')
            assert(model.bound == 'party3')
            units.party3 = nil
            event('GROUP_ROSTER_UPDATE')
            event('NAME_PLATE_UNIT_ADDED', 'nameplate7')
            assert(not model.bound)
            units.nameplate7 = {'Alice', 'Jones'}
            event('UNIT_NAME_UPDATE', 'nameplate7')
            assert(model.bound == 'nameplate7')
            event('NAME_PLATE_UNIT_REMOVED', 'nameplate7')
            assert(not model.bound)
        """)

    def test_legacy_replies_and_invitations_leave_dev_state_untouched(self):
        self.check("""
            local notices = 0
            DRE.Print = function() notices = notices + 1 end
            fire('CHAT_MSG_WHISPER', 'DEATHROLL_CHALLENGE:100:0:2.4.2', 'Alice Jones')
            fire('CHAT_MSG_WHISPER', 'DEATHROLL_ACCEPT', 'Alice Jones')
            fire('CHAT_MSG_WHISPER', 'DEATHROLL_DECLINE', 'Alice Jones')
            fire('CHAT_MSG_ADDON', 'DREInvite1', string.rep('b',22) .. ':Alice Jones:DEATHROLL_CHALLENGE:100:0:2.4.2:wait', 'WHISPER', 'Alice Jones')
            receiveOffer(0, 'unknown')
            receiveOffer(20, 'trade')
            assert(not DRE.activeDialog and not DRE.pendingChallenge and notices == 0 and #addonPackets == 0)
        """)

    def test_invitations_preserve_confirmations_and_cached_rolls(self):
        self.check("""
            for _, combat in ipairs({false, true}) do
                InCombatLockdown = function() return combat end
                for _, key in ipairs({'DEATHROLL_RESET_CONFIRM', 'DEATHROLL_DELETE_GAME_CONFIRM'}) do
                    local dialog = DRE:ShowDialog(key, nil, nil, 1)
                    DRE:StoreRecentRoll('Alice Jones', 23, 100)
                    local cached = DRE:FindRecentTargetRoll('Alice Jones')
                    assert(cached)
                    receiveOffer(0, 'trade')
                    assert(DRE.activeDialog == dialog and not DRE.pendingChallenge)
                    assert(DRE:FindRecentTargetRoll('Alice Jones') == cached)
                    DRE:CloseDialog(dialog, false, 'override')
                end
            end
        """)

    def test_fixed_wagers_round_trip_from_zero_to_the_maximum(self):
        for amount in (0, 2147483647, 2147483648, 9999999999):
            with self.subTest(amount=amount):
                other = ForeverDuelTests()
                other.setUp()
                other.check("units.player = {'Alice', 'Jones'}")
                self.lua.globals().amount = amount
                self.check("""
                    DRE.db.profile.challengeSystem.sendWhisper = true
                    assert(DRE:InviteToDuel('Alice Jones', 100, amount, false))
                """)
                packet = self.lua.eval('table.remove(addonPackets, 1)')
                self.assertTrue(packet[2].endswith(f':100:{amount}:fixed'))
                other.lua.globals().fire('CHAT_MSG_ADDON', packet[1], packet[2], packet[3], 'Me Smith')
                other.lua.globals().amount = amount
                other.check("""
                    assert(DRE.pendingChallenge.wager == amount and DRE.pendingChallenge.trackTrade == false)
                    assert(DRE.dialogWindow.message.text:find('Fixed wager ' .. DRE:FormatGold(amount), 1, true))
                    DRE:SlashCommand('accept')
                    DRE:SetTradeWagerModeEnabled(false)
                    DRE:SetTradeWagerModeEnabled(true)
                    roll('Me Smith', 1, 100)
                    action()
                    assert(DRE.UI.duelResult.wager == amount and #(DRE.db.profile.pendingTradeWagers or {}) == 0)
                """)
                self.check("DRE:WithdrawDuelInvite(); addonPackets = {}")
        self.check("assert(not DRE:InviteToDuel('Alice Jones', 100, 10000000000, false) and #addonPackets == 0)")

    def test_change_wager_setting_refreshes_open_duel_and_preserves_draft(self):
        self.check("""
            assert(widgets().tradeWager and not DRE.UI.goldEdit)
            DRE:SetTradeWagerModeEnabled(false)
            assert(not widgets().tradeWager and DRE.UI.goldEdit)
            DRE.UI.goldEdit:SetText('17')
            DRE.UI.rollEdit:SetText('351')
            DRE:SetTradeWagerModeEnabled(true)
            assert(not DRE.UI.goldEdit and widgets().detail.text == 'Wager from trade')
            DRE:SetTradeWagerModeEnabled(false)
            assert(DRE.UI.goldEdit:GetText() == '17' and DRE.UI.rollEdit:GetText() == '351')
        """)

    def test_trade_mode_invite_and_unrelated_older_opener(self):
        self.check("""
            roll('Alice Jones',1,100)
            clock = clock + 45
            receiveOffer(0, 'trade')
            assert(DRE.dialogWindow.message.text:find('final gold trade'))
            click(DRE.dialogWindow.acceptButton)
            assert(widgets().action.disabled and widgets().detail.text:find('Wager from trade'))
            local old = DRE:FindRecentTargetRoll('Alice Jones')
            assert(not DRE:AcceptObservedChallenge(old))
            roll('Alice Jones',12,50)
            assert(widgets().action.disabled)
            roll('Alice Jones',39,100)
            assert(not widgets().action.disabled)
            action()
            assert(DRE.gameState.currentRoll == 39 and DRE.gameState.trackWagerByTrade)
            roll('Me Smith',1,39)
            assert(payment() == 'Awaiting payment')
        """)

    def test_other_duel_payment_cannot_overwrite_current_result(self):
        self.check("""
            finish(true)
            local oldId = DRE.UI.duelResult.gameId
            action()
            units.target = {'Alice','Smith'}
            fire('PLAYER_TARGET_CHANGED')
            action()
            roll('Me Smith',1,100)
            local currentId = DRE.UI.duelResult.gameId
            assert(currentId ~= oldId)
            fire('TRADE_SHOW')
            theirs = 150000
            fire('TRADE_MONEY_CHANGED')
            success()
            local _, _, oldRecord = DRE:FindGameRecordById(oldId)
            assert(oldRecord.goldAmount == 150000)
            assert(DRE.UI.duelResult.gameId == currentId and payment() == 'Awaiting payment')
        """)

    def test_invalid_range_and_navigation_during_an_active_game(self):
        self.check("""
            action()
            roll('Me Smith',20,100)
            DRE:GroupCommand('')
            assert(DRE.UI.currentTab == 'group' and not DRE.UI.duelPane)
            for _, tab in ipairs({'statistics', 'settings', 'history'}) do
                DRE:SelectMainSection(tab)
                assert(DRE.UI.currentTab == tab)
            end
            DRE:ShowMainWindow()
            roll('Alice Jones',3,99)
            assert(widgets().action.disabled and widgets().log.text:find('expected 1%-20'))
            roll('Alice Jones',3,20)
            assert(not widgets().action.disabled and widgets().action:GetText():find('3'))
            action()
            local pending = DRE.gameState.pendingRoll
            widgets().action.callbacks.OnClick()
            assert(DRE.gameState.pendingRoll == pending)
            roll('Me Smith',1,3)
            assert(payment() == 'Awaiting payment')
        """)

    def test_ambiguous_payment_before_first_open_after_reload(self):
        self.check("""
            finish(true)
            DRE:SelectMainSection('history')
            DRE.UI.duelRestored, DRE.UI.duelResult = nil, nil
            fire('TRADE_SHOW')
            mine, theirs = 150000, 100000
            fire('TRADE_MONEY_CHANGED')
            success()
            DRE:ShowMainWindow()
            assert(payment() == 'Review payment')
            assert(DRE.db.profile.goldTracking.totalWon == 0)
        """)

    def test_group_round_owns_its_rolls_from_duel_page(self):
        self.check(r"""
            assert(DRE:StartGroupRound('Me Smith\nAlice Jones\nBob Jones',100,'SAY'))
            assert(widgets().phase == 'group')
            action()
            assert(DRE.UI.currentTab == 'group')
            DRE:ShowMainWindow()
            roll('Me Smith',10,100)
            assert(widgets().phase == 'group' and not DRE.gameState)
            DRE:CancelGroupRound()
            assert(widgets().phase == 'setup' and not next(DRE.db.profile.history))
        """)
