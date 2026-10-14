-- Complete the six payload-bearing status gaps reported by upstream's audit.
return function(mod)
 local E=mod.exports
 local Native=require('src.battle.MoveEffects')
 local function raw(w)return w.mon or w end
 local function stage(n,w,key,delta)
  if key=='speed' then
   if n.gen2 then n.battle:changeStageAgainstMist(n.user,w,key,delta)
   else Native.changeStage(n.battle,w,key,delta,w~=n.user and delta<0)end
  else E.changeStage(n.battle,w,key,delta,w~=n.user and delta<0,n.gen2)end
 end
 local function grass(w,n)
  for _,t in ipairs(E.curTypesOf(w,n.gen2))do if t=='GRASS'then return true end end
 end
 local function grounded(w,n)
  if w.gravityGrounded then return true end
  for _,t in ipairs(E.curTypesOf(w,n.gen2))do if t=='FLYING'then return false end end
  return E.abilityIdOf(w)~='LEVITATE'
 end
 local functions={}
 functions.CLANGOROUSSOUL=function(n)
  local m=raw(n.user);local cost=math.max(1,math.floor(m.stats.hp/3))
  if m.hp<=cost then return false end
  local s=E.stagesFor(n.battle,n.user)
  if (s.attack or 0)>=6 and (s.defense or 0)>=6 and (s.spa or 0)>=6 and (s.spd or 0)>=6
     and (n.gen2 and n.battle.stages[n.battle:sideOf(n.user)].speed or n.user.stages.speed or 0)>=6 then return false end
  m.hp=m.hp-cost
  for _,key in ipairs({'attack','defense','spa','spd','speed'})do stage(n,n.user,key,1)end
  return true
 end
 functions.NORETREAT=function(n)
  local v=n.battle:volatile(n.user)
  if v.dexNoRetreat then return false end
  v.dexNoRetreat=true
  for _,key in ipairs({'attack','defense','spa','spd','speed'})do stage(n,n.user,key,1)end
  return true
 end
 functions.VENOMDRENCH=function(n)
  local status=raw(n.target).status
  if status~='PSN' and status~='poison' and status~='toxic' then return false end
  if n.target.substituteHP or (n.battle:volatile(n.target).substitute or 0)>0 then return false end
  for _,key in ipairs({'attack','spa','speed'})do stage(n,n.target,key,-1)end
  return true
 end
 functions.FLOWERSHIELD=function(n)
  local affected=false
  for _,w in ipairs({n.battle.player,n.battle.enemy})do
   if raw(w).hp>0 and grass(w,n)then stage(n,w,'defense',1);affected=true end
  end
  return affected
 end
 functions.ROTOTILLER=function(n)
  local affected=false
  for _,w in ipairs({n.battle.player,n.battle.enemy})do
   if raw(w).hp>0 and grass(w,n)and grounded(w,n)then
    stage(n,w,'attack',1);stage(n,w,'spa',1);affected=true
   end
  end
  return affected
 end
 functions.STUFFCHEEKS=function(n)
  local item=E.itemOf(n.user,n.gen2)
  if not item or not E.isBerryItem(item)then return false end
  local def=n.battle.data.items[item]
  if not def then return false end
  E.setItemOf(n.user,nil,n.gen2)
  raw(n.user).ggdConsumedBerryThisBattle=true
  E.applyEatenBerryEffect(n.battle,raw(n.user),def,n.battle:monName(n.user))
  stage(n,n.user,'defense',2)
  return true
 end
 for id,run in pairs(functions)do
  local effect='DEX_PRIMARY_'..id
  mod.content.move_effects:register(effect,{kind='primary',accuracyChecked=true,run=function(a,b,c)
   local n=E.normalize(a,b,c)
   local success=run(n)
   local text=success and 'The move took effect!'or 'But it failed!'
   if n.gen2 then n.battle:emit{kind='message',text=text};return{}end
   return{ text,failed=not success }
  end})
  mod.content.moves:patch(id,{effect=effect,effectModeled=true})
 end
 mod.exports.statusCoverageGaps={}
 -- A voluntary switch/run is blocked until the user leaves the field.
 local function locked(b,w)
  if not w then return false end
  for _,t in ipairs(E.curTypesOf(w,E.isGen2Battle(b)))do if t=='GHOST'then return false end end
  return b:volatile(w).dexNoRetreat==true
 end
 local ok,Battle2=pcall(require,'src.battle.gen2.Battle')
 if ok then
  local switchLocked=Battle2.switchLocked
  function Battle2:switchLocked()return locked(self,self.player)or switchLocked(self)end
 end
 local State=require('src.battle.BattleState')
 if State.resolveSwitch then
  local switch=State.resolveSwitch
  function State:resolveSwitch(mon)
   if locked(self,self.player)then self:say('This Pokemon cannot retreat!');return false end
   return switch(self,mon)
  end
  if not State.heal then
   function State:heal(w,amount)return E.g9TryHeal(self,w,amount)end
  end
 end
 mod.hooks:wrap('battle.run',function(next,ctx)
  if locked(ctx.battle,ctx.battle.player)then return false end
  return next(ctx)
 end,100)
end
