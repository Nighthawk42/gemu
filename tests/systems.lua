-- Cross-platform profile and blank material behavior with mocked model operations.
local count = 0
local function check(value, message) assert(value, message) count=count+1 end
function Vector(x,y,z) return {x=x,y=y,z=z} end
function Angle(p,y,r) return {p=p,y=y,r=r} end
function table.Copy(value)
    local copy = {}
    for k,v in pairs(value) do copy[k] = type(v)=='table' and table.Copy(v) or v end
    return copy
end
emu = {Systems={}}
local ids = {'snes','gba','nes','gb','gbc','genesis'}
for _, id in ipairs(ids) do dofile('lua/emu/systems/' .. id .. '.lua') end
function emu.GetSystem(source) return emu.Systems[source.id] end
dofile('lua/emu/sh_emu_cartridges.lua')
for _, id in ipairs(ids) do
    local profile = emu.Systems[id]
    local source = {id=id, present=true, blank=true}
    function source:GetHasCartridge() return self.present end
    function source:GetBlankCartridge() return self.blank end
    function source:GetCartridgeSkin() return 0 end
    local model = {materials={}}
    function model:SetSkin(skin) self.skin=skin end
    function model:SetBodygroup(group,value) self.group=value end
    function model:GetBoneCount() return 8 end
    function model:ManipulateBoneScale(bone,scale) self.scale=scale end
    function model:SetSubMaterial(index,material) self.materials[index]=material end
    check(profile.id==id and profile.buttons.start and profile.buttons.a, id .. ' controller contract')
    check(profile.cartridgeClass and profile.blankMaterial, id .. ' cartridge contract')
    emu.ApplyCartridgeAppearance(model, source, false)
    for _, index in ipairs(profile.cartridgeLabelMaterials) do
        check(model.materials[index]==profile.blankMaterial, id .. ' blank loose label')
    end
    emu.ApplyCartridgeAppearance(model, source, true)
    for _, index in ipairs(profile.insertedLabelMaterials or {}) do
        check(model.materials[index]==profile.blankMaterial, id .. ' blank inserted label')
    end
    source.present=false
    emu.ApplyCartridgeAppearance(model, source, true)
    for _, index in ipairs(profile.insertedLabelMaterials or {}) do
        check(model.materials[index]==nil, id .. ' empty slot clears label override')
    end
    if profile.cartridgeBodygroup then check(model.group==profile.cartridgeEmpty,id .. ' empty slot bodygroup') end
    source.blank=false
    emu.ApplyCartridgeAppearance(model, source, false)
    for _, index in ipairs(profile.cartridgeLabelMaterials) do
        check(model.materials[index]==nil, id .. ' labeled cartridge clears blank override')
    end
end
check(emu.Systems.genesis.buttonAliases.y=='c' and emu.Systems.genesis.buttonAliases.r=='z', 'Genesis six-button aliases')
check(emu.Systems.snes.insertedLabelMaterials[1]==3, 'SNES label must not override shell material 2')
print('All ' .. count .. ' cross-system tests PASSED!')
