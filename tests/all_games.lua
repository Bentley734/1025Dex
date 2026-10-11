local root,version,hoennto=arg[1],arg[2],arg[3]
love=require('tests.love_stub');loadstring=loadstring or load
local GV=require('src.core.GameVersion');GV.set(version)
local gen=GV.generation()
local function file(name)local f=assert(io.open(root..'/'..name));local s=f:read('*a');f:close();return s end
for _,name in ipairs({'main.lua','storage.lua','cries/main.lua','encounters/main.lua','encounters/gb.lua','emerald.lua','compat/hoennto.lua'})do assert(load(file(name),name)) end
local national=assert(load(file('dex/data/species/generated/national.lua')))()
local roster=assert(load(file('encounters/roster.lua')))()
local shape=assert(load(file('dex/src/gen2shape.lua')))()
local data={pokemon={},encounters={},moves={},items={}}
local nativeMax=gen==1 and 151 or gen==2 and 251 or 386
for id,row in pairs(national.register)do if not row.form and row.dex<=nativeMax then data.pokemon[id]=gen==2 and shape.record(row) or row end end
for id,row in pairs(national.patch)do
 local nat;for _,mon in ipairs(roster)do if mon.name:gsub('[^A-Z0-9]','')==id:gsub('[^A-Z0-9]','')then nat=mon.id;break end end
 data.pokemon[id]={id=id,name=id,dex=assert(nat,id),types=row.types,catchRate=45,baseExp=64,growthRate='MEDIUM_FAST',level1Moves={'TACKLE'},learnset={},levelMoves={{level=1,move='TACKLE'}},evolutions={},baseStats={hp=50,attack=50,defense=50,speed=50,special=50,specialAttack=50,specialDefense=50},spriteFront='x.png',spriteBack='x.png'}
end
local Registry=require('src.mods.Registry');local Schemas=require('src.mods.Schemas')
local content={};local constants={generation=gen,dexSize=nativeMax,dexDigits=3}
for name,spec in pairs(Schemas.REGISTRIES)do
 local reg=Registry.new(name,spec);local base=name=='pokemon' and data.pokemon or name=='constants' and constants or {}
 reg.base=function()return base end
 local facade={}
 for _,method in ipairs({'register','override','patch'})do
  local action=method
  facade[action]=function(_,id,value)
   local ok,errors=Schemas.check(spec,name,id,value,action,gen)
   assert(ok,name..':'..id..':'..table.concat(errors or {},';'))
   return reg[action](reg,id,value,'1025dex')
  end
 end
 facade.get=function(_,id)return reg:get(id)end
 facade._registry=reg;content[name]=facade
end
local values={national_dex='on',type_chart='modern',moves='gen-native',stats='gen1',fireredGenEncounterPool='17'}
local messages={}
local mod={path=root,exports={},content=content,game={data=data,save={hallOfFame={count=1}}},
 read=function(_,name)return file(name)end,rootRead=function(_,name)return file(name)end,list=function()return {}end,info=function()return {type='file'}end,
 assets={path=function(_,name)return root..'/'..name end,list=function()return {}end,info=function()return {type='file'}end},
 options={get=function(_,key)return values[key]end,define=function(_,rows)for _,row in ipairs(rows)do if values[row.key]==nil then values[row.key]=row.default end end end},
 log={info=function()end,warn=function(_,fmt,...)if fmt:find('registration') then messages[#messages+1]=string.format(fmt,...)end end,error=function(_,fmt,...)messages[#messages+1]=string.format(fmt,...)end},
 events={on=function()end},hooks={wrap=function()end},find=function()return nil end}
-- Exercise the real registry adapter, including its optional UI hooks.
local dex=setmetatable({path=root..'/dex',read=function(_,name)return file('dex/'..name)end}, {__index=mod})
if gen<3 then
 assert(load(file('dex/main.lua')))()(dex)
else
 Schemas.REGISTRIES.pokemon.gen3Fields.index=Schemas.f.opt(Schemas.f.int(1,65535))
 local adapter=assert(load(file('dex/src/gen3shape.lua')))()
 assert(load(file('dex/src/nationaldex.lua')))()(dex,nil,national,shape,3,'modern',nil,adapter)
end
assert(#messages==0,table.concat(messages,'\n'))
local count=0
for nat=1,1025 do
 local found
 for id,row in content.pokemon._registry:each() do if row and row.dex==nat and not row.form then found=id;break end end
 assert(found,version..' missing National '..nat);count=count+1
end
print('PASS '..version..' schema-backed National registry '..count)
data.pokemon={};local byDex={}
for id,row in content.pokemon._registry:each()do data.pokemon[id]=row;if not row.form then byDex[row.dex]=id end end
if gen<3 then
 local cries=setmetatable({rootRead=function(_,name)return file(name)end,assets={path=function(_,name)return root..'/cries/'..name end}}, {__index=mod})
 assert(load(file('cries/main.lua')))()(cries)
 assert(mod.exports.cryCount==1025,'GB cry count '..tostring(mod.exports.cryCount))
 for nat=1,1025 do assert(content.cries:get(byDex[nat]).file:find('/'..nat..'.ogg',1,true))end
 local maps={'ROUTE_3','VIRIDIAN_FOREST',gen==1 and 'SAFARI_ZONE_CENTER' or 'ROUTE_28','MT_MOON_1F','VICTORY_ROAD_1F','POWER_PLANT','SEAFOAM_ISLANDS_B4F','POKEMON_TOWER_5F','BURNED_TOWER_B1F','CERULEAN_CAVE_B1F'}
 local grass={rate=255,slots={{species='JIGGLYPUFF',level=8},{species='ZUBAT',level=12}}}
 if gen==1 then for _,map in ipairs(maps)do data.encounters[map]={grass=grass,water={rate=255,slots={{species='TENTACOOL',level=50},{species='GOLDEEN',level=60}}}}end
 else
  data.encounters={grass={},water={}}
  for _,map in ipairs(maps)do
   data.encounters.grass[map]={rates={MORN=255,DAY=255,NITE=255},slots={MORN=grass.slots,DAY=grass.slots,NITE={{species='HOOTHOOT',level=8}}}}
   data.encounters.water[map]={rate=255,slots={{species='TENTACOOL',level=50},{species='GOLDEEN',level=60}}}
  end
 end
 local links={};mod.hooks.wrap=function(_,name,fn)links[name]=fn end
 local enc=setmetatable({read=function(_,name)return file('encounters/'..name)end},{__index=mod})
 assert(load(file('encounters/main.lua')))()(enc)
 local rolls=0;local native={species='JIGGLYPUFF',level=8}
 local keep=links['encounter.roll'](function()rolls=rolls+1;return native end,{}, {mapId='ROUTE_3',terrain='grass',rng=function()return 1 end})
 assert(keep==native and rolls==1,'cartridge roll and native exact levels preserved')
 assert(links['encounter.roll'](function()return nil end,{}, {mapId='ROUTE_3',terrain='grass',rng=function()error('must not roll')end})==nil,'no new encounters on failed native roll')
 assert(links['encounter.roll'](function()return native end,{}, {mapId='ROUTE_3',terrain='grass',kind='contest',rng=function()error('must not roll')end})==native,'contest untouched')
 values.fullEncounterRandomizer=true;mod.game.save.hallOfFame={count=0}
 local all=mod.exports.randomEncounterPool();assert(#all==1389,'all registered bases and forms available before League')
 for i,row in ipairs(all)do
  local hit=mod.exports.chooseGBWildEncounter(native,'UNLISTED_EARLY_MAP','water',function(lo,hi)assert(lo==1 and hi==1389);return i end)
  assert(hit.species==row.species and hit.level==8,'uniform randomizer loses identity or native level')
 end
 local distribution=links['encounter.table'](function()return {JIGGLYPUFF=100}end,{}, {mapId='UNLISTED_EARLY_MAP',terrain='water'})
 local size=0;for _,weight in pairs(distribution)do assert(weight==1);size=size+1 end;assert(size==1389)
 assert(links['encounter.fishing'](function()return nil end,'OLD_ROD','UNLISTED_EARLY_MAP',{})==nil,'randomizer turns failed fishing into a battle')
 local scripted={species='MEW',level=5,wildScripted=true}
 assert(mod.exports.chooseGBWildEncounter(scripted,'ROUTE_3','land')==scripted,'scripted encounter randomized')
 values.fullEncounterRandomizer=false;mod.game.save.hallOfFame={count=1}
 local policy=assert(load(file('encounters/policy.lua')))()
 for selection=1,17 do values.fireredGenEncounterPool=tostring(selection)
  for _,map in ipairs(maps)do for _,terrain in ipairs({'land','water'})do
   local rows=mod.exports.gbEncounterAdditions(map,terrain)
   for _,mon in ipairs(rows)do local nat=mon.baseDex or mon.id;assert(nat>=policy.choices[selection].first and nat<=policy.choices[selection].last,'GB generation filter')end
  end end
 end
 assert(load(file('main.lua')))()(mod)
 assert(#mod.exports.supportedGames==11,'all-game entrypoint')
 mod.game.save.hallOfFame={count=0}
 values.fireredGenEncounterPool='17'
 local locked,p=mod.exports.gbEncounterAdditions(gen==1 and 'SAFARI_ZONE_CENTER' or 'ROUTE_28','land')
 assert(p.hi==12,'story area ceiling')
 for _,mon in ipairs(locked)do assert(mon.gate<=12 and not mon.special and not policy.ultraBeasts[mon.id],'story progression lock')end
 mod.game.save.hallOfFame={count=1}
 local unlocked,late=mod.exports.gbEncounterAdditions(gen==1 and 'SAFARI_ZONE_CENTER' or 'ROUTE_28','land')
 assert(late.hi==70,'post-League ceiling')
 local hit=mod.exports.chooseGBWildEncounter(native,'VICTORY_ROAD_1F','land',function(lo,hi)return lo end)
 assert(data.pokemon[hit.species].form and hit.level==55,'natural form encounter lost identity')
 local dist=links['encounter.table'](function()return {JIGGLYPUFF=100}end,{}, {mapId='VICTORY_ROAD_1F',terrain='land'})
 local total,rare=0,0;for id,w in pairs(dist)do total=total+w;if data.pokemon[id].form then rare=rare+w end end
 assert(math.abs(rare/total-0.02)<1e-9,'GB form table chance')
 mod.game.save.hallOfFame={count=0}
 assert(mod.exports.chooseGBWildEncounter(native,'VICTORY_ROAD_1F','land',function(lo)return lo end)==native,'form before League')
 mod.game.save.hallOfFame={count=1}
 print('PASS '..version..' full entrypoint, native roll, failures, contest and 1025 cry identities')
end
-- Test Hoennto's real converter and projection with a complete collection.
assert(load(file('storage.lua')))()(mod)
local C=assert(loadfile(hoennto..'/campaign.lua'))()
local R=assert(loadfile(hoennto..'/roster.lua'))()(C,function()return mod.game end)
local pokemon={}
local slotToName={};for nat,id in pairs(byDex)do slotToName[nat<=251 and nat or nat+64]=id end
pokemon.keyName=function(slot)return slotToName[slot]end
pokemon.speciesFromName=function(name)for slot,id in pairs(slotToName)do if id:gsub('[^A-Z0-9]','')==name:upper():gsub('[^A-Z0-9]','') then return slot end end end
pokemon.name=pokemon.keyName
pokemon.national=function(slot)return slot<=251 and slot or slot-64 end
pokemon.applyStats=function(mon)mon.maxHp=100 end
package.loaded['src.core.game3.pokemon']=pokemon
mod.find=function()return {exports={transfer=R}}end
assert(load(file('compat/hoennto.lua')))()(mod)
local state={collection={records={},dex={seen={},owned={}}},projected={}}
for nat=1,1025 do state.collection.records[nat]={id=nat,species=byDex[nat],version='emerald',moves={},forms={},mon={species=nat<=251 and nat or nat+64,level=60,moves={},ivs={},dvs={},evs={},hp=100,maxHp=100}}end
state.collection.records[1026]={id=1026,species='NOT_A_SPECIES',version='emerald',moves={},forms={},mon={moves={}}}
local raw={version=version,party={},storage={boxes={[36]={name='COLLECTION',wallpaper=7,mons={}}}},boxes={}}
R.project(raw,state)
assert(state.reserveCount==1,version..' compatible mons left in reserve '..state.reserveCount)
local restored=0;for _ in pairs(state.projected[version])do restored=restored+1 end
assert(restored==1025,version..' lost collection members')
if gen==3 then assert(raw.storage.boxes[36].name=='COLLECTION' and raw.storage.boxes[36].wallpaper==7,'expanded box metadata retained')end
print('PASS '..version..' Hoennto complete collection projection '..restored)
if version=='ruby' or version=='sapphire' then
 local source=assert(load(file('encounters/native.lua')))().ruby
 local tables={}
 for map,channels in pairs(source)do
  local live=version=='sapphire' and map:gsub('^RU_','SA_') or map
  tables[live]={}
  for terrain,rows in pairs(channels)do
   local slots={};for nat,range in pairs(rows)do
    -- An alternate-edition fixture must come from its live tables, rather
    -- than accidentally borrowing the Ruby or Emerald native roster.
    if version=='sapphire' and nat==273 then nat=270 end
    slots[#slots+1]={species=nat<=251 and nat or nat+64,minLevel=range[1],maxLevel=range[2]}
   end
   tables[live][terrain]={rate=30,slots=slots}
  end
 end
 package.loaded['src.core.game3.encounters']={_tables=tables,ensureLoaded=function()end,tableFor=function(map)return tables[map]end}
 package.loaded['src.core.game3.runtime']={getSession=function()return nil end}
 package.loaded['src.core.game3.options']={block=function(o)return o end}
 package.loaded['src.ui.game3.option_rows']={}
 package.loaded['src.core.game3.battle_bridge']={}
 package.loaded['src.import.gba.map_catalog']={resolve=function(map)return map end}
 local enc=setmetatable({read=function(_,name)return file('encounters/'..name)end},{__index=mod})
 mod.find=function()return nil end
 assert(load(file('encounters/main.lua')))()(enc)
 local checked=0
 for map,channels in pairs(tables)do
  local header=assert(mod.exports.dexnavEncounters(map),'RS missing map '..map)
  for terrain,area in pairs(channels)do
   local entries={};for _,row in ipairs(header[terrain].slots)do entries[row.species]=row end
   for _,native in ipairs(area.slots)do
    local row=assert(entries[native.species],map..':'..terrain..':'..native.species)
    assert(row.minLevel==native.minLevel and row.maxLevel==native.maxLevel,'RS native levels')
    checked=checked+1
   end
  end
 end
 print('PASS '..version..' live native encounter API '..checked)
end
