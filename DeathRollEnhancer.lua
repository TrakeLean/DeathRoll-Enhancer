-- DeathRoll-Enhancer.lua

-- Table to store win/loss records
DeathRollHistoryDB = DeathRollHistoryDB or {} -- SavedVariables to persist between sessions

local LibDBIcon = LibStub("LibDBIcon-1.0")

-- Check if LibDBIcon is available
if not LibDBIcon then
    print("|cFFFF0000<< |r|cFFFF0000Death|r|cFFFFFFFFRoll|r Enhancer: |cFFFF0000LibDBIcon-1.0 not found >>")
else
    print("|cFF00FF00<< |r|cFFFF0000Death|r|cFFFFFFFFRoll|r Enhancer: |cFF00FF00Has been loaded >>")
end

function CusRound(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Function to pick a random happy emote from a list
function GetRandomHappyEmote()
    local happyEmotes = {"CHEER", "LAUGH", "SALUTE", "DANCE", "VICTORY"} -- Add more happy emotes as needed
    local randomIndex = math.random(1, #happyEmotes)
    return happyEmotes[randomIndex]
end

-- Function to pick a random sad emote from a list
function GetRandomSadEmote()
    local sadEmotes = {"CRY", "SIGH", "SURRENDER", "LAY", "CONGRATULATE"} -- Add more sad emotes as needed
    local randomIndex = math.random(1, #sadEmotes)
    return sadEmotes[randomIndex]
end

-- Function to update win/loss history in the database, including gold won/loss
local function UpdateDeathRollHistory(targetName, won, gold)
    -- If this is the first time playing against this player, initialize their record
    if not DeathRollHistoryDB[targetName] then
        DeathRollHistoryDB[targetName] = {
            wins = 0,
            losses = 0,
            currentStreak = 0,
            longestWinStreak = 0,
            longestLossStreak = 0,
            goldWon = 0,
            goldLoss = 0
        }
    end

    -- Update win/loss count and current streak
    if won then
        DeathRollHistoryDB[targetName].wins = DeathRollHistoryDB[targetName].wins + 1
        DeathRollHistoryDB[targetName].currentStreak = (DeathRollHistoryDB[targetName].currentStreak >= 0) and DeathRollHistoryDB[targetName].currentStreak + 1 or 1
        DeathRollHistoryDB[targetName].goldWon = DeathRollHistoryDB[targetName].goldWon + (gold or 0)
    else
        DeathRollHistoryDB[targetName].losses = DeathRollHistoryDB[targetName].losses + 1
        DeathRollHistoryDB[targetName].currentStreak = (DeathRollHistoryDB[targetName].currentStreak <= 0) and DeathRollHistoryDB[targetName].currentStreak - 1 or -1
        DeathRollHistoryDB[targetName].goldLoss = DeathRollHistoryDB[targetName].goldLoss + (gold or 0)
    end

    -- Keep track of longest win streak
    if DeathRollHistoryDB[targetName].currentStreak > DeathRollHistoryDB[targetName].longestWinStreak then
        DeathRollHistoryDB[targetName].longestWinStreak = DeathRollHistoryDB[targetName].currentStreak
    end

    -- Keep track of longest loss streak (using absolute values for losses)
    if DeathRollHistoryDB[targetName].currentStreak < 0 and math.abs(DeathRollHistoryDB[targetName].currentStreak) > DeathRollHistoryDB[targetName].longestLossStreak then
        DeathRollHistoryDB[targetName].longestLossStreak = math.abs(DeathRollHistoryDB[targetName].currentStreak)
    end

    -- Print updated stats with conditional message based on win/loss streak
    local streakMessage
    if DeathRollHistoryDB[targetName].currentStreak > 0 then
        streakMessage = "Current win streak: " .. DeathRollHistoryDB[targetName].currentStreak
    elseif DeathRollHistoryDB[targetName].currentStreak < 0 then
        streakMessage = "Current loss streak: " .. math.abs(DeathRollHistoryDB[targetName].currentStreak)
    else
        streakMessage = "No current streak"
    end

    -- Print statement including gold stats
    print("DeathRoll history updated for " .. targetName .. ": " ..
          DeathRollHistoryDB[targetName].wins .. " wins, " ..
          DeathRollHistoryDB[targetName].losses .. " losses, " ..
          "Gold won: " .. DeathRollHistoryDB[targetName].goldWon .. ", " ..
          "Gold lost: " .. DeathRollHistoryDB[targetName].goldLoss .. ". " ..
          streakMessage .. ".")
end

-- Function to show deathroll history for a specific target, with color coding and additional details
local function ShowDeathRollHistory(target)
    if DeathRollHistoryDB[target] then
        local record = DeathRollHistoryDB[target]

        -- Color codes
        local winColor = "|cff00ff00"  -- Green for wins
        local lossColor = "|cffff0000"  -- Red for losses
        local neutralColor = "|cffffffff"  -- White/neutral color for neutral info
        local positiveGoldColor = "|cffffff00"  -- Gold color for positive gold (hex for yellow)
        local negativeGoldColor = "|cffff0000"  -- Red color for negative gold

        -- Determine gold status (positive or negative)
        local netGold = (record.goldWon or 0) - (record.goldLoss or 0)
        local goldColor = netGold >= 0 and positiveGoldColor or negativeGoldColor
        local goldStatus = netGold >= 0 and "Profit" or "Loss"
        
        -- Form the history message with colors
        local message = string.format("%s DeathRoll History: %s%d|r wins, %s%d|r losses.", 
                        target, winColor, record.wins, lossColor, record.losses)
        
        -- Add current streak
        if record.currentStreak > 0 then
            message = message .. " " .. winColor .. "Current win streak: " .. record.currentStreak .. "|r."
        elseif record.currentStreak < 0 then
            message = message .. " " .. lossColor .. "Current loss streak: " .. math.abs(record.currentStreak) .. "|r."
        else
            message = message .. " " .. neutralColor .. "No current streak.|r"
        end

        -- Add gold won/lost and net gold status
        message = message .. string.format(" Gold won: %s%d|r, Gold lost: %s%d|r. %sNet gold: %s%d (%s)|r.",
                        positiveGoldColor, record.goldWon or 0,
                        negativeGoldColor, record.goldLoss or 0,
                        goldColor, netGold, goldStatus)

        -- Print the final message
        print(message)
    else
        print("No DeathRoll history found for " .. target .. ".")
    end
end

local WindowX = 150
local WindowY = 70
local customText = "DeathRoll Enhancer!"
local targetName = nil
local rollNumber = nil
local UIOpened = false

-- Create a frame for measuring text dimensions
local textMeasureFrame = CreateFrame("Frame", nil, DeathRollFrame)
textMeasureFrame.title = textMeasureFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
textMeasureFrame.title:SetSize(0, 0) -- Set initial size to 0 to avoid interference

-- Function to create or update the infoFrame
local function UpdateInfoFrame(text)
    if not DeathRollFrame.infoFrame then
        DeathRollFrame.infoFrame = CreateFrame("Frame", nil, DeathRollFrame, "TranslucentFrameTemplate")
        DeathRollFrame.infoFrame:SetPoint("BOTTOM", DeathRollFrame.titleFrame.title, "TOP", 0, 0)
        DeathRollFrame.infoFrame.title = DeathRollFrame.infoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        DeathRollFrame.infoFrame.title:SetPoint("CENTER", DeathRollFrame.infoFrame)
        DeathRollFrame.infoFrame.title:SetTextColor(0.741, 0.718, 0.420, 1)
    end

    -- Set the text for measuring dimensions
    textMeasureFrame.title:SetText(text)

    -- Set the size of the infoFrame based on the text dimensions
    local textWidth = textMeasureFrame.title:GetStringWidth()
    DeathRollFrame.infoFrame:SetSize(textWidth + 30, WindowY*0.6) -- Add some padding
    DeathRollFrame.infoFrame.title:SetText(text)

    DeathRollFrame.infoFrame:SetScript("OnMouseDown", function(self) DeathRollFrame:StartMoving() end)
    DeathRollFrame.infoFrame:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        DeathRollFrame:StopMovingOrSizing()
    elseif button == "RightButton" then
        DeathRollFrame:HideUI(false)
    end
    end)
end

-- Create the main frame
local DeathRollFrame = CreateFrame("Frame", "DeathRollFrame", UIParent, "TranslucentFrameTemplate")
DeathRollFrame:SetPoint("CENTER", UIParent, "CENTER")
DeathRollFrame:SetSize(WindowX-15, WindowY)
DeathRollFrame:SetMovable(true)
DeathRollFrame:EnableMouse(true)
DeathRollFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
DeathRollFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
DeathRollFrame:Hide()

-- Create a translucent frame
DeathRollFrame.titleFrame = CreateFrame("Frame", nil, DeathRollFrame, "TranslucentFrameTemplate")
DeathRollFrame.titleFrame:SetSize(WindowX, WindowY*0.6)
DeathRollFrame.titleFrame:SetPoint("CENTER", DeathRollFrame, "TOP", 0, 0)
DeathRollFrame.titleFrame.title = DeathRollFrame.titleFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
DeathRollFrame.titleFrame.title:SetPoint("CENTER", DeathRollFrame.titleFrame, "CENTER", 0, 0)
DeathRollFrame.titleFrame.title:SetText("DeathRoll Enhancer!")
DeathRollFrame.titleFrame.title:SetTextColor(0.863, 0.078, 0.235, 1)
DeathRollFrame:SetFrameStrata("HIGH")
DeathRollFrame.titleFrame:SetScript("OnMouseDown", function(self) DeathRollFrame:StartMoving() end)
DeathRollFrame.titleFrame:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        DeathRollFrame:StopMovingOrSizing()
    elseif button == "RightButton" then
        DeathRollFrame:HideUI(false)
    end
end)

-- Create an input box for the number
DeathRollFrame.inputBox = CreateFrame("EditBox", "DeathRollInputBox", DeathRollFrame, "InputBoxTemplate")
DeathRollFrame.inputBox:SetSize(WindowX * 0.6, 25)
DeathRollFrame.inputBox:SetPoint("CENTER", DeathRollFrame, "CENTER", 0, 10)
DeathRollFrame.inputBox:SetAutoFocus(false)
DeathRollFrame.inputBox:SetMaxLetters(6)
DeathRollFrame.inputBox:SetNumeric(true)
DeathRollFrame.inputBox:SetJustifyH("CENTER")
DeathRollFrame.inputBox:SetScript("OnMouseDown", function(self, button)
    if button == "RightButton" then
        if not targetName then
            DeathRollFrame.inputBox:SetText("")
        end
    end
end)

-- Create a roll button
DeathRollFrame.rollButton = CreateFrame("Button", "DeathRollButton", DeathRollFrame, "GameMenuButtonTemplate")
DeathRollFrame.rollButton:SetSize(WindowX*0.75, 25)
DeathRollFrame.rollButton:SetPoint("BOTTOM", DeathRollFrame, "BOTTOM", 0, 11)
DeathRollFrame.rollButton:SetText("Roll!")
DeathRollFrame.rollButton:SetScript("OnClick", function(self)
    DeathRollFrame:OnRollButtonClick()
    DeathRollFrame.infoFrame:Show()
    if DeathRollFrame.infoFrame then
    else
        UpdateInfoFrame(customText)
        DeathRollFrame.inputBox:ClearFocus()
        
    end
end)

-- UIPanelInfoButton
-- Create a custom close button
DeathRollFrame.closeButton = CreateFrame("Button", "DeathRollCloseButton", DeathRollFrame, "UIPanelCloseButton")
DeathRollFrame.closeButton:SetPoint("LEFT", DeathRollFrame.titleFrame, "RIGHT", -6, 0)
DeathRollFrame.closeButton:SetScript("OnClick", function() DeathRollFrame:ResetUI(false) end)

-- -- Create a custom info button (FOR LATER)
-- DeathRollFrame.infoButton = CreateFrame("Button", "DeathRollInfoButton", DeathRollFrame, "UIPanelInfoButton")
-- DeathRollFrame.infoButton:SetPoint("RIGHT", DeathRollFrame.titleFrame, "LEFT", -3, 0)
-- DeathRollFrame.infoButton:SetScript("OnClick", function() DeathRollFrame:ResetUI(false) end)

-- Create a ScrollingMessageFrame
local scrollingMessageFrame = CreateFrame("ScrollingMessageFrame", "MyScrollingMessageFrame", DeathRollFrame)
scrollingMessageFrame:SetSize(WindowX, WindowY)
scrollingMessageFrame:SetPoint("TOP", DeathRollFrame, "BOTTOM", 0, 5)
scrollingMessageFrame:SetFontObject(ChatFontNormal)
scrollingMessageFrame:SetJustifyH("CENTER")
scrollingMessageFrame:SetFading(true)
scrollingMessageFrame:SetFadeDuration(30)
scrollingMessageFrame:SetMaxLines(5)
scrollingMessageFrame:SetFrameStrata("LOW")
-- Set new messages to be inserted at the top
scrollingMessageFrame:SetInsertMode("TOP")

-- Add text to the ScrollingMessageFrame
scrollingMessageFrame:AddMessage("AddOn Loaded!", 0.0, 1.0, 0.0, nil, false);
scrollingMessageFrame:AddMessage(" ");
scrollingMessageFrame:AddMessage(" ");
scrollingMessageFrame:AddMessage(" ");
scrollingMessageFrame:AddMessage(" ");


-- Disable mouse wheel scrolling
scrollingMessageFrame:EnableMouseWheel(false)

-- Adjust the size of the ScrollingMessageFrame to fit the content
scrollingMessageFrame:SetSize(200, scrollingMessageFrame:GetHeight())

-- Create a flag to determine if the button is in 'submit' mode or 'roll' mode
local isSubmittingGold = false

-- Function to handle the Roll button click and the Submit button click
function DeathRollFrame:OnRollButtonClick()
    if isSubmittingGold then
        -- This block is executed when we are submitting the gold wager
        local goldInput = self.inputBox:GetText()
        local gold = tonumber(goldInput) or 0 -- Default to 0 if invalid

        -- Update the deathroll history with the result
        UpdateDeathRollHistory(targetName, self.wonGame, gold) -- Use self.wonGame here

        -- Reset the UI and return the button to roll mode
        self.rollButton:SetText("Roll!")
        isSubmittingGold = false
        self.inputBox:ClearFocus()
        self.rollButton:Disable() -- Disable the button until the user clicks it again to start a new roll
        C_Timer.After(5, function() self:ResetUI(true) end)
    else
        -- This block is executed when the user clicks to start a roll
        local rollNumber = tonumber(self.inputBox:GetText())

        if rollNumber then
            -- Store the target player when rolling
            if not targetName then
                targetName = UnitName("target")
            end
            if rollNumber <= 1 then
                UpdateInfoFrame("Please enter a number greater than 1.")
                return
            end
            if targetName then
                RandomRoll(1, rollNumber)
                UpdateInfoFrame("Waiting for " .. targetName .. " to roll...")
                self.rollButton:SetText("Waiting...")
                self.rollButton:Disable()
            else
                UpdateInfoFrame("Target a player before rolling.")
            end
        else
            UpdateInfoFrame("Please enter a number.")
        end
        self.inputBox:ClearFocus()
    end
end

-- Event handler for CHAT_MSG_SYSTEM to capture the target's roll
function DeathRollFrame:OnChatMsgSystem(event, msg)
    local playerName, rollResult, targetRollString = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)")
    if playerName and targetName and targetRollString then
        -- Check if the roll is from the player you're dueling with
        if playerName == targetName then
            -- Check if the player has already rolled
            if (playerName ~= UnitName("player")) or (UnitName("player") == targetName) then
                self.rollButton:SetText("Roll!")
                self.rollButton:Enable()
                self.inputBox:SetText(tostring(rollResult)) -- Set the next max roll
                UpdateInfoFrame("You have a " .. CusRound((1 / (tonumber(rollResult))) * 100, 3) .. "% chance of losing")
                scrollingMessageFrame:AddMessage(msg, 0.863, 0.078, 0.235)
            else
                UpdateInfoFrame(targetName .. " has a " .. CusRound((1 / (tonumber(rollResult))) * 100, 3) .. "% chance of losing")
                scrollingMessageFrame:AddMessage(msg, 0.741, 0.718, 0.420)
            end

            if tonumber(rollResult) == 1 then
                self.rollButton:Disable()
                self.wonGame = playerName ~= UnitName("player") -- Store the result in self.wonGame
                UpdateInfoFrame(playerName .. " has won the death roll!")
                if self.wonGame then
                    scrollingMessageFrame:AddMessage("You won!!!")
                    DoEmote(GetRandomHappyEmote())
                else
                    scrollingMessageFrame:AddMessage("You lost...")
                    DoEmote(GetRandomSadEmote())
                end

                -- Ask how much gold was wagered
                DeathRollFrame.titleFrame.title:SetText("Wagered Gold?")
                self.inputBox:SetText("")
                self.rollButton:SetText("Submit")
                self.rollButton:Enable()
                
                -- Set the flag for submitting gold
                isSubmittingGold = true
            end
        else
            print(playerName .. " rolled, but they are not your duel target (" .. targetName .. "). Ignoring roll.")
        end
    end
end

-- Function to hide the UI when entering combat to avoid interference
function DeathRollFrame:OnPlayerRegenDisabled(event, ...)
    self:SetPropagateKeyboardInput(true)
    self:HideUI(true)
end

-- Function to show the UI when leaving combat
function DeathRollFrame:OnPlayerRegenEnabled(event, ...)
    self:SetPropagateKeyboardInput(false)
    if UIOpened then
        self:ShowUI()
    end
end

-- Function to show the DeathRoll UI
function DeathRollFrame:ShowUI()
    UIOpened = true
    self:Show()
end

-- Function to hide the DeathRoll UI
function DeathRollFrame:HideUI(combat)
    if not combat then
        UIOpened = false
    end
    self:Hide()
end

-- Function to reset variables and UI elements
function DeathRollFrame:ResetUI(endOfRoll)
    targetName = nil
    rollNumber = nil

    self.inputBox:SetText("")
    if self.infoFrame then
        self.infoFrame:Hide()
    end
    if not endOfRoll then
        scrollingMessageFrame:Clear()
    end
    DeathRollFrame.titleFrame.title:SetText("DeathRoll Enhancer!")
    self.rollButton:SetText("Roll!")
    self.rollButton:Enable()
    UIOpened = false
    self:HideUI(false)
end

-- Set a single OnEvent handler for both events
DeathRollFrame:SetScript("OnEvent", function(self, event, msg, ...)
    if event == "CHAT_MSG_SYSTEM" then
        self:OnChatMsgSystem(event, msg)
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:OnPlayerRegenDisabled(...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:OnPlayerRegenEnabled(...)
    end
end)

-- Slash command to open the DeathRoll UI
SLASH_DEATHROLL1 = "/deathroll"
SLASH_DEATHROLL2 = "/dr"
SlashCmdList["DEATHROLL"] = function(msg)
    DeathRollFrame:ShowUI()
end

-- Slash command to show deathroll history
SLASH_DEATHROLLHISTORY1 = "/deathrollhistory"
SLASH_DEATHROLLHISTORY2 = "/drh"
SlashCmdList["DEATHROLLHISTORY"] = function(msg)
    local target = msg:trim()
    if target == "" then
        target = UnitName("target")
    end
    if target then
        ShowDeathRollHistory(target)
    else
        print("Please provide a target name or select a target.")
    end
end

-----------------------------------------------------------------------------------------------------------------------

-- Table to store the addon settings (including minimap icon position)
DeathRollSettings = DeathRollSettings or {}

-- Default minimap button position if not saved
local defaultMinimapButtonPosition = {
    minimapPos = 225, -- Default angle position around the minimap (45 degrees as an example)
}

-- Create the minimap button using LibDBIcon
local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("DeathRollEnhancer", {
    type = "data source",
    text = "DeathRoll Enhancer",
    icon = "Interface\\AddOns\\DeathRollEnhancer\\Media\\Logo",
    OnClick = function(self, btn)
        if DeathRollFrame:IsVisible() then
            DeathRollFrame:HideUI(false)
        else
            DeathRollFrame:ShowUI()
        end
    end,
    OnTooltipShow = function(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        -- Tooltip for Death Roll Enhancer
        tooltip:AddLine("|cFFFF0000Death|r|cFFFF0000Roll|r Enhancer")
        tooltip:AddLine("|cff808080Left Click:|r Toggle UI")
        tooltip:AddLine("|cff808080Right-click the UI to hide it.")
        tooltip:AddLine("|cff808080The closing button resets the UI.")
    end,
})

local icon = LibStub("LibDBIcon-1.0")

-- Function to save the minimap icon position
local function SaveMinimapButtonPosition()
    -- Save the current position to SavedVariables
    DeathRollSettings.minimapPos = DeathRollSettings.minimapPos or defaultMinimapButtonPosition.minimapPos
end

-- Function to restore the minimap icon position
local function RestoreMinimapButtonPosition()
    -- Use saved position or default if none
    local pos = DeathRollSettings.minimapPos or defaultMinimapButtonPosition.minimapPos
    icon:Register("DeathRollEnhancer", miniButton, {
        minimapPos = pos,
        hide = false,
        lock = false
    })
end

-- Hook the addon loading to restore position
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addon)
    if addon == "DeathRollEnhancer" then
        -- Restore minimap button position when the addon is loaded
        RestoreMinimapButtonPosition()
    end
end)

-- Register callback to save the position when the icon is moved
icon:RegisterCallback("LibDBIcon_IconMoved", function(name, position)
    -- Save the position using the function
    DeathRollSettings.minimapPos = position
    SaveMinimapButtonPosition()
end)

-- Slash commands to hide or show the minimap icon
SLASH_MINIMAP1 = "/deathrollminimap"
SLASH_MINIMAP2 = "/drm"
SlashCmdList["MINIMAP"] = function(msg)
    if msg == "hide" then
        icon:Hide("DeathRollEnhancer")
        DeathRollSettings.hide = true
    elseif msg == "show" then
        icon:Show("DeathRollEnhancer")
        DeathRollSettings.hide = false
    else
        print("Use '/deathrollminimap show' or '/deathrollminimap hide'.")
    end
end

-- Register events to handle UI interactions (existing code)
DeathRollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
DeathRollFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
DeathRollFrame:RegisterEvent("PLAYER_REGEN_ENABLED")