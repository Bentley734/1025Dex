-- SPDX-License-Identifier: GPL-3.0-or-later
-- Modern status moves absent from the cartridge effect table.
return function(models)
 local F=models.class
 local function fail(b)b:markMissed();b:emit{kind='message',text='But it failed!'}end
 local handlers={}
 handlers.HEALORDER=function(b,u)if u.hp>=u.stats.hp then return fail(b)end;b:heal(u,math.max(1,math.floor(u.stats.hp/2)))end
 handlers.DARKVOID=function(b,u,t)
  if u.species~='DARKRAI'then return fail(b)end
  if not b:applyStatus(t,'sleep',u)then fail(b)end
 end
 local function attention(b,who)
  local native=assert(b:native(who));local side=b._adapter:ownSide(native)
  side.expFollowMe=native;side.expFollowMeId=native.id
  b:emit{kind='message',text=b:monName(who)..' became the center of attention!'}
 end
 handlers.RAGEPOWDER=function(b,u)attention(b,u);b._adapter:ownSide(b:native(u)).dexRagePowder=true end
 handlers.SPOTLIGHT=function(b,u,t)attention(b,t)end
 handlers.ALLYSWITCH=function(b,u)
  local State=require('src.core.game3.battle.state')
  local a=b:native(u);local partner=State.battler(b._state,State.PARTNER(a.id))
  if not b._state.double or not partner or(partner.mon.hp or 0)<=0 then return fail(b)end
  local first,second=a.id,partner.id
  -- Battler slots are a view over the named native slots. Swap complete
  -- occupants, retaining each mon's stats, stages, ability and party index.
  b._state.battlers[first],b._state.battlers[second]=partner,a
  a.id,partner.id=second,first;a.flank,partner.flank=State.flankOf(second),State.flankOf(first)
  b:emit{kind='message',text=b:monName(u)..' switched places with its ally!'}
 end
 handlers.MEFIRST=function(b,u,t)
  local id=b.__g9ChosenMoves and b.__g9ChosenMoves[t]
  local move=id and b:moveDef(id)
  if not move or move.category=='status'or(t.__g9MoveActions or 0)>0 then return fail(b)end
  b.dexMeFirstUser=u;b.copyDepth=(b.copyDepth or 0)+1
  local ok,err=pcall(b.useMove,b,u,t,id)
  b.copyDepth=b.copyDepth-1;b.dexMeFirstUser=nil
  if not ok then error(err,0)end
 end
 models.hooks:wrap('battle.damage',function(next,ctx)
  local amount,info=next(ctx)
  if ctx.battle.dexMeFirstUser==ctx.user then amount=math.floor(amount*1.5)end
  return amount,info
 end,5,'1025dex-gen3')
 for id,fn in pairs(handlers)do
  local effect='DEX_GEN3_'..id
  models.content.move_effects:register(effect,{kind='primary',accuracyChecked=id=='DARKVOID',run=fn})
  models.content.moves:patch(id,{effect=effect,effectModeled=true})
 end
 return handlers
end
