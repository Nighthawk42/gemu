"""Build and inspect the distributable addon without publishing it."""
import argparse
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
__import__('sys').path.insert(0, str(ROOT / 'tools'))
from gmod_paths import find_gmod  # noqa: E402

def entries(path):
    with path.open('rb') as f:
        def cstring():
            result = bytearray()
            while True:
                char = f.read(1)
                if not char:
                    raise ValueError('Truncated GMA')
                if char == b'\0':
                    return result.decode('utf-8')
                result.extend(char)
        if f.read(4) != b'GMAD' or f.read(1) != b'\x03':
            raise ValueError('Unsupported GMA header')
        f.read(16)  # Steam ID and timestamp
        while cstring():
            pass  # Required content
        cstring(); cstring(); cstring()  # Name, description, author
        f.read(4)
        paths = []
        while struct.unpack('<I', f.read(4))[0]:
            paths.append(cstring())
            f.read(12)  # Size and CRC
        return paths

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    game = find_gmod()
    parser.add_argument('--gmad', type=Path, default=game / 'bin' / 'gmad.exe' if game else None, required=game is None,
                        help="gmad.exe (default: detected Garry's Mod install, or GMOD_ROOT)")
    parser.add_argument('--out', type=Path, default=ROOT / 'dist/gemu.gma')
    args = parser.parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(args.gmad), 'create', '-folder', str(ROOT), '-out', str(args.out.resolve())],
                            capture_output=True, text=True)
    log = args.out.with_suffix('.build.log')
    log.write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise SystemExit(f'GMA build failed. See {log}')
    paths = entries(args.out)
    unexpected = [p for p in paths if p.split('/')[0] not in {'lua', 'models', 'materials'}]
    if unexpected:
        raise SystemExit(f'Unexpected packaged files: {unexpected}')
    required = ['lua/autorun/emu_init.lua', 'lua/emu/license.lua',
                'lua/weapons/weapon_emu_gba/shared.lua', 'lua/entities/emu_console/init.lua',
                'lua/emu/client/cl_emu_stream.lua']
    required += ['lua/emu/systems/' + id + '.lua' for id in ('snes','gba','nes','gb','gbc','genesis')]
    required += ['lua/weapons/weapon_emu_base/shared.lua', 'materials/gemu/blank_label.vtf',
                 'materials/gemu/blank_gray.vtf', 'materials/gemu/blank_dark.vtf']
    required += ['materials/gemu/icons/' + id + '_console.png' for id in ('snes','nes','genesis','gba','gb','gbc','crt')]
    required += ['materials/gemu/icons/' + id + '_cartridge.png' for id in ('snes','nes','genesis','gba','gb','gbc')]
    required += ['lua/emu/client/cl_emu_power.lua', 'lua/emu/client/cl_emu_gamepad.lua']
    required += ['lua/emu/client/cl_emu_saves.lua', 'lua/emu/client/cl_emu_controls.lua',
                 'lua/emu/client/cl_emu_rtc.lua', 'lua/emu/server/sv_emu_rtc.lua']
    required += ['lua/emu/server/sv_emu_stream_demand.lua', 'lua/emu/server/sv_emu_ownership.lua']
    required += ['materials/gemu/power/' + id + suffix + '.vtf' for id in ('snes','nes','genesis','gba','gb','gbc') for suffix in ('_on','_mask')]
    if any(p not in paths for p in required):
        raise SystemExit('Required addon files missing from GMA')
    print(f'Verified {len(paths)} addon files, {args.out.stat().st_size:,} bytes: {args.out}')
    print('Only lua/, models/, and materials/ packaged. Frontend and ROMs remain separately hosted.')

if __name__ == '__main__':
    main()
