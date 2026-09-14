SWEP.PrintName = "GEMU Handheld Base"
SWEP.Author = "Nighthawk"
SWEP.Instructions = "LMB: Play | RMB: Zoom | R: Controls | Alt+R: Eject"
SWEP.Category = "GEMU - Consoles"
SWEP.Spawnable = false
SWEP.AdminOnly = false
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.Slot = 0
SWEP.SlotPos = 4
SWEP.ViewModel = "models/unconid/gameboy/gameboy_advance.mdl"
SWEP.WorldModel = "models/unconid/gameboy/gameboy_advance.mdl"
SWEP.UseHands = false
SWEP.IsEmuHandheld = true

function SWEP:GetSystemId() return self.SystemID or "gba" end

function SWEP:SetupDataTables()
    self:NetworkVar("String", 0, "GameTitle")
    self:NetworkVar("String", 1, "RomUrl")
    self:NetworkVar("String", 2, "RomName")
    self:NetworkVar("Int", 0, "CartridgeSkin")
    self:NetworkVar("Bool", 0, "HasCartridge")
    self:NetworkVar("Bool", 1, "BlankCartridge")
    self:NetworkVar("Bool", 2, "SessionPaused")
end

function SWEP:Initialize()
    self:SetHoldType("camera")
    if SERVER then
        local profile = emu.GetSystem(self)
        self:InsertCartridge(profile.defaultGame, "", profile.defaultRom, profile.defaultSkin)
    end
end

function SWEP:InsertCartridge(title, url, name, skin, blank)
    if not SERVER then return end
    local owner = self:GetOwner()
    if IsValid(owner) and owner.EmuSession == self then emu.EndSession(owner, true) end
    local profile = emu.GetSystem(self)
    self:SetGameTitle(title or profile.defaultGame)
    self:SetRomUrl(url or "")
    self:SetRomName(name or profile.defaultRom)
    self:SetCartridgeSkin(skin or profile.defaultSkin)
    self:SetHasCartridge(true)
    self:SetBlankCartridge(blank == true)
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.25)
    if SERVER and game.SinglePlayer() then self:CallOnClient("PrimaryAttack") end
    if not CLIENT or (not game.SinglePlayer() and not IsFirstTimePredicted()) then return end
    if self:GetHasCartridge() and emu and emu.OpenWindow then emu.OpenWindow(self, true) end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.25)
    if SERVER and game.SinglePlayer() then self:CallOnClient("SecondaryAttack") end
    if CLIENT and (game.SinglePlayer() or IsFirstTimePredicted()) then self.IsZoomed = not self.IsZoomed end
end

function SWEP:Reload()
    local owner = self:GetOwner()
    if not IsValid(owner) or CurTime() < (self.NextMenuAction or 0) then return end
    self.NextMenuAction = CurTime() + 0.5
    if owner:KeyDown(IN_WALK) or owner:KeyDown(IN_DUCK) then
        if SERVER and self:GetHasCartridge() then self:EjectCartridgeToWorld() end
        return
    end
    if SERVER and game.SinglePlayer() then self:CallOnClient("OpenControls") end
    if CLIENT and (game.SinglePlayer() or IsFirstTimePredicted()) then self:OpenControls() end
end

function SWEP:OpenControls()
    if CLIENT and self:GetHasCartridge() and emu and emu.OpenWindow then emu.OpenWindow(self, false) end
end

function SWEP:Holster()
    self.IsZoomed = false
    -- Holstering drops the controls; the game keeps running until the player pauses it.
    if CLIENT and emu and emu.ActiveTarget == self and emu.ReleaseHardwareInput then
        emu.ReleaseHardwareInput()
    end
    return true
end
