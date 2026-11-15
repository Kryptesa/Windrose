"""Comparison only. Texture/palette candidates never enter the installed mod."""
from pathlib import Path
import math,random,sys

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/python'))
from PIL import Image,ImageDraw,ImageFont,ImageChops,ImageFilter
from surface_pattern import pattern
from lupa.lua54 import LuaRuntime

lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path=... .. '/?.lua;' .. package.path",(ROOT/'mods/VerdantStamina/Scripts').as_posix())
core=lua.eval("require('core')")[0];config=lua.eval("require('config')")[0]
S=3;W,H=1160,854
canvas=Image.new('RGBA',(W*S,H*S),'#20241f')
fonts={n:ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',n*S) for n in (13,15,18,22)}
assets=ROOT/'mods/VerdantStamina/Assets'
palettes=[('1  Олива','#78AA35'),('2  Морская зелень','#509874'),('3  Латунь','#AD934A')]
styles=[('A  Ровная заливка','flat'),('B  Потёртая краска','paint'),('C  Сухой штрих','hatch')]

def ring(r,layer,fraction,color,kind,cx,cy,scale):
    radius=r.radius+r.thickness/2+1
    n=round(radius*2*scale*S)
    mask=Image.open(assets/f'ring-{r.index}-{layer}.png').getchannel('A').resize((n,n),Image.Resampling.LANCZOS)
    sector=Image.new('L',(n,n),0)
    if fraction>=1:sector.paste(255,(0,0,n,n))
    elif fraction>0:ImageDraw.Draw(sector).pieslice((0,0,n-1,n-1),-90,-90+fraction*360,fill=255)
    mask=ImageChops.multiply(mask,sector)
    paint=Image.new('RGB',(n,n),color)
    if layer=='fill' and r.index==0 and kind!='flat':
        luminance=pattern(n,kind,scale*S)
        paint=ImageChops.multiply(paint,Image.merge('RGB',(luminance,luminance,luminance)))
    paint=paint.convert('RGBA');paint.putalpha(mask)
    canvas.alpha_composite(paint,(round(cx*S-n/2),round(cy*S-n/2)))

draw=ImageDraw.Draw(canvas)
draw.text((24*S,15*S),'Фактура и цвет — варианты для обсуждения',font=fonts[22],fill='#e2e7dc')
draw.text((24*S,49*S),'Одинаковая геометрия. Слева в каждой ячейке — увеличено, справа — игровой размер.',font=fonts[13],fill='#afbaa5')
for col,(title,kind) in enumerate(styles):
    draw.text(((185+col*320)*S,92*S),title,font=fonts[18],fill='#d8dfd0')
for row,(title,color) in enumerate(palettes):
    top=130+row*232
    draw=ImageDraw.Draw(canvas)
    draw.text((22*S,(top+75)*S),title,font=fonts[15],fill='#e2e7dc')
    draw.text((22*S,(top+100)*S),color,font=fonts[13],fill='#9fac97')
    for col,(_,kind) in enumerate(styles):
        left=175+col*320
        draw.rectangle((left*S,top*S,(left+302)*S,(top+212)*S),fill='#a38d6d')
        draw.rectangle(((left+211)*S,top*S,(left+302)*S,(top+212)*S),fill='#343b2d')
        rings=core.rings(450,config)
        for cx,cy,scale in ((left+102,top+96,2.15),(left+257,top+98,1)):
            for i in range(1,len(rings)+1):
                r=rings[i]
                ring(r,'track',r.available/r.capacity,'#273220','flat',cx,cy,scale)
                ring(r,'fill',core.fill(r,365),color,kind,cx,cy,scale)
        draw=ImageDraw.Draw(canvas)
        draw.text(((left+12)*S,(top+183)*S),'База + два внешних кольца',font=fonts[13],fill='#222b1e')
draw=ImageDraw.Draw(canvas)
draw.text((24*S,828*S),'Цвет и фактура пока не установлены. B и C — эскизы по мотивам штрихованного HUD игры.',font=fonts[13],fill='#b6c2ad')
out=ROOT/'research/stamina-texture-options.png'
canvas.convert('RGB').resize((W,H),Image.Resampling.LANCZOS).save(out)
print(out)

if __name__=='__main__':pass
