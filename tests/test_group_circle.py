"""Forever Group tab controls, character bindings and turn geometry."""
import unittest

from test_addon import runtime


class GroupCircleTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime("""
            GetAddOnMetadata = function(_, key) if key == 'X-DRE-DuelUI' then return '1' end end
            local stub = LibStub
            LibStub = function(key, ...)
                if key == 'AceConfig-3.0' then
                    return {RegisterOptionsTable=function(_, _, options) settingsOptions=options end}
                end
                return stub(key, ...)
            end
            regionalNames = true
            units.player, units.target = {'Mira','Summer'}, {'Theo','Stone'}
            local create = CreateFrame
            GameTooltip = {IsOwned = function() return false end}
            frames = {}
            CreateFrame = function(kind, name, parent, ...)
                local frame = create(kind, name, parent, ...)
                frame.parent = parent
                frames[#frames+1] = frame
                function frame:SetSize(w, h) self.width, self.height = w, h end
                function frame:SetAlpha(value) self.alpha = value end
                function frame:GetAlpha() return self.alpha or 1 end
                function frame:SetIgnoreParentAlpha(value) self.ignoreParentAlpha = value end
                if kind == 'PlayerModel' then
                    function frame:SetModelAlpha(value) self.modelAlpha = value end
                    function frame:SetModelDrawLayer(layer) self.modelLayer = layer end
                    function frame:SetRotation(angle) assert(type(angle) == 'number'); self.rotation = angle end
                    function frame:SetPortraitZoom(zoom) self.zoom = zoom end
                    function frame:SetKeepModelOnHide(value) self.keepOnHide = value end
                    function frame:SetUnit(unit, blend, useNativeForm)
                        self.bound = unit
                        if reject then return false end
                        self.character = DRE:GetUnitPlayerName(unit)
                        self.appearance = not useNativeForm and forms and forms[unit] or self.character
                        if not delayed then self:GetScript('OnModelLoaded')() end
                        return true
                    end
                    function frame:ClearModel() self.bound, self.character = nil, nil end
                end
                return frame
            end
            SetPortraitTexture = function(texture, unit)
                texture.portraitUnit, texture.character = unit, DRE:GetUnitPlayerName(unit)
            end
            local release = AceGUI.Release
            function AceGUI:Release(widget)
                if widget.kind == 'DREGroupCircle' then widget:OnRelease() end
                release(self, widget)
            end
        """)
        self.lua.execute(r"""
            function openGroup()
                DRE:SlashCommand('group')
                w = DRE.UI.groupWidgets
                board = w.circle
            end
            function click(widget)
                assert(not widget.disabled)
                widget.control:GetScript('OnClick')(widget.control, 'LeftButton')
            end
            function roll(name, n, maximum)
                DRE:CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM', name..' rolls '..n..' (1-'..maximum..')')
            end
            function edit(names)
                for i = #board.players, 1, -1 do
                    local remove = board.seats[i].portraitButton
                    assert(remove:IsShown())
                    remove:GetScript('OnClick')(remove, 'RightButton')
                end
                for _, name in ipairs(names) do
                    w.nameInput:SetText(name)
                    w.nameInput:Fire('OnEnterPressed')
                end
            end
            function near(a, b) assert(math.abs(a-b) < 0.000001, a..' vs '..b) end
            function unitEvent(event, unit)
                board.frame:GetScript('OnEvent')(board.frame, event, unit)
            end
            function flushUnits()
                for _, frame in ipairs(frames) do
                    if frame.parent == board.frame and frame:GetScript('OnUpdate') then
                        frame:GetScript('OnUpdate')(frame, 0.01)
                    end
                end
            end
            openGroup()
        """)

    def test_typed_lowercase_names_take_their_turns_and_bind_models(self):
        self.lua.execute("""
            DRE:SetGroupAppearance('models')
            delayed = true
            edit({'theo stone', 'mira summer', 'Theo Brook'})
            local seat = board.seats[1]
            click(w.primary)
            local round = DRE.groupRound
            roll('Theo Brook', 1, 100)
            roll('Theo Stone', 1, 99)
            assert(round.turn == 1 and round.rollCount == 0)
            roll('Theo Stone', 37, 100)
            assert(round.turn == 2 and round.rollCount == 1 and round.currentRoll == 37)
            assert(w.phase == 'roll' and not w.primary.disabled)
            click(w.primary)
            assert(#rolls == 1 and rolls[1][2] == 37)
            roll('Mira Summer', 1, 37)
            assert(round.status == 'finished' and round.rollCount == 2)
            assert(seat.nameLabel:GetText() == 'theo stone' and seat.unit == 'target')
            seat.model:GetScript('OnModelLoaded')()
            assert(seat.ready and seat.model.character == 'Theo Stone')
            unitEvent('UNIT_MODEL_CHANGED', 'target')
            flushUnits()
            seat.model:GetScript('OnModelLoaded')()
            assert(seat.ready and seat.model.character == 'Theo Stone')
            assert(board.seats[2].nameLabel:GetText() == 'mira summer')
        """)

    def test_different_caps_cannot_add_a_second_seat(self):
        self.lua.execute(r"""
            edit({'theo stone', 'ThEo StOnE'})
            assert(#board.players == 1 and board.players[1] == 'theo stone')
            assert(not DRE:AddGroupPlayerFromUnit('target'))
            assert(not DRE:StartGroupRound('theo stone\nTHEO STONE', 100, 'SAY'))
            w.nameInput:SetText('Theo Brook')
            w.nameInput:Fire('OnEnterPressed')
            assert(#board.players == 2 and board.players[2] == 'Theo Brook')
            regionalNames = false
            assert(not DRE:ParseGroupRoster('theo-RealmA\nThEo-realMa'))
            assert(DRE:ParseGroupRoster('theo-RealmA\nTHEO-RealmB'))
            assert(DRE:StartGroupRound('theo-realma\nTheo-RealmB', 100, 'SAY'))
            roll('Theo-RealmB', 1, 100)
            assert(DRE.groupRound.rollCount == 0)
            roll('Theo-RealmA', 37, 100)
            assert(DRE.groupRound.turn == 2 and DRE.groupRound.currentRoll == 37)
        """)

    def test_group_uses_client_utf8_comparison_for_accented_names(self):
        def compare(first, second):
            a, b = first.lower(), second.lower()
            return (a > b) - (a < b)

        self.lua.globals().strcmputf8i = compare
        self.lua.execute("""
            edit({'élise stone', 'ÉLISE STONE', 'Elise Stone'})
            assert(#board.players == 2 and board.players[1] == 'élise stone')
            click(w.primary)
            roll('Elise Stone', 1, 100)
            assert(DRE.groupRound.rollCount == 0)
            roll('Élise Stone', 42, 100)
            assert(DRE.groupRound.turn == 2 and DRE.groupRound.currentRoll == 42)
        """)

    def test_roll_replaces_the_rollers_face_then_lands_in_the_badge(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone'})
            click(w.primary)
            local badge = board.rollBadge
            for i, seat in ipairs(board.seats) do
                function seat:GetCenter() return self.x,self.y end
            end
            function badge:GetCenter()
                return self.seat.x,self.seat.y-self.seat:GetWidth()/2+10
            end
            function badge.number:GetStringWidth() return 14 end
            function badge.caption:SetPoint(_, _, _, x, y) self.dx,self.dy = x or 0,y or 0 end
            local first, second = board.seats[1],board.seats[2]
            roll('Theo Stone', 57, 100)
            assert(not badge:GetScript('OnUpdate'))
            roll('Mira Summer', 57, 100)
            assert(badge.rollingSeat == first and badge.number:GetText() == '57')
            assert(not first.face:IsShown() and first.model.modelAlpha == 0 and first.cornerCover.ignoreParentAlpha)
            near(first.face:GetAlpha(),0); near(second.face:GetAlpha(),1); near(badge.plate:GetAlpha(),0)
            local step = assert(badge:GetScript('OnUpdate'))
            local full = badge.caption:GetScale()
            assert(full > 1)
            near(badge.caption.dy * full,first:GetWidth()/2-10)
            step(badge,1)
            DRE:RefreshGroupUI()
            roll('Theo Stone', 42, 100)
            near(badge.elapsed,1); near(first.face:GetAlpha(),0)
            near(badge.caption:GetScale(),full)
            near(badge.caption.dy * full,first:GetWidth()/2-10)
            step(badge,0.15)
            assert(first.face:IsShown() and first.cornerCover:IsShown())
            near(first.model.modelAlpha, 0.5)
            near(first.face:GetAlpha(),0.5); near(badge.plate:GetAlpha(),0.5)
            near(badge.caption:GetScale(),(full+1)/2)
            near(badge.caption.dy*badge.caption:GetScale(),(first:GetWidth()/2-10)/2)
            roll('Theo Stone', 57, 57)
            assert(badge.rollingSeat == second)
            near(first.face:GetAlpha(),1); near(second.face:GetAlpha(),0)
            step(badge,1.3)
            near(second.face:GetAlpha(),1); near(badge.plate:GetAlpha(),1)
            near(badge.caption:GetScale(),1); near(badge.caption.dy,0)
            assert(not badge:GetScript('OnUpdate') and badge:IsShown())
            roll('Mira Summer', 1, 57)
            assert(badge.rollingSeat == first and not board.hand:IsShown())
            click(w.primary)
            near(first.face:GetAlpha(),1)
            assert(not badge:IsShown() and not badge:GetScript('OnUpdate'))
            roll('Mira Summer', 40, 100)
            board.frame:Hide()
            roll('Theo Stone', 20, 40)
            board.frame:Show()
            assert(not badge:GetScript('OnUpdate') and badge.number:GetText() == '20')
            near(first.face:GetAlpha(),1)
            roll('Mira Summer', 5, 20)
            DRE:CancelGroupRound(true)
            assert(not badge:GetScript('OnUpdate') and not badge:IsShown())
            near(first.face:GetAlpha(),1)
        """)

    def test_eight_seat_sweep_wrap_and_terminal_result(self):
        self.lua.execute("""
            local names = {'Mira Summer','Theo Stone','Adi Sun','Bo Oak',
                'Ira Sky','Reed Bay','Kim Hill','Jo Lake'}
            edit(names)
            w.form.children[7].children[1]:Fire('OnValueChanged', 'SAY')
            assert(w.status:GetText() == 'Mira Summer rolls first' and w.lastRoll:IsShown())
            assert(w.lastRoll:GetText():find('The first player to roll 1 loses.', 1, true))
            assert(w.primary:GetText() == 'Start  1–100')
            assert(#board.seats == 8 and w.form and not w.roster)
            click(w.primary)
            assert(w.status:GetText() == 'Mira Summer rolls 1–100' and #w.pane.children == 1)
            assert(DRE.UI.tableHero.groupBelow and not board.rollBadge:IsShown())
            assert(not board.seats[1].portraitButton:IsShown() and not w.form)
            click(w.primary)
            assert(#rolls == 1 and w.primary.disabled)
            roll('Theo Stone', 1, 100)
            roll('Mira Summer', 1, 99)
            assert(DRE.groupRound.rollCount == 0 and not board.frame:GetScript('OnUpdate'))
            assert(not board.rollBadge:IsShown())
            local maximum = 100
            for i, name in ipairs(names) do
                local start = board.angle
                local result = i == 1 and 37 or maximum
                roll(name, result, maximum)
                assert(w.lastRoll:GetText() == '2.7% chance to roll a 1')
                assert(board.rollBadge:IsShown() and board.rollBadge.seat == board.seats[i])
                assert(board.rollBadge.number:GetText() == '37')
                assert(w.status:GetText() == names[i%8+1]..' rolls 1–37')
                near(board.angle, start)
                near(board.destination - start, math.pi/4)
                local advance = assert(board.frame:GetScript('OnUpdate'))
                advance(board.frame, 0.16)
                near(board.angle, start + math.pi/8)
                DRE:RefreshGroupUI()
                advance(board.frame, 0.16)
                near(board.angle, start + math.pi/4)
                assert(not board.frame:GetScript('OnUpdate'))
                maximum = result
            end
            roll(names[1], 1, 37)
            assert(w.status:GetText() == 'Mira Summer rolled 1 and loses')
            assert(w.lastRoll:GetText() == 'Settle payouts manually.')
            assert(board.rollBadge.seat == board.seats[1] and board.rollBadge.number:GetText() == '1')
            assert(not board.hand:IsShown() and not next(DRE.db.profile.history))
            click(w.announce)
            assert(sent[#sent][1]:find('Mira Summer rolled 1',1,true))
            click(w.primary)
            assert(w.status:GetText() == 'Mira Summer rolls 1–100' and not DRE.groupRound.lastRoll)
            assert(not board.rollBadge:IsShown())
            click(w.secondary)
            assert(w.status:GetText() == 'Round cancelled' and not board.hand:IsShown())
        """)

    def test_resize_scales_the_roll_reveal_and_landed_badge_without_restarting(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone'})
            board.parent = w.pane
            local badge = board.rollBadge
            function badge.number:GetStringHeight() return badge.fontSize end
            function badge.number:GetStringWidth() return #self:GetText() * badge.fontSize * 0.55 end
            local roller = board.seats[1]
            function roller:GetCenter() return self.x, self.y end
            function badge:GetCenter() return self.seat.x, self.seat.y - self.seat:GetWidth()/2 + self:GetHeight()/2 end
            w.initialRoll:Fire('OnTextChanged', '999999')
            click(w.primary)
            w.pane.frame:SetHeight(540)
            board:OnWidthSet(760)
            roll('Mira Summer', 987654, 999999)
            local step = assert(badge:GetScript('OnUpdate'))
            step(badge, 0.5)
            local function reveal() return badge.number:GetStringWidth() * badge.caption:GetScale() end
            local width, height, font, initialReveal = badge:GetWidth(), badge:GetHeight(), badge.fontSize, reveal()
            w.pane.frame:SetHeight(1080)
            board:OnWidthSet(1520)
            step(badge, 0)
            near(badge.elapsed, 0.5)
            assert(reveal() > 1.9 * initialReveal and reveal() <= board.seats[1]:GetWidth())
            assert(badge:GetWidth() > 1.9 * width and badge:GetHeight() > 1.9 * height)
            assert(badge.fontSize > 1.9 * font)
            step(badge, 0.81)
            assert(not badge:GetScript('OnUpdate') and badge.caption:GetScale() == 1)
            w.pane.frame:SetHeight(540)
            board:OnWidthSet(760)
            near(badge:GetWidth(), width); near(badge:GetHeight(), height)
            assert(badge.number:GetText() == '987654')
        """)

    def test_dense_table_keeps_badge_by_the_rollers_label_and_summary_outside_scroll(self):
        self.lua.execute("""
            local names = {'Mira Summer'}
            for i = 2,40 do names[i] = 'Player '..string.rep('a',i) end
            edit(names)
            local content = DRE.UI.mainWindow.content
            local anchors = {}
            function content:SetPoint(point, target, edge) anchors[point] = {target, edge} end
            w.initialRoll:Fire('OnTextChanged', '999999')
            click(w.primary)
            assert(anchors.TOPLEFT[1] == DRE.UI.mainWindow.frame)
            assert(anchors.BOTTOMRIGHT[2] == 'TOPRIGHT')
            local badge = board.rollBadge
            function badge:SetPoint(_, target) self.anchor = target end
            board.seats[1].GetCenter = function() return 0, 0 end
            local destination = 38
            function badge:GetCenter() return destination, 12 end
            function badge.caption:SetPoint(_, _, _, x) self.dx = x or 0 end
            roll(names[1], 987654, 999999)
            assert(board.badgeInLabel and badge.anchor == board.seats[1].nameLabel)
            assert(badge.number:GetText() == '987654' and badge:GetFrameLevel() > board.seats[1]:GetFrameLevel())
            near(badge.caption.dx * badge.caption:GetScale(), -38)
            destination = 54
            badge:GetScript('OnUpdate')(badge, 1.15)
            near(badge.caption.dx * badge.caption:GetScale(), -27)
            DRE:CancelGroupRound(true)
            assert(not badge:IsShown() and not w.lastRoll:IsShown())
            click(w.secondary)
            assert(not DRE.UI.tableHero.groupBelow and anchors.TOPLEFT[2] == 'BOTTOMLEFT')
        """)

    def test_silent_table_round_and_saved_picker_on_reopen(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone'})
            local picker = w.form.children[7].children[1]
            assert(picker:GetValue() == 'NONE')
            click(w.primary)
            assert(not w.announce)
            roll('Mira Summer', 48, 100)
            assert(not w.announce and w.status:GetText() == 'Theo Stone rolls 1–48')
            roll('Theo Stone', 1, 48)
            assert(not w.announce and #sent == 0)
            click(w.secondary)
            w.form.children[7].children[1]:Fire('OnValueChanged','SAY')
            DRE.groupDraft, DRE.groupRound = nil, nil
            DRE:SelectMainSection('deathroll')
            openGroup()
            assert(w.form.children[7].children[1]:GetValue() == 'SAY')
        """)

    def test_elimination_resets_skips_seats_and_records_one_match(self):
        self.lua.execute("""
            edit({'Mira Summer', 'Theo Stone', 'Arlo Strand'})
            w.mode:Fire('OnValueChanged', 'elimination')
            click(w.primary)
            local round = DRE.groupRound
            roll('Mira Summer', 50, 100)
            roll('Theo Stone', 1, 50)
            assert(round.status == 'active' and round.remaining == 2 and round.currentRoll == 100)
            assert(board.seats[2].inactiveShade:IsShown() and w.status:GetText() == 'Arlo Strand rolls 1–100')
            assert(board.rollBadge.seat == board.seats[2] and board.rollBadge.number:GetText() == '1')
            assert(w.lastRoll:GetText() == 'Theo Stone is out · 2 players left')
            assert(DRE:GetGroupAnnouncement(round):find('Theo Stone is out', 1, true))
            assert(not DRE:GetHostedGroupStats())
            roll('Theo Stone', 1, 100)
            roll('Arlo Strand', 1, 50)
            assert(round.rollCount == 2)
            roll('Arlo Strand', 20, 100)
            roll('Mira Summer', 10, 20)
            assert(round.turn == 3)
            near(board.destination, (5 + 0.5)*2*math.pi/3)
            roll('Arlo Strand', 1, 10)
            assert(round.winner == 'Mira Summer' and not board.hand:IsShown())
            assert(w.status:GetText() == 'Mira Summer wins Elimination')
            local stats = DRE:GetHostedGroupStats()
            assert(stats.played == 1 and stats.losses == 0 and stats.longest.rolls == 5)
            assert(stats.regulars['theo stone'].losses == 1 and stats.regulars['arlo strand'].losses == 1)
            click(w.primary)
            assert(DRE.groupRound.mode == 'elimination' and DRE.groupRound.remaining == 3)
            assert(not board.seats[2].inactiveShade:IsShown() and board.seats[2].faceAlpha == 1)
            roll('Mira Summer', 1, 100)
            DRE:CancelGroupRound(true)
            assert(stats.played == 1 and stats.losses == 0)
        """)

    def test_hot_potato_draws_once_per_safe_roll_and_announces_the_selected_seat(self):
        self.lua.execute("""
            edit({'Mira Summer', 'Theo Stone', 'Arlo Strand'})
            w.mode:Fire('OnValueChanged', 'hotPotato')
            click(w.primary)
            local round = DRE.groupRound
            local draws, original = 0, math.random
            math.random = function(n) assert(n == 2); draws = draws + 1; return 2 end
            roll('Theo Stone', 9, 100)
            roll('Mira Summer', 42, 100)
            assert(draws == 1 and round.turn == 3 and round.currentRoll == 42)
            near(board.destination, 2.5*2*math.pi/3)
            assert(DRE:GetGroupAnnouncement(round):find('Arlo Strand, /roll 42', 1, true))
            roll('Mira Summer', 1, 42)
            roll('Arlo Strand', 42, 42)
            assert(draws == 2 and round.turn == 2)
            near(board.destination, 4.5*2*math.pi/3)
            roll('Theo Stone', 1, 42)
            assert(draws == 2 and round.loser == 'Theo Stone' and not board.hand:IsShown())
            math.random = original
            click(w.primary)
            assert(DRE.groupRound.mode == 'hotPotato' and DRE.groupRound.turn == 1)
        """)

    def test_two_lives_first_loss_final_loss_and_replay(self):
        self.lua.execute("""
            edit({'Mira Summer', 'Theo Stone', 'Arlo Strand'})
            w.mode:Fire('OnValueChanged', 'twoLives')
            for _, seat in ipairs(board.seats) do
                assert(seat.score:IsShown() and seat.score.caption:GetText() == '2')
                function seat.score:SetBackdropBorderColor(red) self.borderRed = red end
            end
            click(w.primary)
            local round = DRE.groupRound
            roll('Mira Summer', 10, 100)
            roll('Theo Stone', 1, 10)
            assert(round.turn == 3 and round.currentRoll == 100 and round.remaining == 3)
            assert(board.seats[2].nameLabel:GetText() == 'Theo Stone')
            assert(board.seats[2].score.caption:GetText() == '1')
            assert(not board.seats[2].inactiveShade:IsShown())
            assert(board.seats[1].score.borderRed == board.seats[2].score.borderRed) -- tied leaders
            assert(DRE:GetGroupAnnouncement(round):find('Theo Stone has one life left', 1, true))
            roll('Arlo Strand', 9, 100)
            roll('Mira Summer', 8, 9)
            roll('Theo Stone', 1, 8)
            assert(round.remaining == 2 and board.seats[2].inactiveShade:IsShown())
            assert(board.seats[2].score.caption:GetText() == '0')
            roll('Arlo Strand', 1, 100)
            assert(board.seats[1].score.borderRed > board.seats[3].score.borderRed)
            roll('Mira Summer', 12, 100)
            assert(round.turn == 3 and not DRE:GetHostedGroupStats())
            roll('Arlo Strand', 1, 12)
            assert(w.status:GetText() == 'Mira Summer wins Two Lives')
            assert(DRE:GetHostedGroupStats().regulars['theo stone'].losses == 1)
            click(w.primary)
            assert(DRE.groupRound.lives[2] == 2 and not board.seats[2].inactiveShade:IsShown())
            assert(board.seats[2].score.caption:GetText() == '2')
        """)

    def test_life_badges_follow_portraits_or_crowded_name_columns_on_resize(self):
        self.lua.execute("""
            local names = {}
            for i = 1, 40 do names[i] = 'Player '..string.rep('a', i) end
            edit(names)
            board:OnWidthSet(428)
            w.mode:Fire('OnValueChanged', 'twoLives')
            local seat = board.seats[1]
            function seat.score:SetPoint(point, relative) self.anchor = relative end
            board:OnWidthSet(430)
            assert(seat.score.anchor == seat.nameLabel)
            local nextSeat = board.seats[2]
            assert(seat.labelY - nextSeat.labelY >= seat.score:GetHeight() + seat.nameLabel:GetStringHeight())
            for i = #names, 3, -1 do
                local remove = board.seats[i].portraitButton
                remove:GetScript('OnClick')(remove, 'RightButton')
            end
            assert(board.seats[1] == seat and seat.score.anchor == seat)
            w.mode:Fire('OnValueChanged', 'classic')
            assert(not seat.score:IsShown())
            w.mode:Fire('OnValueChanged', 'twoLives')
            assert(seat.score:IsShown() and seat.score.anchor == seat)
        """)

    def test_seat_badges_persist_across_rotation_and_clear_on_life_loss(self):
        self.lua.execute("""
            local names = {'Mira Summer', 'Theo Stone', 'Arlo Strand'}
            edit(names)
            w.mode:Fire('OnValueChanged', 'twoLives')
            click(w.primary)
            local r = DRE.groupRound
            roll(names[1], 80, 100)
            roll(names[2], 41, 80)
            roll(names[3], 19, 41)
            roll(names[1], 12, 19)
            assert(r.seatRolls[1] == 12 and r.seatRolls[2] == 41 and r.seatRolls[3] == 19)
            for i = 2, 3 do
                local badge = board.seats[i].lastRollBadge
                assert(badge:IsShown() and badge.number:GetText() == tostring(r.seatRolls[i]))
            end
            assert(board.rollBadge.seat == board.seats[1] and board.rollBadge.number:GetText() == '12')
            roll(names[2], 1, 12)
            assert(not next(r.seatRolls) and r.lives[2] == 1)
            for _, seat in ipairs(board.seats) do
                assert(not seat.lastRollBadge or not seat.lastRollBadge:IsShown())
            end
            roll(names[3], 68, 100)
            assert(r.seatRolls[3] == 68 and not r.seatRolls[1] and not r.seatRolls[2])
        """)

    def test_high_roller_scores_complete_rounds_and_replays_ties(self):
        self.lua.execute("""
            local names = {'Mira Summer', 'Theo Stone', 'Arlo Strand', 'Fia Day'}
            edit(names)
            w.mode:Fire('OnValueChanged', 'highRoller')
            for _, seat in ipairs(board.seats) do
                assert(seat.score:IsShown() and seat.score.caption:GetText() == '0')
                local coin = seat.score.pips[1]
                function coin:SetTexture(path) self.path = path end
                function seat:GetCenter() return self.x, self.y end
            end
            local badge = board.rollBadge
            function badge:GetCenter() return self.seat.x, self.seat.y - 8 end
            local function expectFaces(...)
                for i, alpha in ipairs({...}) do
                    near(board.seats[i].face:GetAlpha(), alpha)
                    assert(board.seats[i].inactiveShade:IsShown() == (board.seats[i].sittingOut == true))
                    near(board.seats[i]:GetAlpha(), 1) -- parent of the name and coins
                end
            end
            click(w.primary)
            local round = DRE.groupRound
            local function pass(values)
                for i, n in ipairs(values) do
                    assert(round.turn == i and round.currentRoll == 100)
                    roll(names[i], n, 100)
                end
            end
            roll(names[2], 100, 100)
            roll(names[1], 1, 99)
            assert(round.rollCount == 0 and not round.highFace)
            roll(names[1], 1, 100)
            roll(names[1], 100, 100)
            assert(round.turn == 2 and round.rollCount == 1 and not round.eliminated[1])
            assert(not DRE:GetGroupAnnouncement(round):find('out', 1, true))
            roll(names[2], 50, 100)
            roll(names[3], 50, 100)
            roll(names[4], 50, 100)
            assert(round.points[2] == 0 and round.points[3] == 0 and round.scoringRound == 1)
            assert(w.lastRoll:GetText():find('Tied at 50', 1, true))
            for i = 2, 4 do assert(round.seatRolls[i] == 50) end
            assert(not round.seatRolls[1] and not board.seats[1].lastRollBadge:IsShown())
            assert(board.seats[2].lastRollBadge:IsShown() and board.seats[3].lastRollBadge:IsShown())
            assert(round.turn == 2 and round.seatSteps % 4 == 1 and not DRE:RollGroupTurn())
            assert(DRE:GetGroupAnnouncement(round):find('Round 1 tiebreak: Theo Stone, /roll 100', 1, true))
            badge:GetScript('OnUpdate')(badge, 1.4)
            expectFaces(0.35, 1, 1, 1)
            roll(names[1], 99, 100) -- outside this tiebreak
            roll(names[2], 10, 50) -- the opening range still applies
            assert(round.turn == 2 and round.rollCount == 4)
            roll(names[2], 80, 100)
            assert(round.seatRolls[2] == 80 and round.seatRolls[3] == 50)
            roll(names[3], 80, 100)
            roll(names[4], 1, 100)
            assert(round.turn == 2 and #round.tiebreak == 2 and round.scoringRound == 1)
            assert(not round.seatRolls[4] and not board.seats[4].lastRollBadge:IsShown())
            assert(not badge:IsShown() and not badge.rollingSeat) -- the last roller is now sitting out
            expectFaces(0.35, 1, 1, 0.35)
            DRE:RefreshGroupUI()
            expectFaces(0.35, 1, 1, 0.35)
            roll(names[2], 1, 100)
            roll(names[4], 100, 100) -- dropped from the second tiebreak
            assert(round.turn == 3 and round.seatSteps % 4 == 2)
            roll(names[3], 9, 100)
            assert(round.turn == 1 and round.seatSteps % 4 == 0 and not round.tiebreak and round.scoringRound == 2)
            expectFaces(1, 1, 0, 1) -- only the scoring roll's normal animation is playing
            badge:GetScript('OnUpdate')(badge, 1.4)
            expectFaces(1, 1, 1, 1)
            assert(round.points[3] == 1 and board.seats[3].score.caption:GetText() == '1')
            assert(not next(round.seatRolls) and not badge:IsShown())
            assert(board.seats[3].score.pips[1].path:match('UI%-GoldIcon$'))
            pass({80,50,75,1})
            assert(round.points[1] == 1 and round.points[3] == 1)
            roll(names[1], 1, 100)
            roll(names[2], 5, 100)
            roll(names[3], 90, 100)
            assert(round.status == 'active' and round.points[3] == 1 and not DRE:GetHostedGroupStats())
            roll(names[4], 90, 100)
            assert(round.turn == 3 and round.scoringRound == 3 and round.points[3] == 1)
            roll(names[3], 70, 100)
            roll(names[4], 5, 100)
            assert(round.winner == names[3] and round.status == 'finished' and round.points[3] == 2)
            assert(board.seats[3].score.caption:GetText() == '2' and not board.hand:IsShown())
            assert(DRE:GetGroupAnnouncement(round):find('Arlo Strand wins with 2 points', 1, true))
            local stats = DRE:GetHostedGroupStats()
            assert(stats.played == 1 and stats.losses == 1 and stats.regulars['arlo strand'].losses == 0)
            assert(not next(DRE.db.profile.history))
            click(w.primary)
            assert(DRE.groupRound.scoringRound == 1 and DRE.groupRound.points[3] == 0 and DRE.groupRound.turn == 1)
            assert(board.seats[3].score.caption:GetText() == '0')
            round = DRE.groupRound
            pass({90,90,1,1})
            DRE:CancelGroupRound(true)
            expectFaces(1, 1, 1, 1)
        """)

    def test_team_backgrounds_follow_players_through_shuffle_and_reset_in_classic(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone'})
            local mira, theo = board.seats[1], board.seats[2]
            for _, seat in ipairs({mira, theo}) do
                assert(rawget(seat.backing, 'mask'))
                function seat.backing:SetColorTexture(r, g, b, a)
                    assert(a == 1)
                    self.tint = r > g and (g > b and 'gold' or 'red') or 'green'
                end
            end
            w.mode:Fire('OnValueChanged', 'teams')
            assert(mira.backing.tint == 'gold' and theo.backing.tint == 'red')
            assert(mira.team == 1 and theo.team == 2 and mira.portraitButton:IsShown())
            local random = math.random
            math.random = function() return 1 end
            click(w.shuffle)
            math.random = random
            assert(board.seats[1] == theo and theo.team == 2 and mira.team == 1)
            assert(mira.backing.tint == 'gold' and theo.backing.tint == 'red')
            mira.portraitButton:GetScript('OnClick')(mira.portraitButton, 'LeftButton')
            assert(mira.backing.tint == 'red')
            w.mode:Fire('OnValueChanged', 'classic')
            assert(mira.backing.tint == 'green' and theo.backing.tint == 'green')
            assert(not mira.portraitButton.ring:IsShown() and not theo.portraitButton.ring:IsShown())
        """)

    def test_team_border_gives_way_to_a_single_active_glow(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone'})
            w.mode:Fire('OnValueChanged', 'teams')
            local mira, theo = board.seats[1].portraitButton.ring, board.seats[2].portraitButton.ring
            local gold, red = board.seats[1].portraitButton.outline, board.seats[2].portraitButton.outline
            assert(gold:IsShown() and red:IsShown())
            assert(not mira:IsShown() and not theo:IsShown())
            click(w.primary)
            assert(mira:IsShown() and not theo:IsShown())
            assert(not gold:IsShown() and red:IsShown())
            roll('Mira Summer', 37, 100)
            board.frame:GetScript('OnUpdate')(board.frame, 0.16)
            assert(not mira:IsShown() and theo:IsShown())
            assert(gold:IsShown() and not red:IsShown())
            assert(not board.turnRing.halo:IsShown() and not board.trailingRing.halo:IsShown())
            roll('Theo Stone', 1, 37)
            assert(not mira:IsShown() and not theo:IsShown())
            assert(gold:IsShown() and red:IsShown())
            click(w.secondary)
            w.mode:Fire('OnValueChanged', 'classic')
            assert(not gold:IsShown() and not red:IsShown())
            click(w.primary)
            assert(board.turnRing:IsShown() and board.turnRing.halo:IsShown())
        """)

    def test_custom_teams_lock_in_for_play_scoring_and_replay(self):
        self.lua.execute("""
            local names = {'Mira Summer','Theo Stone','Arlo Strand'}
            edit(names)
            w.mode:Fire('OnValueChanged', 'teams')
            local function switch(i)
                local button = board.seats[i].portraitButton
                button:GetScript('OnClick')(button, 'LeftButton')
            end
            switch(2)
            assert(w.primary.disabled)
            local draft = DRE:GetGroupDraft()
            assert(not DRE:StartGroupRound(draft.roster, 100, 'NONE', 'teams') and DRE.groupRound == nil)
            switch(1)
            assert(not w.primary.disabled and board.seats[1].team == 2)
            for _, seat in ipairs(board.seats) do
                function seat.backing:SetColorTexture(r, g, b)
                    assert(r > g and r > b)
                    assert((seat.team == 1 and g > b) or (seat.team == 2 and b > g))
                    self.red = r
                end
            end
            DRE:RefreshGroupUI()
            local restingRed = board.seats[1].backing.red
            click(w.primary)
            local round = DRE.groupRound
            assert(board.seats[1].backing.red > restingRed)
            assert(round.teamRemaining[1] == 2 and round.teamRemaining[2] == 1)
            switch(1)
            assert(round.teams[names[1]] == 2)
            assert(DRE:GetGroupAnnouncement(round):find('Red team: Mira Summer', 1, true))
            roll(names[1], 20, 100)
            roll(names[2], 1, 20)
            assert(round.turn == 1 and round.teamRemaining[1] == 1)
            assert(board.seats[2].backing.red < board.seats[3].backing.red)
            assert(board.seats[2].inactiveShade:IsShown() and not board.seats[3].inactiveShade:IsShown())
            roll(names[1], 4, 100)
            near(board.seats[2].model.modelAlpha, 0.35)
            assert(round.turn == 3)
            roll(names[3], 1, 4)
            assert(w.status:GetText() == 'Team Red wins')
            local stats = DRE:GetHostedGroupStats().byMode.teams
            assert(stats.losses == 0 and stats.regulars['theo stone'].losses == 1)
            click(w.secondary)
            switch(1)
            assert(w.primary.disabled and round.teams[names[1]] == 2)
            assert(DRE:RestartGroupRound() and DRE.groupRound.teams[names[1]] == 2)
            assert(not board.seats[2].inactiveShade:IsShown() and board.seats[2].model.modelAlpha == 1)
        """)

    def test_odd_teams_rotate_fairly_and_score_the_entire_winning_team(self):
        self.lua.execute("""
            local names = {'Mira Summer','Theo Stone','Arlo Strand','Fia Day','Ada Sun'}
            edit(names)
            w.mode:Fire('OnValueChanged', 'teams')
            assert(board.seats[1].nameLabel:GetText() == 'Mira Summer' and board.seats[1].team == 1)
            assert(board.seats[4].nameLabel:GetText() == 'Fia Day' and board.seats[4].team == 2)
            click(w.primary)
            local round = DRE.groupRound
            for _, seat in ipairs({1,2,3,4,5,2,1,4,3,2,5,4}) do
                assert(round.turn == seat and round.seatSteps % 5 == seat-1)
                roll(names[seat], 100, 100)
            end
            roll(names[1], 1, 100)
            roll(names[2], 1, 100)
            roll(names[3], 5, 100)
            assert(DRE:GetGroupAnnouncement(round):find('Red team: Fia Day, /roll 5', 1, true))
            roll(names[4], 1, 5)
            assert(round.remaining == 2 and w.status:GetText() == 'Team Gold wins')
            assert(DRE:GetGroupAnnouncement(round):find('Team Gold wins', 1, true))
            local stats = DRE:GetHostedGroupStats()
            assert(stats.played == 1 and stats.losses == 0 and stats.regulars['mira summer'].losses == 0)
            assert(stats.regulars['fia day'].losses == 1 and stats.regulars['theo stone'].losses == 1)
            click(w.primary)
            assert(DRE.groupRound.mode == 'teams' and DRE.groupRound.remaining == 5)
            assert(DRE.groupRound.teamRemaining[1] == 3 and DRE.groupRound.teamRemaining[2] == 2)
        """)

    def test_shuffle_previews_the_order_and_locks_it_for_the_round(self):
        self.lua.execute("""
            assert(w.shuffle.disabled and not DRE:ShuffleGroupOrder())
            edit({'Mira Summer','Theo Stone','Arlo Strand'})
            local random = math.random
            math.random = function(n) return 1 end
            click(w.shuffle)
            math.random = random
            assert(table.concat(board.players, ',') == 'Theo Stone,Arlo Strand,Mira Summer')
            assert(w.status:GetText() == 'Theo Stone rolls first')
            click(w.primary)
            local played = DRE.groupRound.players
            assert(table.concat(played, ',') == table.concat(board.players, ','))
            assert(not w.shuffle and not DRE:ShuffleGroupOrder())
            roll('Theo Stone', 1, 100)
            assert(not DRE:ShuffleGroupOrder())
            click(w.secondary)
            assert(w.shuffle and DRE:ShuffleGroupOrder())
            assert(table.concat(played, ',') == 'Theo Stone,Arlo Strand,Mira Summer')
            assert(DRE:RestartGroupRound() and DRE.groupRound.players[1] == 'Theo Stone')
        """)

    def test_removing_a_seat_preserves_order_and_round_result(self):
        self.lua.execute("""
            assert(#board.players == 1 and w.primary.disabled)
            assert(DRE:AddGroupPlayerFromUnit('target') and not DRE:AddGroupPlayerFromUnit('target'))
            assert(not w.primary.disabled and not w.roster)
            w.nameInput:SetText('Eration Rageclaw')
            w.nameInput:Fire('OnEnterPressed')
            local remove = board.seats[2].portraitButton
            remove:GetScript('OnClick')(remove, 'LeftButton')
            assert(#board.players == 3)
            remove:GetScript('OnClick')(remove, 'RightButton')
            assert(table.concat(board.players, ',') == 'Mira Summer,Eration Rageclaw')
            board.parent = w.pane
            w.pane.frame:SetHeight(220)
            board:OnWidthSet(444)
            assert(board.handLength >= 19)
            click(w.primary)
            local original = DRE.groupRound
            remove = board.seats[2].portraitButton
            remove:GetScript('OnClick')(remove, 'RightButton')
            assert(#original.players == 2 and not w.form)
            roll('Mira Summer', 1, 100)
            click(w.secondary)
            remove:GetScript('OnClick')(remove, 'RightButton')
            assert(w.primary.disabled and #board.players == 1)
            assert(original.loser == 'Mira Summer' and #original.players == 2)
            assert(DRE:RestartGroupRound())
            assert(#board.players == 2 and not w.form and w.phase == 'roll')
        """)

    def test_full_names_models_fallback_rebinding_and_tab_switch(self):
        self.lua.execute("""
            DRE:SetGroupAppearance('models')
            units.party1 = {'Theo','Brook'}
            reject = true
            edit({'Mira Summer', 'Theo Stone', 'Theo Brook', 'Fia Day'})
            local seat = board.seats[2]
            assert(seat.nameLabel:GetText() == 'Theo Stone' and seat.unit == 'target')
            assert(seat.portrait:IsShown() and seat.portrait.portraitUnit == 'target')
            assert(board.seats[3].unit == 'party1' and board.seats[4].standIn)
            board.frame:Hide()
            reject = false
            board.frame:Show()
            assert(not seat.portrait:IsShown() and seat.model.bound == 'target')
            local stale = seat.model:GetScript('OnModelLoaded')
            units.target = {'Different', 'Stone'}
            unitEvent('PLAYER_TARGET_CHANGED')
            local isPlayer, probes = UnitIsPlayer, 0
            UnitIsPlayer = function(unit) probes = probes+1; return isPlayer(unit) end
            for i=1,40 do unitEvent('NAME_PLATE_UNIT_ADDED', 'nameplate'..i) end
            assert(probes == 0)
            flushUnits()
            assert(probes >= 40 and probes < 100)
            UnitIsPlayer = isPlayer
            stale()
            assert(not seat.unit and seat.model:IsShown() and not seat.portrait:IsShown())
            assert(seat.model.character == 'Theo Stone' and seat.model.keepOnHide)
            units.nameplate3 = {'Theo', 'Stone'}
            unitEvent('UNIT_NAME_UPDATE', 'nameplate3')
            flushUnits()
            assert(seat.unit == 'nameplate3' and not seat.portrait:IsShown())
            click(w.primary)
            DRE:SelectMainSection('deathroll')
            roll('Mira Summer', 9, 100)
            openGroup()
            assert(w.status:GetText() == 'Theo Stone rolls 1–9')
            assert(w.lastRoll:GetText() == '11.1% chance to roll a 1')
            assert(board.rollBadge.seat == board.seats[1] and board.rollBadge.number:GetText() == '9')
            near(board.angle, 1.5*math.pi/2)
        """)

    def test_detached_players_keep_their_own_appearance_across_roster_and_tab_changes(self):
        self.lua.execute("""
            DRE:SetGroupAppearance('models')
            assert(DRE:AddGroupPlayerFromUnit('target'))
            local theo = board.seats[2]
            units.focus, reject = units.target, true
            units.target = {'Ira', 'Sky'}
            unitEvent('PLAYER_TARGET_CHANGED')
            flushUnits()
            assert(theo.unit == 'focus' and theo.ready and theo.model.character == 'Theo Stone')
            board.frame:Hide()
            board.frame:Show()
            assert(theo.ready and not theo.portrait:IsShown())
            units.focus, reject = nil, false
            unitEvent('PLAYER_FOCUS_CHANGED')
            flushUnits()
            assert(DRE:AddGroupPlayerFromUnit('target'))
            units.target = nil
            unitEvent('PLAYER_TARGET_CHANGED')
            flushUnits()
            assert(theo.ready and theo.model.character == 'Theo Stone')
            local ira = board.seats[3]
            assert(ira.ready and ira.model.character == 'Ira Sky')
            local remove = board.seats[1].portraitButton
            remove:GetScript('OnClick')(remove, 'RightButton')
            assert(board.seats[1] == theo and board.seats[2] == ira)
            DRE:SelectMainSection('deathroll')
            openGroup()
            click(w.primary)
            assert(board.seats[1].model.character == 'Theo Stone' and board.seats[1].ready)
            assert(board.seats[2].model.character == 'Ira Sky' and board.seats[2].ready)
        """)

    def test_focus_loss_during_loading_keeps_portrait_and_rejects_late_model(self):
        self.lua.execute("""
            DRE:SetGroupAppearance('models')
            delayed = true
            units.focus = {'Arlo','Strand'}
            w.nameInput:SetText('Arlo Strand')
            w.nameInput:Fire('OnEnterPressed')
            local seat = board.seats[2]
            local late = assert(seat.model:GetScript('OnModelLoaded'))
            units.focus = {'Cora','Oak'}
            unitEvent('PLAYER_FOCUS_CHANGED')
            flushUnits()
            late()
            assert(not seat.unit and not seat.ready and not seat.model:IsShown())
            assert(seat.portrait:IsShown() and seat.portrait.character == 'Arlo Strand')
            seat.portraitButton:GetScript('OnClick')(seat.portraitButton, 'RightButton')
            delayed = false
            w.nameInput:SetText('Cora Oak')
            w.nameInput:Fire('OnEnterPressed')
            late()
            local replacement = board.seats[2]
            assert(replacement.ready and replacement.model.character == 'Cora Oak')
            if seat ~= replacement then
                local fade = assert(seat:GetScript('OnUpdate'))
                fade(seat, 0.28)
                late()
                assert(not seat.ready and not seat:IsShown() and replacement.ready)
            end
        """)

    def test_stand_in_is_stable_and_yields_to_a_real_player(self):
        self.lua.execute("""
            edit({'Mira Summer','Arlo Strand'})
            local seat = board.seats[2]
            local avatar = DRE:SetStandInPortrait(seat.portrait, 'Arlo Strand')
            assert(avatar == DRE:SetStandInPortrait(seat.portrait, 'arlo strand'))
            assert(seat.standIn and not seat.unit)
            local old = assert(seat.model:GetScript('OnModelLoaded'))
            old()
            assert(seat.ready and not seat.portrait:IsShown())
            delayed = true
            units.party1 = {'Arlo','Strand'}
            unitEvent('GROUP_ROSTER_UPDATE')
            flushUnits()
            assert(seat.unit == 'party1' and not seat.standIn and not seat.ready)
            old()
            assert(seat.portrait:IsShown() and seat.portrait.character == 'Arlo Strand')
            seat.model:GetScript('OnModelLoaded')()
            assert(seat.ready and seat.model.character == 'Arlo Strand')
        """)

    def test_appearance_switch_preserves_inflight_arrow_and_marks_only_current_roller(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone','Arlo Strand','Fia Day'})
            local me, theo = board.seats[1], board.seats[2]
            local mask = assert(theo.portrait.mask)
            assert(me.portrait.mask and board.seats[3].portrait.mask)
            local ring = board.turnRing
            function ring:SetAllPoints(seat) self.anchor = seat end
            assert(not ring:IsShown() and me.ready and theo.ready)
            assert(me.portrait.character == 'Mira Summer' and theo.portrait.character == 'Theo Stone')
            DRE:SetupOptions()
            local option = settingsOptions.args.interface.args.groupAppearance
            assert(option.get() == 'portraits')
            click(w.primary)
            assert(ring:IsShown() and ring.anchor == me)
            local round = DRE.groupRound
            roll('Mira Summer', 37, 100)
            local update = assert(board.frame:GetScript('OnUpdate'))
            update(board.frame, 0.08)
            local angle, dest = board.angle, board.destination
            assert(ring.seat == theo and angle > math.pi/4 and angle < dest)
            option.set(nil, 'models')
            assert(theo.model:IsShown() and not theo.portrait:IsShown())
            assert(board.seats[3].standIn and board.seats[3].portrait:IsShown())
            near(board.angle, angle)
            near(board.elapsed, 0.08)
            near(board.destination, dest)
            assert(board.frame:GetScript('OnUpdate') == update and ring.seat == theo)
            update(board.frame, 0.08)
            near(board.angle, math.pi/2)
            option.set(nil, 'portraits')
            assert(theo.model:IsShown() and theo.cornerCover:IsShown() and theo.model.zoom == 1)
            assert(theo.portrait.mask == mask)
            near(board.angle, math.pi/2)
            near(board.elapsed, 0.16)
            update(board.frame, 0.16)
            near(board.angle, 3*math.pi/4)
            assert(not board.frame:GetScript('OnUpdate') and ring.anchor == theo)
            near(math.sin(board.angle)*board.radius, theo.x)
            near(math.cos(board.angle)*board.radius, theo.y)
            assert(DRE.groupRound == round and round.turn == 2 and round.currentRoll == 37 and round.rollCount == 1)

            -- Change the preference through the addon's Settings tab too.
            DRE:SelectMainSection('settings')
            local function findAppearance(parent)
                for _, child in ipairs(parent.children) do
                    if child.kind == 'DRETableDropdown' and child:GetValue() == 'portraits' then return child end
                    local found = findAppearance(child)
                    if found then return found end
                end
            end
            local dropdown = assert(findAppearance(DRE.UI.settingsContent))
            dropdown:Fire('OnValueChanged','models')
            assert(option.get() == 'models' and DRE.db.profile.ui.groupAppearance == 'models')
            openGroup()
            near(board.angle, dest)
            assert(board.turnRing.seat == board.seats[2] and board.seats[2].model:IsShown())
            roll('Theo Stone', 1, 37)
            assert(round.loser == 'Theo Stone' and not board.turnRing:IsShown())
            click(w.primary)
            assert(board.turnRing:IsShown() and board.turnRing.seat == board.seats[1])
            click(w.secondary)
            assert(not board.turnRing:IsShown())
        """)

    def test_portrait_mode_ignores_late_model_and_keeps_detached_face(self):
        self.lua.execute("""
            delayed = true
            assert(DRE:AddGroupPlayerFromUnit('target'))
            local seat = board.seats[2]
            DRE:SetGroupAppearance('models')
            local late = assert(seat.model:GetScript('OnModelLoaded'))
            DRE:SetGroupAppearance('flat')
            units.target = nil
            unitEvent('PLAYER_TARGET_CHANGED')
            flushUnits()
            late()
            assert(not seat.ready and not seat.model:IsShown() and not seat.model:GetScript('OnModelLoaded'))
            assert(seat.portrait:IsShown() and seat.portrait.character == 'Theo Stone')
            DRE:SetGroupAppearance('models')
            assert(seat.portrait:IsShown() and not seat.model:IsShown())
            units.focus, delayed = {'Theo','Stone'}, false
            unitEvent('PLAYER_FOCUS_CHANGED')
            flushUnits()
            assert(seat.ready and seat.model.character == 'Theo Stone' and not seat.portrait:IsShown())
        """)

    def test_group_face_portraits_bind_native_models_across_form_and_mode_changes(self):
        self.lua.execute("""
            units.party1 = {'Bench','Shrek'}
            forms = {target = 'Cat Form', party1 = 'Ghost Wolf'}
            edit({'Mira Summer','Theo Stone','Bench Shrek'})
            local me, druid, shaman = unpack(board.seats)
            assert(druid.model.appearance == 'Theo Stone' and shaman.model.appearance == 'Bench Shrek')
            assert(me.model.appearance == 'Mira Summer' and me.model.zoom == 1)
            DRE:SetGroupAppearance('models')
            assert(druid.model.appearance == 'Cat Form' and shaman.model.appearance == 'Ghost Wolf')
            delayed = true
            DRE:SetGroupAppearance('portraits')
            local stale = assert(druid.model:GetScript('OnModelLoaded'))
            forms.target = 'Bear Form'
            unitEvent('UNIT_MODEL_CHANGED','target')
            flushUnits()
            stale()
            assert(not druid.ready and druid.portrait:IsShown())
            druid.model:GetScript('OnModelLoaded')()
            shaman.model:GetScript('OnModelLoaded')()
            assert(druid.ready and druid.model.appearance == 'Theo Stone' and druid.model.zoom == 1)
            assert(shaman.ready and shaman.model.appearance == 'Bench Shrek')
            units.target = nil
            unitEvent('PLAYER_TARGET_CHANGED')
            flushUnits()
            DRE:SetGroupAppearance('models')
            assert(not druid.model:IsShown() and druid.portrait:IsShown())
            units.focus, forms.focus, delayed = {'Theo','Stone'}, 'Bear Form', false
            unitEvent('PLAYER_FOCUS_CHANGED')
            flushUnits()
            assert(druid.ready and druid.model:IsShown() and druid.model.appearance == 'Bear Form')
        """)

    def test_seven_player_closeups_and_name_lines_follow_the_sweep(self):
        self.lua.execute("""
            units.party1 = {'Arlo','Strand'}
            units.party2 = {'Fia','Day'}
            units.party3 = {'Ira','Sky'}
            units.party4 = {'Jo','Lake'}
            edit({'Mira Summer','Theo Stone','Arlo Strand','Fia Day','Ira Sky','Jo Lake','Kim Hill'})
            assert(board.seats[7].portrait:IsShown() and board.seats[7].standIn)
            for i = 1, 6 do
                local seat = board.seats[i]
                assert(seat.ready and seat.cornerCover:IsShown())
                near(seat.model.zoom, 1)
                assert(math.abs(seat.model.rotation) <= math.rad(15))
                if math.abs(seat.x) > 0.001 then
                    assert(seat.model.rotation * seat.x < 0)
                end
                near(seat.model.width, seat.width - 4)
            end
            near(board.seats[4].model.rotation, 0)
            near(board.seats[2].model.rotation, -board.seats[6].model.rotation)
            assert(math.abs(board.seats[2].model.rotation) > math.rad(12))
            assert(math.abs(board.seats[1].model.rotation) < math.abs(board.seats[2].model.rotation))
            for _, ring in ipairs({board.turnRing,board.trailingRing}) do
                for _, line in ipairs(ring.strokes) do
                    function line:SetAlpha(alpha) self.opacity = alpha end
                    function line:SetStartPoint(_, seat) self.start = seat end
                    function line:SetEndPoint(side, label, dx) self.edge,self.label,self.dx = side,label,dx end
                end
            end
            local function verify(ring, seat, alpha)
                for _, line in ipairs(ring.strokes) do
                    assert(line:IsShown() and line.start == seat and line.label == seat.nameLabel)
                    assert(line.edge == seat.labelEdge and line.dx == (line.edge == 'LEFT' and -3 or 3))
                    near(line.opacity, alpha)
                end
                near(ring:GetAlpha(), alpha)
            end
            click(w.primary)
            verify(board.turnRing, board.seats[1], 1)
            roll('Mira Summer',37,100)
            local tick = board.frame:GetScript('OnUpdate')
            tick(board.frame,0.16)
            verify(board.trailingRing,board.seats[1],0.5)
            verify(board.turnRing,board.seats[2],0.5)
            DRE:SetGroupAppearance('models')
            assert(board.seats[2].model.zoom == 0.22 and not board.seats[2].cornerCover:IsShown())
            DRE:SetGroupAppearance('portraits')
            tick(board.frame,0.16)
            verify(board.turnRing,board.seats[2],1)
            assert(not board.trailingRing.lineCore:IsShown())
            roll('Theo Stone',1,37)
            assert(not board.turnRing.lineCore:IsShown() and not board.turnRing.lineGlow:IsShown())
        """)

    def test_local_portrait_faces_inward_with_an_off_center_camera_on_either_side(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone'})
            local me, other = board.seats[1], board.seats[2]
            local function loadCamera(seat, bearing)
                local model = seat.model
                function model:SetPosition(x,y,z) self.offset = {x,y,z} end
                function model:GetCameraTarget() return 0.2, -0.4, 1.7 end
                function model:GetCameraPosition()
                    return 0.2 + 2*math.cos(bearing), -0.4 + 2*math.sin(bearing), 1.8
                end
                model:GetScript('OnModelLoaded')()
                local c, s = math.cos(model.rotation), math.sin(model.rotation)
                near(c*0.2 - s*(-0.4) + model.offset[1], 0.2)
                near(s*0.2 + c*(-0.4) + model.offset[2], -0.4)
            end
            local dwarfCamera, orcCamera = math.rad(-28), math.rad(-8)
            loadCamera(me,dwarfCamera)
            loadCamera(other,orcCamera)
            near(me.model.rotation-dwarfCamera, -math.rad(15))
            near(other.model.rotation-orcCamera, math.rad(15))
            board:Present({'Theo Stone','Mira Summer'}, nil)
            assert(board.seats[2] == me)
            near(me.model.rotation-dwarfCamera, math.rad(15))
            near(other.model.rotation-orcCamera, -math.rad(15))
            DRE:SetGroupAppearance('models')
            near(me.model.rotation, 0.35)
            near(me.model.offset[1], 0)
            near(me.model.offset[2], 0)
            DRE:SetGroupAppearance('portraits')
            near(me.model.rotation-dwarfCamera, math.rad(15))
        """)

    def test_portrait_corners_sample_the_table_after_resize_and_roster_changes(self):
        self.lua.execute("""
            edit({'Mira Summer'})
            local seat = board.seats[1]
            local cover = seat.cornerCover
            local felt = cover.felt
            assert(seat.model.modelLayer == 'BACKGROUND' and cover:GetFrameLevel() > seat.model:GetFrameLevel())
            assert(felt.mask == cover.mask)
            for _, tex in ipairs({felt, cover.mask}) do
                function tex:SetTexCoord(l,r,t,b) self.uv = {l,r,t,b} end
            end
            function board.felt:SetSize(w,h) self.span = w end
            for _, count in ipairs({5,40}) do
                local names = {'Mira Summer','Theo Stone'}
                for i=3,count do names[i] = 'Player '..string.rep('a', i) end
                board:Present(names, nil)
                assert(board.seats[1] == seat)
                for _, width in ipairs({428,511.5,580}) do
                    board:OnWidthSet(width)
                    assert(felt:IsShown())
                    local l,r,t,b = unpack(felt.uv)
                    local span = board.felt.span
                    near((r-l)*span, seat.width)
                    near((b-t)*span, seat.height)
                    local left,right,top,bottom = unpack(cover.mask.uv)
                    assert(left < 0 and top < 0 and right > 1 and bottom > 1)
                    near(seat.width/(right-left), seat.model.width)
                    near(seat.height/(bottom-top), seat.model.height)
                    near((left+right)/2, 0.5)
                    near((top+bottom)/2, 0.5)
                    near(((l+r)/2-0.5)*span, seat.x)
                    near((0.5-(t+b)/2)*span, seat.y)
                end
            end
            board:Present({'Mira Summer'}, nil)
            near((felt.uv[2]-felt.uv[1])*board.felt.span, seat.width)
        """)

    def test_setup_fields_share_the_footer_and_only_the_board_scrolls(self):
        self.lua.execute("""
            local footer = DRE.UI.tableFooter
            edit({'Mira Summer','Theo Stone'})
            local form = w.form
            assert(#w.pane.children == 1 and w.pane.children[1] == board)
            assert(#footer.children == 3 and footer.children[1] == form)
            assert(footer.children[2] == w.primary and footer.children[3] == w.shuffle)
            w.initialRoll:Fire('OnTextChanged','500')
            assert(w.form == form and w.primary:GetText() == 'Start  1–500')
            click(w.primary)
            assert(not w.form and footer.children[1] == w.primary)
            click(w.secondary)
            click(w.secondary)
            assert(footer.children[1] == w.form and footer.children[3] == w.shuffle)
            assert(#w.pane.children == 1 and w.pane.children[1] == board)
            DRE:SelectMainSection('deathroll')
            assert(footer:GetHeight() == 44)
        """)

    def test_roster_motion_retargets_from_visible_seats_and_stops_on_hide(self):
        self.lua.execute("""
            local function tick(dt)
                local update = board.motion:GetScript('OnUpdate')
                assert(update)
                update(board.motion, dt)
            end
            local function add(name)
                w.nameInput:SetText(name)
                w.nameInput:Fire('OnEnterPressed')
            end
            add('Theo Stone')
            local me, theo = board.seats[1], board.seats[2]
            near(theo:GetAlpha(), 0)
            tick(0.14)
            near(theo:GetAlpha(), 0.5)
            add('Arlo Strand')
            local startX, startY = me.drawX, me.drawY
            near(theo:GetAlpha(), 0.5)
            tick(0.08)
            assert(me.drawY > startY and me.drawY < me.y)
            local visibleX, visibleY, radius = me.drawX, me.drawY, board.radius
            add('Fia Day')
            near(me.drawX, visibleX); near(me.drawY, visibleY); near(board.radius, radius)
            tick(0.14)
            local mid = board.radius
            tick(0.14)
            assert(mid < radius and board.radius < mid)
            assert(not me.drawX and not board.motion:GetScript('OnUpdate'))
            local remove = board.seats[4].portraitButton
            local leaving = board.seats[4]
            remove:GetScript('OnClick')(remove, 'RightButton')
            assert(#board.players == 3)
            assert(leaving:IsShown() and not remove:IsShown() and leaving.name == 'Fia Day')
            tick(0.06)
            leaving:GetScript('OnUpdate')(leaving, 0.14)
            near(leaving:GetAlpha(), 0.5)
            board.frame:Hide()
            assert(not leaving:IsShown() and not leaving.name and not leaving:GetScript('OnUpdate'))
            assert(not board.motion:GetScript('OnUpdate') and not me.drawX)
            board.frame:Show()
            click(w.primary)
            assert(DRE.groupRound.players[1] == 'Mira Summer' and me:GetAlpha() == 1)
        """)

    def test_readding_the_last_player_during_the_exit_reclaims_the_portrait(self):
        self.lua.execute("""
            local me = board.seats[1]
            local button = me.portraitButton
            button:GetScript('OnClick')(button, 'RightButton')
            assert(#board.players == 0 and w.primary.disabled and me:IsShown() and not button:IsShown())
            local exitStep = assert(me:GetScript('OnUpdate'))
            exitStep(me, 0.14)
            near(me:GetAlpha(), 0.5)
            assert(DRE:AddGroupPlayerFromUnit('player'))
            assert(#board.players == 1 and board.seats[1] == me and button:IsShown())
            assert(not me:GetScript('OnUpdate'))
            near(me:GetAlpha(), 0.5)
            board.motion:GetScript('OnUpdate')(board.motion, 0.28)
            near(me:GetAlpha(), 1)
            assert(me.name == 'Mira Summer' and me.ready)
        """)

    def test_group_phase_eases_visible_viewport_and_keeps_rolls_interactive(self):
        self.lua.execute("""
            local content = DRE.UI.mainWindow.content
            local anchors = {}
            function content:SetPoint(point, relative, edge, x, y) anchors[point] = y end
            function content:GetTop()
                return (DRE.UI.tableHero.groupBelow and 500 or 400) + (anchors.TOPLEFT or -12)
            end
            function content:GetBottom()
                return (DRE.UI.tableHero.groupBelow and 80 or 160) + (anchors.BOTTOMRIGHT or 8)
            end
            function content:SetAlpha(value) self.opacity = value end
            local function tick(dt)
                for _, f in ipairs(frames) do
                    local update = f:GetScript('OnUpdate')
                    if update and f:IsVisible() then update(f,dt) end
                end
            end
            edit({'Mira Summer','Theo Stone'})
            w.mode:Fire('OnValueChanged','twoLives')
            tick(0.3)
            local top, bottom = content:GetTop(), content:GetBottom()
            click(w.primary)
            near(content:GetTop(), top); near(content:GetBottom(), bottom)
            tick(0.14)
            assert(content:GetTop() > top and content:GetTop() < 454)
            assert(content:GetBottom() < bottom and content:GetBottom() > 84)
            local alpha = content.opacity
            roll('Mira Summer', 50, 100)
            assert(DRE.groupRound.turn == 2 and content.opacity == alpha)
            click(w.secondary)
            local intermediate = content:GetTop()
            click(w.secondary)
            near(content:GetTop(), intermediate)
            tick(0.3)
            near(content:GetTop(), top); near(content:GetBottom(), bottom); near(content.opacity, 1)
            w.mode:Fire('OnValueChanged','classic')
            DRE:SelectMainSection('deathroll')
            near(content.opacity, 1)
        """)

    def test_group_tracks_native_viewport_height_without_a_window_resize(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone'})
            local viewport = CreateFrame('Frame',nil,w.pane.frame)
            viewport:SetSize(1000, 320)
            w.pane.scrollframe = viewport
            board:WatchViewport(w.pane)
            local watcher
            for _, f in ipairs(frames) do
                if f.parent == board.frame and f:GetScript('OnSizeChanged') and f:GetScript('OnShow') then watcher = f end
            end
            watcher:GetScript('OnUpdate')(watcher,0)
            local small = board.radius
            click(w.primary)
            viewport:SetSize(1000, 680)
            watcher:GetScript('OnSizeChanged')(watcher,1000,680)
            watcher:GetScript('OnUpdate')(watcher,0)
            assert(board.viewportHeight == 680 and board.radius > small * 1.9)
            viewport:SetSize(1000, 280)
            watcher:GetScript('OnSizeChanged')(watcher,1000,280)
            DRE:SelectMainSection('deathroll')
            assert(not watcher:GetScript('OnUpdate'))
        """)

    def test_board_scales_with_both_viewport_dimensions_in_setup_and_play(self):
        self.lua.execute("""
            board.parent = w.pane
            function board.coin:SetSize(width) self.span = width end
            function board.felt:SetSize(width) self.span = width end
            for _, count in ipairs({2, 6}) do
                local names = {'Mira Summer', 'Theo Stone', 'Eda Moon', 'Ari Rose', 'Jill Bay', 'Ren Moss'}
                while #names > count do table.remove(names) end
                edit(names)
                local label = board.seats[1].nameLabel
                function label:SetFont(path, size, flags)
                    assert(path == 'font' and flags == '')
                    self.fontSize = size
                end
                for phase = 1,2 do
                    if phase == 2 then click(w.primary) end
                    w.pane.frame:SetHeight(540)
                    board:OnWidthSet(760)
                    local normalSize = label.fontSize
                    local radius, diameter, coin, span, hand = board.radius, board.seats[1].width,
                        board.coin.span, board.felt.span, board.handLength
                    w.pane.frame:SetHeight(1080)
                    board:OnWidthSet(1520)
                    assert(label.fontSize > normalSize)
                    assert(board.radius > 1.9*radius and board.seats[1].width > 1.9*diameter)
                    assert(board.coin.span > 1.9*coin and board.felt.span > 1.9*span and board.handLength > 1.9*hand)
                    assert(board.felt.span < 1080 and board:GetHeight() <= 1080)
                    w.pane.frame:SetHeight(245)
                    board:OnWidthSet(1520)
                    assert(label.fontSize <= normalSize and label.fontSize >= board.seats[1].baseNameSize)
                    assert(board.felt.span < 245 and board:GetHeight() <= 245)
                end
                click(w.secondary)
                click(w.secondary)
            end
        """)

    def test_solo_draft_reserves_the_hosts_seat_and_table(self):
        self.lua.execute("""
            local me = board.seats[1]
            assert(me.unit == 'player' and #board.players == 1 and w.primary.disabled)
            function board.coin:SetSize(w,h) self.size=w end
            board:OnWidthSet(510)
            assert(board.felt:IsShown() and board.coin:IsShown() and not board.hand:IsShown())
            local span, x, y, diameter, height, coin = me.feltSize, me.x, me.y, me.width, board:GetHeight(), board.coin.size
            near(x, board.radius)
            assert(x > 0 and coin > 0 and not board.turnRing:IsShown())
            assert(DRE:AddGroupPlayerFromUnit('target'))
            assert(board.seats[1] == me and not w.primary.disabled and board.hand:IsShown())
            near(me.x,x); near(me.y,y); near(me.width,diameter)
            near(me.feltSize,span); near(board:GetHeight(),height); near(board.coin.size,coin)
            board:Present({},nil)
            assert(not board.felt:IsShown() and not board.coin:IsShown() and not board.hand:IsShown())
        """)

    def test_cuff_emerges_from_the_coin_without_exposing_its_cut_edge(self):
        self.lua.execute("""
            edit({'Mira Summer','Theo Stone'})
            board.parent = w.pane
            w.pane.frame:SetHeight(600)
            function board.coin:SetSize(w,h) self.width = w end
            function board.hand:SetTexCoord(...) self.uv = {...} end
            for _, width in ipairs({600, 320}) do
                board:OnWidthSet(width)
                if width == 600 then assert(board.coin.width > 88) end
                local rim = board.coin.width * 0.45
                -- At the east-facing seat, U runs down the screen and V runs left.
                local uv = board.hand.uv
                local function radiusAt(px, py)
                    local x = ((py/256-uv[2])/(uv[6]-uv[2])-0.5)*2*board.handLength
                    local y = ((px/256-uv[1])/(uv[3]-uv[1])-0.5)*2*board.handLength
                    return math.sqrt(x*x + y*y)
                end
                assert(radiusAt(112,109) < rim and radiusAt(157,109) < rim)
                assert(radiusAt(128,84) > rim + 0.05 * board.handLength)
                local gap = board.radius - board.seats[1].width/2 - radiusAt(126,4)
                assert(gap > 2 and gap < 5)
            end
        """)

    def test_spinner_texture_points_to_seats_and_shares_glow_timing(self):
        self.lua.execute("""
            assert(not board.hand:IsShown() and board.coin:IsShown() and board.felt:IsShown())
            function board.hand:SetTexCoord(...) self.uv = {...} end
            for _, tex in ipairs({board.hand, board.coin, board.felt}) do
                function tex:SetSize(w,h) self.width, self.height = w,h end
            end
            edit({'Mira Summer','Theo Stone','Arlo Strand','Fia Day'})
            click(w.primary)
            assert(board.felt.width >= 2*board.radius)
            local rimRadius = board.coin.width * 0.45 -- opaque radius of the logo texture
            assert(rimRadius > 0.36 * board.handLength and rimRadius < 0.65 * board.handLength)
            assert(board.hand:IsShown() and board.hand.width == 2*board.handLength)
            local function verifyTip(angle)
                -- Sample near the tip in screen space. Its texture coordinates must
                -- land near the north edge of the artwork at the same radius.
                local u = board.hand.uv
                local x,y = 0.5+0.4925*math.sin(angle), 0.5-0.4925*math.cos(angle)
                near(u[1]+x*(u[5]-u[1])+y*(u[3]-u[1]), 0.5)
                near(u[2]+x*(u[6]-u[2])+y*(u[4]-u[2]), 4/256)
            end
            for i, name in ipairs(board.players) do
                local start = (i-0.5)*math.pi/2
                verifyTip(start)
                roll(name, 17, i == 1 and 100 or 17)
                local sweep = assert(board.frame:GetScript('OnUpdate'))
                sweep(board.frame, 0.16)
                verifyTip(start + math.pi/4)
                near(board.turnRing:GetAlpha(), 0.5)
                near(board.trailingRing:GetAlpha(), 0.5)
                sweep(board.frame, 0.16)
                verifyTip(start + math.pi/2)
                assert(board.turnRing.seat == board.seats[i%4+1] and not board.trailingRing:IsShown())
            end
            roll(board.players[1], 1, 17)
            assert(not board.hand:IsShown() and board.coin:IsShown() and board.felt:IsShown())
        """)

    def test_glow_tracks_arrow_through_interrupted_sweep_wrap_and_hide(self):
        self.lua.execute("""
            edit({'Mira Summer', 'Theo Stone', 'Arlo Strand'})
            local function glow(index)
                for _, ring in ipairs({board.turnRing, board.trailingRing}) do
                    if ring:IsShown() and ring.seat == board.seats[index] then return ring:GetAlpha() end
                end
                return 0
            end
            local function expect(a, b, c)
                near(glow(1), a); near(glow(2), b); near(glow(3), c)
            end
            local function tick(dt) board.frame:GetScript('OnUpdate')(board.frame, dt) end
            expect(0, 0, 0)
            click(w.primary)
            expect(1, 0, 0)
            roll('Mira Summer', 37, 100)
            expect(1, 0, 0)
            tick(0.08)
            expect(0.84375, 0.15625, 0)
            tick(0.08)
            expect(0.5, 0.5, 0)
            roll('Theo Stone', 20, 37)
            DRE:SetGroupAppearance('models')
            DRE:RefreshGroupUI()
            expect(0.5, 0.5, 0)
            tick(0.16)
            expect(0, 0.75, 0.25)
            tick(0.16)
            expect(0, 0, 1)
            roll('Arlo Strand', 8, 20)
            tick(0.16)
            expect(0.5, 0, 0.5)
            board.frame:Hide()
            expect(0, 0, 0)
            board.frame:Show()
            expect(1, 0, 0)
            assert(not board.frame:GetScript('OnUpdate'))
            roll('Mira Summer', 3, 8)
            tick(0.16)
            roll('Theo Stone', 1, 3)
            expect(0, 0, 0)
            assert(not board.frame:GetScript('OnUpdate'))
        """)

    def test_three_seat_summary_at_normal_and_narrow_widths(self):
        self.lua.execute("""
            edit({'Mira Summer', 'Theo Stone', 'Eration Rageclaw'})
            for _, width in ipairs({512, 444}) do
                if w.phase == 'result' then click(w.secondary) end
                board.parent = w.pane
                w.pane.frame:SetHeight(220)
                board:OnWidthSet(width)
                assert(board.handLength >= 19 and board.seats[1].nameLabel:GetWidth() < 2*board.seats[1].x)
                w.initialRoll:Fire('OnTextChanged', '999999')
                assert(w.primary:GetText() == 'Start  1–999999')
                click(w.primary)
                assert(w.status:GetText() == 'Mira Summer rolls 1–999999')
                assert(w.lastRoll:GetText() == DRE:FormatRollOneChance(999999)..' chance to roll a 1' and w.lastRoll:IsShown())
                roll('Mira Summer', 37, 999999)
                assert(w.status:GetText() == 'Theo Stone rolls 1–37')
                assert(w.lastRoll:GetText() == '2.7% chance to roll a 1')
                roll('Theo Stone', 1, 37)
                assert(w.status:GetText() == 'Theo Stone rolled 1 and loses')
                assert(w.lastRoll:GetText() == 'Settle payouts manually.' and not board.hand:IsShown())
            end
        """)

    def test_all_supported_roster_sizes_keep_seats_and_names_separate(self):
        self.lua.execute("""
            local names = {'Player a'}
            for count = 2, 40 do
                names[count] = 'Player '..string.rep('a', count)
                edit(names)
                board:OnWidthSet(428)
                local update = board.motion:GetScript('OnUpdate')
                if update then update(board.motion, 0.28) end
                assert(#board.players == count)
                for i, name in ipairs(names) do
                    local seat = board.seats[i]
                    local neighbor = board.seats[i%count+1]
                    near(math.sqrt(seat.x^2 + seat.y^2), board.radius)
                    local dx = math.max(0, math.abs(seat.x) - seat.width/2)
                    local dy = math.max(0, math.abs(seat.y) - seat.width/2)
                    assert(board.handLength + 2.49 < math.sqrt(dx*dx + dy*dy))
                    assert(math.max(math.abs(seat.x-neighbor.x), math.abs(seat.y-neighbor.y)) > seat.width)
                    assert(seat.nameLabel:GetText() == name and seat:IsShown())
                    if count > 3 and i < count and i ~= math.ceil(count/2) then
                        assert(math.abs(seat.labelY - neighbor.labelY) >= seat.nameLabel:GetStringHeight())
                    end
                end
            end
            edit({'Mira Summer','Theo Stone'})
            for i = 3, #board.seats do
                local seat = board.seats[i]
                local fade = seat:GetScript('OnUpdate')
                if fade then fade(seat, 0.28) end
            end
            assert(board.seats[2]:IsShown() and not board.seats[3]:IsShown())
            assert(not board.seats[40].lead:IsShown())
        """)
