-- The curated set of switch_in abilities this generic engine safely
-- auto-derives via combat/modern_terrain.lua's own setTerrain primitive --
-- Electric/Grassy/Misty/Psychic Surge, plus Hadron Engine's terrain half.
-- This is ONLY an inclusion list: the actual terrain value is read LIVE
-- from national_dex's own abilityBehaviorOf at dispatch time (abilities/
-- engine/switchin_terrain.lua's own header) -- nothing about the effect
-- itself is duplicated here.
--
-- Hadron Engine's own second effect (a Sp. Atk stat_multiplier while
-- Electric Terrain is active) is wired SEPARATELY from this file --
-- abilities/data/stat_multiplier.lua's own HADRONENGINE entry (the real
-- Showdown factor is 4/3, overridden in that file's own engine) -- and, by
-- 2026-09-10, also applied inside combat/modern_combat.lua's modern damage
-- path. Only the terrain-setting half is listed here.
--
-- Seed Sower is NOT here: its real trigger is on_hit_taken, not switch_in
-- -- a different phase, same reasoning as weather_switchin.lua's own Sand
-- Spit exclusion.
return {
  ELECTRICSURGE = true,
  GRASSYSURGE = true,
  MISTYSURGE = true,
  PSYCHICSURGE = true,
  HADRONENGINE = true,
}
