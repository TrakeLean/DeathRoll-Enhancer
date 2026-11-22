-- Shared Forever tables. Only the host runs game logic. Guests receive bounded
-- display snapshots and still roll through WoW's ordinary RandomRoll API.
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
if not DRE.devDuel then return end
local prefix = "DRETable2"
DRE.groupPrefix = prefix
local serial = 0
local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function identifier()
    serial = serial + 1
    return string.format("%08x%06x%08x", time(), math.random(0, 0xffffff), serial)
end
local function validId(id) return type(id) == "string" and #id == 22 and id:match("^%x+$") end
local function number(s, max)
    local n = tonumber(s)
    if n and n >= 0 and n <= max and n == math.floor(n) then return n end
end
local function equalName(a, b)
    if not a or not b then return false end
    if strcmputf8i then return strcmputf8i(a, b) == 0 end
    return a:lower() == b:lower()
end
local function from(sender, name)
    if equalName(DRE:NormalizePlayerName(sender), name) then return true end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return DRE:IsAccessibleValue(realm) and type(realm) == "string" and realm ~= "" and equalName(sender, name .. "-" .. realm)
end
local function send(text, channel, address)
    local modern = C_ChatInfo and C_ChatInfo.SendAddonMessage
    local api = modern or SendAddonMessage
    if not api or #text > 255 then return false end
    local ok, result = pcall(api, prefix, text, channel, address)
    return ok and DRE:IsAccessibleValue(result) and (result == true or result == 0 or result == nil)
end
local function whisper(name, text) return send(text, "WHISPER", name) end
local function indexOf(players, name)
    if name then for i, player in ipairs(players) do if equalName(name, player) then return i end end end
    return 0
end
local function split(text, sep)
    local out = {}
    for part in (text .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do out[#out+1] = part end
    return out
end

local function snapshot(host)
    local players, mode, opening, teams, channel, r = DRE:GetSharedGroupView()
    if not DRE:IsBoundedInteger(opening, 2, DRE.MAX_ROLL) then opening = 0 end
    if r and host.lastRound ~= r then host.roundNumber = host.roundNumber + 1 end
    host.lastRound = r
    -- One base-36 digit per seat carries team (0..2), score/lives (0..2),
    -- elimination and tiebreak participation. Normal turns can omit all names.
    local tied, rows, flags = {}, {}, {}
    local realm = not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()) and GetNormalizedRealmName and GetNormalizedRealmName()
    for _, i in ipairs(r and r.tiebreak or {}) do tied[i] = true end
    for i, name in ipairs(players) do
        local score = r and (r.points or r.lives)
        local team = mode == "teams" and teams[name] or 0
        local value = team + 3*(score and score[i] or 0) + (r and r.eliminated[i] and 9 or 0) + (tied[i] and 18 or 0)
        flags[i] = digits:sub(value+1,value+1)
        local wireName = name
        if realm and realm ~= "" and not name:find("-",1,true) then wireName = name .. "-" .. realm end
        rows[i] = wireName .. ":" .. flags[i]
    end
    local header = {r and r.status or "setup", mode, channel, opening, host.roundNumber}
    if r then
        for _, key in ipairs({"currentRoll","turn","rollCount","seatSteps","remaining","lastSeat","lastRoll","winningTeam","scoringRound","highFace"}) do
            header[#header+1] = r[key] or 0
        end
        header[#header+1] = indexOf(players, r.winner)
        header[#header+1] = indexOf(players, r.loser)
    end
    local meta, detail = table.concat(header, ","), r and r.pointResult or ""
    return meta .. "|" .. table.concat(rows, ";") .. "|" .. detail, table.concat(players,"\n"),
        meta .. "|" .. table.concat(flags) .. "|" .. detail, players
end

local channels = {NONE=true, PARTY=true, RAID=true, INSTANCE_CHAT=true, SAY=true}
local function decode(body, knownNames)
    local meta, roster, detail = body:match("^([^|]+)|([^|]*)|([^|]*)$")
    if not meta or #detail > 255 or detail:find("[%c]") then return end
    local h = split(meta, ",")
    local status, mode, channel = h[1], h[2], h[3]
    local setup = status == "setup"
    if not DRE.groupModes[mode] or not channels[channel] or #h ~= (setup and 5 or 17) then return end
    if not setup and status ~= "active" and status ~= "finished" and status ~= "cancelled" then return end
    for i=4,#h do h[i] = number(h[i], 2147483647); if not h[i] then return end end
    if h[4] > DRE.MAX_ROLL or (not setup and h[4] < 2) then return end
    local names, teams, scores, out, tied = {}, {}, {}, {}, {}
    local rows = knownNames or (roster == "" and {} or split(roster, ";"))
    if #rows > 40 or (knownNames and #roster ~= #rows) then return end
    for i, row in ipairs(rows) do
        local name, flag
        if knownNames then name, flag = row, roster:sub(i,i)
        else name, flag = row:match("^([^:]+):([0-9A-Z])$") end
        local value = flag and digits:find(flag,1,true)
        if not DRE:IsValidPlayerName(name) or not value then return end
        name = DRE:NormalizePlayerName(name)
        if not name then return end
        value = value - 1
        local team = value % 3
        names[i] = name
        if mode == "teams" then
            if team == 0 then return end
            teams[name] = team
        end
        scores[i] = math.floor(value/3) % 3
        if math.floor(value/9) % 2 == 1 then out[i] = true end
        if value >= 18 then tied[#tied+1] = i end
    end
    local text = table.concat(names, "\n")
    local players = DRE:ParseGroupRoster(text, setup)
    if not players or table.concat(players, "\n") ~= text then return end
    local draft = {roster=text, mode=mode, initialRoll=tostring(h[4]), channel=channel, teams=teams}
    if setup then return draft end
    local count = #players
    local current, turn, rolls, steps, remaining, last, face, winning, scoring, high, winner, loser = unpack(h,6,17)
    if current < 1 or current > h[4] or turn < 1 or turn > count or remaining > count or last > count
        or face > h[4] or high > h[4] or winning > 2 or winner > count or loser > count
        or (rolls == 0 and (last ~= 0 or face ~= 0)) or (rolls > 0 and (last == 0 or face == 0))
        or (mode == "highRoller" and scoring < 1) then return end
    local r = {sharedNumber=h[5], status=status, players=players, mode=mode, initialRoll=h[4], channel=channel,
        currentRoll=current, turn=turn, rollCount=rolls, seatSteps=steps, remaining=remaining, eliminated=out,
        lastSeat=last > 0 and last or nil, lastPlayer=players[last], lastRoll=face > 0 and face or nil,
        winner=players[winner], loser=players[loser], winningTeam=winning > 0 and winning or nil, log={}}
    if mode == "teams" then r.teams = teams
    elseif mode == "twoLives" then r.lives = scores
    elseif mode == "highRoller" then
        r.points, r.scoringRound, r.tiebreak = scores, scoring, #tied > 0 and tied or nil
        r.highFace, r.pointResult = high > 0 and high or nil, detail ~= "" and detail or nil
    end
    return draft, r
end

local function saved()
    DRE.db.char = DRE.db.char or {}
    return DRE.db.char
end
local function checkpoint(s)
    local data = {role=s.role, host=s.host, id=s.id, updated=time()}
    if s.role == "host" then
        data.revision, data.roundNumber = s.rev, s.roundNumber
        data.draft, data.round = DRE.groupDraft, DRE.groupRound
    end
    saved().sharedTable = data
end

local function packets(host, body)
    local parts, at = {}, 1
    while at <= #body do
        local nextByte = math.min(#body+1, at+205)
        while nextByte > at and (body:byte(nextByte) or 0) >= 128 and (body:byte(nextByte) or 0) < 192 do
            nextByte = nextByte-1
        end
        if nextByte == at then return {} end
        parts[#parts+1] = body:sub(at,nextByte-1)
        at = nextByte
    end
    for i, part in ipairs(parts) do
        parts[i] = ("S:%s:%d:%s:%d:%d:"):format(host.epoch,host.rev,body:sub(1,1),i,#parts) .. part
    end
    return parts
end

local function eligible(host, name)
    if indexOf(host.names,name) > 0 then return true end
    local raid = IsInRaid and IsInRaid()
    for i=1,(raid and 40 or 4) do
        if equalName(name,DRE:GetUnitPlayerName((raid and "raid" or "party") .. i)) then return true end
    end
    return false
end
local function authorized(host, peer)
    if host.peers[peer.key] ~= peer then return false end
    if eligible(host,peer.name) then return true end
    host.peers[peer.key] = nil
    whisper(peer.name,"N:" .. peer.ticket .. ":roster")
    return false
end

-- Queue at most the current and latest snapshot per destination. Finish a
-- multipart revision before superseding it so busy tables still make progress.
local function pump(host)
    if DRE.sharedTable ~= host then return end
    host.pumping = nil
    local job = table.remove(host.queue,1)
    if not job then return end
    local allowed = authorized(host,job.peer)
    if allowed and whisper(job.peer.name, job.parts[job.index]) then job.index = job.index + 1 end
    job.attempts = job.attempts + 1
    if allowed and job.index <= #job.parts and job.attempts < #job.parts + 4 then
        host.queue[#host.queue+1] = job
    else
        host.jobs[job.peer] = nil
        if allowed and job.latest then
            job.parts, job.latest, job.index, job.attempts = job.latest, nil, 1, 0
            host.jobs[job.peer] = job
            host.queue[#host.queue+1] = job
        end
    end
    if #host.queue > 0 then
        host.pumping = true
        C_Timer.After(0.07, function() pump(host) end)
    end
end
local function enqueue(host, peer, full)
    local job = host.jobs[peer]
    local parts = full and host.fullParts or host.parts
    if job then
        if job.parts ~= parts then job.latest = job.latest and host.fullParts or parts end
    else
        job = {peer=peer,parts=parts,index=1,attempts=0}
        host.jobs[peer] = job
        host.queue[#host.queue+1] = job
    end
    if not host.pumping then
        host.pumping = true
        C_Timer.After(0, function() pump(host) end)
    end
end
function DRE:PublishSharedTable()
    local host = self.sharedTable
    local body, roster, compact, players = snapshot(host)
    if body == host.body then return end
    host.body, host.rev = body, host.rev + 1
    local changed = roster ~= host.roster
    if changed then host.roster, host.rosterRev, host.names = roster, host.rev, players end
    host.fullParts = packets(host, "=" .. host.rosterRev .. ":" .. body)
    host.parts = changed and host.fullParts or packets(host, "@" .. host.rosterRev .. ":" .. compact)
    checkpoint(host)
    for _,peer in pairs(host.peers) do
        if authorized(host,peer) then enqueue(host,peer) end
    end
end

local function request(s)
    local me = DRE:GetUnitPlayerName("player")
    return me and whisper(s.host, ("J:%s:%s:%d:%s"):format(s.ticket,s.id or "-",s.rev,me))
end
function DRE:SharedHostOnline()
    local s = self.sharedTable
    return s and s.role == "guest" and s.rev > 0 and s.rev >= (s.expected or 0) and GetTime()-s.seen < 20
end
local function heartbeat(s)
    C_Timer.After(8,function()
        if DRE.sharedTable ~= s then return end
        if s.role == "guest" then
            if GetTime()-s.seen > (s.id and 90 or 15) then
                DRE:LeaveSharedTable()
                DRE:Print("Could not reach the table host. Target them and join again.")
                return
            end
            request(s)
            DRE:RefreshGroupUI()
        else
            for key, peer in pairs(s.peers) do if GetTime()-peer.seen > 35 then s.peers[key] = nil end end
        end
        if s.id then checkpoint(s) end
        heartbeat(s)
    end)
end
local function hostTable(restore)
    if (DRE:HasActiveGame() and (restore or not DRE:IsGroupRoundActive())) or DRE.pendingChallenge or DRE.acceptedChallenge then
        return false,"Finish your current game or invitation first."
    end
    local s = {role="host",host=DRE:GetUnitPlayerName("player"),id=restore and restore.id or identifier(),epoch=identifier(),
        rev=restore and restore.revision or 0, roundNumber=restore and restore.roundNumber or 0, peers={}, jobs={}, queue={}}
    if not s.host then return false, "Your character name is unavailable." end
    if restore then
        DRE.groupDraft, DRE.groupRound = restore.draft, restore.round
        s.lastRound = restore.round
        if s.lastRound then s.lastRound.pendingRoll = nil end
    end
    DRE.sharedTable = s
    DRE:RefreshGroupUI()
    heartbeat(s)
    return true
end
local function joinTable(name, id)
    name = DRE:NormalizePlayerName(name)
    if not name or equalName(name,DRE:GetUnitPlayerName("player")) then return false,"Target another player who is hosting a table." end
    if DRE:HasActiveGame() or DRE.pendingChallenge or DRE.acceptedChallenge then return false,"Finish your current game or invitation first." end
    local s = {role="guest", host=name, ticket=identifier(), id=id, rev=0, seen=GetTime(),
        localDraft=DRE.groupDraft, localRound=DRE.groupRound}
    if not request(s) and not id then return false,"The table request could not be sent." end
    DRE.sharedTable, DRE.groupDraft, DRE.groupRound = s, nil, nil
    DRE:RefreshGroupUI()
    heartbeat(s)
    return true
end
function DRE:LeaveSharedTable()
    local s = self.sharedTable
    if not s then return end
    if s.role == "guest" then
        if s.id then whisper(s.host, "L:"..s.id..":"..s.ticket) end
        self.groupDraft, self.groupRound = s.localDraft, s.localRound
    else
        for _, peer in pairs(s.peers) do whisper(peer.name, "X:"..s.id) end
    end
    self.sharedTable, saved().sharedTable = nil, nil
    self:RefreshGroupUI()
end
function DRE:RestoreSharedTable()
    if self.sharedTable then return end
    local data = saved().sharedTable
    if not data then return end
    if type(data) ~= "table" or not validId(data.id) or not number(data.updated,4294967295)
        or time()-data.updated > 900 then saved().sharedTable=nil; return end
    local function restore(attempt)
        if DRE.disabled or DRE.sharedTable or saved().sharedTable ~= data then return end
        local player = DRE:GetUnitPlayerName("player")
        if not player and attempt < 10 then C_Timer.After(1,function() restore(attempt+1) end); return end
        local ok
        if player and data.role == "guest" then ok = joinTable(data.host, data.id)
        elseif data.role == "host" and equalName(data.host,player) then ok = hostTable(data) end
        if not ok then saved().sharedTable=nil end
    end
    C_Timer.After(1,function() restore(1) end)
end
function DRE:SharedTableCommand(command, name)
    if command ~= "host" and command ~= "join" and command ~= "leave" then return false end
    if not self.groupMessagesEnabled then self:Print("Shared tables need addon messaging on this client."); return true end
    local ok, reason
    if command == "leave" then self:LeaveSharedTable(); return true
    elseif self.sharedTable then reason = "Leave the current shared table first."
    elseif command == "host" then ok, reason = hostTable()
    else ok, reason = joinTable(name and name ~= "" and name or self:GetUnitPlayerName("target")) end
    if not ok then self:Print(reason) else self:ShowMainWindow("group") end
    return true
end

local function handleJoin(host, payload, sender)
    local ticket, wanted, revision, name = payload:match("^J:(%x+):([%x%-]+):(%d+):(.+)$")
    revision = number(revision,2147483647)
    if not validId(ticket) or (wanted ~= "-" and not validId(wanted)) or not revision or not DRE:IsValidPlayerName(name) then return end
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        if not from(sender,name) then return end
    else
        name = DRE:NormalizePlayerName(sender)
        if not name then return end
    end
    if not host or host.role ~= "host" then
        if wanted == "-" then whisper(name, "N:"..ticket..":closed") end
        return
    end
    if wanted ~= "-" and wanted ~= host.id then whisper(name, "N:"..ticket..":closed"); return end
    local key = name:lower()
    local peer = host.peers[key]
    local needsBaseline = not peer or peer.ticket ~= ticket
    if not eligible(host,name) then
        host.peers[key] = nil
        whisper(name, "N:"..ticket..":roster")
        return
    end
    if not peer then
        local count = 0
        for _ in pairs(host.peers) do count=count+1 end
        if count >= 40 then whisper(name,"N:"..ticket..":full"); return end
        peer = {name=name,key=key}
        host.peers[key] = peer
    elseif GetTime()-peer.seen < 1 then return end
    peer.ticket, peer.seen = ticket, GetTime()
    whisper(name, ("A:%s:%s:%s:%d"):format(ticket,host.id,host.epoch,host.rev))
    if needsBaseline or revision ~= host.rev or wanted == "-" then enqueue(host,peer,true) end
end

local function applySnapshot(s, rev, body)
    local form, base, content = body:match("^([=@])(%d+):(.+)$")
    base = number(base,rev)
    if not base or base == 0 or (form == "@" and base ~= s.rosterRev) then return end
    local draft, incoming = decode(content, form == "@" and s.names or nil)
    if not draft then return end
    local old = DRE.groupRound
    local sameRound = old and incoming and old.sharedNumber == incoming.sharedNumber
    local liveRoll = sameRound and incoming.rollCount > old.rollCount
    if sameRound then
        if table.concat(old.players,"\n") ~= draft.roster or incoming.rollCount < old.rollCount then return end
        incoming.players = old.players
        if incoming.rollCount == old.rollCount then incoming.pendingRoll = old.pendingRoll end
        for key in pairs(old) do old[key] = nil end
        for key,value in pairs(incoming) do old[key] = value end
        incoming = old
    elseif incoming and incoming.status ~= "cancelled" and indexOf(incoming.players,DRE:GetUnitPlayerName("player")) > 0 then
        DRE:ProtectGroupTradeWagers(incoming.players)
    end
    if form == "=" then
        s.rosterRev, s.names = base, draft.roster == "" and {} or split(draft.roster,"\n")
    end
    if s.rev == 0 and DRE.UI.groupWidgets then DRE.UI.groupWidgets.draftText = nil end
    s.rev, s.seen = rev, GetTime()
    DRE.groupDraft, DRE.groupRound = draft, incoming
    DRE:RefreshGroupUI()
    if incoming and (liveRoll or not sameRound) and incoming.status == "active"
        and equalName(incoming.players[incoming.turn],DRE:GetUnitPlayerName("player")) then DRE:PlayTurnSound() end
    local widgets = DRE.UI.groupWidgets
    if liveRoll and widgets and widgets.circle and widgets.circle.round == incoming and widgets.circle.frame:IsVisible() then
        widgets.circle:AnimateRollBadge()
    end
end

function DRE:ReceiveGroupMessage(payload, channel, sender)
    if not self:IsAccessibleValue(payload) or type(payload) ~= "string" or #payload > 255
        or not self:IsAccessibleValue(channel) or not self:IsValidPlayerName(sender) then return end
    local s = self.sharedTable
    local op = payload:sub(1,2)
    if op == "J:" and channel == "WHISPER" then handleJoin(s,payload,sender); return end
    if not s then return end
    if s.role == "host" then
        if op ~= "L:" or channel ~= "WHISPER" then return end
        local id,ticket = payload:match("^L:(%x+):(%x+)$")
        if id == s.id then
            for key, peer in pairs(s.peers) do
                if peer.ticket == ticket and from(sender,peer.name) then s.peers[key]=nil; break end
            end
        end
        return
    end
    if not from(sender,s.host) then return end
    if channel == "WHISPER" and op == "A:" then
        local ticket,id,epoch,rev = payload:match("^A:(%x+):(%x+):(%x+):(%d+)$")
        rev = number(rev,2147483647)
        if ticket ~= s.ticket or not validId(id) or not validId(epoch) or not rev or (s.id and s.id ~= id) then return end
        if s.epoch and epoch ~= s.epoch then
            if s.retired and s.retired[epoch] then return end
            s.retired = s.retired or {}
            s.retired[s.epoch] = true
            s.rev, s.expected, s.batch, s.rosterRev, s.names = 0, 0, nil, nil, nil
            self.groupDraft, self.groupRound = nil, nil
        end
        s.epoch = epoch
        s.id, s.expected, s.seen = id, math.max(rev,s.expected or 0), GetTime()
        checkpoint(s)
        self:RefreshGroupUI()
    elseif channel == "WHISPER" and (op == "N:" or op == "X:") then
        local ticket, reason = payload:match("^N:(%x+):(%a+)$")
        if ticket == s.ticket or (s.id and payload == "X:"..s.id) then
            self:LeaveSharedTable()
            self:Print(reason == "roster" and "Ask the host to add you to the roster or join their party first."
                or reason == "full" and "That table is full." or "The host's shared table is closed.")
        end
    elseif op == "S:" and channel == "WHISPER" then
        local id,rev,form,i,count,data = payload:match("^S:(%x+):(%d+):([=@]):(%d+):(%d+):(.+)$")
        rev, i, count = number(rev,2147483647), number(i,48), number(count,48)
        if not s.epoch or id ~= s.epoch or not rev or rev <= s.rev or not i or not count or i < 1 or i > count or #data > 205 then return end
        local batch = s.batch
        if not batch or rev > batch.rev or (rev == batch.rev and batch.form == "@" and form == "=") then
            batch = {rev=rev,form=form,count=count,received=0,parts={}}
            s.batch = batch
        end
        if batch.rev ~= rev or batch.form ~= form or batch.count ~= count or batch.parts[i] then return end
        batch.parts[i], batch.received = data, batch.received+1
        if batch.received == count then
            s.batch = nil
            applySnapshot(s,rev,table.concat(batch.parts))
        end
    end
end
