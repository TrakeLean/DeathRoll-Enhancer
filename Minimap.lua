-- Minimap.lua
-- Minimap integration using LibDBIcon

local addonName, addonTable = ...
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
if not DRE then return end

local LibDBIcon = LibStub("LibDBIcon-1.0", true)
local LDB = LibStub("LibDataBroker-1.1", true)

-- The native addon compartment resolves this callback by its global name.
function DeathRollEnhancer_OnLauncherClick(_, button)
    if DRE.disabled then return end
    if button == "LeftButton" then
        DRE:ShowMainWindow()
    elseif button == "RightButton" then
        DRE:OpenOptions()
    end
end

local muted = "|cFFB6AEA0"
local white = "|cFFFFF4DF"
local gain = "|cFF82D69A"
local loss = "|cFFF49A8F"

local function addRow(tooltip, label, value, valueColor)
    label = muted .. label .. "|r"
    value = (valueColor or white) .. value .. "|r"
    if tooltip.AddDoubleLine then
        tooltip:AddDoubleLine(label, value)
    else
        tooltip:AddLine(label .. "  " .. value)
    end
end

local function money(copper)
    return GetCoinTextureString and GetCoinTextureString(copper) or DRE:FormatGold(copper)
end

local function showTooltip(tooltip)
    if not tooltip or not tooltip.AddLine then return end
    tooltip:AddLine("|cFFFFD474" .. DRE.displayName .. "|r  " .. muted .. "v" .. DRE.version .. "|r")

    local profile = DRE.db and DRE.db.profile
    local stats = profile and profile.goldTracking
    local won = tonumber(stats and stats.totalWon) or 0
    local lost = tonumber(stats and stats.totalLost) or 0
    local streak = tonumber(stats and stats.currentStreak) or 0
    if won > 0 or lost > 0 or streak ~= 0 then
        tooltip:AddLine(" ")
        if won > 0 or lost > 0 then
            local net = won - lost
            local sign = net > 0 and "+" or net < 0 and "-" or ""
            local color = net > 0 and gain or net < 0 and loss or white
            addRow(tooltip, "Net gold", sign .. money(math.abs(net)), color)
            addRow(tooltip, "Gold won", money(won))
            addRow(tooltip, "Gold lost", money(lost))
        end
        if streak ~= 0 then
            local label = streak > 0 and "Win streak" or "Loss streak"
            addRow(tooltip, label, math.abs(streak), streak > 0 and gain or loss)
        end
    end

    tooltip:AddLine(" ")
    addRow(tooltip, "Left-click", "Open DeathRoll")
    addRow(tooltip, "Right-click", "Open settings")
end

-- Create the data object used by the bundled LibDataBroker and LibDBIcon.
local minimapLDB = {
    type = "data source",
    text = "DeathRoll",
    icon = "Interface\\AddOns\\DeathRollEnhancer\\Media\\Logo.tga",
    OnClick = DeathRollEnhancer_OnLauncherClick,
    OnTooltipShow = showTooltip,
}

-- If LibDataBroker is available, register with it for better compatibility
if LDB then
    minimapLDB = LDB:NewDataObject("DeathRollEnhancer", minimapLDB)
end

-- Initialize minimap integration
function DRE:InitializeMinimap()
    if not LibDBIcon then
        self:Print("LibDBIcon not found - minimap icon disabled")
        return
    end
    
    -- Register the minimap icon
    if not LibDBIcon:IsRegistered("DeathRollEnhancer") then
        LibDBIcon:Register("DeathRollEnhancer", minimapLDB, self.db.profile.minimap)
    end
    
    -- Update visibility based on settings
    self:UpdateMinimapVisibility()
end

-- Toggle minimap icon visibility
function DRE:ToggleMinimapIcon()
    if not LibDBIcon then return end
    
    if self.db.profile.minimap.hide then
        LibDBIcon:Hide("DeathRollEnhancer")
    else
        LibDBIcon:Show("DeathRollEnhancer")
    end
end

-- Update minimap visibility based on settings
function DRE:UpdateMinimapVisibility()
    if not LibDBIcon then return end
    
    if self.db and self.db.profile.minimap.hide then
        LibDBIcon:Hide("DeathRollEnhancer")
    else
        LibDBIcon:Show("DeathRollEnhancer")
    end
end

-- Update minimap tooltip data
function DRE:UpdateMinimapTooltip()
    -- Tooltip data is updated dynamically in OnTooltipShow
end

-- Lock/unlock minimap icon
function DRE:SetMinimapLocked(locked)
    if not self.db then return end
    
    self.db.profile.minimap.lock = locked
    if LibDBIcon then
        if locked then
            LibDBIcon:Lock("DeathRollEnhancer")
        else
            LibDBIcon:Unlock("DeathRollEnhancer")
        end
    end
end

-- Get minimap icon position
function DRE:GetMinimapPosition()
    if not self.db then return 225 end
    return self.db.profile.minimap.minimapPos or 225
end

-- Set minimap icon position
function DRE:SetMinimapPosition(angle)
    if not self.db then return end
    
    self.db.profile.minimap.minimapPos = angle
    if LibDBIcon then
        LibDBIcon:Refresh("DeathRollEnhancer")
    end
end

-- Handle minimap-related slash commands (legacy support)
function DRE:HandleMinimapSlashCommand(args)
    if not args or args == "" then
        self:Print("Minimap commands:")
        self:Print("/dr minimap show - Show minimap icon")
        self:Print("/dr minimap hide - Hide minimap icon")
        self:Print("/dr minimap lock - Lock minimap icon")
        self:Print("/dr minimap unlock - Unlock minimap icon")
        return
    end
    
    local command = DRE and DRE.Trim and DRE:Trim(args and args:lower() or "") or (args and args:lower() or "")
    
    if command == "show" then
        self.db.profile.minimap.hide = false
        self:ToggleMinimapIcon()
        self:Print("Minimap icon shown")
        
    elseif command == "hide" then
        self.db.profile.minimap.hide = true
        self:ToggleMinimapIcon()
        self:Print("Minimap icon hidden")
        
    elseif command == "lock" then
        self:SetMinimapLocked(true)
        self:Print("Minimap icon locked")
        
    elseif command == "unlock" then
        self:SetMinimapLocked(false)
        self:Print("Minimap icon unlocked")
        
    else
        self:Print("Unknown minimap command: " .. command)
    end
end

-- Cleanup minimap integration
function DRE:CleanupMinimap()
    if LibDBIcon then
        LibDBIcon:Hide("DeathRollEnhancer")
    end
end
