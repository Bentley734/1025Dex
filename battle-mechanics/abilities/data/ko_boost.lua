-- Inclusion list -- Phase 14 (ability audit close-out), the KO-reward
-- family: four abilities that raise a stat when a Pokémon faints.
-- Real, confirmed mechanics (national_dex's own records + Showdown):
--   MOXIE        -- +1 Attack when THIS Pokémon directly knocks out a
--                  target with a move (ally or foe).
--   CHILLINGNEIGH -- +1 Attack when this Pokémon knocks out a target.
--   GRIMNEIGH    -- +1 Sp. Atk when this Pokémon knocks out a target.
--   SOULHEART    -- +1 Sp. Atk whenever ANY Pokémon faints (either
--                  side, including this one's own side -- real text
--                  "every time any Pokémon faints").
-- Trigger split (confirmed against each record's own trigger): Moxie/
-- Chilling Neigh/Grim Neigh fire on the knocker's OWN move landing the
-- KO (the damage_dealt event, move-caused only); Soul-Heart fires on
-- the faint itself regardless of cause (the fainted event, any mon).
return {
  MOXIE = true,
  CHILLINGNEIGH = true,
  GRIMNEIGH = true,
  SOULHEART = true,
}
