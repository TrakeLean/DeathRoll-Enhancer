"""Forever Statistics, entered through the main window."""
import unittest

from test_addon import runtime


class ForeverStatsTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime("""
            GetAddOnMetadata = function(_, key) if key == 'X-DRE-DuelUI' then return '1' end end
            local stub = LibStub
            local config = {RegisterOptionsTable=function(_, _, options) configStats = options.args.statistics end}
            LibStub = function(name, ...)
                if name == 'AceConfig-3.0' then return config end
                return stub(name, ...)
            end
        """)
        self.lua.execute("""
            function findWidget(widget, kind, choice)
                if widget.kind == kind and (not choice or widget.list[choice]) then return widget end
                for _, child in ipairs(widget.children) do
                    local match = findWidget(child, kind, choice)
                    if match then return match end
                end
            end
            function modePicker() return findWidget(DRE.UI.tabGroup, 'DRETableDropdown', 'all') end
            function selectMode(mode) modePicker():Fire('OnValueChanged', mode) end
            function screen(widget)
                if widget.kind == 'DREStatsPanel' then
                    return table.concat({widget.title:GetText(), widget.total:GetText(),
                        widget.labels[1]:GetText(), widget.values[1]:GetText(),
                        widget.labels[2]:GetText(), widget.values[2]:GetText()}, '\\n')
                end
                if widget.kind == 'DREFunStatRow' then
                    return table.concat({widget.caption:GetText(), widget.player:GetText(), widget.detail:GetText()}, '\\n')
                end
                local lines = {widget:GetText()}
                for _, child in ipairs(widget.children) do lines[#lines + 1] = screen(child) end
                return table.concat(lines, '\\n')
            end
            function displayed(text) return screen(DRE.UI.tabGroup):find(text, 1, true) end
            function button(widget, text)
                if widget.kind == 'DRETableButton' and widget:GetText() == text then return widget end
                for _, child in ipairs(widget.children) do
                    local found = button(child, text)
                    if found then return found end
                end
            end
            function switch(text) assert(button(DRE.UI.tabGroup, text)):Fire('OnClick') end
            function toggle(key, value)
                local info = {'statistics', key}
                assert(configStats.args[key].type == 'toggle')
                configStats.set(info, value)
                assert(configStats.get(info) == value)
            end
            DRE:SetupOptions()
            DRE:SlashCommand('')
            DRE:SelectMainSection('statistics')
        """)

    def test_empty_sparse_and_live_visibility_preferences(self):
        self.lua.execute("""
            assert(displayed('No games recorded') and not displayed('0.0%'))
            assert(displayed('Net gold\\n0g\\nWon\\n0g\\nLost\\n0g') and displayed('Current streak\\nNone'))
            assert(displayed('Enable Fun Statistics in Settings'))
            toggle('showLikelyCheater', true)
            assert(not configStats.args.showLuckyPlayer and not configStats.args.showUnluckyPlayer)
            assert(configStats.args.showLikelyCheater.name == 'Wrong-range Rolls')
            DRE:SlashCommand('setsuspicious "Alice Jones" 2')
            assert(not displayed('Alice Jones') and displayed('No games recorded'))
            DRE:SelectMainSection('history')
            local ledger = DRE.UI.historyDropdown
            assert(ledger:GetValue() == 'Alice Jones' and ledger.wrongRanges:GetText() == 'Wrong-range rolls: 2')
            toggle('showLikelyCheater', false)
            assert(not ledger:GetValue() and ledger.wrongRanges:GetText() == '')
            DRE:SelectMainSection('statistics')
            assert(not displayed('Alice Jones') and displayed('Enable Fun Statistics in Settings'))
        """)

    def test_finished_cancelled_and_restarted_hosted_rounds(self):
        self.lua.execute(r"""
            switch('Group')
            local roster = 'Me\nAlice\nBob'
            local function roll(name, n, cap)
                DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM', string.format('%s rolls %d (1-%d)',name,n,cap))
            end
            assert(DRE:StartGroupRound(roster, 2, 'SAY'))
            roll('Me', 2, 2)
            DRE:SlashCommand('group cancel')
            roll('Alice', 1, 2)
            assert(not DRE:GetHostedGroupStats() and displayed('0 rounds') and displayed('0 times'))
            assert(DRE:RestartGroupRound())
            roll('Me', 2, 2)
            roll('Alice', 2, 2)
            roll('Bob', 2, 2)
            roll('Me', 1, 2)
            local stats = DRE:GetHostedGroupStats()
            assert(stats.played == 1 and stats.losses == 1 and stats.escapes == 1)
            assert(stats.longest.rolls == 4 and stats.longest.opening == 2 and stats.longest.seats == 3)
            assert(displayed('My group record\n1 round\nWon or survived\n0\nLost\n1') and displayed('4 rolls'))
            assert(displayed('Alice\n1 round · 0 losses') and displayed('Me\n1 round · 1 loss'))
            assert(not DRE:HandleGroupRoll('Me', 1, 2) and stats.played == 1)
            assert(DRE:StartGroupRound('alice\nME',100,'SAY'))
            roll('Alice',1,100)
            assert(stats.played == 2 and stats.losses == 1 and stats.regulars.alice.played == 2)
            assert(DRE:StartGroupRound('Alice\nBob',100,'SAY'))
            roll('Alice',1,100)
            assert(stats.played == 2 and stats.regulars.alice.played == 3 and stats.regulars.alice.losses == 2)
            assert(DRE:StartGroupRound(roster,2,'SAY'))
            for i=1,2 do roll('Me',2,2);roll('Alice',2,2);roll('Bob',2,2) end
            DRE:CancelGroupRound()
            assert(stats.longest.rolls == 4 and stats.escapes == 1 and stats.regulars.alice.played == 3)
            assert(not next(DRE.db.profile.history) and not next(DRE.db.profile.pendingTradeWagers or {}))
            assert(DRE:ExportData():find('hostedGroupStats', 1, true))
            switch('1v1')
            assert(displayed('No games recorded') and not displayed('Closest calls'))
            switch('Group')
            toggle('showGroupLongest', false)
            assert(not displayed('Longest round') and displayed('My group record'))
            local old = playerGUID
            playerGUID = 'Player-2'
            DRE:UpdateStatsDisplay()
            assert(not DRE:GetHostedGroupStats() and displayed('0 rounds'))
            playerGUID = old
            DRE:ResetAllData()
            assert(not DRE:GetHostedGroupStats() and displayed('0 rounds'))
        """)

    def test_closest_rival_displays_the_head_to_head_record(self):
        self.lua.execute("""
            DRE.db.profile.history.Alice = {wins=3, losses=2, recentGames={}}
            toggle('showFrenemy', true)
            assert(configStats.args.showFrenemy.name == 'Closest Rival')
            assert(displayed('Closest Rival\\nAlice\\n3 wins · 2 losses'))
        """)

    def test_in_addon_settings_control_the_same_group_preferences(self):
        self.lua.execute("""
            local controls = {}
            local create = DRE.CreateWindowWidget
            function DRE:CreateWindowWidget(kind)
                local widget = create(self, kind)
                if kind == 'CheckBox' then
                    local label = widget.SetLabel
                    function widget:SetLabel(text) label(self, text); controls[text] = self end
                end
                return widget
            end
            DRE:SelectMainSection('settings')
            assert(controls['Closest Rival'] and controls['Wrong-range Rolls'])
            assert(not controls['Frenemy'] and not controls['Lucky Player'] and not controls['Most Likely to Cheat'])
            for _, option in ipairs(DRE.groupStatOptions) do
                local widget = assert(controls[option.label])
                assert(widget:GetValue())
                widget.frame:GetScript('OnClick')(widget.frame)
                assert(configStats.get({'statistics', option.key}) == false)
            end
            DRE:SelectMainSection('statistics')
            switch('Group')
            assert(displayed('Enable Group statistics in Settings.'))
            toggle('showGroupEscapes', true)
            assert(displayed('You survived /roll 2 0 times.') and not displayed('My group record'))
        """)

    def test_regulars_pages_include_unrolled_seats_and_survive_reopening(self):
        self.lua.execute(r"""
            local names = {'Me'}
            for i = 1, 39 do names[#names + 1] = 'Player ' .. string.char(65 + math.floor(i / 26), 65 + i % 26) end
            assert(DRE:StartGroupRound(table.concat(names, '\n'), 100, 'SAY'))
            DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM', 'Me rolls 1 (1-100)')
            switch('Group')
            assert(displayed('40') and displayed('#1\nMe\n1 round · 1 loss'))
            for page = 2, 5 do switch('Next') end
            assert(displayed('#40\n' .. names[40] .. '\n1 round · 0 losses'))
            assert(button(DRE.UI.tabGroup, 'Next').disabled)
            DRE:SelectMainSection('group')
            DRE:SelectMainSection('statistics')
            assert(displayed('#40') and not displayed('Net gold'))
        """)

    def test_category_selection_survives_results_edits_and_tab_switches(self):
        self.lua.execute("""
            local name = 'Élodie Longsurname-OtherRealm'
            toggle('showMostPlayedWith', true)
            toggle('showBiggestLoss', true)
            findWidget(DRE.UI.tabGroup, 'DRETableDropdown', 2):Fire('OnValueChanged', 2)
            DRE:AddGameToHistory(name, 'Lost', 12345, 100)
            assert(displayed('0.0%') and displayed('-1g 23s 45c'))
            assert(displayed('Current streak\\n1 loss') and displayed('Biggest Single Loss\\n'..name..'\\n1g 23s 45c'))
            local game = DRE.db.profile.history[name].recentGames[1]
            assert(DRE:EditGameRecordById(game.id, 'Won', 20000, 100))
            assert(displayed('100.0%') and displayed('Won\\n2g\\nLost\\n0g') and displayed('Current streak\\n1 win'))
            assert(not displayed(name) and displayed('Awaiting qualifying data'))
            DRE:SelectMainSection('deathroll')
            DRE:SelectMainSection('statistics')
            assert(findWidget(DRE.UI.tabGroup, 'DRETableDropdown', 2):GetValue() == 2)
            toggle('showBiggestLoss', false)
            assert(not findWidget(DRE.UI.tabGroup, 'DRETableDropdown', 2) and displayed(name))
            assert(DRE:DeleteGameRecordById(game.id))
            assert(displayed('No games recorded') and not displayed(name))
        """)

    def test_duel_mode_filter_uses_tagged_history_and_updated_results(self):
        self.lua.execute(r"""
            assert(modePicker():GetValue() == 'all' and modePicker().list.cursed7 and not modePicker().list.teams)
            DRE:AddGameToHistory('Alice','Won',0,100) -- untagged
            local function add(mode, result, details)
                details.mode = mode
                return DRE:AddGameToHistory('Alice', result, 10000, 100, details)
            end
            add('twoLives','Won',{score={player=2,opponent=0}}) -- backfill final score
            add('twoLives','Won',{score={player=1,opponent=0}, firstLifeLost='player'})
            add('highRoller','Lost',{score={player=1,opponent=2}})
            add('highRoller','Won',{score={player=2,opponent=0}, tiebreaks=2, tiebreakWins=1})
            add('cursed7','Lost',{lastFace=1})
            local _, id = add('cursed7','Lost',{lastFace=7, offeredDouble=true})
            add('cursed7','Won',{lastFace=7, offeredDouble=true})
            assert(displayed('Win rate · 8 games') and displayed('Double or Nothing · break-even rate\n50.0%'))
            selectMode('classic')
            assert(displayed('No games recorded'))
            selectMode('twoLives')
            assert(displayed('Flawless wins\n1\nComeback wins\n1') and displayed('Win rate · 2 games'))
            selectMode('highRoller')
            assert(displayed('Points won\n3\nTiebreak points won / contested\n1 / 2'))
            selectMode('cursed7')
            assert(displayed('Rolled a 1\n1\nRolled a 7\n1'))
            assert(DRE:EditGameRecordById(id, 'Won', 10000, 100))
            assert(displayed('Rolled a 1\n1\nRolled a 7\n0') and displayed('Your completed offers\n1'))
            switch('Group')
            assert(modePicker():GetValue() == 'all' and modePicker().list.teams and not modePicker().list.cursed7)
            selectMode('highRoller')
            switch('1v1')
            assert(modePicker():GetValue() == 'cursed7')
            assert(DRE:DeleteGameRecordById(id) and displayed('Win rate · 2 games'))
        """)

    def test_group_modes_count_personal_points_ties_lives_and_survival(self):
        self.lua.execute(r"""
            switch('Group')
            local function start(mode, names)
                assert(DRE:StartGroupRound(names or 'Me\nAlice', 10, 'NONE', mode))
            end
            local function rolls(...)
                for _, value in ipairs({...}) do
                    local r = DRE.groupRound
                    assert(DRE:HandleGroupRoll(r.players[r.turn], value, r.currentRoll))
                end
            end
            -- A combined record from an earlier build has no attributable mode.
            DRE.db.profile.hostedGroupStats = {[playerGUID]={played=5,losses=2,escapes=0,regulars={}}}
            selectMode('classic')
            start('classic'); rolls(3,1)
            assert(displayed('Survival rate · 1 game\n100.0%'))
            selectMode('hotPotato')
            start('hotPotato'); rolls(1)
            assert(displayed('Survival rate · 1 game\n0.0%'))
            selectMode('twoLives')
            start('twoLives'); rolls(1,1,8,1)
            start('twoLives'); rolls(8,1,10,1)
            assert(displayed('Flawless wins\n1\nComeback wins\n1'))
            selectMode('highRoller')
            start('highRoller', 'Me\nAlice\nBob')
            rolls(9,9,9, 1,8,8, 2,1) -- host drops out of a repeated tiebreak
            rolls(7,7,1, 4,4, 9,2)   -- host wins one contested point
            rolls(10,5,3)
            assert(displayed('Points won\n2\nTiebreak points won / contested\n1 / 2'))
            start('highRoller'); rolls(5,5,9,2)
            assert(DRE:CancelGroupRound(true))
            start('highRoller','Alice\nBob'); rolls(10,1,10,1)
            assert(displayed('Win rate · 1 game') and displayed('Tiebreak points won / contested\n1 / 2'))
            selectMode('all')
            assert(displayed('My group record\n10 rounds'))
        """)

    def test_text_formatter_keeps_the_same_player_and_result(self):
        self.lua.execute("""
            local data = {player='Alice Jones', count=1, amount=10203}
            assert(DRE:FormatFunStat('mostWinsAgainst', data) == 'Most Wins Against: Alice Jones (1 win)')
            assert(DRE:FormatFunStat('biggestWin', data) == 'Biggest Single Win: 1g 2s 3c vs Alice Jones')
            assert(DRE:FormatFunStat('biggestLoss', data) == 'Biggest Single Loss: 1g 2s 3c to Alice Jones')
            assert(DRE:FormatFunStat('biggestLoss', {}) == nil and DRE:FormatFunStat('unknown', data) == nil)
        """)

    def test_legacy_aggregates_without_detailed_games(self):
        self.lua.execute("""
            local profile = DRE.db.profile
            profile.history = {['Alice Jones'] = {wins=4, losses=2, recentGames={}}}
            profile.goldTracking = {totalWon=20000, totalLost=30000, currentStreak=-2,
                bestWinStreak=4, worstLossStreak=-2}
            toggle('showBiggestWin', true)
            assert(displayed('6 games') and displayed('66.7%') and displayed('-1g'))
            assert(displayed('Win rate · 6 games\\n66.7%\\nWins\\n4\\nLosses\\n2'))
            assert(displayed('Net gold\\n-1g\\nWon\\n2g\\nLost\\n3g'))
            assert(displayed('Current streak\\n2 losses\\nBest\\n4 wins\\nWorst\\n2 losses'))
            assert(displayed('Awaiting qualifying data') and not displayed('Alice Jones'))
            assert(#profile.history['Alice Jones'].recentGames == 0)
        """)
