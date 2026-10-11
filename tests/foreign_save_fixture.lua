-- Generate a scratch save with the supplied National Dex / Modern Spawns mods.
-- Invoked only by tools/test_save_editor.py --foreign; never writes a user save.
local S=require('App').getState()
local loaded={};for _,m in ipairs(S.mods:status().loaded)do loaded[m.id]=true end
assert(loaded.national_dex and loaded.modern_spawns,'reference mods not loaded')
local Gen=require('Gen');local MonOps=require('MonOps');local SD=require('src.core.SaveData')
local g=require('src.core.GameVersion').generation();assert(g<3,'supplied National Dex only supports GB')
local ref=assert(loadfile(referenceRoot..'/data/species/generated/national.lua'))()
local save=Gen.newGame(version);Gen.ensureBoxes(save)
save.compatAllMons={}
for _,rows in ipairs({ref.patch,ref.register})do
 for id in pairs(rows)do
  local mon=MonOps.create(S.data,id,35,g)
  mon.nickname='FROMMODS';mon.ot='OTHER';mon.otId=54321
  save.compatAllMons[#save.compatAllMons+1]=mon
 end
end
save.party={}
for _,id in ipairs({'CYNDAQUIL','TORCHIC','CHARIZARD_MEGA_X','CHARIZARD_GMAX','RAICHU_ALOLA','SNEASEL_HISUI'})do
 save.party[#save.party+1]=MonOps.create(S.data,id,35,g)
end
save.boxes[Gen.boxCount(save)][1]=MonOps.create(S.data,'CHARIZARD_MEGA_Y',35,g)
local f=assert(io.open(fixturePath,'wb'));f:write(SD.encode(save));f:close()
print('PASS generated source-mod save',version,#save.compatAllMons,fixturePath)
