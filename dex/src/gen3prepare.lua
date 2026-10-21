-- Register real modern move identities before species learnsets are checked.
return function(mod)
 local P=require('src.core.game3.pokemon')
 local Moves=require('src.core.game3.battle.moves')
 local api=assert(load(assert(mod:read('src/api.lua'))))()
 api(mod)
 -- A native table extension alone is invisible to registry cross-validation.
 if not mod.content.type_chart:get('FAIRY')then
  mod.content.type_chart:register('FAIRY',{name='FAIRY',category='special',index=18})
 end
 -- Modern API IDs omit spaces; native registry IDs retain underscores.
 -- Reuse native identities instead of claiming their numeric slots twice.
 local canonical={}
 for _,id in ipairs(mod.exports.listMoves())do
  local info=mod.exports.moveById(id);local number=tonumber(info.moveId)
  if number and number<=354 then canonical[id]=(Moves.constName and Moves.constName(number))or id end
 end
 local registry=mod.content.moves
 for _,method in ipairs({'get','register','patch','override','remove'})do
  local original=registry[method]
  if original then registry[method]=function(self,id,row,...)
   local key=canonical[id]or id
   if type(row)=='table'and row.id and row.id~=key then
    local copy={};for k,v in pairs(row)do copy[k]=v end;copy.id=key;row=copy
   end
   return original(self,key,row,...)
  end end
 end
 -- Species records must reference the same native identity as their moves.
 local pokemon=mod.content.pokemon
 if pokemon then
  for _,method in ipairs({'register','patch','override'})do
   local original=pokemon[method]
   if original then pokemon[method]=function(self,id,row,...)
    if type(row)=='table'and(row.learnset or row.tmhm)then
     local copy={};for k,v in pairs(row)do copy[k]=v end
     if type(row.learnset)=='table'then
      copy.learnset={}
      for i,entry in ipairs(row.learnset)do
       local e={};for k,v in pairs(entry)do e[k]=v end
       e.move=canonical[e.move]or e.move;copy.learnset[i]=e
      end
     end
     if type(row.tmhm)=='table'then
      copy.tmhm={};for i,move in ipairs(row.tmhm)do copy.tmhm[i]=canonical[move]or move end
     end
     row=copy
    end
    return original(self,id,row,...)
   end end
  end
 end
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
 -- Native tables belong to the loader until content validation/commit ends.
 local committed=false
 local function names()
  if not committed then return end
  for id,number in pairs(byId)do
   if number>354 then P._moveNames[number]=assert(mod.exports.moveById(id)).name end
  end
 end
 P.onReload(names,'1025dex_modern_move_names')
 mod.events:on('mods.loaded',function()committed=true;names()end)
 local nativeNumber=Moves.numForName
 Moves.numForName=function(id)return byId[id]or nativeNumber(id)end
 return byId
end
