if not CLIENT then return end
emu = emu or {}
function emu.RequestPowerOff()
    local target = emu.ActiveTarget
    if not IsValid(target) then return end
    net.Start("emu_manage") net.WriteEntity(target) net.WriteString("power_off") net.SendToServer()
end
concommand.Add("emu_power_off", emu.RequestPowerOff)
net.Receive("emu_power_off", function()
    local target=net.ReadEntity()
    if emu.ActiveTarget == target then emu.StopSession() end
end)

function emu.OpenCartridgePicker(cart)
    if not IsValid(cart) or not cart.IsEmuCartridge or cart:GetIsInserted() then return end
    local system = cart:GetSystemId()
    local function available()
        return IsValid(cart) and not cart:GetIsInserted() and cart:GetSystemId() == system
    end
    local frame=vgui.Create("DFrame")
    frame:SetSize(620,460) frame:Center() frame:SetTitle("Choose " .. emu.GetSystem(cart).name .. " game") frame:MakePopup()
    local search=frame:Add("DTextEntry") search:Dock(TOP) search:SetPlaceholderText("Search games")
    local list=frame:Add("DListView") list:Dock(FILL) list:AddColumn("Game") list:AddColumn("Filename")
    local status=frame:Add("DLabel") status:Dock(BOTTOM) status:SetTall(24) status:SetText("Loading hosted catalog...")
    local rows={}
    local function populate()
        list:Clear()
        local query=string.lower(search:GetValue())
        for _, row in ipairs(rows) do
            local title=row.title or row.filename:gsub("%.[^.]+$", ""):gsub("_", " ")
            if (title .. " " .. row.filename):lower():find(query,1,true) then list:AddLine(title,row.filename) end
        end
    end
    search.OnChange=populate
    list.DoDoubleClick=function(_, _, row)
        if not available() then frame:Close() return end
        net.Start("emu_manage") net.WriteEntity(cart) net.WriteString("select") net.WriteString(row:GetColumnText(2)) net.SendToServer()
        frame:Close()
    end
    local base=string.Trim(GetConVar("emu_url"):GetString()):gsub("/*$", "/")
    if base=="/" then status:SetText("This server has not set emu_url, so no catalog is available.") return end
    http.Fetch(base .. "roms.json",function(body,_,_,code)
        if not IsValid(frame) then return end
        if not available() then frame:Close() return end
        if base ~= string.Trim(GetConVar("emu_url"):GetString()):gsub("/*$", "/") then
            status:SetText("Web host changed. Reopen the cartridge picker.") return
        end
        local data=code==200 and #body <= 1024 * 1024 and util.JSONToTable(body)
        if not istable(data) or not istable(data.roms) then status:SetText("Catalog unavailable. Check the shared web host.") return end
        for _,row in ipairs(data.roms) do
            row = emu.NormalizeCatalogRow(row)
            if row and row.system==system then rows[#rows+1]=row end
        end
        populate() status:SetText(#rows .. " games available. Double-click to select.")
    end,function() if IsValid(frame) then status:SetText("Unable to reach the shared web host.") end end)
end
properties.Add("emu_choose_game",{MenuLabel="Choose GEMU game",Order=900,MenuIcon="icon16/controller.png",
    Filter=function(_,ent) return IsValid(ent) and ent.IsEmuCartridge and not ent:GetIsInserted() end,
    Action=function(_,ent) emu.OpenCartridgePicker(ent) end})
