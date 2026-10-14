-- Inclusion list only -- Phase 8 (`other` bucket), the real "changes an
-- ability via a genuine trigger" family, now buildable now that
-- abilities/ability_dispatch.lua's own mod.exports.setAbility exists.
-- Real triggers, one shared primitive:
--   TRACE (switch_in): copies the current opponent's ability onto
--     itself. Real, confirmed exclusion list (national_dex's own notes):
--     Flower Gift, Forecast, Illusion, Imposter, Multitype, Trace itself,
--     Wonder Guard, Zen Mode -- Illusion/Imposter/Zen Mode aren't built
--     anywhere in this ability system at all (moot here), the other five
--     are real, reachable ids in this mod today.
--   MUMMY (on_contact_taken): changes the ATTACKING Pokémon's ability to
--     Mummy. Real, confirmed exclusion: does not affect Multitype.
--   LINGERINGAROMA (on_contact_taken): same real mechanic as Mummy,
--     different flavor id -- built alongside it, same exclusion.
--   WANDERINGSPIRIT (on_contact_taken): swaps abilities both ways with
--     whatever Pokémon just hit it with a contact move.
--   RECEIVER / POWEROFALCHEMY (on ally faint): copies the fainted ally's
--     own ability onto itself. UPDATE (2026-08-28): this file used to
--     mark both as permanent structural no-ops ("no ally slot exists in
--     this engine's 1v1-only format") -- stale the moment this session's
--     own earlier multi-battler work landed real ally adjacency
--     (requestAdjacency's own .allies list, g9-Battle-Scene's real
--     doubles/triples/boss-fight layouts). Built for real now, on the
--     real battle.fainted event.
return {
  TRACE = true, MUMMY = true, LINGERINGAROMA = true, WANDERINGSPIRIT = true,
  RECEIVER = true, POWEROFALCHEMY = true,
}
