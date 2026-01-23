-- Minimap.lua
-- Minimap integration using LibDBIcon

local addonName, addonTable = ...
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
if not DRE then return end

local LibDBIcon = LibStub("LibDBIcon-1.0", true)
local LDB = LibStub("LibDataBroker-1.1", true)

-- Create data broker object - LibDBIcon can work without LibDataBroker in many cases
local minimapLDB = {
    type = "data source",
    text = "DeathRoll",
    icon = "Interface\\AddOns\\DeathRollEnhancer\\Media\\Logo.tga",
    OnClick = function(frame, button)
        if button == "LeftButton" then
            DRE:ShowMainWindow()
        elseif button == "RightButton" then
            DRE:OpenOptions()
        end
    end,
    OnTooltipShow = function(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        
        tooltip:AddLine("|cFFFF0000Death|r|cFFFFFFFFRoll|r Enhancer v" .. DRE.version)
        tooltip:AddLine(" ")
        tooltip:AddLine("|cFFFFFFFFLeft Click:|r Open DeathRoll window")
        tooltip:AddLine("|cFFFFFFFFRight Click:|r Open options")
        
        if DRE.db and DRE.db.profile.goldTracking then
            local stats = DRE.db.profile.goldTracking
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFFFFD700Statistics:|r")
            
            if stats.totalWon and stats.totalWon > 0 then
                tooltip:AddLine("|cFF00FF00Gold Won:|r " .. DRE:FormatGold(stats.totalWon))
            end
            
            if stats.totalLost and stats.totalLost > 0 then
                tooltip:AddLine("|cFFFF0000Gold Lost:|r " .. DRE:FormatGold(stats.totalLost))
            end
            
            if stats.currentStreak and stats.currentStreak ~= 0 then
                local streakText = stats.currentStreak > 0 and 
                    "|cFF00FF00Win Streak: " .. stats.currentStreak .. "|r" or
                    "|cFFFF0000Loss Streak: " .. math.abs(stats.currentStreak) .. "|r"
                tooltip:AddLine(streakText)
            end
        end
        
        tooltip:Show()
    end,
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
    LibDBIcon:Register("DeathRollEnhancer", minimapLDB, self.db.profile.minimap)
    
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
        LibDBIcon:Lock("DeathRollEnhancer")
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