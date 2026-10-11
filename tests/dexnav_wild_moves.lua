-- Real DexNav resolver/generator consumes the installed Dex API unchanged.
-- texlua tests/dexnav_wild_moves.lua DEXNAV_ROOT ENGINE_FIXTURES [PREVIOUS_RULES]
local nav=assert(arg[1]);local engine=arg[2] or '../move-audit';local checks=0
local function eq(a,b,m)checks=checks+1;assert(a==b,m..': '..tostring(a)..' ~= '..tostring(b))end
local R=assert(loadfile('dex/src/gen3moves.lua'))()
local rules=assert(loadfile('dex/data/species/generated/gen3_moves.lua'))()
local Builtin=assert(loadfile(engine..'/builtin_moves.lua'))()
local game='firered';local active=true
package.loaded['src.core.GameVersion']={get=function()return game end}
local P={national=function(sp)return sp>450 and sp-64 or sp end,
 movePp=function(n)return assert(Builtin[n]).pp end,onReload=function()end}
local mod={exports={}}
R.install(mod,P,function(dex)return dex>386 and dex+64 or dex end,rules)
local D=assert(loadfile(nav..'/src/data.lua'))()
D.init({pokemon=function()return {movesAtLevel=function()return {33,45},{35,40}end}end},
 {find=function()return active and mod or nil end})
local G=assert(loadfile(nav..'/src/generator.lua'))()
G.init({EGG_MOVE={[1]=100},band=function()return 1 end})
for _,family in ipairs({'firered','leafgreen','emerald'})do game=family
 for dex=1,1025 do for lv=1,100 do
  local sp=dex>386 and dex+64 or dex
  local expected,expectedPp=mod.exports.vanillaWildMoves(sp,lv)
  local moves,pp,bonus=G.moves(D.resolver,{tmhm={'53'}},sp,lv,function()return 0 end,1000)
  eq(bonus,nil,'no bonus TM while Dex is active')
  local seen={};local count=0
  for i=1,4 do
   eq(moves[i],expected[i]or 0,'preview matches actual wild API')
   eq(pp[i],expectedPp[i]or 0,'preview has real Gen3 PP')
   if moves[i]~=0 then
    count=count+1;eq(seen[moves[i]],nil,'preview has distinct moves');seen[moves[i]]=true
    eq(pp[i]>0,true,'preview move can be used')
   end
  end
  if dex>386 then eq(count>=3,true,'every added DexNav wild has at least three moves')end
 end end
end
active=false;eq(D.resolver.strictLevelUpMoves(),false,'standalone behavior retained')
local moves,pp,bonus=G.moves(D.resolver,{tmhm={'53'}},4,3,function()return 0 end,1000)
eq(bonus,53,'standalone bonus retained');eq(moves[1],53,'standalone TM still generated')
-- Previous release data verifies the native schedules, machine permissions,
-- and canonical learn levels stay unchanged while wild compatibility expands.
if arg[3]then
 local old=assert(loadfile(arg[3]))()
 for _,family in ipairs({'frlg','rse'})do for dex=1,386 do
  local before,after=old.native[family][dex],rules.native[family][dex]
  eq(#before,#after,'native learnset size preserved')
  for i,row in ipairs(before)do eq(row[1],after[i][1],'native learn level preserved');eq(row[2],after[i][2],'native move preserved')end
 end end
 for dex=387,1025 do
  local before,after=old.extended[dex],rules.extended[dex]
  eq(before.version,after.version,'modern reference version preserved')
  eq(#before.learnset,#after.learnset,'canonical progression preserved')
  for i,row in ipairs(before.learnset)do eq(row[1],after.learnset[i][1],'canonical level preserved');eq(row[2],after.learnset[i][2],'canonical native move preserved')end
  eq(#before.tmhm,#after.tmhm,'machine permission count preserved')
  for i,move in ipairs(before.tmhm)do eq(move,after.tmhm[i],'machine permission preserved')end
 end
end
print('PASS: '..checks..' installed Dex API / DexNav previews / three distinct usable moves / levels 1-100 / FRLG and Emerald / native and TM regression checks')
