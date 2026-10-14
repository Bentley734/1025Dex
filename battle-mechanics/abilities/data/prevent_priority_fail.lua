-- Inclusion list only -- Phase 7 (`prevent` bucket), the real
-- opposing-priority-move-fail family: Dazzling, Queenly Majesty, Armor
-- Tail all carry the identical mechanic (confirmed via each one's own
-- national_dex `what` text -- Armor Tail's own record is literally
-- Dazzling/Queenly Majesty's text with "the mysterious tail" flavor
-- swapped in): any opposing Pokémon's priority move (priority > 0,
-- checked via combat/turn_order.lua's own registered priority chain, the
-- same one Prankster/Triage/Gale Wings already feed) that targets this
-- Pokémon fails outright. Real, confirmed exclusion (Showdown's own
-- source, `sim/battle-actions.ts`, the same file this mod's own Prankster/
-- Dark-type check was verified against): this only blocks a move that
-- SELECTS this Pokémon as its target -- a side/field move (Stealth Rock,
-- Tailwind) never reaches the check in the first place, same reasoning
-- already documented for Prankster's own Dark-type immunity.
return {
  DAZZLING = true, QUEENLYMAJESTY = true, ARMORTAIL = true,
}
