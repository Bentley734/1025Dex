-- SPDX-License-Identifier: GPL-3.0-or-later
-- A combat-only view over real Gen 3 state. Numeric species/moves, native
-- parties and save records remain native; modern handlers see their own API.
return function(mod, registry, data)
 local Pokemon=require('src.core.game3.pokemon')
 local Types=require('src.core.game3.battle.types')
 local Damage=require('src.core.game3.battle.damage')
 local State=require('src.core.game3.battle.state')
 local Items=require('src.core.game3.items_data')
 local states=setmetatable({},{__mode='k'})
 local F={}
 local stateFields={weather=true,weatherTurns=true,terrain=true,turn=true,over=true,result=true}
 F.__index=function(self,key)
  if F[key]~=nil then return F[key]end
  if stateFields[key]then return self._state[key]end
 end
 F.__newindex=function(self,key,value)
  if stateFields[key]then self._state[key]=value else rawset(self,key,value)end
 end
 function F.setData(value)
  data=value
  for _,battle in pairs(states)do battle.data=value end
 end
 local statusToModern={BRN='burn',PSN='poison',TOX='toxic',PAR='paralyze',FRZ='freeze',SLP='sleep'}
 local statusToNative={burn='BRN',poison='PSN',toxic='TOX',paralyze='PAR',freeze='FRZ',sleep='SLP'}
 local statKeys={hp='maxHp',attack='attack',defense='defense',speed='speed',spa='spAtk',spd='spDef',specialAttack='spAtk',specialDefense='spDef'}
 local stageKeys={spa='spAtk',spd='spDef'}
 local function numberType(id)return Types.ID[id=='PSYCHIC_TYPE' and 'PSYCHIC' or id]end
 local function nameType(id)
  for name,value in pairs(Types.ID)do if value==id then return name=='PSYCHIC'and 'PSYCHIC_TYPE'or name end end
 end
 local function speciesName(mon)
  if type(mon.species)=='string'then return mon.species end
  return Pokemon.keyName(mon.species)
 end
 function F:native(who)return who and self._nativeByView[who]end
 function F:stageStore(who)
  local stages=assert(self:native(who),'Stages require an active battler').stages
  return setmetatable({},{__index=function(_,key)return stages[stageKeys[key]or key]end,
   __newindex=function(_,key,value)stages[stageKeys[key]or key]=value end})
 end
 function F:view(mon,battler)
  if not mon then return end
  local view=self._views[mon]
  if view then if battler then self._nativeByView[view]=battler end;return view end
  local volatile={}
  local stats=setmetatable({},{__index=function(_,key)
   local native=statKeys[key]or key
   return mon[native]or(mon.stats and mon.stats[native])
  end,__newindex=function(_,key,value)
   local native=statKeys[key]or key;mon[native]=value
   if mon.stats then mon.stats[native]=value end
  end})
  view=setmetatable({},{__index=function(_,key)
   local b=self._nativeByView[view]
   if key=='mon'then return nil end
   if key=='species'then return speciesName(mon)end
   if key=='stats'then return stats end
   if key=='ability'then return mon.dexAbility end
   if key=='item'then
    local item=tonumber(mon.item or mon.heldItem)
    if not item or item==0 then return nil end
    return Items.bagKey(item)
   end
   if key=='types'then
    if b then local result={nameType(b.type1)};if b.type2 then result[#result+1]=nameType(b.type2)end;return result end
    local info=mod.exports.statsBySpecies(speciesName(mon));return info and info.types or{}
   end
   if key=='status'then return statusToModern[mon.status]or mon.status end
   if key=='volatile'then return volatile end
   if key=='name'then return mon.nickname or speciesName(mon)end
   if key=='moves'then
    local out={}
    for slot,num in ipairs(mon.moves or{})do
     local row=registry.resolve(num)
     if row then
      out[#out+1]=setmetatable({id=row.id},{__index=function(_,field)
       if field=='pp'then return(mon.pp or{})[slot]or 0 end
       if field=='maxPP'then return(mon.maxPp or{})[slot]or row.pp end
      end,__newindex=function(_,field,value)
       if field=='pp'then mon.pp=mon.pp or{};mon.pp[slot]=value end
      end})
     end
    end
    return out
   end
   return(b and b[key])or mon[key]
  end,__newindex=function(_,key,value)
   local b=self._nativeByView[view]
   if key=='ability'then mon.dexAbility=value;return end
   if key=='item'then
    local item=value and assert(Items.toNumericId(value),'Unknown native held item')or 0
    mon.item=item;mon.heldItem=item;if b then b.item=item end;return
   end
   if key=='status'then mon.status=statusToNative[value]or value;if b then b.status=mon.status end;return end
   if key=='types'then
    assert(b,'Type changes require a live Gen 3 battler')
    b.type1=assert(numberType(value[1]),'Unknown modern type')
    b.type2=value[2]and assert(numberType(value[2]),'Unknown modern secondary type')or nil
    return
   end
   if key=='moves'then
    mon.moves={};mon.pp={};mon.maxPp={}
    for slot,entry in ipairs(value or{})do
     mon.moves[slot]=assert(registry.numberFor(entry.id),'Unresolved modern move')
     mon.pp[slot]=entry.pp or 0;mon.maxPp[slot]=entry.maxPP or entry.pp or 0
    end
    return
   end
   if key=='volatile'then volatile=value or{};return end
   if key=='hp'then
    local before=mon.hp or 0;mon.hp=math.max(0,math.min(value,mon.maxHp or value))
    if b and before~=mon.hp then self._adapter:recordHp(b,before,mon.hp,mon.hp<before and 'damage'or 'heal')end
    return
   end
   if b then b[key]=value else mon[key]=value end
  end})
  self._views[mon]=view;if battler then self._nativeByView[view]=battler end
  return view
 end
 function F.bind(st,adapter)
  local self=states[st]
  if not self then
   self=setmetatable({_state=st,_views=setmetatable({},{__mode='k'}),_nativeByView=setmetatable({},{__mode='k'}),data=data,events={},screens={player={},enemy={}}},F)
   states[st]=self
  end
  self._adapter=adapter or self._adapter
  assert(self._adapter,'Gen 3 adapter missing')
  for _,b in ipairs(State.present(st))do self:view(b.mon,b)end
  self.player=self:view(st.player.mon,st.player);self.enemy=self:view(st.enemy.mon,st.enemy)
  self.__gen3=true
  self.stages={player=self:stageStore(self.player),enemy=self:stageStore(self.enemy)}
  self.screens={player=st.playerSide,enemy=st.enemySide}
  self.spikes=setmetatable({},{__index=function(_,side)
   return require('src.core.game3.battle.effects.hazards').layers(side=='player'and st.playerSide or st.enemySide)
  end,__newindex=function(_,side,value)
   require('src.core.game3.battle.effects.hazards').set(side=='player'and st.playerSide or st.enemySide,value)
  end})
  self.party={};for _,mon in ipairs(st.playerParty or{})do self.party[#self.party+1]=self:view(mon)end
  self.enemyParty={};for _,mon in ipairs(st.foeParty or{})do self.enemyParty[#self.enemyParty+1]=self:view(mon)end
  self.playerIndex=st.player.partyIndex;self.enemyIndex=st.enemy.partyIndex
  self.turn=st.turn;self.over=st.over;self.wild=st.wild
  if st.chosen and next(st.chosen)then
   self.__g9ChosenMoves={}
   for id,action in pairs(st.chosen)do
    local battler=State.battler(st,id)
    local move=registry.resolve(action.move or action.moveId)
    if battler and move then self.__g9ChosenMoves[self:view(battler.mon,battler)]=move.id end
   end
  end
  self.random=function(n)return self._adapter:roll(0,n-1)end
  self.rng=function(lo,hi)return self._adapter:roll(lo,hi)end
  return self
 end
 function F:sideOf(who)local b=self:native(who);return b and b.side end
 function F:sideRecord(who)return{index=self:sideOf(who)=='player'and 1 or 2}end
 function F:monName(who)return who and(who.nickname or who.name or who.species)or '?'end
 F.battlerName=F.monName
 function F:speciesDef(who)return self.data.pokemon[who.species]end
 function F:moveDef(id)
  local move=registry.resolve(id)
  return move and(self.data.moves and self.data.moves[move.id]or move)
 end
 function F:roller()return self.random end
 function F:volatile(who)return who.volatile end
 function F:clearVolatile(who)who.volatile={}end
 function F:emit(event)
  self.events[#self.events+1]=event
  if event.text then self._adapter:say(event.text)end
  return event
 end
 function F:takeEvents()local events=self.events;self.events={};return events end
 function F:findMove(who,id)
  for _,slot in ipairs(who.moves)do if slot.id==id then return slot end end
 end
 function F:effectiveSpeed(who)
  local b=self:native(who)
  local value=Damage.applyStage(self:battleStat(who,'speed'),b and b.stages.speed or 0)
  return F.statusPenaltyFor(self.data,who,'speed',value)
 end
 function F.statusPenaltyFor(_,who,key,value)
  if key=='speed'and who.status=='paralyze'then return math.max(1,math.floor(value/2))end
  if key=='attack'and who.status=='burn'then return math.max(1,math.floor(value/2))end
  return value
 end
 function F:battleStat(who,key)return who.stats[key]end
 function F:badgeTypeBoost()return 1 end
 function F:screenActive(who,special)
  local screen=self.screens[self:sideOf(who)]or{}
  return special and(tonumber(screen.expLightScreenTurns or screen.lightScreen)or 0)>0
   or(not special and(tonumber(screen.expReflectTurns or screen.reflect)or 0)>0)
 end
 function F:changeStageAgainstMist(user,target,key,delta)
  local b=assert(self:native(target),'Stage change requires live battler')
  return self._adapter:changeStages(b,{[stageKeys[key]or key]=delta})
 end
 function F:changeStage(target,key,delta)
  return self._adapter:changeStages(assert(self:native(target)),{[stageKeys[key]or key]=delta})
 end
 function F:heal(who,amount)return self._adapter:heal(assert(self:native(who)),amount)end
 function F:applyStatus(who,status,source)
  return self._adapter:applyStatus(assert(self:native(who)),statusToNative[status]or status,self:native(source))
 end
 function F:applyConfusion(who,turns)return self._adapter:applyConfusion(assert(self:native(who)),turns)end
 function F:switchLocked()return false end
 function F:requestSwitchNative(who,opts)return assert(self._switch,'Native switch bridge missing')(self,who,opts)end
 function F:switchMonAtSide(side,slot)
  local who=side=='enemy'and self.enemy or self.player
  return self:requestSwitchNative(who,{slot=slot})
 end
 function F:tickWeather()return self._adapter:tickWeather()end
 function F:useMove(user,target,id)
  return assert(self._execute,'Gen 3 move execution bridge is not installed')(self,user,target,id)
 end
 function F:moveOrder()
  local ids={};for id in pairs(registry.byId)do ids[#ids+1]=id end;table.sort(ids);return ids
 end
 function F.moveEffectRecordFor(value,effect)
  if value.__gen3 then
   local move=registry.resolve(effect)
   return value.data.move_effects[move and move.effect or effect]
  end
  return value.move_effects[effect]
 end
 function F:itemDef(id)return self.data.items[id]end
 function F:heldEffect()return false end
 function F:dealDamage(user,target,amount,opts)
  if self._deal then return self:_deal(user,target,amount,opts)end
  return self._adapter:applyHpLoss(assert(self:native(target)),amount,opts)
 end
 function F:hitOnce(user,target,move,opts)
  return assert(self._hit,'Gen 3 damage bridge is not installed')(self,user,target,move,opts)
 end
 function F:canAct()return true end -- Native Gen 3 checks the standard statuses.
 function F:markMissed()
  local invocation=self.__nativeInvocation
  if invocation then invocation.missed=true end
  if invocation and invocation.out and invocation.out._anim then invocation.out._anim.missed=true end
 end
 function F:clearAllVolatiles()
  for _,view in pairs(self._views)do view.volatile={}end
 end
 function F:endBattle(outcome)self._state.over=true;self._state.result=outcome;self.over=true end
 F.MOVE_EFFECT_RECORDS={};F.MOVE_EFFECTS={};F.HELD_STATUS_CURES={}
 F.STATUSES={
  poison={residual=function(_,_,maxHp)return math.max(1,math.floor(maxHp/8))end},
  burn={residual=function(_,_,maxHp)return math.max(1,math.floor(maxHp/16))end},
  toxic={residual=function(_,who,maxHp)
   who.toxicCounter=math.min(15,(who.toxicCounter or 0)+1)
   return math.max(1,math.floor(maxHp*who.toxicCounter/16))
  end},sleep={},paralyze={},freeze={}
 }
 -- The execution bridge installs useMove/dealDamage and native sequencing.
 return F
end
