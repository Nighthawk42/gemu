# GEMU optional streaming service

The service carries an occupied GEMU device's canvas and game audio over WebRTC. LiveKit forwards VP8 video and Opus audio; a small Node broker assigns membership from the Garry's Mod server. There is no camera, microphone, desktop capture, recording, ROM hosting, or save storage in this module. It is independent of the optional XInput DLL.

The default addon works without this service. Enable it on the game server after deployment. Each viewer switches to WebRTC only after video advances and the audio element starts playing. Failed/unsupported connections retain the existing JPEG/μ-law relay. Healthy WebRTC viewers are excluded from that relay; if all spectators use WebRTC, the owner stops uploading fallback frames. Viewer volume controls both paths.

## Layout and versions

- `broker.mjs`: HTTPS-proxied membership/token API, internal LiveKit admin client.
- `compose.yaml`, `Dockerfile`: separate media and broker containers; external `proxy_net` connects the HTTPS proxy.
- `livekit.example.yaml`, `.env.example`: configuration templates. Actual credentials/configuration are ignored by Git.
- `../../web/stream.js`, `viewer.html`: publisher/receiver adapter shared by every system.
- `../../lua/emu/{server,client}/*rtc.lua`: game authority and DHTML integration, included in the Workshop GMA.

Pinned dependencies: LiveKit server `v1.13.6`, browser client `2.22.3`, server SDK `2.19.0`, Node 22 container. `package-lock.json` locks npm dependencies. The browser UMD bundle is vendored as `web/livekit-client.umd.min.js`; its upstream license is `web/livekit-license.txt`. After changing the SDK version, run `npm ci --ignore-scripts`, copy `node_modules/livekit-client/dist/livekit-client.umd.js` to that web filename, and copy its `LICENSE` to `livekit-license.txt`.

## Deploy

1. Copy this directory to your host and create a Docker network named `proxy_net` if your proxy does not already use it. Attach the HTTPS reverse proxy to the same network. Use a dedicated LiveKit instance for GEMU: the broker removes unassigned rooms whose names begin `gemu_`.
2. Copy `.env.example` to `.env` and `livekit.example.yaml` to `livekit.yaml`. Generate two independent secrets of at least 32 random bytes. Set the **same LiveKit API key/secret** in `.env` and the YAML `keys` mapping. Set `LIVEKIT_PUBLIC_URL` to your public `wss://` signaling URL. The internal URL uses `http://gemu-livekit:7880`.
3. Create `servers.json`, for example `{"my-gmod-server":"YOUR_OTHER_RANDOM_SECRET"}`. Each game server gets a distinct key/value. Only the corresponding value goes into that game server's `garrysmod/data/emu/stream_key.txt`. Never put the LiveKit API secret in Lua, the web directory, a URL, or a GMA. The broker runs as UID 1000; make the mounted credential file readable by that UID, and protect configuration files from other host users.
4. Run `docker compose -p gemu-stream up -d --build`. Allow incoming **TCP 7881** and **UDP 7882** through host/provider firewalls and NAT. Only signaling/API requests use HTTPS port 443; opening 443 alone is insufficient. Ports 7880 and 8090 remain private to Docker.
5. Add these routes inside your existing HTTPS Caddy site, ahead of its normal frontend handler:

```caddyfile
handle_path /gemu-stream/* {
    reverse_proxy gemu-stream-broker:8090
}
handle_path /gemu-rtc/* {
    reverse_proxy gemu-livekit:7880
}
```

`LIVEKIT_PUBLIC_URL` is then `wss://YOUR_HOST/gemu-rtc`. Deploy the shared web frontend including `stream.js`, `viewer.html`, and the vendored SDK/license beneath the configured `emu_url`. Validate and reload your proxy normally. Preserve backups outside the public web root.

6. Set these game-server settings and reload the map/server so both realms load the new Lua:

```cfg
emu_url "https://YOUR_HOST/gemu/"
emu_sv_stream_service "https://YOUR_HOST/gemu-stream"
emu_sv_stream_enabled 1
```

Put these lines in `garrysmod/cfg/gemu.cfg`: GEMU reads that file after creating its convars, and `server.cfg` does not reach them on listen servers. Check with `emu_rtc_server_status` on the server.

Set `emu_sv_stream_enabled 0` to disable it at runtime. The JPEG/PCM relay remains available. Do not delete the old web assets during rollback until the game server has switched back. A browser page already loaded before deployment needs reopening.

## Sessions and authorization

`/gemu/` opens a library. `?system=gba&rom=hello_world.gba` starts that game locally. Reusing a game URL never synchronizes independent emulator instances. A spectator opens `viewer.html` and receives credentials from GMod, not from public URL parameters. An informational `#session=...` fragment identifies its assigned stream; knowing it does not authorize watching.

The game server generates a startup instance ID and a new media-session generation when the entity's owner or cartridge changes, or an inactive session restarts. The broker adds a namespace derived from the authenticated game server and instance. Two devices with the same system/ROM therefore have different rooms. Only the controlling client emulates; nearby spectators subscribe. GMod retains control input, player-two input, save handling, and handoff state.

Membership renews every five seconds; game-side proximity is checked every half-second. Browser configuration expires after twelve seconds without game-server renewal, and broker membership expires after fifteen. Join tokens initially allow no media; the broker grants publisher or subscriber permissions after admission. It reconciles every two seconds, demotes/removes departed participants, and rediscovers old rooms after restart. Revocation is bounded and asynchronous, not instantaneous. The game client also immediately closes receivers when it receives a departure/configuration change.

Limits are 16 occupied streamed devices per game server request, 32 viewers per device, and 128 tracked rooms per broker. Extra viewers/devices retain fallback. A publisher requests up to 30 fps, 1 Mbit/s VP8 and 64 kbit/s Opus; these are encoding targets, not guaranteed throughput. Each publisher uploads one stream; SFU outbound bandwidth scales with viewers. Watch CPU/network capacity before raising limits. The game server must reach the broker over HTTPS, and every WebRTC participant must reach the frontend and media service.

## Network limitations and checks

Direct UDP and ICE-TCP are configured by default. For viewers whose networks block both media ports, enable LiveKit's embedded TURN relay. Uncomment the `turn:` block in `livekit.yaml` with a domain matching your certificate, set `TURN_CERT_DIR` in `.env` to the directory holding that certificate and key, allow 3478/udp and 5349/tcp, and start with `docker compose -f compose.yaml -f compose.turn.yaml up -d`. TURN relays only to this LiveKit server. LiveKit reads the certificate at startup, so restart it after your proxy renews the certificate (for example, a weekly `docker compose restart livekit`). Ports 443/tcp and 443/udp are normally taken by the HTTPS/HTTP3 proxy, so TURN/TLS on 5349 still does not make this setup HTTPS-only compatible; networks that allow only 443 fall back to JPEG/μ-law. A paused publisher is reported healthy to viewers, so pausing does not drop them to fallback. See the official [deployment guide](https://docs.livekit.io/transport/self-hosting/deployment/) and [ports reference](https://docs.livekit.io/transport/self-hosting/ports-firewall/).

`GET /gemu-stream/healthz` checks the broker process, not end-to-end media. `POST /gemu-stream/sync` without a credential returns 401. Run `npm test` for the focused authentication, namespace, role, departure and lease contract. Use `emu_rtc_status` in GMod for per-device connection status, `emu_stream_status` for fallback, and `emu_stream_capabilities` with a game open to inspect CEF APIs. Diagnostics never print tokens.

Pre-release checks on a development deployment: a headless Chrome publisher/subscriber pair carried synthetic canvas frames and an audio track and detected publisher departure; with TURN enabled, an external TLS handshake on 5349 and a STUN binding on 3478 succeeded; and a two-client GMod test on the patched CEF connected publisher and viewer. A relayed media session, audible quality and constrained-network behavior remain unverified. Codec/API/autoplay failures should leave fallback active.

This module and its deployment secrets stay outside the GMA. Server owners operate their own service and frontend.

The optional `npm run smoke` check uses Playwright with installed Chrome in headless mode. Install Playwright separately or set `PLAYWRIGHT_MODULE` to its package path; set `GEMU_STREAM_KEY_FILE` to a local game-server credential file and `GEMU_SMOKE_ORIGIN` to your HTTPS origin (required). It expects the documented `/gemu`, `/gemu-stream` routes and the configured catalog, verifies the landing page and GBA filter, then publishes a synthetic canvas/tone to a temporary authorized room. It checks decoded frames, nonzero audio samples and publisher departure, and removes membership on exit. No ROMs are run by this check. Do not run it repeatedly as a general smoke suite.
