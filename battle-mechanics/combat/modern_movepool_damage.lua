-- Phase 2 (part 2) of the move-effect completion pipeline: moves_new.lua's
-- recoil/drain/heal stubs (8 moves) and its two-turn/charge/recharge stubs
-- (3 moves: Bounce, Outrage, Eternabeam). Grouped in one file, not two --
-- both buckets ride the SAME real primitive shape (a `full`-kind
-- move_effects record's `afterDamage` stage callback, EffectRegistry.lua's
-- staged damaging pipeline), unlike modern_movepool_status.lua's
-- kind="secondary"+run pattern. Must load after modern_combat.lua (only
-- HEALPULSE/LIFEDEW/SYNTHESIS/PAINSPLIT below need its exports; the
-- recoil/drain/charge handlers don't, but one load order keeps every
-- Phase 2 sibling consistent).
--
-- Why `afterDamage`, not `run`, for recoil/drain/Bounce/Outrage/
-- Eternabeam: `afterDamage` is ONLY ever read by Gen 1's own damaging
-- pipeline (EffectRegistry.runDamaging, "post-damage effect bookkeeping"
-- -- confirmed, EffectRegistry.lua:307-317) and Gen 1's charge gate
-- (BattleState:performMove reads `record.charge`, :3602). Gen 2's own
-- dispatch (gen2/Battle.lua:1533-1538) never looks at either field --
-- it only ever checks `record.run`, and calling handler(...) there
-- returns immediately regardless of what the handler does inside (see
-- modern_movepool_status.lua's header for the full grounding). So a
-- record with NO `run` field is invisible to that early-return branch:
-- Gen 2 falls through to its OWN native damage path unmodified, meaning
-- these moves deal ordinary, un-recoiled/un-charged damage on Gen 2 today
-- -- not broken, just not (yet) wired there, the same "pre-existing gap,
-- not a regression" bar Phase 1 already established. Giving one of these
-- records a `run` field too (to also drive some Gen 2 behavior) would
-- flip that from "unwired" to "deals zero damage on Gen 2", strictly
-- worse -- deliberately not attempted here.
--
-- schema note: R.move_effects (src/mods/Schemas.lua:1280-1288) only lists
-- kind/accuracyChecked/run as known fields, but Schemas.check's own
-- record-mode validator explicitly allows and preserves unknown top-level
-- keys ("Unknown top-level fields are allowed and preserved -- extensible
-- records are a feature", Schemas.lua:211-217; confirmed in the actual
-- non-patch branch at :249-260, which only rejects unrecognized keys in
-- patch mode). That's what makes `afterDamage`/`charge` on a MOD-registered
-- record legal at all -- they ride through as ordinary extra fields, the
-- same way MoveEffects.full's own native records carry them.
--
-- mon.hp / mon.stats.hp are the confirmed real current/max HP fields
-- (native HEAL_EFFECT, MoveEffects.lua:201-214, reads/writes exactly
-- these two).
return function(mod)
  local EffectRegistry = require("src.battle.EffectRegistry")
  local StatusRegistry = require("src.battle.StatusRegistry")
  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  assert(normalize and displayNameFor,
    "modern_movepool_damage: combat/modern_combat.lua must load first")

  ------------------------------------------------------------------
  -- Recoil: user takes a fraction of the RAW damage it just dealt.
  -- Native RECOIL_EFFECT (MoveEffects.lua:530-539) is hardcoded to 1/4
  -- (Gen 1's only recoil ratio) -- Brave Bird/Wood Hammer (1/3) and Head
  -- Smash (1/2) need their own real Showdown fractions, so this can't
  -- reuse that id even generation risk aside; copies its exact shape
  -- (ctx.rawDamage, ctx.battle:applyDamage) with a configurable fraction.
  ------------------------------------------------------------------
  -- RETIRED (2026-08-27): recoilFraction/GALAR_RECOIL_EFFECT_3/2 and
  -- GALAR_DRAIN_EFFECT_75 used to live here, both `kind="full"`/
  -- `afterDamage`-shaped -- this file's own header above already
  -- documented that shape as Gen 1-only. GALAR_RECOIL_EFFECT_3/2 were
  -- registered but never actually patched onto any move at all
  -- (confirmed by direct grep -- Brave Bird/Wood Hammer/Head Smash had
  -- zero recoil, on either gen); GALAR_DRAIN_EFFECT_75 WAS patched onto
  -- Draining Kiss, meaning its drain silently never applied on a Gen 2
  -- battle, a real live bug. Superseded by a genuinely generic,
  -- dual-gen-correct handler (main.lua's own installGenericDrainRecoil)
  -- that reads every move's real `drain` field live off national_dex --
  -- covers Draining Kiss (now fixed on both gens) and every other real
  -- drain/recoil move in the roster, not just these four.

  ------------------------------------------------------------------
  -- Plain heals (kind="primary", power=0 status moves) -- BattleState's
  -- own pure-status-move dispatch (:3637) requires kind=="primary" AND a
  -- `run` field to do anything at all, unlike the afterDamage-only shape
  -- above; these run on both Gen 1 and Gen 2 (normalize+displayNameFor
  -- bridge, same as modern_movepool_status.lua's primary handlers).
  ------------------------------------------------------------------
  local function healFraction(battle, who, numerator, denominator)
    local mon = who.mon or who
    if mon.hp >= mon.stats.hp then return false end
    local amount = math.max(1, math.floor(mon.stats.hp * numerator / denominator))
    -- Heal Block / boss "healblock": the one gate every heal routes through.
    local tryHeal = mod.exports.g9TryHeal
    if tryHeal then
      if tryHeal(battle, who, amount) <= 0 then return false end
    else
      mon.hp = math.min(mon.stats.hp, mon.hp + amount)
    end
    return true
  end

  ------------------------------------------------------------------
  -- Ally-side ("user-and-allies") recovery helpers -- Life Dew and
  -- Lunar Blessing below.
  --
  -- Both moves are national_dex target "user-and-allies" (real Showdown
  -- `target: "allies"`: the user AND every adjacent ally), so their real
  -- effect is a spread across the user's OWN side. This engine delivers
  -- such a move ONCE -- resolveMoveTargets expands only the two
  -- OFFENSIVE spread archetypes -- so the effect handler itself walks the
  -- real side, the exact same shape combat/modern_party_support.lua's
  -- Aromatherapy / Heal Bell / Jungle Healing already use. It is the
  -- adjacency seam that answers "how big is the side": the native
  -- two-battler fallback reports no allies (singles), a doubles/triples
  -- layout reports the literally-adjacent slots, and the 4v4/boss/horde
  -- layouts report the whole team -- so this is correct in every format
  -- with no per-layout wiring here.
  ------------------------------------------------------------------
  local function rawMon(who) return who and (who.mon or who) or nil end

  -- The user plus every adjacent ally, in order. requestAdjacency's own
  -- contract already excludes the caster from `allies`, so nothing is
  -- double-counted.
  local function alliesAndSelf(battle, user)
    local out = { user }
    local requestAdjacency = mod.exports.requestAdjacency
    if requestAdjacency then
      local ok, adj = pcall(requestAdjacency, battle, user, nil)
      if ok and adj and adj.allies then
        for _, ally in ipairs(adj.allies) do out[#out + 1] = ally end
      end
    end
    return out
  end

  -- Heal num/den of max HP on a living, not-already-full recipient and
  -- return the amount actually restored (0 for any no-op). Written
  -- raw-mon-tolerant because the caster arrives as a battler (Gen 1
  -- wrapper / Gen 2 mon) while every adjacency-reported ally is a raw mon,
  -- and routed through the one real heal gate (Heal Block / boss
  -- "healblock") exactly like healFraction above.
  local function healFractionAmount(battle, who, numerator, denominator)
    local mon = rawMon(who)
    if not mon then return 0 end
    local maxHp = mon.maxHp or (mon.stats and mon.stats.hp)
    if not maxHp or maxHp <= 0 then return 0 end
    if (mon.hp or 0) <= 0 or (mon.hp or 0) >= maxHp then return 0 end
    local amount = math.max(1, math.floor(maxHp * numerator / denominator))
    local tryHeal = mod.exports.g9TryHeal
    if tryHeal then return tryHeal(battle, who, amount) end
    mon.hp = math.min(maxHp, mon.hp + amount)
    return amount
  end

  local function emitMsg(battle, text)
    if battle and battle.emit then battle:emit({ kind = "message", text = text }) end
  end

  -- A recipient's display name WITHOUT a side prefix -- displayNameFor
  -- prefixes "Enemy" for a raw mon it can't place, which an ally is not.
  -- Reuses modern_party_support.lua's own tolerant namer, the one every
  -- existing side-wide effect already messages through, and falls back to
  -- displayNameFor only if that module is absent.
  local function sideName(battle, who)
    local nameOf = mod.exports.g9NameOf
    if nameOf then
      local ok, nm = pcall(nameOf, battle, who)
      if ok and nm then return nm end
    end
    return displayNameFor(battle, who, true)
  end

  -- Heal Pulse: heals the TARGET (not the user) by half its max HP.
  -- Target-directed like Decorate in stages.lua, so accuracyChecked=true
  -- for the same reason (a genuine miss roll against the target, not a
  -- self-only buff that should never consult the opponent's evasion).
  -- In this engine's own single-battle-only shape "target" is always the
  -- opponent (no ally slot to aim at) -- healing the opponent is legal
  -- if odd play, exactly as in real single-battle Showdown.
  mod.content.move_effects:register("GALAR_HEALPULSE_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      if not healFraction(n.battle, n.target, 1, 2) then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      return { Strings("%s's\nHP was restored!", displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })

  -- Life Dew: heals the USER and every adjacent ally by 1/4 of max HP.
  -- Showdown moves.ts:10289 carries `heal: [1, 4]` with `target: "allies"`,
  -- and national_dex's own record agrees (`healing = 25`) -- NOT the 1/2 an
  -- earlier note here claimed (no generation ever raised it; that note was
  -- wrong). One line is emitted per recipient (a handler's return value is
  -- discarded on Gen 2, so messages must be emitted), and the move fails
  -- only when nobody on the side needed healing.
  mod.content.move_effects:register("GALAR_LIFEDEW_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      local healedAny = false
      for _, ally in ipairs(alliesAndSelf(battle, n.user)) do
        if healFractionAmount(battle, ally, 1, 4) > 0 then
          healedAny = true
          emitMsg(battle, Strings("%s's\nHP was restored!", sideName(battle, ally)))
        end
      end
      if not healedAny then
        emitMsg(battle, romText(battle.data, "_ButItFailedText", "But, it failed!"))
      end
    end,
  })

  -- Synthesis/Moonlight/Morning Sun: real Showdown heal is
  -- weather-conditional -- 2/3 max HP in sun, 1/4 in any other real
  -- weather (rain/sand/snow), 1/2 with none -- fulfilling this file's
  -- own earlier deferral note (weather didn't exist in this engine yet
  -- when Synthesis was first wired; it does now, combat/modern_weather
  -- .lua). All three moves share the identical real formula -- one
  -- handler, patched onto all three move ids (see main.lua's own
  -- CUSTOM_EFFECT_PATCH) rather than copy-pasted three times.
  local function weatherVariableSelfHeal(a, b, c)
    local n = normalize(a, b, c)
    local currentWeather = mod.exports.currentWeather
    local weather = currentWeather and currentWeather(n.battle, n.gen2)
    -- Mega Sol (Phase 8, other bucket): its own real personal sun
    -- simulation ("as if the weather were harsh sunlight") extends to
    -- every real sun-conditional MOVE behavior this engine already
    -- models, not just the Fire/Water damage multiplier -- Synthesis/
    -- Moonlight/Morning Sun's own real 2/3-in-sun heal included.
    local abilityIdOf = mod.exports.abilityIdOf
    if weather ~= "SUN" and abilityIdOf and abilityIdOf(n.user) == "MEGASOL" then
      weather = "SUN"
    end
    local ok
    if weather == "SUN" then
      ok = healFraction(n.battle, n.user, 2, 3)
    elseif weather == "RAIN" or weather == "SAND" or weather == "SNOW" then
      ok = healFraction(n.battle, n.user, 1, 4)
    else
      ok = healFraction(n.battle, n.user, 1, 2)
    end
    if not ok then
      return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
    end
    return { Strings("%s's\nHP was restored!", displayNameFor(n.battle, n.user, n.gen2)) }
  end
  mod.content.move_effects:register("GALAR_SYNTHESIS_EFFECT", { kind = "primary", run = weatherVariableSelfHeal })
  mod.content.move_effects:register("GALAR_MOONLIGHT_EFFECT", { kind = "primary", run = weatherVariableSelfHeal })
  mod.content.move_effects:register("GALAR_MORNINGSUN_EFFECT", { kind = "primary", run = weatherVariableSelfHeal })

  -- Shore Up: real Showdown heal is 2/3 max HP during sandstorm, 1/2
  -- otherwise -- a single-condition variant of the same weather-read
  -- shape above, not worth generalizing further for just one move.
  mod.content.move_effects:register("GALAR_SHOREUP_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local currentWeather = mod.exports.currentWeather
      local weather = currentWeather and currentWeather(n.battle, n.gen2)
      local ok = (weather == "SAND") and healFraction(n.battle, n.user, 2, 3) or healFraction(n.battle, n.user, 1, 2)
      if not ok then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      return { Strings("%s's\nHP was restored!", displayNameFor(n.battle, n.user, n.gen2)) }
    end,
  })

  -- Floral Healing: real Showdown heal is 2/3 max HP on Grassy Terrain,
  -- 1/2 otherwise -- TARGET-directed (heals the target, not the user --
  -- confirmed via its own real prose text), same accuracyChecked shape
  -- Heal Pulse above already uses for the identical reason.
  mod.content.move_effects:register("GALAR_FLORALHEALING_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local onGrassyTerrain = n.battle.terrain == "GRASSY"
      local ok = onGrassyTerrain and healFraction(n.battle, n.target, 2, 3) or healFraction(n.battle, n.target, 1, 2)
      if not ok then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      return { Strings("%s's\nHP was restored!", displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })

  -- Purify: cures the TARGET's major status and heals the USER 50% max
  -- HP -- fails if the target has no status to cure (real Showdown
  -- rule), regardless of the user's own HP. Reuses abilities/engine/
  -- status_cure.lua's own cureStatusOf (looked up lazily -- that file
  -- loads much later, but this handler only ever runs during a real
  -- battle, by which point every mod has finished loading).
  mod.content.move_effects:register("GALAR_PURIFY_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local cureStatusOf = mod.exports.cureStatusOf
      if not (cureStatusOf and cureStatusOf(n.target)) then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      healFraction(n.battle, n.user, 1, 2)
      return { Strings("%s\nwas cured of its\nstatus condition!", displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })

  -- Lunar Blessing: heals the USER and every adjacent ally by 1/4 of max
  -- HP and cures each of its status. Showdown moves.ts:10550 -- `target:
  -- "allies"`, `onHit` heals 0.25 then `cureStatus()` -- i.e. the user and
  -- its adjacent allies, one recipient at a time. Unconditional (never
  -- "but it failed," matching the real Blessing family), so the heal and
  -- the cure run independently rather than one gating the other.
  mod.content.move_effects:register("GALAR_LUNARBLESSING_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      local cureStatusOf = mod.exports.cureStatusOf
      for _, ally in ipairs(alliesAndSelf(battle, n.user)) do
        if healFractionAmount(battle, ally, 1, 4) > 0 then
          emitMsg(battle, Strings("%s's\nHP was restored!", sideName(battle, ally)))
        end
        if cureStatusOf then pcall(cureStatusOf, ally) end
      end
      emitMsg(battle, Strings("%s\nwas blessed\nby the full moon!", sideName(battle, n.user)))
    end,
  })

  -- Pain Split: both battlers' current HP is set to the floor of their
  -- average (each still clamped to its own max, which the average of two
  -- HP values already at or under their own maxes can never exceed).
  -- Genuinely never misses in real Showdown (no accuracy roll at all,
  -- not even a 100-accuracy one) -- accuracyChecked left unset/nil is
  -- what skips BattleState's own accuracy roll for a primary effect
  -- (:3642, `if record.accuracyChecked and ...`), matching that exactly.
  mod.content.move_effects:register("GALAR_PAINSPLIT_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local userMon, targetMon = n.user.mon or n.user, n.target.mon or n.target
      local avg = math.floor((userMon.hp + targetMon.hp) / 2)
      userMon.hp = math.min(userMon.stats.hp, avg)
      targetMon.hp = math.min(targetMon.stats.hp, avg)
      return { Strings("The battlers'\nHP was\nshared!") }
    end,
  })

  ------------------------------------------------------------------
  -- Two-turn / recharge moves. Real primitive: `record.charge` read
  -- directly off the merged move_effects record by BattleState:performMove
  -- (:3602: "charge moves: first turn just charges" -- confirmed against
  -- native CHARGE_EFFECT/FLY_EFFECT, MoveEffects.lua:556-557), NOT a
  -- field on the move's own data at all -- R.moves (Schemas.lua:824-846)
  -- has chargeText/semiInvulnerable but no `charge` field at all, so
  -- there is nothing for this mod to patch onto a move record for this
  -- (checked, not assumed).
  --
  -- Bounce, Outrage, and Eternabeam are NOT wired by pointing their
  -- moves_new.lua `effect` straight at Gen 1's native ids (FLY_EFFECT /
  -- THRASH_PETAL_DANCE_EFFECT / HYPER_BEAM_EFFECT), even though the
  -- mechanics genuinely match -- same cross-generation reference risk as
  -- modern_movepool_status.lua's header explains for BURN_SIDE_EFFECT1:
  -- move.effect is f.id("move_effects")-validated against whichever
  -- generation's registry is active for that boot, and Gen 1's native ids
  -- are absent from Gen 2's own (gen2/Battle.lua-seeded) copy. Custom
  -- GALAR_* ids, registered fresh on every boot, are the only shape valid
  -- on both -- their handlers below are still DIRECT copies of the real
  -- native Gen 1 algorithms (same field names, same turn counts), not
  -- reinvented, just re-homed under an id that resolves everywhere.
  ------------------------------------------------------------------

  -- Bounce: semi-invulnerable charge turn (Fly-shaped -- no confirmed
  -- Bounce-specific animation exists in this engine, so this reuses
  -- Fly's own TELEPORT charge anim as a placeholder, same as Fly/Dig
  -- already share one), then a 30% paralyze chance on the hit that
  -- releases it. The paralyze roll lives in `afterDamage` (fires once,
  -- after the release-turn hit lands), NOT `run` -- see this file's own
  -- header for why a `run` field here would be actively worse than no
  -- wiring at all on Gen 2. Gen 2's own charge/semi-invulnerable
  -- mechanism is a completely separate `state.chargeMove`/
  -- `Effects.CHARGE[def.effect]` system keyed on GEN 2's OWN hardcoded
  -- effect-id strings (gen2/Battle.lua:1324,1459) -- unreachable for a
  -- custom id without new Gen 2-side engine hooks, out of scope this
  -- phase. Not a regression: Bounce currently has zero charge behavior
  -- on either engine, so Gen 1 gaining the real two-turn mechanic while
  -- Gen 2 stays an ordinary instant-hit move is a strict improvement, not
  -- a new gap.
  mod.content.move_effects:register("GALAR_BOUNCE_EFFECT", {
    kind = "full",
    charge = { invulnerable = true, anim = "TELEPORT" },
    afterDamage = function(ctx)
      if ctx.battle.rng(0, 255) >= 77 then return end -- 30%
      for _, m in ipairs(StatusRegistry.inflict(ctx.battle, ctx.target, "PAR", {
        moveType = ctx.move.type, secondary = true, source = ctx.move.id,
      })) do
        ctx.say(m)
      end
    end,
  })

  -- Outrage: direct copy of native THRASH_PETAL_DANCE_EFFECT's afterDamage
  -- (MoveEffects.lua:584-602) -- locks the user into 2-3 more turns of the
  -- same move via user.thrashTurns/thrashMove/thrashAnnounced, then
  -- confuses it. These exact field names are confirmed read generically
  -- elsewhere in BattleState.lua regardless of which move set them
  -- (:3552 isContinuation, :3562 skip-reannounce, :3494 clearVolatiles),
  -- so the engine's existing turn-continuation machinery Just Works for
  -- Outrage the same way it already does for native Thrash/Petal Dance.
  mod.content.move_effects:register("GALAR_OUTRAGE_EFFECT", {
    kind = "full",
    afterDamage = function(ctx)
      local user = ctx.user
      if not user.thrashTurns then
        user.thrashTurns = ctx.rng(2, 3)
        user.thrashMove = ctx.moveInst
        user.thrashAnnounced = true
      else
        user.thrashTurns = user.thrashTurns - 1
        if user.thrashTurns <= 0 then
          user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
          -- Phase 3a (abilities/engine/status_immunity.lua): OWNTEMPO
          -- blocks real self-inflicted rampage confusion too, not just
          -- hostile confusion -- unlike boss-fight softStatus (hostile-
          -- only in scope, this site deliberately left untouched there).
          local hasStatusImmunity = mod.exports.hasStatusImmunity
          if not user.confusedTurns
              and not (hasStatusImmunity and hasStatusImmunity(user, "confusion", ctx.battle)) then
            user.confusedTurns = ctx.rng(2, 5)
            ctx.say(romText(ctx.battle.data, "_BecameConfusedText", "%s\nbecame confused!", EffectRegistry.displayName(user)))
          end
        end
      end
    end,
  })

  -- Eternabeam: direct copy of native HYPER_BEAM_EFFECT's afterDamage
  -- (MoveEffects.lua:619-629) -- sets user.mustRecharge unless the target
  -- fainted or its substitute broke (ruleset hyperBeamSkipRechargeOnKO
  -- default true). mustRecharge is likewise confirmed read generically
  -- (:1781 action gate, :3333 recharge-turn consume), so the existing
  -- recharge machinery already works for Eternabeam without any further
  -- hook here.
  mod.content.move_effects:register("GALAR_ETERNABEAM_EFFECT", {
    kind = "full",
    afterDamage = function(ctx)
      local ruleset = ctx.battle and ctx.battle.ruleset
      local skipOnKO = not ruleset or ruleset.hyperBeamSkipRechargeOnKO ~= false
      local targetDown = ctx.target.mon.hp <= 0 or ctx.brokeSub
      if not skipOnKO or not targetDown then
        ctx.user.mustRecharge = true
      end
    end,
  })

  ------------------------------------------------------------------
  -- Gen 2 halves of Bounce/Eternabeam/Outrage/Raging Fury/Uproar, added
  -- 2026-08-27.
  --
  -- Neither of these adds a `.run` field to the records above: Gen 2's
  -- dispatch calls ANY record's `.run` field, if present, and returns
  -- immediately without ever reaching its own real damage path (the
  -- exact bug this file's own header already documents for the old
  -- flinch/confuse code) -- fatal for a move with real power like these
  -- two, not just a silent no-op. Both additions below instead use
  -- primitives already confirmed safe for a damaging move on Gen 2: a
  -- plain data table Gen 2's own native charge system already reads
  -- (Bounce's charge turn), and a `battle.damage_dealt` listener (fires
  -- AFTER Gen 2's own real damage path already ran).
  ------------------------------------------------------------------
  local isGen2Battle = mod.exports.isGen2Battle

  -- Bounce, Gen 2 charge turn: Effects.CHARGE is a plain Lua table Gen
  -- 2's own native move-execution gate already reads generically
  -- (`Effects.CHARGE[def.effect]`, gen2/Battle.lua) -- confirmed by
  -- direct read, not a schema-validated registry the way move_effects
  -- ids are, so adding a new key here carries none of the cross-
  -- generation id-validation risk this file's own header already flags
  -- for Outrage below. GALAR_BOUNCE_EFFECT is the SAME id already
  -- patched onto Bounce for Gen 1 (CUSTOM_EFFECT_PATCH, main.lua) --
  -- Gen 2's native system reads it off the identical live `.effect`
  -- field, no second patch needed.
  local gen2Ok_Gen2Effects, Gen2Effects = pcall(require, "src.battle.gen2.Effects")
  Gen2Effects = gen2Ok_Gen2Effects and Gen2Effects or nil
  if Gen2Effects then
    Gen2Effects.CHARGE.GALAR_BOUNCE_EFFECT = { text = "%s sprang up!", vanish = true }
  end

  -- Bounce, Gen 2 release-turn paralyze (real 30% chance, same fraction
  -- the Gen 1 registration above already uses) -- gen2-only, Gen 1's own
  -- afterDamage handler above already covers that engine.
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target
    local user = ev and ev.user
    if not (battle and moveId == "BOUNCE" and target and user and (ev.damage or 0) > 0) then return end
    if not (isGen2Battle and isGen2Battle(battle)) then return end
    if battle.random(100) >= 30 then return end
    battle:applyStatus(target, "paralyze", "BOUNCE")
  end)

  -- Eternabeam, both gens' recharge -- Gen 1's own afterDamage handler
  -- above already covers that engine correctly (including the real
  -- skip-recharge-on-KO rule); this only adds the Gen 2 half, via the
  -- same real generic `vol.recharge` flag Gen 2's own native `checkTurn`
  -- already consumes unconditionally (confirmed by direct read,
  -- gen2/Battle.lua -- it does not care which move set the flag).
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target
    local user = ev and ev.user
    if not (battle and moveId == "ETERNABEAM" and target and user and (ev.damage or 0) > 0) then return end
    if not (isGen2Battle and isGen2Battle(battle)) then return end
    local targetMon = target.mon or target
    if (targetMon.hp or 0) > 0 then
      battle:volatile(user).recharge = true
    end
  end)

  ------------------------------------------------------------------
  -- Outrage / Raging Fury / Uproar, Gen 2 rampage-lock -- closed
  -- 2026-08-27. The earlier pass here tried to cooperate with Gen 2's
  -- own hardcoded `def.effect == "EFFECT_RAMPAGE"` check inside its
  -- central move-execution gate, found no safe way to alias a custom id
  -- onto it, and left the whole mechanic unclosed as a result. Wrong
  -- move: this mod doesn't need that check to cooperate at all -- we
  -- own the lock-in DECISION ourselves (the same "we are the bible of
  -- combat" principle already applied to paralysis/sleep/freeze turn-
  -- loss) and simply force the ACTUAL move executed, via
  -- Battle:useMove, regardless of what Gen 2's own selection/AI logic
  -- thinks it chose. No native cooperation needed at all.
  ------------------------------------------------------------------
  local RAMPAGE_LOCK_MOVES = { OUTRAGE = true, RAGINGFURY = true, UPROAR = true }
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local user = ev and ev.user
    if not (battle and moveId and user and (ev.damage or 0) > 0) then return end
    if not (isGen2Battle and isGen2Battle(battle)) then return end
    if not RAMPAGE_LOCK_MOVES[moveId] then return end
    local vol = battle:volatile(user)
    if not vol.rampageMoveId then
      vol.rampageMoveId = moveId
      -- Real durations: Outrage/Raging Fury lock for 2-3 more turns
      -- (rand+2); Uproar locks for exactly 3 (Showdown-verified,
      -- data/moves.ts).
      vol.rampageTurns = (moveId == "UPROAR") and 3 or (battle.random(2) + 2)
    else
      vol.rampageTurns = vol.rampageTurns - 1
      if vol.rampageTurns <= 0 then
        vol.rampageMoveId, vol.rampageTurns = nil, nil
        -- Real rule: Outrage/Raging Fury confuse the user when the lock
        -- ends; Uproar does not.
        if moveId ~= "UPROAR" then
          local hasStatusImmunity = mod.exports.hasStatusImmunity
          if not (hasStatusImmunity and hasStatusImmunity(user, "confusion", battle)) then
            battle:applyConfusion(user, nil, moveId)
          end
        end
      end
    end
  end)
  -- Force the locked move regardless of what was actually selected --
  -- the real, direct ownership mechanism: WE decide what executes, the
  -- native dispatch underneath just runs whatever moveId it's handed.
  do
    local gen2Ok_Battle2, Battle2 = pcall(require, "src.battle.gen2.Battle")
    Battle2 = gen2Ok_Battle2 and Battle2 or nil
    if Battle2 then
      local nativeUseMoveRampage = Battle2.useMove
      function Battle2:useMove(attacker, defender, moveId)
        if attacker then
          local vol = self:volatile(attacker)
          if vol.rampageMoveId and vol.rampageMoveId ~= moveId then
            moveId = vol.rampageMoveId
          end
        end
        return nativeUseMoveRampage(self, attacker, defender, moveId)
      end
    end
  end
  -- Uproar's own real extra effect (both engines): wakes every active
  -- sleeping mon the turn it's used. Gen 1's own registration below
  -- already has this via beforeAccuracy; this is the Gen 2 half.
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    if not (battle and moveId == "UPROAR") then return end
    if not (isGen2Battle and isGen2Battle(battle)) then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and mon.status == "sleep" then mon.status = nil end
    end
  end)

  ------------------------------------------------------------------
  -- Electro Shot: real 2-turn charge move, raises the user's own
  -- Special Attack on the charge turn, skips the charge entirely in
  -- rain (Showdown-verified, data/moves.ts). Mirrors Solar Beam's own
  -- established shape exactly: Gen 1 registration + a Gen 1-only
  -- BattleState:performMove wrap for the rain-skip (same technique,
  -- same file that already documents why no sanctioned hook exists for
  -- this), Gen 2 gets the real charge turn via the same Effects.CHARGE
  -- table entry Bounce/Solar Beam's own Gen 2 fixes already use -- the
  -- Special-Attack-on-charge-turn half and the rain-skip are NOT built
  -- for Gen 2 (no clean multi-gen hook found for "run custom code on
  -- just the charge turn" -- a real, smaller, flagged gap, same
  -- shape as Solar Beam's own remaining sun-skip-on-Gen-2 gap).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_ELECTROSHOT_EFFECT", {
    kind = "full",
    charge = { anim = "XSTATITEM_ANIM", enemyAnim = "XSTATITEM_DUPLICATE_ANIM" },
  })
  do local ok, E = pcall(require, "src.battle.gen2.Effects"); if ok and E then E.CHARGE.GALAR_ELECTROSHOT_EFFECT = { text = "%s absorbed electricity!" } end end

  local BattleState = require("src.battle.BattleState")
  local nativePerformMove = rawget(BattleState, "performMove")
  if type(nativePerformMove) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    if moveInst and moveInst.id == "ELECTROSHOT" and not isGen2Battle(self) and not user.charging then
      local currentWeather = mod.exports.currentWeather
      local changeStage = mod.exports.changeStage
      if currentWeather and currentWeather(self, false) == "RAIN" then
        user.charging = moveInst
        user.chargeReady = true
      elseif changeStage then
        for _, m in ipairs(changeStage(self, user, "spa", 1, false, false)) do self:sayNext(m) end
      end
    end
    return nativePerformMove(self, user, target, moveInst, isCalled)
  end
  end

  mod.log:info("galar_gmax_dex: modern_movepool_damage loaded")
end
