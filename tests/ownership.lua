-- Focused permission tests, including real mutation entry points.
SERVER=true
local count=0
local function check(v,m) assert(v,m) count=count+1 end
function IsValid(v) return type(v)=='table' and v.valid~=false end
function CurTime() return 10 end
function AddCSLuaFile() end
function include() end
function GetConVar() return {GetBool=function() return true end} end
hook={items={},Add=function(name,_,fn) hook.items[name]=fn end}
local function player(admin)
    return {IsPlayer=function() return true end,IsAdmin=function() return admin or false end,
        Alive=function() return true end,ChatPrint=function() end,
        GetShootPos=function() return {DistToSqr=function() return 0 end} end}
end
local owner,other,admin=player(),player(),player(true)
local function device(kind,creator)
    return {['IsEmu'..kind]=true,creator=creator,
        GetCreator=function(s) return s.creator end,GetOwner=function(s) return s.creator end,
        GetControllingPlayer=function(s) return s.controller end,
        GetIsInserted=function(s) return s.inserted end,GetCurrentConsole=function(s) return s.console end,
        GetLinkedConsole=function(s) return s.console end,GetSystemId=function() return 'gba' end,
        WorldSpaceCenter=function() return {} end}
end
emu={UseDistance=160}
dofile('lua/emu/server/sv_emu_ownership.lua')
local console,cart,weapon=device('Console',owner),device('Cartridge',owner),device('Handheld',owner)
check(emu.CanManage(owner,console),'creator can manage idle console')
check(not emu.CanManage(other,console),'stranger cannot manage console')
check(emu.CanManage(admin,console),'admin can manage idle console')
console.controller=other
check(not emu.CanManage(owner,console) and not emu.CanManage(admin,console),'active controller cannot be interrupted')
check(emu.CanManage(other,console),'active controller can manage borrowed console')
console.controller=nil
console.CPPIGetOwner=function() return {valid=false} end
check(not emu.CanManage(other,console),'invalid CPPI owner falls back to creator')
console.CPPIGetOwner=function() return other end
check(emu.CanManage(other,console) and not emu.CanManage(owner,console),'valid CPPI owner is authoritative')
console.CPPIGetOwner=nil
local tv=device('CRT',owner)
check(not emu.CanManage(other,tv),'standalone CRT remains protected')
tv.console=console
check(emu.GetSetupTarget(tv)==console,'linked TV uses console permissions')
cart.inserted=true cart.console=console
check(emu.GetSetupTarget(cart)==console,'inserted cart uses console permissions')
cart.inserted=false cart.console=nil
check(emu.CanInsertCartridge(owner,console,cart),'owner can insert owned cartridge')
check(not emu.CanInsertCartridge(other,console,cart),'stranger cannot insert owned cartridge')
cart.creator=other
check(not emu.CanInsertCartridge(owner,weapon,cart),'handheld owner cannot steal another cartridge')
check(not emu.CanInsertCartridge(nil,console,cart),'cross-owner collision cannot dock')
cart.creator=owner
check(emu.CanInsertCartridge(nil,console,cart),'same-owner collision can dock')
cart.EmuLastMover=other cart.EmuMoverUntil=12
check(not emu.CanInsertCartridge(nil,console,cart),'recent unauthorized mover cannot trigger docking')
cart.EmuMoverUntil=9
check(emu.CanInsertCartridge(nil,console,cart),'expired mover does not permanently block owner')
local worldConsole,worldCart=device('Console'),device('Cartridge')
check(emu.CanInsertCartridge(nil,worldConsole,worldCart),'idle unowned world props can dock')
worldConsole.controller=other
check(not emu.CanInsertCartridge(nil,worldConsole,worldCart),'unowned props cannot alter active setup')
check(hook.items.PhysgunPickup(other,console)==false,'physgun denies strangers')
check(hook.items.GravGunPickupAllowed(other,console)==false,'gravity gun pickup denies strangers')
check(hook.items.GravGunPunt(other,console)==false,'gravity gun punt denies strangers')
check(hook.items.CanTool(other,{Entity=console})==false,'tools deny strangers')
check(hook.items.CanProperty(other,'editentity',cart)==false,'property edits deny strangers')
check(hook.items.PhysgunPickup(owner,console)==nil,'allowed actions do not override other addons')
check(hook.items.PhysgunPickup(other,{})==nil,'unrelated entities are unaffected')
-- Real entity methods must deny before changing cartridge state or spawning props.
ENT={} dofile('lua/entities/emu_console/init.lua')
check(ENT.InsertCartridgeEntity(console,cart,other)==false,'console insertion enforces permission at entry')
check(ENT.EjectCartridge(console,other)==false,'console ejection enforces permission at entry')
local consumed=false
cart.Remove=function() consumed=true end
other.GetActiveWeapon=function() return weapon end
ENT={} dofile('lua/entities/emu_cartridge/init.lua')
ENT.Use(cart,other)
check(not consumed,'unauthorized handheld insertion does not consume cartridge')
print('All '..count..' ownership tests PASSED!')
