include("shared.lua")
function ENT:Draw()
    if self:GetIsInserted() then return end
    emu.ApplyCartridgeAppearance(self, self, false)
    self:DrawModel()
end
