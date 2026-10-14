-- Dispatch engine for abilities/data/form_combat_effects.lua -- see
-- that file's own header for the full real-mechanic grounding and the
-- explicit "transformation out of scope, combat effect isn't" rule
-- behind every one of these.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "form_combat_effects: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  local displayNameFor = mod.exports.displayNameFor
  local requestAdjacency = mod.exports.requestAdjacency
  local allActiveBattlers = mod.exports.allActiveBattlers
  local isGen2Battle = mod.exports.isGen2Battle
  local changeStage = mod.exports.changeStage
  local itemOf = mod.exports.itemOf
  local setMonTypes = mod.exports.setMonTypes
  local canChangeType = mod.exports.canChangeType
  local registerPostEffectivenessModifier = mod.exports.registerPostEffectivenessModifier
  local setWeather = mod.exports.setWeather
  local setTerrain = mod.exports.setTerrain
  local activeTeraType = mod.exports.activeTeraType
  assert(abilityIdOf and displayNameFor and requestAdjacency and allActiveBattlers
      and isGen2Battle and changeStage and itemOf and setMonTypes and canChangeType
      and registerPostEffectivenessModifier and setWeather and setTerrain and activeTeraType,
    "form_combat_effects: ability_dispatch.lua, modern_combat.lua, move_targeting.lua, "
      .. "modern_items.lua, type_override_primitives.lua, and modern_tera.lua must all load first")

  local function hpOf(m) local r = m and (m.mon or m); return r and (r.hp or 0) or 0 end
  local function speciesIdOf(m, gen2) return gen2 and m.species or (m.mon and m.mon.species) end

  -- Live battle reference for the Tera event below: battle_forms's own
  -- `mod.battle_forms.tera_applied` payload (its formapi payload()
  -- helper) carries the real `mon` but NO `battle` field, so the battle
  -- is tracked here from the same battle.started/battle.ended pair the
  -- rest of this engine already keys off (ability_dispatch.lua's own
  -- pattern) -- set before any combat event can matter, cleared on end.
  local currentBattle
  mod.events:on("battle.started", function(ev) currentBattle = ev and ev.battle or nil end)
  mod.events:on("battle.ended", function(ev) currentBattle = nil end)

  -- Same real per-generation native-store speed write Battle Bond's own
  -- header already established this same phase (changeStage's own
  -- bucket doesn't cover speed at all).
  local function raiseSpeed(battle, mon, gen2, delta)
    if gen2 then
      battle:changeStageAgainstMist(mon, mon, "speed", delta)
    else
      mon.stages = mon.stages or {}
      local cur = mon.stages.speed or 0
      mon.stages.speed = math.max(-6, math.min(6, cur + delta))
    end
  end

  ------------------------------------------------------------------
  -- RKS SYSTEM -- type matches the held Memory item's own real type
  -- prefix (`<TYPE>MEMORY`), re-checked on switch-in and every turn
  -- start (cheap, catches Trick/Fling/Knock Off changing the held item
  -- mid-battle without needing a dedicated hook into each of them).
  ------------------------------------------------------------------
  local TYPE_ID_TRANSLATION = { PSYCHIC = "PSYCHIC_TYPE" } -- same real quirk main.lua's own table documents
  local function applyRksSystem(battle, mon)
    if not (data.RKSSYSTEM and abilityIdOf(mon) == "RKSSYSTEM" and hpOf(mon) > 0) then return end
    local gen2 = isGen2Battle(battle)
    local item = itemOf(mon, gen2)
    local typeId = "NORMAL"
    if item and item:sub(-6) == "MEMORY" then
      local raw = item:sub(1, -7)
      typeId = TYPE_ID_TRANSLATION[raw] or raw
    end
    if canChangeType(battle, mon) == false then return end
    setMonTypes(battle, mon, { typeId })
  end
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      applyRksSystem(battle, mon)
    end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    applyRksSystem(ev and ev.battle, ev and ev.battler)
  end)
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      applyRksSystem(battle, mon)
    end
  end)

  ------------------------------------------------------------------
  -- HUNGER SWITCH -- Aura Wheel's own real type alternates with an
  -- internal, form-free "hangry" flag, toggled every turn end. Wrapped
  -- as a "battle.damage" swap-and-restore, the exact same idiom
  -- type_override_moves.lua's own header established this same phase.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and data.HUNGERSWITCH and abilityIdOf(mon) == "HUNGERSWITCH" then
        mon.ggdHangry = not mon.ggdHangry
      end
    end
  end)
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move, user = ctx.move, ctx.user
    if not (move and move.id == "AURAWHEEL" and user and data.HUNGERSWITCH
        and abilityIdOf(user) == "HUNGERSWITCH" and user.ggdHangry) then
      return next(ctx)
    end
    local origType = move.type
    move.type = "DARK"
    local ok, dmg, info = pcall(next, ctx)
    move.type = origType
    if not ok then
      mod.log:warn("g9-battle-engine: form_combat_effects Hunger Switch failed: %s", tostring(dmg))
      return 0, { crit = false, typeMult = 0 }
    end
    return dmg, info
  end, 200)

  ------------------------------------------------------------------
  -- GULP MISSILE -- loads on a real Surf/Dive use attempt (whole-move
  -- entry point, matching real Showdown's own onSourceTryPrimaryHit
  -- timing -- before the accuracy roll, not gated on landing), real
  -- gorging/gulping split by the holder's OWN hp at that moment;
  -- retaliates on any damaging hit taken while loaded.
  ------------------------------------------------------------------
  local GULP_MOVES = { SURF = true, DIVE = true }
  local function loadGulpMissile(mon, gen2)
    if not (data.GULPMISSILE and abilityIdOf(mon) == "GULPMISSILE") then return end
    local m = mon.mon or mon
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0) then return end
    mon.ggdGulpLoaded = (m.hp or 0) * 2 > maxHp and "gorging" or "gulping"
  end
  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMoveGulp = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if attacker and GULP_MOVES[moveId] then loadGulpMissile(attacker, true) end
      return nativeUseMoveGulp(self, attacker, defender, moveId)
    end
  end
  local BattleState = require("src.battle.BattleState")
  local nativePerformMoveGulp = rawget(BattleState, "performMove")
  if type(nativePerformMoveGulp) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    if user and moveInst and GULP_MOVES[moveInst.id] then loadGulpMissile(user, false) end
    return nativePerformMoveGulp(self, user, target, moveInst, isCalled)
  end
  end
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    if not (battle and user and target and (ev.damage or 0) > 0) then return end
    if not (target.ggdGulpLoaded and hpOf(target) > 0) then return end
    local loaded = target.ggdGulpLoaded
    target.ggdGulpLoaded = nil
    local m = user.mon or user
    local maxHp = m.stats and m.stats.hp
    if maxHp and maxHp > 0 then
      m.hp = math.max(0, (m.hp or 0) - math.max(1, math.floor(maxHp / 4)))
    end
    local gen2 = isGen2Battle(battle)
    if loaded == "gorging" then
      -- Real Gen 2 primitive, same real call shape modern_movepool_damage
      -- .lua's own Bounce paralyze-on-release already uses
      -- (`battle:applyStatus(target, "paralyze", "BOUNCE")`) -- Gen 1 has
      -- no equivalent method on BattleState at all (StatusRegistry.inflict
      -- is a different real shape not yet threaded through here) -- a
      -- real, honestly narrower gap for that one generation, not a guess.
      if gen2 and battle.applyStatus then
        battle:applyStatus(user, "paralyze", "GULPMISSILE")
      end
    else
      for _, line in ipairs(changeStage(battle, user, "defense", -1, true, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
    end
  end)

  ------------------------------------------------------------------
  -- COMMANDER -- while active alongside a living ally Dondozo, that
  -- Dondozo's own Atk/SpA/Speed are raised 2 stages each; reversed the
  -- same amount when the Tatsugiri leaves (switch-out or faint).
  ------------------------------------------------------------------
  local function findAllyDondozo(battle, mon, gen2)
    for _, ally in ipairs(requestAdjacency(battle, mon, nil).allies) do
      if ally and hpOf(ally) > 0 and speciesIdOf(ally, gen2) == "DONDOZO" then return ally end
    end
    return nil
  end
  local function applyCommanderBoost(battle, mon, gen2, sign)
    local dondozo = mon.ggdCommanderDondozo
    if not (dondozo and hpOf(dondozo) > 0) then mon.ggdCommanderDondozo = nil return end
    for _, stat in ipairs({ "attack", "spa" }) do
      for _, line in ipairs(changeStage(battle, dondozo, stat, 2 * sign, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
    end
    raiseSpeed(battle, dondozo, gen2, 2 * sign)
    mon.ggdCommanderDondozo = sign > 0 and dondozo or nil
  end
  local function applyCommander(battle, mon)
    if not (data.COMMANDER and abilityIdOf(mon) == "COMMANDER" and hpOf(mon) > 0) then return end
    if mon.ggdCommanderDondozo then return end -- already linked
    local gen2 = isGen2Battle(battle)
    local dondozo = findAllyDondozo(battle, mon, gen2)
    if not dondozo then return end
    mon.ggdCommanderDondozo = dondozo
    applyCommanderBoost(battle, mon, gen2, 1)
  end

  -- Round 338: Transform/Imposter re-run these for the ability it copied.
  mod.exports.registerSwitchInAbility(applyRksSystem)
  mod.exports.registerSwitchInAbility(applyCommander)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      applyCommander(battle, mon)
    end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local battle, mon, previous = ev and ev.battle, ev and ev.battler, ev and ev.previous
    if not battle then return end
    if previous and data.COMMANDER and abilityIdOf(previous) == "COMMANDER" and previous.ggdCommanderDondozo then
      applyCommanderBoost(battle, previous, isGen2Battle(battle), -1)
    end
    if mon then applyCommander(battle, mon) end
  end)
  mod.events:on("battle.fainted", function(ev)
    local battle, mon = ev and ev.battle, ev and ev.battler
    if not (battle and mon) then return end
    if data.COMMANDER and abilityIdOf(mon) == "COMMANDER" and mon.ggdCommanderDondozo then
      applyCommanderBoost(battle, mon, isGen2Battle(battle), -1)
    end
  end)

  ------------------------------------------------------------------
  -- TERASHELL -- while at full HP, caps any super-effective hit down
  -- to not-very-effective (0.5x), regardless of the real type matchup.
  ------------------------------------------------------------------
  registerPostEffectivenessModifier("terashell", 0, function(ctx)
    if not (data.TERASHELL and abilityIdOf(ctx.target) == "TERASHELL") then return 1.0 end
    local m = ctx.target.mon or ctx.target
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0 and (m.hp or 0) >= maxHp) then return 1.0 end
    -- Real, confirmed bug fixed 2026-08-28 (Wonder-Guard-reachability
    -- review): ctx.mult is x10-scaled (10=neutral -- see combat/
    -- modern_combat.lua's own TypeChart usage), not 0..1-scaled, so
    -- BOTH the threshold and the return value here were wrong. The
    -- threshold: `> 1.0` fired on every non-immune hit, not just a
    -- genuinely super-effective one. The return value: by the time this
    -- runs, `d` (the running damage total) has ALREADY been scaled by
    -- the real per-row type multiplier (computeModernDamage's own
    -- TypeChart.rows() loop, earlier in the same function) -- so
    -- capping the EFFECTIVE multiplier at a real 0.5x needs a
    -- correction factor of 0.5 / (ctx.mult / 10), i.e. 5 / ctx.mult, not
    -- the old 0.5 / ctx.mult (which for a real 2x hit, ctx.mult=20,
    -- worked out to 0.025x -- capping a super-effective hit down to
    -- 1/40th damage instead of the real, intended half).
    if ctx.mult and ctx.mult > 10 then return 5 / ctx.mult end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- TERAFORM ZERO / EMBODY ASPECT -- both real, confirmed to fire on
  -- Terastallizing, driven off battle_forms's own real
  -- `mod.battle_forms.tera_applied` event (see combat/modern_tera.lua's
  -- own header for the full landed contract). The payload carries `mon`
  -- but no `battle`, so the live battle comes from currentBattle above.
  ------------------------------------------------------------------
  local EMBODY_STAT_BY_SPECIES = {
    OGERPON_CORNERSTONE_MASK = "defense", OGERPON_HEARTHFLAME_MASK = "attack",
    OGERPON_WELLSPRING_MASK = "spd",
  }
  mod.events:on("mod.battle_forms.tera_applied", function(ev)
    local mon = ev and ev.mon
    local battle = currentBattle
    if not (mon and battle) then return end
    local id = abilityIdOf(mon)
    local gen2 = true -- Terastallization is Gen 2-only in this mod (combat/modern_tera.lua's own real scope)
    if id == "TERAFORMZERO" and data.TERAFORMZERO then
      if activeTeraType(battle, mon, gen2) == "STELLAR" then
        setWeather(battle, gen2, nil)
        setTerrain(battle, mon, nil, "The terrain\nnormalized!")
        battle:emit({ kind = "message", text = Strings("All weather and terrain effects vanished!") })
      end
    elseif id == "EMBODYASPECT" and data.EMBODYASPECT then
      local species = speciesIdOf(mon, gen2)
      local stat = EMBODY_STAT_BY_SPECIES[species] or "speed" -- base Ogerpon (Teal Mask) defaults to Speed
      if stat == "speed" then
        raiseSpeed(battle, mon, gen2, 1)
        battle:emit({ kind = "message", text = Strings("%s's Speed rose!", displayNameFor(battle, mon, gen2)) })
      else
        for _, line in ipairs(changeStage(battle, mon, stat, 1, false, gen2) or {}) do
          battle:emit({ kind = "message", text = line })
        end
      end
    end
  end)

  mod.log:info("g9-battle-engine: form_combat_effects installed (RKSSYSTEM, HUNGERSWITCH, "
    .. "GULPMISSILE, COMMANDER, TERASHELL, TERAFORMZERO, EMBODYASPECT)")
end
