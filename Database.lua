-- Database.lua
-- Database management using AceDB

local addonName, addonTable = ...
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
if not DRE then return end

-- Database functions are now handled by AceDB in Core.lua
-- This file provides helper functions for data management

local function IsWinResult(result)
    return result == "Won" or result == "WIN"
end

local function IsLossResult(result)
    return result == "Lost" or result == "LOSS"
end

local function ParseDateTimeToEpoch(dateText)
    if not dateText or type(dateText) ~= "string" then
        return 0
    end

    local year, month, day, hour, min = dateText:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$")
    if not year then
        year, month, day, hour, min = dateText:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
    end

    if not year then
        return 0
    end

    local parsedTime = time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = 0
    })

    return tonumber(parsedTime) or 0
end

local function GetGameTimestamp(game)
    if not game then
        return 0
    end

    local timestamp = tonumber(game.timestamp) or 0
    if timestamp > 0 then
        return timestamp
    end

    return ParseDateTimeToEpoch(game.date)
end

local function RecalculatePlayerAggregates(playerData)
    if not playerData then
        return
    end

    local recentGames = playerData.recentGames or {}
    local wins = 0
    local losses = 0
    local goldWon = 0
    local goldLost = 0

    for _, game in ipairs(recentGames) do
        local goldAmount = tonumber(game and game.goldAmount) or 0
        local result = game and game.result

        if IsWinResult(result) then
            wins = wins + 1
            goldWon = goldWon + goldAmount
        elseif IsLossResult(result) then
            losses = losses + 1
            goldLost = goldLost + goldAmount
        end
    end

    playerData.recentGames = recentGames
    playerData.wins = wins
    playerData.losses = losses
    playerData.gamesPlayed = wins + losses
    playerData.goldWon = goldWon
    playerData.goldLost = goldLost
end

-- Helper function to get player history
function DRE:GetPlayerHistory(playerName)
    if not self.db or not self.db.profile.history then
        return nil
    end
    
    return self.db.profile.history[playerName]
end

-- Merge all history from sourceName into targetName, then remove sourceName.
function DRE:MergePlayerHistory(sourceName, targetName)
    if not self.db or not self.db.profile or not self.db.profile.history then
        return false, "No data available"
    end

    sourceName = self:Trim(sourceName or "")
    targetName = self:Trim(targetName or "")

    if sourceName == "" or targetName == "" then
        return false, "Usage: /dr merge <oldName> <newName>"
    end

    if sourceName == targetName then
        return false, "Old and new player names must be different"
    end

    local history = self.db.profile.history
    local sourceData = history[sourceName]
    if not sourceData then
        return false, string.format("No history found for '%s'", sourceName)
    end

    if not history[targetName] then
        history[targetName] = {
            gamesPlayed = 0,
            wins = 0,
            losses = 0,
            goldWon = 0,
            goldLost = 0,
            recentGames = {}
        }
    end

    local targetData = history[targetName]
    targetData.recentGames = targetData.recentGames or {}
    local mergedGames = sourceData.recentGames and #sourceData.recentGames or ((sourceData.wins or 0) + (sourceData.losses or 0))

    if sourceData.recentGames then
        for _, game in ipairs(sourceData.recentGames) do
            table.insert(targetData.recentGames, game)
        end
    end

    table.sort(targetData.recentGames, function(a, b)
        return GetGameTimestamp(a) > GetGameTimestamp(b)
    end)
    RecalculatePlayerAggregates(targetData)

    if self.db.profile.suspiciousRolls and self.db.profile.suspiciousRolls[sourceName] then
        local sourceSuspicious = self.db.profile.suspiciousRolls[sourceName]
        local targetSuspicious = self.db.profile.suspiciousRolls[targetName] or { count = 0 }
        targetSuspicious.count = (targetSuspicious.count or 0) + (sourceSuspicious.count or 0)

        if (sourceSuspicious.lastSeen or 0) >= (targetSuspicious.lastSeen or 0) then
            targetSuspicious.lastSeen = sourceSuspicious.lastSeen
            targetSuspicious.lastRoll = sourceSuspicious.lastRoll
            targetSuspicious.lastMaxRoll = sourceSuspicious.lastMaxRoll
            targetSuspicious.expectedMaxRoll = sourceSuspicious.expectedMaxRoll
        end

        self.db.profile.suspiciousRolls[targetName] = targetSuspicious
        self.db.profile.suspiciousRolls[sourceName] = nil
    end

    history[sourceName] = nil

    local _, recalcMessage = self:RecalculateGoldTracking()

    if self.UpdateStatsDisplay then
        self:UpdateStatsDisplay()
    end

    return true, string.format(
        "Merged '%s' into '%s' (%d games moved). %s",
        sourceName,
        targetName,
        mergedGames,
        recalcMessage or "Global gold tracking recalculated."
    )
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
    
    if IsWinResult(result) then
        playerData.wins = (playerData.wins or 0) + 1
        playerData.goldWon = (playerData.goldWon or 0) + (goldAmount or 0)
    elseif IsLossResult(result) then
        playerData.losses = (playerData.losses or 0) + 1
        playerData.goldLost = (playerData.goldLost or 0) + (goldAmount or 0)
    end
    
    -- Add to recent games
    if not playerData.recentGames then
        playerData.recentGames = {}
    end
    
    local recordedAt = time()

    table.insert(playerData.recentGames, 1, {
        date = date("%Y-%m-%d %H:%M"),
        timestamp = recordedAt,
        result = result,
        goldAmount = goldAmount or 0,
        initialRoll = initialRoll or 0
    })
    
    -- Keep all games - complete history tracking
    
    -- Update overall gold tracking
    self:UpdateGoldTracking(result, goldAmount)

    return recordedAt
end

-- Update gold tracking statistics
function DRE:UpdateGoldTracking(result, goldAmount)
    if not self.db then
        return
    end
    
    local tracking = self.db.profile.goldTracking
    goldAmount = goldAmount or 0
    
    if IsWinResult(result) then
        tracking.totalWon = (tracking.totalWon or 0) + goldAmount
        
        if tracking.currentStreak >= 0 then
            tracking.currentStreak = (tracking.currentStreak or 0) + 1
        else
            tracking.currentStreak = 1
        end
        
        if tracking.currentStreak > (tracking.bestWinStreak or 0) then
            tracking.bestWinStreak = tracking.currentStreak
        end
        
    elseif IsLossResult(result) then
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
            local wins = playerData.wins or 0
            local losses = playerData.losses or 0
            stats.totalWins = stats.totalWins + wins
            stats.totalLosses = stats.totalLosses + losses
            stats.totalGames = stats.totalGames + wins + losses
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
        local wins = playerData.wins or 0
        local losses = playerData.losses or 0
        local gamesPlayed = wins + losses
        table.insert(players, {
            name = playerName,
            gamesPlayed = gamesPlayed,
            wins = wins,
            losses = losses,
            goldWon = playerData.goldWon or 0,
            goldLost = playerData.goldLost or 0,
            winRate = gamesPlayed > 0 and (wins / gamesPlayed * 100) or 0
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
    
    local playersToRemove = {}

    for playerName, playerData in pairs(self.db.profile.history) do
        if playerData.recentGames then
            local newGames = {}
            for _, game in ipairs(playerData.recentGames) do
                local gameTime = GetGameTimestamp(game)
                
                if gameTime == 0 or gameTime >= cutoffTime then
                    table.insert(newGames, game)
                else
                    cleanedCount = cleanedCount + 1
                end
            end
            playerData.recentGames = newGames
        end

        RecalculatePlayerAggregates(playerData)
        if (playerData.gamesPlayed or 0) <= 0 then
            table.insert(playersToRemove, playerName)
        end
    end

    for _, playerName in ipairs(playersToRemove) do
        self.db.profile.history[playerName] = nil
    end
    
    if cleanedCount > 0 then
        self:RecalculateGoldTracking()
        self:Print(string.format("Cleaned %d old game records", cleanedCount))
    else
        self:Print("No old game records found to clean")
    end
end

-- Reset all data
function DRE:ResetAllData()
    if not self.db then
        return
    end
    
    -- Reset history
    self.db.profile.history = {}

    -- Reset suspicious-roll tracking
    self.db.profile.suspiciousRolls = {}
    
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
        suspiciousRolls = self.db.profile.suspiciousRolls,
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
            local gameTime = GetGameTimestamp(game)

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

    -- Helper function to safely parse date strings
    local function parseDateToEpoch(dateStr)
        if not dateStr or type(dateStr) ~= "string" then
            return 0
        end

        return ParseDateTimeToEpoch(dateStr)
    end

    -- Sort by timestamp (newest first) - handle missing timestamps and date fields
    table.sort(allGames, function(a, b)
        local aTime = a.timestamp or 0
        local bTime = b.timestamp or 0

        -- If timestamp is 0 or missing, try to parse the date field
        if aTime == 0 and a.game and a.game.date then
            aTime = parseDateToEpoch(a.game.date)
        end

        if bTime == 0 and b.game and b.game.date then
            bTime = parseDateToEpoch(b.game.date)
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

    if IsWinResult(newResult) then
        newResult = "Won"
    elseif IsLossResult(newResult) then
        newResult = "Lost"
    else
        return false, "Invalid result value. Use Won or Lost."
    end

    -- Update the game record
    oldGame.result = newResult
    oldGame.goldAmount = math.max(0, tonumber(newGoldAmount) or 0)
    if newInitialRoll ~= nil then
        oldGame.initialRoll = tonumber(newInitialRoll) or 0
    end

    RecalculatePlayerAggregates(playerData)
    local success, message = self:RecalculateGoldTracking()
    if not success then
        return false, "Game updated but totals could not be recalculated: " .. (message or "unknown error")
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
    
    -- Remove the game from the list
    table.remove(playerData.recentGames, gameIndex)
    RecalculatePlayerAggregates(playerData)
    
    -- If player has no more games, optionally remove them entirely
    if (playerData.gamesPlayed or 0) == 0 then
        self.db.profile.history[playerName] = nil
        local success, message = self:RecalculateGoldTracking()
        if not success then
            return false, "Game deleted but totals could not be recalculated: " .. (message or "unknown error")
        end
        return true, "Game deleted and player record removed (no remaining games)"
    end

    local success, message = self:RecalculateGoldTracking()
    if not success then
        return false, "Game deleted but totals could not be recalculated: " .. (message or "unknown error")
    end
    
    return true, "Game record deleted successfully"
end

-- Compatibility function - edit the most recent game record
function DRE:EditLastGame(playerName, newResult, newGoldAmount, newInitialRoll)
    return self:EditGameRecord(playerName, 1, newResult, newGoldAmount, newInitialRoll)
end

function DRE:FindGameRecordIndexByTimestamp(playerName, recordedAt)
    if not self.db or not self.db.profile.history or not playerName or not recordedAt then
        return nil
    end

    local playerData = self.db.profile.history[playerName]
    if not playerData or not playerData.recentGames then
        return nil
    end

    for gameIndex, game in ipairs(playerData.recentGames) do
        if game and tonumber(game.timestamp) == tonumber(recordedAt) then
            return gameIndex, game
        end
    end

    return nil
end

function DRE:UpdateGameWagerByTimestamp(playerName, recordedAt, newGoldAmount)
    local gameIndex, game = self:FindGameRecordIndexByTimestamp(playerName, recordedAt)
    if not gameIndex or not game then
        return false, "Unable to find the recorded game"
    end

    return self:EditGameRecord(playerName, gameIndex, game.result, newGoldAmount or 0, game.initialRoll)
end

-- Recalculate and fix global gold tracking totals from individual player data
function DRE:RecalculateGoldTracking()
    if not self.db or not self.db.profile.history then
        return false, "No data available"
    end

    local totalWon = 0
    local totalLost = 0
    local playersToRemove = {}

    -- Sum up all individual player gold totals
    for playerName, playerData in pairs(self.db.profile.history) do
        RecalculatePlayerAggregates(playerData)
        if (playerData.gamesPlayed or 0) <= 0 then
            table.insert(playersToRemove, playerName)
        end
        totalWon = totalWon + (playerData.goldWon or 0)
        totalLost = totalLost + (playerData.goldLost or 0)
    end

    for _, playerName in ipairs(playersToRemove) do
        self.db.profile.history[playerName] = nil
    end

    -- Update global tracking with correct totals
    if not self.db.profile.goldTracking then
        self.db.profile.goldTracking = {}
    end

    local oldTotalWon = self.db.profile.goldTracking.totalWon or 0
    local oldTotalLost = self.db.profile.goldTracking.totalLost or 0

    self.db.profile.goldTracking.totalWon = totalWon
    self.db.profile.goldTracking.totalLost = totalLost

    -- Recalculate streaks from game history
    self:RecalculateStreaks()

    -- Update UI if it's open
    if DRE.UpdateStatsDisplay then
        DRE:UpdateStatsDisplay()
    end

    return true, string.format("Global gold tracking recalculated: Won %d->%d, Lost %d->%d",
        oldTotalWon, totalWon, oldTotalLost, totalLost)
end

-- Recalculate streaks from complete game history
function DRE:RecalculateStreaks()
    if not self.db or not self.db.profile.history or not self.db.profile.goldTracking then
        return
    end

    -- Collect all games with timestamps
    local allGames = {}
    for playerName, playerData in pairs(self.db.profile.history) do
        if playerData.recentGames then
            for _, game in ipairs(playerData.recentGames) do
                table.insert(allGames, {
                    result = game.result,
                    timestamp = game.timestamp or 0,
                    date = game.date
                })
            end
        end
    end

    -- Sort games by timestamp/date (oldest first)
    table.sort(allGames, function(a, b)
        local aTime = a.timestamp or 0
        local bTime = b.timestamp or 0

        -- If timestamp is missing, try to parse date
        if aTime == 0 and a.date then
            aTime = ParseDateTimeToEpoch(a.date)
        end

        if bTime == 0 and b.date then
            bTime = ParseDateTimeToEpoch(b.date)
        end

        return aTime < bTime
    end)

    -- Calculate streaks by replaying game history
    local currentStreak = 0
    local bestWinStreak = 0
    local worstLossStreak = 0

    for _, game in ipairs(allGames) do
        if game.result == "Won" or game.result == "WIN" then
            if currentStreak >= 0 then
                currentStreak = currentStreak + 1
            else
                currentStreak = 1
            end

            if currentStreak > bestWinStreak then
                bestWinStreak = currentStreak
            end

        elseif game.result == "Lost" or game.result == "LOSS" then
            if currentStreak <= 0 then
                currentStreak = currentStreak - 1
            else
                currentStreak = -1
            end

            if currentStreak < worstLossStreak then
                worstLossStreak = currentStreak
            end
        end
    end

    -- Update tracking values
    self.db.profile.goldTracking.currentStreak = currentStreak
    self.db.profile.goldTracking.bestWinStreak = bestWinStreak
    self.db.profile.goldTracking.worstLossStreak = worstLossStreak

    self:DebugPrint(string.format("Streaks recalculated: Current=%d, Best Win=%d, Worst Loss=%d",
        currentStreak, bestWinStreak, worstLossStreak))
end
