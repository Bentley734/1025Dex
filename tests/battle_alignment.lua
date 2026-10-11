-- Production positioning, with deliberately different cartridge art offsets.
local checks=0
local function eq(a,b,why) checks=checks+1; assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b)) end
local nativeOffsets={[1]=16,[2]=1,[3]=9,[999]=5}
local Ui={bounceOffset=function() return 3 end}
local P={frontPic=function(s) return s~=999 and {__completeDexBattleLift=0} or {} end}
P.backPic=P.frontPic
local bases={[0]={x=72,y=80},[1]={x=176,y=40},[2]={x=90,y=88},[3]={x=152,y=32}}
local Coords={battlerCoords=function(_,id)return bases[id]end}
Ui.battlerSpriteCenter=function(side,species,base)
  return base.x,base.y+(nativeOffsets[species] or 0)
end
Ui._st={player={species=1},enemy={species=2},battlers={[2]={species=3},[3]={species=1}}}
package.loaded['src.core.game3.battle.ui']=Ui
package.loaded['src.core.game3.pokemon']=P
package.loaded['src.core.game3.battle.pic_coords']=Coords
local install=dofile('battle_position.lua');install()
for _,species in ipairs({1,2,3})do
  Ui._st.player.species=species;Ui._st.enemy.species=species
  eq(Ui.bounceOffset('mon',0),3-nativeOffsets[species],'player cancels ROM padding')
  eq(Ui.bounceOffset('mon',1),3-nativeOffsets[species],'enemy cancels ROM padding')
end
eq(Ui.bounceOffset('hb',1),3,'healthbox unchanged')
Ui._st.double=true
eq(Ui.bounceOffset('mon',2),3-9-8,'second ally fits y112 field')
eq(Ui.bounceOffset('mon',3),3-16,'second enemy cancels padding')
Ui._st.double=false
local observed
package.loaded['src.core.game3.battle.anim']={shownBattler=function(key,b)observed=key;return {species=2}end}
eq(Ui.bounceOffset('mon',1),2,'displayed species');eq(observed,'enemy','singles key')
package.loaded['src.core.game3.battle.anim']=nil
Ui._st.enemy={species=1,expTransform={species=2}}
eq(Ui.bounceOffset('mon',1),2,'Transform display')
Ui._st.enemy={mon={speciesId=3}}
eq(Ui.bounceOffset('mon',1),-6,'mon fallback species')
Ui._st.enemy.species=999
eq(Ui.bounceOffset('mon',1),3,'native/pending unchanged')
Ui.showsGhost=function()return true end;Ui._st.enemy.species=2
eq(Ui.bounceOffset('mon',1),3,'ghost unchanged');Ui.showsGhost=nil
package.loaded['src.core.game3.battle.anim']={present=function()return {substitute=true}end}
eq(Ui.bounceOffset('mon',1),3,'substitute unchanged')
package.loaded['src.core.game3.battle.anim']=nil
local before=Ui.bounceOffset;install();eq(Ui.bounceOffset,before,'idempotent')
print(('PASS: %d battle positioning assertions; ROM padding, both sides, doubles, Transform, ghosts, substitutes and animation motion.'):format(checks))
