"""Собрать index.xml ReaPack из манифеста установщика.

Версия и список файлов берутся из ReaStems/manifest.json, текст изменений —
из раздела «Что изменилось» в RELEASE_NOTES.md. Запускать после
`tools/prepare_payload.py`:

    python tools/make_index.py
"""
import json
from datetime import datetime, timezone
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / "ReaStems"
REPOSITORY = "Aiwist/ai-reastems"
CATEGORY = "ReaStems"
PACKAGE = "Aiwist_ReaStems.lua"


def changes():
    notes = (ROOT / "RELEASE_NOTES.md").read_text(encoding="utf-8")
    section = re.search(r"^## Что изменилось\s*$(.*?)(?=^## |\Z)", notes, re.MULTILINE | re.DOTALL)
    text = section[1].strip() if section else ""
    return re.sub(r"\s+", " ", text).strip()


def build():
    manifest = json.loads((PAYLOAD / "manifest.json").read_text(encoding="utf-8"))
    version = manifest["version"]
    base = f"https://raw.githubusercontent.com/{REPOSITORY}/v{version}/ReaStems"

    root = ET.Element("index", {"version": "1", "name": "Aiwist"})
    category = ET.SubElement(root, "category", {"name": CATEGORY})
    package = ET.SubElement(category, "reapack",
                            {"name": PACKAGE, "type": "script", "desc": "Ai ReaStems"})
    metadata = ET.SubElement(package, "metadata")
    ET.SubElement(metadata, "description").text = (
        "Ai ReaStems: split audio into stems inside REAPER. Windows x64; requires "
        "ReaImGui (cfillion). Local stems.cpp engine with Vulkan and CPU builds. "
        "Models download separately in Settings.")
    ET.SubElement(metadata, "link", {"rel": "website",
                                     "href": f"https://github.com/{REPOSITORY}"}).text = "GitHub"
    ET.SubElement(metadata, "link", {"rel": "website",
                                     "href": "https://boosty.to/aiwist"}).text = "Boosty"
    for shot in ("main-window", "settings"):
        ET.SubElement(metadata, "link", {"rel": "screenshot"}).text = (
            f"https://raw.githubusercontent.com/{REPOSITORY}/main/Media/screenshots/{shot}.png")

    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    release = ET.SubElement(package, "version",
                            {"name": version, "author": "Aiwist", "time": stamp})
    ET.SubElement(release, "changelog").text = changes() or f"Ai ReaStems {version}"

    files = dict(manifest["files"])
    files["manifest.json"] = None  # манифест ставится вместе со скриптом
    for name in sorted(files):
        attrs = {"platform": "win64", "file": name}
        if name == PACKAGE:
            attrs["main"] = "main"
        ET.SubElement(release, "source", attrs).text = f"{base}/{name}"

    ET.indent(root, space="  ")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n", version, len(files)


if __name__ == "__main__":
    data, version, count = build()
    (ROOT / "index.xml").write_bytes(data)
    print(f"Ai ReaStems {version}: {count} файлов в index.xml")
