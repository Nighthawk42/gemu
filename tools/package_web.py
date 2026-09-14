"""Create a web release containing frontend assets and ONLY catalog-listed ROMs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import tarfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / '.work/gemu-web-release.tar.gz')
    args = parser.parse_args()
    web = ROOT / 'web'
    rows = json.loads((web / 'roms.json').read_text())['roms']
    paths = [p for p in web.iterdir() if p.is_file() and p.suffix in {'.html', '.css', '.js', '.json', '.txt'}]
    paths += [p for p in (web / 'cores').rglob('*') if p.is_file()]
    for row in rows:
        assert row['system'] in {'snes', 'nes', 'gba', 'gb', 'gbc', 'genesis'}
        assert re.fullmatch(r'[a-z0-9_]+\.[a-z0-9]+', row['filename'])
        path = web / 'roms' / row['system'] / row['filename']
        data = path.read_bytes()
        assert len(data) == row['size'] and hashlib.sha256(data).hexdigest() == row['sha256'], path
        paths.append(path)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.out, 'w:gz') as archive:
        for path in paths:
            archive.add(path, arcname=path.relative_to(web).as_posix())
    print(f'Packaged frontend and {len(rows)} catalog-selected ROMs: {args.out}')

if __name__ == '__main__':
    main()
