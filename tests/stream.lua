-- Multiplayer transport: sender ownership, rate limits, payloads and recipient isolation.
SERVER, CLIENT = true, false
local now, count = 10, 0
local function check(ok, why) assert(ok, why) count = count + 1 end
function CurTime() return now end
function RealTime() return now end
function IsValid(v) return type(v) == "table" and v.valid ~= false end
NULL = {valid = false}
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(v, hi)) end
function GetConVar(name) return {GetFloat = function() return name == "emu_sv_stream_fps" and 4 or 1800 end} end
local handlers, hooks, sent, incoming, unreliable = {}, {}, {}, {}, nil
hook = {Add = function(_, name, fn) hooks[name] = fn end}
concommand = {Add = function() end}
util = {AddNetworkString = function() end}
net = {Receive = function(name, fn) handlers[name] = fn end,
    ReadEntity = function() return incoming.target end, ReadUInt = function(bits) return bits == 32 and incoming.serial or incoming.size end,
    ReadString = function() return incoming.rom end, ReadBool = function() return incoming.wanted end,
    ReadData = function() return incoming.data end,
    Start = function(_, flag) unreliable = flag end, WriteEntity = function() end, WriteUInt = function() end, WriteData = function() end,
    WriteString = function() end, WriteBool = function() end,
    Send = function(recipients) sent[#sent+1] = recipients end}
local function point(x) return {x=x, DistToSqr = function(self, p) return (self.x-p.x)^2 end} end
local function viewer(x) return {GetShootPos = function() return point(x) end} end
local p1, p2, far = viewer(0), viewer(100), viewer(5000)
player = {GetAll = function() return {p1,p2,far} end}
local target = {WorldSpaceCenter = function() return point(0) end, GetLinkedDisplay = function() return NULL end,
    GetRomName = function() return "test.smc" end,
    GetControllingPlayer = function() return p1 end}
local eligible = true
emu = {CanFocusTarget = function() return eligible end, IsHandheld = function(t) return t.handheld end,
    CanKeepSession = function() return eligible end,
    GetSessionRunner = function(t) return t.GetControllingPlayer and t:GetControllingPlayer() or p1 end}
dofile("lua/emu/server/sv_emu.lua")
check(not emu.CanRelayVideoFrame(p1,target,100), "unreserved target must reject video")
p1.EmuSession = target
check(emu.CanRelayVideoFrame(p1,target,100), "reserved console accepts video")
check(not emu.CanRelayVideoFrame(p1,target,100), "repeated packet must be rate limited")
now = now + 0.3
check(not emu.CanRelayVideoFrame(p1,target,60001), "oversized packet must be rejected")
check(not emu.CanRelayVideoFrame(p2,target,100), "another player cannot impersonate owner")
eligible = false
check(not emu.CanRelayVideoFrame(p1,target,100), "invalidated session must stop streaming immediately")
eligible = true
local recipients = emu.GetVideoRecipients(p1,target)
check(#recipients == 1 and recipients[1] == p2, "only nearby spectators receive frames; sender and distant player excluded")
incoming = {target=target,size=4,data="jpeg"}
-- This GMod build writes entities with MAX_EDICT_BITS (13): 13 + 16 + payload bits.
handlers.emu_video_frame(4 * 8 + 29, p1)
check(#sent == 1 and sent[1][1] == p2, "valid network frame must be relayed")
check(unreliable == false, "listen servers relay fallback frames reliably")
handlers.emu_video_frame(64,p1)
check(#sent == 1, "rate-limited network frame must not relay")
now = now + 1
incoming.data = "x"
handlers.emu_video_frame(64,p1)
check(#sent == 1, "truncated payload must not relay")
incoming.data = "jpeg"
game = {IsDedicated = function() return true end}
now = now + 1
handlers.emu_video_frame(64, p1)
check(#sent == 2 and unreliable == true, "dedicated servers keep unreliable fallback frames")
game = nil
incoming = {target = target, size = 6000, data = string.rep("j", 6000)}
now = now + 1
handlers.emu_video_frame(6000 * 8 + 32, p1)
check(#sent == 3, "a large reliable frame fits a refilled spectator budget")
now = now + 0.25
handlers.emu_video_frame(6000 * 8 + 32, p1)
check(#sent == 3, "reliable fallback skips frames beyond the per-spectator byte budget")
incoming = {target = target, size = 4, data = "jpeg"}
now = now + 1
target.handheld, target.GetControllingPlayer = true, nil
check(emu.CanRelayVideoFrame(p1,target,100), "owned equipped handheld uses the same relay")
local nextAllowed = p1.EmuNextVideoFrame
emu.EndSession(p1,false)
check(p1.EmuNextVideoFrame == nextAllowed, "restarting a session cannot bypass the frame rate limit")

dofile("lua/emu/server/sv_emu_stream_demand.lua")
p1.EmuSession = target
hooks.Emu_UpdateVideoDemand()
check(p1.EmuVideoDemand == true, "nearby spectator requests capture for the owner's entity")
player.GetAll = function() return {p1,far} end
now = now + 1
hooks.Emu_UpdateVideoDemand()
check(p1.EmuVideoDemand == false, "no nearby spectators stops the upload")

-- Client receiving and cleanup, including a frame arriving before DHTML has loaded.
SERVER, CLIENT = false, true
local panels = {}
vgui = {GetWorldPanel = function() return {} end, Create = function()
    local panel = {scripts={}}
    for _, method in ipairs({"SetSize","SetPos","SetPaintedManually","SetMouseInputEnabled","SetKeyboardInputEnabled","SetVisible","SetHTML","UpdateHTMLTexture"}) do panel[method] = function() end end
    panel.QueueJavascript = function(self,s) self.scripts[#self.scripts+1]=s end
    panel.Remove = function(self) self.valid = false end
    panels[#panels+1] = panel
    return panel
end}
util.Base64Encode = function() return "anBlZw==" end
emu.IsInputFocused = function() return false end
dofile("lua/emu/client/cl_emu_stream.lua")
incoming.data = "jpeg"
incoming.serial, incoming.rom = 10, "test.smc"
handlers.emu_video_frame()
local html = emu.GetRemoteScreen(target)
check(IsValid(html) and #html.scripts == 0, "retain the latest frame until the DHTML document is ready")
html:OnDocumentReady()
emu.GetRemoteScreen(target)
check(#html.scripts == 1 and html.scripts[1]:find("data:image/jpeg;base64",1,true), "ready spectator panel receives the image")
incoming.serial = 9
handlers.emu_video_frame()
check(emu.RemoteStreams[target].serial == 10, "out-of-order frames must not rewind the image")
incoming.serial, incoming.rom = 11, "different.smc"
handlers.emu_video_frame()
check(emu.RemoteStreams[target].serial == 10, "frames for a changed cartridge must be rejected")
local second = {GetRomName = function() return "other.gba" end}
incoming.target, incoming.rom, incoming.serial = second, "other.gba", 1
handlers.emu_video_frame()
local secondHTML = emu.GetRemoteScreen(second)
check(IsValid(secondHTML) and secondHTML ~= html, "different entities have isolated spectator screens")
check(emu.RemoteStreams[target].serial == 10, "another entity's frame cannot replace the first screen")
incoming.target, incoming.rom, incoming.serial, incoming.size, incoming.data = target, 'test.smc', 1, 4, 'pcms'
local audioRead = 0
net.ReadUInt = function(bits)
    if bits == 32 then return incoming.serial end
    audioRead = audioRead + 1
    return audioRead % 2 == 1 and 11025 or incoming.size
end
handlers.emu_audio_frame()
local before = #html.scripts
hooks.Emu_PlayRemoteAudio()
check(#html.scripts == before + 2, 'volume and audio are sent without rendering the screen')
for i = 2, 6 do incoming.serial = i handlers.emu_audio_frame() end
check(#emu.RemoteStreams[target].audioQueue == 3, 'audio queue remains bounded during a browser stall')
now = now + 0.3
before = #html.scripts
hooks.Emu_PlayRemoteAudio()
check(#html.scripts == before, 'delayed audio is dropped rather than replayed')
now = now + 3
incoming.serial = 7 handlers.emu_audio_frame()
check(not emu.GetRemoteScreen(target), "stale stream must expire instead of showing old gameplay forever")
check(emu.RemoteStreams[target].lastSeen == now, 'fresh audio cannot keep frozen video alive')
now = now + 5
hooks.Emu_CleanupRemoteStreams()
check(not IsValid(html) and emu.RemoteStreams[target] == nil, "expired spectator browser must be removed")
print(string.format("All %d stream tests PASSED!",count))
