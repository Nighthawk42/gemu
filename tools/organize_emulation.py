"""Create a normalized, non-destructive GEMU ROM view inside a local ROM library.

The source library is left untouched. Files on the same NTFS volume are
hard-linked into GEMU/roms/<system>, so the organized view does not duplicate
ROM data. A manifest records the original path and SHA-256 for each entry.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
from pathlib import Path

DEST: Path
SOURCES: dict = {}


def configure(root: Path) -> None:
    """Point the organizer at a library laid out as <maker>/<system>/Roms."""
    global DEST, SOURCES
    DEST = root / "GEMU" / "roms"
    SOURCES = {
        "nes": [(root / "Nintendo" / "NES" / "roms", {".nes"})],
        "snes": [(root / "Nintendo" / "Super Nintendo", {".smc", ".sfc"})],
        "gba": [(root / "Nintendo" / "GBA" / "Roms", {".gba"})],
        "gb": [(root / "Nintendo" / "GBA" / "Roms", {".gb"})],
        "gbc": [(root / "Nintendo" / "GBA" / "Roms", {".gbc"})],
        "genesis": [(root / "SEGA" / "Genesis" / "Roms", {".md", ".bin", ".gen", ".smd"})],
    }


def normalized_stem(name: str) -> str:
    value = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
    value = re.sub(r"[^a-z0-9]+", "_", value).strip("_")
    return (value or "game")[:150]


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def entries():
    for system, roots in SOURCES.items():
        for root, extensions in roots:
            if not root.is_dir():
                continue
            for path in sorted(root.rglob("*")):
                if path.is_file() and path.suffix.lower() in extensions:
                    yield system, path


def organize(dry_run: bool) -> dict:
    manifest = []
    planned = {}
    for system, source in entries():
        file_hash = digest(source)
        stem = normalized_stem(source.stem)
        suffix = source.suffix.lower()
        filename = stem + suffix
        target_dir = DEST / system
        target = target_dir / filename
        if target in planned and planned[target]["sha256"] != file_hash:
            target = target_dir / (stem + "__" + file_hash[:8] + suffix)
        while target in planned and planned[target]["sha256"] != file_hash:
            target = target.with_name(target.stem + "_" + file_hash[:4] + target.suffix)
        if target in planned:
            continue
        planned[target] = {"sha256": file_hash}
        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                if digest(target) != file_hash:
                    raise RuntimeError(f"refusing to overwrite different file: {target}")
            else:
                target.hardlink_to(source)
        manifest.append({
            "system": system,
            "filename": target.name,
            "source": str(source),
            "size": source.stat().st_size,
            "sha256": file_hash,
        })
    if not dry_run:
        DEST.mkdir(parents=True, exist_ok=True)
        (DEST.parent / "manifest.json").write_text(
            json.dumps({"version": 1, "roms": manifest}, indent=2) + "\n", encoding="utf-8"
        )
        (DEST.parent / "README.txt").write_text(
            "GEMU normalized ROM view. Files are hardlinks; the original library is unchanged.\n"
            "Folders are lowercase system IDs and filenames use lowercase underscores.\n",
            encoding="utf-8",
        )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path, required=True, help="root of your local ROM library")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    configure(args.library)
    rows = organize(args.dry_run)
    by_system = {}
    for row in rows:
        by_system[row["system"]] = by_system.get(row["system"], 0) + 1
    print(json.dumps({"dry_run": args.dry_run, "total": len(rows), "systems": by_system}, indent=2))


if __name__ == "__main__":
    main()
