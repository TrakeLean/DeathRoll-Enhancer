-- Host-controlled group rounds. Outcomes never create 1v1 results or trade debts.
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
local AceGUI = LibStub("AceGUI-3.0")
local channels = { SAY = "Say (nearby)", PARTY = "Party", RAID = "Raid", INSTANCE_CHAT = "Instance" }
local startText = "Group DeathRoll: first 1 loses; payouts manual. Turn %d/%d: %s, /roll %d. Stay near the host."
local turnText = "Group DeathRoll: turn %d/%d - %s, /roll %d."
local finishText = "Group DeathRoll: %s rolled 1 and loses. Round finished; settle payouts manually."

function DRE:IsGroupRoundActive()
    return self.groupRound ~= nil and self.groupRound.status == "active"
end

function DRE:HasActiveGame()
    return self:IsGroupRoundActive() or (self.gameState and self.gameState.isActive)
        or (self.spicyDuel and self.spicyDuel.isActive) or false
end

function DRE:GetGroupDraft()
    if not self.groupDraft then
        self.groupDraft = { roster = self:GetUnitPlayerName("player") or "", initialRoll = "100", channel = "SAY" }
    end
    return self.groupDraft
end

function DRE:ParseGroupRoster(text)
    if not self:IsAccessibleValue(text) or type(text) ~= "string" or #text > 12000 then
        return nil, "Enter up to 40 full player names, one per line."
    end
    local players, seen = {}, {}
    for line in text:gmatch("[^\r\n]+") do
        local trimmed = self:Trim(line)
        if trimmed ~= "" then
            local name = self:NormalizePlayerName(trimmed)
            if not name then return nil, "Invalid player name on line " .. (#players + 1) .. "." end
            if seen[name] then return nil, "Duplicate player: " .. name end
            if #string.format(startText, 40, 40, name, self.MAX_ROLL) > 255
                or #string.format(finishText, name) > 255 then
                return nil, "Player name is too long for a group announcement."
            end
            players[#players + 1], seen[name] = name, true
            if #players > 40 then return nil, "A group round supports at most 40 players." end
        end
    end
    if #players < 2 then return nil, "Add at least two different players." end
    return players
end

function DRE:AddGroupLog(round, text)
    round.log[#round.log + 1] = text
    if #round.log > 20 then table.remove(round.log, 1) end
end

function DRE:GetGroupAnnouncement(round, starting)
    if round.status == "finished" then return string.format(finishText, round.loser) end
    if round.status == "cancelled" then return "Group DeathRoll cancelled by the host. No result or payment recorded." end
    return string.format(starting and startText or turnText,
        round.turn, #round.players, round.players[round.turn], round.currentRoll)
end

function DRE:AnnounceGroupRound(starting, automatic)
    local round = self.groupRound
    if not round or self.disabled then return false end
    -- SAY can require a hardware event. System-roll callbacks have none.
    if automatic and round.channel == "SAY" then
        round.chatError = "Click Announce to send the current turn or result to Say."
        self:RefreshGroupUI()
        return false
    end
    -- Recheck channel membership, but never silently switch the round's audience.
    local channel, _, reason = self:ResolveStatsBroadcastChannel(round.channel)
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

function DRE:StartGroupRound(rosterText, initialRoll, channelHint)
    if self.disabled then return false, "The addon is disabled." end
    if self:HasActiveGame() then return false, "Finish or cancel the active game first." end
    local players, reason = self:ParseGroupRoster(rosterText)
    if not players then return false, reason end
    if not self:IsBoundedInteger(initialRoll, 2, self.MAX_ROLL) then
        return false, "Starting roll must be a whole number from 2 to 999,999."
    end
    if not channels[channelHint] then return false, "Choose Say, Party, Raid, or Instance chat." end
    local channel, _, channelError = self:ResolveStatsBroadcastChannel(channelHint)
    if not channel then return false, channelError end
    if channel ~= channelHint then
        return false, "That channel is unavailable here. Select Raid or Instance explicitly."
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
    local participants, manualCount = {}, 0
    for _, name in ipairs(players) do participants[name] = true end
    for _, pending in ipairs(self.db.profile.pendingTradeWagers or {}) do
        local name = self:NormalizePlayerName(pending.playerName)
        if name and participants[name] then
            pending.manualAssignmentRequired = true
            manualCount = manualCount + 1
        end
    end
    if manualCount > 0 then
        self:Print("Earlier unpaid 1v1 games with these players now require /dr edit to assign payments. Group payouts will not update them automatically.")
    end
    self.groupRound = { status = "active", players = players, initialRoll = initialRoll,
        currentRoll = initialRoll, turn = 1, rollCount = 0, channel = channel, log = {} }
    self.groupDraft = { roster = table.concat(players, "\n"), initialRoll = tostring(initialRoll), channel = channel }
    local widgets = self.UI.groupWidgets
    if widgets then
        widgets.roster:SetText(self.groupDraft.roster)
        widgets.initialRoll:SetText(self.groupDraft.initialRoll)
        widgets.channel:SetValue(channel)
    end
    self:AddGroupLog(self.groupRound, "Round started. First roll of 1 loses; payouts are manual.")
    self:AnnounceGroupRound(true)
    self:Print(self:GetGroupAnnouncement(self.groupRound, true))
    self:RefreshGroupUI()
    return true
end

function DRE:HandleGroupRoll(playerName, roll, maximum)
    local round = self.groupRound
    if self.disabled or not self:IsGroupRoundActive() then return false end
    local name = self:NormalizePlayerName(playerName)
    if name ~= round.players[round.turn] then return false end
    if not self:IsBoundedInteger(maximum, 1, self.MAX_ROLL) or maximum ~= round.currentRoll
        or not self:IsBoundedInteger(roll, 1, maximum) then return false end
    round.pendingRoll = nil
    round.rollCount = round.rollCount + 1
    self:AddGroupLog(round, string.format("%s: %d (1-%d)", name, roll, maximum))
    if roll == 1 then
        round.status, round.loser = "finished", name
        self:AddGroupLog(round, name .. " loses. Round finished.")
    else
        round.currentRoll = roll
        round.turn = round.turn % #round.players + 1
    end
    self:Print(self:GetGroupAnnouncement(round))
    self:AnnounceGroupRound(false, true)
    self:RefreshGroupUI()
    return true
end

function DRE:CancelGroupRound(quiet)
    if not self:IsGroupRoundActive() then return false end
    local round = self.groupRound
    round.status, round.pendingRoll = "cancelled", nil
    self:AddGroupLog(round, "Cancelled. No result or payment recorded.")
    if not quiet then
        self:Print(self:GetGroupAnnouncement(round))
        self:AnnounceGroupRound()
    end
    self:RefreshGroupUI()
    return true
end

function DRE:RestartGroupRound()
    local round = self.groupRound
    if not round then return false, "No group round to restart." end
    return self:StartGroupRound(table.concat(round.players, "\n"), round.initialRoll, round.channel)
end

function DRE:RollGroupTurn()
    local round = self.groupRound
    if self.disabled or not self:IsGroupRoundActive() or round.pendingRoll
        or not self:IsSamePlayer(round.players[round.turn], self:GetUnitPlayerName("player")) then return false end
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

function DRE:AddGroupPlayerFromUnit(unit)
    if self:IsGroupRoundActive() then return false end
    if not UnitIsPlayer(unit) then self:Print("Select a player to add."); return false end
    local name = self:GetUnitPlayerName(unit)
    if not name then return false end
    local draft = self:GetGroupDraft()
    for line in draft.roster:gmatch("[^\r\n]+") do
        if self:IsSamePlayer(line, name) then self:Print("That player is already in the roster."); return false end
    end
    draft.roster = draft.roster == "" and name or (draft.roster .. "\n" .. name)
    local widgets = self.UI.groupWidgets
    if widgets then widgets.roster:SetText(draft.roster) end
    return true
end

function DRE:GroupCommand(command)
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
        self:ShowMainWindow()
        self.UI.tabGroup:SelectTab("group")
    else
        self:Print("Usage: /dr group [cancel|roll|announce|restart]")
    end
end

function DRE:CreateGroupSection(container)
    local pane = AceGUI:Create("ScrollFrame")
    pane:SetFullWidth(true); pane:SetFullHeight(true); pane:SetLayout("Flow")
    container:AddChild(pane)
    local widgets = {}
    self.UI.groupWidgets = widgets
    local function label(text)
        local widget = AceGUI:Create("Label")
        widget:SetText(text); widget:SetFullWidth(true); pane:AddChild(widget)
        return widget
    end
    label("Host a fixed-order round. First 1 loses. Only the host needs the addon; everyone must stay nearby so the host sees their rolls. Payouts are manual.")
    widgets.status = label("")
    widgets.error = label("")
    widgets.error:SetColor(1, 0.35, 0.25)
    local function button(text, callback)
        local widget = AceGUI:Create("Button")
        widget:SetText(text); widget:SetWidth(145); widget:SetCallback("OnClick", callback)
        pane:AddChild(widget)
        return widget
    end
    widgets.start = button("Start Round", function()
        local draft = self:GetGroupDraft()
        local ok, reason = self:StartGroupRound(draft.roster, tonumber(draft.initialRoll), draft.channel)
        if not ok then self:Print(reason) end
    end)
    widgets.restart = button("Restart Round", function()
        local ok, reason = self:RestartGroupRound()
        if not ok then self:Print(reason) end
    end)
    widgets.cancel = button("Cancel Round", function() self:CancelGroupRound() end)
    widgets.roll = button("Roll Your Turn", function() self:RollGroupTurn() end)
    widgets.announce = button("Announce", function() self:AnnounceGroupRound() end)
    local draft = self:GetGroupDraft()
    local roster = AceGUI:Create("MultiLineEditBox")
    roster:SetLabel("Turn order: one exact full name per line (2-40 players)")
    roster:SetNumLines(4); roster:SetFullWidth(true); roster:DisableButton(true)
    roster:SetText(draft.roster)
    roster:SetCallback("OnTextChanged", function(_, _, text)
        if not self:IsGroupRoundActive() then self:GetGroupDraft().roster = text end
    end)
    pane:AddChild(roster); widgets.roster = roster
    widgets.addTarget = button("Add Target", function() self:AddGroupPlayerFromUnit("target") end)
    widgets.addMe = button("Add Me", function() self:AddGroupPlayerFromUnit("player") end)
    local initialRoll = AceGUI:Create("EditBox")
    initialRoll:SetLabel("Starting roll"); initialRoll:SetWidth(145); initialRoll:DisableButton(true)
    initialRoll:SetText(draft.initialRoll)
    initialRoll:SetCallback("OnTextChanged", function(_, _, text)
        if not self:IsGroupRoundActive() then self:GetGroupDraft().initialRoll = text end
    end)
    pane:AddChild(initialRoll); widgets.initialRoll = initialRoll
    local channel = AceGUI:Create("Dropdown")
    channel:SetLabel("Announce to"); channel:SetWidth(145); channel:SetList(channels); channel:SetValue(draft.channel)
    channel:SetCallback("OnValueChanged", function(_, _, value)
        if not self:IsGroupRoundActive() then self:GetGroupDraft().channel = value end
    end)
    pane:AddChild(channel); widgets.channel = channel
    label("Start uses the roster above. Restart reuses the last round's roster, order and starting roll. Cancel first if a player leaves; turns are never skipped automatically. Reloading ends the local round. Settle group payouts before starting new trade-tracked 1v1 games. Group results are session-only. Earlier unpaid 1v1 games with these players require /dr edit for payment assignment, so group payouts cannot change them.")
    widgets.log = label("")
    self:RefreshGroupUI()
end

function DRE:RefreshGroupUI()
    local round = self.groupRound
    local active = self:IsGroupRoundActive()
    if self.UI.currentTab == "deathroll" and self.UI.gameButton then self:RestoreGameControls() end
    local widgets = self.UI.groupWidgets
    if not widgets or self.UI.currentTab ~= "group" then return end
    local busy = self:HasActiveGame() or self.disabled
    widgets.start:SetDisabled(busy)
    widgets.restart:SetDisabled(busy or not round)
    widgets.cancel:SetDisabled(not active)
    widgets.announce:SetDisabled(not round or self.disabled)
    widgets.roll:SetDisabled(not active or round.pendingRoll ~= nil
        or not self:IsSamePlayer(round.players[round.turn], self:GetUnitPlayerName("player")))
    for _, key in ipairs({"roster", "initialRoll", "channel", "addTarget", "addMe"}) do
        widgets[key]:SetDisabled(active)
    end
    widgets.status:SetText(round and self:GetGroupAnnouncement(round) or "Ready to configure a group round.")
    widgets.error:SetText(round and round.chatError and round.chatError or "")
    widgets.log:SetText(round and ("Recent group rolls:\n" .. table.concat(round.log, "\n")) or "")
end
