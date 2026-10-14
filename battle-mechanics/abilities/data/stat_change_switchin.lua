-- The curated set of switch_in + kind="stat_change" abilities this generic
-- engine safely auto-derives -- Intimidate, Intrepid Sword, Dauntless
-- Shield, Supersweet Syrup. This is ONLY an inclusion list: the actual
-- scope/stat/stages come straight from national_dex's own live
-- abilityBehaviorOf at dispatch time (abilities/engine/
-- switchin_stat_change.lua's own header explains why nothing about the
-- effect itself is duplicated here) -- if that data ever changes upstream,
-- this engine tracks it automatically instead of silently drifting out of
-- sync with a hand-copied value.
--
-- Excluded, not guessed into this generic shape: every stat_change ability
-- with more than one stat_change effect at once (Anger Shell: 5 changes),
-- a trigger other than switch_in, or a dynamically-chosen stat (Download/
-- Moody carry kind="other" in national_dex's own data for exactly this
-- reason -- not even reachable here).
return {
  INTIMIDATE = true,
  INTREPIDSWORD = true,
  DAUNTLESSSHIELD = true,
  SUPERSWEETSYRUP = true,
}
