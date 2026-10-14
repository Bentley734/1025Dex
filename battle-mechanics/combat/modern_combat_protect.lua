-- Protect move logic: genuine greenfield work (confirmed by grepping all of
-- src/battle/ for "protect"/"Protect"/"Detect" -- only unrelated Mist/Light
-- Screen flavor text exists; Gen 1's original ROM never had Protect at all,
-- it was introduced Gen 2).
--
-- DUAL-ENGINE file (2026-09-16, round 169). This mod's manifest declares
-- "games": ["gen1", "gen2"], so everything here has to run on BOTH. It
-- was originally written against gen2/Battle.lua's own API only (an
-- earlier header here wrongly claimed a gen2-only manifest), which is a
-- real, confirmed bug: gen2/Battle.lua:1533-1538 is the only dispatch
-- site for a move's registered effect record, reading `effectRecord.run`
-- called positionally as `run(self, attacker, defender, def, moveId,
-- sureHit)` and IGNORING the return value -- while gen1's
-- BattleState:performMove (:4350-4377) calls the SAME record as
-- `record.run(ctx)` with ONE ctx table and prints the RETURNED message
-- array. Under gen 1 the old gen2-shaped handlers therefore received the
-- ctx as `battle` and nil as `user`, crashing at rollStall's
-- `user.protectChainTurn` (the reported "attempt to index local 'user'"
-- at line 122) the instant Protect was used. Every handler below is now
-- dual via the local ctxOf() normalizer: it returns a message list on gen
-- 1 and emits via battle:emit on gen 2. Gen 1 also lacks battle.turn and
-- battle:roller (it has turnCount and battle.rng(a,b), no roller), so the
-- stall chain reads whichever field each engine actually has.
--
-- The earlier fix's own reasoning (record.run, not a non-existent
-- `.perform`, and not kind="full") still holds on both engines -- the
-- move_effects schema (src/mods/Schemas.lua:1280-1288) defines neither,
-- and both engines dispatch kind="primary" records through `run`.
--
-- Part A: PROTECT already exists in this mod's own data
-- (GalarGmaxDex/moves_new.lua, priority = 4, correct already) as a
-- documented no-op (effect = "NO_ADDITIONAL_EFFECT", functionCode =
-- "ProtectUser" -- functionCode is dead documentation, grepped: nothing in
-- the core engine ever reads it). Registered here as a real move_effects
-- record (kind = "primary", a `run` handler in Gen 2's own calling
-- convention -- the same shape modern_hazards.lua's GALAR_STEALTHROCK_
-- EFFECT/GALAR_TOXICSPIKES_EFFECT already use successfully) and patched
-- onto PROTECT. Effect records are keyed by move id, so this applies
-- identically in wild, trainer, and link battles with no extra wiring --
-- and any future Detect/Endure/Spiky Shield/Baneful Bunker/King's Shield
-- can point their own `effect` field at this exact same id (they're
-- mechanically identical decay chains in every real generation).
--
-- Success-chance formula deliberately stays the modern Showdown "stall"
-- decay (1/3 per consecutive use, capped 1/729) rather than switching to
-- Gen 2's own native halving chain (Effects.protectSucceeds, the formula
-- Battle.MOVE_EFFECTS.EFFECT_PROTECT already uses natively) -- an earlier,
-- separate, already-explained design choice this fix doesn't revisit; only
-- the dispatch/messaging plumbing was actually broken.
--
-- Turn-scoping and roster-wide clearing (2026-09-10, direct user report --
-- "protect is protecting despite failing"). The two block flags were only
-- ever cleared by Part C's battle.turn_started listener, and that listener
-- touched only battle.player/battle.enemy -- so in a multi-battler battle
-- (g9-Battle-Scene's doubles/triples/boss rosters) any OTHER battler kept
-- `protected`/`maxGuarded` set forever, and a mon whose Protect FAILED was
-- still shielded by the stale flag it had earned on an earlier turn (the
-- reported symptom exactly). Each flag is now stamped with the turn it was
-- raised and only counts while that stamp matches the live turn, both
-- run() handlers drop the user's flags BEFORE rolling (so a failed roll
-- leaves the user provably unprotected), and Part C clears the whole
-- active roster via mod.exports.allActiveBattlers rather than the lead
-- pair. See clearProtection/raiseProtection/protectionOf below.
--
-- Status-effect coverage (same report, second request -- "make sure that
-- protect also blocks status moves effects"). Part D's Gen 2 record swap
-- used to substitute only kind=="primary"/"secondary" records, so a
-- power-0 move whose effect record is kind=="full" slipped through
-- entirely: the Counter/Mirror Coat/Metal Burst family (a full record
-- carrying its own run) and the bare full markers the fixed-damage moves
-- use (Seismic Toss, Night Shade, Sonic Boom, Dragon Rage, Super Fang --
-- these reach the native fixedDamage arm, which never calls battle.damage,
-- so Part B never saw them either). The swap now replaces the move's own
-- record whatever its kind, and both Part B and Part D additionally refuse
-- only moves whose national_dex target actually aims at the shielded
-- battler (targetsBattler below) so field/side archetypes -- Spikes,
-- Reflect, Trick Room, weather -- are never wrongly blocked.
--
-- Part B: blocking an INCOMING damaging move against a protected target.
--
-- Wraps battle.damage (the same hook modern_combat.lua already uses) at a
-- HIGHER priority, so it runs first in the chain and can short-circuit
-- straight to typeMult = 0 without ever calling next() -- reusing Gen 2's
-- own existing, already-correct handling for that exact value (confirmed
-- by direct read, gen2/Battle.lua:1124-1140:
-- `normalizeDamageInfo` maps `typeMult` onto `info.effectiveness`, and
-- `if info.effectiveness == 0 then ... "It doesn't affect %s..." ... end`
-- short-circuits before dealDamage is ever called). Same code path a type
-- immunity already uses, so no new message logic is needed here at all --
-- PP/animation/announcement all run completely normally through the
-- untouched native useMove, and only the damage number comes back zeroed.
--
-- Part D: blocking an INCOMING pure status move (Thunder Wave, Toxic, a
-- stat-lowering move) against a protected target -- these never call
-- hitOnce/battle.damage at all, so Part B's hook never sees them. No hook
-- exists for "a primary status effect is about to run" the way
-- battle.damage does for damage, so this wraps Battle:useMove itself --
-- but NOT the naive "block before native runs at all" version: that would
-- skip PP decrement and the "X used Y!" announcement, giving the attacker
-- their move back for free, which is wrong (a Protect-blocked move still
-- costs PP and still gets announced in every real generation, exactly
-- like Part B's reasoning for damaging moves).
--
-- Instead, when the block condition is met, this temporarily swaps
-- Battle.moveEffectRecordFor (gen2/Battle.lua:2703's own lookup function,
-- a plain function on the class table, not per-instance -- the same
-- monkeypatch shape modern_hazards.lua's own header cites this file as
-- having established) for the single native useMove call, substituting a
-- "doesn't affect" stand-in record -- so native's PP/announcement/
-- accuracy-roll logic (useMove's own top half) runs completely unmodified
-- and unduplicated, and only the real record.run(...) that would have
-- applied the effect is swapped out. Restored immediately after, even on
-- error.
return function(mod)
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  local PROTECT_EFFECT_ID = "GMAX_PROTECT_EFFECT"
  local ENDURE_EFFECT_ID = "GMAX_ENDURE_EFFECT"
  local MAX_GUARD_EFFECT_ID = "GMAX_MAX_GUARD_EFFECT"
  local MAX_GUARD_MOVE_ID = "BATTLE_FORMS_MAXGUARD"

  local okStrings, Strings = pcall(require, "src.core.Strings")
  Strings = okStrings and Strings or nil
  local okStatusReg, StatusRegistry = pcall(require, "src.battle.StatusRegistry")
  StatusRegistry = okStatusReg and StatusRegistry or nil
  local okBattleState, BattleState = pcall(require, "src.battle.BattleState")
  BattleState = okBattleState and BattleState or nil

  ------------------------------------------------------------------
  -- Dual-engine plumbing (2026-09-16, round 169). See the file header
  -- for why both shapes have to be handled here. Gen 1's performMove
  -- builds its one argument with EffectRegistry.makeCtx (ctx.battle /
  -- ctx.user / ctx.target / ctx.move / ctx.displayName / ctx.sayNext),
  -- so `a.battle ~= nil` discriminates a gen1 ctx from a gen2 Battle
  -- instance cleanly -- gen2's Battle has no `.battle` field of its own
  -- (same discriminator modern_combat.lua's own `normalize` already
  -- uses and documents).
  ------------------------------------------------------------------
  local function ctxOf(a, b, c, d, e)
    if type(a) == "table" and a.battle ~= nil then
      return {
        battle = a.battle, user = a.user, target = a.target,
        gen2 = false, ctx = a,
        moveId = a.move and a.move.id or (a.moveInst and a.moveInst.id),
      }
    end
    return { battle = a, user = b, target = c, gen2 = true, moveId = e, def = d }
  end

  -- A battler's display name on either engine. Gen 1's own ctx.displayName
  -- (EffectRegistry.displayName) already prefixes "Enemy " correctly, so
  -- prefer it when present; displayNameFor (modern_combat.lua) is the
  -- shared fallback every other dual-engine file here uses, and it also
  -- has the correct branch for a gen2 battle.
  local function nameOf(n, who)
    if n.gen2 then return n.battle:monName(who) end
    if n.ctx and n.ctx.displayName then return n.ctx.displayName(who) end
    local displayNameFor = mod.exports.displayNameFor
    if displayNameFor then return displayNameFor(n.battle, who, false) end
    return who and who.name or "?"
  end

  -- One line of battle text on either engine. Gen 2 ignores a handler's
  -- return value and reads only battle:emit; Gen 1 prints the run() return
  -- list. `out` is that list on gen 1 (ignored on gen 2).
  local function say(n, out, text)
    if n.gen2 then
      n.battle:emit({ kind = "message", text = text })
    else
      out[#out + 1] = text
    end
  end

  -- Same, but for call sites (Part B's shield riders) that only have a
  -- raw battle and no normalizer object.
  local function sayB(battle, text)
    if battle.emit then
      battle:emit({ kind = "message", text = text })
    elseif battle.sayNext then
      battle:sayNext(text)
    end
  end

  local function nameB(battle, who)
    if battle.monName then return battle:monName(who) end
    local displayNameFor = mod.exports.displayNameFor
    if displayNameFor then return displayNameFor(battle, who, false) end
    return who and who.name or "?"
  end

  -- Gen 2 tracks `battle.turn` (0 at construction, +1 per turn); Gen 1
  -- tracks `battle.turnCount` (BattleState.lua:2804). Neither field exists
  -- on the other engine, so read whichever is present.
  local function battleTurnOf(battle)
    if not battle then return 0 end
    local t = battle.turn
    if t == nil then t = battle.turnCount end
    return t or 0
  end

  -- One 1-in-`x` roll on either engine: Gen 2's roller()(x) == 0
  -- (gen2/Battle.lua:475), Gen 1's battle.rng(a,b) is an inclusive integer
  -- range (BattleState.lua:706), so rng(1, x) == 1 is the same 1-in-x.
  local function rollOneIn(battle, x)
    if battle.roller then return battle:roller()(x) == 0 end
    return battle.rng(1, x) == 1
  end

  ------------------------------------------------------------------
  -- Turn-scoped protection flags (2026-09-10). Every block path reads
  -- through protectionOf instead of the raw flag, so a flag can only
  -- ever answer the turn it was raised on -- the fix for the reported
  -- "protect is protecting despite failing". clearProtection drops
  -- everything a battler can carry (the block flags, their turn stamps,
  -- the shield id and the contact-rider de-dupe table), and is used both
  -- by Part C at turn start and by the run() handlers before they roll.
  ------------------------------------------------------------------
  local function clearProtection(who)
    if not who then return end
    who.protected = nil
    who.maxGuarded = nil
    who.protectShield = nil
    who.protectTurn = nil
    who.guardTurn = nil
    who.protectRiderKeys = nil
  end

  local function raiseProtection(battle, who, kind, moveId)
    if not who then return end
    local turn = battleTurnOf(battle)
    if kind == "guard" then
      who.maxGuarded = true
      who.guardTurn = turn
    else
      who.protected = true
      who.protectTurn = turn
    end
    who.protectShield = moveId
  end

  -- "guard" for Max Guard, "protect" for the rest of the family, nil when
  -- the battler is not shielded THIS turn (no flag, or a flag from an
  -- earlier turn). The stamp is the whole point: a flag Part C missed can
  -- never answer a later move.
  local function protectionOf(battle, who)
    if not who then return nil end
    local turn = battleTurnOf(battle)
    if who.maxGuarded and who.guardTurn == turn then return "guard" end
    if who.protected and who.protectTurn == turn then return "protect" end
    return nil
  end
  mod.exports.clearProtection = clearProtection
  mod.exports.protectionOf = protectionOf

  ------------------------------------------------------------------
  -- Target archetypes (2026-09-10). Protect only stops a move that
  -- actually aims at the shielded battler; national_dex's own `target`
  -- field is the source (the same field combat/move_targeting.lua and
  -- combat/modern_side_protection.lua key off), read lazily at battle
  -- time because the per-move view is only wanted on demand. The exempt
  -- set is the self / ally / side / field archetypes: Spikes and Stealth
  -- Rock ("opponents-field"), Reflect and Safeguard ("users-field"),
  -- Trick Room and Haze ("entire-field"/"all"), and self-buffs ("user")
  -- are never stopped by Protect in any real generation. Anything not in
  -- this set -- the unknown/nil case included -- is treated as aimed at
  -- the battler, so a move with no dex record keeps the old block rather
  -- than silently losing it.
  ------------------------------------------------------------------
  local PROTECT_EXEMPT_TARGETS = {
    ["user"] = true, ["ally"] = true, ["user-and-allies"] = true,
    ["users-field"] = true, ["entire-field"] = true,
    ["opponents-field"] = true, ["all"] = true, ["all-pokemon"] = true,
  }

  local function moveTargetOf(battle, moveId, def)
    if def and def.target then return def.target end
    local dex = mod.find and mod.find("national_dex")
    local moveById = dex and dex.exports and dex.exports.moveById
    if moveById and moveId then
      local ok, info = pcall(moveById, moveId)
      if ok and type(info) == "table" and info.target then return info.target end
    end
    return nil
  end

  local function targetsBattler(battle, moveId, def)
    local target = moveTargetOf(battle, moveId, def)
    if target == nil then return true end
    return not PROTECT_EXEMPT_TARGETS[target]
  end
  -- Exported for the harness's own regression battery (round 281): the
  -- block paths use it directly, and a direct unit test of the archetype
  -- gate keeps that rule honest without standing up the whole pipeline.
  mod.exports.protectTargetsBattler = targetsBattler

  ------------------------------------------------------------------
  -- Shared Protect-family "stall" chain -- the real Pokemon Showdown
  -- rule (data/conditions.ts's own `stall` condition: counter starts at
  -- 3, triples on each consecutive use, counterMax 729, deleted on any
  -- failed roll). Mapped onto this engine as: chance is 100% on the
  -- first use (or after any break in the chain), then 1/3, 1/9, 1/27,
  -- ... capped at 1/729; a failed use OR a turn gap resets it to 100%.
  -- `protectChainX` is the next roll's denominator and `protectChainTurn`
  -- is the last turn the chain succeeded; the two together encode
  -- Showdown's counter one-to-one (fresh chain -> x = 1, then 3, 9, ...).
  --
  -- REAL BUG FIXED HERE (2026-09-10, direct user report -- "protect and
  -- other protection similar moves might not have their 'succesful uses
  -- lower next pass chance to X pass chance' base on pokemon showdown
  -- formula for them"). Both run() handlers below used to compare/assign
  -- `battle.turnCount`, a field that DOES NOT EXIST on gen2/Battle.lua's
  -- battle object -- confirmed by direct read of the base engine, which
  -- only ever has `self.turn` (`self.turn = 0` at :294, incremented once
  -- per turn at the top of runTurn, :4737). So `(battle.turnCount or 0)
  -- - 1` was always -1, `consecutive` was ALWAYS false, `x` was ALWAYS
  -- 1, and `battle:roller()(1) == 0` always succeeded: Protect and Max
  -- Guard could never decay and never fail, exactly the reported symptom.
  -- Only the field name was wrong; the formula's own values already
  -- matched Showdown.
  --
  -- One chain per Pokemon, shared across the WHOLE family (Protect,
  -- Detect, Endure, Spiky Shield, Baneful Bunker, King's Shield, Silk
  -- Trap, Burning Bulwark, Obstruct, Max Guard), exactly as real games
  -- and Showdown treat it -- which is why this is a single shared helper
  -- rather than each effect carrying its own copy.
  ------------------------------------------------------------------
  local CHAIN_CAP = 729
  local function rollStall(battle, user)
    local turn = battleTurnOf(battle)
    local consecutive = user.protectChainTurn ~= nil
      and user.protectChainTurn == turn - 1
    local x = (consecutive and user.protectChainX) or 1
    local success = rollOneIn(battle, x)
    if success then
      user.protectChainX = math.min(x * 3, CHAIN_CAP)
      user.protectChainTurn = turn
    else
      -- Showdown's onStallMove deletes the `stall` volatile on failure,
      -- so the NEXT protection use starts a fresh 100% chain -- clear
      -- BOTH fields (the old code left protectChainTurn behind).
      user.protectChainX = nil
      user.protectChainTurn = nil
    end
    return success
  end

  ------------------------------------------------------------------
  -- Phase 22 export: the Guard family (Wide Guard / Quick Guard) shares
  -- Showdown's own `stall` volatile with the whole Protect family --
  -- their `onHitSide(side, source)` is literally `source.addVolatile
  -- ('stall')` (moves.ts:20827 / :14507). Adding a volatile that is
  -- already active is a no-op in Showdown, which is exactly what this
  -- mirrors: if the user already has a live chain from last turn, leave
  -- it alone; otherwise start one at 3 (Showdown's own `onStart`
  -- counter), i.e. the same state rollStall writes after a first
  -- success. Kept here, beside rollStall, so the field names live in one
  -- place and a future member of the family never re-derives them.
  ------------------------------------------------------------------
  function mod.exports.armStallChain(battle, user)
    if not (battle and user) then return end
    local turn = battleTurnOf(battle)
    if user.protectChainTurn ~= nil and user.protectChainTurn == turn - 1 then
      return -- already active this chain; addVolatile('stall') no-ops
    end
    user.protectChainX = 3
    user.protectChainTurn = turn
  end

  ------------------------------------------------------------------
  -- Contact-triggered riders for the shield family, transcribed from
  -- Showdown's own data/moves.ts condition blocks (fetched to
  -- scratch/protect-family-showdown.txt, 2026-09-10). `stat` changes go
  -- through this mod's shared changeStage primitive -- or Gen 2's native
  -- changeStageAgainstMist for the one NATIVE stat, Speed -- and
  -- `status` goes through Battle:applyStatus; both already respect every
  -- real interaction (Mist/Substitute, Clear Body, Contrary/Simple,
  -- Mirror Armor, the status-immunity abilities). `fraction` is Spiky
  -- Shield's own 1/8 max-HP chip, written flat exactly as
  -- abilities/engine/contact_retaliation.lua's Iron Barbs/Aftermath
  -- already do (writing hp directly avoids recursing back through the
  -- very battle.damage hook this rider runs inside).
  ------------------------------------------------------------------
  local SHIELD_RIDERS = {
    KINGSSHIELD = { stat = "attack", stages = -1 },
    OBSTRUCT = { stat = "defense", stages = -2 },
    SILKTRAP = { stat = "speed", stages = -1, native = true },
    SPIKYSHIELD = { fraction = 1 / 8 },
    BANEFULBUNKER = { status = "poison" },
    BURNINGBULWARK = { status = "burn" },
  }

  -- Gen 1 exposes curTypes, Gen 2's mon carries .types; accept either so
  -- the same check works here and in the fengari harness.
  local function liveTypes(who)
    local t = who and (who.types or who.curTypes)
    if (not t or #t == 0) and mod.exports.curTypesOf then
      t = mod.exports.curTypesOf(who, true)
    end
    return t or {}
  end

  local function hasType(who, want)
    for _, t in ipairs(liveTypes(who)) do
      if t == want then return true end
    end
    return false
  end

  local function applyShieldRider(battle, attacker, shieldOwner, shieldMoveId, blockedMoveId, turn)
    if not (battle and attacker and shieldOwner and shieldMoveId) then return end
    local rider = SHIELD_RIDERS[shieldMoveId]
    if not rider then return end
    -- Every rider is contact-only in Showdown (checkMoveMakesContact).
    local makesContact = mod.exports.makesContact
    if not (makesContact and blockedMoveId and makesContact(blockedMoveId, attacker)) then
      return
    end
    -- Fire once per (turn, attacker) for this shield even if the engine
    -- routes the same move through battle.damage more than once
    -- (multi-hit moves call it per hit); Showdown's onTryHit fires once
    -- per move.
    turn = turn or 0
    shieldOwner.protectRiderKeys = shieldOwner.protectRiderKeys or {}
    local key = tostring(turn) .. ":" .. tostring(attacker)
    if shieldOwner.protectRiderKeys[key] then return end
    shieldOwner.protectRiderKeys[key] = true

    if rider.stat then
      if rider.native then
        -- Speed/accuracy/evasion are NATIVE stats this mod never tracks
        -- through changeStage -- Gen 2's own changeStageAgainstMist is
        -- the proven route (and emits its own message). The shield owner
        -- is passed as the `attacker` argument so the drop is Mist-gated
        -- as hostile, exactly like every other hostile Speed drop here.
        -- Gen 1 has no changeStageAgainstMist; the shared changeStage
        -- (gen2=false) covers those same three stats there.
        if battle.changeStageAgainstMist then
          battle:changeStageAgainstMist(shieldOwner, attacker, rider.stat, rider.stages)
        else
          local changeStage = mod.exports.changeStage
          if changeStage then
            for _, line in ipairs(changeStage(battle, attacker, rider.stat, rider.stages, true, false) or {}) do
              sayB(battle, line)
            end
          end
        end
      else
        local changeStage = mod.exports.changeStage
        if changeStage then
          for _, line in ipairs(changeStage(battle, attacker, rider.stat, rider.stages, true, true) or {}) do
            sayB(battle, line)
          end
        end
      end
    elseif rider.fraction then
      local m = attacker.mon or attacker
      local maxHp = m.stats and m.stats.hp
      if maxHp and maxHp > 0 then
        m.hp = math.max(0, (m.hp or 0) - math.max(1, math.floor(maxHp * rider.fraction)))
        sayB(battle, Strings("%s was hurt!", nameB(battle, attacker)))
      end
    elseif rider.status then
      -- applyStatus enforces ability immunity (status_immunity.lua) and
      -- the one-status-at-a-time + Safeguard rules natively, but NOT
      -- type immunity -- confirmed by direct read of gen2/Battle.lua
      -- :3396-3438 -- so it is checked here via the one shared helper
      -- (Phase 11: combat/modern_combat.lua's own statusTypeImmune):
      -- Fire can never be burned, Poison/Steel can never be poisoned.
      -- The shield owner is the inflicting SOURCE here, so Corrosion's
      -- real pierce of the poison half (Showdown sim/pokemon.ts:1710)
      -- still applies.
      local statusTypeImmune = mod.exports.statusTypeImmune
      local corrosionPiercesPoison = mod.exports.corrosionPiercesPoison
      local immune = statusTypeImmune and statusTypeImmune(battle, attacker, rider.status)
      local pierce = immune and corrosionPiercesPoison
        and corrosionPiercesPoison(shieldOwner)
      if not (immune and not pierce) then
        if battle.applyStatus then
          battle:applyStatus(attacker, rider.status, shieldOwner)
        elseif StatusRegistry and StatusRegistry.inflict then
          -- Gen 1 route: the same function its own ctx.inflict calls
          -- (EffectRegistry.makeCtx), so ability immunity and the
          -- one-status-at-a-time rule are enforced identically there.
          StatusRegistry.inflict(battle, attacker, rider.status,
            { source = shieldOwner })
        end
      end
    end
  end

  ------------------------------------------------------------------
  -- Part A: Protect's own move, plus every other block-shield move,
  -- sharing the one stall chain above. Detect (functionCode
  -- "ProtectUser", the same as Protect's own) is mechanically identical
  -- in every real generation -- same chain, same target flag. King's
  -- Shield, Spiky Shield, Baneful Bunker, Silk Trap, Burning Bulwark and
  -- Obstruct were previously NOT wired at all: national_dex hands them
  -- effect = "EFFECT_NORMAL_HIT" (confirmed by direct dump of
  -- data/moves/generated/registry_gen2.lua), a dead no-op for a power-0
  -- move, so they neither protected nor had a chain to decay. Each id's
  -- own contact rider (SHIELD_RIDERS above) is applied by Part B/Part D
  -- when the shield actually blocks a move.
  ------------------------------------------------------------------
  mod.content.move_effects:register(PROTECT_EFFECT_ID, {
    kind = "primary",
    run = function(a, b, c, d, e)
      local n = ctxOf(a, b, c, d, e)
      local out = {}
      -- A fresh use always starts from nothing: if the roll below fails,
      -- no flag -- stale or otherwise -- may be left standing. That is the
      -- reported "protecting despite failing" fixed at its source.
      clearProtection(n.user)
      if rollStall(n.battle, n.user) then
        raiseProtection(n.battle, n.user, "protect", n.moveId)
        say(n, out, Strings("%s protected itself!", nameOf(n, n.user)))
      else
        out.failed = true
        say(n, out, Strings("But it failed!"))
      end
      return out
    end,
  })
  local BLOCK_SHIELD_MOVES = {
    "PROTECT", "DETECT", "KINGSSHIELD", "SPIKYSHIELD", "BANEFULBUNKER",
    "SILKTRAP", "BURNINGBULWARK", "OBSTRUCT",
  }
  do
    -- Patched id-by-id, each pcall-guarded, so one unexpected/missing id
    -- can never abort the rest of this file's install (see the file
    -- header's own warning about that exact failure mode).
    local patched = 0
    for _, shieldMoveId in ipairs(BLOCK_SHIELD_MOVES) do
      local ok = pcall(function()
        mod.content.moves:patch(shieldMoveId, { effect = PROTECT_EFFECT_ID })
      end)
      if ok then patched = patched + 1
      else mod.log:warn("galar_gmax_dex: modern_combat_protect: could not patch %s", shieldMoveId) end
    end
    mod.log:info("galar_gmax_dex: modern_combat_protect: wired %d block-shield move(s) to the shared stall chain",
      patched)
  end

  ------------------------------------------------------------------
  -- Endure: shares the exact same stall chain (Showdown's own
  -- onPrepareHit/onHit are byte-identical to Protect's), but sets no
  -- blocking flag -- instead it arms Gen 2's native `endure` volatile,
  -- which Battle:dealDamage already reads to clamp a lethal hit to 1 HP
  -- ("<mon> endured the hit!", gen2/Battle.lua's dealDamage Endure arm).
  -- Also previously unwired (national_dex: "EFFECT_NORMAL_HIT"), so
  -- Endure did nothing at all.
  ------------------------------------------------------------------
  mod.content.move_effects:register(ENDURE_EFFECT_ID, {
    kind = "primary",
    run = function(a, b, c, d, e)
      local n = ctxOf(a, b, c, d, e)
      local out = {}
      if rollStall(n.battle, n.user) then
        -- Gen 2 has a native `endure` volatile (Battle:volatile); Gen 1
        -- has no Endure at all, so only the shared stall chain runs there.
        if n.gen2 then n.battle:volatile(n.user).endure = true end
        say(n, out, Strings("%s braced itself!", nameOf(n, n.user)))
      else
        out.failed = true
        say(n, out, Strings("But it failed!"))
      end
      return out
    end,
  })
  do
    local ok = pcall(function()
      mod.content.moves:patch("ENDURE", { effect = ENDURE_EFFECT_ID })
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_combat_protect: could not patch ENDURE")
    end
  end

  ------------------------------------------------------------------
  -- Part A2: Max Guard, rebuilt onto this same Protect chain instead of
  -- battle_forms's own original implementation. Confirmed by reading
  -- battle_forms/src/maxmoves.lua directly: its own M.GUARD_EFFECT sets
  -- `user.invulnerable = true` -- the engine's native semi-invulnerability
  -- flag (the same one Fly/Dig use), not a Protect-style flag at all, and
  -- with no concept of a Feint/Z-Move exception or a different rule
  -- against incoming Max/G-Max moves. Explicit user instruction (2026-08-20):
  -- combat sub-effects, including gimmick move interactions, are this
  -- mod's own domain -- so BATTLE_FORMS_MAXGUARD's effect is patched to
  -- point here instead, replacing battle_forms's invulnerable-flag
  -- approach outright rather than layering on top of it (both active at
  -- once would leave the native semi-invulnerability check ALSO blocking
  -- things this new effect intends to let through, e.g. Feint).
  --
  -- Shares Protect's own protectChainTurn/protectChainX counter fields
  -- (real games treat every member of the Protect family -- Protect,
  -- Detect, Max Guard, Spiky Shield, etc. -- as one shared decaying
  -- chain per Pokemon, not a separate counter per move), but sets a
  -- DIFFERENT target flag (maxGuarded, not protected) -- Part B below
  -- reads which flag is set to tell Max Guard's own 100%-blocks-
  -- everything-including-Max-Moves rule apart from plain Protect's
  -- 75%-blocks-Max-Moves rule.
  ------------------------------------------------------------------
  mod.content.move_effects:register(MAX_GUARD_EFFECT_ID, {
    kind = "primary",
    run = function(a, b, c, d, e)
      local n = ctxOf(a, b, c, d, e)
      mod.log:info("galar_gmax_dex: modern_combat_protect: [diag] Max Guard run() reached")
      local out = {}
      clearProtection(n.user)
      if rollStall(n.battle, n.user) then
        raiseProtection(n.battle, n.user, "guard", n.moveId)
        say(n, out, Strings("%s protected itself!", nameOf(n, n.user)))
      else
        out.failed = true
        say(n, out, Strings("But it failed!"))
      end
      return out
    end,
  })
  -- priority = 4 set explicitly, not left to patch-merge with
  -- battle_forms's own registration: explicit user instruction after
  -- live testing showed Max Guard's user taking no visible action/turn
  -- at all -- consistent with Max Guard losing its going-first priority
  -- and resolving after the incoming hit already landed instead of
  -- before it. battle_forms's own registerMove call already sets
  -- priority = 4 (src/maxmoves.lua:136) and Registry.lua's op-log/fold
  -- model should compose patches from different mods without one
  -- clobbering the other's fields -- but stating it here removes any
  -- doubt rather than trusting that merge silently, given the live
  -- symptom pointed straight at priority.
  --
  -- Called SYNCHRONOUSLY, right here, not deferred to any event --
  -- confirmed directly (src/mods/Loader.lua:1717 registry:freeze() runs
  -- BEFORE :1728's "mods.loaded" emit) that a mod.content.moves:patch
  -- call from a "mods.loaded" handler hits an already-frozen registry.
  -- A same-day attempt to defer this call there was reverted for exactly
  -- that reason -- it silently no-opped every time (Registry:patch on a
  -- frozen registry throws, and the event dispatcher's own protective
  -- pcall swallowed it with no visible error), confirmed by the Z-Move
  -- heuristic's own patched-count dropping from a real number to 0 and
  -- this block's own diagnostic never printing at all.
  --
  -- The real fix for battle_forms's load order is `battle_forms` now
  -- listed in THIS mod's own manifest.json optional_dependencies (see
  -- that file) -- a real graph edge (Loader.lua:739-749) that makes
  -- battle_forms's entire entry function, including every move it
  -- registers, finish running before this mod's own entry function ever
  -- starts, regardless of the two mods' raw priority numbers. battle_forms
  -- ALSO lists this mod as ITS OWN optional dependency, so this creates a
  -- genuine two-mod cycle -- confirmed the loader breaks exactly this
  -- shape deliberately rather than failing (Loader.lua:766-774,
  -- "optional dependency loop broken at %s", alphabetically-first id
  -- wins) -- "battle_forms" sorts before "g9-battle-engine", so the
  -- cycle resolves in the direction this file's own patch below needs.
  mod.content.moves:patch(MAX_GUARD_MOVE_ID, { effect = MAX_GUARD_EFFECT_ID, priority = 4 })

  -- Diagnostic: confirms both this patch and Registry's own fold
  -- actually landed, since reasoning about it in the abstract hasn't
  -- been reliable enough this session -- read back what the LIVE
  -- resolved record actually holds right after patching.
  do
    local ok, resolved = pcall(function() return mod.content.moves:get(MAX_GUARD_MOVE_ID) end)
    mod.log:info("galar_gmax_dex: modern_combat_protect: [diag] %s resolved as effect=%s priority=%s (ok=%s)",
      MAX_GUARD_MOVE_ID, tostring(ok and resolved and resolved.effect), tostring(ok and resolved and resolved.priority),
      tostring(ok))
  end

  -- "Is this a Max Move or G-Max move" -- explicit user spec: Protect
  -- reduces these to 25% damage (not a full block, unlike every other
  -- damaging move); Max Guard still blocks them entirely. Detected by
  -- battle_forms's own confirmed id convention (src/maxmoves.lua:38,
  -- M.PREFIX = "BATTLE_FORMS_", every Max/G-Max move stem starts with
  -- MAX/GMAX) rather than a hand-maintained id list, since this mod
  -- cannot read battle_forms's own data files directly (sandboxed
  -- mod:read refuses a path outside this mod's own folder) -- excludes
  -- Max Guard's own id specifically, which is a status move, not a
  -- damage-dealing one this rule ever applies to.
  local function isMaxMove(move)
    local id = move and move.id
    return id ~= nil and id ~= MAX_GUARD_MOVE_ID and id:match("^BATTLE_FORMS_G?MAX") ~= nil
  end

  ------------------------------------------------------------------
  -- Part B: block an incoming damaging move against a protected target.
  -- Priority 50, above modern_combat.lua's damage-formula hook (0) --
  -- runs first in the chain. ctx.user ~= ctx.target guards a protected
  -- mon's own follow-up self-targeting moves (Swords Dance, Recover,
  -- using Protect again) from ever being blocked by its own flag.
  --
  -- Explicit user spec, four rules in priority order:
  --   1. move.bypassesProtect (Feint, Z-Moves -- see Part E below for how
  --      Z-Moves get this flag) -- ignores any shield entirely, full
  --      damage, unchanged from before.
  --   2. target.maxGuarded -- 100% block of everything else, Max/G-Max
  --      moves included (Max Guard's whole point: it stops what plain
  --      Protect can't).
  --   3. target.protected + an incoming Max/G-Max move -- NOT a full
  --      block: next(ctx) runs the real formula, then the result is
  --      scaled to 25% (rounded to the nearest whole number, floor+0.5
  --      matching this file's own established rounding elsewhere).
  --   4. target.protected against anything else -- 100% block, unchanged
  --      from before.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local target = ctx.target
    if not (target and target ~= ctx.user) then return next(ctx) end
    if ctx.move and ctx.move.bypassesProtect then return next(ctx) end
    -- Side/field archetypes (Spikes, Reflect, Trick Room, weather) are not
    -- stopped by Protect; only a move that aims at the shielded battler is.
    if not targetsBattler(ctx.battle, ctx.move and ctx.move.id, ctx.move) then
      return next(ctx)
    end

    -- Turn-scoped: the flag only counts while it still belongs to the live
    -- turn (protectionOf above), so a stale flag can never block.
    local protection = protectionOf(ctx.battle, target)

    if protection == "guard" then
      return 0, { crit = false, typeMult = 0 }
    end

    if protection == "protect" then
      -- Unseen Fist / Piercing Drill (Phase 8, other bucket): both real,
      -- confirmed CONTACT-move-specific bypasses of an incoming Protect
      -- (checked against the ATTACKER's own ability, the real direction
      -- -- neither is about the defender). Unseen Fist: full damage,
      -- same as a Max move ignoring a plain Protect entirely never
      -- applies here since Unseen Fist isn't scaled at all. Piercing
      -- Drill: real text is explicit about a 1/4-damage bypass -- reuses
      -- the exact same 25% scale-down/rounding the Max-move branch just
      -- below already established, rather than a second rounding rule.
      local abilityIdOf = mod.exports.abilityIdOf
      local makesContact = mod.exports.makesContact
      local userAbility = abilityIdOf and ctx.user and abilityIdOf(ctx.user)
      local contact = makesContact and ctx.move and makesContact(ctx.move.id, ctx.user)
      if contact and userAbility == "UNSEENFIST" then
        return next(ctx)
      end
      if contact and userAbility == "PIERCINGDRILL" then
        local dmg, info = next(ctx)
        dmg = math.floor((dmg or 0) * 0.25 + 0.5)
        return dmg, info
      end
      if isMaxMove(ctx.move) then
        local dmg, info = next(ctx)
        dmg = math.floor((dmg or 0) * 0.25 + 0.5)
        return dmg, info
      end
      -- Fully blocked: fire this shield's own contact rider (King's
      -- Shield/Obstruct attack/defense drop, Silk Trap Speed drop,
      -- Spiky Shield 1/8 chip, Baneful Bunker/Burning Bulwark status).
      -- Only reached on a real, full block -- a bypass (Feint/Z-Move,
      -- Unseen Fist) or the 25% Max-move branch above is NOT a block, so
      -- no rider, matching Showdown's onTryHit early-returns.
      applyShieldRider(ctx.battle, ctx.user, target, target.protectShield,
        ctx.move and ctx.move.id, battleTurnOf(ctx.battle))
      return 0, { crit = false, typeMult = 0 }
    end

    return next(ctx)
  end, 50)

  ------------------------------------------------------------------
  -- Part C: turn-scoped cleanup. Runtime.emit("battle.turn_started", ...)
  -- fires once both sides have chosen and before either acts, before
  -- either battler's action executes -- so clearing here, then Protect's/
  -- Max Guard's own run() (above) re-setting a flag if used again this
  -- turn, always happens in the right order regardless of move order.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    -- Every battler, not just the native lead pair: the reported stale-flag
    -- leak was exactly the doubles/triples/boss case where the shielding
    -- mon was never battle.player/battle.enemy. mod.exports.allActiveBattlers
    -- is the mod's own N-way roster (combat/move_targeting.lua); the whole
    -- party is swept too, so a mon that switched out carrying a flag -- or
    -- switches in later this turn -- cannot carry one back in. All of this
    -- is belt-and-braces beside the turn stamp in protectionOf, which
    -- neutralises any flag the sweep somehow misses.
    local function sweep(list)
      for _, who in ipairs(list or {}) do clearProtection(who) end
    end
    local allActive = mod.exports.allActiveBattlers
    if allActive then
      local ok, list = pcall(allActive, battle)
      if ok and type(list) == "table" then sweep(list) end
    end
    sweep(battle.party)
    sweep(battle.playerParty)
    sweep(battle.enemyParty)
    clearProtection(battle.player)
    clearProtection(battle.enemy)
  end)

  ------------------------------------------------------------------
  -- Part C2: real, confirmed bug fix (2026-08-28, direct user report --
  -- "max guard and protect uses aren't doing the formula for lower
  -- chance till fail to restore 100% chance of passing"). The decay
  -- chain (protectChainX/protectChainTurn) is stored directly on the
  -- mon's own persistent table, NOT a per-battle volatile -- confirmed
  -- the same real shape this whole session's own established knowledge
  -- already flags repeatedly (Gen 2 mon tables are the persistent party
  -- members, the SAME table across every battle that mon ever fights).
  -- Real Showdown's own equivalent ("stall") is a genuine per-BATTLE
  -- volatile that clears automatically on switch-out and never exists
  -- at all in a fresh battle -- this mod's own fields had no such
  -- clearing anywhere (confirmed, grepped every reference to both
  -- fields in this whole mod: only ever read/written inside this same
  -- file's own two run() handlers above, never reset elsewhere), so a
  -- mon that had decayed down to 1/9 or lower stayed decayed forever
  -- after switching out and back in, or even into a LATER, completely
  -- separate battle -- exactly the reported symptom, "never restores
  -- 100%." Fixed the same real way modern_items.lua's own Ripen/Cheek
  -- Pouch state (ggdLastConsumedItem/ggdConsumedBerryThisBattle) already
  -- resets: on `battle.started` for the WHOLE party (every mon that
  -- might switch in fresh, not just the two currently active) and on
  -- `battle.battler_switched` for whichever mon just left (`ev.previous`
  -- -- the same real field Natural Cure/Regenerator already read for an
  -- identical "the mon that just left" need).
  ------------------------------------------------------------------
  local function clearProtectChain(mon)
    if not mon then return end
    mon.protectChainX = nil
    mon.protectChainTurn = nil
  end
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(battle.party or {}) do clearProtectChain(mon) end
    for _, mon in ipairs(battle.enemyParty or {}) do clearProtectChain(mon) end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    clearProtectChain(ev and ev.previous)
  end)

  ------------------------------------------------------------------
  -- Part E: Z-Moves bypass Protect/Max Guard entirely, same as Feint --
  -- explicit user spec. Unlike Feint (a fixed id already carrying
  -- bypassesProtect = true in this mod's own moves_new.lua), Z-Moves are
  -- ~100 individually-registered ids owned entirely by battle_forms, with
  -- no shared marker field on the registered record to test (confirmed
  -- by reading battle_forms/src/zmoves.lua and speciesz.lua's own
  -- mod.content.moves:register calls directly -- id/name/type/power/
  -- accuracy/pp/effect only, nothing like a `kind`/`zMove` flag) and no
  -- way to read battle_forms's own source data files to enumerate them
  -- properly (same sandboxing limit as isMaxMove above). Best-effort
  -- heuristic instead: every BATTLE_FORMS_-prefixed move that ISN'T a Max/
  -- G-Max move (isMaxMove above) and isn't a Tera Blast variant (a real,
  -- ordinary damaging move Tera just retypes, never Protect-exempt) gets
  -- the flag.
  --
  -- Confirmed bug, fixed here: this originally ran on "mods.loaded",
  -- reasoning that it needed to wait for battle_forms's own moves to be
  -- registered first. Direct read of src/mods/Loader.lua proved that
  -- reasoning backwards -- registry:freeze() (Loader.lua:1465) runs
  -- BEFORE "mods.loaded" is ever emitted (Loader.lua:1476), so every
  -- mod.content.moves:patch call in the original version was silently
  -- throwing "content is frozen after load" inside its own pcall, every
  -- single time -- this whole block was a no-op from the start. The real
  -- fix needs no event wait at all: mod loading is priority-ascending,
  -- ties broken by id (Loader.lua's own orderedIds/_order) -- confirmed
  -- battle_forms's manifest priority is 80, this mod's is 95, so
  -- battle_forms's entire entry function (including every move it
  -- registers) has already finished running by the time this mod's own
  -- entry function -- this line included -- starts. Runs synchronously,
  -- same as every other registration in this file. Logs exactly what it
  -- patched so this heuristic's real coverage is checkable rather than
  -- silently trusted.
  ------------------------------------------------------------------
  do
    -- Whole block pcall-guarded, not just each individual patch() call --
    -- confirmed real risk: if mod.content.moves:each() itself doesn't
    -- exist or throws for any reason, that was previously an UNCAUGHT
    -- error that would abort the rest of this file's install (Part D
    -- below, status-move blocking, never gets wired) and cascade further
    -- (nothing calling this file's install function catches errors
    -- either) -- exactly matching a live symptom of damage AND status
    -- effects both failing to be blocked together, not just Z-Move
    -- bypass being incomplete.
    local runOk, runErr = pcall(function()
      local patched = 0
      for id in mod.content.moves:each() do
        if type(id) == "string" and id:match("^BATTLE_FORMS_")
            and not isMaxMove({ id = id })
            and not id:match("^BATTLE_FORMS_TERA_BLAST") then
          local ok = pcall(function() mod.content.moves:patch(id, { bypassesProtect = true }) end)
          if ok then patched = patched + 1 end
        end
      end
      mod.log:info("galar_gmax_dex: modern_combat_protect: marked %d battle_forms move(s) as Protect/Max-Guard-bypassing (Z-Move heuristic)", patched)
    end)
    if not runOk then
      mod.log:warn("galar_gmax_dex: modern_combat_protect: Z-Move bypass heuristic errored, skipped (%s)", tostring(runErr))
    end
  end

  ------------------------------------------------------------------
  -- Part D: block an incoming pure status move (power == 0, a
  -- record.kind == "primary"/"secondary" effect) against a protected
  -- target. See the file header for why this can't reuse Part B's
  -- battle.damage hook and why it doesn't just skip useMove outright.
  --
  -- Own move/Detect/Max Guard being reapplied is never caught by this:
  -- attacker == defender whenever a mon targets itself, so `defender ~=
  -- attacker` already excludes it without needing to name PROTECT_
  -- EFFECT_ID/MAX_GUARD_EFFECT_ID specifically.
  ------------------------------------------------------------------
  if Battle then
    local nativeUseMove = Battle.useMove
    local nativeMoveEffectRecordFor = Battle.moveEffectRecordFor
    function Battle:useMove(attacker, defender, moveId)
      local blockable = defender and defender ~= attacker
        and protectionOf(self, defender) ~= nil
      if not blockable then
        return nativeUseMove(self, attacker, defender, moveId)
      end
      local ok, def = pcall(function() return self:moveDef(moveId) end)
      if not (ok and def and (def.power or 0) == 0 and not def.bypassesProtect
              and targetsBattler(self, moveId, def)) then
        return nativeUseMove(self, attacker, defender, moveId)
      end
      -- The move's OWN effect id: only this one lookup is swapped, so a
      -- recursive useMove or another effect looked up during the call still
      -- resolves normally.
      local gatedEffect = def.effect
      if gatedEffect == nil then
        return nativeUseMove(self, attacker, defender, moveId)
      end
      Battle.moveEffectRecordFor = function(data, effect)
        if effect ~= gatedEffect then
          return nativeMoveEffectRecordFor(data, effect)
        end
        -- Whatever kind the real record is -- a plain primary/secondary
        -- status record (Thunder Wave, Toxic, Taunt), a kind="full" record
        -- carrying its own run (Counter/Mirror Coat/Metal Burst), or a bare
        -- kind="full" marker (Seismic Toss and the fixed-damage family,
        -- which reach the native arm PAST this dispatch and never touch
        -- battle.damage at all) -- it is turned aside here. Only reached for
        -- a power-0, non-bypassing, battler-targeting move against a live
        -- shield, so nothing Protect should let through is intercepted.
        return {
          kind = "primary",
          run = function(battle)
            battle:emit({ kind = "message",
              text = Strings("It doesn't affect %s...", battle:monName(defender)) })
            -- A blocked status move still triggers a contact shield's
            -- rider if it makes contact (Showdown's onTryHit fires for
            -- any blocked move, status or damaging alike).
            applyShieldRider(battle, attacker, defender, defender.protectShield,
              moveId, battleTurnOf(battle))
          end,
        }
      end
      local callOk, callErr = pcall(nativeUseMove, self, attacker, defender, moveId)
      Battle.moveEffectRecordFor = nativeMoveEffectRecordFor
      if not callOk then
        mod.log:warn("galar_gmax_dex: modern_combat_protect: status-move block-check errored (%s)",
          tostring(callErr))
        error(callErr, 0)
      end
    end
  end

  ------------------------------------------------------------------
  -- Part D (Gen 1): the same rule as the Gen 2 wrap directly above, but
  -- Gen 1 has no Battle:useMove and no class-level moveEffectRecordFor.
  -- Its dispatch is BattleState:performMove, which resolves the effect
  -- record once at the top (BattleState.lua:4223) through
  -- self:effectRecord(move.effect) (:2687). Swapping that one lookup for
  -- the single call leaves all of native's PP decrement, "X used Y!"
  -- announcement and charge/accuracy handling untouched -- exactly the
  -- property the Gen 2 version was built for -- and replaces only the
  -- real status effect's run() with a "doesn't affect" stand-in that
  -- still fires the shield's contact rider.
  --
  -- Restricted to kind=="primary" records (that is the only kind gen 1's
  -- own `move.power == 0` branch dispatches through run()), and skips
  -- records with a `perform`/`callsMove`/`chooseDamage`/`charge` field so
  -- a fully-custom or charging move is never intercepted. maxGuarded is
  -- Gen 2-only, so only `protected` is reachable here; both are checked
  -- for symmetry with Part D above.
  ------------------------------------------------------------------
  if BattleState and rawget(BattleState, "performMove") and rawget(BattleState, "effectRecord") then
    local nativePerformMove = rawget(BattleState, "performMove")
    local nativeEffectRecord = rawget(BattleState, "effectRecord")
    function BattleState:performMove(user, target, moveInst, isCalled)
      if not (target and target ~= user and protectionOf(self, target) ~= nil) then
        return nativePerformMove(self, user, target, moveInst, isCalled)
      end
      local move = self:moveDef(moveInst)
      local moveId = (moveInst and moveInst.id) or (move and move.id) or moveInst
      if not (move and (move.power or 0) == 0 and not move.bypassesProtect
              and targetsBattler(self, moveId, move)) then
        return nativePerformMove(self, user, target, moveInst, isCalled)
      end
      local real = self:effectRecord(move.effect)
      if not (real and real.kind == "primary" and not real.perform
              and not real.callsMove and not real.chooseDamage and not real.charge) then
        return nativePerformMove(self, user, target, moveInst, isCalled)
      end
      local blockedName = nameB(self, target)
      local standin = {
        kind = "primary",
        run = function()
          applyShieldRider(self, user, target, target.protectShield,
            move.id, battleTurnOf(self))
          local out = {}
          out[#out + 1] = Strings and Strings("It doesn't affect\n%s!", blockedName)
            or ("It doesn't affect " .. blockedName .. "!")
          out.failed = true
          return out
        end,
      }
      local prev = rawget(self, "effectRecord")
      self.effectRecord = function(bs, effect)
        if effect == move.effect then return standin end
        return nativeEffectRecord(bs, effect)
      end
      local ok, err = pcall(nativePerformMove, self, user, target, moveInst, isCalled)
      self.effectRecord = prev
      if not ok then error(err, 0) end
    end
  end

  mod.log:info("galar_gmax_dex: modern_combat_protect loaded")
end
