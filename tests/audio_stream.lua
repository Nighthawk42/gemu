-- Spectator audio transport: authority, validation, rate limiting and isolation.
SERVER=true
local now, count = 10, 0
local function check(ok, why) assert(ok, why) count=count+1 end
function CurTime() return now end
function IsValid(v) return type(v)=='table' and v.valid~=false end
math.Clamp = function(v,lo,hi) return math.max(lo,math.min(v,hi)) end
function GetConVar() return {GetFloat=function() return 4 end} end
local handler, incoming, sent, readIndex
hook={Add=function() end}
util={AddNetworkString=function() end}
net={
    Receive=function(name,fn) if name=='emu_audio_frame' then handler=fn end end,
    ReadEntity=function() return incoming.target end,
    ReadString=function() return incoming.rom end,
    ReadUInt=function(bits)
        if bits==32 then return incoming.serial end
        readIndex=readIndex+1
        return readIndex==1 and incoming.sampleRate or incoming.size
    end,
    ReadData=function() return incoming.data end,
    Start=function() end,WriteEntity=function() end,WriteUInt=function() end,
    WriteString=function() end,WriteData=function() end,
    Send=function(recipients) sent=recipients end
}
local function point() return {DistToSqr=function() return 0 end} end
local function playerMock() return {GetShootPos=function() return point() end} end
local p1,p2=playerMock(),playerMock()
player={GetAll=function() return {p1,p2} end}
local target={WorldSpaceCenter=function() return {DistToSqr=function() return 0 end} end,
    GetLinkedDisplay=function() return nil end,GetRomName=function() return 'test.smc' end,
    GetControllingPlayer=function() return p1 end}
emu={CanFocusTarget=function() return true end,IsHandheld=function() return false end,
    CanKeepSession=function() return true end,GetSessionRunner=function(t) return t:GetControllingPlayer() end}
dofile('lua/emu/server/sv_emu.lua')
p1.EmuSession=target
check(emu.CanRelayAudioFrame(p1,target,2048,11025),'reserved target accepts valid audio')
check(emu.CanRelayAudioFrame(p1,target,2048,11025) and emu.CanRelayAudioFrame(p1,target,2048,11025),'a short burst absorbs capture jitter')
check(not emu.CanRelayAudioFrame(p1,target,2048,11025),'sustained audio beyond the rate limit is rejected')
now=now+0.1
check(not emu.CanRelayAudioFrame(p1,target,12001,11025),'oversized audio is rejected')
now=now+1
check(not emu.CanRelayAudioFrame(p1,target,0,11025),'empty audio is rejected')
check(emu.CanRelayAudioFrame(p1,target,1023,11025),'odd-sized mu-law blocks are valid')
incoming={target=target,sampleRate=11025,size=4,data='pcms',rom='test.smc'}
readIndex=0
now=now+1
check(#emu.GetVideoRecipients(p1,target)==1,'nearby recipient is discoverable')
handler(64,p1)
check(sent and sent[1]==p2, 'valid audio is relayed only to nearby spectators ('..tostring(sent and #sent)..')')
print('All '..count..' audio stream tests PASSED!')
