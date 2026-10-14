-- Protean and Libero -- identical real mechanic (national_dex's own
-- Libero record: "identical mechanic to Protean"), both trigger=
-- "on_move_used", scope="self": the bearer's own type is set to match the
-- move it is about to use, immediately before that move executes, once
-- per switch-in. No per-ability parameters needed -- both are handled by
-- exactly the same logic in abilities/engine/onmove_type_change.lua, so
-- this table is really a SET (id -> true), not a spec table.
--
-- Multitype/Forecast/Mimicry are deliberately NOT here -- explicit user
-- decision, Phase 1.8: they're continuously re-derived from live field/
-- item state rather than fired once on a discrete event, a structurally
-- different pattern this phase's engine doesn't handle.
return {
  PROTEAN = true,
  LIBERO = true,
}
