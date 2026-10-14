-- Inclusion list only -- blocked move type and the reaction (heal
-- fraction or stat-change stages) are both read LIVE from national_dex's
-- own abilityBehaviorOf at hit time, matching every other abilities/
-- data/*.lua file in this mod. Real, confirmed type_immunity abilities
-- (2026-08-27 audit): DRYSKIN(water), SAPSIPPER(grass), WATERABSORB
-- (water), VOLTABSORB(electric), WELLBAKEDBODY(fire).
--
-- DRY SKIN's own two other real effects (damage_self 1/8 max HP each
-- turn in strong sunlight, heal 1/8 max HP each turn in rain) are NOT
-- this file's job -- CLOSED elsewhere, not a gap: `abilities/engine/
-- heal.lua`'s own real per-turn weather-tick primitive (Phase 6) wires
-- both, alongside Ice Body/Rain Dish. This file's own comment used to
-- say that primitive didn't exist yet -- stale, written before Phase 6
-- landed. Only Dry Skin's own water-immunity + on-hit heal (the
-- type_immunity-kind effect and its paired "hit by a Water-type move"
-- heal) are wired here, correctly.
--
-- LEVITATE (Phase 8, `other` bucket, added 2026-08-28): its own real
-- national_dex record already carries a genuine `{kind="type_immunity",
-- moveType="ground"}` entry, confirmed by direct dump -- this generic
-- engine handles it automatically, no code change needed beyond adding
-- the id here. Its own OTHER real clause ("immune to Spikes, Toxic
-- Spikes, and Arena Trap") is a separate `other`-kind effect, already
-- closed elsewhere: the hazard-grounding fix (`combat/modern_hazards
-- .lua`) and Arena Trap's own exemption (`abilities/engine/
-- trap_abilities.lua`) both already check for a LEVITATE holder by id.
-- Real, honestly-flagged remaining gap (national_dex's own notes,
-- verbatim): "Immunity is suspended during Gravity or Ingrain, or while
-- holding an Iron Ball" -- Ingrain IS built in this mod now, but this
-- suspension interaction isn't modeled (Gravity/Iron Ball don't exist
-- here at all either) -- a narrow, secondary rule, not required for the
-- core immunity to be correct.
return {
  DRYSKIN = true, SAPSIPPER = true, WATERABSORB = true, VOLTABSORB = true,
  WELLBAKEDBODY = true, LEVITATE = true, EARTHEATER = true,
}
