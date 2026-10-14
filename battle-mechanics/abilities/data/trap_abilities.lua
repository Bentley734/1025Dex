-- Inclusion list only -- Phase 7 (`prevent` bucket), the real
-- switch/flee-lock family: Arena Trap, Shadow Tag, Magnet Pull all
-- prevent the OPPONENT from switching out or fleeing while the holder is
-- active; Run Away is the real, confirmed exemption every one of the
-- other three carries against a holder that has it. Real, current-
-- Showdown exemptions (not modeled at all in national_dex's own data --
-- each one's own `notes` field says so explicitly):
--   ARENATRAP: does not trap a Flying-type target or one made airborne
--     by Levitate (Magnet Rise/Telekinesis are a separate, temporary kind
--     of airborne this engine tracks per-mon rather than per-ability --
--     not checked here, an honest, narrower gap than "unbuilt").
--   SHADOWTAG: does not trap a Ghost-type target, and (real, current-
--     Showdown rule, added Gen 4) does not trap another Shadow Tag
--     holder.
--   MAGNETPULL: the inverse shape of the other two -- traps ONLY a
--     Steel-type target, not "everything except an exemption list."
-- All three are real, confirmed via each one's own `effect` prose text.
return {
  ARENATRAP = true, SHADOWTAG = true, MAGNETPULL = true, RUNAWAY = true,
}
