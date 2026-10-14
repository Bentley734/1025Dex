-- SPDX-License-Identifier: GPL-3.0-or-later
-- Native lookups use the same canonical IDs as modern mechanics and saves.
return function(mod,registry,models)
 local Moves=require('src.core.game3.battle.moves')
 local Pokemon=require('src.core.game3.pokemon')
 local Types=require('src.core.game3.battle.types')
 local function copy(row)local result={};for k,v in pairs(row or{})do result[k]=v end;return result end
 Types.ID.FAIRY=18
 Types.NAME[18]='FAIRY'
 require('src.mods.Schemas').gen3View.TYPES[18]='FAIRY'
 local typeName=Types.name
 Types.name=function(id)if tonumber(id)==18 then return 'FAIRY'end;return typeName(id)end
 local function modernName(id)
  for name,number in pairs(Types.ID)do if number==tonumber(id)then return name=='PSYCHIC'and 'PSYCHIC_TYPE'or name end end
 end
 local chart=assert(load(assert(mod:read('gen3-mechanics/type_chart.lua'))))()(models.data)
 Types.effectiveness=function(attacker,first,second)
  local defenders={modernName(first)}
  if second~=nil and second~=first then defenders[#defenders+1]=modernName(second)end
  return chart.effectiveness(modernName(attacker),defenders)/10
 end
 -- Native AI/type-calculation paths consult this table directly.
 local tableRows={}
 for _,row in ipairs(models.data.type_chart.matchups)do
  local a=Types.ID[row.attacker=='PSYCHIC_TYPE'and 'PSYCHIC'or row.attacker]
  local d=Types.ID[row.defender=='PSYCHIC_TYPE'and 'PSYCHIC'or row.defender]
  if a and d then tableRows[#tableRows+1]=a;tableRows[#tableRows+1]=d;tableRows[#tableRows+1]=row.multiplier end
 end
 tableRows[#tableRows+1]=-1;tableRows[#tableRows+1]=-1;tableRows[#tableRows+1]=0
 Types.TABLE=tableRows
 local get,name,number=Moves.get,Moves.constName,Moves.numForName
 Moves.get=function(id)
  local modern=registry.resolve(id)
  if not modern then return get(id)end
  local row=copy(models.data.moves[modern.id]or modern)
  row.id=modern.id;row.numId=modern.numId
  local target=modern.target
  local targets={['selected-pokemon']=0,['random-opponent']=4,['all-opponents']=8,
   ['user']=16,['all-other-pokemon']=32,['users-field']=64,['opponents-field']=128}
  row.target=targets[target]or 0
  if modern.numId<=354 then row.flags=get(modern.numId).flags end
  row.type=assert(Types.ID[row.type=='PSYCHIC_TYPE'and 'PSYCHIC'or row.type],'Unknown move type')
  -- Primary/secondary effects are dispatched by the private combat bus.
  row.effect=0;row.effectId=nil;row.secondaryChance=0
  local modernEffect=models.data.move_effects[(models.data.moves[modern.id]or{}).effect]
  local active=models.activeEffect
  if active and active.id==modern.id and active.statusOnly then row.power=0;row.category='status'end
  if row.category=='status'and(not modernEffect or not modernEffect.run)and modern.numId<=354 then
   local original=get(modern.numId)
   row.effect=original.effect;row.effectId=original.effectId
  elseif row.category~='status'and(tonumber(row.power)or 0)==0 then
   -- Computed-power moves still enter native hit sequencing; the modern
   -- formula computes their power/damage from the real battle state.
   row.power=1
  end
  return row
 end
 Moves.constName=function(id)local row=registry.resolve(id);return row and row.id or name(id)end
 Moves.numForName=function(id)return registry.numberFor(id)or number(id)end
 local moveName,movePp=Pokemon.moveName,Pokemon.movePp
 Pokemon.moveName=function(id)local row=registry.resolve(id);return row and row.name or moveName(id)end
 Pokemon.movePp=function(id)local row=registry.resolve(id);return row and row.pp or movePp(id)end
 local battleMove=Pokemon.battleMove
 Pokemon.battleMove=function(id)
  local modern=registry.resolve(id)
  if not modern then return battleMove(id)end
  local row=Moves.get(id);row.power=modern.power;return row
 end
 local Summary=require('src.core.game3.summary_data')
 local description=Summary.moveDescription
 Summary.moveDescription=function(id,...)
  local row=registry.resolve(id)
  if row and row.numId>354 then return row.shortEffect or row.effect or row.name end
  return description(id,...)
 end
 local nativeTypes=Pokemon.types
 Pokemon.types=function(species)
  local key=type(species)=='string'and species or Pokemon.keyName(type(species)=='table'and Pokemon.speciesOf(species)or species)
  local info=key and mod.exports.statsBySpecies(key)
  if not info or not info.types then return nativeTypes(species)end
  local result={}
  for i,t in ipairs(info.types)do result[i]=assert(Types.ID[t=='PSYCHIC_TYPE'and 'PSYCHIC'or t],'Unknown species type')end
  return result
 end
 local function restoreTypes()
  for species in pairs(Pokemon._names or{})do
   local row=mod.exports.statsBySpecies(Pokemon.keyName(species))
   if row and row.types then
    local types={}
    for i,name in ipairs(row.types)do types[i]=Types.ID[name=='PSYCHIC_TYPE'and'PSYCHIC'or name]end
    if types[1]then Pokemon._types[species]={types[1],types[2]or types[1]}end
   end
  end
 end
 restoreTypes();Pokemon.onReload(restoreTypes,'1025dex_real_modern_types')
 -- The native schema writer has a closed 0..17 type-name map. Reapply the
 -- real type slots after its merge, independent of registry iteration order.
 local Schemas=require('src.mods.Schemas')
 local shape=Schemas.shapeFor('pokemon',Schemas.REGISTRIES.pokemon,3)
 local write=shape.write
 shape.write=function(target,content)write(target,content);restoreTypes()end
 return{moves=Moves,pokemon=Pokemon,types=Types}
end
