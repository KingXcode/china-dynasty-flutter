#!/usr/bin/env python3
"""Generate code-native seal icons for platform scaffolds (Pillow required)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parent.parent
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def icon(path,size):
 im=Image.new('RGB',(size,size),'#faf8f1');d=ImageDraw.Draw(im)
 inset=round(size*.12);d.rounded_rectangle((inset,inset,size-inset,size-inset),radius=round(size*.18),fill='#a4543b')
 f=ImageFont.truetype(font,round(size*.52),index=2)
 d.text((size/2,size/2),'华',font=f,fill='white',anchor='mm')
 im.save(path)
for p in (root/'web').rglob('*.png'):
 with Image.open(p) as im:size=im.width
 icon(p,size)
for p in (root/'android/app/src/main/res').glob('mipmap-*/ic_launcher.png'):
 with Image.open(p) as im:size=im.width
 icon(p,size)
for p in (root/'ios/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png'):
 with Image.open(p) as im:size=im.width
 icon(p,size)
print('Generated native seal icons')
