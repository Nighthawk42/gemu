# Emulatrix Game Boy Advance core

Source: `Emulatrix_GameBoyAdvance.js` from [lrusso/Emulatrix](https://github.com/lrusso/Emulatrix), commit `d00f12a7d60893ce1c4c2f6526bad9303927c456`.

The bundled file has one integration hook: after the embedded libretro module initializes, it is assigned to `window.GBA_MODULE`. `web/app.js` uses that reference for in-page save/load and clean teardown. Emulator behavior and ROM loading otherwise remain upstream Emulatrix behavior.

See `LICENSE.frontend.txt` for the upstream MIT license.
