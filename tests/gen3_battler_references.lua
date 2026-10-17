local api=assert(loader.exports['1025dex']);local installed=assert(api.gen3BattleAdapter)
local P=require('src.core.game3.pokemon');local Moves=require('src.core.game3.battle.moves')
local State=require('src.core.game3.battle.state');local Adapter=require('src.core.game3.battle.adapter')
local Engine=require('src.core.game3.battle.engine')
local function mon()
 local m={species=assert(P.speciesFromName('BULBASAUR')),level=30,moves={33},pp={35},personality=0}
 P.applyStats(m);m.hp=m.maxHp;return m
end
local function setup(double)
 local st=State.new{playerParty={mon(),mon()},foeParty={mon(),mon()},double=double,wild=false,rng=function(lo)return lo end}
 return st,Adapter.new(st)
end
for _,pair in ipairs({{0,1},{1,0},{2,3},{3,2}})do
 local st,ad=setup(true);local u,t=State.battler(st,pair[1]),State.battler(st,pair[2])
 local hp,pp=t.mon.hp,u.mon.pp[1]
 local out=Engine.resolveMove(pair[1],pair[2],33,1,ad,st,{},{})
 assert(out._anim and out._anim.user==u and out._anim.target==t,'Wrong slot presentation')
 assert(t.mon.hp<hp and u.mon.pp[1]==pp-1,'Numeric action lost damage or PP')
end
for _,refs in ipairs({'table','side','nil-target','pursuit','replacement'})do
 local st,ad=setup(refs~='side');local u,t=st.player,st.enemy
 local ur,tr=u,t;local opts={}
 if refs=='side'then ur,tr='player','enemy'
 elseif refs=='nil-target'then ur,tr=0,nil
 elseif refs=='pursuit'then ur,tr=0,1;opts.pursuitSwitch=true
 elseif refs=='replacement'then
  local stale=u;local fresh=State.makeBattler(mon(),'player',{id=0});fresh.id=0
  st.battlers[0]=fresh;st.player=fresh;u=fresh;ur,tr=stale,1
 end
 local pp=u.mon.pp[1];local out=Engine.resolveMove(ur,tr,33,1,ad,st,{},opts)
 assert(out._anim and out._anim.user==u,refs..' wrong actor')
 assert(u.mon.pp[1]==pp-1,refs..' PP wrong')
end
do
 local st,ad=setup(true);local u,t=st.player,st.enemy
 u.mon.moves={585};u.mon.pp={Moves.get(585).pp};local hp=t.mon.hp;local pp=u.mon.pp[1]
 local out=Engine.resolveMove(0,1,585,1,ad,st,{},{})
 assert(out._anim.moveId==585 and t.mon.hp<hp and u.mon.pp[1]==pp-1,'Modern numeric move bypassed mechanics')
end
for _,ended in ipairs({false,true})do
 local st,ad=setup(true);local u=st.player;local hp=st.enemy.mon.hp;local pp=u.mon.pp[1]
 if ended then st.over=true else st.absent=st.absent or{};st.absent[0]=true end
 local out=Engine.resolveMove(0,1,33,1,ad,st,{},{})
 assert(out._anim and u.mon.pp[1]==pp and st.enemy.mon.hp==hp,'Cancelled action executed')
end
assert(#installed.models.failures==0,installed.models.failures[1]and installed.models.failures[1].error)
assert(#loader.errors==0,loader.errors[1])
print('BATTLER-REFERENCES-PASS',version,'four numeric slots, tables, sides, automatic targeting, Pursuit, replacement, absent and ended battle')

