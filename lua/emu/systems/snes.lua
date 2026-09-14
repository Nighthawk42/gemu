-- SNES System Profile
emu = emu or {}
emu.Systems = emu.Systems or {}

local SNES = {
    blankMaterial = "gemu/blank_label",
    cartridgeLabelMaterials = {1},
    insertedLabelMaterials = {3},
    id = "snes",
    name = "Super Nintendo",
    consoleModel = "models/unconid/snes/snes.mdl",
    cartridgeModel = "models/unconid/snes/snes_cartridge.mdl",
    controllerModel = "models/unconid/snes/snes_controller.mdl",
    cartridgeClass = "emu_cartridge",
    cartridges = {
        { class = "emu_cart_smw", name = "SNES Cartridge: Super Mario World", rom = "super_mario_world.smc", title = "Super Mario World", skin = 4 },
        { class = "emu_cart_mariokart", name = "SNES Cartridge: Super Mario Kart", rom = "mario_kart.smc", title = "Super Mario Kart", skin = 3 },
        { class = "emu_cart_chrono", name = "SNES Cartridge: Chrono Trigger", rom = "chrono_trigger.smc", title = "Chrono Trigger", skin = 2 },
        { class = "emu_cart_ff2", name = "SNES Cartridge: Final Fantasy II", rom = "final_fantasy_2.smc", title = "Final Fantasy II", skin = 1 },
        { class = "emu_cart_mk", name = "SNES Cartridge: Mortal Kombat", rom = "mortal_kombat.smc", title = "Mortal Kombat", skin = 5 },
        { class = "emu_cart_earthbound", name = "SNES Cartridge: EarthBound", rom = "earthbound.smc", title = "EarthBound", skin = 6 },
        { class = "emu_cart_megamanx", name = "SNES Cartridge: Mega Man X", rom = "mega_man_x.smc", title = "Mega Man X", skin = 8 },
        { class = "emu_cart_castlevania4", name = "SNES Cartridge: Super Castlevania IV", rom = "castlevania_4.smc", title = "Super Castlevania IV", skin = 10 },
        { class = "emu_cart_contra3", name = "SNES Cartridge: Contra III", rom = "contra_3.smc", title = "Contra III", skin = 11 },
        { class = "emu_cart_dkc", name = "SNES Cartridge: Donkey Kong Country", rom = "donkey_kong_country.smc", title = "Donkey Kong Country", skin = 12 },
        { class = "emu_cart_mariorpg", name = "SNES Cartridge: Super Mario RPG", rom = "super_mario_rpg.smc", title = "Super Mario RPG", skin = 14 },
        { class = "emu_cart_metroid", name = "SNES Cartridge: Super Metroid", rom = "super_metroid.smc", title = "Super Metroid", skin = 15 },
        { class = "emu_cart_zelda", name = "SNES Cartridge: Zelda - A Link to the Past", rom = "zelda_lttp.smc", title = "The Legend of Zelda: A Link to the Past", skin = 19 },
        { class = "emu_cart_turtles", name = "SNES Cartridge: TMNT IV Turtles in Time", rom = "turtles_in_time.smc", title = "TMNT IV: Turtles in Time", skin = 17 },
        { class = "emu_cart_zombies", name = "SNES Cartridge: Zombies Ate My Neighbors", rom = "zombies_ate_my_neighbors.smc", title = "Zombies Ate My Neighbors", skin = 20 }
    },
    defaultRom = "super_mario_world.smc",
    defaultGame = "Super Mario World",
    defaultSkin = 4,
    interaction = "console", -- Handheld profiles use a SWEP instead of a CRT station.
    player2 = true,
    initialBodygroups = {[2]=0, [4]=1},
    cartridgeBodygroup = 3,
    cartridgeInserted = 0, -- cartridge_snes.smd
    cartridgeEmpty = 1, -- no_cartridge.smd
    cartridgePosition = Vector(1.42, 0, 3.8),
    cartridgeAngles = Angle(0, 90, -90), -- Label faces -X; cartridge top (-Y) faces up.
    consoleCable = Vector(4.8, 0, 1.5),
    display = {
        model = "models/ivip/cineos/philipscineos.mdl",
        spawnOffset = Vector(2, 32, 0),
        spawnAngles = Angle(0, 180, 0), -- CRT runtime front +X becomes SNES front -X.
        cable = Vector(-15, 0, 8),
        screenCenter = Vector(9.6, 0, 14.58),
        screenAspect = 34.398 / 19.322,
        cameraPosition = Vector(65, 0, 18),
        cameraFOV = 45,
        screenMaterials = {1, 10, 14}
    },
    extensions = { "smc", "sfc" },

    -- Cartridge skin mappings (models/unconid/snes/snes_cartridge.mdl)
    romSkins = {
        ["super_mario_world.smc"] = 4,
        ["super_mario_world.sfc"] = 4,
        ["mario_world.smc"] = 4,
        ["mario_kart.smc"] = 3,
        ["chrono_trigger.smc"] = 2,
        ["final_fantasy_2.smc"] = 1,
        ["mortal_kombat.smc"] = 5,
        ["earthbound.smc"] = 6,
        ["earthworm_jim.smc"] = 7,
        ["mega_man_x.smc"] = 8,
        ["shadowrun.smc"] = 9,
        ["castlevania_4.smc"] = 10,
        ["contra_3.smc"] = 11,
        ["donkey_kong_country.smc"] = 12,
        ["super_ghouls_n_ghosts.smc"] = 13,
        ["super_mario_rpg.smc"] = 14,
        ["super_metroid.smc"] = 15,
        ["super_star_wars.smc"] = 16,
        ["turtles_in_time.smc"] = 17,
        ["yoshis_island.smc"] = 18,
        ["zelda_lttp.smc"] = 19,
        ["zombies_ate_my_neighbors.smc"] = 20
    },

    buttons = {up=true, down=true, left=true, right=true, a=true, b=true, l=true, r=true, start=true, select=true, x=true, y=true},
    aspectRatio = 4 / 3,
    browserWidth = 640, browserHeight = 480,
    frameWidth = 512,
    frameHeight = 448
}

function SNES:GetSkinForRom(filename)
    if not filename then return self.defaultSkin end
    local clean = string.lower(filename)
    if self.romSkins[clean] then return self.romSkins[clean] end
    for pattern, skin in pairs(self.romSkins) do
        if string.find(clean, pattern, 1, true) then
            return skin
        end
    end
    return self.defaultSkin
end

emu.Systems["snes"] = SNES
