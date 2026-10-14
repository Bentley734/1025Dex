-- Inclusion list only. Real, confirmed abilities: IRONBARBS (attacker
-- takes 1/8 its own max HP on a contact hit against this mon),
-- AFTERMATH (attacker takes 1/4 its own max HP when a CONTACT move
-- lands the killing blow), INNARDSOUT (attacker takes damage equal to
-- this mon's own remaining HP when ANY move lands the killing blow, no
-- contact requirement), LIQUIDOOZE (a drain move against this mon
-- damages the attacker by the would-be-healed amount instead of healing
-- it -- the exact per-mon-ability version of combat/boss_fight_status
-- .lua's own antiDrain boss-fight flag).
return {
  IRONBARBS = true, AFTERMATH = true, INNARDSOUT = true, LIQUIDOOZE = true,
}
