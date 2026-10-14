local api=assert(loader.exports['1025dex']);local installed=assert(api.gen3BattleAdapter)
local models,F=installed.models,installed.models.class
local P=require('src.core.game3.pokemon');local Moves=require('src.core.game3.battle.moves')
local State=require('src.core.game3.battle.state');local Adapter=require('src.core.game3.battle.adapter')
local Engine=require('src.core.game3.battle.engine');local Runtime=require('src.mods.Runtime')
local function mon(species,move)
 local m={species=assert(P.speciesFromName(species)),level=50,moves={move or 33},pp={Moves.get(move or 33).pp},personality=0}
 P.applyStats(m);m.hp=m.maxHp;return m
end
local count=0
for number,move in pairs(installed.registry.byNumber)do
 local p,e=mon('BULBASAUR',number),mon('SQUIRTLE')
 local st=State.new{playerParty={p},foeMon=e,wild=true,rng=function(lo)return lo end};local ad=Adapter.new(st)
 local out=Engine.resolveMove(st.player,st.enemy,number,1,ad,st,{},{})
 assert(type(out)=='table'and out._anim,move.id..' has no native result')
 assert(p.pp[1]==math.max(0,move.pp-1),move.id..' PP wrong')
 count=count+1
end
assert(count==833)
local p,e=mon('CLEFAIRY',585),mon('DRAGONITE')
local st=State.new{playerParty={p},foeMon=e,wild=true,rng=function(lo)return lo end};local ad=Adapter.new(st)
Runtime.emit('battle.started',{battle=st});local before=e.hp
local out=Engine.resolveMove(st.player,st.enemy,585,1,ad,st,{},{})
assert(e.hp<before and Moves.get(585).type==18 and out._anim.moveId==585)
local frog=mon('GRENINJA',594);frog.dexAbility='Protean';models.abilities.assign(frog);frog.pp[1]=7
local Storage=require('src.core.game3.storage');local storage=Storage.new();storage.boxes[1].mons[1]=frog
local Codec=require('src.core.SaveSerializer')
local save=assert(Codec.decode(Codec.encode{party={frog},storage=Storage.serialize(storage)}))
local boxed=Storage.deserialize(save.storage).boxes[1].mons[1]
require('src.core.game3.save_mon').normalize(boxed)
assert(boxed.moves[1]==594 and boxed.pp[1]==7 and boxed.dexAbility=='Protean'and P.abilityName(boxed.ability)=='Protean')
assert(save.party[1].moves[1]==594 and save.party[1].pp[1]==7)
local learner=mon('BULBASAUR');assert(api.teachModernMove(learner,'ENERGYBALL',1));assert(learner.moves[1]==412 and learner.pp[1]==10)
assert(not api.teachModernMove(learner,'DRACOMETEOR',1))
local dr=mon('DARKRAI',464);local foe=mon('SQUIRTLE')
local ds=State.new{playerParty={dr},foeMon=foe,wild=true,rng=function(lo,hi)return hi end};local da=Adapter.new(ds)
Engine.resolveMove(ds.player,ds.enemy,464,1,da,ds,{},{})
assert(not foe.status,'Dark Void ignored accuracy')
local burn=mon('BULBASAUR');burn.status='BRN'
local bs=State.new{playerParty={burn},foeMon=mon('SQUIRTLE'),wild=true};local ba=Adapter.new(bs);local hp=burn.hp
require('src.core.game3.battle.status').tickChip(bs.player,ba)
assert(hp-burn.hp==math.max(1,math.floor(burn.maxHp/16)))
local a,b,c,d=mon('BULBASAUR',502),mon('PIKACHU'),mon('SQUIRTLE'),mon('CHARMANDER')
local doubles=State.new{playerParty={a,b},foeParty={c,d},double=true,wild=true,rng=function(lo)return lo end};local dad=Adapter.new(doubles)
Engine.resolveMove(doubles.player,doubles.enemy,502,1,dad,doubles,{},{})
assert(doubles.player.mon==b and doubles.battlers[2].mon==a,'Ally Switch lost native slots')
assert(#models.failures==0,models.failures[1]and models.failures[1].error)
assert(#loader.errors==0,loader.errors[1])
print('GEN3-PRODUCTION-PASS',version,count,'native dispatch/PP, Fairy, save roundtrip, learning, accuracy, burn, doubles')
local victim,bench,attacker=mon('GOLISOPOD'),mon('PIKACHU'),mon('BULBASAUR')
victim.hp=math.floor(victim.maxHp/2)+1;victim.dexAbility='Emergency Exit';attacker.moves={33};attacker.pp={35}
local vs=State.new{playerParty={attacker},foeParty={victim,bench},wild=false,rng=function(lo)return lo end};local va=Adapter.new(vs)
Engine.resolveMove(vs.player,vs.enemy,33,1,va,vs,{},{})
assert(vs.enemy.mon==bench,'Emergency Exit did not use native switching')
assert(#models.failures==0,models.failures[1]and models.failures[1].error)
print('GEN3-SWITCH-PASS',version,'Emergency Exit native replacement')
local water,wall=mon('GRENINJA',594),mon('BLISSEY');water.dexAbility='Skill Link'
local ms=State.new{playerParty={water},foeMon=wall,wild=true,rng=function(lo)return lo end};local ma=Adapter.new(ms)
local multi=Engine.resolveMove(ms.player,ms.enemy,594,1,ma,ms,{},{})
assert(#multi._anim.hits==5 and water.pp[1]==Moves.get(594).pp-1,'Skill Link native multi-hit failed')
print('GEN3-MULTI-PASS',version,'Water Shuriken five real native hits, one PP')
assert(P.battleMove(585).type==18 and P._types[P.speciesFromName('CLEFAIRY')][1]==18,'Native summary Fairy type lost: '..tostring(P.battleMove(585).type)..' / '..tostring(P._types[P.speciesFromName('CLEFAIRY')][1])..' / '..tostring(api.statsBySpecies('CLEFAIRY').types[1]))
local forgotten=mon('GRENINJA',594);forgotten.dexAbility=nil;forgotten.ability=nil
Runtime.emit('game.ready',{game={session={party={},storage={boxes={{mons={forgotten}}}}}}})
assert(forgotten.dexAbility and P.abilityName(forgotten.ability)==forgotten.dexAbility,'Stored ability assignment missing')
local flyer,target=mon('CHARIZARD',19),mon('BLISSEY')
local fs=State.new{playerParty={flyer},foeMon=target,wild=true,rng=function(lo)return lo end};local fa=Adapter.new(fs);local originalHp=target.hp
Engine.resolveMove(fs.player,fs.enemy,19,1,fa,fs,{},{})
assert(target.hp==originalHp,'Fly failed to preserve its native charging turn')
Engine.resolveMove(fs.player,fs.enemy,19,1,fa,fs,{},{})
assert(target.hp<originalHp and flyer.pp[1]==Moves.get(19).pp-1,'Fly second turn or PP broken')
print('GEN3-CHARGE-PASS',version,'native two-turn Fly')
local beam,wall=mon('PORYGON',63),mon('BLISSEY');beam.moves={63,33};beam.pp={5,35}
local hs=State.new{playerParty={beam},foeMon=wall,wild=true,rng=function(lo)return lo end};local ha=Adapter.new(hs)
Engine.resolveMove(hs.player,hs.enemy,63,1,ha,hs,{},{})
local after=wall.hp
Engine.resolveMove(hs.player,hs.enemy,33,2,ha,hs,{},{})
assert(wall.hp==after and beam.pp[2]==35,'Native Hyper Beam recharge not preserved')
print('GEN3-RECHARGE-PASS',version,'Hyper Beam recharge consumes no second move PP')
