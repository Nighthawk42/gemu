-- Client Emulator GUI and DHTML Session Management
if not CLIENT then return end

emu = emu or {}
local handoffStates = {}

local function applyHandoffState(target)
    local state = handoffStates[target]
    local frame = emu.ActiveWindow
    if not state or not state.data or not IsValid(frame) or emu.ActiveTarget ~= target then return end
    if not frame.Ready or not IsValid(frame.HTML) then
        frame.PendingHandoffState = state
        return
    end
    handoffStates[target] = nil
    frame.PendingHandoffState = nil
    frame.HTML:QueueJavascript("if(window.GModEmulator && GModEmulator.applyHandoffState) GModEmulator.applyHandoffState('" .. util.Base64Encode(state.data) .. "');")
end

net.Receive("emu_state_chunk", function()
    local target = net.ReadEntity()
    local rom = net.ReadString()
    local total = net.ReadUInt(24)
    local offset = net.ReadUInt(24)
    local size = net.ReadUInt(16)
    if not IsValid(target) or total < 1 or total > 4 * 1024 * 1024
        or offset >= total or size < 1 or size > 8192 or offset + size > total
        or target:GetRomName() ~= rom then return end
    local data = net.ReadData(size)
    if not data or #data ~= size then return end
    local state = handoffStates[target]
    if offset == 0 then state = {rom = rom, total = total, received = 0, parts = {}} handoffStates[target] = state end
    if not state or state.rom ~= rom or state.total ~= total or offset ~= state.received then
        handoffStates[target] = nil
        return
    end
    state.parts[#state.parts + 1] = data
    state.received = state.received + size
    net.Start("emu_state_download_ack") net.WriteEntity(target) net.WriteString(rom) net.WriteUInt(state.received, 24) net.SendToServer()
    if state.received == state.total then
        handoffStates[target] = {rom = rom, data = table.concat(state.parts)}
        applyHandoffState(target)
    end
end)

local BG = Color(24, 25, 38)
local HEADER = Color(30, 32, 48)
local TEXT = Color(241, 245, 249)

function emu.ApplyVolume()
    local frame = emu.ActiveWindow
    if IsValid(frame) and IsValid(frame.HTML) and frame.Ready then
        frame.HTML:QueueJavascript("if(window.GModEmulator) GModEmulator.setVolume(" ..
            math.Clamp(GetConVar("emu_volume"):GetFloat(), 0, 1) .. ");")
    end
end

function emu.AdjustVolume(delta)
    RunConsoleCommand("emu_volume", tostring(math.Clamp(GetConVar("emu_volume"):GetFloat() + delta, 0, 1)))
end

local unmutedVolume = 0.8
function emu.ToggleMute()
    local volume = GetConVar("emu_volume"):GetFloat()
    if volume > 0 then unmutedVolume = volume end
    RunConsoleCommand("emu_volume", tostring(volume > 0 and 0 or unmutedVolume))
end
cvars.AddChangeCallback("emu_volume", emu.ApplyVolume, "Emu_Volume")
concommand.Add("emu_volume_up", function() emu.AdjustVolume(0.05) end)
concommand.Add("emu_volume_down", function() emu.AdjustVolume(-0.05) end)
concommand.Add("emu_mute", emu.ToggleMute)

local function browserAction(method)
    local frame = emu.ActiveWindow
    if IsValid(frame) and IsValid(frame.HTML) and frame.Ready then
        frame.HTML:QueueJavascript("if(window.GModEmulator && GModEmulator." .. method .. ") GModEmulator." .. method .. "();")
    end
end

function emu.QuickSave() browserAction("quickSave") end
function emu.QuickLoad() browserAction("quickLoad") end
function emu.ResetGame() browserAction("reset") end
concommand.Add("emu_save", emu.QuickSave)
concommand.Add("emu_load", emu.QuickLoad)
concommand.Add("emu_reset", emu.ResetGame)

-- Only the player pauses; leaving play, closing the window or walking away does not.
function emu.TogglePause() browserAction("togglePause") end
concommand.Add("emu_pause", function() emu.TogglePause() end)
concommand.Add("emu_web_status", function()
    local frame = emu.ActiveWindow
    if not IsValid(frame) or not IsValid(frame.HTML) then print("[GEMU web] No active emulator session.") return end
    print("[GEMU web] Lua: ready=" .. tostring(frame.Ready) .. " loaded=" .. tostring(frame.LoadedGame)
        .. " paused=" .. tostring(frame.Paused) .. " session granted=" .. tostring(frame.SessionGranted))
    frame.HTML:AddFunction("gemuProbe", "web", function(report) print("[GEMU web] Page: " .. tostring(report):sub(1, 2000)) end)
    frame.HTML:QueueJavascript("gemuProbe.web(window.GModEmulator && GModEmulator.status ? JSON.stringify(GModEmulator.status()) : 'bridge missing or outdated (no status())');")
end)

-- The server reserves a device for the client that runs its emulator until
-- the session explicitly ends. Keepalives prove the browser still exists.
local function sendSession(target, active)
    if not IsValid(target) then return end
    net.Start("emu_session") net.WriteEntity(target) net.WriteBool(active) net.SendToServer()
end

net.Receive("emu_session_result", function()
    local target, granted = net.ReadEntity(), net.ReadBool()
    local frame = emu.ActiveWindow
    if not IsValid(frame) or emu.ActiveTarget ~= target then return end
    if granted then frame.SessionGranted = true return end
    if not frame.SessionGranted then
        notification.AddLegacy("GEMU: Another player is running this device.", NOTIFY_ERROR, 5)
    end
    emu.StopSession()
end)

local function setPresentation(frame, screen)
    if not IsValid(frame.HTML) then return end
    frame.HTML:QueueJavascript("document.body.classList." .. (screen and "add" or "remove") ..
        "('mode-screen'); document.body.classList." .. (screen and "add" or "remove") .. "('emu-hardware');")
end

local function encode(str)
    return (tostring(str or ""):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- Lua values injected into QueueJavascript must be escaped, never spliced raw.
local jsEscapes = {["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
local function jsStringLiteral(value)
    return '"' .. tostring(value or ""):gsub("[%c\\\"]", function(c)
        return jsEscapes[c] or string.format("\\u%04x", string.byte(c))
    end) .. '"'
end

function emu.BuildURL(base, title, url, name, minimal, systemId)
    local path, query = base:match("^([^?]+)%??(.*)$")
    path = path or base
    if not path:match("/$") and not path:match("%.html?$") then
        path = path .. "/"
    end
    local params = {}
    if query and query ~= "" then params[#params + 1] = query end
    if minimal then params[#params + 1] = "mode=screen" end
    params[#params + 1] = "storage=gmod"
    -- Legacy URL argument retained for compatibility; all ROMs use the shared host.
    if name and name ~= "" then params[#params + 1] = "rom=" .. encode(name) end
    if title and title ~= "" then params[#params + 1] = "game=" .. encode(title) end
    params[#params + 1] = "system=" .. encode(systemId or "snes")
    return path .. (#params > 0 and ("?" .. table.concat(params, "&")) or "")
end

function emu.StowWindow()
    local frame = emu.ActiveWindow
    if not IsValid(frame) then return end
    local html = frame.HTML
    if IsValid(html) then
        html:SetParent(vgui.GetWorldPanel())
        html:SetPos(0, 0)
        local profile = frame.Profile or emu.Systems.snes
        html:SetSize(profile.browserWidth or 640, profile.browserHeight or 480)
        html:SetPaintedManually(true)
        html:SetMouseInputEnabled(false)
        html:SetKeyboardInputEnabled(false)
        html:SetVisible(true)
        setPresentation(frame, true)
    end
    frame:SetMouseInputEnabled(false)
    frame:SetKeyboardInputEnabled(false)
    frame:SetVisible(false)
end

function emu.StopSession()
    local frame, target = emu.ActiveWindow, emu.ActiveTarget
    if emu.ReleaseHardwareInput then emu.ReleaseHardwareInput() end
    emu.ActiveWindow = nil
    emu.ActiveTarget = nil
    emu.ActiveConsole = nil
    if not IsValid(frame) then return end
    sendSession(target, false)
    local html = frame.HTML
    if not IsValid(html) or not frame.Ready then
        if IsValid(html) then html:Remove() end
        frame:Remove()
        return
    end
    frame.Closing = true
    emu.ClosingSaveFrames = emu.ClosingSaveFrames or {}
    emu.ClosingSaveFrames[frame] = true
    frame:SetVisible(false)
    html:SetParent(vgui.GetWorldPanel())
    html:SetPaintedManually(true)
    html:SetMouseInputEnabled(false)
    html:SetKeyboardInputEnabled(false)
    local function finish(ok, message)
        emu.ClosingSaveFrames[frame] = nil
        if not IsValid(frame) then return end
        if not ok then notification.AddLegacy("GEMU final save failed: " .. tostring(message), NOTIFY_ERROR, 10) end
        if IsValid(html) then html:Remove() end
        frame:Remove()
    end
    html:AddFunction("gmod", "shutdownComplete", finish)
    -- The final snapshot lets the next player resume exactly where this session ended.
    html:QueueJavascript([[if(window.GModEmulator) {
        if (GModEmulator.snapshotForHandoff) GModEmulator.snapshotForHandoff();
        Promise.resolve(GModEmulator.shutdown()).then(function(ok) {
            gmod.shutdownComplete(ok !== false, GModEmulator.saves.lastError || '');
        }).catch(function(err) { gmod.shutdownComplete(false, String(err)); });
    } else { gmod.shutdownComplete(false, 'Browser bridge unavailable'); }]])
    timer.Simple(6, function() if IsValid(frame) then finish(false, "Browser did not confirm the final save; previous saves remain on disk") end end)
end

local function showWindow(frame)
    emu.ReleaseHardwareInput()
    local html = frame.HTML

    frame:SetVisible(true)
    frame:MakePopup()
    if IsValid(html) then
        html:SetParent(frame)
        html:SetPaintedManually(false)
        html:SetMouseInputEnabled(true)
        html:SetKeyboardInputEnabled(true)
        setPresentation(frame, false)
        frame:InvalidateLayout(true)
        html:RequestFocus()
    end
end

function emu.StartPlay(fullscreen)
    local frame = emu.ActiveWindow
    if not IsValid(frame) then return end
    emu.StowWindow()
    frame.PendingFocus = true
    frame.PendingFullscreen = fullscreen == true
end

function emu.ToggleFullscreen()
    if emu.IsInputFocused() then
        emu.Fullscreen = not emu.Fullscreen
    else
        emu.StartPlay(true)
    end
end
concommand.Add("emu_fullscreen", emu.ToggleFullscreen)
concommand.Add("emu_leave", function() emu.ReleaseHardwareInput() end)

function emu.BindBrowserCallbacks(frame, target)
    if not IsValid(frame) or not IsValid(frame.HTML) then return end
    local html = frame.HTML
    emu.BindSaveStorage(frame, html)

    local function active() return IsValid(frame) and emu.ActiveWindow == frame end
    html:AddFunction("gmod", "powerOff", function() if active() then emu.RequestPowerOff() end end)
    html:AddFunction("gmod", "exportSave", function(data)
        if not active() or not isstring(data) or #data > 8 * 1024 * 1024 + 4096 then return end
        local dir="emu/saves/" .. frame.Profile.id
        file.CreateDir(dir)
        local name=string.gsub(frame.RomName,"[^%w_%-]","_") .. "_" .. os.time() .. "_" .. util.CRC(data) .. ".json"
        file.Write(dir .. "/" .. name,data)
        if file.Read(dir .. "/" .. name,"DATA") ~= data then
            notification.AddLegacy("GEMU export failed; check free disk space", NOTIFY_ERROR, 8) return
        end
        notification.AddLegacy("Saved to garrysmod/data/" .. dir .. "/" .. name, NOTIFY_GENERIC, 8)
    end)
    html:AddFunction("gmod", "importSave", function()
        if not active() then return end
        local dir="emu/saves/" .. frame.Profile.id
        local files=file.Find(dir .. "/*.json","DATA")
        local menu=DermaMenu()
        for _,name in ipairs(files) do
            menu:AddOption(name,function()
                if not active() then return end
                if file.Size(dir .. "/" .. name,"DATA") > 8*1024*1024+4096 then
                    notification.AddLegacy("GEMU save file is too large",NOTIFY_ERROR,8) return
                end
                local data=file.Read(dir .. "/" .. name,"DATA")
                if data then html:QueueJavascript("if(window.GModEmulator && GModEmulator.saves) GModEmulator.saves.importFile(" .. jsStringLiteral(data) .. ");") end
            end)
        end
        if #files==0 then menu:AddOption("No exported saves in " .. dir) end
        menu:Open()
    end)
    html:AddFunction("gmod", "closeMenu", function() if active() then emu.StartPlay(false) end end)
    html:AddFunction("gmod", "configureControls", function() if active() then emu.OpenControls() end end)
    html:AddFunction("gmod", "fullscreen", function() if active() then emu.StartPlay(true) end end)
    html:AddFunction("gmod", "onVolume", function(volume)
        if active() then
            RunConsoleCommand("emu_volume", tostring(math.Clamp(tonumber(volume) or 0.8, 0, 1)))
        end
    end)
    html:AddFunction("gmod", "onVideoFrame", function(data)
        if active() and emu.SendVideoFrame then emu.SendVideoFrame(target, data) end
    end)
    html:AddFunction("gmod", "onAudioFrame", function(data, sampleRate)
        if active() and emu.SendAudioFrame then emu.SendAudioFrame(target, data, sampleRate) end
    end)
    html:AddFunction("gmod", "onStateSnapshot", function(data)
        if (active() or frame.Closing) and emu.SendHandoffState then
            emu.SendHandoffState(target, frame.RomName, data)
        end
    end)
    html:AddFunction("gmod", "onPauseChanged", function(paused)
        if not active() then return end
        frame.Paused = paused == true
        net.Start("emu_session_paused") net.WriteEntity(target) net.WriteBool(frame.Paused) net.SendToServer()
    end)
    html:AddFunction("gmod", "onReady", function()
        if not IsValid(frame) or emu.ActiveWindow ~= frame then return end
        frame.Ready = true
        frame.Error = nil
        emu.ApplyVolume()
        applyHandoffState(target)
        setPresentation(frame, not frame:IsVisible())
        -- The game runs as soon as it boots; it pauses only when the player asks.
        html:QueueJavascript("if(window.GModEmulator) { GModEmulator.configureHardware(); }")
        print("[gmod-emu] Emulator core ready.")
    end)
    html:AddFunction("gmod", "onGameLoaded", function(title)
        if active() then
            frame.LoadedGame = tostring(title)
            frame.Error = nil
            print("[gmod-emu] Loaded game: " .. frame.LoadedGame)
        end
    end)
    html:AddFunction("gmod", "onError", function(msg)
        if active() then
            frame.Error = tostring(msg)
            frame.PendingFocus = false
            emu.ReleaseHardwareInput()
            showWindow(frame)
            print("[gmod-emu] Browser error: " .. tostring(msg))
        end
    end)

    -- Check if already initialized
    html:QueueJavascript([[
        (function() {
            if (window.GModEmulator && window.GModEmulator.isReady) {
                gmod.onReady();
                var game = window.GModEmulator.getLoadedGame();
                if (game) gmod.onGameLoaded(game);
            }
        })();
    ]])
end

function emu.OpenWindow(target, hardwareOnly)
    local enabled = GetConVar("emu_sv_enabled")
    if enabled and not enabled:GetBool() then return end

    if not emu.CanUseTarget(LocalPlayer(), target, true) then return end
    -- There is no default host: each server supplies its own frontend and ROMs.
    if string.Trim(GetConVar("emu_url"):GetString()) == "" then
        notification.AddLegacy("GEMU: this server has not set emu_url (see cfg/gemu.cfg).", NOTIFY_ERROR, 6)
        return
    end

    local gameTitle, romName, romUrl = emu.GetTargetRom(target)
    local profile = emu.GetSystem(target)
    if romName == "" and romUrl == "" then
        LocalPlayer():ChatPrint("[GEMU] Set the blank cartridge's ROM filename in its context-menu Edit Properties before inserting it.")
        return
    end

    local frame = emu.ActiveWindow
    if IsValid(frame) and frame.Profile.id == profile.id and emu.ActiveTarget == target and frame.RomName == romName and frame.RomUrl == romUrl then
        if hardwareOnly then
            emu.StartPlay(false)
        else
            showWindow(frame)
        end
        return frame
    end

    emu.StopSession()

    local scale = GetConVar("emu_scale"):GetFloat()
    local winW = math.Clamp(680 * scale, 512, ScrW() - 32)
    local winH = math.Clamp(540 * scale, 480, ScrH() - 32)

    frame = vgui.Create("DFrame")
    frame:SetSize(winW, winH)
    frame:Center()
    frame:SetTitle("")
    frame:SetSizable(true)
    frame:ShowCloseButton(false)
    frame:SetDeleteOnClose(false)
    frame.GameTitle = gameTitle
    frame.RomName = romName
    frame.RomUrl = romUrl
    frame.Profile = profile
    frame.Display = not emu.IsHandheld(target) and target:GetLinkedDisplay() or nil
    frame.BootDeadline = RealTime() + 20
    frame.PowerDeadline = RealTime() + 1
    emu.ActiveWindow = frame
    emu.ActiveTarget = target
    emu.ActiveConsole = target.IsEmuConsole and target or nil
    frame.SessionSeen = RealTime()
    sendSession(target, true)

    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, BG)
        draw.RoundedBoxEx(8, 0, 0, w, 40, HEADER, true, true, false, false)
        local label = string.upper(profile.id)
        draw.SimpleText(self.Error and (label .. " | Unable to start (see console)") or (label .. "  |  " .. (self.GameTitle or profile.name)),
            "DermaDefaultBold", 14, 20, self.Error and Color(255, 120, 120) or TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(110, 26)
    btnClose:SetText("Return to Game")
    btnClose.DoClick = function() emu.StartPlay(false) end

    local btnFull = vgui.Create("DButton", frame)
    btnFull:SetSize(90, 26)
    btnFull:SetText("Fullscreen")
    btnFull.DoClick = function() emu.StartPlay(true) end

    local btnStop = vgui.Create("DButton", frame)
    btnStop:SetSize(50, 26)
    btnStop:SetText("Stop")
    btnStop.DoClick = emu.StopSession

    local html = vgui.Create("DHTML", frame)
    frame.HTML = html
    frame.OnRemove = function()
        if IsValid(html) then html:Remove() end
        if emu.ActiveWindow == frame then
            emu.ReleaseHardwareInput()
            sendSession(target, false)
            emu.ActiveWindow, emu.ActiveTarget, emu.ActiveConsole = nil, nil, nil
        end
    end

    frame.PerformLayout = function(self, w, h)
        btnClose:SetPos(w - 118, 7)
        btnStop:SetPos(w - 174, 7)
        btnFull:SetPos(w - 270, 7)
        if IsValid(html) and html:GetParent() == self then
            html:SetPos(6, 44)
            html:SetSize(w - 12, h - 50)
        end
    end

    html.OnDocumentReady = function(self, url)
        emu.BindBrowserCallbacks(frame, target)
    end

    local base = string.Trim(GetConVar("emu_url"):GetString())
    local full = emu.BuildURL(base, gameTitle, romUrl, romName, true, profile.id)

    html:OpenURL(full)

    if hardwareOnly then
        emu.StartPlay(false)
    else
        showWindow(frame)
    end

    return frame
end

-- Network receiver to open UI from server
net.Receive("emu_open_ui", function()
    local target = net.ReadEntity()
    local hardwareOnly = net.ReadBool()
    if IsValid(target) then
        emu.OpenWindow(target, hardwareOnly)
    end
end)

-- Bind focus to browser readiness and the physical console's entire lifecycle.
hook.Add("Think", "Emu_SessionLifecycle", function()
    local frame, target = emu.ActiveWindow, emu.ActiveTarget or emu.ActiveConsole
    if not IsValid(frame) then return end
    local romName, romUrl
    if IsValid(target) then
        local ignored
        ignored, romName, romUrl = emu.GetTargetRom(target)
    end
    local displayChanged = IsValid(target) and not emu.IsHandheld(target)
        and frame.Display ~= target:GetLinkedDisplay()
    -- Distance, death and closed windows never stop a running game.
    if not emu.CanKeepSession(LocalPlayer(), target, RealTime() < frame.PowerDeadline) or displayChanged
        or (IsValid(target) and frame.Profile.id ~= emu.GetSystem(target).id)
        or frame.RomName ~= romName or frame.RomUrl ~= romUrl then
        emu.StopSession() return
    end
    if RealTime() - (frame.SessionSeen or 0) > 5 then
        frame.SessionSeen = RealTime()
        sendSession(target, true)
    end
    if not frame.Ready and not frame.Error and RealTime() > frame.BootDeadline then
        frame.Error = "Emulator startup timed out. Check emu_url and ROM availability."
        emu.ReleaseHardwareInput()
        showWindow(frame)
        print("[gmod-emu] " .. frame.Error)
    end
    if frame.PendingFocus and (not system.HasFocus() or gui.IsGameUIVisible() or gui.IsConsoleVisible()) then
        frame.PendingFocus, frame.PendingFullscreen = false, false
    end
    if frame.PendingFocus and emu.GetHardwareContext() then
        frame.PendingFocus = false
        emu.EnterFocus(target)
    end
end)

concommand.Add("emu_menu", function()
    local target = emu.ActiveTarget or emu.ActiveConsole
    if IsValid(target) then
        emu.OpenWindow(target, false)
    end
end)

local function openHandheld()
    local weapon = LocalPlayer():GetActiveWeapon()
    if IsValid(weapon) and weapon.IsEmuHandheld then emu.OpenWindow(weapon, false) end
end
concommand.Add("emu_handheld", openHandheld)

print("[gmod-emu] Client GUI module loaded.")
