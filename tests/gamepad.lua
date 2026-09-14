-- Focused XInput-to-system mapping contract test.
local count = 0
local function check(value, message)
    assert(value, message)
    count = count + 1
end

CLIENT, SERVER = true, false
local now = 10
function RealTime() return now end
function math.Clamp(value, low, high) return math.max(low, math.min(high, value)) end

local cvars = {
    emu_gamepad_slot = {GetInt = function() return 0 end},
    emu_gamepad_deadzone = {GetFloat = function() return 0.24 end}
}
function CreateClientConVar(name, default)
    cvars[name] = cvars[name] or {GetString = function() return default end, GetInt = function() return tonumber(default) or 0 end, GetFloat = function() return tonumber(default) or 0 end}
    return cvars[name]
end
function GetConVar(name) return cvars[name] end

local nativeState = {
    connected = true, buttons = 0x1000 + 0x0100 + 0x0010 + 0x0001,
    left_stick_x = 0.8, left_stick_y = 0, left_trigger = 0.7, right_trigger = 0
}
local native = {get_state = function() return nativeState end}
local originalRequire = require
function require(name)
    if name == "gemu_input" then return native end
    return originalRequire(name)
end

emu = {GetSystem = function(target) return {id = target.system, buttonAliases = target.system == 'genesis' and {b='a',a='b',y='c',l='y',r='z'} or {}} end}
dofile("lua/emu/client/cl_emu_gamepad.lua")

local snes = {system = "snes"}
local buttons = emu.GetGamepadButtons(snes)
local seen = {}
for _, button in ipairs(buttons) do seen[button] = true end
check(seen.a and seen.l and seen.start and seen.up and seen.right, "SNES mapping should include face, shoulder, d-pad and stick")

now = now + 1
nativeState.buttons = 0x8000 + 0x0200 + 0x0020
nativeState.left_stick_x, nativeState.left_stick_y = 0, -0.8
local genesis = {system = "genesis"}
buttons = emu.GetGamepadButtons(genesis)
seen = {}
for _, button in ipairs(buttons) do seen[button] = true end
check(seen.c and seen.z and seen.select and seen.down, "Genesis mapping should use C/Z/Mode aliases")
check(not seen.l and not seen.r, "Genesis mapping should not leak SNES shoulder names")

now = now + 1
nativeState.connected = false
buttons = emu.GetGamepadButtons(genesis)
check(#buttons == 0, "Disconnected controller should clear mapped buttons")

native.get_direct_state = function() return {connected=true,backend='directinput',left_stick_x=0,left_stick_y=0,pov=4500,raw_buttons={[1]=true,[3]=true,[5]=true,[7]=true,[9]=true,[10]=true}} end
now = now + 1
buttons = emu.GetGamepadButtons(snes)
seen = {} for _, button in ipairs(buttons) do seen[button]=true end
check(seen.x and seen.b and seen.l and seen.select and seen.start and seen.up and seen.right and #buttons==7, 'Generic pad defaults and diagonal POV; button 7 stays unmapped')
now = now + 1
buttons = emu.GetGamepadButtons(genesis)
seen = {} for _, button in ipairs(buttons) do seen[button]=true end
check(seen.a and seen.y and not seen.l, 'DirectInput Genesis aliases')
cvars.emu_pad_a = {GetInt=function() return 7 end}
now = now + 1
buttons=emu.GetGamepadButtons(snes)
seen={} for _,button in ipairs(buttons) do seen[button]=true end
check(seen.a, 'DirectInput custom button number')
native.get_direct_state=function() return {connected=false,backend='directinput'} end
now=now+1
check(#emu.GetGamepadButtons(snes)==0,'DirectInput disconnect clears all buttons')
print("All " .. count .. " gamepad mapping tests PASSED!")
