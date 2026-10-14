-- Inclusion list -- Phase 14 (ability audit close-out), the absorb
-- family: four abilities that (a) nullify an incoming move of a given
-- type outright and (b) fire a one-stage stat rise (or, for Flash Fire,
-- a lasting Fire-boost charge) instead. Real, confirmed mechanics from
-- national_dex's own records (each quoted in abilities/engine/
-- absorb.lua's own header) and Showdown:
--   FLASHFIRE    -- immune to Fire; after being hit by a Fire move, own
--                  Fire moves deal 1.5x until it leaves battle.
--   MOTORDRIVE   -- immune to Electric; +1 Speed when hit by Electric.
--   LIGHTNINGROD -- immune to Electric; +1 Sp. Atk when hit by Electric
--                  (a Ground-type holder immune to Electric gets the
--                  block but NO boost -- real Showdown ruling).
--   STORMDRAIN   -- immune to Water; +1 Sp. Atk when hit by Water.
--
-- The move type each absorbs is HARDCODED here rather than read live:
-- national_dex's own records carry a real `type_immunity` kind entry
-- only for FLASHFIRE (moveType="fire") -- the other three carry a plain
-- `stat_change` (with the type mentioned only in prose/notes) or a
-- `prevent`-shaped entry (Storm Drain's redirect half), nothing this
-- file's own live-read convention could key on generically. The type
-- list is small, fixed, and confirmed against both the dex text and
-- Showdown for all four, so it is written out explicitly rather than
-- guessed -- the same documented-exception discipline this mod already
-- applies to Earth Eater's un-structured heal fraction.
return {
  FLASHFIRE = "FIRE",
  MOTORDRIVE = "ELECTRIC",
  LIGHTNINGROD = "ELECTRIC",
  STORMDRAIN = "WATER",
}
