-- Private Forever widgets. AceGUI keeps these in their own pools.
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
if not DRE.devDuel then return end
local AceGUI = LibStub("AceGUI-3.0")
local white = "Interface\\Buttons\\WHITE8X8"
local goldTable = "Interface\\AddOns\\DeathRollEnhancer\\Media\\GoldTable"
local coinGlints = "Interface\\AddOns\\DeathRollEnhancer\\Media\\GoldTableGlints"
local coinLogo = "Interface\\AddOns\\DeathRollEnhancer\\Media\\Logo"
local gripSize = 24
local gold = {0.94, 0.73, 0.45}
local ink = {0.99, 0.94, 0.86}
local muted = {0.71, 0.67, 0.72}
local edge = {bgFile = white, edgeFile = white, edgeSize = 1}
local duelBannerHeight = 190
-- The two setup rows use 129 units in AceGUI Flow. Include rounding room
-- above the scrollbar threshold as well as the title, banner gap and footer.
local duelSetupSpace = 132 + 41 + 13 + 107
DRE.tableWidth, DRE.tableHeight = 568, 516
DRE.tableMinWidth, DRE.tableMinHeight = 500, 440

local function surface(frame, r, g, b)
    frame:SetBackdrop(edge)
    frame:SetBackdropColor(r, g, b, 0.99)
    frame:SetBackdropBorderColor(0.30, 0.25, 0.29, 1)
end

local function lettering(frame, size, color, display)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local font = display and (DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT) or STANDARD_TEXT_FONT
    if font then text:SetFont(font, size, "") end
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(color))
    return text
end

local function fill(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

local function rule(parent, point, y, r, g, b)
    local tex = fill(parent, "ARTWORK", r, g, b)
    tex:SetPoint(point .. "LEFT", 0, y)
    tex:SetPoint(point .. "RIGHT", 0, y)
    tex:SetHeight(1)
    return tex
end

local function buttonWidget()
    local root = CreateFrame("Frame", nil, UIParent)
    local control = CreateFrame("Button", nil, root, "BackdropTemplate")
    control:SetPoint("TOPLEFT", 2, -2)
    control:SetPoint("BOTTOMRIGHT", -2, 2)
    surface(control, 0.16, 0.13, 0.17)
    local finish = control:CreateTexture(nil, "ARTWORK")
    finish:SetPoint("TOPLEFT", 1, -2)
    finish:SetPoint("BOTTOMRIGHT", -1, 1)
    finish:SetColorTexture(1, 1, 1, 1)
    finish:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.30), CreateColor(1, 0.79, 0.71, 0.09))
    local text = lettering(control, 14, ink)
    text:SetPoint("LEFT", 6, 0)
    text:SetPoint("RIGHT", -6, 0)
    text:SetJustifyH("CENTER")
    local lip = rule(control, "TOP", -1, 0.42, 0.32, 0.36)
    local widget = {type = "DRETableButton", frame = root, control = control}
    local function paint()
        local over, primary = widget.over and not widget.disabled, widget.primary
        if primary then
            control:SetBackdropColor(over and 0.69 or 0.52, 0.13, 0.23, 1)
            control:SetBackdropBorderColor(0.77, 0.32, 0.38, 1)
            lip:SetColorTexture(0.96, 0.56, 0.48, 0.7)
        else
            control:SetBackdropColor(over and 0.25 or 0.15, over and 0.20 or 0.13, over and 0.24 or 0.18, 1)
            control:SetBackdropBorderColor(0.34, 0.28, 0.34, 1)
            lip:SetColorTexture(0.41, 0.35, 0.41, 0.55)
        end
        root:SetAlpha(widget.disabled and 0.48 or 1)
    end
    function widget:SetPrimary(value) self.primary = value; paint() end
    function widget:SetDisabled(value)
        self.disabled = value
        control:SetEnabled(not value)
        paint()
    end
    function widget:SetText(value) text:SetText(value) end
    function widget:GetText() return text:GetText() end
    function widget:OnAcquire()
        self.over, self.primary = false, false
        self:SetDisabled(false)
        self:SetWidth(150)
        self:SetHeight(34)
        self:SetText("")
    end
    control:SetScript("OnEnter", function() widget.over = true; paint(); widget:Fire("OnEnter") end)
    control:SetScript("OnLeave", function() widget.over = false; paint(); widget:Fire("OnLeave") end)
    control:SetScript("OnClick", function(_, ...)
        AceGUI:ClearFocus()
        widget:Fire("OnClick", ...)
    end)
    return AceGUI:RegisterAsWidget(widget)
end

local function fieldCaption(root)
    local label = lettering(root, 11, muted)
    label:SetPoint("TOPLEFT", 4, -2)
    return label
end

local function inputWidget()
    local root = CreateFrame("Frame", nil, UIParent)
    local label = fieldCaption(root)
    local edit = CreateFrame("EditBox", nil, root, "BackdropTemplate")
    edit:SetPoint("TOPLEFT", 2, -19)
    edit:SetPoint("BOTTOMRIGHT", -2, 6)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlight)
    edit:SetTextInsets(10, 8, 0, 0)
    surface(edit, 0.075, 0.068, 0.095)
    local widget = {type = "DRETableInput", frame = root, editbox = edit}
    function widget:SetLabel(value) label:SetText(value) end
    function widget:SetText(value) edit:SetText(value or ""); edit:SetCursorPosition(0) end
    function widget:GetText() return edit:GetText() end
    function widget:SetMaxLetters(value) edit:SetMaxLetters(value) end
    function widget:ClearFocus() edit:ClearFocus() end
    function widget:SetDisabled(value)
        edit:EnableMouse(not value)
        if value then edit:ClearFocus() end
        root:SetAlpha(value and 0.58 or 1)
    end
    function widget:DisableButton() end -- edits commit on Enter without a separate OK button
    function widget:OnAcquire()
        self:SetWidth(145)
        self:SetHeight(55)
        -- AceGUI Flow aligns adjacent buttons to the center of the visible edit box.
        self.alignoffset = 34
        self:SetDisabled(false)
        self:SetMaxLetters(0)
        self:SetText("")
        self:SetLabel("")
    end
    function widget:OnRelease() self:ClearFocus() end
    edit:SetScript("OnEditFocusGained", function()
        AceGUI:SetFocus(widget)
        edit:SetBackdropBorderColor(unpack(gold))
    end)
    edit:SetScript("OnEditFocusLost", function() edit:SetBackdropBorderColor(0.30, 0.25, 0.29, 1) end)
    edit:SetScript("OnTextChanged", function(_, user) if user then widget:Fire("OnTextChanged", edit:GetText()) end end)
    edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function() widget:Fire("OnEnterPressed", edit:GetText()); edit:ClearFocus() end)
    return AceGUI:RegisterAsWidget(widget)
end

local function dropdownWidget()
    local root = CreateFrame("Frame", nil, UIParent)
    local caption = fieldCaption(root)
    local face = CreateFrame("Button", nil, root, "BackdropTemplate")
    face:SetPoint("BOTTOMRIGHT", -2, 2)
    surface(face, 0.075, 0.068, 0.095)
    local text = lettering(face, 13, ink)
    text:SetPoint("LEFT", 10, 0)
    text:SetPoint("RIGHT", -28, 0)
    text:SetWordWrap(false)
    local arrow = {}
    for i = 1, 2 do
        local line = face:CreateLine(nil, "ARTWORK")
        line:SetThickness(1.5)
        line:SetStartPoint("RIGHT", face, i == 1 and -18 or -10, 2)
        line:SetEndPoint("RIGHT", face, -14, -2)
        arrow[i] = line
    end

    local widget = {type = "DRETableDropdown", frame = root, control = face}
    local function paint()
        local over = (widget.hover or widget.menu) and not widget.disabled
        for _, line in ipairs(arrow) do
            line:SetColorTexture(over and 1 or 0.73, over and 0.80 or 0.56, over and 0.47 or 0.32, 1)
        end
        face:SetBackdropBorderColor(over and 0.55 or 0.30, over and 0.43 or 0.25, over and 0.31 or 0.29, 1)
    end
    function widget:ClearFocus()
        local menu = self.menu
        if not menu then return end
        self.menu = nil
        face:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        menu:Close()
        menu.frame:SetBackdrop(self.menuBackdrop)
        menu.frame:SetBackdropColor(unpack(self.menuColor))
        menu.frame:SetBackdropBorderColor(unpack(self.menuBorder))
        menu.frame:SetScale(self.menuScale)
        AceGUI:Release(menu)
        paint()
    end
    function widget:SetList(list, order)
        if self.menu then AceGUI:ClearFocus() end
        self.list = list or {}
        self.order = order
        if not order then
            self.order = {}
            for key in pairs(self.list) do self.order[#self.order + 1] = key end
            table.sort(self.order, function(a, b)
                if tonumber(a) and tonumber(b) then return tonumber(a) < tonumber(b) end
                return tostring(a) < tostring(b)
            end)
        end
        self:SetValue(self.value)
    end
    function widget:SetValue(value)
        self.value = value
        text:SetText(self.list and self.list[value] or "")
    end
    function widget:GetValue() return self.value end
    function widget:SetLabel(value)
        local labeled = value and value ~= ""
        caption:SetText(value or "")
        face:SetPoint("TOPLEFT", 2, labeled and -19 or -2)
        self:SetHeight(labeled and 52 or 30)
        self.alignoffset = labeled and 34 or 15
    end
    function widget:SetDisabled(value)
        if value and self.menu then AceGUI:ClearFocus() end
        self.disabled = value
        face:SetEnabled(not value)
        root:SetAlpha(value and 0.48 or 1)
        paint()
    end
    function widget:OnAcquire()
        self.hover = false
        self:SetWidth(200)
        self:SetLabel(nil)
        self:SetDisabled(false)
    end
    function widget:OnRelease()
        if self.menu then AceGUI:ClearFocus() end
        self.list, self.order = nil, nil
        self:SetValue(nil)
    end
    root:SetScript("OnHide", function()
        widget.hover = false
        if widget.menu then AceGUI:ClearFocus() end
    end)
    face:SetScript("OnEvent", function()
        if widget.menu and not face:IsMouseOver() and not widget.menu.frame:IsMouseOver() then AceGUI:ClearFocus() end
    end)
    face:SetScript("OnEnter", function() widget.hover = true; paint(); widget:Fire("OnEnter") end)
    face:SetScript("OnLeave", function() widget.hover = false; paint(); widget:Fire("OnLeave") end)
    face:SetScript("OnClick", function()
        if widget.menu then AceGUI:ClearFocus(); return end
        if widget.disabled or not widget.order or #widget.order == 0 then return end
        AceGUI:SetFocus(widget)
        local menu = AceGUI:Create("Dropdown-Pullout")
        widget.menu = menu
        -- The menu belongs to AceGUI's shared pool. Restore its skin and scale on close.
        widget.menuBackdrop = menu.frame:GetBackdrop()
        widget.menuColor = {menu.frame:GetBackdropColor()}
        widget.menuBorder = {menu.frame:GetBackdropBorderColor()}
        widget.menuScale = menu.frame:GetScale()
        surface(menu.frame, 0.09, 0.077, 0.105)
        menu.frame:SetScale(face:GetEffectiveScale() / UIParent:GetEffectiveScale())
        menu:SetWidth(face:GetWidth())
        for _, key in ipairs(widget.order) do
            local item = AceGUI:Create("Dropdown-Item-Toggle")
            item:SetText(widget.list[key])
            item:SetValue(key == widget.value)
            item:SetCallback("OnValueChanged", function()
                local changed = widget.value ~= key
                widget:SetValue(key)
                AceGUI:ClearFocus()
                if changed then widget:Fire("OnValueChanged", key) end
            end)
            menu:AddItem(item)
        end
        menu:Open("TOPLEFT", face, "BOTTOMLEFT", 0, -2)
        face:RegisterEvent("GLOBAL_MOUSE_DOWN")
        paint()
    end)
    return AceGUI:RegisterAsWidget(widget)
end

-- Align the caption and face with the neighboring table input.
local function dropdownField()
    local frame = CreateFrame("Frame", nil, UIParent)
    local caption = fieldCaption(frame)
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 2, -22)
    content:SetPoint("BOTTOMRIGHT", -2, 7)
    local field = {type = "DRETableDropdownField", frame = frame, content = content}
    function field:SetLabel(value) caption:SetText(value) end
    function field:OnAcquire()
        self:SetHeight(55)
        self.alignoffset = 34
    end
    return AceGUI:RegisterAsContainer(field)
end

function DRE:CreateTableDropdownField(parent, caption, width)
    local field = AceGUI:Create("DRETableDropdownField")
    field:SetLayout("Fill")
    field:SetRelativeWidth(width)
    field:SetLabel(caption)
    local dropdown = self:CreateWindowWidget("Dropdown")
    field:AddChild(dropdown)
    parent:AddChild(field)
    return dropdown
end

local createInviteBanner
local inviteContentTop, inviteBottomPadding = 151, 9
local function windowWidget()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    surface(frame, 0.09, 0.077, 0.105)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(40)
    fill(bar, "BACKGROUND", 0.11, 0.09, 0.12):SetAllPoints()
    rule(bar, "BOTTOM", 0, 0.31, 0.23, 0.25)
    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(coinLogo)
    logo:SetSize(30, 30)
    logo:SetPoint("LEFT", 10, 0)
    local title = lettering(bar, 15, ink)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetWordWrap(false)
    local version = lettering(bar, 10, gold)
    version:SetPoint("RIGHT", -51, 0)
    title:SetPoint("RIGHT", version, "LEFT", -10, 0)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(34, 32)
    close:SetPoint("RIGHT", -3, 0)
    local cross = lettering(close, 22, muted)
    cross:SetPoint("CENTER")
    cross:SetText("×")
    close:SetScript("OnEnter", function() cross:SetTextColor(unpack(ink)) end)
    close:SetScript("OnLeave", function() cross:SetTextColor(unpack(muted)) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(gripSize, gripSize)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    local grabber = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
    grip:SetNormalTexture(grabber .. "Up")
    grip:SetHighlightTexture(grabber .. "Highlight")
    grip:SetPushedTexture(grabber .. "Down")
    local content = CreateFrame("Frame", nil, frame)
    local widget = {type = "DRETableWindow", frame = frame, content = content}
    function widget:SetInviteArt(challenge)
        if challenge then
            self.inviteBanner = self.inviteBanner or createInviteBanner(frame)
            self.inviteBanner:Present(challenge)
            self:SetInsets(inviteContentTop, inviteBottomPadding)
        elseif self.inviteBanner then
            self.inviteBanner:Hide()
        end
    end
    function widget:LayoutFinished(_, height)
        if self.duelInvite and height then
            local desired = math.ceil(inviteContentTop + height + inviteBottomPadding)
            if self:GetHeight() ~= desired then self:SetHeight(desired) end
        end
    end
    local function save()
        frame:StopMovingOrSizing()
        if widget.status then
            widget.status.left, widget.status.top = frame:GetLeft(), frame:GetTop()
            widget.status.width, widget.status.height = frame:GetWidth(), frame:GetHeight()
        end
    end
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", save)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop", save)
    frame:SetScript("OnHide", function() widget:Fire("OnClose") end)
    function widget:SetInsets(top, bottom)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", 18, -top)
        content:SetPoint("BOTTOMRIGHT", -18, bottom)
    end
    function widget:EnableResize(value) grip:SetShown(value) end
    function widget:SetTitle(value) title:SetText(value) end
    function widget:SetStatusText(value) version:SetText(value) end
    function widget:Show() frame:Show() end
    function widget:Hide() frame:Hide() end
    function widget:GetWidth() return frame:GetWidth() end
    function widget:GetHeight() return frame:GetHeight() end
    function widget:SetStatusTable(status)
        self.status = status
        frame:ClearAllPoints()
        if status.left and status.top then frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", status.left, status.top)
        else frame:SetPoint("CENTER") end
    end
    function widget:OnAcquire()
        self.status = nil
        frame:SetParent(UIParent)
        frame:SetFrameLevel(DRE.UI.mainWindow and DRE.UI.mainWindow.frame:GetFrameLevel() + 40 or 100)
        grip:SetFrameLevel(frame:GetFrameLevel() + 3)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
        frame:SetResizeBounds(350, 200)
        self:SetWidth(460)
        self:SetHeight(330)
        self:SetInsets(52, 16)
        self:SetInviteArt(false)
        self:SetTitle("")
        self:SetStatusText("")
        self:EnableResize(true)
        self:Show()
    end
    return AceGUI:RegisterAsContainer(widget)
end

local function metricWidget()
    local frame = CreateFrame("Frame", nil, UIParent)
    local panel = fill(frame, "BACKGROUND", 0.135, 0.112, 0.147)
    panel:SetPoint("TOPLEFT", 2, -2)
    panel:SetPoint("BOTTOMRIGHT", -3, 4)
    local stripe = fill(frame, "ARTWORK", 0.65, 0.40, 0.32)
    stripe:SetWidth(2)
    stripe:SetPoint("TOPLEFT", panel)
    stripe:SetPoint("BOTTOMLEFT", panel)
    local caption = lettering(frame, 10, muted)
    caption:SetPoint("TOPLEFT", 14, -10)
    local value = lettering(frame, 19, ink, true)
    value:SetPoint("TOPLEFT", 13, -25)
    value:SetPoint("BOTTOMRIGHT", -10, 8)
    local widget = {type = "DRETableMetric", frame = frame}
    function widget:SetLabel(text) caption:SetText(text) end
    function widget:SetText(text) value:SetText(text) end
    function widget:GetText() return value:GetText() end
    function widget:OnAcquire()
        self:SetHeight(64)
        self:SetWidth(230)
        self:SetText("")
        self:SetLabel("")
    end
    return AceGUI:RegisterAsWidget(widget)
end

local function sectionWidget()
    local frame = CreateFrame("Frame", nil, UIParent)
    local content = CreateFrame("Frame", nil, frame)
    local title = lettering(frame, 13, gold)
    title:SetPoint("TOPLEFT", 2, -8)
    local divider = rule(frame, "TOP", 0, 0.27, 0.22, 0.28)
    local widget = {type = "DRETableSection", frame = frame, content = content}
    function widget:SetTitle(value)
        title:SetText(value)
        self.inset = value and value ~= "" and 30 or 6
        divider:SetShown(self.inset == 30)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", 2, -self.inset)
        content:SetPoint("BOTTOMRIGHT", -2, 6)
    end
    function widget:LayoutFinished(_, height)
        if not self.noAutoHeight then self:SetHeight(self.inset + (height or 0) + 6) end
    end
    function widget:OnAcquire()
        self:SetTitle("")
        self:SetWidth(250)
        self:SetHeight(72)
    end
    return AceGUI:RegisterAsContainer(widget)
end

local function switchWidget()
    local frame = CreateFrame("Button", nil, UIParent)
    local track = fill(frame, "ARTWORK", 0.24, 0.21, 0.26)
    track:SetPoint("RIGHT", -3, 0)
    track:SetSize(30, 13)
    local knob = fill(frame, "OVERLAY", unpack(ink))
    knob:SetSize(9, 9)
    local label = lettering(frame, 13, ink)
    label:SetPoint("LEFT", 2, 0)
    label:SetPoint("RIGHT", track, "LEFT", -8, 0)
    local widget = {type = "DRETableSwitch", frame = frame}
    function widget:SetLabel(value) label:SetText(value) end
    function widget:SetValue(value)
        self.value = value == true
        knob:ClearAllPoints()
        knob:SetPoint(self.value and "RIGHT" or "LEFT", track, self.value and "RIGHT" or "LEFT", self.value and -2 or 2, 0)
        if self.value then track:SetColorTexture(0.54, 0.19, 0.29)
        else track:SetColorTexture(0.24, 0.21, 0.26) end
    end
    function widget:GetValue() return self.value end
    function widget:OnAcquire()
        self:SetLabel("")
        self:SetHeight(29)
        self:SetWidth(200)
        self:SetValue(false)
    end
    frame:SetScript("OnClick", function()
        widget:SetValue(not widget.value)
        widget:Fire("OnValueChanged", widget.value)
    end)
    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType("DRETableWindow", windowWidget, 1)
AceGUI:RegisterWidgetType("DRETableButton", buttonWidget, 1)
AceGUI:RegisterWidgetType("DRETableInput", inputWidget, 1)
AceGUI:RegisterWidgetType("DRETableDropdown", dropdownWidget, 1)
AceGUI:RegisterWidgetType("DRETableDropdownField", dropdownField, 1)
AceGUI:RegisterWidgetType("DRETableSection", sectionWidget, 1)
AceGUI:RegisterWidgetType("DRETableSwitch", switchWidget, 1)
AceGUI:RegisterWidgetType("DRETableMetric", metricWidget, 1)

local function matchesUnit(unit, name)
    local player = UnitIsPlayer(unit)
    return DRE:IsAccessibleValue(player) and player and DRE:IsSamePlayer(DRE:GetUnitPlayerName(unit), name)
end

local function rollBadge(slot, left)
    local badge = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    badge:SetFrameLevel(slot:GetFrameLevel() + 3)
    badge:SetPoint(left and "RIGHT" or "LEFT", left and -3 or 3, -34)
    badge:SetHeight(34)
    surface(badge, 0.12, 0.085, 0.10)
    badge:SetBackdropBorderColor(0.65, 0.45, 0.26, 1)

    local die = badge:CreateTexture(nil, "ARTWORK")
    die:SetPoint("CENTER")
    die:SetSize(27, 27)
    die:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
    local spin = die:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local rotation = spin:CreateAnimation("Rotation")
    rotation:SetOrigin("CENTER", 0, 0)
    rotation:SetDegrees(-360)
    rotation:SetDuration(1.4)
    local number = lettering(badge, 17, ink)
    number:SetPoint("CENTER")
    badge.number = number
    badge:SetScript("OnHide", function() spin:Stop() end)
    badge:SetScript("OnShow", function() if badge.rolling then spin:Play() end end)
    function badge:SetRoll(rolling, value)
        if self.rolling == rolling and self.value == value then return end
        self.rolling, self.value = rolling, value
        if not rolling and not value then self:Hide(); return end
        die:SetShown(rolling)
        number:SetShown(not rolling)
        if rolling then
            self:SetWidth(36)
        else
            spin:Stop()
            number:SetText(tostring(value))
            number:SetTextColor(unpack(value == 1 and {1, 0.68, 0.62} or gold))
            self:SetWidth(math.max(36, number:GetStringWidth() + 16))
        end
        self:Show()
        if rolling and self:IsVisible() and not spin:IsPlaying() then spin:Play() end
    end
    badge:Hide()
    return badge
end

function DRE:CreateTableScoreBadge(parent, compact)
    local score = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    score:SetSize(compact and 44 or 112, compact and 17 or 25)
    score:SetFrameLevel(parent:GetFrameLevel() + 4)
    surface(score, 0.10, 0.07, 0.09)
    score.caption = lettering(score, compact and 12 or 16, ink)
    score.caption:SetPoint("LEFT", compact and 32 or 47, 0)
    score.pips = {}
    local icon = compact and 13 or 17
    for i = 1, 2 do
        local pip = score:CreateTexture(nil, "OVERLAY")
        pip:SetSize(icon, icon)
        pip:SetPoint("LEFT", (compact and 3 or 6) + (i - 1) * (icon + 2), 0)
        score.pips[i] = pip
    end
    function score:Present(mode, value, leading)
        self:SetShown(value ~= nil)
        if value == nil then return end
        local lives = mode == "twoLives"
        local unit = lives and (value == 1 and "life" or "lives") or (value == 1 and "point" or "points")
        self.caption:SetText(compact and tostring(value) or (value .. " " .. unit))
        if leading then
            self:SetBackdropBorderColor(0.98, 0.73, 0.37, 1)
        else
            self:SetBackdropBorderColor(0.39, 0.31, 0.32, 1)
        end
        local texture = lives and "Interface\\AddOns\\DeathRollEnhancer\\Media\\DuelHeart" or "Interface\\MoneyFrame\\UI-GoldIcon"
        for i, pip in ipairs(self.pips) do
            pip:SetTexture(texture)
            pip:SetDesaturated(i > value)
            pip:SetAlpha(i > value and 0.30 or 1)
        end
    end
    score:Hide()
    return score
end

local function fighterSlot(parent, side)
    local slot = CreateFrame("Frame", nil, parent)
    local left = side == "LEFT"
    slot:SetPoint("TOP" .. side, left and 4 or -4, -4)
    slot:SetPoint("BOTTOM" .. side, left and 4 or -4, 4)
    slot:SetWidth(150)
    -- The glints map contains the lower half of the table. Anchor to the
    -- full banner so the highlights stay on the coins as the model slots resize.
    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("BOTTOM" .. side, parent, "BOTTOM" .. side)
    glow:SetPoint(left and "TOPRIGHT" or "TOPLEFT", parent, "CENTER")
    glow:SetTexture(coinGlints)
    glow:SetTexCoord(left and 0 or 0.5, left and 0.5 or 1, 0, 1)
    glow:SetBlendMode("ADD")
    glow:Hide()
    slot.turnGlow = glow
    slot.nameLabel = lettering(slot, 13, ink)
    slot.nameLabel:SetPoint("TOPLEFT", 2, -2)
    slot.nameLabel:SetPoint("TOPRIGHT", -2, -2)
    slot.nameLabel:SetHeight(30)
    slot.nameLabel:SetJustifyH("CENTER")
    slot.nameLabel:SetJustifyV("MIDDLE")
    slot.nameLabel:SetShadowOffset(1, -1)
    local portraitArea = CreateFrame("Frame", nil, slot)
    portraitArea:SetPoint("TOP", slot.nameLabel, "BOTTOM", 0, -1)
    portraitArea:SetPoint("BOTTOMLEFT")
    portraitArea:SetPoint("BOTTOMRIGHT")
    slot.portrait = slot:CreateTexture(nil, "ARTWORK")
    slot.portrait:SetPoint("CENTER", portraitArea)
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, slot)
    if ok and model then
        slot.model = model
        model:SetAllPoints(portraitArea)
        model:EnableMouse(false)
        model:Hide()
    end
    slot.facing = left and 1.2 or -1.2
    slot.badge = rollBadge(slot, left)
    local score = DRE:CreateTableScoreBadge(slot)
    score:SetPoint("TOP", slot.nameLabel, "BOTTOM", 0, -1)
    score:SetScript("OnShow", function() portraitArea:SetPoint("TOP", score, "BOTTOM", 0, -1) end)
    score:SetScript("OnHide", function() portraitArea:SetPoint("TOP", slot.nameLabel, "BOTTOM", 0, -1) end)
    slot.score = score
    return slot
end

-- PlayerModel takes AnimationData sequences, distinct from chat emote IDs.
local emoteSequences = {
    CHEER = 68, LAUGH = 70, SALUTE = 113, DANCE = 69, VICTORY = 68,
    CRY = 77, SIGH = 77, SURRENDER = 79, LAY = 71, CONGRATULATE = 64,
}

local function applyGesture(slot)
    local motion = slot.motion
    if not motion or motion.played or not slot.ready or not matchesUnit(slot.unit, slot.name) then return end
    -- Some forms lack a sequence. A cosmetic API failure must never interrupt a roll.
    pcall(function()
        local model = slot.model
        local sequence = model:HasAnimation(motion.sequence) and motion.sequence or motion.fallback
        if model:HasAnimation(sequence) then
            model:SetAnimation(sequence)
            motion.played = true
        end
    end)
end

local function stopGesture(slot)
    local motion = slot.motion
    slot.motion = nil
    if motion and motion.played then pcall(slot.model.SetAnimation, slot.model, 0) end
end

local function playGesture(slot, sequence, fallback, duration)
    if not slot.binding then return end
    stopGesture(slot)
    local motion = {sequence = sequence, fallback = fallback}
    slot.motion = motion
    applyGesture(slot)
    C_Timer.After(duration, function()
        if slot.motion == motion then stopGesture(slot) end
    end)
end

local function clearFighter(slot)
    slot.unit, slot.name = nil, nil
    slot.binding, slot.motion, slot.ready = nil, nil, nil
    slot.boundNativeForm = nil
    slot.standIn = nil
    if slot.model then
        slot.model:SetScript("OnModelLoaded", nil)
        slot.model:Hide()
        slot.model:ClearModel()
    end
    slot.portrait:Hide()
end

-- Local character art for names the client has never seen. The same name keeps
-- its avatar across tabs and shuffles until WoW can supply the actual player.
local standIns = {
    {3524, "Dwarf_Male"}, {2141, "Tauren_Male"}, {5566, "Human_Male"},
    {4259, "Orc_Male"}, {2306, "Nightelf_Female"}, {10357, "Troll_Male"},
    {3167, "Human_Male"}, {7006, "Gnome_Male"}, {8769, "Human_Female"}, {3597, "Dwarf_Male"},
}
function DRE:SetStandInPortrait(portrait, name)
    local key, hash = name:lower(), 0
    for i = 1, #key do hash = (hash * 37 + key:byte(i)) % 65521 end
    local avatar = standIns[hash % #standIns + 1]
    portrait:SetTexture("Interface\\Icons\\Achievement_Character_" .. avatar[2])
    if SetPortraitTextureFromCreatureDisplayID then
        pcall(SetPortraitTextureFromCreatureDisplayID, portrait, avatar[1])
    end
    return avatar[1]
end

local function showFighter(slot, name, unit, refreshUnit, unitMatchesName)
    if slot.name == name and slot.unit == unit and not (unit and refreshUnit == unit) then return end
    clearFighter(slot)
    slot.name, slot.unit = name, unit
    if slot.nameLabel then slot.nameLabel:SetText(slot.displayName or name) end
    if not name then return end
    local portrait = slot.portrait
    portrait:SetAlpha(1)
    portrait:Show()
    slot.standIn = not unit
    local displayID
    if not unit or not SetPortraitTexture or not pcall(SetPortraitTexture, portrait, unit) then
        displayID = DRE:SetStandInPortrait(portrait, name)
    end
    local model = slot.model
    if not model or slot.portraitOnly or (not unit and not model.SetDisplayInfo) then return end

    -- SetUnit can fail or finish loading later. Keep the portrait until this binding is ready.
    local loaded, accepted = false, false
    local function reveal()
        if not accepted or slot.binding ~= reveal then return end
        if unit and not (unitMatchesName or matchesUnit)(unit, name) then return end
        if slot.applyCamera then
            slot:applyCamera()
        else
            model:SetPortraitZoom(slot.zoom or 0.22)
            model:SetRotation(slot.facing, false)
        end
        model:SetAlpha(1)
        portrait:Hide()
        local firstLoad = not slot.ready
        slot.ready = true
        if firstLoad and slot.onReady then slot:onReady() else applyGesture(slot) end
    end
    slot.binding = reveal
    model:SetAlpha(0)
    model:Show()
    model:SetScript("OnModelLoaded", function()
        loaded = true
        reveal()
    end)
    slot.boundNativeForm = slot.useNativeForm
    if unit then
        local ok, success = pcall(model.SetUnit, model, unit, false, slot.useNativeForm)
        accepted = ok and DRE:IsAccessibleValue(success) and success == true
    else
        accepted = pcall(model.SetDisplayInfo, model, displayID)
    end
    if not accepted then model:Hide()
    elseif loaded then reveal() end
end

createInviteBanner = function(frame)
    local banner = CreateFrame("Frame", nil, frame)
    banner:SetPoint("TOPLEFT", 1, -41)
    banner:SetPoint("TOPRIGHT", -1, -41)
    banner:SetHeight(102)
    local art = banner:CreateTexture(nil, "BACKGROUND")
    art:SetAllPoints()
    art:SetTexture(goldTable)
    art:SetTexCoord(0, 1, 0.525, 1)
    rule(banner, "BOTTOM", 0, 0.61, 0.45, 0.25)
    banner.portrait = banner:CreateTexture(nil, "ARTWORK")
    banner.portrait:SetPoint("CENTER")
    banner.portrait:SetSize(64, 64)
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, banner)
    if ok and model then
        banner.model = model
        model:SetPoint("TOP", 0, -1)
        model:SetPoint("BOTTOM", 0, 1)
        model:SetWidth(158)
        model:EnableMouse(false)
        model:Hide()
    end
    banner.zoom, banner.facing = 0.42, 0.15
    function banner:onReady()
        playGesture(self, 82, 68, 3) -- Flex, or cheer for forms without a flex sequence.
    end
    local function refresh(unit)
        local name = banner.challenger
        if not name then return end
        local token = banner.unit
        if not token or not matchesUnit(token, name) then token = DRE:FindVisiblePlayerUnit(name) end
        showFighter(banner, name, token, unit)
    end
    banner:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE" then
            if DRE:IsAccessibleValue(unit) and unit == banner.unit then refresh(unit) end
        elseif event == "UNIT_NAME_UPDATE" and DRE:IsAccessibleValue(unit) and unit == banner.unit then
            refresh(unit)
        elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_NAME_UPDATE" then
            if not banner.unit and DRE:IsAccessibleValue(unit) and matchesUnit(unit, banner.challenger) then
                showFighter(banner, banner.challenger, unit)
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if DRE:IsAccessibleValue(unit) and unit == banner.unit then
                showFighter(banner, banner.challenger, DRE:FindVisiblePlayerUnit(banner.challenger, unit))
            end
        else
            refresh()
        end
    end)
    function banner:Present(challenge)
        self.challenger = challenge.preview and DRE:GetUnitPlayerName("player") or challenge.sender
        for _, event in ipairs({"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE",
            "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_NAME_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE"}) do
            self:RegisterEvent(event)
        end
        self:Show()
        refresh()
    end
    banner:SetScript("OnHide", function()
        banner:UnregisterAllEvents()
        banner.challenger = nil
        clearFighter(banner)
    end)
    return banner
end

function DRE.BindGroupSeat(seat, name, unit, refreshUnit)
    local appearance = DRE:GetGroupAppearance()
    local portraitOnly = appearance == "flat"
    seat.useNativeForm = appearance == "portraits"
    -- A close-up binds the racial model even in Cat Form or Ghost Wolf.
    -- Switching to a full model needs a new binding to the visible form.
    local matchingModel = seat.boundNativeForm == seat.useNativeForm
    if seat.appearance ~= appearance then
        seat.appearance, seat.portraitOnly = appearance, portraitOnly
        if seat.standIn then seat.name = nil end
        if name and name == seat.name then
            seat.binding = nil
            local showModel = not portraitOnly and seat.ready and matchingModel
            if seat.model then
                seat.model:SetScript("OnModelLoaded", nil)
                seat.model:SetShown(showModel == true)
            end
            seat.portrait:SetShown(not showModel)
            if not portraitOnly and not showModel then refreshUnit = unit end
        end
    end
    if unit and not portraitOnly and not matchingModel then refreshUnit = unit end
    if name and name == seat.name and (not unit or (not seat.standIn and seat.ready and not refreshUnit)) then
        -- A selected character can move between target, focus and roster tokens.
        -- Keep its loaded appearance; a pending request keeps its captured portrait.
        if seat.unit ~= unit then
            seat.unit, seat.binding = unit, nil
            if seat.model then
                seat.model:SetScript("OnModelLoaded", nil)
                if not seat.ready then
                    seat.model:Hide()
                    seat.model:ClearModel()
                end
            end
        end
        return
    end
    showFighter(seat, name, unit, refreshUnit, DRE.GroupUnitMatches)
end

local function duelReadoutScale(width, height)
    return math.max(1, math.min(1.5, width/640, height/300))
end

local function addMatchup(hero, header, art)
    local fighters = CreateFrame("Frame", nil, hero)
    fighters:SetAllPoints()
    fighters:Hide()
    local player = fighterSlot(fighters, "LEFT")
    local opponent = fighterSlot(fighters, "RIGHT")
    local centerWidth
    local function sizeFighters(_, width, height)
        if width <= 0 or height <= 0 then return end
        -- Keep the sides proportional without crowding the turn and odds in the middle.
        local wing = math.max(1, math.min(width * 0.31, (width - 172)/2, height))
        centerWidth = width - 2*wing - 16
        local portrait = math.max(1, math.min(wing, height - 41) * 0.68)
        player:SetWidth(wing)
        opponent:SetWidth(wing)
        player.portrait:SetSize(portrait, portrait)
        opponent.portrait:SetSize(portrait, portrait)
        local scale = duelReadoutScale(width, height)
        player.badge:SetScale(scale)
        opponent.badge:SetScale(scale)
        player.score:SetScale(scale)
        opponent.score:SetScale(scale)
    end
    fighters:SetScript("OnSizeChanged", sizeFighters)
    function header:StopGestures()
        self.pendingReaction, self.playingReaction = nil, nil
        stopGesture(player)
        stopGesture(opponent)
    end
    local odds = CreateFrame("Frame", nil, hero)
    odds:SetSize(1, 1)
    odds:EnableMouse(false)
    odds:SetPoint("BOTTOM", header.stage, "TOP", 0, 3)
    local oddsText = lettering(odds, 12, muted)
    oddsText:SetPoint("BOTTOM")
    odds:Hide()
    local flight = CreateFrame("Frame", nil, fighters)
    flight:SetFrameLevel(math.max(player.badge:GetFrameLevel(), opponent.badge:GetFrameLevel()) + 1)
    flight:SetSize(1, 1)
    flight:EnableMouse(false)
    local numeral = lettering(flight, 17, gold)
    numeral:SetPoint("CENTER")
    numeral:SetShadowOffset(1, -1)
    flight:Hide()
    function header:SetNextRollOdds(maximum)
        -- The history refresh can arrive before the game advances to the next range.
        local game = DRE.gameState
        local mode = game and game.mode
        maximum = mode == "twoLives" and game.currentRoll or flight.roll or maximum
        if self.phase ~= "active" or mode == "highRoller" or not maximum or maximum <= 1 then
            odds:Hide()
            return
        end
        if mode == "cursed7" then
            oddsText:SetText(string.format("%.3g%% to lose", (maximum >= 7 and 200 or 100) / maximum))
        else
            oddsText:SetText(DRE:FormatRollOneChance(maximum) .. " to roll a 1")
        end
        odds:Show()
    end
    local function finishFlight()
        if not flight.badge then return end
        flight.badge.number:SetAlpha(1)
        flight.badge, flight.roll = nil, nil
        flight:SetScript("OnUpdate", nil)
        flight:Hide()
    end
    local function moveRoll(_, elapsed)
        flight.elapsed = flight.elapsed + elapsed
        local t = math.max(0, (flight.elapsed - 1) / 0.3)
        if t >= 1 then finishFlight(); return end
        t = t*t*(3 - 2*t)
        local badge = flight.badge
        local cx, cy = hero:GetCenter()
        local bx, by = badge:GetCenter()
        if not cx or not bx then return end
        local height = hero:GetHeight()
        local startScale = 1.2 * math.min(4.5, math.max(2, height/105))
        if centerWidth and centerWidth > 0 then
            startScale = math.min(startScale, centerWidth / flight.textWidth)
        end
        -- The live roll has its own space below the turn label. Leave room for
        -- the larger outcome heading when the final 1 lands.
        local originOffset = header.phase == "result" and -height*0.08 or height/2 - math.max(74, height*0.35)
        local endScale = badge:GetScale()
        local scale = startScale + (endScale - startScale)*t
        flight:SetScale(scale)
        flight:ClearAllPoints()
        flight:SetPoint("CENTER", hero, "CENTER", (bx*endScale - cx)*t/scale,
            (originOffset*(1-t) + (by*endScale-cy)*t)/scale)
        flight:SetAlpha(1)
    end
    function header:PlayThrow(isPlayer, target, value)
        if fighters:IsVisible() and DRE:IsSamePlayer(self.opponent, target) then
            local slot = isPlayer and player or opponent
            playGesture(slot, 107, 63, 1.0)
            finishFlight()
            flight.badge, flight.elapsed, flight.roll = slot.badge, 0, value
            self:SetNextRollOdds(value)
            slot.badge.number:SetAlpha(0)
            numeral:SetText(tostring(value))
            flight:SetAlpha(0)
            flight:Show()
            flight.textWidth = math.max(1, numeral:GetStringWidth())
            flight:SetScript("OnUpdate", moveRoll)
            moveRoll(flight, 0)
        end
    end
    function header:SyncOpponentReaction(result)
        local round = result.emoteRound
        if self.playingReaction ~= result or not round or not fighters:IsVisible() then return false end
        local token = round.received
        if not DRE:IsResultEmote(result.result == "Lost", token) then return false end
        -- SIGH is text-only in the world. An exact mirror leaves the model standing.
        if token == "SIGH" then stopGesture(opponent)
        else playGesture(opponent, emoteSequences[token], emoteSequences[token], 3.0) end
        return true
    end
    function header:PlayOutcome(result, ownEmote, otherEmote)
        if not fighters:IsVisible() or not DRE:IsSamePlayer(self.opponent, result.playerName) then return end
        self.pendingReaction = result
        -- Let the losing character release the die before either character reacts.
        C_Timer.After(0.75, function()
            if self.pendingReaction ~= result or DRE.UI.duelResult ~= result or not fighters:IsVisible() then return end
            self.pendingReaction = nil
            self.playingReaction = result
            local won = result.result == "Won"
            playGesture(player, emoteSequences[ownEmote], won and 68 or 77, 3.0)
            if not self:SyncOpponentReaction(result) then
                playGesture(opponent, emoteSequences[otherEmote], won and 77 or 68, 3.0)
            end
        end)
    end
    local litTurn, mix, startMix, endMix, fadeTime
    local function setCoinLight(left)
        mix = left
        local right = 1 - left
        player.turnGlow:SetVertexColor(left, left, left)
        opponent.turnGlow:SetVertexColor(right, right, right)
        player.turnGlow:SetShown(litTurn ~= nil and left > 0)
        opponent.turnGlow:SetShown(litTurn ~= nil and right > 0)
    end
    local function fadeCoins(_, elapsed)
        fadeTime = fadeTime + elapsed
        local t = math.min(1, fadeTime / 0.55)
        local eased = t * t * (3 - 2 * t)
        if t == 1 then
            fighters:SetScript("OnUpdate", nil)
            setCoinLight(endMix)
        else
            setCoinLight(startMix + (endMix - startMix) * eased)
        end
    end
    function header:SetRolls(turn, playerRoll, opponentRoll, keepFaces)
        if turn ~= litTurn then
            local crossfade = litTurn and turn and fighters:IsVisible()
            litTurn = turn
            endMix = turn == "player" and 1 or 0
            if crossfade then
                startMix, fadeTime = mix, 0
                fighters:SetScript("OnUpdate", fadeCoins)
            else
                fighters:SetScript("OnUpdate", nil)
                setCoinLight(endMix)
            end
        end
        player.badge:SetRoll(turn == "player" and not (keepFaces and playerRoll), playerRoll)
        opponent.badge:SetRoll(turn == "opponent" and not (keepFaces and opponentRoll), opponentRoll)
    end
    function header:SetDuelScore(mode, values)
        local mine, theirs = values and values.player, values and values.opponent
        player.score:Present(mode, mine, mine and theirs and mine > theirs)
        opponent.score:Present(mode, theirs, mine and theirs and theirs > mine)
    end
    local function refresh(refreshUnit, excludedUnit)
        if not header.opponent or not fighters:IsVisible() then return end
        local myName = DRE:GetUnitPlayerName("player")
        showFighter(player, myName or "You", myName and "player", refreshUnit)
        local unit
        if DRE:IsSamePlayer(myName, header.opponent) then unit = "player"
        elseif matchesUnit("target", header.opponent) then unit = "target"
        elseif matchesUnit("focus", header.opponent) then unit = "focus"
        elseif opponent.unit and opponent.unit ~= excludedUnit and matchesUnit(opponent.unit, header.opponent) then unit = opponent.unit
        else unit = DRE:FindVisiblePlayerUnit(header.opponent, excludedUnit) end
        showFighter(opponent, header.opponent, unit, refreshUnit)
    end
    fighters:SetScript("OnShow", function(self)
        sizeFighters(self, self:GetWidth(), self:GetHeight())
        refresh()
    end)
    fighters:SetScript("OnHide", function()
        finishFlight()
        if litTurn then
            fighters:SetScript("OnUpdate", nil)
            setCoinLight(endMix)
        end
        header.pendingReaction, header.playingReaction = nil, nil
        clearFighter(player)
        clearFighter(opponent)
    end)
    fighters:RegisterEvent("PLAYER_TARGET_CHANGED")
    fighters:RegisterEvent("PLAYER_FOCUS_CHANGED")
    fighters:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    fighters:RegisterEvent("UNIT_MODEL_CHANGED")
    fighters:RegisterEvent("UNIT_NAME_UPDATE")
    fighters:RegisterEvent("GROUP_ROSTER_UPDATE")
    fighters:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    fighters:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    fighters:SetScript("OnEvent", function(_, event, unit)
        if not header.opponent or not fighters:IsVisible() then return end
        if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
            refresh()
        elseif DRE:IsAccessibleValue(unit) and unit then
            if event == "NAME_PLATE_UNIT_REMOVED" then
                if unit == opponent.unit then refresh(nil, unit) end
            elseif unit == "player" or unit == opponent.unit or (not opponent.unit and matchesUnit(unit, header.opponent)) then
                refresh(unit)
            end
        end
    end)
    function header:AnchorStageText()
        if self.phase ~= "active" then odds:Hide() end
        self.stage:ClearAllPoints()
        if self.opponent then
            local top = self.phase == "active" and -8 or -49
            self.heading:ClearAllPoints()
            self.heading:SetPoint("TOPLEFT", player, "TOPRIGHT", 2, top)
            self.heading:SetPoint("TOPRIGHT", opponent, "TOPLEFT", -2, top)
        end
        if not self.opponent then
            self.stage:SetPoint("TOPLEFT", 22, -20)
        elseif self.phase == "active" then
            self.stage:SetPoint("BOTTOM", 0, 44)
        else
            self.stage:SetPoint("TOP", 0, -19)
        end
    end
    function header:SetOpponent(name)
        if self.phase ~= "active" and self.phase ~= "result" then self:SetDuelScore(nil, nil) end
        if self.opponent ~= name or (self.phase ~= "active" and self.phase ~= "result") then finishFlight() end
        local active = name ~= nil
        local wasActive = self.opponent ~= nil
        self.opponent = name
        if not active then self:SetRolls(nil) end
        if active ~= wasActive then
            fighters:SetShown(active)
            art:SetAlpha(active and 0.76 or 1)
            for _, text in ipairs({self.stage, self.heading, self.detail}) do
                text:ClearAllPoints()
                text:SetJustifyH(active and "CENTER" or "LEFT")
            end
            self:AnchorStageText()
            if active then
                self.detail:SetPoint("BOTTOMLEFT", player, "BOTTOMRIGHT", 2, 18)
                self.detail:SetPoint("BOTTOMRIGHT", opponent, "BOTTOMLEFT", -2, 18)
            else
                self.heading:SetPoint("TOPLEFT", 21, -42)
                self.heading:SetPoint("RIGHT", hero, "CENTER", 90, 0)
                self.detail:SetPoint("BOTTOMLEFT", 23, 14)
                self.detail:SetPoint("RIGHT", hero, "CENTER", 62, 0)
            end
        end
        if active then refresh() end
    end
end

function DRE:PrepareTableWindow(window, pages, sections)
    local frame = window.frame
    frame:SetResizeBounds(self.tableMinWidth, self.tableMinHeight)
    window:SetTitle(self.displayName .. " |cffd9b072- Forever Celebration|r")
    window:SetStatusText("v" .. self.version)
    local hero = CreateFrame("Frame", nil, frame)
    hero:SetPoint("TOPLEFT", 1, -41)
    hero:SetPoint("TOPRIGHT", -1, -41)
    hero:SetHeight(duelBannerHeight)
    local art = hero:CreateTexture(nil, "BACKGROUND")
    art:SetAllPoints()
    art:SetTexture(goldTable)
    rule(hero, "BOTTOM", 0, 0.61, 0.45, 0.25)
    local stage = lettering(hero, 11, gold)
    stage:SetPoint("TOPLEFT", 22, -20)
    local heading = lettering(hero, 31, ink, true)
    heading:SetPoint("TOPLEFT", 21, -42)
    heading:SetPoint("RIGHT", hero, "CENTER", 90, 0)
    heading:SetHeight(64)
    heading:SetJustifyV("TOP")
    local detail = lettering(hero, 13, muted)
    detail:SetPoint("BOTTOMLEFT", 23, 14)
    detail:SetPoint("RIGHT", hero, "CENTER", 62, 0)
    detail:SetHeight(33)
    detail:SetJustifyV("BOTTOM")
    local header = {stage = stage, heading = heading, detail = detail}
    addMatchup(hero, header, art)
    local groupSummary = CreateFrame("Frame", nil, hero)
    groupSummary:SetPoint("TOPLEFT", 22, -8)
    groupSummary:SetPoint("BOTTOMRIGHT", -22, 8)
    groupSummary:Hide()
    header.groupTurn = lettering(groupSummary, 21, ink)
    header.groupTurn:SetPoint("TOPLEFT")
    header.groupTurn:SetPoint("TOPRIGHT")
    header.groupLast = lettering(groupSummary, 13, muted)
    header.groupLast:SetPoint("TOPLEFT", header.groupTurn, "BOTTOMLEFT", 0, -2)
    header.groupLast:SetPoint("TOPRIGHT", header.groupTurn, "BOTTOMRIGHT", 0, -2)
    header.groupTurn:SetNonSpaceWrap(true)
    header.groupLast:SetNonSpaceWrap(true)
    local startHeight, targetHeight, resizeElapsed
    local function finishResize()
        hero:SetScript("OnUpdate", nil)
        resizeElapsed = nil
        hero:SetHeight(targetHeight)
    end
    local function animateResize(_, elapsed)
        resizeElapsed = resizeElapsed + elapsed
        local t = math.min(1, resizeElapsed / 0.28)
        if t == 1 then
            finishResize()
        else
            local eased = t * t * (3 - 2 * t)
            hero:SetHeight(startHeight + (targetHeight - startHeight) * eased)
        end
    end
    local function sizeStage(animate)
        local height = header.phase and duelBannerHeight or 78
        if groupSummary:IsShown() then
            local detailHeight = header.groupLast:IsShown() and (header.groupLast:GetStringHeight() + 2) or 0
            height = math.max(40, header.groupTurn:GetStringHeight() + detailHeight + 16)
        elseif header.phase and header.phase ~= "group" then
            local playing = header.phase == "active" or header.phase == "result"
            -- Leave space for the setup fields or roll history and settlement.
            -- Width also limits the table's height on tall, narrow windows.
            local windowHeight = frame:GetHeight()
            local reserved = header.phase == "result" and 300 or (playing and 250 or 326)
            height = math.max(duelBannerHeight, math.min(
                frame:GetWidth() * (playing and 0.54 or 0.42),
                windowHeight * (playing and 0.65 or 0.52),
                windowHeight - reserved))
        end
        local current = hero:GetHeight()
        if header.phase == "setup" then
            -- Returning from a taller active table must leave room for the fields
            -- from the first frame of the transition.
            current = math.min(current, frame:GetHeight() - duelSetupSpace)
        end
        if animate == true and frame:IsVisible() and current ~= height then
            if not resizeElapsed or height ~= targetHeight then
                startHeight, targetHeight, resizeElapsed = current, height, 0
                hero:SetScript("OnUpdate", animateResize)
            end
            hero:SetHeight(current)
        else
            targetHeight = height
            finishResize()
        end
    end
    local footer = AceGUI:Create("SimpleGroup")
    footer:SetLayout("Flow")
    footer:SetAutoAdjustHeight(false)
    footer.frame:SetParent(frame)
    footer.frame:SetPoint("BOTTOMLEFT", 18, 55)
    footer.frame:SetPoint("BOTTOMRIGHT", -18, 55)
    footer:SetHeight(44)
    local function anchorGroupContent(topOffset, bottomOffset)
        if header.groupBelow then
            window.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -46 + topOffset)
            window.content:SetPoint("BOTTOMRIGHT", hero, "TOPRIGHT", -17, 4 + bottomOffset)
        else
            window.content:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 17, -12 + topOffset)
            window.content:SetPoint("BOTTOMRIGHT", footer.frame, "TOPRIGHT", 0, 8 + bottomOffset)
        end
    end
    local function anchorStage()
        hero:ClearAllPoints()
        window.content:ClearAllPoints()
        if header.groupBelow then
            hero:SetPoint("BOTTOMLEFT", footer.frame, "TOPLEFT", -17, 5)
            hero:SetPoint("BOTTOMRIGHT", footer.frame, "TOPRIGHT", 17, 5)
        else
            hero:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -41)
            hero:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -41)
            if not groupSummary:IsShown() then
                window.content:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 17, header.phase and -13 or -12)
                window.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, header.phase and 107 or 53)
            end
        end
        if groupSummary:IsShown() then anchorGroupContent(0, 0) end
    end
    local groupMotion = CreateFrame("Frame", nil, groupSummary)
    local motionTime, topShift, bottomShift, fadeControls
    local function finishGroupMotion()
        if not motionTime then return end
        groupMotion:SetScript("OnUpdate", nil)
        motionTime = nil
        anchorGroupContent(0, 0)
        groupSummary:SetAlpha(1)
        window.content:SetAlpha(1)
        footer.frame:SetAlpha(1)
    end
    local function advanceGroupMotion(_, elapsed)
        motionTime = motionTime + elapsed
        local t = math.min(1, motionTime / 0.28)
        if t == 1 then finishGroupMotion(); return end
        local eased = t*t*(3 - 2*t)
        if topShift ~= 0 or bottomShift ~= 0 then
            anchorGroupContent(topShift*(1-eased), bottomShift*(1-eased))
        end
        groupSummary:SetAlpha(0.25 + 0.75*eased)
        window.content:SetAlpha(0.72 + 0.28*eased)
        if fadeControls then footer.frame:SetAlpha(0.35 + 0.65*eased) end
    end
    groupMotion:SetScript("OnHide", finishGroupMotion)
    function header:SizeGroupSummary(below, initialized, previousView)
        if previousView then finishGroupMotion() end
        if self.groupBelow ~= below then
            self.groupBelow = below
            self.groupTurn:SetJustifyH(below and "CENTER" or "LEFT")
            self.groupLast:SetJustifyH(below and "CENTER" or "LEFT")
            self.groupTurn:SetTextColor(unpack(below and gold or ink))
            anchorStage()
        end
        sizeStage(initialized)
        if previousView and frame:IsVisible() then
            local top, bottom = window.content:GetTop(), window.content:GetBottom()
            topShift = previousView.top and top and previousView.top - top or 0
            bottomShift = previousView.bottom and bottom and previousView.bottom - bottom or 0
            fadeControls, motionTime = previousView.controlsChanged, 0
            advanceGroupMotion(groupMotion, 0)
            groupMotion:SetScript("OnUpdate", advanceGroupMotion)
        end
    end
    function header:SetDuelPhase(phase, animate)
        if self.phase ~= phase then
            if phase ~= "result" then self:StopGestures() end
            self.phase = phase
            local titleFont = DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT
            if titleFont then heading:SetFont(titleFont, phase == "active" and 17 or 31, "") end
            local minHeight = phase == "setup" and duelBannerHeight + duelSetupSpace or DRE.tableMinHeight
            frame:SetResizeBounds(DRE.tableMinWidth, minHeight)
            if frame:GetHeight() < minHeight then window:SetHeight(minHeight) end
            self:AnchorStageText()
        end
        if STANDARD_TEXT_FONT then stage:SetFont(STANDARD_TEXT_FONT, phase == "active" and 17 or 11, "") end
        -- Keep the content attached to the moving table edge throughout the transition.
        anchorStage()
        sizeStage(animate)
    end
    frame:HookScript("OnSizeChanged", sizeStage)
    frame:HookScript("OnHide", function() if resizeElapsed then finishResize() end end)

    local nav = CreateFrame("Frame", nil, frame)
    nav:SetPoint("BOTTOMLEFT", 1, 1)
    nav:SetPoint("BOTTOMRIGHT", -1, 1)
    nav:SetHeight(42)
    fill(nav, "BACKGROUND", 0.115, 0.093, 0.125):SetAllPoints()
    rule(nav, "TOP", 0, 0.28, 0.22, 0.28)
    local tabs = {}
    for i, section in ipairs(sections) do
        local key = section.value
        local tab = CreateFrame("Button", nil, nav)
        tab:SetPoint("LEFT", i == 1 and nav or tabs[i-1], i == 1 and "LEFT" or "RIGHT", 0, 0)
        tab:SetHeight(40)
        local caption = lettering(tab, 13, muted)
        caption:SetPoint("CENTER")
        caption:SetText(key == "deathroll" and "Duel" or section.text)
        tab.caption = caption
        tab.indicator = fill(tab, "ARTWORK", unpack(gold))
        tab.indicator:SetHeight(2)
        tab.indicator:SetPoint("TOPLEFT", 8, 1)
        tab.indicator:SetPoint("TOPRIGHT", -8, 1)
        tab:SetScript("OnClick", function() self:SelectMainSection(key) end)
        tab:SetScript("OnEnter", function() caption:SetTextColor(unpack(ink)) end)
        tab:SetScript("OnLeave", function() caption:SetTextColor(unpack(tab.selected and gold or muted)) end)
        tabs[i] = tab
    end
    local function sizeTabs(_, width)
        for _, tab in ipairs(tabs) do tab:SetWidth((width - gripSize) / #tabs) end
    end
    nav:SetScript("OnSizeChanged", sizeTabs)
    sizeTabs(nav, window:GetWidth())
    function pages:SetGroup(key)
        finishGroupMotion()
        local duel = key == "deathroll"
        if key ~= "group" then header.groupBelow = nil end
        groupSummary:SetShown(key == "group")
        heading:SetShown(key ~= "group")
        header:SetOpponent(nil)
        footer:ReleaseChildren()
        footer:SetAutoAdjustHeight(false)
        footer:SetHeight(44)
        footer.frame:SetShown(duel or key == "group")
        -- The Duel page chooses its phase after restoring the actual game state.
        header:SetDuelPhase(nil)
        if duel then
            art:SetTexture(goldTable)
        else
            art:SetColorTexture(0.12, 0.10, 0.13, 1)
        end
        stage:SetShown(duel)
        detail:SetShown(duel)
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", 21, duel and -42 or -20)
        heading:SetPoint("RIGHT", hero, "CENTER", 90, 0)
        for i, section in ipairs(sections) do
            local tab = tabs[i]
            tab.selected = key == section.value
            tab.caption:SetTextColor(unpack(tab.selected and gold or muted))
            tab.indicator:SetShown(tab.selected)
            if tab.selected then
                stage:SetText(key == "deathroll" and "DUEL TABLE" or "DEATHROLL ENHANCER")
                heading:SetText(section.text)
                heading:SetTextColor(unpack(ink))
                detail:SetText("")
            end
        end
        self:Fire("OnGroupSelected", key)
    end
    return header, footer
end
