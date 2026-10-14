-- Inclusion list only -- fractions are read LIVE from national_dex's own
-- abilityBehaviorOf; only WHICH TRIGGER SHAPE each belongs to is
-- hardcoded (see abilities/engine/heal.lua's own header). Real, confirmed
-- heal-kind abilities (2026-08-27 audit, 9 total across the whole
-- roster):
--   DRYSKIN (turn-end: damage_self 1/8 max HP in sun, heal 1/8 max HP in
--     rain -- its own water-hit heal + type_immunity half is ALREADY
--     built, Phase 3's abilities/engine/type_immunity.lua),
--   ICEBODY (turn-end: heal 1/16 max HP in snow),
--   RAINDISH (turn-end: heal 1/16 max HP in rain),
--   POISONHEAL (heal 1/8 max HP each turn while poisoned, REPLACING the
--     normal poison residual damage entirely, not stacking with it),
--   HOSPITALITY (switch-in: heals every ADJACENT ALLY, not self, by 1/4
--     of the ally's own max HP -- a genuine no-op in today's 2-battler
--     engine, same "built now, ready when a real ally slot exists"
--     status as Intimidate's own foes-scope adjacency work),
--   REGENERATOR (switch-out: heals the mon that just left by 1/3 its own
--     max HP, unless it fainted).
-- WATERABSORB and VOLTABSORB are NOT in this file -- both are real
-- heal-kind abilities too, but their own heal (on being hit by their
-- blocked type) is already fully built as part of Phase 3's
-- type_immunity.lua, and duplicating them here would double-heal.
return {
  DRYSKIN = true, ICEBODY = true, RAINDISH = true, POISONHEAL = true,
  HOSPITALITY = true, REGENERATOR = true,
}
