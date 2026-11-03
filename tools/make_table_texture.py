"""Reproducible sea-glass cloth, enamel tile backs and soft contact shadows.

The coastal contour artwork and wave emblem are original, deterministic geometry.
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
    # Broad illumination is baked very gently, keeping the playing field calm.
    radius = ((x-size*.46)/(size*.71))**2 + ((y-size*.40)/(size*.78))**2
    light = np.exp(-radius*1.5)
    # The cloth is almost smooth at gameplay zoom. Low-pass random grain adds
    # material depth at close range without any repeated weave or sharp pixels.
    grain_image = Image.fromarray(RNG.integers(108,149,(768,768),dtype=np.uint8))
    grain_image = grain_image.filter(ImageFilter.GaussianBlur(1.8))
    grain_image = grain_image.resize((size,size),Image.Resampling.BICUBIC)
    grain = (np.asarray(grain_image,dtype=float)-128)*.09
    rgb = np.stack([64+light*35+grain, 113+light*40+grain,
                    125+light*33+grain], axis=2)
    cloth = Image.fromarray(np.clip(rgb, 0, 255).astype("uint8")).convert("RGBA")
    art = Image.new("RGBA", cloth.size)
    d = ImageDraw.Draw(art)

    # Two tailored seams and a thin shaded inner edge feel like an inset cloth.
    for inset, color, width in [(18, (220,244,244,100), 3),
                                (25, (30,75,88,90), 2),
                                (77, (218,241,239,75), 2)]:
        d.rounded_rectangle((inset, inset, size-inset-1, size-inset-1),
                            radius=55, outline=color, width=width)
    for t in range(120, size-120, 14):
        for edge in [53, size-54]:
            d.line([(t, edge), (t+5, edge)], fill=(219,240,237,55), width=2)
            d.line([(edge, t), (edge, t+5)], fill=(219,240,237,55), width=2)

    # Quiet topographic ribbons appear only in the outer corners. Their open
    # silhouettes leave the hands, rivers and walls on unpatterned fabric.
    corner = Image.new("RGBA", (650, 650))
    c = ImageDraw.Draw(corner)
    for i in range(7):
        shift = i*21
        points = [(98+shift, 590), (55+shift, 302),
                  (242, 68+shift), (592, 96+shift)]
        c.line(curve(points, 130), fill=(220,241,237,68-i*6), width=2)
    for i in range(3):
        shift = i*23
        c.line(curve([(144+shift,540), (172+shift,326),
                      (353,178+shift), (551,156+shift)], 100),
               fill=(25,76,91,35), width=2)
    # The corner seam ends in a spare navigation diamond, not a floral seal.
    c.polygon([(212,191),(222,201),(212,211),(202,201)],
              fill=(218,239,234,125))
    c.line([(212,221),(212,246)], fill=(219,239,234,68), width=2)
    c.line([(232,201),(257,201)], fill=(219,239,234,68), width=2)
    for rotation, position in enumerate([(86,86), (size-736,86),
                                          (size-736,size-736),(86,size-736)]):
        art.alpha_composite(corner.rotate(-90*rotation), position)

    # A restrained registration circle frames the centre display. Short marks
    # imply the four seats without adding typography or distracting symbols.
    middle = size/2
    for r, alpha in [(299,42),(311,24),(372,19)]:
        d.ellipse((middle-r,middle-r,middle+r,middle+r),
                  outline=(220,241,237,alpha), width=2)
    for angle in range(0,360,90):
        a = math.radians(angle)
        nx, ny = math.cos(a), math.sin(a)
        d.line([(middle+327*nx,middle+327*ny),
                (middle+349*nx,middle+349*ny)],
               fill=(225,242,238,67), width=3)
    cloth = Image.alpha_composite(cloth, art)
    mask = Image.new("L", cloth.size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,size-1,size-1),radius=42,fill=255)
    cloth.putalpha(mask)
    cloth.save(ROOT / "felt.png")


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
    make_back()
    make_shadow()
    print("Built sea-glass cloth, silver-wave enamel backs and contact shadow.")
