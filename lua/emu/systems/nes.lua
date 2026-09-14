emu = emu or {}
emu.Systems = emu.Systems or {}
emu.Systems.nes = {
    id = "nes", name = "Nintendo Entertainment System", interaction = "console", player2 = true,
    consoleModel = "models/unconid/nes/nes.mdl",
    cartridgeModel = "models/unconid/nes/nes_nes_cartridge.mdl",
    cartridgeClass = "emu_nes_cartridge",
    defaultRom = "super_mario_bros_duck_hunt.nes", defaultGame = "Super Mario Bros. / Duck Hunt", defaultSkin = 0,
    extensions = {"nes"},
    aspectRatio = 4 / 3,
    browserWidth = 640, browserHeight = 480,
    frameWidth = 256, frameHeight = 240,
    buttons = {up=true, down=true, left=true, right=true, a=true, b=true, start=true, select=true},
    cartridges = {},
    blankMaterial = "gemu/blank_gray",
    cartridgeLabelMaterials = {0},
    display = table.Copy(emu.Systems.snes.display),
    consoleCable = Vector(4.8, 0, 1.5),
    initialBodygroups = {[2]=1, [3]=0},
    cartridgePosition = Vector(0,0,2), cartridgeAngles = Angle(0,0,90),
    insertedLabelMaterials = {},
}
