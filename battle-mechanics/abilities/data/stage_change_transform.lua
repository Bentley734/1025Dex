-- Inclusion list only. CONTRARY (inverts all of this mon's own stat
-- stage changes, any source) and SIMPLE (doubles their magnitude) --
-- confirmed unconditional, apply to every stat, real Gen 5+ mechanic.
-- The main effect lives directly inside combat/modern_combat.lua's own
-- changeStage (a core-primitive edit, not a wrap -- see that function's
-- own comment for why); this file only covers speed/accuracy/evasion,
-- which route through Gen 2's native Battle:changeStageAgainstMist
-- instead (switchin_stat_change.lua's own NATIVE_STATS branch, and
-- combat/modern_movepool_stages.lua's changeNativeStage).
return { CONTRARY = true, SIMPLE = true }
