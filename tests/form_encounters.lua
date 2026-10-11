local root,version=arg[1],arg[2]
local function data(path)local f=assert(io.open(root..'/'..path));local s=f:read('*a');f:close();return assert(load(s))()end
local GV=require('src.core.GameVersion');GV.set(version);local gen=GV.generation()
local Forms=data('encounters/forms.lua');local Policy=data('encounters/policy.lua')
local national=data('dex/data/species/generated/national.lua')
local index={};for id,row in pairs(national.register)do if row.form then index[id]=gen==3 and row.dex+64 or id end end
local cleared=false
local forms=Forms.new(national,data('encounters/roster.lua'),Policy,gen,function()return cleared end,function(id)return index[id]end)
assert(#forms.forms==364)
local map=gen==1 and 'CERULEAN_CAVE_1F' or gen==2 and 'SILVER_CAVE_ROOM_2'
 or ((version=='firered' or version=='leafgreen') and 'FR_CERULEAN_CAVE_1F' or 'EM_VICTORY_ROAD_B2F')
assert(#forms:pool(map,'land')==0 and not forms:choose(map,'land',nil,function()error('pre-League RNG touched')end))
cleared=true
assert(#forms:pool('ROUTE_1','land')==0)
local found={}
for _,terrain in ipairs({'land','water','fishing'})do
 local rows=forms:pool(map,terrain)
 for _,row in ipairs(rows)do
  assert(row.species==index[row.name],'form identity lost')
  assert(row.minLevel==55 and row.maxLevel==70)
  found[row.name]=true
 end
 for _,choice in ipairs(Policy.choices)do
  for _,row in ipairs(forms:pool(map,terrain,choice))do assert(row.baseDex>=choice.first and row.baseDex<=choice.last,'generation filter leaked')end
 end
 if #rows>0 then
  for i,row in ipairs(rows)do
   local call=0
   local mon,level=forms:choose(map,terrain,nil,function(lo,hi)
    call=call+1;if call==1 then assert(lo==1 and hi==100);return 2 elseif call==2 then return i else return 70 end
   end)
   assert(mon.species==row.species and level==70,'unreachable form '..row.name)
  end
  local successes=0
  for roll=1,100 do
   local call=0;local row=forms:choose(map,terrain,nil,function(lo)
    call=call+1;return call==1 and roll or lo
   end)
   if row then successes=successes+1 end
  end
  assert(successes==2,'combined chance is not exactly 2%')
 end
end
local count=0;for _ in pairs(found)do count=count+1 end;assert(count==364,'forms missing homes')
cleared=false;assert(#forms:pool(map,'water')==0,'gate retained stale postgame pool')
print('PASS '..version..': 364 forms reachable after League, exact identities, generation filters, land/water rules and 2% combined chance')
if gen==3 then
 love=require('tests.love_stub')
 local session={version=version,flags={},options={fireredGenEncounterPool=17}}
 package.loaded['src.core.game3.runtime']={getSession=function()return session end}
 package.loaded['src.core.game3.scripting.space']={isActive=function()return false end}
 local P={_speciesMeta={},speciesFromName=function(id)return index[id]end,keyName=function(slot)return tostring(slot)end,national=function(slot)return slot>450 and slot-64 or slot end}
 for _,row in ipairs(data('encounters/roster.lua'))do index[row.name]=row.id>386 and row.id+64 or row.id end
 package.loaded['src.core.game3.pokemon']=P
 local tableMap=version=='ruby' and 'RU_VICTORY_ROAD_B2F' or version=='sapphire' and 'SA_VICTORY_ROAD_B2F' or map
 local area={land={rate=30,slots={{species=41,minLevel=45,maxLevel=50}}},water={rate=30,slots={{species=72,minLevel=45,maxLevel=50}}}}
 local E={_tables={[tableMap]=area},ensureLoaded=function()end,tableFor=function()return area end}
 package.loaded['src.core.game3.encounters']=E
 local dispatched
 package.loaded['src.core.game3.battle_bridge']={start=function(_,_,mon)dispatched=mon;return true end}
 package.loaded['src.core.game3.options']={block=function(opts)return opts end}
 package.loaded['src.ui.game3.option_rows']={build=function()return {}end}
 package.loaded['src.import.gba.map_catalog']={resolve=function(id)return id end}
 local values={}
 local mod={path=root..'/encounters',exports={},game={},find=function()end,
  options={get=function(_,key)return values[key]end,define=function(_,rows)for _,row in ipairs(rows)do if values[row.key]==nil then values[row.key]=row.default end end end},
  read=function(_,path)local f=assert(io.open(root..'/encounters/'..path));local s=f:read('*a');f:close();return s end,
  rootRead=function(_,path)local f=assert(io.open(root..'/'..path));local s=f:read('*a');f:close();return s end,
  log={info=function()end,warn=function()end}}
 assert(load(mod:read('main.lua')))()(mod)
 assert(#mod.exports.formEncounterPool(tableMap,'land')==0)
 session.flags.FLAG_SYS_GAME_CLEAR=true
 local pool=mod.exports.formEncounterPool(tableMap,'land');assert(#pool>0,'live League flag / map alias')
 -- Fixed rolls exercise the real bridge and visible-wild selection hooks.
 math.random=function(lo)return lo end
 local Bridge=require('src.core.game3.battle_bridge')
 Bridge.start(nil,mod.game,{species=41,level=45,__completeDexTerrain='land',__completeDexMap=tableMap},{wild=true})
 assert(dispatched.species==pool[1].species and dispatched.level==55,'natural Gen 3 form identity')
 local _,sp,lv=mod.exports.chooseWildEncounter(tableMap,'land',45)
 assert(sp==pool[1].species and lv==55,'visible-wild form identity')
 Bridge.start(nil,mod.game,{species=41,level=45,__completeDexTerrain='land',__completeDexMap=tableMap},{wild=true,__completeDexExact=true})
 assert(dispatched.species==41,'CodeBreaker/DexNav exact selection replaced')
 Bridge.start(nil,mod.game,{species=41,level=45,__completeDexTerrain='land',__completeDexMap=tableMap},{wild=true,wildScripted=true})
 assert(dispatched.species==41,'scripted encounter replaced')
 local header=assert(mod.exports.dexnavEncounters(tableMap))
 local bySpecies={};for _,form in ipairs(pool)do bySpecies[form.species]=true end
 local sum,rare=0,0
 for _,slot in ipairs(header.land.slots)do
  local weight=slot.weight or 1;sum=sum+weight
  if bySpecies[slot.species] then rare=rare+weight;assert(slot.minLevel==55 and slot.maxLevel==70)end
 end
 assert(math.abs(rare/sum-.02)<1e-9,'live encounter API chance differs')
 session.flags.FLAG_SYS_GAME_CLEAR=false
 assert(#mod.exports.formEncounterPool(tableMap,'land')==0,'live progress cache leaked forms')
 print('PASS '..version..': live battle/visible-wild dispatch, League flag, exact/scripted preservation and table weights')
 assert(values.fullEncounterRandomizer==false,'randomizer must default OFF')
 values.fullEncounterRandomizer=true;session.options.fireredGenEncounterPool=1
 local all=mod.exports.randomEncounterPool();assert(#all==1389,'randomizer excludes registered species/forms')
 local seen={}
 for i,row in ipairs(all)do
  math.random=function(lo,hi)assert(lo==1 and hi==1389,'randomizer is not one equal-weight draw');return i end
  local _,species,level=mod.exports.chooseWildEncounter('UNLISTED_EARLY_MAP','water',4)
  assert(species==row.species and level==4,'randomizer lost form identity or native level')
  assert(not seen[species],'duplicate randomizer species');seen[species]=true
 end
 math.random=function()return #all end
 Bridge.start(nil,mod.game,{species=41,level=5,__completeDexTerrain='fishing',__completeDexMap='UNLISTED_EARLY_MAP'},{wild=true})
 assert(dispatched.species==all[#all].species and dispatched.level==5,'randomized battle handoff lost form')
 Bridge.start(nil,mod.game,{species=41,level=5,__completeDexTerrain='land'},{wild=true,__completeDexExact=true})
 assert(dispatched.species==41,'visible-wild exact selection randomized twice')
 Bridge.start(nil,mod.game,{species=41,level=5,__completeDexTerrain='land'},{wild=true,wildScripted=true})
 assert(dispatched.species==41,'randomizer replaced scripted encounter')
 local header=mod.exports.dexnavEncounters('UNLISTED_EARLY_MAP')
 assert(#header.land.slots==1389 and #header.water.slots==1389,'DexNav randomizer pool differs')
 for _,slot in ipairs(header.land.slots)do assert(slot.weight==1 and slot.minLevel==45 and slot.maxLevel==50)end
 values.fullEncounterRandomizer=false;assert(#mod.exports.randomEncounterPool()==0,'OFF did not restore normal behavior')
 print('PASS '..version..': uniform all-1389 randomizer, early-game water/battle/visible-wild selection, original levels, DexNav and exact/scripted exclusions')
end
