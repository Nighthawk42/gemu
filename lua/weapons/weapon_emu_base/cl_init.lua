include("shared.lua")

function SWEP:CalcViewModelView(vm, oldPos, oldAng, pos, ang)
    local profile = emu.GetSystem(self)
    local offset = Vector(profile.viewDistance, 0, profile.viewHeight)
    local tilt = profile.viewPitch
    if self.IsZoomed then offset, tilt = Vector(profile.zoomDistance, 0, profile.zoomHeight), profile.zoomPitch end
    local newPos = pos + ang:Forward() * offset.x + ang:Up() * offset.z
    local newAng = Angle(ang.p, ang.y, ang.r)
    newAng:RotateAroundAxis(newAng:Up(), profile.viewYaw)
    newAng:RotateAroundAxis(newAng:Right(), tilt)
    return newPos, newAng
end

function SWEP:PreDrawViewModel(vm)
    if not IsValid(vm) then return end
    local profile = emu.GetSystem(self)
    self.PreviousSkin = vm:GetSkin()
    self.PreviousMaterials = {[profile.screenMaterial] = vm:GetSubMaterial(profile.screenMaterial)}
    self.PreviousMaterials[0] = vm:GetSubMaterial(0)
    for _, index in ipairs(profile.insertedLabelMaterials or {}) do
        self.PreviousMaterials[index] = vm:GetSubMaterial(index)
    end
    self.PreviousBodygroup = profile.cartridgeBodygroup and vm:GetBodygroup(profile.cartridgeBodygroup)
    self.PreviousBoneScale = profile.cartridgeBone and vm:GetManipulateBoneScale(profile.cartridgeBone)
    emu.ApplyCartridgeAppearance(vm, self, true)
    emu.ApplyPowerLED(vm, self)
    if emu.ApplyHandheldScreen then emu.ApplyHandheldScreen(vm, self) end
end

function SWEP:PostDrawViewModel(vm)
    if not IsValid(vm) then return end
    local profile = emu.GetSystem(self)
    for index, material in pairs(self.PreviousMaterials or {}) do vm:SetSubMaterial(index, material) end
    if self.PreviousSkin then vm:SetSkin(self.PreviousSkin) end
    if self.PreviousBodygroup then vm:SetBodygroup(profile.cartridgeBodygroup, self.PreviousBodygroup) end
    if self.PreviousBoneScale then vm:ManipulateBoneScale(profile.cartridgeBone, self.PreviousBoneScale) end
end

function SWEP:DrawWorldModel()
    self:SetSkin(self:GetCartridgeSkin())
    emu.ApplyCartridgeAppearance(self, self, true)
    emu.ApplyPowerLED(self, self)
    if emu.ApplyHandheldScreen then emu.ApplyHandheldScreen(self, self) end
    local owner = self:GetOwner()
    if IsValid(owner) then
        local bone = owner:LookupBone("ValveBiped.Bip01_R_Hand")
        local matrix = bone and owner:GetBoneMatrix(bone)
        if matrix then
            local pos, ang = matrix:GetTranslation(), matrix:GetAngles()
            pos = pos + ang:Forward() * 3 + ang:Right() * 1.5 - ang:Up()
            ang:RotateAroundAxis(ang:Forward(), 90)
            ang:RotateAroundAxis(ang:Right(), 180)
            self:SetRenderOrigin(pos)
            self:SetRenderAngles(ang)
        end
    end
    self:DrawModel()
    self:SetRenderOrigin(nil)
    self:SetRenderAngles(nil)
end

function SWEP:OnRemove()
    if emu and emu.ActiveTarget == self and emu.StopSession then emu.StopSession() end
end
