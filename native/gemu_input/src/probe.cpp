#include "directinput.h"
#include <iostream>
int main() {
    gemu::DirectInput input;
    auto devices=input.List();
    for(const auto& d:devices) {
        std::cout << "DirectInput: " << d.name << " ID=" << d.id << " VID=" << std::hex << LOWORD(d.product) << " PID=" << HIWORD(d.product) << std::dec << '\n';
        const auto state=input.Poll(d.id);
        std::cout << "connected=" << state.connected << " x=" << state.value.lX << " y=" << state.value.lY << " pov=" << state.value.rgdwPOV[0] << " buttons=";
        for(int i=0;i<128;i++) if(state.value.rgbButtons[i]&0x80)std::cout<<i+1<<',';
        std::cout<<'\n';
    }
    return devices.empty()?1:0;
}
