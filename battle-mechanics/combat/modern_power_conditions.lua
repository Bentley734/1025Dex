-- Phase 13 of the missing-effects pipeline: conditional and variable power.
--
-- Showdown source of truth (scratch/showdown/moves.ts, read by direct
-- extraction this session; the handler quoted per move is the real one):
--   avalanche (908): basePowerCallback doubles when the user was damaged
--     BY THIS TARGET this turn.
--   payback (13187): doubles when the target has ALREADY MOVED this turn.
--   revenge (15054): doubles when the user was damaged by this target.
--   hex (8608): doubles when the target has a status (or Comatose).
--   brine (1841): onBasePower x2 when target.hp * 2 <= target.maxhp.
--   facade (5033): onBasePower x2 while the user has a non-sleep status.
--   boltbeak (1602) / fishiousrend (5493): doubles when the target
--     `newlySwitched || this.queue.willMove(target)` (i.e. the user moves
--     first); payback is the explicit inverse.
--   collisioncourse (2625) / electrodrift (4611): onBasePower applies
--     chainModify([5461, 4096]) (x1.3331) on a super-effective target.
--   ficklebeam (5219): onBasePower x2 on a randomChance(3, 10) (30%).
--   fusionbolt (6354) / fusionflare (6373): onBasePower x2 when
--     this.lastSuccessfulMoveThisTurn was the counterpart.
--   lashout (10049): onBasePower x2 when source.statsLoweredThisTurn.
--   psyblade (14024): onBasePower x1.5 in Electric Terrain.
--   expandingforce (4944): onBasePower x1.5 in Psychic Terrain while the
--     source is grounded (and it spreads in doubles -- out of scope here).
--   retaliate (14996): onBasePower x2 when the user's side fainted last turn.
--   smellingsalts (17014): doubles on a PARALYZED target, then cures it.
--   wakeupslap (20465): doubles on a SLEEPING (or Comatose) target, then
--     cures the sleep.
--   risingvoltage (15138): doubles in Electric Terrain on a grounded target.
--   eruption (4889) / waterspout (20662) / dragonenergy (4134):
--     basePower * pokemon.hp / pokemon.maxhp.
--   return (15015): floor(happiness * 10 / 25) || 1.
--   frustration (6273): floor((255 - happiness) * 10 / 25) || 1.
--   ragefist (14584): min(350, 50 + 50 * timesAttacked).
--   storedpower (18111): basePower + 20 * positiveBoosts.
--   lastrespects (10092): 50 + 50 * side.totalFainted.
--   furycutter (6306): basePower * the volatile 'furycutter' multiplier,
--     clamped [1, 160] -- i.e. 40, 80, 160, 160, ... on consecutive uses.
--     The volatile carries `duration: 2` and only EXPIRES (resetting to
--     40) when the user goes a full turn without using Fury Cutter (or
--     uses a different move); it is NOT a per-turn reset, so a user who
--     keeps clicking Fury Cutter keeps escalating across turns.
--
-- Two of these moves carry a SECOND, real effect beyond the power change,
-- wired here alongside it because it is the same move's own behavior and
-- belongs in the same round:
--   - SMELLINGSALTS cures the target's paralysis after a landed hit
--     (`if (target.status === 'par') target.cureStatus();`, moves.ts).
--   - WAKEUPSLAP cures the target's sleep after a landed hit (same block).
-- Both are applied on `battle.damage_dealt` (a real landed hit), never
-- inside the power hook: the power hook runs during the damage
-- CALCULATION, which the AI also performs to preview a candidate move, so
-- curing there would strip a status from a target the AI merely
-- considered attacking.
--
-- HEX and WAKE-UP SLAP also double against Comatose
-- (`target.hasAbility('comatose')`, moves.ts hex/wakeupslap) -- Comatose
-- is an ability, not a .status value, so both checks consult the ability
-- id too (the ability is registered by abilities/data/status_immunity.lua).
--
-- FACADE's x2 is expressed here, but its OTHER real property -- it is not
-- weakened by its own user's burn (battle-actions.ts:1816: the burn
-- x0.5 is skipped when `move.id === 'facade'`) -- lives where the burn
-- cut itself lives, combat/modern_combat.lua's computeModernDamage.
--
-- DEFERRED (documented, not faked). Four of this phase's moves need engine
-- state that does not exist anywhere in this codebase, and inventing an
-- approximation would be a silent lie rather than a partial:
--   STOMPINGTANTRUM / TEMPERFLARE -- both double when the user's PREVIOUS
--     move FAILED (`moveLastTurnResult === false`). Nothing tracks per-move
--     success/failure, and a "move used" event is not a "move succeeded"
--     one, so the two are being kept out of this round rather than guessed.
--   PURSUIT -- doubles and becomes sure-hit/tracking on a target that is
--     being switched out (`beingCalledBack || switchFlag`); it needs the
--     switch-interception pass, not a power hook.
--   COMEUPPANCE -- deals a FLAT `lastDamagedBy.damage * 1.5` from its own
--     damageCallback (not a scaled power), so it belongs with the
--     fixed-damage family, not here.
-- When the switch-interception and move-success work lands, these move to
-- their own round; until then they stay listed in MISSING_EFFECTS_PLAN.md.
--
-- Every entry registers through registerPowerOverride -- the base-power
-- substitution seam Heavy Slam / Flail / Power Trip already use -- rather
-- than the trailing registerDamageModifier chain, because every one of
-- these moves changes its base power BEFORE the damage formula (see the
-- block comment above the entries).
return function(mod)
  -- Every entry below is a BASE-POWER change (see the big comment above the
  -- power-override block near the bottom), so this file uses ONLY
  -- registerPowerOverride -- not registerDamageModifier, which scales the
  -- finished damage and would land a couple of HP off.
  local registerPowerOverride = mod.exports.registerPowerOverride
  local curTypesOf = mod.exports.curTypesOf
  local resolvedTypeMult = mod.exports.resolvedTypeMult
  local isGen2Battle = mod.exports.isGen2Battle
  local stagesFor = mod.exports.stagesFor
  local sideOfWho = mod.exports.sideOfWho
  assert(registerPowerOverride,
    "modern_power_conditions: combat/modern_combat.lua must load first")
  assert(curTypesOf and resolvedTypeMult,
    "modern_power_conditions: combat/modern_combat.lua must load first")

  ------------------------------------------------------------------
  -- Battler / HP / status helpers (same shapes modern_combat.lua's own
  -- local statusOf/currentAndMaxHP use -- gen2 objects ARE the raw mon,
  -- gen1 battlers carry the real mon under .mon).
  ------------------------------------------------------------------
  local function rawMon(who, gen2)
    if gen2 then return who end
    return who and who.mon
  end

  -- Exact mirror of modern_combat.lua's own local currentAndMaxHP (this
  -- file does not get to reach it -- it is a local there, not exported),
  -- including the per-generation max-HP fallback chain: Gen 2's raw mon
  -- carries maxHp, Gen 1's wrapper-mon carries it under stats.hp.
  local function hpAndMax(who, gen2)
    local mon = gen2 and who or (who and who.mon)
    if not mon then return 0, 1 end
    local maxHp = gen2 and (mon.maxHp or (mon.stats and mon.stats.hp))
      or (mon.stats and mon.stats.hp)
    return mon.hp or 0, math.max(1, maxHp or 1)
  end

  local function statusCode(who, gen2)
    local mon = rawMon(who, gen2)
    return mon and mon.status
  end

  local function isStatused(who, gen2)
    local s = statusCode(who, gen2)
    return s ~= nil and s ~= "" and s ~= "OK" and s ~= 0
  end

  -- Status words differ by generation: Gen 1's StatusRegistry uses codes
  -- (PSN/BRN/PAR/FRZ/SLP), Gen 2 uses words (poison/burn/paralyze/freeze/
  -- sleep/toxic). Normalize to the word for a targeted check.
  local function statusIs(who, gen2, kind)
    local s = statusCode(who, gen2)
    if not s then return false end
    s = tostring(s):upper()
    if kind == "par" then return s == "PAR" or s == "PARALYZE" or s == "PARALYSIS" end
    if kind == "slp" then return s == "SLP" or s == "SLEEP" end
    return false
  end

  -- Ability id of a battler, lazily (ability_dispatch.lua may load after
  -- this file, so never capture it at load time) -- used only for
  -- Comatose, which is not a .status value and so is invisible to
  -- statusCode above.
  local function hasAbilityId(who, id)
    local fn = mod.exports.abilityIdOf
    return (fn and fn(who)) == id
  end
  local function comatose(who)
    return hasAbilityId(who, "COMATOSE")
  end
  -- Hex doubles against "has a status OR Comatose"; Wake-Up Slap against
  -- "asleep OR Comatose" (Comatose is not curable, so the cure half below
  -- deliberately does NOT trigger for it -- matches moves.ts, where only
  -- `target.status === 'slp'` calls cureStatus()).
  local function isStatusedOrComatose(who, gen2)
    return isStatused(who, gen2) or comatose(who)
  end
  local function isAsleepLike(who, gen2)
    return statusIs(who, gen2, "slp") or comatose(who)
  end

  -- "Grounded", deliberately the SAME rule combat/modern_terrain.lua's own
  -- local isGrounded already applies to every terrain effect (Gravity's
  -- field-grounded flag, then the live, Transform/Tera-aware type list):
  -- Psychic Terrain's Expanding Force and Electric Terrain's Rising
  -- Voltage are terrain rules, so they must agree with terrain's own
  -- sleep/priority rules about who is grounded. That file's header already
  -- documents the shared, known limit honestly -- Levitate / Air Balloon /
  -- Magnet Rise / Telekinesis are not modelled, so "grounded" here means
  -- "not Flying and not lifted by Gravity" and no further. Both
  -- `gravityGrounded` shapes are read because a Gen 1 battler keeps it
  -- under .mon while a Gen 2 battler IS the mon (modern_terrain's own
  -- version accepts either).
  local function grounded(who, gen2)
    if who and (who.gravityGrounded or (who.mon and who.mon.gravityGrounded)) then
      return true
    end
    for _, t in ipairs(curTypesOf(who, gen2)) do
      if t == "FLYING" then return false end
    end
    return true
  end

  local function terrainOf(battle)
    return battle and battle.terrain
  end

  local function superEffective(ctx)
    local mult = resolvedTypeMult(ctx.battle, ctx.user, ctx.target, ctx.gen2, ctx.move.type)
    return mult ~= nil and mult > 10
  end

  ------------------------------------------------------------------
  -- Per-turn state. All flags live on the battler/mon objects (or a
  -- battle-scoped table for the one side-level fact), the same direct-
  -- field convention the engine and this mod already use, and are cleared
  -- at turn boundaries so a stale flag can never leak into a later turn.
  ------------------------------------------------------------------
  local function movedThisTurn(battle, who)
    if isGen2Battle(battle) then return battle:volatile(who).movedThisTurn == true end
    return who.movedThisTurn == true
  end

  -- attackRecords[battle][victim][attacker] = true -- "this attacker hit
  -- this victim this turn", the direct analogue of Showdown's
  -- `pokemon.attackedBy ... thisTurn` that Avalanche/Revenge read.
  local attackedBy = setmetatable({}, { __mode = "k" })
  local function recordAttacker(battle, victim, attacker)
    local b = attackedBy[battle]
    if not b then b = {}; attackedBy[battle] = b end
    local v = b[victim]
    if not v then v = {}; b[victim] = v end
    if attacker then v[attacker] = true end
  end
  local function wasHitByThisTurn(battle, victim, attacker)
    local b = attackedBy[battle]
    local v = b and b[victim]
    return (v and v[attacker]) == true
  end

  local switchedIn = setmetatable({}, { __mode = "k" })
  local function markSwitched(battle, who)
    if not who then return end
    local s = switchedIn[battle]
    if not s then s = {}; switchedIn[battle] = s end
    s[who] = true
  end
  local function isNewlySwitched(battle, who)
    local s = switchedIn[battle]
    return (s and s[who]) == true
  end

  -- Previous-turn faint per side (Retaliate's side.faintedLastTurn).
  local faintedThisTurn = setmetatable({}, { __mode = "k" })
  local faintedLastTurn = setmetatable({}, { __mode = "k" })
  local function markFainted(battle, who, gen2)
    local side = sideOfWho(battle, who, gen2)
    if not side then return end
    local s = faintedThisTurn[battle]
    if not s then s = {}; faintedThisTurn[battle] = s end
    s[side] = true
  end
  local function sideFaintedLastTurn(battle, who, gen2)
    local side = sideOfWho(battle, who, gen2)
    local s = faintedLastTurn[battle]
    return side ~= nil and s ~= nil and s[side] == true
  end

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    -- ev.battler is the INCOMING mon and ev.previous the outgoing one
    -- (the same pair modern_combat.lua's own stage-bucket reset listener
    -- reads). Both lose their per-mon carry-over state, so a mon that
    -- switches out and later returns starts clean -- the direct analogue
    -- of Showdown clearing timesAttacked/volatiles on switch-out.
    markSwitched(battle, ev.battler)
    for _, who in ipairs({ ev.battler, ev.previous }) do
      if who then
        who.__g9TimesAttacked = nil
        who.__g9StatLoweredThisTurn = nil
        who.__g9FuryCutterUses = nil
        who.__g9FuryCutterTurn = nil
      end
    end
  end)

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local target, user, damage = ev.target, ev.user, ev.damage
    -- Only a real move-owned hit counts -- a user AND positive damage.
    -- Showdown's `pokemon.attackedBy` entries and `timesAttacked` both
    -- come from moveHit, never from burn/sand/hazard chip, which reaches
    -- this event with no user.
    if not (target and user and (damage or 0) > 0) then return end
    recordAttacker(battle, target, user)
    target.__g9TimesAttacked = (target.__g9TimesAttacked or 0) + 1
  end)

  -- Smellingsalts / Wake-Up Slap's second real effect (see file header):
  -- cure the target's paralysis / sleep after a landed hit. Fired from
  -- damage_dealt rather than the power hook so AI damage previews (which
  -- run the power hook without dealing damage) can never strip a status.
  -- cureStatusOf is combat/... abilities/engine/status_cure.lua's own
  -- exported primitive and is looked up lazily, since that file loads
  -- after this one.
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    if not (battle and ev.target and ev.move and (ev.damage or 0) > 0) then return end
    local cureStatusOf = mod.exports.cureStatusOf
    if not cureStatusOf then return end
    local gen2 = isGen2Battle(battle)
    local id = ev.move.id
    if id == "SMELLINGSALTS" and statusIs(ev.target, gen2, "par") then
      cureStatusOf(ev.target)
    elseif id == "WAKEUPSLAP" and statusIs(ev.target, gen2, "slp") then
      cureStatusOf(ev.target)
    end
  end)

  mod.events:on("battle.fainted", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local who = ev.mon or ev.target or ev.battler or ev.pokemon
    local gen2 = isGen2Battle(battle)
    if who then markFainted(battle, who, gen2) end
  end)

  mod.events:on("battle.move_used", function(ev)
    local battle, user = ev and ev.battle, ev and ev.user
    if not (battle and user) then return end
    if isGen2Battle(battle) then battle:volatile(user).movedThisTurn = true
    else user.movedThisTurn = true end
    -- lastSuccessfulMoveThisTurn approximation: the move most recently
    -- STARTED this turn (see file header -- success is not tracked).
    local moveId = (ev.move and ev.move.id) or ev.moveId
    battle.__g9LastMoveThisTurn = moveId
    -- Each new use rerolls Fickle Beam's 30% gamble.
    user.__g9FickleDoubles = nil
    -- Fury Cutter's consecutive-use counter. Real Showdown models this as
    -- a volatile with `duration: 2` that onRestart doubles the multiplier:
    -- it survives to the user's NEXT turn and expires only if a full turn
    -- passes without another Fury Cutter. `battle.__g9TurnIndex` (bumped
    -- once per battle.turn_started, below) lets the same rule be applied
    -- here -- consecutive = this turn or the immediately preceding one.
    -- Using any other move clears it outright, matching the volatile
    -- simply not being refreshed.
    if moveId == "FURYCUTTER" then
      local turn = battle.__g9TurnIndex or 0
      if user.__g9FuryCutterTurn and (turn - user.__g9FuryCutterTurn) <= 1 then
        user.__g9FuryCutterUses = (user.__g9FuryCutterUses or 1) + 1
      else
        user.__g9FuryCutterUses = 1
      end
      user.__g9FuryCutterTurn = turn
    else
      user.__g9FuryCutterUses = nil
      user.__g9FuryCutterTurn = nil
    end
  end)

  local function resetTurnFlags(battle)
    if not battle then return end
    attackedBy[battle] = nil
    switchedIn[battle] = nil
    -- Retaliate's "fainted last turn" rolls forward as the turn advances.
    local prev = faintedThisTurn[battle]
    faintedLastTurn[battle] = prev or {}
    faintedThisTurn[battle] = {}
    battle.__g9LastMoveThisTurn = nil
    -- Monotonic per-battle turn counter for Fury Cutter's duration-2
    -- expiry rule (never reset for the life of the battle, only for its
    -- own ordering); bumped here so the very first turn is 1.
    battle.__g9TurnIndex = (battle.__g9TurnIndex or 0) + 1
    local fn = mod.exports.allActiveBattlers
    local list = (fn and fn(battle)) or { battle.player, battle.enemy }
    for _, m in ipairs(list) do
      if m then
        m.__g9StatLoweredThisTurn = nil
        -- NOTE: __g9FuryCutterUses is deliberately NOT cleared here --
        -- it is a cross-turn consecutive-use counter, not a per-turn
        -- flag (see the move_used handler above). It clears on a
        -- different move, on switch-out, or by the duration-2 expiry.
        if isGen2Battle(battle) then
          battle:volatile(m).movedThisTurn = nil
        else
          m.movedThisTurn = nil
        end
      end
    end
  end
  mod.events:on("battle.turn_started", function(ev) resetTurnFlags(ev and ev.battle) end)
  mod.events:on("battle.started", function(ev) resetTurnFlags(ev and ev.battle) end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if battle then
      attackedBy[battle] = nil; switchedIn[battle] = nil
      faintedThisTurn[battle] = nil; faintedLastTurn[battle] = nil
    end
  end)

  -- Fickle Beam caches its 30% roll for the whole use so the modifier chain
  -- (which may be evaluated more than once for one hit) cannot reroll.
  local function fickleBeamDoubles(battle, who, gen2)
    if who.__g9FickleDoubles == nil then
      if gen2 then
        who.__g9FickleDoubles = battle.random(100) < 30
      else
        who.__g9FickleDoubles = battle.rng(1, 100) <= 30
      end
    end
    return who.__g9FickleDoubles
  end

  ------------------------------------------------------------------
  -- Power-override entries.
  --
  -- EVERY move in this phase changes its BASE POWER in Showdown -- the
  -- basePowerCallback family replaces the value outright, the onBasePower
  -- family chainModify()s it -- and both happen BEFORE the damage formula
  -- runs. They therefore all go through registerPowerOverride, never the
  -- trailing damage-multiplier chain: doubling the finished damage is a
  -- couple of HP off from doubling the power (the formula's own +2 and
  -- inner floors), so the plan's original "use registerDamageModifier for
  -- the onBasePower ones" shortcut was retired here in favour of the exact
  -- base-power order. `ctx.move.power` is the stored base power; the
  -- constants in BASE_POWER are the read-from-Showdown fallback, used only
  -- when a move record carries no power (PokeAPI reports null for a few).
  ------------------------------------------------------------------
  local BASE_POWER = {
    AVALANCHE = 60, REVENGE = 60, PAYBACK = 50, BOLTBEAK = 85, FISHIOUSREND = 85,
    HEX = 65, BRINE = 65, FACADE = 70, SMELLINGSALTS = 70, WAKEUPSLAP = 70,
    RISINGVOLTAGE = 70, LASHOUT = 75, PSYBLADE = 80, EXPANDINGFORCE = 80,
    FICKLEBEAM = 80, FUSIONBOLT = 100, FUSIONFLARE = 100,
    COLLISIONCOURSE = 100, ELECTRODRIFT = 100, RETALIATE = 70,
    ERUPTION = 150, WATERSPOUT = 150, DRAGONENERGY = 150,
    RAGEFIST = 50, STOREDPOWER = 20, LASTRESPECTS = 50, FURYCUTTER = 40,
  }
  local function basePowerOf(ctx, id)
    local mp = ctx.move and ctx.move.power
    if mp and mp > 0 then return mp end
    return BASE_POWER[id] or 0
  end
  -- Showdown's chainModify(num/den) on the base power is a floored
  -- multiply, so every multiplier below is floor(power * num / den):
  -- x2 = 2/1, x1.5 = 3/2, Collision Course's chainModify([5461, 4096]).
  local function scaled(ctx, id, num, den)
    return math.floor(basePowerOf(ctx, id) * num / den)
  end

  -- `newlySwitched || this.queue.willMove(target)`: the target either just
  -- came in, or has not acted yet this turn (Bolt Beak / Fishious Rend's
  -- condition; Payback is the explicit inverse).
  local function userMovesFirst(ctx)
    if isNewlySwitched(ctx.battle, ctx.target) then return true end
    return not movedThisTurn(ctx.battle, ctx.target)
  end

  -- ---- basePowerCallback family (replace the base power) ----------------

  registerPowerOverride("AVALANCHE", function(ctx)
    if wasHitByThisTurn(ctx.battle, ctx.user, ctx.target) then
      return scaled(ctx, "AVALANCHE", 2, 1)
    end
    return basePowerOf(ctx, "AVALANCHE")
  end)

  registerPowerOverride("REVENGE", function(ctx)
    if wasHitByThisTurn(ctx.battle, ctx.user, ctx.target) then
      return scaled(ctx, "REVENGE", 2, 1)
    end
    return basePowerOf(ctx, "REVENGE")
  end)

  registerPowerOverride("PAYBACK", function(ctx)
    -- Doubles only when the target is NOT newly switched and CANNOT still
    -- move, i.e. it has already acted this turn.
    if isNewlySwitched(ctx.battle, ctx.target) then return basePowerOf(ctx, "PAYBACK") end
    if movedThisTurn(ctx.battle, ctx.target) then
      return scaled(ctx, "PAYBACK", 2, 1)
    end
    return basePowerOf(ctx, "PAYBACK")
  end)

  registerPowerOverride("BOLTBEAK", function(ctx)
    if userMovesFirst(ctx) then return scaled(ctx, "BOLTBEAK", 2, 1) end
    return basePowerOf(ctx, "BOLTBEAK")
  end)

  registerPowerOverride("FISHIOUSREND", function(ctx)
    if userMovesFirst(ctx) then return scaled(ctx, "FISHIOUSREND", 2, 1) end
    return basePowerOf(ctx, "FISHIOUSREND")
  end)

  registerPowerOverride("HEX", function(ctx)
    if isStatusedOrComatose(ctx.target, ctx.gen2) then return scaled(ctx, "HEX", 2, 1) end
    return basePowerOf(ctx, "HEX")
  end)

  registerPowerOverride("SMELLINGSALTS", function(ctx)
    if statusIs(ctx.target, ctx.gen2, "par") then return scaled(ctx, "SMELLINGSALTS", 2, 1) end
    return basePowerOf(ctx, "SMELLINGSALTS")
  end)

  registerPowerOverride("WAKEUPSLAP", function(ctx)
    if isAsleepLike(ctx.target, ctx.gen2) then return scaled(ctx, "WAKEUPSLAP", 2, 1) end
    return basePowerOf(ctx, "WAKEUPSLAP")
  end)

  registerPowerOverride("RISINGVOLTAGE", function(ctx)
    if terrainOf(ctx.battle) == "ELECTRIC" and grounded(ctx.target, ctx.gen2) then
      return scaled(ctx, "RISINGVOLTAGE", 2, 1)
    end
    return basePowerOf(ctx, "RISINGVOLTAGE")
  end)

  -- ---- onBasePower family (chainModify the base power) ------------------

  registerPowerOverride("BRINE", function(ctx)
    local hp, maxHp = hpAndMax(ctx.target, ctx.gen2)
    if hp * 2 <= maxHp then return scaled(ctx, "BRINE", 2, 1) end
    return basePowerOf(ctx, "BRINE")
  end)

  registerPowerOverride("FACADE", function(ctx)
    -- Doubles while the user has a status OTHER than sleep. (Its other real
    -- property -- burn not cutting it -- lives in modern_combat.lua's own
    -- burn block.)
    if isStatused(ctx.user, ctx.gen2) and not statusIs(ctx.user, ctx.gen2, "slp") then
      return scaled(ctx, "FACADE", 2, 1)
    end
    return basePowerOf(ctx, "FACADE")
  end)

  registerPowerOverride("COLLISIONCOURSE", function(ctx)
    if superEffective(ctx) then return scaled(ctx, "COLLISIONCOURSE", 5461, 4096) end
    return basePowerOf(ctx, "COLLISIONCOURSE")
  end)

  registerPowerOverride("ELECTRODRIFT", function(ctx)
    if superEffective(ctx) then return scaled(ctx, "ELECTRODRIFT", 5461, 4096) end
    return basePowerOf(ctx, "ELECTRODRIFT")
  end)

  registerPowerOverride("FICKLEBEAM", function(ctx)
    if fickleBeamDoubles(ctx.battle, ctx.user, ctx.gen2) then
      return scaled(ctx, "FICKLEBEAM", 2, 1)
    end
    return basePowerOf(ctx, "FICKLEBEAM")
  end)

  registerPowerOverride("FUSIONBOLT", function(ctx)
    if ctx.battle.__g9LastMoveThisTurn == "FUSIONFLARE" then
      return scaled(ctx, "FUSIONBOLT", 2, 1)
    end
    return basePowerOf(ctx, "FUSIONBOLT")
  end)

  registerPowerOverride("FUSIONFLARE", function(ctx)
    if ctx.battle.__g9LastMoveThisTurn == "FUSIONBOLT" then
      return scaled(ctx, "FUSIONFLARE", 2, 1)
    end
    return basePowerOf(ctx, "FUSIONFLARE")
  end)

  registerPowerOverride("LASHOUT", function(ctx)
    -- The flag lives on the BATTLER object (changeStage writes `who`, the
    -- same object ctx.user is), NOT the raw mon under .mon -- so this reads
    -- ctx.user directly, exactly as Assurance reads ctx.target
    -- .damagedThisTurn (and that is correct on BOTH generations).
    if ctx.user.__g9StatLoweredThisTurn then return scaled(ctx, "LASHOUT", 2, 1) end
    return basePowerOf(ctx, "LASHOUT")
  end)

  registerPowerOverride("PSYBLADE", function(ctx)
    if terrainOf(ctx.battle) == "ELECTRIC" then return scaled(ctx, "PSYBLADE", 3, 2) end
    return basePowerOf(ctx, "PSYBLADE")
  end)

  registerPowerOverride("EXPANDINGFORCE", function(ctx)
    if terrainOf(ctx.battle) == "PSYCHIC" and grounded(ctx.user, ctx.gen2) then
      return scaled(ctx, "EXPANDINGFORCE", 3, 2)
    end
    return basePowerOf(ctx, "EXPANDINGFORCE")
  end)

  registerPowerOverride("RETALIATE", function(ctx)
    if sideFaintedLastTurn(ctx.battle, ctx.user, ctx.gen2) then
      return scaled(ctx, "RETALIATE", 2, 1)
    end
    return basePowerOf(ctx, "RETALIATE")
  end)

  -- ---- pure-substitution family (no base-power relationship) ------------

  local function hpFractionPower(id)
    return function(ctx)
      local hp, maxHp = hpAndMax(ctx.user, ctx.gen2)
      return math.floor(basePowerOf(ctx, id) * hp / maxHp)
    end
  end
  registerPowerOverride("ERUPTION", hpFractionPower("ERUPTION"))
  registerPowerOverride("WATERSPOUT", hpFractionPower("WATERSPOUT"))
  registerPowerOverride("DRAGONENERGY", hpFractionPower("DRAGONENERGY"))

  registerPowerOverride("RETURN", function(ctx)
    local mon = rawMon(ctx.user, ctx.gen2)
    local happiness = (mon and mon.happiness) or 70
    local bp = math.floor((happiness * 10) / 25)
    return bp == 0 and 1 or bp
  end)
  registerPowerOverride("FRUSTRATION", function(ctx)
    local mon = rawMon(ctx.user, ctx.gen2)
    local happiness = (mon and mon.happiness) or 70
    local bp = math.floor(((255 - happiness) * 10) / 25)
    return bp == 0 and 1 or bp
  end)

  registerPowerOverride("RAGEFIST", function(ctx)
    -- `timesAttacked` is counted onto the battler in the damage_dealt
    -- handler, so it is read from ctx.user directly (see Lashout above).
    local times = ctx.user.__g9TimesAttacked or 0
    return math.min(350, 50 + 50 * times)
  end)

  registerPowerOverride("STOREDPOWER", function(ctx)
    -- 20 + 20 per positive stage, summed across the mod's atk/def/spa/spd
    -- store (Power Trip's own documented scope -- speed/accuracy/evasion
    -- stay native).
    local st = stagesFor(ctx.battle, ctx.user) or {}
    local positive = 0
    for _, v in pairs(st) do if (v or 0) > 0 then positive = positive + v end end
    return basePowerOf(ctx, "STOREDPOWER") + 20 * positive
  end)

  registerPowerOverride("LASTRESPECTS", function(ctx)
    -- side.totalFainted: every fainted member of the user's party. The
    -- engine's party arrays are battle.party (player) / battle.enemyParty
    -- (enemy) -- the same pair modern_side_conditions.lua reads.
    local side = ctx.battle and sideOfWho(ctx.battle, ctx.user, ctx.gen2)
    local party = side == "enemy" and (ctx.battle.enemyParty or {}) or (ctx.battle.party or {})
    local fainted = 0
    for _, p in ipairs(party) do
      local mon = p and (p.mon or p)
      if mon and (mon.hp or 0) <= 0 then fainted = fainted + 1 end
    end
    return 50 + 50 * fainted
  end)

  registerPowerOverride("FURYCUTTER", function(ctx)
    -- multiplier doubles per consecutive use; clamped [1, 160] exactly as
    -- Showdown's clampIntRange(move.basePower * multiplier, 1, 160).
    local uses = ctx.user.__g9FuryCutterUses or 1
    local bp = basePowerOf(ctx, "FURYCUTTER") * (2 ^ (uses - 1))
    return math.max(1, math.min(160, bp))
  end)

  return true
end
