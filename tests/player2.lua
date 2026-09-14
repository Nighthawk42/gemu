-- Cooperative console controller: join, validated buttons and release.
SERVER=true
local now, count = 10, 0
local function check(ok, why) assert(ok, why) count=count+1 end
function CurTime() return now end
function IsValid(v) return type(v)=='table' and v.valid~=false end
function isstring(v) return type(v)=='string' end
function GetConVar() return {GetFloat=function() return 4 end} end
math.Clamp=function(v,lo,hi) return math.max(lo,math.min(v,hi)) end
local handlers, incoming, readIndex, sent = {}, {}, 0, nil
hook={Add=function() end}
util={AddNetworkString=function() end}
net={Receive=function(name,fn) handlers[name]=fn end,ReadEntity=function() return incoming.target end,
    ReadBool=function() return incoming.requested end,ReadUInt=function() readIndex=readIndex+1 return incoming.count end,
    ReadString=function() return incoming.buttons[readIndex] end,Start=function() end,WriteEntity=function() end,
    WriteBool=function() end,WriteUInt=function() end,WriteString=function() end,Send=function(p) sent=p end}
local function point() return {DistToSqr=function() return 0 end} end
local p1,p2={GetShootPos=function() return point() end},{GetShootPos=function() return point() end}
local target={IsEmuConsole=true,GetControllingPlayer=function() return p1 end,GetPlayer2=function(s) return s.player2 end,
    SetPlayer2=function(s,p) s.player2=p end,GetPower=function() return true end,GetHasCartridge=function() return true end,
    WorldSpaceCenter=function() return point() end,GetLinkedDisplay=function() return nil end,GetRomName=function() return 'x.sfc' end}
emu={GetSystem=function() return {player2=true,buttons={a=true,b=true}} end,CanFocusTarget=function() return true end,
    IsHandheld=function() return false end,IsNearSetup=function() return true end}
player={GetAll=function() return {p1,p2} end}
dofile('lua/emu/server/sv_emu.lua')
local unowned={IsEmuConsole=true,GetControllingPlayer=function() return nil end}
local granted,reason=emu.GrantPlayer2(p2,unowned)
check(not granted and reason=='nobody is playing it','refusal explains why player two cannot join')
check(emu.GrantPlayer2(p2,target),'nearby player can join supported console')
check(target.player2==p2 and p2.EmuPlayer2Target==target,'player2 reservation is stored on both entities')
incoming={target=target,count=2,buttons={'a','b'}} readIndex=0
handlers.emu_player2_buttons(0,p2)
check(sent==p1,'validated player2 buttons are forwarded to owner')
emu.ReleasePlayer2(p2,false)
check(target.player2==nil and p2.EmuPlayer2Target==nil,'player2 release clears reservation')
incoming={target=target,requested=true}
handlers.emu_player2_focus(0,p2)
check(target.player2==p2,'focus request joins player2')
incoming={target=target,requested=false}
handlers.emu_player2_focus(0,p2)
check(target.player2==nil,'focus release leaves player2 slot')
print('All '..count..' player2 tests PASSED!')
