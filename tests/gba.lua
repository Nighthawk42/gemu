-- Handheld profile, eligibility, cartridge catalog and SWEP contract.
local count = 0
local function check(value, message) assert(value, message) count = count + 1 end

CLIENT, SERVER = true, false
function IsValid(value) return type(value) == "table" and value.valid ~= false end
function GetConVar() return {GetBool = function() return true end} end

emu = {}
dofile("lua/emu/systems/gba.lua")
dofile("lua/emu/sh_emu_play.lua")
local profile = emu.Systems.gba
check(profile.interaction == "handheld", "GBA must use the handheld interaction path")
check(profile.aspectRatio == 3 / 2 and profile.frameWidth == 240 and profile.frameHeight == 160,
    "GBA video geometry must be 240x160 at 3:2")
check(profile.screenMaterial == 1 and profile.screenUV.w < 1 and profile.screenUV.h < 1,
    "GBA LCD must target the model's measured screen submesh UVs")

local player = {valid = true, active = nil}
function player:Alive() return true end
function player:InVehicle() return false end
function player:GetActiveWeapon() return self.active end
local weapon = {valid = true, IsEmuHandheld = true, owner = player, cart = true}
function weapon:GetSystemId() return "gba" end
function weapon:IsWeapon() return true end
function weapon:GetOwner() return self.owner end
function weapon:GetHasCartridge() return self.cart end
player.active = weapon
check(emu.CanUseTarget(player, weapon), "a living owner must be able to open the GBA session")
check(emu.CanFocusTarget(player, weapon), "the equipped GBA must be eligible for focused input")
player.active = nil
check(emu.CanUseTarget(player, weapon) and not emu.CanFocusTarget(player, weapon),
    "holstering may preserve the session but must release focused input")
player.active = weapon
weapon.cart = false
check(not emu.CanUseTarget(player, weapon), "an empty GBA must not boot")

ENT = {}
dofile("lua/entities/emu_gba_cartridge/shared.lua")
check(ENT.Base == "emu_cartridge" and ENT.SystemID == "gba", "GBA cartridges must inherit shared cartridge behavior")
check(profile.cartridges[0].rom == "hello_world.gba" and profile.cartridges[9].skin == 9,
    "the restored GBA cartridge catalog must retain demo and game skins")

SWEP = {Primary = {}, Secondary = {}}
dofile("lua/weapons/weapon_emu_base/shared.lua")
dofile("lua/weapons/weapon_emu_gba/shared.lua")
check(SWEP.IsEmuHandheld and SWEP.ViewModel == profile.consoleModel,
    "weapon_emu_gba must render the original GBA model in hand")
check(SWEP:GetSystemId() == "gba", "weapon_emu_gba must select the GBA Emulatrix core")

-- The server must grant only an equipped, player-owned handheld and release it on holster.
CLIENT, SERVER = false, true
NULL = {valid = false}
function CurTime() return 20 end
function player:EyeAngles() return {p = 0, y = 0, r = 0} end
local receivers, incoming, reply = {}, {}, nil
util = {AddNetworkString = function() end}
net = {
    Receive = function(name, fn) receivers[name] = fn end,
    ReadEntity = function() return incoming.target end,
    ReadBool = function() return incoming.requested end,
    Start = function() reply = {} end,
    WriteEntity = function(value) reply.target = value end,
    WriteBool = function(value) reply.granted = value end,
    Send = function() end
}
hook = {items = {}, Add = function(_, name, fn) hook.items[name] = fn end}
player.GetAll = nil
_G.player = {GetAll = function() return {player} end}
weapon.cart = true
player.active = weapon
dofile("lua/emu/server/sv_emu.lua")
incoming = {target = weapon, requested = true}
receivers.emu_play_focus(0, player)
check(reply.granted and player.EmuTarget == weapon, "server must grant the equipped handheld")
player.active = nil
hook.items.Emu_ValidateControllers()
check(player.EmuTarget == nil and not reply.granted, "server must revoke handheld focus after holster")
check(player.EmuSession == weapon, "holstering keeps the handheld game running")

print(string.format("All %d GBA integration tests PASSED!", count))
