-- combat/modern_move_flags.lua
--
-- ROUND 68 (category-3 flag audit; explicit user directive 2026-09-10:
-- "priority fix category 3 ... special case, ohko move final gambit").
--
-- The round-67/68 audit found the move flags national_dex publishes that
-- this engine never READ at all -- "category 3". They are grouped by the
-- mechanism they gate, and closed across three files:
--   noparentalbond  -- abilities/engine/parental_bond.lua
--   mustpressure    -- abilities/engine/pressure.lua
--   cantusetwice    -- THIS FILE
--   defrost         -- THIS FILE
--   powder          -- THIS FILE
--   minimize        -- THIS FILE
--   gravity         -- THIS FILE, documented MOOT (see the note below)
--
-- Every real rule below is transcribed from the Pokemon Showdown source
-- fetched into scratch/showdown/ this session -- the exact file and line
-- is cited beside each block -- never recalled from memory.
--
-- SPECIAL CASE the user called out by name -- the OHKO moves (Fissure,
-- Guillotine, Horn Drill, Sheer Cold) and Final Gambit. Neither carries
-- ANY of the flags this file reads (verified against national_dex's own
-- generated moveFlags payload: FINALGAMBIT has `noparentalbond`, the four
-- OHKO moves have no category-3 flag at all), so nothing here may touch
-- them. Final Gambit's own real behavior -- the user faints, the target
-- takes the user's current HP, and the user does NOT faint if the move
-- fails (type immunity/Protect/miss) -- lives untouched in
-- combat/legacy_move_takeover.lua, and the only category-3 fact that
-- concerns it, its `noparentalbond` flag, is read in parental_bond.lua.
-- The four OHKO moves carry no category-3 flag at all and are kept out
-- of Parental Bond by that file's own explicit id set + power guard (its
-- header explains why Showdown's own `ohko` property is NOT the reason).
-- This file deliberately has no OHKO/Final Gambit branch at all.
--
-- gravity -- MOOT, deliberately not implemented, and named so a future
-- reader does not hunt for it. data/moves.ts's `gravity` flag means "this
-- move cannot be used while Gravity is in effect" (Fly, Bounce, Sky Drop,
-- Splash, Magnet Rise, Telekinesis, High Jump Kick, Jump Kick, Flying
-- Press, Floaty Fall). This engine has no Gravity move and no Gravity
-- field state anywhere -- a full-text search of every .lua in the mod
-- finds no GRAVITY token at all -- so there is nothing the flag could be
-- evaluated against. If a Gravity field is ever built, its gate belongs
-- here beside the rest.
--
-- ---------------------------------------------------------------------
-- Sourcing
-- ---------------------------------------------------------------------
-- cantusetwice -- data/moves.ts flags on bloodmoon/gigatonhammer, enforced
--   in battle.ts endTurn (battle.ts:1687-1698): at the start of every
--   round, after clearing every move slot's disabled flag, a slot is
--   re-disabled when `move.flags['cantusetwice'] && pokemon.lastMove?.id
--   === moveSlot.id`. The net observable rule is exactly "cannot use it
--   on consecutive turns": the disable is cleared again the next round,
--   so a mon that skips a turn with a different move may use it again.
--   Reproduced here by remembering the turn the move was USED and
--   blocking only when the current turn is exactly one past it -- the
--   engine's own lastMove storage cannot do this alone, because a blocked
--   attempt never updates it and it would then stay stuck forever.
--
-- defrost -- data/conditions.ts frz (conditions.ts:96-121):
--   onBeforeMovePriority 10, `if (move.flags['defrost'] && !(move.id ===
--   'burnup' && !pokemon.hasType('Fire'))) return;` -- a defrost move is
--   usable while frozen (Burn Up only by a Fire-type), and onModifyMove
--   then cures the user's freeze (`-curestatus`). Also onAfterMoveSecondary
--   cures the TARGET when `move.thawsTarget`, and onDamagingHit cures the
--   target for any FIRE damaging move (category !== 'Status', except
--   'polarflare').
--
--   thawsTarget is a move PROPERTY, not in national_dex's flags payload
--   (confirmed: zero hits for it in generated/flags.lua), so its five real
--   moves -- Hydro Steam, Matcha Gotcha, Scald, Scorching Sands, Steam
--   Eruption -- are hardcoded, the same "nothing to read, so a named table
--   is honest" exception modern_status_turn_loss.lua's Sleep-Talk/Snore
--   pair already established.
--
-- powder -- battle-actions.ts hitStepTryImmunity (battle-actions.ts:
--   666-689): `if (gen >= 6 && move.flags['powder'] && target !== pokemon
--   && !dex.getImmunity('powder', target)) return this.battle.add
--   ('-immune', target) ...`. `dex.getImmunity('powder', target)` is the
--   Grass-type immunity plus Overcoat and Safety Goggles. It runs BEFORE
--   accuracy. The message is the standard "It doesn't affect X...".
--
-- minimize -- data/moves.ts minimize (moves.ts:11918-11950): the move sets
--   volatileStatus 'minimize' and boosts evasion by 2; the condition is
--   `noCopy: true` and has onSourceModifyDamage -> chainModify(2) and
--   onAccuracy -> return true, both gated on the ATTACKER's move carrying
--   the `minimize` flag. The eight real minimizer-hitting moves
--   (Body Slam, Dragon Rush, Flying Press, Heat Crash, Heavy Slam,
--   Steamroller, Stomp, Supercell Slam) are read live from moveFlags.
--
return function(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "modern_move_flags: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  local isGen2Battle = mod.exports.isGen2Battle
  local curTypesOf = mod.exports.curTypesOf
  assert(abilityIdOf and isGen2Battle and curTypesOf,
    "modern_move_flags: ability_dispatch.lua and modern_combat.lua must load first")

  local Strings = require("src.core.Strings")

  ------------------------------------------------------------------
  -- Shared helpers
  ------------------------------------------------------------------

  -- moveFlags is a SEPARATE national_dex lookup from moveById and is keyed
  -- by the dex's own registered spelling, which mixes separator styles
  -- (SLEEP_POWDER beside COTTONSPORE); the engine's move ids do the same.
  -- Hands back the record's own id/strippedId as fallbacks, so either
  -- spelling resolves. Cached per id: a landed hit asks several times.
  local flagCache = {}
  local function flagsOf(moveId)
    if type(moveId) ~= "string" then return nil end
    local cached = flagCache[moveId]
    if cached ~= nil then
      if cached == false then return nil end
      return cached
    end
    local found
    if moveFlags then
      local ok, f = pcall(moveFlags, moveId)
      if ok and type(f) == "table" then found = f end
      if not found then
        local ok2, info = pcall(moveById, moveId)
        if ok2 and type(info) == "table" then
          for _, key in ipairs({ info.id, info.strippedId }) do
            if key and key ~= moveId then
              local ok3, f2 = pcall(moveFlags, key)
              if ok3 and type(f2) == "table" then found = f2 break end
            end
          end
        end
      end
    end
    flagCache[moveId] = found or false
    return found
  end

  local function monOf(who) return who and (who.mon or who) or nil end

  local function nameOf(battle, who, gen2)
    local displayNameFor = mod.exports.displayNameFor
    if displayNameFor then return displayNameFor(battle, who, gen2) end
    local m = monOf(who)
    return (m and m.name) or "?"
  end

  -- One message sink for both generations: Gen 2's Battle:emit is a real
  -- method (gen2/Battle.lua:437); Gen 1's native BattleState has no emit,
  -- so its own sayNext is used there.
  local function say(battle, text)
    if not battle then return end
    if type(battle.emit) == "function" then
      battle:emit({ kind = "message", text = text })
    elseif type(battle.sayNext) == "function" then
      battle:sayNext(text)
    end
  end

  local function normalize(a, b, c)
    local fn = mod.exports.normalize
    if fn then return fn(a, b, c) end
    if type(a) == "table" and a.battle ~= nil then
      return { battle = a.battle, user = a.user, target = a.target, gen2 = false }
    end
    return { battle = a, user = b, target = c, gen2 = true }
  end

  -- The real current round number on each engine. Gen 2 increments
  -- Battle.turn once per round (native runTurn :4737, or
  -- combat/turn_order.lua's resolveTurnActions for scene-driven battles);
  -- Gen 1 increments BattleState.turnCount (BattleState.lua:2804).
  local function currentTurn(battle, gen2)
    if gen2 then return battle.turn or 0 end
    return battle.turnCount or 0
  end

  -- Freeze spelling differs per engine: Gen 1 uses "FRZ", Gen 2 "freeze"
  -- (confirmed both via Status.RECORDS / Battle.STATUSES).
  local function isFrozen(mon, gen2)
    local m = monOf(mon)
    if not m then return false end
    return m.status == (gen2 and "freeze" or "FRZ")
  end

  local function cureFrozen(mon)
    local m = monOf(mon)
    if not (m and m.status) then return false end
    local cure = mod.exports.cureStatusOf
    if cure then return cure(m) end
    m.status, m.statusTurns, m.toxicCounter = nil, nil, nil
    return true
  end

  ------------------------------------------------------------------
  -- 1+2. cantusetwice and defrost
  --
  -- Both are decisions about whether a CHOSEN move is allowed to run, so
  -- both live at the two real execution gates: Gen 1's Status.beforeMove
  -- (the one authoritative gate every real and AI move passes through,
  -- reached from BattleState:statusInterrupt immediately before
  -- performMove, where lastMove still holds the PREVIOUS turn's move) and
  -- Gen 2's Battle:canAct (reached from CheckPlayerTurn/CheckEnemyTurn).
  --
  -- Gen 2 SCENE-driven battles never call canAct at all
  -- (combat/turn_order.lua's resolveTurnActions drives battle:useMove
  -- directly -- see its own round-66 header), so cantusetwice is ALSO
  -- enforced at Battle:useMove below, which every path funnels through.
  ------------------------------------------------------------------

  local function cantUseTwiceBlocks(battle, mon, moveId, gen2)
    local f = flagsOf(moveId)
    if not (f and f.cantusetwice) then return false end
    local turn = currentTurn(battle, gen2)
    if gen2 then
      if type(battle.volatile) ~= "function" then return false end
      local vol = battle:volatile(mon)
      return vol ~= nil and vol.cantUseTwiceId == moveId
        and vol.cantUseTwiceTurn ~= nil and turn == vol.cantUseTwiceTurn + 1
    end
    return mon.cantUseTwiceId == moveId and mon.cantUseTwiceTurn ~= nil
      and turn == mon.cantUseTwiceTurn + 1
  end

  local function recordCantUseTwice(battle, mon, moveId, gen2)
    local f = flagsOf(moveId)
    if not (f and f.cantusetwice) then return end
    local turn = currentTurn(battle, gen2)
    if gen2 then
      if type(battle.volatile) ~= "function" then return end
      local vol = battle:volatile(mon)
      vol.cantUseTwiceId, vol.cantUseTwiceTurn = moveId, turn
    else
      mon.cantUseTwiceId, mon.cantUseTwiceTurn = moveId, turn
    end
  end

  -- The move was USED (announced) -- record it for next round. Gen 1 emits
  -- battle.move_used from BattleState:performMove after the announcement
  -- and after Metronome/called re-entry, exactly where the engine sets its
  -- own lastMove; Gen 2 emits the same event from Battle:useMove at the
  -- identical point. isCalled is honored so a Metronome-picked Blood Moon
  -- never locks the picked move.
  mod.events:on("battle.move_used", function(ev)
    local battle = ev and ev.battle
    local user = ev and ev.user
    local move = ev and ev.move
    if not (battle and user and move) then return end
    if ev.isCalled then return end
    local id = move.id or ev.moveId
    if id then recordCantUseTwice(battle, user, id, isGen2Battle(battle)) end
  end)

  -- defrost: the freeze is cured BEFORE the engine's own freeze arm ever
  -- runs, so the move proceeds. Burn Up's real exception (usable while
  -- frozen only by a Fire-type) is honored (conditions.ts:98).
  local function canDefrost(mon, moveId, gen2)
    local f = flagsOf(moveId)
    if not (f and f.defrost) then return false end
    local strip = tostring(moveId):upper():gsub("[^A-Z0-9]", "")
    if strip ~= "BURNUP" then return true end
    for _, t in ipairs(curTypesOf(mon, gen2) or {}) do
      if tostring(t):upper() == "FIRE" then return true end
    end
    return false
  end

  local Status = require("src.battle.Status")
  local nativeBeforeMove = Status.beforeMove
  function Status.beforeMove(battler, rng, battle, selectedMoveId)
    local preMsgs
    if selectedMoveId and battler and isFrozen(battler.mon, false)
        and canDefrost(battler.mon, selectedMoveId, false) then
      cureFrozen(battler.mon)
      preMsgs = { Strings("%s\nthawed out!", (battler.mon and battler.mon.name) or battler.name or "?") }
    end
    if selectedMoveId and battler and cantUseTwiceBlocks(battle, battler, selectedMoveId, false) then
      local msgs = preMsgs or {}
      msgs[#msgs + 1] = Strings("%s can't use\nthe same move twice in a row!",
        (battler.mon and battler.mon.name) or battler.name or "?")
      return false, msgs
    end
    if type(nativeBeforeMove) ~= "function" then return true, preMsgs or {} end
    local canMove, msgs, selfHit = nativeBeforeMove(battler, rng, battle, selectedMoveId)
    if preMsgs then
      local out = {}
      for _, m in ipairs(preMsgs) do out[#out + 1] = m end
      for _, m in ipairs(msgs or {}) do out[#out + 1] = m end
      return canMove, out, selfHit
    end
    return canMove, msgs, selfHit
  end

  local gen2Ok_Gen2Battle, Gen2Battle = pcall(require, "src.battle.gen2.Battle")
  Gen2Battle = gen2Ok_Gen2Battle and Gen2Battle or nil
  if Gen2Battle then
    local nativeCanAct = Gen2Battle.canAct
    function Gen2Battle:canAct(mon, moveId)
      if moveId and isFrozen(mon, true) and canDefrost(mon, moveId, true) then
        cureFrozen(mon)
        say(self, Strings("%s thawed out!", ((mon and mon.name) or "?")))
      end
      if moveId and cantUseTwiceBlocks(self, mon, moveId, true) then
        say(self, Strings("%s can't use the same move twice in a row!", ((mon and mon.name) or "?")))
        return false
      end
      if type(nativeCanAct) ~= "function" then return true end
      return nativeCanAct(self, mon, moveId)
    end
  end

  -- AI legality on Gen 2's one shared seam (Ai.lua trusts usableMoves
  -- completely -- see modern_status_effects.lua's own header).
  if Gen2Battle then
    local nativeUsableMoves = Gen2Battle.usableMoves
    function Gen2Battle:usableMoves(mon)
      local out
      if type(nativeUsableMoves) == "function" then
        out = nativeUsableMoves(self, mon)
      else
        out = {}
        for _, mv in ipairs((mon and mon.moves) or {}) do out[#out + 1] = mv end
      end
      local filtered = {}
      for _, mv in ipairs(out or {}) do
        if not (mv and mv.id and cantUseTwiceBlocks(self, mon, mv.id, true)) then
          filtered[#filtered + 1] = mv
        end
      end
      return filtered
    end
  end

  -- Gen 1 AI legality. Re-picks from the legal alternatives only when the
  -- native answer is a cantusetwice-blocked move, so ordinary AI behavior
  -- (including the AI-layer scoring pass) is untouched.
  local TrainerAI = require("src.battle.TrainerAI")
  local nativeChooseMove = TrainerAI.chooseMove
  function TrainerAI.chooseMove(battler, rng, battle)
    local ok, pick = pcall(nativeChooseMove, battler, rng, battle)
    if not ok then return pick end
    if not (pick and pick.id and cantUseTwiceBlocks(battle, battler, pick.id, false)) then
      return pick
    end
    rng = rng or love.math.random
    local unlimited = battle and battle.ruleset and battle.ruleset.enemyUnlimitedPP
    local legal = {}
    for i, mv in ipairs((battler and battler.curMoves) or {}) do
      if mv and battler.disabledSlot ~= i and (unlimited or (mv.pp or 0) > 0)
          and not cantUseTwiceBlocks(battle, battler, mv.id, false) then
        legal[#legal + 1] = mv
      end
    end
    if #legal > 0 then return legal[rng(1, #legal)] end
    return pick
  end

  ------------------------------------------------------------------
  -- 3. powder
  ------------------------------------------------------------------

  local function isGrassType(who, gen2)
    local types = curTypesOf(who, gen2)
    for _, t in ipairs(types or {}) do
      if tostring(t):upper() == "GRASS" then return true end
    end
    return false
  end

  -- dex.getImmunity('powder', target) collapses to: the target is a
  -- non-user, and either it is Grass-type or its ability is Overcoat
  -- (Safety Goggles is an item this engine does not have). Overcoat is an
  -- ignorable ability, so Mold Breaker/Teravolt/Turboblaze bypass it --
  -- the same trio abilities/engine/type_immunity.lua already honors.
  local function powderImmune(battle, user, target, moveId, gen2)
    local f = flagsOf(moveId)
    if not (f and f.powder) then return false end
    if not target then return false end
    if target == user or monOf(target) == monOf(user) then return false end
    if isGrassType(target, gen2) then return true end
    local ignoreAbility = monOf(user) and abilityIdOf(monOf(user))
    if ignoreAbility == "MOLDBREAKER" or ignoreAbility == "TERAVOLT"
        or ignoreAbility == "TURBOBLAZE" then
      return false
    end
    return abilityIdOf(target) == "OVERCOAT"
  end

  -- The move was used (so its PP is spent and it is announced), then the
  -- target is revealed immune -- Showdown's own effect ordering
  -- (deductPP -> move announcement -> hitStepTryImmunity).
  local function runPowderFizzleGen2(battle, attacker, defender, moveId)
    local move = battle.findMove and battle:findMove(attacker, moveId)
    if move and (move.pp or 0) > 0 and (battle.copyDepth or 0) == 0 then
      move.pp = move.pp - 1
    end
    local def = battle.moveDef and battle:moveDef(moveId)
    if battle.emit then
      battle.moveEvent = battle:emit({ kind = "move",
        side = battle.sideOf and battle:sideOf(attacker) or "player",
        move = moveId,
        text = Strings("%s\nused %s!", battle:monName(attacker),
          (def and def.name) or moveId) })
      if battle.markMissed then battle:markMissed() end
      battle:emit({ kind = "message",
        text = Strings("It doesn't affect %s...", battle:monName(defender)) })
    end
  end

  if Gen2Battle then
    local nativeUseMove = Gen2Battle.useMove
    function Gen2Battle:useMove(attacker, defender, moveId)
      -- powder runs ahead of everything else this engine would do with the
      -- move.
      if isGen2Battle(self) and powderImmune(self, attacker, defender, moveId, true) then
        runPowderFizzleGen2(self, attacker, defender, moveId)
        return
      end
      -- cantusetwice authoritative gate for scene-driven battles (which
      -- never call canAct) -- a plain fizzle, no PP spent, exactly the
      -- convention Disable/Torment's own fizzle uses.
      if attacker and cantUseTwiceBlocks(self, attacker, moveId, true) then
        say(self, Strings("%s can't use the same move twice in a row!", ((attacker and attacker.name) or "?")))
        return
      end
      if type(nativeUseMove) ~= "function" then return end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  -- Gen 1 powder: no native emit, so the native sayNext convention is used
  -- for both lines, and PP is spent (guarded by the called/struggle/
  -- enemy-unlimited exemptions the native decrement itself honors).
  local BattleState = require("src.battle.BattleState")
  local nativePerformMove = rawget(BattleState, "performMove")
  if type(nativePerformMove) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    local moveId = moveInst and moveInst.id
    if moveId and powderImmune(self, user, target, moveId, false) then
      local move = self.moveDef and self:moveDef(moveInst)
      if moveInst and not isCalled and not moveInst.struggle
          and (moveInst.pp or 0) > 0 then
        moveInst.pp = moveInst.pp - 1
      end
      local userName = nameOf(self, user, false)
      if type(self.sayNextAuto) == "function" then
        self:sayNextAuto(Strings("%s\nused %s!", userName, (move and move.name) or moveId))
        self:sayNextAuto(Strings("It doesn't affect\n%s!", nameOf(self, target, false)))
      end
      return
    end
    return nativePerformMove(self, user, target, moveInst, isCalled)
  end
  end

  ------------------------------------------------------------------
  -- 4. thawsTarget + the general "a Fire damaging hit thaws" rule
  --
  -- Both are the frz condition's own reaction to being HIT
  -- (conditions.ts:112-121). battle.damage_dealt is the real, shared,
  -- both-engines seam that fires once per landed hit (confirmed same
  -- payload on both: ev.move/ev.user/ev.target/ev.damage), the same event
  -- every other on-hit engine in this mod already listens on.
  ------------------------------------------------------------------

  -- thawsTarget is not a national_dex flag (absent from the generated
  -- payload), so these five are the documented named exception -- the
  -- same class as the Sleep-Talk/Snore pair in modern_status_turn_loss.
  local THAWS_TARGET = {
    HYDROSTEAM = true, MATCHAGOTCHA = true, SCALD = true,
    SCORCHINGSANDS = true, STEAMERUPTION = true,
  }
  local function stripId(id) return tostring(id):upper():gsub("[^A-Z0-9]", "") end

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local move = ev and ev.move
    local target = ev and ev.target
    if not (battle and move and target) then return end
    local id = move.id
    if not id then return end
    local gen2 = isGen2Battle(battle)
    local thaws = THAWS_TARGET[stripId(id)] == true
    if not thaws then
      -- The general Fire rule: any FIRE damaging move thaws the target
      -- (status Fire moves like Will-O-Wisp do not, and Polar Flare is
      -- explicitly excluded -- neither exists in this roster, so the
      -- exclusions are belt-and-braces).
      local mtype = move.type and tostring(move.type):upper()
      local damaging = (move.power or 0) > 0
      if move.category ~= nil then
        damaging = tostring(move.category):lower() ~= "status"
      end
      if mtype == "FIRE" and damaging and stripId(id) ~= "POLARFLARE" then
        thaws = true
      end
    end
    if not thaws then return end
    if isFrozen(target, gen2) then
      cureFrozen(target)
      say(battle, Strings("%s\nthawed out!", nameOf(battle, target, gen2)))
    end
  end)

  ------------------------------------------------------------------
  -- 5. minimize
  ------------------------------------------------------------------

  local function hasMinimize(who, gen2)
    local m = monOf(who)
    if not m then return false end
    if gen2 then
      return (m.volatile and m.volatile.minimize) == true
    end
    return m.minimize == true
  end

  local function setMinimize(battle, who, gen2)
    local m = monOf(who)
    if not m then return end
    if gen2 then
      m.volatile = m.volatile or {}
      m.volatile.minimize = true
    else
      m.minimize = true
    end
  end

  -- The MINIMIZE move itself: evasion +2 through each engine's own native
  -- stage path (exactly how modern_movepool_stages.lua routes every
  -- speed/accuracy/evasion change), plus the volatile the flag reads.
  local function applyEvasion(n, delta)
    if n.gen2 then
      if type(n.battle.changeStageAgainstMist) == "function" then
        pcall(function() n.battle:changeStageAgainstMist(n.user, n.user, "evasion", delta) end)
      end
      return {}
    end
    local NativeMoveEffects = require("src.battle.MoveEffects")
    if NativeMoveEffects and type(NativeMoveEffects.changeStage) == "function" then
      return NativeMoveEffects.changeStage(n.battle, n.user, "evasion", delta, false) or {}
    end
    return {}
  end

  mod.content.move_effects:register("GALAR_MINIMIZE_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      if not n.user then return {} end
      setMinimize(n.battle, n.user, n.gen2)
      return applyEvasion(n, 2)
    end,
  })

  -- The eight minimizer-hitting moves deal double and never miss
  -- (moves.ts:11931-11941). Doubling is applied to the FINAL number this
  -- wrap's next(ctx) returns, so it composes with every modifier below it
  -- (STAB, type effectiveness, crit) exactly as chainModify(2) does.
  mod.hooks:wrap("battle.damage", function(nextFn, ctx)
    local move = ctx.move
    if not (move and move.id) then return nextFn(ctx) end
    local f = flagsOf(move.id)
    if not (f and f.minimize) then return nextFn(ctx) end
    if not hasMinimize(ctx.target, isGen2Battle(ctx.battle)) then return nextFn(ctx) end
    local dmg, info = nextFn(ctx)
    dmg = dmg or 0
    if dmg > 0 then dmg = dmg * 2 end
    return dmg, info
  end, 50)

  -- accuracy true = guaranteed hit, the same plain-boolean contract
  -- Battle:vanillaAccuracyRoll / accuracy_multiplier.lua's own No Guard
  -- branch already returns.
  mod.hooks:wrap("battle.accuracy", function(nextFn, ctx)
    local moveId = (ctx.move and ctx.move.id) or ctx.moveId
    if moveId then
      local f = flagsOf(moveId)
      if f and f.minimize and hasMinimize(ctx.target, isGen2Battle(ctx.battle)) then
        return true
      end
    end
    return nextFn(ctx)
  end, 50)

  -- minimize carries noCopy:true (moves.ts:11929), so Baton Pass must drop
  -- it. Mutating the live list native reads fresh on every Baton Pass, the
  -- same idiom modern_status_effects.lua already uses for Torment.
  do
    local ok, Effects = pcall(require, "src.battle.gen2.Effects")
    if ok and Effects and Effects.BATON_PASS_DROPS then
      local listed = false
      for _, key in ipairs(Effects.BATON_PASS_DROPS) do
        if key == "minimize" then listed = true break end
      end
      if not listed then
        Effects.BATON_PASS_DROPS[#Effects.BATON_PASS_DROPS + 1] = "minimize"
      end
    end
  end

  mod.log:info("g9-battle-engine: modern_move_flags installed "
    .. "(cantusetwice BLOODMOON/GIGATONHAMMER, defrost + thawsTarget + Fire-hit thaw, "
    .. "powder Grass/Overcoat, minimize damage-double/never-miss + the MINIMIZE move; "
    .. "gravity documented moot; OHKO + Final Gambit deliberately untouched here)")
end
