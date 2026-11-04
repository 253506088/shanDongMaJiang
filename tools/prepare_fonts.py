"""Create deterministic, static-weight OFL font subsets (GB2312 + project glyphs)."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tmp'/'python'))
from fontTools.ttLib import TTFont
from fontTools import subset
from fontTools.varLib.instancer import instantiateVariableFont
characters=set(chr(c) for c in range(32,127))
for high in range(0xA1,0xF8):
    for low in range(0xA1,0xFF):
        try:characters.update(bytes([high,low]).decode('gb2312'))
        except UnicodeDecodeError:pass
for folder in ['scripts','tools']:
    for path in (ROOT/folder).rglob('*'):
        if path.suffix in ['.gd','.py']:characters.update(path.read_text(encoding='utf-8'))
characters.update('東萬發壹貳參肆伍陸柒捌玖→×·…—')
for source,name,weight in [('NotoSansSC','NotoSansSC',600),('NotoSansSC','NotoSansSC-Bold',700),('NotoSerifSC','NotoSerifSC',600)]:
    f=TTFont(ROOT/'tmp'/f'{source}.ttf')
    instantiateVariableFont(f,{'wght':weight},inplace=True)
    options=subset.Options();options.layout_features=['*'];options.recalc_timestamp=False
    sub=subset.Subsetter(options=options);sub.populate(unicodes=sorted(ord(c) for c in characters));sub.subset(f)
    f.save(ROOT/'assets'/'fonts'/f'{name}.ttf')
    print('Static font subset:',name,weight,flush=True)
