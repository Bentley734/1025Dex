-- Inclusion list only -- amounts are read LIVE from national_dex's own
-- abilityBehaviorOf; only Merciless's own condition (target poisoned) is
-- hardcoded, since crit_change has no condition field at all (confirmed
-- via its own notes: "Guaranteed critical hits only apply when the
-- target is poisoned or badly poisoned; crit_change has no condition
-- field to restrict this"). Real, confirmed crit_change abilities
-- (2026-08-27 audit, 2 total): SUPERLUCK (+1 crit stage, unconditional),
-- MERCILESS (guaranteed crit against a poisoned target -- built as a
-- +3 stage delta, since combat/modern_combat.lua's own CRIT_STAGE_DENOM
-- table already treats stage 3+ as a guaranteed hit, denom=1).
return {
  SUPERLUCK = true, MERCILESS = true,
}
