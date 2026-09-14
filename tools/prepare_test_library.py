"""Replace local web ROM staging with the explicit testing selection."""
from pathlib import Path
import argparse, datetime, hashlib, html, json, shutil, re
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True, help='root of your local ROM library')
    args = parser.parse_args()
    selected = json.loads((ROOT/'tools/test_titles.json').read_text())
    sources = []
    for system, title, name, relative in selected:
        source = (args.library/relative).resolve()
        assert source.is_relative_to(args.library.resolve()) and source.is_file(), source
        assert system in {'snes','nes','genesis','gba','gbc','gb'} and re.fullmatch(r'[a-z0-9_]+\.[a-z0-9]+',name)
        sources.append((system,title,name,source))
    backup = (ROOT/'.work'/('rom-selection-'+datetime.datetime.now().strftime('%Y%m%d%H%M%S'))).resolve()
    backup.mkdir(parents=True)
    stage=backup/'new-roms';stage.mkdir()
    rows=[]
    for system,title,name,source in sources:
        target=stage/system/name;target.parent.mkdir(exist_ok=True)
        shutil.copy2(source,target)
        data=target.read_bytes()
        rows.append(dict(system=system,title=title,filename=name,size=len(data),sha256=hashlib.sha256(data).hexdigest()))
    live=(ROOT/'web/roms').resolve()
    assert live.is_relative_to((ROOT/'web').resolve()) and backup.is_relative_to((ROOT/'.work').resolve())
    if live.exists(): live.rename(backup/'old-roms')
    stage.rename(live)
    web=ROOT/'web'
    (web/'roms.json').write_text(json.dumps({'roms':rows},indent=2)+'\n',encoding='utf-8')
    listing=''.join('<tr><td>'+r['system'].upper()+'</td><td>'+html.escape(r['title'])+'</td><td><a href="roms/'+r['system']+'/'+r['filename']+'">'+r['filename']+'</a></td></tr>' for r in rows)
    (web/'library.html').write_text('<!doctype html><meta charset="utf-8"><title>GEMU Test Library</title><style>body{font:16px system-ui;max-width:1100px;margin:40px auto}td,th{padding:8px;text-align:left}</style><h1>GEMU Test Library</h1><p>Temporary testing: '+str(len(rows))+' selected titles. Server owners supply their own deployment and ROMs.</p><p><a href="./">Play a game</a></p><table><tr><th>System</th><th>Title</th><th>File</th></tr>'+listing+'</table>\n',encoding='utf-8')
    print('Staged',len(rows),'titles; previous local staging archived outside web/. Original library unchanged.')

if __name__=='__main__': main()
