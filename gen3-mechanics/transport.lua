-- SPDX-License-Identifier: GPL-3.0-or-later
-- Translate only the private mechanics bus. Native payloads remain native for
-- the engine and other mods. This module does not install global patches.
return function(models,adapterFor)
 local F,registry=models.class,models.registry
 local Types=require('src.core.game3.battle.types')
 local transport={}
 local function copy(value)local result={};for k,v in pairs(value or{})do result[k]=v end;return result end
 function transport.context(native)
  assert(native and native.battle,'Gen 3 mechanics context requires a battle')
  local adapter=assert(adapterFor(native.battle),'Gen 3 mechanics adapter unavailable')
  local battle=F.bind(native.battle,adapter)
  local result=copy(native);result.battle=battle
  for _,key in ipairs({'user','target','battler','previous','source'})do
   local value=native[key]
   if type(value)=='table'and value.mon then result[key]=battle:view(value.mon,value)end
  end
  if native.mon then result.mon=battle:view(native.mon)end
  local number=native.moveNum or native.moveId or(native.move and(native.move.numId or native.move.id))
  if number then
   local move=assert(registry.resolve(number),'Unregistered move identity: '..tostring(number))
   result.move=copy(models.data.moves[move.id]or move)
   result.move.id=move.id;result.moveId=move.id;result.moveNum=move.numId
  end
  result.rng=native.rng or function(lo,hi)return adapter:roll(lo,hi)end
  return result
 end
 function transport.event(name,native)
  if not native or not native.battle then return models.events:emit(name,native)end
  return models.events:emit(name,transport.context(native))
 end
 function transport.status(native)
  local context=transport.context(native)
  local effect=F.moveEffectRecordFor(models.data,context.move.effect)
  local moveContext=context.battle.__nativeMoveContext
  if effect and effect.accuracyChecked and moveContext and not moveContext:accuracyCheck('normal',true)then return true end
  if(not effect or type(effect.run)~='function')and type(F.MOVE_EFFECTS[context.move.effect])=='function'then
   F.MOVE_EFFECTS[context.move.effect](context.battle,context.user,context.target)
   return true
  end
  if not effect or type(effect.run)~='function'then return false end
  effect.run(context.battle,context.user,context.target)
  return true
 end
 function transport.hook(name,next,native)
  local context=transport.context(native)
  local function downstream(changed)
   changed=changed or context
   local restored=copy(native)
   restored.opts=changed.opts;restored.rng=changed.rng
   for _,key in ipairs({'user','target'})do
    restored[key]=context.battle:native(changed[key])or native[key]
   end
   local value,info=next(restored)
   if name=='battle.damage'and type(info)=='table'then
    info=copy(info);info.crit=info.critical;info.typeMult=(info.effectiveness or 1)*10
   end
   return value,info
  end
  local value,info=models.hooks:call(name,downstream,context)
  if name~='battle.damage'or type(info)~='table'then return value,info end
  info=copy(info)
  info.critical=info.crit==true
  info.effectiveness=(info.typeMult or 10)/10
  local move=context.move
  info.moveType=Types.ID[move.type=='PSYCHIC_TYPE'and 'PSYCHIC'or move.type]
  assert(info.moveType~=nil,'Gen 3 type registry missing '..tostring(move.type))
  info.power=move.power
  info.typeFlags={super=info.effectiveness>1,notVery=info.effectiveness>0 and info.effectiveness<1,immune=info.effectiveness==0}
  return value,info
 end
 return transport
end
