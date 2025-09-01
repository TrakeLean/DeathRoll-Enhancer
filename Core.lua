-- Core.lua
-- Main addon initialization and coordination

local addonName, DeathRollEnhancer = ...

-- Create the main addon namespace
DeathRollEnhancer = DeathRollEnhancer or {}
local DRE = DeathRollEnhancer

-- Addon information
DRE.version = "1.5.3"
DRE.author = "EgyptianSheikh"

-- Core addon state
DRE.isLoaded = false
DRE.isInitialized = false

-- Utility functions
function DRE.CusRound(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Function to pick a random happy emote from a list
function DRE.GetRandomHappyEmote()
    local happyEmotes = {"CHEER", "LAUGH", "SALUTE", "DANCE", "VICTORY"}
    local randomIndex = math.random(1, #happyEmotes)
    return happyEmotes[randomIndex]
end

-- Function to pick a random sad emote from a list
function DRE.GetRandomSadEmote()
    local sadEmotes = {"CRY", "SIGH", "SURRENDER", "LAY", "CONGRATULATE"}
    local randomIndex = math.random(1, #sadEmotes)
    return sadEmotes[randomIndex]
end

-- Slash command handlers
function DRE.RegisterSlashCommands()
    -- Main DeathRoll command
    SLASH_DEATHROLL1 = "/deathroll"
    SLASH_DEATHROLL2 = "/dr"
    SlashCmdList["DEATHROLL"] = function(msg)
        if DRE.UI then
            DRE.UI:ShowUI()
        end
    end

    -- DeathRoll history command
    SLASH_DEATHROLLHISTORY1 = "/deathrollhistory"
    SLASH_DEATHROLLHISTORY2 = "/drh"
    SlashCmdList["DEATHROLLHISTORY"] = function(msg)
        local target = msg:trim()
        if target == "" then
            target = UnitName("target")
        end
        if target and DRE.Database then
            DRE.Database:ShowDeathRollHistory(target)
        else
            print("Please provide a target name or select a target.")
        end
    end

    -- Minimap command
    SLASH_MINIMAP1 = "/deathrollminimap"
    SLASH_MINIMAP2 = "/drm"
    SlashCmdList["MINIMAP"] = function(msg)
        if DRE.Minimap then
            DRE.Minimap:HandleSlashCommand(msg)
        end
    end
    
    -- UI reset command
    SLASH_DEATHROLLRESET1 = "/deathrollreset"
    SLASH_DEATHROLLRESET2 = "/drreset"
    SlashCmdList["DEATHROLLRESET"] = function(msg)
        if DRE.UI then
            DRE.UI:ResetScale()
        end
    end
end

-- Initialize the addon
function DRE.Initialize()
    if DRE.isInitialized then return end
    
    -- Initialize database
    if DRE.Database then
        DRE.Database:Initialize()
    end
    
    -- Initialize UI
    if DRE.UI then
        DRE.UI:Initialize()
    end
    
    -- Initialize event handling
    if DRE.Events then
        DRE.Events:Initialize()
    end
    
    -- Initialize minimap
    if DRE.Minimap then
        DRE.Minimap:Initialize()
    end
    
    -- Initialize gold tracking
    if DRE.GoldTracking then
        DRE.GoldTracking:Initialize()
    end
    
    -- Register slash commands
    DRE.RegisterSlashCommands()
    
    DRE.isInitialized = true
    
    print("|cFF00FF00<< |r|cFFFF0000Death|r|cFFFFFFFFRoll|r Enhancer: |cFF00FF00Has been loaded >>")
end

-- Event frame for addon loading
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "DeathRollEnhancer" then
        DRE.isLoaded = true
        DRE.Initialize()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGOUT" then
        DRE.Cleanup()
    end
end)

-- Cleanup function to prevent memory leaks
function DRE.Cleanup()
    if DRE.GoldTracking then
        DRE.GoldTracking:Cleanup()
    end
    
    if DRE.Events then
        DRE.Events:UnregisterEvents()
    end
    
    print("|cFFFFFF00DeathRoll: |rAddon cleaned up for logout")
end

-- Make the addon globally accessible
_G.DeathRollEnhancer = DeathRollEnhancer