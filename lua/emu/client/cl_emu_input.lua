-- Explicit, server-approved input for console stations and handheld SWEPs.
if not CLIENT then return end
emu = emu or {}
if emu.ReleaseHardwareInput then emu.ReleaseHardwareInput() end

local state = {focused = false, blocked = {}, actions = {}}
local actionKeys = {KEY_E, KEY_P, KEY_F1, KEY_F5, KEY_F8, KEY_F11, KEY_MINUS, KEY_EQUAL, KEY_M}
local player2State = {target = nil, actions = {}, lastButtons = ""}
function emu.LeavePlayer2()
    if IsValid(player2State.target) then
        net.Start("emu_player2_focus") net.WriteEntity(player2State.target) net.WriteBool(false) net.SendToServer()
    end
    player2State = {target = nil, actions = {}, lastButtons = ""}
end

net.Receive("emu_player2_result", function()
    local target, granted = net.ReadEntity(), net.ReadBool()
    if granted then
        player2State.target, player2State.lastButtons = target, ""
        player2State.blocked = {}
        for key in pairs(emu.GetKeyboardLayout()) do player2State.blocked[key] = input.IsKeyDown(key) end
        player2State.actions[KEY_E] = input.IsKeyDown(KEY_E)
    elseif player2State.target == target then player2State.target, player2State.lastButtons = nil, "" end
end)

net.Receive("emu_player2_buttons", function()
    local target, count = net.ReadEntity(), net.ReadUInt(4)
    local buttons = {}
    for _ = 1, count do buttons[#buttons + 1] = net.ReadString() end
    if target == emu.ActiveTarget and IsValid(emu.ActiveWindow) and IsValid(emu.ActiveWindow.HTML) then
        emu.ActiveWindow.HTML:QueueJavascript("if(window.GModEmulator) GModEmulator.setPlayer2Buttons(" .. util.TableToJSON(buttons) .. ");")
    end
end)

local function pollPlayer2()
    local target = player2State.target
    if not IsValid(target) then return end
    local settingsDown = input.IsKeyDown(KEY_F1)
    if settingsDown and not player2State.actions[KEY_F1] then emu.OpenControls() return end
    player2State.actions[KEY_F1] = settingsDown
    if not system.HasFocus() or gui.IsGameUIVisible() or gui.IsConsoleVisible() or vgui.CursorVisible() then emu.LeavePlayer2() return end
    local buttons, seen = {}, {}
    local profile = emu.GetSystem(target)
    local function add(button)
        if not seen[button] and (not profile.buttons or profile.buttons[button]) then seen[button] = true buttons[#buttons + 1] = button end
    end
    for key, button in pairs(emu.GetKeyboardLayout()) do
        if input.IsKeyDown(key) then
            if not (player2State.blocked or {})[key] then add((profile.buttonAliases or {})[button] or button) end
        elseif player2State.blocked then player2State.blocked[key] = nil end
    end
    if emu.GetGamepadButtons then for _, button in ipairs(emu.GetGamepadButtons(target)) do add(button) end end
    table.sort(buttons)
    local signature = table.concat(buttons, ",")
    if signature ~= player2State.lastButtons then
        net.Start("emu_player2_buttons")
        net.WriteEntity(target)
        net.WriteUInt(#buttons, 4)
        for _, button in ipairs(buttons) do net.WriteString(button) end
        net.SendToServer()
        player2State.lastButtons = signature
    end
    local eDown = input.IsKeyDown(KEY_E)
    if eDown and not player2State.actions[KEY_E] then
        net.Start("emu_player2_focus") net.WriteEntity(target) net.WriteBool(false) net.SendToServer()
    end
    player2State.actions[KEY_E] = eDown
end

-- Shift+Use on another player's console requests the second controller. The
-- client reads Shift directly: the server does not reliably see sprint during Use.
hook.Add("PlayerBindPress", "Emu_JoinPlayer2", function(ply, bind, pressed)
    if not pressed or state.focused or IsValid(player2State.target) or not bind:find("+use", 1, true) then return end
    if not (input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)) then return end
    local console = ply:GetEyeTrace().Entity
    if IsValid(console) and console.IsEmuCRT then console = console:GetLinkedConsole() end
    if not IsValid(console) or not console.IsEmuConsole then return end
    local owner = console:GetControllingPlayer()
    if not IsValid(owner) or owner == ply then return end
    net.Start("emu_player2_focus") net.WriteEntity(console) net.WriteBool(true) net.SendToServer()
    return true -- Handled; do not also send Use to the occupied console.
end)

local function sendButtons(html, buttons)
    if not IsValid(html) then return end
    table.sort(buttons)
    html:QueueJavascript("if(window.GModEmulator) GModEmulator.setHardwareButtons(" ..
        (#buttons == 0 and "[]" or util.TableToJSON(buttons)) .. ");")
end

local function sendFocus(target, requested)
    if not IsValid(target) then return end
    net.Start("emu_play_focus")
    net.WriteEntity(target)
    net.WriteBool(requested)
    net.SendToServer()
end

function emu.ReleaseHardwareInput()
    -- Leaving the controls never pauses; only the player's explicit pause does.
    sendButtons(state.html, {})
    sendFocus(state.target or state.requested, false)
    if IsValid(emu.ActiveWindow) then emu.ActiveWindow.PendingFocus = false end
    if state.viewAngles and IsValid(LocalPlayer()) then LocalPlayer():SetEyeAngles(state.viewAngles) end
    state = {focused = false, blocked = {}, actions = {}}
    emu.Fullscreen = false
end

function emu.GetHardwareContext()
    local target = emu.ActiveTarget or emu.ActiveConsole
    local frame, ply = emu.ActiveWindow, LocalPlayer()
    if not emu.CanFocusTarget(ply, target) then return end
    if not IsValid(frame) or not frame.Ready or not frame.LoadedGame or frame.Error then return end
    if not IsValid(frame.HTML) or frame:IsVisible() then return end
    if not system.HasFocus() or gui.IsGameUIVisible() or gui.IsConsoleVisible() or vgui.CursorVisible() then return end
    return target, frame, frame.HTML, ply
end

function emu.EnterFocus(target)
    local current = emu.GetHardwareContext()
    if not current or current ~= target or state.focused or state.requested then return false end
    state.requested = target
    state.requestTime = RealTime()
    sendFocus(target, true)
    return true
end

net.Receive("emu_focus_result", function()
    local target, granted = net.ReadEntity(), net.ReadBool()
    if not granted then
        if state.target == target or state.requested == target then emu.ReleaseHardwareInput() end
        return
    end
    local current, frame, html, ply = emu.GetHardwareContext()
    if state.requested ~= target or current ~= target then
        sendFocus(target, false)
        return
    end
    state.requested = nil
    state.focused, state.target, state.html = true, target, html
    state.display = not emu.IsHandheld(target) and target:GetLinkedDisplay() or nil
    state.viewAngles = ply:EyeAngles()
    state.zoomDown = input.IsMouseDown(MOUSE_RIGHT)
    local layout
    layout, state.layout = emu.GetKeyboardLayout()
    for key in pairs(layout) do state.blocked[key] = input.IsKeyDown(key) end
    for _, key in ipairs(actionKeys) do state.actions[key] = input.IsKeyDown(key) end
    if frame.PendingFullscreen then emu.Fullscreen = true end
    frame.PendingFullscreen = false
end)

function emu.IsInputFocused(target)
    return state.focused and IsValid(state.target) and (target == nil or state.target == target)
end

local function edge(key)
    local down = input.IsKeyDown(key)
    local pressed = down and not state.actions[key]
    state.actions[key] = down
    return pressed
end

hook.Add("Think", "Emu_InputPolling", function()
    if state.requested and (RealTime() - state.requestTime > 5 or not emu.GetHardwareContext()) then
        emu.ReleaseHardwareInput()
    end
    if not state.focused then pollPlayer2() return end
    local target, _, html = emu.GetHardwareContext()
    if target ~= state.target or not target then emu.ReleaseHardwareInput() return end
    if state.display and target:GetLinkedDisplay() ~= state.display then emu.ReleaseHardwareInput() return end
    if edge(KEY_E) then emu.ReleaseHardwareInput() return end
    if edge(KEY_F1) then emu.OpenControls() return end
    if edge(KEY_P) and emu.TogglePause then emu.TogglePause() end
    if edge(KEY_F5) then emu.QuickSave() end
    if edge(KEY_F8) then emu.QuickLoad() end
    if edge(KEY_F11) then emu.ToggleFullscreen() end
    if edge(KEY_MINUS) then emu.AdjustVolume(-0.05) end
    if edge(KEY_EQUAL) then emu.AdjustVolume(0.05) end
    if edge(KEY_M) then emu.ToggleMute() end
    local zoomDown = input.IsMouseDown(MOUSE_RIGHT)
    if zoomDown and not state.zoomDown and emu.IsHandheld(target) then target.IsZoomed = not target.IsZoomed end
    state.zoomDown = zoomDown

    local layout, selected = emu.GetKeyboardLayout()
    if selected ~= state.layout then
        state.layout = selected
        for key in pairs(layout) do state.blocked[key] = input.IsKeyDown(key) end
    end
    local supported = emu.GetSystem(target).buttons
    local aliases = emu.GetSystem(target).buttonAliases or {}
    local buttons = {}
    for key, button in pairs(layout) do
        button = aliases[button] or button
        if input.IsKeyDown(key) then
            if not state.blocked[key] and (not supported or supported[button]) then buttons[#buttons + 1] = button end
        else
            state.blocked[key] = nil
        end
    end
    -- Native XInput is additive to the selected keyboard layout. The bridge
    -- returns an empty list when its optional DLL is not installed.
    if emu.GetGamepadButtons then
        for _, button in ipairs(emu.GetGamepadButtons(target)) do
            if not supported or supported[button] then buttons[#buttons + 1] = button end
        end
    end
    local unique, seen = {}, {}
    for _, button in ipairs(buttons) do if not seen[button] then seen[button] = true unique[#unique + 1] = button end end
    buttons = unique
    table.sort(buttons)
    local signature = table.concat(buttons, ",")
    if signature ~= state.lastButtons then
        sendButtons(html, buttons)
        state.lastButtons = signature
    end
end)

hook.Add("CreateMove", "Emu_BlockPlayerMovement", function(cmd)
    if not state.focused then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    cmd:SetViewAngles(state.viewAngles)
end)

hook.Add("PlayerBindPress", "Emu_BlockGameBinds", function(_, bind)
    if not state.focused then return end
    if bind:find("messagemode", 1, true) or bind == "toggleconsole" or bind == "screenshot"
        or bind:match("^emu_") then return end
    return true
end)
hook.Add("StartChat", "Emu_ChatOpen", emu.ReleaseHardwareInput)
hook.Add("OnSpawnMenuOpen", "Emu_SpawnMenuOpen", emu.ReleaseHardwareInput)
hook.Add("OnContextMenuOpen", "Emu_ContextMenuOpen", emu.ReleaseHardwareInput)

hook.Add("CalcView", "Emu_SeatedView", function(ply)
    if not state.focused or not IsValid(state.display) then return end
    local display = emu.GetSystem(state.target).display
    local target = state.display:LocalToWorld(display.screenCenter)
    local desired = state.display:LocalToWorld(display.cameraPosition)
    local trace = util.TraceHull({start = target, endpos = desired,
        mins = Vector(-2, -2, -2), maxs = Vector(2, 2, 2),
        filter = {ply, state.target, state.display}, mask = MASK_SOLID})
    local origin = trace.Hit and trace.HitPos + trace.HitNormal * 2 or desired
    return {origin = origin, angles = (target - origin):Angle(), fov = display.cameraFOV, znear = 1}
end)

hook.Add("PreDrawViewModel", "Emu_HideWeapon", function()
    if state.focused and not emu.IsHandheld(state.target) then return true end
end)
hook.Add("HUDShouldDraw", "Emu_HideGameHUD", function(name)
    if not state.focused then return end
    local hidden = {CHudCrosshair=true, CHudHealth=true, CHudBattery=true, CHudAmmo=true,
        CHudSecondaryAmmo=true, CHudWeaponSelection=true, CHudSuitPower=true, CHudDamageIndicator=true}
    if hidden[name] then return false end
end)

surface.CreateFont("Emu_HUDHint", {font = "Arial", size = 16, weight = 700})
hook.Add("HUDPaint", "Emu_FocusHUDHint", function()
    if not state.focused then return end
    local w, h = ScrW(), ScrH()
    if emu.Fullscreen then
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 0, w, h)
        emu.DrawHTMLScreen(state.html, 0, 0, w, h, false, emu.GetSystem(state.target).aspectRatio)
    end
    local boxW = math.min(w - 24, 850)
    local x, y = (w - boxW) / 2, h - 70
    draw.RoundedBox(8, x, y, boxW, 56, Color(15, 17, 26, 230))
    local paused = IsValid(emu.ActiveWindow) and emu.ActiveWindow.Paused
    draw.SimpleText(state.target:GetGameTitle() .. "  |  " .. (paused and "PAUSED" or "CUSTOM CONTROLS") ..
        "  |  Volume " .. math.Round(GetConVar("emu_volume"):GetFloat() * 100) .. "%",
        "Emu_HUDHint", x + 12, y + 8, Color(165, 180, 252))
    draw.SimpleText("E: Leave   P: " .. (paused and "Resume" or "Pause") .. "   F1: Controls   F5/F8: Save/Load   F11: Fullscreen   -/=: Volume   M: Mute",
        "DermaDefaultBold", x + 12, y + 32, color_white)
end)

print("[gmod-emu] Hardware input router loaded.")
