-- Dispatch engine for abilities/data/item_interaction.lua -- see that
-- file's own header for the full real-mechanic grounding and the
-- honestly-scoped remainder (Gluttony/Pickup/Symbiosis/Cud Chew).
return function(mod, data)
  local Strings = require("src.core.Strings")
  local isGen2Battle = mod.exports.isGen2Battle
  local abilityIdOf = mod.exports.abilityIdOf
  local displayNameFor = mod.exports.displayNameFor
  local requestAdjacency = mod.exports.requestAdjacency
  local allActiveBattlers = mod.exports.allActiveBattlers
  local orderActiveBattlers = mod.exports.orderActiveBattlers
  local itemOf = mod.exports.itemOf
  local isUnremovable = mod.exports.isUnremovable
  local currentWeather = mod.exports.currentWeather
  local makesContact = mod.exports.makesContact
  assert(isGen2Battle and abilityIdOf and displayNameFor and requestAdjacency
      and allActiveBattlers and orderActiveBattlers and itemOf and isUnremovable
      and currentWeather and makesContact,
    "item_interaction: modern_combat.lua, modern_items.lua, move_targeting.lua, "
      .. "turn_order.lua, ability_dispatch.lua, and long_reach.lua must all load first")

  ------------------------------------------------------------------
  -- FRISK -- switch-in, purely informational.
  ------------------------------------------------------------------
  local function applySwitchIn(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0 and isGen2Battle(battle)) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    if id == "FRISK" then
      for _, foe in ipairs(requestAdjacency(battle, mon, nil).enemies) do
        local item = itemOf(foe, true)
        if item then
          local def = battle:itemDef(item)
          battle:emit({ kind = "message", text = Strings("%s frisked %s and found its %s!", displayNameFor(battle, mon, true), displayNameFor(battle, foe, true), (def and def.name or item)) })
        end
      end
    elseif id == "HARVEST" then
      -- The 50%/100% roll itself lives on battle.turn_ended below --
      -- switch-in only needs the same dispatch table membership check,
      -- nothing else, so there's genuinely nothing to do here. Listed
      -- for clarity that Harvest IS handled by this file, not missed.
    end
  end
  -- Round 338: Transform/Imposter re-run this for the ability it copied.
  mod.exports.registerSwitchInAbility(applySwitchIn)
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local roster = allActiveBattlers(battle) or { battle.player, battle.enemy }
    for _, mon in ipairs(orderActiveBattlers(battle, roster) or roster) do
      applySwitchIn(battle, mon)
    end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local battle, mon = ev and ev.battle, ev and ev.battler
    if battle and mon then applySwitchIn(battle, mon) end
  end)

  ------------------------------------------------------------------
  -- MAGICIAN / PICKPOCKET -- both real item-steal-on-hit abilities,
  -- opposite directions (Magician: attacker steals from whoever it just
  -- hit; Pickpocket: defender steals from whoever just hit it with a
  -- CONTACT move). Both gated on the STEALER currently holding nothing,
  -- and on the victim's item actually being removable (same real Mail
  -- exemption Knock Off/Thief/Covet already established).
  ------------------------------------------------------------------
  local function steal(battle, stealer, victim, stealerName, victimName)
    if itemOf(stealer, true) then return end -- real: only fires while itemless
    local item = itemOf(victim, true)
    if not item or isUnremovable(item) then return end
    local def = battle:itemDef(item)
    victim.item = nil
    stealer.item = item
    battle:emit({ kind = "message", text = Strings("%s stole %s's %s!", stealerName, victimName, (def and def.name or item)) })
  end

  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target, move = ev and ev.battle, ev and ev.user, ev and ev.target, ev and ev.move
    if not (battle and user and target and move and (ev.damage or 0) > 0 and isGen2Battle(battle)) then return end
    if data.MAGICIAN and abilityIdOf(user) == "MAGICIAN" then
      steal(battle, user, target, displayNameFor(battle, user, true), displayNameFor(battle, target, true))
    end
    if data.PICKPOCKET and abilityIdOf(target) == "PICKPOCKET" and (target.hp or 0) > 0
        and makesContact(move.id, user) then
      steal(battle, target, user, displayNameFor(battle, target, true), displayNameFor(battle, user, true))
    end
  end)

  ------------------------------------------------------------------
  -- HARVEST -- after this Pokemon's own held Berry has been auto-eaten
  -- (modern_items.lua's own real ggdLastConsumedItem/
  -- ggdConsumedBerryThisBattle tracking, the one real consumption path
  -- this engine models), a 50%/100%-in-sun chance each end of turn to
  -- regrow it -- self-limiting: once regrown, itemOf(mon) is no longer
  -- nil, so this stops re-rolling for that mon until it eats again.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not (battle and isGen2Battle(battle)) then return end
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and (mon.hp or 0) > 0 and data.HARVEST and abilityIdOf(mon) == "HARVEST"
          and not itemOf(mon, true) and mon.ggdConsumedBerryThisBattle and mon.ggdLastConsumedItem then
        local chance = (currentWeather(battle, true) == "SUN") and 100 or 50
        if love.math.random(1, 100) <= chance then
          mon.item = mon.ggdLastConsumedItem
          local def = battle:itemDef(mon.item)
          battle:emit({ kind = "message", text = Strings("%s's Harvest grew a fresh %s!", displayNameFor(battle, mon, true), (def and def.name or mon.item)) })
        end
      end
    end
  end)

  mod.log:info("g9-battle-engine: item_interaction installed (FRISK, MAGICIAN, PICKPOCKET, HARVEST)")
end
