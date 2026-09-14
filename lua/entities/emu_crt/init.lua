-- CRT Display Entity Server
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel(emu.Systems.snes.display.model)
    self:SetUseType(SIMPLE_USE)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetSkin(1) -- Default static snow skin
end

function ENT:PreEntityCopy()
    if not duplicator or not duplicator.StoreEntityModifier then return end
    local console = self:GetLinkedConsole()
    duplicator.StoreEntityModifier(self, "EmuLinks", IsValid(console) and {console = console:EntIndex()} or {})
end

function ENT:PostEntityPaste(_, ent, createdEntities)
    local links = ent.EntityMods and ent.EntityMods.EmuLinks
    local console = links and emu.PastedEntity(createdEntities, links.console)
    if IsValid(console) then
        self:SetLinkedConsole(console)
        console:SetLinkedDisplay(self)
    end
end

function ENT:Use(ply, caller, useType, value)
    local console = self:GetLinkedConsole()
    if IsValid(console) then
        console:Use(ply, caller, useType, value)
    end
end

function ENT:OnRemove()
    local console = self:GetLinkedConsole()
    if IsValid(console) then
        emu.ReleaseConsole(console)
        console:SetLinkedDisplay(NULL)
    end
end
