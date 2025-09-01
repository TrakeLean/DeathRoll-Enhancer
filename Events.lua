-- Events.lua
-- Event handling using AceEvent

local addonName, addonTable = ...
local DRE = _G.DeathRollEnhancer
if not DRE then return end

-- Event handling is now integrated into the main addon via AceEvent
-- This file provides additional event-specific functions

-- Game state tracking
local gameState = {
    isActive = false,
    currentTarget = nil,
    initialRoll = nil,
    playerRoll = nil,
    opponentRoll = nil,
    goldAmount = nil,
    waitingForRoll = false
}

-- Chat message patterns
local PATTERNS = {
    ROLL_PATTERN = "^(.+) rolls (%d+) %(1%-(%d+)%)$",
    DEATHROLL_CHALLENGE = "challenges? you to a [Dd]eathRoll",
    DEATHROLL_ACCEPT = "accepts? your [Dd]eathRoll challenge",
    GOLD_WAGER = "(%d+)g",
    SILVER_WAGER = "(%d+)s",
    COPPER_WAGER = "(%d+)c"
}

-- Enhanced chat message handler
function DRE:CHAT_MSG_SYSTEM(event, message, sender)
    if not message then return end
    
    -- Handle roll messages
    local playerName, roll, maxRoll = message:match(PATTERNS.ROLL_PATTERN)
    if playerName and roll and maxRoll then
        self:HandleRollMessage(playerName, tonumber(roll), tonumber(maxRoll))
        return
    end
    
    -- Handle other system messages
    self:HandleSystemMessage(message)
end

-- Handle chat messages for challenges and wagers
function DRE:CHAT_MSG_SAY(event, message, sender)
    if not message or not sender then return end
    
    self:HandleChatMessage(message, sender, "SAY")
end

function DRE:CHAT_MSG_YELL(event, message, sender)
    if not message or not sender then return end
    
    self:HandleChatMessage(message, sender, "YELL")
end

function DRE:CHAT_MSG_PARTY(event, message, sender)
    if not message or not sender then return end
    
    self:HandleChatMessage(message, sender, "PARTY")
end

function DRE:CHAT_MSG_GUILD(event, message, sender)
    if not message or not sender then return end
    
    self:HandleChatMessage(message, sender, "GUILD")
end

-- Handle roll messages
function DRE:HandleRollMessage(playerName, roll, maxRoll)
    if not gameState.isActive then return end
    
    local playerFullName = UnitName("player")
    
    -- Check if this is a DeathRoll-related roll
    if gameState.currentTarget and 
       (playerName == playerFullName or playerName == gameState.currentTarget) then
        
        if playerName == playerFullName then
            gameState.playerRoll = roll
            self:Print(string.format("You rolled %d (1-%d)", roll, maxRoll))
        else
            gameState.opponentRoll = roll
            self:Print(string.format("%s rolled %d (1-%d)", playerName, roll, maxRoll))
        end
        
        -- Check for game end conditions
        if roll == 1 then
            self:HandleGameEnd(playerName, roll)
        else
            -- Continue game with new max roll
            self:ContinueGame(roll)
        end
    end
end

-- Handle chat messages for challenges and wagers
function DRE:HandleChatMessage(message, sender, channel)
    if not message or not sender then return end
    
    local lowerMessage = message:lower()
    
    -- Check for DeathRoll challenge
    if lowerMessage:find(PATTERNS.DEATHROLL_CHALLENGE) then
        self:HandleDeathRollChallenge(sender, message, channel)
    end
    
    -- Check for challenge acceptance
    if lowerMessage:find(PATTERNS.DEATHROLL_ACCEPT) then
        self:HandleChallengeAcceptance(sender, message, channel)
    end
    
    -- Extract gold wager information
    local goldAmount = self:ExtractGoldAmount(message)
    if goldAmount > 0 then
        gameState.goldAmount = goldAmount
        if self.db and self.db.profile.gameplay.trackGold then
            self:Print(string.format("Gold wager detected: %s", self:FormatGold(goldAmount)))
        end
    end
end

-- Handle system messages
function DRE:HandleSystemMessage(message)
    -- Handle any relevant system messages
    if message:find("duel") or message:find("challenge") then
        -- Could be related to our DeathRoll
    end
end

-- Handle DeathRoll challenge
function DRE:HandleDeathRollChallenge(sender, message, channel)
    if sender == UnitName("player") then return end
    
    -- Extract initial roll value from challenge
    local initialRoll = message:match("starting at (%d+)") or message:match("roll (%d+)")
    if initialRoll then
        initialRoll = tonumber(initialRoll)
    end
    
    self:Print(string.format("%s has challenged you to a DeathRoll!", sender))
    
    if initialRoll then
        self:Print(string.format("Starting roll: %d", initialRoll))
        
        -- Auto-accept if we have UI open and target matches
        if DRE.UI and DRE.UI.mainWindow and DRE.UI.currentTarget == sender then
            self:StartGame(sender, initialRoll)
        end
    end
end

-- Handle challenge acceptance
function DRE:HandleChallengeAcceptance(sender, message, channel)
    if sender == UnitName("player") then return end
    
    if gameState.currentTarget == sender then
        self:Print(string.format("%s accepted your DeathRoll challenge!", sender))
        gameState.waitingForRoll = true
    end
end

-- Start a new DeathRoll game
function DRE:StartGame(target, initialRoll)
    gameState.isActive = true
    gameState.currentTarget = target
    gameState.initialRoll = initialRoll or 100
    gameState.playerRoll = nil
    gameState.opponentRoll = nil
    gameState.goldAmount = 0
    gameState.waitingForRoll = false
    
    self:Print(string.format("DeathRoll game started with %s (starting at %d)", target, gameState.initialRoll))
    
    if DRE.UI and DRE.UI.statusLabel then
        DRE.UI.statusLabel:SetText(string.format("Game active with %s", target))
    end
end

-- Continue the game with a new max roll
function DRE:ContinueGame(newMaxRoll)
    if newMaxRoll <= 1 then
        return
    end
    
    -- Update UI status
    if DRE.UI and DRE.UI.statusLabel then
        DRE.UI.statusLabel:SetText(string.format("Continue rolling (1-%d)", newMaxRoll))
    end
    
    -- Clear previous rolls
    gameState.playerRoll = nil
    gameState.opponentRoll = nil
end

-- Handle game end
function DRE:HandleGameEnd(loser, finalRoll)
    local winner = (loser == UnitName("player")) and gameState.currentTarget or UnitName("player")
    local playerWon = (winner == UnitName("player"))
    
    self:Print(string.format("Game Over! %s rolled %d and loses!", loser, finalRoll))
    self:Print(string.format("Winner: %s", winner))
    
    -- Play emotes if enabled
    if self.db and self.db.profile.gameplay.autoEmote then
        if playerWon then
            local emote = self:GetRandomHappyEmote()
            DoEmote(emote)
        else
            local emote = self:GetRandomSadEmote()
            DoEmote(emote)
        end
    end
    
    -- Record the game
    if gameState.currentTarget then
        local result = playerWon and "WIN" or "LOSS"
        self:AddGameToHistory(gameState.currentTarget, result, gameState.goldAmount, gameState.initialRoll)
    end
    
    -- Update UI
    if DRE.UI and DRE.UI.statusLabel then
        local statusText = playerWon and 
            string.format("You won against %s!", gameState.currentTarget) or
            string.format("You lost to %s", gameState.currentTarget)
        DRE.UI.statusLabel:SetText(statusText)
    end
    
    -- Reset game state
    self:ResetGameState()
end

-- Reset game state
function DRE:ResetGameState()
    gameState.isActive = false
    gameState.currentTarget = nil
    gameState.initialRoll = nil
    gameState.playerRoll = nil
    gameState.opponentRoll = nil
    gameState.goldAmount = nil
    gameState.waitingForRoll = false
end

-- Extract gold amount from message
function DRE:ExtractGoldAmount(message)
    if not message then return 0 end
    
    local totalCopper = 0
    
    -- Extract gold
    local gold = message:match("(%d+)g")
    if gold then
        totalCopper = totalCopper + (tonumber(gold) * 10000)
    end
    
    -- Extract silver
    local silver = message:match("(%d+)s")
    if silver then
        totalCopper = totalCopper + (tonumber(silver) * 100)
    end
    
    -- Extract copper
    local copper = message:match("(%d+)c")
    if copper then
        totalCopper = totalCopper + tonumber(copper)
    end
    
    return totalCopper
end

-- Get current game state (for UI updates)
function DRE:GetGameState()
    return {
        isActive = gameState.isActive,
        currentTarget = gameState.currentTarget,
        initialRoll = gameState.initialRoll,
        playerRoll = gameState.playerRoll,
        opponentRoll = gameState.opponentRoll,
        goldAmount = gameState.goldAmount,
        waitingForRoll = gameState.waitingForRoll
    }
end

-- Force end current game
function DRE:EndCurrentGame()
    if gameState.isActive then
        self:Print("DeathRoll game manually ended")
        self:ResetGameState()
        
        if DRE.UI and DRE.UI.statusLabel then
            DRE.UI.statusLabel:SetText("Ready to roll!")
        end
    end
end

-- Register additional events when needed
function DRE:RegisterGameEvents()
    self:RegisterEvent("CHAT_MSG_SAY")
    self:RegisterEvent("CHAT_MSG_YELL")
    self:RegisterEvent("CHAT_MSG_PARTY")
    self:RegisterEvent("CHAT_MSG_GUILD")
end

-- Unregister game events
function DRE:UnregisterGameEvents()
    self:UnregisterEvent("CHAT_MSG_SAY")
    self:UnregisterEvent("CHAT_MSG_YELL")
    self:UnregisterEvent("CHAT_MSG_PARTY")
    self:UnregisterEvent("CHAT_MSG_GUILD")
end