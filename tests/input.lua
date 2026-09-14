-- Standalone LuaJIT Input Router Tests for gmod-emu
-- Run from repository root: luajit tests/input.lua

local count = 0
local function check(cond, msg)
    assert(cond, msg or "Assertion failed")
    count = count + 1
end

CLIENT, SERVER = true, false
NULL = { valid = false }
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function AddCSLuaFile() end
function include() end
function Color(...) return {...} end
function Vector(...) return { DistToSqr = function() return 0 end } end
function Angle(...) return {...} end
function ScrW() return 1920 end
function ScrH() return 1080 end
function RealTime() return 10 end
function CurTime() return 10 end

local keyDownState = {}
local layout = "arrows"
local volume = 0.8
local hasFocus, cursorVisible = true, false
function GetConVar(name) return {
    GetBool = function() return true end,
    GetString = function() return layout end,
    GetFloat = function() return volume end
} end
system = {HasFocus = function() return hasFocus end}
input = {
    IsMouseDown = function() return false end,
    IsKeyDown = function(k) return keyDownState[k] == true end
}

gui = {
    IsGameUIVisible = function() return false end,
    IsConsoleVisible = function() return false end
}

vgui = {
    CursorVisible = function() return cursorVisible end
}

draw = { RoundedBox = function() end, SimpleText = function() end }
surface = { CreateFont = function() end }
hook = { items = {}, Add = function(name, id, fn) hook.items[id] = fn end }
local receivers, receivedEntity, receivedBool = {}, nil, false
local focusRequests = {}
net = {
    Start = function() end,
    WriteEntity = function() end,
    WriteBool = function(v) focusRequests[#focusRequests + 1] = v end,
    SendToServer = function() end,
    Receive = function(name, fn) receivers[name] = fn end,
    ReadEntity = function() return receivedEntity end,
    ReadBool = function() return receivedBool end
}
util = { TableToJSON = function(t)
    local parts = {}
    for _, v in ipairs(t) do parts[#parts + 1] = '"' .. v .. '"' end
    return "[" .. table.concat(parts, ",") .. "]"
end }

KEY_W, KEY_S, KEY_A, KEY_D = 1, 2, 3, 4
KEY_Z, KEY_X, KEY_C, KEY_V = 5, 6, 7, 8
KEY_Q, KEY_E, KEY_ENTER, KEY_BACKSPACE, KEY_RSHIFT = 9, 10, 11, 12, 13
KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT = 14, 15, 16, 17
KEY_I, KEY_K, KEY_J, KEY_L = 18, 19, 20, 21
KEY_APOSTROPHE, KEY_SEMICOLON, KEY_O, KEY_P = 22, 23, 24, 25
KEY_LBRACKET, KEY_RBRACKET = 26, 27
KEY_PAD_8, KEY_PAD_2, KEY_PAD_4, KEY_PAD_6 = 28, 29, 30, 31
KEY_PAD_1, KEY_PAD_3, KEY_PAD_5, KEY_PAD_7, KEY_PAD_9, KEY_PAD_0, KEY_PAD_ENTER = 32, 33, 34, 35, 36, 37, 38
KEY_F, KEY_PAD_PLUS, KEY_F1, KEY_F11, KEY_MINUS, KEY_EQUAL, KEY_M = 39, 40, 41, 42, 43, 44, 45

KEY_F5, KEY_F8, MOUSE_RIGHT = 46, 47, 108

local ply = {
    valid = true,
    Alive = function() return true end,
    InVehicle = function() return false end,
    SetEyeAngles = function() end,
    EyeAngles = function() return Angle(0,0,0) end,
    GetShootPos = function() return Vector(0,0,0) end
}
function LocalPlayer() return ply end

local lastJavascript = nil
local htmlMock = {
    valid = true,
    QueueJavascript = function(_, js) lastJavascript = js end
}

local frameMock = {
    valid = true,
    Ready = true,
    LoadedGame = "Super Mario World",
    IsVisible = function() return false end,
    HTML = htmlMock
}

local crtMock = {valid = true, WorldSpaceCenter = function() return Vector(0,0,0) end}
local powered, cartridge = true, true
local consoleMock = {
    valid = true,
    IsEmuConsole = true,
    WorldSpaceCenter = function() return Vector(0,0,0) end,
    GetGameTitle = function() return "Super Mario World" end,
    GetLinkedDisplay = function() return crtMock end,
    GetPower = function() return powered end,
    GetHasCartridge = function() return cartridge end
}
crtMock.GetLinkedConsole = function() return consoleMock end

-- Load input module
dofile("lua/emu/sh_emu_play.lua")
emu.GetKeyboardLayout = function()
    local variants = {
        arrows = {[KEY_UP]="up",[KEY_DOWN]="down",[KEY_LEFT]="left",[KEY_RIGHT]="right",[KEY_Z]="b",[KEY_X]="a"},
        ijkl = {[KEY_I]="up",[KEY_SEMICOLON]="a"},
        numpad = {[KEY_PAD_4]="left"}
    }
    return variants[layout], layout
end
dofile("lua/emu/client/cl_emu_input.lua")
emu.AdjustVolume = function(delta) volume = volume + delta end
emu.QuickSave = function() emu.saved = true end
emu.QuickLoad = function() emu.loaded = true end
emu.ToggleMute = function() volume = 0 end
emu.ToggleFullscreen = function() emu.Fullscreen = not emu.Fullscreen end

local function grant(console, allowed)
    receivedEntity, receivedBool = console, allowed
    receivers.emu_focus_result()
end
local function focus()
    emu.EnterFocus(consoleMock)
    grant(consoleMock, true)
    hook.items.Emu_InputPolling()
end

emu.ActiveConsole = consoleMock
emu.ActiveWindow = frameMock

-- Test initial state
check(emu.IsInputFocused() == false, "should not be focused initially")

-- Test EnterFocus
emu.EnterFocus(consoleMock)
check(not emu.IsInputFocused(), "request must not take controls before server approval")
grant(consoleMock, true)
check(emu.IsInputFocused() == true, "should be focused after server grant")

-- Test key polling in Think
keyDownState[KEY_UP] = true
keyDownState[KEY_Z] = true
hook.items["Emu_InputPolling"]()
check(lastJavascript ~= nil, "should queue javascript on key down")
check(string.find(lastJavascript, '"b"') ~= nil, "should include 'b' button for Z")
check(string.find(lastJavascript, '"up"') ~= nil, "should include 'up' button for Up arrow")
check(lastJavascript:find('["b","up"]', 1, true), "Up arrow and Z must send exactly Up and B, without R")

keyDownState[KEY_UP] = false
hook.items["Emu_InputPolling"]()
check(string.find(lastJavascript, '"up"') == nil, "should not include 'up' after Up arrow released")
check(string.find(lastJavascript, '"b"') ~= nil, "should still include 'b' while Z is held")

-- Test IJKL keys
layout = "ijkl"
keyDownState = {}
hook.items.Emu_InputPolling()
keyDownState[KEY_Z] = false
keyDownState[KEY_I] = true
keyDownState[KEY_SEMICOLON] = true
hook.items["Emu_InputPolling"]()
check(string.find(lastJavascript, '"up"') ~= nil, "I should map to 'up'")
check(string.find(lastJavascript, '"a"') ~= nil, "; should map to 'a'")

-- Test CreateMove movement lock
local clearedMovement, clearedButtons = false, false
local cmd = {
    ClearMovement = function() clearedMovement = true end,
    ClearButtons = function() clearedButtons = true end,
    SetViewAngles = function() end
}
hook.items["Emu_BlockPlayerMovement"](cmd)
check(clearedMovement == true, "movement should be cleared during focus")
check(clearedButtons == true, "buttons should be cleared during focus")

-- Test chat opening releases focus
hook.items["Emu_ChatOpen"]()
check(emu.IsInputFocused() == false, "opening chat must release input focus")

-- Entry key must be released before it can exit; leave never presses R.
keyDownState = {[KEY_E] = true}
focus()
check(emu.IsInputFocused(), "E held during entry must not instantly exit")
keyDownState[KEY_E] = false
hook.items.Emu_InputPolling()
keyDownState[KEY_E] = true
hook.items.Emu_InputPolling()
check(not emu.IsInputFocused(), "a fresh E press must leave")
check(not lastJavascript:find("pause()", 1, true) and lastJavascript:find("setHardwareButtons([])", 1, true),
    "leaving focus releases buttons without pausing the game")

keyDownState = {}
layout = "numpad"
focus()
keyDownState[KEY_PAD_4] = true
hook.items.Emu_InputPolling()
check(lastJavascript:find('["left"]', 1, true), "numpad 4 must send only Left")
keyDownState = {}
hook.items.Emu_InputPolling()
keyDownState[KEY_MINUS] = true
hook.items.Emu_InputPolling()
hook.items.Emu_InputPolling()
check(math.abs(volume - 0.75) < 0.001, "volume down should apply once per key press")
keyDownState = {[KEY_F11] = true}
hook.items.Emu_InputPolling()
check(emu.Fullscreen, "F11 must toggle fullscreen")
keyDownState = {[KEY_M] = true}
hook.items.Emu_InputPolling()
check(volume == 0, "M must mute")
check(hook.items.Emu_BlockGameBinds(ply, "+menu") == true, "Q must not open spawnmenu while playing")
check(hook.items.Emu_BlockGameBinds(ply, "messagemode") == nil, "chat binding must remain available")

keyDownState = {[KEY_F5] = true, [KEY_F8] = true}
hook.items.Emu_InputPolling()
check(emu.saved and emu.loaded, "save/load shortcuts must dispatch shared actions")

cartridge = false
hook.items.Emu_InputPolling()
check(not emu.IsInputFocused() and not emu.Fullscreen, "ejection must release focus and fullscreen")
cartridge = true
keyDownState = {}
focus()
hasFocus = false
hook.items.Emu_InputPolling()
check(not emu.IsInputFocused(), "app blur must release focus")
hasFocus = true
focus()
crtMock.valid = false
hook.items.Emu_InputPolling()
check(not emu.IsInputFocused(), "TV removal must release focus")
crtMock.valid = true

emu.EnterFocus(consoleMock)
emu.ReleaseHardwareInput()
grant(consoleMock, true)
check(not emu.IsInputFocused() and focusRequests[#focusRequests] == false, "late grant must release server reservation")
emu.EnterFocus(consoleMock)
grant(consoleMock, false)
check(not emu.IsInputFocused(), "denied focus must leave controls with GMod")

local toggled = 0
emu.TogglePause = function() toggled = toggled + 1 end
keyDownState = {}
focus()
keyDownState[KEY_P] = true
hook.items.Emu_InputPolling()
hook.items.Emu_InputPolling()
check(toggled == 1 and emu.IsInputFocused(), "P toggles pause once per press without leaving play")

print(string.format("All %d Lua input router tests PASSED!", count))
