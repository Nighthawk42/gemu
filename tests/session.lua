-- Exercise browser startup -> focus request -> grant, presentation and cleanup.
CLIENT, SERVER = true, false
NULL = {valid = false}
local now, count, console = 10, 0, nil
local function check(v, message) assert(v, message) count = count + 1 end
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function Color(...) return {...} end
local vec = {}
vec.__index = vec
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vec) end
function vec.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function vec.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function vec.__mul(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function vec:DistToSqr(b) return (self.x-b.x)^2 + (self.y-b.y)^2 + (self.z-b.z)^2 end
function vec:Angle() return {direction = self} end
function Angle(...) return {...} end
function RealTime() return now end
function CurTime() return now end
local closeTimers, saveWarnings = {}, {}
timer = {Simple=function(_,fn) closeTimers[#closeTimers+1]=fn end}
notification = {AddLegacy=function(message) saveWarnings[#saveWarnings+1]=message end}
function ScrW() return 1920 end
function ScrH() return 1080 end
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
math.Round = function(v) return math.floor(v + 0.5) end
string.Trim = function(v) return v:match("^%s*(.-)%s*$") end
local values = {emu_volume = "0.8", emu_scale = "1", emu_sv_enabled = "1", emu_input_layout = "wasd", emu_url = "http://localhost:8080/"}
local cvarCallbacks = {}
function GetConVar(name) return {
    GetString = function() return values[name] end,
    GetFloat = function() return tonumber(values[name]) end,
    GetBool = function() return values[name] ~= "0" end
} end
function RunConsoleCommand(name, value)
    values[name] = value
    if cvarCallbacks[name] then cvarCallbacks[name]() end
end
cvars = {AddChangeCallback = function(name, fn) cvarCallbacks[name] = fn end}
local commands = {}
concommand = {Add = function(name, fn) commands[name] = fn end}
draw = {RoundedBox = function() end, RoundedBoxEx = function() end, SimpleText = function() end}
surface = {CreateFont = function() end}
hook = {items = {}, Add = function(_, id, fn) hook.items[id] = fn end}
local receivers, incoming, sent, packet = {}, {}, {}, nil
net = {
    Receive = function(name, fn) receivers[name] = fn end,
    ReadEntity = function() return incoming.console end,
    ReadBool = function() return incoming.flag end,
    Start = function(name) packet = {name = name} end,
    WriteEntity = function(v) packet.console = v end,
    WriteBool = function(v) packet.flag = v end,
    SendToServer = function() sent[#sent + 1] = packet end
}
util = {TableToJSON = function(t) return '["' .. table.concat(t, '","') .. '"]' end}
system = {HasFocus = function() return true end}
local gameUI = false
gui = {IsGameUIVisible = function() return gameUI end, IsConsoleVisible = function() return false end}
local keys = {"W", "S", "A", "D", "Z", "X", "C", "V", "Q", "F", "ENTER", "BACKSPACE", "UP", "DOWN", "LEFT", "RIGHT", "I", "K", "J", "L", "APOSTROPHE", "SEMICOLON", "O", "P", "LBRACKET", "RBRACKET", "PAD_8", "PAD_2", "PAD_4", "PAD_6", "PAD_1", "PAD_3", "PAD_5", "PAD_PLUS", "PAD_7", "PAD_9", "PAD_ENTER", "PAD_0", "E", "F1", "F5", "F8", "F11", "MINUS", "EQUAL", "M"}
for i, key in ipairs(keys) do _G["KEY_" .. key] = i end
local keyState = {}
input = {IsMouseDown = function() return false end, IsKeyDown = function(key) return keyState[key] == true end}
local panels, world = {}, {}
local methods = {}
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:GetSize() return self.w, self.h end
function methods:SetParent(parent) self.parent = parent end
function methods:GetParent() return self.parent end
function methods:SetVisible(v) self.visible = v end
function methods:IsVisible() return self.visible end
function methods:SetText(v) self.text = v end
function methods:QueueJavascript(js) self.scripts[#self.scripts + 1] = js end
function methods:AddFunction(_, name, fn) self.callbacks[name] = fn end
function methods:OpenURL(url) self.url = url end
function methods:Remove()
    if not self.valid then return end
    self.valid = false
    if self.OnRemove then self:OnRemove() end
    for _, panel in ipairs(panels) do if panel.parent == self then panel:Remove() end end
end
function methods:InvalidateLayout() if self.PerformLayout then self:PerformLayout(self.w, self.h) end end
for _, name in ipairs({"SetPos", "SetPaintedManually", "SetMouseInputEnabled", "SetKeyboardInputEnabled", "Center", "SetTitle", "SetSizable", "ShowCloseButton", "SetDeleteOnClose", "MakePopup", "RequestFocus"}) do methods[name] = function() end end
vgui = {GetWorldPanel = function() return world end, CursorVisible = function() return false end,
    Create = function(class, parent)
        local panel = setmetatable({class = class, valid = true, visible = true, parent = parent, scripts = {}, callbacks = {}}, {__index = methods})
        panels[#panels + 1] = panel return panel
    end}
local exportedFile = '{"version":2,"system":"snes","rom":"super_mario_world.smc","state":"AAAA","checksum":"1"}'
file = {
    Find = function() return {"export.json"} end,
    Size = function() return #exportedFile end,
    Read = function() return exportedFile end,
    CreateDir = function() end,
    Write = function() end,
    Delete = function() end,
    Rename = function() end
}
local openedMenu
DermaMenu = function()
    local menu = {options = {}, AddOption = function(self, label, fn) self.options[#self.options + 1] = {label = label, fn = fn} end, Open = function() end}
    openedMenu = menu
    return menu
end
local ply = {Alive = function() return true end, InVehicle = function() return false end,
    GetShootPos = function() return Vector() end, EyeAngles = function() return Angle() end, SetEyeAngles = function() end}
function LocalPlayer() return ply end
local crt = {position = Vector(), yaw = 0, WorldSpaceCenter = function() return Vector() end, GetLinkedConsole = function() return console end}
function crt:LocalToWorld(v)
    return self.position + Vector(v.x * math.cos(self.yaw) - v.y * math.sin(self.yaw),
        v.x * math.sin(self.yaw) + v.y * math.cos(self.yaw), v.z)
end
console = {IsEmuConsole = true, power = true, cartridge = true,
    GetPower = function(self) return self.power end, GetHasCartridge = function(self) return self.cartridge end,
    GetGameTitle = function() return "Super Mario World" end, GetRomName = function() return "super_mario_world.smc" end,
    GetRomUrl = function() return "" end, WorldSpaceCenter = function() return Vector() end,
    GetLinkedDisplay = function() return crt end}
console.GetSystemId = function() return "snes" end
dofile("lua/emu/systems/snes.lua")
dofile("lua/emu/sh_emu_play.lua")
dofile("lua/emu/client/cl_emu_input.lua")
-- Keyboard mapping lives in cl_emu_controls; this contract only needs an empty layout.
emu.GetKeyboardLayout = function() return {}, "" end
dofile("lua/emu/client/cl_emu_gui.lua")
dofile("lua/emu/client/cl_emu_saves.lua")
local function open(hardware)
    incoming = {console = console, flag = hardware}
    receivers.emu_open_ui()
    return emu.ActiveWindow
end
local function ready(frame)
    frame.HTML.OnDocumentReady(frame.HTML, frame.HTML.url)
    frame.HTML.callbacks.onReady()
    frame.HTML.callbacks.onGameLoaded("Super Mario World")
end
local function grant()
    incoming = {console = console, flag = true}
    receivers.emu_focus_result()
end
local function hasScript(html, needle)
    return table.concat(html.scripts, "\n"):find(needle, 1, true) ~= nil
end

keyState[KEY_E] = true
local frame = open(true)
check(IsValid(frame) and not frame:IsVisible(), "Use should open a stowed session")
check(frame.HTML:GetParent() == world, "stowed browser must remain on world panel")
local w, h = frame.HTML:GetSize()
check(w == 640 and h == 480, "stowed browser viewport must be 4:3")
hook.items.Emu_SessionLifecycle()
local function sentNamed(name)
    local list = {}
    for _, p in ipairs(sent) do if p.name == name then list[#list + 1] = p end end
    return list
end
check(#sentNamed("emu_play_focus") == 0 and sentNamed("emu_session")[1] and sentNamed("emu_session")[1].flag == true,
    "opening starts a session but must not request controls while booting")
ready(frame)
check(not hasScript(frame.HTML, "pause()"), "a booted game runs immediately instead of pausing")
hook.items.Emu_SessionLifecycle()
check(sent[#sent].flag and sent[#sent].console == console, "ready callback path must request focus without direct test EnterFocus call")
grant()
hook.items.Emu_InputPolling()
check(emu.IsInputFocused(), "Use held through boot must produce stable play focus")
util.TraceHull = function() return {Hit = false} end
crt.position = Vector(100, 20, 0)
local view = hook.items.Emu_SeatedView(ply)
check(view.origin:DistToSqr(Vector(165, 20, 18)) < 0.001 and view.fov == 45, "camera must sit directly in front of CRT screen")
crt.yaw = math.pi / 2
view = hook.items.Emu_SeatedView(ply)
check(view.origin:DistToSqr(Vector(100, 85, 18)) < 0.001, "camera must follow rotated TV")
util.TraceHull = function() return {Hit = true, HitPos = Vector(1, 2, 3), HitNormal = Vector(0, 1, 0)} end
view = hook.items.Emu_SeatedView(ply)
check(view.origin:DistToSqr(Vector(1, 4, 3)) < 0.001, "camera must pull in when its view position is obstructed")
crt.position, crt.yaw = Vector(), 0
keyState = {}
commands.emu_fullscreen()
check(emu.Fullscreen and emu.ActiveWindow == frame, "fullscreen must reuse existing session")
commands.emu_fullscreen()
check(not emu.Fullscreen and emu.IsInputFocused(), "fullscreen toggle must return to seated view")
commands.emu_volume_down()
check(math.abs(tonumber(values.emu_volume) - 0.75) < 0.001 and hasScript(frame.HTML, "setVolume(0.75)"), "volume bind must reach active browser")
commands.emu_mute()
check(values.emu_volume == "0", "mute bind should update volume")
commands.emu_mute()
check(math.abs(tonumber(values.emu_volume) - 0.75) < 0.001, "unmute should restore prior volume")
commands.emu_save()
commands.emu_load()
commands.emu_reset()
check(hasScript(frame.HTML, "quickSave()") and hasScript(frame.HTML, "quickLoad()") and hasScript(frame.HTML, "reset()"), "shared save/load/reset commands must reach browser")
ply.GetShootPos = function() return Vector(5000, 0, 0) end
ply.Alive = function() return false end
hook.items.Emu_SessionLifecycle()
check(emu.ActiveWindow == frame and not frame.Closing, "walking away or dying keeps the game running")
ply.GetShootPos = function() return Vector() end
ply.Alive = function() return true end
commands.emu_pause()
check(hasScript(frame.HTML, "togglePause()"), "the pause command reaches the browser")
frame.HTML.callbacks.onPauseChanged(true)
check(frame.Paused and sent[#sent].name == "emu_session_paused" and sent[#sent].flag == true, "pause state is reported to the server")
frame.HTML.callbacks.onPauseChanged(false)
now = now + 6
hook.items.Emu_SessionLifecycle()
check(sent[#sent].name == "emu_session" and sent[#sent].flag == true, "a running session sends keepalives")
open(false)
check(not emu.IsInputFocused() and frame:IsVisible(), "controls window must release gameplay focus")
check(hasScript(frame.HTML, "classList.remove('mode-screen')"), "controls window must reveal web toolbar")
check(emu.ActiveWindow == frame, "menu must reuse browser and save state")
local fullscreenButton
for _, panel in ipairs(panels) do if panel.text == "Fullscreen" then fullscreenButton = panel end end
check(fullscreenButton ~= nil, "controls frame must include a fullscreen button")
fullscreenButton.DoClick()
hook.items.Emu_SessionLifecycle()
grant()
check(emu.IsInputFocused() and emu.Fullscreen, "fullscreen button must enter play and fullscreen after grant")
local oldHTML = frame.HTML
console.cartridge = false
hook.items.Emu_SessionLifecycle()
check(IsValid(oldHTML) and frame.Closing, "ejection must keep browser alive until final save acknowledgement")
check(sent[#sent].name == "emu_session" and sent[#sent].flag == false and hasScript(oldHTML, "snapshotForHandoff()"),
    "stopping ends the server session and uploads a final snapshot")
oldHTML.callbacks.shutdownComplete(true, "")
check(not IsValid(oldHTML) and not IsValid(frame), "ejection must remove frame AND stowed DHTML")
check(not emu.IsInputFocused() and emu.ActiveWindow == nil, "ejection must clear focus and active session")
console.cartridge = true
frame = open(true)
oldHTML.callbacks.onReady()
check(not frame.Ready, "late callback from old browser must not ready replacement")
ready(frame)
crt.valid = false
hook.items.Emu_SessionLifecycle()
frame.HTML.callbacks.shutdownComplete(true, "")
check(not IsValid(frame.HTML) and emu.ActiveWindow == nil, "TV removal must destroy browser")
crt.valid = true
frame = open(true)
now = now + 21
hook.items.Emu_SessionLifecycle()
check(frame.Error and frame:IsVisible() and not frame.PendingFocus, "boot timeout must expose error and cancel focus")
emu.StopSession()
check(not IsValid(frame.HTML), "stop must destroy a browser even if it never became ready")
frame = open(true)
gameUI = true
hook.items.Emu_SessionLifecycle()
gameUI = false
ready(frame)
hook.items.Emu_SessionLifecycle()
check(not frame.PendingFocus and not emu.IsInputFocused(), "Escape during boot must cancel automatic focus")
emu.StopSession()
closeTimers[#closeTimers]()
check(not IsValid(frame.HTML) and #saveWarnings==1, "unresponsive close must report failed final save and clean up")
-- Import must hand the browser the exported file as an escaped JavaScript string literal.
local IMPORT_PREFIX = "if(window.GModEmulator && GModEmulator.saves) GModEmulator.saves.importFile("
local function queuedImport(frame)
    local found
    for _, script in ipairs(frame.HTML.scripts) do
        if script:find("importFile", 1, true) then found = script end
    end
    return found
end
-- loadstring decodes the same \" \\ \n \r \t escapes a browser does, so the literal round-trips.
local function decodeLiteral(statement)
    local literal = statement:sub(#IMPORT_PREFIX + 1, #statement - 2)
    return assert(loadstring("return " .. literal))()
end
frame = open(true)
ready(frame)
frame.HTML.callbacks.importSave()
check(openedMenu and openedMenu.options[1] and openedMenu.options[1].label == "export.json", "import menu must list exported saves")
openedMenu.options[1].fn()
local statement = queuedImport(frame)
check(statement and statement:sub(-3) == '");' and statement:find("%c") == nil,
    "import must emit one control-free JavaScript call: " .. tostring(statement))
check(decodeLiteral(statement) == exportedFile,
    "import payload must round-trip the exported save file")
exportedFile = 'quote " back \\ line\nbreak\ttab\rreturn'
openedMenu.options[1].fn()
statement = queuedImport(frame)
check(decodeLiteral(statement) == exportedFile,
    "import literal must escape quotes, backslashes and line breaks")
exportedFile = "\1"
openedMenu.options[1].fn()
statement = queuedImport(frame)
check(statement == IMPORT_PREFIX .. '"\\u0001"' .. ');',
    "control bytes must be unicode-escaped: " .. tostring(statement))
emu.StopSession()
frame.HTML.callbacks.shutdownComplete(true, "")

local warnings = #saveWarnings
frame = open(true)
incoming = {console = console, flag = false}
receivers.emu_session_result()
check(emu.ActiveWindow == nil and not IsValid(frame) and #saveWarnings == warnings + 1, "a denied session stops and explains why")

print(string.format("All %d client session tests PASSED!", count))
