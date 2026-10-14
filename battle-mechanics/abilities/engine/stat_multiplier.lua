-- Dispatch engine for abilities/data/stat_multiplier.lua -- Phase 4 of
-- the ability roadmap. Which stat and by how much are read LIVE from
-- national_dex's own abilityBehaviorOf at read time; only the CONDITION
-- TYPE (weather/terrain/HP-threshold/status/none) is a small hardcoded
-- lookup below, and only because several of these abilities' own
-- `effects[].when` field is empty in the real generated data despite
-- the ability genuinely being conditional (confirmed against each
-- record's own free-text `notes` field, not guessed -- Orichalcum
-- Pulse's and Toxic Boost's own notes explicitly state the real
-- condition even though the structured `when` field carries nothing).
--
-- WHY THIS WRAPS Battle:battleStat, NOT registerDamageModifier: that
-- chain only scales a computed DAMAGE number after the fact; these
-- abilities change the underlying STAT VALUE itself, which feeds
-- multiple unrelated computations (the damage formula's own
-- attack/specialAttack/defense/specialDefense reads, AND turn order's
-- own Speed read) that would otherwise each need their own separate
-- fix. battleStat is the one real, confirmed choke point EVERY one of
-- those already goes through (gen2/Battle.lua's own DoDamage,
-- effectiveSpeed, and confusion self-hit all call it directly) --
-- wrapping it here means every included ability is automatically
-- correct everywhere a stat gets read, with no changes needed at any of
-- those call sites, the same "one real primitive, not a parallel one"
-- discipline this mod already applies everywhere else.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local currentWeather = mod.exports.currentWeather
  local canonicalStatusOf = mod.exports.canonicalStatusOf
  local isGen2Battle = mod.exports.isGen2Battle
  local requestAdjacency = mod.exports.requestAdjacency
  assert(abilityIdOf and abilityBehaviorOf and currentWeather and canonicalStatusOf
      and requestAdjacency,
    "stat_multiplier: modern_combat.lua, status_immunity.lua, and move_targeting.lua must load first")

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil

  -- national_dex's own stat spelling -> Battle:battleStat's own key
  -- convention (confirmed by direct read of gen2/Battle.lua -- distinct
  -- from every OTHER stat-key adapter in this mod, e.g. changeStage's
  -- own "spa"/"spd" shorthand -- battleStat genuinely uses the longer
  -- camelCase form). Evasion/accuracy are deliberately absent: they have
  -- no base stat at all in this engine (stage-only, gen2/Battle.lua's
  -- own vanillaAccuracyRoll reads self.stages[...].evasion directly,
  -- never battleStat) -- see abilities/data/stat_multiplier.lua's own
  -- header for why the three evasion-multiplier abilities are deferred.
  local STAT_TO_BATTLESTAT_KEY = {
    attack = "attack", defense = "defense",
    ["special-attack"] = "specialAttack", ["special-defense"] = "specialDefense",
    speed = "speed",
  }

  local WEATHER_COND = {
    CHLOROPHYLL = "SUN", SWIFTSWIM = "RAIN", SANDRUSH = "SAND", SLUSHRUSH = "SNOW",
    SOLARPOWER = "SUN", ORICHALCUMPULSE = "SUN",
  }
  local TERRAIN_COND = { SURGESURFER = "ELECTRIC", GRASSPELT = "GRASSY", HADRONENGINE = "ELECTRIC" }

  -- Showdown-truth factor overrides. The generated national_dex data
  -- disagrees with Showdown on the two "also boosts a stat while its
  -- weather/terrain is up" signature abilities: it carries ORICHALCUMPULSE
  -- at 1.5 and HADRONENGINE at 1.3, but both really use 4/3 -- Showdown
  -- chainModify([5461, 4096]) (orichalcumpulse abilities.ts:3088-3100,
  -- hadronengine abilities.ts:1782-1792), and Bulbapedia independently
  -- states 33% for both. Showdown is this project's stated ground truth, so
  -- its real fraction wins here -- the same documented-exception discipline
  -- this engine's own header already applies to the empty conditional
  -- `when` fields. Keyed by ability id; only ever consulted for a matching
  -- stat_multiplier effect, so a future dex correction needs no other change.
  local FACTOR_OVERRIDE = {
    ORICHALCUMPULSE = 5461 / 4096,
    HADRONENGINE = 5461 / 4096,
  }
  local HP_HALF_COND = { DEFEATIST = true }
  local STATUS_COND = { FLAREBOOST = "burn", TOXICBOOST = "poison" }
  local ANY_STATUS_COND = { QUICKFEET = true, GUTS = true, MARVELSCALE = true }
  local ALLY_COND = { MINUS = true, PLUS = true }
  local UNCONDITIONAL = { HUGEPOWER = true, PUREPOWER = true, GORILLATACTICS = true }

  local function conditionMet(battle, mon, id, gen2)
    if UNCONDITIONAL[id] then return true end
    local wantWeather = WEATHER_COND[id]
    if wantWeather then
      -- Air Lock/Cloud Nine (Phase 8, other bucket): nullifies the
      -- weather-dependent boost too, real Showdown behavior.
      if mod.exports.weatherNullified and mod.exports.weatherNullified(battle) then return false end
      return currentWeather(battle, gen2) == wantWeather
    end
    local wantTerrain = TERRAIN_COND[id]
    if wantTerrain then return battle.terrain == wantTerrain end
    if HP_HALF_COND[id] then
      local m = mon.mon or mon
      local maxHp = m.stats and m.stats.hp
      return maxHp and maxHp > 0 and (m.hp or 0) <= maxHp * 0.5
    end
    local wantStatus = STATUS_COND[id]
    if wantStatus then return canonicalStatusOf(mon) == wantStatus end
    if ANY_STATUS_COND[id] then return canonicalStatusOf(mon) ~= nil end
    if ALLY_COND[id] then
      -- Real Plus/Minus scope (national_dex's own notes confirm both
      -- read the OTHER as well as themselves: "an ally on the field has
      -- Plus or Minus"). requestAdjacency's allies are the real
      -- adjacent (double-battle) allies -- in the single battles this
      -- base engine runs, none, so the boost is correctly inert there
      -- too (matching how it genuinely works in singles).
      for _, ally in ipairs(requestAdjacency(battle, mon, nil).allies) do
        local aid = ally and abilityIdOf(ally)
        if aid == "MINUS" or aid == "PLUS" then return true end
      end
      return false
    end
    return false
  end

  -- statMultiplierFor(battle, mon, battleStatKey) -> number, the product
  -- of every matching, currently-active effect (almost always exactly
  -- one factor or 1 -- no included ability has more than one
  -- stat_multiplier entry for the SAME stat, but this stays correct if
  -- one ever does). Exported directly in case anything else ever needs
  -- to preview a mon's effective stat without going through
  -- Battle:battleStat itself.
  local function statMultiplierFor(battle, mon, battleStatKey)
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return 1 end
    local record = abilityBehaviorOf(mon)
    local behavior = record and record.behaviour
    local effects = behavior and behavior.effects
    if not effects then return 1 end
    local gen2 = isGen2Battle and isGen2Battle(battle)
    local mult = 1
    for _, eff in ipairs(effects) do
      if eff.kind == "stat_multiplier" and eff.factor
          and STAT_TO_BATTLESTAT_KEY[eff.stat] == battleStatKey
          and conditionMet(battle, mon, id, gen2) then
        mult = mult * (FACTOR_OVERRIDE[id] or eff.factor)
      end
    end
    return mult
  end
  mod.exports.statMultiplierFor = statMultiplierFor

  ------------------------------------------------------------------
  -- Protosynthesis / Quark Drive (Phase 8, other bucket): a real,
  -- different SHAPE than every other ability above -- those all boost
  -- one FIXED stat; these two boost whichever of the mon's own five
  -- battle stats is currently HIGHEST, decided dynamically. Real
  -- trigger: harsh sunlight (Protosynthesis) / Electric Terrain (Quark
  -- Drive) -- Booster Energy, the real item-triggered alternative, is
  -- NOT built (this ROM's own item roster, confirmed earlier this
  -- phase via modern_items.lua's own header, has no such item at all).
  -- Real persistence, honored here: once activated, the boost survives
  -- the weather/terrain actually ending, lasting until the holder
  -- itself switches out (mon.protosynthesisActive/mon.quarkDriveActive,
  -- cleared on battle.battler_switched's own real `previous` field and
  -- defensively on battle.started for every party member, so a flag
  -- can never leak from an earlier battle into a fresh one via a
  -- persistent save-file mon object).
  ------------------------------------------------------------------
  local PROTO_TERRA = { PROTOSYNTHESIS = "weather", QUARKDRIVE = "terrain" }
  local HIGHEST_STAT_ORDER = { "attack", "defense", "specialAttack", "specialDefense", "speed" }
  local PROTO_FLAG = { PROTOSYNTHESIS = "protosynthesisActive", QUARKDRIVE = "quarkDriveActive" }
  -- Forward-declared: assigned right after Battle.battleStat is
  -- captured below, so protoQuarkBoost's own "compare all five raw
  -- stats" scan reads the TRUE native value -- never re-entering the
  -- wrapped Battle:battleStat itself, which would double-apply this
  -- same ability's own multiplier while still deciding whether to.
  local nativeBattleStatFwd

  local function protoQuarkActivate(battle, mon, id, gen2)
    local flag = PROTO_FLAG[id]
    if mon[flag] then return end
    local triggered
    if PROTO_TERRA[id] == "weather" then
      triggered = not (mod.exports.weatherNullified and mod.exports.weatherNullified(battle))
        and currentWeather(battle, gen2) == "SUN"
    else
      triggered = battle.terrain == "ELECTRIC"
    end
    if not triggered then return end
    mon[flag] = true
    battle:emit({ kind = "message",
      text = Strings("%s activated, boosting its highest stat!", (id == "PROTOSYNTHESIS" and "Protosynthesis" or "Quark Drive")) })
  end

  local function protoQuarkBoost(battle, mon, key)
    local id = abilityIdOf(mon)
    if not (id and PROTO_TERRA[id] and data[id]) then return 1 end
    local gen2 = isGen2Battle and isGen2Battle(battle)
    protoQuarkActivate(battle, mon, id, gen2)
    if not mon[PROTO_FLAG[id]] then return 1 end
    local best, bestVal = HIGHEST_STAT_ORDER[1], -math.huge
    for _, statKey in ipairs(HIGHEST_STAT_ORDER) do
      local v = nativeBattleStatFwd(battle, mon, statKey)
      if v > bestVal then best, bestVal = statKey, v end
    end
    if key ~= best then return 1 end
    return key == "speed" and 1.5 or 1.3
  end

  local function resetProtoQuark(mon)
    if mon then mon.protosynthesisActive, mon.quarkDriveActive = nil, nil end
  end
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(battle.party or {}) do resetProtoQuark(mon) end
    for _, mon in ipairs(battle.enemyParty or {}) do resetProtoQuark(mon) end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    resetProtoQuark(ev and ev.previous)
  end)

  -- Real Gen 2 rounding convention already established in this mod
  -- (combat/modern_combat_protect.lua's own Max Guard 25% scale-down:
  -- math.floor(x + 0.5)) -- matched here rather than a bare floor, so a
  -- x1.5/x1.25-shaped boost rounds the same way the rest of this mod
  -- already does.
  if Battle then
    local nativeBattleStat = Battle.battleStat
    nativeBattleStatFwd = function(battle, mon, key) return nativeBattleStat(battle, mon, key) end
    function Battle:battleStat(mon, key)
      local value = nativeBattleStat(self, mon, key)
      local mult = statMultiplierFor(self, mon, key) * protoQuarkBoost(self, mon, key)
      if mult ~= 1 then
        value = math.floor(value * mult + 0.5)
      end
      return value
    end
  else
    -- Gen 1 has no Battle:battleStat -- protoQuarkBoost's own raw-stat
    -- scan (if ever reached here) reads the battler/mon's own stat table.
    nativeBattleStatFwd = function(battle, mon, key)
      local stats = (mon and (mon.stats or (mon.mon and mon.mon.stats))) or {}
      return stats[key] or 1
    end
  end

  mod.log:info("g9-battle-engine: stat_multiplier installed (22 abilities: CHLOROPHYLL, SWIFTSWIM, SANDRUSH, SLUSHRUSH, SOLARPOWER, SURGESURFER, DEFEATIST, FLAREBOOST, TOXICBOOST, ORICHALCUMPULSE, HADRONENGINE, HUGEPOWER, PUREPOWER, GORILLATACTICS, QUICKFEET, PROTOSYNTHESIS, QUARKDRIVE, GUTS, MARVELSCALE, GRASSPELT, MINUS, PLUS)")
end
