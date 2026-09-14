CLIENT=true
local handlers,hooks={},{}
local now,sent,size=0,0,0
function RealTime() return now end
function IsValid(v) return type(v)=='table' and not v.invalid end
net={Receive=function(n,f) handlers[n]=f end,Start=function() end,WriteEntity=function() end,WriteString=function() end,
    WriteUInt=function() end,WriteData=function(_,n) size=n end,SendToServer=function() sent=sent+1 end}
hook={Add=function(_,n,f) hooks[n]=f end}
concommand={Add=function() end}
util={Base64Decode=function(s) return s end}
emu={}
dofile('lua/emu/client/cl_emu_stream.lua')
local target={GetRomName=function() return 'game.gba' end}
local ack=0
net.ReadEntity=function() return target end
net.ReadString=function() return 'game.gba' end
net.ReadUInt=function() return ack end
emu.SendHandoffState(target,'game.gba',string.rep('x',20000))
assert(sent==1 and size==8192,'large state must enqueue only one small chunk')
emu.SendHandoffState(target,'game.gba',string.rep('y',20000))
assert(sent==1,'repeat snapshot cannot flood queue')
ack=100;handlers.emu_state_upload_ack();assert(sent==1,'bad ACK ignored')
ack=8192;handlers.emu_state_upload_ack();assert(sent==2 and size==8192)
ack=16384;handlers.emu_state_upload_ack();assert(sent==3 and size==3616)
ack=20000;handlers.emu_state_upload_ack();assert(sent==3)
emu.SendHandoffState(target,'game.gba','abc');assert(sent==4)
now=11;hooks.Emu_StateUploadTimeout()
emu.SendHandoffState(target,'game.gba','abc');assert(sent==5,'stalled upload expires')
print('State upload: bounded chunks, ACK flow, duplicate suppression and timeout passed.')
