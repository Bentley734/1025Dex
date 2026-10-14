-- Dispatch engine for abilities/data/status_cure.lua -- Phase 8b of the
-- ability roadmap ("other" bucket). Chances are read LIVE from
-- national_dex's own abilityBehaviorOf.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local currentWeather = mod.exports.currentWeather
  local requestAdjacency = mod.exports.requestAdjacency
  local isGen2Battle = mod.exports.isGen2Battle
  assert(abilityIdOf and abilityBehaviorOf and currentWeather and requestAdjacency and isGen2Battle,
    "status_cure: ability_dispatch.lua, modern_combat.lua, and move_targeting.lua must load first")

  -- Direct field clear, matching the real, confirmed convention both
  -- engines already use for a status cure (combat/modern_items.lua's own
  -- HELD_HEAL_STATUS branch: .status/.statusTurns/.toxicCounter, all
  -- three cleared together) -- not routed through combat/
  -- showdown_primitives.lua's own Primitives.cureStatus, which uses a
  -- THIRD, lowercase status-code convention ("brn"/"par"/...) that
  -- doesn't match either engine's real field values (confirmed this
  -- session: Gen 1 uses "PSN"/"BRN"/uppercase codes, Gen 2 uses
  -- "poison"/"burn"/lowercase words) -- reusing it here without first
  -- confirming what actually writes/reads that third convention would
  -- risk a silent no-op cure.
  -- Exported for reuse -- combat/modern_movepool_damage.lua's own
  -- Purify/Lunar Blessing handlers (heal-plus-cure moves) reuse this
  -- same real convention rather than a second copy of it.
  local function cureStatusOf(mon)
    local m = mon.mon or mon
    if not m.status then return false end
    m.status = nil
    m.statusTurns = nil
    m.toxicCounter = nil
    return true
  end
  mod.exports.cureStatusOf = cureStatusOf

  -- Same percent-roll convention this mod already established (main
  -- .lua's own installMovepoolEffects): Gen 2's battle.random(100) is
  -- 0..99, Gen 1's battle.rng(1,100) is inclusive both ends.
  local function percentRoll(battle, gen2, chance)
    if gen2 then return battle.random(100) < chance end
    return battle.rng(1, 100) <= chance
  end

  local function chanceFor(mon, wantId)
    local id = abilityIdOf(mon)
    if id ~= wantId or not data[wantId] then return nil end
    local record = abilityBehaviorOf(mon)
    return (record and record.behaviour and record.behaviour.chance) or 100
  end

  ------------------------------------------------------------------
  -- SHEDSKIN -- turn-end, cures self
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and (mon.hp or 0) > 0 then
        local chance = chanceFor(mon, "SHEDSKIN")
        if chance and percentRoll(battle, gen2, chance) then cureStatusOf(mon) end
      end
    end
  end)

  ------------------------------------------------------------------
  -- HYDRATION -- cures self while raining. Reuses the SAME battle.
  -- turn_ended boundary as the weather-residual family in abilities/
  -- engine/heal.lua rather than a new event.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    if currentWeather(battle, gen2) ~= "RAIN" then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and (mon.hp or 0) > 0 and chanceFor(mon, "HYDRATION") then
        cureStatusOf(mon)
      end
    end
  end)

  ------------------------------------------------------------------
  -- NATURALCURE -- cures self on switch-out. Reuses the real `previous`
  -- field on battle.battler_switched, same as Phase 6's Regenerator.
  ------------------------------------------------------------------
  mod.events:on("battle.battler_switched", function(ev)
    local previous = ev and ev.previous
    if previous and (previous.hp or 0) > 0 and chanceFor(previous, "NATURALCURE") then
      cureStatusOf(previous)
    end
  end)

  ------------------------------------------------------------------
  -- HEALER -- turn-end, cures every adjacent ally (never self -- real
  -- Healer's own scope, confirmed "cures each adjacent ally").
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and (mon.hp or 0) > 0 then
        local chance = chanceFor(mon, "HEALER")
        if chance then
          for _, ally in ipairs(requestAdjacency(battle, mon, nil).allies) do
            if percentRoll(battle, gen2, chance) then cureStatusOf(ally) end
          end
        end
      end
    end
  end)

  mod.log:info("g9-battle-engine: status_cure installed (SHEDSKIN, HYDRATION, NATURALCURE, HEALER)")
end
