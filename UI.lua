-- UI.lua
-- User interface components and frame management

local addonName, DeathRollEnhancer = ...
local DRE = DeathRollEnhancer

-- Create UI module
DRE.UI = {}
local UI = DRE.UI

-- UI constants - Optimized default sizing
local WINDOW_WIDTH = 250
local WINDOW_HEIGHT = 180
local PADDING = 16
local BUTTON_HEIGHT = 36
local INPUT_HEIGHT = 32
local SECTION_SPACING = 20

-- UI state
UI.targetName = nil
UI.rollNumber = nil
UI.isUIOpened = false
UI.isSubmittingGold = false
UI.wonGame = false
UI.waitingForOpponent = false
UI.playerRollResult = nil

-- Main UI frame
UI.mainFrame = nil
UI.titleFrame = nil
UI.infoFrame = nil
UI.inputBox = nil
UI.rollButton = nil
UI.closeButton = nil
UI.scrollingMessageFrame = nil
UI.textMeasureFrame = nil

function UI:Initialize()
    self:CreateMainFrame()
    self:CreateTitleFrame()
    self:CreateInputBox()
    self:CreateRollButton()
    self:CreateCloseButton()
    self:CreateScrollingMessageFrame()
    self:CreateTextMeasureFrame()
    
    -- Update component sizes to ensure proper initial positioning
    self:UpdateComponentSizes()
end

function UI:CreateMainFrame()
    self.mainFrame = CreateFrame("Frame", "DeathRollFrame", UIParent, "BasicFrameTemplateWithInset")
    self.mainFrame:SetPoint("CENTER", UIParent, "CENTER")
    self.mainFrame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    self.mainFrame:SetMovable(true)
    self.mainFrame:SetResizable(true)
    self.mainFrame:EnableMouse(true)
    self.mainFrame:SetScript("OnMouseDown", function(frame) frame:StartMoving() end)
    self.mainFrame:SetScript("OnMouseUp", function(frame) frame:StopMovingOrSizing() end)
    self.mainFrame:SetFrameStrata("HIGH")
    self.mainFrame:SetClampedToScreen(true)
    self.mainFrame:Hide()
    
    -- Create invisible fullscreen frame to detect clicks outside UI
    self.clickCatcher = CreateFrame("Frame", nil, UIParent)
    self.clickCatcher:SetAllPoints(UIParent)
    self.clickCatcher:EnableMouse(true)
    self.clickCatcher:SetFrameStrata("BACKGROUND") -- Much lower than main frame
    self.clickCatcher:Hide() -- Hidden by default
    
    self.clickCatcher:SetScript("OnMouseDown", function(frame, button)
        -- Only handle if input box has focus
        if not (self.inputBox and self.inputBox:HasFocus()) then
            return
        end
        
        -- Check if click is actually outside the UI frame
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x = x / scale
        y = y / scale
        
        if self.mainFrame:IsVisible() then
            local left = self.mainFrame:GetLeft()
            local right = self.mainFrame:GetRight() 
            local top = self.mainFrame:GetTop()
            local bottom = self.mainFrame:GetBottom()
            
            -- No external title to check anymore
            
            -- If click is outside the UI bounds, unfocus
            if left and right and top and bottom then
                if x < left or x > right or y < bottom or y > top then
                    self.inputBox:ClearFocus()
                end
            end
        end
    end)
    
    -- Resize bounds will be handled in the resize script
    
    -- Load saved scale
    local savedScale = DRE.Database and DRE.Database:GetSetting("ui_scale") or 1.0
    self.mainFrame:SetScale(savedScale)
    
    -- Add resize grip in bottom right corner
    local resizeButton = CreateFrame("Button", nil, self.mainFrame)
    resizeButton:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeButton:SetSize(16, 16)
    resizeButton:EnableMouse(true)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    resizeButton:SetScript("OnMouseDown", function(frame, button)
        if button == "LeftButton" then
            self.mainFrame:StartSizing("BOTTOMRIGHT")
            -- Enable live resizing updates
            self.mainFrame:SetScript("OnSizeChanged", function()
                self:UpdateComponentSizes()
            end)
        end
    end)
    
    resizeButton:SetScript("OnMouseUp", function(frame, button)
        self.mainFrame:StopMovingOrSizing()
        -- Disable live resizing updates
        self.mainFrame:SetScript("OnSizeChanged", nil)
        
        -- Enforce size bounds manually - 25% bigger minimums
        local width, height = self.mainFrame:GetSize()
        width = math.max(125, math.min(250, width))
        height = math.max(94, math.min(200, height))
        self.mainFrame:SetSize(width, height)
        
        -- Final update after size enforcement
        self:UpdateComponentSizes()
        
        -- Save new scale when resizing stops
        if DRE.Database then
            DRE.Database:SetSetting("ui_scale", self.mainFrame:GetScale())
        end
    end)
    
    -- Enhanced visual styling
    if self.mainFrame.Bg then
        -- Dark gradient background
        self.mainFrame.Bg:SetColorTexture(0.05, 0.05, 0.1, 0.95)
    end
    
    -- Add subtle border glow
    if self.mainFrame.Border then
        for i = 1, 8 do
            local border = _G[self.mainFrame:GetName().."Border"..i]
            if border then
                border:SetVertexColor(0.8, 0.6, 0.2, 1)
            end
        end
    end
    
    -- Add mouse wheel scaling
    self.mainFrame:EnableMouseWheel(true)
    self.mainFrame:SetScript("OnMouseWheel", function(frame, delta)
        if IsControlKeyDown() then
            local currentScale = frame:GetScale()
            local newScale = currentScale + (delta * 0.1)
            newScale = math.max(0.5, math.min(2.0, newScale)) -- Clamp between 0.5 and 2.0
            frame:SetScale(newScale)
            
            -- Save the new scale
            if DRE.Database then
                DRE.Database:SetSetting("ui_scale", newScale)
            end
        end
    end)
    
    -- Store reference to UI object in frame
    self.mainFrame.UI = self
    self.resizeButton = resizeButton
end

function UI:CreateTitleFrame()
    -- Use the built-in title bar of BasicFrameTemplateWithInset
    if self.mainFrame.TitleText then
        self.mainFrame.TitleText:SetText("DeathRoll Enhancer")
        self.mainFrame.TitleText:SetTextColor(1, 0.9, 0.3, 1) -- Brighter gold
    end
    
    -- Create internal status area
    self.titleFrame = CreateFrame("Frame", nil, self.mainFrame)
    self.titleFrame:SetSize(WINDOW_WIDTH - (PADDING * 2), 50)
    self.titleFrame:SetPoint("TOP", self.mainFrame, "TOP", 0, -30)
    
    -- Add header background with gradient
    local headerBg = self.titleFrame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.1, 0.1, 0.2, 0.6)
    
    -- Add subtle border line at bottom
    local borderLine = self.titleFrame:CreateTexture(nil, "BORDER")
    borderLine:SetHeight(2)
    borderLine:SetPoint("BOTTOMLEFT", self.titleFrame, "BOTTOMLEFT", 0, 0)
    borderLine:SetPoint("BOTTOMRIGHT", self.titleFrame, "BOTTOMRIGHT", 0, 0)
    borderLine:SetColorTexture(0.8, 0.6, 0.2, 0.8)
    
    -- Status text
    self.titleFrame.title = self.titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.titleFrame.title:SetPoint("CENTER", self.titleFrame, "CENTER", 0, 2)
    self.titleFrame.title:SetText("Ready to roll! Target a player first.")
    self.titleFrame.title:SetTextColor(0.8, 0.8, 0.8, 1) -- Light gray for status
    self.titleFrame.title:SetShadowOffset(1, -1)
    self.titleFrame.title:SetShadowColor(0, 0, 0, 0.8)
    
    -- Make title frame draggable
    self.titleFrame:EnableMouse(true)
    self.titleFrame:SetScript("OnMouseDown", function() self.mainFrame:StartMoving() end)
    self.titleFrame:SetScript("OnMouseUp", function(frame, button)
        if button == "LeftButton" then
            self.mainFrame:StopMovingOrSizing()
        elseif button == "RightButton" then
            self:HideUI(false)
        end
    end)
end

function UI:CreateInputBox()
    -- Create enhanced input section container with background
    local inputContainer = CreateFrame("Frame", nil, self.mainFrame)
    inputContainer:SetSize(WINDOW_WIDTH - (PADDING * 2), 65)
    inputContainer:SetPoint("TOP", self.titleFrame, "BOTTOM", 0, -SECTION_SPACING)
    
    -- Add section background
    local sectionBg = inputContainer:CreateTexture(nil, "BACKGROUND")
    sectionBg:SetAllPoints()
    sectionBg:SetColorTexture(0.08, 0.08, 0.15, 0.4)
    
    -- Enhanced input label with better styling
    self.inputLabel = inputContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.inputLabel:SetPoint("TOP", inputContainer, "TOP", 0, -4)
    self.inputLabel:SetText("Roll Amount:")
    self.inputLabel:SetTextColor(0.9, 0.8, 0.5, 1) -- Warm gold tone
    self.inputLabel:SetShadowOffset(1, -1)
    self.inputLabel:SetShadowColor(0, 0, 0, 0.6)
    
    -- Create custom styled input box
    self.inputBox = CreateFrame("EditBox", "DeathRollInputBox", inputContainer, "InputBoxTemplate")
    self.inputBox:SetSize(WINDOW_WIDTH - (PADDING * 4), INPUT_HEIGHT)
    self.inputBox:SetPoint("TOPLEFT", inputContainer, "TOPLEFT", PADDING * 2, -25)
    self.inputBox:SetAutoFocus(false)
    self.inputBox:SetMaxLetters(8)
    self.inputBox:SetNumeric(true)
    self.inputBox:SetJustifyH("CENTER")
    self.inputBox:SetFontObject("GameFontHighlightLarge")
    
    -- Style the input box background
    if self.inputBox.Left then
        self.inputBox.Left:SetVertexColor(0.6, 0.5, 0.3, 0.8)
    end
    if self.inputBox.Right then
        self.inputBox.Right:SetVertexColor(0.6, 0.5, 0.3, 0.8)
    end
    if self.inputBox.Middle then
        self.inputBox.Middle:SetVertexColor(0.6, 0.5, 0.3, 0.8)
    end
    
    self.inputBox:SetScript("OnMouseDown", function(frame, button)
        if button == "RightButton" then
            if not self.targetName then
                frame:SetText("")
            end
        end
    end)
    
    -- Add focus glow effect and click catcher control
    self.inputBox:SetScript("OnEditFocusGained", function(frame)
        if frame.Left then frame.Left:SetVertexColor(0.9, 0.7, 0.2, 1) end
        if frame.Right then frame.Right:SetVertexColor(0.9, 0.7, 0.2, 1) end
        if frame.Middle then frame.Middle:SetVertexColor(0.9, 0.7, 0.2, 1) end
        
        -- Show click catcher when input gains focus
        if self.clickCatcher then
            self.clickCatcher:Show()
        end
    end)
    
    self.inputBox:SetScript("OnEditFocusLost", function(frame)
        if frame.Left then frame.Left:SetVertexColor(0.6, 0.5, 0.3, 0.8) end
        if frame.Right then frame.Right:SetVertexColor(0.6, 0.5, 0.3, 0.8) end
        if frame.Middle then frame.Middle:SetVertexColor(0.6, 0.5, 0.3, 0.8) end
        
        -- Hide click catcher when input loses focus
        if self.clickCatcher then
            self.clickCatcher:Hide()
        end
    end)
    
    self.inputContainer = inputContainer
end

function UI:CreateRollButton()
    -- Create enhanced button container
    local buttonContainer = CreateFrame("Frame", nil, self.mainFrame)
    buttonContainer:SetSize(WINDOW_WIDTH - (PADDING * 2), 55)
    buttonContainer:SetPoint("TOP", self.inputContainer, "BOTTOM", 0, -SECTION_SPACING)
    
    -- Add section background
    local sectionBg = buttonContainer:CreateTexture(nil, "BACKGROUND")
    sectionBg:SetAllPoints()
    sectionBg:SetColorTexture(0.08, 0.08, 0.15, 0.4)
    
    -- Create custom styled button
    self.rollButton = CreateFrame("Button", "DeathRollButton", buttonContainer, "UIPanelButtonTemplate")
    self.rollButton:SetSize(WINDOW_WIDTH - (PADDING * 3), BUTTON_HEIGHT)
    self.rollButton:SetPoint("CENTER", buttonContainer, "CENTER", 0, 0)
    
    -- Enhanced button styling
    self.rollButton:SetText("Roll!")
    self.rollButton:SetNormalFontObject("GameFontNormalLarge")
    self.rollButton:SetHighlightFontObject("GameFontHighlightLarge")
    self.rollButton:SetDisabledFontObject("GameFontDisableLarge")
    
    -- Custom button colors - with nil checks
    local normalTexture = self.rollButton:GetNormalTexture()
    local highlightTexture = self.rollButton:GetHighlightTexture()
    local pushedTexture = self.rollButton:GetPushedTexture()
    
    if normalTexture then
        normalTexture:SetVertexColor(0.2, 0.6, 0.2, 1) -- Green
    end
    if highlightTexture then
        highlightTexture:SetVertexColor(0.3, 0.8, 0.3, 1) -- Bright green on hover
    end
    if pushedTexture then
        pushedTexture:SetVertexColor(0.1, 0.4, 0.1, 1) -- Dark green when pressed
    end
    
    -- Add button glow effect on hover
    self.rollButton:SetScript("OnEnter", function(frame)
        local tex = frame:GetNormalTexture()
        if tex then
            tex:SetVertexColor(0.3, 0.8, 0.3, 1)
        end
    end)
    
    self.rollButton:SetScript("OnLeave", function(frame)
        local tex = frame:GetNormalTexture()
        if frame:IsEnabled() and tex then
            tex:SetVertexColor(0.2, 0.6, 0.2, 1)
        end
    end)
    
    self.rollButton:SetScript("OnClick", function()
        self:OnRollButtonClick()
        self.inputBox:ClearFocus()
    end)
    
    self.buttonContainer = buttonContainer
end

-- Enhanced helper function to update button appearance with colors
function UI:SetButtonState(text, color, enabled)
    if not self.rollButton then return end
    
    self.rollButton:SetText(text)
    
    local normalTexture = self.rollButton:GetNormalTexture()
    if not normalTexture then return end
    
    if enabled then
        self.rollButton:Enable()
        -- Set colors based on state
        if color == "green" then
            normalTexture:SetVertexColor(0.2, 0.6, 0.2, 1)
        elseif color == "yellow" then
            normalTexture:SetVertexColor(0.8, 0.8, 0.2, 1)
        elseif color == "blue" then
            normalTexture:SetVertexColor(0.2, 0.4, 0.8, 1)
        elseif color == "red" then
            normalTexture:SetVertexColor(0.8, 0.2, 0.2, 1)
        end
    else
        self.rollButton:Disable()
        normalTexture:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    end
end

function UI:CreateCloseButton()
    -- The BasicFrameTemplateWithInset already provides a close button
    -- Just customize its behavior
    if self.mainFrame.CloseButton then
        self.mainFrame.CloseButton:SetScript("OnClick", function() 
            self:ResetUI(false) 
        end)
    end
end

function UI:CreateScrollingMessageFrame()
    -- Create enhanced status area at bottom of main frame
    local statusContainer = CreateFrame("Frame", nil, self.mainFrame)
    statusContainer:SetSize(WINDOW_WIDTH - (PADDING * 2), 50)
    statusContainer:SetPoint("BOTTOM", self.mainFrame, "BOTTOM", 0, PADDING + 5)
    
    -- Add status background
    -- local statusBg = statusContainer:CreateTexture(nil, "BACKGROUND")
    -- statusBg:SetAllPoints()
    -- statusBg:SetColorTexture(0.08, 0.08, 0.15, 0.4)
    
    -- Add top border line
    -- local topLine = statusContainer:CreateTexture(nil, "BORDER")
    -- topLine:SetHeight(2)
    -- topLine:SetPoint("TOPLEFT", statusContainer, "TOPLEFT", 0, 0)
    -- topLine:SetPoint("TOPRIGHT", statusContainer, "TOPRIGHT", 0, 0)
    -- topLine:SetColorTexture(0.8, 0.6, 0.2, 0.6)
    
    self.scrollingMessageFrame = CreateFrame("ScrollingMessageFrame", "MyScrollingMessageFrame", statusContainer)
    self.scrollingMessageFrame:SetSize(WINDOW_WIDTH - (PADDING * 2), 40)
    self.scrollingMessageFrame:SetPoint("CENTER", statusContainer, "CENTER", 0, 0)
    
    -- Enhanced font setup
    local font = ChatFontNormal or GameFontNormal
    if font then
        self.scrollingMessageFrame:SetFontObject(font)
    else
        -- Fallback font setup with larger size
        self.scrollingMessageFrame:SetFont("Fonts\\FRIZQT__.TTF", 12)
    end
    
    self.scrollingMessageFrame:SetJustifyH("CENTER")
    self.scrollingMessageFrame:SetFading(true)
    self.scrollingMessageFrame:SetFadeDuration(20)
    self.scrollingMessageFrame:SetMaxLines(3)
    self.scrollingMessageFrame:SetFrameStrata("MEDIUM")
    self.scrollingMessageFrame:SetInsertMode("TOP")
    self.scrollingMessageFrame:EnableMouseWheel(false)
    
    -- Initialize with enhanced startup message
    self.scrollingMessageFrame:AddMessage("Ready to roll! Target a player first.", 0.3, 1.0, 0.3)
    
    self.statusContainer = statusContainer
end

function UI:CreateTextMeasureFrame()
    self.textMeasureFrame = CreateFrame("Frame", nil, self.mainFrame)
    self.textMeasureFrame.title = self.textMeasureFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.textMeasureFrame.title:SetSize(0, 0)
end

-- Update component sizes when frame is resized
function UI:UpdateComponentSizes()
    local frameWidth, frameHeight = self.mainFrame:GetSize()
    local padding = math.max(4, frameWidth * 0.04) -- Smaller dynamic padding
    
    -- Calculate font scale based on window size
    local baseFontScale = math.min(frameWidth / 250, frameHeight / 180) -- Scale relative to new default size
    local fontScale = math.max(0.6, math.min(1.2, baseFontScale)) -- Clamp between 60% and 120%
    
    -- Calculate proportional heights with smaller minimums
    local titleHeight = math.max(15, frameHeight * 0.16)      -- 16% of height, min 15px
    local inputHeight = math.max(25, frameHeight * 0.32)      -- 32% of height, min 25px
    local buttonHeight = math.max(18, frameHeight * 0.22)     -- 22% of height, min 18px  
    local statusHeight = math.max(15, frameHeight * 0.20)     -- 20% of height, min 15px
    
    -- Update title frame (now status area)
    if self.titleFrame then
        self.titleFrame:SetSize(frameWidth - (padding * 2), titleHeight)
        -- Scale status text font
        if self.titleFrame.title then
            local fontSize = math.max(8, 12 * fontScale)
            self.titleFrame.title:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
        end
    end
    
    -- Update built-in title bar font
    if self.mainFrame.TitleText then
        local titleFontSize = math.max(10, 14 * fontScale)
        self.mainFrame.TitleText:SetFont("Fonts\\FRIZQT__.TTF", titleFontSize, "OUTLINE")
    end
    
    -- Update input container - clear old anchors and reposition
    if self.inputContainer then
        self.inputContainer:ClearAllPoints()
        self.inputContainer:SetSize(frameWidth - (padding * 2), inputHeight)
        self.inputContainer:SetPoint("TOP", self.titleFrame, "BOTTOM", 0, -math.max(5, padding * 0.5))
        
        -- Scale input label font
        if self.inputLabel then
            local labelFontSize = math.max(6, 10 * fontScale)
            self.inputLabel:SetFont("Fonts\\FRIZQT__.TTF", labelFontSize, "OUTLINE")
        end
        
        -- Update input box within container with smaller minimum
        if self.inputBox then
            local inputBoxHeight = math.max(12, inputHeight * 0.35)
            self.inputBox:ClearAllPoints()
            self.inputBox:SetSize(frameWidth - (padding * 4), inputBoxHeight)
            self.inputBox:SetPoint("TOPLEFT", self.inputContainer, "TOPLEFT", padding * 2, -20)
            
            -- Scale input font (EditBox uses different font setting method)
            local inputFontSize = math.max(8, 12 * fontScale)
            if inputFontSize <= 10 then
                self.inputBox:SetFontObject("GameFontNormalSmall")
            else
                self.inputBox:SetFontObject("GameFontNormal")
            end
        end
    end
    
    -- Update button container - clear old anchors and reposition
    if self.buttonContainer then
        self.buttonContainer:ClearAllPoints()
        self.buttonContainer:SetSize(frameWidth - (padding * 2), buttonHeight)
        self.buttonContainer:SetPoint("TOP", self.inputContainer, "BOTTOM", 0, -math.max(5, padding * 0.5))
        
        -- Update button within container with smaller minimum
        if self.rollButton then
            local buttonWidth = frameWidth - (padding * 3)
            local buttonBtnHeight = math.max(12, buttonHeight * 0.7)
            self.rollButton:SetSize(buttonWidth, buttonBtnHeight)
            
            -- Scale button font (use appropriate font objects)
            local buttonFontSize = math.max(8, 12 * fontScale)
            if buttonFontSize <= 10 then
                self.rollButton:SetNormalFontObject("GameFontNormalSmall")
                self.rollButton:SetHighlightFontObject("GameFontHighlightSmall")
                self.rollButton:SetDisabledFontObject("GameFontDisableSmall")
            else
                self.rollButton:SetNormalFontObject("GameFontNormal")
                self.rollButton:SetHighlightFontObject("GameFontHighlight")
                self.rollButton:SetDisabledFontObject("GameFontDisable")
            end
        end
    end
    
    -- Update status container - clear old anchors and reposition
    if self.statusContainer then
        self.statusContainer:ClearAllPoints()
        self.statusContainer:SetSize(frameWidth - (padding * 2), statusHeight)
        self.statusContainer:SetPoint("TOP", self.buttonContainer, "BOTTOM", 0, -math.max(8, padding * 0.7))
        
        -- Update scrolling message frame with smaller minimum
        if self.scrollingMessageFrame then
            local msgHeight = math.max(10, statusHeight - 8)
            self.scrollingMessageFrame:SetSize(frameWidth - (padding * 2), msgHeight)
            
            -- Skip font scaling for ScrollingMessageFrame to avoid errors
            -- The font is set during creation and doesn't need dynamic scaling
        end
    end
    
    -- Update info frame if it exists
    if self.infoFrame then
        local text = self.infoFrame.title:GetText()
        if text then
            self:UpdateInfoFrame(text)
        end
    end
end

function UI:UpdateInfoFrame(text)
    -- Now uses the title area for status messages instead of separate info frame
    if self.titleFrame and self.titleFrame.title then
        self.titleFrame.title:SetText(text)
        -- Color code based on message type
        if string.find(text, "error") or string.find(text, "Please") or string.find(text, "Target") then
            self.titleFrame.title:SetTextColor(1.0, 0.4, 0.4, 1) -- Red for errors
        elseif string.find(text, "Waiting") or string.find(text, "Battling") then
            self.titleFrame.title:SetTextColor(1.0, 0.8, 0.2, 1) -- Yellow for waiting/active
        elseif string.find(text, "Complete") or string.find(text, "won") then
            self.titleFrame.title:SetTextColor(0.2, 1.0, 0.2, 1) -- Green for success
        else
            self.titleFrame.title:SetTextColor(0.8, 0.8, 0.8, 1) -- Default gray
        end
    end
end

function UI:OnRollButtonClick()
    -- Don't allow rolling if waiting for opponent
    if self.waitingForOpponent then
        self:UpdateInfoFrame("Still waiting for " .. (self.targetName or "opponent") .. " to roll!")
        return
    end
    
    if self.isSubmittingGold then
        self:HandleGoldSubmission()
    else
        self:HandleRollSubmission()
    end
end

function UI:HandleGoldSubmission()
    local goldInput = self.inputBox:GetText()

    if goldInput == "" then
        self:UpdateInfoFrame("Please enter a value.")
        return
    end

    local gold = tonumber(goldInput)
    if not gold then
        self:UpdateInfoFrame("Please enter a valid number.")
        return
    end

    -- Update database with the result
    if DRE.Database then
        DRE.Database:UpdateDeathRollHistory(self.targetName, self.wonGame, gold)
    end

    -- Reset UI state
    self.isSubmittingGold = false
    self.inputBox:ClearFocus()
    self.rollButton:Disable()

    -- Update status to show battle is over
    self:UpdateInfoFrame("Battle Complete!")

    -- Auto-reset after 5 seconds
    C_Timer.After(5, function() self:ResetUI(true) end)
end

function UI:HandleRollSubmission()
    local rollInput = self.inputBox:GetText()

    if rollInput == "" then
        self:UpdateInfoFrame("Please enter a value.")
        return
    end

    local rollNumber = tonumber(rollInput)
    if not rollNumber then
        self:UpdateInfoFrame("Please enter a valid number.")
        return
    end

    if rollNumber <= 1 then
        self:UpdateInfoFrame("Please enter a number greater than 1.")
        return
    end

    -- Store target player when rolling
    if not self.targetName then
        self.targetName = UnitName("target")
        if self.targetName then
            -- Update status to show who we're battling
            self:UpdateInfoFrame("Battling: " .. self.targetName)
        end
    end

    if not self.targetName then
        self:UpdateInfoFrame("Target a player before rolling.")
        return
    end

    -- Start gold tracking
    if DRE.GoldTracking then
        DRE.GoldTracking:StartTracking(self.targetName)
    end

    -- Initiate the roll
    RandomRoll(1, rollNumber)
    self:UpdateInfoFrame("Waiting for " .. self.targetName .. " to roll...")
    self:SetButtonState("Waiting...", "yellow", false)
    self.inputBox:ClearFocus()
end

function UI:OnGameComplete(playerName, rollResult, wonGame)
    self.rollButton:Disable()
    self.wonGame = wonGame
    
    self:UpdateInfoFrame(playerName .. " has won the death roll!")
    
    if wonGame then
        self.scrollingMessageFrame:AddMessage("You won!!!")
        DoEmote(DRE.GetRandomHappyEmote())
    else
        self.scrollingMessageFrame:AddMessage("You lost...")
        DoEmote(DRE.GetRandomSadEmote())
    end

    -- Check for automatic gold detection
    C_Timer.After(2, function()
        self:CheckForAutomaticGold()
    end)
end

-- Check if gold was automatically detected and fill it in
function UI:CheckForAutomaticGold()
    local detectedGold = 0
    
    if DRE.GoldTracking then
        local status = DRE.GoldTracking:GetTrackingStatus()
        if status.detectedAmount > 0 then
            detectedGold = status.detectedAmount
        elseif status.isTracking then
            -- Still tracking, show status
            local timeLeft = math.max(0, math.floor(status.timeRemaining))
            self:ShowTrackingStatus(timeLeft)
            return
        end
    end
    
    if detectedGold > 0 then
        -- Auto-fill detected gold amount
        self:AutoFillGoldAmount(detectedGold)
    else
        -- Switch to manual gold submission mode
        self:SwitchToGoldSubmissionMode()
    end
end

-- Show tracking status to user
function UI:ShowTrackingStatus(timeLeft)
    local minutes = math.floor(timeLeft / 60)
    local seconds = timeLeft % 60
    local timeString = string.format("%d:%02d", minutes, seconds)
    
    self.titleFrame.title:SetText("Tracking Gold... " .. timeString)
    self.inputBox:SetText("")
    self:SetButtonState("Monitoring...", "blue", false)
    self.isSubmittingGold = false
    
    -- Check again in 3 seconds
    C_Timer.After(3, function()
        if self.isSubmittingGold == false then -- Still in tracking mode
            self:CheckForAutomaticGold()
        end
    end)
    
end

-- Auto-fill detected gold amount
function UI:AutoFillGoldAmount(goldAmount)
    local goldCopper = math.floor(goldAmount / 10000)
    local goldDisplay = goldCopper > 0 and tostring(goldCopper) or tostring(goldAmount)
    
    -- Get detection source for better feedback
    local source = "unknown"
    if DRE.GoldTracking then
        local status = DRE.GoldTracking:GetTrackingStatus()
        source = status.source or "unknown"
    end
    
    local sourceText = ""
    if source == "trade_giving" or source == "trade_receiving" then
        sourceText = " (Trade)"
    elseif source == "money_gained" or source == "money_lost" then
        sourceText = " (Direct)"
    end
    
    self.titleFrame.title:SetText("Detected: " .. DRE.GoldTracking:FormatGold(goldAmount) .. sourceText)
    self.inputBox:SetText(goldDisplay)
    self:SetButtonState("Confirm", "green", true)
    self.isSubmittingGold = true
    
    -- Show confidence indicator in scroll frame
    self.scrollingMessageFrame:AddMessage("Gold detected: " .. DRE.GoldTracking:FormatGold(goldAmount) .. sourceText, 0.0, 1.0, 0.0)
    
end

-- Switch to manual gold submission mode
function UI:SwitchToGoldSubmissionMode()
    self.titleFrame.title:SetText("Wagered Gold?")
    self.inputBox:SetText("")
    self:SetButtonState("Submit", "green", true)
    self.isSubmittingGold = true
    
    -- Show fallback message
    self.scrollingMessageFrame:AddMessage("No gold auto-detected - manual entry", 1.0, 1.0, 0.0)
end

function UI:OnPlayerRoll(playerName, rollResult, targetRollString)
    local isPlayerRoll = (playerName == UnitName("player"))
    local isTargetRoll = (playerName == self.targetName)
    
    if not isPlayerRoll and not isTargetRoll then
        print(playerName .. " rolled, but they are not your duel target (" .. self.targetName .. "). Ignoring roll.")
        return
    end

    local rollNum = tonumber(rollResult)
    local chanceText = "You have a " .. DRE.CusRound((1 / rollNum) * 100, 3) .. "% chance of losing"
    
    if isPlayerRoll then
        -- Player rolled - now wait for opponent to roll using this number
        self.playerRollResult = rollNum
        self.waitingForOpponent = true
        self:UpdateInfoFrame("Waiting for " .. self.targetName .. " to roll 1-" .. rollNum .. "...")
        self:SetButtonState("Waiting...", "yellow", false)
        self.scrollingMessageFrame:AddMessage(playerName .. " rolls " .. rollResult .. " (" .. targetRollString .. ")", 0.741, 0.718, 0.420)
        -- Keep the original roll amount in input box
        
    else
        -- Opponent rolled - check if this is valid
        if not self.waitingForOpponent or not self.playerRollResult then
            -- Could be the opponent starting a new death roll or continuing one we're not tracking
            print("Opponent rolled but we're not expecting a roll. They may be starting a new game or continuing a different sequence.")
            return
        end
        
        -- Check if opponent rolled within the correct range
        local expectedMax = self.playerRollResult
        if rollNum < 1 or rollNum > expectedMax then
            -- Invalid roll - send whisper and ignore
            local message = "Please roll 1-" .. expectedMax .. " (you rolled " .. rollNum .. ")"
            SendChatMessage(message, "WHISPER", nil, playerName)
            print("Opponent's roll (" .. rollNum .. ") is invalid. Expected 1-" .. expectedMax .. ". Whispered correction.")
            
            -- Show rejection in scroll frame
            self.scrollingMessageFrame:AddMessage("❌ " .. playerName .. " rolled " .. rollNum .. " (invalid - need 1-" .. expectedMax .. ")", 1.0, 0.2, 0.2)
            
            -- Update UI to show we're still waiting
            self:UpdateInfoFrame("Still waiting for " .. self.targetName .. " to roll 1-" .. expectedMax .. "...")
            return
        end
        
        -- Valid opponent roll - now player can roll using opponent's number
        self.waitingForOpponent = false
        self.playerRollResult = nil
        self:UpdateInfoFrame(chanceText)
        self:SetButtonState("Roll!", "green", true)
        self.inputBox:SetText(tostring(rollResult))
        self.scrollingMessageFrame:AddMessage(playerName .. " rolls " .. rollResult .. " (" .. targetRollString .. ")", 0.863, 0.078, 0.235)
    end

    -- Check for game end (roll of 1)
    if rollNum == 1 then
        local winner = (playerName ~= UnitName("player"))
        self:OnGameComplete(playerName, rollResult, winner)
    end
end

function UI:ShowUI()
    self.isUIOpened = true
    self.mainFrame:Show()
    -- Don't show click catcher here - only when input has focus
end

function UI:HideUI(combat)
    if not combat then
        self.isUIOpened = false
    end
    self.mainFrame:Hide()
    if self.clickCatcher then
        self.clickCatcher:Hide()
    end
end

function UI:ResetUI(endOfRoll)
    -- Stop gold tracking
    if DRE.GoldTracking then
        DRE.GoldTracking:Reset()
    end
    
    -- Reset state
    self.targetName = nil
    self.rollNumber = nil
    self.isSubmittingGold = false
    self.wonGame = false
    self.waitingForOpponent = false
    self.playerRollResult = nil

    -- Reset UI elements
    self.inputBox:SetText("")
    if self.infoFrame then
        self.infoFrame:Hide()
    end
    
    if not endOfRoll then
        self.scrollingMessageFrame:Clear()
    end
    
    self:UpdateInfoFrame("Ready to roll! Target a player first.")
    self:SetButtonState("Roll!", "green", true)
    
    self.isUIOpened = false
    self:HideUI(false)
end

-- Combat handling
function UI:OnCombatStart()
    self.mainFrame:SetPropagateKeyboardInput(true)
    self:HideUI(true)
end

function UI:OnCombatEnd()
    self.mainFrame:SetPropagateKeyboardInput(false)
    if self.isUIOpened then
        self:ShowUI()
    end
end

-- Reset UI scale to default
function UI:ResetScale()
    if self.mainFrame then
        self.mainFrame:SetScale(1.0)
        self.mainFrame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
        self:UpdateComponentSizes()
    end
    
    if DRE.Database then
        DRE.Database:SetSetting("ui_scale", 1.0)
    end
    
    print("|cFF00FF00DeathRoll: |rUI scale reset to default")
end

-- Getter methods for other modules
function UI:GetTargetName()
    return self.targetName
end

function UI:GetMainFrame()
    return self.mainFrame
end