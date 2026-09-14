"""Generate tiny original diagnostic ROMs; no commercial game data is used.

These exercise boot/frame/state APIs, not CPU accuracy or game compatibility.
Output goes to the ignored, separately hosted web/roms directory.
"""
from pathlib import Path
import struct

def generate(destination):
    destination.mkdir(parents=True, exist_ok=True)
    for system in ('nes', 'gb', 'gbc', 'genesis'):
        (destination / system).mkdir(exist_ok=True)
    # NES NROM-128: disable interrupts, set backdrop palette, loop forever.
    prg = bytearray(16384)
    code = bytes.fromhex('78 D8 A2 FF 9A A9 00 8D 00 20 8D 01 20 A9 3F 8D 06 20 A9 00 8D 06 20 A9 21 8D 07 20 4C 1C 80')
    prg[:len(code)] = code
    struct.pack_into('<HHH', prg, 16378, 0x8000, 0x8000, 0x8000)
    (destination / 'nes/gemu_test.nes').write_bytes(b'NES\x1a' + bytes([1,1]) + bytes(10) + prg + bytes(8192))
    # GB/GBC: minimal no-MBC cartridge. Cores start after the boot ROM.
    for extension, color in [('gb',0), ('gbc',0x80)]:
        rom = bytearray(32768)
        rom[0x100:0x104] = bytes.fromhex('00 C3 50 01')
        rom[0x134:0x13d] = b'GEMU TEST'
        rom[0x143] = color
        rom[0x14a] = 1
        checksum = 0
        for b in rom[0x134:0x14d]:
            checksum = (checksum - b - 1) & 255
        rom[0x14d] = checksum
        rom[0x150:0x15e] = bytes.fromhex('F3 31 FE FF 3E E4 E0 47 3E 91 E0 40 18 FE')
        struct.pack_into('>H', rom, 0x14e, sum(rom) & 65535)
        (destination / extension / ('gemu_test.' + extension)).write_bytes(rom)
    # Genesis: valid ROM vectors/header, enable VDP display and set backdrop blue.
    rom = bytearray(65536)
    struct.pack_into('>II', rom, 0, 0x00fffe00, 0x200)
    rom[0x100:0x110] = b'SEGA MEGA DRIVE '
    rom[0x120:0x129] = b'GEMU TEST'
    rom[0x150:0x159] = b'GEMU TEST'
    rom[0x190:0x1a0] = b'J               '
    struct.pack_into('>IIII', rom, 0x1a0, 0, len(rom)-1, 0xff0000, 0xffffff)
    rom[0x1f0:0x200] = b'JUE             '
    code = bytes.fromhex('46 FC 27 00 33 FC 81 44 00 C0 00 04 23 FC C0 00 00 00 00 C0 00 04 33 FC 0E 00 00 C0 00 00 60 FE')
    rom[0x200:0x200+len(code)] = code
    struct.pack_into('>H', rom, 0x18e, sum(struct.unpack('>32512H', rom[0x200:])) & 65535)
    (destination / 'genesis/gemu_test.md').write_bytes(rom)

if __name__ == '__main__':
    generate(Path(__file__).resolve().parents[1] / 'web/roms')
    print('Generated NES, GB, GBC and Genesis diagnostic ROMs in web/roms/.')
