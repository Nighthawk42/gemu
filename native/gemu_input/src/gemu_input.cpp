#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "GarrysMod/Lua/Interface.h"

#include <Windows.h>
#include <Xinput.h>

#include <algorithm>
#include "directinput.h"

#pragma comment(lib, "Xinput.lib")

using namespace GarrysMod::Lua;

namespace
{
    gemu::DirectInput direct;
    void SetString(ILuaBase* lua, const char* key, const std::string& value) {
        lua->PushString(key); lua->PushString(value.c_str()); lua->SetTable(-3);
    }
    LUA_FUNCTION(GetDevices) {
        LUA->CreateTable(); int i=1;
        for(const auto& item:direct.List()) {
            LUA->PushNumber(i++); LUA->CreateTable();
            SetString(LUA,"id",item.id); SetString(LUA,"name",item.name);
            LUA->SetTable(-3);
        }
        return 1;
    }
    constexpr int kFirstSlot = 0;
    constexpr int kLastSlot = 3;

    double NormalizeStick(SHORT value)
    {
        const double normalized = value < 0
            ? static_cast<double>(value) / 32768.0
            : static_cast<double>(value) / 32767.0;
        return std::max(-1.0, std::min(1.0, normalized));
    }

    double NormalizeTrigger(BYTE value)
    {
        return static_cast<double>(value) / 255.0;
    }

    void SetBool(ILuaBase* lua, int table, const char* key, bool value)
    {
        lua->PushString(key);
        lua->PushBool(value);
        lua->SetTable(table);
    }

    void SetNumber(ILuaBase* lua, int table, const char* key, double value)
    {
        lua->PushString(key);
        lua->PushNumber(value);
        lua->SetTable(table);
    }

    LUA_FUNCTION(GetState)
    {
        const int slot = LUA->IsType(1, Type::Number)
            ? static_cast<int>(LUA->GetNumber(1))
            : 0;
        if (slot < kFirstSlot || slot > kLastSlot)
        {
            LUA->ArgError(1, "XInput slot must be between 0 and 3");
            return 0;
        }

        XINPUT_STATE state{};
        const DWORD result = XInputGetState(static_cast<DWORD>(slot), &state);
        const bool connected = result == ERROR_SUCCESS;

        LUA->CreateTable();
        SetNumber(LUA, -3, "slot", slot);
        SetBool(LUA, -3, "connected", connected);
        SetNumber(LUA, -3, "error", static_cast<double>(result));
        SetNumber(LUA, -3, "packet", connected ? state.dwPacketNumber : 0);
        SetNumber(LUA, -3, "buttons", connected ? state.Gamepad.wButtons : 0);
        SetNumber(LUA, -3, "left_trigger", connected ? NormalizeTrigger(state.Gamepad.bLeftTrigger) : 0.0);
        SetNumber(LUA, -3, "right_trigger", connected ? NormalizeTrigger(state.Gamepad.bRightTrigger) : 0.0);
        SetNumber(LUA, -3, "left_stick_x", connected ? NormalizeStick(state.Gamepad.sThumbLX) : 0.0);
        SetNumber(LUA, -3, "left_stick_y", connected ? NormalizeStick(state.Gamepad.sThumbLY) : 0.0);
        SetNumber(LUA, -3, "right_stick_x", connected ? NormalizeStick(state.Gamepad.sThumbRX) : 0.0);
        SetNumber(LUA, -3, "right_stick_y", connected ? NormalizeStick(state.Gamepad.sThumbRY) : 0.0);
        return 1;
    }

    LUA_FUNCTION(GetVersion)
    {
        LUA->PushString("gemu_input/2");
        return 1;
    }
    LUA_FUNCTION(GetDirectState) {
        const auto state=direct.Poll(LUA->IsType(1,Type::String)?LUA->GetString(1):"");
        LUA->CreateTable(); SetBool(LUA,-3,"connected",state.connected);
        SetString(LUA,"backend","directinput");
        SetNumber(LUA,-3,"left_stick_x",state.connected?NormalizeStick(static_cast<SHORT>(state.value.lX)):0);
        SetNumber(LUA,-3,"left_stick_y",state.connected?-NormalizeStick(static_cast<SHORT>(state.value.lY)):0);
        SetNumber(LUA,-3,"pov",state.connected && LOWORD(state.value.rgdwPOV[0])!=0xffff?state.value.rgdwPOV[0]:-1);
        LUA->PushString("raw_buttons");LUA->CreateTable();
        for(int i=0;i<128;i++){LUA->PushNumber(i+1);LUA->PushBool(state.connected && (state.value.rgbButtons[i]&0x80));LUA->SetTable(-3);}
        LUA->SetTable(-3);return 1;
    }
}

GMOD_MODULE_OPEN()
{
    LUA->CreateTable();

    LUA->PushString("get_devices"); LUA->PushCFunction(GetDevices); LUA->SetTable(-3);
    LUA->PushString("get_direct_state"); LUA->PushCFunction(GetDirectState); LUA->SetTable(-3);

    LUA->PushString("get_state");
    LUA->PushCFunction(GetState);
    LUA->SetTable(-3);

    LUA->PushString("version");
    LUA->PushCFunction(GetVersion);
    LUA->SetTable(-3);

    // Keep a global reference so Lua can use the result of require() and the
    // startup shim can also recover it on builds that return true from require.
    LUA->PushSpecial(SPECIAL_GLOB);
    LUA->PushString("gemu_input");
    LUA->Push(-3);
    LUA->SetTable(-3);
    return 1;
}

GMOD_MODULE_CLOSE()
{
    (void)LUA;
    direct.Shutdown();
    return 0;
}
