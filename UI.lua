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

local tableWidgets = {Frame = "DRETableWindow", Button = "DRETableButton", EditBox = "DRETableInput",
    InlineGroup = "DRETableSection", CheckBox = "DRETableSwitch", Dropdown = "DRETableDropdown"}
function DRE:CreateWindowWidget(kind)
    return AceGUI:Create(self.devDuel and tableWidgets[kind] or kind)
end

-- UI state
UI.mainWindow = nil
UI.isGameActive = false
UI.playerRoll = nil
UI.opponentRoll = nil
UI.gameState = "WAITING" -- WAITING, ROLLING, FINISHED
UI.rollHistory = {}

function DRE:ReleaseWindowOnClose(window, reference)
    self.transientWindows = self.transientWindows or {}
    self.transientWindows[window] = true
    window:SetCallback("OnClose", function(widget)
        if not self.transientWindows[widget] then return end
        self.transientWindows[widget] = nil
        if reference and self[reference] == widget then self[reference] = nil end
        AceGUI:Release(widget)
    end)
end

function DRE:AfterUI(delay, callback)
    local generation = UI.tabGeneration or 0
    C_Timer.After(delay, function()
        if not self.disabled and generation == (UI.tabGeneration or 0) then callback() end
    end)
end

function DRE:SetWagerInputs(amount)
    UI.inputWager = amount or 0
    if UI.goldEdit then UI.goldEdit:SetText(tostring(math.floor(UI.inputWager / 10000))) end
    if UI.silverEdit then UI.silverEdit:SetText(tostring(math.floor(UI.inputWager % 10000 / 100))) end
    if UI.copperEdit then UI.copperEdit:SetText(tostring(UI.inputWager % 100)) end
end

function DRE:RestoreGameControls()
    local game = self.gameState
    if game and game.isActive then
        UI.currentTarget = game.target
        self:SetWagerInputs(game.wager)
        if UI.rollEdit then UI.rollEdit:SetText(tostring(game.currentRoll)) end
        local state = game.pendingRoll and "WAITING_FOR_ROLL_RESULT"
            or ((game.playerTurn or self:IsSamePlayer(game.target, self:GetUnitPlayerName("player")))
                and "ROLLING" or "WAITING_FOR_OPPONENT")
        self:UpdateGameUIState(state)
    else
        if UI.rollEdit and UI.inputRoll then UI.rollEdit:SetText(tostring(UI.inputRoll)) end
        self:SetWagerInputs(UI.inputWager or 0)
        self:UpdateGameUIState(UI.gameState == "GAME_OVER" and "GAME_OVER" or "WAITING")
        self:UpdateChallengeButtonText()
    end
end

-- Initialize UI system
function DRE:InitializeUI()
    self.UI = self.UI or {}
end

function DRE:UpdateMainTabLayout()
    if not (self.UI and self.UI.tabGroup) then
        return
    end

    local tabGroup = self.UI.tabGroup

    -- Let AceGUI compute tab widths/rows natively to avoid anchor overlap.
    if tabGroup.BuildTabs then
        tabGroup:BuildTabs()
    elseif tabGroup.frame and tabGroup.frame.obj and tabGroup.frame.obj.BuildTabs then
        tabGroup.frame.obj:BuildTabs()
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
    if UI.groupWidgets and UI.groupWidgets.circle then
        -- A height-only resize can leave the scroll child's width unchanged.
        UI.groupWidgets.pane:DoLayout()
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
function DRE:SelectMainSection(section)
    if not UI.tabGroup then return self:ShowMainWindow(section) end
    if self.devDuel then
        UI.tabGroup:SetGroup(section)
    else
        UI.tabGroup:SelectTab(section)
    end
end

function DRE:ShowMainWindow(section)
    if not AceGUI then
        self:Print("AceGUI-3.0 not available. Please install Ace3.")
        return
    end
    
    if UI.mainWindow and not UI.tabGroup then
        UI.mainWindow:Hide()
        UI.mainWindow, UI.tableHero, UI.tableFooter = nil, nil, nil
    end
    if UI.mainWindow then
        UI.mainWindow:Show()
        section = section or (self.devDuel and "deathroll")
        if section and UI.currentTab ~= section then self:SelectMainSection(section) end
        if UI.currentTab == "group" then self:RefreshGroupUI() end
        if self.RefreshDuel then
            self:RefreshDuel()
        elseif UI.currentTab == "deathroll" and self.gameState and self.gameState.isActive then
            self:RestoreGameControls()
        end
        self:QueueLayoutRefresh()
        self:UpdateMainTabLayout()
        self:UpdateRollHistoryPanelVisibility()
        -- Check for recent rolls when reopening UI
        self:CheckRecentRollsForChallenge()
        return
    end
    
    -- Create main window frame (initially hidden to prevent flash)
    local frame = self:CreateWindowWidget("Frame")
    frame:SetTitle(self.displayName)
    frame:SetStatusText("v" .. self.version .. " - 2SChoppy Edition")
    frame:SetCallback("OnClose", function(widget)
        self:HideRollHistoryPanel()
        widget:Hide()
    end)
    
    -- Hide frame initially to prevent flash during setup
    frame.frame:Hide()
    
    frame:SetLayout("Fill")
    local settings = self.db.profile.ui
    settings.frameStatus = settings.frameStatus or {}
    local status = settings.frameStatus
    frame:SetStatusTable(status)
    frame:EnableResize(true)
    if self.devDuel then
        -- Small dimensions from the former 400-by-311 shell use the new default once.
        local oldSize = (status.width or 0) < self.tableMinWidth or (status.height or 0) < self.tableMinHeight
        frame:SetWidth(oldSize and self.tableWidth or status.width)
        frame:SetHeight(oldSize and self.tableHeight or status.height)
    elseif not status.width and not status.height then
        frame:SetWidth(400)
        frame:SetHeight(311)
    end
    frame.frame:SetScale(settings.scale or 0.9)
    if not self.devDuel then
        local applyStatus = frame.ApplyStatus
        frame.ApplyStatus = function(window)
            applyStatus(window)
            window.frame:SetScale(settings.scale or 0.9)
            DRE:QueueLayoutRefresh()
        end
    end

    -- Create TabGroup
    local tabGroup = AceGUI:Create(self.devDuel and "SimpleGroup" or "TabGroup")
    tabGroup:SetLayout("Fill")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    local sections = {
        {text="DeathRoll", value="deathroll"},
        {text="Group", value="group"},
        {text="Statistics", value="statistics"}, 
        {text="History", value="history"},
        {text="Settings", value="settings"}
    }
    local header, footer
    if self.devDuel then
        tabGroup:SetAutoAdjustHeight(false)
        header, footer = self:PrepareTableWindow(frame, tabGroup, sections)
    else
        tabGroup:SetTabs(sections)
    end
    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        if not (self.gameState and self.gameState.isActive) then
            if UI.rollEdit then UI.inputRoll = tonumber(UI.rollEdit:GetText()) end
            if UI.goldEdit then UI.inputWager = self:CalculateWagerFromUI() end
        end
        UI.tabGeneration = (UI.tabGeneration or 0) + 1
        self:ReleaseEmbeddedRollHistory()
        UI.duelPane, UI.duelWidgets = nil, nil
        UI.groupWidgets = nil
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
        UI.statsBroadcastChannelDropdown = nil
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
        UI.cancelGameButton = nil
        UI.goldEdit = nil
        UI.silverEdit = nil
        UI.copperEdit = nil
        
        -- Track current tab
        UI.currentTab = group
        
        if group == "deathroll" then
            if self.devDuel then
                self:CreateDuelSection(container)
            else
                self:CreateGameSection(container)
            end
            -- Check for recent rolls when switching to deathroll tab
            self:CheckRecentRollsForChallenge()
        elseif group == "group" then
            self:CreateGroupSection(container)
        elseif group == "statistics" then
            self:CreateStatsSection(container)
        elseif group == "history" then
            self:CreateHistorySection(container)
        elseif group == "settings" then
            self:CreateSettingsSection(container)
        end

        self:UpdateRollHistoryPanelVisibility()
    end)
    frame:AddChild(tabGroup)
    -- A failed shell setup must leave the next open free to build a fresh window.
    UI.mainWindow, UI.tabGroup, UI.tableHero, UI.tableFooter = frame, tabGroup, header, footer
    self:SelectMainSection(section or "deathroll")
    
    -- Show the frame AFTER all setup is complete to prevent flash
    frame:Show()

    frame.frame:HookScript("OnSizeChanged", function()
        self:RefreshVisibleUILayout()
        self:AfterUI(0, function()
            self:RefreshVisibleUILayout()
        end)
    end)

    self:AfterUI(0, function()
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

    local rollEdit = DRE:CreateWindowWidget("EditBox")
    rollEdit:SetLabel("")
    rollEdit:SetWidth(90)
    
    rollEdit:SetText(tostring(UI.inputRoll or self:GetDefaultStartingRoll()))
    
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

    local autoRollButton = DRE:CreateWindowWidget("Button")
    autoRollButton:SetText("Use My Gold")
    autoRollButton:SetAutoWidth(true)
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
        
        goldEdit = DRE:CreateWindowWidget("EditBox")
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
        
        silverEdit = DRE:CreateWindowWidget("EditBox")
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
        
        copperEdit = DRE:CreateWindowWidget("EditBox")
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
    local actionGroup = AceGUI:Create("SimpleGroup")
    actionGroup:SetFullWidth(true)
    actionGroup:SetLayout("Flow")
    controlsGroup:AddChild(actionGroup)
    local gameButton = DRE:CreateWindowWidget("Button")
    gameButton:SetText("Challenge Player to DeathRoll!")
    gameButton:SetRelativeWidth(0.76)
    gameButton:SetCallback("OnClick", function()
        self:HandleGameButtonClick()
    end)
    actionGroup:AddChild(gameButton)
    local cancelGameButton = DRE:CreateWindowWidget("Button")
    cancelGameButton:SetText("Cancel")
    cancelGameButton:SetRelativeWidth(0.24)
    cancelGameButton:SetCallback("OnClick", function() self:CancelCurrentGame() end)
    actionGroup:AddChild(cancelGameButton)

    local rollHistoryGroup = DRE:CreateWindowWidget("InlineGroup")
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
    UI.cancelGameButton = cancelGameButton
    UI.tradeWagerHelp = tradeWagerHelp
    UI.rollHistory = UI.rollHistory or {}
    if #UI.rollHistory == 0 then
        table.insert(UI.rollHistory, "Ready to start! Target someone and click Challenge Player to DeathRoll!")
    end
    
    self:UpdateWagerInputMode()
    self:AfterUI(0, function()
        self:UpdateGameSectionLayout()
        self:RefreshRollHistoryDisplay()
    end)
    
    self:RestoreGameControls()
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
    -- AceGUI reserves 15 pixels on each side of a button label. Measure the
    -- actual font so larger captions can also trigger the full-width row.
    local buttonMinWidth = 110
    if UI.autoRollButton then
        UI.autoRollButton:SetAutoWidth(true)
        buttonMinWidth = math.max(buttonMinWidth, UI.autoRollButton.frame.width or 0)
    end
    local rollLabelAndSpacing = 42 -- 34px label plus 8px of breathing room
    local stackRollControls = isStacked or availableWidth < math.max(250, rollLabelAndSpacing + 82 + buttonMinWidth)
    local rollEditWidth

    if UI.rollEdit then
        UI.rollEdit:SetFullWidth(false)
        if stackRollControls then
            rollEditWidth = math.max(78, availableWidth - 42)
        else
            rollEditWidth = math.max(82, math.min(140, availableWidth - rollLabelAndSpacing - buttonMinWidth))
        end
        UI.rollEdit:SetWidth(rollEditWidth)
    end

    if UI.autoRollButton then
        UI.autoRollButton:SetFullWidth(stackRollControls)
        if not stackRollControls then
            UI.autoRollButton:SetWidth(math.max(buttonMinWidth, availableWidth - rollLabelAndSpacing - (rollEditWidth or 82)))
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
    if self.RefreshDuel then self:RefreshDuel(); return end
    if not UI.rollHistory then
        return
    end

    local historyText = table.concat(UI.rollHistory, "\n")

    if UI.rollHistoryBox then
        pcall(function()
            UI.rollHistoryBox:SetText(historyText)
        end)

        self:UpdateRollHistoryPanelLayout()

        self:AfterUI(0, function()
            if not (UI and UI.rollHistoryScroll and UI.rollHistoryContent) then
                return
            end

            local maxScroll = math.max(0, (UI.rollHistoryContent:GetHeight() or 0) - (UI.rollHistoryScroll:GetHeight() or 0))
            UI.rollHistoryScroll:SetVerticalScroll(maxScroll)
        end)
    end
end

function DRE:FormatRollOneChance(maximum)
    return string.format("%.3g%%", 100 / maximum)
end

-- Add a roll entry to the history display
function DRE:AddRollToHistory(playerName, roll, maxRoll, isSelfDuel, rollCount, modeDetail)
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

    if roll < 1 or roll > maxRoll then
        self:DebugPrint("AddRollToHistory: Roll outside the given range")
        return
    end

    local myName = DRE:GetUnitPlayerName("player")
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

    if self.devDuel and self.gameState then
        local game = self.gameState
        if game.emoteRound and not game.emoteRound.opener then
            self:ObserveEmoteOpener(game.emoteRound, isMe, roll)
        end
        game.duelRolls = game.duelRolls or {}
        game.duelRolls[isMe and "player" or "opponent"] = roll
        if UI.tableHero then UI.tableHero:PlayThrow(isMe, game.target, roll) end
    end

    -- Create colored entry
    local colorCode = isMe and "|cff00ff00" or "|cffff6666" -- Green for player, red for opponent
    local resetColor = "|r"
    local outcomeText = ""

    if modeDetail then
        outcomeText = modeDetail
    elseif roll == 1 then
        outcomeText = isMe and "you lost" or "you win"
    else
        local nextRoller = isMe and "Opponent has" or "You have"
        outcomeText = string.format("%s a %s chance to roll 1 next", nextRoller, self:FormatRollOneChance(roll))
    end

    local entry = string.format("%s%s%s rolled %d (1-%d) - %s",
        colorCode, displayName, resetColor, roll, maxRoll, outcomeText)

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

local function statsLabel(parent, text, width, font)
    local label = AceGUI:Create("Label")
    if width then label:SetRelativeWidth(width) else label:SetFullWidth(true) end
    label:SetFontObject(font or GameFontHighlight)
    label:SetText(text)
    parent:AddChild(label)
    return label
end

local function counted(value, singular, plural)
    return value .. " " .. (value == 1 and singular or plural)
end

local function statsSection(parent, title)
    local group = DRE:CreateWindowWidget("InlineGroup")
    group:SetFullWidth(true)
    group:SetTitle(title)
    group:SetLayout("Flow")
    parent:AddChild(group)
    return group
end

local function statsPanel()
    local frame = CreateFrame("Frame", nil, UIParent)
    local surface = frame:CreateTexture(nil, "BACKGROUND")
    surface:SetColorTexture(0.14, 0.115, 0.15, 1)
    surface:SetPoint("TOPLEFT")
    surface:SetPoint("BOTTOMRIGHT", 0, 10)
    local function lettering(font, size, align, r, g, b)
        local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        if font then text:SetFont(font, size, "") end
        text:SetTextColor(r, g, b)
        text:SetJustifyH(align)
        text:SetJustifyV("TOP")
        text:SetNonSpaceWrap(true)
        return text
    end
    local bodyFont = UNIT_NAME_FONT or STANDARD_TEXT_FONT
    local title = lettering(bodyFont, 15, "LEFT", 0.94, 0.77, 0.55)
    local total = lettering(STANDARD_TEXT_FONT, 25, "LEFT", 1, 0.97, 0.90)
    title:SetPoint("TOPLEFT", 12, -12)
    total:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    local labels, values = {}, {}
    for index = 1, 2 do
        labels[index] = lettering(bodyFont, 15, "LEFT", 0.80, 0.76, 0.79)
        values[index] = lettering(bodyFont, 16, "RIGHT", 1, 0.97, 0.90)
    end
    local panel = {type = "DREStatsPanel", frame = frame, title = title, total = total, labels = labels, values = values}
    function panel:OnWidthSet(width)
        -- AceGUI also calls this when the table equalizes panel heights.
        if self.measuredWidth == width then return end
        self.measuredWidth = width
        local inner = math.max(1, width - 24)
        title:SetWidth(inner)
        total:SetWidth(inner)
        local labelWidth = math.floor(inner * 0.34)
        local top = 12 + title:GetStringHeight() + 4 + total:GetStringHeight() + 10
        for index = 1, 2 do
            local label, value = labels[index], values[index]
            label:SetWidth(math.max(1, labelWidth))
            value:SetWidth(math.max(1, inner - labelWidth - 4))
            label:SetPoint("TOPLEFT", 12, -top)
            value:SetPoint("TOPRIGHT", -12, -top)
            top = top + math.max(label:GetStringHeight(), value:GetStringHeight()) + 4
        end
        self:SetHeight(top + 18)
    end
    function panel:SetFigures(caption, headline, firstLabel, firstValue, secondLabel, secondValue)
        title:SetText(caption)
        total:SetText(headline)
        labels[1]:SetText(firstLabel)
        values[1]:SetText(firstValue)
        labels[2]:SetText(secondLabel)
        values[2]:SetText(secondValue)
        self.measuredWidth = nil
        self:OnWidthSet(frame:GetWidth())
    end
    function panel:OnAcquire()
        self:SetWidth(210)
    end
    return AceGUI:RegisterAsWidget(panel)
end
if DRE.devDuel then AceGUI:RegisterWidgetType("DREStatsPanel", statsPanel, 1) end

local function summaryPanel(parent, title, total, firstLabel, firstValue, secondLabel, secondValue)
    local panel = AceGUI:Create("DREStatsPanel")
    panel:SetFullWidth(true)
    panel:SetFigures(title, total, firstLabel, firstValue, secondLabel, secondValue)
    parent:AddChild(panel)
end

local function percentage(won, played)
    return played > 0 and string.format("%.1f%%", 100 * won / played) or "—"
end

local function showModeFigures(scroll, mode, stats)
    if mode == "highRoller" then
        local won, contested = stats.tiebreakWins or 0, stats.tiebreaks or 0
        summaryPanel(scroll, "Points won", stats.points or 0, "Tiebreak points won / contested",
            won .. " / " .. contested, "Tiebreak win rate", percentage(won, contested))
    elseif mode == "twoLives" then
        summaryPanel(scroll, "Two Lives victories", counted(stats.totalWins or ((stats.played or 0) - (stats.losses or 0)), "win", "wins"),
            "Flawless wins", stats.flawless or 0, "Comeback wins", stats.comebacks or 0)
        statsLabel(scroll, "Flawless means both lives remained. A comeback starts with you losing the first life at the table.")
    elseif mode == "cursed7" then
        summaryPanel(scroll, "Cursed 7 losses by final roll", counted(stats.ones + stats.sevens, "recorded loss", "recorded losses"),
            "Rolled a 1", stats.ones, "Rolled a 7", stats.sevens)
    end
end

local function fillDuelStats(scroll, mode)
    if DRE.db and DRE.db.profile.goldTracking then
        local stats = DRE:GetDuelModeStats(mode)
        local games = stats.totalGames
        local won, lost = stats.totalGoldWon, stats.totalGoldLost
        local overview = AceGUI:Create("SimpleGroup")
        overview:SetFullWidth(true)
        overview:SetUserData("table", {columns = {1, 1, 1}, spaceH = 8, alignH = "fill", alignV = "fill"})
        overview:SetLayout("Table")
        scroll:AddChild(overview)
        local record = games == 0 and "No games recorded" or counted(games, "game", "games")
        local rate = percentage(stats.totalWins, games)
        summaryPanel(overview, "Win rate · " .. record, rate, "Wins", stats.totalWins, "Losses", stats.totalLosses)
        summaryPanel(overview, "Net gold", DRE:FormatGold(won - lost), "Won", DRE:FormatGold(won), "Lost", DRE:FormatGold(lost))
        local current = stats.currentStreak
        local run = "None"
        if current > 0 then run = counted(current, "win", "wins")
        elseif current < 0 then run = counted(-current, "loss", "losses") end
        summaryPanel(overview, "Current streak", run, "Best", counted(stats.bestWinStreak, "win", "wins"),
            "Worst", counted(math.abs(stats.worstLossStreak), "loss", "losses"))
        showModeFigures(scroll, mode, stats)
        local offers = stats.offers
        summaryPanel(scroll, "Double or Nothing · break-even rate", percentage(stats.breakEvens, offers),
            "Broke even", stats.breakEvens, "Your completed offers", offers)
    else
        statsLabel(scroll, "Overall statistics are unavailable.")
    end
    if mode == "all" then
        DRE:CreateFunStatsSection(scroll)
    else
        statsLabel(scroll, "Includes duels recorded with this mode. Comeback, tiebreak and rematch counts use games played since those stats were added.")
    end
end

local function statsButton(parent, text, callback)
    local button = DRE:CreateWindowWidget("Button")
    button:SetText(text)
    button:SetRelativeWidth(0.5)
    button:SetCallback("OnClick", callback)
    parent:AddChild(button)
    return button
end

local function fillGroupStats(scroll, mode)
    local settings = DRE.db.profile.funStats
    local stats = DRE:GetHostedGroupStats() or {}
    if mode ~= "all" then stats = (stats.byMode or {})[mode] or {} end
    if settings.showGroupRecord ~= false or settings.showGroupLongest ~= false then
        local overview = AceGUI:Create("SimpleGroup")
        overview:SetFullWidth(true)
        local both = settings.showGroupRecord ~= false and settings.showGroupLongest ~= false
        overview:SetUserData("table", {columns = both and {1, 1} or {1}, spaceH = 8, alignH = "fill", alignV = "fill"})
        overview:SetLayout("Table")
        scroll:AddChild(overview)
        if settings.showGroupRecord ~= false then
            local played, losses = stats.played or 0, stats.losses or 0
            if mode == "classic" or mode == "hotPotato" then
                summaryPanel(overview, "Survival rate · " .. counted(played, "game", "games"), percentage(played - losses, played),
                    "Survived", played - losses, "Lost", losses)
            elseif mode ~= "all" then
                summaryPanel(overview, "Win rate · " .. counted(played, "game", "games"), percentage(played - losses, played),
                    "Wins", played - losses, "Losses", losses)
            else
                summaryPanel(overview, "My group record", counted(played, "round", "rounds"),
                    "Won or survived", played - losses, "Lost", losses)
            end
        end
        if settings.showGroupLongest ~= false then
            local longest = stats.longest
            summaryPanel(overview, "Longest round", longest and counted(longest.rolls, "roll", "rolls") or "—",
                "Players", longest and longest.seats or "—", "Opening", longest and longest.opening or "—")
        end
    end
    if settings.showGroupRecord ~= false then showModeFigures(scroll, mode, stats) end
    if mode ~= "highRoller" and settings.showGroupEscapes ~= false then
        statsLabel(statsSection(scroll, "Closest calls"), "You survived /roll 2 " .. counted(stats.escapes or 0, "time", "times") .. ".")
    end
    if settings.showGroupRegulars ~= false then
        local group = statsSection(scroll, "Table regulars")
        local rows = {}
        for _, entry in pairs(stats.regulars or {}) do rows[#rows + 1] = entry end
        table.sort(rows, function(a, b)
            if a.played ~= b.played then return a.played > b.played end
            return a.name < b.name
        end)
        local pageSize = 8
        local pages = math.max(1, math.ceil(#rows / pageSize))
        local page = math.min(UI.statsRegularsPage or 1, pages)
        UI.statsRegularsPage = page
        for index = (page - 1) * pageSize + 1, math.min(page * pageSize, #rows) do
            local entry = rows[index]
            local row = AceGUI:Create("DREFunStatRow")
            row:SetFullWidth(true)
            row:SetResult("#" .. index, entry.name, counted(entry.played, "round", "rounds") .. " · " ..
                counted(entry.losses, "loss", "losses"), index % 2 == 1)
            group:AddChild(row)
        end
        if #rows == 0 then statsLabel(group, "Finish a hosted round to see who played.") end
        if pages > 1 then
            local function changePage(delta)
                UI.statsRegularsPage = page + delta
                DRE:UpdateStatsDisplay()
            end
            statsButton(group, "Previous", function() changePage(-1) end):SetDisabled(page == 1)
            statsButton(group, "Next", function() changePage(1) end):SetDisabled(page == pages)
        end
    end
    local anyShown = false
    for _, option in ipairs(DRE.groupStatOptions) do
        if settings[option.key] ~= false then anyShown = true end
    end
    local scope = mode == "all" and "Completed rounds hosted by this character." or "Hosted games since mode tracking began. Personal figures count games you played in."
    statsLabel(scroll, anyShown and scope or "Enable Group statistics in Settings.")
end

local function fillTableStats(scroll)
    scroll:PauseLayout()
    scroll:ReleaseChildren()
    local modes = AceGUI:Create("SimpleGroup")
    modes:SetFullWidth(true)
    modes:SetLayout("Flow")
    scroll:AddChild(modes)
    local view = UI.statsView or "duel"
    for _, mode in ipairs({"duel", "group"}) do
        local button = statsButton(modes, mode == "duel" and "1v1" or "Group", function()
            if UI.statsView == mode then return end
            UI.statsView = mode
            scroll:SetScroll(0)
            DRE:UpdateStatsDisplay()
        end)
        button:SetPrimary(mode == view)
    end
    local names = view == "group" and DRE.groupModes or DRE.duelModes
    local order = view == "group" and DRE.groupModeOrder or DRE.duelModeOrder
    local choices, keys = {all = "All modes"}, {"all"}
    for _, key in ipairs(order) do
        keys[#keys + 1] = key
        choices[key] = names[key]
    end
    UI.statsModes = UI.statsModes or {}
    local selected = UI.statsModes[view] or "all"
    local picker = DRE:CreateTableDropdownField(scroll, "Mode", 1)
    picker:SetList(choices, keys)
    picker:SetValue(selected)
    picker:SetCallback("OnValueChanged", function(_, _, key)
        if not choices[key] or key == selected then return end
        UI.statsModes[view] = key
        if view == "group" then UI.statsRegularsPage = 1 end
        scroll:SetScroll(0)
        DRE:UpdateStatsDisplay()
    end)
    if view == "group" then fillGroupStats(scroll, selected) else fillDuelStats(scroll, selected) end
    scroll:ResumeLayout()
    scroll:DoLayout()
end

-- Create stats section
function DRE:CreateStatsSection(container)
    local statsGroup = AceGUI:Create("ScrollFrame")
    statsGroup:SetFullWidth(true)
    statsGroup:SetFullHeight(true)
    statsGroup:SetLayout("Flow")
    container:AddChild(statsGroup)
    if self.devDuel then
        statsGroup:SetCallback("OnStatsRefresh", fillTableStats)
        fillTableStats(statsGroup)
        return
    end
    
    -- Header
    if not self.devDuel then
        local header = AceGUI:Create("Heading")
        header:SetText("DeathRoll Statistics")
        header:SetFullWidth(true)
        statsGroup:AddChild(header)
    end
    
    if not self.db or not self.db.profile.goldTracking then
        local noDataLabel = AceGUI:Create("Label")
        noDataLabel:SetText("No statistics available yet. Play some DeathRoll games to see your stats here!")
        noDataLabel:SetFullWidth(true)
        statsGroup:AddChild(noDataLabel)
        return
    end
    
    local stats = self.db.profile.goldTracking
    
    -- Overall statistics
    local overallGroup = DRE:CreateWindowWidget("InlineGroup")
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
    local streakGroup = DRE:CreateWindowWidget("InlineGroup")
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
    self:AfterUI(0.1, function()
        if statsGroup and statsGroup.content then
            statsGroup:DoLayout()
        end
    end)
    
    UI.statsLabel = statsLabel
    UI.streakLabel = streakLabel
end

-- Create fun statistics section
local function funStatRow()
    local frame = CreateFrame("Frame", nil, UIParent)
    local shade = frame:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    local function lettering(size, r, g, b)
        local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        if STANDARD_TEXT_FONT then label:SetFont(STANDARD_TEXT_FONT, size, "") end
        label:SetTextColor(r, g, b)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("TOP")
        label:SetNonSpaceWrap(true)
        return label
    end
    local caption = lettering(15, 0.96, 0.82, 0.61)
    local player = lettering(17, 1, 0.97, 0.90)
    local detail = lettering(14, 0.88, 0.86, 0.88)
    caption:SetPoint("TOPLEFT", 10, -8)
    local row = {type = "DREFunStatRow", frame = frame, caption = caption, player = player, detail = detail}
    function row:OnWidthSet(width)
        local split = math.floor(width * 0.35)
        caption:SetWidth(math.max(1, split - 18))
        local right = math.max(1, width - split - 10)
        player:SetWidth(right)
        detail:SetWidth(right)
        player:ClearAllPoints()
        player:SetPoint("TOPLEFT", split, -7)
        local nameHeight = player:GetText() ~= "" and player:GetStringHeight() or 0
        local detailTop = nameHeight > 0 and nameHeight + 3 or 0
        detail:ClearAllPoints()
        detail:SetPoint("TOPLEFT", split, -7 - detailTop)
        self:SetHeight(15 + math.max(caption:GetStringHeight(), detailTop + detail:GetStringHeight()))
    end
    function row:SetResult(title, name, value, alternate)
        caption:SetText(title)
        player:SetText(name or "")
        detail:SetText(value)
        shade:SetColorTexture(1, 0.92, 0.80, alternate and 0.065 or 0.018)
        self:OnWidthSet(self.frame:GetWidth())
    end
    function row:OnAcquire()
        self:SetWidth(400)
    end
    return AceGUI:RegisterAsWidget(row)
end
if DRE.devDuel then AceGUI:RegisterWidgetType("DREFunStatRow", funStatRow, 1) end

local function getFunStatSections(dev)
    local statSections = {
        {
            title = "Player Relationships",
            stats = {
                {setting = "showMostPlayedWith", stat = "mostPlayedWith", label = "Most Played With"},
                {setting = "showMostWinsAgainst", stat = "mostWinsAgainst", label = "Most Wins Against"},
                {setting = "showMostLossesAgainst", stat = "mostLossesAgainst", label = "Most Losses Against"},
                {setting = "showNemesis", stat = "nemesis", label = "Your Nemesis"},
                {setting = "showVictim", stat = "victim", label = "Your Victim"},
                {setting = "showFrenemy", stat = "frenemy", label = dev and "Closest Rival" or "Frenemy"},
                {setting = "showLikelyCheater", stat = "likelyCheater", label = "Most Likely to Cheat", legacy = true},
            }
        },
        {
            title = "Gold & Money",
            stats = {
                {setting = "showMostMoneyWonFrom", stat = "mostMoneyWonFrom", label = "Biggest Gold Mine"},
                {setting = "showMostMoneyLostTo", stat = "mostMoneyLostTo", label = "Biggest Money Sink"},
                {setting = "showBestMatchup", stat = "bestMatchup", label = "Best Matchup"},
                {setting = "showWorstMatchup", stat = "worstMatchup", label = "Worst Matchup"},
                {setting = "showBiggestWin", stat = "biggestWin", label = "Biggest Single Win"},
                {setting = "showBiggestLoss", stat = "biggestLoss", label = "Biggest Single Loss"},
                {setting = "showHighRoller", stat = "highRoller", label = "High Roller"},
                {setting = "showCheapskate", stat = "cheapskate", label = "Cheapskate"},
            }
        },
        {
            title = dev and "Opening Rolls" or "Luck & Streaks",
            stats = {
                {setting = "showLuckyPlayer", stat = "luckyPlayer", label = "Lucky Player", legacy = true},
                {setting = "showUnluckyPlayer", stat = "unluckyPlayer", label = "Unlucky Player", legacy = true},
                {setting = "showDaredevil", stat = "daredevil", label = "Daredevil Opponent"},
                {setting = "showConservative", stat = "conservative", label = "Conservative Opponent"},
            }
        },
    }

    if dev then
        for _, section in ipairs(statSections) do
            for index = #section.stats, 1, -1 do
                if section.stats[index].legacy then table.remove(section.stats, index) end
            end
        end
    end
    return statSections
end

function DRE:CreateFunStatsSection(container)
    if not self.db or not self.db.profile.funStats then return end
    local settings = self.db.profile.funStats
    local statSections = getFunStatSections(self.devDuel)
    -- Check only known/displayable fun-stat toggles.
    local categories, order = {}, {}
    for index, section in ipairs(statSections) do
        for _, statInfo in ipairs(section.stats) do
            if settings[statInfo.setting] then
                categories[index] = section.title
                order[#order + 1] = index
                break
            end
        end
    end

    if #order == 0 then
        if self.devDuel then
            statsLabel(statsSection(container, "Fun Statistics"), "Enable Fun Statistics in Settings to see them here.")
        end
        return
    end

    local funStats = self:CalculateFunStats()
    if self.devDuel then
        local group = statsSection(container, "Fun Statistics")
        local selected = categories[UI.statsCategory] and UI.statsCategory or order[1]
        local picker
        if #order > 1 then
            picker = self:CreateWindowWidget("Dropdown")
            picker:SetWidth(235)
            picker:SetList(categories, order)
            picker:SetValue(selected)
            group:AddChild(picker)
        else
            statsLabel(group, categories[selected], nil, GameFontNormal)
        end
        local results = AceGUI:Create("SimpleGroup")
        results:SetLayout("List")
        results:SetFullWidth(true)
        group:AddChild(results)
        local function addResult(title, player, detail)
            local row = AceGUI:Create("DREFunStatRow")
            row:SetFullWidth(true)
            row:SetResult(title, player, detail, #results.children % 2 == 0)
            results:AddChild(row)
        end
        local function showCategory(index)
            UI.statsCategory = index
            results:PauseLayout()
            results:ReleaseChildren()
            local pending = {}
            for _, item in ipairs(statSections[index].stats) do
                if settings[item.setting] then
                    local title, player, detail = self:GetFunStatFields(item.stat, funStats[item.stat])
                    if title then
                        addResult(title, player, detail)
                    else
                        pending[#pending + 1] = item.label
                    end
                end
            end
            if #pending > 0 then
                addResult("Awaiting qualifying data", nil, table.concat(pending, ", "))
            end
            results:ResumeLayout()
            results:DoLayout()
            group:DoLayout()
            container:DoLayout()
        end
        if picker then picker:SetCallback("OnValueChanged", function(_, _, index) showCategory(index) end) end
        showCategory(selected)
        return
    end

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
            local sectionGroup = DRE:CreateWindowWidget("InlineGroup")
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
    local hintGroup = DRE:CreateWindowWidget("InlineGroup")
    hintGroup:SetFullWidth(true)
    hintGroup:SetLayout("Flow")
    container:AddChild(hintGroup)

    local settingsHint = AceGUI:Create("Label")
    settingsHint:SetText("Tip: Use /dr config -> Fun Statistics to customize which stats are shown!")
    settingsHint:SetFullWidth(true)
    settingsHint:SetColor(0.7, 0.7, 0.7)
    hintGroup:AddChild(settingsHint)
end

-- The Forever ledger keeps a reusable row per visible slot, independent of archive size.
local function hasLedgerHistory(player)
    return player and ((tonumber(player.gamesPlayed) or 0) > 0 or (tonumber(player.wins) or 0) > 0
        or (tonumber(player.losses) or 0) > 0 or (tonumber(player.goldWon) or 0) > 0
        or (tonumber(player.goldLost) or 0) > 0 or #(player.recentGames or {}) > 0)
end

local function historyText(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function historyTooltip(row)
    if not row.tip or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.tip)
    if row.gameId then GameTooltip:AddLine("Click to edit this duel", 0.94, 0.73, 0.45) end
    GameTooltip:Show()
end

local function ledgerRow(list, index)
    local row = CreateFrame("Button", nil, list.frame)
    row:SetPoint("TOPLEFT", 0, -list.inset - (index - 1) * list.rowHeight)
    row:SetPoint("TOPRIGHT", 0, -list.inset - (index - 1) * list.rowHeight)
    row:SetHeight(list.rowHeight)
    row.tint = row:CreateTexture(nil, "BACKGROUND")
    row.tint:SetAllPoints()
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnEnter", historyTooltip)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.label = historyText(row, "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 6, 0)
    if list.isRoster then
        row.label:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function() DRE:UpdateHistoryDisplay(row.name) end)
    else
        row.label:SetWidth(40)
        row.when = historyText(row, "GameFontHighlightSmall")
        row.when:SetPoint("LEFT", 50, 0)
        row.when:SetPoint("RIGHT", -107, 0)
        row.amount = historyText(row, "GameFontHighlightSmall")
        row.amount:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnClick", function() if row.gameId then DRE:ShowEditGameDialog(row.gameId) end end)
    end
    list.rows[index] = row
    return row
end

local function historyPageSize(list)
    return math.max(1, math.floor((list.frame:GetHeight() - list.inset - 30 - (list.footerExtra or 0)) / list.rowHeight))
end

local function drawHistoryList(list, entries, selected)
    local count = #entries
    local capacity = historyPageSize(list)
    local lastPage = math.max(1, math.ceil(count / capacity))
    list.page = math.max(1, math.min(list.page, lastPage))
    local start = (list.page - 1) * capacity + 1
    local visible = math.min(capacity, count - start + 1)
    for i = 1, visible do
        local row = list.rows[i] or ledgerRow(list, i)
        local entry = entries[start + i - 1]
        local active = list.isRoster and entry == selected
        row.tint:SetColorTexture(0.66, 0.49, 0.28, active and 0.31 or (i % 2 == 1 and 0.09 or 0.025))
        if list.isRoster then
            row.name, row.tip = entry, entry
            row.label:SetText(entry)
        else
            local result = entry.result
            local won = result == "Won" or result == "WIN"
            local lost = result == "Lost" or result == "LOSS"
            local outcome = won and "Won" or lost and "Lost" or "Unknown"
            local when = entry.date or "Unknown date"
            local amount = DRE:FormatGold(tonumber(entry.goldAmount) or 0)
            row.gameId = entry.id
            row.label:SetText((won and "|cff9bce9c" or lost and "|cffe49a92" or "|cffb8b0b8") .. outcome .. "|r")
            row.when:SetText(when)
            row.amount:SetText(amount)
            row.tip = selected .. "\n" .. when .. "   " .. outcome .. "\nRecorded wager: " .. amount
            if DRE.db.profile.funStats.showLikelyCheater and (tonumber(entry.suspiciousRollCount) or 0) > 0 then
                row.tip = row.tip .. "\nWrong-range rolls: " .. entry.suspiciousRollCount
            end
        end
        row:Show()
        if GameTooltip and GameTooltip:IsOwned(row) then historyTooltip(row) end
    end
    for i = visible + 1, #list.rows do list.rows[i]:Hide() end
    list.range:SetText(count > 0 and string.format("%d–%d / %d", start, start + visible - 1, count) or "")
    list.prev:SetEnabled(list.page > 1)
    list.next:SetEnabled(list.page < lastPage)
end

local function ledgerList(parent, isRoster, redraw)
    local frame = CreateFrame("Frame", nil, parent)
    local list = {frame = frame, rows = {}, page = 1, isRoster = isRoster,
        inset = isRoster and 52 or 84, rowHeight = isRoster and 25 or 24}
    list.range = historyText(frame, "GameFontDisableSmall")
    list.range:SetPoint("BOTTOM", 0, 9)
    for _, direction in ipairs({-1, 1}) do
        local side = direction == -1 and "LEFT" or "RIGHT"
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(23, 21)
        btn:SetPoint("BOTTOM" .. side, 0, 3)
        btn:SetText(direction == -1 and "<" or ">")
        btn:SetScript("OnClick", function() list.page = list.page + direction; redraw() end)
        list[direction == -1 and "prev" or "next"] = btn
    end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        list.page = list.page + (delta > 0 and -1 or 1)
        redraw()
    end)
    return list
end

local function historyLedger()
    local frame = CreateFrame("Frame", nil, UIParent)
    -- AceGUI manages the broadcast controls in the footer. The two lists have independent pages.
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(35)
    local pane = {type = "DREHistoryLedger", frame = frame, content = footer}
    local function redraw() if pane.names then pane:Draw() end end
    local roster = ledgerList(frame, true, redraw)
    local duels = ledgerList(frame, false, redraw)
    pane.roster, pane.duels = roster, duels
    roster.frame:SetPoint("TOPLEFT")
    roster.frame:SetPoint("BOTTOMLEFT", 0, 41)
    duels.frame:SetPoint("TOPLEFT", roster.frame, "TOPRIGHT", 14, 0)
    duels.frame:SetPoint("BOTTOMRIGHT", 0, 41)
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", roster.frame, "TOPRIGHT", 6, 0)
    rule:SetPoint("BOTTOMLEFT", roster.frame, "BOTTOMRIGHT", 6, 0)
    rule:SetWidth(1)
    rule:SetColorTexture(0.48, 0.36, 0.27, 0.7)
    local searchLabel = historyText(roster.frame, "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 4, -3)
    searchLabel:SetText("Find opponent")
    local search = CreateFrame("EditBox", nil, roster.frame, "InputBoxTemplate")
    search:SetAutoFocus(false)
    search:SetHeight(26)
    search:SetPoint("TOPLEFT", 8, -20)
    search:SetPoint("TOPRIGHT", -4, -20)
    search:SetScript("OnEscapePressed", function()
        search:SetText("")
        roster.page = 1
        pane:Filter(pane.selected, true)
        search:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function() search:ClearFocus() end)
    search:SetScript("OnTextChanged", function(_, userInput)
        if userInput then roster.page = 1; pane:Filter(pane.selected) end
    end)
    pane.search = search
    local badge = CreateFrame("Frame", nil, duels.frame)
    badge:SetSize(34, 34)
    badge:SetPoint("TOPLEFT", 3, -3)
    local portrait = badge:CreateTexture(nil, "ARTWORK")
    portrait:SetAllPoints()
    local function updatePortrait()
        portrait:SetTexture("Interface\\AddOns\\DeathRollEnhancer\\Media\\Logo")
        if not pane.selected or not SetPortraitTexture then return end
        for _, unit in ipairs({"player", "target"}) do
            local isPlayer = UnitIsPlayer(unit)
            if DRE:IsAccessibleValue(isPlayer) and isPlayer and DRE:IsSamePlayer(DRE:GetUnitPlayerName(unit), pane.selected) then
                pcall(SetPortraitTexture, portrait, unit)
                return
            end
        end
    end
    badge:SetScript("OnShow", function()
        badge:RegisterEvent("PLAYER_TARGET_CHANGED")
        badge:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "target", "player")
        updatePortrait()
    end)
    badge:SetScript("OnHide", function() badge:UnregisterAllEvents() end)
    badge:SetScript("OnEvent", updatePortrait)
    badge:Hide()
    local name = historyText(duels.frame, "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", 44, -2)
    name:SetPoint("TOPRIGHT", -3, -2)
    local totals = historyText(duels.frame, "GameFontHighlightSmall")
    totals:SetPoint("TOPLEFT", 45, -24)
    local gold = historyText(duels.frame, "GameFontHighlightSmall")
    gold:SetPoint("TOPLEFT", 4, -43)
    gold:SetPoint("TOPRIGHT", -2, -43)
    local headers = {}
    for _, column in ipairs({{"Result", 6}, {"Date", 50}, {"Recorded wager", -6}}) do
        local header = historyText(duels.frame, "GameFontNormalSmall")
        header:SetPoint(column[2] < 0 and "TOPRIGHT" or "TOPLEFT", column[2], -67)
        header:SetText(column[1])
        table.insert(headers, header)
    end
    local empty = historyText(duels.frame, "GameFontHighlight")
    empty:SetPoint("TOPLEFT", 4, -89)
    empty:SetPoint("TOPRIGHT", -4, -89)
    empty:SetWordWrap(true)
    pane.title, pane.totals, pane.gold, pane.empty = name, totals, gold, empty
    pane.wrongRanges = historyText(duels.frame, "GameFontHighlightSmall")
    pane.wrongRanges:SetPoint("BOTTOMLEFT", 4, 29)
    function pane:GetValue() return self.selected end
    function pane:Draw()
        local player = self.selected and DRE.db.profile.history[self.selected]
        local games = player and player.recentGames or {}
        local counts = DRE.db.profile.suspiciousRolls
        local entry = counts and counts[self.selected]
        local wrong = DRE.db.profile.funStats.showLikelyCheater and tonumber(entry and entry.count) or 0
        pane.wrongRanges:SetText(wrong > 0 and ("Wrong-range rolls: " .. wrong) or "")
        duels.footerExtra = wrong > 0 and 18 or 0
        name:SetText(self.selected or "Duel history")
        for _, header in ipairs(headers) do header:SetShown(#games > 0) end
        local message
        if hasLedgerHistory(player) then
            local wins, losses = tonumber(player.wins) or 0, tonumber(player.losses) or 0
            local summary = string.format("%d wins   %d losses", wins, losses)
            if wins + losses > 0 then
                summary = summary .. string.format("   ·   %.0f%% wins", 100 * wins / (wins + losses))
            end
            totals:SetText(summary)
            gold:SetText("Recorded  ·  Won " .. DRE:FormatGold(tonumber(player.goldWon) or 0)
                .. "   Lost " .. DRE:FormatGold(tonumber(player.goldLost) or 0))
            if #games == 0 then message = "Only lifetime totals were saved for this opponent." end
        else
            totals:SetText("")
            gold:SetText("")
            message = wrong > 0 and "No completed duels with this opponent."
                or (#self.names == 0 and "Your first recorded duel will appear here." or "No opponents match your search.")
        end
        empty:SetText(message or "")
        drawHistoryList(roster, self.matches, self.selected)
        drawHistoryList(duels, games, self.selected)
        if self.send then self.send:SetDisabled(not hasLedgerHistory(player)) end
    end
    function pane:Select(playerName)
        local changed = self.selected ~= playerName
        if changed then duels.page = 1 end
        self.selected, UI.selectedHistoryPlayer = playerName, playerName
        if changed then updatePortrait() end
        self:Draw()
    end
    function pane:Filter(preferred, reveal)
        local lower = strlower or string.lower
        local query = lower(DRE:Trim(search:GetText() or ""))
        local selectedIndex
        self.matches = {}
        for _, fullName in ipairs(self.names) do
            if lower(fullName):find(query, 1, true) then
                table.insert(self.matches, fullName)
                if fullName == preferred then selectedIndex = #self.matches end
            end
        end
        if reveal and selectedIndex then roster.page = math.ceil(selectedIndex / historyPageSize(roster)) end
        self:Select(selectedIndex and preferred or self.matches[1])
    end
    function pane:Refresh(preferred)
        self.names = {}
        for fullName, player in pairs(DRE.db.profile.history or {}) do
            if hasLedgerHistory(player) then
                table.insert(self.names, fullName)
            end
        end
        if DRE.db.profile.funStats.showLikelyCheater then
            for fullName, entry in pairs(DRE.db.profile.suspiciousRolls or {}) do
                if (tonumber(entry.count) or 0) > 0 and not hasLedgerHistory(DRE.db.profile.history[fullName]) then
                    table.insert(self.names, fullName)
                end
            end
        end
        table.sort(self.names)
        local reveal = preferred ~= self.selected
        if reveal then search:SetText("") end
        self:Filter(preferred, reveal)
    end
    function pane:OnWidthSet(width)
        roster.frame:SetWidth(math.min(235, math.max(135, math.floor(width * 0.30))))
    end
    function pane:OnAcquire()
        self:SetFullWidth(true)
        self:SetFullHeight(true)
        roster.page, duels.page = 1, 1
        search:SetText("")
        self:OnWidthSet(frame:GetWidth())
        badge:Show()
    end
    function pane:OnRelease()
        search:ClearFocus()
        self.names, self.matches, self.selected, self.send = nil, nil, nil, nil
    end
    duels.frame:SetScript("OnSizeChanged", redraw)
    return AceGUI:RegisterAsContainer(pane)
end

if DRE.devDuel then AceGUI:RegisterWidgetType("DREHistoryLedger", historyLedger, 1) end

local function addHistoryBroadcastControls(self, historyControlsGroup)
    local broadcastControlsGroup = AceGUI:Create("SimpleGroup")
    broadcastControlsGroup:SetFullWidth(true)
    broadcastControlsGroup:SetLayout("Flow")
    historyControlsGroup:AddChild(broadcastControlsGroup)

    local channelLabel = AceGUI:Create("Label")
    channelLabel:SetText("Send stats to:")
    channelLabel:SetWidth(120)
    broadcastControlsGroup:AddChild(channelLabel)

    local channelDropdown = self:CreateWindowWidget("Dropdown")
    channelDropdown:SetList({
        party = "Party",
        raid = "Raid",
        guild = "Guild",
        officer = "Officer",
        instance = "Instance",
        say = "Say",
        yell = "Yell",
    })
    channelDropdown:SetWidth(140)

    local defaultChannel = "say"
    if IsInRaid and IsInRaid() then
        defaultChannel = "raid"
    elseif IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        defaultChannel = "instance"
    elseif IsInGroup and IsInGroup() then
        defaultChannel = "party"
    elseif IsInGuild and IsInGuild() then
        defaultChannel = "guild"
    end
    channelDropdown:SetValue(defaultChannel)
    broadcastControlsGroup:AddChild(channelDropdown)

    local sendStatsButton = DRE:CreateWindowWidget("Button")
    sendStatsButton:SetText("Send Stats")
    sendStatsButton:SetWidth(120)
    sendStatsButton:SetCallback("OnClick", function()
        local selectedPlayer = nil
        if UI.historyDropdown and UI.historyDropdown.GetValue then
            selectedPlayer = UI.historyDropdown:GetValue()
        end
        selectedPlayer = selectedPlayer or UI.selectedHistoryPlayer
        if not selectedPlayer then
            self:Print("No player selected to broadcast.")
            return
        end

        local channelHint = "say"
        if UI.statsBroadcastChannelDropdown and UI.statsBroadcastChannelDropdown.GetValue then
            channelHint = UI.statsBroadcastChannelDropdown:GetValue() or channelHint
        end

        local success, message = self:SendPlayerStatsBroadcast(selectedPlayer, channelHint)
        if success then
            self:Print(message)
        else
            self:Print("Failed to send stats: " .. (message or "Unknown error"))
        end
    end)
    broadcastControlsGroup:AddChild(sendStatsButton)
    UI.statsBroadcastChannelDropdown = channelDropdown
    return sendStatsButton
end

-- Create history section
function DRE:CreateHistorySection(container)
    if self.devDuel then
        local pane = AceGUI:Create("DREHistoryLedger")
        pane:SetLayout("Fill")
        container:AddChild(pane)
        UI.historyDropdown = pane
        pane.send = addHistoryBroadcastControls(self, pane)
        pane:Refresh(UI.selectedHistoryPlayer)
        return
    end
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
    if not self.devDuel then
        local header = AceGUI:Create("Heading")
        header:SetText("Game History")
        header:SetFullWidth(true)
        historyControlsGroup:AddChild(header)
    end

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

    -- Player selector section
    local playerSelectorGroup = AceGUI:Create("SimpleGroup")
    playerSelectorGroup:SetFullWidth(true)
    playerSelectorGroup:SetLayout("Flow")
    historyControlsGroup:AddChild(playerSelectorGroup)

    local playerLabel = AceGUI:Create("Label")
    playerLabel:SetText("View history with:")
    playerLabel:SetWidth(120)
    playerSelectorGroup:AddChild(playerLabel)

    local dropdown = self:CreateWindowWidget("Dropdown")
    dropdown:SetList(playerDropdown)
    dropdown:SetValue(playerNames[1])
    dropdown:SetWidth(180)
    dropdown:SetCallback("OnValueChanged", function(widget, event, key)
        UI.selectedHistoryPlayer = key
        self:UpdateHistoryDisplay(key)
    end)
    playerSelectorGroup:AddChild(dropdown)

    addHistoryBroadcastControls(self, historyControlsGroup)
    
    -- History display area - with explicit height for proper scrolling
    local historyDisplayGroup = DRE:CreateWindowWidget("InlineGroup")
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
    self:AfterUI(0.1, function()
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
    UI.selectedHistoryPlayer = playerNames[1]
    
    -- Show first player's history by default
    self:RefreshHistoryDropdown(playerNames[1])

    self:AfterUI(0, function()
        self:UpdateHistorySectionLayout()
    end)
end

function DRE:RefreshHistoryLayout()
    if not UI.historyScroll then
        return
    end

    self:UpdateHistorySectionLayout()

    UI.historyScroll:DoLayout()

    self:AfterUI(0, function()
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

    if not self.devDuel then
        local header = AceGUI:Create("Heading")
        header:SetText("Settings")
        header:SetFullWidth(true)
        settingsGroup:AddChild(header)

        local description = AceGUI:Create("Label")
        description:SetText("These settings mirror the main addon configuration and apply immediately.")
        description:SetFullWidth(true)
        description:SetColor(0.8, 0.8, 0.8)
        settingsGroup:AddChild(description)
    end

    local function addSection(title)
        local group = DRE:CreateWindowWidget("InlineGroup")
        group:SetTitle(title)
        group:SetFullWidth(true)
        group:SetLayout("Flow")
        settingsGroup:AddChild(group)
        return group
    end

    local function addToggle(parent, label, value, onChange)
        local checkbox = DRE:CreateWindowWidget("CheckBox")
        checkbox:SetLabel(label)
        checkbox:SetFullWidth(true)
        checkbox:SetValue(value)
        checkbox:SetCallback("OnValueChanged", function(_, _, newValue)
            onChange(newValue)
        end)
        parent:AddChild(checkbox)
        return checkbox
    end

    local function addButton(parent, text, onClick)
        local button = DRE:CreateWindowWidget("Button")
        button:SetText(text)
        button:SetFullWidth(true)
        button:SetCallback("OnClick", function()
            onClick()
        end)
        parent:AddChild(button)
        return button
    end

    local function addRollField(parent, label, get, set)
        local field = AceGUI:Create("EditBox")
        field:SetLabel(label .. " (2–999,999)")
        field:SetFullWidth(true)
        field:SetText(tostring(get()))
        field:SetCallback("OnEnterPressed", function(widget, _, text)
            local value, reason = self:ParseRollSetting(text)
            if value then set(value) else self:Print(reason) end
            widget:SetText(tostring(get()))
        end)
        parent:AddChild(field)
    end

    local gameplayGroup = addSection("Gameplay")
    addToggle(gameplayGroup, "Auto Emote", self.db.profile.gameplay.autoEmote, function(value)
        self.db.profile.gameplay.autoEmote = value
    end)
    addToggle(gameplayGroup, "Play Sound on Your Turn", self.db.profile.gameplay.soundEnabled, function(value)
        self.db.profile.gameplay.soundEnabled = value
    end)
    addToggle(gameplayGroup, "Chat Messages", self.db.profile.gameplay.chatMessages, function(value)
        self.db.profile.gameplay.chatMessages = value
    end)
    addToggle(gameplayGroup, "Debug Messages", self.db.profile.gameplay.debugMessages, function(value)
        self.db.profile.gameplay.debugMessages = value
    end)

    addRollField(gameplayGroup, "Default Starting Roll", function() return self:GetDefaultStartingRoll() end,
        function(value) self:SetDefaultStartingRoll(value) end)

    local challengeGroup = addSection("Challenge System")
    addToggle(challengeGroup, "Enable Challenge Popups", self.db.profile.challengeSystem.enabled, function(value)
        self.db.profile.challengeSystem.enabled = value
    end)
    addToggle(challengeGroup, self.devDuel and "Send Challenge Invites" or "Send Challenge Whispers", self.db.profile.challengeSystem.sendWhisper, function(value)
        self.db.profile.challengeSystem.sendWhisper = value
    end)
    addToggle(challengeGroup, "Track Wager From Completed Trade", self.db.profile.challengeSystem.trackWagerByTrade, function(value)
        self:SetTradeWagerModeEnabled(value)
    end)
    addRollField(challengeGroup, "Minimum Roll for Popups",
        function() return self.db.profile.challengeSystem.minRollThreshold end,
        function(value) self.db.profile.challengeSystem.minRollThreshold = value end)
    if self.devDuel then
        addButton(challengeGroup, "Test Challenge Popup", function() self:PreviewChallengePopup() end)
    end

    local interfaceGroup = addSection("Interface")
    if self.devDuel then
        local appearance = self:CreateWindowWidget("Dropdown")
        appearance:SetLabel("Group appearance")
        appearance:SetFullWidth(true)
        appearance:SetList(self.groupAppearances, self.groupAppearanceOrder)
        appearance:SetValue(self:GetGroupAppearance())
        appearance:SetCallback("OnValueChanged", function(_, _, value) self:SetGroupAppearance(value) end)
        interfaceGroup:AddChild(appearance)
    end
    local scaleSlider = AceGUI:Create("Slider")
    scaleSlider:SetLabel("UI Scale")
    scaleSlider:SetFullWidth(true)
    scaleSlider:SetSliderValues(0.6, 2.2, 0.1)
    scaleSlider:SetValue((self.db.profile.ui.scale or 0.9) + 0.1)
    local function applyScale(widget)
        local scale = self:CusRound(widget:GetValue() - 0.1, 1)
        if math.abs(scale - (self.db.profile.ui.scale or 0.9)) < 0.00001 then return end
        self.db.profile.ui.scale = scale
        self:UpdateUIScale()
    end
    scaleSlider:SetCallback("OnValueChanged", function(widget)
        -- A wheel step has no mouse-up event. Let the thumb move freely during a drag.
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then applyScale(widget) end
    end)
    scaleSlider:SetCallback("OnMouseUp", function(widget)
        -- Enter also fires this callback, with raw text as a number. Use the snapped value.
        widget:SetValue(widget:GetValue())
        applyScale(widget)
    end)
    interfaceGroup:AddChild(scaleSlider)
    addToggle(interfaceGroup, "Hide Minimap Icon", self.db.profile.minimap.hide, function(value)
        self.db.profile.minimap.hide = value
        self:ToggleMinimapIcon()
    end)
    addToggle(interfaceGroup, "Lock Minimap Icon", self.db.profile.minimap.lock, function(value)
        self:SetMinimapLocked(value)
    end)
    addButton(interfaceGroup, "Reset Window Position", function()
        self:ResetWindowPosition()
        self:UpdateMainTabLayout()
    end)
    addButton(interfaceGroup, "Reset Window Size", function()
        self:ResetWindowSize()
        self:UpdateMainTabLayout()
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
        local frame = DRE:CreateWindowWidget("Frame")
        self:ReleaseWindowOnClose(frame)
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
        DRE:ShowDialog("DEATHROLL_RESET_CONFIRM")
    end)

    for _, section in ipairs(getFunStatSections(self.devDuel)) do
        local group = addSection((self.devDuel and "1v1 · " or "Fun Statistics: ") .. section.title)
        for _, item in ipairs(section.stats) do
            addToggle(group, item.label, self.db.profile.funStats[item.setting], function(value)
                self:SetStatPreference(item.setting, value)
            end)
        end
    end
    if self.devDuel then
        local history = addSection("Opponent History")
        addToggle(history, "Wrong-range Rolls", self.db.profile.funStats.showLikelyCheater, function(value)
            self:SetStatPreference("showLikelyCheater", value)
        end)
        local group = addSection("Group Statistics")
        for _, option in ipairs(self.groupStatOptions) do
            addToggle(group, option.label, self.db.profile.funStats[option.key] ~= false, function(value)
                self:SetStatPreference(option.key, value)
            end)
        end
    end

    UI.settingsScroll = settingsScroll
    UI.settingsContent = settingsGroup

    self:AfterUI(0.1, function()
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
    if not playerData or (self.devDuel and not hasLedgerHistory(playerData)) then
        self:Print("No history found for " .. playerName)
        return
    end
    if self.devDuel then
        self:ShowMainWindow("history")
        local pane = UI.historyDropdown
        if pane then
            pane.search:SetText("")
            pane:Filter(playerName, true)
        end
        return
    end
    
    -- Create history window
    local histFrame = DRE:CreateWindowWidget("Frame")
    self:ReleaseWindowOnClose(histFrame)
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
    
    local wins = playerData.wins or 0
    local losses = playerData.losses or 0
    local text = string.format("Games Played: %d\n", wins + losses)
    text = text .. string.format("Wins: %d\n", wins)
    text = text .. string.format("Losses: %d\n", losses)
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
    if UI.currentTab == "history" then
        self:RefreshHistoryDropdown(UI.selectedHistoryPlayer)
        return
    end
    if UI.currentTab ~= "statistics" then
        return
    end

    if not UI.tabGroup then return end
    if self.devDuel then
        local scroll = UI.tabGroup.children[1]
        if scroll then scroll:Fire("OnStatsRefresh") end
        return
    end
    if not self.db or not self.db.profile.goldTracking then
        return
    end

    -- Rebuild the statistics tab so sectioned fun stats stay in sync with live edits/deletes/cleanup.
    UI.tabGeneration = (UI.tabGeneration or 0) + 1
    UI.tabGroup:ReleaseChildren()
    self:CreateStatsSection(UI.tabGroup)
    if UI.tabGroup.DoLayout then
        UI.tabGroup:DoLayout()
    end
    self:UpdateMainTabLayout()
end

-- Update history display for selected player
function DRE:UpdateHistoryDisplay(playerName)
    if self.devDuel then
        if UI.historyDropdown then UI.historyDropdown:Select(playerName) end
        return
    end
    if not UI.historyBox or not self.db or not self.db.profile.history then
        return
    end

    UI.selectedHistoryPlayer = playerName
    
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

function DRE:RefreshHistoryDropdown(preferredPlayer)
    if self.devDuel then
        if UI.historyDropdown then UI.historyDropdown:Refresh(preferredPlayer) end
        return
    end
    if not UI.historyDropdown or not self.db or not self.db.profile or not self.db.profile.history then
        return
    end

    local playerNames = {}
    local playerDropdown = {}
    for playerName, playerData in pairs(self.db.profile.history) do
        local wins = tonumber(playerData and playerData.wins) or 0
        local losses = tonumber(playerData and playerData.losses) or 0
        local recentGamesCount = (playerData and playerData.recentGames and #playerData.recentGames) or 0

        if wins > 0 or losses > 0 or recentGamesCount > 0 then
            table.insert(playerNames, playerName)
            playerDropdown[playerName] = playerName
        end
    end

    table.sort(playerNames)
    UI.historyDropdown:SetList(playerDropdown)

    local selectedPlayer = preferredPlayer
    if not selectedPlayer or not playerDropdown[selectedPlayer] then
        selectedPlayer = playerNames[1]
    end

    if selectedPlayer then
        UI.historyDropdown:SetValue(selectedPlayer)
        UI.selectedHistoryPlayer = selectedPlayer
        self:UpdateHistoryDisplay(selectedPlayer)
    else
        UI.historyDropdown:SetValue(nil)
        UI.selectedHistoryPlayer = nil
        if UI.historyBox then
            UI.historyBox:SetText("No players in history yet!")
            self:RefreshHistoryLayout()
        end
    end
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
    local gameStateGroup = DRE:CreateWindowWidget("InlineGroup")
    gameStateGroup:SetTitle("Game Status")
    gameStateGroup:SetFullWidth(true)
    gameStateGroup:SetLayout("Flow")
    spicyGroup:AddChild(gameStateGroup)
    
    local gameStateLabel = AceGUI:Create("Label")
    gameStateLabel:SetText("Ready to start a new Spicy Duel!")
    gameStateLabel:SetFullWidth(true)
    gameStateGroup:AddChild(gameStateLabel)
    
    -- Stance selection
    local stanceGroup = DRE:CreateWindowWidget("InlineGroup")
    stanceGroup:SetTitle("Choose Your Stance")
    stanceGroup:SetFullWidth(true)
    stanceGroup:SetLayout("Flow")
    spicyGroup:AddChild(stanceGroup)
    
    local stanceDropdown = self:CreateWindowWidget("Dropdown")
    stanceDropdown:SetList({
        ["attack"] = "Attack (Straightforward strike)",
        ["defend"] = "Defend (Shield and parry)",
        ["gamble"] = "Gamble (Wild lunge - high risk/reward)"
    })
    stanceDropdown:SetValue("attack")
    stanceDropdown:SetWidth(200)
    stanceGroup:AddChild(stanceDropdown)
    
    local rollButton = DRE:CreateWindowWidget("Button")
    rollButton:SetText("Roll & Reveal!")
    rollButton:SetWidth(120)
    rollButton:SetCallback("OnClick", function()
        self:HandleSpicyRoll(stanceDropdown:GetValue())
    end)
    stanceGroup:AddChild(rollButton)
    
    -- Challenge section
    local challengeGroup = DRE:CreateWindowWidget("InlineGroup")
    challengeGroup:SetTitle("Challenge Someone")
    challengeGroup:SetFullWidth(true)
    challengeGroup:SetLayout("Flow")
    spicyGroup:AddChild(challengeGroup)
    
    local challengeButton = DRE:CreateWindowWidget("Button")
    challengeButton:SetText("Challenge Target to Spicy Duel")
    challengeButton:SetFullWidth(true)
    challengeButton:SetCallback("OnClick", function()
        local target = DRE:GetUnitPlayerName("target")
        if not target or target == "" then
            self:Print("Please target a player first!")
            return
        end
        self:StartSpicyDuel(target)
    end)
    challengeGroup:AddChild(challengeButton)
    
    -- Rules section
    local rulesGroup = DRE:CreateWindowWidget("InlineGroup")
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
function DRE:SetTradeWagerModeEnabled(enabled)
    enabled = enabled == true
    if self:IsTradeWagerModeEnabled() == enabled then return end
    local setup = UI.currentTab == "deathroll" and UI.rollEdit and not self:HasActiveGame() and not self.acceptedChallenge
    local draft = setup and UI.goldEdit and self:CalculateWagerFromUI()
    if setup then UI.inputRoll = tonumber(UI.rollEdit:GetText()) end
    if draft then UI.inputWager = draft end
    self.db.profile.challengeSystem.trackWagerByTrade = enabled
    if self.devDuel then
        self:RefreshDuel()
    elseif setup and UI.tabGroup then
        self:SelectMainSection("deathroll")
        if draft then self:SetWagerInputs(draft) end
    end
end

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
    if self:IsGroupRoundActive() then return end
    if self.gameState and self.gameState.isActive then
        self:PerformRoll()
        return
    end
    local observed = UI.recentTargetRoll
    if observed then
        self:AcceptObservedChallenge(observed)
    else
        self:StartChallengeFlow()
    end
end

function DRE:AcceptObservedChallenge(observed)
    if self:HasActiveGame() or (self.devDuel and self.pendingChallenge) then return false end
    local accepted = self.devDuel and self.acceptedChallenge
    local target = accepted and accepted.sender or self:GetUnitPlayerName("target")
    if not observed or not self:IsSamePlayer(observed.playerName, target)
        or (accepted and observed ~= accepted.opener)
        or not observed.timestamp or GetTime() - observed.timestamp > (self.recentRollTimeWindow or 60) then
        UI.recentTargetRoll, UI.incomingChallenge = nil, nil
        self:UpdateChallengeButtonText()
        self:Print("That roll is no longer a current challenge. Ask your target to roll again.")
        return false
    end
    local trackTrade = self:IsTradeWagerModeEnabled()
    local wager = self:CalculateWagerFromUI()
    if accepted then
        trackTrade = accepted.trackTrade
        wager = trackTrade and 0 or accepted.wager
    end
    local valid, reason = self:ValidateGameInputs(target, observed.maxRoll, wager)
    if not valid then self:Print(reason); return false end
    if not self:IsBoundedInteger(observed.roll, 1, observed.maxRoll) then return false end
    if accepted and accepted.double and not self:MatchesDoubleOffer(accepted, target, "Won") then
        self.acceptedChallenge = nil
        self:ClearRecentRollsForPlayer(target)
        self:RefreshDuel()
        return false
    end
    if accepted and accepted.mode and accepted.mode ~= "classic" then
        if not self:StartActualGame(target, observed.maxRoll, wager, nil, trackTrade, accepted) then return false end
        self:HandleGameRoll(target, observed.roll, observed.maxRoll)
        if self.gameState and self.gameState.playerTurn then self:PerformRoll() end
        return true
    end
    if not self:StartActualGame(target, observed.maxRoll, wager, observed.roll, trackTrade, accepted or nil) then return false end
    self:AddRollToHistory(target, observed.roll, observed.maxRoll, false, nil)
    if observed.roll == 1 then
        self:HandleGameEnd(target, "WIN", wager, observed.maxRoll)
    else
        self:PerformRoll()
    end
    return true
end

function DRE:AcceptIncomingChallenge()
    if self.devDuel and self.acceptedChallenge then return self:AcceptObservedChallenge(self.acceptedChallenge.opener) end
    local challenge = UI.incomingChallenge
    if not challenge then return false end
    return self:AcceptObservedChallenge({ playerName = challenge.player, roll = challenge.roll,
        maxRoll = challenge.maxRoll, timestamp = challenge.timestamp })
end

function DRE:DenyIncomingChallenge()
    UI.incomingChallenge, UI.recentTargetRoll = nil, nil
    self:ClearRecentRollsForPlayer(self:GetUnitPlayerName("target"))
    self:UpdateChallengeButtonText()
end

function DRE:AcceptRecentRoll()
    return self:AcceptObservedChallenge(UI.recentTargetRoll)
end

-- Start the challenge flow
function DRE:StartChallengeFlow()
    if self:HasActiveGame() or self.disabled or (self.devDuel and self.pendingChallenge) then return false end
    local target = DRE:GetUnitPlayerName("target")
    if not target then
        self:Print("Please target a player whose name is available to the addon.")
        return false
    end

    -- Compare readable identities; UnitIsUnit can return a restricted value.
    if UnitExists("target") then
        if self:IsSamePlayer(target, self:GetUnitPlayerName("player")) then
            target = DRE:GetUnitPlayerName("player")
            self:Print("Self-duel mode activated!")
        else
            -- Check if target is a player (not NPC)
            if not UnitIsPlayer("target") then
                self:Print("You can only DeathRoll with other players, not NPCs!")
                return
            end
            
            -- Target is a valid player
            target = DRE:GetUnitPlayerName("target")
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
    
    local valid, reason = self:ValidateGameInputs(target, roll, totalWager)
    if not valid then self:Print(reason); return end
    if not usingTradeWager then
        valid, reason = self:ValidateWager(gold, silver, copper)
        if not valid then self:Print(reason); return end
    end
    local terms = self.devDuel and {mode = UI.duelMode or "classic"} or nil
    if self.devDuel and (self.db.profile.challengeSystem.sendWhisper or terms.mode ~= "classic")
        and not self:IsSamePlayer(target, self:GetUnitPlayerName("player")) then
        return self:InviteToDuel(target, roll, totalWager, usingTradeWager, terms)
    end
    if self:StartDeathRoll(target, roll, totalWager, usingTradeWager, terms)
        and not self:IsSamePlayer(target, self:GetUnitPlayerName("player")) then
        self:SendChallengeWhisper(target, roll, totalWager)
    end
end

-- Perform a roll in the active game
function DRE:PerformRoll()
    local game = self.gameState
    if not game or not game.isActive or self.disabled then return false end
    if game.pendingRoll then return false end
    if not game.playerTurn and not self:IsSamePlayer(game.target, self:GetUnitPlayerName("player")) then
        self:RestoreGameControls()
        return false
    end
    if not self:IsBoundedInteger(game.currentRoll, 1, self.MAX_ROLL) then return false end
    local request, range = {}, game.currentRoll
    game.pendingRoll = request
    self:UpdateGameUIState("WAITING_FOR_ROLL_RESULT")
    local function isCurrent()
        return not self.disabled and self.gameState == game and game.isActive and game.pendingRoll == request
    end
    C_Timer.After(0.1, function()
        if not isCurrent() then return end
        local ok, reason = pcall(RandomRoll, 1, range)
        if not ok and isCurrent() then
            game.pendingRoll = nil
            self:RestoreGameControls()
            self:Print("Unable to roll: " .. tostring(reason))
        end
    end)
    C_Timer.After(3.2, function()
        if not isCurrent() then return end
        game.pendingRoll = nil
        self:RestoreGameControls()
    end)
    return true
end

-- UpdateGameUIState function moved to Core.lua to avoid scoping issues


-- Clean up UI
function DRE:CleanupUI()
    UI.tabGeneration = (UI.tabGeneration or 0) + 1
    UI.layoutRefreshToken = (UI.layoutRefreshToken or 0) + 1
    -- This window owns persistent raw frame hooks. Keep it out of AceGUI's pool.
    if UI.mainWindow then UI.mainWindow:Hide() end
    local windows = {}
    for window in pairs(self.transientWindows or {}) do windows[#windows + 1] = window end
    for _, window in ipairs(windows) do window:Hide() end
end
