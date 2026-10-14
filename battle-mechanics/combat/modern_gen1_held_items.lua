-- =============================================================================
-- Held-item combat effects for GEN 1 battles (round 99)
-- =============================================================================
-- THE GAP THIS CLOSES
-- combat/modern_held_item_api.lua (round 98) gave Gen 1 a saved held-item slot
-- (`mon.g9HeldItem`) and a public get/set/clear API, but nothing in the
-- engine's Gen-1 battle path ever READ that slot for a combat effect: every
-- held-item effect in this mod was either Gen-2-gated (`if not ctx.gen2 then
-- return ... end`) or relied on a Gen-2-only mechanism (`held_item.trigger`,
-- `Battle2:MOVE_EFFECTS`, `Battle:*` monkeypatches). A Gen-1 mon could hold an
-- item and it did exactly nothing. This file wires the Gen-1 side up.
--
-- WHAT IS SHARED, WHAT IS GEN-1-SPECIFIC
--   * The DAMAGE-FORMULA and stat/crit/accuracy families now run for both
--     generations directly in their original files (modern_held_items_phase2
--     .lua, modern_held_items.lua): they were only gated, not structurally
--     Gen-2 (they all flow through chains both engines' damage/accuracy/crit
--     paths already drive). Those edits also fixed a real, pre-existing bug:
--     computeModernDamage passed the engine's own battle.damage ctx to
--     applyHeldItemStatMultiplier without a gen2 field, so the whole stat-
--     multiplier family (Choice Band/Specs/Scarf, Assault Vest, Eviolite,
--     Light Ball, Thick Club, Deep Sea Tooth/Scale, Metal Powder) was inert on
--     BOTH generations. That is fixed at the source (modern_combat.lua now
--     publishes ctx.gen2), not worked around here.
--   * FIELD-EFFECT DURATION ITEMS now run for both generations too, though
--     that edit lives in combat/field_duration.lua rather than here: Damp
--     Rock / Heat Rock / Smooth Rock / Icy Rock / Terrain Extender (and Light
--     Clay wherever a real clock exists -- see the deferral note below) now
--     stretch a Gen-1 set effect 5 -> 8. resolveFieldDuration's own
--     setterItem reads the native `.item` first (Gen 2 unchanged) and then
--     falls back to this mod's Gen-1 slot, and modern_weather.lua passes its
--     setter on both generations instead of nil-gating Gen 1.
--   * This file owns only the mechanics that are GEN-1-SPECIFIC, because Gen 1
--     has no analogue of the native choke points the Gen-2 code uses:
--       1. TURN ORDER. Gen-1 Speed is read by src/battle/TurnOrder.lua, whose
--          local `effectiveSpeed` is captured by its own `firstMover` -- and
--          the mod's own battle.turn_order wrap deliberately falls through to
--          that native comparator for Gen 1. So the item Speed/priority
--          effects (Choice Scarf, Quick Powder, Iron Ball, Quick Claw, Lagging
--          Tail, Full Incense) are folded in by replacing the TurnOrder
--          module's own two functions, the one seam every Gen-1 caller
--          (BattleState:resolveTurn's direct call AND its battle.turn_order
--          nextFn closure, plus LinkBattle) reaches at call time.
--       2. FOCUS SASH / FOCUS BAND. Gen 2 runs these through the native
--          held-item trigger / the legacy damage_pipeline; Gen 1 has neither,
--          so they are applied from this file's own battle.damage wrap, above
--          the pipeline so it clamps the FINAL number.
--       3. KING'S ROCK. Gen 2's flinch roll lives in `held_item.trigger`; Gen 1
--          gets the same real 10% roll off `battle.damage_dealt`.
--       4. LEFT OVERS / BERRY JUICE. Gen 2's native held-item residual tick
--          heals these; Gen 1 has no such tick, so they ride `battle.turn_
--          ended` (which Gen 1's BattleState DOES emit -- BattleState.lua:
--          3037/3085) exactly like the mod's other Gen-1-safe residual work.
--
-- WHAT IS *NOT* WIRED HERE (flagged, not silently claimed)
--   * Choice move-lock / Assault Vest's status-move ban. Both are Gen-2
--     `Battle:forcedMove` / `Battle:usableMoves` monkeypatches; Gen 1 has no
--     equivalent method (its menu path is BattleState:chooseMenu/chooseMove
--     with fightLockedAction, a different shape that would need its own
--     selection-seam work). The STAT halves of Choice Band/Specs and Assault
--     Vest DO work on Gen 1 -- only the menu lock does not.
--   * Light Clay on the NATIVE Gen-1 screens. Gen-1 Reflect/Light Screen are
--     permanent until a switch (a plain per-mon boolean,
--     src/battle/MoveEffects.lua:239-246 -- no duration at all), so there is
--     no 5-turn clock for Light Clay to extend there. Where the MOD's own
--     screens DO carry a numeric clock on Gen 1 -- Aurora Veil and the LGPE
--     Baddy Bad / Glitzy Glow screens -- Light Clay now extends them 5 -> 8
--     exactly like Gen 2 (field_duration.lua's shared setterItem).
--   * Berry auto-eat. Gen 1 has no native berry data (`battle:itemDef` does
--     not exist on BattleState), so the ten Gen-2 berries' heldEffect taxonomy
--     has nowhere to come from on Gen 1. Leftovers/Berry Juice are handled
--     because their effect is self-describing.
--
-- Gen-1 HP writes are direct (`mon.hp = ...`), the same primitive the mod's
-- own Black Sludge already uses for Gen 1; Gen-1 BattleState exposes no
-- battle:heal, and its residual phase runs before battle.turn_ended fires, so
-- a queued message there would be out of order. Silent ticks, flagged.
return function(mod)
  local itemOf = mod.exports.itemOf
  local isGen2Battle = mod.exports.isGen2Battle
  assert(itemOf and isGen2Battle,
    "modern_gen1_held_items: combat/modern_items.lua and combat/modern_combat.lua must load first")

  local function rawMon(who) return who and (who.mon or who) or nil end

  -- The item a GEN-1 battler holds, read only from the saved slot. Used by
  -- the turn-order helpers, which are only ever invoked for Gen-1 battlers.
  local function heldItemOf(battler)
    return itemOf(battler, false)
  end

  ------------------------------------------------------------------
  -- 1. TURN ORDER -- item Speed and fractional priority.
  --
  -- Real Showdown values, matching the Gen-2 file's own registrations
  -- exactly so the two generations cannot drift:
  --   CHOICE_SCARF  x1.5 Speed (Battle2:battleStat's own Gen-2 patch)
  --   QUICK_POWDER  x2 Speed, untransformed Ditto only
  --   IRON_BALL     x0.5 Speed, unconditional
  --   QUICK_CLAW    +0.1 fractional priority, real 1/8 chance
  --   LAGGING_TAIL / FULL_INCENSE  -0.1 fractional priority
  -- The integer priority comes from national_dex's own record first (the
  -- project's standing rule: national_dex owns priority), then the move
  -- record's own field, then the engine's two native entries -- the exact
  -- same precedence TurnOrder.firstMover itself uses.
  ------------------------------------------------------------------
  local function gen1ItemSpeedMultiplier(battler)
    local item = heldItemOf(battler)
    if item == "CHOICE_SCARF" then return 1.5 end
    if item == "QUICK_POWDER" then
      local m = rawMon(battler)
      if m and m.species == "DITTO" and not m.transformed then return 2 end
      return 1
    end
    if item == "IRON_BALL" then return 0.5 end
    return 1
  end
  mod.exports.gen1ItemSpeedMultiplier = gen1ItemSpeedMultiplier

  -- roller(n) -> 0..n-1, the engine's own rng convention. nil roller (a
  -- caller that did not pass one) means "no Quick Claw proc", never a
  -- crash, so a battle without an RNG simply does not get the item roll.
  local function gen1ItemFractionalPriority(battler, roller)
    local item = heldItemOf(battler)
    if item == "QUICK_CLAW" then
      if type(roller) == "function" and roller(0, 7) == 0 then return 0.1 end
      return 0
    end
    if item == "LAGGING_TAIL" or item == "FULL_INCENSE" then return -0.1 end
    return 0
  end
  mod.exports.gen1ItemFractionalPriority = gen1ItemFractionalPriority

  local okTurnOrder, TurnOrder = pcall(require, "src.battle.TurnOrder")
  if okTurnOrder and type(TurnOrder) == "table" and type(TurnOrder.firstMover) == "function" then
    local baseEffectiveSpeed = TurnOrder.effectiveSpeed
    local function gen1BaseSpeed(battler)
      if type(baseEffectiveSpeed) == "function" then return baseEffectiveSpeed(battler) end
      -- Engine module absent (only the test harness hits this): the mod's own
      -- level-appropriate subset -- raw Speed through the real stat-stage
      -- helper. Badge/status composition is the engine's and stays there.
      local okStats, Stats = pcall(require, "src.pokemon.Stats")
      local raw = (battler and battler.curStats and battler.curStats.speed) or 0
      local stage = (battler and battler.stages and battler.stages.speed) or 0
      if okStats and Stats and type(Stats.applyStage) == "function" then
        return Stats.applyStage(raw, stage)
      end
      return raw
    end

    -- Replace the module's exported reader (external callers such as the
    -- run-away roll and Counter's Speed compare), then firstMover, which
    -- captures the ORIGINAL local and so must be rewritten to consult the
    -- patched table field instead.
    TurnOrder.effectiveSpeed = function(battler)
      local base = gen1BaseSpeed(battler)
      local mult = gen1ItemSpeedMultiplier(battler)
      if mult ~= 1 then base = math.floor(base * mult) end
      return base
    end
    local NATIVE_PRIORITY = { QUICK_ATTACK = 1, COUNTER = -1 }
    local function priorityOf(move)
      if not move then return 0 end
      if move.priority ~= nil then return move.priority end
      return NATIVE_PRIORITY[move.id] or 0
    end
    TurnOrder.firstMover = function(a, aMove, b, bMove, rng, invertTie)
      local pa, pb = priorityOf(aMove), priorityOf(bMove)
      if pa ~= pb then return pa > pb end
      local fa = gen1ItemFractionalPriority(a, rng)
      local fb = gen1ItemFractionalPriority(b, rng)
      if fa ~= fb then return fa > fb end
      local sa, sb = TurnOrder.effectiveSpeed(a), TurnOrder.effectiveSpeed(b)
      if sa ~= sb then return sa > sb end
      rng = rng or love.math.random
      local aFirst = rng(0, 1) == 0
      if invertTie then aFirst = not aFirst end
      return aFirst
    end
  end

  ------------------------------------------------------------------
  -- 2. FOCUS SASH / FOCUS BAND -- Gen-1 survive-at-1-HP clamps, on the FINAL
  -- damage number so neither can be pushed back into a KO by a later
  -- multiplier. Priority 501 sits above damage_pipeline's 500 wrap.
  -- Focus Sash requires FULL HP and is consumed; Focus Band is a real 1/10
  -- roll and is permanent (both are Showdown's own values, items.ts).
  ------------------------------------------------------------------
  local function monLooksGen2(who)
    return who ~= nil and who.curStats == nil and who.stats ~= nil
  end
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local dmg, info = next(ctx)
    if type(dmg) ~= "number" then return dmg, info end
    local gen2 = isGen2Battle(ctx.battle) or monLooksGen2(ctx.user) or monLooksGen2(ctx.target)
    if gen2 or dmg <= 0 or not ctx.target then return dmg, info end
    local who = ctx.target
    local m = rawMon(who)
    local maxHp = m and m.stats and m.stats.hp
    local hp = m and (m.hp or 0)
    if not (maxHp and hp > 1 and dmg >= hp) then return dmg, info end
    local item = heldItemOf(who)
    if item == "FOCUS_SASH" and hp == maxHp then
      mod.exports.clearHeldItem(who)
      return hp - 1, info
    end
    if item == "FOCUS_BAND" then
      local rng = ctx.rng
      if type(rng) == "function" and rng(0, 9) == 0 then
        return hp - 1, info
      end
    end
    return dmg, info
  end, 501)

  ------------------------------------------------------------------
  -- 3. KING'S ROCK -- real 10% flinch on a landed hit, x10 aggregate roll
  -- (rng(0,9)==0), skipped when the move already carries its own flinch
  -- secondary (Showdown's `if (secondary.volatileStatus === 'flinch')
  -- return`, so Rock Slide/Headbutt/Bite do not double-dip). Gen 2 keeps its
  -- native held_item.trigger roll.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    if not (battle and not isGen2Battle(battle)) then return end
    if (ev.damage or 0) <= 0 then return end
    local user, target, move = ev.user, ev.target, ev.move
    if not (user and target) then return end
    if heldItemOf(user) ~= "KINGS_ROCK" then return end
    local effect = move and move.effect
    if effect and tostring(effect):find("FLINCH", 1, true) then return end
    local rng = battle.rng
    if type(rng) ~= "function" or rng(0, 9) ~= 0 then return end
    -- Route through the central flinch setter so the Dynamax flinch immunity
    -- (Round 27) is honoured here too; fall back to a guarded raw write.
    local setFlinched = mod.exports.setFlinched
    if setFlinched then
      setFlinched(battle, target, false)
    else
      local isDyn = mod.exports.isDynamaxed
      if not (isDyn and isDyn(target)) then target.flinched = true end
    end
  end)

  ------------------------------------------------------------------
  -- 4. LEFTOVERS / BERRY_JUICE -- Gen-1 residual heals. Gen 2's native
  -- held-item tick owns both there, so this only runs when the battle is NOT
  -- Gen 2. Leftovers is a flat 1/16 max HP; Berry Juice is a flat 20 HP
  -- consumed at or below half HP.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not (battle and not isGen2Battle(battle)) then return end
    for _, who in ipairs({ battle.player, battle.enemy }) do
      local m = rawMon(who)
      if m and (m.hp or 0) > 0 then
        local maxHp = m.stats and m.stats.hp
        if maxHp and maxHp > 0 then
          local item = heldItemOf(who)
          if item == "LEFTOVERS" then
            local tryHeal = mod.exports.g9TryHeal
            if tryHeal then
              tryHeal(battle, who, math.max(1, math.floor(maxHp / 16)))
            else
              m.hp = math.min(maxHp, m.hp + math.max(1, math.floor(maxHp / 16)))
            end
          elseif item == "BERRY_JUICE" and m.hp * 2 <= maxHp then
            local tryHeal = mod.exports.g9TryHeal
            if tryHeal then
              tryHeal(battle, who, 20)
            else
              m.hp = math.min(maxHp, m.hp + 20)
            end
            -- Mirror the Gen-2 residual (modern_items.lua's own Berry Juice
            -- tick) so Recycle has the same item to restore on either
            -- generation. Berry Juice is NOT a Berry, so this deliberately
            -- does NOT set ggdConsumedBerryThisBattle (it must not enable
            -- Belch) -- the exact split the Gen-2 tick makes.
            m.ggdLastConsumedItem = "BERRY_JUICE"
            mod.exports.clearHeldItem(who)
          end
        end
      end
    end
  end)

  mod.log:info("g9-battle-engine: modern_gen1_held_items installed "
    .. "(Gen-1 held-item combat wiring: Choice Scarf/Quick Powder/Iron Ball "
    .. "Speed + Quick Claw/Lagging Tail/Full Incense turn-order priority via "
    .. "src/battle/TurnOrder; Focus Sash/Focus Band survive-at-1; King's Rock "
    .. "flinch; Leftovers/Berry Juice residual. The damage/stat/crit/accuracy "
    .. "item families are dual-generation in their own files)")
end
