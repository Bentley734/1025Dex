-- Dispatch engine for abilities/data/weather_switchin.lua -- that file is
-- only an inclusion list; the weather value is read LIVE from national_dex
-- 's own abilityBehaviorOf here, at dispatch time, every time. The one
-- genuinely new (non-duplicated) piece is WEATHER_KEY: PokeAPI's own
-- lowercase weather spelling (national_dex's behaviour.effects[].weather)
-- mapped to this engine's own RAIN/SUN/SAND/SNOW keys --
-- SNOWWARNING's own record literally says weather="hail", but this engine
-- deliberately has no hail value at all (combat/modern_weather.lua's own
-- header: "Snow (Snowscape) is Gen 9's real replacement... we won't bring
-- hail yet") -- mapped to SNOW here, consistent with that already-
-- established project decision, not a new guess. Every other mapping here
-- is a plain 1:1 rename.
--
-- Sets the field's weather via the exact primitive combat/
-- modern_weather.lua's own move starters already use.
--
-- Duration: real current Showdown -- an ability-set weather lasts the same
-- 5/8 turns a move-set one does (no held-item extension applies to an
-- ability trigger, since the setter never "holds" the weather-rock item
-- for its OWN ability the way a move's user would need to) -- so this
-- passes the setter mon through combat/field_duration.lua's own
-- resolveFieldDuration exactly like modern_weather.lua's weatherStarter
-- does, keeping the Damp Rock/Heat Rock/Smooth Rock/Icy Rock check
-- available for free if a Pokemon happens to hold the matching rock AND
-- have the matching ability.
--
-- Triggers: battle.started + battle.battler_switched -- identical two-
-- event pattern abilities/engine/switchin_stat_change.lua's own header
-- explains in full (both are real, separate, and both needed).
--
-- "Already this weather -> does nothing" (no failure message, unlike a
-- move): a real Showdown ability re-checks silently, never prints a "but
-- it failed" line the way a move would -- this file matches that by simply
-- not re-setting an already-matching weather rather than emitting
-- anything.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local setWeather = mod.exports.setWeather
  local currentWeather = mod.exports.currentWeather
  local canSetWeather = mod.exports.canSetWeather
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local FIELD_BASE_TURNS = mod.exports.FIELD_BASE_TURNS
  local FIELD_EXTENDED_TURNS = mod.exports.FIELD_EXTENDED_TURNS
  assert(setWeather and currentWeather and canSetWeather and abilityIdOf
      and abilityBehaviorOf and resolveFieldDuration,
    "switchin_weather: modern_combat.lua, field_duration.lua, and ability_dispatch.lua must load first")

  local WEATHER_KEY = { rain = "RAIN", sun = "SUN", sandstorm = "SAND", hail = "SNOW" }
  local WEATHER_EXTEND_ITEM = {
    RAIN = "DAMPROCK", SUN = "HEATROCK", SAND = "SMOOTHROCK", SNOW = "ICYROCK",
  }

  local function applySwitchInAbility(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    local record = abilityBehaviorOf(mon)
    local behavior = record and record.behaviour
    local effect = behavior and behavior.effects and behavior.effects[1]
    local weather = effect and effect.kind == "set_weather" and WEATHER_KEY[effect.weather]
    if not weather then return end
    if currentWeather(battle, true) == weather then return end
    -- Phase 1.5's own primal-weather lock (Desolate Land/Primordial Sea/
    -- Delta Stream) blocks a plain weather ability exactly like it blocks
    -- a plain weather move -- see modern_combat.lua's own canSetWeather
    -- header. Silent no-op, same as every other re-check in this file.
    -- Boss-fight "sun" protection rides the same check (mon lets it tell
    -- the boss's own side from the player's).
    if not canSetWeather(battle, false, mon) then return end
    local turns = resolveFieldDuration(mon, FIELD_BASE_TURNS, FIELD_EXTENDED_TURNS,
      WEATHER_EXTEND_ITEM[weather])
    setWeather(battle, true, weather, turns, mon)
    battle:emit({ kind = "message", text = Strings("%s's ability changed the weather!", battle:monName(mon)) })
  end

  -- Round 338: Transform/Imposter re-run this for the ability it copied.
  mod.exports.registerSwitchInAbility(applySwitchInAbility)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    -- Speed order across the real, N-way roster, not a fixed player-then-
    -- enemy pair -- a Drought vs Drizzle lead matchup must resolve
    -- fastest-first so the SLOWEST lead's weather is what's actually
    -- left standing (each overwrites the other unconditionally). See
    -- combat/turn_order.lua's own orderActiveBattlers header for the
    -- full rule. Read lazily, not hoisted: this closure only runs later,
    -- during a real battle, by which point every mod (including
    -- turn_order.lua) has loaded.
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

  mod.log:info("g9-battle-engine: switchin_weather ability engine installed (DRIZZLE, DROUGHT, SNOWWARNING, ORICHALCUMPULSE)")
end
