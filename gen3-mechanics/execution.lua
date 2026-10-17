-- SPDX-License-Identifier: GPL-3.0-or-later
-- Connect the native resolver to the private, wrapped useMove implementation.
-- Native resolution still owns announcements, PP, interruption and animation
-- event collection; mechanics keep canonical modern move identities.
return function(mod,models,transport,adapterMap)
 local F=models.class
 local Engine=require('src.core.game3.battle.engine')
 local Effects=require('src.core.game3.battle.effects')
 local NativeAdapter=require('src.core.game3.battle.adapter')
 local resolve=Engine.resolveMove
 local newAdapter=NativeAdapter.new
 local State=require('src.core.game3.battle.state')
 local makeBattler=State.makeBattler
 State.makeBattler=function(mon,...)
  if models.abilities then models.abilities.assign(mon)end
  return makeBattler(mon,...)
 end
 function F:_switch(who,opts)
  opts=opts or{}
  local native=assert(self:native(who));local candidates=Engine.switchCandidates(self._state,native.id)
  if #candidates==0 then return false end
  local pick=opts.slot
  local thread,main=coroutine.running()
  if not pick and native.side=='player'and self._state.interactiveChoices and thread and not main then
   pick=coroutine.yield{kind='baton_pass',side=native.side,battler=native.id,candidates=candidates}
  elseif not pick and native.side=='enemy'then pick=Engine.mostSuitableMon(self._state,self._adapter,native.id)end
  pick=tonumber(pick)or candidates[1]
  local legal=false;for _,slot in ipairs(candidates)do if slot==pick then legal=true end end
  if not legal then return false end
  local replacement=Engine.performSwitch(self._state,self._adapter,native.id,pick,{reason=opts.reason})
  if not replacement then return false end
  if opts.text then self._adapter:say(opts.text)end
  Engine.switchInEffects(self._state,self._adapter,replacement,{spikes=true,deferIntimidate=true})
  F.bind(self._state,self._adapter)
  return true
 end
 local nativePassive={INSOMNIA=true,VITAL_SPIRIT=true,LIMBER=true,IMMUNITY=true,WATER_VEIL=true,
  MAGMA_ARMOR=true,OWN_TEMPO=true,EARLY_BIRD=true,RUN_AWAY=true,ARENA_TRAP=true,SHADOW_TAG=true,
  MAGNET_PULL=true,SUCTION_CUPS=true,STICKY_HOLD=true,PRESSURE=true}
 local function configure(st,adapter)
  if adapter.__dexModern then return end
  adapter.__dexModern=true
  if models.abilities then
   for _,b in ipairs(require('src.core.game3.battle.state').present(st))do models.abilities.assign(b.mon);b.ability=b.mon.ability end
  end
  local abilityOf=adapter.abilityOf
  adapter.abilityOf=function(self,battler)
   if not models.abilities then return abilityOf(self,battler)end
   if not battler then return nil end
   models.abilities.assign(battler.mon)
   battler.ability=battler.mon.ability
   local name=battler.mon.dexAbility
   if not name or battler.expAbilitySuppressed then return nil end
   local native=name:upper():gsub('%s+','_')
   -- Native prevention rules still apply. Callback/damage/residual abilities
   -- have one owner, the modern bus, so native callbacks cannot apply twice.
   if nativePassive[native]then return native end
   return nil
  end
 end
 NativeAdapter.new=function(st,...)
  local adapter=newAdapter(st,...);adapterMap[st]=adapter;configure(st,adapter);return adapter
 end
 for name in pairs(models.events.listeners)do
  mod.events:on(name,function(payload)
   if payload and payload.battle and adapterMap[payload.battle]then transport.event(name,payload)end
  end)
 end
 -- Only hook contracts whose native payload has a battle context belong here.
 for _,name in ipairs({'battle.damage','battle.accuracy','battle.crit','battle.charge_required'})do
  if models.hooks.chains[name]then
   mod.hooks:wrap(name,function(next,context)
    if context and context.battle and adapterMap[context.battle]then return transport.hook(name,next,context)end
    return next(context)
   end,1000)
  end
 end
 if models.hooks.chains['battle.turn_order']then
  mod.hooks:wrap('battle.turn_order',function(next,a,aMove,b,bMove,ctx)
   if not ctx or not ctx.battle or not a or not b or not aMove or not bMove then return next(a,aMove,b,bMove,ctx)end
   local battle=F.bind(ctx.battle,assert(adapterMap[ctx.battle]))
   local oldPlayer,oldEnemy=battle.player,battle.enemy
   local left,right=battle:view(a.mon,a),battle:view(b.mon,b)
   battle.player,battle.enemy=left,right
   local first=assert(models.registry.resolve(ctx.playerMove or aMove)).id
   local second=assert(models.registry.resolve(ctx.enemyMove or bMove)).id
   local context={battle=battle,rng=ctx.rng,playerMove=first,enemyMove=second}
   local ok,result=pcall(models.hooks.call,models.hooks,'battle.turn_order',
    function()return next(a,aMove,b,bMove,ctx)end,left,battle:moveDef(first),right,battle:moveDef(second),context)
   battle.player,battle.enemy=oldPlayer,oldEnemy
   if not ok then error(result,0)end
   return result
  end,1000)
 end
 local runStatus=Effects.runForMove
 Effects.runForMove=function(adapter,user,target,id,moveContext)
  local st=adapter._st
  local battle=st and adapterMap[st]and F.bind(st,adapter)
  local previous=battle and battle.__nativeMoveContext
  if battle then battle.__nativeMoveContext=moveContext end
  local ok,handled=pcall(transport.status,{battle=st,user=user,target=target,moveNum=id})
  if battle then battle.__nativeMoveContext=previous end
  if not ok then error(handled,0)end
  if handled then
   if moveContext then moveContext:attackAnimation()end
   return true
  end
  return runStatus(adapter,user,target,id,moveContext)
 end
 local Hit=require('src.core.game3.battle.effects.hit')
 local runHit=Hit.run
 Hit.run=function(context)
  local move=models.registry.resolve(context.mnum)
  local low,high=move and tonumber(move.minHits),move and tonumber(move.maxHits)
  if low and high and low>0 and high>0 then
   local ability=tostring(context.user.mon.dexAbility or''):upper():gsub('[^A-Z0-9]','')
   local count=low
   if ability=='SKILLLINK'then count=high
   elseif high>low then
    if low==2 and high==5 then local distribution={2,2,2,3,3,3,4,5};count=distribution[context.adapter:roll(1,8)]
    else count=context.adapter:roll(low,high)end
   end
   context.move.hits=count
  elseif context.move.multiHit then context.move.hits=context.move.multiHit end
  return runHit(context)
 end
 local nativeDeal=Hit.dealDamage
 Hit.dealDamage=function(context,amount,info)
  info=info or{}
  local row=models.registry.resolve(context.mnum)
  if row then info.physical=row.category=='physical'end
  return nativeDeal(context,amount,info)
 end
 function F:_deal(user,target,amount,opts)
  opts=opts or{}
  local id=opts.moveId or(opts.move and opts.move.id)
  if not id then return self._adapter:applyHpLoss(assert(self:native(target)),amount,opts)end
  local invocation=assert(self.__nativeInvocation,'Move damage requires native invocation')
  local context=self.__nativeMoveContext
  if not context or context.user~=self:native(user)or context.target~=self:native(target)then
   local number=assert(models.registry.numberFor(id),'Unknown damage move identity')
   local anim=invocation.out._anim or{moveId=number,user=self:native(user),target=self:native(target),hits={},heals={},faints={},events={},msgs=invocation.out}
   invocation.out._anim=anim
   context=Engine.newContext(self:native(user),self:native(target),number,nil,self._adapter,self._state,invocation.out,anim,{called=true})
  end
  local damage=Hit.adjustDamage(context,self:native(target),amount,'set')
  context:attackAnimation()
  local dealt=Hit.dealDamage(context,damage,{physical=context.move.category=='physical'})
  context:tryFaintTarget()
  return dealt
 end
 function F:_execute(user,target,id)
  local invocation=assert(self.__nativeInvocation,'Missing native move invocation')
  local number=assert(models.registry.numberFor(id),'Unregistered move identity')
  local slot=invocation.slot
  if(self.copyDepth or 0)>0 then slot=nil end
  local move=models.data.moves[assert(models.registry.resolve(id)).id]
  local effect=F.moveEffectRecordFor(self.data,move.effect)
  local previous=models.activeEffect
  models.activeEffect={id=move.id,statusOnly=effect~=self.data.move_effects[move.effect]}
  local ok,result=pcall(resolve,assert(self:native(user)),assert(self:native(target)),number,
   slot,self._adapter,self._state,invocation.out,invocation.opts)
  if invocation.missed and type(result)=='table'and result._anim then result._anim.missed=true end
  models.activeEffect=previous
  if not ok then error(result,0)end
  return result
 end
 Engine.resolveMove=function(user,target,id,slot,adapter,st,out,opts)
  -- Native doubles/Pursuit/facility actions may pass slot IDs, not battlers.
  -- Resolve current occupants before touching .mon (including replaced slots).
  local userRef,targetRef=user,target
  user,target=State.occupant(st,user),State.occupant(st,target)
  -- Keep native cancellation and automatic target selection ahead of modern
  -- callbacks; an absent actor must not spend PP or trigger an ability.
  if type(user)~='table'or not user.mon or type(target)~='table'or not target.mon
   or(not(opts and opts.called)and st and(st.over or(st.double and State.isAbsent(st,State.idOf(user)))))then
   return resolve(userRef,targetRef,id,slot,adapter,st,out,opts)
  end
  adapterMap[st]=adapter
  configure(st,adapter)
  if models.abilities then
   for _,battler in ipairs(require('src.core.game3.battle.state').present(st))do
    models.abilities.assign(battler.mon);battler.ability=battler.mon.ability
   end
  end
  local battle=F.bind(st,adapter)
  local previous=battle.__nativeInvocation
  out=out or{}
  local mark=adapter:eventMark()
  local oldSay=adapter._say
  adapter._say=function(text)out[#out+1]=text end
  local ppBefore=slot and(user.mon.pp or{})[slot]
  battle.__nativeInvocation={slot=slot,out=out,opts=opts or{}}
  local ok,result=pcall(battle.useMove,battle,battle:view(user.mon,user),battle:view(target.mon,target),assert(models.registry.resolve(id)).id)
  battle.__nativeInvocation=previous
  adapter._say=oldSay
  if not ok then error(result,0)end
  -- Modern conditional failures can stop before the native resolver. They
  -- still need a valid native presentation result and exactly one PP spend.
  if type(result)~='table'or not result._anim then
   if ppBefore and ppBefore>0 and user.mon.pp[slot]==ppBefore and not(opts and opts.called)then user.mon.pp[slot]=ppBefore-1 end
   out._anim={moveId=id,user=user,target=target,hits={},heals={},faints={},statusOnly=true,
    msgs=out,events=adapter:eventsSince(mark),missed=false}
   return out
  end
  return result
 end
 return{originalResolve=resolve}
end
