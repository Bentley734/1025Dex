-- Dispatch engine for abilities/data/good_as_gold.lua -- Phase 7 of the
-- ability roadmap. Wired at the same real Battle:useMove/BattleState
-- :performMove choke points Prankster's own Dark-type immunity and
-- Aroma Veil above already use -- checks the move's own real
-- damageClass/target fields live (national_dex's own moveById) rather
-- than a per-move id list, so this covers every status move in the
-- entire roster automatically, existing and future.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "good_as_gold: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "good_as_gold: ability_dispatch.lua must load first")

  local function blocksMove(target, moveId)
    if not (target and data.GOODASGOLD and abilityIdOf(target) == "GOODASGOLD") then return false end
    local info = moveById(moveId)
    return info ~= nil and info.damageClass == "status" and info.target == "selected-pokemon"
  end

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMoveGoodAsGold = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if defender and defender ~= attacker and blocksMove(defender, moveId) then
        self:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      return nativeUseMoveGoodAsGold(self, attacker, defender, moveId)
    end
  end

  local BattleState = require("src.battle.BattleState")
  local nativePerformMoveGoodAsGold = rawget(BattleState, "performMove")
  if type(nativePerformMoveGoodAsGold) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    if moveInst and target and target ~= user and blocksMove(target, moveInst.id) then
      self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
      return
    end
    return nativePerformMoveGoodAsGold(self, user, target, moveInst, isCalled)
  end
  end

  mod.log:info("g9-battle-engine: good_as_gold installed (GOODASGOLD)")
end
