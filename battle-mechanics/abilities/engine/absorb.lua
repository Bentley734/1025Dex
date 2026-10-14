-- Dispatch engine for abilities/data/absorb.lua -- Phase 14 (ability
-- audit close-out), the absorb family. See that file's own header for
-- the full real-mechanic grounding and the explicit hardcoding note
-- (the type each absorbs is written out there, not read live).
--
-- Real mechanics (confirmed against national_dex's own records and
-- Showdown, quoted in full in data/absorb.lua's own header):
--   FLASHFIRE    -- immune to Fire; +1.5x Fire power until it leaves
--                  battle (the charge flag is set here and read by
--                  abilities/engine/damage_multiplier.lua).
--   MOTORDRIVE   -- immune to Electric; +1 Speed.
--   LIGHTNINGROD -- immune to Electric; +1 Sp. Atk. A Ground-type
--                  holder immune to Electric gets the block but NO
--                  boost (real Showdown ruling).
--   STORMDRAIN   -- immune to Water; +1 Sp. Atk.
--
-- WHY THIS IS A "battle.damage" WRAP: identical reasoning to
-- abilities/engine/type_immunity.lua's own header (a registerDamage-
-- Modifier can't fire a stat raise inline; battle.damage_dealt only
-- fires for a landed NON-ZERO hit, so zeroing via a modifier would
-- lose the reaction entirely). PRIORITY 40 -- below Protect (50), so a
-- protected target's absorb never triggers, matching Showdown; above
-- modern_combat.lua's own formula wrap (0). Mold Breaker/Teravolt/
-- Turboblaze bypass the block exactly like type_immunity's own.
--
-- The stat-raise primitives mirror type_immunity's own established
-- convention: fromEnemy=false (a raise from being hit is never Mist-
-- gated), gen2=true in the changeStage call (matching switchin_stat_
-- change.lua's own convention for that primitive). Speed (Motordrive)
-- uses the real gen-native speed store, per this mod's own established
-- speed boundary (see hit_taken.lua's own header).
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local isGen2Battle = mod.exports.isGen2Battle
  local changeStage = mod.exports.changeStage
  local curTypesOf = mod.exports.curTypesOf
  assert(abilityIdOf and isGen2Battle and changeStage and curTypesOf,
    "absorb: ability_dispatch.lua, modern_combat.lua must load first")

  local function raiseSpeed(battle, mon, gen2)
    if gen2 then
      battle:changeStageAgainstMist(mon, mon, "speed", 1)
    else
      mon.stages = mon.stages or {}
      local cur = mon.stages.speed or 0
      mon.stages.speed = math.max(-6, math.min(6, cur + 1))
    end
  end

  local function setFlashFireCharged(battle, mon, gen2)
    if gen2 then
      battle:volatile(mon).flashFireCharged = true
    else
      mon.flashFireCharged = true
    end
  end

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local target = ctx.target
    local move = ctx.move
    if not (target and move and move.type) then return next(ctx) end
    local id = abilityIdOf(target)
    if not (id and data[id]) then return next(ctx) end
    -- Mold Breaker/Teravolt/Turboblaze bypass the block (same real,
    -- honestly-scoped rule as type_immunity.lua's own header).
    local ignoreAbility = ctx.user and abilityIdOf(ctx.user)
    if ignoreAbility == "MOLDBREAKER" or ignoreAbility == "TERAVOLT" or ignoreAbility == "TURBOBLAZE" then
      return next(ctx)
    end
    if data[id] ~= move.type then return next(ctx) end
    local gen2 = isGen2Battle(ctx.battle)
    if id == "MOTORDRIVE" then
      raiseSpeed(ctx.battle, target, gen2)
    elseif id == "LIGHTNINGROD" then
      local grounded = false
      for _, t in ipairs(curTypesOf(target, gen2) or {}) do
        if t == "GROUND" then grounded = true break end
      end
      if not grounded then
        for _, line in ipairs(changeStage(ctx.battle, target, "spa", 1, false, true) or {}) do
          ctx.battle:emit({ kind = "message", text = line })
        end
      end
    elseif id == "STORMDRAIN" then
      for _, line in ipairs(changeStage(ctx.battle, target, "spa", 1, false, true) or {}) do
        ctx.battle:emit({ kind = "message", text = line })
      end
    elseif id == "FLASHFIRE" then
      setFlashFireCharged(ctx.battle, target, gen2)
    end
    return 0, { crit = false, typeMult = 0 }
  end, 40)

  -- Clear the Flash Fire charge when the holder leaves the field (real:
  -- "until it leaves battle") and defensively on battle start.
  local function clearCharge(battle, mon, gen2)
    if not mon then return end
    if gen2 then battle:volatile(mon).flashFireCharged = nil
    else mon.flashFireCharged = nil end
  end
  mod.events:on("battle.battler_switched", function(ev)
    local battle, prev = ev and ev.battle, ev and ev.previous
    if battle and prev then clearCharge(battle, prev, isGen2Battle(battle)) end
  end)
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    for _, mon in ipairs(battle.party or {}) do clearCharge(battle, mon, gen2) end
    for _, mon in ipairs(battle.enemyParty or {}) do clearCharge(battle, mon, gen2) end
  end)

  mod.log:info("g9-battle-engine: absorb installed (FLASHFIRE, MOTORDRIVE, LIGHTNINGROD, STORMDRAIN)")
end
