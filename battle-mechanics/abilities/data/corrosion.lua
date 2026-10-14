-- Inclusion list -- Phase 11 (ability gaps close-out). UN-DEFERRED.
--   CORROSION -- the holder's poison infliction ignores the Poison- and
--                Steel-type immunity to being poisoned. Real mechanic
--                (national_dex api/002.lua:9 + Showdown).
--
-- The old deferral ("attacker never reaches the status APIs") was stale:
-- the generic secondary listener in main.lua DOES have the attacking mon
-- (`user`), so the type-immunity check lives there now, via
-- combat/modern_combat.lua's own statusTypeImmune + corrosionPiercesPoison
-- (Showdown sim/pokemon.ts:1710 -- `source?.hasAbility('corrosion') &&
-- ['tox','psn'].includes(status.id)`). national_dex's own record is
-- `expressible=false` (no kind models a one-status type-immunity bypass);
-- the engine's own effect entry is an unstructured `other` note, hence
-- the marker + the shared-primitive edit rather than a structured effect.
--
-- Scope: this closes every infliction site that knows its source mon --
-- the generic move-secondary listener (main.lua) and the ability-inflicted
-- family (abilities/engine/inflict_status.lua: Poison Point/Poison Touch/
-- Toxic Chain/Effect Spore, plus the Fire-type burn immunities for Flame
-- Body/Spicy Spray). A site with no source mon (Toxic Spikes, a native
-- status move's own effect script) is a pre-existing native concern, not
-- something this marker can reach.
return {
  CORROSION = true,
}
