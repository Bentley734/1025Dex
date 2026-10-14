-- Gym Badge Buff -- explicit user request (2026-08-28): a real, honestly-
-- flagged gap turned into a togglable fix rather than silently applied.
--
-- Native Gen 2 badge boosts (Battle:battleStat's own BadgeStatBoosts
-- port, Battle:badgeTypeBoost's own DoBadgeTypeBoosts port,
-- src/battle/gen2/Battle.lua:776-808) both gate on literal object
-- identity: `mon ~= self.player then return value end` / `attacker ~=
-- self.player`. Correct in the native single-battler case (self.player
-- IS the only player-side mon that ever exists) -- silently wrong the
-- moment a real doubles/triples fight (g9-Battle-Scene's own real
-- rosters) puts a SECOND or THIRD player-side battler in play: that mon
-- is never literally self.player, so it silently computes its stats as
-- if the player owned no badges at all, even though a real Gold/Silver
-- player's badges are meant to boost their WHOLE team.
--
-- ON (default): fixed for real -- both checks become `battle:sideOf(mon)
-- == "player"` (combat/move_targeting.lua's own N-way override), so
-- every player-side battler gets the same badge boost the lead already
-- did natively. Everything else about either function (the GLACIER
-- special case, the Battle Tower guard, the badge-to-stat/type tables
-- themselves) is untouched -- only the WHO check changes.
-- OFF: badge boosts never apply to anyone, on purpose -- a genuine
-- opt-out for players who don't want this mechanic factored in at all,
-- not a "keep the narrow native behavior" middle state.
return function(mod)
  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil

  local function badgeBuffOn()
    return mod.options:get("gym_badge_buff") == "true"
  end

  if Battle then
  local nativeBattleStat = Battle.battleStat
  function Battle:battleStat(mon, key)
    if not badgeBuffOn() then
      return (mon.stats or {})[key] or 1
    end
    if mon ~= self.player and self:sideOf(mon) == "player" then
      -- Real fix: run the SAME native logic (badge table lookup, GLACIER
      -- special case, Battle Tower guard) against a stand-in that
      -- satisfies the native function's own `mon == self.player` check,
      -- rather than re-implementing that logic a second time here (which
      -- would drift the moment the native badge tables/rules change).
      -- Swaps self.player to `mon` for the duration of this one call
      -- only, restored immediately after -- no other code observes
      -- self.player mid-call (native battleStat itself never emits or
      -- calls back out).
      local realPlayer = self.player
      self.player = mon
      local ok, value = pcall(nativeBattleStat, self, mon, key)
      self.player = realPlayer
      if ok then return value end
      return (mon.stats or {})[key] or 1
    end
    return nativeBattleStat(self, mon, key)
  end

  local nativeBadgeTypeBoost = Battle.badgeTypeBoost
  function Battle:badgeTypeBoost(attacker, moveType)
    if not badgeBuffOn() then return false end
    if attacker ~= self.player and self:sideOf(attacker) == "player" then
      local realPlayer = self.player
      self.player = attacker
      local ok, boosted = pcall(nativeBadgeTypeBoost, self, attacker, moveType)
      self.player = realPlayer
      return ok and boosted or false
    end
    return nativeBadgeTypeBoost(self, attacker, moveType)
  end
  end

  mod.log:info("g9-battle-engine: gym_badge_buff installed (real N-way badge stat/type boost, togglable via GYM BADGE BUFF option)")
end
