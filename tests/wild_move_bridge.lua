local checks=0
local function eq(a,b,m)checks=checks+1;assert(a==b,m..': '..tostring(a)..' ~= '..tostring(b))end
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local R=assert(loadfile('dex/src/gen3moves.lua'))();local rules=assert(loadfile('dex/data/species/generated/gen3_moves.lua'))()
local game='firered';local roster=assert(loadfile('encounters/roster.lua'))();local names={}
for _,m in ipairs(roster)do names[m.name]=m.id>386 and m.id+64 or m.id end
local P={_speciesMeta={},speciesFromName=function(n)return names[n]end,
 keyName=function(s)return roster[s>450 and s-64 or s].name end}
package.loaded['src.core.game3.pokemon']=P
package.loaded['src.core.GameVersion']={get=function()return game end,generation=function()return 3 end}
package.loaded['src.core.game3.runtime']={getSession=function()return {engineOptions={fireredGenEncounterPool=17}}end}
package.loaded['src.core.game3.options']={block=function(o)return o end}
package.loaded['src.import.gba.map_catalog']={resolve=function(n)return n end}
package.loaded['src.core.game3.profile']={forSession=function()return {id=game}end}
package.loaded['src.core.game3.constants']={of=function()return {require=function()return 1 end}end}
package.loaded['src.core.game3.scripting.flags']={getFlag=function()return false end}
package.loaded['src.core.game3.scripting.space']={}
local E={onStep=function()return {species=4,level=3,moves={53}}end}
package.loaded['src.core.game3.encounters']=E
local B={start=function(_,_,foe)return foe end};package.loaded['src.core.game3.battle_bridge']=B
local mod={exports={},log={info=function()end,warn=function()end},read=function(_,p)return read('encounters/'..p)end}
mod.exports.vanillaWildMoves=function(sp,lv)
 local dex=sp>450 and sp-64 or sp;local row=rules.extended[dex]
 if row then return R.wildAtLevel(row,lv,function()return 20 end)end
 return R.atLevel(rules.native[game=='emerald'and'rse'or'frlg'][dex],lv,function()return 20 end)
end
assert(loadfile('encounters/main.lua'))()(mod)
for _,family in ipairs({'firered','leafgreen','emerald'})do game=family
 for dex=1,1025 do for _,lv in ipairs({1,3,5,10,15,30,31,50,70,100})do
  local sp=dex>386 and dex+64 or dex
  local foe={species=sp,level=lv,moves={53,63,126,152},pp={1,2,3,4},personality=12345,item=99,hp=20}
  local result=B.start(mod,{},foe,{wild=true,__completeDexExact=true})
  local moves,pp,maxPp=mod.exports.vanillaWildMoves(sp,lv)
  eq(result==foe,false,'caller source is not mutated');eq(foe.moves[1],53,'caller moves unchanged')
  eq(result.personality,12345,'personality retained');eq(result.item,99,'held item retained');eq(result.hp,20,'health retained')
  eq(#result.moves,#moves,'exact natural move count')
  if dex>386 then eq(#result.moves>=3,true,'visible/DexNav wild has at least three moves')end
  for i,m in ipairs(moves)do eq(result.moves[i],m,'clean wild move');eq(result.pp[i],pp[i],'clean wild PP');eq(result.maxPp[i],maxPp[i],'clean maximum PP')end
 end end
end
local special={species=4,level=3,moves={53}}
for _,opts in ipairs({{}, {wild=true,roamer=true},{wild=true,wildScripted=true},{wild=true,link=true},{wild=true,firstBattle=true},{wild=true,trainerId=1}})do
 eq(B.start(mod,{},special,opts),special,'trainer/tutorial/scripted/roamer/link data preserved')
end
local result=B.start(mod,{},E.onStep('FR_ROUTE_1','land'),{wild=true})
local moves=mod.exports.vanillaWildMoves(result.species,result.level)
for i,m in ipairs(moves)do eq(result.moves[i],m,'rolled replacement uses final species and level')end
-- Execute the actual option-definition block; old saved settings are not exposed.
local main=read('dex/main.lua');local a=assert(main:find('return function(mod)',1,true));local b=assert(main:find('  local nationalDex',a,true))
local define=assert(load(main:sub(a,b-1)..'\nend'))()
for _,gen in ipairs({1,2,3})do
 package.loaded['src.core.GameVersion'].generation=function()return gen end
 local rows;define({options={define=function(_,r)rows=r end}})
 local legacy=false;for _,r in ipairs(rows)do if r.key=='stats'or r.key=='moves'then legacy=true end end
 eq(legacy,gen~=3,'legacy options hidden only in Game3')
end
print('PASS: '..checks..' production wild bridge / 1025 species / final species-level moves / saved caller data / options checks')
