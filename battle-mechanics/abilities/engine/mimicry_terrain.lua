-- Dispatch engine for abilities/data/mimicry_terrain.lua -- Phase 1.8.
--
-- TERRAIN_TYPE: Electric Terrain -> Electric, Grassy Terrain -> Grass,
-- Misty Terrain -> Fairy, Psychic Terrain -> Psychic, no terrain ->
-- Normal -- confirmed against national_dex's own MIMICRY record ("the
-- type matching the currently active terrain (Normal if no terrain is
-- active)"), which describes the RULE in prose but not a structured
-- terrain->type table; the per-terrain mapping itself is real, current
-- Showdown mechanic data, not a project-specific choice.
--
-- Same re-derivation shape as abilities/engine/forecast_weather.lua
-- (continuously live, unlike Multitype's fixed-at-switch-in rule) --
-- reapplies on switch-in and on every terrain change. Simpler than
-- Forecast: terrain has NO Gen-2-native-unreachable-expiry gap to work
-- around at all (confirmed: Terrain is Gen 6+, so Gen 2's cartridge has
-- no native terrain concept to collide with or hide behind -- this mod's
-- own combat/modern_terrain.lua is the ONLY mechanism setting/clearing
-- terrain on either generation, and both of its change points -- setTerrain
-- itself and its own battle.turn_ended expiry block -- already fire
-- mod.1025dex.terrain_changed, so no turn_ended safety net is needed here the way
-- Forecast needs one for Gen 2 weather).
--
-- Reuses combat/type_override_primitives.lua's setMonTypes/canChangeType,
-- same as every other type-changing ability in this directory. Never
-- gated by the once-per-switch-in limiter, same reasoning as Forecast.
return function(mod, data)
  local setMonTypes = mod.exports.setMonTypes
  local canChangeType = mod.exports.canChangeType
  local abilityIdOf = mod.exports.abilityIdOf
  assert(setMonTypes and canChangeType and abilityIdOf,
    "mimicry_terrain: type_override_primitives.lua and ability_dispatch.lua must load first")

  local TERRAIN_TYPE = { ELECTRIC = "ELECTRIC", GRASSY = "GRASS", MISTY = "FAIRY", PSYCHIC = "PSYCHIC" }

  local function reapply(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    if not canChangeType(battle, mon, { viaOpponent = false }) then return end
    local targetType = battle.terrain and TERRAIN_TYPE[battle.terrain]
    setMonTypes(battle, mon, { targetType or "NORMAL" })
  end

  local function reapplyBothSides(battle)
    if not battle then return end
    -- N-way (round 27): iterate the REAL active roster, not just the
    -- player/enemy pair -- in doubles/triples the second slot must also
    -- re-derive Mimicry every time the terrain changes, not only the lead
    -- pair. Falls back to the native pair when move_targeting.lua's
    -- allActiveBattlers isn't available (read lazily, the usual convention).
    local allActiveBattlers = mod.exports.allActiveBattlers
    local roster = allActiveBattlers and allActiveBattlers(battle) or { battle.player, battle.enemy }
    for _, mon in ipairs(roster) do
      if mon then reapply(battle, mon) end
    end
  end

  mod.events:on("battle.started", function(ev) reapplyBothSides(ev and ev.battle) end)

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local mon = ev and ev.battler
    if battle and mon then reapply(battle, mon) end
  end)

  mod.events:on("mod.1025dex.terrain_changed", function(ev) reapplyBothSides(ev and ev.battle) end)

  mod.log:info("g9-battle-engine: mimicry_terrain ability engine installed (MIMICRY)")
end
