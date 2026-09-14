-- GMod Multi-Emulator Initialization
emu = emu or {}
emu.Version = "1.0.0"

CreateConVar("emu_url", "", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Frontend base URL (required). Server owners host their own frontend and set it in cfg/gemu.cfg")
CreateConVar("emu_scale", "1.0", FCVAR_ARCHIVE, "Window scale factor")
CreateConVar("emu_sv_enabled", "1", FCVAR_REPLICATED + FCVAR_NOTIFY, "Enable or disable emulator entities")
CreateConVar("emu_screen_mode", "1", FCVAR_ARCHIVE, "Default minimal screen mode")
-- Replicated convars must exist in both realms; a server-only definition leaves
-- GetConVar() nil on clients, which previously crashed spectator capture.
CreateConVar("emu_sv_stream_fps", "4", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Screen frames per second sent to nearby spectators", 1, 8)
CreateConVar("emu_sv_stream_distance", "1800", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Maximum distance for receiving emulator screen frames", 256, 4096)

for _, id in ipairs({"snes", "gba", "nes", "genesis", "gb", "gbc"}) do
    AddCSLuaFile("emu/systems/" .. id .. ".lua")
    include("emu/systems/" .. id .. ".lua")
end
AddCSLuaFile("emu/sh_emu_cartridges.lua")
include("emu/sh_emu_cartridges.lua")
AddCSLuaFile("emu/sh_emu_play.lua")
include("emu/sh_emu_play.lua")

if SERVER then
    CreateConVar("emu_sv_stream_transport", "auto", FCVAR_ARCHIVE,
        "Fallback screen/audio transport: auto (reliable on listen servers), reliable or unreliable")
    CreateConVar("emu_sv_stream_budget", "32000", FCVAR_ARCHIVE,
        "Reliable fallback bytes per second per spectator", 8000, 256000)
    cleanup.Register("emulators")
    -- server.cfg runs before Lua creates these convars on listen servers, and GMod
    -- blocks "exec" from Lua, so read cfg/gemu.cfg and apply its emu_* lines directly.
    function emu.ApplyServerConfig(text)
        local applied = 0
        for line in string.gmatch(text or "", "[^\r\n]+") do
            if not line:match("^%s*//") then
                local name, value = line:match('^%s*(emu_[%w_]+)%s+"([^"]*)"')
                if not name then name, value = line:match("^%s*(emu_[%w_]+)%s+(%S+)") end
                if name and GetConVar(name) then
                    RunConsoleCommand(name, value)
                    applied = applied + 1
                end
            end
        end
        return applied
    end
    if timer and file then
        timer.Simple(0, function()
            local text = file.Read("cfg/gemu.cfg", "GAME")
            if text then print("[gmod-emu] Applied " .. emu.ApplyServerConfig(text) .. " setting(s) from cfg/gemu.cfg.") end
        end)
    end
    AddCSLuaFile("emu/client/cl_emu_stream.lua")
    AddCSLuaFile("emu/client/cl_emu_rtc.lua")
    AddCSLuaFile("emu/client/cl_emu_screen.lua")
    AddCSLuaFile("emu/client/cl_emu_power.lua")
    AddCSLuaFile("emu/client/cl_emu_management.lua")
    AddCSLuaFile("emu/client/cl_emu_saves.lua")
    AddCSLuaFile("emu/client/cl_emu_input.lua")
    AddCSLuaFile("emu/client/cl_emu_controls.lua")
    AddCSLuaFile("emu/client/cl_emu_gamepad.lua")
    AddCSLuaFile("emu/client/cl_emu_gui.lua")
    include("emu/server/sv_emu.lua")
    include("emu/server/sv_emu_rtc.lua")
    include("emu/server/sv_emu_stream_demand.lua")
    include("emu/server/sv_emu_ownership.lua")
    include("emu/server/sv_emu_duplication.lua")
    include("emu/server/sv_emu_management.lua")
end

if CLIENT then
    CreateClientConVar("emu_volume", "0.8", true, false, "Emulator volume", 0, 1)
    CreateClientConVar("emu_screen_grid", "0", true, false, "Show CRT alignment grid", 0, 1)
    CreateClientConVar("emu_stream_quality", "35", true, false, "Spectator screen JPEG quality", 20, 60)
    include("emu/client/cl_emu_stream.lua")
    include("emu/client/cl_emu_rtc.lua")
    include("emu/client/cl_emu_screen.lua")
    include("emu/client/cl_emu_power.lua")
    include("emu/client/cl_emu_gamepad.lua")
    include("emu/client/cl_emu_input.lua")
    include("emu/client/cl_emu_controls.lua")
    include("emu/client/cl_emu_gui.lua")
    include("emu/client/cl_emu_saves.lua")
    include("emu/client/cl_emu_management.lua")

    -- Chat Command Hook (!snes or /snes)
    hook.Add("OnPlayerChat", "Emu_ChatCommand", function(ply, text, teamOnly, isDead)
        if ply == LocalPlayer() then
            local cmd = string.lower(string.Trim(text))
            if cmd == "!snes" or cmd == "/snes" or cmd == "!emu" or cmd == "/emu" then
                RunConsoleCommand("emu_menu")
                return true
            elseif cmd == "!gba" or cmd == "/gba" or cmd == "!gb" or cmd == "/gb" or cmd == "!gbc" or cmd == "/gbc" then
                RunConsoleCommand("emu_handheld")
                return true
            end
        end
    end)

    -- Spawnmenu Utilities Menu Integration
    hook.Add("PopulateToolMenu", "Emu_PopulateToolMenu", function()
        spawnmenu.AddToolMenuOption("Utilities", "User", "Emu_Settings", "Emulators", "", "", function(panel)
            panel:ClearControls()
            panel:Help("Console and handheld emulator settings")
            panel:ControlHelp("")

            local btnOpen = panel:Button("Open Emulator Controls", "emu_menu")
            btnOpen:SetTall(32)
            panel:Button("Open Equipped Handheld", "emu_handheld")

            panel:ControlHelp("")
            panel:TextEntry("Emulator Web Server URL:", "emu_url")
            panel:Help("Server owners: set your own frontend base URL. ROMs use roms/<system>/<filename> beneath it.")

            panel:NumSlider("Master Volume", "emu_volume", 0.0, 1.0, 2)
            panel:Button("Configure Keyboard and Controller", "emu_controls")
            panel:Button("Toggle Fullscreen", "emu_fullscreen")
            panel:Button("Quick Save", "emu_save")
            panel:Button("Quick Load", "emu_load")
            panel:Button("Reset Game", "emu_reset")
            panel:CheckBox("CRT alignment grid", "emu_screen_grid")

            panel:ControlHelp("")
            panel:Help("In-Game Controls:")
            panel:Help(" • Press [E] on the console or TV to enter Focused Play.")
            panel:Help(" • Press [E] again, open chat, or press Escape to leave. The game keeps running.")
            panel:Help(" • [P] pauses or resumes. Only pausing, Stop or powering off halts the game.")
            panel:Help(" • Press [Shift+E] to open the Full Controls Window.")
            panel:Help(" • Press [R+E] or [Alt+E] on the console to eject.")
            panel:Help(" • [-] / [=]: volume down/up. [M]: mute. [F11]: fullscreen.")
            panel:Help(" • [F1] opens controls while playing.")
            panel:ControlHelp("")
            panel:Help("Focused Key Mapping:")
            panel:Help(" • Arrow keys: D-Pad. Use Configure Keyboard and Controller to rebind.")
            panel:Help(" • Z / X: B / A Buttons")
            panel:Help(" • C / V: Y / X Buttons")
            panel:Help(" • Q / F: L / R Shoulder")
            panel:Help(" • Enter: Start")
            panel:Help(" • Backspace: Select")
        end)
    end)
end

-- Profiles own catalog data; every cartridge uses the same registration path.
local function RegisterCartridges()
    for _, profile in pairs(emu.Systems) do
        scripted_ents.Register({Type="anim", Base=profile.cartridgeClass, Spawnable=true,
            IconOverride="gemu/icons/" .. profile.id .. "_cartridge.png",
            PrintName="Blank " .. string.upper(profile.id) .. " Cartridge", Category="GEMU - " .. string.upper(profile.id),
            PresetRom="", PresetTitle="Blank Cartridge", PresetSkin=0, PresetBlank=true}, "emu_" .. profile.id .. "_cart_blank")
        for _, preset in pairs(profile.cartridges or {}) do
            scripted_ents.Register({
                Type = "anim", Base = profile.cartridgeClass,
                IconOverride = "gemu/icons/" .. profile.id .. "_cartridge.png",
                PrintName = preset.title,
                Category = "GEMU - " .. string.upper(profile.id), Spawnable = true, AdminOnly = false,
                PresetRom = preset.rom, PresetTitle = preset.title, PresetSkin = preset.skin
            }, preset.class)
        end
    end
end
hook.Add("Initialize", "Emu_RegisterCartridges", RegisterCartridges)
hook.Add("OnGamemodeLoaded", "Emu_RegisterCartridges_GM", RegisterCartridges)
RegisterCartridges()
