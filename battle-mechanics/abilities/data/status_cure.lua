-- Inclusion list only -- chances are read LIVE from national_dex's own
-- abilityBehaviorOf (SHEDSKIN's real 33%, HEALER's real 30%, both
-- confirmed via a direct dump, not assumed to be 100%). Real, confirmed
-- abilities: SHEDSKIN (turn-end, cures self), HYDRATION (cures self
-- while raining), NATURALCURE (cures self on switch-out), HEALER
-- (turn-end, cures each adjacent ally -- a genuine no-op in today's
-- 2-battler engine, ready once a real ally slot exists).
return {
  SHEDSKIN = true, HYDRATION = true, NATURALCURE = true, HEALER = true,
}
