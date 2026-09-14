# Emulatrix Nintendo

Vendored from lrusso/Emulatrix commit d00f12a7d60893ce1c4c2f6526bad9303927c456.
Integration patch: expose the initialized module for shared save/load.

Startup exceptions propagate to the shared UI instead of reloading the page. NES asynchronous errors use cbError.
