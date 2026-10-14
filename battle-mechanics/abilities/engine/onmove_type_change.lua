-- Dispatch engine for abilities/data/type_change_onmove.lua (Protean,
-- Libero) -- no ability-specific data lives here beyond the id set itself.
--
-- Trigger point: wraps Battle:useMove, checking BEFORE calling native --
-- national_dex's own Protean record: "The change happens immediately
-- before the move executes," which is exactly what the top of a useMove
-- wrap is, the same class-level-method-wrap pattern this mod already
-- establishes everywhere else (SUBEFFECTS.md's own cited precedent).
--
-- Reuses three primitives that all predate any ability: mod.exports.
-- setMonTypes/canChangeType (combat/type_override_primitives.lua) for the
-- actual change and its Tera/Dynamax gate, and mod.exports.
-- hasUsedTypeChangeThisSwitchIn/markTypeChangeUsedThisSwitchIn (same file)
-- for the real once-per-switch-in limit national_dex's own Protean/Libero
-- notes both call out explicitly.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  local abilityIdOf = mod.exports.abilityIdOf
  local setMonTypes = mod.exports.setMonTypes
  local canChangeType = mod.exports.canChangeType
  local hasUsed = mod.exports.hasUsedTypeChangeThisSwitchIn
  local markUsed = mod.exports.markTypeChangeUsedThisSwitchIn
  assert(abilityIdOf and setMonTypes and canChangeType and hasUsed and markUsed,
    "onmove_type_change: ability_dispatch.lua and type_override_primitives.lua must load first")

  if Battle then
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if attacker and (attacker.hp or 0) > 0 then
        local id = abilityIdOf(attacker)
        if id and data[id] and not hasUsed(self, attacker) then
          local def = self:moveDef(moveId)
          local moveType = def and def.type
          if moveType and canChangeType(self, attacker, { viaOpponent = false }) then
            markUsed(self, attacker)
            setMonTypes(self, attacker, { moveType })
            self:emit({ kind = "message",
              text = Strings("%s transformed into the %s type!", self:monName(attacker), moveType) })
          end
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  mod.log:info("g9-battle-engine: onmove_type_change ability engine installed (PROTEAN, LIBERO)")
end
