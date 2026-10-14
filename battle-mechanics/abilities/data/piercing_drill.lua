-- Documentation-only marker -- Phase 8 (`other` bucket). PIERCINGDRILL
-- is never loadSibling'd; its real behavior (this Pokemon's own CONTACT
-- moves bypass an incoming Protect/Detect for 1/4 damage, national_dex's
-- own confirmed real fraction) is wired directly into combat/
-- modern_combat_protect.lua's own existing Part B "battle.damage" wrap,
-- alongside Unseen Fist -- both real attacker-side Protect bypasses,
-- one file already owns every other Protect-interaction rule.
return { PIERCINGDRILL = true }
