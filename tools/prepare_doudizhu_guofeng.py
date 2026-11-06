"""Prepare 54 Guofeng faces and a back from the six user-delivered paintings.

Requires Pillow. Run with --prepare, then --verify (verification needs no raw
archive). --verify-sources also checks all twelve originals and their backup.
No AI generation, downloads or source-image edits occur here.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageStat

ROOT = Path(__file__).resolve().parents[1]
DELIVERY = "art-delivery-doudizhu-guofeng-2026-11-06"
RAW = ROOT / "artifacts" / DELIVERY / "raw"
BACKUP = ROOT.parent / (ROOT.name + "-美术备份") / DELIVERY / "raw"
OUT = ROOT / "assets/doudizhu/guofeng"
MANIFEST = ROOT / "assets/licenses/doudizhu-guofeng-manifest.json"
FONT = ROOT / "assets/fonts/NotoSansSC-Bold.ttf"
W, H, SCALE = 338, 490, 2
PAPER = (242, 236, 221)
BLACK, RED, GOLD = "#172e2a", "#aa302a", "#baa471"
NAMES = ["j-young", "q-scholar", "k-elder", "joker-black", "joker-red", "back-jade"]
# All court crops retain hands and end below the waist; no stretched portraits.
CROPS = {name: (62, 85, 798, 1115) for name in NAMES[:3]}
CROPS.update({name: (64, 76, 800, 1246) for name in NAMES[3:5]})

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def suit_image(kind: int, ink: str, size: int) -> Image.Image:
    tile = Image.new("RGBA", (100, 112))
    draw = ImageDraw.Draw(tile)
    if kind in (0, 1):
        points = []
        for i in range(160):
            t = i * math.tau / 160
            x = 16 * math.sin(t) ** 3
            y = 13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t)
            points.append((50 + x * 2.85, 47 - y * 2.75 if kind == 1 else 51 + y * 2.75))
        draw.polygon(points, fill=ink)
    elif kind == 2:
        for bounds in [(30, 3, 70, 50), (6, 36, 51, 84), (49, 36, 94, 84)]: draw.ellipse(bounds, fill=ink)
    else: draw.polygon([(50, 4), (91, 53), (50, 103), (9, 53)], fill=ink)
    if kind in (0, 2): draw.polygon([(50, 62), (35, 103), (65, 103)], fill=ink)
    return tile.resize((size, round(size * 1.12)), Image.Resampling.LANCZOS)

def paste_center(canvas, source, xy, upside=False):
    if upside: source = source.transpose(Image.Transpose.ROTATE_180)
    canvas.alpha_composite(source, (round(xy[0]*SCALE-source.width/2), round(xy[1]*SCALE-source.height/2)))

def paper_card():
    card = Image.new("RGBA", (W*SCALE, H*SCALE))
    ImageDraw.Draw(card).rounded_rectangle((2, 2, W*SCALE-3, H*SCALE-3), radius=19, fill=PAPER, outline="#a99672", width=2)
    return card

def indices(card, rank, kind):
    ink = RED if kind in (1, 3) else BLACK
    layer = Image.new("RGBA", card.size)
    font = ImageFont.truetype(str(FONT), 48*SCALE)
    text = {11: "J", 12: "Q", 13: "K", 14: "A", 15: "2"}.get(rank, str(rank))
    ImageDraw.Draw(layer).text((33*SCALE, 12*SCALE), text, font=font, fill=ink, anchor="mt", stroke_width=0)
    paste_center(layer, suit_image(kind, ink, 31*SCALE), (33, 81))
    card.alpha_composite(layer)
    card.alpha_composite(layer.transpose(Image.Transpose.ROTATE_180))

def jokers(card, ink):
    layer = Image.new("RGBA", card.size)
    font = ImageFont.truetype(str(FONT), 30*SCALE)
    draw = ImageDraw.Draw(layer)
    for index, letter in enumerate("JOKER"):
        draw.text((31*SCALE, (16+32*index)*SCALE), letter, font=font, fill=ink, anchor="mt")
    card.alpha_composite(layer)
    card.alpha_composite(layer.transpose(Image.Transpose.ROTATE_180))

def painting(name):
    im = Image.open(RAW / ("guofeng-" + name + ".png")).convert("RGB")
    # Match the quiet corner paper to the deck while retaining painted shading.
    bg = ImageStat.Stat(im.crop((15, 15, 100, 90))).mean
    bands = [band.point([min(255, round(v*PAPER[c]/bg[c])) for v in range(256)]) for c, band in enumerate(im.split())]
    return Image.merge("RGB", bands).crop(CROPS[name])

def soft_edges(im, width=12):
    im = im.convert("RGBA")
    alpha = Image.new("L", im.size)
    draw = ImageDraw.Draw(alpha)
    for i in range(width):
        draw.rectangle((i, i, im.width-i-1, im.height-i-1), fill=round(255*(i+1)/width))
    im.putalpha(alpha)
    return im

def court(card, name):
    art = ImageOps.contain(painting(name), (222*SCALE, 227*SCALE), Image.Resampling.LANCZOS)
    top = Image.new("RGBA", card.size)
    top.alpha_composite(soft_edges(art), ((W*SCALE-art.width)//2, H*SCALE//2-art.height))
    card.alpha_composite(top)
    card.alpha_composite(top.transpose(Image.Transpose.ROTATE_180))
    # Deliberate waist seam, below both hands; no frame or placeholder art slot.
    draw = ImageDraw.Draw(card)
    for y in (H*SCALE//2-2, H*SCALE//2+2):
        draw.line((82*SCALE,y,256*SCALE,y), fill=GOLD, width=2)

def pips(card, rank, kind):
    n = {14: 1, 15: 2}.get(rank, rank)
    ink = RED if kind in (1, 3) else BLACK
    rows = [112, 378] if n <= 5 else [112, 245, 378] if n <= 8 else [106, 198, 292, 384]
    positions = []
    if n <= 3: positions = [(169,y) for y in ([245] if n == 1 else [112,378] if n == 2 else [112,245,378])]
    else:
        positions = [(x,y) for x in (109,229) for y in rows]
        positions += {4: [], 5: [(169,245)], 6: [], 7: [(169,178.5)], 8: [(169,178.5),(169,311.5)], 9: [(169,245)], 10: [(169,152),(169,338)]}[n]
    pip = suit_image(kind, ink, (64 if n == 1 else 45)*SCALE)
    for x,y in positions: paste_center(card, pip, (x,y), y > H/2)
    assert len(positions) == n

def back_card():
    card = paper_card()
    raw = Image.open(RAW / "guofeng-back-jade.png").convert("RGBA")
    # Repeat the upper half exactly to make the back orientation-independent.
    half = raw.crop((0,0,raw.width,raw.height//2)).resize((318*SCALE,235*SCALE), Image.Resampling.LANCZOS)
    card.alpha_composite(half,(10*SCALE,10*SCALE))
    card.alpha_composite(half.transpose(Image.Transpose.ROTATE_180),(10*SCALE,245*SCALE))
    return card

def verify_sources(backup=True):
    entries = json.loads((RAW.parent / "backup-verification.json").read_text(encoding="utf-8-sig"))
    for entry in entries:
        for root in ((RAW, BACKUP) if backup else (RAW,)):
            if sha(root / entry["name"]) != entry["sha256"]: raise RuntimeError("Source/backup mismatch: " + str(root / entry["name"]))
    print(f"Verified {len(entries)} originals" + (" and their external backup." if backup else "."))
    return entries

def prepare():
    sources = verify_sources(backup=False)
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for key in [f"{i:02d}" for i in range(54)] + ["back"]:
        name = None
        if key == "back": card = back_card(); name = "back-jade"
        else:
            card = paper_card(); cid = int(key)
            if cid >= 52:
                name = "joker-black" if cid == 52 else "joker-red"
                art = ImageOps.contain(painting(name), (235*SCALE,424*SCALE), Image.Resampling.LANCZOS)
                paste_center(card, soft_edges(art), (169,245))
                jokers(card, BLACK if cid == 52 else RED)
            else:
                rank, kind = 3 + cid//4, cid%4
                if rank in (11,12,13): name = NAMES[rank-11]; court(card,name)
                else: pips(card,rank,kind)
                indices(card,rank,kind)
        path = OUT / (key + ".png")
        card.resize((W,H), Image.Resampling.LANCZOS).save(path,compress_level=9)
        entries.append({"key":key, "path":path.relative_to(ROOT).as_posix(), "sha256":sha(path), "bytes":path.stat().st_size, "width":W,"height":H,"painting":name})
    manifest = {"format_version":1,"prepared_date":"2026-11-06", "origin":"User-delivered generated artwork following docs/doudizhu-guofeng-art-prompts.md; generation model not supplied.",
        "source_archive":RAW.relative_to(ROOT).as_posix(), "external_backup":str(BACKUP), "sources":sources,
        "font":{"path":FONT.relative_to(ROOT).as_posix(),"sha256":sha(FONT),"license":"SIL OFL 1.1; assets/fonts/OFL-NotoSansSC.txt"},
        "processing":{"tool":"tools/prepare_doudizhu_guofeng.py", "court_crops":CROPS, "notes":"Native 848x1264 paintings; warm paper matching; portraits scaled proportionally, paired by 180-degree rotation at the waist. Code-drawn standard indices and pips; stacked upright JOKER letters in opposite corners. Back repeats rotated upper half. 2x composition, Lanczos downsample to 338x490."}, "cards":entries}
    MANIFEST.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    verify()

def verify():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert {e["key"] for e in manifest["cards"]} == {f"{i:02d}" for i in range(54)} | {"back"}
    for entry in manifest["cards"]:
        path = ROOT / entry["path"]
        assert sha(path) == entry["sha256"], path
        with Image.open(path) as im:
            assert im.size == (W,H) and im.mode == "RGBA", path
            if entry["key"] == "back": assert im.tobytes() == im.transpose(Image.Transpose.ROTATE_180).tobytes(), "Back must be directionless"
    assert sha(FONT) == manifest["font"]["sha256"]
    print("Verified 54 Guofeng faces, symmetric back and bundled index font.")

if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare",action="store_true")
    parser.add_argument("--verify",action="store_true")
    parser.add_argument("--verify-sources",action="store_true")
    args=parser.parse_args()
    if args.prepare: prepare()
    elif args.verify: verify()
    elif args.verify_sources: verify_sources()
    else: parser.error("Choose --prepare, --verify or --verify-sources")
