# GEMU

Retro consoles and handhelds for Garry's Mod with one Emulatrix WebUI. SNES, NES and Genesis use console + CRT stations; GBA, GB and GBC use handheld SWEPs. Volume, input, fullscreen, saves, sessions and spectator screens share the same implementation.

## Folder layout

```text
addon.json                 Workshop archive metadata and exclusions
lua/autorun/               Registration and settings
lua/emu/systems/           System models, buttons, cartridges and alignment
lua/emu/client/            Shared browser, input, screens and spectator receiver
lua/emu/server/            Controller reservations and spectator relay
server/stream/            Optional WebRTC broker and media-service deployment
native/gemu_input/         Optional XInput/DirectInput client module (manual install)
lua/entities/             Console, CRT and cartridge entities
lua/weapons/              Shared handheld base and system-specific SWEPs
models/, materials/       Source assets, including GEMU blank VTF materials
web/                      Separately hosted frontend
  app.js                  Shared UI and GMod bridge
  systems.js              Core adapters
  cores/                  Bundled Emulatrix builds and provenance
  roms/<system>/          Local games grouped by system; ignored, never in GMA
server/                   Local development web server
tests/, tools/            Automated checks and packaging
dist/                     Ignored validated gemu.gma release output
.work/                    Ignored temporary build/development work (created as needed)
```

## Install and host

Run `python tools/deploy_game.py` to build and validate `dist/gemu.gma`, extract its runtime files, and install them into `garrysmod/addons/gemu/`. The tools find Garry's Mod through Steam's library list; set `GMOD_ROOT` or pass `--game-root`/`--gmad` to override. The default local installation is a real addon folder, not a checkout junction. `--format gma` installs the archive instead. Previous packages or development folders are preserved under `garrysmod/gemu-backups/`, outside the addon search path. Only one GEMU installation should be mounted. Restart GMod after deployment. Code edits require redeployment.

The optional controller DLL stays in `garrysmod/lua/bin/`, streaming credentials in `garrysmod/data/emu/stream_key.txt`, and settings in `garrysmod/cfg/gemu.cfg`. Deploying the GMA does not replace these or player saves. The web frontend and selected ROMs remain separately hosted. `tools/link_gmod.ps1` is an explicit development-only alternative; it refuses to add a junction while the installed GMA is present.

Server admins do **not** need their own repacked addon. Install the same release (or, once published, the same Workshop addon), then set `emu_url` in `cfg/gemu.cfg` for that server's frontend/catalog. Optional WebRTC uses `emu_sv_stream_service`, `emu_sv_stream_enabled` and the separate server-only credential file. ROMs follow `roms/<system>/<filename>` under that frontend. Blank cartridges use the server catalog. Code/assets changes require a new addon release; changing hosting or ROM catalogs does not. Native controller DLLs are installed manually on each participating client, outside the GMA.

`server.cfg` does not reach GEMU's Lua-created settings on listen servers. Put GEMU settings (`emu_url`, `emu_sv_stream_service`, `emu_sv_stream_enabled`, `emu_sv_stream_transport`, ...) in `garrysmod/cfg/gemu.cfg`. Once its settings exist, the addon reads that file and applies only its `emu_*` lines (GMod blocks `exec` from Lua), on both listen and dedicated servers. The console prints how many settings were applied. `emu_rtc_server_status` reports whether the stream service is enabled and configured.

Each server owner supplies their own frontend and ROM deployment and sets `emu_url` in `garrysmod/cfg/gemu.cfg`, for example `emu_url "https://games.example.org/gemu/"`. The addon ships with no default host; until `emu_url` is set, opening a game says it is missing. Cartridge filenames contain only the basename; the shared frontend loads `roms/<system>/<filename>` beneath that base. Supported system folders are `snes`, `nes`, `gba`, `gb`, `gbc` and `genesis`. There are no per-cartridge host overrides.

`web/library.html` lists the hosted catalog, and `web/roms.json` records each game's system, filename, size and SHA-256. `tools/test_titles.json` lists a test selection by relative source path and hosted filename; `python tools/prepare_test_library.py --library <your ROM library>` stages it into `web/roms/` and rebuilds the catalog. `tools/package_web.py` packages frontend assets and only catalog-listed ROMs; it never uploads a whole library. Deploy into a fresh directory and archive prior releases outside the web root so removed titles cannot remain accessible. ROM bytes never enter Git or the GMA. Only host ROMs you are entitled to distribute.

`python tools/organize_emulation.py --library <your ROM library>` builds a non-destructive, hard-linked normalized view (`GEMU/roms/<system>` plus a manifest) inside that library.

Link the checkout with `powershell -File tools/link_gmod.ps1 -GameRoot <GarrysMod\garrysmod>`, or install the generated GMA. Reload the map after Lua/entity changes.

Run `python server/server.py` to serve `web/` on port 8080. Set the server's `emu_url` to `http://localhost:8080/` for a same-machine check. Multiplayer clients need a reachable URL: localhost refers to each client's own machine. Archived convars may retain an older URL. Local edits do not deploy automatically.

Supply games in `web/roms/<system>/` and list them in `web/roms.json` with system, filename, size and SHA-256. Existing SNES/GBA presets name files in their profiles. `python tools/make_test_roms.py` generates original minimal NES/GB/GBC/Genesis diagnostics in those folders. These exercise APIs rather than demonstrate game compatibility. Commercial ROMs are not included in the released addon.

## Play and cartridges

Spawn stations under **Entities > GEMU - Consoles**. Press **Use** on a console or TV to play. The first player to start a game reserves that console; the camera faces the screen and movement is suppressed while they hold the controls. **E** leaves the controls, but the game keeps running and stays reserved: walking away, dying, chatting or closing the window neither pauses nor stops it. Only the player pauses it (**P**, the menu **Pause** button or `emu_pause`). A game ends on **Stop**, power off, ejecting or changing the cartridge, removing the console or TV, disconnecting, or starting another device. Other players can join as Player 2 but cannot take over a reserved console. This moves the camera, not the player's body; there is no chair or seated animation. **Shift+Use** opens controls; **Reload+Use** or **Alt+Use** ejects. Touch a compatible cartridge to the console to insert it.

Handhelds appear under **Weapons > GEMU - GBA / GB / GBC**. Primary fire plays, secondary fire zooms, reload opens controls, and **Alt+R** or **Crouch+R** ejects. While holding a matching handheld, press Use on a loose cartridge to insert it. Holstering releases input; the game keeps running until it is paused, powered off, or the handheld leaves your inventory.

Cartridges appear under **GEMU - SNES / NES / GENESIS / GBA / GB / GBC**. Each system has a blank cartridge. Open context-menu **Edit Properties**, set **RomName** to the hosted filename and **GameTitle**, then insert it. Blank VTFs remove artwork; single-atlas NES/Genesis models receive a plain shell finish. Existing labeled SNES/GBA presets remain. The old mGBA addon's `ent_mgba_cartridge_*` aliases have been removed, so saves or dupes that still name those classes no longer spawn them.

## Shared controls

Spawn-menu icons live in `materials/gemu/icons/`. Each system shares one generic cartridge icon across its blanks and game presets. Rebuild these geometric PNG assets with `python tools/make_icons.py` (Pillow required). The GMA check requires all 13 icons.

Use **Utilities > User > Emulators > Configure Keyboard and Controller** to customize the single default mapping. The WebUI Controls button opens the same settings in GMod.

| Action | Default key |
| --- | --- |
| Direction | Arrow keys |
| B / A | Z / X |
| SNES Y / X | C / V |
| SNES/GBA L / R | Q / F |
| Genesis A / B / C / X / Y / Z | Z / X / C / V / Q / F |
| Start / Select (Genesis Mode) | Enter / Backspace |
| Volume down / up; mute | - / =; M |
| Save / load state | F5 / F8 |
| Fullscreen / controls | F11 / F1 |
| Leave play (game keeps running) | E |
| Pause / resume | P |

Fullscreen/menu reuse the running session. GMod saves live under `garrysmod/data/emu/saves/`, separated by system and ROM. Bindable commands: `emu_volume_down`, `emu_volume_up`, `emu_mute`, `emu_fullscreen`, `emu_save`, `emu_load`, `emu_reset`, `emu_pause`, `emu_menu`, `emu_leave`, `emu_handheld`. The old mGBA `emu_gba` alias has been removed.

### Native gamepad input

`native/gemu_input` contains an optional x86-64 client binary module. It polls XInput slots 0-3 and exposes normalized sticks, triggers, packet numbers and button bits to Lua; the shared input router maps Xbox-compatible pads to the active system and keeps keyboard layouts working alongside it. Build it with CMake and the Visual Studio C++ workload, then copy the resulting `gmcl_gemu_input_win64.dll` to `garrysmod/lua/bin/`. Binary modules must be installed there and are intentionally excluded from the Workshop GMA. Set `emu_gamepad_slot 0` (through `3`) and tune `emu_gamepad_deadzone` if needed. Generic USB pads can use the DirectInput backend, selected through `emu_controls`. Auto mode prefers the configured XInput slot and falls back to DirectInput.

### Save handling

The shared menu provides three manual slots plus an autosave. Autosave runs every 30 seconds during play, on pause, and on normal session shutdown. Startup restores it before granting input. Normal close waits for a write acknowledgement; a six-second timeout reports failure. A crash or forced game exit can still lose progress since the last autosave.

Slots are JSON files in `garrysmod/data/emu/saves/<system>/<game-and-id>/`, with previous copies. Writes are staged and verified before replacing the primary. Corrupt primaries cannot overwrite a valid backup. Checksums detect damage; ROM-content identity and a state-format build ID prevent accidentally loading another revision. Legacy browser-local saves for the same filename migrate when read. If both autosave copies fail, automatic writes stop until a manual save or valid import, preserving damaged files.

Staging and backup filenames also end in `.json`, as required by GMod's file-write extension whitelist. Handoff uploads and downloads use acknowledged 8 KiB chunks with one chunk in flight per transfer, instead of queuing a complete multi-megabyte state into the reliable channel. Stalled transfers expire; the maximum state size remains 4 MiB. This bounds handoff network buffering but does not measure live multiplayer latency.

Export writes a portable JSON file to `garrysmod/data/emu/saves/<system>/` independently of slot storage. To import a transferred file, place it there, open the same game, select a slot and click Import. Failed import persistence restores the prior gameplay state. Standalone web use retains browser-local slots and file import/download. Saves remain on the player's machine, not the web host, and are not transferred between players automatically.

Focused checks include `luajit tests/stream.lua`, `luajit tests/audio_stream.lua`, `luajit tests/handoff.lua`, `luajit tests/player2.lua` and `luajit tests/duplication.lua`, alongside the save checks.

## Multiplayer

### Control configuration

GEMU uses one arrow-key default across systems and multiplayer roles: arrows move, Z/X are B/A, C/V are Y/X, Q/F are L/R, Enter starts and Backspace selects. Genesis translates these shared actions to its A/B/C/X/Y/Z buttons. Unused buttons are ignored by simpler systems.

Open **Utilities → User → Emulators → Configure Keyboard and Controller**, press **F1** while playing, click the WebUI **Controls** button, or run `emu_controls`. Click a binding to replace it; Clear unbinds it, and Restore defaults resets the map. Duplicate assignments clear the previous action. Reserved game/GEMU shortcut keys cannot be assigned. Bindings persist in client `emu_key_<action>` convars; old `emu_input_layout` presets no longer select controls. Changes apply to all devices on that client and both multiplayer controller roles.

The same window reports whether the native XInput module loaded and whether the selected controller slot is connected, with slot/deadzone settings. XInput and DirectInput polling are implemented. DirectInput exposes device selection and editable numbered button mappings; XInput mappings remain fixed. Steam Controller API integration remains unimplemented. The Windows x64 DLL is published on GitHub Releases; each client installs it into `garrysmod/lua/bin/` separately. In-game hardware verification remains pending.

### Spectator transport

**64 KiB is a per-message limit, not a per-second bandwidth limit.** The built-in relay shares GMod's game network and remains a low-fps preview. An illustrative 8 KiB JPEG at 4 fps plus 8-bit μ-law audio (about 11 KiB/s) costs about 43 KiB/s per viewer before overhead; actual frame size depends on gameplay.

GMod rarely delivers multi-kilobyte unreliable messages on listen/P2P servers. With `emu_sv_stream_transport auto` (default), dedicated servers send fallback media unreliably, while listen servers send it reliably under a per-spectator byte budget, `emu_sv_stream_budget` (default 32000 bytes/s), and a matching client upload budget. Frames that do not fit are skipped rather than queued. Set `reliable` or `unreliable` to override. `emu_stream_status` reports average received JPEG size. Increasing fps also increases client/server traffic and can cause media drops or interfere with other game traffic. See [GMod's net limits](https://wiki.facepunch.com/gmod/net.Start).

The optional WebRTC transport is implemented in server/stream/: LiveKit forwards VP8 video and Opus audio, and a GEMU broker authorizes one publisher and nearby viewers per entity session. Media bypasses GMod's net channel. The JPEG/PCM relay remains the default and automatically serves viewers whose WebRTC connection is unavailable. See [streaming setup](server/stream/README.md) for installation, credentials, ports, limits and fallback behavior. This is a self-hosted service, separate from the optional gamepad DLL, and excluded from the GMA.

A headless-browser publish/view check received video and audio and detected publisher departure, and a two-client GMod test on the patched CEF connected publisher and viewer through LiveKit. Direct UDP and ICE-TCP are enabled. An optional TURN relay (UDP 3478 and TLS 5349, via `server/stream/compose.turn.yaml`) helps viewers whose networks block the direct media ports; networks that allow only port 443 still use fallback. Run `emu_rtc_status`, `emu_stream_status`, or `emu_stream_capabilities` for diagnostics.

The bare /gemu/ URL shows the game library. Individual games use `?system=<system>&rom=<filename>`. Streaming rooms have separate server-instance and entity-session IDs, so two copies of the same console/game stay isolated. A copied game URL starts an independent local emulator; only a game-server-authorized spectator receives that entity's stream.

The running client emulates the game and, whether or not its player holds the controls, relays compressed screen frames and low-rate mono audio through the server to nearby spectators using the shared CRT/handheld renderer. Default video is **4 fps**, a **256-pixel-wide JPEG at the core's native aspect ratio**, and **1800 units**. An AudioWorklet captures audio, downsamples it to **11.025 kHz**, encodes it as 8-bit μ-law and sends it in bounded packets. A short burst allowance absorbs capture jitter. Nothing new is captured while the game is paused. Server settings: `emu_sv_stream_fps` (1-8), `emu_sv_stream_distance`; client JPEG quality: `emu_stream_quality` (20-60). The server checks ownership, session validity, packet size and rate.

Spectators receive audio only while a nearby player is watching that entity. The player running the session remains authoritative. When a session ends, a bounded emulator state snapshot is cached on the server and offered to the next player who starts the same ROM, while normal save slots remain per-client. Spectator screens show **PAUSED** over the frozen frame, **RECONNECTING...** when frames stop arriving, or who is playing when no picture is available, never "Press E to play" for someone else's game. SNES, NES and Genesis support a second controller: hold sprint while pressing Use on an occupied station, then use your configured keyboard or controller bindings; press Use again to leave. Each client has one active local session. Actual two-client rendering, audible quality and network performance still need a live GMod check.

Spectator audio is drained independently of screen rendering, follows the viewer's volume, and drops queued packets older than 250 ms. Video freshness is tracked separately so audio cannot preserve a frozen frame indefinitely. These are buffering fixes, not timestamp-based audio/video synchronization: the current JPEG and PCM packets have independent sequence numbers and no common playback clock. Browser autoplay restrictions may still prevent audible playback; this needs a live CEF check.

## Check and package

With Python, LuaJIT and Node on PATH:

```text
python tools/check.py
python tools/build_gma.py
```

Pass `--gmad` to override the build tool's local GMod installation path. Checks parse Lua, run mocked GMod contracts and boot all six real core configurations. SNES/GBA checks explicitly skip when local ROMs are absent. Browser DOM, audio device and JPEG encoding are mocked; CEF performance, audible quality and final model fit remain unverified.

The build invokes gmad and inspects the archive. Only **lua/**, **models/** and **materials/** ship. Web files, cores, ROMs, native DLLs, development scripts, documentation and scratch output stay outside the GMA. The project license is included as `lua/emu/license.lua`. Output: `dist/gemu.gma`; `tools/deploy_game.py` installs it locally. Nothing is published to Workshop automatically.

Live camera/model alignment, CEF rendering, audio and multiplayer spectator appearance remain unverified. `emu_screen_grid 1` enables the alignment aid. See `DESIGN.md` and `ACKNOWLEDGEMENTS.md` for architecture and credits.

### Entity-scoped spectator video

Only the session's running client emulates. Nearby clients receive compressed game frames and audio keyed to that console or handheld entity; they do not open the ROM or need access to the web host to watch. A shared URL would still create independent emulator instances. The server requests capture only while spectators are within range. Frame and audio packets use unreliable delivery on dedicated servers and byte-budgeted reliable delivery on listen servers, so a backlog is never replayed. Sequence numbers reject out-of-order data, and ROM checks reject stale cartridge images. Multiple nearby devices have separate receivers. Video is 256 pixels wide at the configured 1-8 fps, with each core's native aspect ratio; audio uses short mono μ-law packets.

For a two-client check, reload the map after updating both clients, play on client 1, and walk client 2 into range without pressing Use. Run `emu_stream_status` on the sender if the screen does not update. The sender should report capture requested/running (it does not need to hold the controls), and the viewer should report a fresh received frame and browser ready. Leaving range stops demand; switching cartridges cannot reuse old media. Live CEF/network verification remains pending.

DirectInput was verified on a generic USB SNES-style gamepad using the standalone native probe. Default buttons: 1=X, 2=A, 3=B, 4=Y, 5=L, 6=R, 9=Select, 10=Start; 7/8 unassigned. Configure button numbers in `emu_controls`; mappings are shared across DirectInput devices on this client. Restart GMod after installing a new DLL. Live GMod button presses remain unverified.
