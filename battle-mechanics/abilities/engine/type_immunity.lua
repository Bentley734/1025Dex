-- Dispatch engine for abilities/data/type_immunity.lua -- Phase 3b of
-- the ability roadmap, alongside abilities/engine/status_immunity.lua's
-- own Phase 3a. Which move type is blocked, and the reaction (heal
-- fraction or stat-change stages) that fires instead, are both read
-- LIVE from national_dex's own abilityBehaviorOf at hit time -- nothing
-- here is a hardcoded per-ability fact except which EFFECT ENTRY is the
-- reaction (the record's own `when` text, "hit by a <Type>-type move",
-- distinguishes a hit-reaction effect from an unrelated one on the same
-- ability, e.g. Dry Skin's separate weather-tick effects -- confirmed
-- real strings, not guessed, via a direct dump of all five abilities'
-- full effect arrays this session).
--
-- WHY THIS IS A "battle.damage" WRAP, NOT A registerDamageModifier ENTRY
-- OR A battle.damage_dealt LISTENER: a registerDamageModifier only ever
-- scales the final number, it can't ALSO fire a heal/stat-change
-- reaction inline; and battle.damage_dealt is confirmed (combat/
-- boss_fight_status.lua's own header) to fire only for a landed,
-- NON-ZERO hit -- forcing damage to 0 via a modifier would mean that
-- event never fires at all, losing the reaction entirely. Wrapping
-- "battle.damage" directly (the same hook combat/modern_combat_protect
-- .lua's own Protect block and combat/modern_items.lua's Fling/
-- Incinerate/Belch checks already use) lets this file compute the
-- reaction and the zero-damage result in the SAME step, with no
-- downstream event to depend on.
--
-- PRIORITY 40 -- below modern_combat_protect.lua's own Protect block
-- (50), matching real Showdown: a protected target's Water Absorb does
-- NOT trigger (the move fails outright, never "hits" for absorption
-- purposes) -- Protect's own wrap runs first in the chain and returns
-- without calling next() whenever the target is protected, so this
-- wrap never even executes for a protected hit. Above modern_combat
-- .lua's own damage-formula wrap (0) and matching modern_items.lua's
-- own move-id-specific checks (also 40, Fling/Incinerate/Belch) -- safe
-- to share that tier since every entry at it is mutually exclusive by
-- what it actually matches (a specific move id there, a specific
-- ability here), so which one runs first within the tier never changes
-- the outcome.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local changeStage = mod.exports.changeStage
  assert(abilityIdOf and abilityBehaviorOf and changeStage,
    "type_immunity: ability_dispatch.lua and modern_combat.lua must load first")

  local STAT_KEY = {
    attack = "attack", defense = "defense",
    ["special-attack"] = "spa", ["special-defense"] = "spd",
    speed = "speed", accuracy = "accuracy", evasion = "evasion",
  }

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local target = ctx.target
    local move = ctx.move
    if not (target and move and move.type) then return next(ctx) end
    local id = abilityIdOf(target)
    if not (id and data[id]) then return next(ctx) end
    -- Mold Breaker/Teravolt/Turboblaze (Phase 8, other bucket; Phase 11
    -- shared primitive): ignore an ability that would block a move's
    -- effect -- scoped to the real type-immunity family specifically
    -- (this file's own real, clearest case: a Ground move now hits a
    -- Levitate/Water Absorb/Sap Sipper/etc. holder). Uses
    -- combat/modern_combat.lua's one shared predicate every immunity
    -- site now consults; see abilities/data/mold_breaker.lua for the
    -- real, honestly-narrower-than-Showdown scope this covers.
    if mod.exports.attackerIgnoresDefenderAbility
        and mod.exports.attackerIgnoresDefenderAbility(ctx.user) then
      return next(ctx)
    end
    local record = abilityBehaviorOf(target)
    local behavior = record and record.behaviour
    local effects = behavior and behavior.effects
    if not effects then return next(ctx) end

    local blocks = false
    local healFraction, statEffect
    for _, eff in ipairs(effects) do
      if eff.kind == "type_immunity" and type(eff.moveType)=="string" and eff.moveType:upper() == move.type then
        blocks = true
      elseif eff.kind == "heal" and (not eff.when or eff.when:match("^hit by")) then
        healFraction = eff.fraction
      elseif eff.kind == "stat_change" and (not eff.when or eff.when:match("^hit by")) then
        statEffect = eff
      end
    end
    if not blocks then return next(ctx) end

    -- Earth Eater (Phase 8, other bucket): real type_immunity effect
    -- entry exists (moveType="ground") but its own real heal fraction
    -- isn't structured data -- national_dex's own notes say so
    -- explicitly ("Source text does not state the healed amount as a
    -- fraction of max HP"). Real, confirmed Showdown value: 1/4 max HP,
    -- the same fraction the rest of this absorb family already uses --
    -- hardcoded here as a documented, verified exception, not a guess.
    if id == "EARTHEATER" and not healFraction then healFraction = 0.25 end

    if healFraction then
      local mon = target.mon or target
      local maxHp = mon.stats and mon.stats.hp
      if maxHp and (mon.hp or 0) < maxHp then
        local amount = math.max(1, math.floor(maxHp * healFraction))
        -- Heal Block / boss "healblock": absorb abilities heal, so gated.
        local tryHeal = mod.exports.g9TryHeal
        if tryHeal then
          tryHeal(ctx.battle, target, amount)
        else
          mon.hp = math.min(maxHp, (mon.hp or 0) + amount)
        end
      end
    elseif statEffect and STAT_KEY[statEffect.stat] then
      -- fromEnemy=false: a stat RAISE from being hit is never Mist-gated
      -- (modern_movepool_status.lua's own Flatter comment already
      -- established this exact rule for the same reason). gen2=true
      -- matches switchin_stat_change.lua's own established call
      -- convention for this same primitive.
      changeStage(ctx.battle, target, STAT_KEY[statEffect.stat], statEffect.stages, false, mod.exports.isGen2Battle(ctx.battle))
    end

    return 0, { crit = false, typeMult = 0 }
  end, 40)

  mod.log:info("g9-battle-engine: type_immunity installed (5 abilities: DRYSKIN, SAPSIPPER, WATERABSORB, VOLTABSORB, WELLBAKEDBODY)")
end
