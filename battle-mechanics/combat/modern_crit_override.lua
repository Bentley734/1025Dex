-- Phase 3 of the missing-effects pipeline: critical-hit overrides -- the
-- moves that ALWAYS crit, and Laser Focus's guaranteed-crit volatile.
--
-- Showdown source of truth (scratch/showdown/battle-actions.ts):
--   getDamage        (1585-1649) `moveHit.crit = move.willCrit || false;`
--                    when `move.willCrit === undefined` it instead rolls
--                    `randomChance(1, critMult[critRatio])`. THEN, whichever
--                    way crit was decided, `if (moveHit.crit) moveHit.crit =
--                    this.battle.runEvent('CriticalHit', target, null, move)`
--                    -- i.e. an always-crit move STILL runs the CriticalHit
--                    event, which is exactly how Battle Armor / Shell Armor
--                    negate it. The override is therefore a guaranteed crit,
--                    not an unconditional one.
--   moves.ts         flowertrick (5882), frostbreath (6259), stormthrow
--                    (18131), surgingstrikes (18540), wickedblow (20776) --
--                    each carries `willCrit: true`; flowertrick also carries
--                    `accuracy: true` (its sure-hit). surgingstrikes is
--                    `multihit: 3` (handled generically off national_dex's
--                    own minHits/maxHits by main.lua).
--   laserfocus       (10013-10044) move: `volatileStatus: 'laserfocus'`,
--                    target "self", `condition.duration = 2`, and
--                    `onModifyCritRatio(critRatio) { return 5; }` -- crit
--                    ratio 5 clamps to the guaranteed tier in the modern
--                    rate table (battle-actions.ts:1625-1636, gen >= 6).
--                    `onEnd` is silent (`[silent]`), so no end message.
--
-- How national_dex carries `willCrit`: the generated api records encode it
-- as `critRate = 6` -- a deliberate sentinel, NOT a stage count. Confirmed by
-- parsing all 833 records this round: critRate is 0 for ordinary moves, 1 for
-- the 25 real high-crit moves (AEROBLAST, CRABHAMMER, ...), and exactly 6 for
-- the five always-crit moves above -- the same 5/25/803 split Showdown's own
-- `willCrit` / high-critRatio data produces. main.lua's wireMovepoolSubEffects
-- therefore patches `alwaysCrit = true` (instead of `highCrit = true`) for
-- critRate >= 6, and `sureHit = true` for a critRate >= 6 move whose dex
-- accuracy is 0 (Flowertrick's `accuracy: true`).
--
-- The override rides modern_combat.lua's existing crit STAGE modifier chain
-- rather than a new forceCrit seam: a stage-3 result is the guaranteed tier
-- (CRIT_STAGE_DENOM[3] = 1), and modernCritRoll still consults Battle Armor /
-- Shell Armor BEFORE the stage lookup, so the guaranteed crit is correctly
-- overridden by a crit-immune holder -- the CriticalHit-event behaviour above.
return function(mod)
  local Strings = require("src.core.Strings")
  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  local registerCritStageModifier = mod.exports.registerCritStageModifier
  assert(normalize and displayNameFor and isGen2Battle and registerCritStageModifier,
    "modern_crit_override: combat/modern_combat.lua must load first")

  ------------------------------------------------------------------
  -- (1) Always-crit moves (Wicked Blow, Surging Strikes, Frost Breath,
  -- Storm Throw, Flower Trick): a guaranteed crit via the stage chain.
  ------------------------------------------------------------------
  registerCritStageModifier("alwayscrit_moves", function(ctx)
    local move = ctx and ctx.move
    if move and move.alwaysCrit then return 3 end
    return 0
  end)

  ------------------------------------------------------------------
  -- (2) Laser Focus: a duration-2 self volatile granting a guaranteed
  -- crit (the modern-tier equivalent of Showdown's crit-ratio 5).
  ------------------------------------------------------------------
  -- The flag lives directly on the mon (Gen 2's party table; Gen 1's wrapper
  -- .mon), like the rest of this mod's switch-scoped direct fields, and is
  -- listed in status_condition_cleanup.lua's SWITCH_SCOPED so a switch-out
  -- clears it. The engine's own battle.turn_ended pass decrements it.
  local LASER_FOCUS_TURNS = 2

  local function monOf(who, gen2)
    if not who then return nil end
    return (gen2 and who) or who.mon
  end

  registerCritStageModifier("laserfocus", function(ctx)
    local user = ctx and ctx.user
    if not user then return 0 end
    local turns = user.laserFocusTurns or (user.mon and user.mon.laserFocusTurns)
    if turns and turns > 0 then return 3 end
    return 0
  end)

  mod.content.move_effects:register("GALAR_LASERFOCUS_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local out = {}
      local m = monOf(n.user, n.gen2)
      if m then
        m.laserFocusTurns = LASER_FOCUS_TURNS
        out[#out + 1] = Strings("%s\nis focusing!", displayNameFor(n.battle, n.user, n.gen2))
      end
      if n.gen2 then
        for i = 1, #out do
          n.battle:emit({ kind = "message", text = out[i] })
        end
        return {}
      end
      return out
    end,
  })

  -- Duration tick: Showdown decrements a volatile's duration before running
  -- its residual/end, so duration 2 grants the crit for the user's next turn
  -- and expires at the end of it.
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    local actives = (mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle))
      or { battle.player, battle.enemy }
    for i = 1, #actives do
      local m = monOf(actives[i], gen2)
      if m and m.laserFocusTurns then
        m.laserFocusTurns = m.laserFocusTurns - 1
        if m.laserFocusTurns <= 0 then m.laserFocusTurns = nil end
      end
    end
  end)

  ------------------------------------------------------------------
  -- (3) Flower Trick's sure-hit. Gen 2 already reads a non-positive dex
  -- accuracy as "never misses" (gen2/Battle.lua:2262-2263, moveAccuracy
  -- passes <= 0 straight through and Damage.rollHit treats it as a sure
  -- hit), so this is a no-op there -- but Gen 1's percent-domain threshold
  -- turns acc = 0 into ~255/256 miss (the pre-existing bug flagged this
  -- round), so an explicit wrap makes the sure-hit true on BOTH engines.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.accuracy", function(nextFn, ctx)
    if ctx and ctx.move and ctx.move.sureHit then return true end
    return nextFn(ctx)
  end, 45)

  ------------------------------------------------------------------
  -- (4) Dragon Cheer: a crit-ratio volatile on the user's ADJACENT ALLIES
  -- (never the user). Real Showdown moves.ts:4057+ -- `target:
  -- "adjacentAlly"`, `volatileStatus: 'dragoncheer'`, whose condition
  -- `onModifyCritRatio` returns `critRatio + (hasDragonType ? 2 : 1)` and
  -- whose `onStart` returns false when the target already holds Focus
  -- Energy. national_dex labels it `all-allies` (the allies, user
  -- excluded -- the same scope the real move has). This is exactly the
  -- ally-side status move combat/structural_exemptions.lua used to list as
  -- unobservable ("no allied battler => empty target set"), so that
  -- exemption is retired now that real ally slots exist. `hasDragonType`
  -- is frozen at application time (the real volatile's own comment: the
  -- boost doesn't change if the recipient later Terastallizes into
  -- Dragon), and both fields are switch-scoped (see status_condition_
  -- cleanup.lua).
  ------------------------------------------------------------------
  local function rawMon(who) return who and (who.mon or who) or nil end
  local function showName(battle, who, gen2)
    local nameOf = mod.exports.g9NameOf
    if nameOf then
      local ok, nm = pcall(nameOf, battle, who)
      if ok and nm then return nm end
    end
    return displayNameFor(battle, who, gen2)
  end

  registerCritStageModifier("dragoncheer", function(ctx)
    local user = ctx and ctx.user
    if not user then return 0 end
    local m = rawMon(user)
    if m and m.dragonCheer then
      return m.dragonCheerDragon and 2 or 1
    end
    return 0
  end)

  mod.content.move_effects:register("GALAR_DRAGONCHEER_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      local curTypesOf = mod.exports.curTypesOf
      local requestAdjacency = mod.exports.requestAdjacency
      local allies = {}
      if requestAdjacency then
        local ok, adj = pcall(requestAdjacency, battle, n.user, nil)
        if ok and adj and adj.allies then
          for _, ally in ipairs(adj.allies) do allies[#allies + 1] = ally end
        end
      end
      local applied = 0
      for _, ally in ipairs(allies) do
        local m = rawMon(ally)
        -- onStart: a recipient already holding Focus Energy is skipped
        -- (the two crit volatiles do not stack), just as in Showdown.
        if m and not m.focusEnergy then
          local isDragon = false
          if curTypesOf then
            local ok2, types = pcall(curTypesOf, ally, n.gen2)
            if ok2 then
              for _, t in ipairs(types or {}) do
                if t == "DRAGON" then isDragon = true break end
              end
            end
          end
          m.dragonCheer = true
          m.dragonCheerDragon = isDragon
          applied = applied + 1
          battle:emit({ kind = "message",
            text = Strings("%s's critical-hit ratio rose!", showName(battle, ally, n.gen2)) })
        end
      end
      if applied == 0 then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
      end
    end,
  })

  mod.log:info("g9-battle-engine: modern_crit_override installed "
    .. "(always-crit: WICKEDBLOW/SURGINGSTRIKES/FROSTBREATH/STORMTHROW/FLOWERTRICK; "
    .. "LASERFOCUS guaranteed-crit volatile; Flower Trick sure-hit; "
    .. "DRAGONCHEER ally-side crit volatile)")
end
