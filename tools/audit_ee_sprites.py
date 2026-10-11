"""Check every converted pixel and make a visual preview from packaged art."""
from pathlib import Path
import json
from PIL import Image, ImageDraw
root=Path(__file__).resolve().parents[2]
data=json.loads((root/'1025Dex/EE-SPRITE-AUDIT.json').read_text())
source=root/'Emerald Expansion Sprites'
assets=root/'1025Dex/sprites/assets/ee'
for row in data['sources']:
    original=Image.open(source/row['source'])
    out=Image.open(assets/row['folder']/(row['stem']+'.png'))
    colors=[tuple(map(int,line.split())) for line in (source/row['palette']).read_text().splitlines()[3:]]
    assert out.size==(original.height,64) and out.mode=='RGBA'
    op=original.load(); converted=out.load()
    for y in range(original.height):
        for x in range(64):
            index=op[x,y]
            assert converted[(y//64)*64+x,y%64]==(*colors[index],0 if index==0 else 255),(row,x,y)
    assert out.getbbox()
print('PASS',len(data['sources']),'EE sheets: every source pixel, normal/shiny palette, transparency and frame order')
names=['BULBASAUR','CHARIZARD_1','PIKACHU_female','APPLIN','FLAPPLE','HYDRAPPLE','MINIOR_7','OGERPON_2']
canvas=Image.new('RGB',(760,len(names)*154+60),'#20252e');draw=ImageDraw.Draw(canvas)
draw.text((12,12),'EE artwork: front pose 1 / front pose 2 / shiny front / back / shiny back',fill='white')
for row,name in enumerate(names):
    y=60+row*154
    draw.text((8,y+5),name,fill='white')
    for col,(folder,frame) in enumerate([('front',0),('front',1),('front_shiny',0),('back',0),('back_shiny',0)]):
        path=assets/folder/(name+'.png')
        if not path.is_file(): continue
        im=Image.open(path);frame=min(frame,im.width//64-1)
        tile=im.crop((frame*64,0,(frame+1)*64,64)).resize((128,128),Image.Resampling.NEAREST)
        canvas.paste(tile,(100+col*130,y+22),tile)
canvas.save(root/'1025Dex-v1.2.24-EE-preview.png')
