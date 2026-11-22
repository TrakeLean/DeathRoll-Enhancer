-- The Forever checkout opts into this view through its development manifest.
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
if not DRE.devDuel then return end
local AceGUI = LibStub("AceGUI-3.0")
local UI = DRE.UI

-- The accepter introduces itself after observing the opener. Both clients echo
-- the other's per-game ID before exchanging a cosmetic result over addon whispers.
local syncPrefix = "DREEmote1"
local invitePrefix = "DREInvite2"
local roundSerial = 0
local modes = {classic = "Classic", twoLives = "Two Lives", cursed7 = "Cursed 7", highRoller = "High Roller"}
local modeOrder = {"classic", "twoLives", "cursed7", "highRoller"}
local setupHints = {twoLives = "Two lives per player", cursed7 = "A 1 or 7 loses", highRoller = "First to 2 points"}
local rules = {
    twoLives = "A 1 costs a life. The other player restarts at the opening range. Lose both lives and you're out.",
    cursed7 = "Roll a 1 or a 7 and you lose.",
    highRoller = "Both roll the opening range. Higher roll scores a point. Ties replay. First to two points wins.",
}
DRE.duelModes, DRE.duelModeOrder = modes, modeOrder

function DRE:DuelSeriesWagerText(wager)
    return "Series wager  " .. self:FormatGold(wager * 2)
end

function DRE:DuelTermsText(terms)
    local mode = terms.mode or "classic"
    local text = rules[mode] and (modes[mode] .. " — " .. rules[mode]) or ""
    if terms.double then
        text = "Double or Nothing · " .. modes[mode] .. "\nChallenger wins: even. Challenger loses: "
            .. self:FormatGold(terms.wager * 2) .. " total."
    end
    return text
end

-- Both seats use the same transition, including practice and the invited opening roll.
function DRE:AdvanceDuelMode(game, playerName, roll, maximum, practice)
    local mine = game.playerTurn
    local seat = mine and "player" or "opponent"
    local other = mine and "opponent" or "player"
    local loser, detail
    game.rollCount = game.rollCount + 1
    if game.mode == "highRoller" then
        if game.firstFace == nil then
            game.duelRolls = {}
            game.firstFace = roll
            detail = "Score to beat: " .. roll
        else
            local first = game.firstFace
            game.firstFace = nil
            if first == roll then
                if not game.tiedPoint then
                    game.tiebreaks = (game.tiebreaks or 0) + 1
                    game.tiedPoint = true
                end
                detail = "Tie — replay the round"
            else
                local winner = roll > first and seat or other
                if game.tiedPoint and winner == "player" then game.tiebreakWins = (game.tiebreakWins or 0) + 1 end
                game.tiedPoint = nil
                game.score[winner] = game.score[winner] + 1
                detail = winner == "player" and "Your point" or "Opponent's point"
                if game.score[winner] == 2 then loser = winner == seat and other or seat end
            end
        end
    elseif game.mode == "twoLives" and roll == 1 then
        game.firstLifeLost = game.firstLifeLost or seat
        game.score[seat] = game.score[seat] - 1
        detail = mine and "You lost a life" or "Opponent lost a life"
        if game.score[seat] == 0 then loser = seat end
        game.currentRoll = game.initialRoll
    elseif game.mode == "cursed7" and (roll == 1 or roll == 7) then
        loser = seat
        detail = "Cursed roll"
    else
        game.currentRoll = roll
        detail = "Next roll 1–" .. roll
    end
    game.lastFace = roll
    self:AddRollToHistory(playerName, roll, maximum, practice, game.rollCount, detail)
    self:ChatPrint(playerName .. " rolled " .. roll .. ". " .. detail)
    if loser then
        local won = loser == "opponent"
        self:HandleGameEnd(won and game.target or self:GetUnitPlayerName("player"), won and "WIN" or "LOSS",
            game.wager, game.initialRoll, {opponent = game.target, recordedResult = won and "Won" or "Lost"})
    else
        game.playerTurn = not mine
        if game.playerTurn then self:PlayTurnSound() end
        self:UpdateGameUIState((practice or game.playerTurn) and "ROLLING" or "WAITING_FOR_OPPONENT")
    end
end

local function registerPrefix(prefix)
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if not register then return false end
    local ok, status = pcall(register, prefix)
    return ok and DRE:IsAccessibleValue(status) and (status == true or status == 0 or status == 1) -- Success or DuplicatePrefix
end

function DRE:EnableDuelMessages()
    self.groupMessagesEnabled = self.groupPrefix and registerPrefix(self.groupPrefix)
    self.inviteMessagesEnabled = registerPrefix(invitePrefix)
    self.emoteSyncEnabled = registerPrefix(syncPrefix)
    if self.inviteMessagesEnabled or self.emoteSyncEnabled or self.groupMessagesEnabled then
        self:RegisterEvent("CHAT_MSG_ADDON", "ReceiveDuelMessage")
    end
end

local function whisper(round, payload)
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if send then pcall(send, syncPrefix, payload, "WHISPER", round.opponent) end
end

local function newRoundId()
    roundSerial = roundSerial + 1
    return string.format("%08x%06x%08x", time(), math.random(0, 0xffffff), roundSerial)
end

function DRE:NewEmoteRound(opponent, maximum)
    return {id = newRoundId(), opponent = opponent, maximum = maximum}
end

local function acknowledge(round, peer)
    whisper(round, "A:" .. peer .. ":" .. round.id)
end

function DRE:ObserveEmoteOpener(round, isMine, roll)
    round.host, round.opener = isMine, roll
    if not isMine then
        whisper(round, string.format("J:%s:%d:%d", round.id, round.maximum, roll))
    elseif round.requestedRoll == roll then
        acknowledge(round, round.offered)
    else
        round.offered = nil
    end
end

local function sendPerformed(round)
    if round.peer and round.performed and not round.sent then
        round.sent = true
        whisper(round, "E:" .. round.peer .. ":" .. round.id .. ":" .. round.performed)
    end
end

function DRE:SharePerformedEmote(round, token)
    round.performed = token
    sendPerformed(round)
end

local function fromOpponent(sender, opponent)
    if DRE:IsSamePlayer(sender, opponent) then return true end
    -- Addon traffic can qualify a full Forever name with the local realm.
    -- Compare the complete expected address so hyphenated surnames stay intact.
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return DRE:IsAccessibleValue(sender) and DRE:IsAccessibleValue(realm)
        and type(realm) == "string" and realm ~= "" and sender == opponent .. "-" .. realm
end

function DRE:SendInviteMessage(message, target, replyTo)
    local modernSend = C_ChatInfo and C_ChatInfo.SendAddonMessage
    local send = modernSend or SendAddonMessage
    if not self.inviteMessagesEnabled or not send then return false, "addon channel unavailable" end
    local name = self:GetUnitPlayerName("player")
    if not name then return false, "your character name is unavailable" end
    local id = replyTo or newRoundId()
    local payload = id .. ":" .. name .. ":" .. message
    local ok, status = pcall(send, invitePrefix, payload, "WHISPER", target)
    if not ok or not self:IsAccessibleValue(status) then return false, "addon send failed" end
    if status ~= 0 and status ~= true and (modernSend or status ~= nil) then
        return false, "addon send failed (" .. tostring(status) .. ")"
    end
    return true, nil, id
end

function DRE:WithdrawDuelInvite()
    local invite = self.outgoingChallenge
    if not invite then return end
    self.outgoingChallenge = nil
    self:SendInviteMessage("DEATHROLL_WITHDRAW", invite.target, invite.id)
    self:RefreshDuel()
end

function DRE:InviteToDuel(target, roll, wager, trackTrade, terms)
    if self:HasActiveGame() or self.pendingChallenge or self.acceptedChallenge then return false end
    if trackTrade == nil then trackTrade = self:IsTradeWagerModeEnabled() end
    local sent, id = self:SendChallengeWhisper(target, roll, wager, trackTrade, terms)
    if not sent then return false end
    local timeout = self.Dialogs.DEATHROLL_CHALLENGE_POPUP.timeout
    local invite = {id = id, target = target, roll = roll, wager = wager, trackTrade = trackTrade, expires = GetTime() + timeout,
        mode = terms and terms.mode or "classic", double = terms and terms.double}
    self.outgoingChallenge = invite
    self:ClearRecentRollsForPlayer(target)
    self:RefreshDuel()
    C_Timer.After(timeout, function()
        if self.outgoingChallenge == invite then
            self:WithdrawDuelInvite()
            self:Print("Invitation to " .. target .. " expired. Both players need the updated dev build for silent invites. For a manual duel, turn off Send Challenge Invites.")
        end
    end)
    return true
end

function DRE:ReceiveDuelMessage(event, prefix, payload, channel, sender)
    if self.disabled or not self:IsAccessibleValue(prefix) then return end
    if self.groupMessagesEnabled and prefix == self.groupPrefix then
        return self:ReceiveGroupMessage(payload, channel, sender)
    end
    if prefix == syncPrefix then return self:ReceiveEmoteSync(event, prefix, payload, channel, sender) end
    if prefix ~= invitePrefix or not self.inviteMessagesEnabled or not self:IsAccessibleValue(channel) or channel ~= "WHISPER"
        or not self:IsAccessibleValue(payload) or type(payload) ~= "string" or #payload > 255 then return end
    local id, name, message = payload:match("^(%x+):([^:]+):(.+)$")
    if not id or #id ~= 22 or not self:IsValidPlayerName(name) then return end
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        if not fromOpponent(sender, name) then return end
    else
        -- For realm-based names the receiver needs the server's full sender address.
        name = self:NormalizePlayerName(sender)
        if not name then return end
    end
    if message:match("^DEATHROLL_CHALLENGE:") then
        self:HandleChallengeWhisper(message, name, id)
    elseif message == "DEATHROLL_ACCEPT" or message == "DEATHROLL_DECLINE" then
        local invite = self.outgoingChallenge
        if not invite or invite.id ~= id or not self:IsSamePlayer(invite.target, name) then return end
        if GetTime() >= invite.expires then self:WithdrawDuelInvite(); return end
        self.outgoingChallenge = nil
        if message == "DEATHROLL_ACCEPT" then
            if invite.double and not self:MatchesDoubleOffer(invite, invite.target, "Lost") then
                self:SendInviteMessage("DEATHROLL_WITHDRAW", invite.target, invite.id)
                self:RefreshDuel()
                return
            end
            self:StartDeathRoll(invite.target, invite.roll, invite.wager, invite.trackTrade, invite)
        end
        self:RefreshDuel()
        self:Print(name .. (message == "DEATHROLL_ACCEPT" and " accepted your DeathRoll challenge!" or " declined your DeathRoll challenge."))
    elseif message == "DEATHROLL_WITHDRAW" then
        local invite = self.pendingChallenge or self.acceptedChallenge
        if not invite or invite.inviteId ~= id or not self:IsSamePlayer(invite.sender, name) then return end
        if self.pendingChallenge == invite then self.pendingChallenge = nil end
        if self.acceptedChallenge == invite then self.acceptedChallenge = nil end
        if self.activeDialog and self.activeDialog.data == invite then self:CloseDialog(self.activeDialog, false, "override") end
        self:ClearRecentRollsForPlayer(name)
        self:RefreshDuel()
    end
end

function DRE:ReceiveEmoteSync(_, prefix, payload, channel, sender)
    if self.disabled or not self.emoteSyncEnabled or not self:IsAccessibleValue(prefix) or prefix ~= syncPrefix
        or not self:IsAccessibleValue(channel) or channel ~= "WHISPER"
        or not self:IsAccessibleValue(payload) or type(payload) ~= "string" or #payload > 96 then return end
    local result = UI.duelResult
    local round = self.gameState and self.gameState.emoteRound or (result and result.emoteRound)
    if not round or not fromOpponent(sender, round.opponent)
        or (round.finishedAt and GetTime() - round.finishedAt > (self.recentRollTimeWindow or 60) + 2) then return end

    local peer, maximum, opener = payload:match("^J:(%x+):(%d+):(%d+)$")
    if peer then
        if #peer ~= 22 or round.host == false or round.peer or tonumber(maximum) ~= round.maximum then return end
        opener = tonumber(opener)
        if not self:IsBoundedInteger(opener, 1, round.maximum) or (round.opener and round.opener ~= opener) then return end
        round.offered, round.requestedRoll = peer, opener
        if round.host then acknowledge(round, peer) end
        return
    end

    local addressed
    addressed, peer = payload:match("^A:(%x+):(%x+)$")
    if addressed then
        if addressed ~= round.id or #peer ~= 22 or round.peer or round.host == nil then return end
        if round.host and peer ~= round.offered then return end
        round.peer = peer
        if not round.host then acknowledge(round, peer) end
        sendPerformed(round)
        return
    end

    local token
    addressed, peer, token = payload:match("^E:(%x+):(%x+):([A-Z]+)$")
    if addressed ~= round.id or (peer ~= round.peer and peer ~= round.offered) or round.received then return end
    if not self:IsResultEmote(true, token) and not self:IsResultEmote(false, token) then return end
    if result and not self:IsResultEmote(result.result == "Lost", token) then return end
    round.received = token
    if result and UI.tableHero then UI.tableHero:SyncOpponentReaction(result) end
end

local function money(amount)
    if amount == nil then return "Unavailable" end
    return GetCoinTextureString and GetCoinTextureString(amount) or DRE:FormatGold(amount)
end

local function label(parent, font)
    local widget = AceGUI:Create("Label")
    widget:SetFullWidth(true)
    widget:SetFontObject(font)
    parent:AddChild(widget)
    return widget
end

local function button(parent, caption, width, click)
    local widget = DRE:CreateWindowWidget("Button")
    widget:SetRelativeWidth(width)
    widget:SetText(caption)
    widget:SetCallback("OnClick", click)
    parent:AddChild(widget)
    return widget
end

local function metric(parent, caption, width)
    local widget = AceGUI:Create("DRETableMetric")
    widget:SetLabel(caption)
    widget:SetRelativeWidth(width)
    parent:AddChild(widget)
    return widget
end

local function numberField(parent, caption, value, digits, width)
    local widget = DRE:CreateWindowWidget("EditBox")
    widget:SetRelativeWidth(width)
    widget:SetLabel(caption)
    widget:SetText(tostring(value))
    widget:SetMaxLetters(digits)
    widget:DisableButton(true)
    widget:SetCallback("OnTextChanged", function(edit, _, text)
        local number = text:gsub("%D", ""):sub(1, digits)
        if text ~= number then edit:SetText(number) end
    end)
    parent:AddChild(widget)
    return widget
end

local function pendingFor(result)
    local ownerGUID = DRE:GetTradeOwnerGUID()
    if not ownerGUID then return end
    for _, item in ipairs(DRE.db.profile.pendingTradeWagers or {}) do
        if item.ownerGUID == ownerGUID and item.gameId == result.gameId and DRE:IsSamePlayer(item.playerName, result.playerName) then
            return item
        end
    end
end

function DRE:RememberDuelResult(id, opponent, result, wager, recordedAt, tracked, rolls, game)
    if not game then
        local _, _, record = self:FindGameRecordById(id)
        game = record or {}
    end
    if not rolls and (game.playerFace or game.opponentFace) then rolls = {player = game.playerFace, opponent = game.opponentFace} end
    local score = game.score or (game.playerScore and {player = game.playerScore, opponent = game.opponentScore})
    local item = {gameId = id, playerName = opponent, result = result, wager = wager or 0,
        mode = game.mode or "classic", initialRoll = game.initialRoll, matchId = game.matchId or "manual",
        double = game.double, proposedDouble = game.proposedDouble, lastFace = game.lastFace, score = score,
        recordedAt = recordedAt, tracked = tracked, rematchInvalid = game.rematchInvalid, outcomeEdited = game.outcomeEdited,
        rolls = rolls or ((game.mode == "highRoller" or game.outcomeEdited) and {}) or {[result == "Won" and "opponent" or "player"] = game.lastFace or 1}}
    UI.duelResult = item
    UI.lastDuelResult = item
    UI.duelRestored = true
    if tracked then
        local delay = math.max(0, recordedAt + self.TRADE_WAGER_TIMEOUT + 1 - time())
        C_Timer.After(delay, function()
            if UI.duelResult == item then self:RefreshDuel() end
        end)
    end
end

local function seriesIsEven(result)
    return (result.result == "Won") == result.proposedDouble
end

local function rematchStake(result)
    if not result or result.rematchInvalid or not result.initialRoll or result.initialRoll < 2 then return end
    local stake = result.wager
    if result.tracked then stake = result.paid end
    if not stake or stake <= 0 then return end
    if result.double then
        -- A comeback closes the series at even for both players.
        if seriesIsEven(result) then return end
        stake = stake * 2
    end
    if stake <= DRE.MAX_WAGER then return stake end
end

function DRE:MatchesDoubleOffer(terms, opponent, outcome)
    local prior = UI.lastDuelResult
    if not prior or prior.result ~= outcome or not self:IsSamePlayer(opponent, prior.playerName)
        or terms.double ~= prior.matchId or terms.mode ~= prior.mode or terms.roll ~= prior.initialRoll
        or terms.wager ~= rematchStake(prior) then return false end
    local name, _, record = self:FindGameRecordById(prior.gameId)
    return self:IsSamePlayer(name, opponent) and record and record.result == outcome
        and record.goldAmount == (prior.paid or prior.wager) and record.initialRoll == prior.initialRoll
end

local function offerDouble(result)
    if UI.duelResult ~= result or DRE:HasActiveGame() or DRE.pendingChallenge or DRE.acceptedChallenge then return end
    local terms = {mode = result.mode, double = result.matchId, wager = rematchStake(result), roll = result.initialRoll}
    if not terms.wager or not DRE:MatchesDoubleOffer(terms, result.playerName, "Lost") then return end
    if DRE:IsSamePlayer(result.playerName, DRE:GetUnitPlayerName("player")) then
        DRE:StartDeathRoll(result.playerName, terms.roll, terms.wager, false, terms)
    else
        DRE:InviteToDuel(result.playerName, terms.roll, terms.wager, false, terms)
    end
end

function DRE:ReviewDuelTrade(partner)
    local trade = self.tradeTracking
    for _, pending in ipairs(self.db.profile.pendingTradeWagers or {}) do
        local offered = pending.result == "Won" and trade.theirGold or trade.myGold
        if trade.ownerGUID and pending.ownerGUID == trade.ownerGUID and self:IsSamePlayer(pending.playerName, partner) and offered > 0 then
            pending.duelPaymentReview = true
        end
    end
    self:RefreshDuel()
end

function DRE:ConfirmDuelPayment(pending, amount)
    -- A saved pending game can settle after login, before the window first opens.
    if not UI.duelRestored then
        self:RememberDuelResult(pending.gameId, pending.playerName, pending.result, 0, pending.recordedAt, true)
    end
    local result = UI.lastDuelResult
    if result and result.gameId == pending.gameId and self:IsSamePlayer(result.playerName, pending.playerName) then
        result.paid = amount
        self:RefreshDuel()
    end
end

-- A merge can move the displayed game to another history entry. A reset removes it.
function DRE:RefreshDuelResultFromHistory()
    local result = UI.lastDuelResult
    if not result then return end
    local opponent = self:FindGameRecordById(result.gameId)
    if opponent == result.playerName then return end
    if opponent then
        result.playerName = opponent
    else
        UI.lastDuelResult = nil
        UI.duelResult = nil
    end
    self:RefreshDuel()
end

function DRE:UpdateEditedDuel(id, outcome, wager, stillPending, record, settlementChanged)
    local result = UI.lastDuelResult
    if not result or result.gameId ~= id then return end
    if outcome then
        -- Edited terms no longer describe the series the two players accepted.
        if result.double and settlementChanged and (result.result ~= outcome or result.wager ~= wager) then
            result.double, result.proposedDouble = nil, nil
        end
        if result.result ~= outcome then
            result.rolls = {}
            result.score, result.lastFace, result.outcomeEdited = nil, nil, true
            result.emoteRound = nil
            if UI.tableHero then UI.tableHero:StopGestures() end
        end
        result.result = outcome
        result.initialRoll, result.rematchInvalid = record.initialRoll, record.rematchInvalid
        if settlementChanged then result.wager, result.paid, result.tracked = wager, nil, stillPending end
    else
        UI.lastDuelResult = nil
        UI.duelResult = nil
    end
    self:RefreshDuel()
end

local function payout(result)
    if result.double then
        if seriesIsEven(result) then return "Series even  ·  0g" end
        return (result.result == "Won" and "Series win  " or "Series loss  ") .. money(result.wager * 2)
    end
    if DRE:IsSamePlayer(result.playerName, DRE:GetUnitPlayerName("player")) then return "Practice duel" end
    if not result.tracked then return "Wager  " .. money(result.wager) end
    if result.paid then
        local verb = result.result == "Won" and "Received " or "Paid "
        local preposition = result.result == "Won" and " from " or " to "
        return verb .. money(result.paid) .. preposition .. result.playerName
    end
    if time() - result.recordedAt > DRE.TRADE_WAGER_TIMEOUT then return "Payment window expired", true end
    local pending = pendingFor(result)
    if not pending then return "Payment tracking closed" end
    if pending.manualAssignmentRequired or pending.duelPaymentReview then return "Review payment", true end
    local trade = DRE.tradeTracking
    if trade and not trade.closedAt and not trade.completed and DRE:IsSamePlayer(trade.partner, result.playerName) then
        return "You offer  " .. money(trade.myGold) .. "     They offer  " .. money(trade.theirGold)
    end
    return "Awaiting payment"
end

local function newDuel()
    UI.duelResult = nil
    UI.duelMode = nil
    DRE:RefreshDuel()
end

local function restorePending()
    if UI.duelRestored then return end
    local ownerGUID = DRE:GetTradeOwnerGUID()
    if not ownerGUID then return end
    UI.duelRestored = true
    local records = DRE:PrunePendingTradeWagers()
    local pending = DRE.db.profile.pendingTradeWagers or {}
    for i = #pending, 1, -1 do
        local p = pending[i]
        if p.ownerGUID == ownerGUID then
            DRE:RememberDuelResult(p.gameId, p.playerName, p.result, 0, p.recordedAt, true, nil, records[p.gameId].game)
            return
        end
    end
end

local function createWidgets(pane, phase, review, tradeWager, accepted, doubleStake)
    UI.rollEdit, UI.goldEdit, UI.silverEdit, UI.copperEdit = nil, nil, nil, nil
    pane:ReleaseChildren()
    pane:SetScroll(0)
    local footer = UI.tableFooter
    footer:ReleaseChildren()
    local w = {phase = phase, review = review, tradeWager = tradeWager, accepted = accepted, doubleStake = doubleStake}
    local hero = UI.tableHero
    -- Animate changes within an open duel. A newly selected tab starts at its final size.
    hero:SetDuelPhase(phase, UI.duelWidgets ~= nil and phase ~= "group" and UI.duelWidgets.phase ~= "group")
    w.heading, w.detail = hero.heading, hero.detail
    w.heading:SetTextColor(0.99, 0.94, 0.86)
    local titles = {setup = "DUEL CHALLENGE", inviting = "DUEL CHALLENGE", result = "DUEL RESULT", group = "GROUP ROUND"}
    hero.stage:SetText(titles[phase] or "")
    if phase == "setup" then
        UI.rollEdit = numberField(pane, "Starting roll", UI.inputRoll or DRE:GetDefaultStartingRoll(), 6, 11/32)
        w.useGold = button(pane, "Use My Gold", 10/32, function() UI.rollEdit:SetText(tostring(DRE:CalculateAutoRoll())) end)
        w.useGold:SetDisabled(accepted ~= nil)
        w.mode = DRE:CreateTableDropdownField(pane, "Mode", 11/32)
        w.mode:SetList(modes, modeOrder)
        w.mode:SetValue(accepted and accepted.mode or UI.duelMode or "classic")
        w.mode:SetDisabled(accepted ~= nil)
        w.mode:SetCallback("OnValueChanged", function(_, _, value)
            if not accepted and modes[value] then UI.duelMode = value; DRE:RefreshDuel() end
        end)
        if accepted and accepted.double then
            label(pane, GameFontHighlightSmall):SetText(DRE:DuelTermsText(accepted))
        elseif not tradeWager then
            -- Binary fractions keep all three fields on one Flow row at fractional widths.
            UI.goldEdit = numberField(pane, "Gold", 0, 6, 13/32)
            UI.silverEdit = numberField(pane, "Silver", 0, 2, 19/64)
            UI.copperEdit = numberField(pane, "Copper", 0, 2, 19/64)
            DRE:SetWagerInputs(accepted and accepted.wager or UI.inputWager)
        else
            local note = label(pane, GameFontHighlightSmall)
            note:SetText("|cffdbb180Settlement|r   Gold is recorded when the trade completes.")
        end
        w.action = button(footer, "Challenge", accepted and 0.66 or 1, function()
            if UI.duelWidgets ~= w or DRE.acceptedChallenge ~= accepted then return end
            if w.observed then
                DRE:AcceptObservedChallenge(w.observed)
            elseif not DRE.acceptedChallenge then
                DRE:StartChallengeFlow()
            end
        end)
        if accepted then
            button(footer, "Dismiss", 0.34, function()
                if DRE.acceptedChallenge ~= accepted then return end
                DRE.acceptedChallenge = nil
                DRE:ClearRecentRollsForPlayer(accepted.sender)
                DRE:RefreshDuel()
            end)
        end
    elseif phase == "inviting" then
        w.action = button(footer, "Cancel invitation", 1, function()
            if UI.duelWidgets == w then DRE:CancelCurrentGame() end
        end)
    elseif phase == "active" then
        w.action = button(footer, "Roll", 0.69, function() DRE:PerformRoll() end)
        button(footer, "Cancel duel", 0.31, function() DRE:CancelCurrentGame() end)
        local game = DRE.gameState
        local title = game.double and rules[game.mode] and (modes[game.mode] .. "  ·  Roll history") or "Roll history"
        label(pane, GameFontNormal):SetText(title)
        w.log = label(pane, GameFontHighlightSmall)
    elseif phase == "result" then
        w.payment = metric(pane, "SETTLEMENT", 1)
        w.payment:SetHeight(80)
        if review then
            local id = UI.duelResult.gameId
            button(footer, "Review payment", 0.5, function() DRE:ShowEditGameDialog(id) end)
        end
        if doubleStake then
            w.doubleTerms = label(pane, GameFontHighlightSmall)
            w.double = button(footer, "Double or Nothing", 0.5, function() offerDouble(UI.duelResult) end)
        end
        w.action = button(footer, "New duel", (review or doubleStake) and 0.5 or 1, newDuel)
    else
        w.action = button(footer, "Open group", 1, function() DRE:SelectMainSection("group") end)
    end
    w.action:SetPrimary(true)
    for _, control in ipairs(footer.children) do control:SetHeight(44) end
    footer:DoLayout()
    UI.duelWidgets = w
    return w
end

local function showSetup(w, tradeWager)
    local target = DRE:GetUnitPlayerName("target")
    local isPlayer = target and UnitIsPlayer("target")
    local validTarget = DRE:IsAccessibleValue(isPlayer) and isPlayer
    local accepted = DRE.acceptedChallenge
    local observed
    if accepted then
        local opener = accepted.opener
        if opener and GetTime() - opener.timestamp <= (DRE.recentRollTimeWindow or 60) then observed = opener end
    elseif validTarget and (UI.duelMode or "classic") == "classic" then
        observed = DRE:FindRecentTargetRoll(target)
    end
    if observed and w.observed ~= observed then
        local delay = observed.timestamp + (DRE.recentRollTimeWindow or 60) + 1 - GetTime()
        C_Timer.After(math.max(0, delay), function()
            if UI.duelWidgets == w and w.observed == observed then DRE:RefreshDuel() end
        end)
    end
    w.observed = observed
    local practice = validTarget and DRE:IsSamePlayer(target, DRE:GetUnitPlayerName("player"))
    UI.tableHero:SetOpponent(accepted and accepted.sender or (validTarget and target or nil))
    UI.tableHero:SetRolls(accepted and not observed and "opponent" or nil, nil, observed and observed.roll)
    w.heading:SetText(accepted and "Challenge accepted" or (practice and "Practice duel") or (validTarget and "Ready to duel" or "Target a player"))
    local mode = tradeWager and "Wager from trade" or "Fixed wager"
    local variant = accepted and accepted.mode or UI.duelMode or "classic"
    if accepted and accepted.double then
        w.detail:SetText(DRE:DuelSeriesWagerText(accepted.wager))
    elseif observed then
        w.detail:SetText(string.format("%s rolled %d (1–%d)  ·  %s", observed.playerName, observed.roll, observed.maxRoll, mode))
    elseif accepted then
        local terms = tradeWager and mode or ("Wager " .. money(accepted.wager))
        w.detail:SetText(string.format("%s  ·  Roll 1–%d  ·  %s", accepted.sender, accepted.roll, terms))
    else
        w.detail:SetText(setupHints[variant] or mode)
    end
    w.action:SetText(observed and "Accept opening roll" or (accepted and "Waiting for roll" or "Challenge"))
    if not observed and not accepted and not practice and variant ~= "classic" then w.action:SetText("Invite to " .. modes[variant]) end
    w.action:SetDisabled(DRE.pendingChallenge ~= nil or (accepted ~= nil and not observed) or (not accepted and not validTarget))
    -- An accepted whisper fixes these inputs to the terms shown in its dialog.
    UI.rollEdit:SetDisabled(accepted ~= nil)
    for _, edit in ipairs({UI.goldEdit, UI.silverEdit, UI.copperEdit}) do edit:SetDisabled(accepted ~= nil) end
end

function DRE:RefreshDuel()
    local pane = UI.duelPane
    if not pane or self.disabled then return end
    local game, result = self.gameState, UI.duelResult
    local phase = (self:IsGroupRoundActive() or self:IsGroupGuest()) and "group" or (game and game.isActive and "active")
        or (self.outgoingChallenge and "inviting") or (result and "result") or "setup"
    local payment, review, doubleStake
    if phase == "result" then
        payment, review = payout(result)
        if result.result == "Lost" then doubleStake = rematchStake(result) end
    end
    local tradeWager = phase == "setup" and self:IsTradeWagerModeEnabled()
    local w = UI.duelWidgets
    local accepted = phase == "setup" and self.acceptedChallenge or nil
    if accepted then tradeWager = accepted.trackTrade end
    if not w or w.phase ~= phase or w.review ~= review or w.tradeWager ~= tradeWager or w.accepted ~= accepted or w.doubleStake ~= doubleStake then
        w = createWidgets(pane, phase, review, tradeWager, accepted, doubleStake)
    end
    if phase == "setup" then
        showSetup(w, tradeWager)
    elseif phase == "inviting" then
        local invite = self.outgoingChallenge
        UI.tableHero:SetOpponent(invite.target)
        UI.tableHero:SetRolls(nil)
        w.heading:SetText(invite.double and "Double or Nothing" or "Waiting for acceptance")
        if invite.double then
            w.detail:SetText(self:DuelSeriesWagerText(invite.wager))
        else
            w.detail:SetText(string.format("Roll 1–%d  ·  %s", invite.roll, invite.trackTrade and "Wager from trade" or ("Wager  " .. money(invite.wager))))
            if invite.mode ~= "classic" then w.detail:SetText(modes[invite.mode] .. "  ·  " .. w.detail:GetText()) end
        end
    elseif phase == "active" then
        UI.tableHero:SetOpponent(game.target)
        local rolls = game.duelRolls
        UI.tableHero:SetRolls(game.playerTurn and "player" or "opponent", rolls and rolls.player, rolls and rolls.opponent, game.mode == "highRoller")
        local practice = self:IsSamePlayer(game.target, self:GetUnitPlayerName("player"))
        local turn = game.playerTurn or practice
        local heading = turn and "Your turn" or "Their turn"
        if practice then heading = "Practice turn " .. (game.rollCount + 1) end
        w.heading:SetText(game.pendingRoll and "Rolling…" or heading)
        UI.tableHero.stage:SetText(string.format("Next roll  1–%d", game.currentRoll))
        UI.tableHero:SetNextRollOdds(game.currentRoll)
        UI.tableHero:SetDuelScore(game.mode, game.score)
        if game.double then
            w.detail:SetText(self:DuelSeriesWagerText(game.wager))
        else
            w.detail:SetText(game.trackWagerByTrade and "Wager from trade" or ("Wager  " .. money(game.wager)))
            if rules[game.mode] then w.detail:SetText(modes[game.mode] .. "  ·  " .. w.detail:GetText()) end
        end
        w.action:SetText(game.pendingRoll and "Rolling…" or (turn and ("Roll 1–" .. game.currentRoll) or "Waiting for roll"))
        w.action:SetDisabled(not turn or game.pendingRoll ~= nil)
        local entries = {}
        for i = #UI.rollHistory, 1, -1 do entries[#entries + 1] = UI.rollHistory[i] end
        w.log:SetText(table.concat(entries, "\n"))
    elseif phase == "result" then
        UI.tableHero:SetOpponent(result.playerName)
        UI.tableHero:SetRolls(nil, result.rolls.player, result.rolls.opponent)
        w.heading:SetText(result.result == "Won" and "You won" or "You lost")
        if result.result == "Won" then
            w.heading:SetTextColor(0.65, 0.93, 0.75)
        else
            w.heading:SetTextColor(1, 0.68, 0.62)
        end
        UI.tableHero:SetDuelScore(result.mode, result.score)
        if result.mode == "highRoller" then
            local score = result.score
            w.detail:SetText(score and string.format("High Roller  ·  %d–%d", score.player, score.opponent) or "High Roller")
        else
            w.detail:SetText(result.outcomeEdited and "" or ("Final roll " .. (result.lastFace or 1)))
        end
        if doubleStake then
            w.doubleTerms:SetText("Double or Nothing: win to break even, lose to reach " .. money(2 * doubleStake) .. " total.")
        end
        w.payment:SetText(payment)
    else
        UI.tableHero:SetOpponent(nil)
        w.heading:SetText(self:IsGroupGuest() and ("Table hosted by " .. self.sharedTable.host) or "Group round in progress")
        w.detail:SetText("Return to the group to continue.")
    end
    pane:DoLayout()
end

function DRE:CreateDuelSection(container)
    restorePending()
    local pane = AceGUI:Create("ScrollFrame")
    pane:SetLayout("Flow")
    pane:SetFullWidth(true)
    pane:SetFullHeight(true)
    container:AddChild(pane)
    UI.duelPane = pane
    self:RefreshDuel()
end
