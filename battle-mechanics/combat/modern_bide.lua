-- ============================================================================
-- BIDE (move 117) -- the store-and-release counter, on BOTH generations.
-- ============================================================================
-- Round 341 (2026-09-25, direct user report: "Bide is used and nothing
-- happens ... follow bide logic of pokemon showdown gen7 ... bide user
-- shouldn't be able to act during bide state duration ... pain split must
-- not contribute to accumulated damage").
--
-- WHY IT DID NOTHING.  national_dex's takeover gives BIDE a `modernMove`
-- record whose `effect` is NO_ADDITIONAL_EFFECT (Gen 1) / EFFECT_NORMAL_HIT
-- (Gen 2) and whose power is 0.  That record REPLACES the cart's own native
-- BIDE effect id, so the native Bide machine (Gen 1's BIDE_EFFECT /
-- continueBide / applyDamage storage; Gen 2's EFFECT_BIDE / bideStored
-- storage) never started -- using the move just spent a turn and printed
-- "used BIDE!" with no state set.  This file re-homes the whole mechanic
-- under a cross-generation id (`GALAR_BIDE_EFFECT`, wired by main.lua's
-- CUSTOM_EFFECT_PATCH) exactly the way modern_movepool_damage.lua re-homes
-- Outrage/Bounce: a custom id registered fresh every boot, valid on both.
--
-- SHOWDOWN REFERENCE (data/moves.ts, `bide`; gen7 inherits it unchanged --
-- gen5/gen6 have no override, gen3 overshoots it with its own priority 0,
-- so the modern master is the gen7 answer).  Its condition is
-- `duration: 3` with `onLockMove: 'bide'`; duration ticks DOWN at the end of
-- each turn, and the release fires on the turn it reads 1 -- i.e. the player
-- uses Bide, WAITS one whole turn, then hits on the very next one.  In a
-- "turns still to run AFTER the use turn" counter that is exactly 2:
-- continuation 1 = wait, continuation 2 = release.  Both generations here
-- use that same fixed 2, so Bide is Showdown's fixed three-turn move on both
-- (NOT the cart's old random 2-3).
--
-- WHAT ACCUMULATES.  Showdown's `onDamage` adds every damaging MOVE hit the
-- user takes (it requires a real Move with a source; recoil, confusion
-- self-damage and other source-less chip are excluded), and the release deals
-- `totalDamage * 2` as a typeless fixed hit.  Pain Split is the user's own
-- explicit example: it does not "deal damage" at all in Showdown (it rewrites
-- HP), and this mod's GALAR_PAINSPLIT_EFFECT likewise writes `mon.hp`
-- directly -- so it never reaches either engine's damage path and cannot enter
-- the store.  That is a property worth stating because a naive "sum every HP
-- loss" would wrongly bank it.
--
-- PER GENERATION, deliberately split the way every other dual-gen effect in
-- this mod is:
--   * GEN 1 uses the cart's OWN machine.  `chooseDamage` only STARTS the
--     store (sets the native battler's `bideTurns` / `bideDamage`); the
--     scene's Gen 1 executor then runs the cart's native
--     `BattleState:continueBide` for the wait/release beats (see
--     g9-Battle-Scene/native.lua's bide arm), and the cart's own
--     `applyDamage` does the accumulation.  That is the lowest-risk, most
--     cartridge-faithful arm -- Bide's damage delivery, animation, Substitute
--     and Rage interactions all stay exactly the native ones.
--   * GEN 2 has no reachable native EFFECT_BIDE (the record's effect was
--     replaced), so `run` owns the whole lifecycle: start / wait / release,
--     accumulating through the native `Battle:dealDamage` (which already
--     banks into `bideStored` for a biding defender) and delivering the
--     release as a routed fixed hit through `battle:dealDamage`.
--
-- LOCK.  `combat/move_usability.lua` gained a Bide gate: while the store is
-- live, every move but BIDE is refused to the scene's menu (and to the AI),
-- so the user genuinely cannot act until it releases -- Showdown's
-- `onLockMove: 'bide'`, the cart's `fightLockedAction`.
-- ============================================================================
return function(mod)
  local Strings = require("src.core.Strings")
  local normalize = mod.exports.normalize
  assert(normalize, "modern_bide: combat/modern_combat.lua must load first")

  -- Showdown gen7's fixed store length, expressed as "continuations still to
  -- run after the use turn": 1 wait + the release.  See the header.
  local BIDE_CONTINUATIONS = 2

  -- Give back the PP a continuation spent.  Gen 2's native useMove decrements
  -- PP before any effect runs and only SKIPS that for `def.effect ==
  -- "EFFECT_BIDE"` (gen2/Battle.lua:1517) -- an id this cross-generation
  -- record deliberately does not use.  The cart's own Bide continuation never
  -- reaches the move executor at all (fightLockedAction -> continueBide), so
  -- Bide costs exactly ONE PP for the whole store-and-release; refunding one
  -- per continuation reproduces that exactly (and keeps the scene's 0-PP
  -- filter from ever refusing the locked move).
  local function refundPp(user, moveId)
    local mon = user and (user.mon or user)
    if not (mon and moveId) then return end
    for _, slot in ipairs(mon.moves or {}) do
      if slot and slot.id == moveId then
        local maxPp = slot.maxPp or slot.pp or 0
        slot.pp = math.min(maxPp, (slot.pp or 0) + 1)
        return
      end
    end
  end

  mod.content.move_effects:register("GALAR_BIDE_EFFECT", {
    -- "full" (not "primary"): Gen 1's EffectRegistry offers a `full` record's
    -- chooseDamage the real damaging pipeline, which is how a fixed-damage
    -- move (Seismic Toss, the counter family) delivers its number.  `run` is
    -- ignored by Gen 1 for this kind (EffectRegistry only calls run for a
    -- non-primary record when chooseDamage is absent), so the two arms cannot
    -- both fire on one generation.
    kind = "full",

    -- -- GEN 1: start the cart's own store ------------------------------------
    -- Only the START lives here -- continueBide (run by the scene on the
    -- wait/release turns) does the rest natively.  Returning (nil, text)
    -- fails the move with that text already chosen (EffectRegistry's own
    -- "counter/Super Fang/fixed damage" branch), which is exactly how the
    -- native BIDE_EFFECT's store turn reads: no damage, one line of flavour.
    chooseDamage = function(ctx)
      local battle, user, target = ctx.battle, ctx.user, ctx.target
      local displayNameFor = mod.exports.displayNameFor
      local name = (displayNameFor and displayNameFor(battle, user, false)) or "???"
      if not user.bideTurns then
        user.bideTurns = BIDE_CONTINUATIONS
        user.bideDamage = 0
        return nil, Strings("%s\nis storing energy!", name)
      end
      -- Defensive fallback only: the scene routes a live store straight into
      -- BattleState:continueBide, so this is reached only if that method is
      -- missing from the running build.  Without it the store could never
      -- release and Bide would hang forever.
      user.bideTurns = user.bideTurns - 1
      if user.bideTurns > 0 then
        return nil, Strings("%s\nis storing energy!", name)
      end
      local dmg = math.min(0xffff, (user.bideDamage or 0) * 2)
      local stored = user.bideDamage
      user.bideTurns, user.bideDamage = nil, nil
      if stored == nil or dmg <= 0 then
        return nil, Strings("But, it failed!")
      end
      -- A typeless fixed hit: route it through battle.damage so Protect,
      -- Wonder Guard and the rest of the shared chain still get first refusal
      -- (the same route the counter family uses), with typeMult 10 = fully
      -- resolved neutral.
      local route = mod.exports.routeThroughBattleDamage
      if route then
        local d1, d2 = route(battle, user, target, ctx.move, dmg,
          { crit = false, typeMult = 10 }, false)
        return d1, d2
      end
      return dmg, { crit = false, typeMult = 10 }
    end,

    -- -- GEN 2: the whole lifecycle ------------------------------------------
    -- Gen 2's dispatch calls `run` for any registered record and then returns
    -- without touching its own damage path, so this is the delivery point.
    -- Guarded to Gen 2 so it cannot double-run beside chooseDamage on Gen 1
    -- (the exact trap modern_movepool_counter.lua's own run documents).
    run = function(a, b, c, d, e)
      local n = normalize(a, b, c)
      if not n.gen2 then return {} end
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user and target) then return {} end
      local def, moveId = d, e
      local displayNameFor = mod.exports.displayNameFor
      local name = (displayNameFor and displayNameFor(battle, user, true)) or "???"
      local state = battle:volatile(user)

      if not state.bideTurns then
        state.bideTurns = BIDE_CONTINUATIONS
        state.bideStored = 0
        -- The native state `Battle:forcedMove` reads to keep the user locked
        -- onto Bide (the same field Encore/Rollout-lock answer through).
        state.bideMove = moveId
        battle:emit({ kind = "message",
          text = Strings("%s\nis storing energy!", name) })
        return {}
      end

      refundPp(user, moveId)
      state.bideTurns = state.bideTurns - 1
      if state.bideTurns > 0 then
        battle:emit({ kind = "message",
          text = Strings("%s\nis storing energy!", name) })
        return {}
      end

      -- The native `Battle:dealDamage` has already banked every hit the user
      -- took into state.bideStored (gen2/Battle.lua:1338-1341) -- Pain Split
      -- never routes through it, so it is not in here.
      local dmg = math.min(0xffff, (state.bideStored or 0) * 2)
      state.bideTurns, state.bideStored, state.bideMove = nil, nil, nil
      battle:emit({ kind = "message",
        text = Strings("%s\nunleashed energy!", name) })
      if dmg <= 0 then
        battle:markMissed()
        battle:emit({ kind = "message", text = Strings("But, it failed!") })
        return {}
      end
      local route = mod.exports.routeThroughBattleDamage
      local dealt = dmg
      if route then
        dealt = route(battle, user, target, def, dmg,
          { crit = false, typeMult = 10 }, true)
      end
      battle:dealDamage(user, target, dealt, { move = def, moveId = moveId })
      return {}
    end,
  })

  mod.log:info("g9-battle-engine: modern_bide loaded (GALAR_BIDE_EFFECT)")
end
