-- Controller handoff state: chunk assembly, authority and ROM matching.
SERVER=true
local now, count = 20, 0
local function check(ok, why) assert(ok, why) count=count+1 end
function CurTime() return now end
function IsValid(v) return type(v)=='table' and v.valid~=false end
function isstring(v) return type(v)=='string' end
function GetConVar() return {GetFloat=function() return 4 end} end
math.Clamp=function(v,lo,hi) return math.max(lo,math.min(v,hi)) end
local handlers, incoming, readIndex, sentTo = {}, {}, 0, nil
hook={Add=function() end}
util={AddNetworkString=function() end}
net={Receive=function(name,fn) handlers[name]=fn end,
    ReadEntity=function() return incoming.target end,
    ReadString=function() return incoming.rom end,
    ReadUInt=function(bits)
        readIndex=readIndex+1
        if bits==24 then return readIndex==1 and incoming.total or incoming.offset end
        return incoming.size
    end,
    ReadData=function() return incoming.data end,
    Start=function() end,WriteEntity=function() end,WriteString=function() end,
    WriteUInt=function() end,WriteData=function() end,Send=function(ply) sentTo=ply end}
local function playerMock(id) return {EntIndex=function() return id end} end
local p1,p2=playerMock(1),playerMock(2)
local target={EntIndex=function() return 7 end,GetRomName=function() return 'test.smc' end,
    GetControllingPlayer=function() return p1 end,SetControllingPlayer=function(s,v) s.controller=v end}
emu={CanFocusTarget=function() return true end,IsHandheld=function() return false end}
player={GetAll=function() return {p1,p2} end}
dofile('lua/emu/server/sv_emu.lua')
p1.EmuSession=target
incoming={target=target,rom='test.smc',total=3,offset=0,size=3,data='abc'}
readIndex=0
handlers.emu_state_snapshot(0,p1)
check(target.EmuHandoffState and target.EmuHandoffState.data=='abc','owner snapshot is assembled and cached')
sentTo=nil
emu.SendHandoffState(target,p2)
check(sentTo==p2,'cached state can be sent to the new controller')
target.EmuHandoffState=nil
incoming={target=target,rom='other.smc',total=3,offset=0,size=3,data='bad'}
readIndex=0
handlers.emu_state_snapshot(0,p2)
check(target.EmuHandoffState==nil,'unreserved player cannot upload state')
incoming={target=target,rom='test.smc',total=3,offset=0,size=3,data='abc'}
readIndex=0
handlers.emu_state_snapshot(0,p1)
emu.EndSession(p1,false)
check(p1.EmuHandoffTarget==target and p1.EmuHandoffUntil>now,'ending a session keeps a short handoff window')
local chunks, lastSize = 0, 0
net.WriteData=function(_, size) chunks=chunks+1 lastSize=size end
local p3=playerMock(3)
target.EmuHandoffState={rom='test.smc',data=string.rep('x',20000)}
emu.SendHandoffState(target,p3)
check(chunks==1 and lastSize==8192,'download sends only one bounded chunk before ACK')
incoming={target=target,rom='test.smc',total=123};readIndex=0
handlers.emu_state_download_ack(0,p3)
check(chunks==1,'invalid download ACK cannot advance transfer')
incoming.total=8192;readIndex=0;handlers.emu_state_download_ack(0,p3)
check(chunks==2 and lastSize==8192,'download advances only on expected ACK')
incoming.total=16384;readIndex=0;handlers.emu_state_download_ack(0,p3)
check(chunks==3 and lastSize==3616,'download final chunk is bounded')
incoming.total=20000;readIndex=0;handlers.emu_state_download_ack(0,p3)
check(chunks==3,'final ACK completes without another packet')
print('All '..count..' handoff tests PASSED!')
