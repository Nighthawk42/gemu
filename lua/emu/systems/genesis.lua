emu = emu or {}
emu.Systems = emu.Systems or {}
emu.Systems.genesis = {
    id = "genesis", name = "Sega Genesis", interaction = "console", player2 = true,
    consoleModel = "models/unconid/genesis/genesis.mdl",
    cartridgeModel = "models/unconid/genesis/genesis_cartridge.mdl",
    cartridgeClass = "emu_genesis_cartridge",
    defaultRom = "sonic_the_hedgehog.bin", defaultGame = "Sonic the Hedgehog", defaultSkin = 0,
    extensions = {"md", "bin", "gen", "smd"},
    aspectRatio = 4 / 3,
    browserWidth = 640, browserHeight = 480,
    frameWidth = 320, frameHeight = 224,
    buttons = {up=true, down=true, left=true, right=true, a=true, b=true, start=true, select=true, c=true, x=true, y=true, z=true},
    cartridges = {},
    blankMaterial = "gemu/blank_dark",
    cartridgeLabelMaterials = {0},
    display = table.Copy(emu.Systems.snes.display),
    consoleCable = Vector(4.8, 0, 1.5),
    cartridgeBodygroup = 2, cartridgeInserted = 1, cartridgeEmpty = 0,
    initialBodygroups = {[3]=0, [4]=1},
    cartridgePosition = Vector(0, -1.95, 1.13), cartridgeAngles = Angle(0,0,0),
    insertedLabelMaterials = {1},
    buttonAliases = {b="a", a="b", y="c", x="x", l="y", r="z"},
}
