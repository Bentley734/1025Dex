-- Dispatch engine for abilities/data/emergency_exit.lua -- see that
-- file's own header for the real mechanic and grounding.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local requestSwitch = mod.exports.requestSwitch
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  assert(abilityIdOf and requestSwitch and displayNameFor and isGen2Battle,
    "emergency_exit: ability_dispatch.lua, switch_primitives.lua, and modern_combat.lua must all load first")

  mod.events:on("battle.damage_dealt", function(ev)
    local battle, target = ev and ev.battle, ev and ev.target
    local dealt = ev and ev.damage
    if not (battle and target and dealt and dealt > 0) then return end
    local id = abilityIdOf(target)
    local eligible = (id == "EMERGENCYEXIT" and data.EMERGENCYEXIT) or (id == "WIMPOUT" and data.WIMPOUT)
    if not eligible then return end
    local m = target.mon or target
    local maxHp = m.maxHp or (m.stats and m.stats.hp)
    if not (maxHp and maxHp > 0) then return end
    local hpAfter = m.hp or 0
    local hpBefore = hpAfter + dealt
    if hpAfter <= 0 then return end -- fainted outright, nothing to switch
    -- Real gate: only fires crossing DOWN through the half-HP line, not
    -- on every hit once already below it.
    if not (hpBefore * 2 > maxHp and hpAfter * 2 <= maxHp) then return end
    local gen2 = isGen2Battle(battle)
    local text = Strings("%s fled the battle!", displayNameFor(battle, target, gen2))
    requestSwitch(battle, target, { reason = id, text = text })
  end)

  mod.log:info("g9-battle-engine: emergency_exit installed (EMERGENCYEXIT, WIMPOUT)")
end
