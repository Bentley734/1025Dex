-- Phase 0 of the missing-effects pipeline: the structural-exemption registry.
--
-- PURPOSE. This mod's audit (combat/NATIVE_COVERAGE.md) classifies every
-- non-native move national_dex registers three ways: natively modelled,
-- handled (referenced by id somewhere in this codebase, or by one of
-- main.lua's generic field-driven listeners), or a genuine residual gap.
-- A fourth, small set exists: moves whose real Showdown mechanic is
-- IMPOSSIBLE TO OBSERVE in a single battle -- it needs a second active
-- battler on the user's side (an ally), which a 1-vs-1 fight never has, or
-- it exists only to interact with a mechanic the base engine does not have
-- at all. Those are not "unbuilt"; there is nothing to build. This file
-- names them explicitly, by id and by reason, so a future audit (or a
-- future agent) does not re-flag them as gaps every session, and so the
-- single-battler-functional moves that superficially resemble them
-- (Gear Up / Howl / Magnetic Flux -- see the non-exemptions note at the
-- bottom) are not swept in by mistake.
--
-- SOURCE OF TRUTH. Pokemon Showdown, scratch/showdown/moves.ts, cited per
-- entry by block line. national_dex's own target field is quoted too, but
-- it is PokeAPI's coarse target label and is LESS precise than the
-- Showdown handler -- e.g. Follow Me / Rage Powder / Ally Switch all carry
-- PokeAPI target "user" while their real Showdown `onTry`/`onHit` gates on
-- `this.activePerHalf` / `this.gameType`, which is the actual singles-vs-
-- doubles condition. The Showdown handler is what each reason below rests
-- on; the PokeAPI label is corroboration only.
--
-- WHY AN ALLY IS REQUIRED FOR EACH ONE (direct reads of the blocks):
--   allyswitch (moves.ts:302-330). onHit: `if (this.gameType !== 'doubles'
--     && this.gameType !== 'triples') success = false;` then it looks up the
--     mon in the swapped position (`pokemon.side.active[newPosition]`) and
--     fails if that slot is empty or fainted. Singles => gameType 'singles'
--     => unconditional fail. Nothing else in the block runs.
--   followme (moves.ts:6040+). `onTry(source) { return this.activePerHalf
--     > 1; }` -- i.e. it refuses to execute unless the user's half of the
--     field holds more than one battler. Singles => activePerHalf 1 =>
--     fail. Its 'followme' volatile exists only to redirect opponents'
--     single-target moves toward the user, and with no ally the user is
--     already the only target, so even a forced success would be a no-op.
--   helpinghand (moves.ts:8574+). target "ally" (PokeAPI: HELPINGHAND.target
--     = "ally"); it puts the 'helpinghand' volatile on the target so THAT
--     mon's next move is powered up. With no allied battler there is no
--     legal target. (It is not self-targetable: Showdown's `target: 'ally'`
--     never resolves to the user.)
--   ragepowder (moves.ts:14599+). Identical `onTry(source) { return
--     this.activePerHalf > 1; }` gate to Follow Me, and the same
--     no-ally-means-nothing-to-redirect argument.
--   spotlight (moves.ts:17764+). `onTryHit(target) { if (this.activePerHalf
--     === 1) return false; }` -- explicitly refuses in singles. Its
--     'spotlight' volatile makes a target the centre of opponents'
--     attention; with no other battler on the user's side there is no
--     attention to draw and no second target to be centred.
--
-- RETIRED (4.6.7): DRAGONCHEER used to sit in this registry (all-allies
-- excludes the user, so a singles battle has an empty target set). Now that a
-- scene-driven battle really does have adjacent allies, it is fully reachable
-- and is implemented instead: combat/modern_crit_override.lua's
-- GALAR_DRAGONCHEER_EFFECT puts the switch-scoped 'dragoncheer' crit volatile
-- on the user's adjacent allies (and status_condition_cleanup.lua drops it on
-- switch-out), so it is removed from this registry.
--
-- WHY THESE ARE DISJOINT FROM THE REST OF THE CODEBASE. Every id here is
-- absent from this mod's move-patch log and from every id-referenced
-- handler (verified by the harness's round81 check, which fails if any
-- exempt id appears in the JS-side movePatches recorder). That is the
-- whole point: an exemption registry that overlapped a real implementation
-- would be a contradiction, so the check is enforced, not assumed.
--
-- THE NON-EXEMPTIONS (deliberately NOT in this registry). These carry an
-- "allies" target label too, but include the USER, so in singles they are
-- ordinary self-boosts and MUST be wired as such -- they live in the
-- residual phase for self stat-stage moves, not here:
--   HOWL        (PokeAPI target "user-and-allies"; Showdown boosts the
--                user's side, allies INCLUDING the user -- Atk +1).
--   GEARUP      (target "user-and-allies"; Atk +1 / SpA +1 to the user's
--                side, user included).
--   MAGNETICFLUX (target "user-and-allies"; Def +1 / SpD +1 to the user's
--                side, user included).
-- The doubles-only GUARD family (WIDEGUARD / QUICKGUARD / CRAFTYSHIELD /
-- MATBLOCK / SAFEGUARD) is likewise NOT exempt: each protects the user's
-- OWN side, and the user IS that side in singles, so they function fully
-- and are wired in their own side-condition phase.
--
-- USAGE. `mod.exports.isStructurallyExempt(moveId)` -> boolean;
-- `mod.exports.structuralExemptions` -> { [ID] = reason-string }.
return function(mod)
  assert(mod and mod.exports, "structural_exemptions: mod table required")

  local registry = {
    ALLYSWITCH = "Ally Switch needs a second allied battler to swap with; "
      .. "Showdown's onHit fails outright unless gameType is doubles/triples "
      .. "(moves.ts:302-330).",
    FOLLOWME = "Follow Me refuses to execute unless activePerHalf > 1 "
      .. "(moves.ts:6040+); with no ally there is also nothing to redirect.",
    HELPINGHAND = "Helping Hand targets an ally (never the user); with no "
      .. "allied battler there is no legal target (moves.ts:8574+).",
    RAGEPOWDER = "Rage Powder has the same activePerHalf > 1 gate as Follow Me "
      .. "(moves.ts:14599+) and nothing to redirect in singles.",
    SPOTLIGHT = "Spotlight explicitly fails when activePerHalf == 1 "
      .. "(moves.ts:17764+); no ally means no attention to draw.",
  }

  mod.exports.structuralExemptions = registry
  mod.exports.isStructurallyExempt = function(moveId)
    if type(moveId) ~= "string" then return false end
    return registry[moveId] ~= nil
  end

  return registry
end
