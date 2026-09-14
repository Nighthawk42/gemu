"""Build simple geometric GEMU spawn-menu PNG icons (requires Pillow).

Icons are drawn at 4x resolution and downsampled for clean edges. No model
renderer, game launch, ROM artwork or external image assets are needed.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'materials/gemu/icons'
OUT.mkdir(parents=True, exist_ok=True)
S = 4
COLORS = {'snes':'#aa93df','nes':'#e47474','genesis':'#7ca7da',
          'gba':'#9990e8','gb':'#afbd79','gbc':'#74bdaf','crt':'#82adbc'}

def make(system, kind):
    image=Image.new('RGBA',(256*S,256*S),(0,0,0,0))
    draw=ImageDraw.Draw(image)
    accent=COLORS[system]
    def box(bounds,fill,r=0):
        draw.rounded_rectangle(tuple(int(x*S) for x in bounds),radius=r*S,fill=fill)
    def circle(bounds,fill): draw.ellipse(tuple(x*S for x in bounds),fill=fill)
    def line(points,fill,width=2): draw.line([(x*S,y*S) for x,y in points],fill=fill,width=width*S)
    def text(value,y,size,color):
        try: font=ImageFont.truetype('arialbd.ttf',size*S)
        except OSError: font=ImageFont.load_default(size=size*S)
        draw.text((128*S,y*S),value,font=font,fill=color,anchor='mt')
    def dpad(x,y):
        box((x+7,y,x+17,y+25),'#303946',2)
        box((x,y+7,x+25,y+17),'#303946',2)
    box((4,4,252,252),'#202935',25)
    box((18,18,238,182),'#2b3745',17)
    circle((45,156,211,174),'#1c2530')
    if kind=='cartridge':
        if system=='gba': bounds=(49,65,207,155)
        elif system=='snes': bounds=(40,50,216,158)
        elif system=='genesis': bounds=(47,46,209,158)
        else: bounds=(64,34,192,165)
        x,y,right,bottom=bounds
        shell='#6b7684' if system=='genesis' else '#c7cbd0'
        box(bounds,shell,8)
        box((x+13,y+9,right-13,bottom-24),'#8995a3',5)
        box((x+19,y+15,right-19,bottom-30),accent,3)
        # Unprinted label: a plain inset, with no copied game artwork.
        box((x+26,y+22,right-26,bottom-37),'#dfe4e9',2)
        box((x+25,bottom-17,right-25,bottom-7),'#404b59',2)
        for xx in range(x+29,right-26,8): box((xx,bottom-16,xx+3,bottom-8),'#c6b57b')
        if system=='snes':
            for yy in (77,89,101):
                line([(44,yy),(52,yy)],'#8c97a4',3)
                line([(204,yy),(212,yy)],'#8c97a4',3)
    elif system in ('gb','gbc'):
        box((76,28,180,172),accent if system=='gbc' else '#c7c9c4',12)
        box((86,39,170,106),'#56606b',7)
        box((99,48,158,94),'#aebf87',2)
        dpad(88,118)
        circle((143,120,155,132),'#9c626e')
        circle((158,112,170,124),'#9c626e')
        line([(121,153),(131,150)],'#687280',4)
        line([(137,153),(147,150)],'#687280',4)
    elif system=='gba':
        box((33,65,223,153),accent,24)
        box((81,72,177,144),'#414b5a',7)
        box((90,81,168,133),'#a7c6c4',2)
        dpad(45,96)
        circle((187,107,199,119),'#374453')
        circle((202,94,214,106),'#374453')
    elif system=='crt':
        box((48,35,208,152),'#a4adb7',14)
        box((59,45,197,135),'#394654',8)
        box((66,51,190,128),'#88aab5',10)
        line([(78,66),(78,109)],'#b9d1d7',3)
        box((92,153,164,167),'#88939f',3)
        circle((185,139,191,145),accent)
    elif system=='nes':
        box((39,59,217,156),'#9ba5ae',7)
        box((39,48,217,113),'#d3d7da',6)
        box((60,61,164,103),'#8e99a4',3)
        line([(65,88),(159,88)],'#333e4c',4)
        box((176,51,204,154),'#566272',2)
        box((54,132,78,142),accent,2)
    elif system=='snes':
        box((37,61,219,157),'#a2abb6',12)
        box((42,48,214,132),'#d4d7db',12)
        box((76,64,181,78),'#556171',4)
        box((63,99,98,119),accent,3)
        box((157,99,192,119),accent,3)
        box((59,140,91,150),'#3a4655',3)
        box((165,140,197,150),'#3a4655',3)
    else:
        box((36,58,220,157),'#626d7a',19)
        box((43,48,213,144),'#364251',18)
        circle((92,52,180,129),'#586777')
        box((99,67,181,77),'#222c37',4)
        box((58,112,79,123),accent,3)
        box((86,140,114,150),'#202935',2)
        box((153,140,181,150),'#202935',2)
    text(system.upper(),192,23,'#e7edf3')
    text('CARTRIDGE' if kind=='cartridge' else ('DISPLAY' if system=='crt' else 'HANDHELD' if system in ('gba','gb','gbc') else 'CONSOLE'),221,11,accent)
    image.resize((256,256),Image.Resampling.LANCZOS).save(OUT/(system+'_'+kind+'.png'))

if __name__=='__main__':
    for system in COLORS:
        make(system,'console')
        if system!='crt': make(system,'cartridge')
    print('Generated 13 icons in materials/gemu/icons/.')
