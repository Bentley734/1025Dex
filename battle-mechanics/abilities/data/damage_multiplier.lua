-- Inclusion list only, same convention as every other abilities/data/
-- *.lua file -- no mechanical value duplicated here. Every id below has
-- a real `damage_dealt_multiplier`/`damage_taken_multiplier` entry in
-- national_dex's own abilityById, read live by abilities/engine/
-- damage_multiplier.lua, never copied into this file.
--
-- Battery, Power Spot, Friend Guard, Steely Spirit (2026-08-28): this
-- header used to mark all four as blocked pending a future multi-
-- battler mod -- stale, that support has since landed
-- (requestAdjacency's own real .allies list). All four now genuinely
-- built, in this same engine file, right alongside the rest.
--
-- Explicitly NOT here, still deferred with a reason (not silently
-- dropped) -- see that engine file's own header for the full breakdown:
--   Aerilate, Pixilate, Galvanize, Refrigerate -- each needs a move-TYPE
--     override primitive this mod doesn't have yet (the existing
--     type_override_primitives.lua changes a MON's own type, not a
--     move's effective type for one hit) -- real, substantial design
--     work, not a live-data read. (FLASHFIRE was UN-DEFERRED 2026-09-07:
--     its immunity half is built in absorb.lua, and its charge-boost
--     half here -- the charge flag it sets is read by this file.)
--   Sheer Force's own secondary-suppression half -- BUILT (main.lua's
--     generic secondary listener nils the flinch/confuse/ailment/stat
--     pool for a Sheer Force attacker); its damage half IS built too
--     (this file, below). See the engine file's own
--     "sheer_force_damage_half" comment for the split.
--   Hustle's own accuracy half (0.8x on physical moves) -- its damage
--     half IS built; the accuracy half needs an accuracy-modifier chain
--     this mod doesn't have (Phase 6: accuracy_multiplier).
--
-- Phase 14 (ability audit close-out) additions:
--   FLUFFY: 0.5x taken from contact moves, 2x taken from Fire moves --
--     both factors are real structured entries, read live.
--   ANALYTIC: 1.3x when this Pokémon moves last in the turn (real
--     exclusion: Future Sight/Doom Desire never boost -- documented
--     engine-side as not modeled).
--   FLASHFIRE: 1.5x Fire damage after being hit by a Fire move (the
--     charge flag comes from abilities/engine/absorb.lua; cleared when
--     the holder leaves battle).
return {
  ADAPTABILITY = true, STEELWORKER = true, ROCKYPAYLOAD = true,
  TRANSISTOR = true, FIREMANE = true, DRAGONSMAW = true,
  BLAZE = true, OVERGROW = true, TORRENT = true, SWARM = true,
  TECHNICIAN = true, SANDFORCE = true, DARKAURA = true, FAIRYAURA = true, AURABREAK = true,
  WATERBUBBLE = true, RIVALRY = true,
  THICKFAT = true, PURIFYINGSALT = true, MULTISCALE = true, SHADOWSHIELD = true,
  NEUROFORCE = true, TINTEDLENS = true, FILTER = true, SOLIDROCK = true,
  PRISMARMOR = true,
  -- Move-flag abilities: real, live data now -- national_dex's own
  -- moveFlags(id) export (data/moves/generated/flags.lua, sourced
  -- directly from Showdown's own moves.json) confirmed real 2026-08-27.
  -- See this engine file's own header for the exact access pattern.
  IRONFIST = true, MEGALAUNCHER = true, STRONGJAW = true, SHARPNESS = true,
  TOUGHCLAWS = true, RECKLESS = true,
  -- Phase 14 additions:
  FLUFFY = true, ANALYTIC = true, FLASHFIRE = true,
  -- Re-scoped from deferred to buildable (2026-08-27): a category filter
  -- (ctx.category) was already available and unused; a one-shot charge
  -- state and switch-in tracking both reuse the same volatile-flag
  -- pattern this mod already established for flinch/confuse.
  FURCOAT = true, ICESCALES = true, HUSTLE = true,
  ELECTROMORPHOSIS = true, WINDPOWER = true, STAKEOUT = true,
  SHEERFORCE = true,
  -- Ally-scope, un-deferred 2026-08-28 -- see this file's own header.
  BATTERY = true, POWERSPOT = true, FRIENDGUARD = true, STEELYSPIRIT = true,
}
