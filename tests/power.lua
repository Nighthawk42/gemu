CLIENT=true
local count=0
local function check(v,m) assert(v,m) count=count+1 end
function IsValid(v) return type(v)=='table' and v.valid~=false end
function table.Copy(t) local r={} for k,v in pairs(t) do r[k]=type(v)=='table' and table.Copy(v) or v end return r end
local original={['$basetexture']='original',['$phong']='1',['$flags']=123,['$flags_defined2']=1}
function Material() return {GetKeyValues=function() return original end} end
local materials={}
function CreateMaterial(name,shader,values)
    materials[name]=values
    return {GetName=function() return name end}
end
emu={GetSystem=function(s) return {id=s.id} end,IsHandheld=function(s) return s.handheld end,
    GetRemoteScreen=function(s) return s.remote end}
dofile('lua/emu/client/cl_emu_power.lua')
local model={SetSubMaterial=function(self,index,value) self[index]=value end}
local source={id='snes',power=false,GetPower=function(s) return s.power end}
emu.ApplyPowerLED(model,source)
check(model[0]==nil,'off must restore original model material')
source.power=true
emu.ApplyPowerLED(model,source)
check(model[0]=='!gemu_power_snes','on must use isolated power material')
check(original['$basetexture']=='original','must not mutate global source material')
check(materials.gemu_power_snes['$selfillummask']=='gemu/power/snes_mask','only LED region must emit light')
emu.ApplyTVPowerLED(model,source)
check(model[7]=='!gemu_crt_power','TV indicator follows console power')
source.power=false
emu.ApplyTVPowerLED(model,source)
check(model[7]==nil,'TV indicator resets on power off')
source={id='gba',handheld=true,GetHasCartridge=function() return true end}
check(not emu.IsDevicePowered(source),'idle handheld must not light up')
emu.ActiveTarget=source emu.ActiveWindow={Ready=true}
check(emu.IsDevicePowered(source),'ready local handheld must light up')
emu.ApplyPowerLED(model,source)
check(materials.gemu_power_gba['$color2']=='{ 64 81 133 }','GBA powered shell keeps its original purple tint')
check(materials.gemu_power_gba['$flags']==nil and materials.gemu_power_gba['$flags_defined2']==nil,'engine flags must not be cloned')
emu.ActiveWindow.Error=true
check(not emu.IsDevicePowered(source),'failed handheld must not light up')
source.remote={}
check(emu.IsDevicePowered(source),'spectator handheld indicator follows remote video')
print('All '..count..' power LED tests PASSED!')
