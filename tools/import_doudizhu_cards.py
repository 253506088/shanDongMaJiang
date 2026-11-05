"""Import the traditional SVG-cards deck from a pinned LGPL-2.1 upstream.

Development: python tools/import_doudizhu_cards.py --download (needs Pillow)
Offline verification: python tools/import_doudizhu_cards.py --verify
Downloads stay in memory. Runtime PNGs, exact SVG source and license/attribution
are retained in assets/. Upstream letters are rasterized, not system fonts.
"""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/doudizhu/cards"
LICENSES = ROOT / "assets/licenses"
MANIFEST = LICENSES / "doudizhu-cards-manifest.json"
REPOSITORY = "https://github.com/htdebeer/SVG-cards"
COMMIT = "6d88bf9c594997b82bc5668ab0877a4e9b717665"
RAW_ROOT = f"https://raw.githubusercontent.com/htdebeer/SVG-cards/{COMMIT}/"
PAPER_RGB = (246, 241, 231)

def catalog() -> list[tuple[str, str]]:
    suits = ["spade", "heart", "club", "diamond"]
    result = []
    for card_id in range(52):
        rank = 3 + card_id // 4
        rank_name = {11: "jack", 12: "queen", 13: "king", 14: "1", 15: "2"}.get(rank, str(rank))
        result.append((f"{card_id:02d}", f"png/2x/{suits[card_id % 4]}_{rank_name}.png"))
    return result + [("52", "png/2x/joker_black.png"), ("53", "png/2x/joker_red.png"), ("back", "png/2x/back-teal.png")]

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def fetch(path: str) -> bytes:
    request = urllib.request.Request(RAW_ROOT + path, headers={"User-Agent": "QingyuMahjong-card-art-import"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()

def download() -> None:
    from PIL import Image, ImageChops, ImageOps
    OUTPUT.mkdir(parents=True, exist_ok=True)
    LICENSES.mkdir(parents=True, exist_ok=True)
    source_files = {}
    for key, upstream, name in [
        ("source_svg", "svg-cards.svg", "doudizhu-cards-source.svg.txt"),
        ("license_file", "LICENSE", "doudizhu-cards-LGPL-2.1.txt"),
        ("upstream_readme", "README.md", "doudizhu-cards-upstream-README.md"),
    ]:
        source = fetch(upstream)
        target = LICENSES / name
        target.write_bytes(source)
        source_files[key] = {"url": RAW_ROOT + upstream, "path": target.relative_to(ROOT).as_posix(), "sha256": digest(source)}
    # The .txt suffix keeps the exact, editable SVG library distributable
    # without asking Godot to import it as another unused atlas texture.
    def make_card(entry: tuple[str, str]) -> dict:
        key, upstream_path = entry
        source = fetch(upstream_path)
        with Image.open(io.BytesIO(source)) as opened:
            card = opened.convert("RGBA")
        alpha = card.getchannel("A")
        rgb = card.convert("RGB")
        if key == "52": rgb = ImageOps.grayscale(rgb).convert("RGB")
        rgb = ImageChops.multiply(rgb, Image.new("RGB", card.size, PAPER_RGB))
        card = rgb.convert("RGBA"); card.putalpha(alpha)
        output = io.BytesIO(); card.save(output, format="PNG", optimize=False, compress_level=9)
        rendered = output.getvalue()
        target = OUTPUT / (key + ".png"); target.write_bytes(rendered)
        print("Imported", key, "from", upstream_path, flush=True)
        return {
            "key": key, "card_id": int(key) if key != "back" else None,
            "source_url": RAW_ROOT + upstream_path, "source_sha256": digest(source),
            "path": target.relative_to(ROOT).as_posix(), "sha256": digest(rendered), "bytes": len(rendered),
            "width": card.width, "height": card.height,
            "modifications": ["RGB multiplication by #f6f1e7; alpha unchanged"]
                + (["Small joker illustration desaturated to distinguish it from the large joker"] if key == "52" else []),
        }
    with ThreadPoolExecutor(max_workers=6) as workers:
        entries = list(workers.map(make_card, catalog()))
    manifest = {
        "format_version": 1, "imported_date": "2026-11-05", "repository": REPOSITORY, "commit": COMMIT,
        "upstream_deck": "SVG-cards 4.0.2 / David Bellot and Huub de Beer",
        "license": "LGPL-2.1 (upstream repository license; SVG header preserved unchanged)",
        "copyright": ["Copyright (C) 2005 David Bellot", "Copyright (C) 2016, 2017 Huub de Beer"],
        **source_files,
        "processing": "Upstream 2x PNGs preserve traditional pips and double-headed court art. Warm tone; small joker grayscale. Chinese small/big joker labels are a runtime Noto overlay in card.gd. PNG indices are rasterized, not runtime system-font text.",
        "cards": entries,
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    verify()

def verify() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if {entry["key"] for entry in manifest["cards"]} != {entry[0] for entry in catalog()}:
        raise RuntimeError("Expected 54 physical faces and one back")
    for entry in manifest["cards"]:
        data = (ROOT / entry["path"]).read_bytes()
        if digest(data) != entry["sha256"]: raise RuntimeError("Card hash mismatch: " + entry["key"])
        if data[:8] != b"\x89PNG\r\n\x1a\n": raise RuntimeError("Not a PNG: " + entry["key"])
        width, height = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
        if (width, height) != (entry["width"], entry["height"]) or width < 330 or height < 480:
            raise RuntimeError("Unexpected dimensions: " + entry["key"])
    for key in ["source_svg", "license_file", "upstream_readme"]:
        entry = manifest[key]
        if digest((ROOT / entry["path"]).read_bytes()) != entry["sha256"]:
            raise RuntimeError("Source/license hash mismatch: " + key)
    print("Verified 54 traditional faces, one back, original SVG source and upstream license.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify: verify()
    elif args.download: download()
    else: parser.error("Choose --download or --verify")
