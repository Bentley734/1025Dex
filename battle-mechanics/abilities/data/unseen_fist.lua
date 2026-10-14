-- Documentation-only marker -- Phase 8 (`other` bucket). UNSEENFIST is
-- never loadSibling'd; its real behavior (this Pokemon's own CONTACT
-- moves bypass an incoming Protect/Detect entirely, full damage) is
-- wired directly into combat/modern_combat_protect.lua's own existing
-- Part B "battle.damage" wrap, right alongside the file that already
-- owns every other real Protect-interaction rule, rather than a
-- separate dispatch engine reaching back into a file it doesn't own.
return { UNSEENFIST = true }
