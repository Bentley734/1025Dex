-- Documentation-only marker -- Phase 8 (`other` bucket). SCRAPPY (and,
-- alongside it, MIND'S EYE's own identical Ghost-hit half) is never
-- loadSibling'd; its real behavior (Normal/Fighting moves hit a Ghost-
-- type target normally) is wired directly into combat/
-- modern_status_volatiles.lua's own existing type_immunity_negation
-- registerPostEffectivenessModifier -- the same real primitive Foresight/
-- Miracle Eye/Smack Down already use for their own immunity-negation
-- effects -- rather than a new dispatch engine for a two-line addition.
return { SCRAPPY = true }
