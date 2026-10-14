-- Missing-effects plan, Phase 17: charge / two-turn / consecutive-use.
-- Verified against Showdown's own real source this pass (data/moves.ts,
-- each record read directly) plus this engine's own move pipeline
-- (scratch/engine/BattleState.lua's charge branch, gen2/Battle.lua's
-- separate Effects.CHARGE system). The twelve moves and what each really is:
--
--   SOLARBLADE (moves.ts:17261) -- a charge move whose CHARGE TURN is
--     skipped in sun and whose POWER is halved in rain/sand/snow.
--   METEORBEAM (moves.ts:11740) -- a charge move that also raises the
--     user's Sp. Atk one stage on the CHARGE turn only.
--   SKYDROP (moves.ts:16681) -- a charge move; the user leaves the field
--     on turn 1 and strikes on turn 2.
--   ICEBALL (moves.ts:9236) / ROLLOUT (moves.ts:15364) -- the same
--     consecutive-use power ladder: `30 * 2 ** contactHitCount`, doubled
--     again while the user still carries Defense Curl's boost.
--   ECHOEDVOICE (moves.ts:4404) -- a field pseudo-weather whose
--     multiplier climbs by one per consecutive use (40 -> 200), resetting
--     once a full turn passes without another use.
--   SHELLTRAP (moves.ts:16277) -- priority -3; it only fires if the user
--     was hit by an opponent's PHYSICAL move before it acts.
--   BEAKBLAST (moves.ts:1119) -- priority -3; any mon that makes CONTACT
--     with the user before it acts is burned, then the move resolves.
--   ROUND (moves.ts:15499) / WATERPLEDGE / FIREPLEDGE / GRASSPLEDGE
--     (moves.ts:20519 / 5380 / 7579) -- all four deal their plain base
--     damage already and only gain a SECOND half from a PARTNER's move
--     (Round doubles when an ally used Round; a Pledge becomes 150 and
--     lays a field condition when an ally used a different Pledge). In
--     this engine's 1-vs-1 shape there is no ally action to pair with, so
--     those halves are genuinely unobservable -- exactly the same
--     situation combat/structural_exemptions.lua already documents for
--     Follow Me / Helping Hand -- and, unlike those, the base move is
--     fully correct as-is. They are deliberately NOT repointed here
--     (nothing is broken); recorded in combat/NATIVE_COVERAGE.md.
--
-- SEAMS USED, all pre-existing:
--   * Charge moves ride the engine's own charge machinery -- the same
--     `charge` field Solar Beam / Bounce already use (Gen 1: BattleState's
--     record.charge branch, keyed by move id for the announce text; Gen 2:
--     the separate `Effects.CHARGE[def.effect]` table). Each charge effect
--     here also gets a Gen 2 `Effects.CHARGE` entry for its own text.
--   * Solar Blade's sun-skip is added to combat/modern_weather.lua's own
--     SUN_SKIPS_CHARGE table (the Solar Beam mechanism), Gen 1 only --
--     the exact same documented Gen 2 limitation Solar Beam already has.
--   * The power ladders ride registerPowerOverride (base power BEFORE the
--     formula, the Phase 13 convention), fed by a `battle.move_used`
--     counter that mirrors modern_power_conditions.lua's own Fury Cutter
--     volatile (`battle.__g9TurnIndex` + a last-use turn).
--   * Meteor Beam's charge-turn boost rides the engine's own
--     `battle.charge_required` hook, which is CALLED on exactly the
--     charge turn and skipped on the release turn.
--   * Shell Trap's fail-if-not-hit rides modern_action_order.lua's
--     reusable `registerFailGate` seam; both it and Beak Blast arm from
--     the `battle.turn_started` payload's chosen actions and react on
--     `battle.damage_dealt`.
--
-- HONEST PARTIALS (documented, not faked):
--   * SKYDROP: the two-turn vanish/strike is wired, but the real move also
--     carries the TARGET into the air (neither mon can act, both are
--     untargetable, and a Flying-type target takes no damage on release).
--     This engine's charge machinery is user-side only (Fly/Dig make only
--     the USER semi-invulnerable), so the target-carry half is not
--     modelled -- Sky Drop plays as a one-mon Fly that deals damage.
--   * ICEBALL / ROLLOUT: the power ladder and Defense Curl doubling are
--     wired, but the real 5-turn onLockMove (the user is forced to keep
--     rolling) is not -- this engine has no generic onLockMove seam, and
--     reusing the rampage lock would wrongly add Outrage's confusion.
--     The player may stop early.
--   * ECHOEDVOICE: the ladder resets on a skipped turn; the real
--     pseudo-weather is field-wide and shared with a partner, which is
--     moot in singles.
--   * All of this is Gen 2 for the Shell Trap gate (registerFailGate runs
--     inside Battle:useMove); the charge/power halves work on both gens.
return function(mod)
  local registerPowerOverride = mod.exports.registerPowerOverride
  local isGen2Battle = mod.exports.isGen2Battle
  local registerFailGate = mod.exports.registerFailGate
  assert(registerPowerOverride,
    "modern_charge_moves: combat/modern_combat.lua must load first")

  local Strings = require("src.core.Strings")

  ------------------------------------------------------------------
  -- Consecutive-use counters (ICE BALL / ROLLOUT / ECHOED VOICE) plus the
  -- Defense Curl marker the two rolling moves read. All are set on the
  -- real `battle.move_used` event -- NEVER inside a power override, which
  -- the AI also runs to preview a candidate move (the exact double-count
  -- trap modern_power_conditions.lua's own Fury Cutter comment names).
  -- `battle.__g9TurnIndex` is modern_power_conditions.lua's monotonic
  -- per-battle turn counter (bumped on every battle.turn_started); it is
  -- reused here rather than re-invented.
  ------------------------------------------------------------------
  mod.events:on("battle.move_used", function(ev)
    local battle, user = ev and ev.battle, ev and ev.user
    if not (battle and user) then return end
    local moveId = (ev.move and ev.move.id) or ev.moveId
    if not moveId then return end

    if moveId == "DEFENSECURL" then
      user.__g9DefenseCurl = true
      return
    end

    local turn = battle.__g9TurnIndex or 0
    local function step(usesField, turnField)
      if user[turnField] and (turn - user[turnField]) <= 1 then
        user[usesField] = (user[usesField] or 1) + 1
      else
        user[usesField] = 1
      end
      user[turnField] = turn
    end
    if moveId == "ICEBALL" then
      step("__g9IceBallUses", "__g9IceBallTurn")
    elseif moveId == "ROLLOUT" then
      step("__g9RolloutUses", "__g9RolloutTurn")
    elseif moveId == "ECHOEDVOICE" then
      -- Field-wide pseudo-weather (Showdown's field.pseudoWeather), so the
      -- counter lives on the battle, not on the user.
      if battle.__g9EchoedVoiceTurn and (turn - battle.__g9EchoedVoiceTurn) <= 1 then
        battle.__g9EchoedVoiceMult = math.min(5, (battle.__g9EchoedVoiceMult or 1) + 1)
      else
        battle.__g9EchoedVoiceMult = 1
      end
      battle.__g9EchoedVoiceTurn = turn
    end
  end)

  ------------------------------------------------------------------
  -- The charge records. `kind = "full"` with only a `charge` table is the
  -- exact shape combat/modern_weather.lua's GALAR_SOLARBEAM_EFFECT uses;
  -- Gen 2's separate Effects.CHARGE table gets the matching announce text
  -- (Gen 1's announce text is keyed by move id in BattleState's own
  -- CHARGE_TEXT, which cannot be extended from a mod, so a modern charge
  -- move falls back to the engine's generic "%s is charging up!" line --
  -- cosmetic only).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_SOLARBLADE_EFFECT", {
    kind = "full",
    charge = { anim = "XSTATITEM_ANIM", enemyAnim = "XSTATITEM_DUPLICATE_ANIM" },
  })
  mod.content.move_effects:register("GALAR_METEORBEAM_EFFECT", {
    kind = "full",
    charge = { anim = "XSTATITEM_ANIM", enemyAnim = "XSTATITEM_DUPLICATE_ANIM" },
  })
  mod.content.move_effects:register("GALAR_SKYDROP_EFFECT", {
    kind = "full",
    charge = { invulnerable = true, anim = "TELEPORT" },
  })
  local gen2Ok_Gen2Effects, Gen2Effects = pcall(require, "src.battle.gen2.Effects")
  Gen2Effects = gen2Ok_Gen2Effects and Gen2Effects or nil
  if Gen2Effects then
    Gen2Effects.CHARGE.GALAR_SOLARBLADE_EFFECT = { text = "%s is charging its blade!" }
    Gen2Effects.CHARGE.GALAR_METEORBEAM_EFFECT = { text = "%s is overflowing with space power!" }
    Gen2Effects.CHARGE.GALAR_SKYDROP_EFFECT = { text = "%s took the target into the sky!", vanish = true }
  end

  ------------------------------------------------------------------
  -- The power ladder for the two rolling moves: 30, 60, 120, 240, 480 --
  -- `30 * 2 ** (uses - 1)`, capped at five uses (Showdown's hitCount < 5
  -- gate), doubled once more while Defense Curl is still up.
  ------------------------------------------------------------------
  local function bp(ctx, fallback)
    local p = ctx.move and ctx.move.power
    if type(p) == "number" and p > 0 then return p end
    return fallback
  end
  local function rollingPower(ctx, usesField)
    local uses = math.min(5, math.max(1, ctx.user[usesField] or 1))
    local power = 30 * (2 ^ (uses - 1))
    if ctx.user.__g9DefenseCurl then power = power * 2 end
    return power
  end
  registerPowerOverride("ICEBALL", function(ctx)
    return rollingPower(ctx, "__g9IceBallUses")
  end)
  registerPowerOverride("ROLLOUT", function(ctx)
    return rollingPower(ctx, "__g9RolloutUses")
  end)

  ------------------------------------------------------------------
  -- Echoed Voice: 40 * the field multiplier, 1..5 -> 40..200. Clamped
  -- exactly as Showdown's `if (multiplier < 5) multiplier++`.
  ------------------------------------------------------------------
  registerPowerOverride("ECHOEDVOICE", function(ctx)
    local mult = math.min(5, math.max(1, ctx.battle.__g9EchoedVoiceMult or 1))
    return bp(ctx, 40) * mult
  end)

  ------------------------------------------------------------------
  -- Solar Blade: onBasePower chainModify(0.5) in the weak weathers
  -- (rain/sand/snow -- Showdown's weakWeathers list). Mega Sol is a
  -- personal "as if sun" override, so it exempts the user even when the
  -- field weather is weak, the same carve-out Synthesis heals already use.
  ------------------------------------------------------------------
  local WEAK_WEATHER = { RAIN = true, SAND = true, SNOW = true }
  registerPowerOverride("SOLARBLADE", function(ctx)
    local currentWeather = mod.exports.currentWeather
    local weather = currentWeather and currentWeather(ctx.battle, ctx.gen2)
    local abilityIdOf = mod.exports.abilityIdOf
    if abilityIdOf and abilityIdOf(ctx.user) == "MEGASOL" then weather = "SUN" end
    local power = bp(ctx, 125)
    if weather and WEAK_WEATHER[weather] then
      power = math.max(1, math.floor(power / 2))
    end
    return power
  end)

  ------------------------------------------------------------------
  -- Meteor Beam: the Sp. Atk +1 on the charge turn. Extracted as an
  -- exported, unit-testable helper (the harness calls it directly) and
  -- driven from the real `battle.charge_required` hook -- that hook is
  -- called on the charge turn only, since the release turn is already
  -- `releasing` and never reaches the charge branch.
  ------------------------------------------------------------------
  -- Keyed by move id AND by the repointed effect string: Gen 1's
  -- battle.charge_required payload carries the move ARGUMENT (which has
  -- `.id`), while Gen 2's carries the move DEF (`self.data.moves[moveId]`),
  -- which may only expose `.effect`. Both spellings answer, so the boost
  -- fires on each generation regardless of which field is present.
  local CHARGE_TURN_BONUS = {
    METEORBEAM = { stat = "spa", delta = 1 },
    GALAR_METEORBEAM_EFFECT = { stat = "spa", delta = 1 },
  }
  function mod.exports.applyChargeTurnBonus(battle, user, moveId)
    local def = CHARGE_TURN_BONUS[moveId]
    if not (def and battle and user) then return false end
    local changeStage = mod.exports.changeStage
    if not changeStage then return false end
    local gen2 = isGen2Battle and isGen2Battle(battle) or false
    -- changeStage returns a message list; there is no say-channel on this
    -- hook, so the boost is applied silently (the stats screen and every
    -- downstream damage read still see it).
    local ok = pcall(changeStage, battle, user, def.stat, def.delta, false, gen2)
    return ok
  end
  mod.hooks:wrap("battle.charge_required", function(nextFn, ctx)
    if ctx and ctx.move then
      mod.exports.applyChargeTurnBonus(ctx.battle, ctx.user, ctx.move.id or ctx.move.effect)
    end
    return nextFn(ctx)
  end)

  ------------------------------------------------------------------
  -- Shell Trap / Beak Blast: both arm at the START of the turn from the
  -- chosen action (battle.turn_started's payload carries both sides'
  -- choices before either acts), then react as the turn unfolds.
  --   Shell Trap (moves.ts:16277): any opponent PHYSICAL hit sets the
  --     `hit` flag; the move's own fail gate then lets it fire only if
  --     that flag is set (otherwise it "can't be used").
  --   Beak Blast (moves.ts:1119): any mon that makes CONTACT with the
  --     armed user is burned.
  ------------------------------------------------------------------
  local function actionMoveId(action)
    if type(action) == "string" then return action end
    if type(action) ~= "table" then return nil end
    if action.kind and action.kind ~= "move" then return nil end
    return action.move or action.id
  end
  local function arm(battle)
    if not battle then return end
    local fn = mod.exports.allActiveBattlers
    local list = (fn and fn(battle)) or { battle.player, battle.enemy }
    for _, m in ipairs(list) do
      if m then
        m.__g9BeakBlastArmed = nil
        m.__g9ShellTrapArmed = nil
        m.__g9ShellTrapHit = nil
      end
    end
    local function armMon(mon, action)
      if not mon then return end
      local id = actionMoveId(action)
      if id == "BEAKBLAST" then mon.__g9BeakBlastArmed = true end
      if id == "SHELLTRAP" then mon.__g9ShellTrapArmed = true end
    end
    armMon(battle.player, battle.__g9PlayerAction or (battle.turnActions and battle.turnActions.player))
    armMon(battle.enemy, battle.__g9EnemyAction or (battle.turnActions and battle.turnActions.enemy))
  end
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    -- The payload's own action copies (both spellings carried by the
    -- engine, see gen2-Battle.lua:4807 / BattleState's own emit).
    battle.__g9PlayerAction = ev.playerAction
    battle.__g9EnemyAction = ev.enemyAction
    arm(battle)
  end)

  local function moveIsPhysical(battle, moveId, move)
    if move and move.category then
      local c = move.category
      return c == "physical" or c == "Physical"
    end
    if not moveId then return false end
    local ok, def = pcall(function() return battle:moveDef(moveId) end)
    local MoveCategory = mod.exports.MoveCategory
    if ok and def and MoveCategory and MoveCategory.of then
      local ok2, cat = pcall(MoveCategory.of, def)
      return ok2 and cat == "Physical"
    end
    return false
  end

  mod.events:on("battle.damage_dealt", function(ev)
    local battle, target, user = ev and ev.battle, ev and ev.target, ev and ev.user
    local moveId = ev and (ev.moveId or (ev.move and ev.move.id))
    if not (battle and target and user and moveId) then return end
    if (ev.damage or 0) <= 0 then return end
    if user == target then return end

    -- Shell Trap: a physical hit from the other side arms its release.
    if target.__g9ShellTrapArmed and moveIsPhysical(battle, moveId, ev.move) then
      target.__g9ShellTrapHit = true
    end

    -- Beak Blast: a contact hit against the armed user burns the attacker.
    if target.__g9BeakBlastArmed then
      local makesContact = mod.exports.makesContact
      if makesContact and makesContact(moveId, user) and battle.applyStatus then
        pcall(function() battle:applyStatus(user, "burn", "BEAKBLAST") end)
      end
    end
  end)

  if registerFailGate then
    registerFailGate("SHELLTRAP", function(battle, attacker, defender, moveId)
      if attacker and attacker.__g9ShellTrapHit then return nil end
      return "fail"
    end)
  end

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local fn = mod.exports.allActiveBattlers
    local list = (fn and fn(battle)) or { battle.player, battle.enemy }
    for _, m in ipairs(list) do
      if m then
        m.__g9BeakBlastArmed = nil
        m.__g9ShellTrapArmed = nil
        m.__g9ShellTrapHit = nil
      end
    end
    battle.__g9PlayerAction = nil
    battle.__g9EnemyAction = nil
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    if battle then battle.__g9EchoedVoiceMult = nil; battle.__g9EchoedVoiceTurn = nil end
    if ev and ev.previous then
      ev.previous.__g9BeakBlastArmed = nil
      ev.previous.__g9ShellTrapArmed = nil
      ev.previous.__g9ShellTrapHit = nil
    end
    if ev and ev.battler then
      ev.battler.__g9BeakBlastArmed = nil
      ev.battler.__g9ShellTrapArmed = nil
      ev.battler.__g9ShellTrapHit = nil
    end
  end)

  mod.log:info("g9-battle-engine: modern_charge_moves installed (Solar Blade / Meteor Beam / Sky Drop charge, Ice Ball / Rollout / Echoed Voice power ladders, Shell Trap / Beak Blast)"
    .. (registerFailGate and "" or " [WARN: registerFailGate missing, Shell Trap gate skipped]"))
end
