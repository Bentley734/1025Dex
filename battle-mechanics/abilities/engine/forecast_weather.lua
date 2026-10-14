-- Dispatch engine for abilities/data/forecast_weather.lua -- Phase 1.8.
--
-- WEATHER_TYPE read from national_dex's own FORECAST record (confirmed by
-- direct read): rain->Water, strong sunlight->Fire, hail->Ice. "hail" is
-- mapped to this engine's own SNOW key, the same established project
-- decision abilities/engine/switchin_weather.lua's own SNOWWARNING entry
-- already uses ("Snow is Gen 9's real replacement... we won't bring hail
-- yet") -- not a new guess, the identical precedent applied again. Any
-- other weather (none, sand, strongwinds, or a primal sun/rain) falls
-- through to NORMAL -- national_dex's own effect text: "If the weather
-- ends or becomes anything that does not trigger this ability... revert
-- to default."
--
-- Unlike Multitype (explicit user correction this session: fixed at
-- switch-in, never re-derived live), Forecast's own real mechanic DOES
-- re-check live as weather changes mid-battle -- confirmed by national_
-- dex's own effect text. Reapplied from three places:
--   1. battle.started / battle.battler_switched -- the standard switch-in
--      pair, derives against whatever weather is already up.
--   2. mod.1025dex.weather_changed -- a new, shared notification this session
--      added to combat/modern_combat.lua's own setWeather (see that
--      function's own header), firing INSTANTLY on every explicit
--      weather change on either generation, including Gen 1's natural
--      expiry (confirmed that path already calls back into setWeather
--      rather than writing the field directly).
--   3. battle.turn_ended -- a safety-net recheck, specifically for Gen 2's
--      NATIVE tickWeather expiry (gen2/Battle.lua), which setWeather's
--      own emission can never see (pure native code, never calls back
--      into this mod at all -- the same "Gen 2 handles its own thing"
--      gap this mod has documented since Phase 4). Accepts at most one
--      turn of lag for THAT one case only; every other transition is
--      instant via mod.1025dex.weather_changed. Honest, narrow, flagged rather
--      than silently approximated as instant everywhere.
--
-- Reuses combat/type_override_primitives.lua's setMonTypes/canChangeType,
-- same as every other type-changing ability in this directory. Never
-- gated by hasUsedTypeChangeThisSwitchIn/markTypeChangeUsedThisSwitchIn
-- -- that's Protean/Libero's own once-per-switch-in rule; Forecast needs
-- to re-trigger an unbounded number of times as weather keeps changing.
return function(mod, data)
  local setMonTypes = mod.exports.setMonTypes
  local canChangeType = mod.exports.canChangeType
  local abilityIdOf = mod.exports.abilityIdOf
  local currentWeather = mod.exports.currentWeather
  local isGen2Battle = mod.exports.isGen2Battle
  assert(setMonTypes and canChangeType and abilityIdOf and currentWeather and isGen2Battle,
    "forecast_weather: type_override_primitives.lua, modern_combat.lua, and ability_dispatch.lua must load first")

  local WEATHER_TYPE = { RAIN = "WATER", SUN = "FIRE", SNOW = "ICE" }

  local function reapply(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    if not canChangeType(battle, mon, { viaOpponent = false }) then return end
    local weatherKey = currentWeather(battle, isGen2Battle(battle))
    local targetType = weatherKey and WEATHER_TYPE[weatherKey]
    setMonTypes(battle, mon, { targetType or "NORMAL" })
  end

  local function reapplyBothSides(battle)
    if not battle then return end
    -- N-way (round 27): iterate the REAL active roster, not just the
    -- player/enemy pair -- in doubles/triples the second slot must also
    -- re-derive Forecast whenever the weather changes, not only the lead
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

  mod.events:on("mod.1025dex.weather_changed", function(ev) reapplyBothSides(ev and ev.battle) end)

  -- Gen 2 native-expiry safety net -- see this file's own header, point 3.
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if battle and isGen2Battle(battle) then reapplyBothSides(battle) end
  end)

  mod.log:info("g9-battle-engine: forecast_weather ability engine installed (FORECAST)")
end
