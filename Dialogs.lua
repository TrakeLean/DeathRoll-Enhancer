-- Private confirmations: never enter Blizzard's protected StaticPopup/gamepad stack.
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
local AceGUI = LibStub("AceGUI-3.0")
local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

function DRE:CloseDialog(dialog, accepted, reason)
    if not dialog or self.activeDialog ~= dialog then return end
    self.activeDialog = nil -- retire ownership before hiding or invoking callbacks
    if self.dialogEventFrame then self.dialogEventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    if self.dialogWindow then self.dialogWindow:Hide() end
    local definition = dialog.definition
    if accepted then
        if definition.OnAccept then definition.OnAccept(dialog, dialog.data) end
    elseif definition.OnCancel then
        definition.OnCancel(dialog, dialog.data, reason or "clicked")
    end
end

function DRE:RenderDialog(dialog)
    if self.disabled or self.activeDialog ~= dialog then return end
    if not dialog.definition.whileDead and UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        self:CloseDialog(dialog, false, "override")
        return
    end
    if InCombat() then
        if not self.dialogEventFrame then
            self.dialogEventFrame = CreateFrame("Frame")
            self.dialogEventFrame:SetScript("OnEvent", function()
                if self.activeDialog then self:RenderDialog(self.activeDialog) end
            end)
        end
        self.dialogEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if self.dialogEventFrame then self.dialogEventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    if dialog.expires and time() >= dialog.expires then
        self:CloseDialog(dialog, false, "timeout")
        return
    end
    local window = self.dialogWindow
    if not window then
        -- Retain this one small window: its raw input hooks must never enter AceGUI's pool.
        window = AceGUI:Create("Frame")
        self.dialogWindow = window
        window:SetTitle("DeathRoll Enhancer")
        window:SetWidth(460)
        window:SetHeight(330)
        window:EnableResize(false)
        window:SetLayout("Flow")
        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        window:AddChild(label)
        local accept = AceGUI:Create("Button")
        accept:SetFullWidth(true)
        window:AddChild(accept)
        local cancel = AceGUI:Create("Button")
        cancel:SetFullWidth(true)
        window:AddChild(cancel)
        window.message, window.acceptButton, window.cancelButton = label, accept, cancel
    end
    window.message:SetText(dialog.textValue)
    window.acceptButton:SetText(dialog.definition.button1)
    window.cancelButton:SetText(dialog.definition.button2)
    window.acceptButton:SetCallback("OnClick", function() self:CloseDialog(dialog, true) end)
    window.cancelButton:SetCallback("OnClick", function() self:CloseDialog(dialog, false) end)
    window:SetCallback("OnClose", function() self:CloseDialog(dialog, false) end)
    local frame = window.frame
    if frame.EnableKeyboard and frame.SetPropagateKeyboardInput then
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(_, key)
            -- Propagation is protected in combat. Leave it untouched there.
            if InCombat() or self.activeDialog ~= dialog then return end
            frame:SetPropagateKeyboardInput(key ~= "ESCAPE")
            if key == "ESCAPE" then self:CloseDialog(dialog, false) end
        end)
    end
    if frame.EnableGamePadButton then
        frame:EnableGamePadButton(true)
        frame:SetScript("OnGamePadButtonDown", function(_, button)
            if button ~= "PAD2" or self.activeDialog ~= dialog then return true end
            self:CloseDialog(dialog, false)
            return false
        end)
    end
    window:Show()
    window:DoLayout()
end

function DRE:ShowDialog(key, text1, text2, data)
    if self.disabled then return end
    local definition = self.Dialogs[key]
    if not definition then return end
    self:CloseDialog(self.activeDialog, false, "override")
    local dialog = {
        definition = definition, data = data,
        textValue = string.format(definition.text, text1, text2),
    }
    self.activeDialog = dialog
    if definition.timeout and definition.timeout > 0 then
        dialog.expires = time() + definition.timeout
        C_Timer.After(definition.timeout, function() self:CloseDialog(dialog, false, "timeout") end)
    end
    self:RenderDialog(dialog)
    return dialog
end
