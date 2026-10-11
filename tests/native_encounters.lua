local root,game=arg[1],arg[2]
local function d(name)return assert(loadfile(root..'/encounters/'..name..'.lua'))()end
local P,r,l=d('policy'),d('roster'),d('locations')
for _,loc in ipairs(d('hoenn_locations'))do l[#l+1]=loc end
local source=d('native');local native={}
for map,rows in pairs(source[game=='leafgreen' and 'leafgreen' or 'firered'])do native[map]=rows end
for map,rows in pairs(source.emerald)do native[map]=rows end
l=d('native_profiles').prepare(l,native)
local channels=d('campaign_terrains')
for map,rows in pairs(native)do
 local key=map:gsub('[^%w]',''):upper();channels[key]={}
 for terrain in pairs(rows)do channels[key][terrain]=true end
end
local p=P.new(r,l,math.random,nil,function()return true end,d('campaign'),channels)
local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
local function contains(pool,id)
 for _,group in ipairs({'common','rare','featured','special','ultra'})do
  for _,mon in ipairs(pool[group])do if mon.id==id then return true end end
 end
 return false
end
for map,terrains in pairs(native)do for terrain,rows in pairs(terrains)do
 for choice=1,17 do for _,campaign in ipairs({true,false})do
  local pool,loc=p:pool(map,choice,terrain,{campaign=campaign,postgame=false})
  check(loc~=nil,'missing map '..map)
  for id in pairs(rows)do
   if id>=P.choices[choice].first and id<=P.choices[choice].last then
    check(contains(pool,id),game..' missing canon '..map..':'..terrain..':'..id)
   end
  end
  if not pool.residentSlots then
   for _,group in ipairs({'common','rare'})do for _,mon in ipairs(pool[group])do
    check(rows[mon.id] or (P.allows(mon,terrain) and P.habitatAllows(mon,loc,terrain)),
      'habitat mismatch '..map..':'..terrain..':'..mon.id)
   end end
  end
 end end
end end
check(not P.allows(r[962],'fishing'),'Bombirdier is not a fishing encounter')
if game~='emerald' then
 check(contains(p:pool('FR_ROUTE_3',17,'land'),39),'Route 3 Jigglypuff')
 check(contains(p:pool('FR_VIRIDIAN_FOREST',17,'land'),25),'Viridian Pikachu')
 check(not contains(p:pool('FR_MT_MOON_1F',17,'land'),129),'no land Magikarp')
 local expected=game=='firered' and 43 or 69
 local absent=game=='firered' and 69 or 43
 check(contains(p:pool('FR_ROUTE_24',17,'land'),expected),'version native')
 check(not native.FR_ROUTE_24.land[absent],'version data distinguished')
end
local seen={}
for _,loc in ipairs(l)do for _,terrain in ipairs({'land','water','fishing','rocks'})do
 local allowed=channels[loc.map:gsub('[^%w]',''):upper()]
 if allowed and allowed[terrain]then
  local pool=p:pool(loc.map,17,terrain,{postgame=true})
  for _,group in ipairs({'common','rare','featured','special','ultra'})do for _,mon in ipairs(pool[group])do seen[mon.id]=true end end
 end
end end
local missing={};for _,mon in ipairs(r)do if not seen[mon.id]then missing[#missing+1]=mon.id end end
check(#missing==0,'coverage missing '..table.concat(missing,','))
check(contains(p:pool('EM_ROUTE119',17,'fishing'),349),'Route 119 Feebas')
-- Exercise the production API consumed by DexNav and WildFollowers, including
-- version selection, all four channels, native levels and encounter sampling.
package.loaded['src.core.GameVersion']={generation=function()return 3 end,get=function()return game end}
package.loaded['src.core.game3.runtime']={getSession=function()return {engineOptions={fireredGenEncounterPool=17}}end}
package.loaded['src.core.game3.options']={block=function(o)return o end}
local names={};for _,mon in ipairs(r)do names[mon.name]=mon.id end
package.loaded['src.core.game3.pokemon']={speciesFromName=function(n)return names[n]end,keyName=function(id)return r[id].name end}
package.loaded['src.import.gba.map_catalog']={resolve=function(n)return n end}
package.loaded['src.core.game3.encounters']={tableFor=function(map)
 local out={};for terrain in pairs(native[map] or {})do out[terrain]={slots={}} end;return out
end}
package.loaded['src.core.game3.battle_bridge']={}
package.loaded['src.core.game3.profile']={forSession=function()return {id=game}end}
package.loaded['src.core.game3.constants']={of=function()return {require=function()return 0x864 end}end}
package.loaded['src.core.game3.scripting.flags']={getFlag=function()return false end}
package.loaded['src.core.game3.scripting.space']={}
local mod={exports={},find=function()return {}end,
 read=function(_,path)local file=assert(io.open(root..'/encounters/'..path));local text=file:read('*a');file:close();return text end,
 log={info=function()end,warn=function()end}}
assert(loadfile(root..'/encounters/main.lua'))()(mod)
math.randomseed(1729)
local caught={}
for map,terrains in pairs(native)do
 local header=mod.exports.dexnavEncounters(map)
 for terrain,rows in pairs(terrains)do
  local slots={};for _,slot in ipairs(header[terrain].slots)do slots[slot.species]=slot end
  for id,range in pairs(rows)do
   check(slots[id]~=nil,'public missing '..map..':'..terrain..':'..id)
   check(slots[id].minLevel==range[1] and slots[id].maxLevel==range[2],'public native levels '..id)
  end
  for i=1,60 do
   local id,_,level=mod.exports.chooseWildEncounter(map,terrain,20)
   if id then
    if rows[id] then check(level>=rows[id][1] and level<=rows[id][2],'chosen native level') end
    if map=='FR_ROUTE_3' then caught[id]=true end
   end
  end
 end
end
if game~='emerald' then check(caught[39],'Jigglypuff sampled through live API') end
print('PASS '..game..' native/habitat checks '..checks)
