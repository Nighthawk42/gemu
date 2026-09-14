-- Game Boy Advance handheld profile
emu = emu or {}
emu.Systems = emu.Systems or {}

local GBA = {
    blankMaterial = "gemu/blank_label",
    cartridgeLabelMaterials = {0},
    insertedLabelMaterials = {2},
    id = "gba",
    name = "Game Boy Advance",
    interaction = "handheld",
    weaponClass = "weapon_emu_gba",
    consoleModel = "models/unconid/gameboy/gameboy_advance.mdl",
    cartridgeModel = "models/unconid/gameboy/gameboy_advance_cartridge.mdl",
    cartridgeClass = "emu_gba_cartridge",
    cartridges = {
    [0] = {class = "emu_gba_cart_demo", title = "Homebrew Demo", rom = "hello_world.gba", skin = 0},
    [1] = {class = "emu_gba_cart_advance_wars", title = "Advance Wars", rom = "advance_wars.gba", skin = 1},
    [2] = {class = "emu_gba_cart_castlevania", title = "Castlevania: Aria of Sorrow", rom = "castlevania_aria_of_sorrow.gba", skin = 2},
    [3] = {class = "emu_gba_cart_ffvi", title = "Final Fantasy VI Advance", rom = "final_fantasy_vi_advance.gba", skin = 3},
    [4] = {class = "emu_gba_cart_metroid", title = "Metroid Fusion", rom = "metroid_fusion.gba", skin = 4},
    [5] = {class = "emu_gba_cart_ruby", title = "Pokemon - Ruby Version", rom = "pokemon_ruby_version.gba", skin = 5},
    [6] = {class = "emu_gba_cart_sapphire", title = "Pokemon - Sapphire Version", rom = "pokemon_sapphire.gba", skin = 6},
    [7] = {class = "emu_gba_cart_tony_hawk", title = "Tony Hawk's Pro Skater 2", rom = "tony_hawk_s_pro_skater_2.gba", skin = 7},
    [8] = {class = "emu_gba_cart_yoshi", title = "Yoshi's Island", rom = "super_mario_advance_3_yoshi_s_island.gba", skin = 8},
    [9] = {class = "emu_gba_cart_zelda", title = "The Legend of Zelda: The Minish Cap", rom = "the_legend_of_zelda_the_minish_cap.gba", skin = 9}
},
    defaultRom = "pokemon_firered.gba",
    defaultGame = "Pokemon FireRed",
    defaultSkin = 0,
    extensions = {"gba"},
    buttons = {up=true, down=true, left=true, right=true, a=true, b=true, l=true, r=true, start=true, select=true},
    aspectRatio = 3 / 2,
    frameWidth = 240,
    frameHeight = 160,
    browserWidth = 720,
    browserHeight = 480,
    cartridgeBone = 1,
    viewYaw = 180, viewPitch = -8, viewHeight = -6.8, viewDistance = 20,
    zoomHeight = -4, zoomDistance = 13, zoomPitch = -3,
    screenMaterial = 1,
    -- The model screen uses only this portion of its 0..1 material UVs.
    screenUV = {x = 0.0090, y = 0.2080, w = 0.9829, h = 0.6190}
}

emu.Systems.gba = GBA
