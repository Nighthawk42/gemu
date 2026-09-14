-- Duplicator relationship restoration without spawning a live map.
SERVER=true
function istable(v) return type(v)=='table' end
function IsValid(v) return type(v)=='table' and v.valid~=false end
MOVETYPE_NONE, SOLID_NONE = 0, 1
emu={GetSystem=function() return {cartridgePosition={},cartridgeAngles={},cartridgeInserted=1,cartridgeBodygroup=2} end}
dofile('lua/emu/server/sv_emu_duplication.lua')
local display, cart = {}, {GetGameTitle=function() return 'Game' end,GetRomName=function() return 'game.sfc' end,
    GetRomUrl=function() return '' end,GetCartridgeSkin=function() return 3 end,
    GetBlankCartridge=function() return false end}
for _,name in ipairs({'SetLinkedConsole','SetParent','SetMoveType','SetSolid','SetLocalPos','SetLocalAngles','SetIsInserted','SetCurrentConsole'}) do
    display[name]=function(self,v) self[name..'Value']=v end
    cart[name]=function(self,v) self[name..'Value']=v end
end
local console={SetLinkedDisplay=function(self,v) self.display=v end,SetHasCartridge=function(self,v) self.has=v end,
    SetInsertedCart=function(self,v) self.cart=v end,SetBlankCartridge=function(self,v) self.blank=v end,
    SetGameTitle=function(self,v) self.title=v end,SetRomName=function(self,v) self.rom=v end,
    SetRomUrl=function(self,v) self.url=v end,SetCartridgeSkin=function(self,v) self.skin=v end,
    SetSkin=function(self,v) self.skinVisual=v end,SetBodygroup=function(self,i,v) self.bodygroup=v end}
emu.RelinkConsole(console,display,cart)
assert(console.display==display and display.SetLinkedConsoleValue==console,'console and CRT links restored')
assert(console.cart==cart and cart.SetCurrentConsoleValue==console and cart.SetIsInsertedValue==true,'inserted cartridge link restored')
assert(console.title=='Game' and console.rom=='game.sfc' and console.skin==3,'duplicated cartridge metadata restored')
local original={}
assert(emu.PastedEntity({[12]=original},12)==original,'numeric entity mapping restored')
assert(emu.PastedEntity({['12']=original},12)==original,'string entity mapping restored')
print('All 5 duplication tests PASSED!')
