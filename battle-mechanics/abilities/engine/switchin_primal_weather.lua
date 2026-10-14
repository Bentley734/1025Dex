-- Dispatch engine for abilities/data/primal_weather_switchin.lua
-- (Desolate Land, Primordial Sea, Delta Stream) -- Phase 1.5, explicitly
-- scoped by the user as its own phase separate from Phase 1's plain
-- weather abilities (Drizzle/Drought/Snow Warning/Orichalcum Pulse,
-- abilities/engine/switchin_weather.lua), because the real mechanic
-- genuinely differs in three ways plain weather doesn't have at all:
--
-- 1. Irreplaceable except by one of the other two primals -- gated at
--    every weather-setting call site via modern_combat.lua's own
--    mod.exports.canSetWeather(battle, isPrimalSource), added alongside
--    setWeather for this phase. A plain move/ability can never override
--    an active primal; a primal always overrides whatever was there
--    (including another primal), matching real Groudon-replaces-Kyogre
--    behavior.
-- 2. Indefinite duration, no 5/8-turn countdown -- battle.weatherTurns is
--    set to math.huge rather than run through field_duration.lua's own
--    resolveFieldDuration at all (there is no held-item extension for a
--    duration that never ends anyway). Native Gen 2 tickWeather still
--    decrements this every turn (gen2/Battle.lua:4381-4392) -- harmless,
--    since math.huge - 1 stays math.huge in Lua's own floating point, so
--    the <= 0 expiry branch is never reached. Its own per-turn flavor
--    message (Effects.WEATHER_TURN_TEXT[self.weather]) has no "strongwinds"
--    entry, same pre-existing gap this mod's own SNOW value already has
--    (Effects.lua only defines rain/sun/sandstorm) -- not a regression
--    introduced here, and out of this phase's scope to fix for either.
-- 3. Ends when the setting Pokemon leaves the field (switches out OR is
--    replaced after fainting), not on a timer -- battle.weatherPrimalSetter
--    tracks who's holding it; battle.battler_switched's own `previous`
--    field (confirmed real at every one of Battle:switch's three call
--    sites, gen2/Battle.lua) fires for both cases identically, so one
--    listener covers both.
--
-- DESOLATELAND/PRIMORDIALSEA are still real national_dex kind=
-- "set_weather" records (weather="sun"/"rain") -- read live via
-- abilityBehaviorOf exactly like Phase 1's plain weather abilities, same
-- WEATHER_KEY convention. DELTASTREAM's own record is kind="other"
-- (confirmed by direct read: its weather value, "a mysterious air
-- current," isn't in national_dex's own weather vocabulary at all) --
-- STRONGWINDS is hardcoded here as the one genuinely new (non-duplicated)
-- value this file introduces, consistent with "if the label doesn't
-- exist, we make our own."
--
-- Move-fail gate: Desolate Land blocks damaging Water-type moves,
-- Primordial Sea blocks damaging Fire-type moves, both via a Battle:
-- useMove wrap that skips the native call entirely on a block -- same
-- established simplification modern_terrain.lua's own Psychic Terrain
-- block already uses (no PP cost, no "used MOVE!" line; see that file's
-- own header for why this project accepts that as a real, simpler
-- behavior rather than the exact PS mechanic). Sun/rain's own existing
-- Fire/Water damage BOOST (modern_combat.lua's weather registerDamageModifier
-- entry) already applies for free to the extreme versions too, since they
-- share the plain SUN/RAIN weather value -- real Showdown behavior, not
-- something this file needs to add separately.
--
-- Delta Stream's own type-effectiveness cap: exports
-- mod.exports.effectivenessOverrideFor, consumed by modern_combat.lua's
-- own computeModernDamage at the one point in the formula that can
-- express "replace the type multiplier" rather than "add another factor
-- on top of it" -- see that file's own header comment at the call site.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  local setWeather = mod.exports.setWeather
  local currentWeather = mod.exports.currentWeather
  local canSetWeather = mod.exports.canSetWeather
  local curTypesOf = mod.exports.curTypesOf
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  assert(setWeather and currentWeather and canSetWeather and curTypesOf and abilityIdOf and abilityBehaviorOf,
    "switchin_primal_weather: modern_combat.lua and ability_dispatch.lua must load first")

  local WEATHER_KEY = { rain = "RAIN", sun = "SUN" }
  -- Damaging-move-type -> which primal blocks it, and which weather key
  -- that primal itself sets (so the useMove wrap can check "is THIS
  -- specific primal active," not just "is any primal active").
  local BLOCKS_TYPE = {
    SUN = "WATER",  -- Desolate Land: damaging Water-type moves fail outright.
    RAIN = "FIRE",  -- Primordial Sea: damaging Fire-type moves fail outright.
  }

  local function primalTarget(id, mon)
    if id == "DELTASTREAM" then return "STRONGWINDS" end
    local record = abilityBehaviorOf(mon)
    local behavior = record and record.behaviour
    local effect = behavior and behavior.effects and behavior.effects[1]
    return effect and effect.kind == "set_weather" and WEATHER_KEY[effect.weather]
  end

  local function applySwitchInAbility(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    local target = primalTarget(id, mon)
    if not target then return end
    if currentWeather(battle, true) == target and battle.weatherPrimal
        and battle.weatherPrimalSetter == mon then
      return
    end
    -- Boss-fight "sun" protection: even a player's primal ability can't
    -- win over a boss's own set weather (explicit user rule). A boss's
    -- OWN primal ability is unaffected -- canSetWeather always authorizes
    -- battle.enemy while this protection is active. Silent no-op on
    -- refusal, matching every other ability re-check in this file.
    if not canSetWeather(battle, true, mon) then return end
    setWeather(battle, true, target, math.huge, mon)
    battle.weatherPrimal = true
    battle.weatherPrimalSetter = mon
    battle:emit({ kind = "message",
      text = Strings("%s's ability intensified the weather!", battle:monName(mon)) })
  end

  -- Round 338: Transform/Imposter re-run this for the ability it copied.
  mod.exports.registerSwitchInAbility(applySwitchInAbility)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    -- Speed order across the real, N-way roster, not a fixed player-then-
    -- enemy pair -- a Groudon vs Kyogre lead matchup must resolve
    -- fastest-first so the SLOWEST lead's primal weather is what's
    -- actually left standing (applySwitchInAbility unconditionally
    -- overwrites, never checking canSetWeather against itself). See
    -- combat/turn_order.lua's own orderActiveBattlers header for the
    -- full rule. Read lazily, not hoisted: this closure only runs later,
    -- during a real battle, by which point every mod has loaded.
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
    -- Ends when the setter leaves the field -- `previous` is whoever
    -- walked out, real for both a voluntary switch and a post-faint
    -- replacement (see this file's own header, point 3). Skipped
    -- entirely while battle.weatherBossLocked is set: a boss-fight "sun"
    -- protection is fight-wide and permanent, not tied to one mon's
    -- presence -- a multi-phase boss switching its own team mid-fight
    -- must not un-lock the weather it already claimed.
    local previous = ev and ev.previous
    if battle and previous and battle.weatherPrimalSetter == previous
        and not battle.weatherBossLocked then
      setWeather(battle, true, nil)
      battle.weatherPrimal = nil
      battle.weatherPrimalSetter = nil
    end
  end)

  ------------------------------------------------------------------
  -- Move-fail gate: Desolate Land / Primordial Sea block the OTHER
  -- element's damaging moves outright while active.
  ------------------------------------------------------------------
  if Battle then
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if self.weatherPrimal and defender then
        local blockedType = BLOCKS_TYPE[currentWeather(self, true)]
        if blockedType then
          local def = self:moveDef(moveId)
          if def and def.type == blockedType and (def.power or 0) > 0 then
            self:emit({ kind = "message",
              text = Strings("%s's move failed against the weather!", self:monName(attacker)) })
            return
          end
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  ------------------------------------------------------------------
  -- Delta Stream's own type-effectiveness cap, consumed by modern_combat
  -- .lua's own computeModernDamage.
  ------------------------------------------------------------------
  mod.exports.effectivenessOverrideFor = function(battle, target, gen2, moveType, mult)
    if not (battle and battle.weatherPrimal and currentWeather(battle, gen2) == "STRONGWINDS") then
      return nil
    end
    if not (mult and mult > 1) then return nil end
    local targetTypes = curTypesOf(target, gen2)
    for _, t in ipairs(targetTypes or {}) do
      if t == "FLYING" then return 1.0 end
    end
    return nil
  end

  mod.log:info("g9-battle-engine: switchin_primal_weather ability engine installed (DESOLATELAND, PRIMORDIALSEA, DELTASTREAM)")
end
