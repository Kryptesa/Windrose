"""Package only our Lua sources and user-facing installation files."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[3]
VERSION = (ROOT / "mods/VerdantStamina/VERSION").read_text().strip()

def build():
    out = ROOT / "dist"
    out.mkdir(exist_ok=True)
    target = out / f"VerdantStamina-{VERSION}.zip"
    files = sorted(p for p in (ROOT / "mods/VerdantStamina").rglob("*") if p.suffix in (".lua", ".png") and p.relative_to(ROOT / "mods/VerdantStamina").parts[0] in ("Scripts", "Assets"))
    manifest = {str(p.relative_to(ROOT / "mods")).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        for path in files:
            z.write(path, "ue4ss/Mods/" + path.relative_to(ROOT / "mods").as_posix())
        z.writestr("ue4ss/Mods/VerdantStamina/enabled.txt", "")
        z.write(ROOT / "mods/VerdantStamina/README.md", "README.md")
        z.writestr("source-manifest.json", json.dumps(manifest, indent=2) + "\n")
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
        assert len(z.namelist()) == len(files) + 3
        assert all("extracted" not in n and not n.endswith((".dll", ".exe", ".uasset")) for n in z.namelist())
    print(target)
    print("SHA256", hashlib.sha256(target.read_bytes()).hexdigest())

if __name__ == "__main__":
    build()
