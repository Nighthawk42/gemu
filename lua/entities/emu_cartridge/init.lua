-- SNES Cartridge Entity Server
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    local profile = emu.Systems[self.SystemID or "snes"]
    self:SetSystemId(profile.id)
    self:SetModel(profile.cartridgeModel)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
    self:SetRomName(self.PresetRom or profile.defaultRom)
    self:SetGameTitle(self.PresetTitle or profile.defaultGame)
    self:SetRomUrl("")
    self:SetCartridgeSkin(self.PresetSkin or profile.defaultSkin)
    self:SetSkin(self:GetCartridgeSkin())
    self:SetIsInserted(false)
    self:SetBlankCartridge(self.PresetBlank == true)
end

function ENT:PreEntityCopy()
    if not duplicator or not duplicator.StoreEntityModifier then return end
    local console = self:GetCurrentConsole()
    duplicator.StoreEntityModifier(self, "EmuLinks", IsValid(console) and {console = console:EntIndex()} or {})
end

function ENT:PostEntityPaste(_, ent, createdEntities)
    local links = ent.EntityMods and ent.EntityMods.EmuLinks
    local console = links and emu.PastedEntity(createdEntities, links.console)
    if IsValid(console) then emu.RelinkConsole(console, console:GetLinkedDisplay(), self) end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or self:GetIsInserted() then return end
    if not GetConVar("emu_sv_enabled"):GetBool() or CurTime() < (self.NextInsertTime or 0) then return end
    if ply:GetShootPos():DistToSqr(self:WorldSpaceCenter()) > emu.UseDistance * emu.UseDistance then return end
    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) or not weapon.IsEmuHandheld or weapon:GetSystemId() ~= self:GetSystemId() then return end
    if not emu.CanInsertCartridge(ply, weapon, self) then
        ply:ChatPrint("GEMU: You do not own this cartridge or handheld.")
        return
    end
    if weapon:GetHasCartridge() and not IsValid(weapon:EjectCartridgeToWorld()) then return end
    weapon:InsertCartridge(self:GetGameTitle(), self:GetRomUrl(), self:GetRomName(), self:GetCartridgeSkin(), self:GetBlankCartridge())
    self:SetIsInserted(true)
    ply:EmitSound("items/ammo_pickup.wav", 65, 110)
    self:Remove()
end

function ENT:OnRemove()
    local console = self:GetCurrentConsole()
    if IsValid(console) and console:GetInsertedCart() == self then
        emu.ReleaseConsole(console)
        console:SetHasCartridge(false)
        console:SetInsertedCart(NULL)
        console:SetGameTitle("No Cartridge")
        console:SetRomName("")
        console:SetRomUrl("")
        console:SetCartridgeSkin(0)
        console:SetSkin(0)
        local profile = emu.GetSystem(console)
        if profile.cartridgeBodygroup then console:SetBodygroup(profile.cartridgeBodygroup, profile.cartridgeEmpty) end
    end
end
