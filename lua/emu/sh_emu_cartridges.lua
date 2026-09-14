-- Cartridge visuals shared by loose cartridges, consoles and handheld models.
emu = emu or {}
-- Normalize hosted metadata once for both the picker and authoritative selection.
function emu.NormalizeCatalogRow(row)
    if not istable(row) or not isstring(row.system) or not isstring(row.filename) then return end
    local profile = emu.Systems[row.system]
    local extension = row.filename:match("^[a-z0-9_]+%.([a-z0-9]+)$")
    if not profile or not extension or #row.filename > 192 then return end
    local supported = false
    for _, ext in ipairs(profile.extensions or {}) do if ext == extension then supported = true break end end
    if not supported then return end
    local title = isstring(row.title) and string.Trim(row.title:gsub("%c", " ")) or ""
    if title == "" then title = row.filename:gsub("%.[^.]+$", ""):gsub("_", " ") end
    return {system=row.system, filename=row.filename, title=title:sub(1, 192)}
end

function emu.ApplyCartridgeAppearance(model, source, inserted)
    local profile = emu.GetSystem(source)
    local present = not inserted or source:GetHasCartridge()
    model:SetSkin(present and source:GetCartridgeSkin() or 0)
    if inserted and profile.cartridgeBodygroup then
        model:SetBodygroup(profile.cartridgeBodygroup, present and profile.cartridgeInserted or profile.cartridgeEmpty)
    end
    if inserted and profile.cartridgeBone and model:GetBoneCount() > profile.cartridgeBone then
        model:ManipulateBoneScale(profile.cartridgeBone, present and Vector(1,1,1) or Vector(0,0,0))
    end
    local blank = present and source.GetBlankCartridge and source:GetBlankCartridge()
    for _, index in ipairs((inserted and profile.insertedLabelMaterials or profile.cartridgeLabelMaterials) or {}) do
        model:SetSubMaterial(index, blank and profile.blankMaterial or nil)
    end
end
