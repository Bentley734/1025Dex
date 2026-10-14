-- Dispatch engine for abilities/data/heal.lua -- Phase 6a of the ability
-- roadmap. Fractions are read LIVE from national_dex's own
-- abilityBehaviorOf; only which TRIGGER SHAPE each ability belongs to is
-- hardcoded, since none of these route through a single existing
-- primitive the way Phase 4/5's abilities did -- three genuinely
-- different real interception points, each documented where it's used:
--
-- 1. TURN-END WEATHER RESIDUAL (Dry Skin's sun/rain halves, Ice Body,
--    Rain Dish): `battle.turn_ended`, the exact same real turn-boundary
--    event combat/modern_weather.lua's own Gen 1 sand-chip hook already
--    uses (confirmed real, fires both generations -- that file's own
--    header). Nothing in this engine had a per-ability turn-end
--    heal/self-damage primitive before this.
--
-- 2. POISON RESIDUAL REPLACEMENT (Poison Heal): NOT a battle.turn_ended
--    listener -- that would run ALONGSIDE the native poison damage, not
--    instead of it, double-counting against the real ability (heal
--    1/8, not "take poison damage AND separately heal 1/8"). Patches the
--    actual residual FUNCTION on both engines' own status records
--    directly -- Gen 1's `Status.RECORDS.PSN.residual`, Gen 2's
--    `Battle.STATUSES.poison.residual` / `.toxic.residual` (both
--    confirmed real, public, patchable fields by direct source read) --
--    so a Poison Heal holder's own poison tick becomes a heal at the
--    exact moment the native damage would otherwise have landed, never
--    both.
--
-- 3. SWITCH EVENTS (Hospitality heals allies on switch-in, Regenerator
--    heals itself on switch-out): `battle.started`/`battle.battler_
--    switched`, the same real events abilities/engine/switchin_stat_
--    change.lua already uses -- switched confirmed to carry a real
--    `previous` field (whoever just left), read directly off the native
--    emit sites in gen2/Battle.lua, not invented for this file.
--    Hospitality's own ally heal reuses combat/move_targeting.lua's
--    requestAdjacency, the same primitive Intimidate's own foes-scope
--    lookup and status_immunity.lua's Sweet Veil ally-check already do.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local currentWeather = mod.exports.currentWeather
  local requestAdjacency = mod.exports.requestAdjacency
  local isGen2Battle = mod.exports.isGen2Battle
  assert(abilityIdOf and abilityBehaviorOf and currentWeather and requestAdjacency and isGen2Battle,
    "heal: ability_dispatch.lua, modern_combat.lua, and move_targeting.lua must load first")

  -- Shared HP-fraction helper -- the same real field convention every
  -- other heal/damage in this mod already uses (mon.hp / mon.stats.hp),
  -- defended against the battler-vs-flat-mon shape difference the same
  -- way status_immunity.lua's canonicalStatusOf already is.
  local function hpOf(mon) return (mon.mon or mon) end
  local function healFraction(battle, mon, fraction)
    local m = hpOf(mon)
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0 and (m.hp or 0) < maxHp) then return end
    local amount = math.max(1, math.floor(maxHp * fraction))
    local tryHeal = mod.exports.g9TryHeal
    if tryHeal then
      tryHeal(battle, mon, amount)
    else
      m.hp = math.min(maxHp, (m.hp or 0) + amount)
    end
  end
  local function damageSelfFraction(mon, fraction)
    local m = hpOf(mon)
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0) then return end
    local amount = math.max(1, math.floor(maxHp * fraction))
    m.hp = math.max(0, (m.hp or 0) - amount)
  end

  ------------------------------------------------------------------
  -- 1. Turn-end weather residual
  ------------------------------------------------------------------
  local TURN_END_WEATHER = {
    DRYSKIN = { { weather = "SUN", kind = "damage_self" }, { weather = "RAIN", kind = "heal" } },
    RAINDISH = { { weather = "RAIN", kind = "heal" } },
    ICEBODY = { { weather = "SNOW", kind = "heal" } },
  }

  local function applyTurnEndWeather(battle, mon)
    local id = abilityIdOf(mon)
    local configs = id and TURN_END_WEATHER[id]
    if not (configs and data[id]) then return end
    local gen2 = isGen2Battle(battle)
    local weather = currentWeather(battle, gen2)
    local record = abilityBehaviorOf(mon)
    local effects = record and record.behaviour and record.behaviour.effects
    if not effects then return end
    for _, cfg in ipairs(configs) do
      if weather == cfg.weather then
        for _, eff in ipairs(effects) do
          -- "^each turn" distinguishes THIS periodic effect from a
          -- differently-triggered one of the same kind on the same
          -- ability (Dry Skin's own "hit by a Water-type move" heal,
          -- already handled by Phase 3, is a real example of exactly
          -- that collision if this check were dropped).
          if eff.kind == cfg.kind and eff.fraction and eff.when
              and eff.when:match("^each turn") then
            if cfg.kind == "heal" then healFraction(battle, mon, eff.fraction)
            else damageSelfFraction(mon, eff.fraction) end
          end
        end
      end
    end
  end

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and (mon.hp or 0) > 0 then applyTurnEndWeather(battle, mon) end
    end
  end)

  ------------------------------------------------------------------
  -- 2. Poison Heal -- residual REPLACEMENT, not an addition
  ------------------------------------------------------------------
  local function poisonHealAmount(mon)
    local id = abilityIdOf(mon)
    if id ~= "POISONHEAL" or not data.POISONHEAL then return nil end
    local record = abilityBehaviorOf(mon)
    for _, eff in ipairs(record and record.behaviour and record.behaviour.effects or {}) do
      if eff.kind == "heal" and eff.fraction then return eff.fraction end
    end
    return nil
  end

  -- Known, minor gap: both replacements below apply the real HP change
  -- silently (no "X's Poison Heal restored some HP!" line) -- correct
  -- mechanics, no flavor text yet. Battle:tickStatus's own emit only
  -- fires when the returned damage is positive, and Status.residual's
  -- own caller only appends whatever message list is returned, so a real
  -- message needs its own battle:emit call here rather than piggy-
  -- backing on either native emit path -- not built this pass.
  local Status = require("src.battle.Status")
  local nativePsnResidual = Status.RECORDS.PSN.residual
  Status.RECORDS.PSN.residual = function(battler, opponent, battle)
    local fraction = poisonHealAmount(battler)
    if fraction then
      healFraction(battle, battler, fraction)
      return {}
    end
    return nativePsnResidual(battler, opponent, battle)
  end

  -- Gen 2's own STATUSES table lives in src.battle.gen2.Battle, which a Gen 1
  -- game refuses to require (crossGenerationDenial). Guarded so this whole
  -- file -- DRYSKIN/ICEBODY/RAINDISH/POISONHEAL/HOSPITALITY/REGENERATOR --
  -- still installs its Gen-1 half instead of failing the boot.
  local gen2ok, Battle = pcall(require, "src.battle.gen2.Battle")
  local function patchGen2PoisonResidual(statusKey)
    if not (gen2ok and type(Battle) == "table") then return end
    local record = Battle.STATUSES[statusKey]
    if not record then return end
    local native = record.residual
    record.residual = function(battle, mon, maxHp)
      local fraction = poisonHealAmount(mon)
      if fraction then
        healFraction(battle, mon, fraction)
        return 0 -- Battle:tickStatus skips the emit/hp-write when damage<=0
      end
      return native(battle, mon, maxHp)
    end
  end
  patchGen2PoisonResidual("poison")
  patchGen2PoisonResidual("toxic")

  ------------------------------------------------------------------
  -- 3. Switch-triggered: Hospitality (ally, switch-in) / Regenerator
  --    (self, switch-out)
  ------------------------------------------------------------------
  local function hospitalityFraction(mon)
    local id = abilityIdOf(mon)
    if id ~= "HOSPITALITY" or not data.HOSPITALITY then return nil end
    local record = abilityBehaviorOf(mon)
    for _, eff in ipairs(record and record.behaviour and record.behaviour.effects or {}) do
      if eff.kind == "heal" and eff.fraction then return eff.fraction end
    end
    return nil
  end
  local function applyHospitality(battle, mon)
    local fraction = hospitalityFraction(mon)
    if not fraction then return end
    for _, ally in ipairs(requestAdjacency(battle, mon, nil).allies) do
      healFraction(battle, ally, fraction)
    end
  end

  -- Round 338: Transform/Imposter re-run this for the ability it copied.
  mod.exports.registerSwitchInAbility(applyHospitality)

  local function regeneratorFraction(mon)
    local id = abilityIdOf(mon)
    if id ~= "REGENERATOR" or not data.REGENERATOR then return nil end
    local record = abilityBehaviorOf(mon)
    for _, eff in ipairs(record and record.behaviour and record.behaviour.effects or {}) do
      if eff.kind == "heal" and eff.fraction then return eff.fraction end
    end
    return nil
  end

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    if battle.player then applyHospitality(battle, battle.player) end
    if battle.enemy then applyHospitality(battle, battle.enemy) end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local mon = ev and ev.battler
    local previous = ev and ev.previous
    if not battle then return end
    if mon then applyHospitality(battle, mon) end
    -- Real Regenerator rule (its own notes, confirmed): does not trigger
    -- when switched out due to fainting.
    if previous and (previous.hp or 0) > 0 then
      local fraction = regeneratorFraction(previous)
      if fraction then healFraction(battle, previous, fraction) end
    end
  end)

  mod.log:info("g9-battle-engine: heal installed (DRYSKIN, ICEBODY, RAINDISH, POISONHEAL, HOSPITALITY, REGENERATOR)")
end
