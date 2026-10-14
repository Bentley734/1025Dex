-- Target-directed force switch-out ("drag"): DRAGON TAIL, CIRCLE THROW.
--
-- Showdown source of truth (scratch/showdown/moves.ts):
--   dragontail  (line 4209-4221, num 525, 60 BP Physical, priority -6)
--     and circlethrow (line 2451-2463, num 509, 60 BP Physical, priority -6)
--     each carry exactly one extra flag in common with Roar/Whirlwind:
--     `forceSwitch: true`.
--   The generic handler is BattleActions#forceSwitch
--   (battle-actions.ts:1353-1366): for every target still at hp > 0, with
--   the source also at hp > 0 and `battle.canSwitch(target.side)` true, it
--   fires runEvent('DragOut', target, source, move); if that does not
--   return a falsy block, it sets `target.forceSwitchFlag = true`. Step 6
--   of spreadMoveHit (battle-actions.ts:1103-1104) runs it only after the
--   hit has actually landed (a missed/immune target is already `false`).
--   `canSwitch` (battle.ts:1566-1568) is `possibleSwitches(side).length`,
--   and possibleSwitches (battle.ts:1577-1584) is every NON-FAINTED bench
--   mon -- in this singles engine, exactly one living bench mon.
--
-- The only real difference from Roar/Whirlwind is WHY those two are not
-- handled here: they are native Gen 2 moves with a working
-- Battle.MOVE_EFFECTS.EFFECT_FORCE_SWITCH handler
-- (base-gen2-Battle.lua:2917-2988) that already drags a random bench mon
-- out, and whose "the user must be moving second" arm is the REAL Gen 2
-- rule. Dragon Tail / Circle Throw are Gen 5 moves national_dex leaves at
-- EFFECT_NORMAL_HIT, so nothing native ever drags for them -- and their
-- real Gen 5+ rule has NO "move second" gate at all (they drag whenever
-- they land). This file therefore implements the drag itself rather than
-- re-pointing at the native effect.
--
-- Blocking, exactly as Showdown's DragOut event resolves it:
--   * Suction Cups (abilities.ts:4693-4699) and Guard Dog
--     (abilities.ts:1728-1734) each define `onDragOut` and return null,
--     so `if (hitResult)` is falsy and no drag happens -- for a DAMAGING
--     force-switch move only the DRAG is cancelled, the damage already
--     landed, which is why these two ids must NOT be added to
--     abilities/engine/prevent_misc.lua's FORCE_SWITCH_MOVES table (that
--     wrap cancels the whole move, correct for the status moves Roar/
--     Whirlwind but wrong for a damaging one).
--   * Ingrain (this mod's own GALAR_INGRAIN_EFFECT sets `n.user.ingrained`)
--     is the other real no-DragOut state.
--   * A Substitute does NOT block it: the substitute condition defines no
--     onDragOut (grepped: conditions.ts has exactly three onDragOut
--     handlers -- Dynamax, Commanded, Commanding), and neither does
--     this mod's own native Roar path, so drag-through-sub is the shipped
--     behavior on both sides of this mod.
--
-- Engine seam: the same one every self-switch move already uses. The
-- player side reuses mod.exports.requestSwitch (combat/switch_primitives
-- .lua) -- it sets the real, public battle.forcedSwitch flag and emits the
-- switch-request the scene consumes. The enemy side cannot use that
-- function's default pick (firstAliveBenchIndex) because Showdown drags a
-- RANDOM bench mon (battle-actions.ts:163 getRandomSwitchable), matching
-- the native Gen 2 force switch's own `bench[rand(self.random, #bench)+1]`
-- (base-gen2-Battle.lua:2963) -- so it calls the same
-- Battle:switchMonAtSide primitive switch_primitives.lua installs, with a
-- random pick. The record is `kind = "full"` with NO `run` field: Gen 2's
-- dispatch calls any record with a `.run` before its own damage path
-- (gen2/Battle.lua:1533-1538), which would pre-empt the hit -- the exact
-- bug modern_switch_moves.lua's own header documents. The drag fires from
-- a battle.damage_dealt listener instead, after a real, landed, non-zero
-- hit, which is the same "the hit actually landed" condition Showdown's
-- step-6 forceSwitch requires.
--
-- Gen 1: inert. switchMonAtSide/requestSwitch are Gen 2 machinery, and
-- this mod's production target is Gen 2 only; isGen2Battle gates it
-- rather than half-building a Gen 1 path.
return function(mod)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  assert(abilityIdOf and displayNameFor and isGen2Battle,
    "modern_force_switch: combat/modern_combat.lua must load first")

  local DRAG_MOVES = { DRAGONTAIL = true, CIRCLETHROW = true }

  -- possibleSwitches equivalent: every living, non-egg bench mon on the
  -- given party behind the given active index.
  local function benchOf(party, activeIndex)
    local bench = {}
    if type(party) ~= "table" then return bench end
    for i, mon in ipairs(party) do
      if i ~= activeIndex and (mon.hp or 0) > 0 and not mon.isEgg then
        bench[#bench + 1] = { index = i, mon = mon }
      end
    end
    return bench
  end
  mod.exports.forceSwitchBenchOf = benchOf

  -- The DragOut-event equivalents that return a falsy block. Each emits the
  -- real activation line, matching Showdown's `this.add('-activate', ...)`.
  local function dragBlocked(battle, target)
    local id = abilityIdOf(target)
    if id == "SUCTIONCUPS" then
      battle:emit({ kind = "message",
        text = Strings("%s's Suction Cups anchors it!", displayNameFor(battle, target, true)) })
      return true
    end
    if id == "GUARDDOG" then
      battle:emit({ kind = "message",
        text = Strings("%s's Guard Dog anchors it!", displayNameFor(battle, target, true)) })
      return true
    end
    if target.ingrained then
      battle:emit({ kind = "message",
        text = Strings("%s is anchored by its roots!", displayNameFor(battle, target, true)) })
      return true
    end
    return false
  end
  mod.exports.dragBlocked = dragBlocked

  -- The drag itself. Returns true when the target's side actually changed
  -- (enemy: immediately; player: the switch-request was raised), false on
  -- any real no-op (dead target, blocked, no bench).
  function mod.exports.forceDrag(battle, target, moveId)
    if not (battle and target) then return false end
    if not isGen2Battle(battle) then return false end
    if (target.hp or 0) <= 0 then return false end
    if dragBlocked(battle, target) then return false end
    local side = battle:sideOf(target)
    if side == "enemy" then
      local bench = benchOf(battle.enemyParty, battle.enemyIndex)
      if #bench == 0 then return false end
      -- Real Showdown pick (getRandomSwitchable -> sample), same shape as
      -- the native Gen 2 force switch's own random bench pick.
      local pick = bench[battle.random(#bench) + 1]
      if not (pick and battle.switchMonAtSide) then return false end
      local name = displayNameFor(battle, target, true)
      if not battle:switchMonAtSide("enemy", pick.index) then return false end
      battle:emit({ kind = "message", text = Strings("%s was dragged out!", name) })
      return true
    end
    -- Player side: requestSwitch raises the real forced-switch request the
    -- running scene consumes (its own bench guard returns false when there
    -- is nothing to send in).
    local requestSwitch = mod.exports.requestSwitch
    if not requestSwitch then return false end
    if #benchOf(battle.party, battle.playerIndex) == 0 then return false end
    local name = displayNameFor(battle, target, true)
    return requestSwitch(battle, target, { reason = moveId,
      text = Strings("%s was dragged out!", name) }) and true or false
  end

  for id in pairs(DRAG_MOVES) do
    local effectId = "GALAR_DRAG_" .. id
    mod.content.move_effects:register(effectId, { kind = "full" })
    mod.content.moves:patch(id, { effect = effectId })
  end

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and (ev.moveId or (ev.move and ev.move.id))
    local target = ev and ev.target
    local user = ev and ev.user
    if not (battle and moveId and DRAG_MOVES[moveId] and target) then return end
    -- Step-6 condition: a landed, non-zero, non-immune hit.
    if (ev.damage or 0) <= 0 then return end
    if user and (user.hp or 0) <= 0 then return end
    local ok, err = pcall(function() mod.exports.forceDrag(battle, target, moveId) end)
    if not ok then
      mod.log:warn("g9-battle-engine: modern_force_switch drag failed: %s", tostring(err))
    end
  end)

  mod.log:info("g9-battle-engine: modern_force_switch installed (DRAGONTAIL, CIRCLETHROW)")
end
