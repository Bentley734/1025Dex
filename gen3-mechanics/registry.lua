-- SPDX-License-Identifier: GPL-3.0-or-later
-- Real modern move identities for the numeric Gen 3 battle/save interface.
-- Metadata is owned by 1025Dex; no modern move is replaced with an older one.
return function(dex, nativeMoves)
 local byNumber,byId,aliases={},{},{}
 local function normal(id)return tostring(id):upper():gsub('[^A-Z0-9]','')end
 for _,id in ipairs(dex.listMoves())do
  local info=assert(dex.moveById(id),'Missing modern move metadata: '..id)
  local number=assert(tonumber(info.moveId),'Missing numeric move identity: '..id)
  assert(number>=1 and number<=1023,'Move identity exceeds Gen 3 mod schema: '..id)
  assert(not byNumber[number],'Duplicate numeric move identity: '..id)
  local record={}
  for key,value in pairs(info)do record[key]=value end
  record.id=id;record.numId=number;record.index=number
  record.category=info.damageClass
  record.type=info.type=='PSYCHIC_TYPE' and 'PSYCHIC' or info.type
  record.power=tonumber(info.power)or 0
  record.accuracy=tonumber(info.accuracy)or 100
  record.pp=tonumber(info.pp)or 0
  byNumber[number]=record;byId[id]=record;aliases[normal(id)]=id
  if info.strippedId then aliases[normal(info.strippedId)]=id end
 end
 local function resolve(id)
  if type(id)=='table'then id=id.id or id.numId end
  if type(id)=='number'then return byNumber[id]end
  return id and byId[aliases[normal(id)]]
 end
 return {byNumber=byNumber,byId=byId,resolve=resolve,
  numberFor=function(id)local row=resolve(id);return row and row.numId end,
  -- Unmodified native rows remain available for native script/animation
  -- lookup. Executed mechanics use the modern record through the adapter.
  native=nativeMoves}
end
