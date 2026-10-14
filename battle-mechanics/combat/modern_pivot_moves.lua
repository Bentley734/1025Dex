-- Phase 20 of the missing-effects pipeline: pivots (self-switch moves whose
-- bench pick matters) and move-copying. The 11 moves here split into four
-- genuinely different shapes, so this file is organized by shape, not by
-- move order:
--
--   PIVOTS (Baton Pass, Shed Tail, Chilly Reception)
--     The engine already has the self-switch primitive (combat/
--     switch_primitives.lua: requestSwitch / switchMonAtSide) and a real
--     native Gen 2 Baton Pass (Battle.MOVE_EFFECTS.EFFECT_BATON_PASS,
--     base-gen2-Battle.lua:2644). This file does NOT re-register Baton
--     Pass's own behavior -- it wraps the native handler to close the ONE
--     real gap: the mod's per-mon atk/def/spa/spd stage bucket
--     (combat/modern_combat.lua's stagesFor) is keyed by the mon object,
--     while the native Baton Pass path moves the volatile table itself and
--     never emits `battle.battler_switched` (the event modern_combat's own
--     listener uses to drop stage buckets). So native Baton Pass carries
--     the native per-side stages (self.stages[side]) but silently loses
--     every mod-tracked stat boost. Shed Tail / Chilly Reception are Gen
--     8/9 moves with no native handler at all (national_dex leaves both at
--     EFFECT_NORMAL_HIT / effectModeled=false).
--
--   MOVE-CALLING (Assist, Copycat, Instruct)
--     All three share one engine seam: a nested Battle:useMove under
--     `battle.copyDepth`, the same "this move was called" guard
--     combat/modern_field_effects.lua's own Nature Power already
--     establishes (gen2/Battle.lua's Metronome/Mirror Move recursion uses
--     the identical guard). Instruct is NOT action re-insertion -- the
--     engine's runTurn is a local, unexported closure (see switch_
--     primitives.lua's own header) -- but Showdown's own
--     `queue.prioritizeAction` makes the instructed move resolve
--     immediately after Instruct's action, which is what a synchronous
--     nested dispatch reproduces.
--
--   MOVE-LEARNING (Sketch)
--     Permanently rewrites the user's Sketch move slot to the target's
--     last move. Battle.party IS save.party on Gen 2, so a direct write to
--     mon.moves persists exactly like the native Transform/learnset paths.
--
--   SELF/STATUS SHUFFLES (Lock-On, Mind Reader, Psych Up, Psycho Shift)
--     Lock-On / Mind Reader are a re-point only: the native Gen 2
--     Battle.MOVE_EFFECTS.EFFECT_LOCK_ON already implements the real
--     target-side SUBSTATUS_LOCK_ON (target.lockOn + Battle:consumeLockOn
--     + the .LockOn sure-hit arm, base-gen2-Battle.lua:1720-1731) -- it is
--     simply unreachable because national_dex registers both ids at
--     EFFECT_NORMAL_HIT (effectModeled=false). Psych Up and Psycho Shift
--     are plain stage/status copies.
--
-- Showdown source of truth (scratch/showdown/moves.ts, read by direct
-- extraction this session; line numbers cited per clause):
--   batonpass      (1092): selfSwitch 'copyvolatile'; onHit fails when
--                  !canSwitch or commanded.
--   shedtail       (16162): volatileStatus 'substitute', selfSwitch
--                  'shedtail'; onTryHit fails when !canSwitch / already
--                  substituted / hp <= ceil(maxhp/2); onHit directDamage
--                  (ceil(maxhp/2)). pokemon.ts:1248-1250 -- 'shedtail'
--                  copies ONLY the substitute volatile, never boosts.
--   chillyreception(2396): weather 'snowscape', selfSwitch true.
--   assist         (608): samples a move from the user's OTHER party
--                  members, skipping flags.noassist/isZ/isMax; fails when
--                  none; this.actions.useMove(pick, user).
--   copycat        (2849): this.actions.useMove(this.lastMove.id, user)
--                  unless the last move has failcopycat/isZ/isMax.
--   instruct       (9642): target repeats its lastMove via
--                  queue.prioritizeAction, refused for failinstruct/isZ/
--                  isMax/charge/recharge/beakblast/focuspunch/shelltrap or
--                  exhausted PP.
--   lockon         (10395): onTryHit fails when the source already has the
--                  volatile; onHit adds the target side lock-on.
--   mindreader     (11896): identical, sharing the same lockon volatile.
--   psychup        (14212): copy every boost; remove/copy the four crit
--                  volatiles (dragoncheer/focusenergy/gmaxchistrike/
--                  laserfocus).
--   psychoshift    (14188): onTryHit fails when the source has no status
--                  and sets move.status = source.status; self.onHit cures
--                  the user. battle-actions.ts:1223-1229 then :1317-1334
--                  confirms the user's cure is SKIPPED when the status
--                  application fails (damage[i] combined with false ->
--                  targets[i] = false -> selfDrops `continue`s), so a
--                  refused transfer means no cure either.
--
-- Gen 1: this mod's own manifest declares gen2 only. Every handler still
-- goes through normalize() so a Gen 1 caller never crashes, but the pivot
-- primitives (requestSwitch/switchMonAtSide) and the mod's native Gen 2
-- move dispatch are Gen 2 machinery -- isGen2Battle gates them honestly
-- rather than half-building a Gen 1 path, exactly as combat/
-- modern_force_switch.lua's own header already does.
return function(mod)
  local Strings = require("src.core.Strings")
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  local gen2Ok_Effects, Effects = pcall(require, "src.battle.gen2.Effects")
  Effects = gen2Ok_Effects and Effects or nil

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local stagesFor = mod.exports.stagesFor
  local isGen2Battle = mod.exports.isGen2Battle
  local sideOfWho = mod.exports.sideOfWho
  local requestSwitch = mod.exports.requestSwitch
  local setWeather = mod.exports.setWeather
  local canSetWeather = mod.exports.canSetWeather
  local currentWeather = mod.exports.currentWeather
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local FIELD_BASE_TURNS = mod.exports.FIELD_BASE_TURNS
  local FIELD_EXTENDED_TURNS = mod.exports.FIELD_EXTENDED_TURNS
  local statusTypeImmune = mod.exports.statusTypeImmune
  assert(normalize and displayNameFor and stagesFor and isGen2Battle and sideOfWho,
    "modern_pivot_moves: combat/modern_combat.lua must load first")
  assert(requestSwitch, "modern_pivot_moves: combat/switch_primitives.lua must load first")
  assert(setWeather and canSetWeather and currentWeather and statusTypeImmune,
    "modern_pivot_moves: combat/modern_combat.lua must load first")
  assert(resolveFieldDuration and FIELD_BASE_TURNS and FIELD_EXTENDED_TURNS,
    "modern_pivot_moves: combat/field_duration.lua must load first")

  local nationalDex = mod.find and mod.find("national_dex")
  local moveFlags = nationalDex and nationalDex.exports and nationalDex.exports.moveFlags
  local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById

  ------------------------------------------------------------------
  -- Shared helpers
  ------------------------------------------------------------------

  -- The underlying party-mon table (Gen 1's battler wrapper carries its mon
  -- as .mon; Gen 2's raw mon IS the table) -- the same monOf shape
  -- combat/modern_stat_manipulation.lua already uses.
  local function monOf(who, gen2)
    if not who then return nil end
    return (gen2 and who) or who.mon
  end

  -- Cross-generation single-message emit: Gen 2's Battle has emit, Gen 1's
  -- BattleState has none but does have sayNext -- the idiom combat/
  -- modern_hazards.lua / modern_stat_manipulation.lua already use.
  local function say(battle, text)
    if not (battle and text) then return end
    if battle.emit then
      battle:emit({ kind = "message", text = text })
    elseif battle.sayNext then
      battle.sayNext(text)
    end
  end

  -- A run() handler's return value is DISCARDED on Gen 2 (gen2/Battle.lua:
  -- 1750-1754) -- the handler must emit its own lines. On Gen 1 the list is
  -- returned for performMove's sayNext loop. gen2 is read off the battle's
  -- real class identity (isGen2Battle), not normalize's ctx-shape guess, so
  -- both a real Gen 2 battle and this file's harness drivers take the emit
  -- path.
  local function finish(battle, lines)
    if isGen2Battle(battle) then
      for i = 1, #lines do say(battle, lines[i]) end
      return {}
    end
    return lines
  end

  local function failed(battle)
    say(battle, Strings("But it failed!"))
    if not isGen2Battle(battle) then return { Strings("But it failed!") } end
    return {}
  end

  -- national_dex's live flags payload, resolved the same tolerant way
  -- modern_move_flags.lua's own flagsOf does (registered spelling first,
  -- then the separator-stripped form).
  local function flagsOf(moveId)
    if not (moveFlags and moveId) then return nil end
    local ok, f = pcall(moveFlags, moveId)
    if ok and type(f) == "table" and next(f) ~= nil then return f end
    local stripped = tostring(moveId):upper():gsub("[^A-Z0-9]", "")
    if stripped ~= moveId then
      local ok2, f2 = pcall(moveFlags, stripped)
      if ok2 and type(f2) == "table" and next(f2) ~= nil then return f2 end
    end
    return f
  end

  local function defOf(battle, moveId)
    if not (battle and moveId) then return nil end
    local ok, def = pcall(battle.moveDef, battle, moveId)
    if ok and def then return def end
    if moveById then
      local ok2, info = pcall(moveById, moveId)
      if ok2 then return info end
    end
    return nil
  end

  local function moveNameOf(battle, moveId)
    local def = defOf(battle, moveId)
    return (def and (def.name or def.shortEffect)) or tostring(moveId)
  end

  -- The opposing active battler a nested call should aim at when the
  -- handler's own target is the user or nil (Assist/Copycat/Instruct's
  -- called move resolves its own target archetype from here, exactly the
  -- fallback modern_field_effects.lua's Nature Power already uses).
  local function opposingActive(battle, user)
    if not (battle and user) then return nil end
    if battle:sideOf(user) == "player" then return battle.enemy end
    return battle.player
  end

  -- The one nested-dispatch seam. copyDepth is the engine's own "this move
  -- was called" guard (gen2/Battle.lua's Metronome/Mirror Move recursion):
  -- with it set, useMove spends no PP and does not overwrite the caller's
  -- own volatile(mon).lastMove.
  local function callMove(battle, user, target, moveId)
    if not (battle and user and moveId) then return false end
    if not target or target == user then target = opposingActive(battle, user) end
    if not target then return false end
    local native = battle.useMove
    if type(native) ~= "function" then return false end
    battle.copyDepth = (battle.copyDepth or 0) + 1
    local ok, err = pcall(native, battle, user, target, moveId)
    battle.copyDepth = battle.copyDepth - 1
    if not ok then
      mod.log:warn("g9-battle-engine: modern_pivot_moves: called-move "
        .. "dispatch failed for %s: %s", tostring(moveId), tostring(err))
      return false
    end
    return true
  end

  -- Living, non-egg bench behind the active index on the mon's own side.
  -- Same possibleSwitches equivalent combat/modern_force_switch.lua's own
  -- benchOf computes; kept local so this file does not depend on that
  -- file's boot order.
  local function livingBench(battle, mon, gen2)
    if not (battle and mon and gen2) then return nil end
    local side = battle:sideOf(mon)
    local party = side == "player" and battle.party or battle.enemyParty
    local activeIndex = side == "player" and battle.playerIndex or battle.enemyIndex
    local bench = {}
    if type(party) ~= "table" then return bench end
    for i, m in ipairs(party) do
      if i ~= activeIndex and (m.hp or 0) > 0 and not m.isEgg then
        bench[#bench + 1] = { index = i, mon = m }
      end
    end
    return bench
  end

  local function hasLivingBench(battle, mon, gen2)
    local bench = livingBench(battle, mon, gen2)
    return bench ~= nil and #bench > 0
  end

  local function hasSubstitute(battle, who, gen2)
    if not who then return false end
    if gen2 then
      if type(battle.volatile) ~= "function" then return false end
      local vol = battle:volatile(who)
      return (vol and vol.substitute or 0) > 0
    end
    return (who.substituteHP or 0) > 0
  end

  ------------------------------------------------------------------
  -- BATON PASS -- wrap the real native handler so the mod's per-mon stage
  -- bucket rides the baton too.
  ------------------------------------------------------------------
  -- Native EFFECT_BATON_PASS (base-gen2-Battle.lua:2644-2683) already
  -- copies every non-dropped volatile and moves the volatile TABLE itself
  -- onto the incoming mon, but it does that with plain field writes and a
  -- `send` emit -- it never emits `battle.battler_switched`, which is the
  -- ONLY event combat/modern_combat.lua's stage-store lifecycle listens on.
  -- So the mod's atk/def/spa/spd boosts (stagesFor, keyed by mon) are left
  -- behind while the native per-side stages ride through. Copy the bucket
  -- forward, keyed on the pre-switch side (Battle:sideOf is a plain
  -- `mon == self.player` identity test, so it MUST be captured before the
  -- native call flips self.player).
  function mod.exports.batonPassCarryStages(battle, fromMon, side)
    if not (battle and fromMon) then return nil end
    side = side or battle:sideOf(fromMon)
    local incoming = side == "player" and battle.player or battle.enemy
    if not incoming or incoming == fromMon then return nil end
    local src = stagesFor(battle, fromMon)
    local dst = stagesFor(battle, incoming)
    for _, key in ipairs({ "attack", "defense", "spa", "spd" }) do
      if src[key] and src[key] ~= 0 then dst[key] = src[key] end
    end
    return incoming
  end

  mod.content.move_effects:register("G9_BATONPASS_EFFECT", {
    kind = "primary",
    run = function(a, b, c, def, moveId, sureHit)
      local n = normalize(a, b, c)
      local battle, attacker, defender = n.battle, n.user, n.target
      if not (battle and attacker) then return end
      local side = battle:sideOf(attacker)
      local snapshot = {}
      local src = stagesFor(battle, attacker)
      for _, key in ipairs({ "attack", "defense", "spa", "spd" }) do
        snapshot[key] = src[key]
      end
      local native = Battle and Battle.MOVE_EFFECT_RECORDS and Battle.MOVE_EFFECT_RECORDS.EFFECT_BATON_PASS
      local nativeRun = native and native.run
      if not nativeRun then return end
      local ok, err = pcall(nativeRun, battle, attacker, defender, def, moveId, sureHit)
      if not ok then
        mod.log:warn("g9-battle-engine: modern_pivot_moves: native Baton "
          .. "Pass failed: %s", tostring(err))
        return
      end
      local incoming = side == "player" and battle.player or battle.enemy
      if incoming and incoming ~= attacker then
        local dst = stagesFor(battle, incoming)
        for key, value in pairs(snapshot) do
          if value and value ~= 0 then dst[key] = value end
        end
      end
    end,
  })
  mod.content.moves:patch("BATONPASS", { effect = "G9_BATONPASS_EFFECT" })

  -- lockon is `noCopy: true` (moves.ts:10412), so it must not ride a Baton
  -- Pass -- the native BATON_PASS_DROPS list already reserves the slot for
  -- exactly this kind of exclusion (modern_move_flags.lua adds "minimize"
  -- the same way). Mutualate the live list native reads fresh at each pass.
  do
    local listed = false
    if Effects then
      for _, key in ipairs(Effects.BATON_PASS_DROPS) do
        if key == "lockOn" then listed = true break end
      end
      if not listed then
        Effects.BATON_PASS_DROPS[#Effects.BATON_PASS_DROPS + 1] = "lockOn"
      end
    end
  end

  ------------------------------------------------------------------
  -- SHED TAIL -- pay half max HP, hand a quarter-max-HP Substitute to the
  -- incoming mon, then switch.
  ------------------------------------------------------------------
  -- pokemon.ts:1246-1251 is explicit: a 'shedtail' volatile transfer copies
  -- ONLY `substitute` (never boosts). This engine's own switch path clears
  -- every volatile on BOTH the outgoing and incoming mon (Battle:switch /
  -- Battle:switchMonAtSide both call clearVolatile), so the substitute
  -- cannot simply be set and left -- it is re-applied to whoever walks in,
  -- on the real `battle.battler_switched` event, from a pending stamp.
  function mod.exports.shedTailApplySubstitute(battle, incoming, hp)
    if not (battle and incoming and hp and hp > 0) then return false end
    if (incoming.hp or 0) <= 0 then return false end
    if isGen2Battle(battle) then
      battle:volatile(incoming).substitute = hp
    else
      incoming.substituteHP = hp
    end
    return true
  end

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local previous = ev and ev.previous
    local incoming = ev and ev.battler
    if not (battle and previous and incoming) then return end
    local pending = battle.__g9ShedTailSub
    if not (pending and pending.mon == previous) then return end
    battle.__g9ShedTailSub = nil
    if mod.exports.shedTailApplySubstitute(battle, incoming, pending.hp) then
      say(battle, Strings("%s received the substitute!", displayNameFor(battle, incoming, isGen2Battle(battle))))
    end
  end)

  mod.content.move_effects:register("G9_SHEDTAIL_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local gen2 = isGen2Battle(battle)
      if not gen2 then return failed(battle) end
      local m = monOf(user, gen2)
      local maxHp = (m and m.maxHp) or (m and m.stats and m.stats.hp) or 1
      if not hasLivingBench(battle, user, gen2) then return failed(battle) end
      if hasSubstitute(battle, user, gen2) then return failed(battle) end
      if (m and m.hp or 0) <= math.ceil(maxHp / 2) then return failed(battle) end
      local cost = math.ceil(maxHp / 2)
      local subHp = math.max(1, math.floor(maxHp / 4))
      m.hp = math.max(0, (m.hp or 0) - cost)
      battle:emit({ kind = "damage", side = battle:sideOf(user),
        amount = cost, hp = m.hp, anim = false })
      battle.__g9ShedTailSub = { mon = user, hp = subHp }
      local lines = { Strings("%s made a substitute!", displayNameFor(battle, user, gen2)) }
      for i = 1, #lines do say(battle, lines[i]) end
      requestSwitch(battle, user, { reason = "SHEDTAIL" })
    end,
  })
  mod.content.moves:patch("SHEDTAIL", { effect = "G9_SHEDTAIL_EFFECT" })

  ------------------------------------------------------------------
  -- CHILLY RECEPTION -- Snowscape, then switch.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_CHILLYRECEPTION_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local gen2 = isGen2Battle(battle)
      if not gen2 then return failed(battle) end
      if not hasLivingBench(battle, user, gen2) then return failed(battle) end
      local lines = {}
      if currentWeather(battle, gen2) ~= "SNOW" then
        if canSetWeather(battle, false, user) then
          local turns = resolveFieldDuration(gen2 and user or nil,
            FIELD_BASE_TURNS, FIELD_EXTENDED_TURNS, "ICYROCK")
          setWeather(battle, gen2, "SNOW", turns, user)
          lines[#lines + 1] = Strings("It started to snow!")
        end
      end
      for i = 1, #lines do say(battle, lines[i]) end
      requestSwitch(battle, user, { reason = "CHILLYRECEPTION" })
    end,
  })
  mod.content.moves:patch("CHILLYRECEPTION", { effect = "G9_CHILLYRECEPTION_EFFECT" })

  ------------------------------------------------------------------
  -- The battle-global "last move" tracker Copycat reads. Showdown's
  -- `this.lastMove` is set in clearActiveMove at the END of a successful
  -- runMove (battle.ts:376-380), i.e. it still points at the PREVIOUS move
  -- while Copycat's own onHit runs -- so this keeps the prior value in
  -- __g9PrevMoveId and Copycat reads that. Honest simplification, flagged:
  -- battle.move_used fires before a move resolves, so a move that then
  -- misses/fails still becomes copyable here (Showdown only skips failed
  -- moves via clearActiveMove(true)).
  ------------------------------------------------------------------
  mod.events:on("battle.move_used", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    if not (battle and moveId) then return end
    battle.__g9PrevMoveId = battle.__g9LastMoveId
    battle.__g9LastMoveId = moveId
  end)

  ------------------------------------------------------------------
  -- ASSIST -- sample a move from the user's OTHER party members.
  ------------------------------------------------------------------
  -- Returns the eligible pool (id list) so the harness can assert the
  -- noassist / self-exclusion filtering without depending on the RNG.
  function mod.exports.assistPool(battle, user, gen2)
    local pool = {}
    if not (battle and user) then return pool end
    local side = gen2 and battle:sideOf(user) or sideOfWho(battle, user, gen2)
    local party = side == "player" and battle.party or battle.enemyParty
    if type(party) ~= "table" then return pool end
    local userMon = monOf(user, gen2)
    for _, member in ipairs(party) do
      local memberMon = monOf(member, gen2)
      if memberMon and memberMon ~= userMon then
        for _, slot in ipairs(memberMon.moves or {}) do
          local id = slot.id
          local f = id and flagsOf(id)
          if id and not (f and f.noassist) then
            pool[#pool + 1] = id
          end
        end
      end
    end
    return pool
  end

  mod.content.move_effects:register("G9_ASSIST_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user) then return end
      local gen2 = isGen2Battle(battle)
      local pool = mod.exports.assistPool(battle, user, gen2)
      if #pool == 0 then return failed(battle) end
      local pick
      if gen2 then
        pick = pool[battle.random(#pool) + 1]
      else
        pick = pool[math.floor(battle.rng(0, #pool - 1)) + 1]
      end
      if not pick then return failed(battle) end
      callMove(battle, user, target, pick)
    end,
  })
  mod.content.moves:patch("ASSIST", { effect = "G9_ASSIST_EFFECT" })

  ------------------------------------------------------------------
  -- COPYCAT -- repeat the battle's last move.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_COPYCAT_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user) then return end
      local last = battle.__g9PrevMoveId
      if not last then return failed(battle) end
      local f = flagsOf(last)
      if f and f.failcopycat then return failed(battle) end
      callMove(battle, user, target, last)
    end,
  })
  mod.content.moves:patch("COPYCAT", { effect = "G9_COPYCAT_EFFECT" })

  ------------------------------------------------------------------
  -- INSTRUCT -- the target repeats its last move, right now.
  ------------------------------------------------------------------
  -- Refusal list mirrors moves.ts:9652-9662: no lastMove / failinstruct /
  -- charge / recharge / beakblast / focuspunch / shelltrap / exhausted PP.
  -- "charge" is read off national_dex's own flags payload (e.g. SOLARBEAM
  -- carries charge=true) with Effects.CHARGE as the engine-side fallback;
  -- recharge likewise (HYPER_BEAM carries recharge=true).
  local function instructRefused(battle, target, moveId, gen2)
    if not moveId then return true end
    local f = flagsOf(moveId)
    if f and f.failinstruct then return true end
    local def = defOf(battle, moveId)
    local effect = def and def.effect
      if (f and f.charge) or (effect and Effects and Effects.CHARGE and Effects.CHARGE[effect]) then
      return true
    end
      if (f and f.recharge) or (effect and Effects and Effects.RECHARGE and Effects.RECHARGE[effect]) then
      return true
    end
    if gen2 and type(battle.volatile) == "function" then
      local vol = battle:volatile(target)
      if vol and (vol.beakBlast or vol.focusPunch or vol.shellTrap) then return true end
    end
    local targetMon = monOf(target, gen2)
    local slot
    for _, s in ipairs((targetMon and targetMon.moves) or {}) do
      if s.id == moveId then slot = s end
    end
    if not slot then return true end
    if (slot.pp or 0) <= 0 then return true end
    return false
  end

  mod.content.move_effects:register("G9_INSTRUCT_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user and target) then return end
      local gen2 = isGen2Battle(battle)
      local last
      if gen2 and type(battle.volatile) == "function" then
        last = battle:volatile(target).lastMove
      else
        last = target.lastMove or (target.mon and target.mon.lastMove)
      end
      if instructRefused(battle, target, last, gen2) then return failed(battle) end
      callMove(battle, target, opposingActive(battle, target), last)
    end,
  })
  mod.content.moves:patch("INSTRUCT", { effect = "G9_INSTRUCT_EFFECT" })

  ------------------------------------------------------------------
  -- SKETCH -- permanently learn the target's last move in Sketch's slot.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_SKETCH_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user and target) then return end
      local gen2 = isGen2Battle(battle)
      local userMon = monOf(user, gen2)
      local targetMon = monOf(target, gen2)
      if not (userMon and targetMon) then return failed(battle) end
      if userMon.transformed then return failed(battle) end
      local last
      if gen2 and type(battle.volatile) == "function" then
        last = battle:volatile(target).lastMove
      else
        last = target.lastMove or targetMon.lastMove
      end
      if not last then return failed(battle) end
      local f = flagsOf(last)
      if f and f.nosketch then return failed(battle) end
      local sketchIndex
      for i, slot in ipairs(userMon.moves or {}) do
        if slot.id == last then return failed(battle) end
        if slot.id == "SKETCH" and not sketchIndex then sketchIndex = i end
      end
      if not sketchIndex then return failed(battle) end
      local def = defOf(battle, last)
      local basePp = (def and def.pp) or 5
      -- `maxPp` (camel) is the field every other move slot uses: Gen 2's own
      -- Mon.movesAtLevel/Trainers.party write it, and the battle scene reads
      -- it for the `PP cur/max` readout. A lowercase `maxpp` here (a
      -- Showdown transcription) left the slot's max nil, so the scene fell
      -- back to the current PP and the sketched move's maximum appeared to
      -- drain with every use; `ppUps = 0` keeps the slot well-formed for
      -- Gen 1's own `def.pp + ppUps * floor(def.pp/5)` maximum as well.
      userMon.moves[sketchIndex] = { id = last, pp = basePp, maxPp = basePp, ppUps = 0 }
      return finish(battle, { Strings("%s sketched %s!", displayNameFor(battle, user, gen2), moveNameOf(battle, last)) })
    end,
  })
  mod.content.moves:patch("SKETCH", { effect = "G9_SKETCH_EFFECT" })

  ------------------------------------------------------------------
  -- LOCK-ON / MIND READER -- re-point at the real native Gen 2 handler.
  ------------------------------------------------------------------
  -- national_dex registers both ids at EFFECT_NORMAL_HIT / effectModeled=
  -- false, which is the only reason the native target-side lock-on never
  -- runs. A tiny primary record forwards to the untouched native handler
  -- (read live off Battle.MOVE_EFFECT_RECORDS, the folded table the Loader
  -- registered), the same proven :register+:patch shape combat/
  -- modern_switch_moves.lua's own Teleport uses to reach a native handler.
  mod.content.move_effects:register("G9_LOCKON_EFFECT", {
    kind = "primary",
    run = function(a, b, c, def, moveId, sureHit)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user and target) then return end
      local native = Battle and Battle.MOVE_EFFECTS and Battle.MOVE_EFFECTS.EFFECT_LOCK_ON
      if type(native) ~= "function" then return failed(battle) end
      native(battle, user, target, def, moveId, sureHit)
    end,
  })
  mod.content.moves:patch("LOCKON", { effect = "G9_LOCKON_EFFECT" })
  mod.content.moves:patch("MINDREADER", { effect = "G9_LOCKON_EFFECT" })

  ------------------------------------------------------------------
  -- PSYCH UP -- copy every stage (and the crit volatiles this engine has).
  ------------------------------------------------------------------
  -- The mod's stage store owns atk/def/spa/spd; speed/accuracy/evasion live
  -- in the native per-side / per-wrapper table. dragoncheer/gmaxchistrike
  -- are not modelled by this engine at all, so only focusEnergy (native
  -- volatile) and the mod's own laserFocusTurns are copied -- flagged
  -- rather than silently assumed complete.
  local ALL_BOOST_KEYS = { "attack", "defense", "spa", "spd", "speed", "accuracy", "evasion" }
  local NATIVE_STAGE_KEYS = { speed = true, accuracy = true, evasion = true }

  local function nativeStageTable(battle, who, gen2)
    if gen2 then
      local stages = battle and battle.stages
      local side = stages and battle:sideOf(who)
      return side and stages[side] or nil
    end
    return who and who.stages
  end

  local function readStage(battle, who, key, gen2)
    if NATIVE_STAGE_KEYS[key] then
      local tbl = nativeStageTable(battle, who, gen2)
      return (tbl and tbl[key]) or 0
    end
    return stagesFor(battle, who)[key] or 0
  end

  local function writeStage(battle, who, key, value, gen2)
    if NATIVE_STAGE_KEYS[key] then
      local tbl = nativeStageTable(battle, who, gen2)
      if tbl then tbl[key] = value end
    else
      stagesFor(battle, who)[key] = value
    end
  end

  mod.content.move_effects:register("G9_PSYCHUP_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user and target) then return end
      local gen2 = isGen2Battle(battle)
      for _, key in ipairs(ALL_BOOST_KEYS) do
        writeStage(battle, user, key, readStage(battle, target, key, gen2), gen2)
      end
      local userMon, targetMon = monOf(user, gen2), monOf(target, gen2)
      if gen2 then
        local uv, tv = battle:volatile(user), battle:volatile(target)
        uv.focusEnergy = tv.focusEnergy
        if userMon then userMon.laserFocusTurns = targetMon and targetMon.laserFocusTurns end
      else
        user.focusEnergy = target.focusEnergy
        if userMon then userMon.laserFocusTurns = targetMon and targetMon.laserFocusTurns end
      end
      return finish(battle, { Strings("%s copied %s's stat changes!", displayNameFor(battle, user, gen2), displayNameFor(battle, target, gen2)) })
    end,
  })
  mod.content.moves:patch("PSYCHUP", { effect = "G9_PSYCHUP_EFFECT" })

  ------------------------------------------------------------------
  -- PSYCHO SHIFT -- hand the user's status to the target, then cure.
  ------------------------------------------------------------------
  -- Gen 2's applyStatus already refuses a second major status, and
  -- statusTypeImmune / hasStatusImmunity cover the type and ability
  -- immunities Showdown's own setStatus path enforces. If the transfer is
  -- refused the whole move fails and the user is NOT cured -- confirmed
  -- against battle-actions.ts:1223-1229 + :1317-1334 (a refused trySetStatus
  -- false-combines damage, so selfDrops skips the cure).
  local function cureStatus(battle, mon, gen2)
    if not mon then return end
    mon.status = nil
    mon.statusTurns = nil
    mon.toxicCounter = nil
    mon.sleepTurns = nil
  end

  mod.content.move_effects:register("G9_PSYCHOSHIFT_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user and target) then return end
      local gen2 = isGen2Battle(battle)
      local userMon, targetMon = monOf(user, gen2), monOf(target, gen2)
      local status = userMon and userMon.status
      if not status then return failed(battle) end
      if statusTypeImmune and statusTypeImmune(battle, targetMon, status) then
        return failed(battle)
      end
      if mod.exports.hasStatusImmunity
          and mod.exports.hasStatusImmunity(targetMon, status, battle) then
        return failed(battle)
      end
      local applied
      if gen2 then
        applied = battle:applyStatus(targetMon, status, userMon)
      else
        local StatusRegistry = require("src.battle.StatusRegistry")
        applied = StatusRegistry.inflict(battle, targetMon, status, { source = userMon })
      end
      if not applied then return failed(battle) end
      cureStatus(battle, userMon, gen2)
      return finish(battle, { Strings("%s shifted its status to %s!", displayNameFor(battle, user, gen2), displayNameFor(battle, target, gen2)) })
    end,
  })
  mod.content.moves:patch("PSYCHOSHIFT", { effect = "G9_PSYCHOSHIFT_EFFECT" })

  mod.log:info("g9-battle-engine: modern_pivot_moves installed "
    .. "(BATONPASS, SHEDTAIL, CHILLYRECEPTION, ASSIST, COPYCAT, INSTRUCT, "
    .. "SKETCH, LOCKON, MINDREADER, PSYCHUP, PSYCHOSHIFT)")
end
