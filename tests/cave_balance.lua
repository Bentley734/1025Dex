local checks=0
local function eq(a,b,msg)checks=checks+1;assert(a==b,msg..': '..tostring(a)..' ~= '..tostring(b))end
local function data(p)return assert(loadfile(p))()end
local P=data('encounters/policy.lua');local roster=data('encounters/roster.lua');local locs=data('encounters/locations.lua')
for _,l in ipairs(data('encounters/hoenn_locations.lua'))do locs[#locs+1]=l end
local roll=1
local rng=function(a,b)return b and a or math.min(roll,a)end
local policy=P.new(roster,locs,rng)
local moon={{'MT_MOON_1F',7,10},{'MT_MOON_B1F',5,10},{'MT_MOON_B2F',8,12}}
for _,prefix in ipairs({'FR_','LG_'})do
 for choice=1,17 do
  for _,cleared in ipairs({false,true})do
   local pool,loc=policy:pool(prefix..'DIGLETTS_CAVE_B1F',choice,'land',{postgame=cleared})
   eq(#pool.common,1,'one standard resident');eq(pool.common[1].id,50,'Diglett standard')
   eq(#pool.rare,1,'one rare resident');eq(pool.rare[1].id,51,'Dugtrio rare')
   eq(#pool.ultra+#pool.special+#pool.featured,0,'no other cave species')
   local counts={[50]=0,[51]=0};local levels={}
   for r=1,100 do roll=r
    for _,native in ipairs({1,4,20,30,99})do
     local m,level=policy:choose(prefix..'DIGLETTS_CAVE_B1F',choice,native,'land',{postgame=cleared})
     eq(m.id==50 or m.id==51,true,'only native cave species')
     eq(m.id==50 and level>=15 and level<=22 or m.id==51 and (level==29 or level==31),true,'species-specific native levels')
     if native==1 then counts[m.id]=counts[m.id]+1;levels[level]=(levels[level] or 0)+1 end
    end
   end
   eq(counts[50],95,'Diglett exactly 95%');eq(counts[51],5,'Dugtrio exactly 5%')
   eq(levels[29],4,'level-29 Dugtrio 4%');eq(levels[31],1,'level-31 Dugtrio 1%')
  end
  for _,m in ipairs(moon)do
   local pool,loc=policy:pool(prefix..m[1],choice,'land',{postgame=true})
   eq(loc.lo,m[2],'native moon minimum');eq(loc.hi,m[3],'native moon maximum')
   for _,group in ipairs({pool.common,pool.rare})do for _,mon in ipairs(group)do eq(mon.gate<=loc.hi,true,'evolution gate fits area')end end
   for _,native in ipairs({1,7,12,20,30,99})do
    local mon,level=policy:choose(prefix..m[1],choice,native,'land')
    if mon then eq(level>=loc.lo and level<=loc.hi,true,'Moon level always in corrected band')end
   end
  end
 end
end
for _,mon in ipairs(roster)do
 local old=locs[mon.location]
 if not mon.special and not P.ultraBeasts[mon.id] and old and
  (old.residentSlots or old.map:match('^FR_MT_MOON_') and mon.gate>old.hi) then
  local found=false
  for _,map in ipairs({'FR_ROCK_TUNNEL_1F','FR_ROCK_TUNNEL_B1F'})do
   local pool=policy:pool(map,17,'land');for _,group in ipairs({pool.common,pool.rare})do for _,m in ipairs(group)do if mon.id==m.id then found=true end end end
  end
  eq(found,true,'displaced '..mon.name..' remains catchable later')
 end
end
-- Production public APIs consumed by native battles, WildFollowers and DexNav.
package.loaded['src.core.game3.profile']={forSession=function()return {id='firered'}end}
package.loaded['src.core.game3.constants']={of=function()return {require=function()return 0x864 end}end}
package.loaded['src.core.game3.scripting.flags']={getFlag=function()return false end}
package.loaded['src.core.game3.scripting.space']={}
local session={engineOptions={fireredGenEncounterPool=17}}
local names={};for _,m in ipairs(roster)do names[m.name]=m.id end
package.loaded['src.core.GameVersion']={generation=function()return 3 end,get=function()return 'firered' end}
package.loaded['src.core.game3.runtime']={getSession=function()return session end}
package.loaded['src.core.game3.options']={block=function(o)return o end}
package.loaded['src.core.game3.pokemon']={speciesFromName=function(n)return names[n]end,keyName=function(n)return roster[n].name end,_speciesMeta={}}
package.loaded['src.import.gba.map_catalog']={resolve=function(n)return n end}
local Enc={tableFor=function()return {land={slots={{species=50,minLevel=15,maxLevel=22}}}}end,
 onStep=function(map)return {species=50,level=30}end}
package.loaded['src.core.game3.encounters']=Enc
local Bridge={start=function(_,_,foe)return foe end};package.loaded['src.core.game3.battle_bridge']=Bridge
local mod={exports={},read=function(_,p)local f=assert(io.open('encounters/'..p));local s=f:read('*a');f:close();return s end,log={warn=function()end,info=function()end}}
local random=math.random;math.random=rng
assert(loadfile('encounters/main.lua'))()(mod)
for _,prefix in ipairs({'FR_','LG_'})do for choice=1,17 do
 session.engineOptions.fireredGenEncounterPool=choice
 local map=prefix..'DIGLETTS_CAVE_B1F';local header=mod.exports.dexnavEncounters(map)
 eq(#header.land.slots,2,'DexNav gets only Diglett and Dugtrio')
 for _,slot in ipairs(header.land.slots)do
  eq(slot.minLevel,slot.species==50 and 15 or 29,'DexNav correct minimum')
  eq(slot.maxLevel,slot.species==50 and 22 or 31,'DexNav correct maximum')
  eq(slot.weight,slot.species==50 and 95 or 5,'DexNav resident weight')
 end
 for _,r in ipairs({1,95,96,100})do roll=r
  local nat,sp,level=mod.exports.chooseWildEncounter(map,'land',30)
  eq(nat==50 or nat==51,true,'visible wild uses native residents')
  eq(level<=22 or nat==51,true,'visible high levels limited to rare Dugtrio')
  local foe=Enc.onStep(map,'land');local result=Bridge.start(mod,{},foe,{wild=true})
  eq(result.species,sp,'native battle and visible wild agree');eq(result.level,level,'same exact policy levels')
 end
end end
math.random=random
print('PASS: '..checks..' cave rarity / floor levels / relocated coverage / battle + WildFollowers + DexNav checks')
