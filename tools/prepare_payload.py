"""Build the checked file inventory consumed by Ai ReaStems and its installer."""

from hashlib import file_digest
import json
from pathlib import Path
import re


payload = Path(__file__).resolve().parents[1] / "ReaStems"
script = (payload / "Aiwist_ReaStems.lua").read_text(encoding="utf-8")
version = re.search(r"^-- @version (\d+\.\d+\.\d+)$", script, re.MULTILINE)[1]
manifest_file = payload / "manifest.json"
files = {}

for path in sorted(payload.rglob("*")):
    if not path.is_file() or path == manifest_file:
        continue
    with path.open("rb") as stream:
        files[path.relative_to(payload).as_posix()] = file_digest(stream, "sha256").hexdigest()

manifest = {"schema": 1, "app": "Ai ReaStems", "version": version, "files": files}
manifest_file.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
