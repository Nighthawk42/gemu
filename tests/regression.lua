-- Standalone LuaJIT Regression Tests for gmod-emu
-- Run from repository root: luajit tests/regression.lua

local count = 0
local function check(cond, msg)
    assert(cond, msg or "Assertion failed")
    count = count + 1
end

CLIENT, SERVER = false, true
NULL = { valid = false }
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function AddCSLuaFile() end
function include(path) end
function Color(...) return {...} end
function isstring(v) return type(v) == "string" end
function Vector(...) return setmetatable({...}, {__mul=function(v) return v end, __add=function(v) return v end, __sub=function(v) return v end}) end
VectorRand = Vector
Angle = Vector
local now = 10
function CurTime() return now end
function GetConVar() return {GetBool=function() return true end} end
player = {GetAll=function() return {} end}
hook = {items={}, Add=function(name, id, fn) hook.items[id]=fn end}
concommand = {Add=function() end}
net = {Receive=function() end, Start=function() end, WriteEntity=function() end, WriteBool=function() end, Send=function() end, SendToServer=function() end}
util = {AddNetworkString=function() end}
IN_WALK, IN_DUCK, IN_SPEED = 1, 2, 3
SOLID_NONE, SOLID_VPHYSICS, MOVETYPE_NONE, MOVETYPE_VPHYSICS = 0, 6, 0, 6

local function entity(methods, values)
    local e = {values = values or {}, bodygroups = {}, valid = true}
    return setmetatable(e, {__index = function(self, k)
        if methods and methods[k] then return methods[k] end
        if k == "SetBodygroup" then
            return function(_, idx, val) self.bodygroups[idx] = val end
        end
        if k == "GetBodygroup" then
            return function(_, idx) return self.bodygroups[idx] or 0 end
        end
        if k:sub(1,3) == "Get" then
            return function() return self.values[k:sub(4)] end
        end
        if k:sub(1,3) == "Set" then
            return function(_, v) self.values[k:sub(4)] = v end
        end
        if k == "EmitSound" then return function() end end
        if k == "PhysicsInit" then return function() end end
        if k == "GetPhysicsObject" then
            return function() return { Wake=function() end, ApplyForceCenter=function() end } end
        end
    end})
end

-- 1. Test SNES System Profile
dofile("lua/emu/systems/snes.lua")
dofile("lua/emu/sh_emu_play.lua")
dofile("lua/emu/server/sv_emu.lua")
dofile("lua/emu/server/sv_emu_ownership.lua")
local snes = emu.Systems["snes"]
check(snes ~= nil, "snes system must be registered")
check(snes.name == "Super Nintendo", "snes name must be Super Nintendo")
check(snes:GetSkinForRom("super_mario_world.smc") == 4, "super mario world must map to skin 4")
check(snes:GetSkinForRom("chrono_trigger.smc") == 2, "chrono trigger must map to skin 2")
check(snes:GetSkinForRom("unknown_game.smc") == 4, "unknown rom must return default skin 4")

-- 2. Test Console & Cartridge Entity Lifecycle
ENT = {}
dofile("lua/entities/emu_console/init.lua")
local consoleMethods = ENT

ENT = {}
dofile("lua/entities/emu_cartridge/init.lua")
local cartMethods = ENT

ENT = {}
dofile("lua/entities/emu_crt/init.lua")
local crtMethods = ENT

local console = entity(consoleMethods, {
    InsertedCart = NULL,
    LinkedDisplay = NULL,
    ControllingPlayer = NULL,
    Pos = Vector(0,0,0),
    Up = Vector(0,0,1),
    Forward = Vector(1,0,0),
    Angles = Angle(0,0,0)
})
console.IsEmuConsole = true
console:Initialize()

check(console:GetBodygroup(2) == 0, "unattached second-controller cable must stay hidden")
check(console:GetBodygroup(3) == 1, "empty console must select no_cartridge.smd (bodygroup 1)")
check(console:GetBodygroup(4) == 1, "console controller bodygroup must be 1")
check(console:GetHasCartridge() == false, "console must start without cartridge")

local cart = entity(cartMethods, {
    CurrentConsole = NULL,
    Pos = Vector(0,0,0),
    Angles = Angle(0,0,0),
    GameTitle = "Super Mario World",
    RomName = "super_mario_world.smc",
    CartridgeSkin = 4
})
cart.IsEmuCartridge = true
cart:Initialize()

check(cart:GetCartridgeSkin() == 4, "cartridge skin must be 4")
check(cart:GetIsInserted() == false, "cartridge must start uninserted")

-- Docking
check(console:InsertCartridgeEntity(cart) == true, "cartridge must dock into console")
check(console:GetHasCartridge() == true, "console must report has cartridge")
check(console:GetInsertedCart() == cart, "console inserted cart must be cart")
check(cart:GetCurrentConsole() == console, "cartridge current console must be console")
check(cart:GetIsInserted() == true, "cartridge isInserted must be true")
check(cart:GetMoveType() == MOVETYPE_NONE, "docked cartridge must have MOVETYPE_NONE")
check(cart:GetSolid() == SOLID_NONE, "docked cartridge must have SOLID_NONE")
check(console:GetBodygroup(3) == 0, "docked console must select cartridge_snes.smd (bodygroup 0)")
check(console:GetSkin() == 4, "console skin must match cartridge skin")

-- Cannot double-dock or steal
local console2 = entity(consoleMethods, { InsertedCart = NULL })
check(console2:InsertCartridgeEntity(cart) == false, "cannot insert cartridge into second console while docked")

-- Ejection
console:EjectCartridge({IsPlayer=function() return true end, IsAdmin=function() return false end, ChatPrint=function() end})
check(console:GetHasCartridge() == false, "console must report no cartridge after eject")
check(not IsValid(console:GetInsertedCart()), "console inserted cart must be NULL after eject")
check(cart:GetIsInserted() == false, "cartridge isInserted must be false after eject")
check(not IsValid(cart:GetCurrentConsole()), "cartridge current console must be NULL after eject")
check(cart:GetMoveType() == MOVETYPE_VPHYSICS, "ejected cartridge must restore MOVETYPE_VPHYSICS")
check(cart:GetSolid() == SOLID_VPHYSICS, "ejected cartridge must restore SOLID_VPHYSICS")
check(console:GetBodygroup(3) == 1, "eject must restore the empty slot")

-- Eject cooldown
check(console:InsertCartridgeEntity(cart) == false, "cartridge cannot immediately re-dock during cooldown")
now = 12
check(console:InsertCartridgeEntity(cart) == true, "cartridge can re-dock after cooldown expires")

-- Removal cleanup
local crt = entity(crtMethods, { LinkedConsole = console })
crt:Initialize()
console:SetLinkedDisplay(crt)

check(crt:GetSkin() == 1, "crt starts with skin 1 (static snow)")
check(crt:GetLinkedConsole() == console, "crt linked console must be console")

-- Cartridge removed while in console
cartMethods.OnRemove(cart)
check(console:GetHasCartridge() == false, "removing cartridge must clear console cartridge state")

-- Console removed
consoleMethods.OnRemove(console)
check(not IsValid(crt:GetLinkedConsole()), "removing console must unbind CRT linked console")

print(string.format("All %d Lua regression tests PASSED!", count))
