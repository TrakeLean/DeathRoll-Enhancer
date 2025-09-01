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
            scale = 1.0,
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
    
    -- Register game-related events
    self:RegisterGameEvents()
    
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
                name = "General Settings",
                type = "group",
                order = 1,
                args = {
                    header = {
                        name = "DeathRoll Enhancer v" .. self.version,
                        type = "header",
                        order = 0,
                    },
                    autoEmote = {
                        name = "Auto Emote",
                        desc = "Automatically perform emotes on win/loss",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.autoEmote end,
                        set = function(_, val) self.db.profile.gameplay.autoEmote = val end,
                        order = 1,
                    },
                    soundEnabled = {
                        name = "Sound Effects",
                        desc = "Enable sound effects",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.soundEnabled end,
                        set = function(_, val) self.db.profile.gameplay.soundEnabled = val end,
                        order = 2,
                    },
                    trackGold = {
                        name = "Track Gold",
                        desc = "Track gold won and lost",
                        type = "toggle",
                        get = function() return self.db.profile.gameplay.trackGold end,
                        set = function(_, val) self.db.profile.gameplay.trackGold = val end,
                        order = 3,
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
                        order = 4,
                    },
                },
            },
            ui = {
                name = "Interface",
                type = "group",
                order = 2,
                args = {
                    header = {
                        name = "Interface Settings",
                        type = "header",
                        order = 0,
                    },
                    scale = {
                        name = "UI Scale",
                        desc = "Adjust the scale of the DeathRoll window",
                        type = "range",
                        min = 0.5,
                        max = 2.0,
                        step = 0.1,
                        bigStep = 0.1,
                        get = function() return self.db.profile.ui.scale end,
                        set = function(_, val) 
                            self.db.profile.ui.scale = val
                            self:UpdateUIScale()
                        end,
                        order = 1,
                    },
                    resetPosition = {
                        name = "Reset Window Position",
                        desc = "Reset the DeathRoll window to center of screen",
                        type = "execute",
                        func = function() self:ResetWindowPosition() end,
                        order = 2,
                    },
                    separator1 = {
                        name = "",
                        type = "header",
                        order = 3,
                    },
                    uiFont = {
                        name = "UI Font",
                        desc = "Choose the font for the DeathRoll interface",
                        type = "select",
                        values = function()
                            if LSM then
                                return LSM:HashTable("font")
                            else
                                return {
                                    ["Friz Quadrata TT"] = "Friz Quadrata TT",
                                    ["Skurri"] = "Skurri", 
                                    ["morpheus"] = "Morpheus",
                                    ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
                                }
                            end
                        end,
                        get = function() return self.db.profile.ui.font or "Friz Quadrata TT" end,
                        set = function(_, val) 
                            self.db.profile.ui.font = val
                            self:UpdateUIFont()
                        end,
                        order = 4,
                    },
                },
            },
            minimap = {
                name = "Minimap",
                type = "group",
                order = 3,
                args = {
                    hide = {
                        name = "Hide Minimap Icon",
                        desc = "Hide the minimap icon",
                        type = "toggle",
                        get = function() return self.db.profile.minimap.hide end,
                        set = function(_, val) 
                            self.db.profile.minimap.hide = val
                            self:ToggleMinimapIcon()
                        end,
                        order = 1,
                    },
                },
            },
            data = {
                name = "Data Management",
                type = "group",
                order = 4,
                args = {
                    header = {
                        name = "Data and Statistics",
                        type = "header",
                        order = 0,
                    },
                    stats = {
                        name = "Show Statistics",
                        desc = "Display current statistics",
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
                        order = 1,
                    },
                    separator1 = {
                        name = "",
                        type = "header",
                        order = 2,
                    },
                    cleanOldData = {
                        name = "Clean Old Data",
                        desc = "Remove game records older than 30 days",
                        type = "execute",
                        func = function() 
                            self:CleanOldData(30)
                        end,
                        order = 3,
                    },
                    resetData = {
                        name = "Reset All Data",
                        desc = "WARNING: This will permanently delete all DeathRoll history and statistics!",
                        type = "execute",
                        func = function() 
                            StaticPopup_Show("DEATHROLL_RESET_CONFIRM")
                        end,
                        order = 4,
                    },
                    exportData = {
                        name = "Export Data",
                        desc = "Export your DeathRoll data for backup",
                        type = "execute",
                        func = function()
                            local exportString = self:ExportData()
                            -- Create a simple text display frame
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
                        order = 5,
                    },
                },
            },
            statistics = {
                name = "Fun Statistics",
                type = "group",
                order = 5,
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
        local scale = self.db.profile.ui.scale or 1.0
        DRE.UI.mainWindow.frame:SetScale(scale)
    end
end

function DRE:UpdateUIFont()
    -- Update font for UI elements
    if not self.db or not self.db.profile.ui.font then
        return
    end
    
    local fontName = self.db.profile.ui.font
    local fontSize = 12
    local fontFlags = ""
    
    -- Get the actual font path if using LibSharedMedia
    local fontPath = fontName
    if LSM and LSM:IsValid("font", fontName) then
        fontPath = LSM:Fetch("font", fontName)
    end
    
    -- Update main window if it exists
    if UI and UI.mainWindow and UI.mainWindow.frame then
        -- Update the main window title font
        if UI.mainWindow.frame.titletext then
            UI.mainWindow.frame.titletext:SetFont(fontPath, 14, fontFlags)
        end
        
        -- Update status text font
        if UI.mainWindow.frame.statustext then
            UI.mainWindow.frame.statustext:SetFont(fontPath, 10, fontFlags)
        end
    end
    
    -- Update other UI elements if they exist
    if UI.statsLabel and UI.statsLabel.label then
        UI.statsLabel.label:SetFont(fontPath, fontSize, fontFlags)
    end
    
    if UI.streakLabel and UI.streakLabel.label then
        UI.streakLabel.label:SetFont(fontPath, fontSize, fontFlags)
    end
    
    if UI.funStatsLabel and UI.funStatsLabel.label then
        UI.funStatsLabel.label:SetFont(fontPath, fontSize, fontFlags)
    end
    
    if UI.historyBox and UI.historyBox.editBox then
        UI.historyBox.editBox:SetFont(fontPath, fontSize, fontFlags)
    end
    
    -- Note: Most AceGUI widgets manage their own fonts and would need to be recreated
    -- to properly apply new fonts. For a complete font change, the user should close
    -- and reopen the main window.
    
    self:Print("Font updated to: " .. fontName .. ". Close and reopen the main window (/dr) to see all changes.")
end

function DRE:ResetWindowPosition()
    self.db.profile.ui.framePos = {
        point = "CENTER",
        x = 0,
        y = 0,
    }
    self:Print("Window position reset to center")
end

function DRE:ToggleMinimapIcon()
end

-- Module initialization methods
function DRE:InitializeUI()
end

function DRE:InitializeMinimap()
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

-- Event handlers
function DRE:CHAT_MSG_SYSTEM(event, message)
end

function DRE:ADDON_LOADED(event, addonName)
    if addonName == "DeathRollEnhancer" then
        self:UnregisterEvent("ADDON_LOADED")
    end
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

-- Make the addon globally accessible
_G.DeathRollEnhancer = DRE