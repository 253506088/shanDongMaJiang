"""Rebuild original Qingyu visual/audio assets. Requires Pillow; fonts are OFL.
The generated files are committed so players need neither Python nor the network.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, random, wave, struct, shutil

ROOT = Path(__file__).resolve().parents[1]
A = ROOT / 'assets'
for name in ('tiles', 'textures', 'audio', 'fonts'):
    (A / name).mkdir(parents=True, exist_ok=True)
for name in ('NotoSerifSC', 'NotoSansSC'):
    if not (A / 'fonts' / f'{name}.ttf').exists():
        shutil.copyfile(ROOT / 'tmp' / f'{name}.ttf', A / 'fonts' / f'{name}.ttf')
def font(size, serif=True):
    f = ImageFont.truetype(str(A / 'fonts' / ('NotoSerifSC.ttf' if serif else 'NotoSansSC.ttf')), size)
    try: f.set_variation_by_axes([650 if serif else 500])
    except OSError: pass  # Prepared static-weight subsets have no variation axes.
    return f
def text_center(d, center, text, size, fill, serif=True):
    d.text(center, text, font=font(size, serif), fill=fill, anchor='mm', stroke_width=0)

RED = '#a83d36'; GREEN = '#25634d'; INK = '#263d3b'; GOLD = '#bd9459'
for tile in range(43):
    if tile < 42 and (A/'licenses'/'lotus-assets.json').exists():
        continue  # Preserve imported artwork. Rebuild it with import_lotus_assets.py.
    im = Image.new('RGBA', (256, 368), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((3, 7, 253, 365), radius=23, fill='#143f37')
    d.rounded_rectangle((3, 0, 253, 351), radius=22, fill='#d5c9a6')
    d.rounded_rectangle((7, 2, 249, 342), radius=19, fill='#f6f1df')
    d.rounded_rectangle((12, 7, 244, 335), radius=15, outline='#fffdf3', width=3)
    if tile == 42:
        d.rounded_rectangle((17, 17, 239, 328), radius=13, fill='#20584b', outline=GOLD, width=3)
        for off in range(-300, 500, 28):
            d.line((17, off, 239, off+222), fill='#2c6958', width=2)
        d.ellipse((55, 106, 201, 252), fill='#20584b', outline=GOLD, width=3)
        d.ellipse((64, 115, 192, 243), outline=GOLD, width=1)
        text_center(d,(128,173),'玉',78,'#dac08a')
    elif tile < 9:
        text_center(d, (128, 95), '一二三四五六七八九'[tile], 101, INK)
        text_center(d, (128, 224), '萬', 113, RED)
    elif tile < 18:
        n = tile-8
        points={1:[(128,172)],2:[(128,85),(128,260)],3:[(64,65),(128,172),(192,279)],4:[(68,87),(188,87),(68,257),(188,257)],5:[(65,65),(191,65),(128,172),(65,279),(191,279)],6:[(70,64),(186,64),(70,172),(186,172),(70,280),(186,280)],7:[(64,57),(128,57),(192,57),(74,164),(182,164),(74,276),(182,276)],8:[(71,51),(185,51),(71,130),(185,130),(71,212),(185,212),(71,291),(185,291)],9:[(x,y) for y in [64,172,280] for x in [58,128,198]]}[n]
        for j,(x,y) in enumerate(points):
            r=67 if n==1 else (26 if n==9 else 32)
            color=RED if n in [5,7,9] and j==len(points)//2 else (GREEN if j%2==0 else INK)
            for k in [0,7,14]:
                if r-k>2:d.ellipse((x-r+k,y-r+k,x+r-k,y+r-k),outline=color,width=4)
            d.ellipse((x-4,y-4,x+4,y+4),fill=color)
    elif tile < 27:
        n=tile-17
        if n==1:
            # Original stylized bamboo bird, not a copied tile design.
            d.arc((44,88,203,298), 155, 322, fill=GREEN,width=20)
            d.ellipse((104,66,165,127),fill=GREEN)
            d.polygon([(153,86),(207,101),(159,107)],fill=RED)
            d.ellipse((142,83,149,90),fill='#f6f1df')
            for x in [67,91,114]:d.line((114,219,x,295),fill=GREEN,width=9)
            d.line((145,226,156,291,190,292),fill=RED,width=5)
            d.arc((97,135,183,220),90,270,fill='#f6f1df',width=6)
        else:
            cols = 2 if n%2==0 else 3
            rows = math.ceil(n/cols)
            for j in range(n):
                row,col=divmod(j,cols)
                x=128+(col-(cols-1)/2)*(70 if cols==3 else 100)
                y=172+(row-(rows-1)/2)*91
                color=RED if n in [5,7,9] and j==n//2 else GREEN
                d.rounded_rectangle((x-10,y-33,x+10,y+33),radius=8,fill=color)
                d.line((x,y-25,x,y+25),fill='#a7bd84',width=3)
                for yy in [y-28,y,y+28]:d.line((x-15,yy,x+15,yy),fill=color,width=7)
    elif tile < 34:
        word=['東','南','西','北','中','發','白'][tile-27]
        if tile==33:
            d.rounded_rectangle((56,65,200,278),radius=9,outline='#3a6384',width=12)
            d.rectangle((72,80,184,263),outline='#3a6384',width=3)
        else:text_center(d,(128,174),word,159,RED if tile==31 else GREEN if tile==32 else INK)
    else:
        idx=tile-34
        color=['#a05f70','#337268','#b78543','#607987'][idx%4]
        for j in range(5):
            ang=j*math.tau/5
            x=128+35*math.cos(ang);y=213+35*math.sin(ang)
            d.ellipse((x-23,y-23,x+23,y+23),outline=color,width=4)
        d.ellipse((117,202,139,224),fill=GOLD)
        text_center(d,(128,90),'春夏秋冬梅兰竹菊'[idx],82,color)
        text_center(d,(128,295),str(idx+1),24,GOLD,False)
    im.save(A/'tiles'/f'{tile:02}.png')

# Original woven felt with restrained, layered mountain contours.
rng=random.Random(731)
size=1536
im=Image.new('RGB',(size,size)); px=im.load()
for y in range(size):
    for x in range(size):
        radial=max(0,1-math.hypot(x-size/2,y-size/2)/(size*.72))
        grain=rng.randrange(-3,4)+(1 if (x+y)%3==0 else 0)
        px[x,y]=(int(22+radial*11+grain),int(66+radial*17+grain),int(58+radial*13+grain))
d=ImageDraw.Draw(im)
for inset in [35,42,69]:d.rounded_rectangle((inset,inset,size-inset,size-inset),radius=24,outline='#6d7a58',width=2)
for corner in range(4):
    art=Image.new('RGBA',(480,480));ad=ImageDraw.Draw(art)
    for row in range(7):
        pts=[]
        for x in range(420):
            yy=350-row*22-95*math.exp(-((x-180)/75)**2)-50*math.exp(-((x-310)/54)**2)+7*math.sin(x/25+row*.2)
            pts.append((x,int(yy)))
        ad.line(pts,fill=(176,160,108,43),width=2)
    art=art.rotate(90*corner)
    im.paste(art,[(95,950),(950,950),(950,95),(95,95)][corner],art)
d=ImageDraw.Draw(im)
cx=cy=size//2
for r in [185,194,274]:d.ellipse((cx-r,cy-r,cx+r,cy+r),outline='#637356',width=2)
for a in range(0,360,15):
    r=math.radians(a)
    d.line((cx+258*math.cos(r),cy+258*math.sin(r),cx+271*math.cos(r),cy+271*math.sin(r)),fill='#7c815b',width=2)
im.save(A/'textures'/'felt.png')

# A silk-paper lobby background, its geometry generated here and kept reproducible.
bg=Image.new('RGB',(1600,900));d=ImageDraw.Draw(bg)
for y in range(900):
    t=y/900;d.line((0,y,1600,y),fill=(int(13+9*t),int(34+12*t),int(34+7*t)))
for layer in range(5):
    pts=[(0,900)]
    for x in range(0,1601,4):
        y=630+layer*42-110*math.sin(x/370+layer*.7)-60*math.sin(x/143+layer*.2)
        pts.append((x,int(y)))
    pts.append((1600,900));d.polygon(pts,fill=(18+layer*3,48+layer*4,45+layer*3))
for r in [113,116]:d.ellipse((1130-r,233-r,1130+r,233+r),outline='#847853',width=1)
bg.save(A/'textures'/'lobby.png')

# Small original synthesized sounds, generated offline; no borrowed recordings.
rate=44100
for kind,duration,base in [('click',.09,1250),('tile',.14,780),('deal',.16,560),('notify',.5,660),('win',1.5,440)]:
    data=[];rng=random.Random(12)
    for i in range(int(rate*duration)):
        t=i/rate;env=math.exp(-t*(48 if kind in ['click','tile','deal'] else 4))
        if kind=='win':
            freq=[440,554.37,659.25,880][min(3,int(t/.21))]
            signal=.28*math.sin(math.tau*freq*t)+.12*math.sin(math.tau*freq*2*t)
        else:signal=.25*math.sin(math.tau*base*t)+(.13*rng.uniform(-1,1) if kind in ['tile','deal'] else .1*math.sin(math.tau*base*1.5*t))
        data.append(struct.pack('<h',int(max(-1,min(1,signal*env))*24000)))
    with wave.open(str(A/'audio'/f'{kind}.wav'),'wb') as w:
        w.setparams((1,2,rate,0,'NONE','not compressed'));w.writeframes(b''.join(data))
if (A/'licenses'/'lotus-assets.json').exists():
    import runpy
    runpy.run_path(str(ROOT/'tools'/'make_table_texture.py'))
print('Generated local decor and effects; imported tile artwork is preserved.')
