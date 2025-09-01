-- Minimap.lua
-- Minimap icon functionality

local addonName, DeathRollEnhancer = ...
local DRE = DeathRollEnhancer

-- Create Minimap module
DRE.Minimap = {}
local Minimap = DRE.Minimap

-- LibDBIcon reference
local LibDBIcon = LibStub("LibDBIcon-1.0")

-- Default minimap button position
local DEFAULT_MINIMAP_POSITION = {
    minimapPos = 225, -- Default angle position around the minimap
    hide = false,     -- Minimap icon visibility
}

-- Minimap button object
Minimap.miniButton = nil

function Minimap:Initialize()
    if not LibDBIcon then
        print("|cFFFF0000<< |r|cFFFF0000Death|r|cFFFFFFFFRoll|r Enhancer: |cFFFF0000LibDBIcon-1.0 not found >>")
        return
    end
    
    self:CreateMinimapButton()
    self:RestoreButtonPosition()
    self:RegisterCallbacks()
end

function Minimap:CreateMinimapButton()
    -- Create the minimap button using LibDataBroker
    self.miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("DeathRollEnhancer", {
        type = "data source",
        text = "DeathRoll Enhancer",
        icon = "Interface\\AddOns\\DeathRollEnhancer\\Media\\Logo",
        OnClick = function(self, btn)
            Minimap:OnButtonClick(btn)
        end,
        OnTooltipShow = function(tooltip)
            Minimap:OnTooltipShow(tooltip)
        end,
    })
end

function Minimap:OnButtonClick(button)
    if not DRE.UI then return end
    
    if button == "LeftButton" then
        if DRE.UI.mainFrame and DRE.UI.mainFrame:IsVisible() then
            DRE.UI:HideUI(false)
        else
            DRE.UI:ShowUI()
        end
    elseif button == "RightButton" then
        -- Show context menu
        self:ShowContextMenu()
    end
end

function Minimap:OnTooltipShow(tooltip)
    if not tooltip or not tooltip.AddLine then return end
    
    tooltip:AddLine("|cFFFF0000Death|r|cFFFF0000Roll|r Enhancer")
    tooltip:AddLine("|cff808080Left Click:|r Toggle UI")
    tooltip:AddLine("|cff808080Right Click:|r Options Menu")
    tooltip:AddLine("|cff808080Commands:|r /dr, /drh, /drreset")
end

function Minimap:ShowContextMenu()
    -- Show available options in chat
    print("|cFF00FF00DeathRoll Options Menu:|r")
    print("|cFFFFFF00→|r |cFFFFFFFF/dr|r - Open DeathRoll UI")
    print("|cFFFFFF00→|r |cFFFFFFFF/drreset|r - Reset UI Scale")
    print("|cFFFFFF00→|r |cFFFFFFFF/drm hide|r - Hide minimap icon")
    print("|cFFFFFF00→|r |cFFFFFFFF/drh [player]|r - View player history")
end

function Minimap:ToggleIcon()
    if not LibDBIcon then return end
    
    if LibDBIcon:IsRegistered("DeathRollEnhancer") then
        local isHidden = LibDBIcon:IsHidden("DeathRollEnhancer")
        if isHidden then
            LibDBIcon:Show("DeathRollEnhancer")
            print("|cFF00FF00DeathRoll: |rMinimap icon shown. Use /deathrollminimap hide to hide it.")
        else
            LibDBIcon:Hide("DeathRollEnhancer")
            print("|cFF00FF00DeathRoll: |rMinimap icon hidden. Use /deathrollminimap show to show it.")
        end
        
        -- Save the new state
        if DRE.Database then
            DRE.Database.settings.hide = LibDBIcon:IsHidden("DeathRollEnhancer")
        end
    end
end

function Minimap:SaveButtonPosition()
    if not LibDBIcon or not DRE.Database then return end
    
    -- Save the current position to settings
    local settings = DRE.Database.settings
    settings.minimapPos = LibDBIcon:GetMinimapButtonPosition("DeathRollEnhancer")
    settings.hide = settings.hide or false
end

function Minimap:RestoreButtonPosition()
    if not LibDBIcon or not DRE.Database then return end
    
    local settings = DRE.Database.settings
    local pos = settings.minimapPos or DEFAULT_MINIMAP_POSITION.minimapPos
    local hide = settings.hide or DEFAULT_MINIMAP_POSITION.hide
    
    LibDBIcon:Register("DeathRollEnhancer", self.miniButton, {
        minimapPos = pos,
        hide = hide,
        lock = false
    })
end

function Minimap:RegisterCallbacks()
    if not LibDBIcon then return end
    
    -- Register callback to save position when icon is moved
    LibDBIcon:RegisterCallback("LibDBIcon_IconMoved", function(name, position)
        if name == "DeathRollEnhancer" and DRE.Database then
            DRE.Database.settings.minimapPos = position
            self:SaveButtonPosition()
        end
    end)
end

function Minimap:ShowIcon()
    if LibDBIcon then
        LibDBIcon:Show("DeathRollEnhancer")
        if DRE.Database then
            DRE.Database.settings.hide = false
        end
        print("DeathRoll Enhancer minimap icon shown.")
    end
end

function Minimap:HideIcon()
    if LibDBIcon then
        LibDBIcon:Hide("DeathRollEnhancer")
        if DRE.Database then
            DRE.Database.settings.hide = true
        end
        print("DeathRoll Enhancer minimap icon hidden.")
    end
end

function Minimap:IsIconVisible()
    if not LibDBIcon then return false end
    return not LibDBIcon:IsButtonHidden("DeathRollEnhancer")
end

function Minimap:ToggleIcon()
    if self:IsIconVisible() then
        self:HideIcon()
    else
        self:ShowIcon()
    end
end

function Minimap:HandleSlashCommand(msg)
    local command = msg:lower():trim()
    
    if command == "show" then
        self:ShowIcon()
    elseif command == "hide" then
        self:HideIcon()
    elseif command == "toggle" then
        self:ToggleIcon()
    else
        print("DeathRoll Enhancer Minimap Commands:")
        print("  /deathrollminimap show - Show the minimap icon")
        print("  /deathrollminimap hide - Hide the minimap icon")
        print("  /deathrollminimap toggle - Toggle the minimap icon")
    end
end

-- Get minimap button position for saving
function Minimap:GetButtonPosition()
    if LibDBIcon then
        return LibDBIcon:GetMinimapButtonPosition("DeathRollEnhancer")
    end
    return nil
end

-- Set minimap button position
function Minimap:SetButtonPosition(position)
    if LibDBIcon and position then
        LibDBIcon:SetButtonPosition("DeathRollEnhancer", position)
    end
end

-- Reset minimap button to default position
function Minimap:ResetButtonPosition()
    self:SetButtonPosition(DEFAULT_MINIMAP_POSITION.minimapPos)
    if DRE.Database then
        DRE.Database.settings.minimapPos = DEFAULT_MINIMAP_POSITION.minimapPos
        DRE.Database.settings.hide = DEFAULT_MINIMAP_POSITION.hide
    end
    print("DeathRoll Enhancer minimap button reset to default position.")
end