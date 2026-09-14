-- Shared rules for physical console stations and player-owned handhelds.
emu = emu or {}
emu.UseDistance = 160
emu.PlayDistance = 192

function emu.GetSystem(target)
    local id = IsValid(target) and target.GetSystemId and target:GetSystemId() or nil
    local systems = emu.Systems or {}
    return systems[id] or systems.snes or {id = "snes", interaction = "console"}
end

function emu.IsHandheld(target)
    return IsValid(target) and (target.IsEmuHandheld or emu.GetSystem(target).interaction == "handheld")
end

function emu.IsNearSetup(ply, console, distance)
    if not IsValid(ply) or not IsValid(console) then return false end
    local origin = ply:GetShootPos()
    if origin:DistToSqr(console:WorldSpaceCenter()) <= distance * distance then return true end
    local crt = console:GetLinkedDisplay()
    return IsValid(crt) and origin:DistToSqr(crt:WorldSpaceCenter()) <= distance * distance
end

function emu.CanPlay(ply, console, allowUnpowered)
    local enabled = GetConVar("emu_sv_enabled")
    if enabled and not enabled:GetBool() then return false end
    if not IsValid(ply) or not ply:Alive() or ply:InVehicle() then return false end
    if not IsValid(console) or not console.IsEmuConsole then return false end
    local owner = console.GetControllingPlayer and console:GetControllingPlayer()
    if IsValid(owner) and owner ~= ply then return false end
    local crt = console:GetLinkedDisplay()
    return (allowUnpowered or console:GetPower()) and console:GetHasCartridge()
        and IsValid(crt) and crt:GetLinkedConsole() == console
        and emu.IsNearSetup(ply, console, emu.PlayDistance)
end

function emu.CanUseTarget(ply, target, allowUnpowered)
    if emu.IsHandheld(target) then
        local enabled = GetConVar("emu_sv_enabled")
        if enabled and not enabled:GetBool() then return false end
        return IsValid(ply) and ply:Alive() and not ply:InVehicle()
            and target:IsWeapon() and target:GetOwner() == ply
            and target.GetHasCartridge and target:GetHasCartridge()
    end
    return emu.CanPlay(ply, target, allowUnpowered)
end

function emu.CanFocusTarget(ply, target)
    if not emu.CanUseTarget(ply, target) then return false end
    if emu.IsHandheld(target) then return ply:GetActiveWeapon() == target end
    return true
end

-- The player whose client emulates the device. Handhelds belong to their holder.
function emu.GetSessionRunner(target)
    if not IsValid(target) then return NULL end
    if emu.IsHandheld(target) then return target:GetOwner() end
    return target.GetControllingPlayer and target:GetControllingPlayer() or NULL
end

-- A running session survives distance, death, vehicles and closed windows;
-- only losing the device or its cartridge, power or display ends it.
function emu.CanKeepSession(ply, target, allowUnpowered)
    local enabled = GetConVar("emu_sv_enabled")
    if enabled and not enabled:GetBool() then return false end
    if not IsValid(ply) or not IsValid(target) then return false end
    if emu.IsHandheld(target) then
        return target:GetOwner() == ply and target.GetHasCartridge and target:GetHasCartridge() or false
    end
    if not target.IsEmuConsole then return false end
    local runner = target.GetControllingPlayer and target:GetControllingPlayer()
    if IsValid(runner) and runner ~= ply then return false end
    local crt = target:GetLinkedDisplay()
    return (allowUnpowered or target:GetPower()) and target:GetHasCartridge()
        and IsValid(crt) and crt:GetLinkedConsole() == target or false
end

function emu.GetTargetRom(target)
    -- Keep the old NetworkVar for saved entities, but never use a per-cart host.
    return target:GetGameTitle(), target:GetRomName(), ""
end
