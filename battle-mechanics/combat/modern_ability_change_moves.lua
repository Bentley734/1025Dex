-- Ability-changing/suppressing moves.
--
-- Phase 10 of the missing-effects pipeline added Role Play, Simple Beam and
-- Doodle here; the earlier pass shipped Skill Swap, Worry Seed, Entrainment
-- and Gastro Acid. Every real change still goes through ONE primitive --
-- abilities/ability_dispatch.lua's own mod.exports.setAbility -- which is
-- combat-only (restores each mon's own natural ability on switch-out/
-- battle-end) and boss-immune (refuses outright against battle.enemy), both
-- already enforced there, not duplicated here. (Corrosive Gas is NOT here:
-- Showdown destroys the target's held ITEM, not its ability, so it lives in
-- combat/modern_items.lua beside Knock Off/Thief/Covet, reusing that file's
-- own itemOf / isUnremovable / Sticky Hold checks.)
--
-- MESSAGE DELIVERY FIX (also Phase 10): the four pre-existing handlers
-- returned `{ Strings(...) }`, but Gen 2's dispatch discards a run handler's
-- return value (combat/SUBEFFECTS.md; combat/modern_stat_manipulation.lua's
-- own finish() note) -- so Skill Swap et al printed NOTHING on Gen 2. All
-- handlers now route their lines through the same finish() helper Phase 2
-- established: Gen 2 emits each line itself, Gen 1 returns the list.
--
-- SHOWDOWN SOURCE OF TRUTH (scratch/showdown/*.ts, read by direct extraction
-- this session; line numbers cited per clause). The refusal flags are NOT one
-- shared list -- each move reads its own real ability flag(s):
--   skillswap  (moves.ts:16591-16607) -> this.skillSwap(source, target)
--              (battle.ts:1311-1339): fails if EITHER mon's ability carries
--              `failskillswap`, then runs the `SetAbility` event; Pokemon
--              .setAbility itself (pokemon.ts:1908-1935) ALSO refuses when
--              either the old or the new ability carries `cantsuppress`
--              (pokemon.ts:1917-1919). Gen 6+ allows swapping two IDENTICAL
--              abilities -- only `this.gen <= 5` fails on that
--              (battle.ts:1320), so this file no longer fails on it either.
--   worryseed  (moves.ts:21051-21081): onTryImmunity -> fail if target is
--              Truant or Insomnia; onTryHit -> fail if the target's ability
--              carries `cantsuppress`.
--   entrainment(moves.ts:4860-4888): onTryHit -> fail if target === source,
--              or the target's ability carries `cantsuppress`, or the target
--              is Truant, or the SOURCE's ability carries `noentrain` (and
--              setAbility refuses a cantsuppress source ability too).
--   gastroacid (moves.ts:6427-6461): onTryHit -> fail if the target's ability
--              carries `cantsuppress`.
--   roleplay   (moves.ts:15324-15345): onTryHit -> fail if target.ability ===
--              source.ability, or the target's ability carries `failroleplay`,
--              or the SOURCE's ability carries `cantsuppress`; onHit ->
--              source.setAbility(target.ability).
--   simplebeam (moves.ts:16483-16505): onTryHit -> fail if the target's
--              ability carries `cantsuppress`, or is Simple, or is Truant;
--              onHit -> target.setAbility('simple').
--   doodle     (moves.ts:3814-3845): onHit -> if the target's ability carries
--              `failroleplay` do nothing; else for every pokemon of
--              source.alliesAndSelf(): skip if pokemon.ability ===
--              target.ability or pokemon.getAbility() carries `cantsuppress`,
--              else pokemon.setAbility(target.ability). Fails if nothing
--              changed.
--
-- THE FLAG SETS are transcribed from abilities.ts' own `flags:` lines
-- (`failroleplay: 1`, `cantsuppress: 1`, `failskillswap: 1`, `noentrain: 1`),
-- then restricted to the ids THIS engine actually builds -- the mod's own
-- abilities/data + abilities/engine files (ability_copy, damage_immunity,
-- form_change_scope, form_combat_effects, forecast_weather, multitype_switchin,
-- neutralizing_gas, stat_multiplier, status_immunity, switch_priority_misc,
-- switchin_multitype, truant). Every other flagged ability in Showdown's list
-- is either not built here or is a doubles-only/ally-scope distinction the
-- 1v1 reduction cannot express, and is deliberately not listed rather than
-- silently absorbing a broad "everything exotic" bucket the way the pre-
-- Phase-10 single UNCHANGEABLE = { MULTITYPE } table did (that table's own
-- header assumed none of these abilities existed in this engine; they do).
return function(mod)
  local normalize = mod.exports.normalize
  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local setAbility = mod.exports.setAbility
  local displayNameFor = mod.exports.displayNameFor
  assert(normalize and abilityIdOf and setAbility and displayNameFor,
    "modern_ability_change_moves: combat/modern_combat.lua and abilities/ability_dispatch.lua must load first")

  -- Showdown abilities.ts `failroleplay` (Role Play / Doodle refuse to copy
  -- these), restricted to ids this engine builds.
  local FAIL_ROLEPLAY = {
    WONDERGUARD = true, TRACE = true, COMATOSE = true, DISGUISE = true,
    ICEFACE = true, SCHOOLING = true, STANCECHANGE = true, ZENMODE = true,
    POWERCONSTRUCT = true, IMPOSTER = true, ZEROTOHERO = true,
    RKSSYSTEM = true, NEUTRALIZINGGAS = true, BATTLEBOND = true,
    FORECAST = true, FLOWERGIFT = true, POWEROFALCHEMY = true,
    RECEIVER = true, MULTITYPE = true, ASONEGLASTRIER = true,
    ASONESPECTRIER = true, HUNGERSWITCH = true, COMMANDER = true,
    TERASHELL = true, TERAFORMZERO = true, EMBODYASPECT = true,
  }
  -- Showdown abilities.ts `cantsuppress` (the ability slot simply cannot be
  -- overwritten/suppressed; Pokemon.setAbility refuses it on BOTH sides).
  local CANT_SUPPRESS = {
    COMATOSE = true, DISGUISE = true, ICEFACE = true, SCHOOLING = true,
    STANCECHANGE = true, ZENMODE = true, POWERCONSTRUCT = true,
    ZEROTOHERO = true, RKSSYSTEM = true, GULPMISSILE = true,
    BATTLEBOND = true, MULTITYPE = true, ASONEGLASTRIER = true,
    ASONESPECTRIER = true, MUMMY = true, LINGERINGAROMA = true,
  }
  -- Exported (Phase 19) so combat/modern_item_moves.lua's Core Enforcer
  -- suppression reads the exact same refusal list this file's own move
  -- handlers do, rather than a second copy that could drift.
  mod.exports.CANNOT_SUPPRESS = CANT_SUPPRESS
  -- Showdown abilities.ts `failskillswap`.
  local FAIL_SKILLSWAP = {
    WONDERGUARD = true, COMATOSE = true, DISGUISE = true, ICEFACE = true,
    SCHOOLING = true, STANCECHANGE = true, ZENMODE = true,
    POWERCONSTRUCT = true, ZEROTOHERO = true, RKSSYSTEM = true,
    NEUTRALIZINGGAS = true, BATTLEBOND = true, MULTITYPE = true,
    ASONEGLASTRIER = true, ASONESPECTRIER = true, HUNGERSWITCH = true,
    COMMANDER = true, TERASHELL = true, TERAFORMZERO = true,
  }
  -- Showdown abilities.ts `noentrain`.
  local NO_ENTRAIN = {
    WONDERGUARD = true, TRACE = true, COMATOSE = true, DISGUISE = true,
    ICEFACE = true, SCHOOLING = true, STANCECHANGE = true, ZENMODE = true,
    POWERCONSTRUCT = true, IMPOSTER = true, ZEROTOHERO = true,
    RKSSYSTEM = true, NEUTRALIZINGGAS = true, BATTLEBOND = true,
    FORECAST = true, FLOWERGIFT = true, POWEROFALCHEMY = true,
    RECEIVER = true, MULTITYPE = true, ASONEGLASTRIER = true,
    ASONESPECTRIER = true, HUNGERSWITCH = true, COMMANDER = true,
    TERASHELL = true, TERAFORMZERO = true,
  }

  -- Collect a run() handler's messages and hand them back once: Gen 2 emits
  -- each line itself (its dispatch ignores a run() handler's return value,
  -- so the pre-Phase-10 version of this file printed NOTHING on Gen 2), Gen 1
  -- returns the list for performMove's own sayNext loop. The exact
  -- cross-generation convention combat/modern_stat_manipulation.lua's own
  -- finish() established in Phase 2.
  local function finish(n, lines)
    if n.gen2 then
      for i = 1, #lines do
        n.battle:emit({ kind = "message", text = lines[i] })
      end
      return {}
    end
    return lines
  end
  local function fail(n)
    return finish(n, { romText(n.battle.data, "_ButItFailedText", "But, it failed!") })
  end

  ------------------------------------------------------------------
  -- Skill Swap -- mutual, both ways.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_SKILLSWAP_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user, target = n.user, n.target
      local userId, targetId = abilityIdOf(user), abilityIdOf(target)
      -- battle.ts:1311-1339 -- either side's `failskillswap`, or either
      -- side's `cantsuppress` (Pokemon.setAbility's own refusal). Gen 6+
      -- does NOT fail on two identical abilities, so neither do we.
      if not (userId and targetId)
          or FAIL_SKILLSWAP[userId] or FAIL_SKILLSWAP[targetId]
          or CANT_SUPPRESS[userId] or CANT_SUPPRESS[targetId] then
        return fail(n)
      end
      -- Second half gated on the first's own real success -- see
      -- abilities/engine/ability_copy.lua's own Wandering Spirit note for
      -- why (boss-immunity must refuse the WHOLE swap, never a half one).
      local userChanged = setAbility(n.battle, user, targetId)
      if userChanged == false then return fail(n) end
      setAbility(n.battle, target, userId)
      return finish(n, { Strings("%s and %s swapped\nabilities!",
        displayNameFor(n.battle, user, n.gen2), displayNameFor(n.battle, target, n.gen2)) })
    end,
  })

  ------------------------------------------------------------------
  -- Worry Seed -- target's ability becomes Insomnia. Real, confirmed
  -- refusals (moves.ts:21051-21081): already Insomnia, Truant, or a
  -- `cantsuppress` ability.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_WORRYSEED_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local target = n.target
      local targetId = abilityIdOf(target)
      if targetId == "INSOMNIA" or targetId == "TRUANT" or CANT_SUPPRESS[targetId] then
        return fail(n)
      end
      local changed = setAbility(n.battle, target, "INSOMNIA")
      if changed == false then return fail(n) end
      return finish(n, { Strings("%s's ability\nbecame Insomnia!", displayNameFor(n.battle, target, n.gen2)) })
    end,
  })

  ------------------------------------------------------------------
  -- Entrainment -- one-way, user's current ability copied onto target.
  -- Real refusals (moves.ts:4860-4888): target already identical, target
  -- `cantsuppress` or Truant, or the SOURCE ability `noentrain` /
  -- `cantsuppress`.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_ENTRAINMENT_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user, target = n.user, n.target
      local userId, targetId = abilityIdOf(user), abilityIdOf(target)
      if not userId
          or userId == targetId
          or targetId == "TRUANT" or CANT_SUPPRESS[targetId]
          or NO_ENTRAIN[userId] or CANT_SUPPRESS[userId] then
        return fail(n)
      end
      local changed = setAbility(n.battle, target, userId)
      if changed == false then return fail(n) end
      return finish(n, { Strings("%s's ability\nbecame the same as\nthe opponent's!",
        displayNameFor(n.battle, target, n.gen2)) })
    end,
  })

  ------------------------------------------------------------------
  -- Gastro Acid -- suppresses the target's ability outright (setAbility
  -- with a nil id) for the rest of its time on the field. Closes the
  -- exact "g9 ability-suppression TODO" this mod's own memory named as
  -- deferred pending a real ability-execution system -- that system has
  -- existed since Phase 0 of this roadmap; only setAbility itself was
  -- still missing. Real refusal (moves.ts:6427-6461): a `cantsuppress`
  -- target.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_GASTROACID_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local target = n.target
      local targetId = abilityIdOf(target)
      if not targetId or CANT_SUPPRESS[targetId] then return fail(n) end
      local changed = setAbility(n.battle, target, nil)
      if changed == false then return fail(n) end
      return finish(n, { Strings("%s's ability\nwas suppressed!", displayNameFor(n.battle, target, n.gen2)) })
    end,
  })

  ------------------------------------------------------------------
  -- Role Play -- the USER copies the TARGET's ability. Real refusals
  -- (moves.ts:15324-15345): the two abilities already match, the target's
  -- ability is `failroleplay`, or the user's own ability is `cantsuppress`.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_ROLEPLAY_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user, target = n.user, n.target
      local userId, targetId = abilityIdOf(user), abilityIdOf(target)
      if not targetId or userId == targetId
          or FAIL_ROLEPLAY[targetId] or CANT_SUPPRESS[userId] then
        return fail(n)
      end
      local changed = setAbility(n.battle, user, targetId)
      if changed == false then return fail(n) end
      return finish(n, { Strings("%s copied\n%s's ability!",
        displayNameFor(n.battle, user, n.gen2), displayNameFor(n.battle, target, n.gen2)) })
    end,
  })

  ------------------------------------------------------------------
  -- Simple Beam -- the TARGET's ability becomes Simple. Real refusals
  -- (moves.ts:16483-16505): target `cantsuppress`, already Simple, or Truant.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_SIMPLEBEAM_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local target = n.target
      local targetId = abilityIdOf(target)
      if targetId == "SIMPLE" or targetId == "TRUANT" or CANT_SUPPRESS[targetId] then
        return fail(n)
      end
      local changed = setAbility(n.battle, target, "SIMPLE")
      if changed == false then return fail(n) end
      return finish(n, { Strings("%s's ability\nbecame Simple!", displayNameFor(n.battle, target, n.gen2)) })
    end,
  })

  ------------------------------------------------------------------
  -- Doodle -- copies the TARGET's ability onto the USER's side of the
  -- field. In Showdown that is every pokemon of source.alliesAndSelf()
  -- (moves.ts:3826); with this engine's 1v1 reduction the only member is
  -- the user itself, so Doodle is "the user copies the target's ability"
  -- unless the ability could not be copied. Real refusals
  -- (moves.ts:3823-3845): the target's ability is `failroleplay`; and each
  -- recipient is skipped (not failed) if it already has that ability or
  -- its own ability is `cantsuppress`. The move fails when nothing changed.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_DOODLE_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user, target = n.user, n.target
      local targetId = abilityIdOf(target)
      if not targetId or FAIL_ROLEPLAY[targetId] then return fail(n) end
      local changed = false
      for _, mon in ipairs({ user }) do
        if abilityIdOf(mon) ~= targetId and not CANT_SUPPRESS[abilityIdOf(mon)] then
          local r = setAbility(n.battle, mon, targetId)
          if r ~= false then changed = true end
        end
      end
      if not changed then return fail(n) end
      return finish(n, { Strings("%s copied\n%s's ability!",
        displayNameFor(n.battle, user, n.gen2), displayNameFor(n.battle, target, n.gen2)) })
    end,
  })

  mod.log:info("g9-battle-engine: modern_ability_change_moves installed "
    .. "(SKILLSWAP, WORRYSEED, ENTRAINMENT, GASTROACID, ROLEPLAY, SIMPLEBEAM, DOODLE)")
end
