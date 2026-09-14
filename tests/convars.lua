-- Replicated convars read by client code must be created in the client realm too.
local count = 0
local function check(ok, why) assert(ok, why) count = count + 1 end
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 128, 8192, 256
local function loadRealm(server)
    SERVER, CLIENT = server, not server
    local created = {}
    CreateConVar = function(name) created[name] = true end
    CreateClientConVar = CreateConVar
    AddCSLuaFile, include = function() end, function() end
    cleanup = {Register = function() end}
    hook = {Add = function() end}
    scripted_ents = {Register = function() end}
    emu = {Systems = {}}
    dofile("lua/autorun/emu_init.lua")
    return created
end
for _, server in ipairs({true, false}) do
    local created = loadRealm(server)
    local realm = server and "server" or "client"
    check(created.emu_sv_stream_fps, "emu_sv_stream_fps exists in the " .. realm .. " realm")
    check(created.emu_sv_stream_distance, "emu_sv_stream_distance exists in the " .. realm .. " realm")
    check(created.emu_sv_enabled and created.emu_url, "shared replicated convars exist in the " .. realm .. " realm")
end
-- cfg/gemu.cfg is applied by Lua because server.cfg runs too early and exec is blocked.
loadRealm(true)
local set = {}
GetConVar = function(name) return (name == "emu_url" or name == "emu_sv_stream_enabled" or name == "emu_sv_stream_service") and {} or nil end
RunConsoleCommand = function(name, value) set[name] = value end
local applied = emu.ApplyServerConfig([[
// GEMU settings
emu_url "https://example.org/gemu/"
emu_sv_stream_service "https://example.org/gemu-stream"
emu_sv_stream_enabled 1
sv_cheats 1
emu_unknown_setting 5
]])
check(applied == 3, "only existing emu_ settings are applied")
check(set.emu_url == "https://example.org/gemu/" and set.emu_sv_stream_service == "https://example.org/gemu-stream",
    "quoted values keep their // characters")
check(set.emu_sv_stream_enabled == "1" and set.sv_cheats == nil, "bare values apply and non-GEMU commands are ignored")
print("All " .. count .. " convar realm tests PASSED!")
