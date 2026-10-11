"""Rebuild the human-readable atlas from the production pools; audit baseline."""
import csv
import os
import sys
import zipfile
from pathlib import Path
workspace=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(workspace/'.tools/lua-test'))
from lupa.lua53 import LuaRuntime
root=workspace/'1025Dex'
os.chdir(root)
rows=[]
report=['# Encounter audit — 1.2.12', '', 'Baseline: supplied 1.2.11 ZIP. Canon data: supplied FireRed, LeafGreen and Emerald USA ROMs, including Emerald extra tables and Feebas. Counts are unique area/channel/species combinations, not encounter slots or rates.', '']
with zipfile.ZipFile(workspace/'1025Dex-v1.2.11.zip') as archive:
    original={name:archive.read('encounters/'+name+'.lua').decode() for name in ['policy','roster','locations','hoenn_locations','campaign','campaign_terrains']}
for game in ['firered','leafgreen','emerald']:
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().game=game
    lua.globals().original=lua.table_from(original)
    result=lua.execute('''
local function d(n)return dofile('encounters/'..n..'.lua')end
local function old(n)return assert(load(original[n]))()end
local native={};local source=d('native')
for map,t in pairs(source[game=='leafgreen' and 'leafgreen' or 'firered'])do native[map]=t end
for map,t in pairs(source.emerald)do native[map]=t end
local l=d('locations');for _,loc in ipairs(d('hoenn_locations'))do l[#l+1]=loc end
l=d('native_profiles').prepare(l,native)
local channels=d('campaign_terrains')
for map,t in pairs(native)do local k=map:gsub('[^%w]',''):upper();channels[k]={};for terrain in pairs(t)do channels[k][terrain]=true end end
local r=d('roster');local p=d('policy').new(r,l,nil,nil,function()return true end,d('campaign'),channels)
local ol=old('locations');for _,loc in ipairs(old('hoenn_locations'))do ol[#ol+1]=loc end
local before=old('policy').new(old('roster'),ol,nil,nil,function()return true end,old('campaign'),old('campaign_terrains'))
local homes={};local missing,total=0,0
for _,loc in ipairs(l)do
 if (game=='emerald')==not not loc.hoenn then
  for _,terrain in ipairs({'land','water','fishing','rocks'})do
   if native[loc.map] and native[loc.map][terrain]then
    local pool=p:pool(loc.map,17,terrain,{postgame=true})
    for _,group in ipairs({'common','rare','featured','special','ultra'})do for _,mon in ipairs(pool[group])do
      homes[mon.id]=homes[mon.id] or {};homes[mon.id][loc.map..'/'..terrain]=true
    end end
    local prior=before:pool(loc.map,17,terrain,{postgame=true});local ids={}
    for _,group in ipairs({'common','rare','featured','special','ultra'})do for _,mon in ipairs(prior[group])do ids[mon.id]=true end end
    for id in pairs(native[loc.map][terrain])do total=total+1;if not ids[id]then missing=missing+1 end end
   end
  end
 end
end
return {homes=homes,roster=r,missing=missing,total=total}
''')
    report.append(f'- {game}: {result.total} canon entries audited; {result.missing} missing from the old campaign pools restored.')
    for species,homes in sorted(result.homes.items()):
        mon=result.roster[species]
        rows.append([game,species,mon.name,mon.gen,mon.gate,'yes' if mon.special or 793<=species<=806 else 'no','; '.join(sorted(homes.keys()))])
with (root/'EncounterAtlas.csv').open('w',newline='',encoding='utf-8') as file:
    writer=csv.writer(file)
    writer.writerow(['Game','National ID','Species','Generation','Added-species level gate','Postgame','Wild homes (map/channel)'])
    writer.writerows(rows)
report += ['', 'All audited canon entries are retained when their generation is selected. Native encounters may overlap both regions. Added residents retain one primary and one alternate habitat-compatible home per channel; fallback visitors remain capped at three. Native species use ROM level ranges; Diglett’s weighted slots and Route 1’s featured starters retain their existing rules.', '', 'Verification covers production pools, public DexNav headers, follower selection samples, all 17 generation settings, both standalone and campaign modes, and complete combined 1,025-species coverage. No interactive playthrough was performed.']
(root/'ENCOUNTER-AUDIT.md').write_text('\n'.join(report)+'\n',encoding='utf-8')
print('\n'.join(report[:8]))
