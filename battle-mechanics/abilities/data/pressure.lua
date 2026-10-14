-- Inclusion list only -- Phase 8 (`other` bucket). Real, confirmed
-- mechanic (national_dex's own notes): moves targeting the Pressure
-- holder use 1 EXTRA PP, applied even to a miss/fail, but NOT to the
-- user's own self-targeted moves or to a side/field-only move. Checked
-- via a real, generic move-target archetype set
-- ("selected-pokemon"/"all-opponents"/"opponents-field"/
-- "all-other-pokemon"), the same real field this mod already keys
-- targeting decisions off elsewhere (combat/move_targeting.lua,
-- Prankster's own Dark-immunity scoping).
return { PRESSURE = true }
