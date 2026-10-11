-- Runs after a sandboxed App.load against imported, read-only ROM caches.
local S=require('App').getState()
local Gen=require('Gen')
local MonOps=require('MonOps')
local SD=require('src.core.SaveData')
local Copy=require('src.mods.Merge').deepCopy
local generation=require('src.core.GameVersion').generation()
assert(S.mods and #S.mods:status().errors==0,'editor registry has errors')
local reference=assert(loadfile(referenceRoot..'/data/species/generated/national.lua'))()
local own=assert(loadfile(dexRoot..'/dex/data/species/generated/national.lua'))()
local catalog={};for _,id in ipairs(S.cat.species)do catalog[id]=true end
local count,forms=0,0
local P=generation==3 and require('src.core.game3.pokemon')
for _,rows in ipairs({reference.patch,reference.register})do
 for id,source in pairs(rows)do
  local offered=catalog[id]
  if P and not offered then
   local slot=P.speciesFromName(id)
   for key in pairs(catalog)do if S.data.pokemon[key].speciesId==slot then offered=true;break end end
  end
  assert(offered,'editor picker missing '..id)
  local row=assert(S.data.pokemon[id])
  if source.form then
   assert(row.form==source.form and row.baseSpecies==source.baseSpecies,'form metadata lost '..id)
   assert(own.register[id].dex==source.dex,'saved form dex changed '..id)
   forms=forms+1
  end
  if source.dex and generation<3 then assert(row.dex==source.dex,'saved GB dex changed '..id)end
  if P then
   local slot=assert(P.speciesFromName(id))
   assert(row.speciesId==slot and S.data.pokemon[slot]==row,'numeric catalog alias missing '..id)
   if source.form then assert(slot==source.dex+64,'existing 1025Dex form slot changed '..id)end
  end
  count=count+1
 end
end
assert(count==1389 and forms==364)
-- Editor-generated native mons can be edited, serialized and restored as forms.
local samples={'CYNDAQUIL','TORCHIC','CHARIZARD_MEGA_X','CHARIZARD_GMAX','RAICHU_ALOLA','SNEASEL_HISUI','ROTOM_WASH','OGERPON_WELLSPRING','MELOETTA_PIROUETTE'}
samples[1]='CYNDAQUIL'
local saved={}
for _,id in ipairs(samples)do
 if S.data.pokemon[id] then
  local mon=MonOps.create(S.data,id,35,generation)
  assert(mon.species==(P and P.speciesFromName(id) or id),'editor create converted '..id)
  mon.nickname='COMPAT';mon.ot='OTHER';mon.otId=12345
  MonOps.setLevel(S.data,mon,36,generation)
  saved[#saved+1]=mon
 end
end
local round=assert(SD.decode(SD.encode({version=version,party=saved})))
for i,mon in ipairs(round.party)do
 assert(mon.species==saved[i].species and mon.nickname=='COMPAT' and mon.otId==12345,'roundtrip changed identity')
 MonOps.recalc(S.data,mon,generation)
 assert(mon.level==36,'editor recalc changed level')
end
if generation<3 then
 -- National Dex / Modern Spawns store GB keys, not National numbers.
 local foreign={};for _,rows in ipairs({reference.patch,reference.register})do
  for id in pairs(rows)do
   local mon=MonOps.create(S.data,id,35,generation)
   mon.nickname='FOREIGN';foreign[#foreign+1]=mon
  end
 end
 local restored=assert(SD.decode(SD.encode({version=version,mons=foreign})))
 for i,mon in ipairs(restored.mons)do assert(mon.species==foreign[i].species and S.data.pokemon[mon.species])end
 local probe=Gen.newGame(version);probe.party={foreign[1]};Gen.ensureBoxes(probe)
 local last=Gen.boxCount(probe);probe.boxes[last]={foreign[#foreign]}
 local report=Gen.validate(probe,S.data)
 assert(#(report.lostMons or {})==0,'foreign save quarantined compatible Pokemon')
 assert(probe.boxes[last][1].species==foreign[#foreign].species,'expanded box lost foreign Pokemon')
else
 local Adapter=require('Game3Adapter');local Storage=require('src.core.game3.storage')
 local save=Gen.newGame(version);save.party={saved[1]};save.storage=Storage.new()
 local last=Storage.TOTAL_BOXES_COUNT
 save.storage.boxes[last]={name='FORMS',wallpaper=7,mons={[30]=saved[3]}}
 save.storage.currentBox=last
 local mirror=Copy(saved[3]);save.boxes={[last]={[30]=mirror}}
 Gen.hydrateSave(S.data,save)
 assert(Gen.boxCount(save)==last and save.currentBox==last,'editor limited to 14 boxes')
 assert(save.storage.boxes[last].name=='FORMS' and save.storage.boxes[last].wallpaper==7)
 assert(save.storage.boxes[last].mons[30].species==saved[3].species)
 assert(Storage.countTotalMons(save.storage)==1,'mirror duplicated Pokemon')
 local restored=assert(SD.decode(SD.encode(Adapter.export(save))))
 Gen.hydrateSave(S.data,restored)
 assert(restored.storage.boxes[last].mons[30].species==saved[3].species,'editor export lost final box')
 assert(restored.storage.boxes[last].name=='FORMS' and restored.storage.boxes[last].wallpaper==7)
 local identity=restored.storage.boxes[last].mons[30].species
 local got=Storage.withdraw(restored,last,30)
 assert(got and restored.party[#restored.party].species==identity,'native PC withdraw changed form')
 assert(Storage.deposit(restored,#restored.party,last,30),'native PC deposit failed')
 assert(restored.storage.boxes[last].mons[30].species==identity,'native PC deposit changed form')
 -- Preserve sparse higher boxes from other extensions, not only our default.
 restored.storage.boxes[40]={name='EXTRA',wallpaper=3,mons={[2]=saved[4]}}
 restored.storage.currentBox=40;restored.boxes=nil
 Gen.hydrateSave(S.data,restored)
 assert(Gen.boxCount(restored)==40 and restored.storage.boxes[40].mons[2].species==saved[4].species)
 local legacy=Gen.newGame(version);legacy.storage=nil;legacy.boxes={[36]={[30]=Copy(saved[3])}}
 Gen.hydrateSave(S.data,legacy)
 assert(legacy.storage.boxes[36].mons[30].species==saved[3].species,'legacy expanded box relocated or lost')
end
print('PASS save editor / foreign-save identity / native PC',version,count,forms)

if S.save.compatAllMons then
 assert(#S.save.compatAllMons==1389,'foreign save lost records')
 for _,mon in ipairs(S.save.compatAllMons)do
  local species,nickname,otId=mon.species,mon.nickname,mon.otId
  local moves=SD.encode(mon.moves)
  Gen.hydrateMon(S.data,mon)
  assert(mon.species==species and mon.nickname==nickname and mon.otId==otId,'foreign identity altered')
  assert(SD.encode(mon.moves)==moves,'foreign moves altered')
 end
 for _,mon in ipairs(S.save.party)do assert(S.data.pokemon[mon.species],'foreign party lost')end
 print('PASS actual National Dex + Modern Spawns save imported',version,#S.save.compatAllMons)
end
