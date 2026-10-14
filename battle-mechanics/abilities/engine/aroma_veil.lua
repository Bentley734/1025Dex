-- Dispatch engine for abilities/data/aroma_veil.lua -- Phase 7 of the
-- ability roadmap. Wired as a real move-fail gate at the same choke
-- points Pressure's own dual-gen fix already proved safe (Gen 2's
-- Battle:useMove, Gen 1's BattleState:performMove) -- checked against
-- the real move id directly rather than touching each of the six
-- separate infliction sites (Attract/Taunt/Torment/Encore live in
-- combat/modern_status_effects.lua, Disable/Heal Block/Psychic Noise in
-- combat/modern_status_volatiles.lua) individually.
--
-- Ally-scope, same real primitive Sweet Veil's own fix already
-- established (abilities/engine/status_immunity.lua's own header):
-- requestAdjacency(battle, target, nil).allies, self checked
-- unconditionally alongside it.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local requestAdjacency = mod.exports.requestAdjacency
  assert(abilityIdOf and requestAdjacency,
    "aroma_veil: ability_dispatch.lua and move_targeting.lua must load first")

  local MENTAL_MOVES = {
    ATTRACT = true, TAUNT = true, TORMENT = true, ENCORE = true,
    DISABLE = true, HEALBLOCK = true, PSYCHICNOISE = true,
  }

  local function protectedByAromaVeil(battle, target)
    if not (target and data.AROMAVEIL) then return false end
    if abilityIdOf(target) == "AROMAVEIL" then return true end
    for _, ally in ipairs(requestAdjacency(battle, target, nil).allies) do
      if abilityIdOf(ally) == "AROMAVEIL" then return true end
    end
    return false
  end

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMoveAromaVeil = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if MENTAL_MOVES[moveId] and defender and defender ~= attacker
          and protectedByAromaVeil(self, defender) then
        self:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      return nativeUseMoveAromaVeil(self, attacker, defender, moveId)
    end
  end

  local BattleState = require("src.battle.BattleState")
  local nativePerformMoveAromaVeil = rawget(BattleState, "performMove")
  if type(nativePerformMoveAromaVeil) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    if moveInst and MENTAL_MOVES[moveInst.id] and target and target ~= user
        and protectedByAromaVeil(self, target) then
      self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
      return
    end
    return nativePerformMoveAromaVeil(self, user, target, moveInst, isCalled)
  end
  end

  mod.log:info("g9-battle-engine: aroma_veil installed (AROMAVEIL)")
end
