# GEMU native gamepad bridge

This optional Windows x64 client module polls XInput and DirectInput. The original XInput API remains compatible:

```lua
local state = require("gemu_input").get_state(0)
-- state.connected, state.buttons, state.left_stick_x/y,
-- state.right_stick_x/y, state.left_trigger/right_trigger, state.packet
```

The Lua input router maps either backend to the active system and supports both multiplayer roles. Auto mode prefers the selected XInput slot, then the selected DirectInput device (or the first enumerated device). Keyboard input continues to work without the DLL.

```lua
local api = require("gemu_input")
local devices = api.get_devices() -- entries: id (instance GUID), name
local state = api.get_direct_state(devices[1].id)
-- connected, backend, left_stick_x/y (-1..1; positive Y is up),
-- pov (hundredths of degrees; -1 neutral), raw_buttons[1..128] booleans
```

DirectInput enumerates attached game controllers and uses nonexclusive background acquisition through an invisible process-owned window. Lua forwards input only while GEMU has focus. Disconnected devices release their buttons; reacquisition is retried. Enumeration is cached for two seconds. Device/interface/window resources are released at module close. A missing explicitly selected device does not silently switch to another pad.

## Build (Windows x86-64)

The official `gmod-module-base` development headers are fetched by CMake when
`GMOD_HEADERS_DIR` is omitted. A local checkout can be supplied for offline
builds. From the repository root:

```text
cmake -S native/gemu_input -B .work/native-build -G "Visual Studio 18 2026" -A x64
cmake --build .work/native-build --config Release
```

The output is `gmcl_gemu_input_win64.dll`. Copy it manually to
`garrysmod/lua/bin/`; Garry's Mod binary modules are installed there and are
not Workshop addon files. Set `emu_gamepad_slot 0` through `3` in the client
console and tune `emu_gamepad_deadzone` when a stick needs more or less
neutral range.

Open `emu_controls` for backend/device selection, connection status, slot/deadzone settings and DirectInput button-number mappings. Defaults for the tested generic USB SNES-style pad: 1=X, 2=A, 3=B, 4=Y, 5=L, 6=R, 9=Select, 10=Start. Buttons 7/8 are unused; 0 unbinds a mapping. These settings are per client and shared across its DirectInput devices. XInput mappings remain fixed. Steam Controller API and force feedback are not implemented.

The build also produces `gemu_input_probe.exe`, using the same DirectInput backend. It successfully acquired and polled the attached USB gamepad. Focused Lua checks cover both backends, default bindings, POV diagonals, Genesis translation, remapping and disconnect clearing. Live GMod button presses remain unverified. Restart GMod after replacing the DLL; a map reload cannot replace a loaded binary.
