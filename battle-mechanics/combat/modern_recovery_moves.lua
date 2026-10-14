-- Missing-effects plan, Phase 16: the recovery-move family
-- (HEALORDER, MILKDRINK, SLACKOFF, ROOST, AQUARING). Verified against
-- Showdown's own real source this pass (data/moves.ts's own records plus
-- battle-actions.ts:1198-1222, the move-resolution handler that actually
-- runs `moveData.heal`), not from memory.
--
--   HEALORDER / MILKDRINK / SLACKOFF -- a plain `heal: [1, 2]` self-move,
--     half of max HP, nothing else. national_dex gives all three
--     gen1Effect = "HEAL_EFFECT" / gen2Effect = "EFFECT_HEAL" with
--     gen1EffectModeled = gen2EffectModeled = true, and this engine's own
--     heal primitives (MoveEffects.lua's HEAL_EFFECT, gen2-Battle.lua's
--     EFFECT_HEAL) already split on move id and heal exactly
--     floor(maxHp / 2) for every move that is not Rest. They are
--     therefore ALREADY COMPLETE on both generations -- the plan's own
--     premise that all five "are not caught by the generic listener" was
--     wrong for these three. Nothing is repointed for them here
--     (re-registering an already-working native handler is pure risk for
--     no behavioral gain); they are recorded as native-covered in
--     combat/NATIVE_COVERAGE.md instead.
--
--   ROOST -- `heal: [1, 2]` PLUS `self: { volatileStatus: 'roost' }`,
--     whose condition has `duration: 1` and an `onType` that filters
--     FLYING out of the user's own types until the end of the turn. The
--     heal half is native and correct; the type-drop half was not
--     modelled anywhere. The move is repointed here at
--     GALAR_ROOST_EFFECT so both halves resolve in one handler.
--
--   AQUARING -- NO native effect at all (gen1Effect =
--     "NO_ADDITIONAL_EFFECT", gen1EffectModeled = false, gen2Effect =
--     "EFFECT_NORMAL_HIT", gen2EffectModeled = false), so this one was
--     genuinely missing. Real shape: `volatileStatus: 'aquaring'`,
--     self-target, condition onResidualOrder 6, `this.heal(pokemon
--     .baseMaxhp / 16)` every turn (1/16 max HP), ending on switch-out
--     but PASSED by Baton Pass.
--
-- Showdown's own ordering matters for Roost, and this file matches it
-- literally (battle-actions.ts:1201): the `moveData.heal` block runs
-- FIRST, and when the target is already at full HP it emits `-fail`,
-- sets `damage[i] = false`, `didAnything = null` and `continue`s --
-- skipping every later block, the `self` volatile included. So a
-- full-HP Roost FAILS and does NOT drop the Flying type. Both halves are
-- gated on the same condition below.
--
-- The Roost type drop is modelled at the one seam combat/modern_combat
-- .lua's resolvedTypeMult already exposes for exactly this question --
-- mod.exports.defensiveTypesOf, the hook combat/modern_tera.lua installed
-- for its Stellar override. It is WRAPPED, never replaced: the previous
-- implementation still runs first, so a Stellar Terastallization answer is
-- computed exactly as before and the FLYING filter is only layered on top.
-- This is the correct seam for Roost's real mechanic because the drop is a
-- purely DEFENSIVE change (an incoming move's type effectiveness): a mon
-- that uses Roost spends its own action doing it and cannot attack again
-- before the turn ends, so its own STAB never observes the drop. Because
-- resolvedTypeMult is reached through the unconditional battle.damage wrap
-- that IS every battle's damage path on both generations (modern_combat
-- .lua's own "this formula is the only damage path" header), the filter
-- works on Gen 1 and Gen 2 alike -- unlike combat/type_override_
-- primitives.lua's stored-type mutation, which is deliberately Gen 2 only.
--
-- Honest partial (documented, not faked): Aqua Ring's own "passed on by
-- Baton Pass" half is not modelled -- Baton Pass has no handler in this
-- mod yet (it is missing-effects plan PHASE 20). Switch-out and battle-end
-- both clear the ring, which is the half combat/status_condition_cleanup
-- .lua owns (see its own SWITCH_SCOPED list).
return function(mod)
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  assert(normalize and displayNameFor,
    "modern_recovery_moves: combat/modern_combat.lua must load first")

  local function monOf(who) return who and (who.mon or who) end

  -- Same direct current/max HP write every other heal in this mod uses
  -- (mon.hp / mon.stats.hp are the confirmed real fields -- native
  -- HEAL_EFFECT, MoveEffects.lua:201-214). Returns false when the mon is
  -- already full, which is the caller's fail gate, exactly the shape
  -- combat/modern_movepool_damage.lua's own healFraction uses.
  local function healFraction(battle, who, numerator, denominator)
    local mon = monOf(who)
    if not mon then return false end
    local maxHp = mon.stats and mon.stats.hp
    if not (maxHp and maxHp > 0) then return false end
    if (mon.hp or 0) >= maxHp then return false end
    local amount = math.max(1, math.floor(maxHp * numerator / denominator))
    local tryHeal = mod.exports.g9TryHeal
    if tryHeal then
      if tryHeal(battle, who, amount) <= 0 then return false end
    else
      mon.hp = math.min(maxHp, (mon.hp or 0) + amount)
    end
    return true
  end

  ------------------------------------------------------------------
  -- Aqua Ring: a self volatile, 1/16 max HP restored at the end of every
  -- turn -- the same direct-write residual shape combat/modern_status_
  -- volatiles.lua already uses for Ingrain (the other 1/16 end-of-turn
  -- self-heal in this mod). Refuses to re-apply while already up, matching
  -- Showdown's addVolatile-returns-false -> move-fails rule.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_AQUARING_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      if n.user.aquaRing then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      n.user.aquaRing = true
      return { Strings("%s\ncovered itself\nwith water!", displayNameFor(n.battle, n.user, n.gen2)) }
    end,
  })

  ------------------------------------------------------------------
  -- Roost: heal half, then drop FLYING for the rest of the turn. The
  -- full-HP check comes FIRST so a full-HP Roost fails without touching
  -- the type list at all (battle-actions.ts:1201). The drop is skipped for
  -- a Terastallized user -- Showdown's own roost condition onStart returns
  -- false once `target.terastallized` ("If a Terastallized Pokemon uses
  -- Roost, it remains Flying-type").
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_ROOST_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      if not healFraction(n.battle, n.user, 1, 2) then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      local isTerastallized = mod.exports.isTerastallized
      if not (isTerastallized and isTerastallized(n.battle, n.user, n.gen2)) then
        n.user.__g9RoostActive = true
      end
      return { Strings("%s's\nHP was restored!", displayNameFor(n.battle, n.user, n.gen2)) }
    end,
  })

  ------------------------------------------------------------------
  -- The defensive-type seam: while __g9RoostActive is set, FLYING is
  -- filtered out of the mon's live defensive type list, which is what
  -- resolvedTypeMult uses for every real effectiveness/immunity lookup.
  -- Wraps whatever defensiveTypesOf is already installed (combat/
  -- modern_tera.lua's Stellar override) rather than clobbering it.
  ------------------------------------------------------------------
  local priorDefensiveTypesOf = mod.exports.defensiveTypesOf
  mod.exports.defensiveTypesOf = function(battle, who, gen2, liveTypes)
    if priorDefensiveTypesOf then
      liveTypes = priorDefensiveTypesOf(battle, who, gen2, liveTypes)
    end
    if who and who.__g9RoostActive then
      local filtered, dropped = {}, false
      for i = 1, #(liveTypes or {}) do
        local t = liveTypes[i]
        if t == "FLYING" then dropped = true else filtered[#filtered + 1] = t end
      end
      if dropped then return filtered end
    end
    return liveTypes
  end

  ------------------------------------------------------------------
  -- End of turn: the Aqua Ring residual heal, then the Roost drop ends
  -- (the real condition's `duration: 1` -- it lasts only until the end of
  -- the turn it was used). Both are read off every active battler, the
  -- same roster combat/modern_status_volatiles.lua's own residual loop
  -- walks. The flag is cleared on both the object the effect wrote to and
  -- (defensively) its underlying mon, so a Gen 1 battler wrapper and a
  -- Gen 2 raw mon are both left clean.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local active = mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle)
      or { battle.player, battle.enemy }
    for i = 1, #active do
      local mon = active[i]
      if mon then
        if mon.aquaRing then
          healFraction(battle, mon, 1, 16)
        end
        mon.__g9RoostActive = nil
        if mon.mon then mon.mon.__g9RoostActive = nil end
      end
    end
  end)

  mod.log:info("g9-battle-engine: modern_recovery_moves installed (Aqua Ring volatile + 1/16 residual, Roost Flying-type drop for the turn; Heal Order/Milk Drink/Slack Off already native)")
end
