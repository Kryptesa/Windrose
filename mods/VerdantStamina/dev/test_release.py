"""Release checks must reject mismatched tags and unexpected archive payloads."""
import shutil
import tempfile
import unittest
from pathlib import Path
import zipfile

import check_release


class ReleaseChecks(unittest.TestCase):
    def test_current_package(self):
        version = (check_release.MOD / "VERSION").read_text().strip()
        check_release.check(f"VerdantStamina/v{version}")

    def test_wrong_tag(self):
        with self.assertRaisesRegex(ValueError, "Tag must match"):
            check_release.check("AnotherMod/v0.1.0")

    def test_extra_payload_is_rejected(self):
        original_root, original_mod = check_release.ROOT, check_release.MOD
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(original_mod, root / "mods/VerdantStamina")
            shutil.copytree(original_root / "dist", root / "dist")
            check_release.ROOT, check_release.MOD = root, root / "mods/VerdantStamina"
            try:
                version = (check_release.MOD / "VERSION").read_text().strip()
                with zipfile.ZipFile(root / "dist" / f"VerdantStamina-{version}.zip", "a") as archive:
                    archive.writestr("ue4ss/Mods/VerdantStamina/unexpected.dll", b"unwanted")
                with self.assertRaisesRegex(ValueError, "Archive contains"):
                    check_release.check(f"VerdantStamina/v{version}")
            finally:
                check_release.ROOT, check_release.MOD = original_root, original_mod


if __name__ == "__main__":
    unittest.main(verbosity=2)
