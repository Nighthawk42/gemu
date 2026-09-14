-- Optional native XInput bridge. The addon remains usable with keyboard input
-- when gmcl_gemu_input_win64.dll is not installed.
if not CLIENT then return end
emu = emu or {}

local native
local ok, loaded = pcall(require, "gemu_input")
if ok and type(loaded) == "table" then native = loaded end
if not native and type(gemu_input) == "table" then native = gemu_input end

CreateClientConVar("emu_gamepad_slot", "0", true, false,
    "XInput controller slot (0-3)", 0, 3)
CreateClientConVar("emu_gamepad_deadzone", "0.24", true, false,
    "XInput stick deadzone", 0, 0.95)
CreateClientConVar("emu_gamepad_backend", "auto", true, false, "auto, xinput, or directinput")
CreateClientConVar("emu_gamepad_device", "", true, false, "DirectInput instance ID; empty selects first device")
local directDefaults = {x=1,a=2,b=3,y=4,l=5,r=6,select=9,start=10}
for action, number in pairs(directDefaults) do
    CreateClientConVar("emu_pad_" .. action, tostring(number), true, false, "DirectInput button for " .. action .. "; 0 unbinds", 0, 128)
end
local function readState(slot)
    local backend = GetConVar("emu_gamepad_backend"):GetString()
    if backend ~= "directinput" then
        local state = native.get_state(slot)
        state.backend = "xinput"
        if state.connected or backend == "xinput" then return state end
    end
    if native.get_direct_state then return native.get_direct_state(GetConVar("emu_gamepad_device"):GetString()) end
    return {connected=false,backend="directinput"}
end
function emu.GetDirectInputDevices()
    if not native or not native.get_devices then return {} end
    local ok, devices = pcall(native.get_devices)
    return ok and type(devices) == "table" and devices or {}
end

local cached = {slot = -1, target = nil, connected = false, buttons = {}, sampled = 0}
local warned = false
local statusAt, statusText = 0, "Checking controller..."
function emu.GetGamepadStatus()
    if not native or type(native.get_state) ~= "function" then return "XInput module not loaded (optional DLL required)" end
    if RealTime() >= statusAt then
        statusAt = RealTime() + 0.5
        local slot = math.Clamp(GetConVar("emu_gamepad_slot"):GetInt(), 0, 3)
        local ok, state = pcall(readState, slot)
        statusText = "Module loaded — " .. (ok and tostring(state.backend) or "poll error") .. ((ok and state.connected) and " connected" or " disconnected")
        if not native.get_direct_state then statusText = statusText .. " (older DLL: XInput only)" end
    end
    return statusText
end

local function addButton(result, seen, button)
    if button and not seen[button] then
        seen[button] = true
        result[#result + 1] = button
    end
end

local function axis(result, seen, value, negative, positive, deadzone)
    value = tonumber(value) or 0
    if value <= -deadzone then addButton(result, seen, negative) end
    if value >= deadzone then addButton(result, seen, positive) end
end

local function bitSet(value, flag)
    return bit.band(value, flag) ~= 0
end

local function mapState(target, state)
    local result, seen = {}, {}
    local buttons = tonumber(state.buttons) or 0
    local deadzone = math.Clamp(GetConVar("emu_gamepad_deadzone"):GetFloat(), 0, 0.95)
    local system = emu.GetSystem(target)
    local id = system and system.id or ""

    if state.backend == "directinput" then
        axis(result, seen, state.left_stick_y, "down", "up", math.max(0.05, deadzone))
        axis(result, seen, state.left_stick_x, "left", "right", math.max(0.05, deadzone))
        local pov = tonumber(state.pov) or -1
        if pov >= 0 then
            if pov >= 31500 or pov <= 4500 then addButton(result,seen,"up") end
            if pov >= 4500 and pov <= 13500 then addButton(result,seen,"right") end
            if pov >= 13500 and pov <= 22500 then addButton(result,seen,"down") end
            if pov >= 22500 and pov <= 31500 then addButton(result,seen,"left") end
        end
        local aliases = system and system.buttonAliases or {}
        for action in pairs(directDefaults) do
            local number = GetConVar("emu_pad_" .. action):GetInt()
            if number > 0 and (state.raw_buttons or {})[number] then addButton(result,seen,aliases[action] or action) end
        end
        table.sort(result)
        return result
    end

    if bitSet(buttons, 0x0001) then addButton(result, seen, "up") end
    if bitSet(buttons, 0x0002) then addButton(result, seen, "down") end
    if bitSet(buttons, 0x0004) then addButton(result, seen, "left") end
    if bitSet(buttons, 0x0008) then addButton(result, seen, "right") end
    axis(result, seen, state.left_stick_y, "down", "up", deadzone)
    axis(result, seen, state.left_stick_x, "left", "right", deadzone)

    if id == "genesis" then
        if bitSet(buttons, 0x1000) then addButton(result, seen, "a") end
        if bitSet(buttons, 0x2000) then addButton(result, seen, "b") end
        if bitSet(buttons, 0x4000) then addButton(result, seen, "x") end
        if bitSet(buttons, 0x8000) then addButton(result, seen, "c") end
        if bitSet(buttons, 0x0100) or (tonumber(state.left_trigger) or 0) >= 0.5 then addButton(result, seen, "y") end
        if bitSet(buttons, 0x0200) or (tonumber(state.right_trigger) or 0) >= 0.5 then addButton(result, seen, "z") end
        -- The shared adapter names Genesis' Mode button "select" so its
        -- existing select->MODE alias remains the single translation point.
        if bitSet(buttons, 0x0020) then addButton(result, seen, "select") end
    else
        if bitSet(buttons, 0x1000) then addButton(result, seen, "a") end
        if bitSet(buttons, 0x2000) then addButton(result, seen, "b") end
        if bitSet(buttons, 0x4000) then addButton(result, seen, "x") end
        if bitSet(buttons, 0x8000) then addButton(result, seen, "y") end
        if bitSet(buttons, 0x0100) or (tonumber(state.left_trigger) or 0) >= 0.5 then addButton(result, seen, "l") end
        if bitSet(buttons, 0x0200) or (tonumber(state.right_trigger) or 0) >= 0.5 then addButton(result, seen, "r") end
        if bitSet(buttons, 0x0020) then addButton(result, seen, "select") end
    end
    if bitSet(buttons, 0x0010) then addButton(result, seen, "start") end
    table.sort(result)
    return result
end

function emu.GetGamepadButtons(target)
    if not native or type(native.get_state) ~= "function" then
        if not warned then
            warned = true
            print("[gmod-emu] gmcl_gemu_input_win64.dll not found; using keyboard input only.")
        end
        return {}
    end

    local slot = math.Clamp(GetConVar("emu_gamepad_slot"):GetInt(), 0, 3)
    local now = RealTime()
    local interval = cached.connected and (1 / 60) or 0.25
    local selection = GetConVar("emu_gamepad_backend"):GetString() .. GetConVar("emu_gamepad_device"):GetString()
    if cached.selection ~= selection or cached.slot ~= slot or cached.target ~= target or now - cached.sampled >= interval then
        cached.selection = selection
        local success, state = pcall(readState, slot)
        if success and type(state) == "table" then
            cached.slot, cached.target, cached.connected, cached.sampled = slot, target, state.connected == true, now
            cached.buttons = cached.connected and mapState(target, state) or {}
        else
            cached.slot, cached.target, cached.connected, cached.sampled, cached.buttons = slot, target, false, now, {}
        end
    end
    return cached.buttons
end
