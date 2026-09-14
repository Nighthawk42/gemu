#pragma once
#define DIRECTINPUT_VERSION 0x0800
#include <Windows.h>
#include <dinput.h>
#include <vector>
#include <string>
#include <cstdio>

namespace gemu {
struct Device { GUID guid; std::string id, name; DWORD product; };
struct DirectState { bool connected = false; DIJOYSTATE2 value{}; };
class DirectInput {
    IDirectInput8A* api = nullptr;
    IDirectInputDevice8A* device = nullptr;
    HWND window = nullptr;
    std::string selected;
    std::vector<Device> devices;
    ULONGLONG refreshed = 0;
    static BOOL CALLBACK Enumerate(const DIDEVICEINSTANCEA* info, void* context) {
        auto& list = *static_cast<std::vector<Device>*>(context);
        char id[64]; const auto& g = info->guidInstance;
        std::snprintf(id, sizeof(id), "%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            g.Data1,g.Data2,g.Data3,g.Data4[0],g.Data4[1],g.Data4[2],g.Data4[3],g.Data4[4],g.Data4[5],g.Data4[6],g.Data4[7]);
        list.push_back({info->guidInstance,id,info->tszProductName,info->guidProduct.Data1});
        return DIENUM_CONTINUE;
    }
    static BOOL CALLBACK SetRange(const DIDEVICEOBJECTINSTANCEA* object, void* context) {
        DIPROPRANGE range{}; range.diph.dwSize = sizeof(range); range.diph.dwHeaderSize = sizeof(range.diph);
        range.diph.dwHow = DIPH_BYID; range.diph.dwObj = object->dwType; range.lMin = -32768; range.lMax = 32767;
        static_cast<IDirectInputDevice8A*>(context)->SetProperty(DIPROP_RANGE, &range.diph);
        return DIENUM_CONTINUE;
    }
    void ReleaseDevice() { if (device) { device->Unacquire(); device->Release(); device = nullptr; } selected.clear(); }
public:
    ~DirectInput() { Shutdown(); }
    void Shutdown() { ReleaseDevice(); if (api) {api->Release();api=nullptr;} if(window){DestroyWindow(window);window=nullptr;} devices.clear();refreshed=0; }
    const std::vector<Device>& List() {
        if (!api && FAILED(DirectInput8Create(GetModuleHandle(nullptr), DIRECTINPUT_VERSION, IID_IDirectInput8A, reinterpret_cast<void**>(&api), nullptr))) return devices;
        if (!refreshed || GetTickCount64() - refreshed > 2000) {
            devices.clear(); api->EnumDevices(DI8DEVCLASS_GAMECTRL, Enumerate, &devices, DIEDFL_ATTACHEDONLY); refreshed=GetTickCount64();
        }
        return devices;
    }
    DirectState Poll(const std::string& id) {
        DirectState result;
        const auto& list = List();
        const Device* found = nullptr;
        for (const auto& item : list) if (item.id == id || (id.empty() && !found)) { found=&item; if(!id.empty())break; }
        if (!found) {ReleaseDevice();return result;}
        if (!device || selected != found->id) {
            ReleaseDevice();
            if (!window) window=CreateWindowExA(0,"STATIC","GEMU input",WS_OVERLAPPED,0,0,1,1,nullptr,nullptr,GetModuleHandle(nullptr),nullptr);
            if (!window || FAILED(api->CreateDevice(found->guid,&device,nullptr))) return result;
            if (FAILED(device->SetDataFormat(&c_dfDIJoystick2)) || FAILED(device->SetCooperativeLevel(window,DISCL_BACKGROUND|DISCL_NONEXCLUSIVE))) {ReleaseDevice();return result;}
            device->EnumObjects(SetRange,device,DIDFT_AXIS); selected=found->id;
        }
        HRESULT hr=device->Poll();
        if (FAILED(hr)) {device->Acquire(); hr=device->Poll();}
        if (SUCCEEDED(hr) && SUCCEEDED(device->GetDeviceState(sizeof(result.value),&result.value))) result.connected=true;
        else ReleaseDevice();
        return result;
    }
};
}
