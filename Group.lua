-- Host-controlled group rounds. Outcomes never create 1v1 results or trade debts.
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
local AceGUI = LibStub("AceGUI-3.0")
local channels = { NONE = "None", SAY = "Say (nearby)", PARTY = "Party", RAID = "Raid", INSTANCE_CHAT = "Instance" }
local channelOrder = {"NONE", "SAY", "PARTY", "RAID", "INSTANCE_CHAT"}
local startText = "Group DeathRoll: first 1 loses; payouts manual. Turn %d/%d: %s, /roll %d. Stay near the host."
local turnText = "Group DeathRoll: turn %d/%d - %s, /roll %d."
local finishText = "Group DeathRoll: %s rolled 1 and loses. Round finished; settle payouts manually."
local sayReminder = "Click Announce to send the current turn or result to Say."
local modes = {classic = "Classic", elimination = "Elimination", hotPotato = "Hot Potato", twoLives = "Two Lives", teams = "Teams"}
local modeOrder = {"classic", "elimination", "hotPotato", "twoLives", "teams"}
if DRE.devDuel then
    modes.highRoller = "High Roller"
    modeOrder[#modeOrder + 1] = "highRoller"
    DRE.groupModes, DRE.groupModeOrder = modes, modeOrder
end
local modeRules = {
    classic = "Take turns in order. Each roll sets the next player's maximum. The first player to roll 1 loses.",
    elimination = "Roll 1 and you're out. The next player restarts at the opening roll. Last player standing wins.",
    hotPotato = "A safe roll passes to a random other player. First roll of 1 loses.",
    twoLives = "Each 1 costs a life and resets the roll. Lose both lives and you're out. Last player standing wins.",
    teams = "Gold and Crimson take turns. A 1 knocks you out and resets the roll. Last team standing wins.",
    highRoller = "Everyone rolls once. Highest roll earns a point. Only players tied for highest reroll. First to 2 points wins.",
}
local teamNames = {"Gold", "Crimson"}

-- Keep teams with the players when the host shuffles or edits the roster.
-- Fill open seats on the smaller side, with Gold first on a tie.
local function assignTeams(players, previous)
    local teams, counts = {}, {0, 0}
    for _, name in ipairs(players) do
        local team = previous and previous[name]
        if team then
            teams[name] = team
            counts[team] = counts[team] + 1
        end
    end
    for _, name in ipairs(players) do
        if not teams[name] then
            local team = counts[1] <= counts[2] and 1 or 2
            teams[name] = team
            counts[team] = counts[team] + 1
        end
    end
    return teams, counts
end

local function lostRound(round, seat)
    if round.mode == "highRoller" then return round.players[seat] ~= round.winner end
    if round.winningTeam then return round.teams[round.players[seat]] ~= round.winningTeam end
    return round.eliminated[seat]
end

DRE.groupAppearances = {models = "3D Models", portraits = "3D Face Portraits", flat = "Portraits"}
DRE.groupAppearanceOrder = {"models", "portraits", "flat"}

function DRE:GetGroupAppearance()
    local value = self.db.profile.ui.groupAppearance
    return self.groupAppearances[value] and value or "portraits"
end

function DRE:IsGroupRoundActive()
    return self.groupRound ~= nil and self.groupRound.status == "active"
end

function DRE:HasActiveGame()
    return self:IsGroupGuest() or self.outgoingChallenge ~= nil or self:IsGroupRoundActive() or (self.gameState and self.gameState.isActive)
        or (self.spicyDuel and self.spicyDuel.isActive) or false
end

function DRE:IsGroupGuest()
    return self.sharedTable ~= nil and self.sharedTable.role == "guest"
end

function DRE:GetGroupDraft()
    if not self.groupDraft then
        local preferred = self.db.profile.ui.groupAnnounceChannel
        self.groupDraft = { roster = self:GetUnitPlayerName("player") or "",
            initialRoll = tostring(self:GetDefaultStartingRoll()), channel = channels[preferred] and preferred or "NONE", mode = "classic" }
    end
    return self.groupDraft
end

local function selectGroupChannel(_, _, value)
    if not channels[value] or DRE:IsGroupRoundActive() or DRE:IsGroupGuest() then return end
    DRE.db.profile.ui.groupAnnounceChannel = value
    DRE:GetGroupDraft().channel = value
    DRE:RefreshGroupUI()
end

-- Compare normalized full names, keeping the roster's spelling for labels and announcements.
local function sameRosterName(first, second)
    if not first or not second then return false end
    if strcmputf8i then return strcmputf8i(first, second) == 0 end
    return first:lower() == second:lower()
end

local function findRosterSeat(players, name)
    if not name then return end
    for index, player in ipairs(players) do
        if sameRosterName(player, name) then return index end
    end
end

local function hostKey()
    return DRE.db.keys and DRE.db.keys.char or DRE:GetTradeOwnerGUID()
end

function DRE:GetHostedGroupStats()
    local records = self.db.profile.hostedGroupStats
    return records and records[hostKey()]
end

local function newGroupStats()
    return {played = 0, losses = 0, escapes = 0, regulars = {}}
end

local function addHostedMatch(stats, round)
    if round.hostSeat then
        stats.played = stats.played + 1
        if lostRound(round, round.hostSeat) then stats.losses = stats.losses + 1 end
        stats.escapes = stats.escapes + (round.escapes or 0)
    end
    for index, name in ipairs(round.players) do
        local key = (strlower or string.lower)(name)
        local row = stats.regulars[key]
        -- A bytewise lowercase can leave accented capitals unchanged. Use
        -- the same client comparison as turn validation for these names.
        if not row and name:find("[\128-\255]") then
            for _, other in pairs(stats.regulars) do
                if sameRosterName(name, other.name) then row = other; break end
            end
        end
        if not row then
            row = {name = name, played = 0, losses = 0}
            stats.regulars[key] = row
        end
        row.played = row.played + 1
        if lostRound(round, index) then row.losses = row.losses + 1 end
    end
    if not stats.longest or round.rollCount > stats.longest.rolls then
        stats.longest = {rolls = round.rollCount, seats = #round.players, opening = round.initialRoll}
    end
end

local function recordFinishedRound(round)
    if not round.host then return end
    local profile = DRE.db.profile
    profile.hostedGroupStats = profile.hostedGroupStats or {}
    local stats = profile.hostedGroupStats[round.host] or newGroupStats()
    profile.hostedGroupStats[round.host] = stats
    addHostedMatch(stats, round)
    -- Older host totals have no mode information and stay in the overall record.
    stats.byMode = stats.byMode or {}
    local mode = stats.byMode[round.mode] or newGroupStats()
    stats.byMode[round.mode] = mode
    addHostedMatch(mode, round)
    local seat = round.hostSeat
    if seat and round.points then
        mode.points = (mode.points or 0) + round.points[seat]
        mode.tiebreaks = (mode.tiebreaks or 0) + (round.hostTiebreaks or 0)
        mode.tiebreakWins = (mode.tiebreakWins or 0) + (round.hostTiebreakWins or 0)
    elseif seat and round.lives and round.winner == round.players[seat] then
        if round.lives[seat] == 2 then mode.flawless = (mode.flawless or 0) + 1 end
        if round.firstLifeLost == seat then mode.comebacks = (mode.comebacks or 0) + 1 end
    end
    if DRE.UI.currentTab == "statistics" and DRE.UI.statsView == "group" then DRE:UpdateStatsDisplay() end
end

local function parseRoster(self, text, minimum)
    if not self:IsAccessibleValue(text) or type(text) ~= "string" or #text > 12000 then
        return nil, "Enter up to 40 full player names, one per line."
    end
    local players = {}
    for line in text:gmatch("[^\r\n]+") do
        local trimmed = self:Trim(line)
        if trimmed ~= "" then
            local name = self:NormalizePlayerName(trimmed)
            if not name then return nil, "Invalid player name on line " .. (#players + 1) .. "." end
            if findRosterSeat(players, name) then return nil, "Duplicate player: " .. name end
            if #string.format(startText, 40, 40, name, self.MAX_ROLL) > 255
                or #string.format(finishText, name) > 255 then
                return nil, "Player name is too long for a group announcement."
            end
            players[#players + 1] = name
            if #players > 40 then return nil, "A group round supports at most 40 players." end
        end
    end
    if #players < minimum then return nil, "Add at least two different players." end
    return players
end

function DRE:ParseGroupRoster(text, draft)
    return parseRoster(self, text, draft and 0 or 2)
end

function DRE:GetSharedGroupView()
    local draft, round = self:GetGroupDraft(), self.groupRound
    if round and not draft.editing then return round.players, round.mode, round.initialRoll, round.teams, round.channel, round end
    local players = self:ParseGroupRoster(draft.roster, true) or {}
    if draft.mode == "teams" then draft.teams = assignTeams(players, draft.teams) end
    return players, draft.mode, tonumber(draft.initialRoll) or 0, draft.teams, draft.channel
end

function DRE:ShuffleGroupOrder()
    if self.disabled or self:HasActiveGame() then return false end
    local draft = self:GetGroupDraft()
    if self.devDuel and self.groupRound and not draft.editing then return false end
    local players, reason = self:ParseGroupRoster(draft.roster)
    if not players then self:Print(reason); return false end
    for i = #players, 2, -1 do
        local j = math.random(i)
        players[i], players[j] = players[j], players[i]
    end
    draft.roster = table.concat(players, "\n")
    local widgets = self.UI.groupWidgets
    if widgets and widgets.roster then widgets.roster:SetText(draft.roster) end
    self:RefreshGroupUI()
    return true
end

function DRE:AddGroupLog(round, text)
    round.log[#round.log + 1] = text
    if #round.log > 20 then table.remove(round.log, 1) end
end

local function groupResult(round)
    if round.winningTeam then return "Team " .. teamNames[round.winningTeam] .. " wins" end
    if round.winner then return round.winner .. " wins " .. modes[round.mode] end
    if round.loser then return round.loser .. " rolled 1 and loses" end
    return "Round cancelled"
end

local function lastOneText(round)
    if round.lives and round.lives[round.lastSeat] == 1 then return round.lastPlayer .. " has one life left" end
    return round.lastPlayer .. " is out"
end

local function livesText(lives)
    return lives == 1 and "1 life" or lives .. " lives"
end

local function highRollerPhase(round)
    return "Round " .. round.scoringRound .. (round.tiebreak and " tiebreak" or "")
end

function DRE:GetGroupAnnouncement(round, starting)
    if round.status == "cancelled" then return "Group DeathRoll cancelled by the host. No result or payment recorded." end
    if round.mode == "classic" then
        if round.loser then return string.format(finishText, round.loser) end
        return string.format(starting and startText or turnText, round.turn, #round.players, round.players[round.turn], round.currentRoll)
    end
    if round.mode == "highRoller" then
        if round.winner then return "High Roller: " .. round.winner .. " wins with 2 points!" end
        local turn = string.format("%s: %s, /roll %d.", highRollerPhase(round), round.players[round.turn], round.initialRoll)
        local detail = starting and modeRules.highRoller or round.pointResult
        if detail and #detail + #turn + 14 <= 255 then return "High Roller: " .. detail .. " " .. turn end
        return "High Roller: " .. turn
    end
    if round.winner then return modes[round.mode] .. ": " .. round.winner .. " is the last player standing and wins!" end
    if round.status == "finished" then return modes[round.mode] .. ": " .. groupResult(round) .. "!" end
    local actor = round.players[round.turn]
    if round.mode == "teams" then actor = teamNames[round.teams[actor]] .. " team: " .. actor end
    if round.lives then actor = actor .. " (" .. livesText(round.lives[round.turn]) .. ")" end
    local turn = string.format("%s, /roll %d.", actor, round.currentRoll)
    if round.mode ~= "hotPotato" then turn = round.remaining .. " players left. " .. turn end
    local prefix = modes[round.mode] .. ": "
    local detail = starting and modeRules[round.mode] or round.lastRoll == 1 and (lastOneText(round) .. ".")
    if detail and #prefix + #detail + 1 + #turn <= 255 then return prefix .. detail .. " " .. turn end
    return prefix .. turn
end

function DRE:AnnounceGroupRound(starting, automatic)
    if self:IsGroupGuest() then return false end
    local round = self.groupRound
    if not round or self.disabled or round.channel == "NONE" or self:GetGroupDraft().channel ~= round.channel then return false end
    -- SAY can require a hardware event. System-roll callbacks have none.
    if automatic and round.channel == "SAY" then
        round.chatError = sayReminder
        self:RefreshGroupUI()
        return false
    end
    -- Recheck channel membership, but never silently switch the round's audience.
    local channel, _, reason = self:ResolveStatsBroadcastChannel(round.channel, true)
    local message = self:GetGroupAnnouncement(round, starting)
    local sent = false
    if channel == round.channel and #message <= 255 then
        sent, reason = self:SendChatSafely(message, channel)
    elseif channel then
        reason = "The round's chat channel changed. Cancel and select the correct channel."
    end
    round.chatError = not sent and (reason or "Chat unavailable.") or nil
    if not sent then
        self:Print("Group announcement could not be sent. Use Announce to retry: " .. (round.chatError or ""))
    end
    -- A successful API call is not confirmation of delivery; local state is authoritative.
    self:RefreshGroupUI()
    return sent == true
end

function DRE:ProtectGroupTradeWagers(players)
    local count = 0
    local ownerGUID = self:GetTradeOwnerGUID()
    for _, pending in ipairs(self.db.profile.pendingTradeWagers or {}) do
        local name = self:NormalizePlayerName(pending.playerName)
        if ownerGUID and pending.ownerGUID == ownerGUID and findRosterSeat(players, name) then
            pending.manualAssignmentRequired = true
            count = count + 1
        end
    end
    return count
end

function DRE:StartGroupRound(rosterText, initialRoll, channelHint, mode, previousTeams)
    if self:IsGroupGuest() then return false, "Only the table host can start a round." end
    if self.disabled then return false, "The addon is disabled." end
    if self:HasActiveGame() then return false, "Finish or cancel the active game first." end
    local players, reason = self:ParseGroupRoster(rosterText)
    if not players then return false, reason end
    mode = mode or "classic"
    if not modes[mode] then return false, "Choose a group mode from the list." end
    local teams, counts
    if mode == "teams" then
        teams, counts = assignTeams(players, previousTeams or self:GetGroupDraft().teams)
        if counts[1] == 0 or counts[2] == 0 then return false, "Each team needs at least one player." end
    end
    if not self:IsBoundedInteger(initialRoll, 2, self.MAX_ROLL) then
        return false, "Starting roll must be a whole number from 2 to 999,999."
    end
    local channel = channelHint
    if channel == nil then channel = self:GetGroupDraft().channel end
    if not channels[channel] then return false, "Choose a destination from Announce to." end
    if channel ~= "NONE" then
        local resolved, _, reason = self:ResolveStatsBroadcastChannel(channel, true)
        if not resolved then return false, reason end
        if resolved ~= channel then return false, "That channel is unavailable here. Select Raid or Instance explicitly." end
    end

    -- A new round owns a separate roster and never reuses observed 1v1 challenges.
    self.pendingChallenge, self.acceptedChallenge = nil, nil
    if self.activeDialog and self.activeDialog.definition == self.Dialogs.DEATHROLL_CHALLENGE_POPUP then
        self:CloseDialog(self.activeDialog, false, "override")
    end
    self.recentRolls = {}
    self.UI.recentTargetRoll, self.UI.incomingChallenge = nil, nil
    -- Existing 1v1 debts and later group payouts cannot be distinguished by trade APIs.
    -- Keep the debts, but require explicit assignment for these participants across reloads.
    local manualCount = self:ProtectGroupTradeWagers(players)
    if manualCount > 0 then
        self:Print("Earlier unpaid 1v1 games with these players now require /dr edit to assign payments. Group payouts will not update them automatically.")
    end
    self.groupRound = { status = "active", players = players, initialRoll = initialRoll,
        currentRoll = initialRoll, turn = 1, rollCount = 0, seatSteps = 0, channel = channel, log = {},
        mode = mode, eliminated = {}, remaining = #players }
    if mode == "twoLives" then
        self.groupRound.lives = {}
        for i = 1, #players do self.groupRound.lives[i] = 2 end
    elseif mode == "highRoller" then
        self.groupRound.points = {}
        for i = 1, #players do self.groupRound.points[i] = 0 end
        self.groupRound.scoringRound = 1
    elseif mode == "teams" then
        self.groupRound.teams, self.groupRound.teamRemaining = teams, counts
        self.groupRound.lastTeamSeat = {0, 0}
    end
    if self.devDuel then
        self.groupRound.host = hostKey()
        self.groupRound.hostSeat = findRosterSeat(players, self:GetUnitPlayerName("player"))
    end
    local draftTeams = self:GetGroupDraft().teams
    if self.devDuel and teams then draftTeams = assignTeams(players, teams) end
    self.groupDraft = { roster = table.concat(players, "\n"),
        initialRoll = tostring(self:GetDefaultStartingRoll()), channel = channel, mode = mode, teams = draftTeams }
    local widgets = self.UI.groupWidgets
    if widgets and widgets.roster then
        widgets.roster:SetText(self.groupDraft.roster)
        widgets.initialRoll:SetText(self.groupDraft.initialRoll)
        widgets.channel:SetValue(channel)
        widgets.mode:SetValue(mode)
    end
    self:AddGroupLog(self.groupRound, modeRules[mode])
    if sameRosterName(players[1], self:GetUnitPlayerName("player")) then self:PlayTurnSound() end
    self:AnnounceGroupRound(true)
    if channel ~= "NONE" then self:Print(self:GetGroupAnnouncement(self.groupRound, true)) end
    self:RefreshGroupUI()
    return true
end

local function nextGroupSeat(round)
    local current, count = round.turn, #round.players
    local nextSeat = current
    if round.mode == "hotPotato" then
        nextSeat = (current - 1 + math.random(count - 1)) % count + 1
    elseif round.mode == "teams" then
        local team = round.teams[round.players[current]]
        round.lastTeamSeat[team] = current
        local other = 3 - team
        nextSeat = round.lastTeamSeat[other]
        repeat nextSeat = nextSeat % count + 1
        until round.teams[round.players[nextSeat]] == other and not round.eliminated[nextSeat]
    else
        repeat nextSeat = nextSeat % count + 1 until not round.eliminated[nextSeat]
    end
    return nextSeat
end

local function handleGroupOne(round)
    local seat = round.turn
    if round.mode ~= "classic" and round.mode ~= "hotPotato" then round.currentRoll = round.initialRoll end
    if round.lives then
        round.firstLifeLost = round.firstLifeLost or seat
        round.lives[seat] = round.lives[seat] - 1
        if round.lives[seat] > 0 then return end
    end
    round.eliminated[seat] = true
    round.remaining = round.remaining - 1
    if round.mode == "classic" or round.mode == "hotPotato" then
        round.status, round.loser = "finished", round.players[seat]
    elseif round.mode == "teams" then
        local team = round.teams[round.players[seat]]
        round.teamRemaining[team] = round.teamRemaining[team] - 1
        if round.teamRemaining[team] == 0 then
            round.status, round.winningTeam = "finished", 3 - team
        end
    end
end

local function scoreHighRoll(round, roll)
    round.pointResult = nil
    if roll > (round.highFace or 0) then
        round.highFace, round.highSeats = roll, {round.turn}
    elseif roll == round.highFace then
        table.insert(round.highSeats, round.turn)
    end
    if round.tiebreak then
        -- High seats were collected in roster order, including on repeated ties.
        for _, seat in ipairs(round.tiebreak) do
            if seat > round.turn then return seat end
        end
    elseif round.turn < #round.players then
        return round.turn + 1
    end

    local nextSeat = 1
    if #round.highSeats == 1 then
        local seat = round.highSeats[1]
        local player = round.players[seat]
        round.points[seat] = round.points[seat] + 1
        round.pointResult = player .. " scores with " .. round.highFace .. "."
        if round.tiebreak and seat == round.hostSeat then round.hostTiebreakWins = (round.hostTiebreakWins or 0) + 1 end
        round.tiebreak = nil
        if round.points[seat] == 2 then round.status, round.winner = "finished", player
        else round.scoringRound = round.scoringRound + 1 end
    else
        if not round.tiebreak and round.hostSeat then
            for _, seat in ipairs(round.highSeats) do
                if seat == round.hostSeat then
                    round.hostTiebreaks = (round.hostTiebreaks or 0) + 1
                    break
                end
            end
        end
        round.tiebreak = round.highSeats
        nextSeat = round.tiebreak[1]
        round.pointResult = string.format("Tied at %d. Only the %d tied players reroll.", round.highFace, #round.tiebreak)
    end
    DRE:AddGroupLog(round, round.pointResult)
    round.highFace, round.highSeats = nil, nil
    return nextSeat
end

function DRE:HandleGroupRoll(playerName, roll, maximum)
    if self:IsGroupGuest() then return false end
    local round = self.groupRound
    if self.disabled or not self:IsGroupRoundActive() then return false end
    local name = self:NormalizePlayerName(playerName)
    if not sameRosterName(name, round.players[round.turn]) then return false end
    if not self:IsBoundedInteger(maximum, 1, self.MAX_ROLL) or maximum ~= round.currentRoll
        or not self:IsBoundedInteger(roll, 1, maximum) then return false end
    round.pendingRoll = nil
    round.rollCount = round.rollCount + 1
    round.lastPlayer, round.lastRoll, round.lastSeat = name, roll, round.turn
    self:AddGroupLog(round, string.format("%s: %d (1-%d)", name, roll, maximum))
    local nextSeat
    if round.mode == "highRoller" then
        nextSeat = scoreHighRoll(round, roll)
    elseif roll == 1 then
        handleGroupOne(round)
        self:AddGroupLog(round, lastOneText(round) .. ".")
    else
        if maximum == 2 and round.hostSeat == round.turn then round.escapes = (round.escapes or 0) + 1 end
        round.currentRoll = roll
    end
    if round.status == "active" then
        nextSeat = nextSeat or nextGroupSeat(round)
        round.seatSteps = round.seatSteps + (nextSeat - round.turn) % #round.players
        round.turn = nextSeat
        if round.remaining == 1 then
            round.status, round.winner = "finished", round.players[round.turn]
        elseif sameRosterName(round.players[round.turn], self:GetUnitPlayerName("player")) then
            self:PlayTurnSound()
        end
    end
    if round.status == "finished" then
        self:AddGroupLog(round, groupResult(round) .. ".")
        recordFinishedRound(round)
    end
    if round.channel ~= "NONE" then self:Print(self:GetGroupAnnouncement(round)) end
    self:AnnounceGroupRound(false, true)
    self:RefreshGroupUI()
    local widgets = self.UI.groupWidgets
    local board = widgets and widgets.circle
    if board and board.round == round and board.frame:IsVisible() then board:AnimateRollBadge() end
    return true
end

function DRE:CancelGroupRound(quiet)
    if self:IsGroupGuest() then return false end
    if not self:IsGroupRoundActive() then return false end
    local round = self.groupRound
    round.status, round.pendingRoll = "cancelled", nil
    self:AddGroupLog(round, "Cancelled. No result or payment recorded.")
    if not quiet and round.channel ~= "NONE" then
        self:Print(self:GetGroupAnnouncement(round))
        self:AnnounceGroupRound()
    end
    self:RefreshGroupUI()
    return true
end

function DRE:RestartGroupRound()
    local round = self.groupRound
    if not round then return false, "No group round to restart." end
    return self:StartGroupRound(table.concat(round.players, "\n"), round.initialRoll, self:GetGroupDraft().channel, round.mode, round.teams)
end

function DRE:RollGroupTurn()
    local round = self.groupRound
    if self.disabled or not self:IsGroupRoundActive() or round.pendingRoll or (self:IsGroupGuest() and not self:SharedHostOnline())
        or not sameRosterName(round.players[round.turn], self:GetUnitPlayerName("player")) then return false end
    local request, turnNumber = {}, round.rollCount
    round.pendingRoll = request
    -- Called directly by the host's button or slash command; never auto-roll another player.
    local ok, reason = pcall(RandomRoll, 1, round.currentRoll)
    if not ok then
        round.pendingRoll = nil
        self:Print("Unable to roll: " .. tostring(reason))
    else
        C_Timer.After(3.2, function()
            if self.disabled or self.groupRound ~= round or round.status ~= "active"
                or round.rollCount ~= turnNumber or round.pendingRoll ~= request then return end
            round.pendingRoll = nil
            self:RefreshGroupUI()
        end)
    end
    self:RefreshGroupUI()
    return ok
end

local function addDraftPlayer(self, name)
    if self:IsGroupRoundActive() or self:IsGroupGuest() then return false end
    if not name or not name:find("%S") or name:find("[\r\n]") then return false end
    local draft = self:GetGroupDraft()
    local players, reason = parseRoster(self, draft.roster .. "\n" .. name, 0)
    if not players then self:Print(reason); return false end
    draft.roster = table.concat(players, "\n")
    self:RefreshGroupUI()
    return true
end

function DRE:AddGroupPlayerFromUnit(unit)
    if self:IsGroupRoundActive() then return false end
    if not UnitIsPlayer(unit) then self:Print("Select a player to add."); return false end
    local name = self:GetUnitPlayerName(unit)
    if self.devDuel then return addDraftPlayer(self, name) end
    if not name then return false end
    local draft = self:GetGroupDraft()
    for line in draft.roster:gmatch("[^\r\n]+") do
        if sameRosterName(self:NormalizePlayerName(line), name) then self:Print("That player is already in the roster."); return false end
    end
    draft.roster = draft.roster == "" and name or (draft.roster .. "\n" .. name)
    local widgets = self.UI.groupWidgets
    if widgets then widgets.roster:SetText(draft.roster) end
    return true
end

function DRE:GroupCommand(command, name)
    if self.SharedTableCommand and self:SharedTableCommand(command, name) then return end
    if command == "cancel" then
        if not self:CancelGroupRound() then self:Print("No active group round.") end
    elseif command == "roll" then
        if not self:RollGroupTurn() then self:Print("It is not your group turn, or a roll is pending.") end
    elseif command == "announce" then
        self:AnnounceGroupRound()
    elseif command == "restart" then
        local ok, reason = self:RestartGroupRound()
        if not ok then self:Print(reason) end
    elseif not command or command == "" then
        self:ShowMainWindow("group")
    else
        self:Print(self.groupMessagesEnabled and "Usage: /dr group [host|join Full Host Name|leave|cancel|roll|announce|restart]"
            or "Usage: /dr group [cancel|roll|announce|restart]")
    end
end

local tau = 2 * math.pi
local maxPortraitTurn = math.rad(15)
local feltTexture = "Interface\\AddOns\\DeathRollEnhancer\\Media\\GroupFeltTable"
local rimTexture = "Interface\\AddOns\\DeathRollEnhancer\\Media\\GroupSeatRim"
local cornerTexture = "Interface\\AddOns\\DeathRollEnhancer\\Media\\GroupPortraitCorners"
local portraitInset = 2
local forestBackdrop = {normal = {0.07, 0.21, 0.15}, active = {0.11, 0.32, 0.21}, dim = {0.045, 0.12, 0.09}}
local teamBackdrops = {
    {normal = {0.38, 0.28, 0.12}, active = {0.51, 0.37, 0.16}, dim = {0.23, 0.17, 0.08}},
    {normal = {0.32, 0.13, 0.17}, active = {0.46, 0.17, 0.23}, dim = {0.20, 0.08, 0.11}},
}
local teamColors = {{1, 0.77, 0.28}, {1, 0.19, 0.30}}
local turnColor = {0.47, 1, 0.66}
local portraitRingScale = 1.23
local glowTexture = "Interface\\AddOns\\DeathRollEnhancer\\Media\\GroupTurnGlow"
local gold, ivory, red = {0.94, 0.73, 0.45}, {0.93, 0.89, 0.83}, {1, 0.47, 0.41}
local unitTokens = {"player"}
for i = 1, 4 do unitTokens[#unitTokens + 1] = "party" .. i end
for i = 1, 40 do unitTokens[#unitTokens + 1] = "raid" .. i end
unitTokens[#unitTokens + 1] = "target"
unitTokens[#unitTokens + 1] = "focus"
for i = 1, 40 do unitTokens[#unitTokens + 1] = "nameplate" .. i end

function DRE:FindVisiblePlayerUnit(name, excludedUnit)
    for _, unit in ipairs(unitTokens) do
        local player = UnitIsPlayer(unit)
        if unit ~= excludedUnit and self:IsAccessibleValue(player) and player and self:IsSamePlayer(self:GetUnitPlayerName(unit), name) then
            return unit
        end
    end
end

local function stroke(frame, layer, width, color, alpha)
    local line = frame:CreateLine(nil, layer)
    line:SetThickness(width)
    line:SetColorTexture(color[1], color[2], color[3], alpha)
    return line
end

-- The felt and rim are drawn again over the corners of a 3D portrait.
-- Use the same fractional coordinates for both copies at every UI scale.
local function alignArt(texture)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
end

local function maskPortrait(frame, texture)
    local mask = frame:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

local function portraitButton(board, seat)
    local button = CreateFrame("Button", nil, seat)
    button:SetFrameLevel(seat:GetFrameLevel() + 3)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(glowTexture)
    ring:SetDesaturated(true)
    ring:SetVertexColor(unpack(turnColor))
    ring:SetPoint("CENTER")
    button.ring = ring
    local outline = button:CreateTexture(nil, "ARTWORK")
    outline:SetAllPoints()
    maskPortrait(button, outline)
    local opening = button:CreateMaskTexture()
    opening:SetTexture(cornerTexture, "CLAMP", "CLAMP")
    opening:SetAllPoints()
    opening:SetTexCoord(-0.015, 1.015, -0.015, 1.015)
    outline:AddMaskTexture(opening)
    button.outline = outline
    button:SetScript("OnSizeChanged", function(_, width) ring:SetSize(width * portraitRingScale, width * portraitRingScale) end)
    button:SetAllPoints(seat)
    local function tooltip()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(seat.name)
        if seat.team then GameTooltip:AddLine(teamNames[seat.team] .. " team", unpack(teamColors[seat.team])) end
        if not board.round and not DRE:HasActiveGame() then
            if seat.team then GameTooltip:AddLine("Left-click to move to " .. teamNames[3 - seat.team] .. ".") end
            GameTooltip:AddLine("Right-click to remove from the table.")
        end
        GameTooltip:Show()
    end
    button:SetScript("OnEnter", tooltip)
    local function hideTooltip()
        if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end
    button:SetScript("OnLeave", hideTooltip)
    button:SetScript("OnHide", hideTooltip)
    button:SetScript("OnClick", function(_, mouseButton)
        if board.round or DRE:HasActiveGame() or not seat:IsShown() then return end
        local draft = DRE:GetGroupDraft()
        if mouseButton == "RightButton" then
            local players = {}
            for _, name in ipairs(board.players) do
                if name ~= seat.name then players[#players + 1] = name end
            end
            hideTooltip()
            draft.roster = table.concat(players, "\n")
            DRE:RefreshGroupUI()
        elseif mouseButton == "LeftButton" and seat.team then
            draft.teams[seat.name] = 3 - seat.team
            DRE:RefreshGroupUI()
            if GameTooltip:IsOwned(button) then tooltip() end
        end
    end)
    return button
end

local function newSeat(board)
    local seat = CreateFrame("Frame", nil, board.frame)
    local rim = seat:CreateTexture(nil, "BACKGROUND")
    rim:SetTexture(rimTexture)
    alignArt(rim)
    rim:SetAllPoints()
    -- The face can be hidden during a roll without clearing its loaded model.
    seat.face = CreateFrame("Frame", nil, seat)
    seat.face:SetAllPoints()
    seat.portrait = seat.face:CreateTexture(nil, "ARTWORK")
    seat.portrait:SetPoint("TOPLEFT", portraitInset, -portraitInset)
    seat.portrait:SetPoint("BOTTOMRIGHT", -portraitInset, portraitInset)
    maskPortrait(seat.face, seat.portrait)
    seat.backing = seat:CreateTexture(nil, "BORDER")
    seat.backing:SetAllPoints(seat.portrait)
    maskPortrait(seat, seat.backing)
    seat.nameLabel = seat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    seat.nameFont, seat.baseNameSize, seat.nameFlags = seat.nameLabel:GetFont()
    seat.nameLabel:SetNonSpaceWrap(true)
    seat.lead = stroke(board.frame, "BACKGROUND", 1, gold, 0.42)
    seat.portraitButton = portraitButton(board, seat)
    return seat
end

function DRE.GroupUnitMatches(unit, name)
    local player = UnitIsPlayer(unit)
    return DRE:IsAccessibleValue(player) and player and sameRosterName(DRE:GetUnitPlayerName(unit), name)
end

-- A PlayerModel has a rectangular viewport. Redraw the board and seat rim
-- only in its four corners so the face can use the entire portrait opening.
local function createCornerCover(seat, model)
    local cover = CreateFrame("Frame", nil, model)
    -- These corners replace the pixels behind the rectangular model. Keep them
    -- opaque even when the face, seat or the whole table is fading.
    cover:SetIgnoreParentAlpha(true)
    cover:SetFrameLevel(model:GetFrameLevel() + 1)
    cover:SetAllPoints(seat)
    local mask = cover:CreateMaskTexture()
    mask:SetTexture(cornerTexture, "CLAMP", "CLAMP")
    mask:SetAllPoints()
    alignArt(mask)
    cover.mask = mask
    -- The felt asset includes the opaque board color. A single sample replaces
    -- the model without darkening the board twice at a fractional pixel edge.
    local felt = cover:CreateTexture(nil, "BORDER")
    felt:SetTexture(feltTexture, "CLAMP", "CLAMP")
    felt:SetAllPoints()
    alignArt(felt)
    felt:AddMaskTexture(mask)
    cover.felt = felt
    local rim = cover:CreateTexture(nil, "ARTWORK")
    rim:SetTexture(rimTexture)
    rim:SetAllPoints(seat)
    alignArt(rim)
    rim:AddMaskTexture(mask)
    cover.rim = rim
    return cover
end

local function applyGroupCamera(seat)
    local model, facing = seat.model, seat.facing
    model:SetPosition(0, 0, 0)
    if seat.zoom == 1 and model.ZeroCachedCenterXY then model:ZeroCachedCenterXY() end
    model:SetPortraitZoom(seat.zoom)
    if seat.zoom == 1 then
        -- Portrait cameras can look at a head from one side. Measure the
        -- unrotated camera bearing before applying this seat's inward tilt.
        model:SetRotation(0, false)
        local x, y = model:GetCameraPosition()
        local tx, ty = model:GetCameraTarget()
        if x and y and tx and ty and (x ~= tx or y ~= ty) then
            facing = facing + math.atan2(y - ty, x - tx)
            -- Turn about the authored face target. Rotating an offset head about
            -- the model origin alone swings it sideways within the circular crop.
            local c, s = math.cos(facing), math.sin(facing)
            model:SetPosition(tx - (c*tx - s*ty), ty - (s*tx + c*ty), 0)
        end
    end
    model:SetRotation(facing, false)
end

local function sampleSeatFelt(seat, x, y)
    local span = seat.feltSize
    local u, v, half = 0.5 + x/span, 0.5 - y/span, seat:GetWidth()/(2*span)
    seat.cornerCover.felt:SetTexCoord(u-half, u+half, v-half, v+half)
end

local function frameSeatModel(seat, appearance)
    local model = seat.model
    if not model or not seat.fullFacing then return end
    local close = appearance == "portraits"
    local facing = close and seat.portraitFacing or seat.fullFacing
    local zoom = close and 1 or 0.22
    local diameter = seat:GetWidth()
    local size = math.max(1, diameter - 2 * portraitInset)
    model:SetSize(size, size)
    seat.cornerCover:SetShown(close)
    if close then
        -- Overscan the rectangular viewport up to the seat bounds, while
        -- keeping the transparent opening at the original portrait diameter.
        local pad = (diameter/size - 1)/2
        seat.cornerCover.mask:SetTexCoord(-pad, 1+pad, -pad, 1+pad)
        sampleSeatFelt(seat, seat.drawX or seat.x, seat.drawY or seat.y)
    end
    if seat.zoom ~= zoom or seat.facing ~= facing then
        seat.zoom, seat.facing = zoom, facing
        if seat.ready then applyGroupCamera(seat) end
    end
end

local function bindSeats(board, force)
    local units = {}
    local appearance = DRE:GetGroupAppearance()
    board.bound = {}
    for _, unit in ipairs(unitTokens) do
        local player = UnitIsPlayer(unit)
        if DRE:IsAccessibleValue(player) and player then
            local name = DRE:GetUnitPlayerName(unit)
            local index = findRosterSeat(board.players, name)
            if index and not units[index] then units[index] = unit end
        end
    end
    for i, name in ipairs(board.players) do
        local seat, unit = board.seats[i], units[i]
        if appearance ~= "flat" and unit and not seat.triedModel then
            seat.triedModel = true
            local ok, model = pcall(CreateFrame, "PlayerModel", nil, seat.face)
            if ok and model then
                seat.model = model
                seat.applyCamera = applyGroupCamera
                model:SetModelDrawLayer("BACKGROUND")
                model:SetKeepModelOnHide(true)
                model:SetPoint("CENTER")
                model:EnableMouse(false)
                model:Hide()
                seat.cornerCover = createCornerCover(seat, model)
            end
        end
        frameSeatModel(seat, appearance)
        if unit then board.bound[unit] = seat end
        DRE.BindGroupSeat(seat, name, unit, (seat.rejoined or (force and not seat.ready)) and unit)
        seat.rejoined = nil
    end
end

function DRE:SetGroupAppearance(value)
    if not self.groupAppearances[value] then return end
    self.db.profile.ui.groupAppearance = value
    local widgets = self.UI.groupWidgets
    if widgets and widgets.circle then bindSeats(widgets.circle) end
end

local function newTurnRing(frame)
    local ring = CreateFrame("Frame", nil, frame)
    ring:EnableMouse(false)
    ring:Hide()
    local halo = ring:CreateTexture(nil, "OVERLAY")
    halo:SetTexture(glowTexture)
    halo:SetDesaturated(true)
    halo:SetVertexColor(unpack(turnColor))
    halo:SetPoint("CENTER")
    ring.halo = halo
    -- Keep both strokes below the seats, even when a line starts behind a model.
    ring.lineGlow = stroke(frame, "BORDER", 5, forestBackdrop.active, 0.4)
    ring.lineCore = stroke(frame, "BORDER", 2, turnColor, 0.98)
    ring.strokes = {ring.lineGlow, ring.lineCore}
    ring.lineGlow:Hide()
    ring.lineCore:Hide()
    ring:SetScript("OnSizeChanged", function(_, width)
        halo:SetSize(width * portraitRingScale, width * portraitRingScale)
    end)
    return ring
end

local function lightSeat(ring, seat, alpha)
    if not seat or alpha == 0 then
        if ring.seat then
            ring:Hide()
            ring.lineGlow:Hide()
            ring.lineCore:Hide()
            ring.seat = nil
        end
        return
    end
    local moved = ring.seat ~= seat
    if moved then
        ring:ClearAllPoints()
        ring:SetAllPoints(seat)
        ring:SetFrameLevel(seat:GetFrameLevel() + 3)
        ring.seat = seat
        ring:Show()
    end
    local edge = seat.labelEdge
    if moved or ring.lineEdge ~= edge then
        ring.lineEdge = edge
        for _, line in ipairs(ring.strokes) do
            line:SetShown(edge ~= nil)
            if edge then
                line:SetStartPoint("CENTER", seat, 0, 0)
                line:SetEndPoint(edge, seat.nameLabel, edge == "LEFT" and -3 or 3, 0)
            end
        end
    end
    ring.lineCore:SetAlpha(alpha)
    ring.lineGlow:SetAlpha(alpha)
    ring:SetAlpha(alpha)
end

local function clearTurnLights(board)
    lightSeat(board.turnRing, nil, 0)
    lightSeat(board.trailingRing, nil, 0)
end

local function drawSpinner(board, angle)
    board.angle = angle
    local handUVRadius, handUVCenterY = board.handUVRadius, board.handUVCenterY
    local c, s = math.cos(angle) * handUVRadius, math.sin(angle) * handUVRadius
    local a, b = c + s, c - s
    board.hand:SetTexCoord(0.5-a, handUVCenterY-b, 0.5-b, handUVCenterY+a,
                           0.5+b, handUVCenterY-a, 0.5+a, handUVCenterY+b)
    if board.round and board.round.status == "active" then
        -- The displayed angle already includes easing and any interrupted sweep.
        local count = #board.players
        local position = angle / tau * count - 0.5
        local nearest = math.floor(position + 0.5)
        if math.abs(position - nearest) < 0.000001 then position = nearest end
        local ahead = math.ceil(position)
        local trailing = ahead - position
        local nextSeat, previousSeat = ahead % count + 1, (ahead - 1) % count + 1
        local out = board.round.eliminated
        lightSeat(board.turnRing, board.seats[nextSeat], out[nextSeat] and 0 or 1 - trailing)
        lightSeat(board.trailingRing, board.seats[previousSeat], out[previousSeat] and 0 or trailing)
    else
        clearTurnLights(board)
    end
end

local function sweep(frame, elapsed)
    local board = frame.obj
    board.elapsed = board.elapsed + elapsed
    local t = math.min(1, board.elapsed / 0.32)
    drawSpinner(board, board.origin + (board.destination - board.origin) * t*t*(3 - 2*t))
    if t == 1 then frame:SetScript("OnUpdate", nil) end
end

local function updateRollBadge(board)
    local badge, round = board.rollBadge, board.round
    local seat = round and round.status ~= "cancelled" and round.lastSeat and board.seats[round.lastSeat]
    badge.seat = seat or nil
    badge:SetShown(not not seat)
    if not seat then return end
    badge.number:SetText(tostring(round.lastRoll))
    local textWidth = badge.number:GetStringWidth()
    badge:SetWidth(math.max(badge:GetHeight(), textWidth + badge.padding))
    -- Size the reveal against the live portrait, including when resized mid-roll.
    local diameter = seat:GetWidth()
    badge.startScale = math.min(diameter * 0.38 / math.max(1, badge.number:GetStringHeight()),
                                diameter * 0.9 / math.max(1, textWidth))
    badge:SetFrameLevel(seat:GetFrameLevel() + 5)
    badge.caption:SetFrameLevel(badge.plate:GetFrameLevel() + 1)
    badge:ClearAllPoints()
    if board.badgeInLabel then
        local right = seat.labelEdge == "LEFT"
        badge:SetPoint(right and "RIGHT" or "LEFT", seat.nameLabel, seat.labelEdge, right and -3 or 3, 0)
    else
        badge:SetPoint("BOTTOM", seat, "BOTTOM", 0, 1)
    end
end

local function setFaceAlpha(seat, alpha)
    seat.face:SetAlpha(alpha)
    seat.face:SetShown(alpha > 0)
    if seat.model and seat.model.SetModelAlpha then seat.model:SetModelAlpha(alpha) end
end

local function settleRollBadge(badge)
    if not badge.rollingSeat then return end
    badge:SetScript("OnUpdate", nil)
    setFaceAlpha(badge.rollingSeat, badge.rollingSeat.faceAlpha)
    badge.rollingSeat = nil
    badge.plate:SetAlpha(1)
    badge.caption:SetScale(1)
    badge.caption:ClearAllPoints()
    badge.caption:SetPoint("CENTER")
end

local function animateRollBadge(badge, elapsed)
    badge.elapsed = badge.elapsed + elapsed
    local seat = badge.rollingSeat
    local t = math.max(0, (badge.elapsed - 1) / 0.3)
    if t >= 1 or seat ~= badge.seat then settleRollBadge(badge); return end
    t = t*t*(3 - 2*t)
    -- Both centers are in board units. Sample the live anchors so a resize or
    -- a badge beside a crowded name column gets the same continuous landing.
    local sx, sy = seat:GetCenter()
    local bx, by = badge:GetCenter()
    if not sx or not bx then settleRollBadge(badge); return end
    local scale = 1 + (badge.startScale - 1) * (1 - t)
    badge.caption:SetScale(scale)
    badge.caption:ClearAllPoints()
    badge.caption:SetPoint("CENTER", badge, "CENTER", (sx-bx)*(1-t)/scale, (sy-by)*(1-t)/scale)
    setFaceAlpha(seat, t * seat.faceAlpha)
    badge.plate:SetAlpha(t)
end

-- Keep the logical order current while portraits move around the rim in setup.
local function moveDraftSeats(board, progress)
    local t = progress * progress * (3 - 2 * progress)
    for _, move in ipairs(board.seatMoves) do
        local seat = move.seat
        if move.entering then
            seat:SetAlpha(move.alpha + (1 - move.alpha) * t)
        else
            local radius = move.radius + (board.radius - move.radius) * t
            local angle = move.angle + move.travel * t
            local x, y = radius * math.sin(angle), radius * math.cos(angle)
            if progress == 1 then x, y = seat.x, seat.y end
            seat:SetPoint("CENTER", board.frame, "CENTER", x, y)
            seat.drawX, seat.drawY = x, y
            if seat.cornerCover and seat.cornerCover:IsShown() then sampleSeatFelt(seat, x, y) end
        end
        if progress == 1 then seat.drawX, seat.drawY = nil, nil end
    end
    if progress == 1 then
        board.seatMoves = nil
    end
    if not board.round and #board.players >= 2 then
        local first = board.seats[1]
        drawSpinner(board, math.atan2(first.drawX or first.x, first.drawY or first.y))
    end
end

-- Keep the circle round. Each side's names follow its seats from top to bottom.
-- Reserve the measured wrap height of every label, including at raid size.
local function layoutCircle(board, width)
    local count = #board.players
    local viewport = board.viewportHeight or 0
    board.felt:SetShown(count > 0)
    board.coin:SetShown(count > 0)
    if count == 0 then
        updateRollBadge(board)
        board:SetHeight(math.max(1, viewport - 6))
        return
    end
    -- Reserve the second seat in a solo draft so the host and table stay put
    -- when the first opponent joins.
    local layoutCount = math.max(2, count)
    local compact = count <= 3
    local score = board.showScore and board.seats[1].score
    local scoreSpace = score and score:GetHeight() + 2 or 0
    -- Leave side columns for larger rosters. Fit both the felt and the highest
    -- and lowest seats inside the viewport while preserving a round table.
    local seatRatio = math.min(compact and 0.62 or 0.67, math.sqrt(2) * math.sin(math.pi / layoutCount))
    local verticalReach = layoutCount % 2 == 1 and 1 or math.cos(math.pi / layoutCount)
    local radius = width * (compact and 0.36 or 0.26)
    if viewport > 0 then
        radius = math.min(radius, (viewport - 9) / (2 + 0.28*seatRatio),
            (viewport - (compact and 57 or 9) - 2*scoreSpace) / (2*verticalReach + seatRatio))
    end
    radius = math.max(48, radius)
    local diameter = math.min(radius * seatRatio - 1, (radius - 25)*math.sqrt(2))
    -- Each portrait plus its badge must fit between neighboring seats. At raid
    -- density the name columns have more room and already follow each seat.
    local cell = math.sqrt(2) * radius * math.sin(math.pi / layoutCount) - 1
    local scoreInLabel = score and not compact and cell < score:GetWidth() + 2
    if score and not scoreInLabel then diameter = math.min(diameter, cell - scoreSpace) end
    local from = board.reflowFrom
    if from then
        local t = board.motionProgress
        if t == 1 or (math.abs(radius-from.radius) < 0.01 and math.abs(diameter-from.diameter) < 0.01) then
            board.reflowFrom = nil
        else
            local eased = t*t*(3 - 2*t)
            radius = from.radius + (radius-from.radius)*eased
            diameter = from.diameter + (diameter-from.diameter)*eased
        end
    end
    local nearestPortrait = radius
    local gutter = radius + diameter/2 + 9
    local labelScale = math.max(1, radius / 150)
    local badge = board.rollBadge
    if badge.font then
        local size = math.floor(badge.baseFontSize * labelScale + 0.5)
        if badge.fontSize ~= size then
            badge.number:SetFont(badge.font, size, badge.fontFlags)
            badge.fontSize = size
        end
    end
    badge.padding = math.floor(10 * labelScale + 0.5)
    badge:SetHeight(math.floor(18 * labelScale + 0.5))
    board.badgeInLabel = false
    if board.round and not compact then
        local number = badge.number
        number:SetText(tostring(board.round.initialRoll))
        local badgeWidth = math.max(badge:GetHeight(), number:GetStringWidth() + badge.padding)
        board.badgeInLabel = diameter < 24 * labelScale or badgeWidth > diameter
        if board.badgeInLabel then gutter = gutter + badgeWidth + 3 end
    end
    local nameWidth = math.max(24, width/2 - gutter - 5)
    board.radius, board.diameter = radius, diameter
    local tableSize = 2 * (radius + diameter * 0.14)
    board.felt:SetSize(tableSize, tableSize)
    local sides = {{}, {}}
    for i = 1, count do
        local seat = board.seats[i]
        local theta = (i - 0.5) * tau/layoutCount
        local x, y = radius * math.sin(theta), radius * math.cos(theta)
        -- The arm can sweep up to the nearest edge of any square portrait.
        local dx = math.max(0, math.abs(x) - diameter/2)
        local dy = math.max(0, math.abs(y) - diameter/2)
        nearestPortrait = math.min(nearestPortrait, math.sqrt(dx*dx + dy*dy))
        if score and not scoreInLabel then
            local badgeX = math.max(0, math.abs(x) - score:GetWidth()/2)
            local badgeY = math.max(0, math.abs(y + diameter/2 + 2 + score:GetHeight()/2) - score:GetHeight()/2)
            nearestPortrait = math.min(nearestPortrait, math.sqrt(badgeX*badgeX + badgeY*badgeY))
        end
        local right = i <= math.ceil(count/2)
        seat.fullFacing = right and -0.35 or 0.35
        seat.portraitFacing = -maxPortraitTurn * math.sin(theta)
        seat:SetSize(diameter, diameter)
        seat.x, seat.y, seat.feltSize = x, y, tableSize
        frameSeatModel(seat, DRE:GetGroupAppearance())
        seat:ClearAllPoints()
        seat:SetPoint("CENTER", board.frame, "CENTER", x, y)
        if seat.nameFont then
            local size = math.floor(seat.baseNameSize * labelScale + 0.5)
            if seat.nameSize ~= size then
                seat.nameLabel:SetFont(seat.nameFont, size, seat.nameFlags)
                seat.nameSize = size
            end
        end
        seat.lead:SetShown(not compact)
        seat.labelEdge = not compact and (right and "LEFT" or "RIGHT") or nil
        if compact then
            seat.nameLabel:ClearAllPoints()
            local labelWidth = math.min(width/2 - 12, width - 2*math.abs(x) - 8)
            if math.abs(x) > 1 then labelWidth = math.min(labelWidth, 2*math.abs(x) - 8) end
            seat.nameLabel:SetWidth(math.max(24, labelWidth))
            seat.nameLabel:SetJustifyH("CENTER")
            if y > 1 then seat.nameLabel:SetPoint("BOTTOM", seat, "TOP", 0, 4 + scoreSpace)
            else seat.nameLabel:SetPoint("TOP", seat, "BOTTOM", 0, -4) end
        else
            seat.nameLabel:SetWidth(nameWidth)
            seat.nameLabel:SetJustifyH(right and "LEFT" or "RIGHT")
            local column = sides[right and 1 or 2]
            column[#column + 1] = seat
        end
        if score then
            seat.score:ClearAllPoints()
            if scoreInLabel then
                local edge = right and "LEFT" or "RIGHT"
                seat.score:SetPoint("BOTTOM"..edge, seat.nameLabel, "TOP"..edge, 0, 2)
            else
                seat.score:SetPoint("BOTTOM", seat, "TOP", 0, 2)
            end
        end
    end
    board.handLength = math.max(0, math.min(radius * 0.96, nearestPortrait - 2.5))
    board.hand:SetSize(2 * board.handLength, 2 * board.handLength)
    local coinSize = math.min(radius * (compact and 0.61 or 0.81), 1.12 * math.max(0, math.min(radius * 0.90, nearestPortrait - 4)))
    board.coin:SetSize(coinSize, coinSize)
    -- In the 256px arm texture the fingertip is at row 4 and the cuff ends at 109.
    -- Map those rows to the outer reach and just inside the coin's visible rim.
    local cuffRadius = 0.45 * coinSize / math.max(1, board.handLength) - 0.075
    board.handUVRadius = (109 - 4) / (256 * (0.985 - cuffRadius))
    board.handUVCenterY = 4/256 + 0.985 * board.handUVRadius
    local height = math.max(tableSize, 2 * radius * verticalReach + diameter + (scoreInLabel and 0 or 2*scoreSpace)) + 4
    if compact then
        for i = 1, count do
            local seat = board.seats[i]
            height = math.max(height, 2*(math.abs(seat.y) + diameter/2 + 8 + seat.nameLabel:GetStringHeight() + (seat.y > 1 and scoreSpace or 0)))
        end
    end
    for side, column in ipairs(sides) do
        local direction = side == 1 and 1 or -1
        local first, last, step = 1, #column, 1
        if side == 2 then first, last, step = #column, 1, -1 end
        local top, bottom
        for j = first, last, step do
            local seat = column[j]
            local row = math.max(board.badgeInLabel and badge:GetHeight() or 12, seat.nameLabel:GetStringHeight())
            local half = (row + (scoreInLabel and scoreSpace or 0))/2
            seat.labelY = math.min(seat.y, bottom and bottom - 3 - half or seat.y)
            top = top or seat.labelY + half
            bottom = seat.labelY - half
        end
        if top then
            local shift = (column[last].y - column[last].labelY)/2
            height = math.max(height, 2 * math.max(top + shift, -bottom - shift) + 8)
            for _, seat in ipairs(column) do
                local labelY = seat.labelY + shift - (scoreInLabel and scoreSpace/2 or 0)
                seat.nameLabel:ClearAllPoints()
                seat.nameLabel:SetPoint(side == 1 and "LEFT" or "RIGHT", board.frame, "CENTER", direction*gutter, labelY)
                seat.lead:SetStartPoint("CENTER", seat, 0, 0)
                seat.lead:SetEndPoint(seat.labelEdge, seat.nameLabel, -direction*3, 0)
            end
        end
    end
    board:SetHeight(math.ceil(math.max(height, viewport - 6)))
    if board.seatMoves then moveDraftSeats(board, board.motionProgress) end
    updateRollBadge(board)
    if board.angle then drawSpinner(board, board.angle) end
end

local function releaseSeat(seat)
    seat:SetScript("OnUpdate", nil)
    seat.exitElapsed, seat.exitBoard = nil, nil
    seat:Hide()
    seat.lead:Hide()
    if seat.name then DRE.BindGroupSeat(seat, nil, nil) end
    seat:SetAlpha(1)
    if seat.cornerCover then seat.cornerCover.rim:SetAlpha(1) end
end

local function fadeRemovedSeat(seat, elapsed)
    seat.exitElapsed = seat.exitElapsed + elapsed
    local t = math.min(1, seat.exitElapsed / 0.28)
    if t == 1 then releaseSeat(seat); return end
    local alpha = seat.exitAlpha * (1 - t*t*(3 - 2*t))
    seat:SetAlpha(alpha)
    if seat.model and seat.model.SetModelAlpha then seat.model:SetModelAlpha(alpha) end
    if seat.cornerCover and seat.cornerCover:IsShown() then
        seat.cornerCover.rim:SetAlpha(alpha)
        local board = seat.exitBoard
        if #board.players > 0 then
            seat.feltSize = board.felt:GetWidth()
            sampleSeatFelt(seat, seat.x, seat.y)
        else
            seat.cornerCover.felt:SetTexCoord(0, 0, 0, 0)
        end
    end
end

local function arrangeSeats(board, players, previous)
    -- A seat owns the character appearance. Keep it with its player when
    -- someone leaves or a pooled board is reopened with a different order.
    local wanted, existing, spare, leaving = {}, {}, {}, {}
    for _, name in ipairs(players) do wanted[name] = true end
    for _, seat in ipairs(board.seats) do
        if seat.name and wanted[seat.name] then
            if seat.exitElapsed then
                seat:SetScript("OnUpdate", nil)
                seat.exitElapsed, seat.exitBoard = nil, nil
                seat.rejoined = true
                if seat.cornerCover then seat.cornerCover.rim:SetAlpha(1) end
                if previous then previous[seat.name] = {x = seat.x, y = seat.y, alpha = seat:GetAlpha()} end
            end
            existing[seat.name] = seat
        elseif previous and seat.name and (seat.exitElapsed or (previous[seat.name] and previous[seat.name].alpha > 0)) then
            if not seat.exitElapsed then
                local pose = previous[seat.name]
                DRE.BindGroupSeat(seat, seat.name, nil)
                seat.x, seat.y = pose.x, pose.y
                seat:SetPoint("CENTER", board.frame, "CENTER", seat.x, seat.y)
                seat.exitAlpha, seat.exitElapsed, seat.exitBoard = pose.alpha, 0, board
                seat.portraitButton:Hide()
                seat.lead:Hide()
                seat:SetScript("OnUpdate", fadeRemovedSeat)
                fadeRemovedSeat(seat, 0)
            end
            leaving[#leaving + 1] = seat
        else
            releaseSeat(seat)
            spare[#spare + 1] = seat
        end
    end
    local seats = {}
    for i, name in ipairs(players) do
        local seat = existing[name] or table.remove(spare) or newSeat(board)
        seats[i] = seat
        seat.nameLabel:SetText(name)
        seat:Show()
    end
    for _, seat in ipairs(spare) do seats[#seats + 1] = seat end
    for _, seat in ipairs(leaving) do seats[#seats + 1] = seat end
    board.seats = seats
end

local function circleWidget()
    local frame = CreateFrame("Frame", nil, UIParent)
    local board = {type = "DREGroupCircle", frame = frame, seats = {}, players = {}, bound = {}, dirty = {}}
    board.motion = CreateFrame("Frame", nil, frame)
    local function advanceSeats(_, elapsed)
        board.motionProgress = math.min(1, board.motionProgress + elapsed / 0.28)
        if board.reflowFrom then
            layoutCircle(board, board.layoutWidth or frame:GetWidth())
            if not board.reflowFrom and board.parent and frame:IsVisible() then
                board.parent:DoLayout()
            end
        elseif board.seatMoves then
            moveDraftSeats(board, board.motionProgress)
        end
        if not board.reflowFrom and not board.seatMoves then board.motion:SetScript("OnUpdate", nil) end
    end
    local function finishMotion()
        if board.reflowFrom or board.seatMoves then advanceSeats(board.motion, 0.28) end
    end
    local updates = CreateFrame("Frame", nil, frame)
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    background:SetTexture(feltTexture, "CLAMP", "CLAMP")
    background:SetTexCoord(0, 0, 0, 0)
    background:SetAllPoints()
    board.felt = frame:CreateTexture(nil, "BACKGROUND")
    board.felt:SetTexture(feltTexture)
    alignArt(board.felt)
    board.felt:SetPoint("CENTER")
    board.hand = frame:CreateTexture(nil, "ARTWORK")
    board.hand:SetTexture("Interface\\AddOns\\DeathRollEnhancer\\Media\\GroupGoblinArm", "CLAMP", "CLAMP")
    board.hand:SetPoint("CENTER")
    board.coin = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    board.coin:SetTexture("Interface\\AddOns\\DeathRollEnhancer\\Media\\Logo")
    board.coin:SetPoint("CENTER")
    local badge = CreateFrame("Frame", nil, frame)
    badge:EnableMouse(false)
    local plate = CreateFrame("Frame", nil, badge, "BackdropTemplate")
    plate:SetAllPoints()
    plate:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    plate:SetBackdropColor(0.13, 0.08, 0.06, 1)
    plate:SetBackdropBorderColor(0.73, 0.52, 0.28, 1)
    badge.plate = plate
    badge.caption = CreateFrame("Frame", nil, badge)
    badge.caption:SetSize(1, 1)
    badge.caption:SetPoint("CENTER", badge, "CENTER")
    badge.number = badge.caption:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge.font, badge.baseFontSize, badge.fontFlags = badge.number:GetFont()
    badge.number:SetPoint("CENTER")
    badge.number:SetTextColor(unpack(gold))
    badge:Hide()
    board.rollBadge = badge
    function board:AnimateRollBadge()
        settleRollBadge(badge)
        local seat = badge.seat
        if not seat then return end
        badge.rollingSeat, badge.elapsed = seat, 0
        badge:SetScript("OnUpdate", animateRollBadge)
        animateRollBadge(badge, 0)
    end
    board.turnRing = newTurnRing(frame)
    board.trailingRing = newTurnRing(frame)
    -- Ace's scrollframe can change height without setting its child's width.
    -- Observe the viewport separately so Ace keeps ownership of its scroll scripts.
    local watcher = CreateFrame("Frame", nil, frame)
    local viewport, scrollPane
    local function syncViewport()
        watcher:SetScript("OnUpdate", nil)
        if not viewport then return end
        local width, height = viewport:GetWidth(), viewport:GetHeight()
        if width > 0 and height > 0 and (width ~= board.layoutWidth or height ~= board.viewportHeight) then
            board:OnWidthSet(width)
            scrollPane:DoLayout()
        end
    end
    local function queueViewport()
        if viewport then watcher:SetScript("OnUpdate", syncViewport) end
    end
    watcher:SetScript("OnSizeChanged", queueViewport)
    watcher:SetScript("OnShow", queueViewport)
    function board:WatchViewport(pane)
        scrollPane, viewport = pane, pane.scrollframe or pane.frame
        watcher:SetAllPoints(viewport)
        queueViewport()
    end
    function board:OnWidthSet(width)
        local height = viewport and viewport:GetHeight() or self.parent and self.parent.frame:GetHeight() or 0
        if width ~= self.layoutWidth or height ~= self.viewportHeight then
            if width ~= self.layoutWidth then self.reflowFrom = nil end
            self.layoutWidth, self.viewportHeight = width, height
            layoutCircle(self, width)
        end
    end
    function board:OnAcquire()
        self:SetFullWidth(true)
        self:SetHeight(1)
        for _, event in ipairs({"GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
            "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED",
            "UNIT_NAME_UPDATE", "PLAYER_ENTERING_WORLD"}) do frame:RegisterEvent(event) end
    end
    function board:OnRelease()
        scrollPane, viewport = nil, nil
        watcher:SetScript("OnUpdate", nil)
        watcher:ClearAllPoints()
        finishMotion()
        frame:UnregisterAllEvents()
        settleRollBadge(badge)
        self.rollBadge:Hide()
        self.rollBadge.seat = nil
        clearTurnLights(self)
        frame:SetScript("OnUpdate", nil)
        updates:SetScript("OnUpdate", nil)
        for _, seat in ipairs(self.seats) do
            if seat.exitElapsed then releaseSeat(seat)
            elseif seat.name then DRE.BindGroupSeat(seat, seat.name, nil) end
            seat:Hide()
            seat.lead:Hide()
        end
        self.bound, self.dirty, self.unitsChanged = {}, {}, nil
        self.players, self.round, self.angle, self.destination = {}, nil, nil, nil
        self.layoutWidth, self.viewportHeight = nil, nil
    end
    function board:Present(players, round, draftMode, animateRoster)
        local count = #players
        local changed = self.players ~= players
        local newRound = self.round ~= round
        local mode = round and round.mode or draftMode
        local showScore = mode == "twoLives" or mode == "highRoller"
        local resize = changed or newRound or self.showScore ~= showScore
        local previous
        if resize then
            local from
            if animateRoster and not round and frame:IsVisible() then
                previous = {}
                for i, name in ipairs(self.players) do
                    local seat = self.seats[i]
                    previous[name] = {x = seat.drawX or seat.x, y = seat.drawY or seat.y, alpha = seat:GetAlpha()}
                end
                if count > 0 and #self.players > 0 and self.radius then from = {radius = self.radius, diameter = self.diameter} end
            end
            finishMotion()
            self.reflowFrom, self.motionProgress = from, 0
        end
        if newRound or (round and round.status == "cancelled") then settleRollBadge(badge) end
        self.round = round
        if changed then
            self.players = players
            arrangeSeats(self, players, previous)
        end
        -- In Teams only the current roller's portrait glows, even during the pointer sweep.
        self.turnRing.halo:SetShown(mode ~= "teams")
        self.trailingRing.halo:SetShown(mode ~= "teams")
        local scores = round and (round.lives or round.points)
        self.showScore = showScore
        local leader, most = nil, 0
        if scores then
            for i, value in ipairs(scores) do
                if value > most then most, leader = value, i
                elseif value == most then leader = nil end
            end
        end
        local active = round ~= nil and round.status == "active"
        local tiedSeats = active and round.tiebreak
        local tiedIndex = 1
        local points = count >= 2 and (active or not round)
        self.hand:SetShown(points)
        for i = 1, count do
            local seat = self.seats[i]
            local caption = players[i]
            if mode == "teams" then
                seat.team = (round and round.teams or DRE:GetGroupDraft().teams)[caption]
            else
                seat.team = nil
            end
            local teamTurn = seat.team ~= nil and active and round.turn == i
            if seat.team then
                local color = teamColors[seat.team]
                seat.portraitButton.outline:SetColorTexture(color[1], color[2], color[3], 0.74)
            end
            seat.portraitButton.outline:SetShown(seat.team ~= nil and not teamTurn)
            seat.portraitButton.ring:SetShown(teamTurn)
            seat.portraitButton:SetShown(not round or seat.team ~= nil)
            if showScore then
                seat.score = seat.score or DRE:CreateTableScoreBadge(seat, true)
                seat.score:Present(mode, scores and scores[i] or (mode == "twoLives" and 2 or 0), i == leader)
            elseif seat.score then
                seat.score:Hide()
            end
            if seat.displayName ~= caption or changed then
                seat.displayName = caption
                seat.nameLabel:SetText(caption)
                resize = true
            end
            -- Tiebreak seats are in roster order. Keep names and coins at full
            -- opacity while the roll animation fades the face to its target.
            seat.faceAlpha = 1
            if tiedSeats then
                if tiedSeats[tiedIndex] == i then tiedIndex = tiedIndex + 1
                else seat.faceAlpha = 0.35 end
            end
            if badge.rollingSeat ~= seat then setFaceAlpha(seat, seat.faceAlpha) end
            local out = round and round.eliminated and round.eliminated[i]
            local palette = teamBackdrops[seat.team] or forestBackdrop
            local backdrop = palette.normal
            if out or seat.faceAlpha < 1 then backdrop = palette.dim
            elseif active and round.turn == i then backdrop = palette.active end
            seat.backing:SetColorTexture(backdrop[1], backdrop[2], backdrop[3], 1)
            if not self.seatMoves then seat:SetAlpha(out and not round.loser and 0.5 or 1) end
            local color = ivory
            if out then color = red
            elseif round and (round.winner == players[i] or (round.winningTeam and round.winningTeam == seat.team)) then color = gold
            elseif points and i == (round and round.turn or 1) then color = gold end
            seat.nameLabel:SetTextColor(unpack(color))
        end
        if resize then layoutCircle(self, self.layoutWidth or frame:GetWidth())
        else updateRollBadge(self) end
        if changed then bindSeats(self) end
        if previous and count > 0 then
            local moves = {}
            for i, name in ipairs(players) do
                local seat, old = self.seats[i], previous[name]
                if old and old.x and (math.abs(old.x-seat.x) > 0.01 or math.abs(old.y-seat.y) > 0.01) then
                    local angle = math.atan2(old.x, old.y)
                    local target = math.atan2(seat.x, seat.y)
                    moves[#moves+1] = {seat = seat, radius = math.sqrt(old.x^2 + old.y^2), angle = angle,
                        travel = (target - angle + math.pi) % tau - math.pi}
                end
                if not old or old.alpha < 1 then
                    moves[#moves+1] = {seat = seat, entering = true, alpha = old and old.alpha or 0}
                end
            end
            if #moves > 0 then
                self.seatMoves, self.motionProgress = moves, 0
                moveDraftSeats(self, 0)
            end
        end
        if self.reflowFrom or self.seatMoves then self.motion:SetScript("OnUpdate", advanceSeats) end
        if not points then
            clearTurnLights(self)
            frame:SetScript("OnUpdate", nil)
            self.angle, self.destination = nil, nil
            return
        end
        local destination = ((round and round.seatSteps or 0) + 0.5) * tau/count
        if changed or newRound or not self.angle or not frame:IsVisible() then
            frame:SetScript("OnUpdate", nil)
            local first = self.seats[1]
            drawSpinner(self, not round and first.drawX and math.atan2(first.drawX, first.drawY) or destination)
        elseif destination ~= self.destination then
            self.origin, self.elapsed = self.angle, 0
            frame:SetScript("OnUpdate", sweep)
        end
        self.destination = destination
    end
    frame:SetScript("OnShow", function()
        if #board.players > 0 then bindSeats(board, true) end
        if board.destination then drawSpinner(board, board.destination) end
    end)
    frame:SetScript("OnHide", function()
        finishMotion()
        for _, seat in ipairs(board.seats) do
            if seat.exitElapsed then releaseSeat(seat) end
        end
        settleRollBadge(badge)
        clearTurnLights(board)
        frame:SetScript("OnUpdate", nil)
        updates:SetScript("OnUpdate", nil)
        board.dirty, board.unitsChanged = {}, nil
    end)
    local function refreshUnits()
        updates:SetScript("OnUpdate", nil)
        if board.unitsChanged then bindSeats(board) end
        for unit, name in pairs(board.dirty) do
            local seat = board.bound[unit]
            if seat and seat.name == name and DRE.GroupUnitMatches(unit, name) then
                DRE.BindGroupSeat(seat, name, unit, unit)
            end
        end
        board.dirty, board.unitsChanged = {}, nil
    end
    frame:SetScript("OnEvent", function(_, event, unit)
        if #board.players == 0 or not frame:IsVisible() then return end
        if event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
            if not DRE:IsAccessibleValue(unit) or not board.bound[unit] then return end
            local name = board.bound[unit].name
            if DRE.GroupUnitMatches(unit, name) then board.dirty[unit] = name
            else board.unitsChanged = true end
        else
            board.unitsChanged = true
        end
        updates:SetScript("OnUpdate", refreshUnits)
    end)
    return AceGUI:RegisterAsWidget(board)
end

if DRE.devDuel then AceGUI:RegisterWidgetType("DREGroupCircle", circleWidget, 1) end

local function tableButton(parent, text, fraction, callback)
    local widget = DRE:CreateWindowWidget("Button")
    widget:SetText(text)
    widget:SetRelativeWidth(fraction)
    widget:SetCallback("OnClick", callback)
    parent:AddChild(widget)
    return widget
end

local function rosterControls(w, draft, footer)
    local form = AceGUI:Create("SimpleGroup")
    form:SetFullWidth(true)
    form:SetLayout("Flow")
    local name = DRE:CreateWindowWidget("EditBox")
    name:SetLabel("Player name")
    name:SetRelativeWidth(3/8)
    form:AddChild(name)
    local function add()
        if addDraftPlayer(DRE, name:GetText()) then name:SetText("") end
    end
    name:SetCallback("OnEnterPressed", add)
    tableButton(form, "Add", 1/8, add)
    tableButton(form, "Add target", 9/32, function() DRE:AddGroupPlayerFromUnit("target") end)
    tableButton(form, "Add me", 7/32, function() DRE:AddGroupPlayerFromUnit("player") end)
    local range = DRE:CreateWindowWidget("EditBox")
    range:SetLabel("Starting roll")
    range:SetRelativeWidth(5/16)
    range:SetText(draft.initialRoll)
    range:SetCallback("OnTextChanged", function(_, _, text)
        draft.initialRoll = text
        DRE:RefreshGroupUI()
    end)
    form:AddChild(range)
    local mode = DRE:CreateTableDropdownField(form, "Mode", 11/32)
    mode:SetList(modes, modeOrder)
    mode:SetValue(draft.mode or "classic")
    mode:SetCallback("OnValueChanged", function(_, _, value)
        draft.mode = value
        DRE:RefreshGroupUI()
    end)
    local channel = DRE:CreateTableDropdownField(form, "Announce to", 11/32)
    channel:SetList(channels, channelOrder)
    channel:SetValue(draft.channel)
    channel:SetCallback("OnValueChanged", selectGroupChannel)
    footer:AddChild(form)
    w.nameInput, w.initialRoll, w.mode, w.form = name, range, mode, form
end

local function refreshTable(self, w, round, active, busy, canRoll)
    local draft = self:GetGroupDraft()
    if draft.editing and not active then round = nil end
    local shared = self.sharedTable
    local guest = self:IsGroupGuest()
    if not round and (w.draftText ~= draft.roster or w.shared ~= shared) then
        w.draftText = draft.roster
        w.preview = guest and shared.rev == 0 and {} or parseRoster(self, draft.roster, 0) or {}
    end
    local players = round and round.players or w.preview
    local mode = round and round.mode or draft.mode
    local displayPhase = round and round.status or "setup"
    local initialized = w.displayPhase ~= nil
    local phaseChanged = initialized and w.displayPhase ~= displayPhase
    local transition = phaseChanged or (initialized and w.displayMode ~= mode)
    -- Read the visible viewport before rebuilding the footer or moving the summary.
    local previousView
    if transition then
        local content = self.UI.mainWindow.content
        previousView = {top = content:GetTop(), bottom = content:GetBottom(), controlsChanged = phaseChanged}
    end
    local ownTurn = active and sameRosterName(players[round.turn], self:GetUnitPlayerName("player"))
    local phase = active and (ownTurn and "roll" or "wait") or (round and "result" or "setup")
    local showAnnounce = not guest and round ~= nil and round.channel ~= "NONE"
    if w.phase ~= phase or w.showAnnounce ~= showAnnounce or w.shared ~= shared then
        local footer = self.UI.tableFooter
        footer:ReleaseChildren()
        w.nameInput, w.initialRoll, w.mode, w.form = nil, nil, nil, nil
        w.primary, w.announce, w.secondary, w.shuffle = nil, nil, nil, nil
        footer:SetAutoAdjustHeight(phase == "setup" and not guest)
        if guest then
            footer:SetHeight(44)
            if ownTurn then
                w.primary = tableButton(footer, "Roll Your Turn", 0.6, function() self:RollGroupTurn() end)
            end
            w.secondary = tableButton(footer, "Leave table", ownTurn and 0.4 or 1, function() self:LeaveSharedTable() end)
        elseif phase == "setup" then
            rosterControls(w, draft, footer)
            if self.groupMessagesEnabled then
                if shared then
                    tableButton(w.form, "Close shared table", 1, function() self:LeaveSharedTable() end)
                else
                    tableButton(w.form, "Host table", 0.5, function() self:SharedTableCommand("host") end)
                    tableButton(w.form, "Join target", 0.5, function() self:SharedTableCommand("join") end)
                end
            end
            w.primary = tableButton(footer, "Start Round", 0.6, function()
                local ok, reason = self:StartGroupRound(draft.roster, tonumber(draft.initialRoll), draft.channel, draft.mode)
                if not ok then self:Print(reason) end
            end)
            w.shuffle = tableButton(footer, "Shuffle order", 0.4, function() self:ShuffleGroupOrder() end)
        else
            footer:SetHeight(44)
            local fraction = showAnnounce and 5/16 or 0.5
            if phase == "wait" then fraction = showAnnounce and 0.5 or 1 end
            if phase == "roll" then
                w.primary = tableButton(footer, "Roll Your Turn", fraction, function() self:RollGroupTurn() end)
            elseif phase == "result" then
                w.primary = tableButton(footer, "Play again", fraction, function()
                    local ok, reason = self:RestartGroupRound()
                    if not ok then self:Print(reason) end
                end)
            end
            if showAnnounce then
                w.announce = tableButton(footer, "Announce", phase == "wait" and 0.5 or 3/8, function() self:AnnounceGroupRound() end)
            end
            if active then
                w.secondary = tableButton(footer, "Cancel Round", fraction, function() self:CancelGroupRound() end)
            else
                w.secondary = tableButton(footer, "Edit roster", fraction, function()
                    self:GetGroupDraft().editing = true
                    self:RefreshGroupUI()
                end)
            end
        end
        if w.primary then w.primary:SetPrimary(true) end
        if w.circle.round ~= round then
            w.pane:SetScroll(0)
            w.pane.scrollbar:SetValue(0)
        end
        footer:DoLayout()
        w.phase, w.showAnnounce, w.shared = phase, showAnnounce, shared
    end
    local detail
    if active then
        w.status:SetText(players[round.turn] .. " rolls 1–" .. round.currentRoll)
        if round.mode == "highRoller" then
            detail = highRollerPhase(round) .. " · " .. (round.pointResult or
                (round.highFace and ("High roll: " .. round.highFace)) or "First to 2 points")
        else
            detail = self:FormatRollOneChance(round.currentRoll) .. " chance to roll a 1"
        end
        if round.mode == "elimination" or round.mode == "twoLives" or round.mode == "teams" then
            if round.lastRoll == 1 then detail = lastOneText(round) end
            detail = detail .. " · " .. round.remaining .. " players left"
        end
        if round.mode == "teams" then detail = teamNames[round.teams[players[round.turn]]] .. " to roll · " .. detail end
        if round.mode == "hotPotato" then detail = "Hot Potato · " .. detail end
        if w.primary then w.primary:SetDisabled(not canRoll) end
    elseif round then
        w.status:SetText(groupResult(round))
        detail = round.status == "finished" and "Settle payouts manually." or nil
        if w.primary then w.primary:SetDisabled(busy) end
    elseif guest then
        w.status:SetText(shared.rev == 0 and "Joining table…" or (#players >= 1 and (players[1] .. " rolls first") or "Waiting for players"))
        detail = modeRules[mode]
    else
        local maximum = tonumber(draft.initialRoll)
        local valid = self:IsBoundedInteger(maximum, 2, self.MAX_ROLL)
        w.status:SetText(#players >= 2 and (players[1] .. " rolls first") or "Add players to the table")
        w.primary:SetText(valid and ("Start  1–" .. maximum) or "Start Round")
        w.shuffle:SetDisabled(busy or #players < 2)
        detail = modeRules[draft.mode or "classic"]
        if draft.mode == "teams" then
            local counts
            draft.teams, counts = assignTeams(players, draft.teams)
            valid = valid and counts[1] > 0 and counts[2] > 0
            detail = ("Gold %d · Crimson %d · Left-click a portrait to switch teams."):format(counts[1], counts[2])
            if #players >= 2 and (counts[1] == 0 or counts[2] == 0) then
                detail = "Each team needs a player. Left-click a portrait to switch teams."
            end
        end
        w.primary:SetDisabled(busy or #players < 2 or not valid)
    end
    if w.announce then
        w.announce:SetText(round.channel == "SAY" and "Announce to Say" or "Announce")
        w.announce:SetDisabled(self.disabled)
        if round.chatError and round.chatError ~= sayReminder then
            detail = (detail and (detail .. "\n") or "") .. round.chatError
        end
    end
    if shared then
        local hostLine = "Hosted by " .. shared.host .. " · " .. modes[mode]
        if not round and guest and shared.rev > 0 then
            hostLine = hostLine .. (draft.initialRoll == "0" and " · Waiting for starting roll" or " · Starting roll " .. draft.initialRoll)
        end
        if guest and shared.rev > 0 and not self:SharedHostOnline() then hostLine = hostLine .. " · Syncing…" end
        detail = hostLine .. (detail and ("\n" .. detail) or "")
    end
    w.lastRoll:SetText(detail or "")
    w.lastRoll:SetShown(detail ~= nil)
    self.UI.tableHero:SizeGroupSummary(round ~= nil, initialized, previousView)
    w.circle:Present(players, round, draft.mode, initialized and w.displayPhase == "setup")
    w.displayPhase, w.displayMode = displayPhase, mode
    w.pane:DoLayout()
end

function DRE:CreateGroupSection(container)
    local pane = AceGUI:Create("ScrollFrame")
    pane:SetFullWidth(true); pane:SetFullHeight(true); pane:SetLayout("Flow")
    container:AddChild(pane)
    local widgets = {pane = pane}
    self.UI.groupWidgets = widgets
    local function label(text)
        local widget = AceGUI:Create("Label")
        widget:SetText(text); widget:SetFullWidth(true); pane:AddChild(widget)
        return widget
    end
    if self.devDuel then
        widgets.status = self.UI.tableHero.groupTurn
        widgets.lastRoll = self.UI.tableHero.groupLast
        widgets.circle = AceGUI:Create("DREGroupCircle")
        pane:AddChild(widgets.circle)
        widgets.circle:WatchViewport(pane)
        self:RefreshGroupUI()
        return
    end
    label("Choose a mode and starting roll. Stay near the host so they can see your rolls. Payouts are manual.")
    widgets.status = label("")
    widgets.error = label("")
    widgets.error:SetColor(1, 0.35, 0.25)
    local function button(text, callback)
        local widget = DRE:CreateWindowWidget("Button")
        widget:SetText(text)
        widget:SetWidth(145)
        widget:SetCallback("OnClick", callback)
        pane:AddChild(widget)
        return widget
    end
    local function startRound()
        local draft = self:GetGroupDraft()
        local ok, reason = self:StartGroupRound(draft.roster, tonumber(draft.initialRoll), draft.channel, draft.mode)
        if not ok then self:Print(reason) end
    end
    local function restartRound()
        local ok, reason = self:RestartGroupRound()
        if not ok then self:Print(reason) end
    end
    widgets.start = button("Start Round", startRound)
    widgets.restart = button("Restart Round", restartRound)
    widgets.cancel = button("Cancel Round", function() self:CancelGroupRound() end)
    widgets.roll = button("Roll Your Turn", function() self:RollGroupTurn() end)
    widgets.announce = button("Announce", function() self:AnnounceGroupRound() end)
    local draft = self:GetGroupDraft()
    local roster = AceGUI:Create("MultiLineEditBox")
    roster:SetLabel("Turn order: one exact full name per line (2-40 players)")
    roster:SetNumLines(4); roster:SetFullWidth(true); roster:DisableButton(true)
    roster:SetText(draft.roster)
    roster:SetCallback("OnTextChanged", function(_, _, text)
        if not self:IsGroupRoundActive() then
            self:GetGroupDraft().roster = text
            widgets.shuffle:SetDisabled(self:HasActiveGame() or not self:ParseGroupRoster(text))
        end
    end)
    pane:AddChild(roster); widgets.roster = roster
    widgets.addTarget = button("Add Target", function() self:AddGroupPlayerFromUnit("target") end)
    widgets.addMe = button("Add Me", function() self:AddGroupPlayerFromUnit("player") end)
    widgets.shuffle = button("Shuffle order", function() self:ShuffleGroupOrder() end)
    local initialRoll = DRE:CreateWindowWidget("EditBox")
    initialRoll:SetLabel("Starting roll"); initialRoll:SetWidth(145); initialRoll:DisableButton(true)
    initialRoll:SetText(draft.initialRoll)
    initialRoll:SetCallback("OnTextChanged", function(_, _, text)
        if not self:IsGroupRoundActive() then
            self:GetGroupDraft().initialRoll = text
        end
    end)
    pane:AddChild(initialRoll); widgets.initialRoll = initialRoll
    local mode = AceGUI:Create("Dropdown")
    mode:SetLabel("Mode"); mode:SetWidth(145); mode:SetList(modes, modeOrder)
    mode:SetValue(draft.mode or "classic")
    mode:SetCallback("OnValueChanged", function(_, _, value)
        if not self:IsGroupRoundActive() then
            self:GetGroupDraft().mode = value
            self:RefreshGroupUI()
        end
    end)
    pane:AddChild(mode); widgets.mode = mode
    widgets.modeHelp = label(modeRules[draft.mode or "classic"])
    local channel = AceGUI:Create("Dropdown")
    channel:SetLabel("Announce to"); channel:SetWidth(145); channel:SetList(channels, channelOrder); channel:SetValue(draft.channel)
    channel:SetCallback("OnValueChanged", selectGroupChannel)
    pane:AddChild(channel); widgets.channel = channel
    label("Start uses the roster above. Restart reuses the last round's roster, order and starting roll. Cancel first if a player leaves; turns are never skipped automatically. Reloading ends the local round. Settle group payouts before starting new trade-tracked 1v1 games. Group results are session-only. Earlier unpaid 1v1 games with these players require /dr edit for payment assignment, so group payouts cannot change them.")
    widgets.log = label("")
    self:RefreshGroupUI()
end

function DRE:RefreshGroupUI()
    if self.sharedTable and self.sharedTable.role == "host" then self:PublishSharedTable() end
    if self.RefreshDuel then self:RefreshDuel() end
    local round = self.groupRound
    local active = self:IsGroupRoundActive()
    if self.UI.currentTab == "deathroll" and self.UI.gameButton then self:RestoreGameControls() end
    local widgets = self.UI.groupWidgets
    if not widgets or self.UI.currentTab ~= "group" then return end
    local busy = self:HasActiveGame() or self.disabled
    local canRoll = active and not round.pendingRoll and (not self:IsGroupGuest() or self:SharedHostOnline())
        and sameRosterName(round.players[round.turn], self:GetUnitPlayerName("player"))
    if widgets.circle then
        refreshTable(self, widgets, round, active, busy, canRoll)
        return
    end
    widgets.start:SetDisabled(busy)
    widgets.shuffle:SetDisabled(busy or not self:ParseGroupRoster(self:GetGroupDraft().roster))
    widgets.restart:SetDisabled(busy or not round)
    widgets.cancel:SetDisabled(not active)
    widgets.roll:SetDisabled(not canRoll)
    widgets.announce:SetDisabled(not round or self.disabled or round.channel == "NONE" or round.channel ~= self:GetGroupDraft().channel)
    for _, key in ipairs({"roster", "initialRoll", "channel", "mode", "addTarget", "addMe"}) do
        widgets[key]:SetDisabled(active)
    end
    widgets.status:SetText(round and self:GetGroupAnnouncement(round) or "Ready to configure a group round.")
    widgets.modeHelp:SetText(modeRules[self:GetGroupDraft().mode or "classic"])
    widgets.error:SetText(round and round.channel == self:GetGroupDraft().channel and round.chatError or "")
    widgets.log:SetText(round and ("Recent group rolls:\n" .. table.concat(round.log, "\n")) or "")
end
