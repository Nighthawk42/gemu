-- Management regressions; no game or hosted ROM downloads required.
SERVER=true
local count, now, base = 0, 20, 'https://old/'
local function check(value, message) assert(value,message) count=count+1 end
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function IsValid(v) return type(v)=='table' and v.valid~=false end
function CurTime() return now end
function string.Trim(s) return s:match('^%s*(.-)%s*$') end
function GetConVar() return {GetString=function() return base end} end
local decoded, requests, receivers = {}, {}, {}
util={AddNetworkString=function() end,JSONToTable=function() return decoded end}
http={Fetch=function(url,success,failure) requests[#requests+1]={url=url,success=success,failure=failure} end}
hook={Add=function() end}
local changed
cvars={AddChangeCallback=function(_,fn) changed=fn end}
local entity, action, filename
net={Receive=function(name,fn) receivers[name]=fn end,ReadEntity=function() return entity end,
    ReadString=function() if action then local a=action action=nil return a end return filename end,
    Start=function() end,WriteEntity=function() end,Broadcast=function() end}
emu={Systems={snes={extensions={'sfc'},cartridges={{rom='known.sfc',title='Known Game',skin=3}}}}}
dofile('lua/emu/sh_emu_cartridges.lua')
for _,bad in ipairs({false,12,'bad',{system='snes',filename='../bad.sfc'},
    {system='snes',filename='bad.gba'},{system={},filename='bad.sfc'}}) do
    check(emu.NormalizeCatalogRow(bad)==nil,'reject malformed catalog row')
end
check(emu.NormalizeCatalogRow({system='snes',filename='test_game.sfc',title={}}).title=='test game','invalid title falls back')
dofile('lua/emu/sh_emu_play.lua')
emu.CanManage=function() return true end
emu.GetSetupTarget=function(e) return e end
local released, powered
emu.EndSession=function(p) released=p end
emu.ReleaseConsole=function(c) powered=c end
dofile('lua/emu/server/sv_emu_management.lua')
local ply={Alive=function() return true end,ChatPrint=function() end,
    GetShootPos=function() return {DistToSqr=function(_,pos) return pos.distance or 0 end} end}
local cart={IsEmuCartridge=true,GetIsInserted=function() return false end,
    GetSystemId=function() return 'snes' end,WorldSpaceCenter=function() return {} end,
    SetRomName=function(s,v) s.rom=v end,SetGameTitle=function(s,v) s.title=v end,
    SetCartridgeSkin=function(s,v) s.skin=v end,SetSkin=function() end,SetBlankCartridge=function(s,v) s.blank=v end}
local function manage(e,a,f)
    now=now+1 entity,action,filename=e,a,f receivers.emu_manage(0,ply)
end
emu.RefreshCatalog()
base='https://new/' changed()
check(#requests==2,'host change supersedes pending request')
decoded={roms={{system='snes',filename='known.sfc'},false,{system='snes',filename='custom.sfc',title={}}}}
requests[2].success('{}',nil,nil,200)
decoded={roms={{system='snes',filename='old.sfc'}}}
requests[1].success('{}',nil,nil,200)
manage(cart,'select','known.sfc')
check(cart.rom=='known.sfc' and cart.skin==3 and not cart.blank,'new host wins and named label matches')
manage(cart,'select','custom.sfc')
check(cart.rom=='custom.sfc' and cart.title=='custom' and cart.blank and cart.skin==0,'custom game uses blank label')
manage(cart,'select','old.sfc')
check(cart.rom=='custom.sfc','stale host game rejected')
check(#requests==2,'missing selection cannot flood catalog requests')
local tv={WorldSpaceCenter=function() return {distance=0} end}
local console={IsEmuConsole=true,WorldSpaceCenter=function() return {distance=1000000} end,
    GetLinkedDisplay=function() return tv end,SetPower=function(s,v) s.power=v end}
manage(console,'power_off')
check(powered==console and console.power==false,'power off works beside linked CRT')
powered=nil tv.valid=false
manage(console,'power_off')
check(powered==nil,'out of range console cannot power off')
local holder={}
local handheld={IsEmuHandheld=true,GetOwner=function() return holder end,WorldSpaceCenter=function() return {} end}
holder.EmuSession=handheld
manage(handheld,'power_off')
check(released==holder,'release handheld holder rather than admin actor')
released=nil holder.EmuSession={}
manage(handheld,'power_off')
check(released==nil,'unrelated holder session is preserved')
print('All '..count..' management tests PASSED!')
