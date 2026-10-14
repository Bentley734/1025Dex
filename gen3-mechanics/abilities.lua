-- SPDX-License-Identifier: GPL-3.0-or-later
-- Modern abilities have a separate numeric namespace from the ROM's 77
-- entries (whose Air Lock/Cacophony numbering differs from PokeAPI).
return function(mod,models)
 local P=require('src.core.game3.pokemon')
 local Summary=require('src.core.game3.summary_data')
 local SaveMon=require('src.core.game3.save_mon')
 local byName,byNumber={},{ }
 local function key(name)return tostring(name):upper():gsub('[^A-Z0-9]','')end
 for _,id in ipairs(mod.exports.listAbilities())do
  local info=assert(mod.exports.abilityById(id))
  local number=1000+assert(tonumber(info.abilityId))
  byName[key(id)]={number=number,info=info};byName[key(info.name)]=byName[key(id)]
  byNumber[number]=info
 end
 local function candidates(species)
  local name=P.keyName(tonumber(species))or species
  return models.exports.ModernStats.resolveAbilities(name,mod.exports)
 end
 local abilities=P.abilities
 P.abilities=function(species)
  local names=candidates(species)
  if #names==0 then return abilities(species)end
  local first=assert(byName[key(names[1])]).number
  return{first,names[2]and assert(byName[key(names[2])]).number or first}
 end
 local name=P.abilityName
 P.abilityName=function(number)local info=byNumber[tonumber(number)];return info and info.name or name(number)end
 local description=Summary.abilityDescription
 Summary.abilityDescription=function(number,...)
  local info=byNumber[tonumber(number)]
  if info then return info.shortEffect or info.effect or info.name end
  return description(number,...)
 end
 local function assign(mon)
  if not mon or mon.isEgg then return end
  local inherited=mon.dexAbility or(type(mon.ability)=='string'and mon.ability)
  local selected=inherited and byName[key(inherited)]
  if not selected then
   local pair=P.abilities(P.speciesOf(mon))
   local slot=tonumber(mon.abilityNum)
   if slot==nil then slot=(tonumber(mon.personality)or 0)%2 end
   local info=byNumber[pair[slot+1]or pair[1]]
   if info then selected=byName[key(info.name)]end
  end
  if selected then
   mon.dexAbility=selected.info.name;mon.ability=selected.number;mon.abilityId=selected.number
   mon.abilityName=nil
   local info=mod.exports.statsBySpecies(P.keyName(P.speciesOf(mon)))
   for _,entry in ipairs(info and info.abilities or{})do
    if key(entry.name)==key(mon.dexAbility)then mon.dexAbilityHidden=entry.hidden==true end
   end
  end
 end
 local normalize=SaveMon.normalize
 SaveMon.normalize=function(mon)local result=normalize(mon);assign(result);return result end
 local function party(list)for _,mon in ipairs(list or{})do assign(mon.mon or mon)end end
 mod.events:on('game.ready',function(ev)
  local game=ev and ev.game;if not game then return end
  local saves={};if game.save then saves[#saves+1]=game.save end;if game.session then saves[#saves+1]=game.session end
  for _,save in ipairs(saves)do
   party(save.party)
   for _,box in pairs(save.boxes or{})do party(box.mons or box)end
   for _,box in pairs(save.storage and save.storage.boxes or{})do party(box.mons)end
   local sidecar=save.modData and save.modData.firered_game3
   for _,box in pairs(sidecar and sidecar.storage and sidecar.storage.boxes or{})do party(box.mons)end
  end
 end,1200)
 mod.events:on('pokemon.created',function(ev)if ev then assign(ev.mon or ev.pokemon)end end,1200)
 mod.events:on('pokemon.evolved',function(ev)
  local mon=ev and ev.mon;if not mon then return end
  local names=candidates(P.speciesOf(mon));local legal=false
  local info=mod.exports.statsBySpecies(P.keyName(P.speciesOf(mon)))
  if mon.dexAbilityHidden then
   for _,entry in ipairs(info and info.abilities or{})do if entry.hidden then mon.dexAbility=entry.name;legal=true;break end end
  end
  for _,name in ipairs(names)do if key(name)==key(mon.dexAbility)then legal=true end end
  if not legal then mon.dexAbility=nil end
  assign(mon)
 end,1200)
 return{assign=assign,byNumber=byNumber,byName=byName}
end
