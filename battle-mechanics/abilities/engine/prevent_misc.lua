-- Dispatch engine for abilities/data/prevent_misc.lua -- Phase 7 of the
-- ability roadmap (DAMP, GORILLATACTICS, QUICKFEET) plus Phase 14's
-- close-out additions (GUTS's burn-cut negation, SUCTIONCUPS/GUARDDOG's
-- forced-switch immunity). Three unrelated real mechanisms, each own
-- real primitive:
--
-- DAMP / GORILLATACTICS: both wired at Battle:useMove (Gen 2 only, the
-- same honest asymmetry the rest of this phase's useMove-based work
-- already carries -- see abilities/engine/trap_abilities.lua's own
-- header for why Gen 1 has no equivalent choke point). Combined into one
-- wrap here rather than two separate ones, since both live in this same
-- file already.
--
-- QUICKFEET: wraps `Battle.statusPenaltyFor` (gen2/Battle.lua) directly
-- -- the one real, class-level function EVERY stat-penalizing status
-- (paralysis' Speed quarter, burn's Attack halving) already routes
-- through, confirmed by direct read, AND the same function combat/
-- turn_order.lua's own Gen-9-accurate Speed compare (effectiveSpeedFor)
-- explicitly calls -- so this fixes turn order too, not just whatever
-- reads the raw stat. Gen 1's own paralysis-Speed-cut lives in a
-- different, TRUE Lua-local closure (`TurnOrder.lua`'s own `effectiveSpeed`,
-- captured as an upvalue by that file's own turn-order comparator at load
-- time) -- confirmed unreachable by any mod, the exact same class of
-- "no export seam exists" finding this project has already hit and named
-- honestly elsewhere (native Gen 2 runTurn, Gen 2's old hardcoded rampage
-- trigger before that got a different real fix). Quick Feet's Speed
-- benefit on Gen 1 turn order specifically stays a real, confirmed gap;
-- everything else (the stat_multiplier.lua boost itself, any other real
-- consumer of Battle.statusPenaltyFor) is fully fixed on Gen 2.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "prevent_misc: ability_dispatch.lua must load first")

  ------------------------------------------------------------------
  -- DAMP + GORILLATACTICS
  ------------------------------------------------------------------
  local EXPLOSIVE_MOVES = { SELFDESTRUCT = true, EXPLOSION = true }
  -- Real N-way check (2026-08-28): Damp's own real text is "while this
  -- Pokémon is in battle" -- ANY battler, not just whichever two happen
  -- to be battle.player/battle.enemy. mod.exports.allActiveBattlers
  -- (combat/move_targeting.lua) is the real roster; falls back to the
  -- native pair if that primitive somehow isn't loaded yet.
  local function anyBattlerHasDamp(battle)
    if not data.DAMP then return false end
    local allActiveBattlers = mod.exports.allActiveBattlers
    local roster = allActiveBattlers and allActiveBattlers(battle) or { battle.player, battle.enemy }
    for _, mon in ipairs(roster) do
      if abilityIdOf(mon) == "DAMP" then return true end
    end
    return false
  end
  mod.exports.anyBattlerHasDamp = anyBattlerHasDamp

  -- Phase 14: Suction Cups / Guard Dog block forced switch-outs. Real
  -- N-way check (any opposing forced-switch move fails while the holder
  -- is on the field, matching real Showdown). The native gen2 class is
  -- what's wrapped here, so this only applies to gen2 battles -- the
  -- same honest gen1 gap this file's own DAMP block already carries and
  -- documents.
  local FORCE_SWITCH_MOVES = { ROAR = true, WHIRLWIND = true }
  local function anyBattlerBlocksForcedSwitch(battle)
    if not (data.SUCTIONCUPS or data.GUARDDOG) then return false end
    local allActiveBattlers = mod.exports.allActiveBattlers
    local roster = allActiveBattlers and allActiveBattlers(battle) or { battle.player, battle.enemy }
    for _, mon in ipairs(roster) do
      local id = abilityIdOf(mon)
      if (data.SUCTIONCUPS and id == "SUCTIONCUPS") or (data.GUARDDOG and id == "GUARDDOG") then
        return true
      end
    end
    return false
  end

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
  local nativeUseMovePreventMisc = Battle.useMove
  function Battle:useMove(attacker, defender, moveId)
    if EXPLOSIVE_MOVES[moveId] and anyBattlerHasDamp(self) then
      self:emit({ kind = "message", text = Strings("But it failed!") })
      return
    end
    -- Phase 14: Suction Cups / Guard Dog block Roar/Whirlwind.
    if FORCE_SWITCH_MOVES[moveId] and anyBattlerBlocksForcedSwitch(self) then
      self:emit({ kind = "message", text = Strings("But it failed!") })
      return
    end
    if attacker and data.GORILLATACTICS and abilityIdOf(attacker) == "GORILLATACTICS" then
      local vol = self:volatile(attacker)
      if not vol.gorillaTacticsMoveId then
        vol.gorillaTacticsMoveId = moveId
      elseif vol.gorillaTacticsMoveId ~= moveId then
        moveId = vol.gorillaTacticsMoveId
      end
    end
    return nativeUseMovePreventMisc(self, attacker, defender, moveId)
  end

  ------------------------------------------------------------------
  -- QUICKFEET
  ------------------------------------------------------------------
  local nativeStatusPenaltyFor = Battle.statusPenaltyFor
  function Battle.statusPenaltyFor(battleData, mon, stat, value)
    if stat == "speed" and data.QUICKFEET and abilityIdOf(mon) == "QUICKFEET" then
      return value
    end
    -- Phase 14: Guts negates the burn Attack cut (real text: "not
    -- affected by the usual Attack cut from a burn"). Mirrors the Quick
    -- Feet shape exactly.
    if stat == "attack" and data.GUTS and abilityIdOf(mon) == "GUTS" then
      return value
    end
    return nativeStatusPenaltyFor(battleData, mon, stat, value)
  end
  end

  mod.log:info("g9-battle-engine: prevent_misc installed (DAMP, GORILLATACTICS, QUICKFEET, GUTS, SUCTIONCUPS, GUARDDOG)")
end
