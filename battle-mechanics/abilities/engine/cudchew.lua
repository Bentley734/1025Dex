-- Dispatch engine for abilities/data/cudchew.lua -- Phase 14 (ability
-- audit close-out). See that file's own header for the real mechanic.
--
-- IMPLEMENTATION -- two observe-only pieces:
--   1. A wrap on held_item.trigger ("residual") -- the SAME hook
--      combat/modern_items.lua's own Unnerve/Ripen/Cheek Pouch work
--      wraps -- that RECORDS the native auto-eat when the holder
--      drops below half HP. This wrap never mutates c.effect or
--      c.parameter and always returns next(c): the native eat itself
--      (Battle:tickHeldItem's own HELD_BERRY arm, heal amount =
--      `parameter > 0 and parameter or 10`, mon.item=nil) proceeds
--      untouched. The record captures the berry's own heal parameter
--      so the second eat heals the SAME amount.
--   2. A battle.turn_ended listener (the event battle:closeTurn emits
--      AFTER the end-of-turn residual sweep -- confirmed by direct
--      source read of base-gen2-Battle.lua: tickHeldItem runs in
--      runTurn, then closeTurn emits turn_ended) that flips the record
--      to "ready" one turn and, the turn after, actually heals:
--      record at turn N's residual, ready at turn N's closeTurn,
--      heal at turn N+1's closeTurn = exactly ONE full turn of delay,
--      matching real Showdown ("at the end of the following turn").
--
-- Gen 1 has no end-of-turn berry auto-eat at all (berries are held
-- items only in Gen 2+), so this whole engine is gated to gen2 battles
-- -- matching how modern_items.lua's own berry logic is gated.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local isGen2Battle = mod.exports.isGen2Battle
  local allActiveBattlers = mod.exports.allActiveBattlers
  local displayNameFor = mod.exports.displayNameFor
  assert(abilityIdOf and isGen2Battle and allActiveBattlers and displayNameFor,
    "cudchew: ability_dispatch.lua, modern_combat.lua must load first")

  local function hpOf(m) return (m and (m.mon or m) or {}).hp or 0 end
  local function maxHpOf(m)
    local mon = m and (m.mon or m) or {}
    return mon.maxHp or (mon.stats and mon.stats.hp) or 1
  end

  mod.hooks:wrap("held_item.trigger", function(next, c)
    if c.trigger == "residual" and c.effect == "HELD_BERRY" and c.mon and c.battle
        and not c.mon.ggdCudChew then
      local mon = c.mon
      local maxHp = maxHpOf(mon)
      -- Same HP gate the native auto-eat itself uses.
      if (mon.hp or 0) * 2 <= maxHp
          and data.CUDCHEW and abilityIdOf(mon) == "CUDCHEW" then
        mon.ggdCudChew = {
          item = c.item,
          amount = (c.parameter and c.parameter > 0) and c.parameter or 10,
          ready = false,
        }
      end
    end
    return next(c)
  end, 0)

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not (battle and isGen2Battle(battle)) then return end
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      local gulp = mon and mon.ggdCudChew
      if gulp and hpOf(mon) > 0 and data.CUDCHEW and abilityIdOf(mon) == "CUDCHEW" then
        if gulp.ready then
          mon.ggdCudChew = nil
          local amount = gulp.amount or 0
          if amount > 0 then
            local healed = battle:heal(mon, amount, { anim = "RECOVER" })
            if healed > 0 then
              battle:emit({ kind = "message",
                text = Strings("%s regurgitated and ate its Berry again!", displayNameFor(battle, mon, true)) })
            end
          end
        else
          gulp.ready = true
        end
      end
    end
  end)

  -- The charge must never leak across a switch-out, a faint-triggered
  -- replacement, or a fresh battle.
  local function clear(battle, mon)
    if mon then mon.ggdCudChew = nil end
  end
  mod.events:on("battle.battler_switched", function(ev)
    if ev and ev.battle and ev.previous then clear(ev.battle, ev.previous) end
  end)
  mod.events:on("battle.ended", function(ev)
    if ev and ev.battle then
      for _, mon in ipairs(ev.battle.party or {}) do clear(ev.battle, mon) end
      for _, mon in ipairs(ev.battle.enemyParty or {}) do clear(ev.battle, mon) end
    end
  end)
  mod.events:on("battle.started", function(ev)
    if ev and ev.battle then
      for _, mon in ipairs(ev.battle.party or {}) do clear(ev.battle, mon) end
      for _, mon in ipairs(ev.battle.enemyParty or {}) do clear(ev.battle, mon) end
    end
  end)

  mod.log:info("g9-battle-engine: cudchew installed (CUDCHEW)")
end
