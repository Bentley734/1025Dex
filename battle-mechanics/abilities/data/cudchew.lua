-- Inclusion list -- Phase 14 (ability audit close-out). Cud Chew:
-- after eating a held Berry, the Pokémon regurgitates it at the end of
-- the NEXT turn and gains its effect a second time.
--   CUDCHEW = true
-- Real mechanic (national_dex record: the holder "regurgitates its
-- Berry and eats it again at the end of the following turn"; Showdown:
-- the second heal happens one full turn after the first, damage gate
-- (below half max HP) and all). This file is pure inclusion; all the
-- timing/heal logic lives in abilities/engine/cudchew.lua, which
-- observes the native held_item "residual" trigger and the native
-- turn_ended event (which, in base-gen2-Battle.lua's closeTurn, fires
-- AFTER the residual sweep -- so the recorded first eat at turn N is
-- followed one turn later, at turn N+1's closeTurn, by the second eat).
return {
  CUDCHEW = true,
}
