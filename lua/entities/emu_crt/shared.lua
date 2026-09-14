-- CRT Display Entity Shared
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "CRT Television"
ENT.Author = "Nighthawk"
ENT.Category = "GEMU - Consoles"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.IsEmuCRT = true

function ENT:SpawnFunction(ply, tr, ClassName)
    if not tr.Hit then return end
    local ent = ents.Create(ClassName)
    if not IsValid(ent) then return end
    ent:SetPos(tr.HitPos + tr.HitNormal * 16)
    ent:SetAngles(Angle(0, ply:EyeAngles().yaw + 180, 0))
    ent:Spawn()
    ent:Activate()
    ent:SetCreator(ply)
    ply:AddCleanup("emulators", ent)
    return ent
end

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "LinkedConsole")
end

ENT.IconOverride = "gemu/icons/crt_console.png"
