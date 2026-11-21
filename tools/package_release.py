"""Package and verify a Windows installer using the Ai ReaStems install manifest."""

import argparse
from hashlib import file_digest
import json
import os
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


def publish(staged, target):
    if os.name == "nt":
        staged.rename(target)  # Windows rename fails if the target exists.
    else:
        os.link(staged, target)


def package(output):
    payload = ROOT / "ReaStems"
    manifest_path = payload / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    version = manifest["version"]
    installer = (ROOT / "Install.ps1").read_text(encoding="utf-8-sig")
    script = (payload / "Aiwist_ReaStems.lua").read_text(encoding="utf-8")
    if (f"$script:SetupVersion='{version}'" not in installer
            or script.splitlines()[0] != f"-- @version {version}"):
        raise ValueError("Installer, manifest and ReaScript versions differ")

    files = {"ReaStems/manifest.json": manifest_path}
    for name, checksum in manifest["files"].items():
        if PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts or "\\" in name:
            raise ValueError(f"Invalid manifest path: {name}")
        path = payload / name
        if digest(path) != checksum:
            raise ValueError(f"Manifest hash mismatch: {name}")
        files[f"ReaStems/{name}"] = path
    for name in ("Установить.bat", "Install.ps1", "reaimgui_install.ps1", "reaper_actions.ps1",
                 "README.md", "README.ru.md", "CHANGELOG.md", "RELEASE_NOTES.md", "LICENSE", "NOTICE.txt"):
        files[name] = ROOT / name

    archive = output / f"Ai_ReaStems_Setup_{version}_Windows.zip"
    checksum_file = archive.with_suffix(".zip.sha256")
    if archive.exists() or checksum_file.exists():
        raise FileExistsError("Release files must never be overwritten")
    with TemporaryDirectory(prefix=".ai-stems-", dir=output) as work:
        staged = Path(work) / archive.name
        with ZipFile(staged, "x", compression=ZIP_DEFLATED, compresslevel=9) as zipped:
            for name, path in sorted(files.items()):
                zipped.write(path, name)
        with ZipFile(staged) as zipped:
            if sorted(zipped.namelist()) != sorted(files):
                raise ValueError("Unexpected ZIP inventory")
            for name, path in files.items():
                with zipped.open(name) as stream:
                    if file_digest(stream, "sha256").hexdigest() != digest(path):
                        raise ValueError(f"ZIP hash mismatch: {name}")
        checksum = digest(staged)
        staged_checksum = Path(work) / checksum_file.name
        staged_checksum.write_text(f"{checksum}  {archive.name}\n", encoding="utf-8")
        publish(staged, archive)
        try:
            publish(staged_checksum, checksum_file)
        except OSError:
            archive.unlink()
            raise
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    print(package(args.output_dir.resolve(strict=True)))
