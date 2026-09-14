emu = emu or {}
emu.Systems = emu.Systems or {}
emu.Systems.gbc = {
    id = "gbc", name = "Game Boy Color", interaction = "handheld",
    consoleModel = "models/unconid/gameboy/gameboy_color.mdl",
    cartridgeModel = "models/unconid/gameboy/gameboy_color_cartridge.mdl",
    cartridgeClass = "emu_gbc_cartridge",
    defaultRom = "pokemon_silver.gbc", defaultGame = "Pokemon Silver", defaultSkin = 0,
    extensions = {"gbc"},
    aspectRatio = 10 / 9,
    browserWidth = 480, browserHeight = 432,
    frameWidth = 160, frameHeight = 144,
    buttons = {up=true, down=true, left=true, right=true, a=true, b=true, start=true, select=true},
    cartridges = {},
    blankMaterial = "gemu/blank_label",
    cartridgeLabelMaterials = {0},
    weaponClass = "weapon_emu_gbc",
    screenMaterial = 1, screenUV = {x=0.0129, y=0.1286, w=0.9674, h=0.8450},
    cartridgeBodygroup = 1, cartridgeInserted = 0, cartridgeEmpty = 1,
    insertedLabelMaterials = {2},
    viewYaw = 180, viewPitch = 0, viewHeight = -9, viewDistance = 20,
    zoomHeight = -8, zoomDistance = 14, zoomPitch = 0,
}
