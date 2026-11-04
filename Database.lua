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

    local ok, parsedTime = pcall(time, {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = 0
    })

    return ok and tonumber(parsedTime) or 0
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

local function SameGameRecord(first, second)
    for key, value in pairs(first) do if second[key] ~= value then return false end end
    for key, value in pairs(second) do if first[key] ~= value then return false end end
    return true
end

local function GameComesBefore(first, second)
    local firstTime, secondTime = GetGameTimestamp(first), GetGameTimestamp(second)
    if firstTime ~= secondTime then return firstTime < secondTime end
    return (tonumber(first.sequence) or 0) < (tonumber(second.sequence) or 0)
end

local function HasPlayerTotals(player)
    return (player.gamesPlayed or 0) > 0 or (player.goldWon or 0) > 0 or (player.goldLost or 0) > 0
end

local function InvalidateLegacyStreakCheckpoint(profile, game)
    local legacy = profile.legacyStreaks
    if legacy and (legacy.checkpointSequence or 0) > 0
        and (tonumber(game.sequence) or 0) <= legacy.checkpointSequence then
        -- An outcome covered by the snapshot changed. Its current streak is no
        -- longer trustworthy; replay retained outcomes, keeping historical maxima.
        legacy.checkpointSequence = 0
        legacy.currentStreak = 0
        legacy.rebuiltFromRetainedHistory = true
    end
end

local function DeduplicateRecentGames(playerData)
    local seen, deduped, removed = {}, {}, 0
    for _, game in ipairs(playerData.recentGames or {}) do
        local existing = game.id and seen[game.id]
        if existing and SameGameRecord(existing, game) then
            removed = removed + 1
        else
            if game.id then seen[game.id] = game end
            deduped[#deduped + 1] = game
        end
    end
    playerData.recentGames = deduped
    return removed
end

function DRE:AllocateGameIdentity(game)
    local profile = self.db.profile
    profile.nextGameSequence = (profile.nextGameSequence or 0) + 1
    game.sequence = profile.nextGameSequence
    game.id = "dre:" .. game.sequence
end

-- Capture missing historical detail before any operation can change the rows.
-- Old releases pruned rows while keeping lifetime totals. Never erase that data.
function DRE:EnsureHistorySchema()
    if not self.db or not self.db.profile then return end
    local profile = self.db.profile
    if self.historySchemaProfile == profile then return end
    profile.history = profile.history or {}
    profile.pendingTradeWagers = profile.pendingTradeWagers or {}
    local counter, rows, incomplete = tonumber(profile.nextGameSequence) or 0, {}, false
    for playerName, player in pairs(profile.history) do
        local totals = { wins = 0, losses = 0, goldWon = 0, goldLost = 0 }
        for index, game in ipairs(player.recentGames or {}) do
            local amount = tonumber(game.goldAmount) or 0
            if IsWinResult(game.result) then totals.wins = totals.wins + 1; totals.goldWon = totals.goldWon + amount end
            if IsLossResult(game.result) then totals.losses = totals.losses + 1; totals.goldLost = totals.goldLost + amount end
            counter = math.max(counter, tonumber(game.sequence) or 0,
                type(game.id) == "string" and tonumber(game.id:match("^dre:(%d+)$")) or 0)
            rows[#rows + 1] = { player = playerName, index = index, game = game }
        end
        if not player.legacyTotals then
            player.legacyTotals = {}
            player.legacySnapshot = {}
            for key, represented in pairs(totals) do
                local saved = tonumber(player[key]) or 0
                player.legacySnapshot[key] = saved
                player.legacyTotals[key] = math.max(0, saved - represented)
            end
        end
        for _, value in pairs(player.legacyTotals) do if value > 0 then incomplete = true end end
    end
    profile.nextGameSequence = counter
    table.sort(rows, function(a, b)
        local aTime, bTime = GetGameTimestamp(a.game), GetGameTimestamp(b.game)
        if aTime ~= bTime then return aTime < bTime end
        if a.player ~= b.player then return a.player < b.player end
        return a.index > b.index -- legacy per-player arrays are newest first
    end)
    local seen = {}
    for _, row in ipairs(rows) do
        local game = row.game
        if not game.id or not game.sequence or (seen[game.id] and not SameGameRecord(seen[game.id], game)) then
            self:AllocateGameIdentity(game)
        end
        seen[game.id] = game
    end
    if incomplete and not profile.legacyStreaks then
        local tracking = profile.goldTracking or {}
        profile.legacyStreaks = {
            checkpointSequence = profile.nextGameSequence,
            currentStreak = tracking.currentStreak or 0,
            bestWinStreak = tracking.bestWinStreak or 0,
            worstLossStreak = tracking.worstLossStreak or 0,
        }
    end
    profile.historySchemaVersion = 1
    self.historySchemaProfile = profile
end

local function RecalculatePlayerAggregates(playerData)
    if not playerData then
        return
    end

    local recentGames = playerData.recentGames or {}
    local baseline = playerData.legacyTotals or {}
    local wins = baseline.wins or 0
    local losses = baseline.losses or 0
    local goldWon = baseline.goldWon or 0
    local goldLost = baseline.goldLost or 0

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
    self:EnsureHistorySchema()
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
    targetData.legacyTotals = targetData.legacyTotals or {}
    for key, value in pairs(sourceData.legacyTotals or {}) do
        targetData.legacyTotals[key] = (targetData.legacyTotals[key] or 0) + value
    end
    targetData.recentGames = targetData.recentGames or {}
    local mergedGames = sourceData.recentGames and #sourceData.recentGames or ((sourceData.wins or 0) + (sourceData.losses or 0))

    if sourceData.recentGames then
        for _, game in ipairs(sourceData.recentGames) do
            table.insert(targetData.recentGames, game)
        end
    end

    table.sort(targetData.recentGames, function(a, b)
        return GameComesBefore(b, a)
    end)
    local dedupedCount = DeduplicateRecentGames(targetData)
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
    for _, pending in ipairs(self.db.profile.pendingTradeWagers or {}) do
        if pending.playerName == sourceName then pending.playerName = targetName end
    end

    local _, recalcMessage = self:RecalculateGoldTracking()

    if self.UpdateStatsDisplay then
        self:UpdateStatsDisplay()
    end

    return true, string.format(
        "Merged '%s' into '%s' (%d games moved, %d duplicate entries removed). %s",
        sourceName,
        targetName,
        mergedGames,
        dedupedCount,
        recalcMessage or "Global gold tracking recalculated."
    )
end

function DRE:DeduplicateHistoryData()
    self:EnsureHistorySchema()
    if not self.db or not self.db.profile or not self.db.profile.history then
        return false, "No data available"
    end

    local totalRemoved = 0
    local playersTouched = 0

    for playerName, playerData in pairs(self.db.profile.history) do
        local removed = DeduplicateRecentGames(playerData)
        if removed > 0 then
            playersTouched = playersTouched + 1
            totalRemoved = totalRemoved + removed
        end
        RecalculatePlayerAggregates(playerData)
    end

    local _, recalcMessage = self:RecalculateGoldTracking()

    if self.UpdateStatsDisplay then
        self:UpdateStatsDisplay()
    end

    return true, string.format(
        "Removed %d duplicate game entries across %d players. %s",
        totalRemoved,
        playersTouched,
        recalcMessage or "Global gold tracking recalculated."
    )
end

-- Helper function to add game result to history
function DRE:AddGameToHistory(playerName, result, goldAmount, initialRoll, metadata)
    self:EnsureHistorySchema()
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
    playerData.legacyTotals = playerData.legacyTotals or { wins = 0, losses = 0, goldWon = 0, goldLost = 0 }
    
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

    local gameRecord = {
        date = date("%Y-%m-%d %H:%M"),
        timestamp = recordedAt,
        result = result,
        goldAmount = goldAmount or 0,
        initialRoll = initialRoll or 0
    }

    local suspiciousRollCount = metadata and tonumber(metadata.suspiciousRollCount) or 0
    if suspiciousRollCount > 0 then
        gameRecord.suspiciousRollCount = suspiciousRollCount
        if metadata.suspiciousRollDetails and metadata.suspiciousRollDetails ~= "" then
            gameRecord.suspiciousRollDetails = tostring(metadata.suspiciousRollDetails)
        end
    end

    self:AllocateGameIdentity(gameRecord)
    table.insert(playerData.recentGames, 1, gameRecord)
    
    -- Keep all games - complete history tracking
    
    -- Update overall gold tracking
    self:UpdateGoldTracking(result, goldAmount)

    return recordedAt, gameRecord.id
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
    self:EnsureHistorySchema()
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
                    InvalidateLegacyStreakCheckpoint(self.db.profile, game)
                    cleanedCount = cleanedCount + 1
                end
            end
            playerData.recentGames = newGames
        end

        RecalculatePlayerAggregates(playerData)
        if not HasPlayerTotals(playerData) then
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
    self.db.profile.pendingTradeWagers = {}
    self.db.profile.legacyStreaks = nil
    -- Keep nextGameSequence: a stale dialog must not resolve to a new game.

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
        historySchemaVersion = self.db.profile.historySchemaVersion,
        nextGameSequence = self.db.profile.nextGameSequence,
        pendingTradeWagers = self.db.profile.pendingTradeWagers,
        legacyStreaks = self.db.profile.legacyStreaks,
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
                result = result .. "[" .. string.format("%q", k) .. "] = "
            else
                result = result .. "[" .. tostring(k) .. "] = "
            end
            
            if type(v) == "table" then
                result = result .. serialize(v, indent + 1) .. ",\n"
            elseif type(v) == "string" then
                result = result .. string.format("%q", v) .. ",\n"
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
    self:EnsureHistorySchema()
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

            if not latestGame or GameComesBefore(latestGame, game) then
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
    self:EnsureHistorySchema()
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
                    gameId = game.id,
                    game = game,
                    timestamp = game.timestamp or 0
                })
            end
        end
    end

    table.sort(allGames, function(a, b) return GameComesBefore(b.game, a.game) end)

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
    self:EnsureHistorySchema()
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

    if not self:IsBoundedInteger(tonumber(newGoldAmount), 0, self.MAX_WAGER)
        or (newInitialRoll ~= nil and not self:IsBoundedInteger(tonumber(newInitialRoll), 0, self.MAX_ROLL)) then
        return false, "Invalid wager or starting roll"
    end
    if IsWinResult(oldGame.result) ~= IsWinResult(newResult) then
        InvalidateLegacyStreakCheckpoint(self.db.profile, oldGame)
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
    self:EnsureHistorySchema()
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
    
    -- Remove only settlements linked to the deleted record.
    InvalidateLegacyStreakCheckpoint(self.db.profile, playerData.recentGames[gameIndex])
    local deletedId = playerData.recentGames[gameIndex].id
    local pending = self.db.profile.pendingTradeWagers or {}
    for index = #pending, 1, -1 do
        if pending[index].gameId == deletedId then table.remove(pending, index) end
    end
    table.remove(playerData.recentGames, gameIndex)
    RecalculatePlayerAggregates(playerData)
    
    -- If player has no more games, optionally remove them entirely
    if not HasPlayerTotals(playerData) then
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

    local foundIndex, foundGame
    for gameIndex, game in ipairs(playerData.recentGames) do
        if game and tonumber(game.timestamp) == tonumber(recordedAt) then
            if foundIndex then return nil end
            foundIndex, foundGame = gameIndex, game
        end
    end
    return foundIndex, foundGame
end

function DRE:UpdateGameWagerByTimestamp(playerName, recordedAt, newGoldAmount)
    local gameIndex, game = self:FindGameRecordIndexByTimestamp(playerName, recordedAt)
    if not gameIndex or not game then
        return false, "Unable to find the recorded game"
    end

    return self:EditGameRecord(playerName, gameIndex, game.result, newGoldAmount or 0, game.initialRoll)
end

function DRE:FindGameRecordById(gameId)
    if type(gameId) ~= "string" or not self.db then return nil end
    self:EnsureHistorySchema()
    local foundPlayer, foundIndex, foundGame
    for playerName, player in pairs(self.db.profile.history) do
        for index, game in ipairs(player.recentGames or {}) do
            if game.id == gameId then
                if foundGame then return nil end -- ambiguous/corrupt identity: refuse mutation
                foundPlayer, foundIndex, foundGame = playerName, index, game
            end
        end
    end
    return foundPlayer, foundIndex, foundGame
end

function DRE:EditGameRecordById(gameId, result, wager, initialRoll)
    local player, index = self:FindGameRecordById(gameId)
    if not player then return false, "The selected game no longer exists or is ambiguous. Reopen the editor." end
    local success, message = self:EditGameRecord(player, index, result, wager, initialRoll)
    if success then
        local pending = self.db.profile.pendingTradeWagers or {}
        for i = #pending, 1, -1 do
            if pending[i].gameId == gameId then table.remove(pending, i) end
        end
    end
    return success, message
end

function DRE:DeleteGameRecordById(gameId)
    local player, index = self:FindGameRecordById(gameId)
    if not player then return false, "The selected game no longer exists or is ambiguous. Reopen the editor." end
    return self:DeleteGameRecord(player, index)
end

function DRE:UpdateGameWagerById(gameId, wager)
    local player, index, game = self:FindGameRecordById(gameId)
    if not player then return false, "Unable to find the recorded game" end
    return self:EditGameRecord(player, index, game.result, wager, game.initialRoll)
end

-- Recalculate and fix global gold tracking totals from individual player data
function DRE:RecalculateGoldTracking()
    self:EnsureHistorySchema()
    if not self.db or not self.db.profile.history then
        return false, "No data available"
    end

    local totalWon = 0
    local totalLost = 0
    local playersToRemove = {}

    -- Sum up all individual player gold totals
    for playerName, playerData in pairs(self.db.profile.history) do
        RecalculatePlayerAggregates(playerData)
        if not HasPlayerTotals(playerData) then
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
    self:EnsureHistorySchema()
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
                    sequence = game.sequence,
                    date = game.date
                })
            end
        end
    end

    table.sort(allGames, GameComesBefore)

    -- Incomplete legacy history has a known streak checkpoint, but cannot be
    -- reconstructed from its retained rows. Replay only games after that point.
    local legacy = self.db.profile.legacyStreaks
    local currentStreak = legacy and legacy.currentStreak or 0
    local bestWinStreak = legacy and legacy.bestWinStreak or 0
    local worstLossStreak = legacy and legacy.worstLossStreak or 0

    for _, game in ipairs(allGames) do
        if not legacy or (game.sequence or 0) > (legacy.checkpointSequence or 0) then
            if IsWinResult(game.result) then
                currentStreak = currentStreak >= 0 and (currentStreak + 1) or 1
                bestWinStreak = math.max(bestWinStreak, currentStreak)
            elseif IsLossResult(game.result) then
                currentStreak = currentStreak <= 0 and (currentStreak - 1) or -1
                worstLossStreak = math.min(worstLossStreak, currentStreak)
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
