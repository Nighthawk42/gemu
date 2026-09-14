"""Run Lua contracts and real Emulatrix core smoke tests without controlling GMod."""
from pathlib import Path
import subprocess
from make_test_roms import generate

ROOT = Path(__file__).resolve().parents[1]
generate(ROOT / 'web/roms')

def run(args):
    print(' '.join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)

paths = sorted((ROOT / 'lua').rglob('*.lua'))
source = '\n'.join('assert(loadfile("' + path.as_posix() + '"))' for path in paths)
subprocess.run(['luajit', '-'], input=source, text=True, cwd=ROOT, check=True)
print(f'Lua syntax: {len(paths)} files passed.')
for name in ['regression', 'input', 'controls', 'gamepad', 'focus_server', 'session', 'gba', 'stream', 'audio_stream', 'handoff', 'player2', 'duplication', 'systems', 'spawn', 'power', 'ownership', 'save_files', 'management', 'convars', 'rtc_client']:
    run(['luajit', 'tests/' + name + '.lua'])
run(['node', 'tests/saves.cjs'])
run(['node', 'tests/audio_capture.cjs'])
run(['node', 'tests/catalog.cjs'])
for name, rom in [('snes','super_mario_world.smc'),('gba','hello_world.gba'),
                  ('nes','gemu_test.nes'),('gb','gemu_test.gb'),('gbc','gemu_test.gbc'),('genesis','gemu_test.md')]:
    if not (ROOT / 'web/roms' / name / rom).is_file():
        print('SKIP ' + name + ': supply local ROM ' + rom)
        continue
    run(['node', 'tests/web_smoke.cjs', name])
