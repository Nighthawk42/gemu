-- Shared display pipeline. Profiles supply screen UVs; devices only apply the material.
if not CLIENT then return end
emu = emu or {}
emu.DisplaySlots = emu.DisplaySlots or {}
local slots, SIZE = emu.DisplaySlots, 512

surface.CreateFont("Emu_ScreenTitle", {font = "Arial", size = 28, weight = 800})
surface.CreateFont("Emu_ScreenText", {font = "Arial", size = 22, weight = 600})
surface.CreateFont("Emu_ScreenHint", {font = "Arial", size = 18, weight = 600})

local function getSlot(owner, source)
    for _, slot in ipairs(slots) do
        if slot.owner == owner and slot.source == source then return slot end
    end
    local slot
    for _, candidate in ipairs(slots) do
        if not IsValid(candidate.owner) or candidate.owner == owner then slot = candidate break end
    end
    if not slot then
        local name = "emu_display_" .. (#slots + 1)
        local rt = GetRenderTarget(name, SIZE, SIZE, false)
        slot = {rt = rt, material = CreateMaterial(name, "UnlitGeneric", {
            ["$basetexture"] = rt:GetName(), ["$model"] = "1", ["$translucent"] = "0"
        })}
        slots[#slots + 1] = slot
    end
    slot.owner, slot.source, slot.signature, slot.wasLive = owner, source, nil, false
    return slot
end

function emu.ApplyScreen(display, source)
    if not IsValid(display) or not IsValid(source) then return end
    if not source:GetPower() then
        display:SetSubMaterial()
        display:SetSkin(1)
        local slot = getSlot(display, source)
        slot.signature, slot.wasLive = nil, false
        return
    end
    local slot = getSlot(display, source)
    slot.lastSeen = RealTime()
    for _, index in ipairs(emu.GetSystem(source).display.screenMaterials) do
        display:SetSubMaterial(index, "!" .. slot.material:GetName())
    end
end

function emu.ApplyHandheldScreen(model, source)
    if not IsValid(model) or not IsValid(source) or not emu.IsHandheld(source) then return end
    local slot = getSlot(source, source)
    slot.lastSeen = RealTime()
    model:SetSubMaterial(emu.GetSystem(source).screenMaterial, "!" .. slot.material:GetName())
end

function emu.DrawHTMLScreen(html, x, y, w, h, stretch, aspect)
    if not IsValid(html) then return false end
    local mat = html:GetHTMLMaterial()
    local tex = mat and mat:GetTexture("$basetexture")
    if not tex then return false end
    local pw, ph = html:GetSize()
    if pw <= 0 or ph <= 0 then return false end
    aspect = aspect or (4 / 3)
    local factor = math.min(w / aspect, h)
    local dw, dh = stretch and w or aspect * factor, stretch and h or factor
    surface.SetMaterial(mat)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(x + (w - dw) / 2, y + (h - dh) / 2, dw, dh,
        0, 0, pw / tex:Width(), ph / tex:Height())
    return true
end

local function screenRegion(profile)
    if profile.screenUV then
        local uv = profile.screenUV
        return uv.x * SIZE, uv.y * SIZE, uv.w * SIZE, uv.h * SIZE
    end
    -- Compensate for the physical TV's aspect ratio in texture space.
    local width = SIZE * profile.aspectRatio / profile.display.screenAspect
    return (SIZE - width) / 2, 0, width, SIZE
end

local function drawGrid(x, y, w, h)
    surface.SetDrawColor(120, 120, 120, 255)
    for i = 0, 8 do
        surface.DrawLine(x + i * w / 8, y, x + i * w / 8, y + h)
        surface.DrawLine(x, y + i * h / 8, x + w, y + i * h / 8)
    end
    draw.SimpleText("TOP LEFT", "Emu_ScreenText", x + 8, y + 8, Color(255, 80, 80))
    draw.SimpleText("TOP RIGHT", "Emu_ScreenText", x + w - 8, y + 8, Color(80, 255, 80), TEXT_ALIGN_RIGHT)
    draw.SimpleText("BOTTOM", "Emu_ScreenText", x + w / 2, y + h - 30, color_white, TEXT_ALIGN_CENTER)
end

-- What a screen without live video says. Another player's running game is
-- never advertised as free to play.
local function screenStatus(source, profile, hasCart, localFrame, paused)
    if not hasCart then return "INSERT A CARTRIDGE" end
    if localFrame and localFrame.Error then return "UNABLE TO LOAD GAME" end
    if localFrame and not localFrame.Ready then return "BOOTING..." end
    local runner = emu.GetSessionRunner(source)
    local remote = not localFrame and IsValid(runner) and runner ~= LocalPlayer()
        and (not emu.IsHandheld(source) or paused or (emu.RemoteStreams or {})[source] ~= nil)
    if remote then
        if paused then return "PAUSED" end
        if emu.HasStaleRemoteStream and emu.HasStaleRemoteStream(source) then return "RECONNECTING..." end
        return string.upper(string.sub(runner:Nick(), 1, 20)) .. " IS PLAYING"
    end
    return profile.interaction == "handheld" and "PRESS LMB TO PLAY" or "PRESS E TO PLAY"
end

hook.Add("PreRender", "Emu_UpdateScreens", function()
    local frame = emu.ActiveWindow
    local html = IsValid(frame) and frame.HTML
    if IsValid(html) then html:UpdateHTMLTexture() end
    for _, slot in ipairs(slots) do
        local source = slot.source
        if IsValid(slot.owner) and IsValid(source) and RealTime() - (slot.lastSeen or 0) < 0.5
            and (emu.IsHandheld(source) or source:GetPower()) then
            local profile = emu.GetSystem(source)
            local hasCart, title = source:GetHasCartridge(), source:GetGameTitle()
            local localSession = emu.ActiveTarget == source and IsValid(frame)
            local controlsOpen = localSession and frame:IsVisible()
            local localLive = hasCart and localSession and not controlsOpen and IsValid(html)
                and frame.Ready and frame.LoadedGame and not frame.Error
            local remoteHTML = (emu.GetRTCRemoteScreen and emu.GetRTCRemoteScreen(source)) or emu.GetRemoteScreen(source)
            local remoteLive = hasCart and not localLive and IsValid(remoteHTML)
            local live = localLive or remoteLive
            local paused = localSession and frame.Paused == true
                or (not localSession and emu.IsSessionPaused and emu.IsSessionPaused(source)) or false
            local grid = GetConVar("emu_screen_grid"):GetBool()
            local status = screenStatus(source, profile, hasCart, localSession and frame or nil, paused)
            local signature = tostring(hasCart) .. title .. tostring(live) .. tostring(grid) .. status .. tostring(paused)
            if (grid or not (controlsOpen and slot.wasLive)) and (live or slot.signature ~= signature) then
                local x, y, w, h = screenRegion(profile)
                render.PushRenderTarget(slot.rt)
                render.Clear(8, 10, 14, 255, true, true)
                cam.Start2D()
                local drawn = not grid and live and emu.DrawHTMLScreen(localLive and html or remoteHTML,
                    x, y, w, h, true, profile.aspectRatio)
                if grid then
                    drawGrid(x, y, w, h)
                elseif drawn then
                    -- The running page shows its own pause overlay; spectators get one here.
                    if paused and not localLive then
                        surface.SetDrawColor(0, 0, 0, 170)
                        surface.DrawRect(x, y + h / 2 - 26, w, 52)
                        draw.SimpleText("PAUSED", "Emu_ScreenTitle", x + w / 2, y + h / 2,
                            color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                else
                    draw.SimpleText(string.upper(profile.name), "Emu_ScreenTitle", x + w / 2, y + h * 0.18,
                        Color(165, 180, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    draw.SimpleText(hasCart and title or "No Cartridge", "Emu_ScreenText", x + w / 2, y + h / 2,
                        color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    draw.SimpleText(status, "Emu_ScreenHint", x + w / 2, y + h * 0.82,
                        Color(74, 222, 128), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                cam.End2D()
                render.PopRenderTarget()
                slot.signature, slot.wasLive = signature, drawn == true
            end
        end
    end
end)

hook.Add("EntityRemoved", "Emu_ReleaseDisplay", function(ent)
    for _, slot in ipairs(slots) do
        if slot.owner == ent or slot.source == ent then
            slot.owner, slot.source, slot.signature, slot.wasLive = nil, nil, nil, false
        end
    end
end)
