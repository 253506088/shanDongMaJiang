"""Reproducible jade cloth, walnut rails, quiet room floor and enamel backs.

All fabric, wood grain, botanical silhouettes and back emblems are original.
No fonts, third-party pictures or network access are required to rebuild them.
"""
from pathlib import Path
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1] / "assets/textures"
ROOT.mkdir(parents=True, exist_ok=True)
RNG = np.random.default_rng(731)


def curve(points, samples=100):
    """Sample one cubic Bezier curve for antialiased original line artwork."""
    p = np.asarray(points, dtype=float)
    t = np.linspace(0, 1, samples)[:, None]
    return [tuple(x) for x in ((1-t)**3*p[0] + 3*(1-t)**2*t*p[1]
                              + 3*(1-t)*t**2*p[2] + t**3*p[3])]


def make_cloth():
    size = 3072
    y, x = np.mgrid[0:size, 0:size]
    # Wide, soft light is deliberately independent of shadow-map quality.
    # A two-scale irregular weave reads as fabric rather than a screen grid.
    radius = ((x-size*.38)/(size*.82))**2 + ((y-size*.32)/(size*.92))**2
    light = np.exp(-radius*1.8)
    grain_image = Image.fromarray(RNG.integers(85,170,(1024,1024),dtype=np.uint8))
    grain_image = grain_image.filter(ImageFilter.GaussianBlur(.5))
    grain_image = grain_image.resize((size,size),Image.Resampling.BICUBIC)
    grain = (np.asarray(grain_image,dtype=np.float32)-128)*.11
    warp = np.sin(x*1.14 + np.sin(y*.051)*.33)
    weft = np.sin(y*1.31 + np.sin(x*.029)*.48)
    weave = (warp + weft)*.50
    cloud_image = Image.fromarray(RNG.integers(90,166,(64,64),dtype=np.uint8))
    cloud_image = cloud_image.resize((size,size),Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(13))
    cloud = (np.asarray(cloud_image,dtype=np.float32)-128)*.045
    grain = grain + weave + cloud
    rgb = np.stack([20+light*15+grain, 72+light*35+grain,
                    67+light*30+grain], axis=2)
    cloth = Image.fromarray(np.clip(rgb, 0, 255).astype("uint8")).convert("RGBA")
    art = Image.new("RGBA", cloth.size)
    d = ImageDraw.Draw(art)

    # Fine piping leaves the playable area free of decorative registration lines.
    for inset, color, width in [(20, (15,43,39,170), 5),
                                (27, (174,186,151,50), 2),
                                (68, (184,186,139,38), 2)]:
        d.rounded_rectangle((inset, inset, size-inset-1, size-inset-1),
                            radius=55, outline=color, width=width)
    # Tone-on-tone ginkgo leaves stay in the corners, like a jacquard weave.
    # Their asymmetry avoids a concentric / default vector ornament look.
    corner = Image.new("RGBA", (650, 650))
    c = ImageDraw.Draw(corner)
    for cx, cy, radius, angle in [(190,195,135,-2.14),(380,132,82,-1.18),(122,375,95,-2.76)]:
        fan = [(cx,cy)]
        for a in np.linspace(angle-.8,angle+.8,60):
            r = radius*(1+.045*math.sin(a*17))
            fan.append((cx+r*math.cos(a),cy+r*math.sin(a)))
        c.polygon(fan,fill=(163,181,139,6))
        for a in np.linspace(angle-.72,angle+.72,9):
            c.line([(cx,cy),(cx+radius*.93*math.cos(a),cy+radius*.93*math.sin(a))],
                   fill=(195,196,149,8),width=2)
        c.line(curve([(cx,cy),(cx+34,cy+40),(cx+51,cy+96),(cx+92,cy+131)]),fill=(162,181,137,8),width=3)
    for rotation, position in enumerate([(86,86), (size-736,86),
                                          (size-736,size-736),(86,size-736)]):
        art.alpha_composite(corner.rotate(-90*rotation), position)
    cloth = Image.alpha_composite(cloth, art)
    mask = Image.new("L", cloth.size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,size-1,size-1),radius=42,fill=255)
    cloth.putalpha(mask)
    cloth.save(ROOT / "felt.png")


def make_wood():
    """Long, mildly wavy walnut fibres, without a repeating stripe graphic."""
    size = 2048
    y, x = np.mgrid[0:size,0:size]
    bend = np.sin(x/size*math.tau)*8 + np.sin(x/size*math.tau*3)*2
    grain = np.sin((y+bend)*.11) + .45*np.sin((y+bend)*.41)
    pore = RNG.normal(0,.65,(size,size))
    tone = np.sin((y+bend)*.018)*4 + grain*2.4 + pore
    # Neutral chocolate walnut keeps warm scene lighting from turning it orange.
    rgb = np.stack([76+tone*1.25,59+tone,44+tone*.8],axis=2)
    Image.fromarray(np.clip(rgb,0,255).astype("uint8")).save(ROOT / "walnut.png")


def make_room_floor():
    """A low-detail wooden interior, with broad diffused window light."""
    size = 2048
    y, x = np.mgrid[0:size,0:size]
    light = np.exp(-(((x-size*.14)/(size*.60))**2+((y-size*.22)/(size*.71))**2)*2)
    grain = np.sin(y*.43+np.sin(x*.005)*3)*.45 + RNG.normal(0,.3,(size,size))
    boards = (np.mod(y,171)/171)*1.7
    rgb = np.stack([24+light*24+grain+boards,36+light*22+grain+boards,32+light*16+grain+boards],axis=2)
    floor = Image.fromarray(np.clip(rgb,0,255).astype("uint8")).convert("RGBA")
    shadow = Image.new("RGBA",(size,size))
    d = ImageDraw.Draw(shadow)
    # Soft diagonal shadows imply window lattice without painted scene objects.
    for offset in [-450,-40,370,780,1190,1600]:
        d.line([(offset,-100),(offset+1200,size+100)],fill=(6,18,16,54),width=24)
    for offset in [80,490,900,1310,1720]:
        d.line([(-100,offset),(size+100,offset-680)],fill=(6,18,16,35),width=19)
    shadow = shadow.filter(ImageFilter.GaussianBlur(21))
    floor = Image.alpha_composite(floor,shadow)
    floor.convert("RGB").save(ROOT / "room_floor.png")


def make_back():
    # Author at 2x and downsample so the wave stays smooth in a 30-pixel wall tile.
    factor = 2
    w, h = 384*factor, 544*factor
    y, x = np.mgrid[0:h, 0:w]
    soft = np.exp(-(((x-w*.30)/(w*.85))**2 + ((y-h*.13)/(h*.70))**2))
    grain = RNG.normal(0,.22,(h,w))
    rgb = np.stack([17+soft*20+grain, 107+soft*32+grain,
                    123+soft*31+grain],axis=2)
    back = Image.fromarray(np.clip(rgb,0,255).astype("uint8")).convert("RGBA")
    art = Image.new("RGBA",back.size)
    d = ImageDraw.Draw(art)
    # Moulded inset plate: a diffuse highlight at the top and a dark seam at
    # the bottom. Silver is used sparingly; the shell supplies the real bevel.
    for inset, color, width in [(9,(166,220,226,160),2),
                                (15,(10,76,93,150),2),
                                (22,(205,238,239,75),1)]:
        i = inset*factor
        d.rounded_rectangle((i,i,w-i-1,h-i-1),radius=28*factor,
                            outline=color,width=width*factor)
    d.line([(44*factor,23*factor),(340*factor,23*factor)],
           fill=(230,250,249,80),width=factor)

    # Original horizon / current emblem: three clean flowing ribbons in a
    # soft silver-white. No busy medallion or tiny text to blur at game scale.
    cx, cy = w/2, h/2
    mark_scale = 1.6
    for row in range(3):
        yy = cy + (row-1)*20*factor
        pts = [(cx-65*factor,yy+4*factor), (cx-25*factor,yy-34*factor),
               (cx+22*factor,yy+34*factor), (cx+65*factor,yy-4*factor)]
        sampled = [(cx+(px-cx)*mark_scale,cy+(py-cy)*mark_scale)
                   for px,py in curve(pts,120)]
        # A single ribbon polygon avoids tiny seams between thick line segments.
        path = np.asarray(sampled)
        tangent = np.gradient(path,axis=0)
        tangent /= np.linalg.norm(tangent,axis=1)[:,None]
        normal = np.stack([-tangent[:,1],tangent[:,0]],axis=1)
        half_width = 3.5*factor*mark_scale
        ribbon = np.concatenate([path+normal*half_width,
                                 (path-normal*half_width)[::-1]])
        d.polygon([tuple(point) for point in ribbon],fill=(228,247,246,245))
        for px,py in (sampled[0],sampled[-1]):
            r = 3.5*factor*mark_scale
            d.ellipse((px-r,py-r,px+r,py+r),fill=(228,247,246,245))
    # A small horizon point completes the mark and gives it a readable top.
    r=5*factor*mark_scale
    d.ellipse((cx-r,cy-58*factor*mark_scale-r,cx+r,cy-58*factor*mark_scale+r),
              fill=(236,250,247,245))

    # Long-edge highlights are deliberately broad, avoiding a noisy grid.
    for xx in [34*factor,350*factor]:
        d.line([(xx,219*factor),(xx,325*factor)],
               fill=(169,226,230,50),width=factor)
    back = Image.alpha_composite(back,art)
    back.resize((384,544),Image.Resampling.LANCZOS).save(ROOT / "tile_back.png")


def make_shadow():
    shadow = Image.new("RGBA",(128,160))
    d = ImageDraw.Draw(shadow)
    d.rounded_rectangle((19,22,109,139),radius=16,fill=(11,37,44,63))
    shadow.filter(ImageFilter.GaussianBlur(10)).save(ROOT / "contact_shadow.png")


if __name__ == "__main__":
    make_cloth()
    make_wood()
    make_room_floor()
    make_back()
    make_shadow()
    print("Built jade cloth, walnut, room floor, enamel backs and contact shadow.")
