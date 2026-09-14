"""Locate the local Garry's Mod install without hard-coding machine paths.

Set GMOD_ROOT to the GarrysMod folder (the one containing bin/ and garrysmod/)
to override detection. Otherwise Steam's library list is searched.
"""
import os
import re
from pathlib import Path


def find_gmod():
    """Return the GarrysMod install folder, or None when it cannot be found."""
    override = os.environ.get('GMOD_ROOT')
    if override:
        return Path(override)
    steam_roots = []
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam') as key:
            steam_roots.append(Path(winreg.QueryValueEx(key, 'SteamPath')[0]))
    except (ImportError, OSError):
        pass
    steam_roots += [Path.home() / '.steam' / 'steam', Path.home() / '.local' / 'share' / 'Steam']
    for steam in steam_roots:
        libraries = [steam]
        folders = steam / 'steamapps' / 'libraryfolders.vdf'
        if folders.is_file():
            text = folders.read_text(encoding='utf-8', errors='ignore')
            libraries += [Path(p.replace('\\\\', '\\')) for p in re.findall(r'"path"\s+"([^"]+)"', text)]
        for library in libraries:
            game = library / 'steamapps' / 'common' / 'GarrysMod'
            if (game / 'garrysmod').is_dir():
                return game
    return None
