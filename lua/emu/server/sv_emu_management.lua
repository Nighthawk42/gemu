-- Server-authoritative maintenance, catalog selection and ownership protection.
if not SERVER then return end
util.AddNetworkString("emu_manage")
util.AddNetworkString("emu_power_off")

local catalog, catalogURL, fetching, generation, nextFetch = {}, nil, false, 0, 0
function emu.RefreshCatalog()
    local base = string.Trim(GetConVar("emu_url"):GetString()):gsub("/*$", "/")
    if base == "/" then catalog, catalogURL = {}, base return end -- emu_url not configured.
    if base ~= catalogURL then
        catalog, catalogURL, fetching, nextFetch = {}, base, false, 0
        generation = generation + 1
    end
    if fetching or CurTime() < nextFetch then return end
    fetching = true
    nextFetch = CurTime() + 10
    local request = generation
    http.Fetch(base .. "roms.json", function(body, _, _, code)
        if request ~= generation then return end
        fetching = false
        if code ~= 200 or #body > 1024 * 1024 then return end
        local data = util.JSONToTable(body)
        if not istable(data) or not istable(data.roms) then return end
        local nextCatalog = {}
        for _, row in ipairs(data.roms) do
            row = emu.NormalizeCatalogRow(row)
            if row then
                nextCatalog[row.system .. ":" .. row.filename] = row
            end
        end
        catalog, catalogURL = nextCatalog, base
    end, function() if request == generation then fetching = false end end)
end
hook.Add("InitPostEntity", "Emu_LoadCatalog", emu.RefreshCatalog)
cvars.AddChangeCallback("emu_url", function() emu.RefreshCatalog() end, "Emu_CatalogURL")

net.Receive("emu_manage", function(_, ply)
    local ent, action = net.ReadEntity(), net.ReadString()
    if CurTime() < (ply.EmuNextManage or 0) then return end
    ply.EmuNextManage = CurTime() + 0.5
    if not emu.CanManage(ply, ent) or not ply:Alive() then return end
    local target = emu.GetSetupTarget(ent)
    if target.IsEmuConsole then
        if not emu.IsNearSetup(ply, target, emu.PlayDistance) then return end
    elseif ply:GetShootPos():DistToSqr(ent:WorldSpaceCenter()) > emu.PlayDistance^2 then return end
    if action == "power_off" and (target.IsEmuConsole or target.IsEmuHandheld) then
        if target.IsEmuConsole then target:SetPower(false) emu.ReleaseConsole(target)
        else
            local holder = target:GetOwner()
            if IsValid(holder) and holder.EmuSession == target then emu.EndSession(holder, true) end
        end
        target.EmuHandoffState = nil
        net.Start("emu_power_off") net.WriteEntity(target) net.Broadcast()
    elseif action == "select" and target.IsEmuCartridge and not target:GetIsInserted() then
        local filename = net.ReadString()
        local id = target:GetSystemId()
        local row = catalog[id .. ":" .. filename]
        if not row then emu.RefreshCatalog() ply:ChatPrint("GEMU: That game is not in the server catalog. Try again shortly.") return end
        target.EmuHandoffState = nil
        target:SetRomName(filename)
        local title, skin, blank = row.title, 0, true
        for _, preset in pairs(emu.Systems[id].cartridges or {}) do
            if preset.rom == filename then title, skin, blank = preset.title, preset.skin or 0, false break end
        end
        target:SetCartridgeSkin(skin)
        target:SetSkin(skin)
        target:SetBlankCartridge(blank)
        target:SetGameTitle(title)
        ply:ChatPrint("GEMU: Cartridge set to " .. title)
    end
end)

