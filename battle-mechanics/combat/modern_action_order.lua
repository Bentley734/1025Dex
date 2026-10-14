-- Phase 5 of the missing-effects pipeline: action order and chosen-move
-- visibility.
--
-- Showdown source of truth (scratch/showdown/moves.ts -- verified by direct
-- read this session, line numbers cited per clause):
--   suckerpunch (18397-18407): priority 1, Dark, Physical. `onTry`:
--     const action = this.queue.willMove(target);
--     const move = action?.choice === 'move' ? action.move : null;
--     if (!move || (move.category === 'Status' && move.id !== 'mefirst')
--         || target.volatiles['mustrecharge']) return false;
--     i.e. FAILS unless the target is STILL QUEUED to move this turn with
--     a chosen move that is not a Status move (Me First is the one
--     Status-move exception), and the target is not recharging.
--   thunderclap (19498-19508): priority 1, Electric, SPECIAL, identical
--     `onTry` to suckerpunch.
--   upperhand (20188-20202): priority 3, Fighting, Physical, and its
--     `onTry` is the stricter sibling:
--     if (!move || move.priority <= 0.1 || move.category === 'Status')
--       return false;
--     i.e. FAILS unless the target chose a move whose BASE priority is
--     strictly positive (Prankster-family modifiers do not count here --
--     `.priority` on the move record is the base). Its own
--     `secondary: { chance: 100, volatileStatus: 'flinch' }` is NOT
--     re-implemented here: main.lua's generic installMovepoolEffects
--     listener already applies any national_dex record's flinchChance
--     (UPPERHAND/FAKEOUT both carry flinchChance 100 -- national_dex
--     api/020.lua:32, api/006.lua:22) after a landed non-zero hit, and
--     neither id is in GENERIC_SECONDARY_EXEMPT, so that path owns the
--     flinch end to end.
--   fakeout (5088-5098): priority 3, Normal, Physical; `onTry(source)`
--     returns false when `source.activeMoveActions > 1`. Showdown
--     increments activeMoveActions at the TOP of runMove
--     (battle-actions.ts:217), so during Fake Out's own onTry the count
--     already INCLUDES this use. This file's gate, however, runs BEFORE
--     native useMove emits battle.move_used, so __g9MoveActions holds
--     COMPLETED action only -- the faithful test is therefore
--     `completed > 0`, exactly as modern_side_protection.lua's own
--     FIRSTIMPRESSION gate documents for the same seam (an earlier `> 1`
--     here was an off-by-one that let Fake Out fire again on the second
--     action since switch-in). Fake Out works only on the very first
--     action after entering the field, exactly as the national_dex prose
--     says (api/006.lua:22: "Can only be used on the user's first turn
--     after entering the field").
--   focuspunch (6002-6030): priority -3, Fighting, Physical. Its
--     `condition.onHit` sets `lostFocus = true` when `move.category !==
--     'Status'` (i.e. when the user is struck by a DAMAGING move this
--     turn), and `beforeMoveCallback` fails the move with
--     `this.add('cant', pokemon, 'Focus Punch', 'Focus Punch')` when
--     lostFocus is set. Damage FROM A MOVE is what matters -- residual
--     chip (burn/sand/hazards) never fires onHit -- which is why this
--     file tracks a dedicated `__g9LostFocus` off `battle.damage_dealt`
--     entries that carry a moveId, rather than reusing the broader
--     `damagedThisTurn` flag modern_combat.lua keeps for Assurance.
--   afteryou (195-214): Status, Normal. `onHit(target)`:
--     if (this.activePerHalf === 1) return false;              // singles
--     const action = this.queue.willMove(target);
--     if (action) this.queue.prioritizeAction(action);
--     else return false;
--     => fails outright in singles (one active per half); otherwise makes
--     the target act NEXT; fails when the target has already acted.
--   quash (14455-14474): Status, Dark. `onHit(target)`:
--     if (this.activePerHalf === 1) return false;              // singles
--     const action = this.queue.willMove(target);
--     if (!action) return false;
--     action.order = 201;                                       // last
--     => fails in singles; otherwise forces the target to act LAST;
--     fails when the target has already acted.
--
-- ENGINE SEAMS (both already exist; this file adds no second turn model):
--   * combat/turn_order.lua's resolveTurnActions publishes
--     battle.__g9ChosenMoves at the top of each turn and clears a mon's
--     entry as its action resolves; mod.exports.chosenMoveOf reads it.
--     For the NATIVE battle loop (which never calls resolveTurnActions),
--     this file wraps the "battle.turn_order" hook instead -- the one
--     pre-move moment native exposes both chosen move ids as
--     ctx.playerMove/ctx.enemyMove (base-gen2-Battle.lua:4832-4837) --
--     and publishes the same map.
--   * mod.exports.prioritizeActor / deprioritizeActor (turn_order.lua)
--     splice a still-pending actor in the live `ordered` list. In native
--     2-battler battles there is no such list, so After You/Quash fail
--     there -- honest-partial, and identical to their real singles
--     behaviour anyway (no ally to speed up, no third battler to quash).
--
-- The FAIL GATE is a Battle:useMove wrap, deliberately the same shape
-- combat/modern_combat_protect.lua's Part D uses: on a failed gate we
-- temporarily replace Battle.moveEffectRecordFor so the move's own
-- dispatch returns a kind="primary" record with a `run` that emits the
-- fail line and marks the move missed -- which means PP is still spent
-- and "X used Y!" is still announced first, exactly like Showdown
-- (a move that passes onTry=false still announced its use). On a PASS
-- the native pipeline runs completely untouched. This file boots after
-- modern_combat_protect, so `nativeUseMove` here is that file's wrap and
-- the two compose (Part D still own its own protected-target branch).
--
-- Gen 1: inert. The five gated moves are modern ids and this mod's
-- production target is Gen 2 only; nothing here is generation-gated
-- beyond that because none of it fires for a Gen 1 move set.
return function(mod)
  local chosenMoveOf = mod.exports.chosenMoveOf
  local prioritizeActor = mod.exports.prioritizeActor
  local deprioritizeActor = mod.exports.deprioritizeActor
  local MoveCategory = mod.exports.MoveCategory
  assert(chosenMoveOf and prioritizeActor and deprioritizeActor,
    "modern_action_order: combat/turn_order.lua (phase 5 exports) must load first")
  local Strings = require("src.core.Strings")
  -- Gen 1 has no Gen-2 Battle class, and the sandbox's cross-generation require
  -- denial refuses the name there (src/mods/Loader.lua crossGenerationDenial).
  -- That used to abort this WHOLE file's boot on Gen 1, taking its round-100
  -- selection-time gates AND its __g9MoveActions bookkeeping with it -- which is
  -- exactly why Fake Out stayed pickable past the first turn on Gen 1. Guarded
  -- the way modern_combat.lua guards its own gen2 require: `Battle` is nil on
  -- Gen 1, the useMove fail wrap below is skipped (Gen 1 resolves through
  -- BattleState:performMove, a path that wrap never covered anyway), and every
  -- other thing in this file -- the event bookkeeping and the
  -- registerMoveUsabilityGate calls -- still installs on both generations.
  local gen2Ok, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok and Battle or nil

  -- ------------------------------------------------------------------
  -- A mon's display name, tolerant of every battle shape this mod runs
  -- in (displayNameFor is the mod's own canonical helper; monName is
  -- native; a bare name is the last resort for a unit test).
  -- ------------------------------------------------------------------
  local function nameOf(battle, mon)
    local displayNameFor = mod.exports.displayNameFor
    if displayNameFor then
      local ok, n = pcall(displayNameFor, battle, mon, true)
      if ok and n then return n end
    end
    if battle and battle.monName then
      local ok, n = pcall(function() return battle:monName(mon) end)
      if ok and n then return n end
    end
    return (mon and (mon.name or mon.species)) or "The Pokemon"
  end

  -- ------------------------------------------------------------------
  -- activeBattlerCount(battle): the real N-way roster size. Showdown's
  -- After You/Quash singles-fail gate is `activePerHalf === 1`; this
  -- engine's only multi-battler consumer is g9-Battle-Scene, so "<= 2
  -- total active" is the same test in every real format this mod ships.
  -- ------------------------------------------------------------------
  local function activeBattlerCount(battle)
    local fn = mod.exports.allActiveBattlers
    if not fn then return 2 end
    local ok, list = pcall(fn, battle)
    if not ok or type(list) ~= "table" then return 2 end
    return #list
  end

  -- ------------------------------------------------------------------
  -- firstTurnOutBlocked(mon): the single Fake Out / First Impression
  -- condition. Read by BOTH this file's resolution fail gate below and the
  -- selection-time usability gate at the bottom of this file (round 100,
  -- combat/move_usability.lua) so the menu and the resolution can never
  -- disagree. Showdown's fakeout.onTry is `source.activeMoveActions > 1`
  -- (moves.ts:5098); this seam runs BEFORE native useMove emits
  -- battle.move_used, so __g9MoveActions holds COMPLETED actions only and
  -- the faithful test is `completed > 0`.
  -- ------------------------------------------------------------------
  local function firstTurnOutBlocked(attacker)
    -- Unwrap a Gen-1 battler wrapper: the bookkeeping below stores this on the
    -- RAW mon, which is the same table combat/move_usability.lua's rawMon()
    -- resolves the scene's battler to, so the menu gate and the counter agree
    -- on both generations (Gen 2 hands this a raw mon already -- idempotent).
    local m = attacker and (attacker.mon or attacker) or nil
    return (m and m.__g9MoveActions or 0) > 0
  end

  -- ------------------------------------------------------------------
  -- actionGateReason(battle, attacker, defender, moveId) -> nil | "fail"
  -- | "focus". nil means the move proceeds normally. Pure (no side
  -- effects), exported so the test harness can exercise every branch
  -- without standing up the whole damage pipeline.
  -- ------------------------------------------------------------------
  local function gateReason(battle, attacker, defender, moveId)
    if not (battle and attacker and defender and moveId) then return nil end

    -- Showdown's `this.queue.willMove(target)?.move`, with the target's
    -- move record alongside it. A target that already acted this turn
    -- has been cleared out of __g9ChosenMoves, so this reads nil and the
    -- move fails, matching willMove returning null for a spent action.
    local function pending()
      local id = chosenMoveOf(battle, defender)
      if not id then return nil end
      local ok, def = pcall(function() return battle:moveDef(id) end)
      if not ok then def = nil end
      return id, def
    end
    local function categoryIsStatus(def)
      if not (MoveCategory and MoveCategory.of) then return false end
      local ok, cat = pcall(MoveCategory.of, def)
      return ok and cat == "Status"
    end

    if moveId == "SUCKERPUNCH" or moveId == "THUNDERCLAP" then
      local pendId, pendDef = pending()
      if not pendId then return "fail" end
      -- Status moves are not "an attack" to punish; Me First is the one
      -- real exception (moves.ts:18401 `move.id !== 'mefirst'`).
      if categoryIsStatus(pendDef) and pendId ~= "MEFIRST" then return "fail" end
      -- target.volatiles['mustrecharge'] (moves.ts:18402).
      local vol = battle.volatile and battle:volatile(defender) or nil
      if defender.recharge or (vol and vol.recharge) then return "fail" end
      return nil
    end

    if moveId == "UPPERHAND" then
      local pendId, pendDef = pending()
      if not pendId then return "fail" end
      if categoryIsStatus(pendDef) then return "fail" end
      -- `move.priority` is the BASE priority on the record, so call the
      -- unmodified base (no caster -> no priority modifiers) -- a
      -- Prankster-boosted status move does not satisfy Upper Hand.
      local ok, prio = pcall(function() return battle:movePriority(pendId) end)
      if not ok or type(prio) ~= "number" or prio <= 0 then return "fail" end
      return nil
    end

    if moveId == "FAKEOUT" then
      -- Showdown's fakeout.onTry: `source.activeMoveActions > 1`
      -- (moves.ts:5098), the exact same test First Impression uses -- now
      -- owned by firstTurnOutBlocked above so this gate and the
      -- selection-time usability gate register the identical predicate.
      if firstTurnOutBlocked(attacker) then return "fail" end
      return nil
    end

    if moveId == "FOCUSPUNCH" then
      if attacker.__g9LostFocus then return "focus" end
      return nil
    end

    return nil
  end
  mod.exports.actionGateReason = gateReason

  -- ------------------------------------------------------------------
  -- SELECTION-TIME GATE (round 100): the same Fake Out condition, answered
  -- for a battle scene BEFORE the move is picked -- see combat/
  -- move_usability.lua's own header. This is why the predicate above is a
  -- named local. Guarded because it is exported by a sibling that boots
  -- earlier; a trimmed/older boot simply skips it and keeps the
  -- resolution-time failure this file has always had.
  -- ------------------------------------------------------------------
  local registerMoveUsabilityGate = mod.exports.registerMoveUsabilityGate
  if registerMoveUsabilityGate then
    registerMoveUsabilityGate("FAKEOUT", function(battle, mon)
      if firstTurnOutBlocked(mon) then
        return { flag = "condition",
          reason = Strings("Fake Out only works on the user's first turn out!") }
      end
      return nil
    end)
  end

  -- ------------------------------------------------------------------
  -- Lifecycle bookkeeping every gate above reads.
  --   __g9MoveActions -- per mon, reset on switch-in. Incremented for
  --     EVERY move it runs, matching Showdown's runMove (called moves
  --     included).
  --   __g9LostFocus -- per mon, set when a MOVE-owned damaging hit
  --     lands on it this turn, cleared at turn start. The `moveId` guard
  --     is what keeps burn/sand/hazard chip (which carries no moveId)
  --     from cancelling Focus Punch, matching Showdown's onHit-only
  --     lostFocus (moves.ts:6022).
  -- ------------------------------------------------------------------
  mod.events:on("battle.move_used", function(ev)
    local battle = ev and ev.battle
    local moved = ev and ev.user
    -- Normalize to the RAW mon: on Gen 1 the emit carries a battler wrapper
    -- (`.mon`), and the selection gate reads the raw mon. On Gen 2 it is the
    -- raw mon already.
    local user = moved and (moved.mon or moved) or nil
    if not (battle and user) then return end
    -- This mon is moving (or being called to move), so it is no longer
    -- "about to move" -- Showdown splices its action out of the queue.
    if battle.__g9ChosenMoves then battle.__g9ChosenMoves[user] = nil end
    user.__g9MoveActions = (user.__g9MoveActions or 0) + 1
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local incoming = ev and ev.battler
    local outgoing = ev and ev.previous
    incoming = incoming and (incoming.mon or incoming) or nil
    outgoing = outgoing and (outgoing.mon or outgoing) or nil
    if incoming then incoming.__g9MoveActions = 0 end
    if outgoing then outgoing.__g9MoveActions = nil end
  end)

  mod.events:on("battle.damage_dealt", function(ev)
    if not (ev and ev.target) then return end
    local moveId = ev.moveId or (ev.move and ev.move.id)
    if not moveId then return end
    if (ev.damage or 0) <= 0 then return end
    local target = ev.target.mon or ev.target
    target.__g9LostFocus = true
  end)

  local function resetTurnFlags(battle)
    if not battle then return end
    local fn = mod.exports.allActiveBattlers
    local list = (fn and fn(battle)) or { battle.player, battle.enemy }
    for _, who in ipairs(list) do
      local m = who and (who.mon or who) or nil
      if m then m.__g9LostFocus = false end
    end
  end
  mod.events:on("battle.turn_started", function(ev) resetTurnFlags(ev and ev.battle) end)
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local fn = mod.exports.allActiveBattlers
    local list = (fn and fn(battle)) or { battle.player, battle.enemy }
    for _, who in ipairs(list) do
      local m = who and (who.mon or who) or nil
      if m then m.__g9MoveActions = 0; m.__g9LostFocus = false end
    end
  end)

  -- ------------------------------------------------------------------
  -- NATIVE chosen-move publication. The native Gen 2 loop decides the
  -- whole turn once, through the "battle.turn_order" hook, and that call
  -- is handed both chosen move ids (ctx.playerMove / ctx.enemyMove --
  -- base-gen2-Battle.lua:4832-4837). Published here so Sucker
  -- Punch/Upper Hand can read the target's choice in a non-scene battle
  -- too; a scene-driven battle gets its map from resolveTurnActions
  -- instead. RESET (not merged) each turn so a stale previous-turn entry
  -- cannot linger.
  -- ------------------------------------------------------------------
  mod.hooks:wrap("battle.turn_order",
    function(nextFn, playerBattler, playerMoveDef, enemyBattler, enemyMoveDef, ctx)
      local battle = ctx and ctx.battle
      if battle then
        local map = {}
        if battle.player and ctx.playerMove then map[battle.player] = ctx.playerMove end
        if battle.enemy and ctx.enemyMove then map[battle.enemy] = ctx.enemyMove end
        battle.__g9ChosenMoves = map
      end
      return nextFn(playerBattler, playerMoveDef, enemyBattler, enemyMoveDef, ctx)
    end)

  -- ------------------------------------------------------------------
  -- THE FAIL GATE. Same wrap shape as combat/modern_combat_protect.lua
  -- Part D (see that file's own comment block for why a useMove wrap is
  -- the right level): substitute moveEffectRecordFor only for the
  -- duration of this one native call, and only when the gate failed.
  -- ------------------------------------------------------------------
  local GATED = {
    SUCKERPUNCH = true, THUNDERCLAP = true, UPPERHAND = true,
    FAKEOUT = true, FOCUSPUNCH = true,
  }
  -- Reusable fail-gate seam: any later file can arm an arbitrary move to
  -- fail through this exact wrap (announced, PP spent, marked missed,
  -- "But it failed!"/custom text) instead of writing a second useMove
  -- wrap. `fn(battle, attacker, defender, moveId)` returns nil to let the
  -- move proceed, or a reason string ("fail", or "focus" for the
  -- Focus-Punch-style message) to fail it. Phase 6's LAST RESORT is the
  -- first consumer.
  local extraGates = {}
  function mod.exports.registerFailGate(id, fn)
    assert(type(id) == "string" and type(fn) == "function",
      "registerFailGate: (moveId, fn) required")
    extraGates[id] = fn
  end
  -- Read-only accessor so the verification probe (and any future test) can
  -- exercise a registered gate directly, without driving a whole move
  -- through the native pipeline. No production caller reads this.
  function mod.exports.failGateOf(id) return extraGates[id] end

  -- Gen 2 only: the native useMove wrap. Skipped entirely when the Gen-2 class
  -- is absent (Gen 1), so nothing here dereferences a nil class.
  if Battle then
  local nativeUseMove = Battle.useMove
  function Battle:useMove(attacker, defender, moveId)
    if not GATED[moveId] and not extraGates[moveId] then
      return nativeUseMove(self, attacker, defender, moveId)
    end
    local reason
    local ok = pcall(function()
      reason = gateReason(self, attacker, defender, moveId)
      if not reason and extraGates[moveId] then
        reason = extraGates[moveId](self, attacker, defender, moveId)
      end
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: modern_action_order: gate errored for %s",
        tostring(moveId))
      return nativeUseMove(self, attacker, defender, moveId)
    end
    if not reason then
      return nativeUseMove(self, attacker, defender, moveId)
    end
    local def = self:moveDef(moveId)
    local gatedEffect = def and def.effect
    if not gatedEffect then
      return nativeUseMove(self, attacker, defender, moveId)
    end
    local msg = (reason == "focus")
      and (Strings("%s lost its focus and couldn't move!", nameOf(self, attacker)))
      or Strings("But it failed!")
    local prevRecordFor = Battle.moveEffectRecordFor
    Battle.moveEffectRecordFor = function(data, effect)
      if effect == gatedEffect then
        return {
          kind = "primary",
          run = function(battle)
            -- Mark missed so the screen skips the move animation, the
            -- same way native's own counter/Dream Eater fail paths do
            -- (base-gen2-Battle.lua markMissed), then say why.
            if battle.markMissed then
              battle:markMissed()
            elseif battle.moveEvent then
              battle.moveEvent.missed = true
            end
            battle:emit({ kind = "message", text = msg })
          end,
        }
      end
      return prevRecordFor(data, effect)
    end
    local callOk, callErr = pcall(nativeUseMove, self, attacker, defender, moveId)
    Battle.moveEffectRecordFor = prevRecordFor
    if not callOk then
      mod.log:warn("g9-battle-engine: modern_action_order: gated dispatch errored (%s)",
        tostring(callErr))
      error(callErr, 0)
    end
  end
  end -- if Battle

  -- ------------------------------------------------------------------
  -- After You / Quash: real live reorder through turn_order.lua's
  -- prioritizeActor/deprioritizeActor. Both are Status moves with power
  -- 0, so a kind="primary" record with a `run` intercepts before the
  -- damage path exactly like GMAX_ATTRACT_EFFECT. Messages are emitted
  -- directly (the engine's dispatch discards a handler's return value).
  -- ------------------------------------------------------------------
  local function repositionRun(mode)
    return function(battle, attacker, defender)
      if not (battle and attacker and defender) then
        return
      end
      -- Showdown: fails in singles (activePerHalf === 1).
      if activeBattlerCount(battle) <= 2 then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      local fn = (mode == "next") and prioritizeActor or deprioritizeActor
      local ok = fn and fn(battle, defender)
      if not ok then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      battle:emit({ kind = "message",
        text = (mode == "next")
          and Strings("%s is ready to go next!", nameOf(battle, defender))
          or Strings("%s was quashed!", nameOf(battle, defender)) })
    end
  end
  local function registerReposition(id, effectId, mode)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      accuracyChecked = true,
      run = repositionRun(mode),
    })
    mod.content.moves:patch(id, { effect = effectId })
  end
  registerReposition("AFTERYOU", "GALAR_AFTERYOU_EFFECT", "next")
  registerReposition("QUASH", "GALAR_QUASH_EFFECT", "last")

  mod.log:info("g9-battle-engine: modern_action_order installed "
    .. "(SUCKERPUNCH, THUNDERCLAP, UPPERHAND, FAKEOUT, FOCUSPUNCH gates; "
    .. "AFTERYOU, QUASH reorder)")
end
