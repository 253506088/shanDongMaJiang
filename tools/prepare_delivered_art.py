"""Prepare the user-delivered courtyard, portraits and cloth for the game.

Requires Pillow and NumPy. Run from any working directory:
    python tools/prepare_delivered_art.py --source-dir artifacts/art-delivery-2026-11-03

The original generation exports stay in the local delivery archive. The checked-in
runtime images and assets/art_manifest.json are sufficient to run the game. A
rebuild requires the delivery archive; its model/version was not supplied. The
background deliberately uses native pixels, not the interpolated 2560x1440 copy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "artifacts/art-delivery-2026-11-03"
PORTRAITS = {
    "self": "avatar_self_female_player_1793720360623.jpg",
    "tingsong": "avatar_tingsong_v2_1793720392127.jpg",
    "guanlan": "avatar_guanlan_1793720369139.jpg",
    "zhiqiu": "avatar_zhiqiu_1793720383677.jpg",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def circle_portrait(source: Image.Image) -> Image.Image:
    """One consistent head-and-shoulders crop, legible at 48-72 display pixels."""
    if source.size != (1024, 1024):
        raise ValueError(f"Expected a 1024x1024 portrait, got {source.size}")
    portrait = source.convert("RGBA").crop((112, 32, 912, 832))
    portrait = portrait.resize((256, 256), Image.Resampling.LANCZOS)
    mask = Image.new("L", (1024, 1024))
    ImageDraw.Draw(mask).ellipse((2, 2, 1021, 1021), fill=255)
    portrait.putalpha(mask.resize((256, 256), Image.Resampling.LANCZOS))
    return portrait


def table_cloth(source: Image.Image) -> Image.Image:
    """Keep the supplied weave; add restrained table lighting and rounded edges.

    This is a complete table-surface image, not the original seamless albedo.
    The delivered image repeats an 8x8 cell. Its strong horizontal/vertical
    harmonics become a screen-door grid when the table is downsampled. Suppress
    those harmonics, gently low-pass and reduce the remaining source detail.
    A broad 0.91-1.08 multiplier gives shape in the stable unshaded table material.
    No extra random grain, brand marks or new ornament is introduced.
    """
    if source.size != (2048, 2048):
        raise ValueError(f"Expected 2048x2048 cloth, got {source.size}")
    size = source.width
    y, x = np.mgrid[0:size, 0:size]
    radius = ((x - size * .38) / (size * .82)) ** 2
    radius += ((y - size * .32) / (size * .92)) ** 2
    light = .91 + .17 * np.exp(-radius * 1.8)
    rgb = np.asarray(source.convert("RGB"), dtype=np.float32)
    mean = rgb.mean(axis=(0, 1), keepdims=True)
    row_pattern = rgb.mean(axis=1, keepdims=True) - mean
    column_pattern = rgb.mean(axis=0, keepdims=True) - mean
    detail = rgb - mean - .90 * (row_pattern + column_pattern)
    # Periodic separable Gaussian in float precision preserves the tile boundary
    # and faint diagonal fibres without quantizing the tiny signal prematurely.
    offsets = np.arange(-2, 3)
    kernel = np.exp(-.5 * (offsets / .65) ** 2)
    kernel /= kernel.sum()
    for axis in (0, 1):
        detail = sum(weight * np.roll(detail, int(offset), axis=axis)
                     for offset, weight in zip(offsets, kernel))
    rgb = (mean + .50 * detail) * light[..., None]
    cloth = Image.fromarray(np.clip(rgb, 0, 255).astype("uint8")).convert("RGBA")
    piping = Image.new("RGBA", cloth.size)
    draw = ImageDraw.Draw(piping)
    for inset, color, width in [(13, (15, 43, 39, 125), 3),
                                (18, (174, 186, 151, 38), 1)]:
        draw.rounded_rectangle((inset, inset, size-inset-1, size-inset-1),
                               radius=37, outline=color, width=width)
    cloth = Image.alpha_composite(cloth, piping)
    mask = Image.new("L", (size * 2, size * 2))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size*2-1, size*2-1),
                                           radius=56, fill=255)
    cloth.putalpha(mask.resize(cloth.size, Image.Resampling.LANCZOS))
    return cloth


def source_record(source_dir: Path, filename: str, raw_filename: str | None) -> dict:
    path = source_dir / filename
    with Image.open(path) as source:
        record = {
            "file": filename,
            "sha256": sha256(path),
            "pixel_dimensions": list(source.size),
        }
    if raw_filename:
        raw = source_dir / "raw" / raw_filename
        # The delivery PNG is a lossless decoded copy of the original JPEG.
        with Image.open(raw) as raw_image, Image.open(path) as named_image:
            if not np.array_equal(np.asarray(raw_image.convert("RGB")),
                                  np.asarray(named_image.convert("RGB"))):
                raise ValueError(f"Named delivery differs from raw pixels: {filename}")
        named_jpeg = path.with_suffix(".jpg")
        if named_jpeg.exists() and sha256(named_jpeg) != sha256(raw):
            raise ValueError(f"Named JPEG differs from raw export: {filename}")
        record["raw_file"] = "raw/" + raw_filename
        record["raw_sha256"] = sha256(raw)
        record["raw_pixel_match"] = True
    else:
        record["raw_file"] = None
        record["note"] = "Supplied PNG texture; no matching raw generation export supplied."
    return record


def output_record(path: Path, source: dict, processing: str) -> dict:
    with Image.open(path) as image:
        record = {
            "file": path.relative_to(ROOT).as_posix(),
            "sha256": sha256(path),
            "bytes": path.stat().st_size,
            "pixel_dimensions": list(image.size),
            "mode": image.mode,
            "source": source,
            "processing": processing,
        }
        if image.mode == "RGBA":
            alpha = image.getchannel("A")
            if alpha.getextrema() != (0, 255):
                raise ValueError(f"Expected transparent and opaque pixels: {path}")
            record["alpha_extrema"] = list(alpha.getextrema())
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--contact-sheet", type=Path,
                        help="Optional local QA image; it is not a game resource.")
    args = parser.parse_args()
    source_dir = args.source_dir.resolve()
    records = []
    sources = []

    background_name = "courtyard-day-01.png"
    background = Image.open(source_dir / background_name).convert("RGB")
    if background.size != (1376, 768):
        raise ValueError(f"Unexpected native background dimensions: {background.size}")
    output = ROOT / "assets/backgrounds/courtyard_day.jpg"
    output.parent.mkdir(parents=True, exist_ok=True)
    background.save(output, quality=92, subsampling=0, optimize=True)
    records.append(output_record(output, source_record(source_dir, background_name,
        "chinese_courtyard_teahouse_bg_1793720221923.jpg"),
        "Native-size JPEG, quality 92, 4:4:4 chroma; no upscale or color grading."))
    sources.append(("Courtyard / native pixels", background))

    for name, raw in PORTRAITS.items():
        filename = f"avatar-{name}.png"
        portrait = circle_portrait(Image.open(source_dir / filename))
        output = ROOT / "assets/ui/avatars" / f"{name}.png"
        save_png(portrait, output)
        records.append(output_record(output, source_record(source_dir, filename, raw),
            "1024 source crop [112,32,912,832], Lanczos to 256, supersampled circular alpha."))
        sources.append((name, portrait))

    filename = "felt-teal-seamless.png"
    cloth = table_cloth(Image.open(source_dir / filename))
    output = ROOT / "assets/textures/felt_delivered.png"
    save_png(cloth, output)
    records.append(output_record(output, source_record(source_dir, filename, None),
        "Native 2048 weave; suppress row/column periodic detail by 90%, periodic Gaussian sigma 0.65px, remaining detail contrast 50%; 0.91-1.08 broad light multiplier, subtle piping and rounded alpha; full table map."))

    manifest = {
        "schema_version": 1,
        "delivery": "art-delivery-2026-11-03",
        "origin": "User-supplied AI-generated art, based on docs/art-generation-prompts.md.",
        "generation_model": "Not supplied in the delivery README.",
        "source_archive": "artifacts/art-delivery-2026-11-03 (local, excluded from Git)",
        "preparation_tool": "tools/prepare_delivered_art.py",
        "resolution_note": "1376x768 is the background's native resolution. The delivered 2560x1440 interpolation is not used.",
        "assets": records,
    }
    (ROOT / "assets/art_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.contact_sheet:
        sheet = Image.new("RGB", (1024, 900), "#143e36")
        sheet.paste(ImageOps.fit(background, (1024, 576)), (0, 0))
        draw = ImageDraw.Draw(sheet)
        for index, (name, portrait) in enumerate(sources[1:]):
            sheet.paste(portrait, (index*256, 600), portrait)
            draw.text((index*256+100, 865), name, fill="#f2e8d2")
        args.contact_sheet.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(args.contact_sheet, quality=92)

    for record in records:
        print(f"{record['file']}: {record['pixel_dimensions']}, {record['bytes']:,} bytes")
    print(f"Total runtime art: {sum(item['bytes'] for item in records):,} bytes")
    print("Verified raw/named pixels, file hashes and alpha; wrote assets/art_manifest.json")


if __name__ == "__main__":
    main()
