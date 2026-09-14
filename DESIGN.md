# GEMU architecture

Updated 2026-09-13.

## Session and adapters

`web/index.html`, `style.css` and `app.js` are the single frontend. Query parameters select system, ROM, title and screen mode. `systems.js` owns core names, input format, gain, pause/resume and save-state ABI. GB/GBC share one core build but separate profiles and save namespaces. GBA uses the Emulatrix JavaScript bundle; the previous standalone mGBA backend and its legacy entity aliases have been removed. `capture-worklet.js` is the AudioWorklet tap for spectator audio.

Lua creates one active DHTML session per client. Controls, fullscreen and physical screens reuse it. A session reserves its device on the server (`emu_session`, five-second keepalives, 15-second expiry) until an explicit end: Stop, power off, ejecting or changing the cartridge, display or device removal, disconnect, the handheld leaving its owner, or starting another device. Focus is separate: it locks movement and routes explicit supported buttons after server approval. Chat, focus loss, holster, death and range changes release only focus. The game runs from boot and pauses only on the player's request; `app.js` resumes cores that halt themselves on browser blur. Pause state is networked as `SessionPaused`. Target changes destroy stale browsers. The server owns reservations; it does not emulate games.

## Profiles and entities

`lua/emu/systems/` contains model paths, dimensions, UVs, bodygroups, catalogs and button aliases. `emu_console` supplies stationary behavior; NES/Genesis are thin subclasses. `emu_cartridge` supplies all cartridge behavior. `weapon_emu_base` supplies GBA/GB/GBC behavior.

SNES/Philips CRT measured alignment: console front -X, CRT front +X, relative yaw 180 degrees. Model bodygroups disable the disconnected second controller cable. CRT rendering compensates for the widescreen mesh; handhelds use measured LCD UV regions. Profile camera/model offsets still require live verification, especially new platforms.

`sh_emu_cartridges.lua` applies label overrides and inserted/empty mesh state consistently. Blank flags survive insertion/ejection. Three VTF/VMT pairs provide plain finishes. NES/Genesis share shell-and-label atlases, so their overrides cover the atlas. Editable filename/title properties configure loose blank cartridges before insertion.

## Spectators

The session runner captures raw game video without frontend chrome, whether or not it holds the controls, and sends nothing new while paused. Lua sends JPEG bytes keyed by the spawned entity. The server validates the running session, range, ROM, size and rate before forwarding the packet to every nearby client. Dedicated servers use unreliable delivery. Listen servers, where large unreliable messages rarely arrive, use reliable delivery under per-spectator and client upload byte budgets that skip frames instead of queuing them. Receivers create one DHTML image panel per entity and feed it to the same CRT or handheld renderer as local video. Frames expire unless the runner is paused, and abandoned panels are removed. Mono 8-bit μ-law audio from the AudioWorklet follows the same entity key and demand signal. Screens without video show PAUSED, RECONNECTING or the running player instead of an invitation to play.

The 65,533-byte limit applies to each net message, not bandwidth per second. Separate constraints include the shared network buffers, latency, server upload and the number of recipients. Unreliable delivery can drop media under congestion; it does not reserve bandwidth. Our 60,000-byte JPEG ceiling is a safety bound, not a measured frame size or a sustainable bandwidth target.

At an illustrative 8 KiB per JPEG and 4 fps, video uses 32 KiB/s. Mono 8-bit μ-law at 11,025 Hz adds 11,025 bytes/s (10.8 KiB/s), giving about 42.8 KiB/s per viewer before transport overhead. Ten viewers would require approximately 428 KiB/s of server media upload for one entity. On listen servers the default 32,000 bytes/s budget per spectator caps this further. Actual JPEG sizes vary with gameplay. This is adequate for a low-frame-rate preview, not smooth 30/60 fps gameplay with high-quality sound. No live bandwidth or latency measurements have been collected yet.

The optional WebRTC path is implemented using LiveKit (VP8/Opus) plus server/stream/broker.mjs. Shared web/stream.js captures the emulator canvas and post-volume WebAudio output. viewer.html renders received tracks into the existing DHTML screen material. The owner publishes once; the SFU forwards to viewers without using GMod net for media. Lua retains ownership, proximity, controller input and handoff.

sv_emu_rtc.lua generates an instance ID and a new generation for each owner/ROM/session transition, requests role credentials over authenticated HTTPS every five seconds, and sends each player only their token. Broker namespaces prevent collisions across game servers. Join tokens start without media permissions; authoritative reconciliation enables the assigned role, removes departed participants, and cleans up old rooms after restart. Configuration and membership leases expire after twelve and fifteen seconds respectively. See [service documentation](server/stream/README.md) for deployment and asynchronous revocation limits.

cl_emu_rtc.lua reports playback readiness only while video advances and audio has started. Ready viewers are omitted from JPEG/PCM forwarding; when every viewer is ready the owner stops fallback capture. Failed/expired sessions restore fallback. The viewer's volume is applied to either receiver and the inactive audio path is muted. WebRTC supplies encoded media timing and congestion control; the independent fallback packets still lack a common A/V clock.

The development SFU and broker run on a development host. A real headless Chrome publisher/viewer pair verified public video/audio transport and departure detection. This does not verify GMod CEF, audibility, all cores, or arbitrary client networks. Direct UDP and ICE-TCP are configured. TURN is an optional operator addition (`compose.turn.yaml`) on UDP 3478 and TLS 5349. A paused publisher is reported healthy to viewers so they do not drop to fallback. The service and web assets stay outside the Workshop GMA; only the Lua integration ships in it. API absence, autoplay failure or an unreachable service keeps the no-service relay available.

References: [GMod net.Start](https://wiki.facepunch.com/gmod/net.Start), [network limits](https://wiki.facepunch.com/gmod/Networking_Usage), [GMod Chromium renderer](https://wiki.facepunch.com/gmod/HTML_Web_Engine), [LiveKit deployment](https://docs.livekit.io/transport/self-hosting/deployment/).

When a session ends, the outgoing runner sends a bounded serialized core state in ordered chunks. The server caches it for the same entity and ROM and offers it to the next player who starts that ROM; normal save slots remain local. Player two's buttons go to the runner, whose client emulates. SNES, NES and Genesis forward a second controller's validated button list. Duplication relinking restores console, CRT and cartridge relationships. Ownership checks use a valid CPPI owner when available, otherwise the creator.

## Distribution and checks

The addon root stays GMod-native: Lua, models, materials. `addon.json` excludes the separately hosted frontend and development files. `tools/build_gma.py` invokes gmad and checks archive paths and required runtime files. This establishes archive structure, not Workshop publication or asset permissions.

`tools/check.py` parses Lua and runs mocked entity/focus/input/session/stream/cartridge contracts. Actual Emulatrix builds run in Node VM smoke tests for frames, input, gain routing, pause/resume, blur auto-resume, saves and teardown. `tests/audio_capture.cjs` covers the AudioWorklet processor, graph tap and μ-law codec. New-platform diagnostics are generated from source; SNES/GBA use local ROMs when available. These checks do not replace live CEF, materials, audio or two-client tests. No Computer Use testing was performed for this consolidation.

## Ownership enforcement

The server checks both cartridge and destination before insertion, including automatic touch docking. Ejection, tools, properties, physgun and gravity-gun actions share the same checks. The session runner has priority for the whole session, not only while holding the controls; another player, including the creator or an admin, cannot interrupt a reserved console. A reservation without a live server session, such as one copied into a pasted duplicate, is cleared. Idle devices allow their owner or an admin to manage them. Unowned world devices remain usable. A standalone TV retains its own ownership; linked TVs and inserted carts use their console. See tests/ownership.lua for the focused contract.
