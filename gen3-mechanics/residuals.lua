-- SPDX-License-Identifier: GPL-3.0-or-later
-- Native end-of-turn sequencing, with modern status amounts and immunities.
return function(models)
 local Status=require('src.core.game3.battle.status')
 local Handlers=require('src.core.game3.battle.residual_handlers')
 local function ability(b)return tostring(b.mon.dexAbility or''):upper():gsub('[^A-Z0-9]','')end
 local original=Status.tickChip
 Status.tickChip=function(b,ad)
  if not b or ad:isFainted(b)then return{}end
  local id=ability(b);local status=b.status or b.mon.status
  if id=='MAGICGUARD'then return{}end
  if id=='POISONHEAL'and(status=='PSN'or status=='TOX')then
   ad:heal(b,math.max(1,math.floor(ad:maxHp(b)/8)));ad:say(ad:displayName(b)..' restored HP with Poison Heal!');return{}
  end
  if status~='BRN'then return original(b,ad)end
  local amount=math.max(1,math.floor(ad:maxHp(b)/(id=='HEATPROOF'and 32 or 16)))
  ad:sayText('STRINGID_PKMNHURTBYBURN',{atk=b});ad:playAnim('status','BURN',b,b);ad:applyHpLoss(b,amount)
  return{}
 end
 local weather=Handlers.tickWeather
 Handlers.tickWeather=function(ad)
  local state=ad._st
  if state.weather=='SNOW'then
   if(state.weatherTurns or 0)>0 then state.weatherTurns=state.weatherTurns-1 end
   if state.weatherTurns==0 then state.weather=nil;ad:say('The snow stopped.')end
   return
  end
  local loss=ad.applyHpLoss
  ad.applyHpLoss=function(self,b,amount,opts)
   local id=ability(b)
   if id=='MAGICGUARD'or id=='OVERCOAT'or(state.weather=='SAND'and(id=='SANDFORCE'or id=='SANDRUSH'or id=='SANDVEIL'))then return 0 end
   return loss(self,b,amount,opts)
  end
  local ok,err=pcall(weather,ad);ad.applyHpLoss=loss
  if not ok then error(err,0)end
 end
end
