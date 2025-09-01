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
                        dialogControl = "LSM30_Font",
                        values = LSM and LSM:HashTable("font") or {},
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
    if DRE.UI and self.db.profile.ui.font then
        -- This would update fonts in AceGUI widgets
        self:Print("Font updated to: " .. self.db.profile.ui.font)
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