-- Dispatch engine for abilities/data/skill_link.lua -- Phase 8 of the
-- ability roadmap. See that file's own header for the real Gen 1-only
-- scope.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "skill_link: ability_dispatch.lua must load first")

  local MoveEffects = require("src.battle.MoveEffects")
  local record = MoveEffects.full and MoveEffects.full.TWO_TO_FIVE_ATTACKS_EFFECT
  if record then
    local nativeHitCount = record.hitCount
    record.hitCount = function(ctx)
      if data.SKILLLINK and ctx.user and abilityIdOf(ctx.user) == "SKILLLINK" then
        return 5
      end
      return nativeHitCount(ctx)
    end
  end

  mod.log:info("g9-battle-engine: skill_link installed (SKILLLINK, Gen 1 only)")
end
