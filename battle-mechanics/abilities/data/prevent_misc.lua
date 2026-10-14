-- Inclusion list only -- Phase 7 (`prevent` bucket), three real
-- abilities that share no common mechanism with each other or with any
-- other file in this phase, each documented at its own engine call site:
--   DAMP: Self-Destruct/Explosion fail outright, and Aftermath doesn't
--     trigger, while ANY Pokémon in the battle (either battler, not just
--     the holder's own opponent) has this ability.
--   GORILLATACTICS: the real choice-lock half (its atk x1.5 boost is
--     already built, Phase 4's stat_multiplier.lua) -- once the holder
--     has used a move, every future move selection is forced back to
--     that same move for the rest of the time it's on the field.
--   QUICKFEET: the real "no paralysis Speed cut" half (its x1.5 boost is
--     now built too, Phase 4's stat_multiplier.lua, un-deferred this same
--     pass now that this half closes the double-count risk that used to
--     block it).
--
-- Phase 14 (ability audit close-out) additions:
--   GUTS: the real burn-cut-negation half (the atk x1.5 boost is built,
--     Phase 4's stat_multiplier.lua) -- "This Pokémon is not affected by
--     the usual Attack cut from a burn", wired on the same
--     Battle.statusPenaltyFor choke point Quick Feet uses.
--   SUCTIONCUPS / GUARDDOG: immune to forced switch-outs (Roar /
--     Whirlwind) while on the field -- Guard Dog's Intimidate-immune +
--     +1 Attack half is wired in switchin_stat_change.lua, its forced-
--     switch immunity here (real text confirms Guard Dog blocks both
--     Intimidate and forced switching).
return {
  DAMP = true, GORILLATACTICS = true, QUICKFEET = true,
  GUTS = true, SUCTIONCUPS = true, GUARDDOG = true,
}
