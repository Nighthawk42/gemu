-- Per-device power materials. Never mutate the globally shared model materials.
if not CLIENT then return end
emu = emu or {}
local originals = {snes="snes/snes",nes="nes/nes",genesis="genesis/genesis",
    gb="gameboy/gameboy",gbc="gameboy/gameboy_color",gba="gameboy/gba"}
local poweredMaterials = {}

function emu.IsDevicePowered(source)
    if not IsValid(source) then return false end
    if not emu.IsHandheld(source) then return source:GetPower() end
    if not source:GetHasCartridge() then return false end
    local frame = emu.ActiveWindow
    return (emu.ActiveTarget == source and IsValid(frame) and frame.Ready and not frame.Error)
        or (emu.IsRTCReceiving and emu.IsRTCReceiving(source)) or IsValid(emu.GetRemoteScreen(source))
end

function emu.ApplyPowerLED(model, source)
    local id = emu.GetSystem(source).id
    if not originals[id] then return end
    if not emu.IsDevicePowered(source) then model:SetSubMaterial(0, nil) return end
    if not poweredMaterials[id] then
        local values = table.Copy(Material("models/unconid/" .. originals[id]):GetKeyValues())
        -- Runtime material flags are engine-owned, not CreateMaterial parameters.
        for key in pairs(values) do
            if tostring(key):lower():find("$flags", 1, true) == 1 then values[key] = nil end
        end
        -- The GBA atlas is white; its original VMT supplies the shell tint via
        -- TF2 item proxies, which GetKeyValues does not preserve reliably.
        if id == "gba" then
            values["$color2"] = "{ 64 81 133 }"
            values["$colortint_base"] = "{ 64 81 133 }"
            values["Proxies"], values["proxies"] = nil, nil
        end
        values["$basetexture"] = "gemu/power/" .. id .. "_on"
        values["$selfillummask"] = "gemu/power/" .. id .. "_mask"
        values["$selfillum"] = "1"
        values[">=dx90"], values[">=DX90"] = nil, nil
        poweredMaterials[id] = CreateMaterial("gemu_power_" .. id, "VertexLitGeneric", values)
    end
    model:SetSubMaterial(0, "!" .. poweredMaterials[id]:GetName())
end

local crtLED = CreateMaterial("gemu_crt_power", "UnlitGeneric", {
    ["$basetexture"]="models/ivip/cineos/red", ["$model"]="1"
})
function emu.ApplyTVPowerLED(display, source)
    display:SetSubMaterial(7, IsValid(source) and source:GetPower() and "!" .. crtLED:GetName() or nil)
end
