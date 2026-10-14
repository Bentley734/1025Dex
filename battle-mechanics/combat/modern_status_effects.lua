-- Volatile statuses this engine's own native code had no mechanic for at
-- all: Attract, Taunt, Torment. (Encore is different -- see
-- combat/moves_new.lua's ENCORE row and gigantamax/gimmick_dynamax.lua's
-- revert-interaction patch; it's already 100% implemented natively in
-- Gen 2, just unreachable until this mod adds the move data. Gen 1 has no
-- forced-move infrastructure to build Encore on at all, and never had the
-- move -- confirmed Gen2-only, per explicit user decision.)
--
-- Storage: one shared field set per battler -- `attract` (bool),
-- `tauntTurns` (countdown), `tormented` (bool, does not expire on its
-- own). Gen 1: directly on the battler wrapper (confirmed dropped for
-- free on every switch -- BattleState.lua's makeBattler always builds a
-- brand new wrapper table at every switch site, the same free-reset
-- modern_combat.lua's own stageState reasoning already relies on). Gen 2:
-- inside battle:volatile(mon) (confirmed dropped for free -- clearVolatile
-- sets mon.volatile = nil outright). `attract` deliberately matches the
-- field name Gen 2's own Effects.BATON_PASS_DROPS already reserves
-- (src/battle/gen2/Effects.lua:474) -- the native authors already named
-- this exact slot, just never filled it.
--
-- Last-move tracking for Torment reuses each engine's OWN existing field
-- instead of adding a parallel one: Gen 1's battler.lastMove (set in
-- BattleState:performMove, confirmed BattleState.lua:3585) and Gen 2's
-- volatile(mon).lastMove (set in Battle:useMove, confirmed
-- gen2/Battle.lua:1435, and already read natively by Encore/Disable/
-- Counter/Mirror Move) are both already reliably populated before this
-- file's own checks ever run -- no new tracking hook needed.
--
-- Enforcement touch points, each confirmed by direct source read:
--   Gen 1: TrainerAI.chooseMove (AI candidate list, real dotted function,
--     not a local), Status.beforeMove (the one authoritative execution-
--     time gate every real and AI move already passes through --
--     confirmed real/dotted, same #860-safe timing Disable's own block
--     relies on -- this is also where Attract's immobilize roll and
--     Taunt's tauntTurns countdown live, mirroring how confusedTurns/
--     disabledTurns already tick right there natively).
--   Gen 2: Battle:canAct (Attract's roll, alongside the existing
--     confuseCount check), Battle:usableMoves (the one shared seam
--     Ai.lua already trusts completely -- confirmed zero independent
--     AI-side legality checks of its own), Battle:useMove (the
--     authoritative execution-time fizzle for BOTH sides -- playerAttack/
--     enemyAttack are local closures inside runTurn, not patchable, but
--     both call this one dotted method immediately after their own
--     moveDisabled check and nothing else sits between that check and
--     useMove, so wrapping useMove itself generalizes to both without
--     touching either closure, and reproduces Disable's own no-PP-cost
--     fizzle convention for free -- confirmed Gen2's Disable block
--     already sits BEFORE useMove is ever called, unlike Gen 1's PP-
--     spent-then-fizzle convention inside performMove), Battle:
--     tickCounters (tauntTurns countdown, mirroring encoreTurns/
--     disabledTurns's own tick right there).
return function(mod)
  local BattleState = require("src.battle.BattleState")
  local TrainerAI = require("src.battle.TrainerAI")
  local Status = require("src.battle.Status")
  local ModernStats = mod.exports.ModernStats
  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")

  local gen2Ok, Gen2Battle = pcall(require, "src.battle.gen2.Battle")
  Gen2Battle = gen2Ok and Gen2Battle or nil

  -- Same ctx-vs-positional discriminator modern_combat.lua's own
  -- normalize() uses (Gen 1's move_effects run(ctx) hands a ctx facade
  -- with a real .battle field; Gen 2's run(battle, attacker, defender,
  -- ...) is six positional args, confirmed gen2/Battle.lua:1529) --
  -- duplicated here rather than shared, matching modern_combat_protect
  -- .lua's own standalone-require convention (no load-order dependency
  -- on modern_combat.lua).
  local function normalize(a, b, c)
    if type(a) == "table" and a.battle ~= nil then
      return { battle = a.battle, user = a.user, target = a.target, gen2 = false }
    end
    return { battle = a, user = b, target = c, gen2 = true }
  end

  -- The one status-field table per generation: the battler wrapper itself
  -- on Gen 1, battle:volatile(mon) on Gen 2.
  local function store(battle, who, gen2)
    if gen2 then return battle:volatile(who) end
    return who
  end

  local function genderOf(who, gen2)
    return gen2 and who.gender or (who.mon and who.mon.gender)
  end

  local function displayNameFor(battle, who, gen2)
    if gen2 then
      local nm = battle:monName(who)
      return battle:sideOf(who) == "player" and nm or Strings("Enemy %s", nm)
    end
    return (who.isPlayer and who.name) or Strings("Enemy %s", who.name)
  end

  -- Mirrors MoveEffects.lua's own confuse()/isProtectedFrom's Substitute
  -- gate convention -- Mist is deliberately NOT checked here (Mist only
  -- ever gates stat-stage drops in this codebase, not other target-
  -- directed status conditions).
  local function substitutedOut(battle, who, gen2)
    if gen2 then
      return (battle:volatile(who).substitute or 0) > 0
    end
    return who.substituteHP ~= nil and who.substituteHP > 0
  end

  local function isStatusMove(battle, gen2, moveId)
    local def = gen2 and battle:moveDef(moveId)
      or (battle and battle.data and battle.data.moves[moveId])
    return def ~= nil and (def.power or 0) == 0, def
  end

  ------------------------------------------------------------------
  -- Attract: opposite, non-genderless genders only, blocked by
  -- Substitute (this ruleset's Gen 6+ rule, matching modern_combat.lua's
  -- own precedent of favoring current-gen behavior -- e.g. Growth's
  -- Gen 5+ Atk+Spa reading -- over Gen 1's original mechanics).
  -- Gen 1 mons get a defensive, idempotent gender roll here (see
  -- ModernStats.generateGender's own header for why -- Gen 1 has no
  -- native gender concept at all); Gen 2 mons already have a real one
  -- from Mon.new and are never expected to need it, but the idempotent
  -- guard makes calling it there harmless too.
  --
  -- Returns applied(bool), message-or-nil -- NOT a messages array --
  -- because the two callers need different behavior on a no-op: ATTRACT
  -- itself (a "primary" pure-status move) always wants a message, success
  -- or failure; G-Max Cuddle (a "secondary" post-damage chance, see
  -- below) wants total silence on a no-op, matching every other
  -- secondary effect in this codebase.
  ------------------------------------------------------------------
  local function tryAttract(battle, user, target, gen2)
    -- OBLIVIOUS: Showdown's onTryHit for Attract ("This Pokémon cannot be
    -- infatuated or taunted") -- the target is immune before any gender
    -- math runs. Every caller (the ATTRACT move, G-Max Cuddle, and the
    -- exported reuse Cute Charm uses) shares this exact primitive, so a
    -- single gate here covers all three.
    local abilityIdOf = mod.exports.abilityIdOf
    if abilityIdOf and abilityIdOf(target) == "OBLIVIOUS" then
      return false
    end
    if not gen2 then
      ModernStats.generateGender(user.mon)
      ModernStats.generateGender(target.mon)
    end
    local ug, tg = genderOf(user, gen2), genderOf(target, gen2)
    if not ug or not tg or ug == "unknown" or tg == "unknown" or ug == tg then
      return false
    end
    if substitutedOut(battle, target, gen2) then
      return false
    end
    local tStore = store(battle, target, gen2)
    if tStore.attract then
      return false
    end
    tStore.attract = true
    return true, Strings("%s fell in love!", displayNameFor(battle, target, gen2))
  end
  -- Exported for reuse -- Cute Charm (abilities/engine/inflict_status
  -- .lua) needs this exact same real, gender-aware, Substitute-aware
  -- primitive, just with the two roles reversed from a normal Attract
  -- move (the ATTACKER falls for the ABILITY HOLDER, not the other way
  -- around).
  mod.exports.tryAttract = tryAttract

  mod.content.move_effects:register("GMAX_ATTRACT_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local applied, msg = tryAttract(n.battle, n.user, n.target, n.gen2)
      if not applied then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      return { msg }
    end,
  })
  -- ATTRACT already carries effect = "GMAX_ATTRACT_EFFECT" directly in
  -- moves_new.lua (this mod's own data, not a native id -- no :patch
  -- needed, unlike modern_combat.lua's AMNESIA/GROWTH re-pointing, which
  -- patches genuine native ROM moves).

  -- G-Max Cuddle: a damaging move (power = 1, unlike plain Attract), so
  -- its infatuate chance is the "secondary" (rolled after a landed hit)
  -- class, not "primary". Round 15: converted from kind="secondary"+run
  -- to kind="full" + a battle.damage_dealt listener -- the old shape
  -- pre-empted the whole move on Gen 2's dispatch (its useMove runs ANY
  -- move_effects record with a .run field and returns before the damage
  -- path, so GMAXCUDDLE dealt 0) and short-circuited to a silent no-op on
  -- Gen 2. The listener now rolls tryAttract AFTER a landed non-zero hit,
  -- and works on BOTH engines.
  mod.content.move_effects:register("GMAX_CUDDLE_EFFECT", { kind = "full" })
  mod.events:on("battle.damage_dealt", function(ev)
    if not (ev and ev.move and ev.move.effect == "GMAX_CUDDLE_EFFECT") then return end
    if (ev.damage or 0) <= 0 then return end
    local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(ev.battle) or false
    local applied, msg = tryAttract(ev.battle, ev.user, ev.target, gen2)
    if applied and msg then
      ev.battle:emit({ kind = "message", text = msg })
    end
  end)
  -- GMAXCUDDLE's own effect field is set directly in gmax_moves.lua, same
  -- reasoning as ATTRACT above.

  ------------------------------------------------------------------
  -- Taunt: 3 turns, blocked by Substitute, prevents selecting/executing
  -- any status-category (power == 0) move.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_TAUNT_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, target, gen2 = n.battle, n.target, n.gen2
      if substitutedOut(battle, target, gen2) then
        return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
      end
      local abilityIdOf = mod.exports.abilityIdOf
      if abilityIdOf and abilityIdOf(target) == "OBLIVIOUS" then
        return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
      end
      local tStore = store(battle, target, gen2)
      if tStore.tauntTurns then
        return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
      end
      tStore.tauntTurns = 3
      return { Strings("%s fell for\nthe TAUNT!", displayNameFor(battle, target, gen2)) }
    end,
  })
  -- TAUNT's own effect field is set directly in moves_new.lua, same
  -- reasoning as ATTRACT above.

  ------------------------------------------------------------------
  -- Torment: does not expire on its own (cured only by switching out, the
  -- native per-battler storage already handling that for free), blocked
  -- by Substitute, prevents selecting/executing the same move used last.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_TORMENT_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, target, gen2 = n.battle, n.target, n.gen2
      if substitutedOut(battle, target, gen2) then
        return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
      end
      local tStore = store(battle, target, gen2)
      if tStore.tormented then
        return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
      end
      tStore.tormented = true
      return { Strings("%s was\ntormented!", displayNameFor(battle, target, gen2)) }
    end,
  })
  -- TORMENT's own effect field is set directly in moves_new.lua, same
  -- reasoning as ATTRACT above.

  ------------------------------------------------------------------
  -- Baton Pass carryover: real current Pokemon Showdown behavior
  -- (smogon/pokemon-showdown's own data/conditions.ts and data/moves.ts,
  -- fetched directly rather than recalled from memory) drops a volatile
  -- from the copy specifically when that volatile's own condition record
  -- carries `noCopy: true` -- confirmed set on disable, encore, and
  -- attract (all three already on Gen 2 native's own Effects.
  -- BATON_PASS_DROPS list) plus torment, which this mod adds (above) and
  -- native's own list predates. Mutated here rather than reimplementing
  -- EFFECT_BATON_PASS: Effects.BATON_PASS_DROPS is a live table native's
  -- own handler reads fresh every time Baton Pass is used (`for _, key in
  -- ipairs(Effects.BATON_PASS_DROPS) do carried[key] = nil end`,
  -- gen2/Battle.lua), so appending to it from mod code takes effect
  -- immediately with no need to touch or duplicate that handler at all.
  -- Taunt, confusion, Leech Seed, Perish Song, and Focus Energy carry no
  -- such flag in the real source and are correctly copied already, which
  -- is why none of those are added here.
  do
    local ok, Effects = pcall(require, "src.battle.gen2.Effects")
    if ok and Effects and Effects.BATON_PASS_DROPS then
      local alreadyListed = false
      for _, key in ipairs(Effects.BATON_PASS_DROPS) do
        if key == "tormented" then alreadyListed = true break end
      end
      if not alreadyListed then
        Effects.BATON_PASS_DROPS[#Effects.BATON_PASS_DROPS + 1] = "tormented"
      end
    end
  end

  ------------------------------------------------------------------
  -- Gen 1 enforcement
  ------------------------------------------------------------------

  -- AI candidate filtering. Reimplements vanilla's own base (non-AI-
  -- layer) fallback -- usable[rng(1,#usable)] -- for a taunted/tormented
  -- turn rather than delegating to vanilla's AI-layer scoring pass
  -- (TrainerAI.LAYERS), which reads straight off battler.curMoves/
  -- disabledSlot by index; swapping that table out from under it for the
  -- duration of one call is the kind of fragile mid-call mutation this
  -- codebase's own link-battle desync history (see the trappingTurns
  -- comment in BattleState.lua) warns against. Losing AI-layer 2's
  -- smarter pick on a taunted/tormented turn is an accepted, minor
  -- simplification -- legality is what matters here, not AI strength.
  local vanillaChooseMove = TrainerAI.chooseMove
  function TrainerAI.chooseMove(battler, rng, battle)
    if not (battler.tauntTurns or battler.tormented) then
      return vanillaChooseMove(battler, rng, battle)
    end
    rng = rng or love.math.random
    local unlimited = battle and battle.ruleset and battle.ruleset.enemyUnlimitedPP
    local usable = {}
    for i, mv in ipairs(battler.curMoves) do
      local statusMove = isStatusMove(battle, false, mv.id)
      local blocked = (battler.tauntTurns and statusMove)
        or (battler.tormented and mv.id == battler.lastMove)
      if battler.disabledSlot ~= i and (unlimited or mv.pp > 0) and not blocked then
        usable[#usable + 1] = mv
      end
    end
    if #usable == 0 then
      return { id = "STRUGGLE", pp = 1, struggle = true }
    end
    return usable[rng(1, #usable)]
  end

  -- The authoritative execution-time gate. Runs native Status.beforeMove
  -- first (sleep/freeze/flinch/disable/confusion/paralysis, all
  -- unmodified); Attract/Taunt/Torment are layered on AFTER, only once
  -- the mon has cleared every native check -- same relative ordering as
  -- this file's Gen 2 canAct wrap below, kept consistent between the two
  -- engines.
  local nativeBeforeMove = Status.beforeMove
  function Status.beforeMove(battler, rng, battle, selectedMoveId)
    local canMove, msgs, selfHit = nativeBeforeMove(battler, rng, battle, selectedMoveId)
    if not canMove then return canMove, msgs, selfHit end
    msgs = msgs or {}

    -- tauntTurns countdown, same tick shape disabledTurns/confusedTurns
    -- already use right here natively -- the turn that ends the count
    -- still goes through untaunted, matching disabledTurns' own
    -- expires-then-allowed-this-turn behavior.
    if battler.tauntTurns then
      battler.tauntTurns = battler.tauntTurns - 1
      if battler.tauntTurns <= 0 then
        battler.tauntTurns = nil
        table.insert(msgs, Strings("%s's\nTAUNT wore off!", displayNameFor(battle, battler, false)))
      end
    end

    if battler.attract then
      if rng(0, 255) < 128 then
        table.insert(msgs, Strings("%s is immobilized\nby love!", displayNameFor(battle, battler, false)))
        return false, msgs
      end
      table.insert(msgs, Strings("%s is in love\nwith the foe!", displayNameFor(battle, battler, false)))
    end

    if selectedMoveId then
      local statusMove, def = isStatusMove(battle, false, selectedMoveId)
      if battler.tauntTurns and statusMove then
        table.insert(msgs, Strings("%s can't use\n%s after the TAUNT!",
          displayNameFor(battle, battler, false), (def and def.name) or selectedMoveId))
        return false, msgs
      end
      if battler.tormented and selectedMoveId == battler.lastMove then
        table.insert(msgs, Strings("%s can't use the\nsame move twice in a row!",
          displayNameFor(battle, battler, false)))
        return false, msgs
      end
    end

    return true, msgs
  end

  ------------------------------------------------------------------
  -- Gen 2 enforcement
  ------------------------------------------------------------------
  if Gen2Battle then
    local nativeCanAct = Gen2Battle.canAct
    -- moveId is forwarded, not dropped: CheckPlayerTurn/CheckEnemyTurn pass
    -- it (gen2/Battle.lua:1057), the native sleep arm reads it for the
    -- Snore/Sleep Talk bypass, and modern_move_flags.lua's own freeze/
    -- cantusetwice wrap below this one needs it too.
    function Gen2Battle:canAct(mon, moveId)
      if not nativeCanAct(self, mon, moveId) then return false end
      local vol = self:volatile(mon)
      if vol.attract then
        local name = self:monName(mon)
        self:emit({ kind = "message", text = Strings("%s is in love with the foe!", name) })
        if self:roller()(256) < 128 then
          self:emit({ kind = "message", text = Strings("%s is immobilized by love!", name) })
          return false
        end
      end
      return true
    end

    -- The one shared seam Ai.lua already trusts completely -- extending
    -- it here fixes AI legality for free, the same way Encore/Disable's
    -- own forcedMove/moveDisabled already do.
    local nativeUsableMoves = Gen2Battle.usableMoves
    function Gen2Battle:usableMoves(mon)
      local vol = self:volatile(mon)
      local out = nativeUsableMoves(self, mon)
      if not (vol.tauntTurns or vol.tormented) then
        return out
      end
      local filtered = {}
      for _, move in ipairs(out) do
        local statusMove = isStatusMove(self, true, move.id)
        local blocked = (vol.tauntTurns and statusMove)
          or (vol.tormented and move.id == vol.lastMove)
        if not blocked then filtered[#filtered + 1] = move end
      end
      return filtered
    end

    -- Authoritative execution-time fizzle, both sides. playerAttack/
    -- enemyAttack (local closures inside runTurn, not patchable) each
    -- call this exactly once, right after their own moveDisabled check
    -- and nothing else -- wrapping useMove itself reproduces Disable's
    -- own no-PP-cost, no-announcement fizzle convention for free (the
    -- native moveDisabled block already sits BEFORE useMove is called at
    -- all, confirmed gen2/Battle.lua:4112-4122/4146-4154), and covers a
    -- called sub-move (Metronome/Sleep Talk) the same way, since those
    -- also route back through this one function.
    local nativeUseMove = Gen2Battle.useMove
    function Gen2Battle:useMove(attacker, defender, moveId)
      local vol = self:volatile(attacker)
      if vol.tauntTurns or vol.tormented then
        local name = self:monName(attacker)
        local statusMove, def = isStatusMove(self, true, moveId)
        if vol.tauntTurns and statusMove then
          self:emit({ kind = "message",
            text = Strings("%s can't use %s after the TAUNT!", name, ((def and def.name) or moveId)) })
          return
        end
        if vol.tormented and moveId == vol.lastMove then
          self:emit({ kind = "message",
            text = Strings("%s can't use the same move twice in a row!", name) })
          return
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end

    -- tauntTurns countdown, mirroring encoreTurns/disabledTurns' own tick
    -- right here natively.
    local nativeTickCounters = Gen2Battle.tickCounters
    function Gen2Battle:tickCounters(mon)
      nativeTickCounters(self, mon)
      local vol = self:volatile(mon)
      if vol.tauntTurns then
        vol.tauntTurns = vol.tauntTurns - 1
        if vol.tauntTurns <= 0 then
          vol.tauntTurns = nil
          self:emit({ kind = "message", text = Strings("%s's TAUNT wore off!", self:monName(mon)) })
        end
      end
    end
  end

  mod.log:info("galar_gmax_dex: modern_status_effects loaded")
end
