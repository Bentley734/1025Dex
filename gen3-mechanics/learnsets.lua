-- SPDX-License-Identifier: GPL-3.0-or-later
-- Rebuild native level-up arrays from canonical data without move aliases.
return function(mod,registry)
 local P=require('src.core.game3.pokemon')
 local function read(path)return assert(load(assert(mod:read('dex/'..path))))()end
 local index=read('data/moves/generated/learnsets/index.lua')
 local shards={};local sets={}
 for id,number in pairs(index)do
  if not shards[number]then shards[number]=read(string.format('data/moves/generated/learnsets/%03d.lua',number))end
  local list=shards[number][id]
  if list then
   local rows={}
   for _,row in ipairs(list)do
    rows[#rows+1]={math.max(1,tonumber(row.level)or 1),assert(registry.numberFor(row.move),'Missing canonical learned move '..row.move)}
   end
   table.sort(rows,function(a,b)if a[1]==b[1]then return a[2]<b[2]end;return a[1]<b[1]end)
   sets[id]=rows
  end
 end
 local function apply()
  for id,rows in pairs(sets)do
   local species=P.speciesFromName(id)
   if species then P._learnsets[species]=rows end
  end
 end
 P.onReload(apply,'1025dex_canonical_modern_learnsets');apply()
 mod.exports.vanillaWildMoves=function(species,level)
  local list=P.learnset(species);local moves,pp,maxPp={},{},{}
  for _,row in ipairs(list)do
   if row[1]>(tonumber(level)or 1)then break end
   local duplicate=false;for _,move in ipairs(moves)do if move==row[2]then duplicate=true end end
   if not duplicate then
    if #moves==4 then table.remove(moves,1);table.remove(pp,1);table.remove(maxPp,1)end
    local maximum=assert(registry.resolve(row[2])).pp
    moves[#moves+1]=row[2];pp[#pp+1]=maximum;maxPp[#maxPp+1]=maximum
   end
  end
  return moves,pp,maxPp
 end
 return{sets=sets,apply=apply}
end
