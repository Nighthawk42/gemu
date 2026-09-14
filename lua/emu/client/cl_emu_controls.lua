-- One saved keyboard mapping for every system and either multiplayer role.
if not CLIENT then return end
emu.ControlDefaults = {
    {"up", "Up", KEY_UP}, {"down", "Down", KEY_DOWN},
    {"left", "Left", KEY_LEFT}, {"right", "Right", KEY_RIGHT},
    {"b", "B / Genesis A", KEY_Z}, {"a", "A / Genesis B", KEY_X},
    {"y", "Y / Genesis C", KEY_C}, {"x", "X", KEY_V},
    {"l", "L / Genesis Y", KEY_Q}, {"r", "R / Genesis Z", KEY_F},
    {"start", "Start", KEY_ENTER}, {"select", "Select / Mode", KEY_BACKSPACE}
}
local reserved = {[KEY_E]=true,[KEY_P]=true,[KEY_F1]=true,[KEY_F5]=true,[KEY_F8]=true,
    [KEY_F11]=true,[KEY_MINUS]=true,[KEY_EQUAL]=true,[KEY_M]=true,[KEY_ESCAPE]=true,[KEY_BACKQUOTE]=true}
for _, row in ipairs(emu.ControlDefaults) do
    CreateClientConVar("emu_key_" .. row[1], tostring(row[3]), true, false, "GEMU " .. row[2] .. " key", 0, KEY_LAST)
end
function emu.GetKeyboardLayout()
    local layout, signature = {}, {}
    for _, row in ipairs(emu.ControlDefaults) do
        local key = GetConVar("emu_key_" .. row[1]):GetInt()
        signature[#signature + 1] = tostring(key)
        if key > 0 and key <= KEY_LAST and not reserved[key] and not layout[key] then layout[key] = row[1] end
    end
    return layout, table.concat(signature, ",")
end
function emu.SetControlKey(action, key)
    key = math.floor(tonumber(key) or 0)
    if key < 0 or key > KEY_LAST or reserved[key] then return false end
    local found = false
    for _, row in ipairs(emu.ControlDefaults) do if row[1] == action then found = true end end
    if not found then return false end
    for _, row in ipairs(emu.ControlDefaults) do
        if key > 0 and row[1] ~= action and GetConVar("emu_key_" .. row[1]):GetInt() == key then
            RunConsoleCommand("emu_key_" .. row[1], "0")
        end
    end
    RunConsoleCommand("emu_key_" .. action, tostring(key))
    return true
end
local window
function emu.OpenControls()
    if emu.ReleaseHardwareInput then emu.ReleaseHardwareInput() end
    if emu.LeavePlayer2 then emu.LeavePlayer2() end
    if IsValid(window) then window:MakePopup() return end
    window = vgui.Create("DFrame")
    window:SetTitle("GEMU Controls") window:SetSize(560, math.min(740, ScrH() - 40)) window:Center() window:MakePopup()
    local panel = vgui.Create("DScrollPanel", window) panel:Dock(FILL)
    local function help(text)
        local label = panel:Add("DLabel") label:Dock(TOP) label:DockMargin(8, 6, 8, 6)
        label:SetText(text) label:SetWrap(true) label:SetAutoStretchVertical(true)
    end
    help("One layout for all systems and both player roles. Click a key to change it. Assigning an occupied key clears its previous binding.")
    for _, row in ipairs(emu.ControlDefaults) do
        local action, title = row[1], row[2]
        local line = panel:Add("DPanel") line:Dock(TOP) line:SetTall(32) line:DockMargin(8, 2, 8, 2)
        local label = vgui.Create("DLabel", line) label:Dock(LEFT) label:SetWide(220) label:SetText(title)
        local clear = vgui.Create("DButton", line) clear:Dock(RIGHT) clear:SetWide(60) clear:SetText("Clear")
        clear.DoClick = function() emu.SetControlKey(action, 0) end
        local binder = vgui.Create("DBinder", line) binder:Dock(FILL)
        binder:SetValue(GetConVar("emu_key_" .. action):GetInt())
        binder.OnChange = function(self, key)
            if not emu.SetControlKey(action, key) then
                notification.AddLegacy("That key is reserved for GEMU or the game UI.", NOTIFY_ERROR, 3)
            end
        end
        local originalThink = binder.Think
        binder.Think = function(self)
            if originalThink then originalThink(self) end
            local value = GetConVar("emu_key_" .. action):GetInt()
            if not self.Trapping and self:GetValue() ~= value then self:SetValue(value) end
        end
    end
    local reset = panel:Add("DButton") reset:Dock(TOP) reset:SetTall(30) reset:DockMargin(8, 8, 8, 8)
    reset:SetText("Restore default arrow-key layout")
    reset.DoClick = function() for _, row in ipairs(emu.ControlDefaults) do RunConsoleCommand("emu_key_" .. row[1], tostring(row[3])) end end
    help("Shortcuts: E leave, P pause/resume, F1 controls, F5/F8 save/load, F11 fullscreen, -/= volume, M mute. These keys are reserved.")
    local status = panel:Add("DLabel") status:Dock(TOP) status:SetTall(36)
    status.Think = function(self) self:SetText(emu.GetGamepadStatus and emu.GetGamepadStatus() or "Controller module unavailable") end
    local slot = panel:Add("DNumSlider") slot:Dock(TOP) slot:SetTall(32)
    local backend = panel:Add("DComboBox") backend:Dock(TOP) backend:SetTall(30)
    backend:SetValue(GetConVar("emu_gamepad_backend"):GetString())
    for _, id in ipairs({"auto", "xinput", "directinput"}) do backend:AddChoice(id, id) end
    backend.OnSelect = function(_, _, _, value) RunConsoleCommand("emu_gamepad_backend", value) end
    local devices = panel:Add("DComboBox") devices:Dock(TOP) devices:SetTall(30)
    devices:SetValue(GetConVar("emu_gamepad_device"):GetString() == "" and "First DirectInput device" or GetConVar("emu_gamepad_device"):GetString())
    devices:AddChoice("First DirectInput device", "")
    for _, device in ipairs(emu.GetDirectInputDevices()) do devices:AddChoice(device.name .. " — " .. device.id, device.id) end
    devices.OnSelect = function(_, _, _, value) RunConsoleCommand("emu_gamepad_device", value) end
    slot:SetText("Controller slot") slot:SetMinMax(0, 3) slot:SetDecimals(0) slot:SetConVar("emu_gamepad_slot")
    local deadzone = panel:Add("DNumSlider") deadzone:Dock(TOP) deadzone:SetTall(32)
    deadzone:SetText("Stick deadzone") deadzone:SetMinMax(0.05, 0.95) deadzone:SetDecimals(2) deadzone:SetConVar("emu_gamepad_deadzone")
    help("Auto prefers the selected XInput slot, then DirectInput. Reopen this window to refresh the device list. DirectInput button numbers below use your generic SNES pad defaults; 0 unbinds. Buttons 7 and 8 are unused by default.")
    for _, action in ipairs({"x","a","b","y","l","r","select","start"}) do
        local bind = panel:Add("DNumSlider") bind:Dock(TOP) bind:SetTall(30)
        bind:SetText("DirectInput " .. string.upper(action)) bind:SetMinMax(0,128) bind:SetDecimals(0) bind:SetConVar("emu_pad_" .. action)
    end
    help("DirectInput mappings are shared across devices on this client; select/reconfigure when switching pads. XInput button mappings remain fixed. Each client installs the optional DLL separately.")
end
concommand.Add("emu_controls", function() emu.OpenControls() end)
