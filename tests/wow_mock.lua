-- Test-only WoW/Ace boundary. Game, parser, database and UI logic are real addon code.
now = 1800000000
clock = 100
units = { player = { 'Me', 'LocalRealm' }, target = { 'Alice', 'LocalRealm' } }
regionalNames = false
GetTime = function() return clock end
time = function(value) if value then return os.time(value) end return now end
date = function(format) return os.date(format, now) end
UnitName = function(unit) if units[unit] then return unpack(units[unit]) end end
UnitNameUnmodified = UnitName
UnitFullName = UnitName
UnitExists = function(unit) return units[unit] ~= nil end
UnitIsPlayer = UnitExists
UnitIsUnit = function(a,b) return a == b end
GetNormalizedRealmName = function() return 'LocalRealm' end
RegionalUniqueNamesEnabled = function() return regionalNames end
NameUtil = { GetFullNameWithoutRealm = function(first,second) return second and (first..' '..second) or first end }
GetMoney = function() return 100000 end
TargetByName = function() end
DoEmote = function() end
ERR_TRADE_COMPLETE = 'Trade complete'
GetPlayerTradeMoney = function() return 0 end
GetTargetTradeMoney = function() return 0 end
RANDOM_ROLL_RESULT = '%s rolls %d (%d-%d)'
NORMAL_FONT_COLOR = {r=1,g=1,b=1}
GameFontNormalSmall = {}
GameFontHighlightSmall = {}
UIParent = { GetWidth = function() return 1920 end, GetHeight = function() return 1080 end }
timers = {}
C_Timer = { After = function(delay,callback) timers[#timers+1] = { delay=delay, callback=callback } end }
rolls = {}
RandomRoll = function(low,high) rolls[#rolls+1] = { low,high } end
sent = {}
SendChatMessage = function(...) sent[#sent+1] = {...} end
StaticPopupDialogs = {}
popups = {}
StaticPopup_Show = function(key,text1,text2,data)
    local config = assert(StaticPopupDialogs[key])
    -- Blizzard formats text before OnShow and installs data before either callback.
    local text = string.format(config.text, text1, text2)
    local popup = { data=data, textValue=text, shown=true }
    function popup:Hide() self.shown=false end
    if config.OnShow then config.OnShow(popup,data) end
    popups[#popups+1] = { key=key, dialog=popup }
    return popup
end
StaticPopup_Hide = function() end

local methods = {}
function methods:SetCallback(name,callback) self.callbacks[name] = callback end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text or '' end
function methods:SetValue(value) self.value = value end
function methods:GetValue() return self.value end
function methods:SetDisabled(value) self.disabled = value end
function methods:SetWidth(value) self.width = value end
function methods:GetWidth() return self.width or 400 end
function methods:SetHeight(value) self.height = value end
function methods:GetHeight() return self.height or 200 end
function methods:GetScale() return self.scale or 1 end
function methods:SetScale(value) self.scale = value end
function methods:GetEffectiveScale() return 1 end
function methods:IsVisible() return self.visible ~= false end
function methods:IsShown() return self:IsVisible() end
function methods:Show() self.visible=true end
function methods:Hide()
    local wasVisible=self.visible
    self.visible=false
    if wasVisible and self.callbacks.OnClose then self.callbacks.OnClose(self) end
end
function methods:AddChild(child) self.children[#self.children+1]=child end
function methods:ReleaseChildren()
    local children=self.children
    self.children={}
    for _,child in ipairs(children) do AceGUI:Release(child) end
end
function methods:SelectTab(group)
    self.value=group
    if self.callbacks.OnGroupSelected then self.callbacks.OnGroupSelected(self,'OnGroupSelected',group) end
end
function methods:GetStringHeight() return 20 end
function methods:GetStringWidth() return 100 end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:SetVerticalScroll(value) self.scroll=value end
function methods:GetMinMaxValues() return 0,100 end
function methods:GetPoint() return 'CENTER',nil,'CENTER',0,0 end
function methods:GetNumPoints() return 1 end
function methods:GetFont() return 'font',12,'' end
function methods:SetScript(name,callback) self.callbacks[name]=callback end
function methods:HookScript(name,callback) self.callbacks[name]=callback end
local function noop() end
local mt={__index=function(_,key)
    if methods[key] then return methods[key] end
    if type(key)=='string' and key:match('^[A-Z]') then return noop end
end}
local function rawFrame()
    return setmetatable({callbacks={},children={},visible=true}, mt)
end
function methods:CreateFontString() return rawFrame() end
CreateFrame = function() return rawFrame() end
AceGUI = { created=0, released=0, pool={} }
function AceGUI:Create(kind)
    local pool = self.pool[kind] or {}
    self.pool[kind]=pool
    local widget=table.remove(pool)
    if not widget then self.created=self.created+1; widget={} end
    for key in pairs(widget) do widget[key]=nil end
    widget.kind=kind; widget.callbacks={};widget.children={};widget.visible=true
    widget.frame=rawFrame();widget.content=rawFrame();widget.scrollbar=rawFrame()
    widget.frame.obj=widget
    setmetatable(widget,mt)
    return widget
end
function AceGUI:Release(widget)
    assert(not rawget(widget,'released'),'double release')
    widget.callbacks={}
    widget:ReleaseChildren()
    widget.visible=false
    widget.released=true
    self.released=self.released+1
    self.pool[widget.kind]=self.pool[widget.kind] or {}
    table.insert(self.pool[widget.kind],widget)
end
DRE={
    Print=function() end, RegisterEvent=function() end, UnregisterEvent=function() end,
    UnregisterAllEvents=function() end, RegisterChatCommand=function() end,
    CleanupMinimap=function() end,
}
LibStub=function(name,silent)
    if name=='AceAddon-3.0' then return {NewAddon=function() return DRE end,GetAddon=function() return DRE end} end
    if name=='AceGUI-3.0' then return AceGUI end
    if name=='AceDB-3.0' then return {} end
    if name=='AceConfig-3.0' or name=='AceConfigDialog-3.0' then return {} end
    if silent then return nil end
    error('Unexpected library '..name)
end
