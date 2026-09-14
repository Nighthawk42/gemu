-- CRT Display Entity Client
include("shared.lua")

function ENT:Draw()
    local console = self:GetLinkedConsole()
    if IsValid(console) then
        emu.ApplyScreen(self, console)
    else
        self:SetSubMaterial()
        self:SetSkin(1)
    end
    emu.ApplyTVPowerLED(self, console)
    self:DrawModel()
end
