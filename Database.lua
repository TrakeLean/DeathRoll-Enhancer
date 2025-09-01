-- Database.lua
-- Win/loss tracking and data persistence

local addonName, DeathRollEnhancer = ...
local DRE = DeathRollEnhancer

-- Create Database module
DRE.Database = {}
local Database = DRE.Database

-- Initialize the database
function Database:Initialize()
    -- Initialize SavedVariables with error handling
    if not DeathRollHistoryDB then
        DeathRollHistoryDB = {}
        print("|cFFFFFF00DeathRoll: |rInitialized new history database")
    elseif type(DeathRollHistoryDB) ~= "table" then
        print("|cFFFF0000DeathRoll: |rCorrupted history database detected, creating new one")
        DeathRollHistoryDB = {}
    end
    
    if not DeathRollSettings then
        DeathRollSettings = {}
        print("|cFFFFFF00DeathRoll: |rInitialized new settings")
    elseif type(DeathRollSettings) ~= "table" then
        print("|cFFFF0000DeathRoll: |rCorrupted settings detected, creating new ones")
        DeathRollSettings = {}
    end
    
    self.historyDB = DeathRollHistoryDB
    self.settings = DeathRollSettings
    
    -- Validate existing data
    self:ValidateDatabase()
end

-- Validate and repair database integrity
function Database:ValidateDatabase()
    local repaired = 0
    
    for playerName, record in pairs(self.historyDB) do
        if type(record) ~= "table" then
            print("|cFFFF0000DeathRoll: |rRemoving corrupted record for " .. tostring(playerName))
            self.historyDB[playerName] = nil
            repaired = repaired + 1
        else
            -- Ensure all required fields exist with valid values
            record.wins = tonumber(record.wins) or 0
            record.losses = tonumber(record.losses) or 0
            record.currentStreak = tonumber(record.currentStreak) or 0
            record.longestWinStreak = tonumber(record.longestWinStreak) or 0
            record.longestLossStreak = tonumber(record.longestLossStreak) or 0
            record.goldWon = tonumber(record.goldWon) or 0
            record.goldLoss = tonumber(record.goldLoss) or 0
            
            -- Fix negative values that shouldn't be negative
            if record.wins < 0 then record.wins = 0 end
            if record.losses < 0 then record.losses = 0 end
            if record.longestWinStreak < 0 then record.longestWinStreak = 0 end
            if record.longestLossStreak < 0 then record.longestLossStreak = 0 end
            if record.goldWon < 0 then record.goldWon = 0 end
            if record.goldLoss < 0 then record.goldLoss = 0 end
        end
    end
    
    if repaired > 0 then
        print("|cFFFFFF00DeathRoll: |rRepaired " .. repaired .. " corrupted database entries")
    end
end

-- Update win/loss history in the database, including gold won/loss
function Database:UpdateDeathRollHistory(targetName, won, gold)
    if not targetName then return end
    
    -- Initialize player record if it doesn't exist
    if not self.historyDB[targetName] then
        self.historyDB[targetName] = {
            wins = 0,
            losses = 0,
            currentStreak = 0,
            longestWinStreak = 0,
            longestLossStreak = 0,
            goldWon = 0,
            goldLoss = 0
        }
    else
        -- Ensure all fields exist for existing records
        local record = self.historyDB[targetName]
        record.wins = record.wins or 0
        record.losses = record.losses or 0
        record.currentStreak = record.currentStreak or 0
        record.longestWinStreak = record.longestWinStreak or 0
        record.longestLossStreak = record.longestLossStreak or 0
        record.goldWon = record.goldWon or 0
        record.goldLoss = record.goldLoss or 0
    end

    local record = self.historyDB[targetName]
    local goldAmount = gold or 0

    -- Update win/loss count and current streak
    if won then
        record.wins = record.wins + 1
        record.currentStreak = (record.currentStreak >= 0) and (record.currentStreak + 1) or 1
        record.goldWon = record.goldWon + goldAmount
    else
        record.losses = record.losses + 1
        record.currentStreak = (record.currentStreak <= 0) and (record.currentStreak - 1) or -1
        record.goldLoss = record.goldLoss + goldAmount
    end

    -- Update longest streaks
    if record.currentStreak > record.longestWinStreak then
        record.longestWinStreak = record.currentStreak
    end

    if record.currentStreak < 0 and math.abs(record.currentStreak) > record.longestLossStreak then
        record.longestLossStreak = math.abs(record.currentStreak)
    end

    -- Generate streak message
    local streakMessage
    if record.currentStreak > 0 then
        streakMessage = "Current win streak: " .. record.currentStreak
    elseif record.currentStreak < 0 then
        streakMessage = "Current loss streak: " .. math.abs(record.currentStreak)
    else
        streakMessage = "No current streak"
    end

    -- Print updated stats
    print("DeathRoll history updated for " .. targetName .. ": " ..
          record.wins .. " wins, " ..
          record.losses .. " losses, " ..
          "Gold won: " .. record.goldWon .. ", " ..
          "Gold lost: " .. record.goldLoss .. ". " ..
          streakMessage .. ".")
end

-- Show deathroll history for a specific target
function Database:ShowDeathRollHistory(target)
    if not target then
        print("No target specified.")
        return
    end
    
    if not self.historyDB[target] then
        print("No DeathRoll history found for " .. target .. ".")
        return
    end

    local record = self.historyDB[target]

    -- Color codes
    local winColor = "|cff00ff00"      -- Green for wins
    local lossColor = "|cffff0000"     -- Red for losses
    local neutralColor = "|cffffffff"  -- White for neutral info
    local positiveGoldColor = "|cffffff00" -- Yellow for positive gold
    local negativeGoldColor = "|cffff0000" -- Red for negative gold

    -- Ensure gold values exist
    local goldWon = record.goldWon or 0
    local goldLoss = record.goldLoss or 0

    -- Calculate net gold and determine color
    local netGold = goldWon - goldLoss
    local goldColor = netGold >= 0 and positiveGoldColor or negativeGoldColor
    local goldStatus = netGold >= 0 and "Profit" or "Loss"

    -- Calculate winrate
    local totalGames = (record.wins or 0) + (record.losses or 0)
    local winrate = totalGames > 0 and ((record.wins / totalGames) * 100) or 0

    -- Determine winrate color
    local winrateColor
    if winrate > 50 then
        winrateColor = winColor
    elseif winrate < 50 then
        winrateColor = lossColor
    else
        winrateColor = neutralColor
    end

    -- Display history
    print("DeathRoll history with " .. target .. ":")

    -- Display wins and losses
    local winsLossesMessage = string.format("wins: %s%d|r, losses: %s%d|r", 
        winColor, record.wins or 0, lossColor, record.losses or 0)
    print(winsLossesMessage)

    -- Display winrate
    local winrateMessage = totalGames > 0 and 
        string.format("Winrate: %s%.2f%%|r", winrateColor, winrate) or "Winrate: N/A"
    print(winrateMessage)

    -- Display current streak
    local streakMessage
    if record.currentStreak > 0 then
        streakMessage = "Current win streak: " .. winColor .. record.currentStreak .. "|r"
    elseif record.currentStreak < 0 then
        streakMessage = "Current loss streak: " .. lossColor .. math.abs(record.currentStreak) .. "|r"
    else
        streakMessage = neutralColor .. "No current streak|r"
    end
    print(streakMessage)

    -- Display gold statistics
    local goldMessage = string.format("Gold won: %s%d|r, Gold lost: %s%d|r. Net gold: %s%d|r (%s)",
        positiveGoldColor, goldWon,
        negativeGoldColor, goldLoss,
        goldColor, netGold, goldStatus)
    print(goldMessage)
end

-- Get player statistics
function Database:GetPlayerStats(targetName)
    if not targetName or not self.historyDB[targetName] then
        return nil
    end
    
    return self.historyDB[targetName]
end

-- Get all player statistics
function Database:GetAllStats()
    return self.historyDB
end

-- Clear history for a specific player
function Database:ClearPlayerHistory(targetName)
    if targetName and self.historyDB[targetName] then
        self.historyDB[targetName] = nil
        print("DeathRoll history cleared for " .. targetName)
    end
end

-- Clear all history
function Database:ClearAllHistory()
    wipe(self.historyDB)
    print("All DeathRoll history cleared")
end

-- Settings management
function Database:GetSetting(key)
    return self.settings[key]
end

function Database:SetSetting(key, value)
    self.settings[key] = value
end