-- Phase 2 (part 1) of the move-effect completion pipeline: moves_new.lua's
-- ~14 status-infliction stubs (burn/paralyze/poison as a secondary chance
-- on a damaging move, plus two moves that raise a stat AND confuse the
-- target in the same breath). Split out as its own sibling, same reasoning
-- modern_movepool_stages.lua gives for its own split: a coherent unit, not
-- grown into modern_combat.lua. Must load after modern_combat.lua
-- (consumes its changeStage/normalize/displayNameFor exports).
--
-- Real primitive: StatusRegistry.inflict(battle, target, status, opts)
-- (src/battle/StatusRegistry.lua), the SAME function every native
-- burn/paralyze/poison side effect calls (MoveEffects.lua's statusSide,
-- BURN_SIDE_EFFECT1/2 etc.) -- confirmed real, not reimplemented: it
-- already handles the per-status type immunity (Fire can't be burned,
-- Poison can't be poisoned, Electric can't paralyze Ground -- Status.lua's
-- own canInflict per record), the "already statused" short-circuit, and
-- the correct landing text. One known, accepted quirk that rides along
-- for free because it's baked into this SHARED primitive rather than
-- something this file adds: Gen 1's FreezeBurnParalyzeEffect also blocks a
-- secondary burn/paralyze whenever the move's own type matches one of the
-- target's types (e.g. an Electric move can never paralyze an
-- Electric-type) -- a real Gen 1-only rule, not how modern Showdown works,
-- but already true of every native Gen 1 side-effect move today (Body
-- Slam, Thunderbolt, ...), not a new gap introduced for Flame
-- Wheel/Discharge/Spark/etc. here. Flagged, not silently reproduced as if
-- unnoticed.
--
-- Custom ids, never a bare native Gen 1 id (unlike the "point the move's
-- effect field straight at a native id" trick that works for two-turn/
-- recharge moves in modern_movepool_damage.lua): Gen 1's BURN_SIDE_EFFECT1
-- (10%) and PARALYZE_SIDE_EFFECT2 (30%) happen to match some of these
-- moves' real percentages exactly, but move.effect is validated as
-- f.id("move_effects") against WHICHEVER generation's move_effects
-- registry is active for that boot -- and Gen 2's copy of that registry is
-- reseeded from src/battle/gen2/Battle.lua's own EFFECT_*-named table
-- (confirmed, src/mods/Builtins.lua:89-90), not from Gen 1's
-- MoveEffects.lua, so "BURN_SIDE_EFFECT1" is not a valid reference on a
-- Gen 2 boot at all. A custom GALAR_* id, freshly registered by this file
-- on every boot regardless of generation (exactly like the pre-existing
-- GALAR_FLINCH_EFFECT_<chance>/GALAR_CONFUSE_EFFECT_<chance> in main.lua's
-- installMovepoolEffects), is the only shape that is valid on both.
--
-- Gen 2 and damage: per modern_movepool_stages.lua's own header, Gen 2's
-- dispatch calls ANY move_effects record with a `.run` field BEFORE its
-- own damage path and returns immediately once it does (confirmed,
-- gen2/Battle.lua:1533-1538: `if handler then handler(...); return end`).
-- That's true regardless of what the handler's body does -- an internal
-- `if n.gen2 then return {} end` guard does not stop Gen 2 from having
-- already skipped its own damage code by the time the guard runs. Every
-- move here is a damaging-move secondary (kind="secondary", has `.run`),
-- so exactly like Phase 1's own GMAX_* secondaries (stages.lua's own
-- header: "an unguarded secondary handler would silently eat the move's
-- damage on Gen 2"), these moves currently deal NO damage on Gen 2 --
-- a pre-existing, already-accepted Phase 1 trade-off this file inherits
-- unchanged, not a new regression, and not something a gen2-guard alone
-- can fix (the guard only stops the STATUS from also misfiring, same as
-- Phase 1's own comment already says of its own moves).
return function(mod)
  local StatusRegistry = require("src.battle.StatusRegistry")
  local Strings = require("src.core.Strings")

  local changeStage = mod.exports.changeStage
  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  assert(changeStage and normalize and displayNameFor,
    "modern_movepool_status: combat/modern_combat.lua must load first")

  -- RETIRED (2026-08-27): a `secondaryStatus` helper used to live here,
  -- registering GALAR_BURN_EFFECT_10/100, GALAR_PARALYZE_EFFECT_30/100,
  -- GALAR_POISON_EFFECT_10/30 -- six per-move, per-CHANCE handlers with
  -- the real percentage hardcoded directly into the identifier itself
  -- (the exact "acting as a data owner" pattern this project's own
  -- standing rule forbids -- national_dex already owns `ailment`/
  -- `ailmentChance` for every one of these moves). Confirmed by direct
  -- grep, all six were registered but never actually patched onto any
  -- move id anywhere -- dead code, not a live mechanic being replaced.
  -- Superseded by main.lua's own installMovepoolEffects, which reads
  -- ailment/ailmentChance live for the ENTIRE roster generically
  -- (Flame Wheel/Pyro Ball/Inferno/Discharge/Dragon Breath/Spark/
  -- Nuzzle/Cross Poison/Poison Tail/Gunk Shot/Poison Jab/Sludge Bomb
  -- included, not just the subset this dead code named) -- also fixes
  -- a real gap this code had regardless of the dead-patch issue: its own
  -- `if n.gen2 then return {} end` made it deliberately Gen 2-inert even
  -- if it HAD been wired.

  ------------------------------------------------------------------
  -- Flatter / Swagger: raise a TARGET stat AND confuse the target, both
  -- unconditional on a landed hit (kind="primary", power=0 status moves).
  -- Stages.lua's own header explicitly deferred these here: "wiring only
  -- the stat half would misreport [them] as fully implemented when half
  -- their real effect is still missing" -- both halves land in the SAME
  -- registration below, not split across two effect ids, so neither can
  -- ship alone.
  --
  -- Confusion reuses the exact field GalarGmaxDex's own pre-existing
  -- GALAR_CONFUSE_EFFECT_<chance> (main.lua) already established
  -- (target.confusedTurns, 2-5 turn approximation) rather than a second
  -- parallel mechanism, per this session's explicit instruction. Same
  -- Gen 2 caveat that mechanism already carries and Phase 1 already
  -- flagged for its own primary() handlers: a primary run()'s RETURN
  -- VALUE is not read on Gen 2 either (only battle:emit() calls are), so
  -- the printed confirmation text is Gen 1-only; confusedTurns itself
  -- still gets set on both engines since that's a direct field write, not
  -- a message.
  ------------------------------------------------------------------
  local function confuseTarget(n)
    local target = n.target
    if target.confusedTurns or target.substituteHP then
      return nil
    end
    -- Boss-fight "softStatus" protection: gated here directly, not via
    -- battle.damage_dealt -- Flatter/Swagger are power=0 status moves,
    -- so that event never fires for them at all (see combat/
    -- boss_fight_status.lua's own header for the full reasoning).
    if target == n.battle.enemy and mod.exports.bossFightHas
        and mod.exports.bossFightHas(n.battle, "softStatus") then
      return nil
    end
    -- Phase 3a (abilities/engine/status_immunity.lua): OWNTEMPO. Gated
    -- here directly, same reasoning as the boss-fight check just above --
    -- Flatter/Swagger are power=0 status moves, battle.damage_dealt
    -- never fires for them at all.
    if mod.exports.hasStatusImmunity
        and mod.exports.hasStatusImmunity(target, "confusion", n.battle) then
      return nil
    end
    target.confusedTurns = n.battle.rng(2, 5)
    return Strings("%s\nbecame confused!", displayNameFor(n.battle, target, n.gen2))
  end

  -- Flatter: +1 target Sp. Atk, then confuse. A stat RAISE on the target
  -- is never Mist-gated (applyChange's own rule in stages.lua: fromEnemy
  -- only follows a drop), so fromEnemy=false here is deliberate, not an
  -- oversight.
  mod.content.move_effects:register("GMAX_FLATTER_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local out = {}
      for _, m in ipairs(changeStage(n.battle, n.target, "spa", 1, false, n.gen2)) do
        out[#out + 1] = m
      end
      local confuseMsg = confuseTarget(n)
      if confuseMsg then out[#out + 1] = confuseMsg end
      return out
    end,
  })

  -- Swagger: +2 target Attack, then confuse.
  mod.content.move_effects:register("GMAX_SWAGGER_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local out = {}
      for _, m in ipairs(changeStage(n.battle, n.target, "attack", 2, false, n.gen2)) do
        out[#out + 1] = m
      end
      local confuseMsg = confuseTarget(n)
      if confuseMsg then out[#out + 1] = confuseMsg end
      return out
    end,
  })

  mod.log:info("galar_gmax_dex: modern_movepool_status loaded")
end
