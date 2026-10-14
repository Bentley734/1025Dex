-- CONTRARY/SIMPLE's speed/accuracy/evasion half -- their attack/defense/
-- spa/spd half is a direct edit inside combat/modern_combat.lua's own
-- changeStage (see that function's own comment). This file covers the
-- one other real path a stat stage change can take in this engine: Gen
-- 2's native Battle:changeStageAgainstMist, which switchin_stat_change
-- .lua's NATIVE_STATS branch and modern_movepool_stages.lua's
-- changeNativeStage both route speed/accuracy/evasion through directly,
-- bypassing modern_combat.lua's changeStage (and its own Substitute
-- check) entirely -- a real, pre-existing split this mod's own code
-- already documents in several places, not something introduced here.
--
-- Reimplements the native Mist gate inline (self-contained monkeypatch,
-- never edits gen1recomp-dev's own source) rather than pre-transforming
-- `stages` before delegating to the native function: Mist must still
-- evaluate the RAW, originally-intended sign (a hostile decrease should
-- still be blocked even if the holder also has Contrary) before
-- Contrary/Simple's own transform is applied to what actually lands.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "stage_change_transform: ability_dispatch.lua must load first")

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
  function Battle:changeStageAgainstMist(attacker, target, stat, stages)
    if target ~= attacker and (stages or 0) < 0 and self:volatile(target).mist then
      self:emit({ kind = "message", text = Strings("%s's protected by MIST.", self:monName(target)) })
      return false
    end
    -- Phase 7 (prevent bucket): Clear Body/Full Metal Body/White Smoke/
    -- Hyper Cutter/Big Pecks/Keen Eye/Mind's Eye/Flower Veil's real
    -- "can't have this stat lowered by an opponent" family -- the one
    -- shared definition combat/modern_combat.lua's own changeStage
    -- exports, reused here rather than a second, possibly-drifting copy,
    -- since speed/accuracy/evasion never route through that function at
    -- all (this file's own header).
    local statDropBlockedByAbility = mod.exports.statDropBlockedByAbility
    if target ~= attacker and (stages or 0) < 0 and statDropBlockedByAbility
        and statDropBlockedByAbility(target, true, stat) then
      return false
    end
    -- Real Foresight/Miracle Eye rule (combat/modern_status_volatiles
    -- .lua): blocks the target's own future evasion RAISES while
    -- active -- checked here since this IS the single, real shared
    -- choke point every Gen 2 evasion change routes through (confirmed:
    -- this file's own header, and changeNativeStage's own real callers,
    -- e.g. Minimize/Double Team), not just the generic secondary-effect
    -- path a status move's own damage-triggered chance would use.
    if stat == "evasion" and (stages or 0) > 0 and (target.foresighted or target.miracleEyed) then
      return false
    end
    local id = abilityIdOf(target)
    if data[id] then
      if id == "CONTRARY" then stages = -stages
      elseif id == "SIMPLE" then stages = stages * 2 end
    end
    return self:changeStage(target, stat, stages)
  end
  end

  mod.log:info("g9-battle-engine: stage_change_transform installed (CONTRARY, SIMPLE speed/accuracy/evasion half)")
end
