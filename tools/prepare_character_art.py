"""Prepare the user's eight role avatars, preserving explicit temporary mappings."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/ui/characters"
MANIFEST = ROOT / "assets/licenses/character-art-manifest.json"
ENTRIES = [
    ("male_01", "听松", "male", 2, "avatar_02_male_18.jpg", None),
    ("male_02", "知秋", "male", 4, "avatar_04_male_28.jpg", None),
    ("male_03", "怀竹", "male", 6, "avatar_06_male_38.jpg", None),
    ("male_04", "行舟", "male", 8, "临时顶替2.png", "avatar_08_male_50.jpg"),
    ("female_01", "清和", "female", 1, "avatar_01_female_16.jpg", None),
    ("female_02", "观澜", "female", 3, "avatar_03_female_24.jpg", None),
    ("female_03", "望舒", "female", 5, "临时顶替.png", "avatar_05_female_32.jpg"),
    ("female_04", "映雪", "female", 7, "avatar_07_female_45.jpg", None),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source, backup):
    source = source.resolve(); backup = backup.resolve()
    if not (source / ".gdignore").exists(): (source / ".gdignore").write_text("", encoding="utf-8")
    backup.mkdir(parents=True, exist_ok=True)
    sources = [source / entry[4] for entry in ENTRIES] + [source / "3d_cg_avatar_prompts.md"]
    for path in sources:
        target = backup / path.name
        if target.exists() and digest(target) != digest(path):
            raise RuntimeError(f"Refusing to replace different backup: {target}")
        if not target.exists(): shutil.copy2(path, target)
        if digest(target) != digest(path): raise RuntimeError(f"Backup mismatch: {path}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    mask = Image.new("L", (2048, 2048), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 2047, 2047), fill=255)
    mask = mask.resize((512, 512), Image.Resampling.LANCZOS)
    entries = []
    for id, name, gender, prompt, file, pending in ENTRIES:
        path = source / file
        with Image.open(path) as original:
            dimensions = list(original.size)
            image = ImageOps.fit(ImageOps.exif_transpose(original).convert("RGBA"), (512, 512), Image.Resampling.LANCZOS)
            image.putalpha(mask)
            output = OUTPUT / (id + ".png")
            image.save(output, optimize=True)
        entries.append({"id": id, "name": name, "gender": gender, "prompt_index": prompt,
            "source_file": file, "source_sha256": digest(path), "source_dimensions": dimensions,
            "temporary": pending is not None, "expected_replacement": pending,
            "replacement_note": ("提示词第8位，50岁男性" if prompt == 8 else "提示词第5位，32岁女性") if pending else "",
            "path": output.relative_to(ROOT).as_posix(), "sha256": digest(output)})
    metadata = {"delivered_date": "2026-11-07", "source_directory": str(source), "backup_directory": str(backup),
        "source": "User-delivered portraits and two explicitly temporary meme stand-ins; no claim of third-party open licensing for the stand-ins.",
        "processing": "EXIF orientation; centered square crop; 512px RGBA; antialiased circular alpha, no generative edits",
        "pending_replacements": [entry["id"] for entry in entries if entry["temporary"]], "avatars": entries,
        "prompt_file": {"name": "3d_cg_avatar_prompts.md", "sha256": digest(source / "3d_cg_avatar_prompts.md")}}
    MANIFEST.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Prepared 8 avatars and verified 9 source backups; temporary: " + ", ".join(metadata["pending_replacements"]))


def verify():
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert len(data["avatars"]) == 8
    for avatar in data["avatars"]:
        path = ROOT / avatar["path"]
        assert digest(path) == avatar["sha256"]
        with Image.open(path) as image:
            assert image.size == (512, 512) and image.mode == "RGBA"
            assert image.getpixel((0, 0))[3] == 0
    expected = {entry[0] for entry in ENTRIES if entry[5] is not None}
    assert {a["id"] for a in data["avatars"] if a["temporary"]} == set(data["pending_replacements"]) == expected
    print("CHARACTER_ART_VERIFIED: 8 circular runtime images; hashes and temporary mappings match")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=ROOT / "头像生成")
    parser.add_argument("--backup-dir", type=Path, default=ROOT.parent / "山东麻将-美术备份/art-delivery-characters-2026-11-07/raw")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if not args.verify: prepare(args.source_dir, args.backup_dir)
    verify()
