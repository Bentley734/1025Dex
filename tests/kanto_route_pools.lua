local root=arg[1] or '.'
local function d(p)return assert(loadfile(root..'/encounters/'..p))()end
local P=d('policy.lua');local roster=d('roster.lua');local locations=d('locations.lua')
for _,l in ipairs(d('hoenn_locations.lua'))do locations[#locations+1]=l end
local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
for _,campaign in ipairs({false,true})do
 local policy=P.new(roster,locations,function(a,b)return b and a or 1 end,nil,function()return campaign end,d('campaign.lua'),d('campaign_terrains.lua'))
 for _,route in ipairs({4,9,10,11,22})do for choice=1,17 do for _,prefix in ipairs({'FR_','LG_'})do
  local map=prefix..'ROUTE_'..route
  local pool,loc=policy:pool(map,choice,'land',{postgame=false})
  check(#pool.common+#pool.rare>0,'empty '..map..' choice '..choice..' campaign '..tostring(campaign))
  for _,group in ipairs({'common','rare'})do for _,m in ipairs(pool[group])do
   check(m.id>=P.choices[choice].first and m.id<=P.choices[choice].last,'generation')
   check(P.allows(m,'land'),'aquatic on land');check(m.gate<=loc.hi,'level gate')
   check(not m.special and not P.ultraBeasts[m.id],'early special')
   if loc.hi<=9 then check(m.stage==1 and group=='common','early rarity')end
  end end
  local mon,level=policy:choose(map,choice,14,'land',{postgame=false})
  check(mon and level>=loc.lo and level<=loc.hi,'visible/battle selection')
 end end end
 check(policy:location('FR_ROUTE_110')==nil,'unknown route must stay unknown')
end
print('Kanto route pool checks',checks)

-- Exercise the actual public APIs used by DexNav and visible wilds.
local rng=function(a,b)return b and a or 1 end
package.loaded['src.core.game3.profile']={forSession=function()return {id='firered'}end}
package.loaded['src.core.game3.constants']={of=function()return {require=function()return 0x864 end}end}
package.loaded['src.core.game3.scripting.flags']={getFlag=function()return false end}
package.loaded['src.core.game3.scripting.space']={}
local session={engineOptions={fireredGenEncounterPool=17}}
local names={};for _,m in ipairs(roster)do names[m.name]=m.id end
package.loaded['src.core.GameVersion']={generation=function()return 3 end}
package.loaded['src.core.game3.runtime']={getSession=function()return session end}
package.loaded['src.core.game3.options']={block=function(o)return o end}
package.loaded['src.core.game3.pokemon']={speciesFromName=function(n)return names[n]end,keyName=function(n)return roster[n].name end,_speciesMeta={}}
package.loaded['src.import.gba.map_catalog']={resolve=function(n)return n end}
local Enc={tableFor=function()return {land={slots={{species=50,minLevel=15,maxLevel=22}}}}end,
 onStep=function(map)return {species=50,level=30}end}
package.loaded['src.core.game3.encounters']=Enc
local Bridge={start=function(_,_,foe)return foe end};package.loaded['src.core.game3.battle_bridge']=Bridge
local mod={exports={},read=function(_,p)local f=assert(io.open(root..'/encounters/'..p));local s=f:read('*a');f:close();return s end,log={warn=function()end,info=function()end}}
local random=math.random;math.random=rng
assert(loadfile(root..'/encounters/main.lua'))()(mod)

for _,route in ipairs({4,9,10,11,22})do for choice=1,17 do
 session.engineOptions.fireredGenEncounterPool=choice
 local map='FR_ROUTE_'..route
 local record=mod.exports.dexnavEncounters(map)
 check(record and record.land and #record.land.slots>0,'DexNav public pool')
 local ids={};for _,slot in ipairs(record.land.slots)do ids[slot.species]=true end
 local nat,species,level=mod.exports.chooseWildEncounter(map,'land',14)
 check(nat and ids[species],'visible wild belongs to DexNav pool')
 local foe=Enc.onStep(map,'land');local result=Bridge.start(mod,{},foe,{wild=true})
 check(ids[result.species],'battle belongs to DexNav pool')
end end
math.random=random
print('Route public API checks passed',checks)
