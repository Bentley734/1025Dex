-- Dispatch engine for abilities/data/terrain_switchin.lua -- that file is
-- only an inclusion list; the terrain value is read LIVE from national_dex
-- 's own abilityBehaviorOf here, at dispatch time, every time. TERRAIN_KEY
-- is the one genuinely new (non-duplicated) piece: PokeAPI's own lowercase
-- terrain spelling (national_dex's behaviour.effects[].terrain) mapped to
-- this engine's own ELECTRIC/GRASSY/MISTY/PSYCHIC keys -- a plain 1:1
-- rename, no special cases like weather's own hail->SNOW override.
--
-- Sets the field's terrain via mod.exports.setTerrain (combat/
-- modern_terrain.lua's own primitive, extracted from its move starters so
-- a move and an ability never duplicate the "already this terrain -> no-
-- op, a different one -> replaces it" + duration + message logic).
--
-- Triggers: battle.started + battle.battler_switched -- identical two-
-- event pattern abilities/engine/switchin_stat_change.lua's own header
-- explains in full.
--
-- No failure message on a no-op, unlike a move: a real ability re-checks
-- silently.
return function(mod, data)
  local setTerrain = mod.exports.setTerrain
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  assert(setTerrain and abilityIdOf and abilityBehaviorOf,
    "switchin_terrain: modern_terrain.lua and ability_dispatch.lua must load first")

  local TERRAIN_KEY = { electric = "ELECTRIC", grassy = "GRASSY", misty = "MISTY", psychic = "PSYCHIC" }
  local START_TEXT = {
    ELECTRIC = "An electric current ran across the battlefield!",
    GRASSY = "Grass grew to cover the battlefield!",
    MISTY = "Mist swirled around the battlefield!",
    PSYCHIC = "The battlefield got weird!",
  }

  local function applySwitchInAbility(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    local record = abilityBehaviorOf(mon)
    local behavior = record and record.behaviour
    local effect = behavior and behavior.effects and behavior.effects[1]
    local terrain = effect and effect.kind == "set_terrain" and TERRAIN_KEY[effect.terrain]
    if not terrain then return end
    setTerrain(battle, mon, terrain, START_TEXT[terrain] or "The battlefield changed!")
  end

  -- Round 338: Transform/Imposter re-run this for the ability it copied.
  mod.exports.registerSwitchInAbility(applySwitchInAbility)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    -- Speed order across the real, N-way roster, not a fixed player-then-
    -- enemy pair -- an Electric Surge vs Grassy Surge lead matchup must
    -- resolve fastest-first so the SLOWEST lead's terrain is what's
    -- actually left standing (setTerrain unconditionally replaces
    -- whatever terrain was there). See combat/turn_order.lua's own
    -- orderActiveBattlers header for the full rule. Read lazily, not
    -- hoisted: this closure only runs later, during a real battle, by
    -- which point every mod has loaded.
    local allActiveBattlers = mod.exports.allActiveBattlers
    local orderActiveBattlers = mod.exports.orderActiveBattlers
    local roster = allActiveBattlers and allActiveBattlers(battle) or { battle.player, battle.enemy }
    local ordered = orderActiveBattlers and orderActiveBattlers(battle, roster) or roster
    for _, mon in ipairs(ordered) do applySwitchInAbility(battle, mon) end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local mon = ev and ev.battler
    if battle and mon then applySwitchInAbility(battle, mon) end
  end)

  mod.log:info("g9-battle-engine: switchin_terrain ability engine installed (ELECTRICSURGE, GRASSYSURGE, MISTYSURGE, PSYCHICSURGE, HADRONENGINE)")
end
