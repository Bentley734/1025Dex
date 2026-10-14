-- Dispatch engine for abilities/data/switch_priority_misc.lua -- see
-- that file's own header for the full real-mechanic grounding.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local displayNameFor = mod.exports.displayNameFor
  local requestAdjacency = mod.exports.requestAdjacency
  local allActiveBattlers = mod.exports.allActiveBattlers
  local orderActiveBattlers = mod.exports.orderActiveBattlers
  local isGen2Battle = mod.exports.isGen2Battle
  local changeStage = mod.exports.changeStage
  local stagesFor = mod.exports.stagesFor
  local rawStat = mod.exports.rawStat
  local registerDamageModifier = mod.exports.registerDamageModifier
  local registerPriorityModifier = mod.exports.registerPriorityModifier
  assert(abilityIdOf and displayNameFor and requestAdjacency and allActiveBattlers
      and orderActiveBattlers and isGen2Battle and changeStage and stagesFor
      and rawStat and registerDamageModifier and registerPriorityModifier,
    "switch_priority_misc: ability_dispatch.lua, move_targeting.lua, turn_order.lua, "
      .. "and modern_combat.lua must all load first")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "switch_priority_misc: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById

  local FOUR_STATS = { "attack", "defense", "spa", "spd" }

  local function hpOf(m) return (m and (m.mon or m) or {}).hp or 0 end

  ------------------------------------------------------------------
  -- DOWNLOAD -- switch-in, compares adjacent opponents' summed raw
  -- Defense vs Special Defense.
  ------------------------------------------------------------------
  local function applyDownload(battle, mon, gen2)
    local defTotal, spdTotal = 0, 0
    for _, foe in ipairs(requestAdjacency(battle, mon, nil).enemies) do
      if hpOf(foe) > 0 then
        defTotal = defTotal + (rawStat(foe, "defense", gen2) or 0)
        spdTotal = spdTotal + (rawStat(foe, "spd", gen2) or 0)
      end
    end
    if defTotal == 0 and spdTotal == 0 then return end -- no live opponent to read yet
    local stat = (defTotal >= spdTotal) and "attack" or "spa"
    local msg = changeStage(battle, mon, stat, 1, false, gen2)
    for _, line in ipairs(msg or {}) do battle:emit({ kind = "message", text = line }) end
  end

  ------------------------------------------------------------------
  -- CURIOUS MEDICINE -- switch-in, resets every adjacent ally's 4-stat
  -- bucket to 0 outright (a direct table write, not a delta -- changeStage
  -- only ever expresses a relative move, and "reset to exactly 0" isn't
  -- one).
  ------------------------------------------------------------------
  local function applyCuriousMedicine(battle, mon, gen2)
    for _, ally in ipairs(requestAdjacency(battle, mon, nil).allies) do
      if hpOf(ally) > 0 then
        local stages = stagesFor(battle, ally)
        local reset = false
        for _, stat in ipairs(FOUR_STATS) do
          if (stages[stat] or 0) ~= 0 then stages[stat] = 0; reset = true end
        end
        if reset then
          battle:emit({ kind = "message",
            text = Strings("%s's stat changes were removed!", displayNameFor(battle, ally, gen2)) })
        end
      end
    end
  end

  ------------------------------------------------------------------
  -- COSTAR -- switch-in, copies one adjacent ally's current 4-stat
  -- bucket onto itself outright (overwrite, not additive). Real
  -- volatile-condition half (Focus Energy etc.) not built -- see this
  -- file's own data header.
  ------------------------------------------------------------------
  local function applyCostar(battle, mon, gen2)
    local allies = requestAdjacency(battle, mon, nil).allies
    local ally
    for _, a in ipairs(allies) do
      if hpOf(a) > 0 then ally = a break end
    end
    if not ally then return end
    local fromStages = stagesFor(battle, ally)
    local toStages = stagesFor(battle, mon)
    for _, stat in ipairs(FOUR_STATS) do toStages[stat] = fromStages[stat] or 0 end
    battle:emit({ kind = "message",
      text = Strings("%s copied %s's stat changes!", displayNameFor(battle, mon, gen2), displayNameFor(battle, ally, gen2)) })
  end

  local function applySwitchInMisc(battle, mon)
    if not (battle and mon and hpOf(mon) > 0) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    local gen2 = isGen2Battle(battle)
    if id == "DOWNLOAD" then applyDownload(battle, mon, gen2)
    elseif id == "CURIOUSMEDICINE" then applyCuriousMedicine(battle, mon, gen2)
    elseif id == "COSTAR" then applyCostar(battle, mon, gen2)
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
  -- MOODY -- end of turn, +2 to a random not-maxed stat, -1 to a
  -- different random not-minned stat.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and hpOf(mon) > 0 and data.MOODY and abilityIdOf(mon) == "MOODY" then
        local stages = stagesFor(battle, mon)
        local raisable, raiseIdx = {}, {}
        for i, stat in ipairs(FOUR_STATS) do
          if (stages[stat] or 0) < 6 then raisable[#raisable + 1] = stat; raiseIdx[stat] = i end
        end
        local raised
        if #raisable > 0 then
          raised = raisable[love.math.random(1, #raisable)]
          for _, line in ipairs(changeStage(battle, mon, raised, 2, false, gen2) or {}) do
            battle:emit({ kind = "message", text = line })
          end
        end
        local lowerable = {}
        for _, stat in ipairs(FOUR_STATS) do
          if stat ~= raised and (stages[stat] or 0) > -6 then lowerable[#lowerable + 1] = stat end
        end
        if #lowerable > 0 then
          local lowered = lowerable[love.math.random(1, #lowerable)]
          for _, line in ipairs(changeStage(battle, mon, lowered, -1, false, gen2) or {}) do
            battle:emit({ kind = "message", text = line })
          end
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- BEAST BOOST / EELEVATE -- after this Pokemon's own damaging move
  -- knocks out its target, raises its own highest raw stat (4-stat
  -- bucket) by 1. Same real mechanic under two different ids (national
  -- dex's own two separate real records) -- one shared handler.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    if not (battle and user and target and (ev.damage or 0) > 0) then return end
    local id = abilityIdOf(user)
    local boosts = (data.BEASTBOOST and id == "BEASTBOOST") or (data.EELEVATE and id == "EELEVATE")
    if not boosts then return end
    if hpOf(target) > 0 then return end -- must actually have fainted the target
    local gen2 = isGen2Battle(battle)
    local best, bestVal = FOUR_STATS[1], -math.huge
    for _, stat in ipairs(FOUR_STATS) do
      local v = rawStat(user, stat, gen2) or 0
      if v > bestVal then best, bestVal = stat, v end
    end
    for _, line in ipairs(changeStage(battle, user, best, 1, false, gen2) or {}) do
      battle:emit({ kind = "message", text = line })
    end
  end)

  ------------------------------------------------------------------
  -- BATTLE BOND -- real CURRENT Showdown mechanic (explicit user
  -- directive, 2026-08-28: the pre-Gen-9 Ash-Greninja TRANSFORM half is
  -- gone from real Showdown outright, and this mod owns combat effects
  -- only, never transformations, matching this whole session's own
  -- standing "we don't handle transformations" rule for every other
  -- form-changing ability). Real, confirmed shape, verified against
  -- Showdown's own current source before writing anything here:
  --   - Fires once, permanently, per battle -- NOT once per KO -- the
  --     first time this Pokemon's own damaging move directly faints
  --     ANY other Pokemon (opponent OR ally -- real text says "including
  --     allies" explicitly, so no side check at all, matching the exact
  --     scope BEAST BOOST/EELEVATE's own identical trigger shape above
  --     already established).
  --   - Raises Attack, Special Attack, AND Speed each by 1 stage, all
  --     three attempted together via the same real changeStage primitive
  --     every other stat-raising ability in this file already uses --
  --     which ALREADY correctly no-ops any one of the three that happens
  --     to already be at +6 on its own (changeStage's own real "new ==
  --     cur" guard), so "won't activate if already at +6" needs no
  --     separate all-or-nothing gate -- it falls out of the existing
  --     primitive for free, per-stat, exactly like real Showdown's own
  --     boost() call.
  --   - Water Shuriken's own real Battle-Bond-specific power/hit-count
  --     boost is GONE in current Showdown (removed alongside the
  --     transform) -- correctly, genuinely absent here: nothing in this
  --     mod ever modeled it, so there's nothing to remove.
  --   - The one-time gate itself lives directly on the mon object
  --     (mon.ggdBattleBondTriggered), the same convention this whole
  --     session's other once-per-battle mon-level flags already use
  --     (Truant's own ggdQuickDrawRolled-style fields) -- cleared on
  --     battle.started for every party member so it can never leak from
  --     an earlier battle via a persistent save-file mon object.
  ------------------------------------------------------------------
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(battle.party or {}) do mon.ggdBattleBondTriggered = nil end
    for _, mon in ipairs(battle.enemyParty or {}) do mon.ggdBattleBondTriggered = nil end
  end)
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    if not (battle and user and target and (ev.damage or 0) > 0) then return end
    if not (data.BATTLEBOND and abilityIdOf(user) == "BATTLEBOND") then return end
    if hpOf(target) > 0 then return end -- must actually have fainted the target
    if user.ggdBattleBondTriggered then return end -- real: fires exactly once per battle
    user.ggdBattleBondTriggered = true
    local gen2 = isGen2Battle(battle)
    for _, line in ipairs(changeStage(battle, user, "attack", 1, false, gen2) or {}) do
      battle:emit({ kind = "message", text = line })
    end
    for _, line in ipairs(changeStage(battle, user, "spa", 1, false, gen2) or {}) do
      battle:emit({ kind = "message", text = line })
    end
    -- Speed is a real, confirmed exception to changeStage's own bucket
    -- (that primitive's own established boundary: speed/accuracy/
    -- evasion stay on each generation's real NATIVE stage store, not
    -- this mod's own atk/def/spa/spd table -- Power Trip's own header,
    -- switchin_stat_change.lua's own NATIVE_STATS split, and main.lua's
    -- own movepool-stat-change handler all already establish this same
    -- real boundary). A positive self-raise never needs the boss-
    -- protection gate (that check is delta<0-only by its own real
    -- definition) or a Mist check (Mist only ever blocks a HOSTILE
    -- change), so both real per-generation native writes are safe here
    -- directly: Gen 2's own real Battle:changeStageAgainstMist (which
    -- emits its own message internally, confirmed by every OTHER real
    -- caller of it in this mod never wrapping it in an extra emit);
    -- Gen 1's own real, confirmed direct field (`mon.stages.speed`,
    -- Damage.lua's own real accuracy/speed-formula consumer, clamped
    -- -6..6 the same way every other stage already is).
    if gen2 then
      battle:changeStageAgainstMist(user, user, "speed", 1)
    else
      user.stages = user.stages or {}
      local cur = user.stages.speed or 0
      user.stages.speed = math.max(-6, math.min(6, cur + 1))
    end
  end)

  ------------------------------------------------------------------
  -- SPEED BOOST (Phase 14 close-out) -- end of turn, +1 Speed.
  -- Real, confirmed mechanic: "raises its Speed stat by one stage at
  -- the end of each turn". Real Showdown also requires the holder to
  -- have actually been on the field for the turn (a just-switched-in
  -- mon's first end-of-turn does NOT boost) -- not modeled here
  -- (documented, not silently completed). Speed is the real gen-native
  -- store (BATTLE BOND's own speed branch above is copied exactly --
  -- changeStageAgainstMist on Gen 2, a direct clamped field write on
  -- Gen 1; a positive self-raise is never Mist-gated).
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and hpOf(mon) > 0 and data.SPEEDBOOST and abilityIdOf(mon) == "SPEEDBOOST" then
        if gen2 then
          battle:changeStageAgainstMist(mon, mon, "speed", 1)
        else
          mon.stages = mon.stages or {}
          local cur = mon.stages.speed or 0
          mon.stages.speed = math.max(-6, math.min(6, cur + 1))
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- SUPREME OVERLORD -- 10% Attack/Special Attack boost per fainted
  -- party member (own side), capped at 5 (1.5x max).
  ------------------------------------------------------------------
  local function faintedAllyCount(battle, user)
    local side = battle:sideOf(user)
    local party = (side == "player") and battle.party or battle.enemyParty
    local count = 0
    for _, mon in ipairs(party or {}) do
      if mon ~= user and (mon.hp or 0) <= 0 then count = count + 1 end
    end
    return math.min(count, 5)
  end
  registerDamageModifier("supremeoverlord", 90, function(ctx)
    if not (data.SUPREMEOVERLORD and abilityIdOf(ctx.user) == "SUPREMEOVERLORD") then return 1.0 end
    return 1.0 + 0.1 * faintedAllyCount(ctx.battle, ctx.user)
  end)

  ------------------------------------------------------------------
  -- STALL / QUICK DRAW -- both a small fractional priority offset
  -- within the real bracket (see this file's own data header). Quick
  -- Draw's 30% roll is cached per mon per turn (cleared on
  -- battle.turn_started, same convention modern_combat.lua's own
  -- damagedThisTurn flag already uses) so a caller invoking
  -- Battle:movePriority more than once for the same action still sees
  -- one consistent answer for the turn, not a fresh re-roll each call.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon then mon.ggdQuickDrawRolled = nil end
    end
  end)
  registerPriorityModifier("stall_quickdraw", function(battle, moveId, caster, def)
    if not caster then return 0 end
    local id = abilityIdOf(caster)
    if data.STALL and id == "STALL" then return -0.99 end
    if data.QUICKDRAW and id == "QUICKDRAW" then
      if caster.ggdQuickDrawRolled == nil then
        caster.ggdQuickDrawRolled = love.math.random(1, 100) <= 30
      end
      if caster.ggdQuickDrawRolled then return 0.99 end
    end
    -- Mycelium Might -- priority half only (see this file's own data
    -- header for the real, honestly-scoped second half). Real, confirmed
    -- text: this Pokemon's own STATUS moves always move last within
    -- their priority bracket -- same fractional-offset trick as Stall,
    -- just gated to status-category moves specifically.
    if data.MYCELIUMMIGHT and id == "MYCELIUMMIGHT" then
      local ok, info = pcall(moveById, moveId)
      if ok and info and info.damageClass == "status" then return -0.99 end
    end
    return 0
  end)

  mod.log:info("g9-battle-engine: switch_priority_misc installed (DOWNLOAD, MOODY, "
    .. "CURIOUSMEDICINE, COSTAR, BEASTBOOST, EELEVATE, SUPREMEOVERLORD, STALL, QUICKDRAW, "
    .. "MYCELIUMMIGHT [priority half], BATTLEBOND, SPEEDBOOST)")
end
