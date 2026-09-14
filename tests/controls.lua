CLIENT = true
emu = {}
local keys = {"UP","DOWN","LEFT","RIGHT","Z","X","C","V","Q","F","ENTER","BACKSPACE","E","F1","F5","F8","F11","MINUS","EQUAL","M","ESCAPE","BACKQUOTE","W"}
for i, name in ipairs(keys) do _G["KEY_" .. name] = i end
KEY_LAST = 100
local values = {}
function CreateClientConVar(name, value) values[name] = tonumber(value) end
function GetConVar(name) return {GetInt = function() return values[name] end} end
function RunConsoleCommand(name, value) values[name] = tonumber(value) end
concommand = {Add = function() end}
KEY_P = KEY_P or 1001 -- GEMU reserves P for pause.
dofile('lua/emu/client/cl_emu_controls.lua')
local map = emu.GetKeyboardLayout()
assert(map[KEY_UP] == 'up' and map[KEY_W] == nil and map[KEY_F] == 'r')
assert(emu.SetControlKey('up', KEY_X))
map = emu.GetKeyboardLayout()
assert(map[KEY_X] == 'up' and map[KEY_UP] == nil and values.emu_key_a == 0)
assert(not emu.SetControlKey('up', KEY_E))
assert(not emu.SetControlKey('unknown', KEY_W))
assert(emu.SetControlKey('up', 0))
assert(emu.GetKeyboardLayout()[KEY_X] == nil)
print('Controls defaults, remapping, collision, reserved keys and unbinding passed.')
