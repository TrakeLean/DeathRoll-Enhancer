-- Events.lua
-- Event handling and chat message parsing

local addonName, DeathRollEnhancer = ...
local DRE = DeathRollEnhancer

-- Create Events module
DRE.Events = {}
local Events = DRE.Events

-- Event frame
Events.eventFrame = nil

function Events:Initialize()
    self:CreateEventFrame()
    self:RegisterEvents()
end

function Events:CreateEventFrame()
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
        self:HandleEvent(event, ...)
    end)
end

function Events:RegisterEvents()
    if not self.eventFrame then return end
    
    self.eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    
    -- Gold tracking events
    self.eventFrame:RegisterEvent("TRADE_SHOW")
    self.eventFrame:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
    self.eventFrame:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
    self.eventFrame:RegisterEvent("TRADE_MONEY_CHANGED")
    self.eventFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")
    self.eventFrame:RegisterEvent("TRADE_CLOSED")
    self.eventFrame:RegisterEvent("PLAYER_MONEY")
end

function Events:UnregisterEvents()
    if not self.eventFrame then return end
    
    self.eventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
    self.eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    
    -- Gold tracking events
    self.eventFrame:UnregisterEvent("TRADE_SHOW")
    self.eventFrame:UnregisterEvent("TRADE_PLAYER_ITEM_CHANGED")
    self.eventFrame:UnregisterEvent("TRADE_TARGET_ITEM_CHANGED")
    self.eventFrame:UnregisterEvent("TRADE_MONEY_CHANGED")
    self.eventFrame:UnregisterEvent("TRADE_ACCEPT_UPDATE")
    self.eventFrame:UnregisterEvent("TRADE_CLOSED")
    self.eventFrame:UnregisterEvent("PLAYER_MONEY")
end

function Events:HandleEvent(event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        self:OnChatMsgSystem(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:OnPlayerRegenDisabled(...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:OnPlayerRegenEnabled(...)
    -- Gold tracking events
    elseif event == "TRADE_SHOW" then
        self:OnTradeShow(...)
    elseif event == "TRADE_MONEY_CHANGED" then
        self:OnTradeMoneyChanged(...)
    elseif event == "TRADE_ACCEPT_UPDATE" then
        self:OnTradeAcceptUpdate(...)
    elseif event == "TRADE_CLOSED" then
        self:OnTradeClosed(...)
    elseif event == "PLAYER_MONEY" then
        self:OnPlayerMoney(...)
    end
end

-- Handle chat messages for roll detection
function Events:OnChatMsgSystem(msg)
    if not DRE.UI then return end
    
    -- Parse roll message: "PlayerName rolls X (Y-Z)"
    local playerName, rollResult, minRoll, maxRoll = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)")
    
    if not (playerName and rollResult and minRoll and maxRoll) then
        return
    end
    
    local targetName = DRE.UI:GetTargetName()
    if not targetName then return end
    
    -- Check if this roll is from the target player or the player themselves
    local currentPlayer = UnitName("player")
    local isValidRoll = (playerName == targetName) or (playerName == currentPlayer)
    
    if isValidRoll then
        -- Create the target roll string for display
        local targetRollString = minRoll .. "-" .. maxRoll
        DRE.UI:OnPlayerRoll(playerName, rollResult, targetRollString)
    else
        -- Ignore rolls from other players
        print(playerName .. " rolled, but they are not your duel target (" .. targetName .. "). Ignoring roll.")
    end
end

-- Handle entering combat
function Events:OnPlayerRegenDisabled()
    if DRE.UI then
        DRE.UI:OnCombatStart()
    end
end

-- Handle leaving combat
function Events:OnPlayerRegenEnabled()
    if DRE.UI then
        DRE.UI:OnCombatEnd()
    end
end

-- Utility function to validate roll messages
function Events:ValidateRollMessage(msg)
    -- Basic validation for roll message format
    local pattern = "^.+ rolls %d+ %(%d+%-%d+%)$"
    return string.match(msg, pattern) ~= nil
end

-- Parse roll data from message
function Events:ParseRollMessage(msg)
    local playerName, rollResult, minRoll, maxRoll = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)")
    
    if not (playerName and rollResult and minRoll and maxRoll) then
        return nil
    end
    
    return {
        playerName = playerName,
        rollResult = tonumber(rollResult),
        minRoll = tonumber(minRoll),
        maxRoll = tonumber(maxRoll)
    }
end

-- Check if a roll is from a valid participant
function Events:IsValidParticipant(playerName, targetName)
    if not playerName or not targetName then
        return false
    end
    
    local currentPlayer = UnitName("player")
    return (playerName == targetName) or (playerName == currentPlayer)
end

-- Get current target name
function Events:GetCurrentTarget()
    return UnitName("target")
end

-- Check if the addon is currently tracking a game
function Events:IsGameActive()
    return DRE.UI and DRE.UI:GetTargetName() ~= nil
end

-- Gold tracking event handlers
function Events:OnTradeShow()
    if DRE.GoldTracking then
        DRE.GoldTracking:OnTradeShow()
    end
end

function Events:OnTradeMoneyChanged()
    if DRE.GoldTracking then
        DRE.GoldTracking:OnTradeMoneyChanged()
    end
end

function Events:OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    if DRE.GoldTracking and playerAccepted and targetAccepted then
        DRE.GoldTracking:OnTradeAccepted()
    end
end

function Events:OnTradeClosed()
    if DRE.GoldTracking then
        DRE.GoldTracking:OnTradeClosed()
    end
end

function Events:OnPlayerMoney()
    if DRE.GoldTracking then
        DRE.GoldTracking:OnPlayerMoney()
    end
end