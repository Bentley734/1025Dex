-- The curated set of switch_in abilities this generic engine safely
-- auto-derives via national_dex's own plain weather primitive (RAIN/SUN/
-- SAND/SNOW, no duration nuance, no move-blocking rule) -- Drizzle,
-- Drought, Snow Warning, and Orichalcum Pulse's weather half. This is
-- ONLY an inclusion list: the actual weather value is read LIVE from
-- national_dex's own abilityBehaviorOf at dispatch time (abilities/
-- engine/switchin_weather.lua's own header) -- nothing about the effect
-- itself is duplicated here.
--
-- ORICHALCUMPULSE carries a SECOND effect (a stat_multiplier Attack boost
-- while Sun is active). That half is wired SEPARATELY from this file --
-- abilities/data/stat_multiplier.lua (HADRONENGINE's twin entry; the real
-- Showdown factor is 4/3, overridden in that file's own engine) -- and, by
-- 2026-09-10, also applied inside combat/modern_combat.lua's modern damage
-- path. Only the weather-setting half is listed here.
--
-- Explicit user decision (Phase 1.5, not this phase): Desolate Land,
-- Primordial Sea, and Delta Stream -- each a stronger, irreplaceable
-- weather this plain primitive can't represent (no duration/move-blocking
-- rule) -- are deliberately NOT in this list yet.
--
-- Sand Spit is NOT here: its real trigger is on_hit_taken, not switch_in
-- -- a different phase (the on-hit-taken cluster), not guessed into this
-- one for a superficial kind match. (It IS wired -- in hit_taken.lua.)
--
-- Phase 14 close-out addition: SANDSTREAM (a Switch-In ability -- real
-- text "summons a sandstorm" -- handled by the same generic
-- switchin_weather engine; its record's scope field says "field" but
-- that engine's own dispatch applies the setter-holder's weather on
-- switch-in, which is exactly the real mechanic).
return {
  DRIZZLE = true,
  DROUGHT = true,
  SNOWWARNING = true,
  SANDSTREAM = true,
  ORICHALCUMPULSE = true,
}
