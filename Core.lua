-- Core.lua
-- Main addon initialization using Ace3 framework

local addonName, addonTable = ...

-- Declare saved variables for debug export
DeathRollEnhancer_DebugExport = DeathRollEnhancer_DebugExport or {}

-- Check for required libraries
if not LibStub then
    error("DeathRollEnhancer requires LibStub")
    return
end

-- Initialize addon with Ace3
local DRE = LibStub("AceAddon-3.0"):NewAddon("DeathRollEnhancer", "AceConsole-3.0", "AceEvent-3.0")

-- TBC Compatibility: C_Timer shim for older WoW versions
if not C_Timer then
    C_Timer = {
        After = function(duration, callback)
            -- Fallback implementation using frame OnUpdate for TBC/Classic
            local waitFrame = CreateFrame("Frame")
            local elapsed = 0
            waitFrame:SetScript("OnUpdate", function(self, delta)
                elapsed = elapsed + delta
                if elapsed >= duration then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                    callback()
                end
            end)
        end
    }
end

-- Debug chat buffer to track messages
DRE.debugChatBuffer = {}
DRE.maxDebugMessages = 40

-- Addon information
local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
DRE.title = (getMetadata and getMetadata(addonName, "Title")) or "DeathRoll Enhancer"
DRE.displayName = DRE.title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
DRE.devDuel = getMetadata and getMetadata(addonName, "X-DRE-DuelUI") == "1"

-- Replaced by CurseForge packager on tagged builds.
local localFallbackVersion = "2.4.2"
DRE.version = "@project-version@"
if not DRE.version or DRE.version == "" or DRE.version:sub(1, 1) == "@" then
    local metadataVersion = getMetadata and getMetadata(addonName, "Version")

    if metadataVersion and metadataVersion ~= "" and metadataVersion:sub(1, 1) ~= "@" then
        DRE.version = metadataVersion
    else
        DRE.version = localFallbackVersion
    end
end

if type(DRE.version) == "string" then
    DRE.version = DRE.version:gsub("^v", "")
end
DRE.author = "0xTrk"

-- Utility: safe trim for user input (WoW Lua doesn't provide string:trim())
function DRE:Trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

-- Import libraries with safety checks
local AceGUI = LibStub("AceGUI-3.0", true)
local AceConfig = LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
local AceDB = LibStub("AceDB-3.0", true)
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Check for essential libraries
if not AceGUI then
    error("DeathRollEnhancer: AceGUI-3.0 library not found. Please install Ace3.")
    return
end

if not AceDB then
    error("DeathRollEnhancer: AceDB-3.0 library not found. Please install Ace3.")
    return
end

-- Default database structure
local defaults = {
    profile = {
        minimap = {
            hide = false,
            minimapPos = 225,
            lock = false,
        },
        ui = {
            scale = 0.9,
            groupAppearance = "portraits",
            groupAnnounceChannel = "NONE",
            framePos = {
                point = "CENTER",
                x = 0,
                y = 0,
            },
            frameWidth = 400,
            frameHeight = 300,
        },
        gameplay = {
            autoEmote = true,
            soundEnabled = true,
            defaultStartingRoll = 100,
            autoRollFromMoney = false,
            chatMessages = false,
            debugMessages = false,
        },
        challengeSystem = {
            enabled = true,
            sendWhisper = true,
            minRollThreshold = 100,
            trackWagerByTrade = false,
        },
        suspiciousRolls = {},
        history = {},
        goldTracking = {
            totalWon = 0,
            totalLost = 0,
            currentStreak = 0,
            bestWinStreak = 0,
            worstLossStreak = 0,
        },
        funStats = {
            showMostPlayedWith = true,
            showMostWinsAgainst = true,
            showMostLossesAgainst = true,
            showFrenemy = true,
            showLikelyCheater = true,
            showMostMoneyWonFrom = true,
            showMostMoneyLostTo = true,
            showBestMatchup = true,
            showWorstMatchup = true,
            showBiggestWin = true,
            showBiggestLoss = true,
            showLuckyPlayer = true,
            showUnluckyPlayer = true,
            showNemesis = true,
            showVictim = true,
            showHighRoller = true,
            showCheapskate = true,
            showDaredevil = true,
            showConservative = true,
        },
    },
}

DRE.groupStatOptions = {
    {key = "showGroupRecord", label = "My group record"},
    {key = "showGroupRegulars", label = "Table regulars"},
    {key = "showGroupLongest", label = "Longest round"},
    {key = "showGroupEscapes", label = "Closest calls"},
}
for _, option in ipairs(DRE.groupStatOptions) do defaults.profile.funStats[option.key] = true end

function DRE:SetStatPreference(key, value)
    self.db.profile.funStats[key] = value
    if self.devDuel and (self.UI.currentTab == "statistics" or self.UI.currentTab == "history") then
        self:UpdateStatsDisplay()
    end
end

-- Ace3 addon lifecycle methods
function DRE:OnInitialize()
    -- Initialize database
    self.db = AceDB:New("DeathRollEnhancerDB", defaults, true)
    self:CleanupLegacyFunStatSettings()
    self:EnsureHistorySchema()
    self:PrunePendingTradeWagers()

    -- Initialize recent rolls storage for challenge detection
    self.recentRolls = {}
    self.maxRecentRolls = 10
    self.recentRollTimeWindow = 60 -- seconds

    -- Initialize processed rolls cache to prevent duplicate processing
    self.processedRolls = {}
    self.processedRollsExpiry = 5 -- seconds to remember a processed roll

    -- Register options
    self:SetupOptions()

    -- Register slash commands
    self:RegisterChatCommand("deathroll", "SlashCommand")
    self:RegisterChatCommand("dr", "SlashCommand")
    self:RegisterChatCommand("drh", "HistoryCommand")
    self:RegisterChatCommand("deathrollhistory", "HistoryCommand")

    self:Print(self.displayName .. " v" .. self.version .. " loaded!")

    -- Test debug buffer
    self:AddToDebugBuffer("SYSTEM", "Addon loaded and debug buffer initialized")
end

function DRE:CleanupLegacyFunStatSettings()
    if not self.db or not self.db.profile or not self.db.profile.funStats then
        return
    end

    local legacyKeys = {
        "showGoldMinePlayer",
        "showMoneySinkPlayer",
        "showLongestWinStreak",
        "showLongestLossStreak",
        "showAvgWager"
    }

    local removedCount = 0
    for _, key in ipairs(legacyKeys) do
        if self.db.profile.funStats[key] ~= nil then
            self.db.profile.funStats[key] = nil
            removedCount = removedCount + 1
        end
    end

    if removedCount > 0 then
        self:DebugPrint(string.format("Removed %d legacy fun-stat toggle keys from profile.", removedCount))
    end
end

function DRE:OnEnable()
    self.disabled = false
    self:DebugPrint("OnEnable called - registering events...")
    
    -- Register core events
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("UI_INFO_MESSAGE")
    
    -- Register game-related events (CHAT_MSG_WHISPER for spicy duels)
    self:RegisterEvent("CHAT_MSG_WHISPER")
    if self.EnableDuelMessages then self:EnableDuelMessages() end
    if self.groupMessagesEnabled then self:RestoreSharedTable() end
    
    -- Only server system messages are authoritative dice results.
    
    -- Register target change event to update button text
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    
    -- Register trade events for optional wager tracking
    self:RegisterEvent("TRADE_SHOW")
    self:RegisterEvent("TRADE_MONEY_CHANGED")
    self:RegisterEvent("PLAYER_TRADE_MONEY", "TRADE_MONEY_CHANGED")
    self:RegisterEvent("TRADE_ACCEPT_UPDATE")
    self:RegisterEvent("TRADE_CLOSED")
    self:RegisterEvent("TRADE_REQUEST_CANCEL")
    
    self:DebugPrint("Events registered: CHAT_MSG_SYSTEM, ADDON_LOADED, UI_INFO_MESSAGE, CHAT_MSG_WHISPER, CHAT_MSG_TEXT_EMOTE, CHAT_MSG_EMOTE, PLAYER_TARGET_CHANGED, TRADE_*")
    
    -- Initialize modules
    self:InitializeUI()
    self:InitializeMinimap()
    self:InitializeSharedMedia()
end

function DRE:OnDisable()
    if self.sharedTable then self:LeaveSharedTable() end
    self.disabled = true
    if self.outgoingChallenge then self:WithdrawDuelInvite() end
    self:CancelGroupRound(true)
    self.tradeTracking = nil
    self.pendingChallenge = nil
    self.acceptedChallenge = nil
    self:CloseDialog(self.activeDialog, false, "override")
    self:CleanupUI()
    self:CleanupMinimap()
    -- Cleanup active game state
    if self.gameState and self.gameState.isActive then
        self:DebugPrint("OnDisable: Cleaning up active game state")
        self.gameState = nil
    end

    -- Cleanup spicy duel state
    if self.spicyDuel and self.spicyDuel.isActive then
        self:DebugPrint("OnDisable: Cleaning up active spicy duel state")
        self.spicyDuel = nil
    end

    -- Clear UI references
    if self.UI then
        self.UI.recentTargetRoll = nil
        self.UI.incomingChallenge = nil
        self.UI.isGameActive = false
        self:UpdateGameUIState("WAITING")
    end

    -- Cleanup
    self:UnregisterAllEvents()
end

-- Utility functions
function DRE:CusRound(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

local happyEmotes = {"CHEER", "LAUGH", "SALUTE", "DANCE", "VICTORY"}
local sadEmotes = {"CRY", "SIGH", "SURRENDER", "LAY", "CONGRATULATE"}

function DRE:IsResultEmote(won, token)
    for _, emote in ipairs(won and happyEmotes or sadEmotes) do
        if emote == token then return true end
    end
    return false
end

function DRE:GetRandomHappyEmote()
    return happyEmotes[math.random(1, #happyEmotes)]
end

function DRE:GetRandomSadEmote()
    return sadEmotes[math.random(1, #sadEmotes)]
end

-- Calculate auto-roll number from player's total money
function DRE:CalculateAutoRoll()
    local totalMoney = GetMoney() -- Returns total money in copper
    if totalMoney <= 0 then
        return 100 -- Default fallback
    end

    -- Apply modulo 999999 to stay within roll limits
    local rollValue = totalMoney % 999999

    -- Ensure it's at least 2 (minimum roll value)
    if rollValue < 2 then
        rollValue = 2
    end

    return rollValue
end

function DRE:IsTradeWagerModeEnabled()
    return self.db
        and self.db.profile
        and self.db.profile.challengeSystem
        and self.db.profile.challengeSystem.trackWagerByTrade == true
end

local function tradeUnitGUID(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if DRE:IsAccessibleValue(guid) and type(guid) == "string" and guid ~= "" then return guid end
end

function DRE:GetTradeOwnerGUID()
    return tradeUnitGUID("player")
end

function DRE:CaptureTradeState(resetState)
    if self.disabled then return end
    if resetState then
        self.tradeTracking = { ownerGUID = self:GetTradeOwnerGUID(), myGold = 0, theirGold = 0 }
    end
    local state = self.tradeTracking
    -- Only TRADE_SHOW creates a transaction. Preserve the last visible offer
    -- after close; teardown/late events must not overwrite it with zeroes.
    if not state or state.closedAt or state.completed then return end
    if not resetState and TradeFrame and TradeFrame.IsShown and not TradeFrame:IsShown() then return end

    -- The recipient label can still belong to the previous trade at TRADE_SHOW.
    local isPlayer = UnitIsPlayer("NPC")
    local partner, guid
    if self:IsAccessibleValue(isPlayer) and isPlayer then
        partner = self:GetUnitPlayerName("NPC")
        guid = tradeUnitGUID("NPC")
    end
    if (partner and state.firstPartner and partner ~= state.firstPartner)
        or (guid and state.partnerGUID and guid ~= state.partnerGUID) then
        self.tradeTracking = nil -- Only another TRADE_SHOW can start tracking again.
        if self.RefreshDuel then self:RefreshDuel() end
        return
    end
    state.firstPartner = state.firstPartner or partner
    state.partnerGUID = state.partnerGUID or guid
    state.partner = partner -- Each offer needs an identifiable partner in the same snapshot.
    local myGold = GetPlayerTradeMoney and GetPlayerTradeMoney()
    local theirGold = GetTargetTradeMoney and GetTargetTradeMoney()
    -- Do not convert or format restricted values, or retain an older readable
    -- amount when the current offer cannot be inspected.
    state.myGold = self:IsBoundedInteger(myGold, 0, self.MAX_WAGER) and myGold or nil
    state.theirGold = self:IsBoundedInteger(theirGold, 0, self.MAX_WAGER) and theirGold or nil
    state.lastUpdated = time()
    if self.RefreshDuel then self:RefreshDuel() end
end

DRE.TRADE_WAGER_TIMEOUT = 300

function DRE:HandleTrackedTradeCompletion()
    if not self.db then return end
    local state = self.tradeTracking
    if not state or state.completed then return end
    state.completed = true -- one payment may be considered only once, including ambiguous payments
    local ownerGUID = self:GetTradeOwnerGUID()
    if not state.partner or not ownerGUID or ownerGUID ~= state.ownerGUID then return end
    if not self:IsBoundedInteger(state.myGold, 0, self.MAX_WAGER)
        or not self:IsBoundedInteger(state.theirGold, 0, self.MAX_WAGER) then return end
    local records = self:PrunePendingTradeWagers()
    local trades = self.db.profile.pendingTradeWagers
    local function matchesTrade(pending)
        return pending.ownerGUID == ownerGUID and self:IsSamePlayer(pending.playerName, state.partner)
    end
    -- Group payouts make earlier debts to the same participant ambiguous, even after reload.
    for _, pending in ipairs(trades) do
        if pending.manualAssignmentRequired and matchesTrade(pending)
            and (state.myGold > 0 or state.theirGold > 0) then
            self:Print("This player also joined a group round. Use /dr edit to assign any earlier 1v1 payment; no wager was changed.")
            if self.ReviewDuelTrade then self:ReviewDuelTrade(state.partner) end
            return
        end
    end
    local matchIndex, tradeAmount
    for index, pending in ipairs(trades) do
        local amount = pending.result == "Won" and state.theirGold or state.myGold
        if matchesTrade(pending) and amount > 0 then
            if state.myGold > 0 and state.theirGold > 0 then
                self:Print("Both players traded gold. Use /dr edit to assign this payment; no wager was changed.")
                if self.ReviewDuelTrade then self:ReviewDuelTrade(state.partner) end
                return
            end
            if matchIndex then
                self:Print("Multiple unpaid games match this trade. Use /dr edit to assign the payment; no wager was changed.")
                if self.ReviewDuelTrade then self:ReviewDuelTrade(state.partner) end
                return
            end
            matchIndex, tradeAmount = index, amount
        end
    end
    if not matchIndex then return end
    local pending = trades[matchIndex]
    local record = records[pending.gameId]
    local success, message = self:ApplyRecordedWager(self.db.profile.history[record.playerName], record.game, tradeAmount)
    if not success then
        self:Print("Trade tracked, but the wager could not be updated: " .. (message or "unknown error"))
        return
    end
    table.remove(trades, matchIndex)
    self.tradeTracking = nil -- never reuse the same payment
    if self.ConfirmDuelPayment then self:ConfirmDuelPayment(pending, tradeAmount) end
    self:Print("Tracked trade updated the wager for your game vs " .. pending.playerName .. ".")
end

local function sendChallengeMessage(self, message, target, replyTo)
    if self.devDuel then return self:SendInviteMessage(message, target, replyTo) end
    return self:SendChatSafely(message, "WHISPER", nil, target)
end

function DRE:SendChallengeWhisper(targetName, roll, wager, trackTrade, terms)
    if not self.db or not self.db.profile.challengeSystem then
        return
    end

    local special = self.devDuel and terms and (terms.double or (terms.mode and terms.mode ~= "classic"))
    if not self.db.profile.challengeSystem.sendWhisper and not special then
        self:DebugPrint("Challenge whisper disabled in settings")
        return
    end

    if not self:ValidateGameInputs(targetName, roll, wager) then return false end
    local message
    if self.devDuel then
        if trackTrade == nil then trackTrade = self:IsTradeWagerModeEnabled() end
        if trackTrade and wager ~= 0 then return false end
        message = string.format("DEATHROLL_CHALLENGE:%d:%.0f:%s", roll, wager, trackTrade and "trade" or "fixed")
        if special then
            if not self.duelModes[terms.mode] then return false end
            message = message .. ":" .. terms.mode
            if terms.double then message = message .. ":double:" .. terms.double end
        end
    else
        message = string.format("DEATHROLL_CHALLENGE:%d:%.0f:%s", roll, wager, self.version)
    end
    local sent, reason, id = sendChallengeMessage(self, message, targetName)
    if not sent then
        self:Print("Challenge invitation was not sent: " .. (reason or "chat unavailable"))
        return false
    end
    if not self.devDuel and self.gameState then
        self.gameState.whisperReplyUntil = GetTime() + self.Dialogs.DEATHROLL_CHALLENGE_POPUP.timeout
    end
    self:DebugPrint(string.format("Sent challenge to %s: roll=%d, wager=%.0f", targetName, roll, wager))
    return true, id
end

local function duelInviteText(challenge, trackTrade)
    local terms = trackTrade and "Wager from the final gold trade" or ("Fixed wager " .. DRE:FormatGold(challenge.wager))
    if challenge.double then terms = DRE:DuelSeriesWagerText(challenge.wager) end
    local extra = DRE:DuelTermsText(challenge)
    return string.format("|cffffcf75%s challenges you|r\n\nOpening roll 1–%d\n%s%s", challenge.sender, challenge.roll, terms,
        extra ~= "" and ("\n" .. extra) or "")
end

local previewChallenge = {sender = "Practice opponent (preview)", roll = 100, wager = 20000, preview = true}
function DRE:PreviewChallengePopup()
    if not self.devDuel then return end
    if self.activeDialog then
        self:Print("Close the current popup before opening the challenge preview.")
        return
    end
    self:ShowDialog("DEATHROLL_CHALLENGE_POPUP", duelInviteText(previewChallenge, self:IsTradeWagerModeEnabled()), nil, previewChallenge)
end

-- Challenge System: Handle incoming challenge whisper
function DRE:HandleChallengeWhisper(message, sender, inviteId)
    if self:HasActiveGame() or (self.devDuel and (self.pendingChallenge or self.acceptedChallenge)) then return end
    if self.activeDialog and self.activeDialog.definition ~= self.Dialogs.DEATHROLL_CHALLENGE_POPUP then return end
    if not self:IsAccessibleValue(message) or type(message) ~= "string" then return end
    sender = self:NormalizePlayerName(sender)
    if not sender then return end
    if not self.db or not self.db.profile.challengeSystem then
        return
    end

    if not self.db.profile.challengeSystem.enabled then
        self:DebugPrint("Challenge system disabled in settings")
        return
    end

    -- Don't show challenge if already in a game
    if self.gameState and self.gameState.isActive then
        self:DebugPrint("Already in active game, ignoring challenge from " .. sender)
        return
    end

    -- Parse challenge message: DEATHROLL_CHALLENGE:roll:wager:version
    local roll, wager, mode = message:match(self.CHAT_PATTERNS.DEATHROLL_CHALLENGE_NEW)
    local duelMode, double = "classic", nil
    if self.devDuel and mode and mode:find(":", 1, true) then
        local settlement, variant, source = mode:match("^(%a+):(%w+):double:(%w+)$")
        if not settlement then settlement, variant = mode:match("^(%a+):(%w+)$") end
        if not self.duelModes[variant] then return end
        mode, duelMode, double = settlement, variant, source
    end
    if self.devDuel and (not inviteId or (mode ~= "trade" and mode ~= "fixed")) then return end
    if not roll or not wager then
        self:DebugPrint("Failed to parse challenge message: " .. message)
        return
    end

    roll = tonumber(roll)
    wager = tonumber(wager)

    local valid = self:ValidateGameInputs(sender, roll, wager)
    if not valid or (self.devDuel and mode == "trade" and wager ~= 0) then return end
    if double and (mode ~= "fixed" or not self:MatchesDoubleOffer(
        {mode = duelMode, double = double, roll = roll, wager = wager}, sender, "Won")) then return end

    -- Validate roll against minimum threshold
    if not double and roll < self.db.profile.challengeSystem.minRollThreshold then
        self:DebugPrint(string.format("Challenge roll %d below threshold %d, ignoring",
            roll, self.db.profile.challengeSystem.minRollThreshold))
        return
    end

    -- Store challenge data
    self.pendingChallenge = {
        sender = sender,
        inviteId = inviteId,
        roll = roll,
        wager = wager,
        timestamp = time()
    }

    local text = string.format("%s challenges you to DeathRoll!\n\nRoll: 1-%d\nWager: %s\n\nDo you accept?",
        sender, roll, self:FormatGold(wager))
    if self.devDuel then
        self.pendingChallenge.receivedAt = GetTime()
        self.pendingChallenge.mode, self.pendingChallenge.double = duelMode, double
        self.pendingChallenge.waitForAccept = true
        self:ClearRecentRollsForPlayer(sender)
        self.pendingChallenge.trackTrade = mode == "trade"
        text = duelInviteText(self.pendingChallenge, self.pendingChallenge.trackTrade)
    end
    self:ShowDialog("DEATHROLL_CHALLENGE_POPUP", text, nil, self.pendingChallenge)
    if self.devDuel then self:RefreshDuel() end

    self:DebugPrint(string.format("Received challenge from %s: roll=%d, wager=%.0f", sender, roll, wager))
end

-- Keep the first eligible system roll with its invite, even if the general roll cache fills up.
local function rememberOpeningRoll(challenge, observed)
    if not challenge.opener and observed.maxRoll == challenge.roll
        and DRE:IsSamePlayer(observed.playerName, challenge.sender)
        and observed.timestamp >= challenge.receivedAt - 2 then
        challenge.opener = observed
    end
end

-- Challenge System: Accept incoming challenge
function DRE:AcceptChallenge(challenge)
    challenge = challenge or self.pendingChallenge
    if not challenge or challenge ~= self.pendingChallenge then return false end
    if (time() - challenge.timestamp) >= self.Dialogs.DEATHROLL_CHALLENGE_POPUP.timeout or self:HasActiveGame()
        or (challenge.double and not self:MatchesDoubleOffer(challenge, challenge.sender, "Won")) then
        self.pendingChallenge = nil
        self:ClearRecentRollsForPlayer(challenge.sender)
        if self.devDuel then self:RefreshDuel() end
        self:Print("This challenge is no longer available.")
        return false
    end
    self.pendingChallenge = nil
    self.acceptedChallenge = challenge
    local sent, reason = sendChallengeMessage(self, "DEATHROLL_ACCEPT", challenge.sender, challenge.inviteId)
    if not sent then
        self:Print("Could not notify the challenger: " .. (reason or "chat unavailable"))
        if challenge.inviteId then
            self.acceptedChallenge = nil
            self:ClearRecentRollsForPlayer(challenge.sender)
            self:RefreshDuel()
            return false
        end
    end
    if TargetByName then pcall(TargetByName, challenge.sender, true) end
    if self.devDuel then
        self.UI.duelResult = nil
        self.UI.duelRestored = true
        C_Timer.After(self.recentRollTimeWindow or 60, function()
            if self.acceptedChallenge == challenge then
                self.acceptedChallenge = nil
                self:ClearRecentRollsForPlayer(challenge.sender)
                self:RefreshDuel()
            end
        end)
    end
    self:ShowMainWindow("deathroll")
    if self.UI then
        self.UI.inputRoll = challenge.roll
        if self.UI.rollEdit then self.UI.rollEdit:SetText(tostring(challenge.roll)) end
        self:SetWagerInputs(challenge.wager) -- zero explicitly clears previous values
    end
    self:UpdateChallengeButtonText()
    self:Print(string.format("Accepted challenge from %s! Roll: %d, Wager: %s",
        challenge.sender, challenge.roll, challenge.trackTrade and "from the final gold trade" or self:FormatGold(challenge.wager)))
    return true
end

function DRE:DeclineChallenge(challenge)
    challenge = challenge or self.pendingChallenge
    if not challenge or challenge ~= self.pendingChallenge then return end
    self.pendingChallenge = nil
    self:ClearRecentRollsForPlayer(challenge.sender)
    local sent, reason = sendChallengeMessage(self, "DEATHROLL_DECLINE", challenge.sender, challenge.inviteId)
    if not sent then self:Print("Could not notify the challenger: " .. (reason or "chat unavailable")) end
    self:Print("Declined challenge from " .. challenge.sender)
    if self.devDuel then self:RefreshDuel() end
end

function DRE:CalculateFunStats()
    if not self.db or not self.db.profile.history then
        return {}
    end
    
    local history = self.db.profile.history
    local suspiciousRolls = self.db.profile.suspiciousRolls or {}
    local funStats = {}
    local MIN_MATCHUP_GAMES = 3
    local MIN_RATE_GAMES = 3
    local MIN_FRENEMY_GAMES = 5
    
    -- Initialize counters
    local mostGamesPlayer, mostGamesCount = nil, 0
    local mostWinsPlayer, mostWinsCount = nil, 0
    local mostLossesPlayer, mostLossesCount = nil, 0
    local mostMoneyWonPlayer, mostMoneyWonAmount = nil, 0
    local mostMoneyLostPlayer, mostMoneyLostAmount = nil, 0
    local nemesisPlayer, nemesisWinRate, nemesisGames = nil, -1, 0  -- Start at -1 so 0% is valid
    local victimPlayer, victimWinRate, victimGames = nil, 2, 0      -- Start at 2 (200%) so 100% is valid
    local frenemyPlayer, frenemyDistance, frenemyGames, frenemyWinRate = nil, math.huge, 0, 0
    local bestMatchupPlayer, bestMatchupPerGame, bestMatchupNet, bestMatchupGames = nil, 0, 0, 0
    local worstMatchupPlayer, worstMatchupPerGame, worstMatchupNet, worstMatchupGames = nil, 0, 0, 0
    local highRollerPlayer, highRollerAvg, highRollerSamples = nil, 0, 0
    local cheapskatePlayer, cheapskateAvg, cheapskateSamples = nil, math.huge, 0
    local luckyPlayer, luckyScore, luckyGames, luckyWinRate = nil, -math.huge, 0, 0
    local unluckyPlayer, unluckyScore, unluckyGames, unluckyWinRate = nil, math.huge, 0, 0
    local daredevilPlayer, daredevilAvg, daredevilSamples = nil, 0, 0
    local conservativePlayer, conservativeAvg, conservativeSamples = nil, math.huge, 0
    local biggestWinAmount, biggestWinPlayer = 0, nil
    local biggestLossAmount, biggestLossPlayer = 0, nil
    local likelyCheaterPlayer, likelyCheaterCount, likelyCheaterLastSeen = nil, 0, 0

    local suspiciousNames = {}
    for playerName in pairs(suspiciousRolls) do
        table.insert(suspiciousNames, playerName)
    end
    table.sort(suspiciousNames)

    for _, playerName in ipairs(suspiciousNames) do
        local entry = suspiciousRolls[playerName]
        local count = entry and tonumber(entry.count) or 0
        local lastSeen = entry and tonumber(entry.lastSeen) or 0
        if count > 0 then
            if count > likelyCheaterCount or (count == likelyCheaterCount and lastSeen > likelyCheaterLastSeen) then
                likelyCheaterPlayer = playerName
                likelyCheaterCount = count
                likelyCheaterLastSeen = lastSeen
            end
        end
    end
    
    local playerNames = {}
    for playerName in pairs(history) do
        table.insert(playerNames, playerName)
    end
    table.sort(playerNames)

    -- Analyze each player
    for _, playerName in ipairs(playerNames) do
        local playerData = history[playerName]
        local wins = playerData.wins or 0
        local losses = playerData.losses or 0
        local totalGames = wins + losses
        local goldWon = playerData.goldWon or 0
        local goldLost = playerData.goldLost or 0
        
        if totalGames > 0 then
            -- Most games played with
            if totalGames > mostGamesCount then
                mostGamesPlayer = playerName
                mostGamesCount = totalGames
            end
            
            -- Most wins against
            if wins > mostWinsCount then
                mostWinsPlayer = playerName
                mostWinsCount = wins
            end
            
            -- Most losses against
            if losses > mostLossesCount then
                mostLossesPlayer = playerName
                mostLossesCount = losses
            end
            
            -- Most money won from
            if goldWon > mostMoneyWonAmount then
                mostMoneyWonPlayer = playerName
                mostMoneyWonAmount = goldWon
            end
            
            -- Most money lost to
            if goldLost > mostMoneyLostAmount then
                mostMoneyLostPlayer = playerName
                mostMoneyLostAmount = goldLost
            end

            -- Best/Worst matchup by net gold per game.
            if totalGames >= MIN_MATCHUP_GAMES then
                local netGold = goldWon - goldLost
                local netPerGame = netGold / totalGames
                if netPerGame > 0 and (
                    not bestMatchupPlayer
                    or netPerGame > bestMatchupPerGame
                    or (netPerGame == bestMatchupPerGame and totalGames > bestMatchupGames)
                ) then
                    bestMatchupPlayer = playerName
                    bestMatchupPerGame = netPerGame
                    bestMatchupNet = netGold
                    bestMatchupGames = totalGames
                end
                if netPerGame < 0 and (
                    not worstMatchupPlayer
                    or netPerGame < worstMatchupPerGame
                    or (netPerGame == worstMatchupPerGame and totalGames > worstMatchupGames)
                ) then
                    worstMatchupPlayer = playerName
                    worstMatchupPerGame = netPerGame
                    worstMatchupNet = netGold
                    worstMatchupGames = totalGames
                end
            end
             
            -- Calculate win rates for nemesis/victim.
            if totalGames >= MIN_RATE_GAMES then
                local theirWinRate = losses / totalGames -- Their wins against us
                local ourWinRate = wins / totalGames -- Our wins against them
                
                -- Nemesis (highest win rate against us)
                if theirWinRate > nemesisWinRate
                    or (theirWinRate == nemesisWinRate and totalGames > nemesisGames) then
                    nemesisPlayer = playerName
                    nemesisWinRate = theirWinRate
                    nemesisGames = totalGames
                end
                
                -- Victim (lowest win rate against us, highest for us)
                if theirWinRate < victimWinRate
                    or (theirWinRate == victimWinRate and totalGames > victimGames) then
                    victimPlayer = playerName
                    victimWinRate = theirWinRate
                    victimGames = totalGames
                end

                -- Frenemy: closest to a 50/50 matchup.
                if totalGames >= MIN_FRENEMY_GAMES then
                    local distanceToEven = math.abs(ourWinRate - 0.5)
                    if distanceToEven < frenemyDistance then
                        frenemyPlayer = playerName
                        frenemyDistance = distanceToEven
                        frenemyGames = totalGames
                        frenemyWinRate = ourWinRate
                    elseif distanceToEven == frenemyDistance and totalGames > frenemyGames then
                        frenemyPlayer = playerName
                        frenemyGames = totalGames
                        frenemyWinRate = ourWinRate
                    end
                end
                 
                -- Lucky/Unlucky based on wins above/below a 50/50 baseline.
                local luckScore = wins - (totalGames * 0.5)
                if luckScore > luckyScore or (luckScore == luckyScore and totalGames > luckyGames) then
                    luckyPlayer = playerName
                    luckyScore = luckScore
                    luckyGames = totalGames
                    luckyWinRate = ourWinRate
                end
                
                if luckScore < unluckyScore or (luckScore == unluckyScore and totalGames > unluckyGames) then
                    unluckyPlayer = playerName
                    unluckyScore = luckScore
                    unluckyGames = totalGames
                    unluckyWinRate = ourWinRate
                end
            end
            
            -- Analyze recent games for additional stats
            if playerData.recentGames then
                local totalWager = 0
                local wagerCount = 0
                local totalStartRoll = 0
                local rollCount = 0
                
                for _, game in ipairs(playerData.recentGames) do
                    -- Track biggest single win/loss
                    if game.goldAmount and game.goldAmount > 0 then
                        if (game.result == "Won" or game.result == "WIN") and game.goldAmount > biggestWinAmount then
                            biggestWinAmount = game.goldAmount
                            biggestWinPlayer = playerName
                        elseif (game.result == "Lost" or game.result == "LOSS") and game.goldAmount > biggestLossAmount then
                            biggestLossAmount = game.goldAmount
                            biggestLossPlayer = playerName
                        end
                        
                        totalWager = totalWager + game.goldAmount
                        wagerCount = wagerCount + 1
                    end
                    
                    -- Track starting rolls for daredevil/conservative
                    if game.initialRoll and game.initialRoll > 0 then
                        totalStartRoll = totalStartRoll + game.initialRoll
                        rollCount = rollCount + 1
                    end
                end
                
                -- Calculate average wager
                if wagerCount > 0 then
                    local avgWager = math.floor(totalWager / wagerCount)
                    if avgWager > highRollerAvg
                        or (avgWager == highRollerAvg and wagerCount > highRollerSamples) then
                        highRollerPlayer = playerName
                        highRollerAvg = avgWager
                        highRollerSamples = wagerCount
                    end
                    if avgWager < cheapskateAvg
                        or (avgWager == cheapskateAvg and wagerCount > cheapskateSamples) then
                        cheapskatePlayer = playerName
                        cheapskateAvg = avgWager
                        cheapskateSamples = wagerCount
                    end
                end
                
                -- Calculate average starting roll
                if rollCount > 0 then
                    local avgRoll = totalStartRoll / rollCount
                    if avgRoll > daredevilAvg
                        or (avgRoll == daredevilAvg and rollCount > daredevilSamples) then
                        daredevilPlayer = playerName
                        daredevilAvg = avgRoll
                        daredevilSamples = rollCount
                    end
                    if avgRoll < conservativeAvg
                        or (avgRoll == conservativeAvg and rollCount > conservativeSamples) then
                        conservativePlayer = playerName
                        conservativeAvg = avgRoll
                        conservativeSamples = rollCount
                    end
                end
            end
        end
    end

    -- Hide contradictory or low-signal pairs.
    if luckyScore <= 0 then
        luckyPlayer = nil
        luckyGames = 0
        luckyWinRate = 0
        luckyScore = 0
    end

    if unluckyScore >= 0 then
        unluckyPlayer = nil
        unluckyGames = 0
        unluckyWinRate = 0
        unluckyScore = 0
    end

    if nemesisPlayer and victimPlayer and nemesisPlayer == victimPlayer then
        victimPlayer = nil
        victimWinRate = 0
    end

    if highRollerPlayer and cheapskatePlayer and highRollerPlayer == cheapskatePlayer then
        cheapskatePlayer = nil
        cheapskateAvg = 0
    end

    if daredevilPlayer and conservativePlayer and daredevilPlayer == conservativePlayer then
        conservativePlayer = nil
        conservativeAvg = 0
    end
    
    -- Package the results
    return {
        mostPlayedWith = {player = mostGamesPlayer, count = mostGamesCount},
        mostWinsAgainst = {player = mostWinsPlayer, count = mostWinsCount},
        mostLossesAgainst = {player = mostLossesPlayer, count = mostLossesCount},
        mostMoneyWonFrom = {player = mostMoneyWonPlayer, amount = mostMoneyWonAmount},
        mostMoneyLostTo = {player = mostMoneyLostPlayer, amount = mostMoneyLostAmount},
        frenemy = {player = frenemyPlayer, distance = frenemyDistance, games = frenemyGames, winRate = frenemyWinRate},
        bestMatchup = {player = bestMatchupPlayer, netPerGame = bestMatchupPerGame, net = bestMatchupNet, games = bestMatchupGames},
        worstMatchup = {player = worstMatchupPlayer, netPerGame = worstMatchupPerGame, net = worstMatchupNet, games = worstMatchupGames},
        nemesis = {player = nemesisPlayer, winRate = nemesisWinRate},
        victim = {player = victimPlayer, winRate = victimWinRate},
        likelyCheater = {player = likelyCheaterPlayer, count = likelyCheaterCount},
        highRoller = {player = highRollerPlayer, avgWager = highRollerAvg},
        cheapskate = {player = cheapskatePlayer, avgWager = cheapskateAvg},
        luckyPlayer = {player = luckyPlayer, winRate = luckyWinRate, score = luckyScore, games = luckyGames},
        unluckyPlayer = {player = unluckyPlayer, winRate = unluckyWinRate, score = unluckyScore, games = unluckyGames},
        daredevil = {player = daredevilPlayer, avgRoll = daredevilAvg},
        conservative = {player = conservativePlayer, avgRoll = conservativeAvg},
        biggestWin = {amount = biggestWinAmount, player = biggestWinPlayer},
        biggestLoss = {amount = biggestLossAmount, player = biggestLossPlayer},
    }
end

-- Keep the full player identity separate from the statistic and its supporting figures.
function DRE:GetFunStatFields(statType, statData)
    if not statData or not statData.player then
        return nil
    end
    
    local formatters = {
        mostPlayedWith = function(data)
            return "Most Played With", string.format(data.count == 1 and "%d game" or "%d games", data.count)
        end,
        mostWinsAgainst = function(data)
            return "Most Wins Against", string.format(data.count == 1 and "%d win" or "%d wins", data.count)
        end,
        mostLossesAgainst = function(data)
            return "Most Losses Against", string.format(data.count == 1 and "%d loss" or "%d losses", data.count)
        end,
        mostMoneyWonFrom = function(data)
            return "Biggest Gold Mine", string.format("%s won", self:FormatGold(data.amount))
        end,
        mostMoneyLostTo = function(data)
            return "Biggest Money Sink", string.format("%s lost", self:FormatGold(data.amount))
        end,
        frenemy = function(data)
            if self.devDuel then
                local games = data.games or 0
                local wins = math.floor((data.winRate or 0) * games + 0.5)
                local losses = games - wins
                return "Closest Rival", string.format("%d %s · %d %s", wins, wins == 1 and "win" or "wins",
                    losses, losses == 1 and "loss" or "losses")
            end
            return "Frenemy", string.format("%d games, %.1f%% win rate", data.games or 0, (data.winRate or 0) * 100)
        end,
        bestMatchup = function(data)
            local netPerGame = data.netPerGame or 0
            if netPerGame >= 0 then
                netPerGame = math.floor(netPerGame + 0.5)
            else
                netPerGame = math.ceil(netPerGame - 0.5)
            end
            return "Best Matchup", string.format(
                "%s net, %s per game over %d games",
                self:FormatGold(data.net or 0),
                self:FormatGold(netPerGame),
                data.games or 0
            )
        end,
        worstMatchup = function(data)
            local netPerGame = data.netPerGame or 0
            if netPerGame >= 0 then
                netPerGame = math.floor(netPerGame + 0.5)
            else
                netPerGame = math.ceil(netPerGame - 0.5)
            end
            return "Worst Matchup", string.format(
                "%s net, %s per game over %d games",
                self:FormatGold(data.net or 0),
                self:FormatGold(netPerGame),
                data.games or 0
            )
        end,
        nemesis = function(data)
            return "Your Nemesis", string.format("%.1f%% win rate against you", data.winRate * 100)
        end,
        victim = function(data)
            return "Your Victim", string.format("%.1f%% win rate against you", data.winRate * 100)
        end,
        likelyCheater = function(data)
            local count = data.count or 0
            local pluralSuffix = count == 1 and "" or "s"
            return "Most Likely to Cheat", string.format("%d suspicious roll%s", count, pluralSuffix)
        end,
        highRoller = function(data)
            return "High Roller", string.format("%s avg wager", self:FormatGold(data.avgWager))
        end,
        cheapskate = function(data)
            return "Cheapskate", string.format("%s avg wager", self:FormatGold(data.avgWager))
        end,
        luckyPlayer = function(data)
            return "Lucky Charm", string.format(
                "%+.1f wins vs 50/50 over %d games, %.1f%% win rate",
                data.score or 0,
                data.games or 0,
                (data.winRate or 0) * 100
            )
        end,
        unluckyPlayer = function(data)
            return "Bad Luck Magnet", string.format(
                "%+.1f wins vs 50/50 over %d games, %.1f%% win rate",
                data.score or 0,
                data.games or 0,
                (data.winRate or 0) * 100
            )
        end,
        daredevil = function(data)
            return "Daredevil", string.format("avg %.0f starting roll", data.avgRoll)
        end,
        conservative = function(data)
            return "Conservative", string.format("avg %.0f starting roll", data.avgRoll)
        end,
        biggestWin = function(data)
            return "Biggest Single Win", self:FormatGold(data.amount)
        end,
        biggestLoss = function(data)
            return "Biggest Single Loss", self:FormatGold(data.amount)
        end,
    }
    
    local formatter = formatters[statType]
    if formatter then
        local title, detail = formatter(statData)
        return title, statData.player, detail
    end
    
    return nil
end

function DRE:FormatFunStat(statType, statData)
    local title, player, detail = self:GetFunStatFields(statType, statData)
    if not title then return nil end
    if statType == "biggestWin" then return title .. ": " .. detail .. " vs " .. player end
    if statType == "biggestLoss" then return title .. ": " .. detail .. " to " .. player end
    return title .. ": " .. player .. " (" .. detail .. ")"
end

-- Slash command handlers
function DRE:SlashCommand(input)
    local trimmedInput = self:Trim(input or "")
    local args, argumentError = self:ParseCommandArguments(trimmedInput)
    if not args then self:Print(argumentError); return end
    local command = args[1]
    local mergeSource, mergeTarget
    if command == "merge" and #args == 3 then mergeSource, mergeTarget = args[2], args[3] end
    local setSuspiciousPlayer, setSuspiciousCount
    if command == "setsuspicious" and #args >= 3 then
        setSuspiciousPlayer, setSuspiciousCount = table.concat(args, " ", 2, #args - 1), args[#args]
    end
    local clearSuspiciousPlayer
    if (command == "clearsuspicious" or command == "forgive") and #args >= 2 then
        clearSuspiciousPlayer = table.concat(args, " ", 2)
    end

    if command == "minimap" then
        self:HandleMinimapSlashCommand(table.concat(args, " ", 2))
    elseif command == "group" then
        self:GroupCommand(args[2], table.concat(args, " ", 3))
    elseif mergeSource and mergeTarget then
        -- Recalculation refreshes History, so remember the user's selection first.
        local selectedPlayer = self.UI and self.UI.historyDropdown and self.UI.historyDropdown:GetValue()
        local success, message = self:MergePlayerHistory(mergeSource, mergeTarget)
        if success then
            self:Print(message)

            if self.UI and self.UI.historyDropdown and self.UI.historyDropdown.GetValue then
                local preferredPlayer = selectedPlayer
                if selectedPlayer == mergeSource then
                    preferredPlayer = mergeTarget
                end

                if self.RefreshHistoryDropdown then
                    self:RefreshHistoryDropdown(preferredPlayer or mergeTarget)
                elseif preferredPlayer then
                    self:UpdateHistoryDisplay(preferredPlayer)
                end
            end
        else
            self:Print("Failed to merge player history: " .. (message or "Unknown error"))
            self:Print("Usage: /dr merge <oldName> <newName>")
        end
    elseif setSuspiciousPlayer and setSuspiciousCount then
        local success, message = self:SetSuspiciousRollCount(setSuspiciousPlayer, setSuspiciousCount)
        if success then
            self:Print(message)
        else
            self:Print("Failed to set suspicious-roll count: " .. (message or "Unknown error"))
        end
    elseif clearSuspiciousPlayer and clearSuspiciousPlayer ~= "" then
        local success, message = self:ClearSuspiciousRollEntry(clearSuspiciousPlayer)
        if success then
            self:Print(message)
        else
            self:Print("Failed to clear suspicious-roll entry: " .. (message or "Unknown error"))
        end
    elseif command == "sendstats" then
        local playerName, channelHint
        local lastArgument = #args
        if #args >= 2 then
            channelHint = self:NormalizeStatsBroadcastChannelToken(args[#args])
            if channelHint then lastArgument = lastArgument - 1 end
            if lastArgument >= 2 then playerName = table.concat(args, " ", 2, lastArgument) end
        end

        if not playerName and self.UI and self.UI.historyDropdown and self.UI.historyDropdown.GetValue then
            playerName = self.UI.historyDropdown:GetValue()
        end
        if (not playerName or playerName == "") and UnitName then
            playerName = DRE:GetUnitPlayerName("target")
        end

        if not playerName or playerName == "" then
            self:Print("No player selected. Use /dr sendstats <player> [party|raid|guild|officer|instance|say|yell] or select a player in History tab.")
            return
        end

        local success, message = self:SendPlayerStatsBroadcast(playerName, channelHint)
        if success then
            self:Print(message)
        else
            self:Print("Failed to send stats: " .. (message or "Unknown error"))
        end
    elseif trimmedInput == "" then
        self:ShowMainWindow()
    elseif trimmedInput == "config" or trimmedInput == "options" then
        self:OpenOptions()
    elseif trimmedInput == "debug" then
        self:Print("Debug command triggered - dumping buffer...")
        self:DumpDebugBuffer()
    elseif self.devDuel and trimmedInput == "testpopup" then
        self:PreviewChallengePopup()
    elseif trimmedInput == "accept" or trimmedInput == "decline" then
        local accept = trimmedInput == "accept"
        local dialog = self.activeDialog
        if dialog and dialog.definition == self.Dialogs.DEATHROLL_CHALLENGE_POPUP
            and (dialog.data == self.pendingChallenge or dialog.data == previewChallenge) then
            self:CloseDialog(dialog, accept)
        elseif self.pendingChallenge then
            if accept then self:AcceptChallenge() else self:DeclineChallenge() end
        else
            self:Print("No pending challenge to " .. trimmedInput)
        end
    elseif trimmedInput == "cancel" then
        self:CancelCurrentGame()
    elseif trimmedInput == "edit" then
        self:ShowEditGameDialog()
    elseif trimmedInput == "fixgold" then
        local success, message = self:RecalculateGoldTracking()
        if success then
            self:Print("Gold tracking fixed: " .. message)
        else
            self:Print("Failed to fix gold tracking: " .. message)
        end
    elseif trimmedInput == "dedupe" then
        local success, message = self:DeduplicateHistoryData()
        if success then
            self:Print("History deduplicated: " .. message)
            if self.UI and self.UI.historyDropdown and self.RefreshHistoryDropdown then
                local selectedPlayer = self.UI.historyDropdown:GetValue()
                self:RefreshHistoryDropdown(selectedPlayer)
            end
        else
            self:Print("Failed to deduplicate history: " .. (message or "Unknown error"))
        end
    elseif trimmedInput == "suspicious" or trimmedInput == "cheaters" then
        self:PrintSuspiciousRollSummary()
    elseif trimmedInput == "size" or trimmedInput == "windowsize" then
        self:PrintCurrentWindowSize()
    else
        self:Print("Usage: /dr or /deathroll - Opens the main window")
        self:Print("       /dr config - Opens configuration")
        self:Print("       /dr minimap [show|hide|lock|unlock] - Manage the minimap icon")
        self:Print("       /dr debug - Show debug chat buffer")
        if self.devDuel then self:Print("       /dr testpopup - Preview a challenge invitation") end
        self:Print("       /dr accept - Accept pending challenge")
        self:Print("       /dr decline - Decline pending challenge")
        self:Print("       /dr cancel - Cancel the active game without recording a result")
        self:Print("       /dr group - Host a group DeathRoll round")
        self:Print("       /dr edit - Edit recent game records")
        self:Print("       /dr merge <oldName> <newName> - Merge player history after rename")
        self:Print("       /dr fixgold - Recalculate gold tracking totals")
        self:Print("       /dr dedupe - Remove duplicate game entries and recalculate stats")
        self:Print("       /dr suspicious - Show tracked invalid/wrong rolls")
        self:Print("       /dr setsuspicious <player> <count> - Set suspicious-roll count")
        self:Print("       /dr clearsuspicious <player> - Clear suspicious-roll entry")
        self:Print("       /dr sendstats [player] [party|raid|guild|officer|instance|say|yell] - Broadcast main stats")
        self:Print("       /dr size - Show current window size")
    end
end

function DRE:HistoryCommand(input)
    local target = input and self:Trim(input) or ""
    if target == "" then
        target = DRE:GetUnitPlayerName("target")
    end
    
    if target then
        self:ShowHistory(target)
    else
        self:Print("Please provide a target name or select a target.")
        self:Print("Usage: /drh [playername] or /deathrollhistory [playername]")
    end
end

function DRE:SanitizeChatText(text)
    if text == nil then
        return ""
    end

    local cleaned = tostring(text)
    -- Chat escape sequences use pipes; strip them from broadcast text.
    cleaned = cleaned:gsub("|", "")
    cleaned = cleaned:gsub("[\r\n]", " ")
    cleaned = cleaned:gsub("%c", "")
    cleaned = cleaned:gsub("%s+", " ")

    return self:Trim(cleaned)
end

function DRE:NormalizeStatsBroadcastChannelToken(channelToken)
    local requested = channelToken and string.upper(self:Trim(channelToken)) or ""
    if requested == "" then
        return nil
    end

    local aliases = {
        P = "PARTY",
        PARTY = "PARTY",
        R = "RAID",
        RAID = "RAID",
        G = "GUILD",
        GUILD = "GUILD",
        S = "SAY",
        SAY = "SAY",
        Y = "YELL",
        YELL = "YELL",
        I = "INSTANCE_CHAT",
        INSTANCE = "INSTANCE_CHAT",
        INSTANCE_CHAT = "INSTANCE_CHAT",
        LFG = "INSTANCE_CHAT",
        O = "OFFICER",
        OFFICER = "OFFICER",
    }

    return aliases[requested]
end

function DRE:BuildPlayerStatsBroadcast(playerName)
    if not playerName or playerName == "" then
        return nil, "Player name is required"
    end

    local playerData = self:GetPlayerHistory(playerName)
    if not playerData then
        return nil, string.format("No history found for %s", playerName)
    end

    local wins = tonumber(playerData.wins) or 0
    local losses = tonumber(playerData.losses) or 0
    local games = wins + losses
    if games <= 0 then
        return nil, string.format("No games recorded against %s", playerName)
    end

    local goldWon = tonumber(playerData.goldWon) or 0
    local goldLost = tonumber(playerData.goldLost) or 0
    local net = goldWon - goldLost
    local winRate = (wins / games) * 100

    local suspiciousCount = 0
    if self.db and self.db.profile and self.db.profile.suspiciousRolls and self.db.profile.suspiciousRolls[playerName] then
        suspiciousCount = tonumber(self.db.profile.suspiciousRolls[playerName].count) or 0
    end

    local flagsSuffix = ""
    if suspiciousCount > 0 then
        flagsSuffix = string.format(" | Flags %d", suspiciousCount)
    end

    local safePlayerName = self:SanitizeChatText(playerName)
    if safePlayerName == "" then
        safePlayerName = "Unknown"
    end

    local message = string.format(
        "[DR] vs %s: %d games (%dW-%dL, %.1f%% WR) | Net %s | Won %s | Lost %s%s",
        safePlayerName,
        games,
        wins,
        losses,
        winRate,
        self:FormatGold(net),
        self:FormatGold(goldWon),
        self:FormatGold(goldLost),
        flagsSuffix
    )

    return message
end

function DRE:ResolveStatsBroadcastChannel(channelHint, requireWholeGroup)
    local requested = self:NormalizeStatsBroadcastChannelToken(channelHint)

    local inRaid = IsInRaid and IsInRaid()
    local inGroup = IsInGroup and IsInGroup()
    local inInstanceGroup = false
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE then
        inInstanceGroup = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end
    local inGuild = IsInGuild and IsInGuild()

    if not requested then
        if inRaid then
            return "RAID", "raid"
        elseif inInstanceGroup then
            return "INSTANCE_CHAT", "instance"
        elseif inGroup then
            return "PARTY", "party"
        elseif inGuild then
            return "GUILD", "guild"
        end
        return nil, nil, "You are not in a party/raid/instance or guild. Specify channel: say, yell, party, raid, guild, officer, instance."
    end

    if requested == "PARTY" then
        if requireWholeGroup and (inRaid or inInstanceGroup) then
            return nil, nil, "Choose Raid or Instance to announce to the whole group."
        end
        -- PARTY uses the home group, including the sender's subgroup in a home raid.
        local inHomeGroup = (inGroup or inRaid) and not inInstanceGroup
        if IsInGroup and LE_PARTY_CATEGORY_HOME then
            inHomeGroup = IsInGroup(LE_PARTY_CATEGORY_HOME)
        end
        if inHomeGroup then
            return "PARTY", "party"
        end
        return nil, nil, "Party chat is unavailable for your current group."
    elseif requested == "RAID" then
        if inRaid then
            return "RAID", "raid"
        end
        return nil, nil, "You are not in a raid."
    elseif requested == "INSTANCE_CHAT" then
        if inInstanceGroup then
            return "INSTANCE_CHAT", "instance"
        end
        return nil, nil, "You are not in an instance group."
    elseif requested == "GUILD" then
        if inGuild then
            return "GUILD", "guild"
        end
        return nil, nil, "You are not in a guild."
    elseif requested == "OFFICER" then
        if inGuild then
            return "OFFICER", "officer"
        end
        return nil, nil, "You are not in a guild."
    elseif requested == "SAY" then
        return "SAY", "say"
    elseif requested == "YELL" then
        return "YELL", "yell"
    end

    return nil, nil, "Unknown channel. Use party, raid, guild, officer, instance, say, or yell."
end

function DRE:SendPlayerStatsBroadcast(playerName, channelHint)
    local message, buildError = self:BuildPlayerStatsBroadcast(playerName)
    if not message then
        return false, buildError
    end

    local chatType, channelName, channelError = self:ResolveStatsBroadcastChannel(channelHint)
    if not chatType then
        return false, channelError
    end

    local safeMessage = self:SanitizeChatText(message)
    if safeMessage == "" then
        return false, "Failed to build a safe broadcast message."
    end

    local sent, sendError = self:SendChatSafely(safeMessage, chatType)
    if not sent then return false, sendError or "Chat could not be sent." end
    return true, string.format("Sent stats for %s to %s.", playerName, channelName)
end

function DRE:GetDefaultStartingRoll()
    local value = self.db.profile.gameplay.defaultStartingRoll
    return self:IsBoundedInteger(value, 2, self.MAX_ROLL) and value or 100
end

function DRE:SetDefaultStartingRoll(value)
    if not self:IsBoundedInteger(value, 2, self.MAX_ROLL) then return end
    local previous = self:GetDefaultStartingRoll()
    self.db.profile.gameplay.defaultStartingRoll = value
    local ui = self.UI
    if not (self.gameState and self.gameState.isActive) and not self.acceptedChallenge then
        local field = ui.rollEdit
        if field and tonumber(field:GetText()) == previous then
            field:SetText(tostring(value))
            ui.inputRoll = value
        elseif not field and ui.inputRoll == previous then
            ui.inputRoll = value
        end
    end
    local draft = self.groupDraft
    if self:IsGroupGuest() then draft = self.sharedTable.localDraft end
    if draft and tonumber(draft.initialRoll) == previous then
        draft.initialRoll = tostring(value)
        local widgets = ui.groupWidgets
        if not self:IsGroupGuest() then
            if widgets and widgets.initialRoll then widgets.initialRoll:SetText(tostring(value)) end
            self:RefreshGroupUI()
        end
    end
end

function DRE:ParseRollSetting(text)
    -- Accept ordinary digits and the grouped form shown in the field label.
    if type(text) == "string" and (text:match("^%d+$") or text:match("^%d%d?%d?,%d%d%d$")) then
        local value = tonumber((text:gsub(",", "")))
        if self:IsBoundedInteger(value, 2, self.MAX_ROLL) then return value end
    end
    return nil, "Enter a whole number from 2 to 999,999."
end

function DRE:PlayTurnSound()
    if not self.db.profile.gameplay.soundEnabled then return end
    local play = C_Sound and C_Sound.PlaySound or PlaySound
    if play then pcall(play, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081) end
end

-- AceConfig Options Table
function DRE:SetupOptions()
    local function rollOption(name, desc, order, get, set)
        return {
            name = name .. " (2–999,999)", desc = desc, order = order, type = "input",
            get = function() return tostring(get()) end,
            validate = function(_, text)
                local value, reason = self:ParseRollSetting(text)
                return value ~= nil or reason
            end,
            set = function(_, text)
                local value = self:ParseRollSetting(text)
                if value then set(value) end
            end,
        }
    end
    local options = {
        name = self.displayName,
        type = "group",
        args = {
            gameplay = {
                name = "Gameplay",
                type = "group",
                order = 1,
                args = {
                    gameplayHeader = {
                        name = "Gameplay",
                        type = "header",
                        order = 1,
                    },
                    autoEmote = {
                        name = "Auto Emote",
                        desc = "Automatically perform emotes on win/loss",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.autoEmote end,
                        set = function(_, val) self.db.profile.gameplay.autoEmote = val end,
                        order = 2,
                    },
                    soundEnabled = {
                        name = "Play Sound on Your Turn",
                        desc = "Play a cue when it is your turn to roll in a duel or hosted group round.",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.soundEnabled end,
                        set = function(_, val) self.db.profile.gameplay.soundEnabled = val end,
                        order = 3,
                    },
                    chatMessages = {
                        name = "Chat Messages",
                        desc = "Show informational messages in chat (challenge status, responses, timeouts, etc.)",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.chatMessages end,
                        set = function(_, val) self.db.profile.gameplay.chatMessages = val end,
                        order = 4,
                    },
                    debugMessages = {
                        name = "Debug Messages",
                        desc = "Show technical debug messages (addon detection, message parsing, etc.). Turn this off for a cleaner experience.",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.debugMessages end,
                        set = function(_, val) self.db.profile.gameplay.debugMessages = val end,
                        order = 5,
                    },
                    defaultStartingRoll = rollOption("Default Starting Roll", "Starting roll for new duels and group rounds.", 6,
                        function() return self:GetDefaultStartingRoll() end,
                        function(value) self:SetDefaultStartingRoll(value) end),
                },
            },
            challenges = {
                name = "Challenges and wagers",
                type = "group",
                order = 2,
                args = {
                    challengeEnabled = {
                        name = "Enable Challenge Popups",
                        desc = "Show a popup when other players with the addon challenge you to a DeathRoll",
                        type = "toggle",
                        get = function() return self.db.profile.challengeSystem.enabled end,
                        set = function(_, val) self.db.profile.challengeSystem.enabled = val end,
                        order = 1,
                    },
                    sendWhisper = {
                        name = self.devDuel and "Send Challenge Invites" or "Send Challenge Whispers",
                        desc = self.devDuel and "Send a silent invitation to opponents using the updated Forever dev build."
                            or "Automatically whisper challenge details to your opponent when you start a game. They will see a popup if they have the addon.",
                        type = "toggle",
                        get = function() return self.db.profile.challengeSystem.sendWhisper end,
                        set = function(_, val) self.db.profile.challengeSystem.sendWhisper = val end,
                        order = 2,
                    },
                    trackWagerByTrade = {
                        name = "Track Wager From Completed Trade",
                        desc = "Hide manual wager inputs in the main window and update the wager from the next successful gold trade with your opponent.",
                        type = "toggle",
                        get = function() return self.db.profile.challengeSystem.trackWagerByTrade end,
                        set = function(_, val) self:SetTradeWagerModeEnabled(val) end,
                        order = 4,
                    },
                    minRollThreshold = rollOption("Minimum Roll for Popups",
                        "Show incoming challenge popups when the starting roll is at least this number.", 3,
                        function() return self.db.profile.challengeSystem.minRollThreshold end,
                        function(value) self.db.profile.challengeSystem.minRollThreshold = value end),
                },
            },
            interface = {
                name = "Interface",
                type = "group",
                order = 3,
                args = {
                    groupAppearance = {
                        name = "Group appearance",
                        type = "select",
                        values = self.groupAppearances,
                        sorting = self.groupAppearanceOrder,
                        hidden = not self.devDuel,
                        get = function() return self:GetGroupAppearance() end,
                        set = function(_, value) self:SetGroupAppearance(value) end,
                        order = 1,
                    },
                    scale = {
                        name = "UI Scale",
                        desc = "Adjust the scale of the DeathRoll window (1.0 = recommended size)",
                        type = "range",
                        min = 0.6,
                        max = 2.2,
                        step = 0.1,
                        bigStep = 0.1,
                        get = function() return (self.db.profile.ui.scale + 0.1) end,
                        set = function(_, val) 
                            self.db.profile.ui.scale = val - 0.1
                            self:UpdateUIScale()
                        end,
                        order = 7,
                    },
                    resetPosition = {
                        name = "Reset Window Position",
                        desc = "Reset the DeathRoll window to center of screen",
                        type = "execute",
                        func = function() self:ResetWindowPosition() end,
                        order = 8,
                    },
                    resetSize = {
                        name = "Reset Window Size",
                        desc = "Reset the DeathRoll window to its default size",
                        type = "execute",
                        func = function() self:ResetWindowSize() end,
                        order = 8.5,
                    },
                    hide = {
                        name = "Hide Minimap Icon",
                        desc = "Hide the minimap icon",
                        type = "toggle",
                        get = function() return self.db.profile.minimap.hide end,
                        set = function(_, val) 
                            self.db.profile.minimap.hide = val
                            self:ToggleMinimapIcon()
                        end,
                        order = 9,
                    },
                    lock = {
                        name = "Lock Minimap Icon",
                        desc = "Keep the minimap icon in its current position.",
                        type = "toggle",
                        get = function() return self.db.profile.minimap.lock end,
                        set = function(_, value) self:SetMinimapLocked(value) end,
                        order = 10,
                    },
                },
            },
            data = {
                name = "History and data",
                type = "group",
                order = 5,
                args = {
                    stats = {
                        name = "Print statistics to chat",
                        desc = "Display current statistics in chat",
                        type = "execute",
                        func = function() 
                            local stats = self:GetOverallStats()
                            self:Print("=== DeathRoll Statistics ===")
                            self:Print("Total Games: " .. stats.totalGames)
                            self:Print("Total Wins: " .. stats.totalWins)
                            self:Print("Total Losses: " .. stats.totalLosses)
                            self:Print("Gold Won: " .. self:FormatGold(stats.totalGoldWon))
                            self:Print("Gold Lost: " .. self:FormatGold(stats.totalGoldLost))
                            self:Print("Current Streak: " .. stats.currentStreak)
                        end,
                        order = 11,
                    },
                    cleanOldData = {
                        name = "Clean old records",
                        desc = "Remove game records older than 30 days",
                        type = "execute",
                        func = function() 
                            self:CleanOldData(30)
                        end,
                        order = 12,
                    },
                    resetData = {
                        name = "Reset All Data",
                        desc = "WARNING: This will permanently delete all DeathRoll history and statistics!",
                        type = "execute",
                        func = function() 
                            self:ShowDialog("DEATHROLL_RESET_CONFIRM")
                        end,
                        order = 16,
                    },
                    exportData = {
                        name = "Export Data",
                        desc = "Export your DeathRoll data for backup",
                        type = "execute",
                        func = function()
                            local exportString = self:ExportData()
                            local frame = DRE:CreateWindowWidget("Frame")
                            self:ReleaseWindowOnClose(frame)
                            frame:SetTitle("Export Data")
                            frame:SetLayout("Fill")
                            frame:SetWidth(600)
                            frame:SetHeight(500)
                            
                            local editBox = AceGUI:Create("MultiLineEditBox")
                            editBox:SetText(exportString)
                            editBox:SetFullWidth(true)
                            editBox:SetFullHeight(true)
                            editBox:SetLabel("Copy this data to save as backup:")
                            frame:AddChild(editBox)
                            
                            frame:Show()
                        end,
                        order = 14,
                    },
                    editGame = {
                        name = "Edit Game Records",
                        desc = "Open dialog to edit recent game records",
                        type = "execute",
                        func = function() 
                            self:ShowEditGameDialog()
                        end,
                        order = 15,
                    },
                },
            },
            statistics = {
                name = "Statistics",
                type = "group",
                order = 4,
                get = function(info) return self.db.profile.funStats[info[#info]] end,
                set = function(info, value)
                    self:SetStatPreference(info[#info], value)
                end,
                args = {
                    description = {
                        name = "Choose which player, gold, and streak statistics appear on the Statistics tab.",
                        type = "description",
                        order = 1,
                    },
                    separator1 = {
                        name = "Player Relationships",
                        type = "header",
                        order = 2,
                    },
                    showMostPlayedWith = {
                        name = "Most Played With",
                        desc = "Show which player you've played the most games against",
                        type = "toggle",
                        order = 3,
                    },
                    showMostWinsAgainst = {
                        name = "Most Wins Against",
                        desc = "Show which player you've beaten the most times",
                        type = "toggle",
                        order = 4,
                    },
                    showMostLossesAgainst = {
                        name = "Most Losses Against",
                        desc = "Show which player has beaten you the most times",
                        type = "toggle",
                        order = 5,
                    },
                    showNemesis = {
                        name = "Your Nemesis",
                        desc = "Show the player with the highest win rate against you (minimum 3 games)",
                        type = "toggle",
                        order = 6,
                    },
                    showVictim = {
                        name = "Your Victim",
                        desc = "Show the player with the lowest win rate against you (minimum 3 games)",
                        type = "toggle",
                        order = 7,
                    },
                    showFrenemy = {
                        name = "Frenemy",
                        desc = "Show your most even matchup near 50/50 (minimum 5 games)",
                        type = "toggle",
                        order = 8,
                    },
                    showLikelyCheater = {
                        name = "Most Likely to Cheat",
                        desc = "Show who has the most flagged invalid roll-range attempts",
                        type = "toggle",
                        order = 8.5,
                    },
                    separator2 = {
                        name = "Gold & Money",
                        type = "header",
                        order = 9,
                    },
                    showMostMoneyWonFrom = {
                        name = "Biggest Gold Mine",
                        desc = "Show which player you've won the most gold from",
                        type = "toggle",
                        order = 10,
                    },
                    showMostMoneyLostTo = {
                        name = "Biggest Money Sink",
                        desc = "Show which player you've lost the most gold to",
                        type = "toggle",
                        order = 11,
                    },
                    showBestMatchup = {
                        name = "Best Matchup",
                        desc = "Show the opponent with the best net gold per game (minimum 3 games)",
                        type = "toggle",
                        order = 12,
                    },
                    showWorstMatchup = {
                        name = "Worst Matchup",
                        desc = "Show the opponent with the worst net gold per game (minimum 3 games)",
                        type = "toggle",
                        order = 13,
                    },
                    showBiggestWin = {
                        name = "Biggest Single Win",
                        desc = "Show your largest single game victory",
                        type = "toggle",
                        order = 14,
                    },
                    showBiggestLoss = {
                        name = "Biggest Single Loss",
                        desc = "Show your largest single game defeat",
                        type = "toggle",
                        order = 15,
                    },
                    showHighRoller = {
                        name = "High Roller",
                        desc = "Show the player you've had the highest average wager with",
                        type = "toggle",
                        order = 16,
                    },
                    showCheapskate = {
                        name = "Cheapskate",
                        desc = "Show the player you've had the lowest average wager with",
                        type = "toggle",
                        order = 17,
                    },
                    separator3 = {
                        name = "Luck & Streaks",
                        type = "header",
                        order = 18,
                    },
                    showLuckyPlayer = {
                        name = "Lucky Player",
                        desc = "Show who overperforms your 50/50 baseline the most (minimum 3 games)",
                        type = "toggle",
                        order = 19,
                    },
                    showUnluckyPlayer = {
                        name = "Unlucky Player",
                        desc = "Show who underperforms your 50/50 baseline the most (minimum 3 games)",
                        type = "toggle",
                        order = 20,
                    },
                    showDaredevil = {
                        name = "Daredevil Opponent",
                        desc = "Show which player prefers the highest starting rolls",
                        type = "toggle",
                        order = 21,
                    },
                    showConservative = {
                        name = "Conservative Opponent",
                        desc = "Show which player prefers the lowest starting rolls",
                        type = "toggle",
                        order = 22,
                    },
                },
            },
        },
    }
    
    if self.devDuel then
        local stats = options.args.statistics.args
        stats.description.name = "Choose which 1v1, Group, and opponent history statistics appear."
        stats.showLuckyPlayer, stats.showUnluckyPlayer = nil, nil
        stats.separator3.name = "Opening Rolls"
        stats.showFrenemy.name = "Closest Rival"
        stats.historyHeader = {type = "header", name = "Opponent History", order = 23}
        stats.showLikelyCheater.name = "Wrong-range Rolls"
        stats.showLikelyCheater.desc = "Show the wrong-range roll count in each opponent’s history."
        stats.showLikelyCheater.order = 24
        stats.groupHeader = {type = "header", name = "Group Statistics", order = 25}
        for index, option in ipairs(self.groupStatOptions) do
            stats[option.key] = {type = "toggle", name = option.label, order = 25 + index}
        end
    end
    -- AceConfig reads width on individual controls. Give each one its own row.
    for _, page in pairs(options.args) do
        for _, control in pairs(page.args) do
            control.width = "full"
        end
    end
    AceConfig:RegisterOptionsTable("DeathRollEnhancer", options)
    -- Current AceConfig integrates with Settings; older clients still use /dr config.
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        if Settings.GetCategory and Settings.RegisterCanvasLayoutSubcategory then
            self.optionsFrame = AceConfigDialog:AddToBlizOptions("DeathRollEnhancer", self.displayName, nil, "gameplay")
            for _, key in ipairs({"challenges", "interface", "statistics", "data"}) do
                AceConfigDialog:AddToBlizOptions("DeathRollEnhancer", options.args[key].name, self.displayName, key)
            end
        else
            self.optionsFrame = AceConfigDialog:AddToBlizOptions("DeathRollEnhancer", self.displayName)
        end
    end
end

-- UI Methods
function DRE:ShowMainWindow()
    self:Print("Opening DeathRoll window...")
end

function DRE:ShowHistory(playerName)
    self:Print("Showing history for: " .. playerName)
end

function DRE:OpenOptions()
    self:ShowMainWindow("settings")
end

function DRE:UpdateUIScale()
    if DRE.UI and DRE.UI.mainWindow and DRE.UI.mainWindow.frame then
        local scale = self.db.profile.ui.scale or 0.9
        DRE.UI.mainWindow.frame:SetScale(scale)
        if self.QueueLayoutRefresh then
            self:QueueLayoutRefresh()
        end
    end
end


function DRE:ResetWindowPosition()
    -- Clear AceGUI status table position data
    if self.db.profile.ui.frameStatus then
        self.db.profile.ui.frameStatus.left = nil
        self.db.profile.ui.frameStatus.top = nil
        self.db.profile.ui.frameStatus.width = nil
        self.db.profile.ui.frameStatus.height = nil
    end
    
    -- Also reset the currently open window if it exists
    if self.UI and self.UI.mainWindow and self.UI.mainWindow.frame then
        self.UI.mainWindow.frame:ClearAllPoints()
        self.UI.mainWindow.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        self.UI.mainWindow:SetWidth(self.tableWidth or 400)
        self.UI.mainWindow:SetHeight(self.tableHeight or 311)
    end
    
    self:Print("Window position and size reset to defaults")
end

function DRE:ResetWindowSize()
    -- Clear AceGUI status table size data
    if self.db.profile.ui.frameStatus then
        self.db.profile.ui.frameStatus.width = nil
        self.db.profile.ui.frameStatus.height = nil
    end
    
    -- Also resize the currently open window if it exists
    if self.UI and self.UI.mainWindow then
        self.UI.mainWindow:SetWidth(self.tableWidth or 400)
        self.UI.mainWindow:SetHeight(self.tableHeight or 311)
    end
    
    self:Print(string.format("Window size reset to default (%dx%d)", self.tableWidth or 400, self.tableHeight or 311))
end

function DRE:PrintCurrentWindowSize()
    local savedWidth = nil
    local savedHeight = nil
    if self.db and self.db.profile and self.db.profile.ui and self.db.profile.ui.frameStatus then
        savedWidth = self.db.profile.ui.frameStatus.width
        savedHeight = self.db.profile.ui.frameStatus.height
    end

    local liveWidth = nil
    local liveHeight = nil
    local scale = (self.db and self.db.profile and self.db.profile.ui and self.db.profile.ui.scale) or 0.9

    if self.UI and self.UI.mainWindow then
        if self.UI.mainWindow.GetWidth and self.UI.mainWindow.GetHeight then
            liveWidth = self.UI.mainWindow:GetWidth()
            liveHeight = self.UI.mainWindow:GetHeight()
        end

        if self.UI.mainWindow.frame and self.UI.mainWindow.frame.GetScale then
            scale = self.UI.mainWindow.frame:GetScale() or scale
        end
    end

    if liveWidth and liveHeight then
        local effectiveWidth = math.floor((liveWidth or 0) * scale + 0.5)
        local effectiveHeight = math.floor((liveHeight or 0) * scale + 0.5)

        self:Print(string.format(
            "Current window size: %.0f x %.0f (scale %.2f, effective %.0f x %.0f)",
            liveWidth,
            liveHeight,
            scale,
            effectiveWidth,
            effectiveHeight
        ))
    else
        local fallbackWidth = savedWidth or self.tableWidth or 400
        local fallbackHeight = savedHeight or self.tableHeight or 311

        self:Print(string.format(
            "Window is not open. Saved size: %.0f x %.0f (scale %.2f)",
            fallbackWidth,
            fallbackHeight,
            scale
        ))
    end

    if savedWidth or savedHeight then
        self:Print(string.format(
            "Saved AceGUI size: %.0f x %.0f",
            savedWidth or self.tableWidth or 400,
            savedHeight or 300
        ))
    end
end

-- Module initialization methods (actual implementations are in separate files)
function DRE:InitializeUI()
    -- UI module is initialized when ShowMainWindow is called
    -- All UI functions are implemented in UI.lua
end

function DRE:InitializeMinimap()
    -- Minimap initialization is implemented in Minimap.lua
    -- This method is defined there and will be called
end

function DRE:InitializeSharedMedia()
    -- Register custom fonts, textures, sounds
    if LSM then
        -- Register custom media if we have any
        -- LSM:Register("font", "DeathRoll Font", "Interface\\AddOns\\DeathRollEnhancer\\Media\\Font.ttf")
        -- LSM:Register("sound", "DeathRoll Win", "Interface\\AddOns\\DeathRollEnhancer\\Media\\win.mp3")
        -- LSM:Register("sound", "DeathRoll Loss", "Interface\\AddOns\\DeathRollEnhancer\\Media\\loss.mp3")
        
        self:Print("LibSharedMedia initialized")
    end
end

-- Event handlers - handle both fallback and active game system messages  
function DRE:CHAT_MSG_SYSTEM(event, message)
    if not self:IsAccessibleValue(message) or type(message) ~= "string" then return end
    -- Add to debug buffer
    self:AddToDebugBuffer("CHAT_MSG_SYSTEM", message)
    
    -- Debug: Show all system messages to help identify roll format
    self:DebugPrint("CHAT_MSG_SYSTEM triggered with message: '" .. (message or "nil") .. "'")
    
    -- Use unified processing function for all roll detection
    self:ProcessPotentialRoll(message, nil, "SYSTEM")
end

function DRE:ADDON_LOADED(event, addonName)
    if addonName == "DeathRollEnhancer" then
        self:UnregisterEvent("ADDON_LOADED")
    end
end

-- Handle target change to update button text
function DRE:PLAYER_TARGET_CHANGED(event)
    -- Don't update button during active games to prevent confusion
    if not (self.gameState and self.gameState.isActive) then
        self:UpdateChallengeButtonText()
        -- Also check for recent rolls from the new target
        self:CheckRecentRollsForChallenge()
    end
end

function DRE:TRADE_SHOW(event)
    self:CaptureTradeState(true)
end

function DRE:TRADE_MONEY_CHANGED(event)
    self:CaptureTradeState(false)
end

function DRE:TRADE_ACCEPT_UPDATE(event)
    self:CaptureTradeState(false)
end

function DRE:TRADE_CLOSED(event)
    if self.tradeTracking then
        self.tradeTracking.closedAt = time()
        if self.RefreshDuel then self:RefreshDuel() end
    end
end

function DRE:TRADE_REQUEST_CANCEL(event)
    self.tradeTracking = nil
    if self.RefreshDuel then self:RefreshDuel() end
end

function DRE:UI_INFO_MESSAGE(event, messageType, message)
    if not self:IsAccessibleValue(message) or not self:IsAccessibleValue(messageType) then return end
    local infoMessage = message or messageType
    if infoMessage ~= ERR_TRADE_COMPLETE then
        return
    end

    self:DebugPrint("Successful trade detected")
    self:HandleTrackedTradeCompletion()
    if self.RefreshDuel then self:RefreshDuel() end
end

-- Player-authored text must never drive dice results or suspicion records.
function DRE:CHAT_MSG_TEXT_EMOTE() end
function DRE:CHAT_MSG_EMOTE() end

function DRE:ProcessPotentialRoll(message, sender, eventType)
    if eventType ~= "SYSTEM" or self.disabled then return end
    local parsed = self:ParseRollMessage(message)
    if not parsed then return end
    -- There is one authoritative event subscription. Content/time deduplication
    -- would incorrectly drop legitimate identical rolls in quick succession.
    self:HandleDetectedRoll(parsed.playerName, parsed.roll, parsed.maxRoll)
end

-- Check if a roll has already been processed (deduplication)
function DRE:IsRollAlreadyProcessed(rollId)
    if not self.processedRolls then
        self.processedRolls = {}
        return false
    end

    local currentTime = GetTime()

    -- Clean up expired entries
    for id, timestamp in pairs(self.processedRolls) do
        if currentTime - timestamp > (self.processedRollsExpiry or 5) then
            self.processedRolls[id] = nil
        end
    end

    return self.processedRolls[rollId] ~= nil
end

-- Mark a roll as processed
function DRE:MarkRollAsProcessed(rollId)
    if not self.processedRolls then
        self.processedRolls = {}
    end
    self.processedRolls[rollId] = GetTime()
end

-- Store a recent roll for later challenge detection
function DRE:StoreRecentRoll(playerName, roll, maxRoll)
    local currentTime = GetTime()

    -- Clean up old rolls first
    self:CleanupOldRolls(currentTime)

    -- Store the new roll
    local rollData = {
        playerName = playerName,
        roll = roll,
        maxRoll = maxRoll,
        timestamp = currentTime
    }

    if not self.recentRolls then
        self.recentRolls = {}
    end

    table.insert(self.recentRolls, rollData)
    if self.devDuel and self.acceptedChallenge then
        rememberOpeningRoll(self.acceptedChallenge, rollData)
    end

    -- Limit the number of stored rolls (with bounds checking to prevent infinite loops)
    local maxRolls = self.maxRecentRolls or 10
    if maxRolls < 1 then
        maxRolls = 10  -- Safety fallback
    end

    -- Limit iterations to prevent infinite loop
    local iterations = 0
    local maxIterations = #self.recentRolls + 10  -- Extra buffer for safety
    while #self.recentRolls > maxRolls and iterations < maxIterations do
        table.remove(self.recentRolls, 1)
        iterations = iterations + 1
    end

    if iterations >= maxIterations then
        self:DebugPrint("WARNING: Hit max iterations in StoreRecentRoll cleanup - possible corruption")
    end

    self:DebugPrint("Stored recent roll: " .. playerName .. " rolled " .. roll .. " (1-" .. maxRoll .. ")")

    -- Update button text dynamically when new rolls are detected
    self:UpdateChallengeButtonText()
end

-- Clean up rolls older than the time window
function DRE:CleanupOldRolls(currentTime)
    if not self.recentRolls then
        self.recentRolls = {}
        return
    end

    local cutoffTime = currentTime - (self.recentRollTimeWindow or 60)

    for i = #self.recentRolls, 1, -1 do
        if self.recentRolls[i] and self.recentRolls[i].timestamp and self.recentRolls[i].timestamp < cutoffTime then
            table.remove(self.recentRolls, i)
        end
    end
end

function DRE:RecordSuspiciousRoll(playerName, roll, maxRoll, expectedMaxRoll)
    if not playerName or not self.db or not self.db.profile then
        return nil
    end

    self.db.profile.suspiciousRolls = self.db.profile.suspiciousRolls or {}

    local existing = self.db.profile.suspiciousRolls[playerName] or {
        count = 0
    }

    existing.count = (existing.count or 0) + 1
    existing.lastRoll = tonumber(roll) or 0
    existing.lastMaxRoll = tonumber(maxRoll) or 0
    existing.expectedMaxRoll = tonumber(expectedMaxRoll) or 0
    existing.lastSeen = time()

    self.db.profile.suspiciousRolls[playerName] = existing

    if self.devDuel and self.UI.currentTab == "history" then self:UpdateStatsDisplay() end

    self:DebugPrint(string.format(
        "Tracked suspicious roll for %s: roll=%d max=%d expectedMax=%d count=%d",
        playerName,
        existing.lastRoll,
        existing.lastMaxRoll,
        existing.expectedMaxRoll,
        existing.count
    ))

    return existing
end

function DRE:PrintSuspiciousRollSummary()
    if not self.db or not self.db.profile or not self.db.profile.suspiciousRolls then
        self:Print("No suspicious rolls recorded.")
        return
    end

    local suspiciousList = {}
    for playerName, entry in pairs(self.db.profile.suspiciousRolls) do
        if entry and (entry.count or 0) > 0 then
            table.insert(suspiciousList, {
                playerName = playerName,
                count = entry.count or 0,
                lastRoll = entry.lastRoll or 0,
                lastMaxRoll = entry.lastMaxRoll or 0,
                expectedMaxRoll = entry.expectedMaxRoll or 0,
                lastSeen = entry.lastSeen or 0
            })
        end
    end

    if #suspiciousList == 0 then
        self:Print("No suspicious rolls recorded.")
        return
    end

    table.sort(suspiciousList, function(a, b)
        if a.count == b.count then
            return a.lastSeen > b.lastSeen
        end
        return a.count > b.count
    end)

    self:Print("=== Tracked Invalid Rolls ===")
    for _, record in ipairs(suspiciousList) do
        local whenText = "unknown"
        if record.lastSeen and record.lastSeen > 0 then
            whenText = date("%Y-%m-%d %H:%M", record.lastSeen)
        end

        self:Print(string.format(
            "%s: %d flagged roll(s) - last %d (1-%d), expected 1-%d at %s",
            record.playerName,
            record.count,
            record.lastRoll,
            record.lastMaxRoll,
            record.expectedMaxRoll,
            whenText
        ))
    end
end

function DRE:SetSuspiciousRollCount(playerName, newCount)
    if not self.db or not self.db.profile then
        return false, "No data available"
    end

    playerName = self:Trim(playerName or "")
    if playerName == "" then
        return false, "Player name is required"
    end

    local countNumber = tonumber(newCount)
    if not countNumber then
        return false, "Suspicious count must be a number"
    end

    countNumber = math.floor(countNumber)
    if countNumber < 0 then
        return false, "Suspicious count cannot be negative"
    end

    self.db.profile.suspiciousRolls = self.db.profile.suspiciousRolls or {}
    local existing = self.db.profile.suspiciousRolls[playerName]

    if countNumber == 0 then
        if existing then
            self.db.profile.suspiciousRolls[playerName] = nil
            if self.UpdateStatsDisplay then
                self:UpdateStatsDisplay()
            end
            return true, string.format("Cleared suspicious-roll entry for %s.", playerName)
        end
        return true, string.format("No suspicious-roll entry exists for %s.", playerName)
    end

    if not existing then
        existing = {
            count = 0,
            lastRoll = 0,
            lastMaxRoll = 0,
            expectedMaxRoll = 0,
            lastSeen = 0
        }
    end

    existing.count = countNumber
    existing.lastSeen = existing.lastSeen or time()
    self.db.profile.suspiciousRolls[playerName] = existing

    if self.UpdateStatsDisplay then
        self:UpdateStatsDisplay()
    end

    return true, string.format("Set suspicious-roll count for %s to %d.", playerName, countNumber)
end

function DRE:ClearSuspiciousRollEntry(playerName)
    return self:SetSuspiciousRollCount(playerName, 0)
end

-- Clear recent rolls for a specific player (e.g., when game starts/ends)
function DRE:ClearRecentRollsForPlayer(playerName)
    if not self.recentRolls or not playerName then return end

    for i = #self.recentRolls, 1, -1 do
        if self.recentRolls[i] and self.recentRolls[i].playerName == playerName then
            table.remove(self.recentRolls, i)
            self:DebugPrint("Cleared recent roll for " .. playerName)
        end
    end
end

-- Check recent rolls for a challenge from the current target
function DRE:CheckRecentRollsForChallenge()
    if self:HasActiveGame() then return end
    local currentTarget = DRE:GetUnitPlayerName("target")
    if not currentTarget then
        self:DebugPrint("CheckRecentRollsForChallenge: No target selected")
        return
    end
    
    -- Check if UI is open and on the right tab
    local uiOpen = (self.UI and self.UI.mainWindow and self.UI.mainWindow.frame and self.UI.mainWindow.frame:IsVisible())
    if not uiOpen then
        self:DebugPrint("CheckRecentRollsForChallenge: UI not open")
        return
    end
    
    local onCorrectTab = (self.UI.currentTab == "deathroll")
    if not onCorrectTab then
        self:DebugPrint("CheckRecentRollsForChallenge: Not on DeathRoll tab")
        return
    end
    
    self:DebugPrint("CheckRecentRollsForChallenge: Checking for recent roll from " .. currentTarget)
    
    -- Clean up old rolls first
    self:CleanupOldRolls(GetTime())
    
    -- Look for the most recent roll from the current target
    for i = #self.recentRolls, 1, -1 do
        local rollData = self.recentRolls[i]
        if self:IsSamePlayer(rollData.playerName, currentTarget) then
            self:DebugPrint("Found recent roll from target: " .. currentTarget .. " rolled " .. rollData.roll .. " (1-" .. rollData.maxRoll .. ")")
            self:ShowChallengeNotification(currentTarget, rollData.roll, rollData.maxRoll)
            return
        end
    end
    
    self:DebugPrint("No recent roll found from " .. currentTarget)
end

-- Handle detected roll from any event source
function DRE:HandleDetectedRoll(playerName, roll, maxRoll)
    if self:IsGroupGuest() then return end -- Only the joined host adjudicates server rolls.
    if self:IsGroupRoundActive() then
        self:HandleGroupRoll(playerName, roll, maxRoll)
        return -- group rolls must never become 1v1 challenge candidates
    end
    playerName = self:NormalizePlayerName(playerName)
    if self.outgoingChallenge or (self.pendingChallenge and self.pendingChallenge.waitForAccept
        and self:IsSamePlayer(playerName, self.pendingChallenge.sender)) then return end
    if not playerName or not self:IsBoundedInteger(maxRoll, 1, self.MAX_ROLL)
        or not self:IsBoundedInteger(roll, 1, maxRoll) then return end
    self:DebugPrint("HandleDetectedRoll called: player=" .. (playerName or "nil") .. ", roll=" .. (roll or "nil") .. ", maxRoll=" .. (maxRoll or "nil"))
    
    -- Store this roll in recent rolls (unless it's our own roll)
    local myName = DRE:GetUnitPlayerName("player")
    if not myName then return end
    if playerName ~= myName then
        self:StoreRecentRoll(playerName, roll, maxRoll)
    end
    
    -- Handle active game rolls first (highest priority)
    if self.gameState and self.gameState.isActive then
        local myName = DRE:GetUnitPlayerName("player")
        self:DebugPrint("Game active - checking if roll is relevant (player: " .. myName .. ", target: " .. (self.gameState.target or "nil") .. ")")
        
        -- Check if this roll is relevant to our game
        if (playerName == myName or playerName == self.gameState.target) then
            self:DebugPrint("Roll is relevant - processing via HandleGameRoll")
            self:HandleGameRoll(playerName, roll, maxRoll)
        else
            self:DebugPrint("Roll not relevant - player: " .. playerName .. ", maxRoll: " .. maxRoll .. ", currentRoll: " .. (self.gameState.currentRoll or "nil"))
        end
        return -- Don't process further if game is active
    end
    
    -- No active game - check for challenges
    self:DebugPrint("No active game - checking for challenges")
    
    -- Check if this roll is from someone we have targeted (they're challenging us)
    local currentTarget = DRE:GetUnitPlayerName("target")
    if currentTarget == playerName then
        self:DebugPrint("Roll detected from our current target - checking for challenge notification")
        self:CheckTargetedPlayerChallenge(playerName, roll, maxRoll)
    else
        self:DebugPrint("Roll from " .. playerName .. " but our target is " .. tostring(currentTarget))
        -- Only run auto-challenge if this isn't from our target (to avoid conflicts)
        self:CheckUIAutoChallenge(playerName, roll, maxRoll)
    end
end

-- Check if targeted player rolled and show challenge notification
function DRE:CheckTargetedPlayerChallenge(playerName, roll, maxRoll)
    if self:HasActiveGame() then return end
    self:DebugPrint("CheckTargetedPlayerChallenge: " .. playerName .. " rolled " .. roll .. " (1-" .. maxRoll .. ")")
    
    -- Only show if UI is open and we have them targeted
    local uiOpen = (self.UI and self.UI.mainWindow and self.UI.mainWindow.frame and self.UI.mainWindow.frame:IsVisible())
    self:DebugPrint("UI Open: " .. tostring(uiOpen))
    if not uiOpen then
        return -- UI not open
    end
    
    local onCorrectTab = (self.UI.currentTab == "deathroll")
    self:DebugPrint("On DeathRoll tab: " .. tostring(onCorrectTab))
    if not onCorrectTab then
        return -- Not on the right tab
    end
    
    local currentTarget = DRE:GetUnitPlayerName("target")
    local isTargeted = (currentTarget and currentTarget == playerName)
    self:DebugPrint("Current target: " .. tostring(currentTarget) .. ", Roll from target: " .. tostring(isTargeted))
    if not isTargeted then
        return -- This player is not our current target
    end
    
    local gameActive = (self.gameState and self.gameState.isActive)
    self:DebugPrint("Game already active: " .. tostring(gameActive))
    if gameActive then
        return -- Already in a game
    end
    
    self:DebugPrint("All conditions met - showing challenge notification!")
    -- Show challenge notification in the UI
    self:ShowChallengeNotification(playerName, roll, maxRoll)
end

-- Store an incoming challenge for the active DeathRoll UI
function DRE:ShowChallengeNotification(playerName, roll, maxRoll)
    if self:HasActiveGame() then return end
    self:DebugPrint("ShowChallengeNotification: " .. tostring(playerName) .. " challenges you to DeathRoll 1-" .. tostring(maxRoll))

    if not self.UI then
        self:DebugPrint("UI not initialized, cannot show challenge notification")
        return
    end

    if not (self.UI.mainWindow and self.UI.mainWindow.frame and self.UI.mainWindow.frame:IsVisible()) then
        self:DebugPrint("UI not open, cannot show challenge notification")
        return
    end

    if self.UI.currentTab ~= "deathroll" then
        self:DebugPrint("Not on deathroll tab, cannot show challenge notification")
        return
    end

    if self.gameState and self.gameState.isActive then
        self:DebugPrint("Game already active, not showing challenge notification")
        return
    end

    -- Store the challenge data
    self.UI.incomingChallenge = {
        player = playerName,
        roll = roll,
        maxRoll = maxRoll,
        timestamp = GetTime()
    }
    
    -- The button text refresh logic reads from UI state when needed.
end

-- Update UI to show incoming challenge notification

-- Check if UI is open and auto-start challenge when target rolls
function DRE:CheckUIAutoChallenge(playerName, roll, maxRoll)
    if self:HasActiveGame() then return end
    self:DebugPrint("CheckUIAutoChallenge called: player=" .. playerName .. ", roll=" .. roll .. ", maxRoll=" .. maxRoll)
    
    -- Check if DeathRoll UI is open and visible
    local uiOpen = (self.UI and self.UI.mainWindow and self.UI.mainWindow.frame and self.UI.mainWindow.frame:IsVisible())
    self:DebugPrint("UI Open: " .. tostring(uiOpen))
    if not uiOpen then
        return -- UI not open
    end
    
    -- Check if we're on the deathroll tab
    local onCorrectTab = (self.UI.currentTab == "deathroll")
    self:DebugPrint("On DeathRoll tab: " .. tostring(onCorrectTab) .. " (current: " .. tostring(self.UI.currentTab) .. ")")
    if not onCorrectTab then
        return -- Not on the right tab
    end
    
    -- Check if this player is currently our target
    local currentTarget = DRE:GetUnitPlayerName("target")
    local isCurrentTarget = (currentTarget and currentTarget == playerName)
    self:DebugPrint("Current target: " .. tostring(currentTarget) .. ", Is target: " .. tostring(isCurrentTarget))
    if not isCurrentTarget then
        return -- Player is not our current target
    end
    
    -- Check if we're already in a game
    local gameActive = (self.gameState and self.gameState.isActive)
    self:DebugPrint("Game active: " .. tostring(gameActive))
    if gameActive then
        return -- Already in a game
    end
    
    -- Auto-fill the roll field in UI and start challenge
    self:DebugPrint("All conditions met - starting auto-challenge!")
    if self.UI.rollEdit then
        self.UI.rollEdit:SetText(tostring(maxRoll))
        self:ChatPrint("Auto-detected " .. playerName .. "'s roll (" .. maxRoll .. ") - starting challenge!")
        
        -- Immediately start the game with the detected roll
        self:StartActualGame(currentTarget, maxRoll, 0, maxRoll)
    else
        self:DebugPrint("ERROR: UI.rollEdit not found!")
    end
end


-- Handle whisper messages for spicy duels and fallback challenges
function DRE:CHAT_MSG_WHISPER(event, message, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
    if not self:IsAccessibleValue(message) or type(message) ~= "string" then return end
    playerName = self:NormalizePlayerName(playerName)
    if not playerName then return end
    -- Handle DeathRoll challenge messages
    if self.devDuel and (message:match("^DEATHROLL_CHALLENGE:") or message == "DEATHROLL_ACCEPT" or message == "DEATHROLL_DECLINE") then return end
    if message:match("^DEATHROLL_CHALLENGE:") then
        self:HandleChallengeWhisper(message, playerName)
        return
    end

    if message == "DEATHROLL_ACCEPT" or message == "DEATHROLL_DECLINE" then
        local game = self.gameState
        if game and game.whisperReplyUntil and GetTime() < game.whisperReplyUntil and self:IsSamePlayer(playerName, game.target) then
            game.whisperReplyUntil = nil
            self:Print(playerName .. (message == "DEATHROLL_ACCEPT" and " accepted your DeathRoll challenge!" or " declined your DeathRoll challenge."))
        end
        return
    end

    -- Handle Spicy Duel acceptance
    if message:lower():find("accept spicy") and self.spicyDuel and self.spicyDuel.target == playerName then
        self:ChatPrint(playerName .. " accepted your Spicy Duel challenge!")
        self:UpdateSpicyGameState("Challenge accepted! Round 1: Choose your stance! (HP: You 150, " .. playerName .. " 150)")

        -- Send confirmation
        self:SendChatSafely("Challenge accepted! Let the Spicy Duel begin! Choose your stance and roll!", "WHISPER", nil, playerName)
        return
    end
    
    -- Handle manual Spicy Duel stance reporting (fallback for non-addon users)
    local stance, roll = message:lower():match("my stance: (%w+) %(roll: (%d+)%)")
    if stance and roll and self.spicyDuel and self.spicyDuel.target == playerName then
        self.spicyDuel.opponentStance = stance
        self.spicyDuel.opponentRoll = tonumber(roll)
        
        -- Check if we're ready to resolve
        if self.spicyDuel.myStance and self.spicyDuel.myRoll then
            self:ResolveSpicyRound()
        end
        return
    end
end

-- Handle addon messages for inter-addon communication

-- Scan recent chat for ANY roll from debug buffer (not just target's)
function DRE:FindRecentTargetRoll(targetName)
    self:CleanupOldRolls(GetTime())
    for index = #self.recentRolls, 1, -1 do
        local roll = self.recentRolls[index]
        if self:IsSamePlayer(roll.playerName, targetName) then return roll end
    end
end

function DRE:UpdateChallengeButtonText()
    if self.RefreshDuel then self:RefreshDuel(); return end
    if self:IsGroupRoundActive() then return end
    -- Validate UI exists and is ready
    if not self.UI then
        self:DebugPrint("UpdateChallengeButtonText: UI not initialized")
        return
    end

    -- Don't update during active games
    if self.gameState and self.gameState.isActive then
        self:DebugPrint("UpdateChallengeButtonText: Game active, skipping update")
        return
    end

    -- Validate game button exists
    if not self.UI.gameButton then
        self:DebugPrint("UpdateChallengeButtonText: gameButton not found")
        return
    end

    local targetName = DRE:GetUnitPlayerName("target")

    if not targetName then
        self.UI.recentTargetRoll = nil
        self.UI.incomingChallenge = nil
        -- No target selected
        self:SafeUIUpdate(self.UI.gameButton, function()
            if self.UI and self.UI.gameButton then
                self.UI.gameButton:SetText("Challenge Player to DeathRoll!")
            end
        end, "gameButton")
        return
    end

    -- Check for recent roll from the current target
    local recentRoll = nil
    self:CleanupOldRolls(GetTime())

    if self.recentRolls then
        for i = #self.recentRolls, 1, -1 do
            local rollData = self.recentRolls[i]
            if rollData and self:IsSamePlayer(rollData.playerName, targetName) then
                recentRoll = rollData
                break
            end
        end
    end

    if recentRoll then
        -- Target has done a roll - show challenge button
        local buttonText = targetName .. " rolled " .. recentRoll.roll .. " from " .. recentRoll.maxRoll .. " - Accept challenge!"
        self:SafeUIUpdate(self.UI.gameButton, function()
            if self.UI and self.UI.gameButton then
                self.UI.gameButton:SetText(buttonText)
            end
        end, "gameButton")

        -- Set the roll input to their ROLL RESULT (not maxRoll)
        if self.UI.rollEdit then
            self:SafeUIUpdate(self.UI.rollEdit, function()
                if self.UI and self.UI.rollEdit then
                    self.UI.rollEdit:SetText(tostring(recentRoll.roll))
                end
            end, "rollEdit")
        end

        -- Store the recent roll data for button click handling
        self.UI.recentTargetRoll = recentRoll

        self:DebugPrint("Button updated for challenge from " .. targetName .. " with roll " .. recentRoll.roll .. " (1-" .. recentRoll.maxRoll .. ")")
    else
        -- No qualifying recent roll - show generic challenge button
        self:SafeUIUpdate(self.UI.gameButton, function()
            if self.UI and self.UI.gameButton then
                self.UI.gameButton:SetText("Challenge " .. targetName .. " to DeathRoll!")
            end
        end, "gameButton")

        -- Clear any stored roll data
        self.UI.recentTargetRoll = nil
    end
end

-- Conditional print that respects chat messages setting
function DRE:ChatPrint(message)
    if self.db and self.db.profile.gameplay.chatMessages then
        self:Print(message)
    end
end

-- Add message to debug chat buffer
function DRE:AddToDebugBuffer(source, message)
    if not self:IsAccessibleValue(source) or not self:IsAccessibleValue(message) then return end
    local timestamp = date("%H:%M:%S")
    local entry = string.format("[%s] %s: %s", timestamp, source, message or "nil")
    
    table.insert(self.debugChatBuffer, entry)
    
    -- Keep only last N messages
    if #self.debugChatBuffer > self.maxDebugMessages then
        table.remove(self.debugChatBuffer, 1)
    end
end

-- Dump debug buffer to chat
function DRE:DumpDebugBuffer()
    self:Print("=== DEBUG CHAT BUFFER START ===")
    self:Print("Buffer size: " .. #self.debugChatBuffer .. " messages")
    
    if #self.debugChatBuffer == 0 then
        self:Print("No messages in buffer yet - try doing some actions first")
    else
        for i, entry in ipairs(self.debugChatBuffer) do
            self:Print(entry)
        end
    end
    
    self:Print("=== DEBUG CHAT BUFFER END ===")
    
    -- Also save to file
    self:SaveDebugBufferToFile()
end

-- Save debug buffer to file
function DRE:SaveDebugBufferToFile()
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    
    -- Save to WoW saved variables instead of file I/O
    if not DeathRollEnhancer_DebugExport then
        DeathRollEnhancer_DebugExport = {}
    end
    
    -- Build debug data
    local debugData = {
        generated = timestamp,
        bufferSize = #self.debugChatBuffer,
        messages = {}
    }
    
    if #self.debugChatBuffer == 0 then
        table.insert(debugData.messages, "No messages in buffer yet - try doing some actions first")
    else
        for i, entry in ipairs(self.debugChatBuffer) do
            table.insert(debugData.messages, entry)
        end
    end
    
    -- Store in saved variables
    DeathRollEnhancer_DebugExport[timestamp] = debugData
    
    self:Print("Debug buffer saved to saved variables")
    self:Print("Will be available in SavedVariables/DeathRollEnhancer.lua after /reload")
    self:Print("Also showing copyable format in chat:")
    
    -- Print copyable format to chat
    print("=== DEATHROLL DEBUG EXPORT ===")
    print("Generated: " .. timestamp)
    print("Buffer size: " .. #self.debugChatBuffer .. " messages")
    print("=" .. string.rep("=", 30))
    
    if #self.debugChatBuffer == 0 then
        print("No messages in buffer yet")
    else
        for i, entry in ipairs(self.debugChatBuffer) do
            print(entry)
        end
    end
    
    print("=" .. string.rep("=", 30))
    print("=== END DEBUG EXPORT ===")
end

-- Conditional print that respects debug messages setting
function DRE:DebugPrint(message)
    -- Add to buffer regardless of settings
    self:AddToDebugBuffer("DEBUG", message)
    
    -- Print to chat if enabled
    if (self.db and self.db.profile.gameplay.debugMessages) then
        self:Print("[DEBUG] " .. message)
    end
end

-- Main function to start a DeathRoll challenge (called from UI)
function DRE:StartDeathRoll(target, roll, wager, trackWagerByTrade, terms)
    -- Check for active game first to prevent concurrent games
    if self:HasActiveGame() then
        self:Print("A game is already in progress! Finish it or use /dr cancel.")
        return
    end

    target = self:NormalizePlayerName(target)
    local valid, reason = self:ValidateGameInputs(target, roll, wager)
    if not valid then self:Print(reason); return false end
    local playerName = self:GetUnitPlayerName("player")

    -- Check for self-dueling
    if target == playerName then
        self:Print("Starting self-duel! You'll play against yourself.")

        -- Start the actual game immediately for self-dueling
        if not self:StartActualGame(target, roll, wager, nil, trackWagerByTrade, terms) then return false end
        self:PlayTurnSound()

        -- Update UI state to rolling
        if self.UpdateGameUIState then
            self:UpdateGameUIState("ROLLING")
        end
        return true
    end

    if not self:StartActualGame(target, roll, wager, roll, trackWagerByTrade, terms) then return false end
    self:PerformRoll()
    return true
end


-- Show dialog to edit recent game records
function DRE:ShowEditGameDialog(gameId)
    -- Close existing dialog if open
    if self.editGameFrame then
        self.editGameFrame:Hide()
    end
    
    local recentGames
    if gameId then
        local player, index, game = self:FindGameRecordById(gameId)
        recentGames = game and {{playerName = player, gameIndex = index, gameId = gameId,
            game = game, timestamp = game.timestamp}} or {}
    else
        recentGames = self:GetRecentGamesForEditing(15)
    end
    
    if #recentGames == 0 then
        self:Print("No recent game records found to edit!")
        return
    end
    
    -- Create frame
    local frame = DRE:CreateWindowWidget("Frame")
    frame:SetTitle("Edit Game Record")
    frame:SetLayout("Flow")
    frame:SetWidth(500)
    frame:SetHeight(400)
    local body = frame
    if self.devDuel then
        frame:SetLayout("Fill")
        body = AceGUI:Create("ScrollFrame")
        body:SetLayout("Flow")
        body:SetFullWidth(true)
        body:SetFullHeight(true)
        frame:AddChild(body)
    end
    
    -- Store reference for refreshing
    self.editGameFrame = frame
    self:ReleaseWindowOnClose(frame, "editGameFrame")
    
    -- Build dropdown options (ensure newest first ordering)
    local gameList = {}
    local gameMap = {}
    
    -- Debug: Print the order we receive games in
    self:DebugPrint("Edit dialog game order:")
    for i, gameData in ipairs(recentGames) do
        local game = gameData.game
        self:DebugPrint(string.format("[%d] %s vs %s: %s - %s (timestamp: %s)", 
            i, DRE:GetUnitPlayerName("player") or "You", gameData.playerName, game.result or "Unknown",
            game.date or "Unknown Date", tostring(gameData.timestamp or 0)))
    end
    
    for i, gameData in ipairs(recentGames) do
        local game = gameData.game
        local myName = DRE:GetUnitPlayerName("player") or "You"
        
        -- Create display text for dropdown
        local resultText = game.result or "Unknown"
        local goldText = ""
        if game.goldAmount and game.goldAmount > 0 then
            goldText = " (" .. self:FormatGold(game.goldAmount) .. ")"
        end
        
        local dateText = game.date or "Unknown Date"
        local suspiciousCount = tonumber(game.suspiciousRollCount) or 0
        local overallSuspiciousCount = 0
        if self.db and self.db.profile and self.db.profile.suspiciousRolls then
            local suspiciousEntry = self.db.profile.suspiciousRolls[gameData.playerName]
            overallSuspiciousCount = tonumber(suspiciousEntry and suspiciousEntry.count) or 0
        end
        local suspiciousSuffix = ""
        if suspiciousCount > 0 then
            suspiciousSuffix = string.format(" [GAME FLAG x%d]", suspiciousCount)
        elseif overallSuspiciousCount > 0 then
            suspiciousSuffix = string.format(" [PLAYER FLAGS x%d]", overallSuspiciousCount)
        end
        local displayText = string.format("[%d] %s vs %s: %s%s - %s", 
            i, myName, gameData.playerName, resultText, goldText, dateText) .. suspiciousSuffix
        
        local key = "game_" .. string.format("%02d", i)  -- Zero-pad to ensure proper sorting
        gameList[key] = displayText
        gameMap[key] = gameData
    end
    
    -- Game selection dropdown
    local gameDropdown = self:CreateWindowWidget("Dropdown")
    gameDropdown:SetLabel("Select Game to Edit:")
    gameDropdown:SetList(gameList)
    gameDropdown:SetWidth(450)
    if self.devDuel then gameDropdown:SetFullWidth(true) end
    body:AddChild(gameDropdown)
    
    -- Container for editing UI (will be created dynamically)
    local selectedGameGroup = AceGUI:Create("SimpleGroup")
    selectedGameGroup:SetLayout("Flow")
    selectedGameGroup:SetFullWidth(true)
    body:AddChild(selectedGameGroup)
    
    -- Function to create editing UI for selected game
    local function createEditUI(gameData)
        selectedGameGroup:ReleaseChildren()
        
        if not gameData then return end
        
        local game = gameData.game
        local playerName = gameData.playerName
        local original = {
            result = self:NormalizeGameResult(game.result),
            wager = tonumber(game.goldAmount) or 0,
            roll = tonumber(game.initialRoll) or 0,
        }
        
        -- Game info header
        local infoLabel = AceGUI:Create("Label")
        infoLabel:SetText(string.format("Editing game vs %s from %s:", playerName, game.date or "Unknown Date"))
        infoLabel:SetFullWidth(true)
        selectedGameGroup:AddChild(infoLabel)

        local suspiciousCount = tonumber(game.suspiciousRollCount) or 0
        local suspiciousLabel = AceGUI:Create("Label")
        suspiciousLabel:SetText(string.format("Suspicious wrong rolls in this game: %d", suspiciousCount))
        suspiciousLabel:SetColor(suspiciousCount > 0 and 1 or 0.7, suspiciousCount > 0 and 0.35 or 0.7, suspiciousCount > 0 and 0.35 or 0.7)
        suspiciousLabel:SetFullWidth(true)
        selectedGameGroup:AddChild(suspiciousLabel)

        local overallSuspiciousCount = 0
        if self.db and self.db.profile and self.db.profile.suspiciousRolls then
            local suspiciousEntry = self.db.profile.suspiciousRolls[playerName]
            overallSuspiciousCount = tonumber(suspiciousEntry and suspiciousEntry.count) or 0
        end
        if overallSuspiciousCount > 0 then
            local overallSuspiciousLabel = AceGUI:Create("Label")
            overallSuspiciousLabel:SetText(string.format("Overall suspicious rolls for %s: %d", playerName, overallSuspiciousCount))
            overallSuspiciousLabel:SetColor(1, 0.8, 0.4)
            overallSuspiciousLabel:SetFullWidth(true)
            selectedGameGroup:AddChild(overallSuspiciousLabel)
        end

        if suspiciousCount > 0 and game.suspiciousRollDetails and game.suspiciousRollDetails ~= "" then
            local suspiciousDetailsLabel = AceGUI:Create("Label")
            suspiciousDetailsLabel:SetText("Details: " .. game.suspiciousRollDetails)
            suspiciousDetailsLabel:SetColor(0.9, 0.7, 0.7)
            suspiciousDetailsLabel:SetFullWidth(true)
            selectedGameGroup:AddChild(suspiciousDetailsLabel)
        end

        local function sizeEditorControl(widget, width, fraction)
            if self.devDuel then widget:SetRelativeWidth(fraction) else widget:SetWidth(width) end
        end
        local suspiciousCountInput = DRE:CreateWindowWidget("EditBox")
        suspiciousCountInput:SetLabel("Player Suspicion Count:")
        suspiciousCountInput:SetText(tostring(overallSuspiciousCount or 0))
        sizeEditorControl(suspiciousCountInput, 140, 0.5)
        selectedGameGroup:AddChild(suspiciousCountInput)
        
        -- Result dropdown
        local resultDropdown
        if self.devDuel then
            resultDropdown = self:CreateTableDropdownField(selectedGameGroup, "Result:", 0.5)
        else
            resultDropdown = AceGUI:Create("Dropdown")
            resultDropdown:SetLabel("Result:")
            resultDropdown:SetWidth(150)
            selectedGameGroup:AddChild(resultDropdown)
        end
        resultDropdown:SetList({win = "Won", lost = "Lost"})
        local resultKeys = {Won = "win", Lost = "lost"}
        resultDropdown:SetValue(resultKeys[original.result])
        
        -- Gold input
        local goldInput = DRE:CreateWindowWidget("EditBox")
        goldInput:SetLabel("Gold:")
        local currentGold = original.wager
        local gold = math.floor(currentGold / 10000)
        goldInput:SetText(tostring(gold))
        sizeEditorControl(goldInput, 80, 0.25)
        selectedGameGroup:AddChild(goldInput)
        
        -- Silver input  
        local silverInput = DRE:CreateWindowWidget("EditBox")
        silverInput:SetLabel("Silver:")
        local silver = math.floor((currentGold % 10000) / 100)
        silverInput:SetText(tostring(silver))
        sizeEditorControl(silverInput, 80, 0.25)
        selectedGameGroup:AddChild(silverInput)
        
        -- Copper input
        local copperInput = DRE:CreateWindowWidget("EditBox")
        copperInput:SetLabel("Copper:")
        local copper = currentGold % 100
        copperInput:SetText(tostring(copper))
        sizeEditorControl(copperInput, 80, 0.25)
        selectedGameGroup:AddChild(copperInput)
        
        -- Starting roll input
        local rollInput = DRE:CreateWindowWidget("EditBox")
        rollInput:SetLabel("Starting Roll:")
        rollInput:SetText(tostring(original.roll))
        sizeEditorControl(rollInput, 100, 0.25)
        selectedGameGroup:AddChild(rollInput)
        
        -- Button container for save and delete buttons
        local buttonGroup = AceGUI:Create("SimpleGroup")
        buttonGroup:SetLayout("Flow")
        buttonGroup:SetFullWidth(true)
        selectedGameGroup:AddChild(buttonGroup)

        local setSuspicionButton = DRE:CreateWindowWidget("Button")
        setSuspicionButton:SetText("Save Suspicion Count")
        sizeEditorControl(setSuspicionButton, 170, 0.5)
        setSuspicionButton:SetCallback("OnClick", function()
            local requestedCount = tonumber(suspiciousCountInput:GetText())
            if not requestedCount then
                self:Print("Suspicion count must be a whole number.")
                return
            end

            requestedCount = math.floor(requestedCount)
            local success, message = self:SetSuspiciousRollCount(playerName, requestedCount)
            if success then
                self:Print(message)
                if self.RefreshEditDialog then
                    self:RefreshEditDialog()
                end
            else
                self:Print("Failed to save suspicion count: " .. (message or "Unknown error"))
            end
        end)
        buttonGroup:AddChild(setSuspicionButton)

        local clearSuspicionButton = DRE:CreateWindowWidget("Button")
        clearSuspicionButton:SetText("Clear Suspicion Entry")
        sizeEditorControl(clearSuspicionButton, 170, 0.5)
        clearSuspicionButton:SetCallback("OnClick", function()
            local success, message = self:ClearSuspiciousRollEntry(playerName)
            if success then
                self:Print(message)
                if self.RefreshEditDialog then
                    self:RefreshEditDialog()
                end
            else
                self:Print("Failed to clear suspicion entry: " .. (message or "Unknown error"))
            end
        end)
        buttonGroup:AddChild(clearSuspicionButton)
        
        -- Save button
        local saveButton = DRE:CreateWindowWidget("Button")
        saveButton:SetText("Save Changes")
        sizeEditorControl(saveButton, 150, 0.5)
        saveButton:SetCallback("OnClick", function()
            local selected = resultDropdown:GetValue()
            if selected ~= "win" and selected ~= "lost" then
                self:Print("Choose Won or Lost before saving.")
                return
            end
            local newResult = selected == "win" and "Won" or "Lost"
            local function readWholeNumber(input)
                local text = self:Trim(input:GetText())
                -- Empty fields explicitly mean zero; malformed text must never erase data.
                if text == "" then return 0 end
                if not text:match("^[0-9]+$") then return nil end
                return tonumber(text)
            end
            local gold = readWholeNumber(goldInput)
            local silver = readWholeNumber(silverInput)
            local copper = readWholeNumber(copperInput)
            local newInitialRoll = readWholeNumber(rollInput)

            -- Validate inputs
            if not self:IsBoundedInteger(gold, 0, 999999) then
                self:Print("Gold must be a whole number between 0 and 999,999 (no commas)!")
                return
            end
            if not self:IsBoundedInteger(silver, 0, 99) then
                self:Print("Silver must be a whole number between 0 and 99!")
                return
            end
            if not self:IsBoundedInteger(copper, 0, 99) then
                self:Print("Copper must be a whole number between 0 and 99!")
                return
            end
            if not self:IsBoundedInteger(newInitialRoll, 0, 999999) then
                self:Print("Starting roll must be a whole number between 0 and 999,999!")
                return
            end

            local newGoldAmount = gold * 10000 + silver * 100 + copper

            local success, message = self:EditGameRecordById(gameData.gameId, newResult, newGoldAmount, newInitialRoll, original)

            if success then
                self:Print(message)
                frame:Hide()
                -- Update UI if it's open
                if self.UpdateStatsDisplay then
                    self:UpdateStatsDisplay()
                end
            else
                self:Print("Failed to update: " .. message)
            end
        end)
        buttonGroup:AddChild(saveButton)
        
        -- Delete button
        local deleteButton = DRE:CreateWindowWidget("Button")
        deleteButton:SetText("Delete Game")
        sizeEditorControl(deleteButton, 150, 0.5)
        deleteButton:SetCallback("OnClick", function()
            -- Show confirmation dialog with parameters
            self:ShowDialog("DEATHROLL_DELETE_GAME_CONFIRM", nil, nil, gameData.gameId)
        end)
        buttonGroup:AddChild(deleteButton)
    end
    
    -- Update edit UI when dropdown selection changes
    gameDropdown:SetCallback("OnValueChanged", function(widget, event, key)
        local selectedGameData = gameMap[key]
        if selectedGameData then
            createEditUI(selectedGameData)
        end
    end)
    
    -- Initialize with first game (newest)
    if recentGames[1] then
        local firstKey = "game_01"  -- Match the zero-padded format
        gameDropdown:SetValue(firstKey)
        createEditUI(gameMap[firstKey])
    end
    
    frame:Show()
end

-- Refresh the edit dialog after a game is deleted
function DRE:RefreshEditDialog()
    if self.editGameFrame then self:ShowEditGameDialog() end
end

-- Addon-owned dialogs avoid Blizzard's protected Forever popup stack.
DRE.Dialogs = {}
DRE.Dialogs["DEATHROLL_CHALLENGE_POPUP"] = {
    text = "%s",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(dialog)
        if dialog.data == previewChallenge then
            DRE:ShowMainWindow("deathroll")
            DRE:Print("Challenge preview accepted.")
            return
        end
        DRE:AcceptChallenge(dialog.data)
    end,
    OnCancel = function(dialog, data, reason)
        local challenge = data or (dialog and dialog.data)
        if not challenge then return end
        if challenge == previewChallenge then
            if reason == "clicked" then DRE:Print("Challenge preview declined.") end
            return
        end
        if not dialog or reason == "timeout" or reason == "override" then
            if DRE.pendingChallenge == challenge then
                DRE.pendingChallenge = nil
                DRE:ClearRecentRollsForPlayer(challenge.sender)
                if DRE.devDuel then DRE:RefreshDuel() end
            end
        else
            DRE:DeclineChallenge(challenge)
        end
    end,
    timeout = 30,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

DRE.Dialogs["DEATHROLL_RESET_CONFIRM"] = {
    text = "Are you sure you want to reset ALL DeathRoll data?\n\nThis will permanently delete:\n- All game history\n- All statistics\n- All player records\n\nThis action cannot be undone!",
    button1 = "Yes, Reset Everything",
    button2 = "Cancel",
    OnAccept = function()
        if DRE and DRE.ResetAllData then
            DRE:ResetAllData()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Create delete game confirmation popup
DRE.Dialogs["DEATHROLL_DELETE_GAME_CONFIRM"] = {
    text = "Are you sure you want to delete this game record?\n\nThis will permanently remove:\n- The game from your history\n- Associated win/loss and gold statistics\n\nThis action cannot be undone!",
    button1 = "Yes, Delete Game",
    button2 = "Cancel",
    OnAccept = function(self)
        if DRE and self.data then
            local success, message = DRE:DeleteGameRecordById(self.data)
            if success then
                DRE:Print(message)
                -- Update UI if it's open
                if DRE.UpdateStatsDisplay then
                    DRE:UpdateStatsDisplay()
                end
                -- Refresh the edit dialog with updated data
                if DRE.RefreshEditDialog then
                    DRE:RefreshEditDialog()
                end
            else
                DRE:Print("Failed to delete game: " .. message)
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Start the actual DeathRoll game
function DRE:StartActualGame(target, initialRoll, wager, currentRoll, trackWagerByTrade, terms)
    target = self:NormalizePlayerName(target)
    local valid, reason = self:ValidateGameInputs(target, initialRoll, wager or 0)
    if not valid then self:Print(reason); return false end
    if not self:IsBoundedInteger(currentRoll or initialRoll, 1, initialRoll) then return false end
    if self:HasActiveGame() or self.disabled then return false end
    if terms and (not self.devDuel or not self.duelModes[terms.mode or "classic"]) then return false end
    local myName = DRE:GetUnitPlayerName("player")
    local isSelfDuel = (target == myName)

    self:DebugPrint("Starting actual game: target=" .. target .. ", initialRoll=" .. initialRoll .. ", currentRoll=" .. (currentRoll or initialRoll) .. ", isSelfDuel=" .. tostring(isSelfDuel))

    -- Initialize game state
    self.gameState = {
        isActive = true,
        target = target,
        initialRoll = initialRoll,
        currentRoll = currentRoll or initialRoll,
        wager = wager or 0,
        trackWagerByTrade = trackWagerByTrade == true,
        playerTurn = true,
        rollCount = 0,
        suspiciousRollCount = 0,
        suspiciousRollSamples = {}
    }
    if self.devDuel then
        local game = self.gameState
        game.mode = terms and terms.mode or "classic"
        if terms and terms.inviteId and game.mode ~= "classic" then game.playerTurn = false end
        game.matchId = terms and (terms.inviteId or terms.id) or "manual"
        game.double = terms and terms.double
        game.proposedDouble = game.double and not terms.inviteId
        if game.mode == "twoLives" or game.mode == "highRoller" then
            local initial = game.mode == "twoLives" and 2 or 0
            game.score = {player = initial, opponent = initial}
        end
    end

    if self.emoteSyncEnabled and not isSelfDuel then
        self.gameState.emoteRound = self:NewEmoteRound(target, initialRoll)
    end
    self.acceptedChallenge = nil
    if self.UI then
        self.UI.duelResult = nil
        self.UI.currentTarget = target
        self.UI.currentWager = wager or 0
        self.UI.isGameActive = true
        self.UI.recentTargetRoll = nil
        self.UI.incomingChallenge = nil
    end

    -- Clear recent rolls for the opponent to prevent button confusion
    if target ~= myName then
        self:ClearRecentRollsForPlayer(target)
    end
    
    -- Clear previous game's roll history to start fresh
    self:ClearRollHistory()
    
    self:DebugPrint("Game state initialized - isActive: " .. tostring(self.gameState.isActive) .. ", currentRoll: " .. self.gameState.currentRoll)
    
    
    self:ChatPrint("DeathRoll game started with " .. target .. "!")
    
    -- If currentRoll is different from initialRoll, it means opponent already rolled
    if not self.gameState.playerTurn then
        self:ChatPrint(target .. " opens with a roll of 1-" .. initialRoll)
    elseif currentRoll and currentRoll ~= initialRoll then
        self:ChatPrint("Current roll range: 1-" .. self.gameState.currentRoll)
        self:ChatPrint("Your turn! Roll 1-" .. self.gameState.currentRoll)
    else
        self:ChatPrint("Starting roll range: 1-" .. self.gameState.currentRoll)  
        self:ChatPrint("You go first! Roll 1-" .. self.gameState.currentRoll)
    end
    
    -- Update UI state to rolling
    if self.UpdateGameUIState then
        self:UpdateGameUIState("ROLLING")
    end
    
    -- Ensure system messages are registered to track rolls
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    return true
end

-- Local recovery only: cancellation never records an outcome or a pending payment.
function DRE:CancelCurrentGame()
    if self.outgoingChallenge then
        self:WithdrawDuelInvite()
        self:Print("Invitation cancelled.")
        return true
    end
    if self:IsGroupRoundActive() then return self:CancelGroupRound() end
    local game = self.gameState
    if not (game and game.isActive) then
        self:Print("No active game to cancel.")
        return false
    end
    game.isActive = false
    game.pendingRoll = nil
    self.gameState = nil -- retires delayed rolls/timeouts owned by this game
    self.acceptedChallenge = nil
    self.pendingChallenge = nil
    if self.activeDialog and self.activeDialog.definition == self.Dialogs.DEATHROLL_CHALLENGE_POPUP then
        self:CloseDialog(self.activeDialog, false, "override")
    end
    self:ClearRecentRollsForPlayer(game.target)
    self:ClearRecentRollsForPlayer(self:GetUnitPlayerName("player"))
    if self.UI then
        self.UI.isGameActive = false
        self.UI.currentTarget = nil
        self.UI.recentTargetRoll = nil
        self.UI.incomingChallenge = nil
        self.UI.inputRoll = game.initialRoll
        self.UI.inputWager = game.wager
        if self.UI.rollEdit then self.UI.rollEdit:SetText(tostring(game.initialRoll)) end
        self:SetWagerInputs(game.wager)
    end
    self:UpdateGameUIState("WAITING")
    self:Print("Game cancelled locally. No result or payment was recorded.")
    return true
end

-- Handle game end
function DRE:HandleGameEnd(loser, result, wager, initialRoll, options)
    local playerName = DRE:GetUnitPlayerName("player")
    local won = (result == "WIN")
    local emoteRound = self.gameState and self.gameState.emoteRound
    local opponent = (options and options.opponent) or (self.gameState and self.gameState.target) or "Unknown"
    local shouldTrackTrade = false
    local recordedPlayerName = nil
    local recordedResult = nil
    local recordedAt, recordedId = nil, nil
    if self.gameState then self.gameState.pendingRoll = nil end
    local forcedRecordedResult = options and options.recordedResult
    local gameMetadata = nil

    if self.gameState then
        local suspiciousRollCount = tonumber(self.gameState.suspiciousRollCount) or 0
        if suspiciousRollCount > 0 then
            gameMetadata = {
                suspiciousRollCount = suspiciousRollCount,
                suspiciousRollDetails = table.concat(self.gameState.suspiciousRollSamples or {}, ", ")
            }
        end
        if self.devDuel then
            gameMetadata = gameMetadata or {}
            gameMetadata.mode = self.gameState.mode
            gameMetadata.matchId = self.gameState.matchId
            gameMetadata.lastFace = self.gameState.lastFace
            gameMetadata.offeredDouble = self.gameState.proposedDouble or nil
            gameMetadata.firstLifeLost = self.gameState.firstLifeLost
            if self.gameState.mode == "highRoller" then
                gameMetadata.tiebreaks = self.gameState.tiebreaks or 0
                gameMetadata.tiebreakWins = self.gameState.tiebreakWins or 0
            end
            if self.gameState.mode ~= "classic" then
                gameMetadata.duelRolls = self.gameState.duelRolls
                gameMetadata.score = self.gameState.score
            end
        end
    end

    if options and options.trackWagerByTrade ~= nil then
        shouldTrackTrade = options.trackWagerByTrade == true
    elseif self.gameState then
        shouldTrackTrade = self.gameState.trackWagerByTrade == true
    end
    
    if won then
        self:Print("You WON the DeathRoll!")
    else
        self:Print("You LOST the DeathRoll!")
    end
    
    -- Add result to roll history
    self:AddGameResultToHistory(result, opponent, wager)
    
    -- Record the game result
    if forcedRecordedResult then
        if forcedRecordedResult == "WIN" then
            forcedRecordedResult = "Won"
        elseif forcedRecordedResult == "LOSS" then
            forcedRecordedResult = "Lost"
        end

        local target = opponent
        if not target or target == "" then
            target = self.gameState and self.gameState.target or "Unknown"
        end
        recordedPlayerName = target
        recordedResult = forcedRecordedResult
        recordedAt, recordedId = self:AddGameToHistory(target, recordedResult, wager or 0, initialRoll or 0, gameMetadata)
    elseif loser and loser ~= playerName then
        -- We won against the loser
        recordedPlayerName = loser
        recordedResult = "Won"
        recordedAt, recordedId = self:AddGameToHistory(loser, recordedResult, wager or 0, initialRoll or 0, gameMetadata)
    elseif loser == playerName then
        -- We lost to the target
        local target = self.gameState and self.gameState.target or "Unknown"
        if options and options.opponent then
            target = options.opponent
        end
        recordedPlayerName = target
        recordedResult = "Lost"
        recordedAt, recordedId = self:AddGameToHistory(target, recordedResult, wager or 0, initialRoll or 0, gameMetadata)
    end

    local trackPayment = shouldTrackTrade and recordedId and recordedPlayerName ~= playerName
    local ownerGUID = trackPayment and self:GetTradeOwnerGUID()
    if ownerGUID then
        self:PrunePendingTradeWagers()
        table.insert(self.db.profile.pendingTradeWagers, {
            ownerGUID = ownerGUID, playerName = recordedPlayerName, result = recordedResult,
            recordedAt = recordedAt, gameId = recordedId,
        })
        self:Print("Waiting for a completed gold trade with " .. recordedPlayerName .. " to record the wager.")
    elseif trackPayment then
        self:Print("Character identity unavailable. Use /dr edit to record this payment.")
    end

    if self.RememberDuelResult and recordedId then
        self:RememberDuelResult(recordedId, recordedPlayerName, recordedResult, wager, recordedAt,
            not not ownerGUID, self.gameState and self.gameState.duelRolls, self.gameState)
    end
    -- Clean up game state
    self.gameState = nil
    
    -- Clear recent roll data so button returns to normal after game
    if self.UI then
        self.UI.recentTargetRoll = nil
        self.UI.isGameActive = false
        self.UI.currentTarget = nil
        
        -- Remove recent rolls from the game opponent to prevent challenge button confusion
        if opponent and self.recentRolls then
            for i = #self.recentRolls, 1, -1 do
                local rollData = self.recentRolls[i]
                if rollData.playerName == opponent then
                    table.remove(self.recentRolls, i)
                end
            end
        end
        
        self.UI.inputRoll = self:GetDefaultStartingRoll()
        self.UI.inputWager = 0
        -- Clear roll and wager input fields
        if self.UI.rollEdit then
            self.UI.rollEdit:SetText(tostring(self.UI.inputRoll))
        end
        if self.UI.goldEdit then
            self.UI.goldEdit:SetText("")
        end
        if self.UI.silverEdit then
            self.UI.silverEdit:SetText("")
        end
        if self.UI.copperEdit then
            self.UI.copperEdit:SetText("")
        end
    end
    
    -- Update button text to clear any challenge text
    self:UpdateChallengeButtonText()
    
    -- Update UI state to game over
    if self.UpdateGameUIState then
        self:UpdateGameUIState("GAME_OVER")
    end
    
    -- Update stats display
    if self.UpdateStatsDisplay then
        self:UpdateStatsDisplay()
    end
    local autoEmote = self.db and self.db.profile.gameplay.autoEmote
    local hero = self.devDuel and self.UI and self.UI.tableHero
    local resultView = self.devDuel and self.UI.duelResult
    if emoteRound and resultView and resultView.gameId == recordedId then
        resultView.emoteRound = emoteRound
        emoteRound.finishedAt = GetTime()
    end
    if autoEmote or hero then
        local emote = won and self:GetRandomHappyEmote() or self:GetRandomSadEmote()
        if autoEmote and self:PerformResultEmote(won, emote) and emoteRound then
            self:SharePerformedEmote(emoteRound, emote)
        end
        if hero and resultView and resultView.gameId == recordedId then
            local otherEmote = won and self:GetRandomSadEmote() or self:GetRandomHappyEmote()
            hero:PlayOutcome(resultView, emote, otherEmote)
        end
    end
end

-- Cosmetic reactions must never interrupt saving or cleaning up a finished game.
function DRE:PerformResultEmote(won, emote)
    local perform = C_ChatInfo and C_ChatInfo.PerformEmote or DoEmote
    if not perform then return false end
    emote = emote or (won and self:GetRandomHappyEmote() or self:GetRandomSadEmote())
    local ok, played = pcall(perform, emote)
    if not ok or not self:IsAccessibleValue(played) then return false end
    if C_ChatInfo and C_ChatInfo.PerformEmote then return played == true end
    return played ~= false -- legacy DoEmote can return nothing on success
end

-- Handle ongoing game rolls
function DRE:HandleGameRoll(playerName, roll, maxRoll)
    self:DebugPrint("HandleGameRoll called: player=" .. (playerName or "nil") .. ", roll=" .. (roll or "nil") .. ", maxRoll=" .. (maxRoll or "nil") .. ", gameState.isActive=" .. tostring(self.gameState and self.gameState.isActive or false))

    -- Validate game state exists and is active
    if not self.gameState or not self.gameState.isActive then
        self:DebugPrint("No active game state, ignoring roll")
        return
    end

    -- Validate game state has required fields
    if not self.gameState.target or not self.gameState.currentRoll or not self.gameState.initialRoll then
        self:DebugPrint("Game state missing required fields, aborting")
        self.gameState = nil
        return
    end

    -- Validate parameters
    playerName = self:NormalizePlayerName(playerName)
    if not playerName or not self:IsBoundedInteger(maxRoll, 1, self.MAX_ROLL)
        or not self:IsBoundedInteger(roll, 1, maxRoll) then
        self:DebugPrint("Invalid parameters passed to HandleGameRoll")
        return
    end

    local myName = DRE:GetUnitPlayerName("player")
    if not myName then
        self:DebugPrint("Could not get player name")
        return
    end

    local isSelfDuel = (self.gameState.target == myName)
    local expectedMaxRoll = tonumber(self.gameState.currentRoll) or 0
    if expectedMaxRoll <= 0 then
        self:DebugPrint("Invalid expected roll range in game state")
        return
    end

    local isMyRoll = (playerName == myName)
    local isOpponentRoll = (not isSelfDuel and playerName == self.gameState.target)

    if not isMyRoll and not isOpponentRoll then return end
    if not isSelfDuel and ((isMyRoll and not self.gameState.playerTurn)
        or (isOpponentRoll and self.gameState.playerTurn)) then return end
    if isMyRoll then self.gameState.pendingRoll = nil end

    if maxRoll ~= expectedMaxRoll then
        if isOpponentRoll then
            local tracked = self:RecordSuspiciousRoll(playerName, roll, maxRoll, expectedMaxRoll)
            local suspiciousCount = tracked and tracked.count or 1
            if self.gameState then
                self.gameState.suspiciousRollCount = (tonumber(self.gameState.suspiciousRollCount) or 0) + 1
                self.gameState.suspiciousRollSamples = self.gameState.suspiciousRollSamples or {}
                if #self.gameState.suspiciousRollSamples < 3 then
                    table.insert(
                        self.gameState.suspiciousRollSamples,
                        string.format("%d (1-%d, expected 1-%d)", roll, maxRoll, expectedMaxRoll)
                    )
                end
            end
            local warningText = string.format(
                "|cffff4444Potential cheat detected: %s rolled %d (1-%d), expected 1-%d. [flag #%d]|r",
                playerName,
                roll,
                maxRoll,
                expectedMaxRoll,
                suspiciousCount
            )
            self:Print(warningText)
            self:ChatPrint(playerName .. " made an invalid roll range. Waiting for a valid roll 1-" .. expectedMaxRoll .. ".")
            if self.UpdateRollHistoryStatus then
                self:UpdateRollHistoryStatus(warningText, false)
            end
            if self.UpdateGameUIState then
                self:UpdateGameUIState("WAITING_FOR_OPPONENT")
            end
            return
        end

        if isMyRoll then
            self:Print(string.format(
                "Invalid roll ignored: you rolled 1-%d but expected 1-%d. Roll again.",
                maxRoll,
                expectedMaxRoll
            ))
            if self.UpdateGameUIState then
                self:UpdateGameUIState("ROLLING")
            end
            return
        end
    end
    
    if self.devDuel and self.gameState.mode and self.gameState.mode ~= "classic" then
        return self:AdvanceDuelMode(self.gameState, playerName, roll, maxRoll, isSelfDuel)
    end
    -- Only process rolls from the player if it's a regular duel or self-duel
    if isMyRoll then
        if isSelfDuel then
            -- Increment roll counter
            self.gameState.rollCount = self.gameState.rollCount + 1
            
            -- Add roll to history display
            self:AddRollToHistory(playerName, roll, maxRoll, true, self.gameState.rollCount)
            
            -- Self-duel: every roll alternates the game state
            self:ChatPrint("Roll " .. self.gameState.rollCount .. ": " .. roll .. " (1-" .. maxRoll .. ")")
            
            if roll == 1 then
                -- Game over - determine winner/loser based on roll count
                if (self.gameState.rollCount % 2) == 1 then
                    self:ChatPrint("You lost your self-duel! (Rolled 1 on turn " .. self.gameState.rollCount .. ")")
                    self:HandleGameEnd(myName, "LOSS", self.gameState.wager, self.gameState.initialRoll, {
                        opponent = myName,
                        recordedResult = "Lost"
                    })
                else
                    self:ChatPrint("You won your self-duel! (Your opponent-self rolled 1 on turn " .. self.gameState.rollCount .. ")")
                    self:HandleGameEnd(myName, "WIN", self.gameState.wager, self.gameState.initialRoll, {
                        opponent = myName,
                        recordedResult = "Won"
                    })
                end
            else
                -- Continue game
                self.gameState.currentRoll = roll
                self.gameState.playerTurn = not self.gameState.playerTurn
                if self.gameState.playerTurn then self:PlayTurnSound() end
                
                local nextTurnText = (self.gameState.rollCount % 2) == 1 and
                    "Your opponent-self's turn! Roll 1-" .. self.gameState.currentRoll or
                    "Your turn! Roll 1-" .. self.gameState.currentRoll
                    
                self:ChatPrint(nextTurnText)
                
                -- Update UI state - always rolling for self-duel
                if self.UpdateGameUIState then
                    self:UpdateGameUIState("ROLLING")
                end
            end
        else
            -- Regular duel - our roll
            self:AddRollToHistory(playerName, roll, maxRoll, false, nil)
            self:ChatPrint("You rolled " .. roll .. " (1-" .. maxRoll .. ")")
            
            if roll == 1 then
                -- We lost
                self:HandleGameEnd(myName, "LOSS", self.gameState.wager, self.gameState.initialRoll)
            else
                -- Continue game, opponent's turn
                self.gameState.currentRoll = roll
                self.gameState.playerTurn = false
                self:ChatPrint(self.gameState.target .. "'s turn! They need to roll 1-" .. self.gameState.currentRoll)
                
                -- Update UI state to waiting for opponent
                if self.UpdateGameUIState then
                    self:UpdateGameUIState("WAITING_FOR_OPPONENT")
                end
            end
        end
        
    elseif not isSelfDuel and playerName == self.gameState.target then
        -- Regular duel - opponent's roll (not applicable for self-duel)
        self:AddRollToHistory(playerName, roll, maxRoll, false, nil)
        self:ChatPrint(playerName .. " rolled " .. roll .. " (1-" .. maxRoll .. ")")
        
        if roll == 1 then
            -- They lost, we won
            self:HandleGameEnd(playerName, "WIN", self.gameState.wager, self.gameState.initialRoll)
        else
            -- Continue game, our turn
            self.gameState.currentRoll = roll
            self.gameState.playerTurn = true
            self:PlayTurnSound()
            self:ChatPrint("Your turn! Roll 1-" .. self.gameState.currentRoll)
            
            -- Update UI state to rolling
            if self.UpdateGameUIState then
                self:UpdateGameUIState("ROLLING")
            end
        end
    end
end

-- Event handling consolidated - CHAT_MSG_SYSTEM handler is at the top of file

-- Spicy Duel Game Logic
function DRE:StartSpicyDuel(target)
    if self:HasActiveGame() or self.disabled then
        self:Print("Finish or cancel the active game first.")
        return false
    end
    if not target or target == "" then
        self:Print("Invalid target for Spicy Duel!")
        return
    end
    
    -- Initialize Spicy Duel state
    self.spicyDuel = {
        isActive = true,
        target = target,
        myHP = 150,
        opponentHP = 150,
        round = 1,
        myStance = nil,
        myRoll = nil,
        opponentStance = nil,
        opponentRoll = nil,
        waitingForOpponent = false
    }
    
    -- Send challenge via whisper
    local message = "I challenge you to a Spicy DeathRoll RPS Dice Duel! Each player chooses Attack/Defend/Gamble, rolls d50, then we resolve damage. 150 HP each, first to 0 loses! Type 'accept spicy' if you're ready!"
    self:SendChatSafely(message, "WHISPER", nil, target)
    
    self:ChatPrint("Challenged " .. target .. " to a Spicy Duel!")
    self:UpdateSpicyGameState("Waiting for " .. target .. " to accept the challenge...")
    
    -- Register for whisper messages to catch responses
    self:RegisterEvent("CHAT_MSG_WHISPER")
end

function DRE:HandleSpicyRoll(stance)
    if not self.spicyDuel or not self.spicyDuel.isActive then
        self:Print("No active Spicy Duel! Challenge someone first.")
        return
    end
    
    if self.spicyDuel.myStance then
        self:Print("You already chose your stance for this round!")
        return
    end
    
    -- Roll d50 for the chosen stance
    local roll = math.random(1, 50)
    
    self.spicyDuel.myStance = stance
    self.spicyDuel.myRoll = roll
    
    -- Send stance and roll to opponent via whisper
    self:SendChatSafely("My stance: " .. stance .. " (roll: " .. roll .. ")", "WHISPER", nil, self.spicyDuel.target)
    
    local stanceName = stance == "attack" and "Attack" or stance == "defend" and "Defend" or "Gamble"
    self:UpdateSpicyGameState("Round " .. self.spicyDuel.round .. ": You chose " .. stanceName .. " and rolled " .. roll .. ". Waiting for opponent...")
    
    -- Check if both players have made their moves
    if self.spicyDuel.opponentStance and self.spicyDuel.opponentRoll then
        self:ResolveSpicyRound()
    end
end

function DRE:ResolveSpicyRound()
    if not self.spicyDuel then return end
    
    local myStance = self.spicyDuel.myStance
    local myRoll = self.spicyDuel.myRoll
    local oppStance = self.spicyDuel.opponentStance
    local oppRoll = self.spicyDuel.opponentRoll
    
    local damageToMe = 0
    local damageToOpp = 0
    
    -- Apply the RPS logic from the spec
    local matchup = myStance .. "_vs_" .. oppStance
    
    if matchup == "attack_vs_attack" then
        if myRoll > oppRoll then
            damageToOpp = myRoll - oppRoll
        elseif oppRoll > myRoll then
            damageToMe = oppRoll - myRoll
        end
        -- tie = no damage
        
    elseif matchup == "attack_vs_defend" then
        if myRoll > oppRoll then
            damageToOpp = myRoll - oppRoll
        end
        -- defend blocks if D >= A
        
    elseif matchup == "attack_vs_gamble" then
        -- Glass Cannon
        if myRoll >= oppRoll then
            damageToOpp = myRoll
        else
            damageToMe = oppRoll
        end
        
    elseif matchup == "defend_vs_attack" then
        if oppRoll > myRoll then
            damageToMe = oppRoll - myRoll
        end
        -- defend blocks if D >= A
        
    elseif matchup == "defend_vs_defend" then
        -- Stalemate, no damage
        
    elseif matchup == "defend_vs_gamble" then
        if oppRoll > myRoll then
            damageToMe = oppRoll
        else
            damageToOpp = math.ceil((myRoll - oppRoll) / 2) -- recoil
        end
        
    elseif matchup == "gamble_vs_attack" then
        -- Glass Cannon (reversed)
        if oppRoll >= myRoll then
            damageToMe = oppRoll
        else
            damageToOpp = myRoll
        end
        
    elseif matchup == "gamble_vs_defend" then
        if myRoll > oppRoll then
            damageToOpp = myRoll
        else
            damageToMe = math.ceil((oppRoll - myRoll) / 2) -- recoil
        end
        
    elseif matchup == "gamble_vs_gamble" then
        if myRoll > oppRoll then
            damageToOpp = 2 * (myRoll - oppRoll)
        elseif oppRoll > myRoll then
            damageToMe = 2 * (oppRoll - myRoll)
        else
            -- tie = both take 10
            damageToMe = 10
            damageToOpp = 10
        end
    end
    
    -- Apply critical hits and fumbles
    if myRoll == 50 then damageToOpp = damageToOpp + 10 end
    if oppRoll == 50 then damageToMe = damageToMe + 10 end
    if myRoll == 1 and (myStance == "attack" or myStance == "gamble") then damageToMe = damageToMe + 5 end
    if oppRoll == 1 and (oppStance == "attack" or oppStance == "gamble") then damageToOpp = damageToOpp + 5 end
    
    -- Apply damage
    self.spicyDuel.myHP = self.spicyDuel.myHP - damageToMe
    self.spicyDuel.opponentHP = self.spicyDuel.opponentHP - damageToOpp
    
    -- Report results
    local myStanceName = myStance == "attack" and "Attack" or myStance == "defend" and "Defend" or "Gamble"
    local oppStanceName = oppStance == "attack" and "Attack" or oppStance == "defend" and "Defend" or "Gamble"
    
    local resultMsg = string.format("Round %d Result:\nYou: %s (%d) vs %s: %s (%d)\nDamage: You took %d, %s took %d\nHP: You %d, %s %d",
        self.spicyDuel.round, myStanceName, myRoll, self.spicyDuel.target, oppStanceName, oppRoll,
        damageToMe, self.spicyDuel.target, damageToOpp,
        math.max(0, self.spicyDuel.myHP), self.spicyDuel.target, math.max(0, self.spicyDuel.opponentHP))
    
    self:Print(resultMsg)
    
    -- Check for game end
    if self.spicyDuel.myHP <= 0 and self.spicyDuel.opponentHP <= 0 then
        self:Print("Double KO! What an epic battle!")
        self:EndSpicyDuel()
    elseif self.spicyDuel.myHP <= 0 then
        self:Print("You lost the Spicy Duel! " .. self.spicyDuel.target .. " is victorious!")
        self:EndSpicyDuel()
    elseif self.spicyDuel.opponentHP <= 0 then
        self:Print("You won the Spicy Duel! Excellent strategy!")
        self:EndSpicyDuel()
    else
        -- Continue to next round
        self.spicyDuel.round = self.spicyDuel.round + 1
        self.spicyDuel.myStance = nil
        self.spicyDuel.myRoll = nil
        self.spicyDuel.opponentStance = nil
        self.spicyDuel.opponentRoll = nil
        
        self:UpdateSpicyGameState(string.format("Round %d: Choose your stance! (HP: You %d, %s %d)", 
            self.spicyDuel.round, self.spicyDuel.myHP, self.spicyDuel.target, self.spicyDuel.opponentHP))
    end
end

function DRE:EndSpicyDuel()
    self.spicyDuel = nil
    self:UpdateSpicyGameState("Duel completed! Ready for another challenge.")
end

function DRE:UpdateSpicyGameState(message)
    if self.UI and self.UI.spicyGameState then
        self.UI.spicyGameState:SetText(message)
    end
end

-- Handle Spicy Duel addon messages
function DRE:HandleSpicyDuelMessage(sender, message)
    if message:find("^SPICY_STANCE:") then
        local stance, roll = message:match("^SPICY_STANCE:([^:]+):(%d+)$")
        if stance and roll and self.spicyDuel and self.spicyDuel.target == sender then
            self.spicyDuel.opponentStance = stance
            self.spicyDuel.opponentRoll = tonumber(roll)
            
            -- Check if we're ready to resolve
            if self.spicyDuel.myStance and self.spicyDuel.myRoll then
                self:ResolveSpicyRound()
            end
        end
    end
end

-- Helper function to safely update UI elements
function DRE:SafeUIUpdate(element, updateFunc, elementName)
    if not element then
        self:DebugPrint("No " .. (elementName or "element") .. " found in UI")
        return false
    end
    
    local success, errorMsg = pcall(updateFunc)
    if not success then
        self:DebugPrint("Error updating " .. (elementName or "element") .. ": " .. tostring(errorMsg))
        return false
    end
    
    return true
end

-- UI State update function with comprehensive error handling
function DRE:UpdateGameUIState(state)
    if not state then
        self:DebugPrint("UpdateGameUIState called with nil state")
        return
    end
    
    self:DebugPrint("UpdateGameUIState called with state: " .. state)
    
    -- Validate UI table exists
    if not self.UI then
        self:DebugPrint("No UI table found - UI may not be initialized")
        return
    end
    
    -- Update UI state
    self.UI.gameState = state
    if self.RefreshDuel then self:RefreshDuel(); return end
    if self.UI.cancelGameButton then
        self.UI.cancelGameButton:SetDisabled(not ((self.gameState and self.gameState.isActive) or self:IsGroupRoundActive()))
    end
    
    if self:IsGroupRoundActive() and self.UI.gameButton then
        self.UI.gameButton:SetText("Group round in progress")
        self.UI.gameButton:SetDisabled(true)
        return
    end
    -- Validate gameButton exists
    if not self.UI.gameButton then
        self:DebugPrint("No gameButton found in UI - UI may not be fully initialized")
        return
    end
        
        if state == "WAITING" then
            -- Get current target name
            local targetName = DRE:GetUnitPlayerName("target")
            local buttonText = targetName and ("Challenge " .. targetName .. " to DeathRoll!") or "Challenge Player to DeathRoll!"
            
            self:SafeUIUpdate(self.UI.gameButton, function()
                self.UI.gameButton:SetText(buttonText)
                self.UI.gameButton:SetDisabled(false)
            end, "gameButton")
            
            self:UpdateRollHistoryStatus("Ready to start! Target someone and click Challenge!", true)
            
            
        elseif state == "ROLLING" then
            local rollRange = self.gameState and self.gameState.currentRoll or 100
            self.UI.gameButton:SetText("Roll 1-" .. rollRange)
            self.UI.gameButton:SetDisabled(false)
            -- Don't update history status for rolling - let the roll history show
            -- Update the roll input to show the current range
            if self.UI.rollEdit then
                self:DebugPrint("Updating roll input to: " .. rollRange)
                self.UI.rollEdit:SetText(tostring(rollRange))
            else
                self:DebugPrint("No rollEdit found in UI")
            end
            
        elseif state == "WAITING_FOR_OPPONENT" then
            local target = (self.gameState and self.gameState.target) or self.UI.currentTarget or "opponent"
            self.UI.gameButton:SetText("Waiting for " .. target .. "...")
            self.UI.gameButton:SetDisabled(true)
            -- Don't update history status - let the roll history show the opponent's upcoming turn
            
        elseif state == "WAITING_FOR_ROLL_RESULT" then
            self.UI.gameButton:SetText("Rolling...")
            self.UI.gameButton:SetDisabled(true)
            -- Don't update history status - the roll result will appear in history soon
            
        elseif state == "GAME_OVER" then
            self.UI.gameButton:SetText("Challenge Player to DeathRoll!")
            self.UI.gameButton:SetDisabled(false)
            -- Don't update roll history - let the win/loss message persist
            -- Don't auto-reset to WAITING - let the user manually start a new game
        end
end

-- Make the addon globally accessible
_G.DeathRollEnhancer = DRE
