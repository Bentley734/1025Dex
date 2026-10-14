-- Inclusion list -- Phase 14 (ability audit close-out). The form /
-- transformation family. These eight abilities exist in national_dex
-- and ARE correctly referenced by the engine's ability_dispatch
-- (so they are NOT "missing"), but their actual mechanic is a
-- battle-time transformation, which the battle_forms plugin owns
-- (the mod's base battle is single-species-form with no Mega/Dynamax/
-- Zen/Mode framework of its own). So there is no GENERIC combat hook
-- to wire for them here.
--
-- This file exists so the audit's "every ability in national_dex is
-- accounted for" invariant has a home for them, and each entry notes
-- the real mechanic in prose:
--   STANCECHANGE  -- Aegislash alternates Shield/Blade form (attacking
--                  move -> Blade, King's Shield -> Shield).
--   SCHOOLING     -- Wishiwashi becomes School Form at Lv20+.
--   ZENMODE       -- Darmanitan changes to Zen Mode when HP <= half.
--   POWERCONSTRUCT -- Zygarde becomes Complete Forme when HP <= half.
--   TERASHIFT     -- Terapagos enters Stellar Form when HP <= half.
--   ILLUSION      -- Zorua disguises itself as the last party member
--                  (wild: as a species from the map's spawn table).
--   IMPOSTER      -- Ditto transforms into the opposing Pokémon.
--   ZEROTOHERO    -- Palafin changes to Hero Form on switch-out.
--
-- CORRECTION (round 179, 2026-09-17): the earlier claim that "battle_forms
-- owns all of these transformations" was WRONG for ILLUSION and IMPOSTER --
-- battle_forms implements neither (grep: no ILLUSION/IMPOSTER handler in it),
-- and nothing else in this project did either. Both are now really wired, by
-- combat/modern_transform.lua (switch-in disguise for Illusion, switch-in
-- transformInto for Imposter), so they are no longer "declared but absent".
-- Their entries stay in this list because the table is an audit marker set
-- (which family each id belongs to), not a claim about who implements it.
-- The remaining six are still battle_forms' (form-changing) scope.
return {
  STANCECHANGE = { transform = true },
  SCHOOLING = { transform = true },
  ZENMODE = { transform = true },
  POWERCONSTRUCT = { transform = true },
  TERASHIFT = { transform = true },
  ILLUSION = { transform = true, wiredBy = "combat/modern_transform.lua" },
  IMPOSTER = { transform = true, wiredBy = "combat/modern_transform.lua" },
  ZEROTOHERO = { transform = true },
}
