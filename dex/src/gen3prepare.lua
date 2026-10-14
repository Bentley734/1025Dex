-- Register real modern move identities before species learnsets are checked.
return function(mod)
 local P=require('src.core.game3.pokemon')
 local Moves=require('src.core.game3.battle.moves')
 local api=assert(load(assert(mod:read('src/api.lua'))))()
 api(mod)
 local byId={}
 for _,id in ipairs(mod.exports.listMoves())do
  local info=assert(mod.exports.moveById(id));local number=assert(tonumber(info.moveId))
  byId[id]=number
  do
   local record={id=id,index=number,name=info.name,
    type=info.type=='PSYCHIC_TYPE'and 'PSYCHIC'or info.type,
    power=tonumber(info.power)or 0,accuracy=tonumber(info.accuracy)or 100,
    pp=tonumber(info.pp)or 1,category=info.damageClass,effect=0,priority=tonumber(info.priority)or 0}
   if number<=354 then record.effect=Moves.get(number).effect end
   if mod.content.moves:get(id)then mod.content.moves:patch(id,record)
   else mod.content.moves:register(id,record)end
  end
 end
 -- The native species writer resolves numeric slots through these names.
 local function names()
  for id,number in pairs(byId)do
   if number>354 then P._moveNames[number]=assert(mod.exports.moveById(id)).name end
  end
 end
 names();P.onReload(names,'1025dex_modern_move_names')
 local nativeNumber=Moves.numForName
 Moves.numForName=function(id)return byId[id]or nativeNumber(id)end
 return byId
end
