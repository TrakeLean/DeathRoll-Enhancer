-- Database.lua
-- Database management using AceDB

local addonName, addonTable = ...
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
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
    
    -- Keep all games - complete history tracking
    
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

-- Find and return the most recent game record for editing
function DRE:GetLastGameRecord()
    if not self.db or not self.db.profile.history then
        return nil
    end
    
    local latestGame = nil
    local latestPlayer = nil
    local latestTime = 0
    
    -- Find the most recent game across all players
    for playerName, playerData in pairs(self.db.profile.history) do
        if playerData.recentGames and #playerData.recentGames > 0 then
            local game = playerData.recentGames[1] -- Most recent is first
            local gameTime = game.timestamp or 0
            
            if gameTime > latestTime then
                latestTime = gameTime
                latestGame = game
                latestPlayer = playerName
            end
        end
    end
    
    return latestGame, latestPlayer
end

-- Get all recent games for editing (last 50 games across all players)
function DRE:GetRecentGamesForEditing(limit)
    limit = limit or 50
    
    if not self.db or not self.db.profile.history then
        return {}
    end
    
    local allGames = {}
    
    -- Collect all games with player and game info
    for playerName, playerData in pairs(self.db.profile.history) do
        if playerData.recentGames and #playerData.recentGames > 0 then
            for gameIndex, game in ipairs(playerData.recentGames) do
                table.insert(allGames, {
                    playerName = playerName,
                    gameIndex = gameIndex,
                    game = game,
                    timestamp = game.timestamp or 0
                })
            end
        end
    end
    
    -- Sort by timestamp (newest first) - handle missing timestamps and date fields
    table.sort(allGames, function(a, b) 
        local aTime = a.timestamp or 0
        local bTime = b.timestamp or 0
        
        -- If timestamp is 0 or missing, try to parse the date field
        if aTime == 0 and a.game.date then
            local year, month, day, hour, min = a.game.date:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
            if year then
                -- Use simple date comparison string instead of os.time (which isn't available in WoW)
                -- Format: YYYYMMDDHHMM for easy numeric comparison
                aTime = tonumber(string.format("%04d%02d%02d%02d%02d", 
                    tonumber(year), tonumber(month), tonumber(day), 
                    tonumber(hour) or 0, tonumber(min) or 0))
            end
        end
        
        if bTime == 0 and b.game.date then
            local year, month, day, hour, min = b.game.date:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
            if year then
                -- Use simple date comparison string instead of os.time (which isn't available in WoW)
                -- Format: YYYYMMDDHHMM for easy numeric comparison
                bTime = tonumber(string.format("%04d%02d%02d%02d%02d", 
                    tonumber(year), tonumber(month), tonumber(day), 
                    tonumber(hour) or 0, tonumber(min) or 0))
            end
        end
        
        -- If still equal, maintain original order
        if aTime == bTime then
            return false
        end
        return aTime > bTime
    end)
    
    -- Limit results
    local result = {}
    for i = 1, math.min(limit, #allGames) do
        table.insert(result, allGames[i])
    end
    
    -- Debug info
    if DRE and DRE.DebugPrint then
        DRE:DebugPrint("GetRecentGamesForEditing: Found " .. #allGames .. " total games, returning " .. #result .. " (limit: " .. limit .. ")")
    end
    
    return result
end

-- Edit a specific game record by player and game index
function DRE:EditGameRecord(playerName, gameIndex, newResult, newGoldAmount, newInitialRoll)
    if not self.db or not self.db.profile.history or not playerName then
        return false, "No data available"
    end
    
    local playerData = self.db.profile.history[playerName]
    if not playerData or not playerData.recentGames or #playerData.recentGames == 0 then
        return false, "No recent games found for " .. playerName
    end
    
    if gameIndex < 1 or gameIndex > #playerData.recentGames then
        return false, "Invalid game index"
    end
    
    local oldGame = playerData.recentGames[gameIndex]
    local oldResult = oldGame.result
    local oldGoldAmount = oldGame.goldAmount or 0
    
    -- Update the game record
    oldGame.result = newResult
    oldGame.goldAmount = newGoldAmount or 0
    if newInitialRoll then
        oldGame.startingRoll = newInitialRoll
    end
    
    -- Update player's win/loss counters based on the change
    if oldResult ~= newResult then
        if oldResult == "Won" then
            -- Was a win, now changing
            playerData.wins = (playerData.wins or 1) - 1
            playerData.goldWon = (playerData.goldWon or oldGoldAmount) - oldGoldAmount
        elseif oldResult == "Lost" then
            -- Was a loss, now changing  
            playerData.losses = (playerData.losses or 1) - 1
            playerData.goldLost = (playerData.goldLost or oldGoldAmount) - oldGoldAmount
        end
        
        if newResult == "Won" then
            -- Now it's a win
            playerData.wins = (playerData.wins or 0) + 1
            playerData.goldWon = (playerData.goldWon or 0) + (newGoldAmount or 0)
        elseif newResult == "Lost" then
            -- Now it's a loss
            playerData.losses = (playerData.losses or 0) + 1
            playerData.goldLost = (playerData.goldLost or 0) + (newGoldAmount or 0)
        end
        
        -- Ensure counters don't go negative
        playerData.wins = math.max(0, playerData.wins or 0)
        playerData.losses = math.max(0, playerData.losses or 0)
        playerData.goldWon = math.max(0, playerData.goldWon or 0)
        playerData.goldLost = math.max(0, playerData.goldLost or 0)
    elseif oldGoldAmount ~= (newGoldAmount or 0) then
        -- Same result, different gold amount
        local goldDiff = (newGoldAmount or 0) - oldGoldAmount
        if newResult == "Won" then
            playerData.goldWon = (playerData.goldWon or 0) + goldDiff
            playerData.goldWon = math.max(0, playerData.goldWon)
        elseif newResult == "Lost" then
            playerData.goldLost = (playerData.goldLost or 0) + goldDiff
            playerData.goldLost = math.max(0, playerData.goldLost)
        end
    end
    
    return true, "Game record updated successfully"
end

-- Delete a specific game record by player and game index
function DRE:DeleteGameRecord(playerName, gameIndex)
    if not self.db or not self.db.profile.history or not playerName then
        return false, "No data available"
    end
    
    local playerData = self.db.profile.history[playerName]
    if not playerData or not playerData.recentGames or #playerData.recentGames == 0 then
        return false, "No recent games found for " .. playerName
    end
    
    if gameIndex < 1 or gameIndex > #playerData.recentGames then
        return false, "Invalid game index"
    end
    
    local gameToDelete = playerData.recentGames[gameIndex]
    local result = gameToDelete.result
    local goldAmount = gameToDelete.goldAmount or 0
    
    -- Update player's win/loss counters
    if result == "Won" then
        playerData.wins = math.max(0, (playerData.wins or 1) - 1)
        playerData.goldWon = math.max(0, (playerData.goldWon or goldAmount) - goldAmount)
    elseif result == "Lost" then
        playerData.losses = math.max(0, (playerData.losses or 1) - 1)
        playerData.goldLost = math.max(0, (playerData.goldLost or goldAmount) - goldAmount)
    end
    
    -- Remove the game from the list
    table.remove(playerData.recentGames, gameIndex)
    
    -- If player has no more games, optionally remove them entirely
    if #playerData.recentGames == 0 and (playerData.wins or 0) == 0 and (playerData.losses or 0) == 0 then
        self.db.profile.history[playerName] = nil
        return true, "Game deleted and player record removed (no remaining games)"
    end
    
    return true, "Game record deleted successfully"
end

-- Compatibility function - edit the most recent game record
function DRE:EditLastGame(playerName, newResult, newGoldAmount, newInitialRoll)
    return self:EditGameRecord(playerName, 1, newResult, newGoldAmount, newInitialRoll)
end