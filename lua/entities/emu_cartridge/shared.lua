-- SNES Cartridge Entity Shared
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "SNES Cartridge"
ENT.Author = "Nighthawk"
ENT.Category = "GEMU - SNES"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.IsEmuCartridge = true
ENT.Editable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "SystemId")
    self:NetworkVar("String", 1, "RomName", {KeyName="romname", Edit={type="Generic", order=1}})
    self:NetworkVar("String", 2, "RomUrl")
    self:NetworkVar("String", 3, "GameTitle", {KeyName="gametitle", Edit={type="Generic", order=2}})
    self:NetworkVar("Int", 0, "CartridgeSkin")
    self:NetworkVar("Bool", 0, "IsInserted")
    self:NetworkVar("Bool", 1, "BlankCartridge")
    self:NetworkVar("Entity", 0, "CurrentConsole")
end

function ENT:SpawnFunction(ply, tr, ClassName)
    if not tr.Hit then return end

    local spawnPos = tr.HitPos + tr.HitNormal * 2
    -- Angle(0, yaw - 90, 0) lays the cartridge flat with the label facing UP and readable right-side up
    local spawnAng = Angle(0, ply:EyeAngles().yaw - 90, 0)

    local ent = ents.Create(ClassName)
    if not IsValid(ent) then return end
    ent:SetPos(spawnPos)
    ent:SetAngles(spawnAng)
    ent:Spawn()
    ent:Activate()
    if SERVER then
        ent:SetCreator(ply)
        ply:AddCleanup("emulators", ent)
    end
    return ent
end
