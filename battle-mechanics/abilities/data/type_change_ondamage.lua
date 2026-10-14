-- Color Change: trigger="on_damaged", scope="self" -- the bearer's own
-- type is set to match whatever move just hit it. Real national_dex notes:
-- doesn't trigger on Substitute-blocked or indirect damage, and only the
-- LAST hit of a multi-hit move counts -- both already true for free of
-- abilities/engine/ondamage_type_change.lua's own battle.damage_dealt
-- hook, which only ever fires per real landed hit (never for a
-- Substitute-absorbed or indirect one) and fires once per individual hit
-- of a multi-hit move, so the final call is naturally the last thing to
-- run.
return {
  COLORCHANGE = true,
}
