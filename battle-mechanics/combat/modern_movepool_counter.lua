-- Phase 3 (part 2) of the move-effect completion pipeline: Metal Burst and
-- Mirror Coat, the two Counter-family stubs (moves_new.lua's METALBURST/
-- MIRRORCOAT, both still effect="NO_ADDITIONAL_EFFECT" going into this
-- file). DETECT's patch lives directly in modern_combat_protect.lua (the
-- identical one-line pattern to that file's own PROTECT patch); FEINT's
-- Protect-bypass is a plain moves_new.lua data field (bypassesProtect),
-- patched onto the live FEINT record by main.lua's wireMovepoolSubEffects
-- -- neither needs a move_effects registration of its own, so neither
-- lives here.
--
-- What COUNTER's real implementation turned out to be (grepped src/battle/
-- MoveEffects.lua and EffectRegistry.lua for "COUNTER" first, per this
-- phase's own instruction, before writing anything): NOT a move_effects
-- record at all -- a hardcoded `if move.id == "COUNTER"` branch inside
-- EffectRegistry.lua's runDamaging (:149-171), reading `battle.lastDamage`,
-- Gen 1's shared wDamage byte -- the LAST damage dealt ANYWHERE in the
-- battle (by either side, from any source), gated only by whether the
-- opponent's last move was itself counterable (Normal/Fighting type,
-- power > 0). No physical/special split exists anywhere in it, and it
-- doesn't reset per turn -- both real, well-known Gen 1 Counter quirks (its
-- own "can counter your OWN last hit" exploitability), not a primitive
-- Metal Burst/Mirror Coat -- which need a genuine "physical or special
-- damage taken THIS turn" split -- can reuse.
--
-- Gen 2 DOES have the real primitive for exactly that split, but it's
-- Gen2-only and unreachable from a mod-registered move_effects record:
-- `defenderState.tookThisTurn`/`tookKind` (gen2/Battle.lua:1201-1202,
-- accumulated per hit inside Battle:dealDamage, cleared at the top of
-- every turn, gen2/Battle.lua:4028-4029) feeds a hardcoded `Effects.COUNTER`
-- table (gen2/Battle.lua:1478, gen2/Effects.lua:219-226) mapping
-- `def.effect == "EFFECT_COUNTER"`/`"EFFECT_MIRROR_COAT"` straight to
-- native dispatch (gen2/Battle.lua:1476-1489) -- entirely bypassing
-- mod.content.move_effects (Gen2's own dispatch, gen2/Battle.lua:1533-1538,
-- only ever reads a record's `.run` field -- the same limitation
-- modern_movepool_damage.lua's own header already established for
-- afterDamage/charge). Confirmed by grepping this engine's own shipped
-- data for the literal ids: no "COUNTER", "MIRRORCOAT", or "METALBURST"
-- move exists anywhere in it -- Gen 2's native Counter/Mirror Coat
-- mechanism is real, correct, tested code with nothing pointing at it yet.
--
-- Deliberately NOT rerouting MIRRORCOAT's effect field at the literal
-- native "EFFECT_MIRROR_COAT" string to pick that mechanism up for free:
-- same cross-generation reference risk modern_movepool_damage.lua's own
-- header already flags for Bounce/Outrage/Eternabeam -- move.effect is
-- validated as f.id("move_effects") against whichever generation's
-- registry is active for that boot, and Gen 1's own registry has no
-- "EFFECT_MIRROR_COAT" id, so a Gen 1 boot's registration would fail
-- outright. A custom GALAR_* id, registered fresh on every boot like every
-- other Phase 1/2 sibling, is the only shape valid on both.
--
-- Known, stated Gen 2 gap (not silently left unmentioned): METALBURST and
-- MIRRORCOAT below are GEN1-ONLY, the same "unwired, not broken" class of
-- gap as Bounce/Outrage/Eternabeam. On a Gen 2 boot these fall through to
-- Gen 2's own native damage path -- but since neither id exists in Gen 2's
-- own native data, that's an ordinary (and near-useless, given the power=1
-- placeholder) hit, not real Metal Burst/Mirror Coat. Gen 2 already has a
-- fully-correct native Mirror Coat sitting unused for exactly the reason
-- above; wiring MIRRORCOAT's Gen2-side data at the real "EFFECT_MIRROR_COAT"
-- id (a second, Gen2-specific registration path, not this file's custom
-- one) and building the Gen4-only Metal Burst into Gen 2's own dispatch/
-- priority table from scratch are both real follow-on work, not attempted
-- here.
--
-- The turn-scoped "damage taken by category" tracker: Gen 1 has no
-- existing primitive for this at all (unlike Protect's own turn-scoped
-- flag, which had a real value worth reusing -- Counter's shared
-- battle.lastDamage, per above, genuinely isn't one). Built here, but out
-- of two REAL existing primitives, not a new hook: `battle.damage_dealt`
-- (already emitted per landed hit by EffectRegistry.lua:285-290 --
-- confirmed zero consumers anywhere in this mod before this file) to
-- observe and accumulate, and the exact same `battle.turn_started` event
-- modern_combat_protect.lua's own Part C already uses to clear per-turn
-- state, in the same way, for the same reason.
--
-- chooseDamage, not perform: EffectRegistry.lua's runDamaging already has
-- a dedicated extension point for exactly this move family --
-- record.chooseDamage, explicitly commented there as "Counter/Super
-- Fang/OHKO/fixed damage" (:172-181) -- and it runs AFTER the normal
-- invulnerability check and accuracy roll (both earlier in runDamaging,
-- ~:104-145), unlike record.perform, which BattleState:performMove
-- dispatches to (:3631-3634) BEFORE either. A perform-shaped handler
-- modeled too literally on Protect's own (a genuinely different case: a
-- power=0, priority-4 status move that never rolls a miss in any real
-- generation) would have silently skipped Metal Burst/Mirror Coat's real
-- accuracy check (evasion, a mid-Fly/Dig target) entirely -- a real
-- behavioral gap, not a style choice, which is why this deviates from a
-- literal perform-shaped read of the plan. A failed chooseDamage returns
-- (nil, message) -- runDamaging's own caller prints it and cancels the
-- move anim on its own (:176-179), so unlike Protect's perform, this needs
-- no ctx.say call itself.
--
-- ROUND 16 (all moves through the mod's battle.damage deliver chain):
-- the counter family was the one real, remaining bypass. Gen 1's
-- chooseDamage returned its number straight to runDamaging (applied
-- directly, never through Runtime.call("battle.damage", ...)); Gen 2's
-- run called battle:dealDamage directly. Both are now thin fail-detection
-- + routing shims: every SUCCESSFUL counter/mirror/metal-burst routes its
-- number through routeThroughBattleDamage (the shared helper this mod
-- exports from combat/legacy_move_takeover.lua), so Protect, Sturdy,
-- every type-immunity ability, Wonder Guard and the mod's damage pipeline
-- all see it exactly like a normal hit -- and the actual number is
-- re-derived authoritatively by legacy_move_takeover.lua's battle.damage
-- priority-1 wrap (keyed on the move id, reading this file's exported
-- counterFamilyParams), which is what keeps it alive past modern_combat
-- .lua's terminal formula wrap (priority 0) that would otherwise clobber
-- any precomputed base with a power=1 placeholder result. Fail-detection
-- (Protect, damage-taken-this-turn, category match, original attacker
-- still out) deliberately stays HERE in chooseDamage/run, not the wrap --
-- a failed counter must print "But, it failed!" / "doesn't affect" via the
-- native (nil, message) contract and must never reach battle.damage at all.
--
-- Protect: chooseDamage bypasses battle:computeDamage entirely (it's a
-- parallel branch inside runDamaging, not a call into it), so it also
-- bypasses modern_combat_protect.lua's own battle.damage hook (that file's
-- Part B) -- re-checked manually here, reusing the exact same "It doesn't
-- affect %s!" message that hook's own typeMult=0 short-circuit produces
-- (EffectRegistry.lua:187-191), so a protected target sees identical
-- failure text regardless of which code path blocked the hit. Neither move
-- sets bypassesProtect (that's Feint-only), but the check mirrors Part B's
-- exact condition shape anyway rather than a narrower one.
--
-- "Original attacker already fainted or switched out" (both moves' real
-- fail condition, per Showdown): stored alongside the accumulated damage
-- is the attacker's own MON table, not the battler slot -- battle.player/
-- battle.enemy are stable per-side tables reused across a switch (only
-- their own `.mon` field changes, confirmed by Pain Split's own
-- userMon/targetMon reads in modern_movepool_damage.lua), so comparing
-- battler identity alone could never detect a mid-battle switch. Requires
-- ctx.target.mon to still be that exact same mon table, with hp > 0.
-- ROUND 21b (last-hit + consume + retarget + Metal Burst priority). Three
-- reported behaviors, all in the user's message:
--  * "still preserving FIRST damage taken" -- the accumulator was a running
--    TOTAL (each hit added), so a second hit made the counter answer the
--    whole turn's combined damage instead of the last hit. Now each hit
--    REPLACES the stored amount (last-hit wins), matching Showdown's
--    counter family (and the user's multi-battler rule: "only accounts for
--    the last damage taken, not the whole damage taken").
--  * "returning it on every move use without getting clean after the move
--    is used" -- the stored hit was never consumed by using the counter, so
--    a Metal Burst used with no fresh damage kept re-answering stale
--    damage every turn. Now both the Gen 1 chooseDamage and the Gen 2 run
--    clear the stored hit on every use -- success OR fail -- so a counter
--    answers exactly one hit, exactly once.
--  * multi-battler retaliation -- Gen 2's native Effects.COUNTER table
--    deals to the player's SELECTED target, not the last attacker. The
--    run now stores the attacker battler (battle.damage_dealt's `user`,
--    which IS the attacker) alongside the damage and deals the counter to
--    THAT battler, failing if it is no longer out -- the user's rule for
--    every counter-like move.
--  * Metal Burst priority -- ROUND 32 correction: this is NOT a -5 move.
--    national_dex is the absolute owner of priority (explicit user rule),
--    and its own METALBURST record says priority=0 (only Counter and Mirror
--    Coat are -5). The 21b round patched → -5 onto the live record under the
--    mistaken belief the whole counter family shared the bracket; that patch
--    is REMOVED. turn_order.lua's movePriority now reads priority straight
--    from national_dex's own moveById reply, so no patch here is needed (or
--    wanted) for any counter-family move.
-- ROUND 21c (native-volatile leak, the follow-up report "something's still
-- loading damage to metal burst and it's not clearing it -- when spammed it
-- still kills pokemon despite no damage being dealt"). The 21b run still had
-- a native-volatile FALLBACK (battle:volatile(user).tookThisTurn) for "a hit
-- the mod's listener never observed". The engine clears that volatile ONLY
-- for battle.player/battle.enemy at turn start (gen2/Battle.lua), so in
-- g9-Battle-Scene's real doubles/triples/boss/horde rosters a NON-lead
-- battler's tookThisTurn was never cleared: stale damage sat in it forever,
-- the fallback re-read it every Metal Burst/Counter/Mirror Coat use, and the
-- counter kept answering turns-old damage even when nothing hit the user this
-- turn -- "spammed, still kills". The fallback is now REMOVED from both the
-- Gen 2 run (this file) and the shared battle.damage wrap
-- (legacy_move_takeover.lua): the mod's own accumulator is the single source
-- of truth, the engine emits battle.damage_dealt for every landed hit so a
-- real hit is always observed, and nil genuinely means "nothing hit us this
-- turn" -> fail.
return function(mod)
  local Strings = require("src.core.Strings")
  local Damage = require("src.battle.Damage")
  local romText = require("src.core.RomText")

  -- Damage.lua's own categoryOf (Damage.lua:110-124) is a local, not
  -- exported -- this reproduces its exact fallback chain (a move's own
  -- category field first, else Gen 1's type-based split) using the one
  -- piece of it that IS public, Damage.isSpecial, rather than guessing at
  -- a simplified version: a native move (Tackle, Thunderbolt, ...) has no
  -- registered `category` field at all and needs the type fallback to
  -- read correctly here too, not just GalarGmaxDex's own moves.
  local function categoryOf(move)
    if not move then return "physical" end
    if move.category == "physical" or move.category == "special" then
      return move.category
    end
    return Damage.isSpecial(move.type) and "special" or "physical"
  end

  ------------------------------------------------------------------
  -- Accumulate "damage taken this turn, by category" onto whichever
  -- battler got hit -- see file header for why this is built fresh
  -- (nothing in Gen 1 already tracks this) out of two existing primitives
  -- rather than a new hook. Also fires on a Gen 2 boot (gen2/Battle.lua's
  -- own battle.damage_dealt emit, :1241-1252, carries `kind` directly --
  -- used here when present instead of re-deriving it) but is inert there:
  -- see header, chooseDamage below is never read by Gen 2's own dispatch.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local target = ev and ev.target
    if not (target and (ev.damage or 0) > 0) then return end
    -- ROUND 21b: LAST-HIT, not a running total. Showdown's counter family
    -- answers only the last hit that landed this turn -- the multi-battler
    -- rule (and the multi-hit rule) both reduce to this -- so each new hit
    -- REPLACES the stored amount instead of adding to it, and the attacker
    -- battler is stored alongside for the Gen 2 run's retarget below.
    target.counterTookThisTurn = ev.damage
    target.counterTookKind = ev.kind or categoryOf(ev.move)
    target.counterAttacker = ev.user
    target.counterAttackerMon = ev.user and ev.user.mon
  end)

  -- ROUND 21 (turn-scoped reset reaches every battler): the clear below
  -- used to touch only battle.player/battle.enemy -- true in a native
  -- two-battler battle, but in g9-Battle-Scene's real doubles/triples/
  -- boss/horde rosters the OTHER battlers (the scene's requestAdjacency
  -- allies/enemies, never battle.player/enemy) kept their
  -- counterTookThisTurn forever -- a stored-damage leak that let a much
  -- later Metal Burst/Mirror Coat reflect damage taken turns ago. Now
  -- iterated via allActiveBattlers, the exact same N-way roster this
  -- mod's ~26 other per-battler loops use (modern_combat.lua:1939,
  -- modern_movepool_damage.lua:492, ...), with the same defensive
  -- fallback to the native pair when the export is absent.
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local all = mod.exports.allActiveBattlers
      and mod.exports.allActiveBattlers(battle)
      or { battle.player, battle.enemy }
    for _, who in ipairs(all) do
      if who then
        who.counterTookThisTurn = nil
        who.counterTookKind = nil
        who.counterAttacker = nil
        who.counterAttackerMon = nil
      end
    end
  end)

  -- wantedKind = nil accepts either category (Metal Burst); a string
  -- requires an exact match (Mirror Coat: "special" only).
  local function registerCounterFamily(effectId, numerator, denominator, wantedKind)
    -- ROUND 21b: a counter answers exactly one hit, exactly once. Every use
    -- -- success or fail -- clears the stored hit so a later turn can never
    -- re-answer stale damage (the reported "returns it on every move use"
    -- bug). The clear runs AFTER routeThroughBattleDamage returns below
    -- because that route re-derives the number from this same accumulator.
    local function consume(user)
      user.counterTookThisTurn = nil
      user.counterTookKind = nil
      user.counterAttacker = nil
      user.counterAttackerMon = nil
    end
    mod.content.move_effects:register(effectId, {
      kind = "full",
      chooseDamage = function(ctx)
        local battle, user, target = ctx.battle, ctx.user, ctx.target
        -- Turn-scoped read (2026-09-10): the raw flag can be stale -- the
        -- Protect part's Part C used to clear only the lead pair, so a
        -- non-lead battler's flag survived and blocked much later moves.
        -- protectionOf (combat/modern_combat_protect.lua) only counts a
        -- flag stamped with the live turn.
        local protectionOf = mod.exports.protectionOf
        local shielded = protectionOf and protectionOf(battle, target)
        if target and target ~= user and shielded
            and not (ctx.move and ctx.move.bypassesProtect) then
          return nil, romText(battle.data, "_DoesntAffectMonText",
            "It doesn't affect\n%s!", ctx.displayName(target))
        end
        local taken = user.counterTookThisTurn or 0
        local rightKind = wantedKind == nil or user.counterTookKind == wantedKind
        local attackerStillOut = target and user.counterAttackerMon == target.mon
          and (target.mon.hp or 0) > 0
        if taken <= 0 or not rightKind or not attackerStillOut then
          consume(user)
          return nil, romText(battle.data, "_ButItFailedText", "But, it failed!")
        end
        local dmg = math.min(65535, math.max(1, math.floor(taken * numerator / denominator)))
        -- ROUND 16: route the success through the mod's battle.damage
        -- deliver chain (fail-detection above already handled the fail
        -- cases, so battle.damage only ever sees a real counter). The
        -- precomputed dmg is just the chain's base fallback; the real
        -- engine's authoritative number comes from legacy_move_takeover
        -- .lua's priority-1 wrap, which re-derives the identical value.
        local route = mod.exports.routeThroughBattleDamage
        if route then
          local d1, d2 = route(battle, user, target, ctx.move, dmg,
            { crit = false, typeMult = 10 }, false)
          -- ROUND 21b: consume AFTER the route re-reads the accumulator.
          consume(user)
          return d1, d2
        end
        consume(user)
        return dmg, { crit = false, typeMult = 10 }
      end,

      -- THE GEN 2 HALF.  `chooseDamage` above is read by Gen 1's
      -- EffectRegistry and by nothing else -- Gen 2 dispatches a mod's move
      -- effect through Battle.moveEffectRecordFor(...).run and reads no other
      -- field (src/battle/gen2/Battle.lua). So on Gold and Crystal the whole
      -- family above was unreachable, and Metal Burst landed as an ordinary
      -- move. This file's own header recorded that as a hard limit; it is not
      -- one. What the header established is that Gen 2's own COUNTER TABLE
      -- cannot be registered into -- but the state that table reads is just a
      -- volatile, and a mod can read it directly.
      --
      -- `tookThisTurn` / `tookKind` are accumulated per hit inside
      -- Battle:dealDamage and cleared at the top of every turn, on the
      -- volatile of whoever TOOK the damage -- which for a counter move is
      -- the user. Mirrored from the native arm beside it, which does exactly
      -- this for EFFECT_COUNTER / EFFECT_MIRROR_COAT.
      --
      -- GUARDED TO GEN 2 ONLY, and that guard is load-bearing: Gen 1's
      -- EffectRegistry ALSO calls `record.run` for any record whose kind is
      -- not "primary" (EffectRegistry.lua:341), and this one is "full". An
      -- unguarded run would therefore fire on Gen 1 as well, on top of the
      -- chooseDamage that already resolved the move -- countering twice.
      run = function(a, b, c, d, e)
        -- Lazily, for the same reason main.lua's GALAR_TRAP_EFFECT reads it
        -- lazily: this closure runs at battle time, long after
        -- modern_combat.lua publishes it, so no load-order assumption.
        local normalize = mod.exports.normalize
        if not normalize then return {} end
        local n = normalize(a, b, c)
        -- Gen 1 already resolved this move through chooseDamage above.
        if not n.gen2 then return {} end

        local battle, user, target = n.battle, n.user, n.target
        if not (battle and user and target) then return {} end
        local def, moveId = d, e
        -- ROUND 21c: read the LAST hit from this mod's OWN accumulator and
        -- NOTHING ELSE -- there is deliberately no native-volatile fallback
        -- here anymore. The native tookThisTurn/tookKind is a running TOTAL
        -- (wrong for the last-hit rule) and, critically, the engine clears
        -- it ONLY for battle.player/battle.enemy at turn start
        -- (gen2/Battle.lua), so in g9-Battle-Scene's real doubles/triples/
        -- boss/horde rosters a NON-lead battler's native volatile is NEVER
        -- cleared -- stale damage sat in it forever and every spammed Metal
        -- Burst/Counter/Mirror Coat re-answered it even when the user had
        -- taken nothing this turn (the reported "still loading damage to
        -- metal burst and it's not clearing it" bug). The mod's own
        -- accumulator is fed by the battle.damage_dealt listener, which the
        -- engine emits for every landed hit, so a real hit is always
        -- observed; a nil accumulator genuinely means "nothing hit us this
        -- turn" and the counter must fail.
        local taken = user.counterTookThisTurn or 0
        local takenKind = user.counterTookKind
        local rightKind = wantedKind == nil or takenKind == wantedKind
        -- ROUND 21b: retaliate against the LAST battler that hit us this
        -- turn (the user's multi-battler rule for every counter-like move),
        -- not the player's selected target -- and fail if that attacker is
        -- no longer out.
        local attacker = user.counterAttacker or target
        local attackerHp = ((attacker.mon or attacker).hp or 0)
        if taken <= 0 or not rightKind or attackerHp <= 0 then
          -- ROUND 21b: consume on fail too -- an attempted counter answers
          -- nothing, but it still clears the stored hit.
          user.counterTookThisTurn = nil
          user.counterTookKind = nil
          user.counterAttacker = nil
          user.counterAttackerMon = nil
          battle:markMissed()
          battle:emit({ kind = "message", text = Strings("But it failed!") })
          return {}
        end
        local dmg = math.min(65535, math.max(1, math.floor(taken * numerator / denominator)))
        -- ROUND 16: route the success through battle.damage (Gen 2's own
        -- dispatch never consults record.chooseDamage, so this run is the
        -- Gen 2 delivery point -- see the round-16 header above). dealDamage
        -- below then emits battle.damage_dealt and handles Substitute/
        -- Endure like any other landed hit. ROUND 21b: the routed target IS
        -- the last attacker, so Protect/type-immunity/Wonder Guard checks
        -- in the chain resolve against the battler actually receiving the
        -- counter, not the selected one.
        local route = mod.exports.routeThroughBattleDamage
        local dealt = dmg
        if route then
          dealt = route(battle, user, attacker, def, dmg,
            { crit = false, typeMult = 10 }, true)
        end
        battle:dealDamage(user, attacker, dealt,
          { move = def, moveId = moveId })
        -- ROUND 21b: consume after the route re-reads the accumulator.
        user.counterTookThisTurn = nil
        user.counterTookKind = nil
        user.counterAttacker = nil
        user.counterAttackerMon = nil
        return {}
      end,
    })
  end

  -- ROUND 16: per-move counter parameters, keyed by the MOVE ID that
  -- ctx.move.id carries at battle time. Read lazily by the shared
  -- battle.damage priority-1 wrap in combat/legacy_move_takeover.lua
  -- (that file owns resolvedTypeMult/Wonder Guard for these moves); this
  -- file owns the actual numbers, so they live in exactly one place.
  mod.exports.counterFamilyParams = {
    METALBURST = { num = 3, den = 2, kind = nil },
    MIRRORCOAT = { num = 2, den = 1, kind = "special" },
    COUNTER = { num = 2, den = 1, kind = "physical" },
  }

  -- Metal Burst: whichever category landed, 1.5x.
  registerCounterFamily("GALAR_METALBURST_EFFECT", 3, 2, nil)
  -- Mirror Coat: special only, 2x (matches native Gen 1 Counter's own 2x
  -- and Gen 2's real Effects.counterDamage, gen2/Effects.lua:224-226).
  registerCounterFamily("GALAR_MIRRORCOAT_EFFECT", 2, 1, "special")
  -- Counter: physical only, 2x -- the real modern rule (category-based,
  -- same as legacy_move_takeover.lua's own counterable bulk-patch).
  -- GEN 1: inert (EffectRegistry's hardcoded `if move.id == "COUNTER"`
  -- branch runs first and ignores the effect field; documented native
  -- exception). GEN 2: main.lua's CUSTOM_EFFECT_PATCH repoints the live
  -- effect off the native EFFECT_COUNTER onto this record, so Gen 2's
  -- Counter finally resolves through THIS mod's run -> battle.damage.
  registerCounterFamily("GALAR_COUNTER_EFFECT", 2, 1, "physical")

  -- METALBURST priority is owned by national_dex (its own record says 0 --
  -- Metal Burst is NOT in Counter/Mirror Coat's -5 bracket). This engine no
  -- longer overrides it: turn_order.lua's movePriority now reads the move's
  -- priority from national_dex's own moveById reply, so a live-record patch
  -- here would be both redundant and wrong. (The -5 patch this replaced was
  -- added under the mistaken belief the whole counter family shared -5; the
  -- real, dex-verified values are Counter -5, Mirror Coat -5, Metal Burst 0.)

  mod.log:info("galar_gmax_dex: modern_movepool_counter loaded")
end
