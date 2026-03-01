-- UI.lua
-- AceGUI-based user interface components

local addonName, addonTable = ...
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
if not DRE then return end

local AceGUI = LibStub("AceGUI-3.0", true)
local LSM = LibStub("LibSharedMedia-3.0", true)

-- UI Manager
DRE.UI = {}
local UI = DRE.UI

-- UI state
UI.mainWindow = nil
UI.isGameActive = false
UI.playerRoll = nil
UI.opponentRoll = nil
UI.gameState = "WAITING" -- WAITING, ROLLING, FINISHED
UI.rollHistory = {}

-- Initialize UI system
function DRE:InitializeUI()
    self.UI = self.UI or {}
end

function DRE:UpdateMainTabLayout()
    if not (self.UI and self.UI.tabGroup and self.UI.tabGroup.tabs) then
        return
    end

    local tabGroup = self.UI.tabGroup
    local tabCount = #tabGroup.tabs
    if tabCount == 0 then
        return
    end

    local availableWidth = 0
    if tabGroup.border and tabGroup.border.GetWidth then
        availableWidth = tabGroup.border:GetWidth() or 0
    end
    if availableWidth <= 0 and self.UI.mainWindow and self.UI.mainWindow.frame then
        availableWidth = self.UI.mainWindow.frame:GetWidth() or 0
    end
    if availableWidth <= 0 and tabGroup.frame and tabGroup.frame.GetWidth then
        availableWidth = tabGroup.frame:GetWidth() or 0
    end
    if availableWidth <= 0 then
        return
    end

    local tabWidth = math.floor((availableWidth - 28) / tabCount)
    if tabWidth < 90 then
        return
    end

    for _, tab in ipairs(tabGroup.tabs) do
        if tab and tab.SetWidth then
            tab:SetWidth(tabWidth)
        end
        if tab and tab.frame and tab.frame.SetWidth then
            tab.frame:SetWidth(tabWidth)
        end
        if tab and tab.text and tab.text.SetWidth then
            tab.text:SetWidth(tabWidth - 20)
            tab.text:SetJustifyH("CENTER")
        end
    end
end

function DRE:EnsureRollHistoryPanel()
    -- Roll history is rendered inside the main window.
end

function DRE:ShowRollHistoryPanel()
    -- Roll history is rendered inside the main window.
end

function DRE:HideRollHistoryPanel()
    -- Roll history is rendered inside the main window.
end

function DRE:UpdateRollHistoryPanelVisibility()
    -- Roll history is rendered inside the main window.
end

function DRE:ReleaseEmbeddedRollHistory()
    if UI.rollHistoryScroll then
        UI.rollHistoryScroll:Hide()
        UI.rollHistoryScroll:ClearAllPoints()
    end

    if UI.rollHistoryContent then
        UI.rollHistoryContent:Hide()
    end

    if UI.rollHistoryBox then
        UI.rollHistoryBox:Hide()
    end
end

function DRE:UpdateRollHistoryPanelLayout()
    if not (UI.rollHistoryGroup and UI.rollHistoryScroll and UI.rollHistoryContent and UI.rollHistoryBox) then
        return
    end

    local contentFrame = UI.rollHistoryGroup.content or UI.rollHistoryGroup.frame
    if not contentFrame then
        return
    end

    local scrollWidth = math.max(160, contentFrame:GetWidth() or 0)
    local textWidth = math.max(154, scrollWidth - 6)
    local scrollHeight = math.max(UI.rollHistoryScroll:GetHeight() or 0, contentFrame:GetHeight() or 0)

    UI.rollHistoryBox:SetWidth(textWidth)
    UI.rollHistoryContent:SetWidth(scrollWidth)

    local textHeight = UI.rollHistoryBox:GetStringHeight() or 0
    UI.rollHistoryContent:SetHeight(math.max(scrollHeight, textHeight + 4))
end

function DRE:RefreshVisibleUILayout()
    if not UI.mainWindow then
        return
    end

    if UI.mainWindow.DoLayout then
        UI.mainWindow:DoLayout()
    end

    if UI.tabGroup and UI.tabGroup.DoLayout then
        UI.tabGroup:DoLayout()
    end

    if UI.settingsContent and UI.settingsContent.DoLayout then
        UI.settingsContent:DoLayout()
    end

    if UI.settingsScroll and UI.settingsScroll.DoLayout then
        UI.settingsScroll:DoLayout()
    end

    self:UpdateMainTabLayout()
    self:UpdateGameSectionLayout()
    self:UpdateHistorySectionLayout()
end

function DRE:QueueLayoutRefresh()
    if not UI.mainWindow then
        return
    end

    UI.layoutRefreshToken = (UI.layoutRefreshToken or 0) + 1
    local refreshToken = UI.layoutRefreshToken

    self:RefreshVisibleUILayout()

    local function runDeferredRefresh()
        if not (self and self.UI and self.UI.mainWindow and self.UI.layoutRefreshToken == refreshToken) then
            return
        end

        self:RefreshVisibleUILayout()
    end

    C_Timer.After(0, runDeferredRefresh)
    C_Timer.After(0.05, runDeferredRefresh)
end


-- Create main DeathRoll window using AceGUI
function DRE:ShowMainWindow()
    if not AceGUI then
        self:Print("AceGUI-3.0 not available. Please install Ace3.")
        return
    end
    
    if UI.mainWindow then
        UI.mainWindow:Show()
        self:UpdateMainTabLayout()
        self:UpdateRollHistoryPanelVisibility()
        -- Check for recent rolls when reopening UI
        self:CheckRecentRollsForChallenge()
        return
    end
    
    -- Create main window frame (initially hidden to prevent flash)
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("DeathRoll Enhancer")
    frame:SetStatusText("v" .. self.version .. " - SKEM Edition")
    frame:SetCallback("OnClose", function(widget)
        self:HideRollHistoryPanel()
        widget:Hide()
    end)
    
    -- Hide frame initially to prevent flash during setup
    frame.frame:Hide()
    
    -- Set default dimensions first
    frame:SetWidth(400)
    frame:SetHeight(311)
    frame:SetLayout("Fill")
    
    -- Set up AceGUI status table (this will override defaults if saved values exist)
    if not self.db.profile.ui.frameStatus then
        self.db.profile.ui.frameStatus = {}
    end
    
    frame:SetStatusTable(self.db.profile.ui.frameStatus)
    frame:EnableResize(true)
    
    -- For first-time users, ensure correct dimensions immediately (no timer)
    if not self.db.profile.ui.frameStatus.width and not self.db.profile.ui.frameStatus.height then
        -- This is likely first time opening - ensure proper sizing immediately
        frame:SetWidth(400)
        frame:SetHeight(311)
        self:DebugPrint("Applied first-time window dimensions")
    end

    -- Apply scaling AFTER dimensions are set but BEFORE AceGUI restoration
    local scaleValue = (self.db and self.db.profile.ui.scale) or 0.9
    frame.frame:SetScale(scaleValue)
    self:DebugPrint("Applied initial scale: " .. scaleValue)

    -- Hook ApplyStatus to maintain scale after position/size restoration
    local originalApplyStatus = frame.ApplyStatus
    frame.ApplyStatus = function(self_frame)
        -- Temporarily store current scale
        local currentScale = self_frame.frame:GetScale()

        -- Apply position/size restoration
        originalApplyStatus(self_frame)

        -- Reapply scale to prevent double-scaling
        local savedScale = (DRE.db and DRE.db.profile.ui.scale) or 0.9
        if math.abs(currentScale - savedScale) > 0.01 then  -- Only reapply if different
            self_frame.frame:SetScale(savedScale)
            DRE:DebugPrint("Frame status applied - scale corrected to: " .. savedScale)
        end

        DRE:QueueLayoutRefresh()
    end
    
    -- Position/size restoration is now handled by AceGUI status table
    
    UI.mainWindow = frame
    
    -- Create TabGroup
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Fill")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    tabGroup:SetTabs({
        {text="DeathRoll", value="deathroll"},
        {text="Statistics", value="statistics"}, 
        {text="History", value="history"},
        {text="Settings", value="settings"}
    })
    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        self:ReleaseEmbeddedRollHistory()
        container:ReleaseChildren()
        -- Clear UI references when switching tabs to prevent cross-contamination
        UI.statsLabel = nil
        UI.streakLabel = nil
        UI.funStatsLabel = nil
        UI.rollHistoryBox = nil
        UI.rollHistoryScroll = nil
        UI.rollHistoryContent = nil
        UI.historyBox = nil
        UI.historyScroll = nil
        UI.historyDropdown = nil
        UI.settingsScroll = nil
        UI.settingsContent = nil
        UI.tradeWagerHelp = nil
        -- Clear challenge UI references too
        UI.gameContainer = nil
        UI.gameGroup = nil
        UI.gameControlsGroup = nil
        UI.rollHistoryGroup = nil
        UI.rollInputGroup = nil
        UI.wagerGroup = nil
        UI.wagerHeader = nil
        UI.goldPairGroup = nil
        UI.silverPairGroup = nil
        UI.copperPairGroup = nil
        UI.goldUnitLabel = nil
        UI.silverUnitLabel = nil
        UI.copperUnitLabel = nil
        UI.autoRollButton = nil
        UI.historyGroup = nil
        UI.historyControlsGroup = nil
        UI.historyDisplayGroup = nil
        UI.rollEdit = nil
        UI.gameButton = nil
        UI.goldEdit = nil
        UI.silverEdit = nil
        UI.copperEdit = nil
        
        -- Track current tab
        UI.currentTab = group
        
        if group == "deathroll" then
            self:CreateGameSection(container)
            -- Check for recent rolls when switching to deathroll tab
            self:CheckRecentRollsForChallenge()
        elseif group == "statistics" then
            self:CreateStatsSection(container)
        elseif group == "history" then
            self:CreateHistorySection(container)
        elseif group == "settings" then
            self:CreateSettingsSection(container)
        end

        self:UpdateRollHistoryPanelVisibility()
    end)
    tabGroup:SelectTab("deathroll") -- Default to DeathRoll tab
    
    frame:AddChild(tabGroup)
    UI.tabGroup = tabGroup
    
    -- Show the frame AFTER all setup is complete to prevent flash
    frame:Show()

    frame.frame:HookScript("OnSizeChanged", function()
        self:RefreshVisibleUILayout()
        C_Timer.After(0, function()
            self:RefreshVisibleUILayout()
        end)
    end)

    C_Timer.After(0, function()
        self:QueueLayoutRefresh()
        self:UpdateRollHistoryPanelVisibility()
    end)
    
    -- Check for recent rolls when first opening UI
    self:CheckRecentRollsForChallenge()
end

-- Create game control section
function DRE:CreateGameSection(container)
    local gameGroup = AceGUI:Create("SimpleGroup")
    gameGroup:SetFullWidth(true)
    gameGroup:SetFullHeight(true)
    gameGroup:SetLayout("List")
    container:AddChild(gameGroup)

    local controlsGroup = AceGUI:Create("SimpleGroup")
    controlsGroup:SetFullWidth(true)
    controlsGroup:SetLayout("List")
    gameGroup:AddChild(controlsGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("Start DeathRoll")
    header:SetFullWidth(true)
    controlsGroup:AddChild(header)
    
    -- Target info display
    local targetInfo = AceGUI:Create("Label")
    targetInfo:SetText("Target someone in-game, then click Challenge!")
    targetInfo:SetFullWidth(true)
    targetInfo:SetColor(0.8, 0.8, 0.8)
    controlsGroup:AddChild(targetInfo)
    
    local rollGroup = AceGUI:Create("SimpleGroup")
    rollGroup:SetFullWidth(true)
    rollGroup:SetLayout("Flow")
    controlsGroup:AddChild(rollGroup)

    local rollLabel = AceGUI:Create("Label")
    rollLabel:SetText("Roll:")
    rollLabel:SetWidth(34)
    rollGroup:AddChild(rollLabel)

    local rollEdit = AceGUI:Create("EditBox")
    rollEdit:SetLabel("")
    rollEdit:SetWidth(90)
    
    rollEdit:SetText("100")
    
    rollEdit:SetMaxLetters(6) -- Limit to 6 digits
    rollEdit:SetCallback("OnTextChanged", function(widget, event, text)
        -- Only allow numbers
        local numericText = text:gsub("[^0-9]", "")
        if numericText ~= text then
            widget:SetText(numericText)
        end
        -- Ensure it doesn't exceed 6 digits
        if #numericText > 6 then
            widget:SetText(numericText:sub(1, 6))
        end
    end)
    rollGroup:AddChild(rollEdit)

    local autoRollButton = AceGUI:Create("Button")
    autoRollButton:SetText("Use My Gold")
    autoRollButton:SetWidth(110)
    autoRollButton:SetCallback("OnClick", function()
        local autoRoll = self:CalculateAutoRoll()
        rollEdit:SetText(tostring(autoRoll))
        self:DebugPrint("Roll input set from money: " .. autoRoll)
    end)
    rollGroup:AddChild(autoRollButton)
    
    -- Store roll edit reference
    UI.rollEdit = rollEdit
    
    local goldEdit = nil
    local silverEdit = nil
    local copperEdit = nil
    local tradeWagerHelp = nil
    local wagerGroup = nil
    local wagerHeader = nil
    local goldPairGroup = nil
    local silverPairGroup = nil
    local copperPairGroup = nil
    local goldUnitLabel = nil
    local silverUnitLabel = nil
    local copperUnitLabel = nil

    if self:IsTradeWagerModeEnabled() then
        tradeWagerHelp = AceGUI:Create("Label")
        tradeWagerHelp:SetText("Wager tracking is set to trades. Complete a gold trade after the game and the wager will be recorded automatically.")
        tradeWagerHelp:SetFullWidth(true)
        tradeWagerHelp:SetColor(0.85, 0.82, 0.45)
        controlsGroup:AddChild(tradeWagerHelp)
    else
        wagerGroup = AceGUI:Create("SimpleGroup")
        wagerGroup:SetFullWidth(true)
        wagerGroup:SetLayout("Flow")
        controlsGroup:AddChild(wagerGroup)

        wagerHeader = AceGUI:Create("Label")
        wagerHeader:SetText("Wager:")
        wagerHeader:SetWidth(45)
        wagerHeader:SetColor(0.85, 0.85, 0.85)
        wagerGroup:AddChild(wagerHeader)
        
        goldEdit = AceGUI:Create("EditBox")
        goldEdit:SetLabel("")
        goldEdit:SetWidth(54)
        goldEdit:SetText("")
        goldEdit:SetMaxLetters(6)
        goldEdit:DisableButton(true)
        
        goldEdit:SetCallback("OnTextChanged", function(widget, event, text)
            local numericText = text:gsub("[^0-9]", "")
            if numericText ~= text then
                widget:SetText(numericText)
            end
        end)

        goldPairGroup = AceGUI:Create("SimpleGroup")
        goldPairGroup:SetWidth(86)
        goldPairGroup:SetLayout("Flow")
        wagerGroup:AddChild(goldPairGroup)
        goldPairGroup:AddChild(goldEdit)

        goldUnitLabel = AceGUI:Create("Label")
        goldUnitLabel:SetText("Gold")
        goldUnitLabel:SetWidth(30)
        goldPairGroup:AddChild(goldUnitLabel)
        
        silverEdit = AceGUI:Create("EditBox")
        silverEdit:SetLabel("")
        silverEdit:SetWidth(40)
        silverEdit:SetText("")
        silverEdit:SetMaxLetters(2)
        silverEdit:DisableButton(true)
        
        silverEdit:SetCallback("OnTextChanged", function(widget, event, text)
            local numericText = text:gsub("[^0-9]", "")
            if numericText ~= text then
                widget:SetText(numericText)
            end
            local num = tonumber(numericText)
            if num and num > 99 then
                widget:SetText("99")
            end
        end)

        silverPairGroup = AceGUI:Create("SimpleGroup")
        silverPairGroup:SetWidth(92)
        silverPairGroup:SetLayout("Flow")
        wagerGroup:AddChild(silverPairGroup)
        silverPairGroup:AddChild(silverEdit)

        silverUnitLabel = AceGUI:Create("Label")
        silverUnitLabel:SetText("Silver")
        silverUnitLabel:SetWidth(36)
        silverPairGroup:AddChild(silverUnitLabel)
        
        copperEdit = AceGUI:Create("EditBox")
        copperEdit:SetLabel("")
        copperEdit:SetWidth(40)
        copperEdit:SetText("")
        copperEdit:SetMaxLetters(2)
        copperEdit:DisableButton(true)
        
        copperEdit:SetCallback("OnTextChanged", function(widget, event, text)
            local numericText = text:gsub("[^0-9]", "")
            if numericText ~= text then
                widget:SetText(numericText)
            end
            local num = tonumber(numericText)
            if num and num > 99 then
                widget:SetText("99")
            end
        end)

        copperPairGroup = AceGUI:Create("SimpleGroup")
        copperPairGroup:SetWidth(100)
        copperPairGroup:SetLayout("Flow")
        wagerGroup:AddChild(copperPairGroup)
        copperPairGroup:AddChild(copperEdit)

        copperUnitLabel = AceGUI:Create("Label")
        copperUnitLabel:SetText("Copper")
        copperUnitLabel:SetWidth(44)
        copperPairGroup:AddChild(copperUnitLabel)
    end
    
    -- Game action button (changes based on game state)
    local gameButton = AceGUI:Create("Button")
    gameButton:SetText("Challenge Player to DeathRoll!")
    gameButton:SetFullWidth(true)
    gameButton:SetCallback("OnClick", function()
        self:HandleGameButtonClick()
    end)
    controlsGroup:AddChild(gameButton)

    local rollHistoryGroup = AceGUI:Create("InlineGroup")
    rollHistoryGroup:SetTitle("Roll History")
    rollHistoryGroup:SetFullWidth(true)
    rollHistoryGroup:SetHeight(130)
    rollHistoryGroup:SetLayout("Fill")
    gameGroup:AddChild(rollHistoryGroup)

    local historyHost = rollHistoryGroup.content or rollHistoryGroup.frame
    local historyScroll = historyHost.dreRollHistoryScroll
    local historyContent = historyHost.dreRollHistoryContent
    local historyText = historyHost.dreRollHistoryText

    if not historyScroll then
        historyScroll = CreateFrame("ScrollFrame", nil, historyHost)
        historyHost.dreRollHistoryScroll = historyScroll
    end

    if not historyContent then
        historyContent = CreateFrame("Frame", nil, historyScroll)
        historyHost.dreRollHistoryContent = historyContent
    end

    if not historyText then
        historyText = historyContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        historyHost.dreRollHistoryText = historyText
    end

    historyScroll:ClearAllPoints()
    historyScroll:SetPoint("TOPLEFT", historyHost, "TOPLEFT", 0, 0)
    historyScroll:SetPoint("BOTTOMRIGHT", historyHost, "BOTTOMRIGHT", 0, 0)
    historyScroll:EnableMouseWheel(true)
    historyScroll:Show()

    historyContent:ClearAllPoints()
    historyContent:SetPoint("TOPLEFT", historyScroll, "TOPLEFT", 0, 0)
    historyContent:SetWidth(math.max(160, historyHost:GetWidth() or 0))
    historyContent:SetHeight(1)
    historyScroll:SetScrollChild(historyContent)
    historyContent:Show()

    historyText:ClearAllPoints()
    historyText:SetPoint("TOPLEFT", historyContent, "TOPLEFT", 4, -4)
    historyText:SetJustifyH("LEFT")
    historyText:SetJustifyV("TOP")
    historyText:Show()

    historyScroll:SetScript("OnMouseWheel", function(scrollFrame, delta)
        local currentScroll = scrollFrame:GetVerticalScroll() or 0
        local maxScroll = math.max(0, ((UI.rollHistoryContent and UI.rollHistoryContent:GetHeight()) or 0) - (scrollFrame:GetHeight() or 0))
        local nextScroll = currentScroll - (delta * 24)
        if nextScroll < 0 then
            nextScroll = 0
        elseif nextScroll > maxScroll then
            nextScroll = maxScroll
        end
        scrollFrame:SetVerticalScroll(nextScroll)
    end)
    
    -- Store all UI references for later updates
    UI.gameContainer = container
    UI.gameGroup = gameGroup
    UI.gameControlsGroup = controlsGroup
    UI.rollHistoryGroup = rollHistoryGroup
    UI.rollHistoryScroll = historyScroll
    UI.rollHistoryContent = historyContent
    UI.rollHistoryBox = historyText
    UI.rollInputGroup = rollGroup
    UI.autoRollButton = autoRollButton
    UI.wagerGroup = wagerGroup
    UI.wagerHeader = wagerHeader
    UI.goldPairGroup = goldPairGroup
    UI.silverPairGroup = silverPairGroup
    UI.copperPairGroup = copperPairGroup
    UI.goldUnitLabel = goldUnitLabel
    UI.silverUnitLabel = silverUnitLabel
    UI.copperUnitLabel = copperUnitLabel
    UI.goldEdit = goldEdit
    UI.silverEdit = silverEdit
    UI.copperEdit = copperEdit
    UI.gameButton = gameButton
    UI.tradeWagerHelp = tradeWagerHelp
    UI.rollHistory = UI.rollHistory or {}
    if #UI.rollHistory == 0 then
        table.insert(UI.rollHistory, "Ready to start! Target someone and click Challenge Player to DeathRoll!")
    end
    
    self:UpdateWagerInputMode()
    C_Timer.After(0, function()
        self:UpdateGameSectionLayout()
        self:RefreshRollHistoryDisplay()
    end)
    
    -- Update button text with current target initially
    self:UpdateChallengeButtonText()
end

function DRE:UpdateGameSectionLayout()
    if not (UI.gameControlsGroup and UI.gameGroup) then
        return
    end

    local groupFrame = UI.gameGroup.content or UI.gameGroup.frame
    local containerWidth = 0
    if groupFrame then
        containerWidth = groupFrame:GetWidth() or 0
    end
    if containerWidth <= 0 and UI.mainWindow and UI.mainWindow.frame then
        local frame = UI.mainWindow.frame
        containerWidth = (frame:GetWidth() or 400) - 40
    end

    if containerWidth <= 0 then
        return
    end

    self:UpdateGameControlsLayout(math.max(140, containerWidth - 8), containerWidth < 260)

    if UI.gameControlsGroup and UI.gameControlsGroup.DoLayout then
        UI.gameControlsGroup:DoLayout()
    end

    if UI.rollHistoryGroup then
        local containerHeight = 0
        if groupFrame then
            containerHeight = groupFrame:GetHeight() or 0
        end
        if containerHeight <= 0 and UI.mainWindow and UI.mainWindow.frame then
            containerHeight = math.max(220, (UI.mainWindow.frame:GetHeight() or 420) - 120)
        end

        local controlsHeight = 0
        if UI.gameControlsGroup.content then
            controlsHeight = UI.gameControlsGroup.content:GetHeight() or 0
        end
        if controlsHeight <= 0 and UI.gameControlsGroup.frame then
            controlsHeight = UI.gameControlsGroup.frame:GetHeight() or 0
        end

        local availableHeight = containerHeight - controlsHeight - 4
        UI.rollHistoryGroup:SetHeight(math.max(84, availableHeight))
    end

    if UI.gameGroup and UI.gameGroup.DoLayout then
        UI.gameGroup:DoLayout()
    end

    self:UpdateRollHistoryPanelLayout()
end

function DRE:UpdateGameControlsLayout(controlsWidth, isStacked)
    local availableWidth = math.max(120, (controlsWidth or 0) - 24)
    local compactMode = isStacked or availableWidth < 235
    local stackRollControls = isStacked or availableWidth < 250

    if UI.rollEdit then
        UI.rollEdit:SetFullWidth(false)
        local rollEditWidth = 0
        if stackRollControls then
            rollEditWidth = math.max(78, availableWidth - 42)
        else
            rollEditWidth = math.max(82, math.min(140, availableWidth - 154))
        end
        UI.rollEdit:SetWidth(rollEditWidth)
    end

    if UI.autoRollButton then
        UI.autoRollButton:SetFullWidth(stackRollControls)
        if not stackRollControls then
            UI.autoRollButton:SetWidth(110)
        end
    end

    local unitLabelWidths = compactMode and {30, 36, 44} or {30, 36, 44}
    local unitWidthTotal = unitLabelWidths[1] + unitLabelWidths[2] + unitLabelWidths[3]
    local headerWidth = compactMode and 42 or 45
    local wagerFieldWidth = compactMode and 34 or math.max(34, math.min(52, math.floor((availableWidth - headerWidth - unitWidthTotal - 18) / 3)))

    if UI.wagerHeader then
        UI.wagerHeader:SetWidth(headerWidth)
    end

    if UI.goldUnitLabel then
        UI.goldUnitLabel:SetWidth(unitLabelWidths[1])
    end
    if UI.silverUnitLabel then
        UI.silverUnitLabel:SetWidth(unitLabelWidths[2])
    end
    if UI.copperUnitLabel then
        UI.copperUnitLabel:SetWidth(unitLabelWidths[3])
    end

    for _, widget in ipairs({UI.goldEdit, UI.silverEdit, UI.copperEdit}) do
        if widget then
            widget:SetFullWidth(false)
            widget:SetWidth(wagerFieldWidth)
        end
    end

    if UI.goldPairGroup then
        UI.goldPairGroup:SetWidth(wagerFieldWidth + unitLabelWidths[1] + 8)
    end
    if UI.silverPairGroup then
        UI.silverPairGroup:SetWidth(wagerFieldWidth + unitLabelWidths[2] + 8)
    end
    if UI.copperPairGroup then
        UI.copperPairGroup:SetWidth(wagerFieldWidth + unitLabelWidths[3] + 8)
    end

    if UI.rollInputGroup and UI.rollInputGroup.DoLayout then
        UI.rollInputGroup:DoLayout()
    end

    if UI.wagerGroup and UI.wagerGroup.DoLayout then
        UI.wagerGroup:DoLayout()
    end

    if UI.gameControlsGroup and UI.gameControlsGroup.DoLayout then
        UI.gameControlsGroup:DoLayout()
    end
end

function DRE:RefreshRollHistoryDisplay()
    if not UI.rollHistory then
        return
    end

    local historyText = table.concat(UI.rollHistory, "\n")

    if UI.rollHistoryBox then
        pcall(function()
            UI.rollHistoryBox:SetText(historyText)
        end)

        self:UpdateRollHistoryPanelLayout()

        C_Timer.After(0, function()
            if not (UI and UI.rollHistoryScroll and UI.rollHistoryContent) then
                return
            end

            local maxScroll = math.max(0, (UI.rollHistoryContent:GetHeight() or 0) - (UI.rollHistoryScroll:GetHeight() or 0))
            UI.rollHistoryScroll:SetVerticalScroll(maxScroll)
        end)
    end
end

-- Add a roll entry to the history display
function DRE:AddRollToHistory(playerName, roll, maxRoll, isSelfDuel, rollCount)
    -- Validate UI components exist
    if not self.UI then
        return
    end

    if not UI.rollHistory then
        self:DebugPrint("AddRollToHistory: UI components not ready")
        return
    end

    -- Validate parameters
    if not playerName or not roll or not maxRoll then
        self:DebugPrint("AddRollToHistory: Invalid parameters")
        return
    end

    if maxRoll <= 0 then
        self:DebugPrint("AddRollToHistory: Invalid maxRoll value")
        return
    end

    local myName = UnitName("player")
    if not myName then
        self:DebugPrint("AddRollToHistory: Could not get player name")
        return
    end

    local displayName = playerName
    local isMe = (playerName == myName)

    -- For self-duels, alternate the color but keep the same name
    if isSelfDuel and rollCount then
        displayName = myName
        if (rollCount % 2) == 1 then
            isMe = true
        else
            isMe = false
        end
    end

    -- Calculate loss probability (chance of rolling 1)
    local lossChance = (1 / maxRoll) * 100

    -- Create colored entry
    local colorCode = isMe and "|cff00ff00" or "|cffff6666" -- Green for player, red for opponent
    local resetColor = "|r"

    local entry = string.format("%s%s%s rolled %d (1-%d) - %.3f%% chance of losing",
        colorCode, displayName, resetColor, roll, maxRoll, lossChance)

    -- Append to history so the newest messages appear at the bottom like chat.
    table.insert(UI.rollHistory, entry)

    self:RefreshRollHistoryDisplay()
end

-- Update roll history with game status messages (for non-game states only)
function DRE:UpdateRollHistoryStatus(message, clearHistory)
    if not UI.rollHistory then
        return
    end
    
    -- Only clear history if explicitly requested (for new games/challenges)
    if clearHistory then
        UI.rollHistory = {}
    end

    if message and message ~= "" then
        table.insert(UI.rollHistory, message)
    end

    self:RefreshRollHistoryDisplay()
end

-- Clear roll history for new game
function DRE:ClearRollHistory()
    if UI.rollHistory then
        UI.rollHistory = {}
    end
end

-- Add game result to roll history
function DRE:AddGameResultToHistory(result, opponent, wager)
    if not UI.rollHistory then
        return
    end
    
    local resultText = ""
    local colorCode = ""
    
    if result == "WIN" then
        colorCode = "|cff00ff00" -- Bright green
        resultText = "*** YOU WON! ***"
    elseif result == "LOSS" then
        colorCode = "|cffff0000" -- Bright red
        resultText = "*** YOU LOST! ***"
    end
    
    local resetColor = "|r"
    local wagerText = wager and wager > 0 and (" (" .. self:FormatGold(wager) .. ")") or ""
    
    local entry = string.format("%s%s%s vs %s%s", 
        colorCode, resultText, resetColor, opponent or "Unknown", wagerText)
    
    table.insert(UI.rollHistory, entry)

    self:RefreshRollHistoryDisplay()
end

-- Create stats section
function DRE:CreateStatsSection(container)
    local statsGroup = AceGUI:Create("ScrollFrame")
    statsGroup:SetFullWidth(true)
    statsGroup:SetFullHeight(true)
    statsGroup:SetLayout("Flow")
    container:AddChild(statsGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("DeathRoll Statistics")
    header:SetFullWidth(true)
    statsGroup:AddChild(header)
    
    if not self.db or not self.db.profile.goldTracking then
        local noDataLabel = AceGUI:Create("Label")
        noDataLabel:SetText("No statistics available yet. Play some DeathRoll games to see your stats here!")
        noDataLabel:SetFullWidth(true)
        statsGroup:AddChild(noDataLabel)
        return
    end
    
    local stats = self.db.profile.goldTracking
    
    -- Overall statistics
    local overallGroup = AceGUI:Create("InlineGroup")
    overallGroup:SetTitle("Overall Performance")
    overallGroup:SetFullWidth(true)
    overallGroup:SetLayout("Flow")
    statsGroup:AddChild(overallGroup)
    
    -- Calculate total games and win rate
    local totalGames = 0
    local totalWins = 0
    local totalLosses = 0
    if self.db.profile.history then
        for playerName, playerData in pairs(self.db.profile.history) do
            totalWins = totalWins + (playerData.wins or 0)
            totalLosses = totalLosses + (playerData.losses or 0)
        end
    end
    totalGames = totalWins + totalLosses
    local winRate = totalGames > 0 and (totalWins / totalGames * 100) or 0
    
    -- Stats display with better formatting
    local statsText = string.format(
        "Total Games Played: %d\nGames Won: %d\nGames Lost: %d\nWin Rate: %.1f%%\n\nGold Won: %s\nGold Lost: %s\nNet Profit: %s",
        totalGames,
        totalWins,
        totalLosses,
        winRate,
        self:FormatGold(stats.totalWon or 0),
        self:FormatGold(stats.totalLost or 0),
        self:FormatGold((stats.totalWon or 0) - (stats.totalLost or 0))
    )
    
    local statsLabel = AceGUI:Create("Label")
    statsLabel:SetText(statsText)
    statsLabel:SetFullWidth(true)
    overallGroup:AddChild(statsLabel)
    
    -- Streak information
    local streakGroup = AceGUI:Create("InlineGroup")
    streakGroup:SetTitle("Streaks")
    streakGroup:SetFullWidth(true)
    streakGroup:SetLayout("Flow")
    statsGroup:AddChild(streakGroup)
    
    local streakText = string.format(
        "Current Streak: %s%d\nBest Win Streak: %d\nWorst Loss Streak: %d",
        (stats.currentStreak or 0) >= 0 and "+" or "",
        stats.currentStreak or 0,
        stats.bestWinStreak or 0,
        stats.worstLossStreak or 0
    )
    
    local streakLabel = AceGUI:Create("Label")
    streakLabel:SetText(streakText)
    streakLabel:SetFullWidth(true)
    streakGroup:AddChild(streakLabel)
    
    -- Fun Statistics section
    self:CreateFunStatsSection(statsGroup)
    
    -- Force ScrollFrame to recalculate content area
    C_Timer.After(0.1, function()
        if statsGroup and statsGroup.content then
            statsGroup:DoLayout()
        end
    end)
    
    UI.statsLabel = statsLabel
    UI.streakLabel = streakLabel
end

-- Create fun statistics section
function DRE:CreateFunStatsSection(container)
    if not self.db or not self.db.profile.funStats then
        return
    end

    -- Calculate fun stats
    local funStats = self:CalculateFunStats()
    local settings = self.db.profile.funStats

    -- Check if any fun stats are enabled
    local hasEnabledStats = false
    for key, enabled in pairs(settings) do
        if enabled then
            hasEnabledStats = true
            break
        end
    end

    if not hasEnabledStats then
        return
    end

    -- Define stats in order matching settings tab structure
    local statSections = {
        {
            title = "Player Relationships",
            stats = {
                {setting = "showMostPlayedWith", stat = "mostPlayedWith"},
                {setting = "showMostWinsAgainst", stat = "mostWinsAgainst"},
                {setting = "showMostLossesAgainst", stat = "mostLossesAgainst"},
                {setting = "showNemesis", stat = "nemesis"},
                {setting = "showVictim", stat = "victim"},
            }
        },
        {
            title = "Gold & Money",
            stats = {
                {setting = "showMostMoneyWonFrom", stat = "mostMoneyWonFrom"},
                {setting = "showMostMoneyLostTo", stat = "mostMoneyLostTo"},
                {setting = "showBiggestWin", stat = "biggestWin"},
                {setting = "showBiggestLoss", stat = "biggestLoss"},
                {setting = "showHighRoller", stat = "highRoller"},
                {setting = "showCheapskate", stat = "cheapskate"},
            }
        },
        {
            title = "Luck & Streaks",
            stats = {
                {setting = "showLuckyPlayer", stat = "luckyPlayer"},
                {setting = "showUnluckyPlayer", stat = "unluckyPlayer"},
                {setting = "showDaredevil", stat = "daredevil"},
                {setting = "showConservative", stat = "conservative"},
            }
        },
    }

    -- Process each section
    for _, section in ipairs(statSections) do
        local sectionStats = {}

        -- Collect enabled stats for this section
        for _, statInfo in ipairs(section.stats) do
            if settings[statInfo.setting] then
                local statText = self:FormatFunStat(statInfo.stat, funStats[statInfo.stat])
                if statText then
                    table.insert(sectionStats, statText)
                end
            end
        end

        -- Only create section if it has stats to show
        if #sectionStats > 0 then
            local sectionGroup = AceGUI:Create("InlineGroup")
            sectionGroup:SetTitle(section.title)
            sectionGroup:SetFullWidth(true)
            sectionGroup:SetLayout("Flow")
            container:AddChild(sectionGroup)

            local sectionText = table.concat(sectionStats, "\n")
            local sectionLabel = AceGUI:Create("Label")
            sectionLabel:SetText(sectionText)
            sectionLabel:SetFullWidth(true)
            sectionLabel:SetColor(0.9, 0.9, 0.5) -- Light yellow color for fun stats
            sectionGroup:AddChild(sectionLabel)
        end
    end

    -- Add settings hint at the bottom
    local hintGroup = AceGUI:Create("InlineGroup")
    hintGroup:SetFullWidth(true)
    hintGroup:SetLayout("Flow")
    container:AddChild(hintGroup)

    local settingsHint = AceGUI:Create("Label")
    settingsHint:SetText("Tip: Use /dr config -> Fun Statistics to customize which stats are shown!")
    settingsHint:SetFullWidth(true)
    settingsHint:SetColor(0.7, 0.7, 0.7)
    hintGroup:AddChild(settingsHint)
end

-- Create history section
function DRE:CreateHistorySection(container)
    local historyGroup = AceGUI:Create("SimpleGroup")
    historyGroup:SetFullWidth(true)
    historyGroup:SetFullHeight(true)
    historyGroup:SetLayout("List")
    container:AddChild(historyGroup)
    
    local historyControlsGroup = AceGUI:Create("SimpleGroup")
    historyControlsGroup:SetFullWidth(true)
    historyControlsGroup:SetLayout("Flow")
    historyGroup:AddChild(historyControlsGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("Game History")
    header:SetFullWidth(true)
    historyControlsGroup:AddChild(header)
    
    if not self.db or not self.db.profile.history then
        local noDataLabel = AceGUI:Create("Label")
        noDataLabel:SetText("No game history yet. Start playing DeathRoll games to see your history here!")
        noDataLabel:SetFullWidth(true)
        historyControlsGroup:AddChild(noDataLabel)
        return
    end
    
    -- Create dropdown with all players
    local playerNames = {}
    local playerDropdown = {}
    for playerName, _ in pairs(self.db.profile.history) do
        table.insert(playerNames, playerName)
        playerDropdown[playerName] = playerName
    end
    table.sort(playerNames)
    
    if #playerNames == 0 then
        local noPlayersLabel = AceGUI:Create("Label")
        noPlayersLabel:SetText("No players in history yet!")
        noPlayersLabel:SetFullWidth(true)
        historyControlsGroup:AddChild(noPlayersLabel)
        return
    end
    
    -- Player selector section
    local playerSelectorGroup = AceGUI:Create("SimpleGroup")
    playerSelectorGroup:SetFullWidth(true)
    playerSelectorGroup:SetLayout("Flow")
    historyControlsGroup:AddChild(playerSelectorGroup)
    
    local playerLabel = AceGUI:Create("Label")
    playerLabel:SetText("View history with:")
    playerLabel:SetWidth(120)
    playerSelectorGroup:AddChild(playerLabel)
    
    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetList(playerDropdown)
    dropdown:SetValue(playerNames[1])
    dropdown:SetWidth(180)
    dropdown:SetCallback("OnValueChanged", function(widget, event, key)
        self:UpdateHistoryDisplay(key)
    end)
    playerSelectorGroup:AddChild(dropdown)
    
    -- History display area - with explicit height for proper scrolling
    local historyDisplayGroup = AceGUI:Create("InlineGroup")
    historyDisplayGroup:SetTitle("Statistics & Recent Games")
    historyDisplayGroup:SetFullWidth(true)
    historyDisplayGroup:SetHeight(200)
    historyDisplayGroup:SetLayout("Fill")
    historyGroup:AddChild(historyDisplayGroup)
    
    local historyScroll = AceGUI:Create("ScrollFrame")
    historyScroll:SetFullWidth(true)
    historyScroll:SetFullHeight(true)
    historyScroll:SetLayout("List")
    historyDisplayGroup:AddChild(historyScroll)

    local historyLabel = AceGUI:Create("Label")
    historyLabel:SetText("Select a player to view history")
    historyLabel:SetFullWidth(true)
    historyLabel:SetJustifyV("TOP")
    historyLabel:SetJustifyH("LEFT")
    historyScroll:AddChild(historyLabel)
    
    -- Force ScrollFrame to recalculate content area
    C_Timer.After(0.1, function()
        if historyGroup and historyGroup.content then
            historyGroup:DoLayout()
        end
        if historyScroll then
            historyScroll:DoLayout()
        end
    end)
    
    -- Store references for updates
    UI.historyGroup = historyGroup
    UI.historyControlsGroup = historyControlsGroup
    UI.historyDisplayGroup = historyDisplayGroup
    UI.historyBox = historyLabel
    UI.historyScroll = historyScroll
    UI.historyDropdown = dropdown
    
    -- Show first player's history by default
    self:UpdateHistoryDisplay(playerNames[1])

    C_Timer.After(0, function()
        self:UpdateHistorySectionLayout()
    end)
end

function DRE:RefreshHistoryLayout()
    if not UI.historyScroll then
        return
    end

    self:UpdateHistorySectionLayout()

    UI.historyScroll:DoLayout()

    C_Timer.After(0, function()
        if not (UI and UI.historyScroll and UI.historyScroll.scrollbar) then
            return
        end

        local scrollbar = UI.historyScroll.scrollbar
        local minValue = select(1, scrollbar:GetMinMaxValues())
        scrollbar:SetValue(minValue)
    end)
end

function DRE:UpdateHistorySectionLayout()
    if not (UI.historyGroup and UI.historyControlsGroup and UI.historyDisplayGroup) then
        return
    end

    local containerHeight = 0
    if UI.historyGroup.frame then
        containerHeight = UI.historyGroup.frame:GetHeight() or 0
    end

    if containerHeight <= 0 and UI.mainWindow and UI.mainWindow.frame then
        containerHeight = (UI.mainWindow.frame:GetHeight() or 300) - 80
    end

    if containerHeight <= 0 then
        return
    end

    local controlsHeight = 0
    if UI.historyControlsGroup.frame then
        controlsHeight = UI.historyControlsGroup.frame:GetHeight() or 0
    end

    local availableHeight = containerHeight - controlsHeight - 12
    if availableHeight < 80 then
        availableHeight = 80
    end

    UI.historyDisplayGroup:SetHeight(availableHeight)

    if UI.historyGroup and UI.historyGroup.DoLayout then
        UI.historyGroup:DoLayout()
    end

    if UI.historyScroll then
        UI.historyScroll:DoLayout()
    end
end

function DRE:CreateSettingsSection(container)
    local settingsScroll = AceGUI:Create("ScrollFrame")
    settingsScroll:SetFullWidth(true)
    settingsScroll:SetFullHeight(true)
    settingsScroll:SetLayout("Flow")
    container:AddChild(settingsScroll)

    local settingsGroup = AceGUI:Create("SimpleGroup")
    settingsGroup:SetFullWidth(true)
    settingsGroup:SetLayout("Flow")
    settingsScroll:AddChild(settingsGroup)

    local header = AceGUI:Create("Heading")
    header:SetText("Settings")
    header:SetFullWidth(true)
    settingsGroup:AddChild(header)

    local description = AceGUI:Create("Label")
    description:SetText("These settings mirror the main addon configuration and apply immediately.")
    description:SetFullWidth(true)
    description:SetColor(0.8, 0.8, 0.8)
    settingsGroup:AddChild(description)

    local function addSection(title)
        local group = AceGUI:Create("InlineGroup")
        group:SetTitle(title)
        group:SetFullWidth(true)
        group:SetLayout("Flow")
        settingsGroup:AddChild(group)
        return group
    end

    local function addToggle(parent, label, value, onChange)
        local checkbox = AceGUI:Create("CheckBox")
        checkbox:SetLabel(label)
        checkbox:SetFullWidth(true)
        checkbox:SetValue(value)
        checkbox:SetCallback("OnValueChanged", function(_, _, newValue)
            onChange(newValue)
        end)
        parent:AddChild(checkbox)
        return checkbox
    end

    local function addSlider(parent, label, minValue, maxValue, step, value, onChange)
        local slider = AceGUI:Create("Slider")
        slider:SetLabel(label)
        slider:SetFullWidth(true)
        slider:SetSliderValues(minValue, maxValue, step)
        slider:SetValue(value)
        slider:SetCallback("OnValueChanged", function(_, _, newValue)
            onChange(newValue)
        end)
        parent:AddChild(slider)
        return slider
    end

    local function addButton(parent, text, onClick)
        local button = AceGUI:Create("Button")
        button:SetText(text)
        button:SetFullWidth(true)
        button:SetCallback("OnClick", function()
            onClick()
        end)
        parent:AddChild(button)
        return button
    end

    local gameplayGroup = addSection("Gameplay")
    addToggle(gameplayGroup, "Auto Emote", self.db.profile.gameplay.autoEmote, function(value)
        self.db.profile.gameplay.autoEmote = value
    end)
    addToggle(gameplayGroup, "Sound Effects", self.db.profile.gameplay.soundEnabled, function(value)
        self.db.profile.gameplay.soundEnabled = value
    end)
    addToggle(gameplayGroup, "Track Gold", self.db.profile.gameplay.trackGold, function(value)
        self.db.profile.gameplay.trackGold = value
    end)
    addToggle(gameplayGroup, "Chat Messages", self.db.profile.gameplay.chatMessages, function(value)
        self.db.profile.gameplay.chatMessages = value
    end)
    addToggle(gameplayGroup, "Debug Messages", self.db.profile.gameplay.debugMessages, function(value)
        self.db.profile.gameplay.debugMessages = value
    end)

    local challengeGroup = addSection("Challenge System")
    addToggle(challengeGroup, "Enable Challenge Popups", self.db.profile.challengeSystem.enabled, function(value)
        self.db.profile.challengeSystem.enabled = value
    end)
    addToggle(challengeGroup, "Send Challenge Whispers", self.db.profile.challengeSystem.sendWhisper, function(value)
        self.db.profile.challengeSystem.sendWhisper = value
    end)
    addToggle(challengeGroup, "Track Wager From Completed Trade", self.db.profile.challengeSystem.trackWagerByTrade, function(value)
        self.db.profile.challengeSystem.trackWagerByTrade = value
    end)
    addSlider(challengeGroup, "Minimum Roll for Popups", 2, 10000, 1, self.db.profile.challengeSystem.minRollThreshold, function(value)
        self.db.profile.challengeSystem.minRollThreshold = math.floor(value)
    end)

    local interfaceGroup = addSection("Interface")
    addSlider(interfaceGroup, "UI Scale", 0.6, 2.2, 0.1, (self.db.profile.ui.scale or 0.9) + 0.1, function(value)
        self.db.profile.ui.scale = value - 0.1
        self:UpdateUIScale()
    end)
    addToggle(interfaceGroup, "Hide Minimap Icon", self.db.profile.minimap.hide, function(value)
        self.db.profile.minimap.hide = value
        self:ToggleMinimapIcon()
    end)
    addButton(interfaceGroup, "Reset Window Position", function()
        self:ResetWindowPosition()
        self:UpdateMainTabLayout()
    end)
    addButton(interfaceGroup, "Reset Window Size", function()
        self:ResetWindowSize()
        self:UpdateMainTabLayout()
    end)
    addButton(interfaceGroup, "Open Blizzard Config", function()
        self:OpenOptions()
    end)

    local dataGroup = addSection("Data Management")
    addButton(dataGroup, "Show Statistics In Chat", function()
        local stats = self:GetOverallStats()
        self:Print("=== DeathRoll Statistics ===")
        self:Print("Total Games: " .. stats.totalGames)
        self:Print("Total Wins: " .. stats.totalWins)
        self:Print("Total Losses: " .. stats.totalLosses)
        self:Print("Gold Won: " .. self:FormatGold(stats.totalGoldWon))
        self:Print("Gold Lost: " .. self:FormatGold(stats.totalGoldLost))
        self:Print("Current Streak: " .. stats.currentStreak)
    end)
    addButton(dataGroup, "Recalculate Gold Tracking", function()
        local success, message = self:RecalculateGoldTracking()
        if success then
            self:Print("Gold tracking fixed: " .. message)
        else
            self:Print("Failed to fix gold tracking: " .. message)
        end
    end)
    addButton(dataGroup, "Clean Old Data (30 Days)", function()
        self:CleanOldData(30)
    end)
    addButton(dataGroup, "Export Data", function()
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
    end)
    addButton(dataGroup, "Edit Game Records", function()
        self:ShowEditGameDialog()
    end)
    addButton(dataGroup, "Reset All Data", function()
        StaticPopup_Show("DEATHROLL_RESET_CONFIRM")
    end)

    local funStatSections = {
        {
            title = "Fun Statistics: Player Relationships",
            items = {
                {key = "showMostPlayedWith", label = "Most Played With"},
                {key = "showMostWinsAgainst", label = "Most Wins Against"},
                {key = "showMostLossesAgainst", label = "Most Losses Against"},
                {key = "showNemesis", label = "Your Nemesis"},
                {key = "showVictim", label = "Your Victim"},
            },
        },
        {
            title = "Fun Statistics: Gold and Money",
            items = {
                {key = "showMostMoneyWonFrom", label = "Biggest Gold Mine"},
                {key = "showMostMoneyLostTo", label = "Biggest Money Sink"},
                {key = "showBiggestWin", label = "Biggest Single Win"},
                {key = "showBiggestLoss", label = "Biggest Single Loss"},
                {key = "showHighRoller", label = "High Roller"},
                {key = "showCheapskate", label = "Cheapskate"},
            },
        },
        {
            title = "Fun Statistics: Luck and Streaks",
            items = {
                {key = "showLuckyPlayer", label = "Lucky Player"},
                {key = "showUnluckyPlayer", label = "Unlucky Player"},
                {key = "showDaredevil", label = "Daredevil Opponent"},
                {key = "showConservative", label = "Conservative Opponent"},
            },
        },
    }

    for _, section in ipairs(funStatSections) do
        local group = addSection(section.title)
        for _, item in ipairs(section.items) do
            addToggle(group, item.label, self.db.profile.funStats[item.key], function(value)
                self.db.profile.funStats[item.key] = value
            end)
        end
    end

    UI.settingsScroll = settingsScroll
    UI.settingsContent = settingsGroup

    C_Timer.After(0.1, function()
        if UI and UI.settingsContent and UI.settingsContent.DoLayout then
            UI.settingsContent:DoLayout()
        end
        if UI and UI.settingsScroll then
            UI.settingsScroll:DoLayout()
        end
    end)
end

-- UI StartDeathRoll function removed - using Core.lua version instead
-- This function just updates the UI state when the game starts

-- Update UI scale
function DRE:UpdateUIScale()
    if UI.mainWindow and UI.mainWindow.frame then
        local scale = self.db.profile.ui.scale or 1.0
        UI.mainWindow.frame:SetScale(scale)
        self:QueueLayoutRefresh()
    end
end

-- Format gold amount for display
function DRE:FormatGold(amount)
    if amount == 0 then
        return "0g"
    end
    
    -- Handle negative amounts
    local isNegative = amount < 0
    local absAmount = math.abs(amount)
    
    local gold = math.floor(absAmount / 10000)
    local silver = math.floor((absAmount % 10000) / 100)
    local copper = absAmount % 100
    
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
    
    if result == "" then
        result = "0c"
    end
    
    -- Add negative sign for negative amounts
    if isNegative then
        result = "-" .. result
    end
    
    return result
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
    -- Only update stats if we're on the statistics tab
    if UI.currentTab ~= "statistics" then
        return
    end
    
    if not UI.statsLabel or not self.db or not self.db.profile.goldTracking then
        return
    end
    
    local stats = self.db.profile.goldTracking
    
    -- Recalculate total games and win rate
    local totalGames = 0
    local totalWins = 0
    local totalLosses = 0
    if self.db.profile.history then
        for playerName, playerData in pairs(self.db.profile.history) do
            totalWins = totalWins + (playerData.wins or 0)
            totalLosses = totalLosses + (playerData.losses or 0)
        end
    end
    totalGames = totalWins + totalLosses
    local winRate = totalGames > 0 and (totalWins / totalGames * 100) or 0
    
    local statsText = string.format(
        "Total Games Played: %d\nGames Won: %d\nGames Lost: %d\nWin Rate: %.1f%%\n\nGold Won: %s\nGold Lost: %s\nNet Profit: %s",
        totalGames,
        totalWins,
        totalLosses,
        winRate,
        self:FormatGold(stats.totalWon or 0),
        self:FormatGold(stats.totalLost or 0),
        self:FormatGold((stats.totalWon or 0) - (stats.totalLost or 0))
    )
    
    UI.statsLabel:SetText(statsText)
    
    if UI.streakLabel then
        local streakText = string.format(
            "Current Streak: %s%d\nBest Win Streak: %d\nWorst Loss Streak: %d",
            (stats.currentStreak or 0) >= 0 and "+" or "",
            stats.currentStreak or 0,
            stats.bestWinStreak or 0,
            stats.worstLossStreak or 0
        )
        UI.streakLabel:SetText(streakText)
    end
    
    -- Update fun stats if they exist
    if UI.funStatsLabel and self.db and self.db.profile.funStats then
        local funStats = self:CalculateFunStats()
        local settings = self.db.profile.funStats
        local statsToShow = {}
        
        local statMappings = {
            showMostPlayedWith = "mostPlayedWith",
            showMostWinsAgainst = "mostWinsAgainst", 
            showMostLossesAgainst = "mostLossesAgainst",
            showMostMoneyWonFrom = "mostMoneyWonFrom",
            showMostMoneyLostTo = "mostMoneyLostTo",
            showBiggestWin = "biggestWin",
            showBiggestLoss = "biggestLoss",
            showNemesis = "nemesis",
            showVictim = "victim",
            showHighRoller = "highRoller",
            showCheapskate = "cheapskate",
            showLuckyPlayer = "luckyPlayer",
            showUnluckyPlayer = "unluckyPlayer", 
            showDaredevil = "daredevil",
            showConservative = "conservative",
        }
        
        for settingKey, statKey in pairs(statMappings) do
            if settings[settingKey] then
                local statText = self:FormatFunStat(statKey, funStats[statKey])
                if statText then
                    table.insert(statsToShow, statText)
                end
            end
        end
        
        local funStatsText = #statsToShow > 0 and 
            table.concat(statsToShow, "\n") or
            "No fun statistics available yet.\nPlay more games to unlock interesting insights!"
            
        UI.funStatsLabel:SetText(funStatsText)
    end
end

-- Update history display for selected player
function DRE:UpdateHistoryDisplay(playerName)
    if not UI.historyBox or not self.db or not self.db.profile.history then
        return
    end
    
    local playerData = self.db.profile.history[playerName]
    if not playerData then
        UI.historyBox:SetText("No data available for " .. (playerName or "Unknown"))
        self:RefreshHistoryLayout()
        return
    end
    
    -- Enhanced player history formatting
    local text = string.format("=== HISTORY WITH %s ===\n\n", string.upper(playerName))
    text = text .. string.format("Games Played: %d\n", (playerData.wins or 0) + (playerData.losses or 0))
    text = text .. string.format("Wins: %d\n", playerData.wins or 0)
    text = text .. string.format("Losses: %d\n", playerData.losses or 0)
    
    local totalGames = (playerData.wins or 0) + (playerData.losses or 0)
    if totalGames > 0 then
        local winRate = (playerData.wins or 0) / totalGames * 100
        text = text .. string.format("Win Rate: %.1f%%\n", winRate)
    end
    
    text = text .. string.format("Gold Won: %s\n", self:FormatGold(playerData.goldWon or 0))
    text = text .. string.format("Gold Lost: %s\n", self:FormatGold(playerData.goldLost or 0))
    text = text .. string.format("Net Profit: %s\n", self:FormatGold((playerData.goldWon or 0) - (playerData.goldLost or 0)))
    
    if playerData.recentGames and #playerData.recentGames > 0 then
        text = text .. "\n=== RECENT GAMES ===\n"
        local displayCount = math.min(#playerData.recentGames, 15) -- Show last 15 games
        for i = 1, displayCount do
            local game = playerData.recentGames[i]
            if game then
                local resultIcon = (game.result == "Won") and "[W]" or "[L]"
                local goldDisplay = (game.goldAmount and game.goldAmount > 0) and 
                    (" (" .. self:FormatGold(game.goldAmount) .. ")") or ""
                text = text .. string.format("%s %s - %s%s\n", 
                    resultIcon,
                    game.date or "Unknown Date",
                    game.result or "Unknown",
                    goldDisplay)
            end
        end
        
        if #playerData.recentGames > 15 then
            text = text .. string.format("\n... and %d more games\n", #playerData.recentGames - 15)
        end
    else
        text = text .. "\n=== RECENT GAMES ===\nNo games recorded yet."
    end
    
    UI.historyBox:SetText(text)
    self:RefreshHistoryLayout()
end


-- Create Spicy Duel RPS section
function DRE:CreateSpicyDuelSection(container)
    local spicyGroup = AceGUI:Create("ScrollFrame")
    spicyGroup:SetFullWidth(true)
    spicyGroup:SetFullHeight(true)
    spicyGroup:SetLayout("Flow")
    container:AddChild(spicyGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("Spicy DeathRoll - RPS Dice Duel")
    header:SetFullWidth(true)
    spicyGroup:AddChild(header)
    
    -- Description
    local descLabel = AceGUI:Create("Label")
    descLabel:SetText("A best-of-rounds duel where each player secretly chooses a stance (Attack/Defend/Gamble), rolls d50, and resolves outcomes via RPS-style matchups!\n\nStarting HP: 150 each | Win condition: reduce opponent to 0 HP")
    descLabel:SetFullWidth(true)
    descLabel:SetColor(0.9, 0.9, 0.7)
    spicyGroup:AddChild(descLabel)
    
    -- Game state display
    local gameStateGroup = AceGUI:Create("InlineGroup")
    gameStateGroup:SetTitle("Game Status")
    gameStateGroup:SetFullWidth(true)
    gameStateGroup:SetLayout("Flow")
    spicyGroup:AddChild(gameStateGroup)
    
    local gameStateLabel = AceGUI:Create("Label")
    gameStateLabel:SetText("Ready to start a new Spicy Duel!")
    gameStateLabel:SetFullWidth(true)
    gameStateGroup:AddChild(gameStateLabel)
    
    -- Stance selection
    local stanceGroup = AceGUI:Create("InlineGroup")
    stanceGroup:SetTitle("Choose Your Stance")
    stanceGroup:SetFullWidth(true)
    stanceGroup:SetLayout("Flow")
    spicyGroup:AddChild(stanceGroup)
    
    local stanceDropdown = AceGUI:Create("Dropdown")
    stanceDropdown:SetList({
        ["attack"] = "Attack (Straightforward strike)",
        ["defend"] = "Defend (Shield and parry)",
        ["gamble"] = "Gamble (Wild lunge - high risk/reward)"
    })
    stanceDropdown:SetValue("attack")
    stanceDropdown:SetWidth(200)
    stanceGroup:AddChild(stanceDropdown)
    
    local rollButton = AceGUI:Create("Button")
    rollButton:SetText("Roll & Reveal!")
    rollButton:SetWidth(120)
    rollButton:SetCallback("OnClick", function()
        self:HandleSpicyRoll(stanceDropdown:GetValue())
    end)
    stanceGroup:AddChild(rollButton)
    
    -- Challenge section
    local challengeGroup = AceGUI:Create("InlineGroup")
    challengeGroup:SetTitle("Challenge Someone")
    challengeGroup:SetFullWidth(true)
    challengeGroup:SetLayout("Flow")
    spicyGroup:AddChild(challengeGroup)
    
    local challengeButton = AceGUI:Create("Button")
    challengeButton:SetText("Challenge Target to Spicy Duel")
    challengeButton:SetFullWidth(true)
    challengeButton:SetCallback("OnClick", function()
        local target = UnitName("target")
        if not target or target == "" then
            self:Print("Please target a player first!")
            return
        end
        self:StartSpicyDuel(target)
    end)
    challengeGroup:AddChild(challengeButton)
    
    -- Rules section
    local rulesGroup = AceGUI:Create("InlineGroup")
    rulesGroup:SetTitle("Quick Rules")
    rulesGroup:SetFullWidth(true)
    rulesGroup:SetLayout("Fill")
    spicyGroup:AddChild(rulesGroup)
    
    local rulesText = AceGUI:Create("MultiLineEditBox")
    rulesText:SetText([[Attack vs Attack: Higher roll deals difference damage
Attack vs Defend: Defend blocks if D>=A, else A deals (A-D)
Attack vs Gamble: Glass Cannon - if A>=G then A deals full A, else G deals full G
Defend vs Defend: No damage (stalemate)
Defend vs Gamble: If G>D then G deals full G, else recoil (D-G)/2 to Gambler
Gamble vs Gamble: Higher deals double difference, tie = both take 10

Attack = consistent pressure | Defend = blocks & counters | Gamble = swingy chaos]])
    rulesText:SetNumLines(8)
    rulesText:DisableButton(true)
    rulesText:SetFullWidth(true)
    rulesText:SetFullHeight(true)
    rulesGroup:AddChild(rulesText)
    
    -- Store references
    UI.spicyGameState = gameStateLabel
    UI.spicyStance = stanceDropdown
    UI.spicyRollButton = rollButton
end

-- Calculate wager from UI input fields
function DRE:UpdateWagerInputMode()
    local isTradeMode = self:IsTradeWagerModeEnabled()

    for _, widget in ipairs({UI.goldEdit, UI.silverEdit, UI.copperEdit}) do
        if widget and widget.SetDisabled then
            widget:SetDisabled(isTradeMode)
        end
    end

    if UI.tradeWagerHelp then
        if isTradeMode then
            UI.tradeWagerHelp:SetText("Wager tracking is set to trades. Complete a gold trade after the game and the wager will be recorded automatically.")
            UI.tradeWagerHelp:SetColor(0.85, 0.82, 0.45)
        else
            UI.tradeWagerHelp:SetText("")
            UI.tradeWagerHelp:SetColor(0.8, 0.8, 0.8)
        end
    end
end

function DRE:CalculateWagerFromUI()
    if self:IsTradeWagerModeEnabled() then
        return 0
    end

    local gold = tonumber(UI.goldEdit and UI.goldEdit:GetText() or "0") or 0
    local silver = tonumber(UI.silverEdit and UI.silverEdit:GetText() or "0") or 0  
    local copper = tonumber(UI.copperEdit and UI.copperEdit:GetText() or "0") or 0
    return gold * 10000 + silver * 100 + copper
end

-- Handle game button clicks based on current state
function DRE:HandleGameButtonClick()
    local gameState = UI.gameState or "WAITING"
    
    if gameState == "WAITING" or gameState == "GAME_OVER" then
        -- Initial challenge state or starting new game after previous ended
        if gameState == "GAME_OVER" then
            -- Reset to WAITING state first to clear previous game
            self:UpdateGameUIState("WAITING")
        end
        
        -- Check if we have a recent target roll (challenge to accept)
        if UI.recentTargetRoll then
            -- Accept the challenge - start DeathRoll with their roll result
            local targetName = UnitName("target")
            if targetName and targetName == UI.recentTargetRoll.playerName then
                local wager = self:CalculateWagerFromUI()
                self:DebugPrint("Accepting challenge from " .. targetName .. " with roll " .. UI.recentTargetRoll.roll)
                self:StartDeathRoll(targetName, UI.recentTargetRoll.roll, wager, self:IsTradeWagerModeEnabled())
            else
                self:Print("Target changed - please target " .. (UI.recentTargetRoll.playerName or "the challenger") .. " to accept their challenge")
            end
        else
            -- Start a new challenge
            self:StartChallengeFlow()
        end
    elseif gameState == "ROLLING" then
        -- Player needs to roll
        self:PerformRoll()
    elseif gameState == "WAITING_FOR_OPPONENT" then
        -- Waiting for opponent, button should be disabled
        self:Print("Waiting for opponent to roll...")
    end
end

-- Accept an incoming challenge from targeted player
function DRE:AcceptIncomingChallenge()
    local challenge = UI.incomingChallenge
    if not challenge then
        self:Print("No incoming challenge to accept!")
        return
    end
    
    local challenger = challenge.player
    local theirRoll = challenge.roll
    local maxRoll = challenge.maxRoll
    local wager = 0 -- Could be made configurable
    local trackWagerByTrade = self:IsTradeWagerModeEnabled()
    
    self:ChatPrint("Accepting " .. challenger .. "'s DeathRoll challenge!")
    self:ChatPrint(challenger .. " rolled " .. theirRoll .. " (1-" .. maxRoll .. ")")
    
    -- Start the game with their roll
    if theirRoll == 1 then
        self:ChatPrint(challenger .. " rolled 1 and lost! You won!")
        self:HandleGameEnd(challenger, "WIN", wager, maxRoll, {
            opponent = challenger,
            trackWagerByTrade = trackWagerByTrade
        })
    else
        self:ChatPrint("Your turn! Roll 1-" .. theirRoll)
        -- Start the game - they already rolled, now it's your turn
        self:StartActualGame(challenger, maxRoll, wager, theirRoll, trackWagerByTrade)
    end
    
    -- Clear the challenge data
    UI.incomingChallenge = nil
    
    -- Update UI to normal state
    self:UpdateChallengeButtonText()
end

-- Deny an incoming challenge
function DRE:DenyIncomingChallenge()
    local challenge = UI.incomingChallenge
    if not challenge then
        return
    end
    
    self:ChatPrint("Denied " .. challenge.player .. "'s DeathRoll challenge.")
    
    -- Clear the challenge data
    UI.incomingChallenge = nil
    
    -- Update UI to normal state
    self:UpdateChallengeButtonText()
end

-- Accept a recent roll detected in chat or use your roll to challenge
function DRE:AcceptRecentRoll()
    local rollData = UI.recentTargetRoll
    if not rollData then
        self:Print("No recent roll found!")
        return
    end
    
    local rollOwner = rollData.player
    local rollResult = rollData.roll
    local maxRoll = rollData.maxRoll
    local currentTarget = UnitName("target")
    local wager = 0 -- Could be made configurable
    local trackWagerByTrade = self:IsTradeWagerModeEnabled()
    
    if rollOwner == UnitName("player") then
        -- You rolled - challenge the current target with your roll
        if not currentTarget then
            self:Print("No target selected to challenge!")
            return
        end
        
        self:ChatPrint("Challenging " .. currentTarget .. " with your roll of " .. rollResult .. " (1-" .. maxRoll .. ")!")
        
        -- Start game with your roll as the starting point
        if rollResult == 1 then
            self:ChatPrint("You rolled 1 and lost! " .. currentTarget .. " wins!")
            self:HandleGameEnd(currentTarget, "LOSS", wager, maxRoll, {
                opponent = currentTarget,
                trackWagerByTrade = trackWagerByTrade
            })
        else
            -- Start the game - you already rolled, now target needs to roll
            self:StartActualGame(currentTarget, maxRoll, wager, rollResult, trackWagerByTrade)
        end
    else
        -- Someone else rolled - accept their challenge
        self:ChatPrint("Accepting " .. rollOwner .. "'s DeathRoll! They rolled " .. rollResult .. " (1-" .. maxRoll .. ")")
        
        -- Start game with their roll as the starting point
        if rollResult == 1 then
            self:ChatPrint(rollOwner .. " rolled 1 and lost! You won!")
            self:HandleGameEnd(rollOwner, "WIN", wager, maxRoll, {
                opponent = rollOwner,
                trackWagerByTrade = trackWagerByTrade
            })
        else
            -- Start the game - they already rolled, now it's your turn
            self:StartActualGame(rollOwner, maxRoll, wager, rollResult, trackWagerByTrade)
        end
    end
    
    -- Clear the recent roll data
    UI.recentTargetRoll = nil
end

-- Start the challenge flow
function DRE:StartChallengeFlow()
    local target = UnitName("target")
    
    -- Check if we have a target
    if UnitExists("target") then
        -- Check if target is yourself (self-dueling)
        if UnitIsUnit("target", "player") then
            target = UnitName("player")
            self:Print("Self-duel mode activated!")
        else
            -- Check if target is a player (not NPC)
            if not UnitIsPlayer("target") then
                self:Print("You can only DeathRoll with other players, not NPCs!")
                return
            end
            
            -- Target is a valid player
            target = UnitName("target")
        end
    else
        -- No target selected
        self:Print("Please target a player first (or target yourself for self-duel)!")
        return
    end
    
    local roll = tonumber(UI.rollEdit:GetText())

    local usingTradeWager = self:IsTradeWagerModeEnabled()
    local totalWager = self:CalculateWagerFromUI()
    local gold = tonumber(UI.goldEdit and UI.goldEdit:GetText() or "0") or 0
    local silver = tonumber(UI.silverEdit and UI.silverEdit:GetText() or "0") or 0
    local copper = tonumber(UI.copperEdit and UI.copperEdit:GetText() or "0") or 0

    if not roll or roll < 2 then
        self:Print("Roll must be at least 2!")
        return
    end
    
    if roll > 999999 then
        self:Print("Roll cannot exceed 999,999 (6 digits maximum)!")
        return
    end
    
    if not usingTradeWager and (gold < 0 or silver < 0 or copper < 0) then
        self:Print("Wager amounts cannot be negative!")
        return
    end
    
    -- Store current target and game info for UI updates
    UI.currentTarget = target
    UI.initialRoll = roll
    UI.currentWager = totalWager

    -- Send challenge whisper (if enabled and not self-duel)
    if target ~= UnitName("player") then
        self:SendChallengeWhisper(target, roll, totalWager)
    end

    -- Skip rolling state since we auto-roll, go straight to waiting for opponent
    self:UpdateGameUIState("WAITING_FOR_OPPONENT")

    -- Start the challenge
    self:StartDeathRoll(target, roll, totalWager, usingTradeWager)
end

-- Perform a roll in the active game
function DRE:PerformRoll()
    if not self.gameState or not self.gameState.isActive then
        self:Print("No active game!")
        return
    end

    local rollRange = self.gameState.currentRoll
    if not rollRange or rollRange < 1 then
        self:Print("Invalid roll range!")
        return
    end

    -- Update UI to show we're waiting for the roll result
    self:UpdateGameUIState("WAITING_FOR_ROLL_RESULT")

    -- Perform the roll using WoW's built-in roll system with a small delay
    C_Timer.After(0.1, function()
        RandomRoll(1, rollRange)
    end)

    -- Fallback timeout to reset UI if roll detection fails (especially for self-duels)
    -- Account for the 0.1s delay before the roll
    C_Timer.After(3.2, function()
        if self.UI and self.UI.gameState == "WAITING_FOR_ROLL_RESULT" then
            self:DebugPrint("Roll detection timeout - resetting UI to ROLLING state")
            self:UpdateGameUIState("ROLLING")
        end
    end)
end

-- UpdateGameUIState function moved to Core.lua to avoid scoping issues


-- Clean up UI
function DRE:CleanupUI()
    self:ReleaseEmbeddedRollHistory()

    UI.rollHistoryGroup = nil
    UI.rollHistoryScroll = nil
    UI.rollHistoryContent = nil
    UI.rollHistoryBox = nil

    if UI.mainWindow then
        UI.mainWindow:Hide()
        UI.mainWindow = nil
    end
end
