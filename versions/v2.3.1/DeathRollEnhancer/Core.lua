-- Core.lua
-- Main addon initialization using Ace3 framework

local addonName, addonTable = ...

-- Declare saved variables for debug export
DeathRollEnhancer_DebugExport = DeathRollEnhancer_DebugExport or {}

-- Check for required libraries
if not LibStub then
    error("DeathRollEnhancer requires LibStub")
    return
end

-- Initialize addon with Ace3
local DRE = LibStub("AceAddon-3.0"):NewAddon("DeathRollEnhancer", "AceConsole-3.0", "AceEvent-3.0")

-- TBC Compatibility: C_Timer shim for older WoW versions
if not C_Timer then
    C_Timer = {
        After = function(duration, callback)
            -- Fallback implementation using frame OnUpdate for TBC/Classic
            local waitFrame = CreateFrame("Frame")
            local elapsed = 0
            waitFrame:SetScript("OnUpdate", function(self, delta)
                elapsed = elapsed + delta
                if elapsed >= duration then
                    callback()
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    }
end

-- Debug chat buffer to track messages
DRE.debugChatBuffer = {}
DRE.maxDebugMessages = 40

-- Addon information
DRE.version = "2.3.1"
DRE.author = "EgyptianSheikh"

-- Utility: safe trim for user input (WoW Lua doesn't provide string:trim())
function DRE:Trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

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
            frameWidth = 400,
            frameHeight = 300,
        },
        gameplay = {
            autoEmote = true,
            soundEnabled = true,
            trackGold = true,
            autoRollFromMoney = false,
            chatMessages = false,
            debugMessages = false,
        },
        challengeSystem = {
            enabled = true,
            sendWhisper = true,
            minRollThreshold = 100,
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

    -- Initialize recent rolls storage for challenge detection
    self.recentRolls = {}
    self.maxRecentRolls = 10
    self.recentRollTimeWindow = 60 -- seconds

    -- Initialize processed rolls cache to prevent duplicate processing
    self.processedRolls = {}
    self.processedRollsExpiry = 5 -- seconds to remember a processed roll

    -- Register options
    self:SetupOptions()

    -- Register slash commands
    self:RegisterChatCommand("deathroll", "SlashCommand")
    self:RegisterChatCommand("dr", "SlashCommand")
    self:RegisterChatCommand("drh", "HistoryCommand")
    self:RegisterChatCommand("deathrollhistory", "HistoryCommand")

    self:Print("DeathRoll Enhancer v" .. self.version .. " loaded!")

    -- Test debug buffer
    self:AddToDebugBuffer("SYSTEM", "Addon loaded and debug buffer initialized")
end

function DRE:OnEnable()
    self:DebugPrint("OnEnable called - registering events...")
    
    -- Register core events
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("ADDON_LOADED")
    
    -- Register game-related events (CHAT_MSG_WHISPER for spicy duels)
    self:RegisterEvent("CHAT_MSG_WHISPER")
    
    -- Register additional events that might carry roll messages
    self:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
    self:RegisterEvent("CHAT_MSG_EMOTE")
    
    -- Register target change event to update button text
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    
    self:DebugPrint("Events registered: CHAT_MSG_SYSTEM, ADDON_LOADED, CHAT_MSG_ADDON, CHAT_MSG_WHISPER, CHAT_MSG_TEXT_EMOTE, CHAT_MSG_EMOTE")
    
    -- Initialize modules
    self:InitializeUI()
    self:InitializeMinimap()
    self:InitializeSharedMedia()
end

function DRE:OnDisable()
    -- Cleanup active game state
    if self.gameState and self.gameState.isActive then
        self:DebugPrint("OnDisable: Cleaning up active game state")
        self.gameState = nil
    end

    -- Cleanup spicy duel state
    if self.spicyDuel and self.spicyDuel.isActive then
        self:DebugPrint("OnDisable: Cleaning up active spicy duel state")
        self.spicyDuel = nil
    end

    -- Clear UI references
    if self.UI then
        self.UI.recentTargetRoll = nil
        self.UI.incomingChallenge = nil
        self.UI.isGameActive = false
    end

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

-- Challenge System: Send whisper challenge to opponent
function DRE:SendChallengeWhisper(targetName, roll, wager)
    if not self.db or not self.db.profile.challengeSystem then
        return
    end

    if not self.db.profile.challengeSystem.sendWhisper then
        self:DebugPrint("Challenge whisper disabled in settings")
        return
    end

    -- Format: DEATHROLL_CHALLENGE:roll:wager:version
    local message = string.format("DEATHROLL_CHALLENGE:%d:%d:%s", roll, wager, self.version)
    SendChatMessage(message, "WHISPER", nil, targetName)

    self:DebugPrint(string.format("Sent challenge whisper to %s: roll=%d, wager=%d", targetName, roll, wager))
end

-- Challenge System: Handle incoming challenge whisper
function DRE:HandleChallengeWhisper(message, sender)
    if not self.db or not self.db.profile.challengeSystem then
        return
    end

    if not self.db.profile.challengeSystem.enabled then
        self:DebugPrint("Challenge system disabled in settings")
        return
    end

    -- Don't show challenge if already in a game
    if self.gameState and self.gameState.isActive then
        self:DebugPrint("Already in active game, ignoring challenge from " .. sender)
        return
    end

    -- Parse challenge message: DEATHROLL_CHALLENGE:roll:wager:version
    local roll, wager, version = message:match(self.CHAT_PATTERNS.DEATHROLL_CHALLENGE_NEW)
    if not roll or not wager then
        self:DebugPrint("Failed to parse challenge message: " .. message)
        return
    end

    roll = tonumber(roll)
    wager = tonumber(wager)

    -- Validate roll against minimum threshold
    if roll < self.db.profile.challengeSystem.minRollThreshold then
        self:DebugPrint(string.format("Challenge roll %d below threshold %d, ignoring",
            roll, self.db.profile.challengeSystem.minRollThreshold))
        return
    end

    -- Store challenge data
    self.pendingChallenge = {
        sender = sender,
        roll = roll,
        wager = wager,
        timestamp = time()
    }

    -- Show popup dialog with challenge data
    local dialog = StaticPopup_Show("DEATHROLL_CHALLENGE_POPUP")
    if dialog then
        dialog.data = self.pendingChallenge
    end

    self:DebugPrint(string.format("Received challenge from %s: roll=%d, wager=%d", sender, roll, wager))
end

-- Challenge System: Accept incoming challenge
function DRE:AcceptChallenge()
    if not self.pendingChallenge then
        self:Print("No pending challenge!")
        return
    end

    local challenge = self.pendingChallenge
    self.pendingChallenge = nil

    -- Send accept whisper
    SendChatMessage("DEATHROLL_ACCEPT", "WHISPER", nil, challenge.sender)

    -- Target the challenger
    TargetByName(challenge.sender, true)

    -- Open main window and pre-fill with challenge data
    self:ShowMainWindow()

    -- Set roll value
    if self.UI and self.UI.rollEdit then
        self.UI.rollEdit:SetText(tostring(challenge.roll))
    end

    -- Set wager value
    if challenge.wager > 0 then
        local gold = math.floor(challenge.wager / 10000)
        local silver = math.floor((challenge.wager % 10000) / 100)
        local copper = challenge.wager % 100

        if self.UI then
            if self.UI.goldEdit then self.UI.goldEdit:SetText(tostring(gold)) end
            if self.UI.silverEdit then self.UI.silverEdit:SetText(tostring(silver)) end
            if self.UI.copperEdit then self.UI.copperEdit:SetText(tostring(copper)) end
        end
    end

    self:Print(string.format("Accepted challenge from %s! Roll: %d, Wager: %s",
        challenge.sender, challenge.roll, self:FormatGold(challenge.wager)))
end

-- Challenge System: Decline incoming challenge
function DRE:DeclineChallenge()
    if not self.pendingChallenge then
        return
    end

    local challenge = self.pendingChallenge
    self.pendingChallenge = nil

    -- Send decline whisper
    SendChatMessage("DEATHROLL_DECLINE", "WHISPER", nil, challenge.sender)

    self:Print(string.format("Declined challenge from %s", challenge.sender))
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
    local nemesisPlayer, nemesisWinRate = nil, -1  -- Start at -1 so 0% is valid
    local victimPlayer, victimWinRate = nil, 2     -- Start at 2 (200%) so 100% is valid
    local highRollerPlayer, highRollerAvg = nil, 0
    local cheapskatePlayer, cheapskateAvg = nil, math.huge
    local luckyPlayer, luckyWinRate = nil, -1      -- Start at -1 so 0% is valid
    local unluckyPlayer, unluckyWinRate = nil, 2   -- Start at 2 (200%) so 100% is valid
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
                    if game.initialRoll and game.initialRoll > 0 then
                        totalStartRoll = totalStartRoll + game.initialRoll
                        rollCount = rollCount + 1
                    end
                end
                
                -- Calculate average wager
                if wagerCount > 0 then
                    local avgWager = math.floor(totalWager / wagerCount)
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
    if not input or self:Trim(input) == "" then
        self:ShowMainWindow()
    elseif input == "config" or input == "options" then
        self:OpenOptions()
    elseif input == "debug" then
        self:Print("Debug command triggered - dumping buffer...")
        self:DumpDebugBuffer()
    elseif input == "accept" then
        self:Print("No pending challenge to accept")
    elseif input == "decline" then
        self:Print("No pending challenge to decline")
    elseif input == "edit" then
        self:ShowEditGameDialog()
    elseif input == "fixgold" then
        local success, message = self:RecalculateGoldTracking()
        if success then
            self:Print("Gold tracking fixed: " .. message)
        else
            self:Print("Failed to fix gold tracking: " .. message)
        end
    else
        self:Print("Usage: /dr or /deathroll - Opens the main window")
        self:Print("       /dr config - Opens configuration")
        self:Print("       /dr debug - Show debug chat buffer")
        self:Print("       /dr accept - Accept pending challenge")
        self:Print("       /dr decline - Decline pending challenge")
        self:Print("       /dr edit - Edit recent game records")
        self:Print("       /dr fixgold - Recalculate gold tracking totals")
    end
end

function DRE:HistoryCommand(input)
    local target = input and self:Trim(input) or ""
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
                            -- Update the roll input immediately if UI is open
                            if self.UI and self.UI.rollEdit then
                                if val then
                                    local autoRoll = self:CalculateAutoRoll()
                                    self.UI.rollEdit:SetText(tostring(autoRoll))
                                    self:Print("Auto-roll enabled - roll input set to: " .. autoRoll)
                                else
                                    self.UI.rollEdit:SetText("100")
                                    self:Print("Auto-roll disabled - roll input reset to: 100")
                                end
                            else
                                self:Print("Auto-roll setting changed to: " .. (val and "enabled" or "disabled"))
                            end
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
                    challengeHeader = {
                        name = "Challenge System",
                        type = "header",
                        order = 5.8,
                    },
                    challengeEnabled = {
                        name = "Enable Challenge Popups",
                        desc = "Show a popup when other players with the addon challenge you to a DeathRoll",
                        type = "toggle",
                        get = function() return self.db.profile.challengeSystem.enabled end,
                        set = function(_, val) self.db.profile.challengeSystem.enabled = val end,
                        order = 5.81,
                    },
                    sendWhisper = {
                        name = "Send Challenge Whispers",
                        desc = "Automatically whisper challenge details to your opponent when you start a game. They will see a popup if they have the addon.",
                        type = "toggle",
                        get = function() return self.db.profile.challengeSystem.sendWhisper end,
                        set = function(_, val) self.db.profile.challengeSystem.sendWhisper = val end,
                        order = 5.82,
                    },
                    minRollThreshold = {
                        name = "Minimum Roll for Popups",
                        desc = "Only show challenge popups for rolls above this threshold (prevents spam from low rolls)",
                        type = "range",
                        min = 2,
                        max = 10000,
                        step = 1,
                        bigStep = 100,
                        get = function() return self.db.profile.challengeSystem.minRollThreshold end,
                        set = function(_, val) self.db.profile.challengeSystem.minRollThreshold = val end,
                        order = 5.83,
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
                    resetSize = {
                        name = "Reset Window Size",
                        desc = "Reset the DeathRoll window to default size (400x300)",
                        type = "execute",
                        func = function() self:ResetWindowSize() end,
                        order = 8.5,
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
                    editGame = {
                        name = "Edit Game Records",
                        desc = "Open dialog to edit recent game records",
                        type = "execute",
                        func = function() 
                            self:ShowEditGameDialog()
                        end,
                        order = 15,
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
    -- Clear AceGUI status table position data
    if self.db.profile.ui.frameStatus then
        self.db.profile.ui.frameStatus.left = nil
        self.db.profile.ui.frameStatus.top = nil
        self.db.profile.ui.frameStatus.width = nil
        self.db.profile.ui.frameStatus.height = nil
    end
    
    -- Also reset the currently open window if it exists
    if self.UI and self.UI.mainWindow and self.UI.mainWindow.frame then
        self.UI.mainWindow.frame:ClearAllPoints()
        self.UI.mainWindow.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        self.UI.mainWindow:SetWidth(400)
        self.UI.mainWindow:SetHeight(300)
    end
    
    self:Print("Window position and size reset to defaults")
end

function DRE:ResetWindowSize()
    -- Clear AceGUI status table size data
    if self.db.profile.ui.frameStatus then
        self.db.profile.ui.frameStatus.width = nil
        self.db.profile.ui.frameStatus.height = nil
    end
    
    -- Also resize the currently open window if it exists
    if self.UI and self.UI.mainWindow then
        self.UI.mainWindow:SetWidth(400)
        self.UI.mainWindow:SetHeight(300)
    end
    
    self:Print("Window size reset to default (400x300)")
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
    -- Add to debug buffer
    self:AddToDebugBuffer("CHAT_MSG_SYSTEM", message)
    
    -- Debug: Show all system messages to help identify roll format
    self:DebugPrint("CHAT_MSG_SYSTEM triggered with message: '" .. (message or "nil") .. "'")
    
    -- Use unified processing function for all roll detection
    self:ProcessPotentialRoll(message, nil, "SYSTEM")
end

function DRE:ADDON_LOADED(event, addonName)
    if addonName == "DeathRollEnhancer" then
        self:UnregisterEvent("ADDON_LOADED")
    end
end

-- Handle target change to update button text
function DRE:PLAYER_TARGET_CHANGED(event)
    -- Don't update button during active games to prevent confusion
    if not (self.gameState and self.gameState.isActive) then
        self:UpdateChallengeButtonText()
        -- Also check for recent rolls from the new target
        self:CheckRecentRollsForChallenge()
    end
end

-- Additional event handlers to catch rolls
function DRE:CHAT_MSG_TEXT_EMOTE(event, message, sender)
    self:AddToDebugBuffer("CHAT_MSG_TEXT_EMOTE", (sender or "unknown") .. ": " .. (message or "nil"))
    self:DebugPrint("CHAT_MSG_TEXT_EMOTE: '" .. (message or "nil") .. "' from " .. (sender or "unknown"))
    self:ProcessPotentialRoll(message, sender, "TEXT_EMOTE")
end

function DRE:CHAT_MSG_EMOTE(event, message, sender)
    self:AddToDebugBuffer("CHAT_MSG_EMOTE", (sender or "unknown") .. ": " .. (message or "nil"))
    self:DebugPrint("CHAT_MSG_EMOTE: '" .. (message or "nil") .. "' from " .. (sender or "unknown"))  
    self:ProcessPotentialRoll(message, sender, "EMOTE")
end

-- Unified roll processing function with deduplication
function DRE:ProcessPotentialRoll(message, sender, eventType)
    if not message then return end

    -- Try multiple roll patterns to catch different formats
    local playerName, roll, maxRoll = message:match("^(.+) rolls (%d+) %(1%-(%d+)%)$")  -- Standard pattern
    if not playerName then
        playerName, maxRoll, roll = message:match("^(%S+) rolls 1%-(%d+) %((%d+)%)$")  -- Alternative pattern (anchored)
    end

    if playerName and roll and maxRoll then
        roll = tonumber(roll)
        maxRoll = tonumber(maxRoll)

        -- Handle "You" as player name for self-rolls
        if playerName == "You" then
            playerName = UnitName("player")
        end

        -- Create unique roll identifier
        local rollId = string.format("%s:%d:%d:%.2f", playerName, roll, maxRoll, math.floor(GetTime() * 100) / 100)

        -- Check if we've already processed this roll
        if self:IsRollAlreadyProcessed(rollId) then
            self:DebugPrint("Skipping duplicate roll: " .. rollId)
            return
        end

        -- Mark roll as processed
        self:MarkRollAsProcessed(rollId)

        self:DebugPrint("Detected roll via " .. eventType .. ": " .. playerName .. " rolled " .. roll .. " (1-" .. maxRoll .. ")")

        self:HandleDetectedRoll(playerName, roll, maxRoll)
    else
        self:DebugPrint("Failed to parse roll from message: '" .. (message or "nil") .. "'")
    end
end

-- Check if a roll has already been processed (deduplication)
function DRE:IsRollAlreadyProcessed(rollId)
    if not self.processedRolls then
        self.processedRolls = {}
        return false
    end

    local currentTime = GetTime()

    -- Clean up expired entries
    for id, timestamp in pairs(self.processedRolls) do
        if currentTime - timestamp > (self.processedRollsExpiry or 5) then
            self.processedRolls[id] = nil
        end
    end

    return self.processedRolls[rollId] ~= nil
end

-- Mark a roll as processed
function DRE:MarkRollAsProcessed(rollId)
    if not self.processedRolls then
        self.processedRolls = {}
    end
    self.processedRolls[rollId] = GetTime()
end

-- Store a recent roll for later challenge detection
function DRE:StoreRecentRoll(playerName, roll, maxRoll)
    local currentTime = GetTime()

    -- Clean up old rolls first
    self:CleanupOldRolls(currentTime)

    -- Store the new roll
    local rollData = {
        playerName = playerName,
        roll = roll,
        maxRoll = maxRoll,
        timestamp = currentTime
    }

    if not self.recentRolls then
        self.recentRolls = {}
    end

    table.insert(self.recentRolls, rollData)

    -- Limit the number of stored rolls (with bounds checking to prevent infinite loops)
    local maxRolls = self.maxRecentRolls or 10
    if maxRolls < 1 then
        maxRolls = 10  -- Safety fallback
    end

    -- Limit iterations to prevent infinite loop
    local iterations = 0
    local maxIterations = #self.recentRolls + 10  -- Extra buffer for safety
    while #self.recentRolls > maxRolls and iterations < maxIterations do
        table.remove(self.recentRolls, 1)
        iterations = iterations + 1
    end

    if iterations >= maxIterations then
        self:DebugPrint("WARNING: Hit max iterations in StoreRecentRoll cleanup - possible corruption")
    end

    self:DebugPrint("Stored recent roll: " .. playerName .. " rolled " .. roll .. " (1-" .. maxRoll .. ")")

    -- Update button text dynamically when new rolls are detected
    self:UpdateChallengeButtonText()
end

-- Clean up rolls older than the time window
function DRE:CleanupOldRolls(currentTime)
    if not self.recentRolls then
        self.recentRolls = {}
        return
    end

    local cutoffTime = currentTime - (self.recentRollTimeWindow or 60)

    for i = #self.recentRolls, 1, -1 do
        if self.recentRolls[i] and self.recentRolls[i].timestamp and self.recentRolls[i].timestamp < cutoffTime then
            table.remove(self.recentRolls, i)
        end
    end
end

-- Clear recent rolls for a specific player (e.g., when game starts/ends)
function DRE:ClearRecentRollsForPlayer(playerName)
    if not self.recentRolls or not playerName then return end

    for i = #self.recentRolls, 1, -1 do
        if self.recentRolls[i] and self.recentRolls[i].playerName == playerName then
            table.remove(self.recentRolls, i)
            self:DebugPrint("Cleared recent roll for " .. playerName)
        end
    end
end

-- Check recent rolls for a challenge from the current target
function DRE:CheckRecentRollsForChallenge()
    local currentTarget = UnitName("target")
    if not currentTarget then
        self:DebugPrint("CheckRecentRollsForChallenge: No target selected")
        return
    end
    
    -- Check if UI is open and on the right tab
    local uiOpen = (self.UI and self.UI.mainWindow and self.UI.mainWindow.frame and self.UI.mainWindow.frame:IsVisible())
    if not uiOpen then
        self:DebugPrint("CheckRecentRollsForChallenge: UI not open")
        return
    end
    
    local onCorrectTab = (self.UI.currentTab == "deathroll")
    if not onCorrectTab then
        self:DebugPrint("CheckRecentRollsForChallenge: Not on DeathRoll tab")
        return
    end
    
    self:DebugPrint("CheckRecentRollsForChallenge: Checking for recent roll from " .. currentTarget)
    
    -- Clean up old rolls first
    self:CleanupOldRolls(GetTime())
    
    -- Look for the most recent roll from the current target
    for i = #self.recentRolls, 1, -1 do
        local rollData = self.recentRolls[i]
        if rollData.playerName == currentTarget then
            self:DebugPrint("Found recent roll from target: " .. currentTarget .. " rolled " .. rollData.roll .. " (1-" .. rollData.maxRoll .. ")")
            self:ShowChallengeNotification(currentTarget, rollData.roll, rollData.maxRoll)
            return
        end
    end
    
    self:DebugPrint("No recent roll found from " .. currentTarget)
end

-- Show challenge notification in the UI
function DRE:ShowChallengeNotification(playerName, roll, maxRoll)
    self:DebugPrint("ShowChallengeNotification: " .. playerName .. " challenges you to DeathRoll 1-" .. maxRoll)
    
    -- Only show notification if UI is open and on deathroll tab
    if not (self.UI and self.UI.mainWindow and self.UI.mainWindow.frame and self.UI.mainWindow.frame:IsVisible()) then
        self:DebugPrint("UI not open, cannot show challenge notification")
        return
    end
    
    if self.UI.currentTab ~= "deathroll" then
        self:DebugPrint("Not on deathroll tab, cannot show challenge notification")
        return
    end
    
    -- Don't show if we already have an active game
    if self.gameState and self.gameState.isActive then
        self:DebugPrint("Game already active, not showing challenge notification")
        return
    end
    
    -- Store the challenge details in UI namespace (consistent with existing code)
    if not self.UI then
        self.UI = {}
    end
    self.UI.incomingChallenge = {
        player = playerName,
        roll = roll,
        maxRoll = maxRoll
    }
    
    -- Update the UI to show the challenge notification
end


-- Handle detected roll from any event source
function DRE:HandleDetectedRoll(playerName, roll, maxRoll)
    self:DebugPrint("HandleDetectedRoll called: player=" .. (playerName or "nil") .. ", roll=" .. (roll or "nil") .. ", maxRoll=" .. (maxRoll or "nil"))
    
    -- Store this roll in recent rolls (unless it's our own roll)
    local myName = UnitName("player")
    if playerName ~= myName then
        self:StoreRecentRoll(playerName, roll, maxRoll)
    end
    
    -- Handle active game rolls first (highest priority)
    if self.gameState and self.gameState.isActive then
        local myName = UnitName("player")
        self:DebugPrint("Game active - checking if roll is relevant (player: " .. myName .. ", target: " .. (self.gameState.target or "nil") .. ")")
        
        -- Check if this roll is relevant to our game
        if (playerName == myName or playerName == self.gameState.target) and
           maxRoll <= self.gameState.currentRoll + 1 then -- Allow some tolerance
            self:DebugPrint("Roll is relevant - processing via HandleGameRoll")
            self:HandleGameRoll(playerName, roll, maxRoll)
        else
            self:DebugPrint("Roll not relevant - player: " .. playerName .. ", maxRoll: " .. maxRoll .. ", currentRoll: " .. (self.gameState.currentRoll or "nil"))
        end
        return -- Don't process further if game is active
    end
    
    -- No active game - check for challenges
    self:DebugPrint("No active game - checking for challenges")
    
    -- Check if this roll is from someone we have targeted (they're challenging us)
    local currentTarget = UnitName("target")
    if currentTarget == playerName then
        self:DebugPrint("Roll detected from our current target - checking for challenge notification")
        self:CheckTargetedPlayerChallenge(playerName, roll, maxRoll)
    else
        self:DebugPrint("Roll from " .. playerName .. " but our target is " .. tostring(currentTarget))
        -- Only run auto-challenge if this isn't from our target (to avoid conflicts)
        self:CheckUIAutoChallenge(playerName, roll, maxRoll)
    end
end

-- Check if targeted player rolled and show challenge notification
function DRE:CheckTargetedPlayerChallenge(playerName, roll, maxRoll)
    self:DebugPrint("CheckTargetedPlayerChallenge: " .. playerName .. " rolled " .. roll .. " (1-" .. maxRoll .. ")")
    
    -- Only show if UI is open and we have them targeted
    local uiOpen = (self.UI and self.UI.mainWindow and self.UI.mainWindow.frame and self.UI.mainWindow.frame:IsVisible())
    self:DebugPrint("UI Open: " .. tostring(uiOpen))
    if not uiOpen then
        return -- UI not open
    end
    
    local onCorrectTab = (self.UI.currentTab == "deathroll")
    self:DebugPrint("On DeathRoll tab: " .. tostring(onCorrectTab))
    if not onCorrectTab then
        return -- Not on the right tab
    end
    
    local currentTarget = UnitName("target")
    local isTargeted = (currentTarget and currentTarget == playerName)
    self:DebugPrint("Current target: " .. tostring(currentTarget) .. ", Roll from target: " .. tostring(isTargeted))
    if not isTargeted then
        return -- This player is not our current target
    end
    
    local gameActive = (self.gameState and self.gameState.isActive)
    self:DebugPrint("Game already active: " .. tostring(gameActive))
    if gameActive then
        return -- Already in a game
    end
    
    self:DebugPrint("All conditions met - showing challenge notification!")
    -- Show challenge notification in the UI
    self:ShowChallengeNotification(playerName, roll, maxRoll)
end

-- Show challenge notification with Accept/Deny buttons
function DRE:ShowChallengeNotification(playerName, roll, maxRoll)
    if not self.UI or not self.UI.mainWindow then
        return
    end
    
    -- Store the challenge data
    self.UI.incomingChallenge = {
        player = playerName,
        roll = roll,
        maxRoll = maxRoll,
        timestamp = GetTime()
    }
    
    -- Update the UI to show the challenge
end

-- Update UI to show incoming challenge notification

-- Check if UI is open and auto-start challenge when target rolls
function DRE:CheckUIAutoChallenge(playerName, roll, maxRoll)
    self:DebugPrint("CheckUIAutoChallenge called: player=" .. playerName .. ", roll=" .. roll .. ", maxRoll=" .. maxRoll)
    
    -- Check if DeathRoll UI is open and visible
    local uiOpen = (self.UI and self.UI.mainWindow and self.UI.mainWindow.frame and self.UI.mainWindow.frame:IsVisible())
    self:DebugPrint("UI Open: " .. tostring(uiOpen))
    if not uiOpen then
        return -- UI not open
    end
    
    -- Check if we're on the deathroll tab
    local onCorrectTab = (self.UI.currentTab == "deathroll")
    self:DebugPrint("On DeathRoll tab: " .. tostring(onCorrectTab) .. " (current: " .. tostring(self.UI.currentTab) .. ")")
    if not onCorrectTab then
        return -- Not on the right tab
    end
    
    -- Check if this player is currently our target
    local currentTarget = UnitName("target")
    local isCurrentTarget = (currentTarget and currentTarget == playerName)
    self:DebugPrint("Current target: " .. tostring(currentTarget) .. ", Is target: " .. tostring(isCurrentTarget))
    if not isCurrentTarget then
        return -- Player is not our current target
    end
    
    -- Check if we're already in a game
    local gameActive = (self.gameState and self.gameState.isActive)
    self:DebugPrint("Game active: " .. tostring(gameActive))
    if gameActive then
        return -- Already in a game
    end
    
    -- Auto-fill the roll field in UI and start challenge
    self:DebugPrint("All conditions met - starting auto-challenge!")
    if self.UI.rollEdit then
        self.UI.rollEdit:SetText(tostring(maxRoll))
        self:ChatPrint("Auto-detected " .. playerName .. "'s roll (" .. maxRoll .. ") - starting challenge!")
        
        -- Immediately start the game with the detected roll
        self:StartActualGame(currentTarget, maxRoll, 0, maxRoll)
    else
        self:DebugPrint("ERROR: UI.rollEdit not found!")
    end
end


-- Handle whisper messages for spicy duels and fallback challenges
function DRE:CHAT_MSG_WHISPER(event, message, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
    -- Handle DeathRoll challenge messages
    if message:match("^DEATHROLL_CHALLENGE:") then
        self:HandleChallengeWhisper(message, playerName)
        return
    end

    -- Handle DeathRoll challenge acceptance
    if message == "DEATHROLL_ACCEPT" then
        self:Print(playerName .. " accepted your DeathRoll challenge!")
        return
    end

    -- Handle DeathRoll challenge decline
    if message == "DEATHROLL_DECLINE" then
        self:Print(playerName .. " declined your DeathRoll challenge.")
        return
    end

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

-- Scan recent chat for ANY roll from debug buffer (not just target's)
function DRE:FindRecentTargetRoll(targetName)
    if not self.debugChatBuffer then return nil end
    
    -- Search through recent debug buffer messages (stored in reverse order)
    for i = #self.debugChatBuffer, 1, -1 do
        local entry = self.debugChatBuffer[i]
        if entry and entry:find("CHAT_MSG_SYSTEM:") then
            -- Extract the actual message from debug format: "[timestamp] CHAT_MSG_SYSTEM: message"
            local message = entry:match("CHAT_MSG_SYSTEM: (.+)$")
            if message then
                -- Look for roll patterns: "PlayerName rolls 1-100 (42)" or "You roll 1-100 (42)"
                local playerName, maxRoll, rollResult = message:match("(%S+) rolls? 1%-(%d+) %((%d+)%)")
                
                if playerName and maxRoll and rollResult then
                    -- Convert "You" to actual player name
                    if playerName == "You" then
                        playerName = UnitName("player")
                    end
                    
                    -- Return any recent roll, not just from target
                    -- This allows detection of your own rolls when targeting someone else
                    return {
                        player = playerName,
                        roll = tonumber(rollResult),
                        maxRoll = tonumber(maxRoll),
                        message = message
                    }
                end
            end
        end
    end
    
    return nil
end

-- Update button text with current target and check for recent rolls
function DRE:UpdateChallengeButtonText()
    -- Validate UI exists and is ready
    if not self.UI then
        self:DebugPrint("UpdateChallengeButtonText: UI not initialized")
        return
    end

    -- Don't update during active games
    if self.gameState and self.gameState.isActive then
        self:DebugPrint("UpdateChallengeButtonText: Game active, skipping update")
        return
    end

    -- Validate game button exists
    if not self.UI.gameButton then
        self:DebugPrint("UpdateChallengeButtonText: gameButton not found")
        return
    end

    local targetName = UnitName("target")

    if not targetName then
        -- No target selected
        self:SafeUIUpdate(self.UI.gameButton, function()
            if self.UI and self.UI.gameButton then
                self.UI.gameButton:SetText("Challenge Player to DeathRoll!")
            end
        end, "gameButton")
        -- Clear the roll input when no target
        if self.UI.rollEdit then
            self:SafeUIUpdate(self.UI.rollEdit, function()
                if self.UI and self.UI.rollEdit then
                    self.UI.rollEdit:SetText("")
                end
            end, "rollEdit")
        end
        return
    end

    -- Check for recent roll from the current target
    local recentRoll = nil
    self:CleanupOldRolls(GetTime())

    if self.recentRolls then
        for i = #self.recentRolls, 1, -1 do
            local rollData = self.recentRolls[i]
            if rollData and rollData.playerName == targetName then
                recentRoll = rollData
                break
            end
        end
    end

    if recentRoll then
        -- Target has done a roll - show challenge button
        local buttonText = targetName .. " rolled " .. recentRoll.roll .. " from " .. recentRoll.maxRoll .. " - Accept challenge!"
        self:SafeUIUpdate(self.UI.gameButton, function()
            if self.UI and self.UI.gameButton then
                self.UI.gameButton:SetText(buttonText)
            end
        end, "gameButton")

        -- Set the roll input to their ROLL RESULT (not maxRoll)
        if self.UI.rollEdit then
            self:SafeUIUpdate(self.UI.rollEdit, function()
                if self.UI and self.UI.rollEdit then
                    self.UI.rollEdit:SetText(tostring(recentRoll.roll))
                end
            end, "rollEdit")
        end

        -- Store the recent roll data for button click handling
        self.UI.recentTargetRoll = recentRoll

        self:DebugPrint("Button updated for challenge from " .. targetName .. " with roll " .. recentRoll.roll .. " (1-" .. recentRoll.maxRoll .. ")")
    else
        -- No qualifying recent roll - show generic challenge button
        self:SafeUIUpdate(self.UI.gameButton, function()
            if self.UI and self.UI.gameButton then
                self.UI.gameButton:SetText("Challenge " .. targetName .. " to DeathRoll!")
            end
        end, "gameButton")

        -- Clear the roll input for normal challenges
        if self.UI.rollEdit then
            self:SafeUIUpdate(self.UI.rollEdit, function()
                if self.UI and self.UI.rollEdit then
                    self.UI.rollEdit:SetText("")
                end
            end, "rollEdit")
        end

        -- Clear any stored roll data
        self.UI.recentTargetRoll = nil
    end
end

-- Conditional print that respects chat messages setting
function DRE:ChatPrint(message)
    if self.db and self.db.profile.gameplay.chatMessages then
        self:Print(message)
    end
end

-- Add message to debug chat buffer
function DRE:AddToDebugBuffer(source, message)
    local timestamp = date("%H:%M:%S")
    local entry = string.format("[%s] %s: %s", timestamp, source, message or "nil")
    
    table.insert(self.debugChatBuffer, entry)
    
    -- Keep only last N messages
    if #self.debugChatBuffer > self.maxDebugMessages then
        table.remove(self.debugChatBuffer, 1)
    end
end

-- Dump debug buffer to chat
function DRE:DumpDebugBuffer()
    self:Print("=== DEBUG CHAT BUFFER START ===")
    self:Print("Buffer size: " .. #self.debugChatBuffer .. " messages")
    
    if #self.debugChatBuffer == 0 then
        self:Print("No messages in buffer yet - try doing some actions first")
    else
        for i, entry in ipairs(self.debugChatBuffer) do
            self:Print(entry)
        end
    end
    
    self:Print("=== DEBUG CHAT BUFFER END ===")
    
    -- Also save to file
    self:SaveDebugBufferToFile()
end

-- Save debug buffer to file
function DRE:SaveDebugBufferToFile()
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    
    -- Save to WoW saved variables instead of file I/O
    if not DeathRollEnhancer_DebugExport then
        DeathRollEnhancer_DebugExport = {}
    end
    
    -- Build debug data
    local debugData = {
        generated = timestamp,
        bufferSize = #self.debugChatBuffer,
        messages = {}
    }
    
    if #self.debugChatBuffer == 0 then
        table.insert(debugData.messages, "No messages in buffer yet - try doing some actions first")
    else
        for i, entry in ipairs(self.debugChatBuffer) do
            table.insert(debugData.messages, entry)
        end
    end
    
    -- Store in saved variables
    DeathRollEnhancer_DebugExport[timestamp] = debugData
    
    self:Print("Debug buffer saved to saved variables")
    self:Print("Will be available in SavedVariables/DeathRollEnhancer.lua after /reload")
    self:Print("Also showing copyable format in chat:")
    
    -- Print copyable format to chat
    print("=== DEATHROLL DEBUG EXPORT ===")
    print("Generated: " .. timestamp)
    print("Buffer size: " .. #self.debugChatBuffer .. " messages")
    print("=" .. string.rep("=", 30))
    
    if #self.debugChatBuffer == 0 then
        print("No messages in buffer yet")
    else
        for i, entry in ipairs(self.debugChatBuffer) do
            print(entry)
        end
    end
    
    print("=" .. string.rep("=", 30))
    print("=== END DEBUG EXPORT ===")
end

-- Conditional print that respects debug messages setting
function DRE:DebugPrint(message)
    -- Add to buffer regardless of settings
    self:AddToDebugBuffer("DEBUG", message)
    
    -- Print to chat if enabled
    if (self.db and self.db.profile.gameplay.debugMessages) then
        self:Print("[DEBUG] " .. message)
    end
end

-- Main function to start a DeathRoll challenge (called from UI)
function DRE:StartDeathRoll(target, roll, wager)
    -- Check for active game first to prevent concurrent games
    if self.gameState and self.gameState.isActive then
        self:Print("A game is already in progress! Finish the current game first.")
        return
    end

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

        -- Basic character validation (letters, some special characters, no pure whitespace/symbols)
        if not target:match("^[%a%s'-]+$") or target:match("^[%s'-]+$") then
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

    self:ChatPrint("Challenging " .. target .. " to DeathRoll - rolling now!")

    -- Start the game and immediately perform our roll
    self:StartActualGame(target, roll, wager, roll)

    -- Automatically perform our first roll
    C_Timer.After(0.1, function()
        if self.gameState and self.gameState.isActive then
            self:PerformRoll()
        end
    end)
end


-- Show dialog to edit recent game records
function DRE:ShowEditGameDialog()
    -- Close existing dialog if open
    if self.editGameFrame then
        self.editGameFrame:Hide()
        self.editGameFrame = nil
    end
    
    local recentGames = self:GetRecentGamesForEditing(15)
    
    if #recentGames == 0 then
        self:Print("No recent game records found to edit!")
        return
    end
    
    -- Create frame
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Edit Game Record")
    frame:SetLayout("Flow")
    frame:SetWidth(500)
    frame:SetHeight(400)
    
    -- Store reference for refreshing
    self.editGameFrame = frame
    frame:SetCallback("OnClose", function(widget)
        self.editGameFrame = nil
        widget:Hide()
    end)
    
    -- Build dropdown options (ensure newest first ordering)
    local gameList = {}
    local gameMap = {}
    
    -- Debug: Print the order we receive games in
    self:DebugPrint("Edit dialog game order:")
    for i, gameData in ipairs(recentGames) do
        local game = gameData.game
        self:DebugPrint(string.format("[%d] %s vs %s: %s - %s (timestamp: %s)", 
            i, UnitName("player") or "You", gameData.playerName, game.result or "Unknown", 
            game.date or "Unknown Date", tostring(gameData.timestamp or 0)))
    end
    
    for i, gameData in ipairs(recentGames) do
        local game = gameData.game
        local myName = UnitName("player") or "You"
        
        -- Create display text for dropdown
        local resultText = game.result or "Unknown"
        local goldText = ""
        if game.goldAmount and game.goldAmount > 0 then
            goldText = " (" .. self:FormatGold(game.goldAmount) .. ")"
        end
        
        local dateText = game.date or "Unknown Date"
        local displayText = string.format("[%d] %s vs %s: %s%s - %s", 
            i, myName, gameData.playerName, resultText, goldText, dateText)
        
        local key = "game_" .. string.format("%02d", i)  -- Zero-pad to ensure proper sorting
        gameList[key] = displayText
        gameMap[key] = gameData
    end
    
    -- Game selection dropdown
    local gameDropdown = AceGUI:Create("Dropdown")
    gameDropdown:SetLabel("Select Game to Edit:")
    gameDropdown:SetList(gameList)
    gameDropdown:SetWidth(450)
    frame:AddChild(gameDropdown)
    
    -- Container for editing UI (will be created dynamically)
    local selectedGameGroup = AceGUI:Create("SimpleGroup")
    selectedGameGroup:SetLayout("Flow")
    selectedGameGroup:SetFullWidth(true)
    frame:AddChild(selectedGameGroup)
    
    -- Function to create editing UI for selected game
    local function createEditUI(gameData)
        selectedGameGroup:ReleaseChildren()
        
        if not gameData then return end
        
        local game = gameData.game
        local playerName = gameData.playerName
        
        -- Game info header
        local infoLabel = AceGUI:Create("Label")
        infoLabel:SetText(string.format("Editing game vs %s from %s:", playerName, game.date or "Unknown Date"))
        infoLabel:SetFullWidth(true)
        selectedGameGroup:AddChild(infoLabel)
        
        -- Result dropdown
        local resultDropdown = AceGUI:Create("Dropdown")
        resultDropdown:SetLabel("Result:")
        resultDropdown:SetList({win = "Won", lost = "Lost"})
        resultDropdown:SetValue(game.result == "Won" and "win" or "lost")
        resultDropdown:SetWidth(150)
        selectedGameGroup:AddChild(resultDropdown)
        
        -- Gold input
        local goldInput = AceGUI:Create("EditBox")
        goldInput:SetLabel("Gold:")
        local currentGold = game.goldAmount or 0
        local gold = math.floor(currentGold / 10000)
        goldInput:SetText(tostring(gold))
        goldInput:SetWidth(80)
        selectedGameGroup:AddChild(goldInput)
        
        -- Silver input  
        local silverInput = AceGUI:Create("EditBox")
        silverInput:SetLabel("Silver:")
        local silver = math.floor((currentGold % 10000) / 100)
        silverInput:SetText(tostring(silver))
        silverInput:SetWidth(80)
        selectedGameGroup:AddChild(silverInput)
        
        -- Copper input
        local copperInput = AceGUI:Create("EditBox")
        copperInput:SetLabel("Copper:")
        local copper = currentGold % 100
        copperInput:SetText(tostring(copper))
        copperInput:SetWidth(80)
        selectedGameGroup:AddChild(copperInput)
        
        -- Starting roll input
        local rollInput = AceGUI:Create("EditBox")
        rollInput:SetLabel("Starting Roll:")
        rollInput:SetText(tostring(game.initialRoll or 0))
        rollInput:SetWidth(100)
        selectedGameGroup:AddChild(rollInput)
        
        -- Button container for save and delete buttons
        local buttonGroup = AceGUI:Create("SimpleGroup")
        buttonGroup:SetLayout("Flow")
        buttonGroup:SetFullWidth(true)
        selectedGameGroup:AddChild(buttonGroup)
        
        -- Save button
        local saveButton = AceGUI:Create("Button")
        saveButton:SetText("Save Changes")
        saveButton:SetWidth(150)
        saveButton:SetCallback("OnClick", function()
            local newResult = resultDropdown:GetValue() == "win" and "Won" or "Lost"
            local gold = tonumber(goldInput:GetText()) or 0
            local silver = tonumber(silverInput:GetText()) or 0
            local copper = tonumber(copperInput:GetText()) or 0
            local newInitialRoll = tonumber(rollInput:GetText()) or 0

            -- Validate inputs
            if gold < 0 or gold > 999999 then
                self:Print("Gold must be between 0 and 999,999!")
                return
            end
            if silver < 0 or silver > 99 then
                self:Print("Silver must be between 0 and 99!")
                return
            end
            if copper < 0 or copper > 99 then
                self:Print("Copper must be between 0 and 99!")
                return
            end
            if newInitialRoll < 0 or newInitialRoll > 999999 then
                self:Print("Starting roll must be between 0 and 999,999!")
                return
            end

            local newGoldAmount = gold * 10000 + silver * 100 + copper

            local success, message = self:EditGameRecord(playerName, gameData.gameIndex, newResult, newGoldAmount, newInitialRoll)

            if success then
                self:Print(message)
                frame:Hide()
                -- Update UI if it's open
                if self.UpdateStatsDisplay then
                    self:UpdateStatsDisplay()
                end
            else
                self:Print("Failed to update: " .. message)
            end
        end)
        buttonGroup:AddChild(saveButton)
        
        -- Delete button
        local deleteButton = AceGUI:Create("Button")
        deleteButton:SetText("Delete Game")
        deleteButton:SetWidth(150)
        deleteButton:SetCallback("OnClick", function()
            -- Show confirmation dialog with parameters
            local popup = StaticPopup_Show("DEATHROLL_DELETE_GAME_CONFIRM")
            if popup then
                popup.data = playerName
                popup.data2 = gameData.gameIndex
            end
        end)
        buttonGroup:AddChild(deleteButton)
    end
    
    -- Update edit UI when dropdown selection changes
    gameDropdown:SetCallback("OnValueChanged", function(widget, event, key)
        local selectedGameData = gameMap[key]
        if selectedGameData then
            createEditUI(selectedGameData)
        end
    end)
    
    -- Initialize with first game (newest)
    if recentGames[1] then
        local firstKey = "game_01"  -- Match the zero-padded format
        gameDropdown:SetValue(firstKey)
        createEditUI(gameMap[firstKey])
    end
    
    frame:Show()
end

-- Refresh the edit dialog after a game is deleted
function DRE:RefreshEditDialog()
    if self.editGameFrame then
        -- Simply reopen the dialog to refresh the list
        self.editGameFrame:Hide()
        self.editGameFrame = nil
        -- Small delay to ensure proper cleanup
        C_Timer.After(0.1, function()
            self:ShowEditGameDialog()
        end)
    end
end

-- Create reset confirmation popup
StaticPopupDialogs["DEATHROLL_CHALLENGE_POPUP"] = {
    text = "%s challenges you to DeathRoll!\n\nRoll: 1-%d\nWager: %s\n\nDo you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnShow = function(self, data)
        if not data or not data.sender or not data.roll then
            self:Hide()
            return
        end

        local wagerText = "No wager"
        if data.wager and data.wager > 0 then
            wagerText = DRE:FormatGold(data.wager)
        end

        self.text:SetFormattedText(self.text:GetText(), data.sender, data.roll, wagerText)
    end,
    OnAccept = function(self)
        if DRE and DRE.AcceptChallenge then
            DRE:AcceptChallenge()
        end
    end,
    OnCancel = function(self)
        if DRE and DRE.DeclineChallenge then
            DRE:DeclineChallenge()
        end
    end,
    timeout = 30,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

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

-- Create delete game confirmation popup
StaticPopupDialogs["DEATHROLL_DELETE_GAME_CONFIRM"] = {
    text = "Are you sure you want to delete this game record?\n\nThis will permanently remove:\n- The game from your history\n- Associated win/loss and gold statistics\n\nThis action cannot be undone!",
    button1 = "Yes, Delete Game",
    button2 = "Cancel",
    OnAccept = function(self)
        if DRE and DRE.DeleteGameRecord and self.data and self.data2 then
            local playerName = self.data
            local gameIndex = self.data2
            local success, message = DRE:DeleteGameRecord(playerName, gameIndex)
            if success then
                DRE:Print(message)
                -- Update UI if it's open
                if DRE.UpdateStatsDisplay then
                    DRE:UpdateStatsDisplay()
                end
                -- Refresh the edit dialog with updated data
                if DRE.RefreshEditDialog then
                    DRE:RefreshEditDialog()
                end
            else
                DRE:Print("Failed to delete game: " .. message)
            end
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

    self:DebugPrint("Starting actual game: target=" .. target .. ", initialRoll=" .. initialRoll .. ", currentRoll=" .. (currentRoll or initialRoll) .. ", isSelfDuel=" .. tostring(isSelfDuel))

    -- Initialize game state
    self.gameState = {
        isActive = true,
        target = target,
        initialRoll = initialRoll,
        currentRoll = currentRoll or initialRoll,
        wager = wager or 0,
        playerTurn = true,
        rollCount = isSelfDuel and 0 or 0  -- Initialize roll counter for all games
    }

    -- Clear recent rolls for the opponent to prevent button confusion
    if target ~= myName then
        self:ClearRecentRollsForPlayer(target)
    end
    
    -- Clear previous game's roll history to start fresh
    self:ClearRollHistory()
    
    self:DebugPrint("Game state initialized - isActive: " .. tostring(self.gameState.isActive) .. ", currentRoll: " .. self.gameState.currentRoll)
    
    
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
    self:RegisterEvent("CHAT_MSG_SYSTEM")
end

-- Handle game end
function DRE:HandleGameEnd(loser, result, wager, initialRoll)
    local playerName = UnitName("player")
    local won = (result == "WIN")
    local opponent = self.gameState and self.gameState.target or "Unknown"
    
    if won then
        self:Print("You WON the DeathRoll!")
        if self.db and self.db.profile.gameplay.autoEmote then
            DoEmote(self:GetRandomHappyEmote())
        end
    else
        self:Print("You LOST the DeathRoll!")
        if self.db and self.db.profile.gameplay.autoEmote then
            DoEmote(self:GetRandomSadEmote())
        end
    end
    
    -- Add result to roll history
    self:AddGameResultToHistory(result, opponent, wager)
    
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
    
    -- Clear recent roll data so button returns to normal after game
    if self.UI then
        self.UI.recentTargetRoll = nil
        self.UI.isGameActive = false
        self.UI.currentTarget = nil
        
        -- Remove recent rolls from the game opponent to prevent challenge button confusion
        if opponent then
            for i = #self.recentRolls, 1, -1 do
                local rollData = self.recentRolls[i]
                if rollData.playerName == opponent then
                    table.remove(self.recentRolls, i)
                end
            end
        end
        
        -- Clear roll and wager input fields
        if self.UI.rollEdit then
            self.UI.rollEdit:SetText("")
        end
        if self.UI.goldEdit then
            self.UI.goldEdit:SetText("")
        end
        if self.UI.silverEdit then
            self.UI.silverEdit:SetText("")
        end
        if self.UI.copperEdit then
            self.UI.copperEdit:SetText("")
        end
    end
    
    -- Update button text to clear any challenge text
    self:UpdateChallengeButtonText()
    
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
    self:DebugPrint("HandleGameRoll called: player=" .. (playerName or "nil") .. ", roll=" .. (roll or "nil") .. ", maxRoll=" .. (maxRoll or "nil") .. ", gameState.isActive=" .. tostring(self.gameState and self.gameState.isActive or false))

    -- Validate game state exists and is active
    if not self.gameState or not self.gameState.isActive then
        self:DebugPrint("No active game state, ignoring roll")
        return
    end

    -- Validate game state has required fields
    if not self.gameState.target or not self.gameState.currentRoll or not self.gameState.initialRoll then
        self:DebugPrint("Game state missing required fields, aborting")
        self.gameState = nil
        return
    end

    -- Validate parameters
    if not playerName or not roll or not maxRoll then
        self:DebugPrint("Invalid parameters passed to HandleGameRoll")
        return
    end

    local myName = UnitName("player")
    if not myName then
        self:DebugPrint("Could not get player name")
        return
    end

    local isSelfDuel = (self.gameState.target == myName)
    
    -- Only process rolls from the player if it's a regular duel or self-duel
    if playerName == myName then
        if isSelfDuel then
            -- Increment roll counter
            self.gameState.rollCount = self.gameState.rollCount + 1
            
            -- Add roll to history display
            self:AddRollToHistory(playerName, roll, maxRoll, true, self.gameState.rollCount)
            
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
                self.gameState.currentRoll = roll
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
            self:AddRollToHistory(playerName, roll, maxRoll, false, nil)
            self:ChatPrint("You rolled " .. roll .. " (1-" .. maxRoll .. ")")
            
            if roll == 1 then
                -- We lost
                self:HandleGameEnd(myName, "LOSS", self.gameState.wager, self.gameState.initialRoll)
            else
                -- Continue game, opponent's turn
                self.gameState.currentRoll = roll
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
        self:AddRollToHistory(playerName, roll, maxRoll, false, nil)
        self:ChatPrint(playerName .. " rolled " .. roll .. " (1-" .. maxRoll .. ")")
        
        if roll == 1 then
            -- They lost, we won
            self:HandleGameEnd(playerName, "WIN", self.gameState.wager, self.gameState.initialRoll)
        else
            -- Continue game, our turn
            self.gameState.currentRoll = roll
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
    
    -- Send stance and roll to opponent via whisper
    SendChatMessage("My stance: " .. stance .. " (roll: " .. roll .. ")", "WHISPER", nil, self.spicyDuel.target)
    
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
        self:Print("Double KO! What an epic battle!")
        self:EndSpicyDuel()
    elseif self.spicyDuel.myHP <= 0 then
        self:Print("You lost the Spicy Duel! " .. self.spicyDuel.target .. " is victorious!")
        self:EndSpicyDuel()
    elseif self.spicyDuel.opponentHP <= 0 then
        self:Print("You won the Spicy Duel! Excellent strategy!")
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
            -- Get current target name
            local targetName = UnitName("target")
            local buttonText = targetName and ("Challenge " .. targetName .. " to DeathRoll!") or "Challenge Player to DeathRoll!"
            
            self:SafeUIUpdate(self.UI.gameButton, function()
                self.UI.gameButton:SetText(buttonText)
                self.UI.gameButton:SetDisabled(false)
            end, "gameButton")
            
            self:UpdateRollHistoryStatus("Ready to start! Target someone and click Challenge!", true)
            
            
        elseif state == "ROLLING" then
            local rollRange = self.gameState and self.gameState.currentRoll or 100
            self.UI.gameButton:SetText("Roll 1-" .. rollRange)
            self.UI.gameButton:SetDisabled(false)
            -- Don't update history status for rolling - let the roll history show
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
            -- Don't update history status - let the roll history show the opponent's upcoming turn
            
        elseif state == "WAITING_FOR_ROLL_RESULT" then
            self.UI.gameButton:SetText("Rolling...")
            self.UI.gameButton:SetDisabled(true)
            -- Don't update history status - the roll result will appear in history soon
            
        elseif state == "GAME_OVER" then
            self.UI.gameButton:SetText("Challenge Player to DeathRoll!")
            self.UI.gameButton:SetDisabled(false)
            -- Don't update roll history - let the win/loss message persist
            -- Don't auto-reset to WAITING - let the user manually start a new game
        end
end

-- Make the addon globally accessible
_G.DeathRollEnhancer = DRE
