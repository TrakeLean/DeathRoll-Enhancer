-- GoldTracking.lua
-- Automatic gold tracking through trade windows and money changes

local addonName, DeathRollEnhancer = ...
local DRE = DeathRollEnhancer

-- Create GoldTracking module
DRE.GoldTracking = {}
local GoldTracking = DRE.GoldTracking

-- Tracking state
GoldTracking.isTracking = false
GoldTracking.gameStartGold = 0
GoldTracking.targetPlayer = nil
GoldTracking.trackingStartTime = 0
GoldTracking.detectedGoldAmount = 0
GoldTracking.goldChangeSource = "unknown"
GoldTracking.timeoutTimer = nil

-- Constants
local TRACKING_TIMEOUT = 300 -- Track for 5 minutes (300 seconds) after game ends
local GOLD_CHANGE_THRESHOLD = 1 -- Minimum gold change to consider (in copper)

function GoldTracking:Initialize()
    -- Module initialized, tracking starts when games begin
end

-- Start tracking gold for a DeathRoll game
function GoldTracking:StartTracking(targetPlayer)
    if not targetPlayer or targetPlayer == "" then 
        print("|cFFFF0000DeathRoll: |rError - No target player specified for gold tracking")
        return false
    end
    
    -- Safely get money with error handling
    local currentMoney = GetMoney()
    if not currentMoney or currentMoney < 0 then
        print("|cFFFF0000DeathRoll: |rError - Could not retrieve current gold amount")
        return false
    end
    
    self.isTracking = true
    self.gameStartGold = currentMoney
    self.targetPlayer = targetPlayer
    self.trackingStartTime = GetTime()
    self.detectedGoldAmount = 0
    self.goldChangeSource = "unknown"
    
    -- Start timeout timer with proper cleanup
    self:StartTimeoutTimer()
    
    print("|cFF00FF00DeathRoll: |rStarting gold tracking with " .. targetPlayer .. " (Starting gold: " .. self:FormatGold(self.gameStartGold) .. ")")
    return true
end

-- Stop tracking and return detected amount
function GoldTracking:StopTracking()
    if not self.isTracking then return 0, "none" end
    
    -- Cancel timeout timer to prevent memory leaks
    self:CancelTimeoutTimer()
    
    local finalGold = GetMoney()
    local goldChange = finalGold - self.gameStartGold
    
    self.isTracking = false
    
    if math.abs(goldChange) >= GOLD_CHANGE_THRESHOLD then
        self.detectedGoldAmount = math.abs(goldChange)
        print("|cFF00FF00DeathRoll: |rGold change detected: " .. self:FormatGold(self.detectedGoldAmount) .. " (" .. self.goldChangeSource .. ")")
        return self.detectedGoldAmount, self.goldChangeSource
    end
    
    print("|cFFFFFF00DeathRoll: |rNo significant gold change detected")
    return 0, "none"
end

-- Handle trade window events
function GoldTracking:OnTradeShow()
    if not self.isTracking then return end
    
    print("|cFF00FF00DeathRoll: |rTrade window opened - monitoring gold exchange")
end

function GoldTracking:OnTradeMoneyChanged()
    if not self.isTracking then return end
    
    -- Safely get trade money amounts with error handling
    local success, playerMoney, targetMoney = pcall(function()
        return GetTradePlayerMoney() or 0, GetTradeTargetMoney() or 0
    end)
    
    if not success then
        print("|cFFFF0000DeathRoll: |rError reading trade window money amounts")
        return
    end
    
    if playerMoney and playerMoney > 0 then
        self.detectedGoldAmount = playerMoney
        self.goldChangeSource = "trade_giving"
        print("|cFF00FF00DeathRoll: |rYou're giving " .. self:FormatGold(playerMoney) .. " in trade")
    elseif targetMoney and targetMoney > 0 then
        self.detectedGoldAmount = targetMoney
        self.goldChangeSource = "trade_receiving"
        print("|cFF00FF00DeathRoll: |rYou're receiving " .. self:FormatGold(targetMoney) .. " in trade")
    end
end

function GoldTracking:OnTradeAccepted()
    if not self.isTracking then return end
    
    print("|cFF00FF00DeathRoll: |rTrade accepted - gold tracking complete")
end

function GoldTracking:OnTradeClosed()
    if not self.isTracking then return end
    
    print("|cFF00FF00DeathRoll: |rTrade window closed")
    
    -- Check if trade was completed and stop tracking
    C_Timer.After(1, function()
        if self.isTracking then
            local goldAmount, source = self:StopTracking()
            if goldAmount > 0 and DRE.UI then
                -- Auto-fill the detected amount
                DRE.UI:AutoFillGoldAmount(goldAmount)
            end
        end
    end)
end

-- Handle money change events
function GoldTracking:OnPlayerMoney()
    if not self.isTracking then return end
    
    -- Safely get current money with error handling
    local success, currentGold = pcall(GetMoney)
    if not success or not currentGold then
        print("|cFFFF0000DeathRoll: |rError reading current gold amount")
        return
    end
    
    -- Validate starting gold amount
    if not self.gameStartGold or self.gameStartGold < 0 then
        print("|cFFFF0000DeathRoll: |rError - Invalid starting gold amount, stopping tracking")
        self:Reset()
        return
    end
    
    local goldChange = currentGold - self.gameStartGold
    
    if math.abs(goldChange) >= GOLD_CHANGE_THRESHOLD then
        self.detectedGoldAmount = math.abs(goldChange)
        
        if goldChange > 0 then
            self.goldChangeSource = "money_gained"
            print("|cFF00FF00DeathRoll: |rGold gained: " .. self:FormatGold(goldChange))
        else
            self.goldChangeSource = "money_lost"
            print("|cFF00FF00DeathRoll: |rGold lost: " .. self:FormatGold(math.abs(goldChange)))
        end
    end
end

-- Timer management functions
function GoldTracking:StartTimeoutTimer()
    self:CancelTimeoutTimer() -- Cancel any existing timer
    
    self.timeoutTimer = C_Timer.NewTimer(TRACKING_TIMEOUT, function()
        if self.isTracking then
            print("|cFFFFFF00DeathRoll: |rGold tracking timed out after " .. (TRACKING_TIMEOUT / 60) .. " minutes")
            self:StopTracking()
        end
    end)
end

function GoldTracking:CancelTimeoutTimer()
    if self.timeoutTimer then
        self.timeoutTimer:Cancel()
        self.timeoutTimer = nil
    end
end

-- Check if tracking has timed out (legacy function, now handled by timer)
function GoldTracking:CheckTimeout()
    -- This function is kept for compatibility but timer handles timeout now
    if not self.isTracking then return end
    
    if GetTime() - self.trackingStartTime > TRACKING_TIMEOUT then
        print("|cFFFFFF00DeathRoll: |rGold tracking timed out after " .. (TRACKING_TIMEOUT / 60) .. " minutes")
        self:StopTracking()
    end
end

-- Format copper amount to gold/silver/copper display
function GoldTracking:FormatGold(copperAmount)
    if not copperAmount or copperAmount == 0 then return "0c" end
    
    local gold = math.floor(copperAmount / 10000)
    local silver = math.floor((copperAmount % 10000) / 100)
    local copper = copperAmount % 100
    
    local result = ""
    if gold > 0 then
        result = result .. gold .. "g"
    end
    if silver > 0 then
        result = result .. (result ~= "" and " " or "") .. silver .. "s"
    end
    if copper > 0 or result == "" then
        result = result .. (result ~= "" and " " or "") .. copper .. "c"
    end
    
    return result
end

-- Convert gold/silver/copper string to copper amount
function GoldTracking:ParseGoldString(goldStr)
    if not goldStr then return 0 end
    
    local totalCopper = 0
    
    -- Parse gold
    local gold = goldStr:match("(%d+)g")
    if gold then
        totalCopper = totalCopper + (tonumber(gold) * 10000)
    end
    
    -- Parse silver
    local silver = goldStr:match("(%d+)s")
    if silver then
        totalCopper = totalCopper + (tonumber(silver) * 100)
    end
    
    -- Parse copper
    local copper = goldStr:match("(%d+)c")
    if copper then
        totalCopper = totalCopper + tonumber(copper)
    end
    
    return totalCopper
end

-- Get current tracking status
function GoldTracking:GetTrackingStatus()
    return {
        isTracking = self.isTracking,
        targetPlayer = self.targetPlayer,
        detectedAmount = self.detectedGoldAmount,
        source = self.goldChangeSource,
        timeRemaining = self.isTracking and (TRACKING_TIMEOUT - (GetTime() - self.trackingStartTime)) or 0
    }
end

-- Manual override for detected gold amount
function GoldTracking:SetDetectedAmount(amount, source)
    self.detectedGoldAmount = amount or 0
    self.goldChangeSource = source or "manual"
end

-- Reset tracking state
function GoldTracking:Reset()
    -- Cancel any active timers to prevent memory leaks
    self:CancelTimeoutTimer()
    
    self.isTracking = false
    self.gameStartGold = 0
    self.targetPlayer = nil
    self.trackingStartTime = 0
    self.detectedGoldAmount = 0
    self.goldChangeSource = "unknown"
end

-- Cleanup function called when addon is disabled/unloaded
function GoldTracking:Cleanup()
    self:CancelTimeoutTimer()
    self:Reset()
    print("|cFFFFFF00DeathRoll: |rGold tracking module cleaned up")
end