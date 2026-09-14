if not CLIENT then return end
local sessions = {}
local function remove(target)
    local state = sessions[target]
    if state and IsValid(state.html) then
        if state.role == "view" then state.html:Remove()
        else state.html:QueueJavascript("if(window.GEMUStream)GEMUStream.stop();") end
    end
    sessions[target] = nil
end
function emu.IsRTCReceiving(target)
    local state = sessions[target]
    return state and state.role == "view" and IsValid(state.html) and IsValid(target)
        and state.rom == target:GetRomName() and state.expires > RealTime()
        and state.healthy and RealTime() - (state.statusAt or 0) < 2 or false
end
function emu.GetRTCRemoteScreen(target)
    if not emu.IsRTCReceiving(target) then return end
    local html = sessions[target].html
    html:UpdateHTMLTexture()
    return html
end
net.Receive("emu_rtc_config", function()
    local target, active = net.ReadEntity(), net.ReadBool()
    if not active then remove(target) return end
    local id, rom, role = net.ReadString(), net.ReadString(), net.ReadString()
    local room, url, token, viewerURL = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()
    if not IsValid(target) or (role ~= "view" and role ~= "publish") then return end
    local state = sessions[target]
    if state and (state.id ~= id or state.role ~= role or state.rom ~= rom) then remove(target) state = nil end
    state = state or {id = id, rom = rom, role = role}
    state.config = {room = room, url = url, token = token}
    state.viewerURL, state.expires, state.dirty = viewerURL, RealTime() + 12, true
    sessions[target] = state
end)
hook.Add("Think", "Emu_RTCPlayback", function()
    for target, state in pairs(sessions) do
        if not IsValid(target) or state.expires < RealTime() or target:GetRomName() ~= state.rom then
            remove(target)
        else
            if state.role == "publish" then
                local frame = emu.ActiveWindow
                -- Publish from the running session whether or not its player holds the controls.
                local html = emu.ActiveTarget == target and IsValid(frame) and frame.Ready and not frame.Closing and frame.HTML or nil
                if state.html ~= html then
                    if IsValid(state.html) then state.html:QueueJavascript("if(window.GEMUStream)GEMUStream.stop();") end
                    state.html, state.bound, state.dirty = html, false, true
                end
            elseif not IsValid(state.html) then
                local profile = emu.GetSystem(target)
                local html = vgui.Create("DHTML", vgui.GetWorldPanel())
                html:SetSize(512, math.floor(512 / (profile and profile.aspectRatio or (4 / 3)) + 0.5))
                html:SetPos(0, 0) html:SetPaintedManually(true) html:SetVisible(true)
                html:SetMouseInputEnabled(false) html:SetKeyboardInputEnabled(false)
                state.html, state.bound = html, false
                -- Patched CEF (GModPatchTool, Site Isolation) discards JS objects bound
                -- before a page loads, so rebind the status callback on every load.
                html.OnDocumentReady = function() state.bound, state.dirty = false, true end
                html:OpenURL(state.viewerURL)
            end
            if IsValid(state.html) then
                if not state.bound and not state.html:IsLoading() then
                    state.html:AddFunction("gemuRTC", "status", function(ok, detail)
                        if sessions[target] ~= state then return end
                        state.healthy, state.statusAt, state.detail = ok == true, RealTime(), tostring(detail)
                    end)
                    state.bound = true
                end
                if state.dirty or RealTime() >= (state.nextPush or 0) then
                    -- Retry page initialization, but never extend an expired server lease.
                    -- A paused publisher sends no new frames; tell viewers so they stay healthy.
                    local paused = emu.IsSessionPaused and emu.IsSessionPaused(target) or false
                    state.html:QueueJavascript("if(window.GEMUStream){GEMUStream.configure(" .. util.TableToJSON(state.config)
                        .. ");if(GEMUStream.setPaused)GEMUStream.setPaused(" .. tostring(paused) .. ");}")
                    state.dirty, state.nextPush = false, RealTime() + 2
                end
                if state.role == "view" and RealTime() >= (state.nextAck or 0) then
                    local ok = emu.IsRTCReceiving(target)
                    local volume = ok and math.Clamp(GetConVar("emu_volume"):GetFloat(), 0, 1) or 0
                    state.html:QueueJavascript("if(window.GEMUStream)GEMUStream.setVolume(" .. volume .. ");")
                    net.Start("emu_rtc_ready") net.WriteEntity(target) net.WriteString(state.id) net.WriteBool(ok) net.SendToServer()
                    state.nextAck = RealTime() + 1
                end
            end
        end
    end
end)
hook.Add("EntityRemoved", "Emu_RTCRemove", remove)
hook.Add("ShutDown", "Emu_RTCShutdown", function() for target in pairs(sessions) do remove(target) end end)
concommand.Add("emu_rtc_status", function()
    for target, state in pairs(sessions) do
        print("[GEMU RTC] entity=" .. tostring(target:EntIndex()) .. " role=" .. state.role .. " healthy=" .. tostring(state.healthy)
            .. " status=" .. tostring(state.detail or "connecting"))
    end
end)
