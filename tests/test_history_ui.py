"""Forever History navigation, live updates, and stable row actions."""
import unittest

from test_addon import runtime


class ForeverHistoryTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime("""
            GetAddOnMetadata = function(_, key) if key == 'X-DRE-DuelUI' then return '1' end end
        """)
        self.lua.execute("""
            regionalNames = true
            units.target = {'Alice', 'Jones'}
            function history() return DRE.UI.historyDropdown end
            function click(button) button:GetScript('OnClick')(button) end
            function editorFields(id)
                DRE:ShowEditGameDialog(id)
                local fields = {}
                local function visit(widget)
                    if widget.kind == 'DRETableInput' then table.insert(fields, widget) end
                    if widget.kind == 'DRETableDropdown' and (widget:GetValue() == 'win' or widget:GetValue() == 'lost') then
                        fields.result = widget
                    end
                    if widget.kind == 'DRETableButton' and widget:GetText() == 'Save Changes' then fields.save = widget end
                    for _, child in ipairs(widget.children) do visit(child) end
                end
                visit(DRE.editGameFrame)
                assert(fields.save and #fields == 5)
                return fields
            end
            function pendingDuel(outcome)
                local _, id = DRE:AddGameToHistory('Alice Jones', outcome, 0, 100)
                DRE.db.profile.pendingTradeWagers = {{ownerGUID=playerGUID,gameId=id, playerName='Alice Jones', recordedAt=now, result=outcome}}
                DRE:RememberDuelResult(id, 'Alice Jones', outcome, 0, now, true)
                return id
            end
            function settleTrade(mine, theirs)
                units.NPC = units.target
                GetPlayerTradeMoney = function() return mine end
                GetTargetTradeMoney = function() return theirs end
                DRE:TRADE_SHOW()
                DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE', 1, 1)
                DRE:TRADE_CLOSED()
                DRE:UI_INFO_MESSAGE('UI_INFO_MESSAGE', 123, ERR_TRADE_COMPLETE)
            end
            function search(text)
                local box = history().search
                box:SetText(text)
                box:GetScript('OnTextChanged')(box, true)
            end
            DRE:SlashCommand('')
            DRE:SelectMainSection('history')
        """)

    def test_search_full_names_broadcast_and_reopen(self):
        self.lua.execute("""
            local pane = history()
            assert(pane and pane.empty:GetText():find('first') and pane.send.disabled)
            DRE:AddGameToHistory('Alice Jones', 'WIN', 10203, 100)
            DRE:AddGameToHistory('Alice Smith', 'Lost', 0, 100)
            assert(pane:GetValue() == 'Alice Jones' and pane.duels.rows[1].label:GetText():find('Won'))
            assert(pane.duels.rows[1].amount:GetText() == '1g 2s 3c')
            assert(pane.duels.rows[1].when:GetText() == date('%Y-%m-%d %H:%M'))
            search('sMiTh')
            assert(#pane.matches == 1 and pane:GetValue() == 'Alice Smith')
            assert(pane.duels.rows[1].amount:GetText() == '0g' and not pane.send.disabled)
            DRE.UI.statsBroadcastChannelDropdown:SetValue('yell')
            pane.send:Fire('OnClick')
            assert(#sent == 1 and sent[1][2] == 'YELL' and sent[1][1]:find('Alice Smith', 1, true))
            search('%[')
            assert(not pane:GetValue() and pane.send.disabled and pane.empty:GetText():find('match'))
            pane.search:GetScript('OnEscapePressed')()
            assert(#pane.matches == 2 and pane:GetValue() == 'Alice Jones')
            click(pane.roster.rows[2])
            DRE:SelectMainSection('deathroll')
            DRE:SelectMainSection('history')
            assert(history():GetValue() == 'Alice Smith')
            DRE:HistoryCommand('')
            assert(history():GetValue() == 'Alice Jones')
            DRE:SlashCommand('merge "Alice Jones" "Alice Stone"')
            assert(history():GetValue() == 'Alice Stone')
        """)

    def test_sharing_stats_to_party_in_a_raid_uses_only_party_chat(self):
        self.lua.execute("""
            LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
            local home, instance, raid = true, false, true
            IsInRaid = function() return raid end
            IsInGroup = function(category)
                if category == LE_PARTY_CATEGORY_HOME then return home end
                if category == LE_PARTY_CATEGORY_INSTANCE then return instance end
                return home or instance
            end
            -- Model one other player in our subgroup and one elsewhere in the raid.
            local partyInbox, otherSubgroupInbox = {}, {}
            C_ChatInfo = {SendChatMessage = function(message, channel)
                SendChatMessage(message, channel)
                if channel == 'PARTY' or channel == 'RAID' then table.insert(partyInbox, message) end
                if channel == 'RAID' then table.insert(otherSubgroupInbox, message) end
            end}
            DRE.Print = function(_, message) notice = message end
            DRE:AddGameToHistory('Alice Jones', 'Won', 150000, 100)
            DRE.UI.statsBroadcastChannelDropdown:SetValue('party')
            history().send:Fire('OnClick')
            assert(#sent == 1 and sent[1][2] == 'PARTY', 'Party selection sent to ' .. tostring(sent[1] and sent[1][2]))
            assert(sent[1][1]:find('Alice Jones', 1, true) and notice:find('to party.', 1, true))
            assert(partyInbox[1] == sent[1][1] and #otherSubgroupInbox == 0)

            instance = true -- both home and instance groups exist
            DRE:SlashCommand('sendstats Alice Jones p')
            assert(#sent == 2 and sent[2][2] == 'PARTY')
            assert(#partyInbox == 2 and #otherSubgroupInbox == 0)
            home = false -- only instance chat is available now
            history().send:Fire('OnClick')
            assert(#sent == 2 and notice:find('Failed to send stats', 1, true))
            raid, instance = false, false -- party disbanded after the dropdown was set
            history().send:Fire('OnClick')
            assert(#sent == 2)

            home, raid = true, true
            DRE.UI.statsBroadcastChannelDropdown:SetValue('raid')
            history().send:Fire('OnClick')
            assert(#sent == 3 and sent[3][2] == 'RAID')
            assert(#partyInbox == 3 and #otherSubgroupInbox == 1)
            DRE:SlashCommand('sendstats Alice Jones')
            assert(#sent == 4 and sent[4][2] == 'RAID')
        """)

    def test_all_duels_are_browsable_and_editor_saves_by_id(self):
        self.lua.execute("""
            for i = 1, 42 do DRE:AddGameToHistory('Opponent '..i, 'Lost', 0, 100) end
            for i = 1, 35 do DRE:AddGameToHistory('Alice Jones', 'Won', 10000, 100) end
            DRE:HistoryCommand('Alice Jones')
            local pane = history()
            click(pane.roster.next)
            assert(pane.roster.page == 2 and #pane.roster.rows < #pane.names)
            local records = DRE.db.profile.history['Alice Jones'].recentGames
            local oldest = records[#records]
            local list = pane.duels
            local displayed = {}
            for page = 1, #records do
                for _, row in ipairs(list.rows) do
                    if row:IsShown() then displayed[row.gameId] = row end
                end
                if displayed[oldest.id] then break end
                click(list.next)
            end
            for _, game in ipairs(records) do assert(displayed[game.id]) end
            assert(#list.rows < #records)
            click(displayed[oldest.id])
            local editor = assert(DRE.editGameFrame)
            local editBoxes, save = {}, nil
            local function visit(widget)
                if widget.kind == 'DRETableInput' then table.insert(editBoxes, widget) end
                if widget.kind == 'DRETableButton' and widget:GetText() == 'Save Changes' then save = widget end
                for _, child in ipairs(widget.children) do visit(child) end
            end
            visit(editor)
            assert(save and #editBoxes == 5)
            local page = list.page
            local _, newId = DRE:AddGameToHistory('Alice Jones', 'Lost', 0, 200)
            editBoxes[2]:SetText('9')
            save:Fire('OnClick')
            assert(oldest.goldAmount == 90000 and records[1].id == newId and records[1].goldAmount == 0)
            assert(list.page == page)
            assert(DRE:DeleteGameRecordById(oldest.id))
            assert(not DRE:FindGameRecordById(oldest.id))
        """)

    def test_trade_refresh_uses_only_the_recorded_wager(self):
        self.lua.execute("""
            local pane = history()
            DRE:AddGameToHistory('Alice Jones', 'Won', 50000, 100)
            local _, id = DRE:AddGameToHistory('Alice Jones', 'Won', 0, 100)
            DRE.db.profile.pendingTradeWagers = {{ownerGUID=playerGUID,gameId=id, playerName='Alice Jones', recordedAt=now, result='Won'}}
            units.NPC = units.target
            GetTargetTradeMoney = function() return 50000 end
            DRE:TRADE_SHOW()
            DRE:TRADE_ACCEPT_UPDATE('TRADE_ACCEPT_UPDATE', 1, 1)
            assert(pane.duels.rows[1].amount:GetText() == '0g')
            DRE:TRADE_CLOSED()
            DRE:UI_INFO_MESSAGE('UI_INFO_MESSAGE', 123, ERR_TRADE_COMPLETE)
            local settled, fixed = pane.duels.rows[1], pane.duels.rows[2]
            assert(settled.gameId == id and settled.amount:GetText() == '5g')
            assert(fixed.amount:GetText() == '5g' and fixed.tip:find('Recorded wager: 5g', 1, true))
            assert(#DRE.db.profile.pendingTradeWagers == 0)
        """)

    def test_legacy_totals_and_final_deletion(self):
        self.lua.execute("""
            local pane = history()
            local _, id = DRE:AddGameToHistory('Alice Jones', 'Won', 0, 100)
            assert(DRE:DeleteGameRecordById(id))
            assert(not pane:GetValue() and pane.send.disabled)
            DRE.db.profile.history.Ancestor = {goldWon = '5300', recentGames = {}}
            DRE:UpdateStatsDisplay()
            DRE:HistoryCommand('Ancestor')
            assert(pane:GetValue() == 'Ancestor' and pane.gold:GetText():find('53s'))
            assert(pane.empty:GetText():find('lifetime') and not pane.totals:GetText():find('%%'))
            assert(DRE.db.profile.history.Ancestor.goldWon == '5300')
        """)

    def test_trade_settles_with_editor_open_in_both_directions(self):
        self.lua.execute("""
            for _, outcome in ipairs({'Won', 'Lost'}) do
                local id = pendingDuel(outcome)
                local fields = editorFields(id)
                fields[5]:SetText('200')
                local won = outcome == 'Won'
                settleTrade(won and 0 or 150000, won and 150000 or 0)
                fields.save:Fire('OnClick')
                local _, _, game = DRE:FindGameRecordById(id)
                assert(game.goldAmount == 150000 and game.initialRoll == 200 and game.result == outcome)
                assert(DRE.UI.duelResult.paid == 150000 and #DRE.db.profile.pendingTradeWagers == 0)
            end
            local totals = DRE.db.profile.goldTracking
            assert(totals.totalWon == 150000 and totals.totalLost == 150000)
        """)

    def test_edit_before_trade_preserves_pending_payment(self):
        self.lua.execute("""
            local id = pendingDuel('Won')
            local fields = editorFields(id)
            fields[5]:SetText('200')
            fields.save:Fire('OnClick')
            assert(#DRE.db.profile.pendingTradeWagers == 1 and DRE.UI.duelResult.tracked)
            fields = editorFields(id)
            fields.result:SetValue('lost')
            fields.save:Fire('OnClick')
            assert(DRE.db.profile.pendingTradeWagers[1].result == 'Lost' and DRE.UI.duelResult.tracked)
            settleTrade(150000, 0)
            local _, _, game = DRE:FindGameRecordById(id)
            assert(game.goldAmount == 150000 and game.initialRoll == 200 and game.result == 'Lost')
            assert(DRE.UI.duelResult.paid == 150000 and #DRE.db.profile.pendingTradeWagers == 0)
        """)

    def test_conflicting_gold_edit_requires_review(self):
        self.lua.execute("""
            local id = pendingDuel('Won')
            local fields = editorFields(id)
            fields[2]:SetText('2')
            fields[5]:SetText('200')
            settleTrade(0, 150000)
            DRE.Print = function(_, text) notice = text end
            fields.save:Fire('OnClick')
            local _, _, game = DRE:FindGameRecordById(id)
            assert(notice:find('Reopen') and game.goldAmount == 150000 and game.initialRoll == 100)
            assert(DRE.UI.duelResult.paid == 150000 and DRE.db.profile.goldTracking.totalWon == 150000)
            fields = editorFields(id)
            fields[2]:SetText('12')
            fields.save:Fire('OnClick')
            assert(game.goldAmount == 120000 and DRE.db.profile.goldTracking.totalWon == 120000)
        """)

    def test_saving_legacy_outcomes_preserves_wins_losses_and_gold(self):
        self.lua.execute("""
            for _, result in ipairs({'WIN', 'LOSS', 'Won', 'Lost'}) do
                local won = result == 'WIN' or result == 'Won'
                local _, id = DRE:AddGameToHistory('Alice Jones', result, 50000, 100)
                local _, _, game = DRE:FindGameRecordById(id)
                game.result = result
                local fields = editorFields(id)
                assert(fields.result:GetValue() == (won and 'win' or 'lost'))
                fields.save:Fire('OnClick')
                assert(game.result == (won and 'Won' or 'Lost') and game.goldAmount == 50000)
            end
            local player = DRE.db.profile.history['Alice Jones']
            assert(player.wins == 2 and player.losses == 2 and player.goldWon == 100000 and player.goldLost == 100000)
            assert(DRE.db.profile.goldTracking.totalWon == 100000 and DRE.db.profile.goldTracking.totalLost == 100000)
        """)
