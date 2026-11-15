"""Offline preview of shipping ring masks and Lua layout; not a game capture."""
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/python'))
from lupa.lua54 import LuaRuntime
from PIL import Image,ImageDraw,ImageFont,ImageChops

lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path=... .. '/?.lua;' .. package.path",(ROOT/'mods/VerdantStamina/Scripts').as_posix())
core=lua.eval("require('core')")[0];config=lua.eval("require('config')")[0]
AA=3
im=Image.new('RGBA',(1250*AA,420*AA),'#20241f')
font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',16*AA)
small=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',12*AA)
assets=ROOT/'mods/VerdantStamina/Assets'

def rgba(c):
    def encode(v):return round(255*(12.92*v if v<=0.0031308 else 1.055*v**(1/2.4)-0.055))
    return tuple(encode(c[k]) for k in ('R','G','B'))+(round(255*c.A),)

def arc(ring,layer,fraction,color,cx,cy,scale):
    scale*=config.ui_scale
    radius=ring.radius+ring.thickness/2+1
    size=round(radius*2*scale*AA)
    brush=Image.open(assets/f'ring-{ring.index}-{layer}.png').resize((size,size),Image.Resampling.LANCZOS)
    mask=brush.getchannel('A')
    sector=Image.new('L',(size,size),0)
    if fraction>=1:sector.paste(255,(0,0,size,size))
    elif fraction>0:ImageDraw.Draw(sector).pieslice((0,0,size-1,size-1),-90,-90+fraction*360,fill=255)
    alpha=ImageChops.multiply(mask,sector)
    rgb=rgba(color)
    if rgb[3]!=255:alpha=alpha.point(lambda x:round(x*rgb[3]/255))
    paint=ImageChops.multiply(Image.new('RGB',(size,size),rgb[:3]),brush.convert('RGB')).convert('RGBA')
    paint.putalpha(alpha)
    im.alpha_composite(paint,(round(cx*AA-size/2),round(cy*AA-size/2)))

cases=[('БАЗА',150,150,150),('ПРОКАЧКА',203.36,203.36,203.36),
       ('С КОФЕ',290.57,290.57,203.36),('ПЛОД И КОФЕ',612.45,612.45,406.55),
       ('ЖЁЛТЫЙ ПОТРАЧЕН',350,612.45,406.55)]
for col,(title,current,maximum,permanent) in enumerate(cases):
    midpoint=125+col*250
    draw=ImageDraw.Draw(im)
    draw.text(((midpoint-104)*AA,20*AA),title,font=font,fill='#d5dccd')
    draw.rectangle(((midpoint-112)*AA,292*AA,(midpoint+112)*AA,402*AA),fill='#a18b6d')
    sources=lua.table_from({'permanent_maximum':permanent,'temporary_maximum':maximum-permanent})
    layout=core.layout(maximum,config,sources)
    left=min(layout[i].x-(layout[i].ring.radius+layout[i].ring.thickness/2)*layout[i].scale for i in range(1,len(layout)+1))
    right=max(layout[i].x+(layout[i].ring.radius+layout[i].ring.thickness/2)*layout[i].scale for i in range(1,len(layout)+1))
    for cy,scale in ((152,2.1),(348,1)):
        cx=midpoint-(left+right)*scale/2
        for i in range(1,len(layout)+1):
            item=layout[i];ring=item.ring
            shown=max(0,current-permanent) if item.kind=='temporary' else min(current,permanent)
            color=config.temporary_color if item.kind=='temporary' else core.tint(core.sample(None,current,maximum,0,config),config)
            arc(ring,'track',ring.available/ring.capacity,config.background_color,cx+item.x*scale,cy+item.y*scale,scale*item.scale)
            fill='fill' if config.surface_style=='flat' else config.surface_style
            arc(ring,fill,core.fill(ring,shown),color,cx+item.x*scale,cy+item.y*scale,scale*item.scale)
    ImageDraw.Draw(im).text(((midpoint-104)*AA,245*AA),f'{current:g} / {maximum:g}',font=small,fill='#aebca6')
    ImageDraw.Draw(im).text(((midpoint-104)*AA,266*AA),f'{permanent:g} + {maximum-permanent:g}',font=small,fill='#aebca6')
im=im.convert('RGB').resize((1250,420),Image.Resampling.LANCZOS)
out=ROOT/'research/stamina-source-preview.png';im.save(out)
print(out)
