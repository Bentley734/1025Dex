-- SPDX-License-Identifier: GPL-3.0-or-later
-- Canonical, species-checked teaching into native numeric move/PP arrays.
return function(mod,models)
 local P=require('src.core.game3.pokemon')
 local function choices(mon)
  local info=mod.exports.statsBySpecies(P.keyName(P.speciesOf(mon)))
  if not info or mon.isEgg then return{}end
  local result,seen={},{}
  local function add(row,method)
   if method=='level'and(row.level or 1)>(mon.level or 1)then return end
   local move=models.registry.resolve(row.move)
   if not move or seen[move.numId]then return end
   for _,number in ipairs(mon.moves or{})do if number==move.numId then return end end
   seen[move.numId]=true;result[#result+1]={id=move.id,number=move.numId,name=move.name,method=method}
  end
  for _,row in ipairs(info.movesFull or{})do add(row,'level')end
  for _,method in ipairs({'machine','tutor','egg'})do for _,row in ipairs(info.movesByMethod and info.movesByMethod[method]or{})do add(row,method)end end
  table.sort(result,function(a,b)return a.name<b.name end);return result
 end
 mod.exports.learnableMoves=choices
 require('src.core.game3.move_learn').relearnableMoves=function(mon)
  local out={};for _,row in ipairs(choices(mon))do out[#out+1]=row.number end;return out
 end
 mod.exports.teachModernMove=function(mon,id,slot)
  local wanted=models.registry.resolve(id);if not wanted then return false end
  local legal=false;for _,row in ipairs(choices(mon))do if row.number==wanted.numId then legal=true end end
  if not legal then return false end
  mon.moves=mon.moves or{};slot=slot or(#mon.moves<4 and #mon.moves+1)
  if not slot or slot<1 or slot>4 or slot>#mon.moves+1 then return false end
  mon.moves[slot]=wanted.numId;mon.pp=mon.pp or{};mon.maxPp=mon.maxPp or{}
  mon.pp[slot]=wanted.pp;mon.maxPp[slot]=wanted.pp;return true
 end
end
