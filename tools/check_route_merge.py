"""Check that the route fallback merge leaves canon-aware runtime pools intact."""
import os
import sys
import zipfile
from pathlib import Path
workspace=Path(__file__).resolve().parents[2]
root=workspace/'1025Dex'
sys.path.insert(0,str(workspace/'.tools/lua-test'))
from lupa.lua53 import LuaRuntime
names=['policy','locations','hoenn_locations','native','native_profiles','roster','campaign','campaign_terrains']
with zipfile.ZipFile(workspace/'1025Dex-v1.2.12.zip') as z:
    old={n:z.read('encounters/'+n+'.lua').decode() for n in names}
new={n:(root/'encounters'/f'{n}.lua').read_text() for n in names}
for edition in ['firered','leafgreen']:
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().before=lua.table_from(old)
    lua.globals().after=lua.table_from(new)
    lua.globals().edition=edition
    lua.execute('''
local function build(sources)
 local function d(n)return assert(load(sources[n]))()end
 local l=d('locations');for _,loc in ipairs(d('hoenn_locations'))do l[#l+1]=loc end
 local native={};local sources=d('native')
 for map,rows in pairs(sources[edition])do native[map]=rows end
 for map,rows in pairs(sources.emerald)do native[map]=rows end
 l=d('native_profiles').prepare(l,native)
 local channels=d('campaign_terrains')
 for map,rows in pairs(native)do local k=map:gsub('[^%w]',''):upper();channels[k]={};for terrain in pairs(rows)do channels[k][terrain]=true end end
 return d('policy').new(d('roster'),l,nil,nil,nil,d('campaign'),channels),native
end
local old,native=build(before);local new=build(after);local checks=0
for map,channels in pairs(native)do for terrain in pairs(channels)do
 for choice=1,17 do for _,campaign in ipairs({false,true})do for _,postgame in ipairs({false,true})do
  local context={campaign=campaign,postgame=postgame}
  local a,aloc=old:pool(map,choice,terrain,context);local b,bloc=new:pool(map,choice,terrain,context)
  assert(aloc.lo==bloc.lo and aloc.hi==bloc.hi,'area level changed')
  for _,group in ipairs({'common','rare','featured','special','ultra'})do
   assert(#a[group]==#b[group],map..':'..terrain..':'..group..' count changed')
   for i,mon in ipairs(a[group])do assert(mon.id==b[group][i].id,map..' species/order changed') end
   checks=checks+1
  end
 end end end
end end
print('PASS unchanged canon-aware pools',edition,checks,'group comparisons')
''')
