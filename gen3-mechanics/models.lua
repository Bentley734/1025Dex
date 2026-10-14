-- SPDX-License-Identifier: GPL-3.0-or-later
-- Load the shared combat code in its own environment and API view. Neither
-- the engine's require/GameVersion nor another component's globals change.
return function(mod,registry,F)
 local unpack=table.unpack or unpack
 local function pack(...)return{n=select('#',...),...}end
 local NativeRequire=require
 local Sandbox=require('src.mods.Sandbox')
 local Damage=require('src.core.game3.battle.damage')
 local hooks=require('src.mods.Hooks').new()
 local events=require('src.mods.Events').new()
 local failures={}
 local function loadFile(path)
  return assert(load(assert(mod:read(path)),'@'..mod.path..'/'..path))()
 end
 local makeRegistry=loadFile('gen3-mechanics/content.lua')()
 local seed=loadFile('dex/data/moves/generated/registry_gen2.lua').moves
 for id,row in pairs(seed)do
  local modern=assert(registry.resolve(id),'Unresolved modern identity: '..id)
  row.index=modern.index;row.numId=modern.numId
 end
 local pokemon,items={},{}
 for id,row in mod.content.pokemon:each()do
  local info=mod.exports.statsBySpecies(id)
  if info then pokemon[id]=info;pokemon[id].levelMoves=row.learnset or{}end
 end
 for id,row in mod.content.items:each()do items[id]=row end
 local content={moves=makeRegistry(seed),pokemon=makeRegistry(pokemon),items=makeRegistry(items),
  move_effects=makeRegistry(),type_chart=makeRegistry(),constants=makeRegistry(),growth_rates=makeRegistry()}
 local chart=loadFile('dex/data/species/generated/type_chart_modern.lua')
 local typeRecords={}
 for name in pairs(require('src.core.game3.battle.types').ID)do
  if name=='PSYCHIC'then name='PSYCHIC_TYPE'end
  typeRecords[name]={name=name,category='special'}
 end
 for id,row in pairs(chart.types)do typeRecords[id]=row end
 local data={moves=content.moves.rows,pokemon=content.pokemon.rows,items=content.items.rows,
  move_effects=content.move_effects.rows,statuses={},type_chart={types=typeRecords,matchups=chart.rows}}
 local TypeChart=loadFile('gen3-mechanics/type_chart.lua')(data)
 F.setData(data)
 F.MOVE_EFFECT_RECORDS=data.move_effects
 local exports=setmetatable({},{__index=mod.exports})
 local api=setmetatable({path=mod.path..'/battle-mechanics',content=content,exports=exports},{__index=mod})
 api.options={get=function(_,key)if key=='moves'then return'all'end;return mod.options:get(key)end,
  define=function(_,rows)return mod.options:define(rows)end}
 api.hooks={wrap=function(_,name,fn,priority)
  return hooks:wrap(name,function(next,...)
   local result=pack(pcall(fn,next,...))
   if not result[1]then failures[#failures+1]={kind='hook',name=name,error=tostring(result[2])};error(result[2],0)end
   return unpack(result,2,result.n)
  end,priority,'1025dex-gen3')
 end}
 api.events={on=function(_,name,fn,priority)
  return events:on(name,function(payload)
   local ok,err=pcall(fn,payload)
   if not ok then failures[#failures+1]={kind='event',name=name,error=tostring(err)};error(err,0)end
  end,priority,'1025dex-gen3')
 end,emit=function(_,name,payload)return events:emit(name,payload)end}
 function api:read(relative)return mod:read('battle-mechanics/'..relative)end
 api.find=function(first,second)
  local id=second or first
  if id=='national_dex'or id=='1025dex'or id=='g9-battle-engine'then return{id='1025dex',exports=exports,version='1.4.0'}end
  return mod.find(first,second)
 end
 local function display(w)return w and(w.nickname or w.name or w.species)or '?'end
 local StatusRegistry={inflict=function(b,w,status,opts)
  local success=b:applyStatus(w,status,opts and opts.source)
  return success and{display(w)..' was afflicted!'}or{}
 end}
 local MoveEffects={changeStage=function(b,w,key,delta)
  b:changeStageAgainstMist(w,w,key,delta);return{display(w).."'s stats changed!"}
 end,full={},primary={}}
 local Effects={WEATHER={RAIN=true,SUN=true,SAND=true},WEATHER_TURNS=5,BATON_PASS_DROPS={},WEATHER_START_TEXT={},WEATHER_TURN_TEXT={},WEATHER_END_TEXT={},CHARGE={},COUNTER={},RECHARGE={}}
 function Effects.hitCount(effect,rng)
  if effect=='EFFECT_DOUBLE_HIT'or effect=='EFFECT_TWINEEDLE'then return 2 end
  return rng and rng(2,5)or 2
 end
 Effects.multiHitCount=Effects.hitCount
 function Effects.protectSucceeds(count,roll)return(count or 0)==0 or roll(2^(count or 0))==0 end
 local EffectRegistry={displayName=display,hitCount=Effects.hitCount}
 local Version=NativeRequire('src.core.GameVersion')
 local modelVersion=setmetatable({generation=function()return 2 end},{__index=Version})
 local uiState={update=function()error('Legacy move UI is not a Gen 3 battle screen')end}
 local statusRecords={PAR={},SLP={},FRZ={}}
 for id,divisor in pairs({BRN=16,PSN=8})do
  statusRecords[id]={residual=function(w,_,battle)
   local raw=w.mon or w
   local amount=math.max(1,math.floor(raw.stats.hp/divisor))
   raw.hp=math.max(0,raw.hp-amount)
   return{display(w)..' was hurt by its status!'}
  end}
 end
 local aliases={
  ['src.battle.gen2.Battle']=F,['src.battle.gen2.Effects']=Effects,
  ['src.battle.BattleState']=uiState,['src.battle.TypeChart']=TypeChart,
  ['src.pokemon.Stats']={applyStage=Damage.applyStage,ensure=function(_,mon)return mon end},
  ['src.battle.Damage']={BADGE_BOOSTS={}},['src.battle.MoveEffects']=MoveEffects,
  ['src.battle.EffectRegistry']=EffectRegistry,['src.battle.StatusRegistry']=StatusRegistry,
  ['src.battle.Status']={RECORDS=statusRecords,recordFor=function(records,id)return records and records[id]end},
  ['src.battle.TurnOrder']={effectiveSpeed=function(w)return w.stats.speed end},
  ['src.battle.TrainerAI']={LAYERS={}},['src.core.GameVersion']=modelVersion,
  ['src.mods.Runtime']={
   wants=function(name)return events.listeners[name]~=nil end,
   wantsHook=function(name)return hooks.chains[name]~=nil end,
   emit=function(name,payload)return events:emit(name,payload)end,
   call=function(name,vanilla,...)
    if name=='g9.request_adjacency'then
     local battle,who=...;local native=battle:native(who)
     local allies,enemies={},{}
     for _,b in ipairs(battle._adapter:activeBattlers())do
      if b~=native then
       local list=b.side==native.side and allies or enemies
       list[#list+1]=battle:view(b.mon,b)
      end
     end
     return{allies=allies,enemies=enemies}
    end
    return hooks:call(name,vanilla,...)
   end},
 }
 local env=setmetatable({},{__index=_G});env._G=env
 env.require=function(name)
  if aliases[name]then return aliases[name]end
  return NativeRequire(name)
 end
 local function compile(source,name)
  source=source:gsub('function mod.exports.requestSwitch%(battle, mon, opts%)',
   'function mod.exports.requestSwitch(battle, mon, opts) if battle.__gen3 then return battle:requestSwitchNative(mon, opts) end')
  -- Modern callbacks and native speed/accuracy checks must share one store.
  -- Restrict this adaptation to the component's private compiled source.
  source=source:gsub('local function stagesFor%(battle, mon%)',
   'local function stagesFor(battle, mon) if battle and battle.__gen3 then return battle:stageStore(mon) end')
  source=source:gsub('local function nativeStageTable%(battle, who, gen2%)',
   'local function nativeStageTable(battle, who, gen2) if battle and battle.__gen3 then return battle:stageStore(who) end')
  return Sandbox.compile(source,name,env)
 end
 env.load=compile;env.loadstring=compile
 local source=assert(api:read('main.lua'))
 -- Gen 3 owns its screen/input, native switch sequencing and learning UI.
 local omitted={switch_vanilla_bridge=true,move_availability_gate=true,battle_prompt=true,
  gen2_vocab=true,gen2_vocab_sweep=true,modern_transform=true,modern_effect_guard=true}
 env.__gen3Omitted=omitted
 source=source:gsub('local function boot%(label, fn%)','local function boot(label, fn) if __gen3Omitted[label] then return end')
 source=source:gsub('  assert%(loadSibling%("bridge/abilities.lua"%)%)%(mod%)','')
 source=source:gsub('  assert%(loadSibling%("bridge/move_tutor.lua"%)%)%(mod%)','')
 local entry=assert(compile(source,'@'..api.path..'/main.lua'))(api)
 entry(api)
 -- This native move's Gen 2 handler is upgraded by modern_hazards; its
 -- generated modern metadata carries only a placeholder effect ID.
 content.moves:patch('SPIKES',{effect='EFFECT_SPIKES'})
 return{api=api,exports=exports,content=content,data=data,class=F,environment=env,registry=registry,hooks=hooks,events=events,failures=failures}
end
