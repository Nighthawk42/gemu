-- WebRTC viewer panel: callbacks bind only after the page loads (patched CEF).
CLIENT = true
local count, now = 0, 10
local function check(v, m) assert(v, m) count = count + 1 end
function RealTime() return now end
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function GetConVar() return {GetFloat = function() return 0.5 end} end
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local receivers, hooks, incoming = {}, {}, {}
net = {Receive = function(name, fn) receivers[name] = fn end,
    ReadEntity = function() return incoming.target end, ReadBool = function() return true end,
    ReadString = function() return table.remove(incoming.strings, 1) end,
    Start = function() end, WriteEntity = function() end, WriteString = function() end,
    WriteBool = function() end, SendToServer = function() end}
hook = {Add = function(_, name, fn) hooks[name] = fn end}
concommand = {Add = function() end}
util = {TableToJSON = function() return "{}" end}
local panels = {}
vgui = {GetWorldPanel = function() return {} end, Create = function()
    local panel = {valid = true, loading = true, bound = {}, scripts = {}}
    for _, name in ipairs({"SetSize", "SetPos", "SetPaintedManually", "SetVisible", "SetMouseInputEnabled", "SetKeyboardInputEnabled"}) do
        panel[name] = function() end
    end
    function panel:OpenURL(url) self.url = url end
    function panel:IsLoading() return self.loading end
    function panel:AddFunction(obj, name) self.bound[#self.bound + 1] = obj .. "." .. name end
    function panel:QueueJavascript(js) self.scripts[#self.scripts + 1] = js end
    function panel:Remove() self.valid = false end
    panels[#panels + 1] = panel
    return panel
end}
local target = {GetRomName = function() return "game.smc" end, EntIndex = function() return 7 end}
emu = {GetSystem = function() return {aspectRatio = 4 / 3} end}
dofile("lua/emu/client/cl_emu_rtc.lua")

incoming = {target = target, strings = {"1", "game.smc", "view", "room", "wss://host", "token", "https://host/gemu/viewer.html"}}
receivers.emu_rtc_config()
hooks.Emu_RTCPlayback()
local viewer = panels[1]
check(viewer and viewer.url == "https://host/gemu/viewer.html", "a viewer panel opens the viewer page")
check(#viewer.bound == 0, "no callback is bound while the page is still loading")
viewer.loading = false
viewer:OnDocumentReady()
hooks.Emu_RTCPlayback()
check(#viewer.bound == 1 and viewer.bound[1] == "gemuRTC.status", "the status callback binds once the page is ready")
viewer:OnDocumentReady()
hooks.Emu_RTCPlayback()
check(#viewer.bound == 2, "a reload rebinds the status callback")
print("All " .. count .. " RTC client tests PASSED!")
