-- Database.lua
-- Database management using AceDB

local addonName, addonTable = ...
local DRE = _G.DeathRollEnhancer
if not DRE then return end

-- Database functions are now handled by AceDB in Core.lua
-- This file provides helper functions for data management

-- Helper function to get player history
function DRE:GetPlayerHistory(playerName)
    if not self.db or not self.db.profile.history then
        return nil
    end
    
    return self.db.profile.history[playerName]
end

-- Helper function to add game result to history
function DRE:AddGameToHistory(playerName, result, goldAmount, initialRoll)
    if not self.db or not playerName then
        return
    end
    
    -- Initialize player history if it doesn't exist
    if not self.db.profile.history[playerName] then
        self.db.profile.history[playerName] = {
            gamesPlayed = 0,
            wins = 0,
            losses = 0,
            goldWon = 0,
            goldLost = 0,
            recentGames = {}
        }
    end
    
    local playerData = self.db.profile.history[playerName]
    
    -- Update game counts
    playerData.gamesPlayed = (playerData.gamesPlayed or 0) + 1
    
    if result == "Won" or result == "WIN" then
        playerData.wins = (playerData.wins or 0) + 1
        playerData.goldWon = (playerData.goldWon or 0) + (goldAmount or 0)
    elseif result == "Lost" or result == "LOSS" then
        playerData.losses = (playerData.losses or 0) + 1
        playerData.goldLost = (playerData.goldLost or 0) + (goldAmount or 0)
    end
    
    -- Add to recent games
    if not playerData.recentGames then
        playerData.recentGames = {}
    end
    
    table.insert(playerData.recentGames, 1, {
        date = date("%Y-%m-%d %H:%M"),
        result = result,
        goldAmount = goldAmount or 0,
        initialRoll = initialRoll or 0
    })
    
    -- Keep only last 50 games
    if #playerData.recentGames > 50 then
        table.remove(playerData.recentGames, 51)
    end
    
    -- Update overall gold tracking
    self:UpdateGoldTracking(result, goldAmount)
end

-- Update gold tracking statistics
function DRE:UpdateGoldTracking(result, goldAmount)
    if not self.db or not self.db.profile.gameplay.trackGold then
        return
    end
    
    local tracking = self.db.profile.goldTracking
    goldAmount = goldAmount or 0
    
    if result == "Won" or result == "WIN" then
        tracking.totalWon = (tracking.totalWon or 0) + goldAmount
        
        if tracking.currentStreak >= 0 then
            tracking.currentStreak = (tracking.currentStreak or 0) + 1
        else
            tracking.currentStreak = 1
        end
        
        if tracking.currentStreak > (tracking.bestWinStreak or 0) then
            tracking.bestWinStreak = tracking.currentStreak
        end
        
    elseif result == "Lost" or result == "LOSS" then
        tracking.totalLost = (tracking.totalLost or 0) + goldAmount
        
        if tracking.currentStreak <= 0 then
            tracking.currentStreak = (tracking.currentStreak or 0) - 1
        else
            tracking.currentStreak = -1
        end
        
        if math.abs(tracking.currentStreak) > math.abs(tracking.worstLossStreak or 0) then
            tracking.worstLossStreak = tracking.currentStreak
        end
    end
    
    -- Update UI if it's open
    if DRE.UpdateStatsDisplay then
        DRE:UpdateStatsDisplay()
    end
end

-- Get overall statistics
function DRE:GetOverallStats()
    if not self.db then
        return {
            totalGames = 0,
            totalWins = 0,
            totalLosses = 0,
            totalGoldWon = 0,
            totalGoldLost = 0,
            currentStreak = 0,
            bestWinStreak = 0,
            worstLossStreak = 0
        }
    end
    
    local stats = {
        totalGoldWon = self.db.profile.goldTracking.totalWon or 0,
        totalGoldLost = self.db.profile.goldTracking.totalLost or 0,
        currentStreak = self.db.profile.goldTracking.currentStreak or 0,
        bestWinStreak = self.db.profile.goldTracking.bestWinStreak or 0,
        worstLossStreak = self.db.profile.goldTracking.worstLossStreak or 0,
        totalGames = 0,
        totalWins = 0,
        totalLosses = 0
    }
    
    -- Calculate totals from all player histories
    if self.db.profile.history then
        for playerName, playerData in pairs(self.db.profile.history) do
            stats.totalGames = stats.totalGames + (playerData.gamesPlayed or 0)
            stats.totalWins = stats.totalWins + (playerData.wins or 0)
            stats.totalLosses = stats.totalLosses + (playerData.losses or 0)
        end
    end
    
    return stats
end

-- Get top players (by games played)
function DRE:GetTopPlayers(limit)
    if not self.db or not self.db.profile.history then
        return {}
    end
    
    limit = limit or 10
    local players = {}
    
    for playerName, playerData in pairs(self.db.profile.history) do
        table.insert(players, {
            name = playerName,
            gamesPlayed = playerData.gamesPlayed or 0,
            wins = playerData.wins or 0,
            losses = playerData.losses or 0,
            goldWon = playerData.goldWon or 0,
            goldLost = playerData.goldLost or 0,
            winRate = playerData.gamesPlayed > 0 and (playerData.wins / playerData.gamesPlayed * 100) or 0
        })
    end
    
    -- Sort by games played
    table.sort(players, function(a, b)
        return a.gamesPlayed > b.gamesPlayed
    end)
    
    -- Limit results
    local result = {}
    for i = 1, math.min(limit, #players) do
        table.insert(result, players[i])
    end
    
    return result
end

-- Clean old data
function DRE:CleanOldData(daysToKeep)
    if not self.db or not self.db.profile.history then
        return
    end
    
    daysToKeep = daysToKeep or 30
    local cutoffTime = time() - (daysToKeep * 24 * 60 * 60)
    local cleanedCount = 0
    
    for playerName, playerData in pairs(self.db.profile.history) do
        if playerData.recentGames then
            local newGames = {}
            for _, game in ipairs(playerData.recentGames) do
                local gameTime = 0
                if game.date then
                    -- Parse date string (YYYY-MM-DD HH:MM)
                    local year, month, day, hour, min = game.date:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
                    if year then
                        gameTime = os.time({
                            year = tonumber(year),
                            month = tonumber(month),
                            day = tonumber(day),
                            hour = tonumber(hour),
                            min = tonumber(min)
                        })
                    end
                end
                
                if gameTime == 0 or gameTime >= cutoffTime then
                    table.insert(newGames, game)
                else
                    cleanedCount = cleanedCount + 1
                end
            end
            playerData.recentGames = newGames
        end
    end
    
    if cleanedCount > 0 then
        self:Print(string.format("Cleaned %d old game records", cleanedCount))
    end
end

-- Reset all data
function DRE:ResetAllData()
    if not self.db then
        return
    end
    
    -- Reset history
    self.db.profile.history = {}
    
    -- Reset gold tracking
    self.db.profile.goldTracking = {
        totalWon = 0,
        totalLost = 0,
        currentStreak = 0,
        bestWinStreak = 0,
        worstLossStreak = 0,
    }
    
    self:Print("All DeathRoll data has been reset")
    
    -- Update UI if it's open
    if DRE.UpdateStatsDisplay then
        DRE:UpdateStatsDisplay()
    end
end

-- Export data for backup
function DRE:ExportData()
    if not self.db then
        return "No data available"
    end
    
    local exportData = {
        version = self.version,
        exportDate = date("%Y-%m-%d %H:%M:%S"),
        history = self.db.profile.history,
        goldTracking = self.db.profile.goldTracking,
        settings = {
            gameplay = self.db.profile.gameplay,
            ui = self.db.profile.ui,
            minimap = self.db.profile.minimap
        }
    }
    
    -- Simple serialization (basic table to string)
    local function serialize(tbl, indent)
        indent = indent or 0
        local result = "{\n"
        local indentStr = string.rep("  ", indent + 1)
        
        for k, v in pairs(tbl) do
            result = result .. indentStr
            if type(k) == "string" then
                result = result .. '["' .. k .. '"] = '
            else
                result = result .. "[" .. tostring(k) .. "] = "
            end
            
            if type(v) == "table" then
                result = result .. serialize(v, indent + 1) .. ",\n"
            elseif type(v) == "string" then
                result = result .. '"' .. v .. '",\n'
            else
                result = result .. tostring(v) .. ",\n"
            end
        end
        
        result = result .. string.rep("  ", indent) .. "}"
        return result
    end
    
    return serialize(exportData)
end