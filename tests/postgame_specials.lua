-- Run from 1025Dex's mod folder: texlua tests/postgame_specials.lua
local P=dofile('encounters/policy.lua')
local roster=dofile('encounters/roster.lua')
local locations=dofile('encounters/locations.lua')
for _,loc in ipairs(dofile('encounters/hoenn_locations.lua')) do locations[#locations+1]=loc end
local maps,seen={},{ }
local function add(map)if not seen[map]then seen[map]=true;maps[#maps+1]=map end end
for _,loc in ipairs(locations)do add(loc.map)end
for _,homes in pairs(P.specialHomes)do
 for _,names in pairs(homes.land)do for _,map in ipairs(names)do add(map)end end
 for _,map in ipairs(homes.water)do add(map)end
end
for _,homes in pairs(P.extraSpecialHomes)do
 for _,terrains in pairs(homes)do
  for _,names in pairs(terrains)do for _,map in ipairs(names)do add(map)end end
 end
end
local checks=0
local function eq(a,b,why)checks=checks+1;assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b))end
local policy=P.new(roster,locations,function(a,b)return b and a or 1 end)
local nativeFRLG={[144]=true,[145]=true,[146]=true,[150]=true}
local coverage={frlg={},emerald={}}
local guide={
 '1025Dex 1.2.2 - Legendary / mythical / special encounter homes',
 'Added wild encounters unlock only after the native Pokemon League clear flag.',
 'WILD GENS still filters them. Levels 55-70; shared 1% special roll when normal',
 'candidates exist. Native scripted/static encounters keep their original rules.',
 'DexNav lists unlocked species directly; WildFollowers uses the same live pools.',
 '',
}
for _,map in ipairs(maps)do
 local family=map:match('^EM_') and 'emerald' or 'frlg'
 for _,terrain in ipairs({'land','water','fishing','rocks'})do
  for choice=1,#P.choices do
   local before=policy:pool(map,choice,terrain,{postgame=false})
   eq(#before.special,0,'pre-League special gate '..map)
   local after=policy:pool(map,choice,terrain,{postgame=true})
   if terrain=='fishing' or terrain=='rocks'then eq(#after.special,0,'no fishing/rock additions')end
   for _,mon in ipairs(after.special)do
    local range=P.choices[choice]
    eq(mon.id>=range.first and mon.id<=range.last,true,'generation filter')
    eq(P.allows(mon,terrain),true,'terrain eligibility')
    local lo,hi=P.specialLevelRange(mon)
    eq(lo>=55 and hi>=lo and hi<=70,true,'special level range')
    if family=='frlg'then eq(nativeFRLG[mon.id],nil,'preserve native static species')end
    coverage[family][mon.id]=coverage[family][mon.id] or {}
    coverage[family][mon.id][map..' ('..terrain..')']=true
   end
   -- Verify false/true/false cache transitions and LG aliases.
   eq(#policy:pool(map,choice,terrain,{postgame=false}).special,0,'relocked cache')
   if family=='frlg'then
    local lg=policy:pool(map:gsub('^FR_','LG_'),choice,terrain,{postgame=true})
    eq(#lg.special,#after.special,'LeafGreen alias')
    for i,mon in ipairs(after.special)do eq(lg.special[i].id,mon.id,'LG species identity')end
   end
  end
 end
end
local counts={}
for _,family in ipairs({'frlg','emerald'})do
 guide[#guide+1]=family=='frlg' and 'FireRed / LeafGreen (FR_ map names also apply to LG_)' or 'Emerald'
 counts[family]=0
 for _,mon in ipairs(roster)do if mon.special then
  local homes=coverage[family][mon.id]
  eq(homes~=nil or family=='frlg' and nativeFRLG[mon.id]==true,true,'missing home '..family..' '..mon.name)
  if homes then
   counts[family]=counts[family]+1
   local names={};for name in pairs(homes)do names[#names+1]=name end;table.sort(names)
   guide[#guide+1]=mon.name..' (#'..mon.id..'): '..table.concat(names,', ')
  else guide[#guide+1]=mon.name..' (#'..mon.id..'): existing native static encounter' end
 end end
 guide[#guide+1]=''
end
eq(counts.frlg,90,'FRLG added special roster');eq(counts.emerald,94,'Emerald special roster')
for _,map in ipairs({'FR_CERULEAN_CAVE_1F','LG_CERULEAN_CAVE_1F','FR_SEVEN_ISLAND_SEVAULT_CANYON','LG_SEVEN_ISLAND_SEVAULT_CANYON'})do
 local mon,level=policy:choose(map,1,5,'land',{postgame=true})
 eq(mon.id,151,'Mew exact post-League selection');eq(level>=55 and level<=70,true,'Mew level')
 local pre=policy:choose(map,1,5,'land',{postgame=false});eq(pre and pre.id==151,false,'Mew absent before League')
end
-- Actual public encounter export: imported session flags and live script
-- flags must unlock Mew immediately, and clearing the flag must remove it.
local session={map='FR_CERULEAN_CAVE_1F',engineOptions={fireredGenEncounterPool=1},flags={}}
local game='firered';local store
local names={};for _,mon in ipairs(roster)do names[mon.name]=mon.id end
local modules={
 ['src.core.GameVersion']={generation=function()return 3 end},
 ['src.core.game3.runtime']={getSession=function()return session end},
 ['src.core.game3.options']={block=function(o)return o end},
 ['src.core.game3.profile']={forSession=function()return {id=game}end},
 ['src.core.game3.constants']={of=function()return {require=function()return 123 end}end},
 ['src.core.game3.scripting.space']={isActive=function()return store~=nil end,getStore=function()return store end},
 ['src.core.game3.scripting.flags']={getFlag=function(s,_,id)return s.flags[id]==true end},
 ['src.core.game3.encounters']={tableFor=function()return {land={slots={{species=42,minLevel=50,maxLevel=55}}}}end},
 ['src.core.game3.pokemon']={speciesFromName=function(n)return names[n]end,keyName=function()return true end},
 ['src.core.game3.battle_bridge']={start=function(_,_,foe)return foe end},
 ['src.import.gba.map_catalog']={resolve=function(id)return id end},
}
for name,value in pairs(modules)do package.loaded[name]=value end
local mod={exports={},read=function(_,path)local f=assert(io.open('encounters/'..path));local t=f:read('*a');f:close();return t end,
 log={warn=function()end,info=function()end}}
dofile('encounters/main.lua')(mod)
local function hasMew(map)
 local record=mod.exports.dexnavEncounters(map)
 for _,slot in ipairs(record.land.slots)do if slot.species==151 then
  eq(slot.minLevel,55,'export Mew minimum');eq(slot.maxLevel,70,'export Mew maximum');return true
 end end
 return false
end
for _,version in ipairs({'firered','leafgreen'})do
 game=version
 local map=version=='firered' and 'FR_CERULEAN_CAVE_1F' or 'LG_CERULEAN_CAVE_1F'
 session.flags={};store=nil;eq(hasMew(map),false,'locked public pool')
 session.flags[123]=true;eq(hasMew(map),true,'imported native League flag')
 session.flags={};store={flags={FLAG_SYS_GAME_CLEAR=true}}
 eq(hasMew(map),true,'live League flag')
 session.engineOptions.fireredGenEncounterPool=2;eq(hasMew(map),false,'public generation filtering')
 session.engineOptions.fireredGenEncounterPool=1;store=nil
 eq(hasMew(map),false,'public relock clears special cache')
end
-- Generate the bundled location reference only when requested.
if arg[1]=='--guide'then
 local f=assert(io.open('POSTGAME-SPAWNS.txt','w'));f:write(table.concat(guide,'\n')..'\n');f:close()
end
print(('PASS: %d assertions; FR/LG 90 added + 4 native specials, Emerald 94; all 17 generation choices and League transitions.'):format(checks))
