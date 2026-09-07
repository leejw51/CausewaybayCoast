"""Cache the official macOS template matching this project's pinned Godot release."""

import hashlib
from pathlib import Path
import shutil
import tempfile
import urllib.request
import zipfile

VERSION = "4.7.2-stable"
SHA256 = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}/Godot_v{VERSION}_export_templates.tpz"
DEST = Path(__file__).resolve().parents[1] / "build/templates/macos.zip"


def main():
    DEST.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading official Godot {VERSION} templates (about 1.2 GB)")
    with tempfile.TemporaryFile() as archive:
        digest = hashlib.sha256()
        with urllib.request.urlopen(URL, timeout=180) as response:
            while chunk := response.read(1024 * 1024):
                archive.write(chunk)
                digest.update(chunk)
        if digest.hexdigest() != SHA256:
            raise RuntimeError("Export template checksum mismatch")
        archive.seek(0)
        with zipfile.ZipFile(archive) as bundle:
            with (
                bundle.open("templates/macos.zip") as source,
                DEST.with_suffix(".tmp").open("wb") as target,
            ):
                shutil.copyfileobj(source, target)
        DEST.with_suffix(".tmp").replace(DEST)
    print(f"Cached {DEST.name}")


if __name__ == "__main__":
    main()
