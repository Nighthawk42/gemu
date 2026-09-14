"""Install a validated runtime-only addon folder (or opt-in GMA); preserve previous installations."""
from pathlib import Path
import argparse, datetime, hashlib, json, os, shutil, subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from gmod_paths import find_gmod

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    game=find_gmod()
    parser.add_argument('--game-root',type=Path,default=game/'garrysmod' if game else None,required=game is None,
        help="garrysmod folder (default: detected Garry's Mod install, or GMOD_ROOT)")
    parser.add_argument('--format',choices=['folder','gma'],default='folder')
    args=parser.parse_args();game=args.game_root.resolve();addons=game/'addons'
    assert addons.is_dir() and (game/'gameinfo.txt').is_file(), 'Not a GarrysMod game folder'
    subprocess.run([sys.executable,str(ROOT/'tools/build_gma.py')],check=True)
    package=ROOT/'dist/gemu.gma'
    backup=(game/'gemu-backups'/datetime.datetime.now().strftime('%Y%m%d%H%M%S')).resolve()
    assert backup.is_relative_to(game/'gemu-backups');backup.mkdir(parents=True)
    pending=backup/'new.gma';shutil.copy2(package,pending)
    assert hashlib.sha256(pending.read_bytes()).digest()==hashlib.sha256(package.read_bytes()).digest()
    destination=addons/'gemu.gma'
    if args.format=='folder':
        from build_gma import entries
        stage=backup/'new-addon'
        result=subprocess.run([str(game.parent/'bin/gmad.exe'),'extract','-file',str(pending),'-out',str(stage)],capture_output=True,text=True)
        (backup/'extract.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode:raise RuntimeError('GMA extraction failed; see '+str(backup/'extract.log'))
        expected=set(entries(package))
        actual={p.relative_to(stage).as_posix() for p in stage.rglob('*') if p.is_file()}
        # gmad may also write archive metadata; it is safe to retain addon.json.
        assert actual-{'addon.json'}==expected,'Extracted addon file list differs from package'
        for name in expected:
            assert hashlib.sha256((stage/name).read_bytes()).digest()==hashlib.sha256((ROOT/name).read_bytes()).digest(),name
        pending=stage
        destination=addons/'gemu'
    moved=[]
    try:
        for name in ['gmod-emu','gemu','gmod-emu.gma','gemu.gma']:
            source=addons/name;target=backup/name
            # Check lexical paths without following a junction into the checkout.
            assert source.parent.resolve()==addons.resolve() and target.parent.resolve()==backup
            if os.path.lexists(source):
                source.rename(target);moved.append((source,target))
        pending.rename(destination)
    except Exception:
        for source,target in reversed(moved):target.rename(source)
        raise
    print('Installed:',destination)
    print('Previous installation preserved outside addons:',backup)
    print('Native DLLs remain in lua/bin; frontend and ROMs remain separately hosted. Restart GMod to remount.')

if __name__=='__main__':main()
