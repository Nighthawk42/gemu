AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function SWEP:Deploy()
    self:SetHoldType("camera")
    return true
end

function SWEP:EjectCartridgeToWorld()
    local owner = self:GetOwner()
    if not IsValid(owner) or not self:GetHasCartridge() then return NULL end
    if not emu.CanManage(owner, self) then return NULL end
    local cart = ents.Create(emu.GetSystem(self).cartridgeClass)
    if not IsValid(cart) then return NULL end
    cart.PresetSkin = self:GetCartridgeSkin()
    cart:SetPos(owner:GetShootPos() + owner:GetForward() * 25 - owner:GetUp() * 5)
    cart:SetAngles(owner:EyeAngles())
    cart:Spawn()
    cart:Activate()
    cart:SetSystemId(self:GetSystemId())
    cart:SetGameTitle(self:GetGameTitle())
    cart:SetRomUrl(self:GetRomUrl())
    cart:SetRomName(self:GetRomName())
    cart:SetCartridgeSkin(self:GetCartridgeSkin())
    cart:SetSkin(self:GetCartridgeSkin())
    cart:SetBlankCartridge(self:GetBlankCartridge())
    cart.NextInsertTime = CurTime() + 1.5
    cart:SetCreator(owner)
    owner:AddCleanup("emulators", cart)
    local phys = cart:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:ApplyForceCenter((owner:GetForward() * 120 + Vector(0, 0, 50)) * phys:GetMass())
    end
    if owner.EmuSession == self then emu.EndSession(owner, true) end
    self:SetGameTitle("No Cartridge")
    self:SetRomUrl("")
    self:SetRomName("")
    self:SetCartridgeSkin(0)
    self:SetHasCartridge(false)
    self:SetBlankCartridge(false)
    self:EmitSound("weapons/smg1/switch_burst.wav", 70, 130)
    return cart
end
