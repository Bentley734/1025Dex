-- Dispatch engine for abilities/data/other_misc.lua -- see that file's
-- own header for the full, per-ability real-mechanic grounding.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "other_misc: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  local requestAdjacency = mod.exports.requestAdjacency
  local allActiveBattlers = mod.exports.allActiveBattlers
  local orderActiveBattlers = mod.exports.orderActiveBattlers
  local canonicalStatusOf = mod.exports.canonicalStatusOf
  local curTypesOf = mod.exports.curTypesOf
  local isGen2Battle = mod.exports.isGen2Battle
  local hazardsFor = mod.exports.hazardsFor
  local registerAccuracyModifier = mod.exports.registerAccuracyModifier
  assert(abilityIdOf and requestAdjacency and allActiveBattlers and orderActiveBattlers
      and canonicalStatusOf and curTypesOf and isGen2Battle and hazardsFor and registerAccuracyModifier,
    "other_misc: ability_dispatch.lua, move_targeting.lua, turn_order.lua, status_immunity.lua, "
      .. "modern_combat.lua, modern_hazards.lua, and accuracy_multiplier.lua must all load first")
  local TypeChart = require("src.battle.TypeChart")

  local function rawMon(m) return m and (m.mon or m) end
  local function hpOf(m) local r = rawMon(m) return r and (r.hp or 0) or 0 end
  local function maxHpOf(m) local r = rawMon(m) return r and r.stats and r.stats.hp or nil end
  local function damageFraction(m, fraction)
    local r = rawMon(m)
    local maxHp = maxHpOf(m)
    if not (r and maxHp and maxHp > 0) then return end
    r.hp = math.max(0, (r.hp or 0) - math.max(1, math.floor(maxHp * fraction)))
  end

  -- Real, confirmed Gen 1/2 OHKO moves. Sheer Cold doesn't exist this
  -- early (Gen 3+) but is included anyway -- harmless, and keeps this
  -- table correct if a later phase ever adds it.
  local OHKO_MOVES = { FISSURE = true, GUILLOTINE = true, HORNDRILL = true, SHEERCOLD = true }

  ------------------------------------------------------------------
  -- BAD DREAMS -- end-of-turn residual against every adjacent sleeping
  -- opponent. See combat/type_immunity.lua's own header on why a plain
  -- events:on (not a hooks:wrap) is correct for a residual tick with no
  -- downstream value to return.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not (battle and data.BADDREAMS) then return end
    local roster = allActiveBattlers(battle) or { battle.player, battle.enemy }
    for _, mon in ipairs(roster) do
      if mon and hpOf(mon) > 0 and abilityIdOf(mon) == "BADDREAMS" then
        local foes = requestAdjacency(battle, mon, nil).enemies
        for _, foe in ipairs(foes) do
          if hpOf(foe) > 0 and canonicalStatusOf(foe) == "sleep" then
            damageFraction(foe, 1 / 8)
          end
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- CURSED BODY -- 30% chance, on any landed damaging hit taken, disable
  -- the attacker's just-used move. Reuses Disable's own real fields
  -- directly (disabledMoveId/disableTurns) -- move_availability_gate.lua
  -- already enforces them for every source, this ability included, for
  -- free. move.id from the damage event IS the attacker's just-used
  -- move -- no separate "lastMove" lookup needed (unlike the Disable
  -- MOVE's own effect, which fires independently of any hit and has to
  -- infer it).
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local target, user, move = ev and ev.target, ev and ev.user, ev and ev.move
    if not (target and user and move and (ev.damage or 0) > 0) then return end
    if not (data.CURSEDBODY and abilityIdOf(target) == "CURSEDBODY") then return end
    if hpOf(target) <= 0 then return end -- real: doesn't trigger if the holder itself fainted from the hit
    if move.id == "STRUGGLE" or user.disabledMoveId then return end
    if love.math.random(1, 100) > 30 then return end
    user.disabledMoveId = move.id
    user.disableTurns = 5
    local battle = ev.battle
    if battle then
      battle:emit({ kind = "message", text = Strings("%s's move was disabled by the Cursed Body!", battle:monName(user)) })
    end
  end)

  ------------------------------------------------------------------
  -- ANTICIPATION / FOREWARN -- both switch-in-only, both purely
  -- informational (message, no mechanical effect), both scan every
  -- adjacent opponent's revealed moveset. Same battle.started +
  -- battle.battler_switched two-event pattern abilities/engine/
  -- switchin_weather.lua's own header already establishes as the real
  -- shape for a switch-in ability trigger.
  ------------------------------------------------------------------
  local function anticipationShudders(battle, mon, gen2)
    local myTypes = curTypesOf(mon, gen2)
    for _, foe in ipairs(requestAdjacency(battle, mon, nil).enemies) do
      if hpOf(foe) > 0 then
        for _, mv in ipairs(rawMon(foe).moves or {}) do
          local ok, info = pcall(moveById, mv.id)
          if ok and info then
            local id = info.id or info.strippedId
            if OHKO_MOVES[id] then return true end
            if (info.power or 0) > 0 and info.type then
              -- pcall-guarded: TypeChart is loaded by the main.lua
              -- battle.started bootstrap, but a switch-in scan must never
              -- be able to hard-crash the battle -- treat a lookup
              -- failure as "no super-effective move found".
              local okEff, mult = pcall(TypeChart.effectiveness, info.type, myTypes)
              if okEff and mult and mult > 1.0 then return true end
            end
          end
        end
      end
    end
    return false
  end

  local function forewarnPower(info)
    if not info then return 0 end
    local id = info.id or info.strippedId
    if OHKO_MOVES[id] then return 150 end
    if id == "COUNTER" or id == "MIRRORCOAT" then return 120 end
    local bp = info.power or 0
    if bp == 0 and info.damageClass and info.damageClass ~= "status" then return 80 end
    return bp
  end

  local function applyForewarn(battle, mon)
    local best, bestBp = {}, 0
    for _, foe in ipairs(requestAdjacency(battle, mon, nil).enemies) do
      if hpOf(foe) > 0 then
        for _, mv in ipairs(rawMon(foe).moves or {}) do
          local ok, info = pcall(moveById, mv.id)
          local bp = ok and forewarnPower(info) or 0
          if bp > 0 then
            if bp > bestBp then
              best, bestBp = { { move = info, foe = foe } }, bp
            elseif bp == bestBp then
              best[#best + 1] = { move = info, foe = foe }
            end
          end
        end
      end
    end
    if #best == 0 then return end
    local pick = best[love.math.random(1, #best)]
    battle:emit({ kind = "message", text = Strings("%s's Forewarn alerted it to %s's %s!", battle:monName(mon), battle:monName(pick.foe), (pick.move.name or pick.move.id)) })
  end

  local function applySwitchInMisc(battle, mon)
    if not (battle and mon and hpOf(mon) > 0) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    local gen2 = isGen2Battle(battle)
    if id == "ANTICIPATION" and anticipationShudders(battle, mon, gen2) then
      battle:emit({ kind = "message", text = Strings("%s shuddered!", battle:monName(mon)) })
    elseif id == "FOREWARN" then
      applyForewarn(battle, mon)
    elseif id == "SCREENCLEANER" then
      local cleared = false
      if gen2 and battle.screens then
        for _, side in ipairs({ "player", "enemy" }) do
          local s = battle.screens[side]
          if s and ((s.lightScreen or 0) > 0 or (s.reflect or 0) > 0) then
            s.lightScreen, s.reflect = nil, nil
            cleared = true
          end
        end
      else
        for _, b in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
          local r = rawMon(b)
          if r and (r.lightScreen or r.reflect) then
            r.lightScreen, r.reflect = nil, nil
            cleared = true
          end
        end
      end
      if cleared then
        battle:emit({ kind = "message", text = Strings("The Light Screen and Reflect effects disappeared!") })
      end
    end
  end

  -- Round 338: Transform/Imposter re-run this for the ability it copied.
  mod.exports.registerSwitchInAbility(applySwitchInMisc)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local roster = allActiveBattlers(battle) or { battle.player, battle.enemy }
    for _, mon in ipairs(orderActiveBattlers(battle, roster) or roster) do
      applySwitchInMisc(battle, mon)
    end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local battle, mon = ev and ev.battle, ev and ev.battler
    if battle and mon then applySwitchInMisc(battle, mon) end
  end)

  ------------------------------------------------------------------
  -- WONDER SKIN -- forces any status move used against the holder to
  -- exactly 50% accuracy, real exceptions: an always-hit move (no
  -- numeric base accuracy at all) and a move already less accurate than
  -- 50 are both left untouched. Approximation, honestly flagged: this
  -- engine's accuracy chain is a pure multiplier stack (registered
  -- factors all multiply together, then apply once), so if some OTHER
  -- accuracy modifier (Compound Eyes, Hustle, Victory Star) is also live
  -- the same turn, the real result would be an absolute override to 50
  -- but this engine's result is 50 scaled by that other factor too -- an
  -- extremely narrow combo (an accuracy-boosting ability's holder
  -- attacking a Wonder Skin holder with a status move) not worth a new
  -- override-shaped hook for.
  ------------------------------------------------------------------
  registerAccuracyModifier("wonderskin", 0, function(ctx)
    local target = ctx.target
    if not (target and data.WONDERSKIN and abilityIdOf(target) == "WONDERSKIN") then return 1.0 end
    local ok, info = pcall(moveById, ctx.moveId)
    if not (ok and info and info.damageClass == "status") then return 1.0 end
    local base = ctx.accuracy
    if type(base) ~= "number" or base < 50 then return 1.0 end
    return 50 / base
  end)

  ------------------------------------------------------------------
  -- TOXIC DEBRIS -- any landed PHYSICAL hit taken sets one layer of
  -- Toxic Spikes (real 2-layer cap, shared hazards table) on the
  -- ATTACKER's own side.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local target, user, move = ev and ev.target, ev and ev.user, ev and ev.move
    local battle = ev and ev.battle
    if not (target and user and move and battle and (ev.damage or 0) > 0) then return end
    if not (data.TOXICDEBRIS and abilityIdOf(target) == "TOXICDEBRIS") then return end
    local ok, info = pcall(moveById, move.id)
    if not (ok and info and info.damageClass == "physical") then return end
    local side = battle:sideOf(user)
    local h = hazardsFor(battle, side)
    if h.toxicSpikes < 2 then
      h.toxicSpikes = h.toxicSpikes + 1
      battle:emit({ kind = "message", text = Strings("Poison spikes scattered around the opposing team's feet!") })
    end
  end)

  mod.log:info("g9-battle-engine: other_misc installed (BADDREAMS, CURSEDBODY, ANTICIPATION, "
    .. "FOREWARN, WONDERSKIN, SCREENCLEANER, TOXICDEBRIS)")
end
