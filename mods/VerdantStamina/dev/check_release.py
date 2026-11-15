"""Validate a tagged source tree and the exact installable archive before upload."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "mods/VerdantStamina"


def check(tag):
    version = (MOD / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        raise ValueError("Invalid VERSION")
    if tag != f"VerdantStamina/v{version}":
        raise ValueError("Tag must match VerdantStamina/VERSION")
    notes = (MOD / "release_notes.md").read_text(encoding="utf-8")
    if notes.splitlines()[0] != f"# Verdant Stamina {version}":
        raise ValueError("Release notes heading does not match VERSION")
    if f"## {version} " not in (MOD / "CHANGELOG.md").read_text(encoding="utf-8"):
        raise ValueError("Missing changelog entry")
    if f"`{version}`" not in (MOD / "README.md").read_text(encoding="utf-8"):
        raise ValueError("README version does not match")
    if f'log("{version} ready;' not in (MOD / "Scripts/main.lua").read_text():
        raise ValueError("Runtime banner does not match VERSION")
    sources = {p.relative_to(MOD).as_posix(): p for folder in ("Scripts", "Assets")
               for p in (MOD / folder).rglob("*") if p.suffix in (".lua", ".png")}
    expected = {"ue4ss/Mods/VerdantStamina/" + n for n in sources}
    expected |= {"README.md", "LICENSE", "release_notes.md", "source-manifest.json",
                 "ue4ss/Mods/VerdantStamina/enabled.txt"}
    with zipfile.ZipFile(ROOT / "dist" / f"VerdantStamina-{version}.zip") as archive:
        names = archive.namelist()
        if archive.testzip() or set(names) != expected or len(names) != len(expected):
            raise ValueError("Archive contains missing, extra, duplicate or damaged entries")
        manifest = {}
        for name, path in sources.items():
            payload = path.read_bytes()
            if archive.read("ue4ss/Mods/VerdantStamina/" + name) != payload:
                raise ValueError(f"Archive source mismatch: {name}")
            manifest["VerdantStamina/" + name] = hashlib.sha256(payload).hexdigest()
        if json.loads(archive.read("source-manifest.json")) != manifest:
            raise ValueError("Source manifest mismatch")
        for name in ("README.md", "LICENSE", "release_notes.md"):
            if archive.read(name) != (MOD / name).read_bytes():
                raise ValueError(f"Archive documentation mismatch: {name}")
        if archive.read("ue4ss/Mods/VerdantStamina/enabled.txt") != b"":
            raise ValueError("Unexpected enabled.txt contents")
    print(f"PASS: {tag}; metadata, archive allowlist and hashes verified")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    check(parser.parse_args().tag)
