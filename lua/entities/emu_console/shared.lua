-- SNES Console Entity Shared
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "SNES + CRT"
ENT.Author = "Nighthawk"
ENT.Category = "GEMU - Consoles"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.IsEmuConsole = true

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Power")
    self:NetworkVar("Bool", 1, "HasCartridge")
    self:NetworkVar("Bool", 2, "BlankCartridge")
    self:NetworkVar("Bool", 3, "SessionPaused")
    self:NetworkVar("String", 0, "SystemId")
    self:NetworkVar("String", 1, "RomName")
    self:NetworkVar("String", 2, "RomUrl")
    self:NetworkVar("String", 3, "GameTitle")
    self:NetworkVar("Int", 0, "CartridgeSkin")
    self:NetworkVar("Entity", 0, "LinkedDisplay")
    self:NetworkVar("Entity", 1, "ControllingPlayer")
    self:NetworkVar("Entity", 2, "InsertedCart")
    self:NetworkVar("Entity", 3, "Player2")
end

ENT.IconOverride = "gemu/icons/snes_console.png"
