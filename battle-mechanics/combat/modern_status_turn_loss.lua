-- Real ownership of the paralysis/sleep/freeze turn-loss DECISION,
-- replacing native cartridge-accurate logic with real, current Showdown
-- mechanics -- verified directly against Pokemon Showdown's own real
-- source (data/conditions.ts) before writing any of this, not from
-- memory. Standing project principle (turn_order.lua's own header: "we
-- are the bible and process of combat" -- extended here to status-based
-- turn loss, not just move ordering): the native engine only executes a
-- decision this mod hands it, it never independently decides an outcome
-- via its own RNG. Confirmed BEFORE this file existed that the ported
-- native logic violated this twice over -- not just in ownership, but in
-- accuracy:
--   PARALYSIS: native rolls 63/256 (~24.6%, Gen 1's own byte-based
--     approximation) -- real current rate is exactly 25% (Showdown's own
--     `this.randomChance(1, 4)`).
--   SLEEP: native duration is `rng(1,7)` (Gen 1's own cartridge range)
--     -- real current duration is 1-3 turns lost, uniform (Showdown's
--     own `this.random(2, 5)`, pre-decremented before the first check).
--     Native ALSO always returns "lose the turn" even on the exact turn
--     the mon wakes up -- real current rule lets a mon act immediately
--     on the turn it wakes (Showdown's own bare `return;` -- no value --
--     on the woken branch, vs an explicit `return false` for "still
--     asleep"). Because the wake now happens ON the turn the counter
--     reaches zero (and that turn is PLAYED, not lost), the stored roll
--     must be one higher than the number of turns actually lost: the roll
--     is 2-4 (matching Showdown's `random(2, 5)`, which is 2/3/4), giving
--     1/2/3 lost turns. ROUND 33 FIX: the roll was 1-3, so a freshly
--     inflicted sleep could wake with ZERO lost turns -- impossible in the
--     real games. Applies to both the Gen 1 record and the Gen 2 one.
--     Rest deliberately sets its counter directly (3 -> 2 lost turns,
--     matching Showdown's own `target.statusState.time = 3`), not through
--     `onInflict` -- see THIS file's own Rest note further down.
--   FREEZE: Gen 1's ported native has NO thaw roll AT ALL (`beforeMove`
--     unconditionally returns "still frozen," confirmed by direct read)
--     -- a Gen 1 battle's frozen mon never thaws on its own under the
--     pre-existing code. Gen 2's own native DOES roll (`Battle
--     .THAW_CHANCE`) but at Gen 2's own cartridge rate, not real current
--     Showdown's exactly 20% (`this.randomChance(1, 5)`).
--
-- Monkeypatches each status's own `beforeMove` (and Sleep's own
-- `onInflict`, for the duration roll) directly -- Gen 1's `Status
-- .RECORDS.PAR/SLP/FRZ`, Gen 2's `Battle.STATUSES.paralyze/sleep/
-- freeze` -- the same surgical, per-status-record pattern already
-- proven safe for Poison Heal/Heatproof/Magic Guard's own residual
-- patches. Each replacement keeps the EXACT return contract the engine
-- already consumes (Gen 1: `(canAct, msgs)`; Gen 2: `canAct` plus its
-- own `battle:emit` calls) -- the engine still just executes a decision
-- handed to it, only the decision itself is now ours.
--
-- Early Bird (abilities/data/*.lua's own Phase 8 deferral list named
-- this as unbuilt) is closed here for free, since it's the exact same
-- code path: real rule (Showdown's own `if (pokemon.hasAbility
-- ('earlybird')) { pokemon.statusState.time--; }`) is a SECOND
-- decrement per turn, halving effective sleep duration.
--
-- Sleep Talk/Snore (real moves usable while asleep, Showdown's own
-- `move.sleepUsable` flag) -- national_dex's own moveFlags has no
-- equivalent flag (confirmed, grepped flags.lua directly), so this is a
-- small, real, necessary hardcoded pair -- the same class of thing
-- CRASH_DAMAGE_MOVES/ROOM_MOVE_FLAG already are, not a violation of the
-- "read live, don't hardcode" discipline (there is nothing to read).
return function(mod)
  local abilityIdOf = mod.exports.abilityIdOf

  local function percentRoll(gen2, battle, chance)
    if gen2 then return battle.random(100) < chance end
    return battle.rng(1, 100) <= chance
  end
  local function rangeRoll(gen2, battle, lo, hi)
    if gen2 then return lo + battle.random(hi - lo + 1) end
    return battle.rng(lo, hi)
  end

  local SLEEP_USABLE_MOVES = { SLEEPTALK = true, SNORE = true }

  ------------------------------------------------------------------
  -- Gen 1
  ------------------------------------------------------------------
  local Status = require("src.battle.Status")

  Status.RECORDS.PAR.beforeMove = function(battler, rng, battle)
    local romText = require("src.core.RomText")
    if percentRoll(false, battle, 25) then
      return false, { romText(battle and battle.data, "_FullyParalyzedText",
        "%s's\nfully paralyzed!", battler.name) }
    end
    return true, {}
  end

  Status.RECORDS.SLP.onInflict = function(battle, target, opts, display)
    -- 2-4, not 1-3: beforeMove wakes the mon on the turn this reaches
    -- zero AND lets it act that turn, so the pre-decrement roll is the
    -- lost-turn count plus one (Showdown's `random(2, 5)`). See header.
    target.sleepTurns = rangeRoll(false, battle, 2, 4)
    local romText = require("src.core.RomText")
    return { romText(battle.data, "_FellAsleepText", "%s\nfell asleep!", display) }
  end
  Status.RECORDS.SLP.beforeMove = function(battler, rng, battle)
    local romText = require("src.core.RomText")
    local dec = (abilityIdOf and abilityIdOf(battler) == "EARLYBIRD") and 2 or 1
    battler.sleepTurns = (battler.sleepTurns or 1) - dec
    if battler.sleepTurns <= 0 then
      battler.mon.status = nil
      battler.sleepTurns = nil
      return true, { romText(battle and battle.data, "_WokeUpText", "%s\nwoke up!", battler.name) }
    end
    return false, { romText(battle and battle.data, "_FastAsleepText", "%s\nis fast asleep!", battler.name) }
  end

  Status.RECORDS.FRZ.beforeMove = function(battler, rng, battle)
    local romText = require("src.core.RomText")
    if percentRoll(false, battle, 20) then
      battler.mon.status = nil
      return true, { romText(battle and battle.data, "_ThawedOutText", "%s\nthawed out!", battler.name) }
    end
    return false, { romText(battle and battle.data, "_IsFrozenText", "%s\nis frozen solid!", battler.name) }
  end

  ------------------------------------------------------------------
  -- Gen 2
  ------------------------------------------------------------------
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil

  if Battle then
    -- Gen 2's own messages go through the engine's Strings() like Gen 1's
    -- romText() above: the English source is the catalog key the translation
    -- mods override (mod.content.strings), so real combat narration
    -- translates instead of being built by concatenation. Every template
    -- below is the engine's own key -- the same wording its native paths
    -- print -- so a translation the mod already carries applies verbatim.
    local Strings = require("src.core.Strings")
    Battle.STATUSES.paralyze.beforeMove = function(battle, mon, name)
      if percentRoll(true, battle, 25) then
        battle:emit({ kind = "message", text = Strings("%s's fully paralyzed!", name) })
        return false
      end
      return true
    end

    Battle.STATUSES.sleep.onInflict = function(battle, mon)
      -- 2-4, not 1-3 -- the same off-by-one the Gen 1 record above had:
      -- beforeMove wakes on the turn the counter hits zero and the mon
      -- acts, so the stored roll is `lost turns + 1`. See this file's
      -- header for the full reasoning and the Showdown citation.
      mon.statusTurns = rangeRoll(true, battle, 2, 4)
    end
    Battle.STATUSES.sleep.beforeMove = function(battle, mon, name)
      local dec = (abilityIdOf and abilityIdOf(mon) == "EARLYBIRD") and 2 or 1
      mon.statusTurns = (mon.statusTurns or 1) - dec
      if mon.statusTurns <= 0 then
        mon.status = nil
        mon.statusTurns = nil
        battle:emit({ kind = "message", text = Strings("%s woke up!", name) })
        return true
      end
      battle:emit({ kind = "message", text = Strings("%s is fast asleep!", name) })
      return false
    end

    Battle.STATUSES.freeze.beforeMove = function(battle, mon, name)
      if percentRoll(true, battle, 20) then
        mon.status = nil
        battle:emit({ kind = "message", text = Strings("%s thawed out!", name) })
        return true
      end
      battle:emit({ kind = "message", text = Strings("%s is frozen solid!", name) })
      return false
    end

    ------------------------------------------------------------------
    -- Toxic's ramp (ROUND 33). Real current Showdown (data/conditions.ts,
    -- the `tox` entry, fetched and read this pass, not recalled):
    --     onResidual(pokemon) {
    --       if (this.effectState.stage < 15) this.effectState.stage++;
    --       this.damage(clampIntRange(pokemon.baseMaxhp / 16, 1) * this.effectState.stage);
    --     }
    -- so the nth tick is `max(1, floor(maxHp / 16)) * stage`, and the ramp
    -- HARD CAPS at stage 15 (a Gen 4+ rule; the pre-existing native Gen 2
    -- residual here was `max(1, floor(maxHp * counter / 16))` with NO cap,
    -- which also drifts from Showdown at high stages because it floors the
    -- product rather than the per-turn slice). Re-pointed here, the same
    -- in-place record swap this file already does for paralysis/sleep/
    -- freeze. `onInflict`'s `mon.toxicCounter = 1` stays native -- it is the
    -- stage the residual reads, and the reset-on-switch half of the real
    -- mechanic lives in combat/status_condition_cleanup.lua.
    Battle.STATUSES.toxic.residual = function(_, mon, maxHp)
      local stage = mon.toxicCounter or 1
      if stage < 15 then mon.toxicCounter = stage + 1 end
      return math.max(1, math.floor(maxHp / 16)) * stage,
        Strings(" is hurt by poison!")
    end
  end

  ------------------------------------------------------------------
  -- Rest's own sleep length, Gen 1 (ROUND 33). Native Gen 1 MoveEffects
  -- .HEAL_EFFECT writes `user.sleepTurns = 2` directly (bypassing
  -- SLP.onInflict, so the roll above never runs for Rest). That value
  -- was tuned for the OLD sleep semantics, where the wake turn was still
  -- lost; under this file's own real-current rule -- the mon wakes AND
  -- acts on the turn the counter reaches zero -- a stored 2 wakes after
  -- only ONE lost turn, where the real games (and this mod's own Gen 2
  -- Rest, whose native handler writes `statusTurns = 3`) give TWO.
  -- Showdown is explicit: data/moves.ts's own `rest` sets
  -- `target.statusState.time = 3` (and `startTime = 3`). So the Gen 1
  -- record's `run` is wrapped in place to bump Rest's counter to 3 AFTER
  -- the native body writes 2 -- mutating the existing record table
  -- rather than replacing it, because MoveEffects.registerInto has
  -- already handed this exact table to the live move-effect registry by
  -- reference (a fresh table assignment would never be seen).
  do
    local ok, MoveEffects = pcall(require, "src.battle.MoveEffects")
    local record = ok and MoveEffects and MoveEffects.RECORDS
      and MoveEffects.RECORDS.HEAL_EFFECT
    if record and type(record.run) == "function" then
      local nativeRun = record.run
      record.run = function(ctx)
        local msgs = nativeRun(ctx)
        if ctx and ctx.move and ctx.move.id == "REST" and ctx.user then
          ctx.user.sleepTurns = 3
        end
        return msgs
      end
    else
      mod.log:warn("g9-battle-engine: modern_status_turn_loss could not wrap Gen 1 Rest's sleep length (MoveEffects.RECORDS.HEAL_EFFECT not found)")
    end
  end

  mod.log:info("g9-battle-engine: modern_status_turn_loss installed (real Gen 9 paralysis 25%%/sleep 1-3 turns lost/freeze 20%% thaw, both engines, Early Bird wired, Rest = 2 lost turns both generations, toxic ramp capped at 15/16)")
end
