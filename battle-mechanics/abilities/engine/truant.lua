-- Dispatch engine for abilities/data/truant.lua -- see that file's own
-- header for the real mechanic and the one honest simplification.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  local allActiveBattlers = mod.exports.allActiveBattlers
  assert(abilityIdOf and displayNameFor and isGen2Battle and allActiveBattlers,
    "truant: ability_dispatch.lua, modern_combat.lua, and move_targeting.lua must all load first")

  local function hpOf(m) return (m and (m.mon or m) or {}).hp or 0 end

  -- Switching in resets the loaf count -- a fresh Truant holder always
  -- acts freely on its first turn back.
  local function resetOnEntry(battle, mon)
    if mon and abilityIdOf(mon) == "TRUANT" then mon.truantLoafing = nil end
  end
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      resetOnEntry(battle, mon)
    end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    resetOnEntry(ev and ev.battle, ev and ev.battler)
  end)

  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and hpOf(mon) > 0 and data.TRUANT and abilityIdOf(mon) == "TRUANT" then
        if mon.truantLoafing then
          if gen2 then battle:volatile(mon).recharge = true else mon.mustRecharge = true end
          battle:emit({ kind = "message", text = Strings("%s is loafing around.", displayNameFor(battle, mon, gen2)) })
          mon.truantLoafing = false
        else
          mon.truantLoafing = true
        end
      end
    end
  end)

  mod.log:info("g9-battle-engine: truant installed (TRUANT)")
end
