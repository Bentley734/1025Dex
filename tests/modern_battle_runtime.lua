local Runtime=require('src.mods.Runtime')
local GV=require('src.core.GameVersion')
local api=loader.exports['1025dex']
assert(api.__bootReport and not next(api.__bootReport.failed))
assert(loader.mods['1025dex'].state=='loaded')
local gen2=GV.generation()==2
local Battle=require(gen2 and 'src.battle.gen2.Battle' or 'src.battle.BattleState')
local Pokemon=require(gen2 and 'src.battle.gen2.Mon' or 'src.pokemon.Pokemon')
local function mon(id)
 local m=Pokemon.new(data,id,50,gen2 and {} or function(a,b)return b and math.floor((a+b)/2)or math.floor(a/2)end)
 m.stats.hp=1000;m.hp=1000
 return m
end
local function wrap(m,player)
 return {mon=m,def=data.pokemon[m.species],name=m.species,isPlayer=player,
 curStats=m.stats,curTypes=data.pokemon[m.species].types,curMoves=m.moves,
 stages={},shownHP=m.hp,statuses=data.statuses}
end
function testBattle(a,z)
 local p,e=mon(a or 'MEW'),mon(z or 'MEW')
 if gen2 then return Battle.new{data=data,party={p},wild=e,random=function()return 0 end}end
 local b=setmetatable({data=data,game={data=data,save={party={p},boxes={},inventory={}}},
 kind='wild',queue={},rng=function(a,b)return b and a or 0 end,fx={},turn=1,
 playerParty={p},enemyParty={e},ruleset={}},Battle)
 b.player=wrap(p,true);b.enemy=wrap(e,false);b.sides={{index=1,battlers={b.player}}, {index=2,battlers={b.enemy}}}
 Runtime.emit('battle.started',{battle=b,kind='wild'})
 return b
end
local function raw(w)return w.mon or w end
function testMove(b,id,enemy)
 local u,t=enemy and b.enemy or b.player,enemy and b.player or b.enemy
 raw(u).moves={{id=id,pp=50,maxPP=50}};if u.mon then u.curMoves=raw(u).moves end
 if gen2 then b:useMove(u,t,id)else b:performMove(u,t,raw(u).moves[1],false)end
end
local b=testBattle('BULBASAUR','SQUIRTLE')
assert(raw(b.player).ability=='Overgrow',tostring(raw(b.player).ability))
assert(raw(b.enemy).ability=='Torrent',tostring(raw(b.enemy).ability))
for _,id in ipairs({'TACKLE','GROWL','TAIL_WHIP','MOONBLAST','PLAYROUGH','DRAININGKISS','WILLOWISP','SWORDSDANCE','SHELLSMASH','PROTECT','SOAK','ROOST','UTURN','THUNDERWAVE'})do
 local mid=api.registeredMoveId(id)
 local b=testBattle()
 local ok,err=pcall(testMove,b,mid)
 print('MOVE-SMOKE',version,mid,ok,err,raw(b.player).hp,raw(b.enemy).hp,raw(b.enemy).status)
end
print('RUNTIME-ERRORS',#loader.errors)
for _,err in ipairs(loader.errors)do print('RUNTIME-ERROR',err)end

-- Assert outcomes, not just absence of exceptions.
for _,enemy in ipairs({false,true})do
 local b=testBattle();local target=raw(enemy and b.player or b.enemy);local before=target.hp
 testMove(b,api.registeredMoveId('MOONBLAST'),enemy)
 assert(target.hp<before,'Moonblast did not damage target')
 b=testBattle();testMove(b,api.registeredMoveId('WILLOWISP'),enemy)
 assert(raw(enemy and b.player or b.enemy).status==(gen2 and 'burn' or 'BRN'))
end
local b=testBattle();raw(b.enemy).ability='Water Absorb';raw(b.enemy).hp=50
local before=raw(b.enemy).hp;testMove(b,api.registeredMoveId('SURF'))
assert(raw(b.enemy).hp>=before,'Water Absorb did not block Water damage')
assert(raw(b.enemy).hp>before,'Water Absorb did not heal')
print('ASSERTED-OUTCOMES',version,'damage/status both sides, Water Absorb immunity and healing')

for _,enemy in ipairs({false,true})do
 local b=testBattle();local u=enemy and b.enemy or b.player;local t=enemy and b.player or b.enemy
 testMove(b,api.registeredMoveId('SOAK'),enemy)
 assert(api.curTypesOf(t,gen2)[1]=='WATER','Soak failed to change type')
 print('TYPE-OUTCOME',version,enemy,'WATER')
 local b=testBattle();local u=enemy and b.enemy or b.player
 testMove(b,api.registeredMoveId('SHELLSMASH'),enemy)
 local st=api.stagesFor(b,u)
 assert(st.attack==2 and st.defense==-1 and st.spa==2 and st.spd==-1)
 print('STAGE-OUTCOME',version,enemy,st.attack,st.defense,st.spa,st.spd)
end
local b=testBattle();raw(b.player).ability='Levitate'
local before=raw(b.player).hp;testMove(b,api.registeredMoveId('EARTHQUAKE'),true)
assert(raw(b.player).hp==before,'Levitate did not block Ground damage')
print('ABILITY-OUTCOME',version,'Levitate blocked enemy Earthquake')

local m=mon('BULBASAUR');m.moves={}
local rows=api.learnableMoves(m)
assert(#rows>0)
local found=false
for _,row in ipairs(rows)do if row.value==api.registeredMoveId('ENERGYBALL')then found=true end end
assert(found,'Energy Ball missing from canonical machine route')
assert(api.teachModernMove(m,api.registeredMoveId('ENERGYBALL')))
assert(m.moves[1].pp==data.moves[m.moves[1].id].pp)
assert(not api.teachModernMove(m,api.registeredMoveId('DRACOMETEOR')),'Illegal species move taught')
local Runtime=require('src.mods.Runtime')
local rows=Runtime.call('ui.party.submenu',function(_,items)return items end,{},{{label='STATS'},{label='CANCEL'}},m,{})
local hasAbility,hasLearn=false,false
for _,row in ipairs(rows)do hasAbility=hasAbility or row.id=='DEX_ABILITY';hasLearn=hasLearn or row.id=='DEX_LEARN_MOVE'end
local compact=false;for _,row in ipairs(rows)do compact=compact or row.id=='DEX_TOOLS'end
assert(compact and #rows==3,'Modern tools must use one compact party entry')
print('TUTOR-OUTCOME',version,#api.learnableMoves(m),'legal Energy Ball learned with PP; illegal Draco Meteor rejected')

local b=testBattle();raw(b.enemy).ability='Intimidate'
Runtime.emit('battle.started',{battle=b,kind='wild'})
local st=api.stagesFor(b,b.player)
print('INTIMIDATE-STAGE',version,st.attack)
assert(st.attack==-1,'Intimidate failed to lower player Attack')

for _,id in ipairs({'CLANGOROUSSOUL','NORETREAT','FLOWERSHIELD','ROTOTILLER'})do
 local b=testBattle('BULBASAUR','BULBASAUR')
 local before=raw(b.player).hp
 testMove(b,id)
 local st=api.stagesFor(b,b.player)
 if id=='CLANGOROUSSOUL'then assert(raw(b.player).hp<before and st.attack==1 and st.spa==1)end
 if id=='NORETREAT'then
  assert(st.attack==1 and b:volatile(b.player).dexNoRetreat)
  testMove(b,id);assert(st.attack==1,'No Retreat incorrectly repeatable')
 end
 if id=='FLOWERSHIELD'then assert(st.defense==1 and api.stagesFor(b,b.enemy).defense==1)end
 if id=='ROTOTILLER'then assert(st.attack==1 and st.spa==1 and api.stagesFor(b,b.enemy).attack==1)end
end
local b=testBattle();raw(b.enemy).status=gen2 and 'poison' or 'PSN';testMove(b,'VENOMDRENCH')
assert(api.stagesFor(b,b.enemy).attack==-1 and api.stagesFor(b,b.enemy).spa==-1)
local b=testBattle();
-- Gen 1 has no native berries: supply the same item record as a held-item provider.
if not gen2 then data.items.BERRY={id='BERRY',name='Berry',heldEffect='HELD_BERRY',heldParameter=10}end
api.setItemOf(b.player,'BERRY',gen2);raw(b.player).hp=50;testMove(b,'STUFFCHEEKS')
assert(api.itemOf(b.player,gen2)==nil and api.stagesFor(b,b.player).defense==2 and raw(b.player).hp>50)
local boxed={species='BULBASAUR',ability='Chlorophyll'};api.ensureAbility(boxed);assert(boxed.ability=='Chlorophyll')
local save={party={{species='BULBASAUR'}},boxes={{{species='SQUIRTLE'}}},daycare={mon={species='CHARMANDER'}}}
Runtime.emit('game.ready',{game={save=save}})
assert(save.party[1].ability=='Overgrow' and save.boxes[1][1].ability=='Torrent' and save.daycare.mon.ability=='Blaze')
print('STATUS-ABILITY-OUTCOME',version,'six completed status moves, save/box/daycare assignment, hidden ability preserved')

local assigned=0
for id,def in pairs(data.pokemon)do
 if type(def)=='table' and def.baseStats and api.statsBySpecies(id)then
  local m={species=id};api.ensureAbility(m)
  assert(type(m.ability)=='string' and api.abilityById(m.ability:upper():gsub('[^A-Z0-9]','')),id..' missing real ability')
  assigned=assigned+1
 end
end
print('ROSTER-ABILITY-OUTCOME',version,assigned)

if gen2 then
 local b=testBattle();local has=false
 for _,id in ipairs(b:moveOrder())do if id=='MOONBLAST'then has=true end end
 assert(has,'Metronome excluded implemented modern moves')
 print('METRONOME-OUTCOME',version,'modern moves included')
end
