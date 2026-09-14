-- Native disk commit/recovery behavior, with deterministic filesystem failures.
CLIENT=true
emu={}
local count=0
local function check(v,m) assert(v,m) count=count+1 end
function isstring(v) return type(v)=='string' end
function istable(v) return type(v)=='table' end
local records={
    one={version=2,system='gba',rom='game.gba',state='first',checksum='crc:first',build='a',romIdentity='rom'},
    two={version=2,system='gba',rom='game.gba',state='second',checksum='crc:second',build='a',romIdentity='rom'}
}
util={JSONToTable=function(s) return records[s] end,CRC=function(s) return 'crc:'..s end}
local data,failWrite,failRename={},nil,false
file={CreateDir=function() end,Read=function(p) return data[p] end,Delete=function(p) data[p]=nil end,
    Write=function(p,s) assert(p:sub(-5)=='.json','GMod rejects unsupported save extensions: '..p) if p~=failWrite then data[p]=s end end,
    Rename=function(a,b) if not failRename and not data[b] then data[b]=data[a] data[a]=nil end end}
dofile('lua/emu/client/cl_emu_saves.lua')
local path='saves/1.json'
local function write(v) return emu.WriteSaveSlot('saves','1',v,'gba','game.gba') end
check(write('one') and data[path]=='one','first disk save')
check(write('two') and data[path]=='two' and data[path..'.previous.json']=='one','replacement preserves previous')
check(write('two') and data[path..'.previous.json']=='one','unchanged state does not erase previous snapshot')
failWrite=path..'.pending.json'
check(not write('one') and data[path]=='two','failed temporary write preserves primary')
failWrite=nil failRename=true
check(not write('one') and data[path]=='two','failed rename preserves primary')
failRename=false
data[path]='corrupt' data[path..'.previous.json']='one'
check(write('two') and data[path..'.previous.json']=='one','corrupt primary cannot replace verified backup')
check(not write('invalid'),'malformed record rejected')
records.two.checksum='bad'
check(not write('two') and data[path]=='two','checksum mismatch rejected before disk change')
-- Reopening the same game must wait for its previous browser's final write.
function IsValid(v) return type(v)=='table' and v.valid~=false end
function isnumber(v) return type(v)=='number' end
util.TableToJSON=function() return '{}' end
file.Size=function(p) return data[p] and #data[p] or -1 end
local retry
timer={Simple=function(_,fn) retry=fn end}
local html={callbacks={},scripts={}}
function html:AddFunction(_,name,fn) self.callbacks[name]=fn end
function html:QueueJavascript(s) self.scripts[#self.scripts+1]=s end
local frame={Profile={id='gba'},RomName='game.gba'}
local closing={Profile={id='gba'},RomName='game.gba',Closing=true}
emu.ActiveWindow=frame emu.ClosingSaveFrames={[closing]=true}
emu.BindSaveStorage(frame,html)
html.callbacks.readSaveSlot(1,'auto')
check(#html.scripts==0 and retry~=nil,'new session waits for old final save')
emu.ClosingSaveFrames[closing]=nil
retry()
check(#html.scripts==1,'restore proceeds after previous session finishes')
print('All '..count..' native save checks PASSED!')
