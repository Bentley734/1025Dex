"""Build self-contained offline guides from the exact 1.2.14 Lua policy."""
import csv
import json
import os
import sys
import zipfile
from pathlib import Path

workspace=Path(__file__).resolve().parents[2]
root=workspace/'1025Dex'
sys.path.insert(0,str(workspace/'.tools/lua-test'))
from lupa.lua53 import LuaRuntime
os.chdir(root)
out=workspace/'Encounter-Guides-v1.2.14'
out.mkdir(exist_ok=True)
lua_source='''
local function d(n)return dofile('encounters/'..n..'.lua')end
local P=d('policy');local r=d('roster');local l=d('locations')
for _,loc in ipairs(d('hoenn_locations'))do l[#l+1]=loc end
local source=d('native');local native={}
for map,rows in pairs(source[edition])do native[map]=rows end
local rs=game=='ruby'
if rs then
 for _,loc in ipairs(l)do if loc.hoenn then for _,terrain in ipairs({'land','water','fishing','rocks'})do if loc[terrain] then loc[terrain].native=nil end end end end
 for map,rows in pairs(source.ruby)do native[map:gsub('^RU_','EM_')]=rows end
else for map,rows in pairs(source.emerald)do native[map]=rows end end
l=d('native_profiles').prepare(l,native)
local channels=rs and {} or d('campaign_terrains')
for map,rows in pairs(native)do local k=map:gsub('[^%w]',''):upper();channels[k]={};for terrain in pairs(rows)do channels[k][terrain]=true end end
local p=P.new(r,l,nil,nil,function()return campaign end,d('campaign'),channels)
local rows={}
for _,base in ipairs(l)do
 if campaign or ((game=='emerald' or rs)==not not base.hoenn) then
  local valid=channels[base.map:gsub('[^%w]',''):upper()]
  for _,terrain in ipairs({'land','water','fishing','rocks'})do
   if valid and valid[terrain]then
    for choice=1,17 do
     local pool,loc=p:pool(base.map,choice,terrain,{postgame=true})
     for _,group in ipairs({'common','rare','featured','special','ultra'})do
      for _,mon in ipairs(pool[group])do
       local lo,hi=math.min(loc.hi,math.max(loc.lo,mon.gate or 1)),loc.hi
       local canon=loc.native and type(loc.native[mon.id])=='table'
       if canon then lo,hi=loc.native[mon.id][1],loc.native[mon.id][2] end
       if mon.special then lo,hi=P.specialLevelRange(mon) end
       if P.ultraBeasts[mon.id]then lo,hi=P.ultraLevelRange(mon,loc,pool.ultraEndgame) end
       local weight=0
       if pool.residentSlots then
        lo,hi=nil,nil
        for _,slot in ipairs(pool.residentSlots)do if slot[1]==mon.id then
         lo=math.min(lo or slot[2],slot[2]);hi=math.max(hi or slot[2],slot[2]);weight=weight+slot[3]
        end end
       end
       rows[#rows+1]={game=base.hoenn and (rs and 'ruby' or 'emerald') or edition,map=rs and base.map:gsub('^EM_','RU_') or base.map,
         region=base.hoenn and 'Hoenn' or 'Kanto',id=mon.id,name=mon.name,gen=mon.gen,
         terrain=terrain,tier=group,lo=lo,hi=hi,canon=not not canon,
         league=group=='special' or group=='ultra',choice=choice,
         weight=weight,ultraChance=pool.ultraChance or 0}
      end
     end
    end
   end
  end
 end
end
return rows
'''

def export(game,edition,campaign):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().game=game
    lua.globals().edition=edition
    lua.globals().campaign=campaign
    result=lua.execute(lua_source)
    merged={}
    for _,entry in result.items():
        row=dict(entry.items())
        choice=row.pop('choice')
        key=(row['game'],row['map'],row['terrain'],row['id'],row['tier'])
        if key not in merged:
            row['mask']=0
            merged[key]=row
        merged[key]['mask'] |= 1 << (choice-1)
    return sorted(merged.values(),key=lambda r:(r['region'],r['map'],r['terrain'],r['id'],r['tier']))

standalone_fr=export('firered','firered',False)
standalone_lg=export('leafgreen','leafgreen',False)
standalone_em=export('emerald','firered',False)
standalone_ru=export('ruby','firered',False)
combined_fr=export('firered','firered',True)
combined_lg=export('leafgreen','leafgreen',True)
# The current Emerald production entry point builds its atlas with FireRed
# metadata. Match that actual Hoenn output for either linked Kanto edition.
combined_lg=[r for r in combined_lg if r['region']=='Kanto']+[dict(r) for r in combined_fr if r['region']=='Hoenn']
for edition,entries in [('firered',combined_fr),('leafgreen',combined_lg)]:
    for entry in entries: entry['edition']=edition

template=(root/'tools/encounter_guide_template.html').read_text(encoding='utf-8')
guides=[('FR-LG','FireRed / LeafGreen','Standalone 1025Dex encounter pools',standalone_fr+standalone_lg),
        ('Emerald','Emerald','Standalone 1025Dex encounter pools',standalone_em),
        ('Ruby','Ruby','Ruby native tables and added habitats; Sapphire uses its own imported cartridge tables',standalone_ru),
        ('Hoennto','Hoennto','Combined Kanto + Hoenn campaign pools',combined_fr+combined_lg)]
report=[]
for slug,title,subtitle,entries in guides:
    payload=json.dumps({'kind':slug,'rows':entries},separators=(',',':'),ensure_ascii=False).replace('</','<\\/')
    html=template.replace('@@TITLE@@',title).replace('@@SUBTITLE@@',subtitle).replace('@@DATA@@',payload)
    target=out/f'{slug}-Encounter-Guide-v1.2.14.html'
    target.write_text(html,encoding='utf-8')
    fields=['edition','game','region','map','id','name','gen','terrain','tier','lo','hi','canon','league','weight','ultraChance','mask']
    with (out/f'{slug}-Encounters-v1.2.14.csv').open('w',newline='',encoding='utf-8') as file:
        writer=csv.DictWriter(file,fieldnames=fields)
        writer.writeheader();writer.writerows(entries)
    assert '@@' not in html
    assert all(1<=r['lo']<=r['hi']<=100 and r['mask']>0 for r in entries)
    if slug in ['FR-LG','Hoennto']:
        for version in ['firered','leafgreen']:
            assert any(r['id']==39 and r['map']=='FR_ROUTE_3' and r['game']==version and r['canon'] for r in entries)
    if slug in ['Emerald','Hoennto']:
        assert any(r['id']==349 and r['map']=='EM_ROUTE119' and r['terrain']=='fishing' and r['canon'] for r in entries)
    if slug=='Hoennto':
        for version in ['firered','leafgreen']:
            ids={r['id'] for r in entries if r['edition']==version and r['mask'] & (1<<16)}
            missing=set(range(1,1026))-ids
            assert missing==set(), (version,missing)
    report.append(f'{title}: {len(entries):,} distinct area/channel/species/tier rows; all 17 generation choices encoded.')
(out/'README.txt').write_text('1025Dex 1.2.14 offline encounter guides\n\nOpen any HTML file in a browser. No internet connection or installation is required.\nFR/LG and Emerald show standalone pools. Hoennto shows the combined campaign; select the linked Kanto edition.\n\nFilters include search, exact area, encounter method, game/region, WILD GENS selection, League clear and canon residents. CSV download exports the filtered view.\n\nLevels are candidate ranges, not a guarantee for every rod or native encounter roll. Fishing/Rock Smash also use the rolled native level to filter candidates. Rare/featured/special/Ultra labels are shared selection tiers, not per-species percentages. Diglett and Dugtrio have their fixed 95%/5% distribution.\nNative scripted encounters, gifts, trades and roamers are outside these replacement pools. Native area access still follows story progression.\n\nCSV mask column uses bit 0 for GEN 1 through bit 16 for GEN 1-9, in the selector order shown by the guide.\n\n'+ '\n'.join(report)+'\n',encoding='utf-8')
readme=out/'README.txt'
readme.write_text(readme.read_text(encoding='utf-8')+'\nFireRed + Emerald and LeafGreen + Emerald both cover all 1,025 species. The all-games companion explains R/B/Y, G/S/C and Ruby/Sapphire support and Hoennto travel.\n',encoding='utf-8')
exec((root/'tools/build_all_games_companion.py').read_text(encoding='utf-8'))
archive=workspace/'Encounter-Guides-v1.2.14.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for file in sorted(out.iterdir()): z.write(file,file.name)
with zipfile.ZipFile(archive) as z: assert z.testzip() is None
print('\n'.join(report))
print(archive)
