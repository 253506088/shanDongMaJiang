"""Import the predecessor's checked-in tile artwork and voice clips; no network.
Usage: python tools/import_lotus_assets.py <lianhuaguangdongmahjong directory>
The glyphs are existing raster artwork, not font-rendered replacements.
"""
from pathlib import Path
import hashlib
import json
import shutil
import sys
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
assets = root / 'assets'
(assets / 'audio' / 'voice').mkdir(parents=True, exist_ok=True)
(assets / 'licenses').mkdir(exist_ok=True)
records = []
for tile in range(34):
    code = f'{tile % 9 + 1}{"mps"[tile // 9]}' if tile < 27 else f'{tile - 26}z'
    original = source / 'public' / 'tiles' / f'{code}.png'
    artwork = Image.open(original).convert('RGBA')
    card = Image.new('RGBA', (256, 344))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((2, 4, 253, 343), 18, fill='#aebdb5')
    draw.rounded_rectangle((2, 0, 253, 335), 18, fill='#ece8dc', outline='#c7cbbf', width=2)
    draw.rounded_rectangle((7, 4, 248, 328), 14, fill='#faf8ee')
    artwork = artwork.resize((211, 281), Image.Resampling.LANCZOS)
    card.alpha_composite(artwork, ((256-artwork.width)//2, (330-artwork.height)//2))
    card.save(assets / 'tiles' / f'{tile:02}.png')
    clip = source / 'public' / 'audio' / f'{code}.mp3'
    shutil.copyfile(clip, assets / 'audio' / 'voice' / f'{tile:02}.mp3')
    records.append({'tile': tile, 'source': f'public/tiles/{code}.png', 'sha256': hashlib.sha256(original.read_bytes()).hexdigest(), 'voice': f'public/audio/{code}.mp3', 'voice_sha256': hashlib.sha256(clip.read_bytes()).hexdigest()})
for name in ('chi', 'peng', 'gang', 'hu', 'zimo'):
    shutil.copyfile(source / 'public' / 'audio' / f'{name}.mp3', assets / 'audio' / 'voice' / f'{name}.mp3')
for tile in range(34, 42):
    shutil.copyfile(source / 'public' / 'tiles' / f'f{tile-33}.svg', assets / 'tiles' / f'{tile:02}.svg')
shutil.copyfile(source / 'LICENSE', assets / 'licenses' / 'lotus-MIT.txt')
shutil.copyfile(source / 'public' / 'licenses' / 'CC-BY-SA-4.0.txt', assets / 'licenses' / 'flowers-CC-BY-SA-4.0.txt')
shutil.copyfile(source / 'assets-src' / 'flowers' / 'sources.json', assets / 'licenses' / 'flowers-sources.json')
(assets / 'licenses' / 'lotus-assets.json').write_text(json.dumps({'repository': 'https://github.com/253506088/lianhuaguangdongmahjong', 'commit': '164822b0cfa21fcda6f73237b131ac0f3e012214', 'adaptation': 'Tile artwork fitted to ivory tile bodies; audio copied unchanged. Flower SVGs retain CC BY-SA 4.0.', 'tiles': records}, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Imported {len(records)} tile faces and voices, 8 flower SVGs, 5 action voices, and licenses.')
