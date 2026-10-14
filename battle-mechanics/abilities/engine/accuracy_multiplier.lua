-- Dispatch engine for abilities/data/accuracy_multiplier.lua -- Phase 6c
-- of the ability roadmap. Factors are read LIVE from national_dex's own
-- abilityBehaviorOf.
--
-- NEW PRIMITIVE: no accuracy-modifier chain existed anywhere in this mod
-- before this file. Built on `Battle:accuracyRoll`'s own real
-- `"battle.accuracy"` hook (gen2/Battle.lua, confirmed the SAME hook
-- name Gen 1's BattleState:accuracyRoll calls too, same ctx shape both
-- engines) -- the exact real extension point this engine already ships
-- for exactly this purpose, not a new hook invented for this file.
-- registerAccuracyModifier below mirrors combat/modern_combat.lua's own
-- registerDamageModifier shape (id, priority, fn(ctx)->multiplier),
-- installed here since this is the one file that needs it -- a future
-- Phase 6/7/8 ability needing accuracy too should reuse this export
-- rather than wrapping the hook a second time.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "accuracy_multiplier: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local requestAdjacency = mod.exports.requestAdjacency
  assert(abilityIdOf and abilityBehaviorOf and requestAdjacency,
    "accuracy_multiplier: ability_dispatch.lua and move_targeting.lua must load first")

  local accuracyModifiers = {} -- { {id=, priority=, fn=fn(ctx)->multiplier}, ... }
  local function registerAccuracyModifier(id, priority, fn)
    assert(type(id) == "string" and id ~= "", "accuracy modifier id is required")
    assert(type(fn) == "function", "accuracy modifier must be a function")
    for i, entry in ipairs(accuracyModifiers) do
      if entry.id == id then table.remove(accuracyModifiers, i) break end
    end
    table.insert(accuracyModifiers, { id = id, priority = priority or 0, fn = fn })
    table.sort(accuracyModifiers, function(a, b) return a.priority > b.priority end)
  end
  mod.exports.registerAccuracyModifier = registerAccuracyModifier

  -- factorFor(mon, id) -- the live accuracy_multiplier effect's own
  -- `factor` for this ability, or nil.
  local function factorFor(mon)
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return nil, nil end
    local record = abilityBehaviorOf(mon)
    for _, eff in ipairs(record and record.behaviour and record.behaviour.effects or {}) do
      if eff.kind == "accuracy_multiplier" and eff.factor then return eff.factor, id end
    end
    return nil, nil
  end

  registerAccuracyModifier("compoundeyes", 0, function(ctx)
    local factor, id = factorFor(ctx.user)
    if id == "COMPOUNDEYES" then return factor end
    return 1.0
  end)

  registerAccuracyModifier("hustle_accuracy", 0, function(ctx)
    local factor, id = factorFor(ctx.user)
    if id ~= "HUSTLE" then return 1.0 end
    local info = ctx.moveId and moveById(ctx.moveId)
    if info and info.damageClass == "physical" then return factor end
    return 1.0
  end)

  -- Victory Star: self-inclusive ally scope, confirmed via its own
  -- notes ("Applies to this Pokémon's own moves as well as its
  -- allies'") -- checks the attacker itself first (the common case in
  -- today's 2-battler engine, where requestAdjacency's own allies list
  -- is always empty), then any real adjacent ally.
  registerAccuracyModifier("victorystar", 0, function(ctx)
    local factor, id = factorFor(ctx.user)
    if id == "VICTORYSTAR" then return factor end
    for _, ally in ipairs(requestAdjacency(ctx.battle, ctx.user, nil).allies) do
      local allyFactor, allyId = factorFor(ally)
      if allyId == "VICTORYSTAR" then return allyFactor end
    end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- Phase 11 (ability gaps close-out): Sand Veil / Snow Cloak / Tangled
  -- Feet -- the evasion-half `stat_multiplier` family that
  -- abilities/engine/stat_multiplier.lua deliberately left deferred
  -- (evasion has no base stat, it is stage-only, so it can't route
  -- through Battle:battleStat the way the other members do). Their own
  -- national_dex records carry them as `stat_multiplier` on `evasion`
  -- (1.25 / 1.25 / 2 -- api/008.lua Sand Veil & Snow Cloak, api/009.lua
  -- Tangled Feet), and Showdown expresses the same mechanic as an
  -- accuracy REDUCTION applied to the attacker: `onModifyAccuracy`
  -- chainModify([3277,4096]) (= x0.8) for Sand Veil/Snow Cloak
  -- (abilities.ts:4006-4022 / 4370-4386) and chainModify(0.5) for
  -- Tangled Feet (abilities.ts:4890-4903). That is exactly this file's
  -- own multiplier shape, so they live here as 1/factor on the
  -- ATTACKER's accuracy, keyed on the ability being on the TARGET.
  -- Because they are a plain accuracy multiplier rather than an evasion
  -- stage, they are correctly NOT cancelled by Keen Eye/Unaware's own
  -- ignoreEvasion below, matching Showdown.
  ------------------------------------------------------------------
  local function evasionFactorFor(mon)
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return nil end
    local record = abilityBehaviorOf(mon)
    for _, eff in ipairs(record and record.behaviour and record.behaviour.effects or {}) do
      if eff.kind == "stat_multiplier" and eff.stat == "evasion" and eff.factor then
        return eff.factor
      end
    end
    return nil
  end

  local function weatherOf(ctx)
    local currentWeather = mod.exports.currentWeather
    local isGen2Battle = mod.exports.isGen2Battle
    if not (currentWeather and ctx.battle) then return nil end
    return currentWeather(ctx.battle, isGen2Battle and isGen2Battle(ctx.battle))
  end

  -- "confused" is stored differently per generation (Gen 2's volatile
  -- confuseCount vs Gen 1's mon.confusedTurns) -- the same split main.lua's
  -- own generic confusion branch and modern_status_effects use.
  local function holderConfused(ctx)
    local t = ctx.target
    if not t then return false end
    local isGen2Battle = mod.exports.isGen2Battle
    if isGen2Battle and isGen2Battle(ctx.battle) then
      return (ctx.battle:volatile(t).confuseCount or 0) > 0
    end
    return (t.confusedTurns or 0) > 0
  end

  local function evasionAbilityModifier(id, condition)
    registerAccuracyModifier(id, 0, function(ctx)
      if abilityIdOf(ctx.target) ~= id or not condition(ctx) then return 1.0 end
      local factor = evasionFactorFor(ctx.target)
      return factor and (1.0 / factor) or 1.0
    end)
  end
  evasionAbilityModifier("SANDVEIL", function(ctx) return weatherOf(ctx) == "SAND" end)
  evasionAbilityModifier("SNOWCLOAK", function(ctx) return weatherOf(ctx) == "SNOW" end)
  evasionAbilityModifier("TANGLEDFEET", holderConfused)

  -- Showdown's `move.ignoreEvasion` family (abilities.ts keeneye:2273-2275,
  -- illuminate:2050-2052, mindseye:2636-2638) plus Unaware's own
  -- attacker-side half (abilities.ts:5214-5234, which zeroes the
  -- opponent's evasion while the holder attacks).
  local IGNORE_EVASION_ABILITIES = {
    KEENEYE = true, ILLUMINATE = true, MINDSEYE = true, UNAWARE = true,
  }

  mod.hooks:wrap("battle.accuracy", function(nextFn, ctx)
    -- No Guard (Phase 8, "other" bucket): a real, unconditional
    -- guaranteed hit, not a multiplier -- accuracy AND evasion stages
    -- are both bypassed entirely (confirmed real: "moves used by this
    -- Pokémon, and moves used against it, never miss"), which is a
    -- different shape than anything registerAccuracyModifier can express
    -- (that chain only ever scales ctx.accuracy before the real roll;
    -- No Guard skips the roll outright). Checked first, either side --
    -- returns true directly rather than calling nextFn, matching
    -- Battle:vanillaAccuracyRoll's own real return contract (a plain hit
    -- boolean).
    if (ctx.user and abilityIdOf(ctx.user) == "NOGUARD")
        or (ctx.target and abilityIdOf(ctx.target) == "NOGUARD") then
      return true
    end
    local total = 1.0
    for _, entry in ipairs(accuracyModifiers) do
      total = total * (entry.fn(ctx) or 1.0)
    end
    if total ~= 1.0 then
      ctx.accuracy = math.floor((ctx.accuracy or 0) * total + 0.5)
    end
    -- Phase 11 (evasion-ignoring). The engine applies the real evasion
    -- stage INSIDE nextFn -- vanillaAccuracyRoll reads
    -- `self.stages[sideOf(defender)].evasion` fresh at roll time
    -- (gen2/Battle.lua:2291-2299) -- so the only faithful way to ignore
    -- it from this hook is to zero that native stage for the duration of
    -- the roll and restore it immediately after. Two real directions:
    --   * the ATTACKER holds Keen Eye / Illuminate / Mind's Eye / Unaware
    --     -> the DEFENDER's evasion is ignored (Showdown move.ignoreEvasion,
    --     abilities.ts keeneye:2273-2275 / illuminate:2050-2052 /
    --     mindseye:2636-2638; Unaware abilities.ts:5214-5234);
    --   * the DEFENDER holds Unaware -> the ATTACKER's accuracy stage is
    --     ignored (the mirror half of the same onAnyModifyBoost).
    -- pcall-guarded so an error in the downstream chain still restores
    -- the saved stages before re-raising.
    local ignoreEva = IGNORE_EVASION_ABILITIES[abilityIdOf(ctx.user)]
    local ignoreAcc = ctx.target and abilityIdOf(ctx.target) == "UNAWARE"
    if not (ignoreEva or ignoreAcc) then return nextFn(ctx) end
    local battle = ctx.battle
    if not (battle and battle.stages) then return nextFn(ctx) end
    local evaSide = ignoreEva and ctx.target and battle:sideOf(ctx.target)
    local accSide = ignoreAcc and ctx.user and battle:sideOf(ctx.user)
    local evaStore = evaSide and battle.stages[evaSide]
    local accStore = accSide and battle.stages[accSide]
    local savedEva = evaStore and evaStore.evasion
    local savedAcc = accStore and accStore.accuracy
    if evaStore then evaStore.evasion = 0 end
    if accStore then accStore.accuracy = 0 end
    local ok, result = pcall(nextFn, ctx)
    if evaStore then evaStore.evasion = savedEva end
    if accStore then accStore.accuracy = savedAcc end
    if not ok then error(result, 0) end
    return result
  end, 0)

  mod.log:info("g9-battle-engine: accuracy_multiplier installed (COMPOUNDEYES, HUSTLE, VICTORYSTAR, SANDVEIL, SNOWCLOAK, TANGLEDFEET, NOGUARD, KEENEYE/ILLUMINATE/MINDSEYE/UNAWARE evasion-ignore)")
end
