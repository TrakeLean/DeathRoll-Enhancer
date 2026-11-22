-- The archive must supply every library and all SavedVariables from cold start.
LibStub, AceGUI, DRE = nil, nil, nil
strlower, strlenutf8, strmatch, format = string.lower, string.len, string.match, string.format
tinsert, tremove, sort = table.insert, table.remove, table.sort
function wipe(t)
    for key in pairs(t) do t[key] = nil end
    return t
end
table.wipe = wipe
function strsplit(separator, value)
    local start, stop = value:find(separator, 1, true)
    if start then return value:sub(1, start - 1), strsplit(separator, value:sub(stop + 1)) end
    return value
end
local protectedCall = xpcall
function xpcall(callback, handler, ...)
    local args, count = {...}, select("#", ...)
    return protectedCall(function() return callback(unpack(args, 1, count)) end, handler)
end
clientErrors = {}
function geterrorhandler() return function(message) table.insert(clientErrors, message) end end
function securecallfunction(callback, ...) return callback(...) end
securecall = securecallfunction
function Mixin(destination, ...)
    for _, source in ipairs({...}) do
        for k, v in pairs(source) do destination[k] = v end
    end
    return destination
end
local newFrame = CreateFrame
function CreateFrame(kind, name, parent, ...)
    local frame = newFrame(kind, name, parent, ...)
    function frame:CreateTexture() return CreateFrame("Texture", nil, self) end
    function frame:GetVertexColor() return 1, 1, 1 end
    function frame:GetParent() return parent end
    function frame:GetName() return name end
    frame.GetNormalTexture, frame.GetPushedTexture = newFrame, newFrame
    frame.GetHighlightTexture, frame.GetFontString = newFrame, newFrame
    if name then _G[name] = frame end
    if (...) == "UIDropDownMenuTemplate" then
        for _, suffix in ipairs({"Left", "Middle", "Right", "Button", "Text"}) do
            CreateFrame("Frame", name .. suffix, frame)
        end
    end
    return frame
end
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetWidth(140)
Minimap:SetHeight(140)
regionalNames, units.player = true, {"Tester", "Smith"}
function GetBuildInfo() return "1.60.1", "71037", nil, 16001 end
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return "Human", "Human" end
function UnitFactionGroup() return "Alliance" end
function GetCurrentRegionName() return "US" end
function GetCurrentRegion() return 1 end
C_GameRules = {IsGameRuleActive = function() return false end}
Enum = {GameRule = {}}
function IsLoggedIn() return true end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = {AddMessage = function() end}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return {ID = 1, name = name, frame = frame, children = {}} end,
    RegisterAddOnCategory = function(category) Settings.root = category end,
    GetCategory = function(id) if Settings.root.ID == id then return Settings.root end end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        local child = {ID = #parent.children + 2, name = name, frame = frame}
        table.insert(parent.children, child)
        return child
    end,
}
function GetAddOnMetadata(_, key) return tocMetadata[key] end
