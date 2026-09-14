-- SNES Console Entity Client
include("shared.lua")

function ENT:Draw()
    emu.ApplyCartridgeAppearance(self, self, true)
    emu.ApplyPowerLED(self, self)

    self:DrawModel()

    -- Draw cosmetic cable connecting console to CRT
    local crt = self:GetLinkedDisplay()
    if IsValid(crt) then
        local profile = emu.GetSystem(self)
        local p1 = self:LocalToWorld(profile.consoleCable)
        local p2 = crt:LocalToWorld(profile.display.cable)
        render.SetColorMaterial()
        render.DrawBeam(p1, p2, 1.2, 0, 1, Color(20, 20, 25, 255))
    end

end
