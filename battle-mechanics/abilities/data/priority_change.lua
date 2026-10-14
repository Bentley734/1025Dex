-- Inclusion list only -- the amount is read LIVE from national_dex's own
-- abilityBehaviorOf; only WHICH MOVES qualify is a small hardcoded
-- condition (see abilities/engine/priority_change.lua's own header for
-- why: none of the three records' own `when`/filter fields actually
-- narrow the move set, confirmed against each one's own free-text
-- `notes` field). Real, confirmed priority_change abilities (2026-08-27
-- audit, 3 total across the whole roster):
--   PRANKSTER (+1, non-damaging/status moves only),
--   TRIAGE (+3, healing moves only),
--   GALEWINGS (+1, Flying-type moves only -- expressible=false in
--     national_dex's own data, since its schema has no move-type filter
--     field at all; its own notes confirm the real condition regardless).
return {
  PRANKSTER = true, TRIAGE = true, GALEWINGS = true,
}
