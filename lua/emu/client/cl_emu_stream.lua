-- Low-rate fallback screen and audio sharing for players near a running session.
if not CLIENT then return end

emu = emu or {}
emu.RemoteStreams = emu.RemoteStreams or {}

local STREAM_SIZE = 256
local STREAM_TIMEOUT = 2
local UPLOAD_BUDGET = 32000
local nextCapture = 0
local demanded = {}
local sentFrames = 0
local uploadTokens, uploadTime = UPLOAD_BUDGET, 0

net.Receive("emu_video_demand", function()
    local target, wanted = net.ReadEntity(), net.ReadBool()
    if IsValid(target) then demanded[target] = wanted or nil end
end)

function emu.IsSessionPaused(target)
    return IsValid(target) and target.GetSessionPaused ~= nil and target:GetSessionPaused() or false
end

-- The local, fully booted session for target, if this client runs it.
local function runningFrame(target)
    local frame = emu.ActiveWindow
    if not IsValid(target) or emu.ActiveTarget ~= target or not IsValid(frame) or not frame.Ready
        or frame.Closing or frame.Error or not IsValid(frame.HTML) then return end
    return frame
end

-- Listen servers carry fallback media reliably, so uploads stay under a byte
-- budget. Returns whether to send reliably and whether this payload fits.
local function uploadMode(bytes)
    if not (GetGlobalBool and GetGlobalBool("EmuStreamReliable", false)) then return false, true end
    local now = RealTime()
    uploadTokens = math.min(UPLOAD_BUDGET, uploadTokens + math.max(0, now - uploadTime) * UPLOAD_BUDGET)
    uploadTime = now
    if uploadTokens < bytes then return true, false end
    uploadTokens = uploadTokens - bytes
    return true, true
end

hook.Add("Think", "Emu_CaptureVideo", function()
    local target = emu.ActiveTarget
    local frame = demanded[target] and runningFrame(target)
    -- Capture follows the running game, not input focus. A paused game keeps
    -- its last frame on spectator screens, so there is nothing new to send.
    if not frame or frame.Paused then return end
    local now = RealTime()
    if now < nextCapture then return end
    nextCapture = now + 1 / math.Clamp(GetConVar("emu_sv_stream_fps"):GetFloat(), 1, 8)
    frame.HTML:QueueJavascript("if(window.GModEmulator && GModEmulator.captureFrame) GModEmulator.captureFrame(" ..
        math.Clamp(GetConVar("emu_stream_quality"):GetInt(), 20, 60) .. ");")
end)

function emu.SendVideoFrame(target, data)
    if not demanded[target] or not runningFrame(target) or type(data) ~= "string" or #data > 80000 then return end
    local jpeg = util.Base64Decode(data)
    if not jpeg or #jpeg == 0 or #jpeg > 60000 then return end
    local reliable, fits = uploadMode(#jpeg + 32)
    if not fits then return end
    net.Start("emu_video_frame", not reliable)
    net.WriteEntity(target)
    net.WriteUInt(#jpeg, 16)
    net.WriteData(jpeg, #jpeg)
    net.SendToServer()
    sentFrames = sentFrames + 1
end

function emu.SendAudioFrame(target, data, sampleRate)
    if not demanded[target] or not runningFrame(target) or type(data) ~= "string" then return end
    local samples = util.Base64Decode(data) -- 8-bit mu-law, one byte per sample.
    sampleRate = math.Clamp(tonumber(sampleRate) or 11025, 8000, 48000)
    if not samples or #samples == 0 or #samples > 12000 then return end
    local reliable, fits = uploadMode(#samples + 32)
    if not fits then return end
    net.Start("emu_audio_frame", not reliable)
    net.WriteEntity(target)
    net.WriteUInt(sampleRate, 16)
    net.WriteUInt(#samples, 16)
    net.WriteData(samples, #samples)
    net.SendToServer()
end

local upload
local function sendStateChunk()
    if not upload or not IsValid(upload.target) or upload.target:GetRomName() ~= upload.rom then upload = nil return end
    local offset = upload.offset
    local size = math.min(8192, #upload.data - offset)
    upload.expected, upload.sent = offset + size, RealTime()
    net.Start("emu_state_snapshot")
    net.WriteEntity(upload.target) net.WriteString(upload.rom)
    net.WriteUInt(#upload.data, 24) net.WriteUInt(offset, 24) net.WriteUInt(size, 16)
    net.WriteData(string.sub(upload.data, offset + 1, offset + size), size)
    net.SendToServer()
end
net.Receive("emu_state_upload_ack", function()
    local target, rom, offset = net.ReadEntity(), net.ReadString(), net.ReadUInt(24)
    if not upload or upload.target ~= target or upload.rom ~= rom or upload.expected ~= offset then return end
    upload.offset = offset
    if offset == #upload.data then upload = nil else sendStateChunk() end
end)
hook.Add("Think", "Emu_StateUploadTimeout", function()
    if upload and (not IsValid(upload.target) or RealTime() - upload.sent > 10 or RealTime() - upload.started > 120) then upload = nil end
end)
function emu.SendHandoffState(target, rom, encoded)
    if not IsValid(target) or type(rom) ~= "string" or type(encoded) ~= "string" then return end
    if #encoded > 6 * 1024 * 1024 then return end
    local data = util.Base64Decode(encoded)
    if not data or #data < 1 or #data > 4 * 1024 * 1024 then return end
    -- One bounded chunk in flight. Repeated close callbacks cannot enqueue
    -- another multi-megabyte snapshot behind an existing transfer.
    if upload then return end
    upload = {target = target, rom = rom, data = data, offset = 0, started = RealTime()}
    sendStateChunk()
end

local function createRemotePanel(target)
    local profile = emu.GetSystem and emu.GetSystem(target) or nil
    local aspect = profile and profile.aspectRatio or (4 / 3)
    local panelHeight = math.max(1, math.floor(STREAM_SIZE / aspect + 0.5))
    local panel = vgui.Create("DHTML", vgui.GetWorldPanel())
    -- Keep the captured canvas at the core's native aspect ratio. The render
    -- target remains square, while DrawHTMLScreen fits this panel into the
    -- physical screen region without stretching gameplay pixels.
    panel:SetSize(STREAM_SIZE, panelHeight)
    panel:SetPos(0, 0)
    panel:SetPaintedManually(true)
    panel:SetMouseInputEnabled(false)
    panel:SetKeyboardInputEnabled(false)
    panel:SetVisible(true)
    panel.OnDocumentReady = function(self) self.StreamReady = true end
    panel:SetHTML([[<html><head><style>html,body,img{margin:0;width:100%;height:100%;overflow:hidden;background:#000}</style></head><body><img id='frame'><script>
        (function(){var ctx=null,next=0,gain=null,volume=0.8,table=new Float32Array(256);
        for(var b=0;b<256;b++){var u=~b&255,m=(Math.pow(256,(u&127)/127)-1)/255;table[b]=u&128?-m:m;}
        window.gemuSetVolume=function(v){volume=Math.max(0,Math.min(1,Number(v)||0));if(gain)gain.gain.value=volume;};
        window.gemuPlayAudio=function(encoded,rate){try{
            if(!ctx)ctx=new(window.AudioContext||window.webkitAudioContext)({sampleRate:Number(rate)||11025});
            if(ctx.state==='suspended'){ctx.resume();return;}
            if(ctx.state!=='running'||next>ctx.currentTime+0.25)return;
            if(!gain){gain=ctx.createGain();gain.gain.value=volume;gain.connect(ctx.destination);}
            var binary=atob(encoded),buf=ctx.createBuffer(1,binary.length,Number(rate)||11025),out=buf.getChannelData(0);
            for(var i=0;i<out.length;i++)out[i]=table[binary.charCodeAt(i)];
            var source=ctx.createBufferSource();source.buffer=buf;source.connect(gain);var when=Math.max(ctx.currentTime+0.02,next);source.start(when);next=when+buf.duration;
        }catch(err){}};window.addEventListener('click',function(){if(ctx&&ctx.resume)ctx.resume();});})();
    </script></body></html>]])
    return panel
end

net.Receive("emu_video_frame", function()
    local target = net.ReadEntity()
    local serial = net.ReadUInt(32)
    local rom = net.ReadString()
    local size = net.ReadUInt(16)
    if not IsValid(target) or size == 0 or size > 60000 then return end
    if target:GetRomName() ~= rom then return end
    local jpeg = net.ReadData(size)
    if not jpeg or #jpeg ~= size then return end

    local stream = emu.RemoteStreams[target]
    if stream and (stream.rom or stream.audioRom) ~= rom then
        if IsValid(stream.html) then stream.html:Remove() end
        emu.RemoteStreams[target], stream = nil, nil
    end
    if stream and stream.rom == rom then
        local delta = (serial - stream.serial) % 4294967296
        if delta == 0 or delta >= 2147483648 then return end
    end
    if not stream or not IsValid(stream.html) then
        stream = {html = createRemotePanel(target), serial = 0}
        emu.RemoteStreams[target] = stream
    end
    stream.serial, stream.rom = serial, rom
    stream.lastSeen = RealTime()
    stream.lastVideoSeen = stream.lastSeen
    stream.videoBytes = (stream.videoBytes or 0) + size
    stream.videoFrames = (stream.videoFrames or 0) + 1
    stream.started = stream.started or stream.lastSeen
    stream.pending = util.Base64Encode(jpeg)
end)

net.Receive("emu_audio_frame", function()
    local target = net.ReadEntity()
    local serial = net.ReadUInt(32)
    local rom = net.ReadString()
    local sampleRate = net.ReadUInt(16)
    local size = net.ReadUInt(16)
    if not IsValid(target) or size == 0 or size > 12000 or sampleRate < 8000 or sampleRate > 48000 then return end
    if target:GetRomName() ~= rom then return end
    local samples = net.ReadData(size)
    if not samples or #samples ~= size then return end
    local stream = emu.RemoteStreams[target]
    if stream and (stream.rom or stream.audioRom) ~= rom then
        if IsValid(stream.html) then stream.html:Remove() end
        emu.RemoteStreams[target], stream = nil, nil
    end
    if stream and stream.audioRom == rom then
        local delta = (serial - (stream.audioSerial or 0)) % 4294967296
        if delta == 0 or delta >= 2147483648 then return end
    end
    if not stream or not IsValid(stream.html) then
        stream = {html = createRemotePanel(target), serial = 0}
        emu.RemoteStreams[target] = stream
    end
    stream.audioSerial, stream.audioRom, stream.lastSeen = serial, rom, RealTime()
    stream.audioQueue = stream.audioQueue or {}
    if #stream.audioQueue >= 3 then table.remove(stream.audioQueue, 1) end
    stream.audioQueue[#stream.audioQueue + 1] = {
        data = util.Base64Encode(samples), sampleRate = sampleRate, received = RealTime()
    }
end)

-- Audio must keep playing when a viewer turns away from the screen. Drain it
-- independently of render-target updates and discard delayed audio instead of
-- replaying it after a stalled browser or a frame-rate hitch.
hook.Add("Think", "Emu_PlayRemoteAudio", function()
    local now = RealTime()
    local volume = math.Clamp(GetConVar("emu_volume"):GetFloat(), 0, 1)
    for target, stream in pairs(emu.RemoteStreams) do
        local effectiveVolume = emu.IsRTCReceiving and emu.IsRTCReceiving(target) and 0 or volume
        if IsValid(target) and IsValid(stream.html) and stream.html.StreamReady
            and target:GetRomName() == stream.audioRom then
            if stream.volume ~= effectiveVolume then
                stream.html:QueueJavascript("if(window.gemuSetVolume)gemuSetVolume(" .. effectiveVolume .. ");")
                stream.volume = effectiveVolume
            end
            for _, packet in ipairs(stream.audioQueue or {}) do
                if now - packet.received <= 0.25 then
                    stream.html:QueueJavascript("if(window.gemuPlayAudio)gemuPlayAudio('" .. packet.data .. "'," .. packet.sampleRate .. ");")
                end
            end
            stream.audioQueue = {}
        end
    end
end)

function emu.GetRemoteScreen(target)
    local stream = emu.RemoteStreams[target]
    if not stream or not IsValid(stream.html) or not stream.lastVideoSeen then return end
    -- A paused runner sends no frames; keep showing the frozen picture.
    if RealTime() - stream.lastVideoSeen > STREAM_TIMEOUT and not emu.IsSessionPaused(target) then return end
    if not IsValid(target) or target:GetRomName() ~= stream.rom then return end
    if stream.pending and stream.html.StreamReady then
        stream.html:QueueJavascript("document.getElementById('frame').src='data:image/jpeg;base64," .. stream.pending .. "';")
        stream.pending = nil
    end
    stream.html:UpdateHTMLTexture()
    return stream.html, stream.serial
end

-- Frames stopped arriving from a running, unpaused game: show RECONNECTING.
function emu.HasStaleRemoteStream(target)
    local stream = emu.RemoteStreams[target]
    return stream ~= nil and stream.lastVideoSeen ~= nil and RealTime() - stream.lastVideoSeen > STREAM_TIMEOUT
end

local nextCleanup = 0
hook.Add("Think", "Emu_CleanupRemoteStreams", function()
    if RealTime() < nextCleanup then return end
    nextCleanup = RealTime() + 1
    for target, stream in pairs(emu.RemoteStreams) do
        if not IsValid(target) or (RealTime() - (stream.lastSeen or 0) > STREAM_TIMEOUT + 2
            and not emu.IsSessionPaused(target)) then
            if IsValid(stream.html) then stream.html:Remove() end
            emu.RemoteStreams[target] = nil
        end
    end
end)

hook.Add("EntityRemoved", "Emu_RemoveStreamEntity", function(target)
    demanded[target] = nil
    local stream = emu.RemoteStreams[target]
    if stream and IsValid(stream.html) then stream.html:Remove() end
    emu.RemoteStreams[target] = nil
end)

hook.Add("ShutDown", "Emu_RemoveRemoteStreams", function()
    for _, stream in pairs(emu.RemoteStreams) do
        if IsValid(stream.html) then stream.html:Remove() end
    end
end)

concommand.Add("emu_stream_status", function()
    local target = emu.ActiveTarget
    print("[GEMU stream] capture requested=" .. tostring(IsValid(target) and demanded[target] == true)
        .. " running=" .. tostring(runningFrame(target) ~= nil) .. " paused=" .. tostring(emu.IsSessionPaused(target))
        .. " reliable=" .. tostring(GetGlobalBool and GetGlobalBool("EmuStreamReliable", false) or false)
        .. " sent=" .. sentFrames)
    for entity, stream in pairs(emu.RemoteStreams) do
        if IsValid(entity) then
            print("[GEMU stream] entity=" .. entity:EntIndex() .. " ROM=" .. tostring(stream.rom)
                .. " frame=" .. stream.serial .. " age=" .. string.format("%.2fs", RealTime() - stream.lastSeen)
                .. " browser ready=" .. tostring(IsValid(stream.html) and stream.html.StreamReady == true)
                .. " video age=" .. string.format("%.2fs", RealTime() - (stream.lastVideoSeen or 0))
                .. " avg JPEG=" .. math.floor((stream.videoBytes or 0) / math.max(1, stream.videoFrames or 0)) .. " bytes")
        end
    end
end)

concommand.Add("emu_stream_capabilities", function()
    local frame = emu.ActiveWindow
    if not IsValid(frame) or not IsValid(frame.HTML) then
        print("[GEMU stream] Open a GEMU game first to inspect its CEF media capabilities.")
        return
    end
    frame.HTML:AddFunction("gemuProbe", "report", function(report)
        print("[GEMU stream capabilities] " .. tostring(report):sub(1, 12000))
    end)
    frame.HTML:QueueJavascript([[
        (function(){var c=document.createElement('canvas');
        var A=window.AudioContext||window.webkitAudioContext;
        var caps={userAgent:navigator.userAgent,secureContext:window.isSecureContext===true,
            peerConnection:typeof window.RTCPeerConnection==='function',
            canvasCapture:typeof c.captureStream==='function',
            audioCapture:!!(A&&A.prototype.createMediaStreamDestination),
            audioWorklet:typeof window.AudioWorkletNode==='function',
            videoEncoder:typeof window.VideoEncoder==='function',
            videoCodecs:[],audioCodecs:[]};
        try{if(window.RTCRtpSender&&RTCRtpSender.getCapabilities){
            caps.videoCodecs=RTCRtpSender.getCapabilities('video').codecs;
            caps.audioCodecs=RTCRtpSender.getCapabilities('audio').codecs;
        }}catch(e){caps.error=String(e);}
        gemuProbe.report(JSON.stringify(caps));})();
    ]])
end)
