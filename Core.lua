-- Core.lua
-- Main addon initialization using Ace3 framework

local addonName, addonTable = ...

-- Check for required libraries
if not LibStub then
    error("DeathRollEnhancer requires LibStub")
    return
end

-- Initialize addon with Ace3
local DRE = LibStub("AceAddon-3.0"):NewAddon("DeathRollEnhancer", "AceConsole-3.0", "AceEvent-3.0")

-- Addon information
DRE.version = "2.0.0"
DRE.author = "EgyptianSheikh"

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
            framePos = {
                point = "CENTER",
                x = 0,
                y = 0,
            },
        },
        gameplay = {
            autoEmote = true,
            soundEnabled = true,
            trackGold = true,
            autoRollFromMoney = false,
            chatMessages = false,
            debugMessages = false,
        },
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
            showMostMoneyWonFrom = true,
            showMostMoneyLostTo = true,
            showBiggestWin = true,
            showBiggestLoss = true,
            showLuckyPlayer = true,
            showUnluckyPlayer = true,
            showNemesis = true,
            showVictim = true,
            showGoldMinePlayer = true,
            showMoneySinkPlayer = true,
            showLongestWinStreak = true,
            showLongestLossStreak = true,
            showAvgWager = true,
            showHighRoller = true,
            showCheapskate = true,
            showDaredevil = true,
            showConservative = true,
        },
    },
}

-- Ace3 addon lifecycle methods
function DRE:OnInitialize()
    -- Initialize database
    self.db = AceDB:New("DeathRollEnhancerDB", defaults, true)
    
    -- Register addon message prefix for inter-addon communication
    C_ChatInfo.RegisterAddonMessagePrefix("DeathRollEnh")
    
    -- Register options
    self:SetupOptions()
    
    -- Register slash commands
    self:RegisterChatCommand("deathroll", "SlashCommand")
    self:RegisterChatCommand("dr", "SlashCommand")
    self:RegisterChatCommand("drh", "HistoryCommand")
    self:RegisterChatCommand("deathrollhistory", "HistoryCommand")
    
    self:Print("DeathRoll Enhancer v" .. self.version .. " loaded!")
end

function DRE:OnEnable()
    -- Register core events
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("CHAT_MSG_ADDON")
    
    -- Register game-related events (CHAT_MSG_WHISPER for spicy duels)
    self:RegisterEvent("CHAT_MSG_WHISPER")
    
    -- Initialize modules
    self:InitializeUI()
    self:InitializeMinimap()
    self:InitializeSharedMedia()
end

function DRE:OnDisable()
    -- Cleanup
    self:UnregisterAllEvents()
end

-- Utility functions
function DRE:CusRound(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function DRE:GetRandomHappyEmote()
    local happyEmotes = {"CHEER", "LAUGH", "SALUTE", "DANCE", "VICTORY"}
    return happyEmotes[math.random(1, #happyEmotes)]
end

function DRE:GetRandomSadEmote()
    local sadEmotes = {"CRY", "SIGH", "SURRENDER", "LAY", "CONGRATULATE"}
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

-- Calculate fun statistics from history data
function DRE:CalculateFunStats()
    if not self.db or not self.db.profile.history then
        return {}
    end
    
    local history = self.db.profile.history
    local funStats = {}
    
    -- Initialize counters
    local mostGamesPlayer, mostGamesCount = nil, 0
    local mostWinsPlayer, mostWinsCount = nil, 0
    local mostLossesPlayer, mostLossesCount = nil, 0
    local mostMoneyWonPlayer, mostMoneyWonAmount = nil, 0
    local mostMoneyLostPlayer, mostMoneyLostAmount = nil, 0
    local nemesisPlayer, nemesisWinRate = nil, 0
    local victimPlayer, victimWinRate = nil, 1
    local highRollerPlayer, highRollerAvg = nil, 0
    local cheapskatePlayer, cheapskateAvg = nil, math.huge
    local luckyPlayer, luckyWinRate = nil, 0
    local unluckyPlayer, unluckyWinRate = nil, 1
    local daredevilPlayer, daredevilAvg = nil, 0
    local conservativePlayer, conservativeAvg = nil, math.huge
    local biggestWinAmount, biggestWinPlayer = 0, nil
    local biggestLossAmount, biggestLossPlayer = 0, nil
    
    -- Analyze each player
    for playerName, playerData in pairs(history) do
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
            
            -- Calculate win rates for nemesis/victim (minimum 5 games)
            if totalGames >= 5 then
                local theirWinRate = losses / totalGames -- Their wins against us
                local ourWinRate = wins / totalGames -- Our wins against them
                
                -- Nemesis (highest win rate against us)
                if theirWinRate > nemesisWinRate then
                    nemesisPlayer = playerName
                    nemesisWinRate = theirWinRate
                end
                
                -- Victim (lowest win rate against us, highest for us)
                if theirWinRate < victimWinRate then
                    victimPlayer = playerName
                    victimWinRate = theirWinRate
                end
                
                -- Lucky/Unlucky based on our win rate
                if ourWinRate > luckyWinRate then
                    luckyPlayer = playerName
                    luckyWinRate = ourWinRate
                end
                
                if ourWinRate < unluckyWinRate then
                    unluckyPlayer = playerName
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
                        if game.result == "Won" and game.goldAmount > biggestWinAmount then
                            biggestWinAmount = game.goldAmount
                            biggestWinPlayer = playerName
                        elseif game.result == "Lost" and game.goldAmount > biggestLossAmount then
                            biggestLossAmount = game.goldAmount
                            biggestLossPlayer = playerName
                        end
                        
                        totalWager = totalWager + game.goldAmount
                        wagerCount = wagerCount + 1
                    end
                    
                    -- Track starting rolls for daredevil/conservative
                    if game.startingRoll and game.startingRoll > 0 then
                        totalStartRoll = totalStartRoll + game.startingRoll
                        rollCount = rollCount + 1
                    end
                end
                
                -- Calculate average wager
                if wagerCount > 0 then
                    local avgWager = totalWager / wagerCount
                    if avgWager > highRollerAvg then
                        highRollerPlayer = playerName
                        highRollerAvg = avgWager
                    end
                    if avgWager < cheapskateAvg then
                        cheapskatePlayer = playerName
                        cheapskateAvg = avgWager
                    end
                end
                
                -- Calculate average starting roll
                if rollCount > 0 then
                    local avgRoll = totalStartRoll / rollCount
                    if avgRoll > daredevilAvg then
                        daredevilPlayer = playerName
                        daredevilAvg = avgRoll
                    end
                    if avgRoll < conservativeAvg then
                        conservativePlayer = playerName
                        conservativeAvg = avgRoll
                    end
                end
            end
        end
    end
    
    -- Package the results
    return {
        mostPlayedWith = {player = mostGamesPlayer, count = mostGamesCount},
        mostWinsAgainst = {player = mostWinsPlayer, count = mostWinsCount},
        mostLossesAgainst = {player = mostLossesPlayer, count = mostLossesCount},
        mostMoneyWonFrom = {player = mostMoneyWonPlayer, amount = mostMoneyWonAmount},
        mostMoneyLostTo = {player = mostMoneyLostPlayer, amount = mostMoneyLostAmount},
        nemesis = {player = nemesisPlayer, winRate = nemesisWinRate},
        victim = {player = victimPlayer, winRate = victimWinRate},
        highRoller = {player = highRollerPlayer, avgWager = highRollerAvg},
        cheapskate = {player = cheapskatePlayer, avgWager = cheapskateAvg},
        luckyPlayer = {player = luckyPlayer, winRate = luckyWinRate},
        unluckyPlayer = {player = unluckyPlayer, winRate = unluckyWinRate},
        daredevil = {player = daredevilPlayer, avgRoll = daredevilAvg},
        conservative = {player = conservativePlayer, avgRoll = conservativeAvg},
        biggestWin = {amount = biggestWinAmount, player = biggestWinPlayer},
        biggestLoss = {amount = biggestLossAmount, player = biggestLossPlayer},
    }
end

-- Format fun statistic for display
function DRE:FormatFunStat(statType, statData)
    if not statData or not statData.player then
        return nil
    end
    
    local player = statData.player
    local formatters = {
        mostPlayedWith = function(data)
            return string.format("Most Played With: %s (%d games)", player, data.count)
        end,
        mostWinsAgainst = function(data)
            return string.format("Most Wins Against: %s (%d wins)", player, data.count)
        end,
        mostLossesAgainst = function(data)
            return string.format("Most Losses Against: %s (%d losses)", player, data.count)
        end,
        mostMoneyWonFrom = function(data)
            return string.format("Biggest Gold Mine: %s (%s won)", player, self:FormatGold(data.amount))
        end,
        mostMoneyLostTo = function(data)
            return string.format("Biggest Money Sink: %s (%s lost)", player, self:FormatGold(data.amount))
        end,
        nemesis = function(data)
            return string.format("Your Nemesis: %s (%.1f%% win rate against you)", player, data.winRate * 100)
        end,
        victim = function(data)
            return string.format("Your Victim: %s (%.1f%% win rate against you)", player, data.winRate * 100)
        end,
        highRoller = function(data)
            return string.format("High Roller: %s (%s avg wager)", player, self:FormatGold(data.avgWager))
        end,
        cheapskate = function(data)
            return string.format("Cheapskate: %s (%s avg wager)", player, self:FormatGold(data.avgWager))
        end,
        luckyPlayer = function(data)
            return string.format("Lucky Charm: %s (%.1f%% win rate with them)", player, data.winRate * 100)
        end,
        unluckyPlayer = function(data)
            return string.format("Bad Luck Magnet: %s (%.1f%% win rate with them)", player, data.winRate * 100)
        end,
        daredevil = function(data)
            return string.format("Daredevil: %s (avg %.0f starting roll)", player, data.avgRoll)
        end,
        conservative = function(data)
            return string.format("Conservative: %s (avg %.0f starting roll)", player, data.avgRoll)
        end,
        biggestWin = function(data)
            return string.format("Biggest Single Win: %s vs %s", self:FormatGold(data.amount), player)
        end,
        biggestLoss = function(data)
            return string.format("Biggest Single Loss: %s to %s", self:FormatGold(data.amount), player)
        end,
    }
    
    local formatter = formatters[statType]
    if formatter then
        return formatter(statData)
    end
    
    return nil
end

-- Slash command handlers
function DRE:SlashCommand(input)
    if not input or input:trim() == "" then
        self:ShowMainWindow()
    elseif input == "config" or input == "options" then
        self:OpenOptions()
    elseif input == "accept" then
        self:Print("No pending challenge to accept")
    elseif input == "decline" then
        self:Print("No pending challenge to decline")
    else
        self:Print("Usage: /dr or /deathroll - Opens the main window")
        self:Print("       /dr config - Opens configuration")
        self:Print("       /dr accept - Accept pending challenge")
        self:Print("       /dr decline - Decline pending challenge")
    end
end

function DRE:HistoryCommand(input)
    local target = input and input:trim() or ""
    if target == "" then
        target = UnitName("target")
    end
    
    if target then
        self:ShowHistory(target)
    else
        self:Print("Please provide a target name or select a target.")
        self:Print("Usage: /drh [playername] or /deathrollhistory [playername]")
    end
end

-- AceConfig Options Table
function DRE:SetupOptions()
    local options = {
        name = "DeathRoll Enhancer",
        type = "group",
        args = {
            general = {
                name = "General",
                type = "group",
                order = 1,
                args = {
                    header = {
                        name = "DeathRoll Enhancer v" .. self.version,
                        type = "header",
                        order = 0,
                    },
                    gameplayHeader = {
                        name = "Gameplay Settings",
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
                        name = "Sound Effects",
                        desc = "Enable sound effects",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.soundEnabled end,
                        set = function(_, val) self.db.profile.gameplay.soundEnabled = val end,
                        order = 3,
                    },
                    trackGold = {
                        name = "Track Gold",
                        desc = "Track gold won and lost",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.trackGold end,
                        set = function(_, val) self.db.profile.gameplay.trackGold = val end,
                        order = 4,
                    },
                    autoRollFromMoney = {
                        name = "Auto-Roll from Money",
                        desc = "Automatically set roll number based on your total money (gold + silver + copper) mod 999,999",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.autoRollFromMoney end,
                        set = function(_, val) 
                            self.db.profile.gameplay.autoRollFromMoney = val
                            self:Print("Auto-roll setting changed. Close and reopen the main window to see the new UI.")
                        end,
                        order = 5,
                    },
                    chatMessages = {
                        name = "Chat Messages",
                        desc = "Show informational messages in chat (challenge status, responses, timeouts, etc.)",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.chatMessages end,
                        set = function(_, val) self.db.profile.gameplay.chatMessages = val end,
                        order = 5.5,
                    },
                    debugMessages = {
                        name = "Debug Messages",
                        desc = "Show technical debug messages (addon detection, message parsing, etc.). Turn this off for a cleaner experience.",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.debugMessages end,
                        set = function(_, val) self.db.profile.gameplay.debugMessages = val end,
                        order = 5.7,
                    },
                    interfaceHeader = {
                        name = "Interface Settings",
                        type = "header",
                        order = 6,
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
                    dataHeader = {
                        name = "Data Management",
                        type = "header",
                        order = 10,
                    },
                    stats = {
                        name = "Show Statistics",
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
                        name = "Clean Old Data",
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
                            StaticPopup_Show("DEATHROLL_RESET_CONFIRM")
                        end,
                        order = 13,
                    },
                    exportData = {
                        name = "Export Data",
                        desc = "Export your DeathRoll data for backup",
                        type = "execute",
                        func = function()
                            local exportString = self:ExportData()
                            local frame = AceGUI:Create("Frame")
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
                },
            },
            statistics = {
                name = "Fun Statistics",
                type = "group",
                order = 2,
                args = {
                    header = {
                        name = "Choose which fun statistics to display",
                        type = "header",
                        order = 0,
                    },
                    description = {
                        name = "Select which interesting statistics you want to see in the Statistics tab. These provide fun insights into your DeathRoll gaming habits!",
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
                        get = function() return self.db.profile.funStats.showMostPlayedWith end,
                        set = function(_, val) self.db.profile.funStats.showMostPlayedWith = val end,
                        order = 3,
                    },
                    showMostWinsAgainst = {
                        name = "Most Wins Against",
                        desc = "Show which player you've beaten the most times",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showMostWinsAgainst end,
                        set = function(_, val) self.db.profile.funStats.showMostWinsAgainst = val end,
                        order = 4,
                    },
                    showMostLossesAgainst = {
                        name = "Most Losses Against",
                        desc = "Show which player has beaten you the most times",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showMostLossesAgainst end,
                        set = function(_, val) self.db.profile.funStats.showMostLossesAgainst = val end,
                        order = 5,
                    },
                    showNemesis = {
                        name = "Your Nemesis",
                        desc = "Show the player with the highest win rate against you (min 5 games)",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showNemesis end,
                        set = function(_, val) self.db.profile.funStats.showNemesis = val end,
                        order = 6,
                    },
                    showVictim = {
                        name = "Your Victim",
                        desc = "Show the player with the lowest win rate against you (min 5 games)",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showVictim end,
                        set = function(_, val) self.db.profile.funStats.showVictim = val end,
                        order = 7,
                    },
                    separator2 = {
                        name = "Gold & Money",
                        type = "header",
                        order = 8,
                    },
                    showMostMoneyWonFrom = {
                        name = "Biggest Gold Mine",
                        desc = "Show which player you've won the most gold from",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showMostMoneyWonFrom end,
                        set = function(_, val) self.db.profile.funStats.showMostMoneyWonFrom = val end,
                        order = 9,
                    },
                    showMostMoneyLostTo = {
                        name = "Biggest Money Sink",
                        desc = "Show which player you've lost the most gold to",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showMostMoneyLostTo end,
                        set = function(_, val) self.db.profile.funStats.showMostMoneyLostTo = val end,
                        order = 10,
                    },
                    showBiggestWin = {
                        name = "Biggest Single Win",
                        desc = "Show your largest single game victory",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showBiggestWin end,
                        set = function(_, val) self.db.profile.funStats.showBiggestWin = val end,
                        order = 11,
                    },
                    showBiggestLoss = {
                        name = "Biggest Single Loss",
                        desc = "Show your largest single game defeat",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showBiggestLoss end,
                        set = function(_, val) self.db.profile.funStats.showBiggestLoss = val end,
                        order = 12,
                    },
                    showHighRoller = {
                        name = "High Roller",
                        desc = "Show the player you've had the highest average wager with",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showHighRoller end,
                        set = function(_, val) self.db.profile.funStats.showHighRoller = val end,
                        order = 13,
                    },
                    showCheapskate = {
                        name = "Cheapskate",
                        desc = "Show the player you've had the lowest average wager with",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showCheapskate end,
                        set = function(_, val) self.db.profile.funStats.showCheapskate = val end,
                        order = 14,
                    },
                    separator3 = {
                        name = "Luck & Streaks",
                        type = "header",
                        order = 15,
                    },
                    showLuckyPlayer = {
                        name = "Lucky Player",
                        desc = "Show which player seems to bring you the most luck",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showLuckyPlayer end,
                        set = function(_, val) self.db.profile.funStats.showLuckyPlayer = val end,
                        order = 16,
                    },
                    showUnluckyPlayer = {
                        name = "Unlucky Player",
                        desc = "Show which player seems to bring you bad luck",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showUnluckyPlayer end,
                        set = function(_, val) self.db.profile.funStats.showUnluckyPlayer = val end,
                        order = 17,
                    },
                    showDaredevil = {
                        name = "Daredevil Opponent",
                        desc = "Show which player prefers the highest starting rolls",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showDaredevil end,
                        set = function(_, val) self.db.profile.funStats.showDaredevil = val end,
                        order = 18,
                    },
                    showConservative = {
                        name = "Conservative Opponent",
                        desc = "Show which player prefers the lowest starting rolls",
                        type = "toggle",
                        get = function() return self.db.profile.funStats.showConservative end,
                        set = function(_, val) self.db.profile.funStats.showConservative = val end,
                        order = 19,
                    },
                },
            },
        },
    }
    
    AceConfig:RegisterOptionsTable("DeathRollEnhancer", options)
    self.optionsFrame = AceConfigDialog:AddToBlizOptions("DeathRollEnhancer", "DeathRoll Enhancer")
end

-- UI Methods
function DRE:ShowMainWindow()
    self:Print("Opening DeathRoll window...")
end

function DRE:ShowHistory(playerName)
    self:Print("Showing history for: " .. playerName)
end

function DRE:OpenOptions()
    AceConfigDialog:Open("DeathRollEnhancer")
end

function DRE:UpdateUIScale()
    if DRE.UI and DRE.UI.mainWindow and DRE.UI.mainWindow.frame then
        local scale = self.db.profile.ui.scale or 0.9
        DRE.UI.mainWindow.frame:SetScale(scale)
    end
end


function DRE:ResetWindowPosition()
    self.db.profile.ui.framePos = {
        point = "CENTER",
        x = 0,
        y = 0,
    }
    self:Print("Window position reset to center")
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
    -- Handle fallback mode (watching for challenge acceptance)
    if self.fallbackChallenge then
        local playerName, maxRoll, rollResult = message:match("(%S+) rolls 1%-(%d+) %((%d+)%)")
        
        if playerName and rollResult and maxRoll then
            if playerName == self.fallbackChallenge.target then
                local currentRoll = tonumber(rollResult)
                local expectedRoll = self.fallbackChallenge.roll
                
                if tonumber(maxRoll) == expectedRoll then
                    self:ChatPrint(playerName .. " accepted! They rolled " .. currentRoll .. " (1-" .. expectedRoll .. ")")
                    
                    if currentRoll == 1 then
                        self:ChatPrint(playerName .. " rolled 1 and lost! You won!")
                        self:HandleGameEnd(playerName, "WIN", self.fallbackChallenge.wager, expectedRoll)
                    else
                        self:ChatPrint("Challenge accepted! Now you roll 1-" .. (currentRoll - 1))
                        self:StartActualGame(playerName, expectedRoll, self.fallbackChallenge.wager, currentRoll - 1)
                    end
                    self:StopFallbackMode()
                    return
                end
            end
        end
    end
    
    -- Handle active game rolls
    if self.gameState and self.gameState.isActive then
        local playerName, maxRoll, rollResult = message:match("(%S+) rolls 1%-(%d+) %((%d+)%)")
        
        if playerName and rollResult and maxRoll then
            local roll = tonumber(rollResult)
            local maxRollNum = tonumber(maxRoll)
            
            -- Check if this roll is relevant to our game
            if (playerName == UnitName("player") or playerName == self.gameState.target) and
               maxRollNum <= self.gameState.currentRoll + 1 then -- Allow some tolerance
                self:HandleGameRoll(playerName, roll, maxRollNum)
            end
        end
    end
end

function DRE:ADDON_LOADED(event, addonName)
    if addonName == "DeathRollEnhancer" then
        self:UnregisterEvent("ADDON_LOADED")
    end
end

-- Handle whisper messages for spicy duels and fallback challenges
function DRE:CHAT_MSG_WHISPER(event, message, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
    -- Handle Spicy Duel acceptance
    if message:lower():find("accept spicy") and self.spicyDuel and self.spicyDuel.target == playerName then
        self:ChatPrint(playerName .. " accepted your Spicy Duel challenge!")
        self:UpdateSpicyGameState("Challenge accepted! Round 1: Choose your stance! (HP: You 150, " .. playerName .. " 150)")
        
        -- Send confirmation
        SendChatMessage("Challenge accepted! Let the Spicy Duel begin! Choose your stance and roll!", "WHISPER", nil, playerName)
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
function DRE:CHAT_MSG_ADDON(event, prefix, message, channel, sender)
    if prefix ~= "DeathRollEnh" then
        return
    end
    
    -- Parse addon message
    local msgType, data = message:match("^([^:]+):(.*)$")
    if not msgType then
        return
    end
    
    if msgType == "CHALLENGE" then
        self:HandleAddonChallenge(sender, data, channel)
    elseif msgType == "PING" then
        self:HandleAddonPing(sender, data, channel)
    elseif msgType == "PONG" then
        self:HandleAddonPong(sender, data, channel)
    elseif msgType == "ACCEPT" then
        self:HandleAddonAccept(sender, data, channel)
    elseif msgType == "DECLINE" then
        self:HandleAddonDecline(sender, data, channel)
    elseif msgType == "SPICYDUEL" then
        self:HandleSpicyDuelMessage(sender, data)
    end
end

-- Send addon message to a player
function DRE:SendAddonMessage(msgType, data, target)
    local message = msgType .. ":" .. (data or "")
    local success = C_ChatInfo.SendAddonMessage("DeathRollEnh", message, "WHISPER", target)
    return success
end

-- Handle addon challenge received
function DRE:HandleAddonChallenge(sender, data, channel)
    local roll, wager, challengeText = data:match("^(%d+):(%d+):(.*)$")
    if roll and wager and challengeText then
        self:ShowChallengeDialog(sender, tonumber(roll), tonumber(wager), challengeText)
    end
end

-- Handle addon ping (for detection)
function DRE:HandleAddonPing(sender, data, channel)
    -- Respond with pong to confirm we have the addon
    self:SendAddonMessage("PONG", self.version, sender)
end

-- Handle addon pong (confirms they have addon)
function DRE:HandleAddonPong(sender, version, channel)
    -- Mark player as having addon
    if self.UI and self.UI.pendingChallenge and self.UI.pendingChallenge.target == sender then
        self.UI.pendingChallenge.hasAddon = true
        self:DebugPrint(sender .. " has DeathRoll Enhancer (v" .. version .. ") - sending enhanced challenge...")
        
        -- Send addon challenge message with structured data
        local challenge = self.UI.pendingChallenge
        local challengeText = challenge.wager > 0 and
            ("DeathRoll challenge: " .. challenge.roll .. " starting roll for " .. self:FormatGold(challenge.wager)) or
            ("DeathRoll challenge: " .. challenge.roll .. " starting roll (no wager)")
            
        self:SendAddonMessage("CHALLENGE", 
            challenge.roll .. ":" .. challenge.wager .. ":" .. challengeText, 
            sender)
    end
end

-- Check if addon response received, otherwise assume no addon
function DRE:CheckAddonResponse(target)
    if not self.UI or not self.UI.pendingChallenge or self.UI.pendingChallenge.target ~= target then
        return
    end
    
    local challenge = self.UI.pendingChallenge
    
    if challenge.hasAddon then
        -- They have the addon, enhanced challenge already sent
        self:ChatPrint("Waiting for " .. target .. "'s response to enhanced challenge...")
    else
        -- No addon detected, send natural challenge and watch for rolls
        self:DebugPrint(target .. " doesn't have the addon - sending natural challenge...")
        
        -- Send natural challenge message
        local message
        if challenge.wager > 0 then
            local wagerText = self:FormatGold(challenge.wager)
            message = "I challenge you to a DeathRoll! Starting at " .. challenge.roll .. " for " .. wagerText .. "!"
        else
            message = "I challenge you to a DeathRoll! Starting at " .. challenge.roll .. " (no wager)"
        end
        
        SendChatMessage(message, "WHISPER", nil, target)
        self:StartFallbackMode(challenge)
    end
end

-- Start fallback mode for non-addon users  
function DRE:StartFallbackMode(challenge)
    self:DebugPrint("Fallback mode: Watching " .. challenge.target .. " for /roll " .. challenge.roll)
    
    -- Store the fallback challenge for monitoring
    self.fallbackChallenge = challenge
    self.fallbackChallenge.startTime = GetTime()
    self.fallbackChallenge.timeout = 60 -- 60 second timeout
    
    -- NOTE: Natural whisper message is already sent by CheckAddonResponse, no need to send again
    
    -- Register for system messages to watch for rolls
    if not self.watchingFallbackRolls then
        self:RegisterEvent("CHAT_MSG_SYSTEM")
        self.watchingFallbackRolls = true
    end
    
    -- Start timeout timer
    C_Timer.After(self.fallbackChallenge.timeout, function()
        if self.fallbackChallenge and self.fallbackChallenge.target == challenge.target then
            self:ChatPrint("Challenge to " .. challenge.target .. " timed out (no response)")
            self:StopFallbackMode()
        end
    end)
end

-- Stop fallback mode
function DRE:StopFallbackMode()
    self.fallbackChallenge = nil
    if self.watchingFallbackRolls then
        self:UnregisterEvent("CHAT_MSG_SYSTEM")
        self.watchingFallbackRolls = false
    end
end

-- Handle system messages for fallback roll watching
function DRE:CHAT_MSG_SYSTEM(event, message)
    if not self.fallbackChallenge then
        return
    end
    
    -- Look for roll patterns: "PlayerName rolls 1-100 (42)"
    local playerName, maxRoll, rollResult = message:match("(%S+) rolls 1%-(%d+) %((%d+)%)")
    
    if playerName and rollResult and maxRoll then
        -- Check if this is from our challenged player
        if playerName == self.fallbackChallenge.target then
            local currentRoll = tonumber(rollResult)
            local expectedRoll = self.fallbackChallenge.roll
            
            -- Check if they rolled the expected starting number
            if tonumber(maxRoll) == expectedRoll then
                -- They rolled within the expected range, challenge accepted
                self:ChatPrint(playerName .. " accepted! They rolled " .. currentRoll .. " (1-" .. expectedRoll .. ")")
                
                if currentRoll == 1 then
                    self:ChatPrint(playerName .. " rolled 1 and lost! You won!")
                    -- Handle win
                    self:HandleGameEnd(playerName, "WIN", self.fallbackChallenge.wager, expectedRoll)
                else
                    self:ChatPrint("Challenge accepted! Now you roll 1-" .. (currentRoll - 1))
                    -- Start actual game
                    self:StartActualGame(playerName, expectedRoll, self.fallbackChallenge.wager, currentRoll)
                end
                self:StopFallbackMode()
            end
        end
    end
end

-- Handle addon accept response
function DRE:HandleAddonAccept(sender, data, channel)
    local roll, wager = data:match("^(%d+):(%d+)$")
    if roll and wager then
        roll = tonumber(roll)
        wager = tonumber(wager)
        self:ChatPrint(sender .. " accepted your DeathRoll challenge!")
        
        -- Start the actual game
        self:StartActualGame(sender, roll, wager)
    end
end

-- Handle addon decline response  
function DRE:HandleAddonDecline(sender, data, channel)
    self:ChatPrint(sender .. " declined your DeathRoll challenge.")
    
    -- Clear challenge state
    if self.UI and self.UI.pendingChallenge then
        self.UI.pendingChallenge = nil
    end
    
    if self.UI and self.UI.statusLabel then
        self.UI.statusLabel:SetText("Ready to roll!")
    end
end

-- Conditional print that respects chat messages setting
function DRE:ChatPrint(message)
    if self.db and self.db.profile.gameplay.chatMessages then
        self:Print(message)
    end
end

-- Conditional print that respects debug messages setting
function DRE:DebugPrint(message)
    if self.db and self.db.profile.gameplay.debugMessages then
        self:Print("[DEBUG] " .. message)
    end
end

-- Main function to start a DeathRoll challenge (called from UI)
function DRE:StartDeathRoll(target, roll, wager)
    -- Validate inputs
    if not target or target == "" then
        self:Print("Invalid target player!")
        return
    end
    
    -- Validate that target is a real player name (basic check)
    local playerName = UnitName("player")
    if target ~= playerName then
        -- For non-self duels, perform additional validation
        -- Check if the name looks like a player name (not too long, reasonable characters)
        if string.len(target) > 12 or string.len(target) < 2 then
            self:Print("Invalid player name: " .. target)
            return
        end
        
        -- Basic character validation (letters, some special characters)
        if not target:match("^[%a%s'-]+$") then
            self:Print("Invalid player name format: " .. target)
            return
        end
    end
    
    if not roll or roll < 2 then
        self:Print("Roll must be at least 2!")
        return
    end
    
    if not wager or wager < 0 then
        self:Print("Invalid wager amount!")
        return
    end
    
    -- Check for self-dueling
    if target == playerName then
        self:Print("Starting self-duel! You'll play against yourself.")
        
        -- Start the actual game immediately for self-dueling
        self:StartActualGame(target, roll, wager)
        
        -- Update UI state to rolling
        if self.UpdateGameUIState then
            self:UpdateGameUIState("ROLLING")
        end
        return
    end
    
    -- Create challenge object for other players
    local challenge = {
        target = target,
        roll = roll,
        wager = wager,
        timestamp = time()
    }
    
    -- Update UI state
    if self.UI then
        self.UI.isGameActive = true
        self.UI.gameState = "ROLLING"
        if self.UI.statusLabel then
            local statusText = wager > 0 and 
                string.format("Challenging %s: %d starting roll, %s wager", target, roll, self:FormatGold(wager)) or
                string.format("Challenging %s: %d starting roll, no wager", target, roll)
            self.UI.statusLabel:SetText(statusText)
        end
    end
    
    self:ChatPrint("Challenging " .. target .. " to a DeathRoll...")
    
    -- Start the hybrid challenge process (addon detection + challenge)
    self:SendChallenge(challenge)
end

-- Send challenge using hybrid detection system
function DRE:SendChallenge(challenge)
    -- Store challenge data for timeout handling
    if self.UI then
        self.UI.pendingChallenge = {
            target = challenge.target,
            roll = challenge.roll,
            wager = challenge.wager,
            timestamp = GetTime(),
            hasAddon = false
        }
    end
    
    -- First, try to detect if target has addon by sending ping
    self:SendAddonMessage("PING", self.version, challenge.target)
    self:DebugPrint("Checking if " .. challenge.target .. " has DeathRoll Enhancer addon...")
    
    -- Set up 3-second timeout to check if they have addon
    C_Timer.After(3, function()
        self:CheckAddonResponse(challenge.target)
    end)
end

-- Create reset confirmation popup
StaticPopupDialogs["DEATHROLL_RESET_CONFIRM"] = {
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

-- Start the actual DeathRoll game
function DRE:StartActualGame(target, initialRoll, wager, currentRoll)
    local myName = UnitName("player")
    local isSelfDuel = (target == myName)
    
    -- Initialize game state
    self.gameState = {
        isActive = true,
        target = target,
        initialRoll = initialRoll,
        currentRoll = currentRoll or initialRoll,
        wager = wager or 0,
        playerTurn = true,
        rollCount = isSelfDuel and 0 or nil  -- Initialize roll counter for self-duels
    }
    
    -- Clear fallback challenge since we're starting the actual game
    self.fallbackChallenge = nil
    
    -- Clear pending challenge
    if self.UI and self.UI.pendingChallenge then
        self.UI.pendingChallenge = nil
    end
    
    self:ChatPrint("DeathRoll game started with " .. target .. "!")
    
    -- If currentRoll is different from initialRoll, it means opponent already rolled
    if currentRoll and currentRoll ~= initialRoll then
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
    if not self.watchingFallbackRolls then
        self:RegisterEvent("CHAT_MSG_SYSTEM")
        self.watchingFallbackRolls = true
    end
end

-- Handle game end
function DRE:HandleGameEnd(loser, result, wager, initialRoll)
    local playerName = UnitName("player")
    local won = (result == "WIN")
    
    if won then
        self:Print("🎉 You WON the DeathRoll!")
        if self.db and self.db.profile.gameplay.autoEmote then
            DoEmote(self:GetRandomHappyEmote())
        end
    else
        self:Print("💀 You LOST the DeathRoll!")
        if self.db and self.db.profile.gameplay.autoEmote then
            DoEmote(self:GetRandomSadEmote())
        end
    end
    
    -- Record the game result
    if loser and loser ~= playerName then
        -- We won against the loser
        self:AddGameToHistory(loser, "Won", wager or 0, initialRoll or 0)
    elseif loser == playerName then
        -- We lost to the target
        local target = self.gameState and self.gameState.target or "Unknown"
        self:AddGameToHistory(target, "Lost", wager or 0, initialRoll or 0)
    end
    
    -- Clean up game state
    self.gameState = nil
    self.fallbackChallenge = nil
    
    -- Clean up event watching
    if self.watchingFallbackRolls then
        self:UnregisterEvent("CHAT_MSG_SYSTEM") 
        self.watchingFallbackRolls = false
    end
    
    if self.UI then
        self.UI.pendingChallenge = nil
        self.UI.isGameActive = false
        self.UI.currentTarget = nil
    end
    
    -- Update UI state to game over
    if self.UpdateGameUIState then
        self:UpdateGameUIState("GAME_OVER")
    end
    
    -- Update stats display
    if self.UpdateStatsDisplay then
        self:UpdateStatsDisplay()
    end
end

-- Handle ongoing game rolls
function DRE:HandleGameRoll(playerName, roll, maxRoll)
    if not self.gameState or not self.gameState.isActive then
        return
    end
    
    local myName = UnitName("player")
    local isSelfDuel = (self.gameState.target == myName)
    
    -- Only process rolls from the player if it's a regular duel or self-duel
    if playerName == myName then
        if isSelfDuel then
            -- Increment roll counter
            self.gameState.rollCount = self.gameState.rollCount + 1
            
            -- Self-duel: every roll alternates the game state
            self:ChatPrint("Roll " .. self.gameState.rollCount .. ": " .. roll .. " (1-" .. maxRoll .. ")")
            
            if roll == 1 then
                -- Game over - determine winner/loser based on roll count
                if (self.gameState.rollCount % 2) == 1 then
                    self:ChatPrint("You lost your self-duel! (Rolled 1 on turn " .. self.gameState.rollCount .. ")")
                    self:HandleGameEnd(myName, "LOSS", self.gameState.wager, self.gameState.initialRoll)
                else
                    self:ChatPrint("You won your self-duel! (Your opponent-self rolled 1 on turn " .. self.gameState.rollCount .. ")")
                    self:HandleGameEnd(myName, "WIN", self.gameState.wager, self.gameState.initialRoll)
                end
            else
                -- Continue game
                self.gameState.currentRoll = roll - 1
                self.gameState.playerTurn = not self.gameState.playerTurn
                
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
            self:ChatPrint("You rolled " .. roll .. " (1-" .. maxRoll .. ")")
            
            if roll == 1 then
                -- We lost
                self:HandleGameEnd(myName, "LOSS", self.gameState.wager, self.gameState.initialRoll)
            else
                -- Continue game, opponent's turn
                self.gameState.currentRoll = roll - 1
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
        self:ChatPrint(playerName .. " rolled " .. roll .. " (1-" .. maxRoll .. ")")
        
        if roll == 1 then
            -- They lost, we won
            self:HandleGameEnd(playerName, "WIN", self.gameState.wager, self.gameState.initialRoll)
        else
            -- Continue game, our turn
            self.gameState.currentRoll = roll - 1
            self.gameState.playerTurn = true
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
    SendChatMessage(message, "WHISPER", nil, target)
    
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
    
    -- Send stance and roll to opponent via addon message or whisper
    local message = "SPICY_STANCE:" .. stance .. ":" .. roll
    if self:SendAddonMessage("SPICYDUEL", message, self.spicyDuel.target) then
        self:DebugPrint("Sent spicy stance via addon message")
    else
        -- Fallback to whisper
        SendChatMessage("My stance: " .. stance .. " (roll: " .. roll .. ")", "WHISPER", nil, self.spicyDuel.target)
    end
    
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
        self:Print("🤝 Double KO! What an epic battle!")
        self:EndSpicyDuel()
    elseif self.spicyDuel.myHP <= 0 then
        self:Print("💀 You lost the Spicy Duel! " .. self.spicyDuel.target .. " is victorious!")
        self:EndSpicyDuel()
    elseif self.spicyDuel.opponentHP <= 0 then
        self:Print("🎉 You won the Spicy Duel! Excellent strategy!")
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
    
    -- Validate gameButton exists
    if not self.UI.gameButton then
        self:DebugPrint("No gameButton found in UI - UI may not be fully initialized")
        return
    end
        
        if state == "WAITING" then
            self:SafeUIUpdate(self.UI.gameButton, function()
                self.UI.gameButton:SetText("Challenge to DeathRoll!")
                self.UI.gameButton:SetDisabled(false)
            end, "gameButton")
            
            self:SafeUIUpdate(self.UI.statusLabel, function()
                self.UI.statusLabel:SetText("Ready to roll!")
            end, "statusLabel")
            
        elseif state == "WAITING_FOR_ACCEPTANCE" then
            local target = self.UI.currentTarget or "player"
            self.UI.gameButton:SetText("Waiting for " .. target .. " to accept...")
            self.UI.gameButton:SetDisabled(true)
            if self.UI.statusLabel then
                self.UI.statusLabel:SetText("Challenge sent to " .. target)
            end
            
        elseif state == "ROLLING" then
            local rollRange = self.gameState and self.gameState.currentRoll or 100
            self.UI.gameButton:SetText("Roll 1-" .. rollRange)
            self.UI.gameButton:SetDisabled(false)
            if self.UI.statusLabel then
                self.UI.statusLabel:SetText("Your turn! Click to roll!")
            end
            -- Update the roll input to show the current range
            if self.UI.rollEdit then
                self:DebugPrint("Updating roll input to: " .. rollRange)
                self.UI.rollEdit:SetText(tostring(rollRange))
            else
                self:DebugPrint("No rollEdit found in UI")
            end
            
        elseif state == "WAITING_FOR_OPPONENT" then
            local target = self.UI.currentTarget or "opponent"
            self.UI.gameButton:SetText("Waiting for " .. target .. "...")
            self.UI.gameButton:SetDisabled(true)
            if self.UI.statusLabel then
                self.UI.statusLabel:SetText(target .. "'s turn to roll")
            end
            
        elseif state == "WAITING_FOR_ROLL_RESULT" then
            self.UI.gameButton:SetText("Rolling...")
            self.UI.gameButton:SetDisabled(true)
            if self.UI.statusLabel then
                self.UI.statusLabel:SetText("Rolling dice...")
            end
            
        elseif state == "GAME_OVER" then
            self.UI.gameButton:SetText("Challenge to DeathRoll!")
            self.UI.gameButton:SetDisabled(false)
            if self.UI.statusLabel then
                self.UI.statusLabel:SetText("Game finished! Ready for another?")
            end
            -- Reset UI state after a short delay
            C_Timer.After(3, function()
                if self.UI.gameState == "GAME_OVER" then
                    self:UpdateGameUIState("WAITING")
                end
            end)
        end
    else
        self:DebugPrint("No UI table found")
    end
end

-- Make the addon globally accessible
_G.DeathRollEnhancer = DRE