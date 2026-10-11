"""Convert the supplied indexed Emerald Expansion art to runtime RGBA sheets."""
from pathlib import Path
import re, json, sys
from PIL import Image

root = Path(__file__).resolve().parents[2]
source = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'Emerald Expansion Sprites'
dest = root / '1025Dex/sprites'
norm = lambda s: re.sub('[^A-Z0-9]', '', s.upper())
mapping = dict(re.findall(r'\["([^"]+)"\] = "([^"]+)"', (dest/'data/dbk_data.lua').read_text().split('  stems =')[0]))
overrides={'DARMANITAN_GALAR_STANDARD':'DARMANITAN_2','DARMANITAN_GALAR_ZEN':'DARMANITAN_3'}
mapping.update(overrides)
directories = {norm('_'.join(p.relative_to(source).parts)):p for p in source.rglob('*') if p.is_dir()}
directories.update({norm(p.name):p for p in source.iterdir() if p.is_dir()})
aliases = {'ALOLAN':'ALOLA','GALARIAN':'GALAR','HISUIAN':'HISUI','PALDEAN':'PALDEA',
           'FEMALE':'F','ICE_RIDER':'ICE','SHADOW_RIDER':'SHADOW','NOICE':'NOICE_FACE',
           'THREE_SEGMENT':'THREE_SEGMENT','ORIGINAL_COLOR':'ORIGINAL','ASH':'ASH'}
explicit = {
    'EEVEE_STARTER':'eevee/partner', 'GRENINJA_BATTLE_BOND':'greninja/ash',
    'MAGEARNA_ORIGINAL':'magearna/original_color', 'MAGEARNA_ORIGINAL_MEGA':'magearna/original_color/mega',
    'MAUSHOLD_FAMILY_OF_THREE':'maushold', 'MEOWSTIC_MALE_MEGA':'meowstic/mega',
    'MEOWSTIC_FEMALE_MEGA':'meowstic/f/mega', 'NECROZMA_DAWN':'necrozma/dawn_wings',
    'NECROZMA_DUSK':'necrozma/dusk_mane', 'TATSUGIRI_CURLY_MEGA':'tatsugiri/mega',
    'TOXTRICITY_AMPED_GMAX':'toxtricity/gmax', 'TOXTRICITY_LOW_KEY_GMAX':'toxtricity/gmax',
    'ZACIAN_CROWNED':'zacian/crowned_sword', 'ZAMAZENTA_CROWNED':'zamazenta/crowned_shield',
    'ZYGARDE_10':'zygarde/10_percent', 'ZYGARDE_10_POWER_CONSTRUCT':'zygarde/10_percent',
    'ZYGARDE_50_POWER_CONSTRUCT':'zygarde', 'MAROWAK_TOTEM':'marowak/alola',
    'RATICATE_TOTEM_ALOLA':'raticate/alola', 'MIMIKYU_TOTEM_BUSTED':'mimikyu/busted',
    'MIMIKYU_TOTEM_DISGUISED':'mimikyu',
}
for drive in ('BURN','CHILL','DOUSE','SHOCK'): explicit['GENESECT_'+drive]='genesect/'+drive.lower()+'_drive'
for cap in ('ALOLA','HOENN','KALOS','ORIGINAL','PARTNER','SINNOH','UNOVA','WORLD'): explicit['PIKACHU_'+cap+'_CAP']='pikachu/'+cap.lower()
for mask in ('CORNERSTONE','HEARTHFLAME','WELLSPRING'): explicit['OGERPON_'+mask+'_MASK']='ogerpon/'+mask.lower()
for color in ('BLUE','WHITE','YELLOW'): explicit['SQUAWKABILLY_'+color+'_PLUMAGE']='squawkabilly/'+color.lower()
for breed in ('AQUA','BLAZE','COMBAT'): explicit['TAUROS_PALDEA_'+breed+'_BREED']='tauros/paldea_'+breed.lower()
files = {k:{} for k in ('front','front_shiny','back','back_shiny')}
missing=[]; report=[]; outputs={}

def palette(path):
    lines=path.read_text().splitlines()
    assert lines[0]=='JASC-PAL', path
    count=int(lines[2]); colors=[tuple(map(int,s.split())) for s in lines[3:3+count]]
    assert len(colors)==count
    return colors

def convert(path, pal):
    im=Image.open(path); assert im.mode=='P', path
    colors=palette(pal)
    out=Image.new('RGBA',im.size)
    out.putdata([(*colors[i],0 if i==0 else 255) for i in im.getdata()])
    assert im.width==64 and im.height%64==0, (path,im.size)
    strip=Image.new('RGBA',(im.height,64))
    for i in range(im.height//64): strip.paste(out.crop((0,i*64,64,(i+1)*64)),(i*64,0))
    assert strip.getbbox(),path
    return strip

for species,stem in sorted(mapping.items()):
    key=species
    for a,b in aliases.items(): key=key.replace(a,b)
    folder=source/explicit[species] if species in explicit else directories.get(norm(key))
    minior = re.fullmatch(r'MINIOR_(BLUE|GREEN|INDIGO|ORANGE|RED|VIOLET|YELLOW)(_METEOR)?',species)
    if minior: folder=source/('minior' if minior[2] else 'minior/core')
    if folder is not None and not folder.is_dir(): folder=None
    if folder is None:
        missing.append(species); continue
    for female in (False,True):
        suffix='f' if female else ''
        front=next((folder/n for n in ('anim_front'+suffix+'.png','front'+suffix+'.png') if (folder/n).is_file()),None)
        back=folder/('back'+suffix+'.png')
        # Some gender variants share their pixel indices and change only palette.
        if female and (folder/'normalf.pal').is_file():
            if front is None: front=next((folder/n for n in ('anim_front.png','front.png') if (folder/n).is_file()),None)
            if not back.is_file(): back=folder/'back.png'
        for side,path in (('front',front),('back',back if back.is_file() else None)):
            if path is None: continue
            for shiny in (False,True):
                pal=folder/('shiny.pal' if shiny else 'normal.pal')
                female_pal=folder/('shinyf.pal' if shiny else 'normalf.pal')
                if female and female_pal.is_file(): pal=female_pal
                if minior and not minior[2] and not shiny: pal=folder/minior[1].lower()/'normal.pal'
                if not pal.is_file(): continue
                target=side+('_shiny' if shiny else '')
                name=stem+('_female' if female else '')
                out=convert(path,pal)
                previous=outputs.get((target,name))
                if previous is not None:
                    assert previous.size==out.size and previous.tobytes()==out.tobytes(), ('Ambiguous artwork',species,name)
                    continue
                outputs[target,name]=out
                output=dest/'assets/ee'/target/(name+'.png'); output.parent.mkdir(parents=True,exist_ok=True)
                out.save(output)
                files[target][name]=True
                report.append({'species':species,'stem':name,'folder':target,'source':str(path.relative_to(source)),'palette':str(pal.relative_to(source)),'frames':out.width//64})
lines=['-- Generated by tools/import_ee_sprites.py.','return { species = {']
lines += ['  ['+json.dumps(k)+'] = '+json.dumps(v)+',' for k,v in overrides.items()]
lines += ['}, files = {']
for folder,entries in files.items():
    lines.append('  '+folder+' = {')
    lines += ['    ['+json.dumps(name)+'] = true,' for name in sorted(entries)]
    lines.append('  },')
lines+=['} }']
(dest/'data/ee_data.lua').write_text('\n'.join(lines)+'\n')
(root/'1025Dex/EE-SPRITE-AUDIT.json').write_text(json.dumps({'files':len(report),'missing':missing,'sources':report},indent=2)+'\n')
print('Imported',len(report),'sheets; unmatched species:',missing)
