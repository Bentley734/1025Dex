-- Inclusion list only -- Phase 7 (`prevent` bucket). Real, confirmed
-- effect: protects the holder AND its allies from moves/effects that
-- affect mental state -- Attract, Disable, Encore, Heal Block (Psychic
-- Noise counts too, real current-Showdown ruling: same category), Taunt,
-- Torment. All six are real, built mechanics in this engine already
-- (combat/modern_status_effects.lua's Attract/Taunt/Torment/Encore,
-- combat/modern_status_volatiles.lua's Disable/Heal Block/Psychic
-- Noise) -- this file only gates them, doesn't rebuild any of them.
return { AROMAVEIL = true }
