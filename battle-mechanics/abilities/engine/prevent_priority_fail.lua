-- Dispatch engine for abilities/data/prevent_priority_fail.lua -- Phase 7
-- of the ability roadmap (DAZZLING, QUEENLYMAJESTY, ARMORTAIL). Wired at
-- the exact same Battle:useMove choke point (Gen 2 only -- this codebase
-- has no equivalent for Gen 1, the same honest asymmetry Embargo/Heal
-- Block/Throat Chop/Disable's own effect-block halves already carry, see
-- combat/modern_status_volatiles.lua's own header) Prankster's own
-- Dark-type immunity and Embargo/Heal Block/Throat Chop already chain
-- through, so all four compose safely regardless of load order.
--
-- Real priority read live via Battle:movePriority(moveId, caster) --
-- combat/turn_order.lua's own real primitive, already caster-aware since
-- Phase 5 (Prankster needed the same thing) -- not a second, hardcoded
-- priority table.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "prevent_priority_fail: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "prevent_priority_fail: ability_dispatch.lua must load first")

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if defender and defender ~= attacker and data[abilityIdOf(defender)] then
        local info = moveById(moveId)
        if info and info.target == "selected-pokemon" and self:movePriority(moveId, attacker) > 0 then
          self:emit({ kind = "message", text = Strings("But it failed!") })
          return
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  mod.log:info("g9-battle-engine: prevent_priority_fail installed (DAZZLING, QUEENLYMAJESTY, ARMORTAIL)")
end
