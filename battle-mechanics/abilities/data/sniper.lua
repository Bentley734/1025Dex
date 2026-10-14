-- Documentation-only marker -- Phase 8 (`other` bucket). SNIPER is never
-- loadSibling'd; its real behavior (critical hits deal 3x damage instead
-- of the normal 1.5x) is wired directly into combat/modern_combat.lua's
-- own crit-multiplier block, right alongside the damage formula it
-- already owns, rather than as a separate dispatch engine for one
-- three-line change.
return { SNIPER = true }
