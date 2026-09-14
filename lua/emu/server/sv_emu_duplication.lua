-- Preserve the relationships that make a console, CRT and cartridge one station.
if not SERVER then return end
emu = emu or {}

function emu.PastedEntity(createdEntities, index)
    if not istable(createdEntities) or index == nil then return end
    return createdEntities[index] or createdEntities[tonumber(index)] or createdEntities[tostring(index)]
end

function emu.RelinkConsole(console, display, cart)
    if not IsValid(console) then return end
    if IsValid(display) then
        console:SetLinkedDisplay(display)
        display:SetLinkedConsole(console)
    end
    if not IsValid(cart) then return end
    local profile = emu.GetSystem(console)
    cart:SetParent(console)
    cart:SetMoveType(MOVETYPE_NONE)
    cart:SetSolid(SOLID_NONE)
    cart:SetLocalPos(profile.cartridgePosition)
    cart:SetLocalAngles(profile.cartridgeAngles)
    cart:SetIsInserted(true)
    cart:SetCurrentConsole(console)
    console:SetHasCartridge(true)
    console:SetInsertedCart(cart)
    console:SetBlankCartridge(cart.GetBlankCartridge and cart:GetBlankCartridge() or false)
    console:SetGameTitle(cart:GetGameTitle())
    console:SetRomName(cart:GetRomName())
    console:SetRomUrl(cart:GetRomUrl())
    console:SetCartridgeSkin(cart:GetCartridgeSkin())
    console:SetSkin(cart:GetCartridgeSkin())
    if profile.cartridgeBodygroup then console:SetBodygroup(profile.cartridgeBodygroup, profile.cartridgeInserted) end
end
