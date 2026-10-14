-- Inclusion list -- Phase 14 (ability audit close-out). Overworld-only
-- abilities: no battle effect at all in national_dex's own records
-- (each says so explicitly), and Showdown likewise has no battle logic
-- for them. They exist so the audit invariant "every ability in
-- national_dex is accounted for" has a home, and to document that the
-- battle engine deliberately does nothing for them:
--   ILLUMINATE -- no battle effect (note: national_dex's record here
--                carries a `stat_change` to the OPPONENT's accuracy
--                on switch-in -- but Showdown rejects that reading
--                (Illumise is a Firefly, not a flashlight; the dex
--                text is wrong and was later fixed). Showdown is the
--                source of truth for LOGIC, so this mod wires it as
--                accuracy-drop-immunity for its holder instead, in
--                statDropBlockedByAbility (SINGLE_STAT_IMMUNE).
--                Gen 3's actual "can't miss in a cave" effect is an
--                overworld/cave mechanic, out of battle scope.)
--   BALLFETCH   -- catches a lost Poké Ball after a failed catch
--                (overworld only; no battle effect).
--   HONEYGATHER -- a random chance to find Honey after battle
--                (overworld only; no battle effect).
return {
  ILLUMINATE = { noBattleEffect = true },
  BALLFETCH = { noBattleEffect = true },
  HONEYGATHER = { noBattleEffect = true },
}
