-- Inclusion list -- Phase 14 (ability audit close-out). Move-redirect
-- immunity: both abilities make the holder immune to the effects of
-- moves that redirect attacks toward it.
--   STALWART     -- unaffected by moves that redirect (follow-me-style).
--   PROPELLERTAIL -- makes the holder's own moves bypass redirection,
--                  always hitting their chosen target.
-- Real mechanics confirmed (national_dex's own records + Showdown).
-- NOTE: the base engine has NO move-redirection mechanic at all (no
-- Follow Me / Rage Powder / Spotlight / Ally Switch implemented), so
-- there is nothing to be immune to. The absorb family's four abilities
-- (see absorb.lua) only ever BLOCK their own type's move for their own
-- holder -- they never redirect. Hence these two are inclusion-only:
-- the entries document that IF redirection is ever added, Stalwart and
-- Propeller Tail must be exempted from it.
return {
  STALWART = { immuneToRedirect = true },
  PROPELLERTAIL = { bypassesRedirect = true },
}
