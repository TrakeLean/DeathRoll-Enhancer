-- DeathRollAddon.lua

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

local WindowX = 100
local WindowY = 60

-- Create the main frame
local DeathRollFrame = CreateFrame("Frame", "DeathRollFrame", UIParent)
DeathRollFrame:SetSize(WindowX, WindowY)
DeathRollFrame:SetPoint("CENTER", UIParent, "CENTER")
DeathRollFrame:SetMovable(true)
DeathRollFrame:EnableMouse(true)
DeathRollFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
DeathRollFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
DeathRollFrame:Hide()

-- Create a title for the frame
DeathRollFrame.title = DeathRollFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
DeathRollFrame.title:SetPoint("TOP", DeathRollFrame, "TOP", 0, 0)
DeathRollFrame.title:SetText("DeathRoll!")

-- Create a custom close button
DeathRollFrame.closeButton = CreateFrame("Button", "DeathRollCloseButton", DeathRollFrame, "UIPanelCloseButton")
DeathRollFrame.closeButton:SetPoint("LEFT", DeathRollFrame.title, "RIGHT", 0, 0)
DeathRollFrame.closeButton:SetScript("OnClick", function() DeathRollFrame:HideUI() end)

-- Create an input box for the number
DeathRollFrame.inputBox = CreateFrame("EditBox", "DeathRollInputBox", DeathRollFrame, "InputBoxTemplate")
DeathRollFrame.inputBox:SetSize(WindowX * 0.9, WindowY/3)
DeathRollFrame.inputBox:SetPoint("CENTER", DeathRollFrame, "CENTER", 2.5, 0)
DeathRollFrame.inputBox:SetAutoFocus(false)
DeathRollFrame.inputBox:SetMaxLetters(6)
DeathRollFrame.inputBox:SetNumeric(true)

-- Create a roll button
DeathRollFrame.rollButton = CreateFrame("Button", "DeathRollButton", DeathRollFrame, "UIPanelButtonTemplate")
DeathRollFrame.rollButton:SetSize(WindowX, WindowY/3)
DeathRollFrame.rollButton:SetPoint("BOTTOM", DeathRollFrame, "BOTTOM", 0, 0)
DeathRollFrame.rollButton:SetText("Roll!")
DeathRollFrame.rollButton:SetScript("OnClick", function(self) DeathRollFrame:OnRollButtonClick() end)


-- Create a background frame
local BackgroundFrame = CreateFrame("Frame", "DeathRollBackground", DeathRollFrame)
BackgroundFrame:SetAllPoints()
BackgroundFrame:SetFrameLevel(DeathRollFrame:GetFrameLevel() - 1) -- Set it to a level below the main frame

-- Set a background texture for the background frame
BackgroundFrame.texture = BackgroundFrame:CreateTexture(nil, "BACKGROUND")
BackgroundFrame.texture:SetAllPoints()
BackgroundFrame.texture:SetColorTexture(0, 0, 0, 0.5) -- Set the texture to a color
-- BackgroundFrame.texture:SetTexture("Interface\\AddOns\\DeathRoll\\skull.tga")



-- Variables to store target information
local targetName = nil
local rollNumber = nil

-- Function to handle the Roll button click
function DeathRollFrame:OnRollButtonClick()
    rollNumber = tonumber(self.inputBox:GetText())

    if rollNumber then
        -- Store the target player when rolling
        local target = UnitName("target")
        if target then
            self.inputBox:ClearFocus()
            targetName = target
            RandomRoll(0, rollNumber)
            self.rollButton:SetText("Waiting for " .. targetName .. " to roll...")
            self.rollButton:Disable()
        else
            print("You need to target a player before rolling.")
        end
    else
        print("Invalid input. Please enter a valid number.")
    end
end

-- Event handler for CHAT_MSG_SYSTEM to capture the target's roll
function DeathRollFrame:OnChatMsgSystem(event, msg)
    local playerName, rollResult, targetRollString = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)")

    if playerName and targetName and targetRollString then
        -- Check if the player has already rolled
        if (playerName ~= UnitName("player")) or (UnitName("player") == UnitName("target")) then
            print(targetName .. " has a " .. CusRound((1 / (tonumber(rollResult) + 1)) * 100, 3) .. "% chance of losing on the next roll.")
            self.rollButton:SetText("Roll!")
            self.rollButton:Enable()
            self.inputBox:SetText(tostring(rollResult)) -- Set the next max roll
        else
            print("You have a " .. CusRound((1 / (tonumber(rollResult) + 1)) * 100, 3) .. "% chance of losing on the next roll.")
        end

        if tonumber(rollResult) == 0 then
            self.rollButton:Disable()
            if playerName ~= UnitName("player") then
                self.rollButton:SetText("You won!!!")
                DoEmote(GetRandomHappyEmote())
            else
                self.rollButton:SetText("You lost...")
                DoEmote(GetRandomSadEmote())
            end

            C_Timer.After(3, function() self:HideUI() end)
        end
    end
end

-- Function to show the DeathRoll UI
function DeathRollFrame:ShowUI()
    self:Show()
    self.inputBox:SetText("")
    self.inputBox:SetFocus()
end

-- Function to hide the DeathRoll UI
function DeathRollFrame:HideUI()
    self:ResetUI()
    self:Hide()
end

-- Function to reset variables and UI elements
function DeathRollFrame:ResetUI()
    print("DeathRoll game ended, resetting...")
    targetName = nil
    rollNumber = nil

    self.inputBox:SetText("")
    self.rollButton:SetText("Roll!")
    self.rollButton:Enable()
end

-- Register events
DeathRollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
DeathRollFrame:SetScript("OnEvent", DeathRollFrame.OnChatMsgSystem)

-- Slash command to open the DeathRoll UI
SLASH_DEATHROLL1 = "/deathroll"
SlashCmdList["DEATHROLL"] = function(msg)
    DeathRollFrame:ShowUI()
end
