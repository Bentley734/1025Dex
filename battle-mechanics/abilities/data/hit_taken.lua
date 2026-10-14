-- Inclusion list -- Phase 14 (ability audit close-out), the
-- "when hit" family: abilities that react to the holder taking damage
-- (or a hit of a given type/source) from a move. All real, confirmed
-- mechanics (national_dex's own records + Showdown; each quoted in
-- abilities/engine/hit_taken.lua's own header):
--   STAMINA       -- +1 Defense whenever this Pokémon is hit.
--   WATERCOMPACTION -- +2 Defense when hit by a Water move.
--   STEAMENGINE   -- +3 Speed when hit by a Fire or Water move.
--   JUSTIFIED     -- +1 Attack when hit by a Dark move.
--   RATTLED       -- +1 Speed when hit by a Dark/Bug/Ghost move.
--   ANGERPOINT    -- +6 Attack if the hit lands a critical hit.
--   WEAKARMOR     -- -1 Defense AND +2 Speed when hit by a physical move.
--   STEADFAST     -- +1 Speed when this Pokémon flinches.
--   BERSERK       -- +1 Sp. Atk when its HP drops below half from a move.
--   ANGERSHELL    -- -1 Def, -1 Sp.Def, +1 Atk, +1 Sp.Atk, +1 Speed when
--                  its HP drops below half from a move.
--   COTTONDOWN    -- -1 Speed to ALL other active Pokémon when hit.
--   GOOEY         -- -1 Speed to the attacker on contact.
--   TANGLINGHAIR  -- -1 Speed to the attacker on contact.
--   SANDSPIT      -- sets Sandstorm when hit.
--   SEEDSOWER     -- sets Grassy Terrain when hit.
--
-- ALL of these trigger off the holder TAKING a damaging move (landed,
-- non-zero damage), i.e. the battle's damage_dealt event -- except
-- Steadfast, which fires on flinch (wired via the setFlinched export
-- instead, since no generic "flinch" event exists in the base engine).
return {
  STAMINA = true,
  WATERCOMPACTION = true,
  STEAMENGINE = true,
  JUSTIFIED = true,
  RATTLED = true,
  ANGERPOINT = true,
  WEAKARMOR = true,
  STEADFAST = true,
  BERSERK = true,
  ANGERSHELL = true,
  COTTONDOWN = true,
  GOOEY = true,
  TANGLINGHAIR = true,
  SANDSPIT = true,
  SEEDSOWER = true,
}
