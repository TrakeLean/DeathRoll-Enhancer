-- Events.lua
-- Chat message patterns and validation helpers
-- Event handling is centralized in Core.lua

local addonName, addonTable = ...
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
if not DRE then return end

-- Chat message patterns for parsing various DeathRoll-related messages
DRE.CHAT_PATTERNS = {
    DEATHROLL_CHALLENGE = "[Cc]hallenge.* you to a [Dd]eathRoll",
    DEATHROLL_CHALLENGE_ALT = "I challenge you to a DeathRoll",
    DEATHROLL_CHALLENGE_NEW = "^DEATHROLL_CHALLENGE:(%d+):(%d+):(.+)$",
    DEATHROLL_ACCEPT = "accepts? your [Dd]eathRoll challenge",
    DEATHROLL_DECLINE = "DEATHROLL_DECLINE",
    GOLD_WAGER = "(%d+)g",
    SILVER_WAGER = "(%d+)s",
    COPPER_WAGER = "(%d+)c"
}

-- Helper function to extract gold amount from message text
function DRE:ExtractGoldFromMessage(message)
    if not message then return 0 end
    
    local totalCopper = 0
    
    -- Extract gold
    local gold = message:match(self.CHAT_PATTERNS.GOLD_WAGER)
    if gold then
        totalCopper = totalCopper + (tonumber(gold) * 10000)
    end
    
    -- Extract silver
    local silver = message:match(self.CHAT_PATTERNS.SILVER_WAGER)
    if silver then
        totalCopper = totalCopper + (tonumber(silver) * 100)
    end
    
    -- Extract copper
    local copper = message:match(self.CHAT_PATTERNS.COPPER_WAGER)
    if copper then
        totalCopper = totalCopper + tonumber(copper)
    end
    
    return totalCopper
end

-- Never inspect or log restricted client values. Older clients have no secret API.
function DRE:IsAccessibleValue(value)
    return not issecretvalue or not issecretvalue(value)
end

DRE.MAX_ROLL = 999999
DRE.MAX_WAGER = 9999999999 -- 999,999 gold, 99 silver, 99 copper

function DRE:IsBoundedInteger(value, minimum, maximum)
    return self:IsAccessibleValue(value) and type(value) == "number"
        and value == value and value >= minimum and value <= maximum
        and value == math.floor(value)
end

function DRE:ValidateGameInputs(playerName, roll, wager)
    if not self:IsValidPlayerName(playerName) then
        return false, "Invalid player name."
    end
    if not self:IsBoundedInteger(roll, 2, self.MAX_ROLL) then
        return false, "Starting roll must be a whole number from 2 to 999,999."
    end
    if not self:IsBoundedInteger(wager, 0, self.MAX_WAGER) then
        return false, "Wager must be a whole copper amount from 0 to 999,999g 99s 99c."
    end
    return true
end

-- Full names can contain UTF-8, surnames and realm qualifiers. The server is
-- authoritative about naming rules; reject control/markup bytes, not non-ASCII names.
function DRE:IsValidPlayerName(name)
    if not self:IsAccessibleValue(name) or type(name) ~= "string" then return false end
    if #name == 0 or #name > 255 then return false end
    local character, realm = name:match("^([^-]+)%-(.+)$")
    if character and not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()) then
        return character:match("^[%a\128-\255][%a\128-\255 ']*$") ~= nil
            and realm:match("^[%w\128-\255 '%-]+$") ~= nil
    end
    return name:match("^[%a\128-\255][%a\128-\255 '%-]*$") ~= nil
end

function DRE:NormalizePlayerName(name)
    if not self:IsAccessibleValue(name) or type(name) ~= "string" then return nil end
    name = self:Trim(name)
    if not self:IsValidPlayerName(name) then return nil end
    -- A realm qualifier is not a surname. Only collapse an explicitly local
    -- realm on traditional clients; never discard remote realms or name parts.
    if not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()) then
        local character, realm = name:match("^([^-]+)%-(.+)$")
        local localRealm = GetNormalizedRealmName and GetNormalizedRealmName()
            or (GetRealmName and GetRealmName())
        if character and realm and self:IsAccessibleValue(localRealm) and localRealm then
            realm = realm:gsub("%s", "")
            if realm:lower() == localRealm:gsub("%s", ""):lower() then
                return character
            end
            return character .. "-" .. realm
        end
    end
    return name
end

function DRE:GetUnitPlayerName(unit)
    -- Guard raw returns before letting the client's formatting helper concatenate.
    local getName = UnitNameUnmodified or UnitName
    local name, second = getName(unit)
    if not self:IsAccessibleValue(name) or not self:IsAccessibleValue(second) or not name then return nil end
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        if NameUtil and NameUtil.GetFullNameWithoutRealm then
            name = NameUtil.GetFullNameWithoutRealm(name, second)
        elseif second and second ~= "" then
            local separator = Constants and Constants.CharacterNameSeparatorConsts
                and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
            name = name .. separator .. second
        end
    else
        if UnitFullName then
            name, second = UnitFullName(unit)
            if not self:IsAccessibleValue(name) or not self:IsAccessibleValue(second) or not name then return nil end
        end
        if second and second ~= "" then name = name .. "-" .. second end
    end
    return self:NormalizePlayerName(name)
end

function DRE:IsSamePlayer(first, second)
    first, second = self:NormalizePlayerName(first), self:NormalizePlayerName(second)
    return first ~= nil and second ~= nil and first == second
end

-- Compile the client's printf format into a Lua pattern. Positional placeholders
-- are used by some translations; retain their argument indices when capturing.
local function CompileRollFormat(formatText)
    local parts, arguments = { "^" }, {}
    local offset, sequential = 1, 0
    while offset <= #formatText do
        local char = formatText:sub(offset, offset)
        if char == "%" then
            if formatText:sub(offset + 1, offset + 1) == "%" then
                parts[#parts + 1] = "%%"
                offset = offset + 2
            else
                local rest = formatText:sub(offset)
                local token, position, kind = rest:match("^(%%(%d+)%$([sd]))")
                if not token then
                    token, kind = rest:match("^(%%([sd]))")
                    sequential = sequential + 1
                    position = sequential
                end
                if not token then return nil end
                parts[#parts + 1] = kind == "s" and "(.+)" or "(%d+)"
                arguments[#arguments + 1] = tonumber(position)
                offset = offset + #token
            end
        else
            parts[#parts + 1] = char:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            offset = offset + 1
        end
    end
    parts[#parts + 1] = "$"
    if #arguments ~= 4 then return nil end
    return table.concat(parts), arguments
end

function DRE:ParseRollMessage(message)
    if not self:IsAccessibleValue(message) or type(message) ~= "string" then return nil end
    local formatText = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    if self.rollFormat ~= formatText then
        self.rollFormat = formatText
        self.rollPattern, self.rollArguments = CompileRollFormat(formatText)
    end
    if not self.rollPattern then return nil end
    local captures = { message:match(self.rollPattern) }
    if #captures ~= 4 then return nil end
    local values = {}
    for index, value in ipairs(captures) do values[self.rollArguments[index]] = value end
    local playerName = self:NormalizePlayerName(values[1])
    local roll, minimum, maximum = tonumber(values[2]), tonumber(values[3]), tonumber(values[4])
    if not playerName or minimum ~= 1 or not self:IsBoundedInteger(maximum, 1, self.MAX_ROLL)
        or not self:IsBoundedInteger(roll, 1, maximum) then return nil end
    return { playerName = playerName, roll = roll, minRoll = minimum, maxRoll = maximum }
end

function DRE:SendChatSafely(message, channel, language, target)
    if not self:IsAccessibleValue(message) or not self:IsAccessibleValue(target) then return false end
    if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
        and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
        return false, "Chat is currently restricted by the client."
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, "Chat is temporarily locked by the client."
    end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if not send then return false, "Chat is unavailable on this client." end
    return pcall(send, message, channel, language, target)
end

-- Helper function to detect challenge messages
function DRE:IsDeathRollChallenge(message)
    if not message then return false end
    local lowerMessage = message:lower()
    -- Use simple lowercase substring checks to avoid pattern case-class issues
    if lowerMessage:find("challenge.* you to a deathroll") then
        return true
    end
    if lowerMessage:find("i challenge you to a deathroll") then
        return true
    end
    return false
end

-- Validation helper for wager amounts
function DRE:ValidateWager(gold, silver, copper)
    gold = gold or 0
    silver = silver or 0
    copper = copper or 0
    
    -- Require finite integer currency components.
    if not self:IsBoundedInteger(gold, 0, 999999) or not self:IsBoundedInteger(silver, 0, 99)
        or not self:IsBoundedInteger(copper, 0, 99) then
        return false, "Wager amounts cannot be negative!"
    end
    
    -- Check for reasonable limits (prevent overflow)
    if gold > 999999 then
        return false, "Gold amount too large (max 999,999)!"
    end
    
    if silver > 99 then
        return false, "Silver amount should be 0-99!"
    end
    
    if copper > 99 then
        return false, "Copper amount should be 0-99!"
    end
    
    return true, nil
end
-- Whitespace separates command arguments; quote a full name when a command
-- takes two names (for example /dr merge "Alice Smith" "Alice Jones").
function DRE:ParseCommandArguments(text)
    local args, offset = {}, 1
    while offset <= #text do
        local _, finish = text:find("^%s+", offset)
        if finish then offset = finish + 1 end
        if offset > #text then break end
        local quote = text:sub(offset, offset)
        if quote == '"' or quote == "'" then
            local closing = text:find(quote, offset + 1, true)
            if not closing then return nil, "Close the quoted player name." end
            args[#args + 1] = text:sub(offset + 1, closing - 1)
            offset = closing + 1
            if offset <= #text and not text:sub(offset, offset):match("%s") then
                return nil, "Separate quoted names with a space."
            end
        else
            local finish = text:find("%s", offset) or (#text + 1)
            args[#args + 1] = text:sub(offset, finish - 1)
            offset = finish
        end
    end
    return args
end
