"""Generate localized emissive LED textures from the bundled model atlases.

Requires Pillow with DDS/DXT5 encoding. Originals remain unchanged.
LED positions are atlas pixels at 512x512 reference size, not world offsets.
"""
from pathlib import Path
import struct, io
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'materials/gemu/power'
SPECS={'snes':('snes/snes',68,292,1.8,(255,55,35)),
       'nes':('nes/nes',37,105,5,(255,45,25)),
       'genesis':('genesis/genesis',352,440,1.8,(75,255,70)),
       'gb':('gameboy/gameboy',287,198,2,(255,45,25)),
       'gbc':('gameboy/gameboy_color',292,213,2,(255,45,25)),
       'gba':('gameboy/gba',396,319,2,(75,255,70))}

def read_vtf(path):
    b=path.read_bytes();w,h=struct.unpack_from('<HH',b,16)
    fmt=struct.unpack_from('<I',b,52)[0]
    assert fmt in (13,15)
    size=max(1,(w+3)//4)*max(1,(h+3)//4)*(8 if fmt==13 else 16)
    return Image.frombytes('RGBA',(w,h),b[-size:],'bcn',(1 if fmt==13 else 3,'DXT1' if fmt==13 else 'DXT5'))

def write_vtf(im,path):
    dds=io.BytesIO();im.save(dds,format='DDS',pixel_format='DXT5')
    payload=dds.getvalue()[128:]
    header=bytearray(80)
    struct.pack_into('<4sIIIHHIHH',header,0,b'VTF\0',7,2,80,im.width,im.height,0x2300,1,0)
    struct.pack_into('<f',header,48,1.0)
    struct.pack_into('<IBI',header,52,15,1,0xffffffff)
    struct.pack_into('<H',header,63,1)
    path.write_bytes(header+payload)

def generate():
    OUT.mkdir(parents=True,exist_ok=True)
    for id,(source,x,y,radius,color) in SPECS.items():
        im=read_vtf(ROOT/'materials/models/unconid'/(source+'.vtf'))
        mask=Image.new('RGBA',im.size,(0,0,0,255))
        sx,sy=im.width/512,im.height/512
        bounds=((x-radius)*sx,(y-radius)*sy,(x+radius)*sx,(y+radius)*sy)
        ImageDraw.Draw(im).ellipse(bounds,fill=color+(255,))
        ImageDraw.Draw(mask).ellipse(bounds,fill=(255,255,255,255))
        write_vtf(im,OUT/(id+'_on.vtf'))
        write_vtf(mask.resize((512,512),Image.Resampling.LANCZOS),OUT/(id+'_mask.vtf'))
    print('Generated six localized power LED textures and masks.')
if __name__=='__main__': generate()
