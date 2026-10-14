-- Inclusion list only -- status/scope/chance are all read LIVE from
-- national_dex's own abilityBehaviorOf at dispatch time, matching every
-- other abilities/data/*.lua file in this mod. Real, confirmed
-- status_immunity abilities (2026-08-27 audit of all 313 abilities'
-- expressible=true behaviour, national_dex's own data):
--   INNERFOCUS(flinch), MAGMAARMOR(freeze), LIMBER(paralysis),
--   OWNTEMPO(confusion), PURIFYINGSALT(any), SWEETVEIL(sleep),
--   VITALSPIRIT(sleep), THERMALEXCHANGE(burn), WATERVEIL(burn),
--   WATERBUBBLE(burn).
-- SWEETVEIL's own record carries scope="allies", but real Sweet Veil
-- protects the HOLDER too, not just its allies (the same discrepancy
-- the Aroma Veil/Flower Veil/Pastel Veil family shares against this
-- dataset's own scope label -- confirmed against national_dex's own
-- prose effect text, "Prevents friendly Pokémon from sleeping," which
-- doesn't exclude self) -- abilities/engine/status_immunity.lua's own
-- check always includes self regardless of scope for this reason.
-- PURIFYINGSALT and WATERBUBBLE each also carry a damage_taken_
-- multiplier effect, already wired in Phase 2
-- (abilities/engine/damage_multiplier.lua) -- this file only adds their
-- status_immunity half; nothing here duplicates that work.
--
-- COMATOSE (Phase 8, other bucket, added 2026-08-28): its own real
-- national_dex record already carries a genuine
-- {kind="status_immunity", status="any"} entry, confirmed by direct
-- dump -- the same "any" value blockedStatusOf below already handles
-- generically (Purifying Salt's own real shape), so this needed only
-- the id added here, no new code. Its own SEPARATE real effect
-- ("always treated as asleep -- can use Sleep Talk, unaffected by
-- Yawn -- without actually losing turns") is a genuine `other`-kind
-- clause this file doesn't cover -- honestly deferred: nothing in this
-- mod currently lets a non-asleep mon use a Sleep-Talk-only move, and
-- Comatose's own real dex list (Komala-only, a single-species gimmick)
-- makes that a very narrow return for the work.
-- SHIELDSDOWN (Phase 8, other bucket, added 2026-08-28): real, HP-
-- gated (>=50%) immunity to every major status -- see this file's own
-- engine header for why this one is hardcoded rather than read from a
-- structured effect entry (national_dex's own record has none).
-- Phase 14 (ability audit close-out) additions:
--   PASTELVEIL: blocks poison for itself AND its allies (real record
--     scope "allies" but real text protects the bearer too -- same
--     self+allies reading as Sweet Veil), and cures poison from
--     allies when it enters the battlefield (the cure is wired in the
--     engine on battle.started/battler_switched).
--   LEAFGUARD: blocks all major statuses, but ONLY during strong
--     sunlight (real record carries six status_immunity entries with a
--     sun condition no structured field expresses) -- handled as a
--     hardcoded sun-gated "all major statuses" in the engine.
return {
  INNERFOCUS = true, MAGMAARMOR = true, LIMBER = true, OWNTEMPO = true,
  PURIFYINGSALT = true, SWEETVEIL = true, VITALSPIRIT = true,
  THERMALEXCHANGE = true, WATERVEIL = true, WATERBUBBLE = true, COMATOSE = true,
  SHIELDSDOWN = true,
  PASTELVEIL = true, LEAFGUARD = true,
}
