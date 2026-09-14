-- The server owns device sessions, controller focus and every stream relay.
-- A session keeps its device reserved until an explicit action ends it;
-- focus only locks the runner's movement while they hold the controls.
if not SERVER then return end
emu = emu or {}
util.AddNetworkString("emu_play_focus")
util.AddNetworkString("emu_focus_result")
util.AddNetworkString("emu_session")
util.AddNetworkString("emu_session_result")
util.AddNetworkString("emu_session_paused")
util.AddNetworkString("emu_open_ui")
util.AddNetworkString("emu_video_frame")
util.AddNetworkString("emu_audio_frame")
util.AddNetworkString("emu_state_snapshot")
util.AddNetworkString("emu_state_chunk")
util.AddNetworkString("emu_state_upload_ack")
util.AddNetworkString("emu_state_download_ack")
util.AddNetworkString("emu_player2_result")
util.AddNetworkString("emu_player2_buttons")
util.AddNetworkString("emu_player2_focus")

local MAX_FRAME_BYTES = 60000
local MAX_AUDIO_BYTES = 12000
local MAX_STATE_BYTES = 4 * 1024 * 1024
local STATE_CHUNK_BYTES = 8192
local SESSION_TIMEOUT = 15
local AUDIO_RATE, AUDIO_BURST = 12, 3
local stateTransfers = {}
local stateDownloads = {}

function emu.IsSessionRunner(ply, target)
    return IsValid(ply) and IsValid(target) and ply.EmuSession == target
        and emu.GetSessionRunner(target) == ply and emu.CanKeepSession(ply, target)
end

-- Listen and P2P servers rarely deliver multi-kilobyte unreliable messages, so
-- fallback frames travel reliably there under a per-spectator byte budget.
function emu.StreamReliable()
    local cvar = GetConVar("emu_sv_stream_transport")
    local mode = cvar and cvar.GetString and cvar:GetString() or "auto"
    if mode == "reliable" then return true end
    if mode == "unreliable" then return false end
    return not (game and game.IsDedicated and game.IsDedicated())
end

function emu.TakeStreamBudget(viewer, bytes, now)
    local cvar = GetConVar("emu_sv_stream_budget")
    local limit = math.Clamp(cvar and cvar.GetFloat and cvar:GetFloat() or 32000, 8000, 256000)
    local bucket = viewer.EmuStreamBudget
    if not bucket then
        bucket = {tokens = limit, time = now}
        viewer.EmuStreamBudget = bucket
    end
    bucket.tokens = math.min(limit, bucket.tokens + math.max(0, now - bucket.time) * limit)
    bucket.time = now
    if bucket.tokens < bytes then return false end
    bucket.tokens = bucket.tokens - bytes
    return true
end

-- Starts a relay message and returns the spectators it may reach, or nil.
local function startRelay(name, recipients, bytes)
    local reliable = emu.StreamReliable()
    if reliable then
        local now, allowed = CurTime(), {}
        for _, viewer in ipairs(recipients) do
            if emu.TakeStreamBudget(viewer, bytes, now) then allowed[#allowed + 1] = viewer end
        end
        recipients = allowed
    end
    if #recipients == 0 then return end
    -- Unreliable frames may drop; never queue stale gameplay on dedicated servers.
    net.Start(name, not reliable)
    return recipients
end

function emu.CanRelayVideoFrame(ply, target, size, now)
    if not emu.IsSessionRunner(ply, target) then return false end
    if size < 1 or size > MAX_FRAME_BYTES then return false end
    now = now or CurTime()
    if now < (ply.EmuNextVideoFrame or 0) then return false end
    local fps = math.Clamp(GetConVar("emu_sv_stream_fps"):GetFloat(), 1, 8)
    -- Client capture runs on its own clock; tolerate jitter without raising the rate.
    ply.EmuNextVideoFrame = now + 0.8 / fps
    return true
end

function emu.GetVideoRecipients(ply, target)
    local recipients = {}
    local distance = math.Clamp(GetConVar("emu_sv_stream_distance"):GetFloat(), 256, 4096)
    local distanceSqr = distance * distance
    local origin = target:WorldSpaceCenter()
    local display = not emu.IsHandheld(target) and target:GetLinkedDisplay() or nil
    local displayOrigin = IsValid(display) and display:WorldSpaceCenter() or nil
    for _, viewer in ipairs(player.GetAll()) do
        if viewer ~= ply and IsValid(viewer) then
            local pos = viewer:GetShootPos()
            if pos:DistToSqr(origin) <= distanceSqr
                or (displayOrigin and pos:DistToSqr(displayOrigin) <= distanceSqr) then
                recipients[#recipients + 1] = viewer
            end
        end
    end
    return recipients
end

function emu.CanRelayAudioFrame(ply, target, size, sampleRate, now)
    if not emu.IsSessionRunner(ply, target) then return false end
    if size < 1 or size > MAX_AUDIO_BYTES or sampleRate < 8000 or sampleRate > 48000 then return false end
    now = now or CurTime()
    -- A small burst absorbs capture jitter; the sustained rate stays bounded.
    local tokens = math.min(AUDIO_BURST, (ply.EmuAudioTokens or AUDIO_BURST)
        + math.max(0, now - (ply.EmuAudioTime or now)) * AUDIO_RATE)
    ply.EmuAudioTime = now
    if tokens < 1 then ply.EmuAudioTokens = tokens return false end
    ply.EmuAudioTokens = tokens - 1
    return true
end

net.Receive("emu_video_frame", function(bits, ply)
    local target = net.ReadEntity()
    local size = net.ReadUInt(16)
    -- net.WriteEntity's width depends on the GMod build (MAX_EDICT_BITS, not a fixed
    -- 16), so require only the payload bits; ReadData's length check catches truncation.
    if bits < size * 8 or not emu.CanRelayVideoFrame(ply, target, size) then return end
    local data = net.ReadData(size)
    if not data or #data ~= size then return end
    local recipients = startRelay("emu_video_frame", (emu.GetFallbackRecipients or emu.GetVideoRecipients)(ply, target), size + 64)
    if not recipients then return end
    target.EmuVideoSerial = ((target.EmuVideoSerial or 0) + 1) % 4294967296
    net.WriteEntity(target)
    net.WriteUInt(target.EmuVideoSerial, 32)
    net.WriteString(target:GetRomName())
    net.WriteUInt(size, 16)
    net.WriteData(data, size)
    net.Send(recipients)
end)

net.Receive("emu_audio_frame", function(_, ply)
    local target = net.ReadEntity()
    local sampleRate = net.ReadUInt(16)
    local size = net.ReadUInt(16)
    if not emu.CanRelayAudioFrame(ply, target, size, sampleRate) then return end
    local data = net.ReadData(size)
    if not data or #data ~= size then return end
    local recipients = startRelay("emu_audio_frame", (emu.GetFallbackRecipients or emu.GetVideoRecipients)(ply, target), size + 64)
    if not recipients then return end
    target.EmuAudioSerial = ((target.EmuAudioSerial or 0) + 1) % 4294967296
    net.WriteEntity(target)
    net.WriteUInt(target.EmuAudioSerial, 32)
    net.WriteString(target:GetRomName())
    net.WriteUInt(sampleRate, 16)
    net.WriteUInt(size, 16)
    net.WriteData(data, size)
    net.Send(recipients)
end)

local function canSendHandoffState(ply, target)
    return IsValid(ply) and IsValid(target)
        and (ply.EmuSession == target
            or (ply.EmuHandoffTarget == target and CurTime() < (ply.EmuHandoffUntil or 0)))
end

net.Receive("emu_state_snapshot", function(_, ply)
    local target = net.ReadEntity()
    local rom = net.ReadString()
    local total = net.ReadUInt(24)
    local offset = net.ReadUInt(24)
    local size = net.ReadUInt(16)
    local transfer = stateTransfers[ply]
    local continuing = transfer and transfer.target == target and transfer.rom == rom and offset > 0 and CurTime() - transfer.started <= 120
    if not IsValid(target) or not (continuing or canSendHandoffState(ply, target)) or not isstring(rom) or rom ~= target:GetRomName()
        or total < 1 or total > MAX_STATE_BYTES or size < 1 or size > STATE_CHUNK_BYTES
        or offset >= total or offset + size > total then return end
    local data = net.ReadData(size)
    if not data or #data ~= size then return end
    local key = ply
    if offset == 0 then
        transfer = {target = target, rom = rom, total = total, received = 0, parts = {}, started = CurTime()}
        stateTransfers[key] = transfer
    end
    if not transfer or transfer.rom ~= rom or transfer.total ~= total
        or transfer.target ~= target or offset ~= transfer.received or CurTime() - transfer.started > 120 then
        stateTransfers[key] = nil
        return
    end
    transfer.parts[#transfer.parts + 1] = data
    transfer.received = transfer.received + size
    net.Start("emu_state_upload_ack") net.WriteEntity(target) net.WriteString(rom) net.WriteUInt(transfer.received, 24) net.Send(ply)
    if transfer.received == transfer.total then
        target.EmuHandoffState = {rom = rom, data = table.concat(transfer.parts), time = CurTime()}
        stateTransfers[key] = nil
    end
end)

local function sendDownload(ply)
    local state = stateDownloads[ply]
    if not state or not IsValid(ply) or not IsValid(state.target) or state.target:GetRomName() ~= state.rom then stateDownloads[ply] = nil return end
    local offset = state.offset
    local size = math.min(STATE_CHUNK_BYTES, #state.data - offset)
    state.expected, state.sent = offset + size, CurTime()
    net.Start("emu_state_chunk") net.WriteEntity(state.target) net.WriteString(state.rom)
    net.WriteUInt(#state.data, 24) net.WriteUInt(offset, 24) net.WriteUInt(size, 16)
    net.WriteData(string.sub(state.data, offset + 1, offset + size), size) net.Send(ply)
end
net.Receive("emu_state_download_ack", function(_, ply)
    local target, rom, offset = net.ReadEntity(), net.ReadString(), net.ReadUInt(24)
    local state = stateDownloads[ply]
    if not state or state.target ~= target or state.rom ~= rom or state.expected ~= offset then return end
    state.offset = offset
    if offset == #state.data then stateDownloads[ply] = nil else sendDownload(ply) end
end)
hook.Add("Think", "Emu_StateTransferCleanup", function()
    for ply, state in pairs(stateTransfers) do
        if not IsValid(ply) or not IsValid(state.target) or CurTime() - state.started > 120 then stateTransfers[ply] = nil end
    end
    for ply, state in pairs(stateDownloads) do
        if not IsValid(ply) or not IsValid(state.target) or CurTime() - state.sent > 10 or CurTime() - state.started > 120 then stateDownloads[ply] = nil end
    end
end)

function emu.SendHandoffState(target, ply)
    local state = IsValid(target) and target.EmuHandoffState
    if not state or state.rom ~= target:GetRomName() or #state.data < 1 or #state.data > MAX_STATE_BYTES then return end
    if stateDownloads[ply] then return end
    stateDownloads[ply] = {target = target, rom = state.rom, data = state.data, offset = 0, started = CurTime()}
    sendDownload(ply)
end

local function player2Reply(ply, target, granted)
    net.Start("emu_player2_result")
    net.WriteEntity(IsValid(target) and target or NULL)
    net.WriteBool(granted)
    net.Send(ply)
end

function emu.ReleasePlayer2(ply, notify)
    if not IsValid(ply) then return end
    local target = ply.EmuPlayer2Target
    if IsValid(target) and target.GetPlayer2 and target:GetPlayer2() == ply then target:SetPlayer2(NULL) end
    ply.EmuPlayer2Target = nil
    if notify then player2Reply(ply, target, false) end
end

local function player2Unavailable(ply, target)
    if not IsValid(ply) or not IsValid(target) or not target.IsEmuConsole then return "that is not a console" end
    if not emu.GetSystem(target).player2 then return "this system has no second controller" end
    local owner = target:GetControllingPlayer()
    if not IsValid(owner) then return "nobody is playing it" end
    if owner == ply then return "you are already player one" end
    if not target.GetPlayer2 then return "this console has no second controller slot" end
    if IsValid(target:GetPlayer2()) then return "player two is already taken" end
    if not target.GetPower or not target:GetPower() or not target:GetHasCartridge() then return "the console is off or empty" end
    if not emu.IsNearSetup(ply, target, emu.PlayDistance) then return "you are too far away" end
end

-- Returns granted, and a player-facing reason when refused.
function emu.GrantPlayer2(ply, target)
    local reason = player2Unavailable(ply, target)
    if reason then
        if IsValid(ply) then player2Reply(ply, target, false) end
        return false, reason
    end
    emu.ReleasePlayer2(ply, false)
    target:SetPlayer2(ply)
    ply.EmuPlayer2Target = target
    player2Reply(ply, target, true)
    return true
end

net.Receive("emu_player2_buttons", function(_, ply)
    local target, count = net.ReadEntity(), net.ReadUInt(4)
    if not IsValid(target) or not target.IsEmuConsole or target:GetPlayer2() ~= ply
        or not IsValid(target:GetControllingPlayer()) or count > 12
        or not emu.IsNearSetup(ply, target, emu.PlayDistance) then return end
    local profile, buttons = emu.GetSystem(target), {}
    for _ = 1, count do
        local button = net.ReadString()
        if isstring(button) and profile.buttons and profile.buttons[button] then buttons[#buttons + 1] = button end
    end
    -- Player two's input goes to the session runner, whose client emulates.
    local owner = target:GetControllingPlayer()
    if not IsValid(owner) then return end
    net.Start("emu_player2_buttons")
    net.WriteEntity(target)
    net.WriteUInt(#buttons, 4)
    for _, button in ipairs(buttons) do net.WriteString(button) end
    net.Send(owner)
end)

net.Receive("emu_player2_focus", function(_, ply)
    local target, requested = net.ReadEntity(), net.ReadBool()
    if requested then
        local granted, reason = emu.GrantPlayer2(ply, target)
        if not granted and reason and ply.ChatPrint then ply:ChatPrint("[GEMU] Cannot join as Player 2: " .. reason .. ".") end
    elseif ply.EmuPlayer2Target == target then
        emu.ReleasePlayer2(ply, true)
    end
end)

local function reply(ply, target, granted)
    if not IsValid(ply) then return end
    net.Start("emu_focus_result")
    net.WriteEntity(IsValid(target) and target or NULL)
    net.WriteBool(granted)
    net.Send(ply)
end

local function sessionReply(ply, target, granted)
    if not IsValid(ply) then return end
    net.Start("emu_session_result")
    net.WriteEntity(IsValid(target) and target or NULL)
    net.WriteBool(granted)
    net.Send(ply)
end

-- Releases only the controls; the session and its reservation keep running.
function emu.ReleaseFocus(ply, notify)
    if not IsValid(ply) then return end
    local target = ply.EmuTarget or ply.EmuConsole
    if not target then return end
    ply.EmuTarget, ply.EmuConsole, ply.EmuViewAngles = nil, nil, nil
    ply.EmuNextUse = CurTime() + 0.5
    if notify then reply(ply, target, false) end
end

-- Ends the running session: power off, eject, Stop, disconnect or device loss.
function emu.EndSession(ply, notify)
    if not IsValid(ply) then return end
    local target = ply.EmuSession
    emu.ReleaseFocus(ply, notify)
    ply.EmuSession = nil
    if IsValid(target) then
        -- The closing client may still upload its final state for the next player.
        ply.EmuHandoffTarget, ply.EmuHandoffUntil = target, CurTime() + 8
        if target.GetPlayer2 and IsValid(target:GetPlayer2()) then emu.ReleasePlayer2(target:GetPlayer2(), true) end
        if target.GetControllingPlayer and target:GetControllingPlayer() == ply then target:SetControllingPlayer(NULL) end
        if target.SetSessionPaused then target:SetSessionPaused(false) end
    end
    if notify and target then sessionReply(ply, target, false) end
end

function emu.StartSession(ply, target)
    if not IsValid(ply) or not IsValid(target) then return false end
    if ply.EmuSession == target and emu.IsSessionRunner(ply, target) then
        target.EmuSessionSeen = CurTime()
        return true
    end
    -- A reservation without a live session (a pasted duplicate, for example)
    -- is stale and must not lock the device.
    local runner = emu.GetSessionRunner(target)
    if not emu.IsHandheld(target) and IsValid(runner) and runner ~= ply and runner.EmuSession ~= target then
        target:SetControllingPlayer(NULL)
    end
    if not emu.CanUseTarget(ply, target) then return false end
    if IsValid(ply.EmuSession) and ply.EmuSession ~= target then emu.EndSession(ply, true) end
    ply.EmuSession = target
    target.EmuSessionSeen = CurTime()
    if target.SetControllingPlayer then target:SetControllingPlayer(ply) end
    if target.SetSessionPaused then target:SetSessionPaused(false) end
    emu.SendHandoffState(target, ply)
    return true
end

function emu.ReleaseConsole(console)
    local ply = console:GetControllingPlayer()
    if IsValid(ply) then
        if ply.EmuSession == console then
            emu.EndSession(ply, true)
        elseif (ply.EmuTarget or ply.EmuConsole) == console then
            emu.ReleaseFocus(ply, true)
        end
    end
    console:SetControllingPlayer(NULL)
end

net.Receive("emu_session", function(_, ply)
    local target, active = net.ReadEntity(), net.ReadBool()
    if not active then
        if IsValid(target) and ply.EmuSession == target then emu.EndSession(ply, false) end
        return
    end
    if not IsValid(target) then return end
    if ply.EmuSession == target and emu.IsSessionRunner(ply, target) then
        target.EmuSessionSeen = CurTime() -- Keepalive.
        return
    end
    sessionReply(ply, target, emu.StartSession(ply, target))
end)

net.Receive("emu_session_paused", function(_, ply)
    local target, paused = net.ReadEntity(), net.ReadBool()
    if emu.IsSessionRunner(ply, target) and target.SetSessionPaused then target:SetSessionPaused(paused) end
end)

net.Receive("emu_play_focus", function(_, ply)
    local target, requested = net.ReadEntity(), net.ReadBool()
    -- A release must work even after death, moving away, or disabling the addon.
    if not requested then
        if ply.EmuTarget == target or ply.EmuConsole == target then emu.ReleaseFocus(ply, false) end
        return
    end
    if not emu.CanFocusTarget(ply, target) then reply(ply, target, false) return end
    if ply.EmuSession ~= target and not emu.StartSession(ply, target) then reply(ply, target, false) return end
    emu.ReleaseFocus(ply, false)
    ply.EmuTarget = target
    ply.EmuConsole = target -- Compatibility with existing console/entity integrations.
    ply.EmuViewAngles = ply:EyeAngles()
    ply.EmuNextUse = CurTime() + 0.5
    target.EmuSessionSeen = CurTime()
    reply(ply, target, true)
end)

hook.Add("StartCommand", "Emu_ReserveControls", function(ply, cmd)
    if IsValid(ply.EmuPlayer2Target) then
        cmd:ClearMovement()
        cmd:ClearButtons()
        return
    end
    local target = ply.EmuTarget or ply.EmuConsole
    if not target then return end
    if not emu.CanFocusTarget(ply, target) then emu.ReleaseFocus(ply, true) return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    cmd:SetViewAngles(ply.EmuViewAngles)
end)

local nextCheck = 0
hook.Add("Think", "Emu_ValidateControllers", function()
    if CurTime() < nextCheck then return end
    nextCheck = CurTime() + 0.25
    for _, ply in ipairs(player.GetAll()) do
        local focus = ply.EmuTarget or ply.EmuConsole
        if focus and not emu.CanFocusTarget(ply, focus) then emu.ReleaseFocus(ply, true) end
        local session = ply.EmuSession
        if session and (not emu.IsSessionRunner(ply, session)
            or CurTime() - (session.EmuSessionSeen or 0) > SESSION_TIMEOUT) then
            emu.EndSession(ply, true)
        end
        local player2 = ply.EmuPlayer2Target
        if IsValid(player2) and (not IsValid(player2:GetControllingPlayer())
            or not emu.IsNearSetup(ply, player2, emu.PlayDistance)) then
            emu.ReleasePlayer2(ply, true)
        end
    end
end)
-- Death drops the controls, not the running game.
hook.Add("PlayerDeath", "emu_PlayerCleanup", function(ply) emu.ReleasePlayer2(ply, true) emu.ReleaseFocus(ply, true) end)
hook.Add("PlayerDisconnected", "emu_PlayerDisconnect", function(ply) emu.ReleasePlayer2(ply, false) emu.EndSession(ply, false) end)

print("[gmod-emu] Server module loaded.")
