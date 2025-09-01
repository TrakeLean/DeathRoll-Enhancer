-- UI.lua
-- AceGUI-based user interface components

local addonName, addonTable = ...
local DRE = _G.DeathRollEnhancer
if not DRE then return end

local AceGUI = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

-- UI Manager
DRE.UI = {}
local UI = DRE.UI

-- UI state
UI.mainWindow = nil
UI.currentTarget = nil
UI.isGameActive = false
UI.playerRoll = nil
UI.opponentRoll = nil
UI.gameState = "WAITING" -- WAITING, ROLLING, FINISHED

-- Initialize UI system
function DRE:InitializeUI()
    self.UI = self.UI or {}
end

-- Create main DeathRoll window using AceGUI
function DRE:ShowMainWindow()
    if UI.mainWindow then
        UI.mainWindow:Show()
        return
    end
    
    -- Create main window frame
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("DeathRoll Enhancer v" .. self.version)
    frame:SetStatusText("Ready to roll!")
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)
    frame:SetLayout("Flow")
    frame:SetWidth(400)
    frame:SetHeight(500)
    
    -- Apply scaling from settings
    if self.db and self.db.profile.ui.scale then
        frame.frame:SetScale(self.db.profile.ui.scale)
    end
    
    UI.mainWindow = frame
    
    -- Create UI components
    self:CreateGameSection(frame)
    self:CreateStatsSection(frame)
    self:CreateHistorySection(frame)
    
    frame:Show()
end

-- Create game control section
function DRE:CreateGameSection(container)
    local gameGroup = AceGUI:Create("SimpleGroup")
    gameGroup:SetFullWidth(true)
    gameGroup:SetLayout("Flow")
    container:AddChild(gameGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("Start DeathRoll")
    header:SetFullWidth(true)
    gameGroup:AddChild(header)
    
    -- Target selection
    local targetGroup = AceGUI:Create("SimpleGroup")
    targetGroup:SetFullWidth(true)
    targetGroup:SetLayout("Flow")
    gameGroup:AddChild(targetGroup)
    
    local targetLabel = AceGUI:Create("Label")
    targetLabel:SetText("Target:")
    targetLabel:SetWidth(80)
    targetGroup:AddChild(targetLabel)
    
    local targetEdit = AceGUI:Create("EditBox")
    targetEdit:SetLabel("")
    targetEdit:SetWidth(200)
    targetEdit:SetText(UnitName("target") or "")
    targetEdit:SetCallback("OnTextChanged", function(widget, event, text)
        UI.currentTarget = text
    end)
    targetGroup:AddChild(targetEdit)
    
    local targetButton = AceGUI:Create("Button")
    targetButton:SetText("Target")
    targetButton:SetWidth(100)
    targetButton:SetCallback("OnClick", function()
        local target = UnitName("target")
        if target then
            targetEdit:SetText(target)
            UI.currentTarget = target
        else
            self:Print("No target selected!")
        end
    end)
    targetGroup:AddChild(targetButton)
    
    -- Roll amount section
    local rollGroup = AceGUI:Create("SimpleGroup")
    rollGroup:SetFullWidth(true)
    rollGroup:SetLayout("Flow")
    gameGroup:AddChild(rollGroup)
    
    local rollLabel = AceGUI:Create("Label")
    rollLabel:SetText("Roll:")
    rollLabel:SetWidth(80)
    rollGroup:AddChild(rollLabel)
    
    local rollEdit = AceGUI:Create("EditBox")
    rollEdit:SetLabel("")
    rollEdit:SetWidth(120)
    rollEdit:SetText("100")
    rollGroup:AddChild(rollEdit)
    
    -- Start game button
    local startButton = AceGUI:Create("Button")
    startButton:SetText("Challenge to DeathRoll!")
    startButton:SetFullWidth(true)
    startButton:SetCallback("OnClick", function()
        local target = targetEdit:GetText()
        local roll = tonumber(rollEdit:GetText())
        
        if not target or target == "" then
            self:Print("Please enter a target name!")
            return
        end
        
        if not roll or roll < 2 then
            self:Print("Roll must be at least 2!")
            return
        end
        
        self:StartDeathRoll(target, roll)
    end)
    gameGroup:AddChild(startButton)
    
    -- Game status
    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetText("")
    statusLabel:SetFullWidth(true)
    statusLabel:SetColor(1, 1, 0) -- Yellow text
    gameGroup:AddChild(statusLabel)
    
    UI.statusLabel = statusLabel
end

-- Create stats section
function DRE:CreateStatsSection(container)
    local statsGroup = AceGUI:Create("InlineGroup")
    statsGroup:SetTitle("Statistics")
    statsGroup:SetFullWidth(true)
    statsGroup:SetLayout("Flow")
    container:AddChild(statsGroup)
    
    if not self.db or not self.db.profile.goldTracking then
        return
    end
    
    local stats = self.db.profile.goldTracking
    
    -- Stats display
    local statsText = string.format(
        "Gold Won: %s\nGold Lost: %s\nCurrent Streak: %d\nBest Win Streak: %d\nWorst Loss Streak: %d",
        self:FormatGold(stats.totalWon or 0),
        self:FormatGold(stats.totalLost or 0),
        stats.currentStreak or 0,
        stats.bestWinStreak or 0,
        stats.worstLossStreak or 0
    )
    
    local statsLabel = AceGUI:Create("Label")
    statsLabel:SetText(statsText)
    statsLabel:SetFullWidth(true)
    statsGroup:AddChild(statsLabel)
    
    UI.statsLabel = statsLabel
end

-- Create history section
function DRE:CreateHistorySection(container)
    local historyGroup = AceGUI:Create("InlineGroup")
    historyGroup:SetTitle("Recent History")
    historyGroup:SetFullWidth(true)
    historyGroup:SetLayout("Fill")
    container:AddChild(historyGroup)
    
    local historyBox = AceGUI:Create("MultiLineEditBox")
    historyBox:SetText("Recent games will appear here...")
    historyBox:SetNumLines(8)
    historyBox:DisableButton(true)
    historyBox:SetFullWidth(true)
    historyBox:SetFullHeight(true)
    historyGroup:AddChild(historyBox)
    
    UI.historyBox = historyBox
end

-- Start a DeathRoll game
function DRE:StartDeathRoll(target, initialRoll)
    if not target or target == "" then
        self:Print("Invalid target!")
        return
    end
    
    UI.currentTarget = target
    UI.isGameActive = true
    UI.gameState = "ROLLING"
    
    -- Send challenge message
    local message = string.format("challenges you to a DeathRoll! Starting at %d. Type /roll %d to accept!", initialRoll)
    SendChatMessage(target .. " " .. message, "SAY")
    
    if UI.statusLabel then
        UI.statusLabel:SetText("Challenging " .. target .. " to DeathRoll starting at " .. initialRoll)
    end
    
    self:Print("Challenged " .. target .. " to DeathRoll starting at " .. initialRoll)
end

-- Update UI scale
function DRE:UpdateUIScale()
    if UI.mainWindow and UI.mainWindow.frame then
        local scale = self.db.profile.ui.scale or 1.0
        UI.mainWindow.frame:SetScale(scale)
    end
end

-- Format gold amount for display
function DRE:FormatGold(amount)
    if amount == 0 then
        return "0g"
    end
    
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    
    local result = ""
    if gold > 0 then
        result = gold .. "g"
    end
    if silver > 0 then
        result = result .. (result ~= "" and " " or "") .. silver .. "s"
    end
    if copper > 0 then
        result = result .. (result ~= "" and " " or "") .. copper .. "c"
    end
    
    return result ~= "" and result or "0c"
end

-- Show player history
function DRE:ShowHistory(playerName)
    if not self.db or not self.db.profile.history then
        self:Print("No history data available")
        return
    end
    
    local playerData = self.db.profile.history[playerName]
    if not playerData then
        self:Print("No history found for " .. playerName)
        return
    end
    
    -- Create history window
    local histFrame = AceGUI:Create("Frame")
    histFrame:SetTitle("History with " .. playerName)
    histFrame:SetLayout("Fill")
    histFrame:SetWidth(500)
    histFrame:SetHeight(400)
    
    local histText = AceGUI:Create("MultiLineEditBox")
    histText:SetText(self:FormatPlayerHistory(playerData))
    histText:DisableButton(true)
    histText:SetFullWidth(true)
    histText:SetFullHeight(true)
    histFrame:AddChild(histText)
    
    histFrame:Show()
end

-- Format player history for display
function DRE:FormatPlayerHistory(playerData)
    if not playerData then
        return "No data available"
    end
    
    local text = string.format("Games Played: %d\n", playerData.gamesPlayed or 0)
    text = text .. string.format("Wins: %d\n", playerData.wins or 0)
    text = text .. string.format("Losses: %d\n", playerData.losses or 0)
    text = text .. string.format("Gold Won: %s\n", self:FormatGold(playerData.goldWon or 0))
    text = text .. string.format("Gold Lost: %s\n", self:FormatGold(playerData.goldLost or 0))
    
    if playerData.recentGames then
        text = text .. "\nRecent Games:\n"
        for i, game in ipairs(playerData.recentGames) do
            if i > 10 then break end -- Show only last 10 games
            text = text .. string.format("%s - %s (%s)\n", 
                game.date or "Unknown", 
                game.result or "Unknown",
                self:FormatGold(game.goldAmount or 0))
        end
    end
    
    return text
end

-- Update stats display
function DRE:UpdateStatsDisplay()
    if not UI.statsLabel or not self.db or not self.db.profile.goldTracking then
        return
    end
    
    local stats = self.db.profile.goldTracking
    local statsText = string.format(
        "Gold Won: %s\nGold Lost: %s\nCurrent Streak: %d\nBest Win Streak: %d\nWorst Loss Streak: %d",
        self:FormatGold(stats.totalWon or 0),
        self:FormatGold(stats.totalLost or 0),
        stats.currentStreak or 0,
        stats.bestWinStreak or 0,
        stats.worstLossStreak or 0
    )
    
    UI.statsLabel:SetText(statsText)
end

-- Clean up UI
function DRE:CleanupUI()
    if UI.mainWindow then
        UI.mainWindow:Hide()
        UI.mainWindow = nil
    end
end