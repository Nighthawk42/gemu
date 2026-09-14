-- Controller ownership and the real Use -> open-UI network path.
SERVER, CLIENT = true, false
NULL = {valid = false}
function IsValid(v) return type(v) == "table" and v.valid ~= false end
local enabled, now, count = true, 10, 0
local function check(v, message) assert(v, message) count = count + 1 end
function CurTime() return now end
function GetConVar() return {GetBool = function() return enabled end} end
function AddCSLuaFile() end
function include() end
IN_DUCK, IN_WALK, IN_RELOAD, IN_SPEED = 1, 2, 3, 4
hook = {items = {}, Add = function(_, id, fn) hook.items[id] = fn end}
local messages, handlers, incoming, message = {}, {}, {}, nil
net = {
    Receive = function(name, fn) handlers[name] = fn end,
    ReadEntity = function() return incoming.console end,
    ReadBool = function() return incoming.focus end,
    Start = function(name) message = {name = name} end,
    WriteEntity = function(ent) message.console = ent end,
    WriteBool = function(v) message.flag = v end,
    Send = function(ply) message.ply = ply messages[#messages + 1] = message end
}
util = {AddNetworkString = function() end}
local function newPlayer()
    return {alive = true, keys = {},
        Alive = function(self) return self.alive end,
        InVehicle = function() return false end,
        IsPlayer = function() return true end,
        KeyDown = function(self, key) return self.keys[key] end,
        EyeAngles = function() return {yaw = 25} end,
        ChatPrint = function(self, text) self.message = text end,
        GetShootPos = function() return {DistToSqr = function(_, point) return point.distance end} end}
end
local p1, p2 = newPlayer(), newPlayer()
player = {GetAll = function() return {p1, p2} end}
dofile("lua/emu/sh_emu_play.lua")
dofile("lua/emu/server/sv_emu.lua")
ENT = {}
dofile("lua/entities/emu_console/init.lua")
local function newConsole()
    local c = {IsEmuConsole = true, power = true, cartridge = true, distance = 64 * 64, owner = NULL}
    c.GetPower = function(self) return self.power end
    c.SetPower = function(self, v) self.power = v end
    c.GetHasCartridge = function(self) return self.cartridge end
    c.GetControllingPlayer = function(self) return self.owner end
    c.SetControllingPlayer = function(self, p) self.owner = p end
    c.WorldSpaceCenter = function(self) return self end
    c.crt = {distance = 70 * 70, GetLinkedConsole = function() return c end,
        WorldSpaceCenter = function(self) return self end}
    c.GetLinkedDisplay = function(self) return self.crt end
    c.EmitSound = function() end
    c.Use = ENT.Use
    return c
end
local c1, c2 = newConsole(), newConsole()
local function request(ply, console, focus)
    incoming = {console = console, focus = focus}
    handlers.emu_play_focus(0, ply)
end

c1:Use(p1)
check(messages[#messages].name == "emu_open_ui" and messages[#messages].flag, "Use must open a play session")
local ejected = false
c1.EjectCartridge = function() ejected = true end
p1.keys[IN_DUCK] = true
c1:Use(p1)
check(not ejected and messages[#messages].name == "emu_open_ui", "crouched Use must play rather than eject")
p1.keys = {[IN_WALK]=true}
c1:Use(p1)
check(ejected, "Alt+Use must retain explicit ejection")
p1.keys = {}
p1.keys[IN_SPEED] = true
c1:Use(p1)
check(messages[#messages].flag == false, "Shift+Use must request the controls window")
p1.keys = {}
request(p1, c1, true)
check(c1.owner == p1 and p1.EmuConsole == c1 and p1.EmuSession == c1 and messages[#messages].flag, "server must grant and reserve the console")
request(p2, c1, true)
check(c1.owner == p1 and messages[#messages].flag == false, "second player cannot steal the reservation")
c1:Use(p2)
check(p2.message ~= nil, "occupied console should explain why Use is unavailable")
local command = {ClearMovement = function(self) self.movement = true end,
    ClearButtons = function(self) self.buttons = true end,
    SetViewAngles = function(self, value) self.angle = value end}
hook.items.Emu_ReserveControls(p1, command)
check(command.movement and command.buttons and command.angle.yaw == 25, "server must block walking and attacks while playing")
request(p1, c2, true)
check(c1.owner == NULL and c2.owner == p1, "one player can own only one controller")

enabled = false
c2.distance, c2.crt.distance = 999999, 999999
request(p1, c2, false)
check(c2.owner == p1 and p1.EmuConsole == nil and p1.EmuSession == c2, "leaving focus after moving away keeps the running session")
enabled = true
now = now + 1
hook.items.Emu_ValidateControllers()
check(c2.owner == p1 and p1.EmuSession == c2, "distance alone never ends a running session")
incoming = {console = c2, focus = false}
handlers.emu_session(0, p1)
check(c2.owner == NULL and p1.EmuSession == nil, "an explicit session end releases the reservation")
now = now + 1
c1.distance, c1.crt.distance = 999999, 64 * 64
c1:Use(p1)
check(messages[#messages].name == "emu_open_ui", "using nearby CRT must work when console is farther away")
request(p1, c1, true)
check(c1.owner == p1, "focus distance must accept either member of the setup")
c1.crt.valid = false
now = now + 1
hook.items.Emu_ValidateControllers()
check(p1.EmuConsole == nil and c1.owner == NULL, "removing the display must end the session")
c1.crt.valid = true
request(p1, c1, true)
p1.alive = false
hook.items.emu_PlayerCleanup(p1)
check(c1.owner == p1 and p1.EmuConsole == nil and p1.EmuSession == c1, "death drops the controls but keeps the game running")
p1.alive = true
request(p1, c1, true)
c1.cartridge = false
now = now + 1
hook.items.Emu_ValidateControllers()
check(c1.owner == NULL, "ejecting a cartridge must release the controller")
request(p1, c1, true)
check(not messages[#messages].flag, "empty console must deny play")
c1.cartridge = true
request(p1, c1, true)
incoming = {console = c1, focus = true}
handlers.emu_session(0, p2)
check(c1.owner == p1 and messages[#messages].name == "emu_session_result" and messages[#messages].flag == false,
    "another player cannot start a session on a running console")
now = now + 10
incoming = {console = c1, focus = true}
handlers.emu_session(0, p1)
now = now + 10
hook.items.Emu_ValidateControllers()
check(c1.owner == p1, "keepalives hold the reservation beyond the timeout")
now = now + 16
hook.items.Emu_ValidateControllers()
check(c1.owner == NULL and p1.EmuSession == nil, "a session without keepalives expires")
c1.owner = p2
now = now + 1 -- Use is rate limited just after a session ends.
c1:Use(p1)
check(c1.owner == NULL and messages[#messages].name == "emu_open_ui", "a stale reservation without a session cannot lock the console")
request(p1, c1, true)
hook.items.emu_PlayerDisconnect(p1)
check(c1.owner == NULL, "disconnect must release ownership")
print(string.format("All %d server focus tests PASSED!", count))
