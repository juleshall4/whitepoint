from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math

OUT=Path(__file__).resolve().parent.parent / 'Launch'
OUT.mkdir(exist_ok=True)
W,H=1600,1000
BG='#F5F4F0'; INK='#18272C'; MUTED='#536168'; LINE='#DADFDA'; GREEN='#345C4F'
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
BOLD='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
def font(size,bold=False): return ImageFont.truetype(BOLD if bold else FONT,size)
def text(d,xy,s,size=28,fill=INK,bold=False): d.text(xy,s,font=font(size,bold),fill=fill,stroke_width=0)
def pill(d,x,y,s):
    tw=d.textlength(s,font=font(23)); d.rounded_rectangle((x,y,x+tw+40,y+48),24,fill='#E8EDE6'); text(d,(x+20,y+11),s,23,GREEN); return x+tw+55

def brand(d,dark=False):
    c='#F5F4F0' if dark else INK
    d.ellipse((80,65,124,109),outline=c,width=3)
    d.pieslice((80,65,124,109),90,270,fill=c)
    text(d,(140,66),'White Point',35,c,True)
    text(d,(80,927),'A lightweight menu bar app for macOS',22,'#91A2A4' if dark else MUTED)

def canvas(dark=False):
    im=Image.new('RGB',(W,H),'#17292C' if dark else BG); brand(ImageDraw.Draw(im),dark); return im

def screen(width=630,height=390):
    im=Image.new('RGB',(width,height),'#FAFAF8'); d=ImageDraw.Draw(im)
    d.rectangle((0,0,width,34),fill='#E9ECE8')
    text(d,(20,7),'Notes',15,INK,True)
    d.rectangle((0,34,150,height),fill='#EFF1ED')
    text(d,(20,62),'Library',17,INK,True)
    for i,label in enumerate(['Evening reading','Ideas','Journal']):
        if i==0: d.rounded_rectangle((12,103,137,139),8,fill='#D7E2D8')
        text(d,(20,113+i*53),label,13,INK)
    text(d,(185,64),'A quieter evening',28,INK,True)
    text(d,(185,117),'The same screen, softened.',18,MUTED)
    for i,l in enumerate([360,315,342,230]): d.rounded_rectangle((185,162+i*28,185+l,171+i*28),4,fill='#8E999C')
    for j,c in enumerate(['#B75142','#6B8D65','#4F7595','#C6A04F']): d.rounded_rectangle((185+j*88,304,250+j*88,346),9,fill=c)
    return im

def framed(im,xy,preview,scale=1):
    d=ImageDraw.Draw(im); x,y=xy; ww,hh=preview.size
    d.rounded_rectangle((x-10,y-10,x+ww+10,y+hh+10),20,fill='#CAD1CC')
    im.paste(preview,(x,y))
    d.rounded_rectangle((x-10,y-10,x+ww+10,y+hh+10),20,outline='#BDC7C0',width=2)

def dim(im,factor): return im.point(lambda c: round(c*factor))

# Hero: typography and a simple, accurately named control illustration.
im=canvas(); d=ImageDraw.Draw(im)
text(d,(80,210),'A softer screen.',76,INK,True)
text(d,(80,305),'One simple slider.',76,INK,True)
text(d,(83,430),'Reduce screen intensity evenly.',31,MUTED)
text(d,(83,476),'Inspired by iOS Reduce White Point.',31,MUTED)
x=80
for s in ['Menu bar app','Uniform dimming']: x=pill(d,x,579,s)
text(d,(83,687),'Your shortcut. Your schedule.',30,INK,True)
text(d,(83,738),'Fixed times · Sun events · Follow Night Shift',24,MUTED)
# Stylized control card, rather than a purported screenshot.
d.rounded_rectangle((925,199,1498,811),30,fill='#FFFFFF',outline=LINE,width=2)
d.ellipse((968,242,1012,286),fill=INK); d.pieslice((970,244,1010,284),-90,90,fill='#E1E8DD')
text(d,(1030,246),'White Point',36,INK,True)
text(d,(969,332),'Reduce white point',29,INK,True)
d.rounded_rectangle((1380,336,1450,374),19,fill=GREEN); d.ellipse((1417,341,1445,369),fill='white')
text(d,(969,430),'Intensity',26,MUTED)
text(d,(1362,430),'35%',26,INK,True)
d.rounded_rectangle((970,489,1450,497),4,fill='#D7DDD5')
d.rounded_rectangle((970,489,1138,497),4,fill=GREEN)
d.ellipse((1121,477,1153,509),fill=GREEN)
for y,label,val in [(556,'Shortcut','Choose shortcut'),(625,'Schedule','Follow Night Shift')]:
    text(d,(969,y),label,24,MUTED)
    text(d,(1146,y),val,24,INK,True)
    d.line((969,y+46,1450,y+46),fill=LINE,width=1)
text(d,(970,742),'Control illustration',21,MUTED)
im.save(OUT/'01-white-point-overview.png')

# Uniform comparison: exactly the same source image on both sides.
im=canvas(); d=ImageDraw.Draw(im)
text(d,(80,175),'Same content. Less intensity.',65,INK,True)
text(d,(83,278),'A consistent reduction across whites, colours, and dark tones.',29,MUTED)
a=screen(640,400); b=dim(a,.55)
text(d,(83,367),'Original',27,INK,True); text(d,(873,367),'White Point on',27,INK,True)
framed(im,(85,430),a); framed(im,(875,430),b)
text(d,(83,866),'Illustration of uniform dimming. Actual appearance depends on your display.',22,MUTED)
im.save(OUT/'02-uniform-dimming.png')

# Schedule: simple event diagram with two endpoints and a separate sync option.
im=canvas(True); d=ImageDraw.Draw(im); WHITE='#F5F4F0'; SOFT='#B1C1BE'
text(d,(80,180),'On at sunset.',76,WHITE,True)
text(d,(80,278),'Off at sunrise.',76,WHITE,True)
text(d,(83,403),'Or let White Point follow Night Shift.',33,SOFT)
# Timeline with solar endpoint illustrations.
d.line((195,648,1405,648),fill='#586C6C',width=3)
for cx,label,up in [(250,'Sunset',False),(1350,'Sunrise',True)]:
    d.ellipse((cx-30,578,cx+30,638),outline='#D9C69A',width=4)
    d.rectangle((cx-45,615,cx+45,643),fill='#17292C')
    d.line((cx-47,615,cx+47,615),fill='#D9C69A',width=4)
    d.ellipse((cx-9,639,cx+9,657),fill='#D9C69A')
    text(d,(cx-48,691),label,28,WHITE,True)
text(d,(630,610),'White Point on',30,WHITE,True)
d.rounded_rectangle((530,774,1070,843),20,fill='#294347')
text(d,(559,795),'Fixed times work too: 20:00 → 07:00',25,WHITE)
text(d,(80,877),'Choose on and off independently. Sun schedules use a saved location.',22,SOFT)
im.save(OUT/'03-scheduling.png')
print('Created three 1600 × 1000 PNG product images.')
