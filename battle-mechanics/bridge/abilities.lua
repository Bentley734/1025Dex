return function(mod)
 local dex=assert(mod.find('national_dex')).exports
 local stats=assert(mod.exports.ModernStats)
 local canonical={}
 for _,entry in ipairs(dex.listSpecies())do
  canonical[entry.id:upper():gsub('[^A-Z0-9]','')]=entry.id
 end
 local function candidatesFor(id,seen)
  seen=seen or{};if not id or seen[id]then return{}end;seen[id]=true
  local candidates=stats.resolveAbilities(id,dex)
  if #candidates>0 then return candidates end
  local fixed=canonical[id:upper():gsub('[^A-Z0-9]','')]
  if fixed and fixed~=id then
   candidates=candidatesFor(fixed,seen);if #candidates>0 then return candidates end
  end
  local info=dex.statsBySpecies(id)
  local live=mod.content.pokemon:get(id)
  local base=(info and info.baseSpecies)or(live and live.baseSpecies)
  return candidatesFor(base,seen)
 end
 local function assign(mon)
  mon=mon and (mon.mon or mon)
  if type(mon)~='table'or not mon.species then return end
  if mon.isEgg or mon.egg then return end
  if mon.ability==nil then stats.generateAbility(mon,candidatesFor(mon.species))end
 end
 local function party(list)for _,entry in ipairs(type(list)=='table'and list or {})do assign(entry.mon or entry)end end
 mod.events:on('battle.started',function(ev)
  local b=ev and ev.battle;if not b then return end
  party(b.playerParty or b.party or(b.game and b.game.save and b.game.save.party))
  party(b.enemyParty)
  if b.player then assign(b.player.mon or b.player)end
  if b.enemy then assign(b.enemy.mon or b.enemy)end
 end,1100)
 mod.events:on('game.ready',function(ev)
  local save=ev and ev.game and ev.game.save
  if not save then return end
  party(save.party);for _,box in ipairs(save.boxes or {})do party(box.mons or box)end
  if save.daycare then assign(save.daycare.mon)end
 end)
 mod.exports.ensureAbility=assign
 -- Make the assigned ability visible without replacing native summaries.
 mod.hooks:wrap('ui.party.submenu',function(next,game,items,mon,ctx)
  local rows=next(game,items,mon,ctx)
  assign(mon)
  if type(rows)~='table' or (ctx and ctx.battle) then return rows end
  for _,row in ipairs(rows)do if row.id=='DEX_ABILITY'then return rows end end
  local copy={};for i,row in ipairs(rows)do copy[i]=row end
  local entry={id='DEX_ABILITY',label='ABILITY',onSelect=function(selected,currentGame)
   assign(selected)
   local id=mod.exports.abilityIdOf(selected)
   local info=id and dex.abilityById(id)
   local name=info and info.name or selected.ability or 'NONE'
   local description=info and (info.shortEffect or info.effect) or 'No ability assigned.'
   local text=tostring(name)..'\n'..description
   currentGame.stack:push(mod.ui.TextBox.new(currentGame,text))
  end}
  table.insert(copy,math.max(1,#copy),entry)
  return copy
 end)
 -- Creation covers gifts, purchases, wild captures and newly hatched mons.
 -- Existing abilities, including hidden abilities, are never rerolled.
 local Version=require('src.core.GameVersion')
 local Pokemon=require(Version.generation()==2 and 'src.battle.gen2.Mon' or 'src.pokemon.Pokemon')
 local originalNew=Pokemon.new
 Pokemon.new=function(...)
  local mon=originalNew(...);assign(mon);return mon
 end
 mod.events:on('battle.battler_switched',function(ev)assign(ev and ev.battler)end,1100)
 mod.events:on('pokemon.evolved',function(ev)
  -- An evolved Pokemon keeps its slot where possible, rather than keeping
  -- an ability its new species cannot have.
  local mon=ev and ev.mon;if not mon then return end
  local candidates=candidatesFor(mon.species)
  for _,ability in ipairs(candidates)do if ability==mon.ability then return end end
  if stats.resolveHiddenAbility(mon.species,dex)==mon.ability then return end
  mon.ability=candidates[1] or mon.ability
 end)
end
