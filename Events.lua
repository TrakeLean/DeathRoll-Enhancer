-- Events.lua
-- Chat message patterns and validation helpers
-- Event handling is centralized in Core.lua

local addonName, addonTable = ...
local DRE = _G.DeathRollEnhancer
if not DRE then return end

-- Chat message patterns for parsing various DeathRoll-related messages
DRE.CHAT_PATTERNS = {
    ROLL_PATTERN = "^(.+) rolls (%d+) %(1%-(%d+)%)$",
    DEATHROLL_CHALLENGE = "[Cc]hallenge.* you to a [Dd]eathRoll",
    DEATHROLL_CHALLENGE_ALT = "I challenge you to a DeathRoll",
    DEATHROLL_CHALLENGE_NEW = "^DEATHROLL_CHALLENGE:(%d+):(%d+):(.+)$",
    DEATHROLL_ACCEPT = "accepts? your [Dd]eathRoll challenge",
    DEATHROLL_DECLINE = "DEATHROLL_DECLINE",
    GOLD_WAGER = "(%d+)g",
    SILVER_WAGER = "(%d+)s",
    COPPER_WAGER = "(%d+)c"
}

-- Helper function to extract gold amount from message text
function DRE:ExtractGoldFromMessage(message)
    if not message then return 0 end
    
    local totalCopper = 0
    
    -- Extract gold
    local gold = message:match(self.CHAT_PATTERNS.GOLD_WAGER)
    if gold then
        totalCopper = totalCopper + (tonumber(gold) * 10000)
    end
    
    -- Extract silver
    local silver = message:match(self.CHAT_PATTERNS.SILVER_WAGER)
    if silver then
        totalCopper = totalCopper + (tonumber(silver) * 100)
    end
    
    -- Extract copper
    local copper = message:match(self.CHAT_PATTERNS.COPPER_WAGER)
    if copper then
        totalCopper = totalCopper + tonumber(copper)
    end
    
    return totalCopper
end

-- Helper function to validate player names
function DRE:IsValidPlayerName(name)
    if not name or type(name) ~= "string" then
        return false
    end
    
    -- Basic validation: length and character set
    if string.len(name) > 12 or string.len(name) < 2 then
        return false
    end
    
    -- Check for valid characters (letters, spaces, apostrophes, hyphens)
    if not name:match("^[%a%s'-]+$") then
        return false
    end
    
    return true
end

-- Helper function to parse roll result messages
function DRE:ParseRollMessage(message)
    if not message then return nil end
    
    local playerName, roll, maxRoll = message:match(self.CHAT_PATTERNS.ROLL_PATTERN)
    if playerName and roll and maxRoll then
        return {
            playerName = playerName,
            roll = tonumber(roll),
            maxRoll = tonumber(maxRoll)
        }
    end
    
    return nil
end

-- Helper function to detect challenge messages
function DRE:IsDeathRollChallenge(message)
    if not message then return false end
    
    local lowerMessage = message:lower()
    return lowerMessage:find(self.CHAT_PATTERNS.DEATHROLL_CHALLENGE) or 
           lowerMessage:find(self.CHAT_PATTERNS.DEATHROLL_CHALLENGE_ALT)
end

-- Validation helper for wager amounts
function DRE:ValidateWager(gold, silver, copper)
    gold = gold or 0
    silver = silver or 0
    copper = copper or 0
    
    -- Check for negative values
    if gold < 0 or silver < 0 or copper < 0 then
        return false, "Wager amounts cannot be negative!"
    end
    
    -- Check for reasonable limits (prevent overflow)
    if gold > 999999 then
        return false, "Gold amount too large (max 999,999)!"
    end
    
    if silver > 99 then
        return false, "Silver amount should be 0-99!"
    end
    
    if copper > 99 then
        return false, "Copper amount should be 0-99!"
    end
    
    return true, nil
end