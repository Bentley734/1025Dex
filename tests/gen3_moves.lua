local engine=arg[1] or '../move-audit';local checks=0
local function eq(a,b,why)checks=checks+1;assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b))end
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
package.loaded['src.core.Logger']={warn=function()end}
package.loaded['src.mods.Merge']=assert(loadfile(engine..'/Merge.lua'))()
local S=assert(loadfile(engine..'/Schemas.lua'))();package.loaded['src.mods.Schemas']=S
local Builtin=assert(loadfile(engine..'/builtin_moves.lua'))()
local Shape=assert(loadfile(arg[2] or 'dex/src/gen3shape.lua'))();local Rules=assert(loadfile('dex/src/gen3moves.lua'))()
local rules=Rules.load(function(p)return read('dex/'..p)end)
local roster=assert(loadfile('encounters/roster.lua'))()
local machines=assert(loadfile('tests/fixtures/gen3_machine_moves.lua'))()
local family='firered';package.loaded['src.core.GameVersion']={get=function()return family end,generation=function()return 3 end}
local P={_names={},_moveNames={},_learnsets={},_tmhm={machines=machines,learnsets={}},_speciesMeta={},_evolutions={}}
for n,m in pairs(Builtin)do P._moveNames[n]=m.name end
P.national=function(n)return n>450 and n-64 or n end
P.speciesFromNational=function(n)return n>386 and n+64 or n end
P.movePp=function(n)return Builtin[n].pp end
P.learnset=function(n)return P._learnsets[n]or{}end
local source=read(engine..'/pokemon.lua')
local a=assert(source:find('function Pokemon.canLearnTmIndex(',1,true));local b=assert(source:find('local function move_max_pp(',a,true))
assert(load(source:sub(a,b-1),'production machine checks','t',setmetatable({Pokemon=P},{__index=_G})))()
package.loaded['src.core.game3.items_data']={toNumericId=function(n)return tonumber(n)end}
package.loaded['src.core.game3.pokemon']=P
package.loaded['src.core.game3.battle.moves']={names=P._moveNames}
local reload={};P.onReload=function(fn)reload[#reload+1]=fn end
local mod={exports={}}
local nativeRow={lo=123,hi=456};P._tmhm.learnsets[4]=nativeRow
local national={register={}};local records,ops={},{ }
for _,m in ipairs(roster)do
 local slot=P.speciesFromNational(m.id);P._names[slot]=m.name
 if m.id>386 then
  local input={id=m.name,name=m.name,dex=m.id,learnset={{level=1,move='TACKLE'}},tmhm=Rules.machineIds(rules,m.id,P._moveNames)}
  national.register[m.name]=input;records[m.name]=Shape.record(input);ops[m.name]=true
 end
end
local registry={ops=ops,get=function(_,id)return records[id]end,
 register=function(_,id,row)records[id]=row;ops[id]=true end,override=function(_,id,row)records[id]=row;ops[id]=true end}
local legacy=Shape.record({id='STARAVIA',name='STARAVIA',dex=397,learnset={}})
eq(#legacy.tmhm,0,'reproduce old second-pass missing permissions')
mod.content={pokemon=registry};mod.path='fixture';mod.log={info=function()end,warn=function()end};mod.assets={path=function(_,p)return 'fixture/'..p end}
assert(loadfile('dex/src/nationaldex.lua'))()(mod,nil,national,nil,3,'modern',nil,Shape)
S.REGISTRIES.pokemon.gen3Write(P,registry)
local function verify()
 for dex,row in pairs(rules.extended)do
  local wanted={};for _,move in ipairs(row.tmhm)do wanted[move]=true end
  local species=P.speciesFromNational(dex)
  for bit,move in pairs(machines)do eq(P.canLearnTmIndex(species,bit),wanted[move]==true,'machine '..dex..':'..move)end
 end
end
verify()
local star=P.speciesFromNational(397)
eq(P.canLearnTmItem(star,340),true,'Staravia HM02 Fly')
eq(P.canLearnTmItem(star,328),true,'Staravia TM40 Aerial Ace')
Rules.install(mod,P,P.speciesFromNational,rules)
for n in pairs(rules.extended)do P._tmhm.learnsets[P.speciesFromNational(n)]={lo=0,hi=0}end
verify();eq(P._tmhm.learnsets[4],nativeRow,'native machine row untouched')
P._tmhm={machines=machines,learnsets={}};for _,fn in ipairs(reload)do fn()end;verify()
-- Execute the complete changed Game3 installation path and subsequent real
-- registration pass. The unchanged evolution subsystem is a boundary fixture.
package.loaded['src.core.game3.dex']={countSeen=function()return 0 end,countCaught=function()return 0 end}
package.loaded['src.core.game3.pokedex_data']={getOrderList=function()return {}end}
P.speciesOf=function(m)return m.species end
mod.read=function(_,p)
 if p=='src/gen3evolutions.lua' then return 'return {install=function()end}'end
 return read('dex/'..p)
end
Shape.install(mod,national)
assert(loadfile('dex/src/nationaldex.lua'))()(mod,nil,national,nil,3,'modern',nil,Shape)
S.REGISTRIES.pokemon.gen3Write(P,registry);verify()
for _,game in ipairs({'firered','leafgreen','emerald'})do family=game
 for dex=1,1025 do
  local species=P.speciesFromNational(dex);local row=rules.extended[dex]
  local set=row and row.wildLearnset or rules.native[game=='emerald' and 'rse' or 'frlg'][dex]
  for lv=1,100 do
   local moves,pp,maxPp=mod.exports.vanillaWildMoves(species,lv);eq(#moves>0 and #moves<=4,true,'valid move count')
   if row then eq(#moves>=3,true,'added wild has at least three moves '..dex..':'..lv)end
   local allowed={};for _,r in ipairs(set)do if r[1]<=lv then allowed[r[2]]=true end end
   if row then for _,id in ipairs(row.wildStarters)do allowed[id]=true end end
   local seen={}
   for i,move in ipairs(moves)do
    eq(allowed[move]==true,true,'eligible comparable/initial moves at '..dex..':'..lv)
    eq(move~=165 and move>=1 and move<=354,true,'implemented Gen3 move, never Struggle')
    eq(seen[move],nil,'no duplicate moves');seen[move]=true
    eq(pp[i]>0 and pp[i]==P.movePp(move) and pp[i]==maxPp[i],true,'correct usable Gen3 PP')
   end
  end
 end
 for lv=1,30 do local moves=mod.exports.vanillaWildMoves(4,lv);for _,m in ipairs(moves)do eq(m~=53,true,'Charmander cannot start Flamethrower early')end end
 local moves=mod.exports.vanillaWildMoves(4,31);local found=false;for _,m in ipairs(moves)do if m==53 then found=true end end;eq(found,true,'Charmander Flamethrower at 31')
end
local blip=mod.exports.vanillaWildMoves(P.speciesFromNational(824),1)
local blipSeen={};for _,id in ipairs(blip)do blipSeen[id]=true end
eq(blipSeen[318],true,'Blipbug Struggle Bug becomes Silver Wind')
eq(blipSeen[141],true,'Blipbug has low-power Leech Life reserve')
eq(blipSeen[81],true,'Blipbug has String Shot reserve')
local leaf=mod.exports.vanillaWildMoves(P.speciesFromNational(906),1)
local leafSeen={};for _,id in ipairs(leaf)do leafSeen[id]=true end
eq(leafSeen[22],true,'Sprigatito Leafage becomes Vine Whip')
eq(leafSeen[10] and leafSeen[39],true,'Sprigatito keeps Scratch and Tail Whip')
local low=mod.exports.vanillaWildMoves(P.speciesFromNational(487),1)
local lowSeen={};for _,id in ipairs(low)do lowSeen[id]=true end
eq(lowSeen[310],true,'Giratina Shadow Sneak becomes Astonish')
eq(lowSeen[82],nil,'Giratina does not borrow level-7 Dragon Breath early')
local support=mod.exports.vanillaWildMoves(P.speciesFromNational(876),25)
local supportSeen={};for _,id in ipairs(support)do supportSeen[id]=true end
eq(supportSeen[270],true,'Indeedee After You uses Helping Hand')
eq(supportSeen[144],nil,'support move does not accidentally become Transform')
for _,row in pairs(rules.extended)do
 local canonical={};for _,entry in ipairs(row.learnset)do canonical[entry[1]..':'..entry[2]]=true end
 for _,entry in ipairs(row.wildLearnset)do
  local unusual=entry[2]==165 or entry[2]==166 or entry[2]==118 or entry[2]==144
  eq(not unusual or canonical[entry[1]..':'..entry[2]]==true,true,'no invented Struggle/Sketch/Metronome/Transform placeholders')
 end
end
print('PASS: '..checks..' production registry / 639 machine permissions / reload / 1025 species at levels 1-100 / FRLG and Emerald checks')
