-- Inclusion list only -- Phase 8 (`other` bucket), the move-type-
-- override family. Real, confirmed conversions (national_dex's own
-- notes, each verified against Showdown source before writing anything
-- here): AERILATE (Normal -> Flying), PIXILATE (Normal -> Fairy),
-- REFRIGERATE (Normal -> Ice), GALVANIZE (Normal -> Electric),
-- DRAGONIZE (Normal -> Dragon) -- all five ALSO give the move a real
-- 1.2x power boost on top of the type change; NORMALIZE (converts
-- EVERY move, any type, to Normal) does NOT carry a power boost in
-- current Showdown.
-- Phase 14 close-out addition: LIQUIDVOICE = "WATER" -- converts only
-- SOUND-BASED moves to Water (real text: "When this Pokémon uses a move
-- that is sound-based, that move's type is Water"); the sound gate lives
-- in the engine (national_dex's own moveFlags sound flag), and like
-- Normalize it carries NO 1.2x power boost.
--
-- Built as a single, generic "battle.damage" wrap at a HIGH priority
-- (above every other real wrap on this same hook -- Protect's 50,
-- type_immunity's 40, contact_retaliation's 45 -- so the type change is
-- already in effect by the time any of THOSE run) rather than a per-
-- ability move-type override primitive: this mod's own
-- type_override_primitives.lua (Protean/Libero/Color Change/Soak/etc.)
-- is a DIFFERENT real mechanic entirely -- it mutates the MON's own
-- persistent types, this needs the MOVE's own effective type changed
-- for exactly ONE hit, never touching mon.types at all. Real, confirmed
-- choke point: ctx.move IS the shared, persistent move-definition
-- object every damage-formula read (STAB, weather Fire/Water bonus,
-- type-effectiveness, every ability's own type_immunity check) already
-- goes through via the SAME ctx.move.type field -- temporarily
-- mutating .type on it and restoring immediately after (even on error,
-- via pcall) is the same established "swap and restore" idiom combat/
-- modern_combat_protect.lua's own header already uses for
-- Battle.moveEffectRecordFor, not a new pattern invented here.
-- Real engine type-id convention (confirmed, main.lua's own
-- TYPE_ID_TRANSLATION): only PSYCHIC gets remapped to "PSYCHIC_TYPE"
-- (a real Lua/engine collision-avoidance quirk this project's own code
-- already documents) -- every other type, Dragon included, is its own
-- plain uppercase name with no special-casing.
return {
  AERILATE = "FLYING", PIXILATE = "FAIRY", REFRIGERATE = "ICE",
  GALVANIZE = "ELECTRIC", DRAGONIZE = "DRAGON", NORMALIZE = "NORMAL",
  LIQUIDVOICE = "WATER",
}
