# Acknowledgements & Third-Party Credits

`gmod-emu` brings retro console emulation into Garry's Mod by bridging embedded Chromium (CEF), dynamic Source engine render targets, and open-source emulation cores. We gratefully acknowledge the creators and contributors of the following projects, models, and technologies:

---

### Emulation & Web Technology

- **[Emulatrix](https://github.com/lrusso/Emulatrix) by Leonardo Javier Russo**:
  - Open-source, pure-JavaScript multi-system browser emulator framework.
  - Supplies the SNES, NES, Genesis, Game Boy/Color and Game Boy Advance browser cores used by the shared CEF frontend adapter.
  - Licensed under the [MIT License](https://github.com/lrusso/Emulatrix/blob/master/LICENSE).

---

### 3D Models & Materials

- **SNES Console, Cartridge & Controller**:
  - Models: `models/unconid/snes/snes.mdl`, `models/unconid/snes/snes_cartridge.mdl`, `models/unconid/snes/snes_controller.mdl`.
  - Created by **unconid**. Includes 21 distinct game label skins and interactive bodygroups.

- **Game Boy Advance & Cartridges**:
  - Models: `models/unconid/gameboy/gameboy_advance.mdl` and `models/unconid/gameboy/gameboy_advance_cartridge.mdl`.
  - Created by **unconid** and restored from the original `mgba-gmod` addon assets.

- **Philips Cineos CRT Television**:
  - Model: `models/ivip/cineos/philipscineos.mdl`.
  - Created by **ivip**. Features multiple skin families, static snow noise shader, and widescreen CRT bezel.

---

### Platform & Engine

- **Facepunch Studios & Valve Corporation**:
  - Garry's Mod and the Source Engine.

The added NES, Genesis and Game Boy/Color models use the existing unconid asset collection. Core provenance and integration changes are recorded in `web/cores/*/README.md`; GB/Color uses the Emulatrix Gambatte build.

## Optional streaming

LiveKit server, browser SDK and server SDK provide WebRTC media forwarding and client transport (Apache-2.0). Pinned versions and deployment details are in server/stream/README.md; the redistributed browser bundle license is web/livekit-license.txt.
