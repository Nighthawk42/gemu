-- Common authorization for explicit actions and physics-driven cartridge docking.
if not SERVER then return end
emu = emu or {}

function emu.GetSetupTarget(ent)
    if not IsValid(ent) then return end
    if ent.IsEmuCRT then
        local console = ent:GetLinkedConsole()
        return IsValid(console) and console or ent
    end
    if ent.IsEmuCartridge and ent:GetIsInserted() then
        local console = ent:GetCurrentConsole()
        return IsValid(console) and console or ent
    end
    return ent
end

function emu.GetDeviceOwner(ent)
    if ent.IsEmuHandheld then return ent:GetOwner() end
    local owner = ent.CPPIGetOwner and ent:CPPIGetOwner()
    if IsValid(owner) then return owner end
    return ent:GetCreator()
end

function emu.CanManage(ply, ent)
    ent = emu.GetSetupTarget(ent)
    if not IsValid(ply) or not ply:IsPlayer() or not IsValid(ent) then return false end
    if not (ent.IsEmuConsole or ent.IsEmuCRT or ent.IsEmuHandheld or ent.IsEmuCartridge) then return false end
    local controller = ent.GetControllingPlayer and ent:GetControllingPlayer()
    if IsValid(controller) and controller ~= ply then return false end
    if ply:IsAdmin() or controller == ply then return true end
    local owner = emu.GetDeviceOwner(ent)
    return not IsValid(owner) or owner == ply
end

function emu.CanInsertCartridge(ply, target, cart)
    if not IsValid(target) or not IsValid(cart) then return false end
    if IsValid(ply) then return emu.CanManage(ply, target) and emu.CanManage(ply, cart) end
    -- Touch callbacks have no player argument. Use a recent physics mover first;
    -- otherwise only allow docking on behalf of the cartridge/setup owner.
    for _, ent in ipairs({cart, target}) do
        if IsValid(ent.EmuLastMover) and CurTime() < (ent.EmuMoverUntil or 0) then
            return emu.CanManage(ent.EmuLastMover, target) and emu.CanManage(ent.EmuLastMover, cart)
        end
    end
    local owner = emu.GetDeviceOwner(cart)
    if not IsValid(owner) then owner = emu.GetDeviceOwner(target) end
    if IsValid(owner) then return emu.CanManage(owner, target) and emu.CanManage(owner, cart) end
    local controller = target.GetControllingPlayer and target:GetControllingPlayer()
    return not IsValid(controller) -- Unowned world props may dock only while idle.
end

local function relevant(ent)
    return IsValid(ent) and (ent.IsEmuConsole or ent.IsEmuCRT or ent.IsEmuHandheld or ent.IsEmuCartridge)
end
local function protect(ply, ent)
    if relevant(ent) and not emu.CanManage(ply, ent) then return false end
end
local function rememberMover(ply, ent)
    if relevant(ent) then ent.EmuLastMover=ply ent.EmuMoverUntil=CurTime()+3 end
end
hook.Add("PhysgunPickup", "Emu_ProtectPhysics", protect)
hook.Add("GravGunPickupAllowed", "Emu_ProtectGravgun", protect)
hook.Add("GravGunPunt", "Emu_ProtectPunt", protect)
hook.Add("PhysgunDrop", "Emu_RememberPhysicsMover", rememberMover)
hook.Add("GravGunOnDropped", "Emu_RememberGravgunMover", rememberMover)
hook.Add("CanTool", "Emu_ProtectTools", function(ply, trace) return protect(ply, trace.Entity) end)
hook.Add("CanProperty", "Emu_ProtectProperties", function(ply, _, ent) return protect(ply, ent) end)
