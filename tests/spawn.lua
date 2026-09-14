-- Exercise the actual station SpawnFunction, including both placement traces.
local count=0
local function check(v,message) assert(v,message) count=count+1 end
local vector={}
vector.__index=vector
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z},vector) end
function vector.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vector.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vector.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function Angle(p,y,r) return {p=p,yaw=y,r=r} end
function table.Copy(t) local r={} for k,v in pairs(t) do r[k]=type(v)=='table' and table.Copy(v) or v end return r end
function IsValid(e) return type(e)=='table' and not e.removed end
function AddCSLuaFile() end
function include() end
emu={Systems={}}
for _,id in ipairs({'snes','nes','genesis'}) do dofile('lua/emu/systems/'..id..'.lua') end
local created={}
local function noop() end
ents={Create=function(class)
    local ent={class=class,pos=Vector(0,0,0)}
    function ent:SetPos(p) self.pos=p end
    function ent:GetPos() return self.pos end
    function ent:Remove() self.removed=true end
    function ent:LocalToWorld(p) return self.pos+p end
    function ent:LocalToWorldAngles(a) return a end
    function ent:OBBMins() return Vector(-10,-10,-2) end
    function ent:WorldSpaceAABB() return self.pos+Vector(-10,-10,-2),self.pos+Vector(10,10,20) end
    function ent:InsertCartridgeEntity(cart) self.cart=cart return true end
    setmetatable(ent,{__index=function(_,k) if k:sub(1,3)=='Set' or k=='Spawn' or k=='Activate' then return noop end end})
    created[#created+1]=ent
    return ent
end}
local obstructed=false
util={TraceLine=function(t) return {Hit=true,HitNormal=Vector(0,0,1),HitPos=Vector(t.start.x,t.start.y,0)} end,
    TraceHull=function(t)
        local filters={}
        for _,ent in ipairs(t.filter) do filters[ent]=true end
        -- Overlapping assembly bounds must not cause the setup to reject itself.
        return {Hit=obstructed or not filters[created[1]] or not filters[created[2]]}
    end}
undo={Create=noop,AddEntity=noop,SetPlayer=noop,Finish=noop}
local ply={EyeAngles=function() return Angle(0,0,0) end,AddCleanup=noop,ChatPrint=noop}
ENT={}
dofile('lua/entities/emu_console/init.lua')
local spawn=ENT.SpawnFunction
for _,id in ipairs({'snes','nes','genesis'}) do
    created={}
    local ent=spawn({SystemID=id},ply,{Hit=true,HitNormal=Vector(0,0,1),HitPos=Vector(0,0,0)},'emu_'..id..'_console')
    check(IsValid(ent),id..' station must survive its own overlapping model bounds')
    check(#created==3 and ent.cart==created[3],id..' must spawn and insert cartridge')
end
created={} obstructed=true
check(spawn({},ply,{Hit=true,HitNormal=Vector(0,0,1),HitPos=Vector(0,0,0)},'emu_console')==nil,'real obstruction must reject spawn')
check(created[1].removed and created[2].removed,'rejected setup must clean up both props')
ENT={}
dofile('lua/entities/emu_crt/shared.lua')
check(IsValid(ENT:SpawnFunction(ply,{Hit=true,HitNormal=Vector(0,0,1),HitPos=Vector(0,0,0)},'emu_crt')),'standalone CRT must spawn')
for _,class in ipairs({'emu_cartridge','emu_nes_cartridge','emu_genesis_cartridge','emu_gba_cartridge','emu_gb_cartridge','emu_gbc_cartridge'}) do
    ENT={} dofile('lua/entities/'..class..'/shared.lua')
    check(ENT.Spawnable==false,class..' generic entry must be hidden')
end
print('All '..count..' spawn tests PASSED!')
