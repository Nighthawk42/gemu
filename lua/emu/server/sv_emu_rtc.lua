-- Optional media service: only the game server assigns rooms and roles.
if not SERVER then return end
local enabled = CreateConVar("emu_sv_stream_enabled", "0", FCVAR_ARCHIVE, "Enable optional WebRTC service")
local service = CreateConVar("emu_sv_stream_service", "", FCVAR_ARCHIVE, "HTTPS GEMU stream broker base URL")
util.AddNetworkString("emu_rtc_config")
util.AddNetworkString("emu_rtc_ready")
local instance = util.SHA256(tostring(SysTime()) .. tostring({}) .. tostring(math.random())):sub(1, 24)
local sessions, assigned, ready = {}, {}, {}
local nextCheck, nextSync, pending = 0, 0, false
local sequence = 0
local lastSync -- {time, result} for emu_rtc_server_status
-- Per-connection identity: two clients can share one Steam account (multirun, family
-- sharing), and the broker rejects a viewer whose identity equals the publisher's.
local function identity(ply) return ply:IsBot() and ("bot_" .. ply:EntIndex()) or (ply:SteamID64() .. "_" .. ply:UserID()) end
local function stop(ply, target)
    if not IsValid(ply) or not IsValid(target) then return end
    net.Start("emu_rtc_config") net.WriteEntity(target) net.WriteBool(false) net.Send(ply)
end
function emu.RTCViewerReady(ply, target)
    local state = sessions[target]
    local row = ready[ply] and ready[ply][target]
    return enabled:GetBool() and state and state.members[ply] == "view" and row
        and row.id == state.id and row.untilTime > CurTime() or false
end
function emu.GetFallbackRecipients(ply, target)
    local result = {}
    for _, viewer in ipairs(emu.GetVideoRecipients(ply, target)) do
        if not emu.RTCViewerReady(viewer, target) then result[#result + 1] = viewer end
    end
    return result
end
net.Receive("emu_rtc_ready", function(_, ply)
    local target, id, ok = net.ReadEntity(), net.ReadString(), net.ReadBool()
    local state = sessions[target]
    if not state or state.id ~= id or state.members[ply] ~= "view" then return end
    ready[ply] = ready[ply] or {}
    ready[ply][target] = ok and {id = id, untilTime = CurTime() + 3} or nil
end)
hook.Add("Think", "Emu_RTCMembership", function()
    if CurTime() < nextCheck then return end
    nextCheck = CurTime() + 0.5
    local current, count = {}, 0
    if enabled:GetBool() then
        for _, owner in ipairs(player.GetAll()) do
            local target = owner.EmuSession
            if count < 16 and IsValid(target) and emu.IsSessionRunner(owner, target) then
                local viewers = emu.GetVideoRecipients(owner, target)
                if #viewers > 0 then
                    local state = sessions[target]
                    local rom = target:GetRomName()
                    if not state or state.owner ~= owner or state.rom ~= rom then
                        sequence = sequence + 1
                        state = {id = tostring(sequence), owner = owner, rom = rom}
                    end
                    state.members = {[owner] = "publish"}
                    for i = 1, math.min(32, #viewers) do state.members[viewers[i]] = "view" end
                    current[target], count = state, count + 1
                end
            end
        end
    end
    for ply, targets in pairs(assigned) do
        for target, id in pairs(targets) do
            local state = current[target]
            if not state or not state.members[ply] or state.id ~= id then
                stop(ply, target) targets[target] = nil
                if ready[ply] then ready[ply][target] = nil end
            end
        end
        if not IsValid(ply) or next(targets) == nil then assigned[ply], ready[ply] = nil, nil end
    end
    sessions = current
    if pending or CurTime() < nextSync then return end
    nextSync = CurTime() + 5
    local base = service:GetString():gsub("/+$", "")
    local key = string.Trim(file.Read("emu/stream_key.txt", "DATA") or "")
    if not base:match("^https://") or #key < 32 then
        lastSync = {time = CurTime(), result = "not configured (emu_sv_stream_service or data/emu/stream_key.txt)"}
        return
    end
    local rows, requested = {}, {}
    for target, state in pairs(sessions) do
        local viewers = {}
        for ply, role in pairs(state.members) do if role == "view" then viewers[#viewers + 1] = identity(ply) end end
        rows[#rows + 1] = {id = state.id, publisher = identity(state.owner), viewers = viewers}
        requested[state.id] = target
    end
    pending = true
    local accepted = HTTP({url = base .. "/sync", method = "POST", type = "application/json",
        headers = {Authorization = "Bearer " .. key}, body = util.TableToJSON({instance = instance, rooms = rows}), timeout = 8,
        failed = function(reason) pending = false lastSync = {time = CurTime(), result = "request failed: " .. tostring(reason)} end,
        success = function(code, body)
            pending = false
            lastSync = {time = CurTime(), result = "HTTP " .. tostring(code) .. " for " .. #rows .. " room(s)"}
            if code ~= 200 or not enabled:GetBool() then return end
            local data = util.JSONToTable(body)
            if not istable(data) or not istable(data.rooms) then return end
            for _, response in ipairs(data.rooms) do
                local target = requested[response.id]
                local state = sessions[target]
                if IsValid(target) and state and state.id == response.id and state.rom == target:GetRomName()
                    and istable(response.members) and isstring(response.url) and response.url:match("^wss://") then
                    for _, member in ipairs(response.members) do
                        for ply, role in pairs(state.members) do
                            if IsValid(ply) and identity(ply) == member.identity and role == member.role
                                and isstring(member.token) and #member.token < 4096 then
                                assigned[ply] = assigned[ply] or {} assigned[ply][target] = state.id
                                net.Start("emu_rtc_config") net.WriteEntity(target) net.WriteBool(true)
                                net.WriteString(state.id) net.WriteString(state.rom) net.WriteString(role)
                                net.WriteString(response.room) net.WriteString(response.url) net.WriteString(member.token)
                                net.WriteString(GetConVar("emu_url"):GetString():gsub("/+$", "") .. "/viewer.html") net.Send(ply)
                            end
                        end
                    end
                end
            end
        end})
    if not accepted then pending = false end
end)
concommand.Add("emu_rtc_server_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local count = 0
    for _ in pairs(sessions) do count = count + 1 end
    print("[GEMU RTC server] enabled=" .. tostring(enabled:GetBool()) .. " streamed devices=" .. count
        .. " last sync=" .. (lastSync and (lastSync.result .. string.format(" (%.0fs ago)", CurTime() - lastSync.time)) or "never"))
end)
