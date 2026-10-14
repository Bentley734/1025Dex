-- Inclusion list -- Phase 14 (ability audit close-out), the
-- Intimidate-resistant family. These three abilities all interact with
-- Intimidate specifically (national_dex's own records + Showdown):
--   OBLIVIOUS  -- immune to Intimidate; also immune to Attract and
--                Taunt (the Attract/Taunt immunity is wired in
--                status_immunity-style checks at their own application
--                sites; the Intimidate immunity is applied inside
--                abilities/engine/switchin_stat_change.lua, which reads
--                THIS table as its third argument).
--   GUARDDOG   -- immune to Intimidate AND gains +1 Attack instead
--                (i.e. the drop becomes a raise); also prevents forced
--                switching (that half is wired in prevent_misc).
--   RATTLED    -- not immune: takes the -1 Attack AND gets +1 Speed in
--                the same breath (Dark/Bug/Ghost moves trigger it too;
--                that half is wired in hit_taken).
return {
  OBLIVIOUS = true,
  GUARDDOG = true,
  RATTLED = true,
}
