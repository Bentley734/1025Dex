-- Phase 1 of the move-effect completion pipeline: wires moves_new.lua's
-- ~60 stat-stage-change stubs (effect="NO_ADDITIONAL_EFFECT" but a
-- functionCode naming a real Raise/Lower/Reset mechanic) to real,
-- Showdown-checked behavior. Split out of modern_combat.lua (whose own
-- header scopes it to "the modern damage formula") rather than grown
-- into it -- ~56 registrations is its own coherent unit, and this file
-- reuses modern_combat.lua's own primitives rather than duplicating them.
--
-- Two storages, on purpose:
--   atk/def/spa/spd: modern_combat.lua's OWN store (mod.exports.
--   changeStage) -- required, not a style choice, because
--   computeModernDamage reads stats out of that exact store and nothing
--   else; writing anywhere else would be silently invisible to damage.
--   speed/accuracy/evasion: modern_combat.lua's store never held these
--   (its own header says so) and computeModernDamage never reads them,
--   so the only storage that's actually CONSULTED by anything is each
--   engine's own native one: Gen 1's who.stages (confirmed read
--   directly by Damage.lua:63,98,100 and TurnOrder.lua:14 for speed/
--   accuracy/evasion/damage-adjacent checks) and Gen 2's
--   self.stages[side] (confirmed read by gen2/Battle.lua's own
--   vanillaAccuracyRoll:2023-2024). changeNativeStage below writes
--   straight to those real primitives -- src.battle.MoveEffects.
--   changeStage for Gen 1, Battle:changeStageAgainstMist for Gen 2 (both
--   pre-existing, already used by the native SPEED_UP2_EFFECT-family
--   ids) -- not a new parallel mechanism.
--
-- Gen 2 message caveat: a move_effects run() handler's RETURN VALUE is
-- never read on Gen 2 (gen2/Battle.lua:1533-1538 calls handler(...) and
-- discards it) -- only battle:emit() calls inside the handler reach the
-- player. Battle:changeStageAgainstMist emits its own real message, so
-- native-routed changes show up fine; store-routed ones (changeStage,
-- above) don't print anything on Gen 2 today -- a pre-existing gap
-- already true of GMAX_AMNESIA_EFFECT/GMAX_GROWTH_EFFECT, not something
-- this file introduces or is trying to fix.
--
-- STALE, CONFIRMED WRONG (2026-08-28, direct user report -- "liquidation
-- move is dealing no damage" -- see the `secondary()` function's own
-- header further down for the full correction): this used to claim
-- damaging-move secondary effects were safe as long as they gen2-guarded
-- (`if n.gen2 then return {} end`) INSIDE run(). They are not -- Gen 2's
-- dispatch calls ANY move_effects record with a .run field BEFORE the
-- damage path and returns immediately once it does, true regardless of
-- what the handler's body does, so that internal guard never had a
-- chance to matter -- Gen 2 had already skipped its own damage
-- computation by the time it ran. Every damaging move ever registered
-- through `secondary()` (29 real moves, not a hypothetical) dealt ZERO
-- damage on Gen 2 until this same pass fixed it by moving off kind=
-- "secondary" entirely. Pure status moves (power == 0, the `primary()`
-- function) were never affected -- there's no damage to pre-empt.
--
-- Chance-based secondaries use the engine's own 0-255 roll convention
-- (already established by native's statDownSide, MoveEffects.lua:136,
-- "33 percent + 1 (85/256)") -- rng(0,255) < N/256, rounded to the
-- nearest integer: 10% -> 26, 20% -> 51, 50% -> 128.
--
-- Left alone, explicitly, NOT guessed at:
--   CURSE (ghost-type-conditional: curses target with recurring damage
--     for a Ghost-type user, HP cost and all, vs. +1 Atk/+1 Def/-1 Spd
--     self otherwise -- a whole new curse-volatile mechanic, not a pure
--     stat change).
--   STOCKPILE (a new stack-counter mechanic Swallow/Spit Up read, not
--     just +1 Def/+1 SpDef).
--   BELLYDRUM (sets Attack straight to +6 at a fixed HP cost with its
--     own fail condition -- Phase 2 territory, recoil/drain/heal-shaped,
--     not a plain delta).
--   FLATTER, SWAGGER (raise a stat AND confuse the target in the same
--     breath -- confusion infliction is Phase 2's "status infliction"
--     bucket; wiring only the stat half would misreport these as fully
--     implemented when half their real effect is still missing).
return function(mod)
  local NativeMoveEffects = require("src.battle.MoveEffects")
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")

  local changeStage = mod.exports.changeStage
  local normalize = mod.exports.normalize
  local resetStages = mod.exports.resetStages
  local bossStatsDropBlocked = mod.exports.bossStatsDropBlocked
  local isGen2Battle = mod.exports.isGen2Battle
  assert(changeStage and normalize and resetStages and bossStatsDropBlocked and isGen2Battle,
    "modern_movepool_stages: combat/modern_combat.lua must load first")

  -- See file header. `n` is already-normalized ({battle,user,target,gen2}
  -- from modern_combat.lua's normalize); `who` is whichever side (n.user
  -- or n.target) is having the stat changed, `fromEnemy` only matters on
  -- Gen 1 (Gen 2's changeStageAgainstMist derives the same Mist gate
  -- itself from who ~= n.user).
  --
  -- Boss-fight "statsDrop" protection checked FIRST, ahead of either
  -- native branch: this is the exact gap this file's own header already
  -- flags for Substitute (native changeStageAgainstMist/NativeMoveEffects
  -- .changeStage have no protection hooks of their own at all) -- the
  -- same reasoning applies here, so the check has to live at this call
  -- site rather than inside either native function. See modern_combat
  -- .lua's own bossStatsDropBlocked header for the full rule.
  local function changeNativeStage(n, who, stat, delta, fromEnemy)
    if bossStatsDropBlocked(n.battle, who, delta) then
      return { romText(n.battle.data, "_NothingHappenedText", "Nothing happened!") }
    end
    if n.gen2 then
      n.battle:changeStageAgainstMist(n.user, who, stat, delta)
      return {}
    end
    return NativeMoveEffects.changeStage(n.battle, who, stat, delta, fromEnemy)
  end

  -- fromEnemy derives the same way registerStatEffect's targetsSelf
  -- param already implies it: a self-change is never hostile; a
  -- target-directed change is hostile (Mist/Substitute-gated) only when
  -- it's a drop, never when it's a buff (e.g. Decorate raising a
  -- target's stats is not something Mist should block).
  local function applyChange(n, ch)
    local who = ch.self and n.user or n.target
    local fromEnemy = (not ch.self) and ch.delta < 0
    if ch.native then
      return changeNativeStage(n, who, ch.stat, ch.delta, fromEnemy)
    end
    return changeStage(n.battle, who, ch.stat, ch.delta, fromEnemy, n.gen2)
  end

  -- Guaranteed stat change(s) on a pure status move (power == 0) --
  -- kind="primary" fires it whole and unconditionally on both engines
  -- (BattleState.lua's own pure-status-move block on Gen 1, the
  -- unconditional moveEffectRecordFor dispatch on Gen 2), same shape as
  -- GMAX_AMNESIA_EFFECT/GMAX_GROWTH_EFFECT above. accuracyChecked=true
  -- whenever any change is target-directed (BattleState.lua:3637-3650
  -- only rolls a miss at all when this is set -- confirmed established
  -- precedent, modern_status_effects.lua's GMAX_ATTRACT/TAUNT/TORMENT_
  -- EFFECT, all target-directed) -- a self-only buff leaves it unset,
  -- since ctx.target is always the opponent regardless of who the
  -- effect actually reads, and rolling a "miss" against the opponent's
  -- evasion for the user's OWN buff would be wrong.
  local function primary(effectId, changes)
    local targetDirected = false
    for _, ch in ipairs(changes) do
      if not ch.self then targetDirected = true end
    end
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      accuracyChecked = targetDirected or nil,
      run = function(a, b, c)
        local n = normalize(a, b, c)
        local out = {}
        for _, ch in ipairs(changes) do
          for _, m in ipairs(applyChange(n, ch)) do out[#out + 1] = m end
        end
        return out
      end,
    })
  end

  -- Secondary stat change(s) on a damaging move (power > 0).
  --
  -- REAL, CONFIRMED BUG FIXED HERE (2026-08-28, direct user report --
  -- "liquidation move is dealing no damage"): this function used to
  -- register `kind = "secondary"` with a real `run` field and guard Gen 2
  -- INSIDE that handler (`if n.gen2 then return {} end`) -- but Gen 2's
  -- own real dispatch (gen2/Battle.lua:1533-1538) calls ANY move_effects
  -- record with a `.run` field BEFORE its own damage path and returns
  -- immediately once it does, true regardless of what the handler's body
  -- does -- the exact same real gotcha modern_hazards.lua's own Rapid Spin
  -- section already found and fixed. An internal Gen-2 guard never had a
  -- chance to matter: Gen 2 had already skipped its own damage computation
  -- by the time that guard ran. Every one of this helper's real callers
  -- (Liquidation, Crunch, Close Combat, Superpower, Flash Cannon, Energy
  -- Ball, Bug Buzz, Rock Tomb, Rock Smash, Play Rough, Spirit Break,
  -- Struggle Bug, Leaf Storm, Ancient Power, Acid Spray, Apple Acid,
  -- Breaking Swipe, Bulldoze, Drum Beating, Fire Lash, Flame Charge, Grav
  -- Apple, Hammer Arm, Lunge, Metal Claw, Power-Up Punch, Razor Shell,
  -- Steel Wing -- confirmed, every single move ever registered through
  -- this function) dealt ZERO damage on Gen 2 -- a real, systemic bug
  -- across this whole file, not just the one move reported.
  --
  -- Fixed the exact same way Rapid Spin already was: `kind = "full"` (no
  -- run field at all -- invisible to that dispatch check on both engines,
  -- confirmed via EffectRegistry.runDamaging being nil-safe on every stage
  -- field) for real, ordinary damage on both generations, and the stat
  -- change wired through `battle.damage_dealt` instead (confirmed
  -- identical payload on both engines, fires only AFTER a landed,
  -- non-zero hit -- exactly "the hit actually landed and dealt damage,"
  -- the same real condition the old kind="secondary" dispatch used). One
  -- shared listener below (not one per call), keyed by the move's own
  -- real `effect` field via SECONDARY_STAT_EFFECTS.
  --
  -- This also correctly ENABLES the stat-change half on Gen 2 for the
  -- first time: the old code's own `if n.gen2 then return {} end` had
  -- deliberately disabled it there as an honest scope limit (this file's
  -- own header, "damaging-move secondary effects ALWAYS gen2-guard") --
  -- moot now that battle.damage_dealt is a real, correct, both-engines
  -- dispatch point, so Gen 2 gets the real chance-based stat drop for the
  -- first time too, not just a damage fix.
  --
  -- Message display is ALSO fixed as a side effect: applyChange's own
  -- return value is a message-string array (changeStage/changeNativeStage
  -- both return strings, never emit themselves) that the OLD run()-based
  -- dispatch only ever displayed on Gen 1 (this file's own header, "Gen 2
  -- message caveat" -- Gen 2's dispatch discards a handler's return value
  -- entirely). This listener explicitly `battle:emit`s every returned
  -- string itself, so the message now shows on BOTH engines instead of
  -- silently only Gen 1.
  --
  -- chance255 is the move's real percentage out of 256, nil for a
  -- genuinely unconditional secondary. Self-targeted secondaries (Close
  -- Combat, Leaf Storm, Superpower) apply even on a KOing hit here (no
  -- `target.mon.hp > 0`-style gate on this new dispatch path) -- arguably
  -- MORE correct than the old EffectRegistry-gated behavior for a
  -- self-drop, not a regression.
  local SECONDARY_STAT_EFFECTS = {} -- effectId -> {changes=, chance255=}
  local function secondary(effectId, changes, chance255)
    mod.content.move_effects:register(effectId, { kind = "full" })
    SECONDARY_STAT_EFFECTS[effectId] = { changes = changes, chance255 = chance255 }
  end
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local move = ev and ev.move
    local effectId = move and move.effect
    local entry = effectId and SECONDARY_STAT_EFFECTS[effectId]
    if not (battle and entry and ev.user and ev.target and (ev.damage or 0) > 0) then return end
    if entry.chance255 and battle.rng(0, 255) >= entry.chance255 then return end
    local n = { battle = battle, user = ev.user, target = ev.target, gen2 = isGen2Battle(battle) }
    for _, ch in ipairs(entry.changes) do
      for _, m in ipairs(applyChange(n, ch)) do
        battle:emit({ kind = "message", text = m })
      end
    end
  end)

  ------------------------------------------------------------------
  -- Pure status moves (guaranteed, primary)
  ------------------------------------------------------------------
  primary("GMAX_AROMATICMIST_EFFECT", { { stat = "spd", delta = 1 } })
  primary("GMAX_BULKUP_EFFECT", { { self = true, stat = "attack", delta = 1 }, { self = true, stat = "defense", delta = 1 } })
  primary("GMAX_CALMMIND_EFFECT", { { self = true, stat = "spa", delta = 1 }, { self = true, stat = "spd", delta = 1 } })
  -- Charge: +1 SpDef self is the only part wired -- doubling the next
  -- Electric move's power is a separate volatile this phase doesn't add.
  primary("GMAX_CHARGE_EFFECT", { { self = true, stat = "spd", delta = 1 } })
  primary("GMAX_CHARM_EFFECT", { { stat = "attack", delta = -2 } })
  primary("GMAX_COIL_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "defense", delta = 1 },
    { self = true, stat = "accuracy", delta = 1, native = true },
  })
  primary("GMAX_CONFIDE_EFFECT", { { stat = "spa", delta = -1 } })
  primary("GMAX_COSMICPOWER_EFFECT", { { self = true, stat = "defense", delta = 1 }, { self = true, stat = "spd", delta = 1 } })
  primary("GMAX_COTTONGUARD_EFFECT", { { self = true, stat = "defense", delta = 3 } })
  primary("GMAX_COTTONSPORE_EFFECT", { { stat = "speed", delta = -2, native = true } })
  -- Decorate raises the TARGET's own stats -- beneficial, not hostile
  -- (applyChange's fromEnemy rule already keeps Mist from blocking it).
  primary("GMAX_DECORATE_EFFECT", { { stat = "attack", delta = 2 }, { stat = "spa", delta = 2 } })
  primary("GMAX_DRAGONDANCE_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "speed", delta = 1, native = true },
  })
  primary("GMAX_EERIEIMPULSE_EFFECT", { { stat = "spa", delta = -2 } })
  primary("GMAX_FAKETEARS_EFFECT", { { stat = "spd", delta = -2 } })
  primary("GMAX_HONECLAWS_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "accuracy", delta = 1, native = true },
  })
  primary("GMAX_IRONDEFENSE_EFFECT", { { self = true, stat = "defense", delta = 2 } })
  primary("GMAX_METALSOUND_EFFECT", { { stat = "spd", delta = -2 } })
  primary("GMAX_NASTYPLOT_EFFECT", { { self = true, stat = "spa", delta = 2 } })
  primary("GMAX_NOBLEROAR_EFFECT", { { stat = "attack", delta = -1 }, { stat = "spa", delta = -1 } })
  -- Play Nice's real distinguishing trait (vs. plain LowerTargetAttack1)
  -- is bypassing Substitute while still respecting Mist -- changeStage
  -- couples both checks together, so that split isn't expressible here;
  -- approximated as a normal Mist+Substitute-gated -1 Atk instead of
  -- guessing at a bespoke carve-out.
  primary("GMAX_PLAYNICE_EFFECT", { { stat = "attack", delta = -1 } })
  primary("GMAX_ROCKPOLISH_EFFECT", { { self = true, stat = "speed", delta = 2, native = true } })
  primary("GMAX_SCARYFACE_EFFECT", { { stat = "speed", delta = -2, native = true } })
  primary("GMAX_SHIFTGEAR_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "speed", delta = 2, native = true },
  })
  primary("GMAX_SWEETSCENT_EFFECT", { { stat = "evasion", delta = -2, native = true } })
  -- Tar Shot: -1 Speed only -- doubling Fire-move damage taken is a
  -- separate volatile flag this phase doesn't add.
  primary("GMAX_TARSHOT_EFFECT", { { stat = "speed", delta = -1, native = true } })
  primary("GMAX_TEARFULLOOK_EFFECT", { { stat = "attack", delta = -1 }, { stat = "spa", delta = -1 } })

  ------------------------------------------------------------------
  -- Damaging moves, secondary stat effects
  ------------------------------------------------------------------
  secondary("GMAX_ACIDSPRAY_EFFECT", { { stat = "spd", delta = -2 } }) -- 100%
  -- Ancient Power: 10% to raise ALL FIVE non-HP stats (incl. Speed) by 1.
  secondary("GMAX_ANCIENTPOWER_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "defense", delta = 1 },
    { self = true, stat = "spa", delta = 1 }, { self = true, stat = "spd", delta = 1 },
    { self = true, stat = "speed", delta = 1, native = true },
  }, 26)
  secondary("GMAX_APPLEACID_EFFECT", { { stat = "spd", delta = -1 } }) -- 100%
  secondary("GMAX_BREAKINGSWIPE_EFFECT", { { stat = "attack", delta = -1 } }) -- 100%
  secondary("GMAX_BUGBUZZ_EFFECT", { { stat = "spd", delta = -1 } }, 26) -- 10%
  -- Bulldoze: 100% -1 Speed target -- grassy-terrain power reduction not
  -- modeled (this mod's terrain support is separate/unbuilt).
  secondary("GMAX_BULLDOZE_EFFECT", { { stat = "speed", delta = -1, native = true } })
  secondary("GMAX_CLOSECOMBAT_EFFECT", { { self = true, stat = "defense", delta = -1 }, { self = true, stat = "spd", delta = -1 } }) -- 100%, self
  secondary("GMAX_CRUNCH_EFFECT", { { stat = "defense", delta = -1 } }, 51) -- 20%
  secondary("GMAX_DRUMBEATING_EFFECT", { { stat = "speed", delta = -1, native = true } }) -- 100%
  secondary("GMAX_ENERGYBALL_EFFECT", { { stat = "spd", delta = -1 } }, 26) -- 10%
  secondary("GMAX_FIRELASH_EFFECT", { { stat = "defense", delta = -1 } }) -- 100%
  secondary("GMAX_FLAMECHARGE_EFFECT", { { self = true, stat = "speed", delta = 1, native = true } }) -- 100%, self
  secondary("GMAX_FLASHCANNON_EFFECT", { { stat = "spd", delta = -1 } }, 26) -- 10%
  -- Grav Apple: 100% -1 Def target -- the Gravity-field power boost is a
  -- separate, unbuilt field-state mechanic.
  secondary("GMAX_GRAVAPPLE_EFFECT", { { stat = "defense", delta = -1 } })
  secondary("GMAX_HAMMERARM_EFFECT", { { self = true, stat = "speed", delta = -1, native = true } }) -- 100%, self
  secondary("GMAX_LEAFSTORM_EFFECT", { { self = true, stat = "spa", delta = -2 } }) -- 100%, self
  secondary("GMAX_LEAFTORNADO_EFFECT", { { stat = "accuracy", delta = -1, native = true } }, 128) -- 50%
  secondary("GMAX_LIQUIDATION_EFFECT", { { stat = "defense", delta = -1 } }, 51) -- 20%
  secondary("GMAX_LUNGE_EFFECT", { { stat = "attack", delta = -1 } }) -- 100%
  secondary("GMAX_METALCLAW_EFFECT", { { self = true, stat = "attack", delta = 1 } }, 26) -- 10%
  secondary("GMAX_PLAYROUGH_EFFECT", { { stat = "attack", delta = -1 } }, 26) -- 10%
  secondary("GMAX_POWERUPPUNCH_EFFECT", { { self = true, stat = "attack", delta = 1 } }) -- 100%
  secondary("GMAX_RAZORSHELL_EFFECT", { { stat = "defense", delta = -1 } }, 128) -- 50%
  secondary("GMAX_ROCKSMASH_EFFECT", { { stat = "defense", delta = -1 } }, 128) -- 50%
  secondary("GMAX_ROCKTOMB_EFFECT", { { stat = "speed", delta = -1, native = true } }) -- 100%
  secondary("GMAX_SPIRITBREAK_EFFECT", { { stat = "spa", delta = -1 } }) -- 100%
  secondary("GMAX_STEELWING_EFFECT", { { self = true, stat = "defense", delta = 1 } }, 26) -- 10%
  secondary("GMAX_STRUGGLEBUG_EFFECT", { { stat = "spa", delta = -1 } }) -- 100%
  secondary("GMAX_SUPERPOWER_EFFECT", { { self = true, stat = "attack", delta = -1 }, { self = true, stat = "defense", delta = -1 } }) -- 100%, self

  ------------------------------------------------------------------
  -- Clear Smog: wipes the TARGET's stat stages entirely (all 7 boost
  -- keys, Showdown's clearBoosts()) -- own store's atk/def/spa/spd via
  -- resetStages (gen2-aware), native who.stages.{speed,accuracy,evasion}
  -- directly (Gen 1's storage -- a Gen 2 raw mon has no .stages, so the
  -- guard skips it there; Gen 2's speed/evasion live in battle.stages
  -- [side], out of scope for this wipe, same as changeNativeStage).
  --
  -- Round 15: converted from kind="secondary"+run to kind="full" + a
  -- battle.damage_dealt listener. Clear Smog is a DAMAGING move (power
  -- 50), so the old shape hit the SAME systemic Gen-2 zero-damage bug
  -- this file's secondary() header documents (Gen 2's dispatch calls
  -- ANY move_effects record with a .run field before its own damage
  -- path and returns -- an internal `if n.gen2 then return {} end` guard
  -- never mattered because damage was already skipped). This listener
  -- runs AFTER a landed non-zero hit on BOTH engines, and enables the
  -- stat wipe on Gen 2 for the first time (the old handler was a
  -- hard no-op there), mirroring the secondary() migration above.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_CLEARSMOG_EFFECT", { kind = "full" })
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local move = ev and ev.move
    if not (battle and move and move.effect == "GMAX_CLEARSMOG_EFFECT") then return end
    if (ev.damage or 0) <= 0 then return end
    local target = ev and ev.target
    if not target then return end
    local gen2 = isGen2Battle(battle)
    -- Boss-fight "statsDrop" protection: Clear Smog ZEROES every stage
    -- rather than applying a signed delta, so it never reaches either
    -- of bossStatsDropBlocked's own call sites (changeStage/
    -- changeNativeStage) -- confirmed real gap, this mod's own
    -- research this session. Stripping the boss's own positive boosts
    -- down to 0 is a worsening exactly like any other drop (the
    -- dominant real use of this move against a boss), so the whole
    -- effect is blocked outright against a protected target rather
    -- than trying to selectively keep only the "cures an existing
    -- debuff" half.
    if target == battle.enemy and mod.exports.bossFightHas
        and mod.exports.bossFightHas(battle, "statsDrop") then
      battle:emit({ kind = "message", text = romText(battle.data, "_NothingHappenedText", "Nothing happened!") })
      return
    end
    local changed = resetStages(battle, target, gen2)
    if target.stages then
      for _, stat in ipairs({ "speed", "accuracy", "evasion" }) do
        if (target.stages[stat] or 0) ~= 0 then
          target.stages[stat] = nil
          changed = true
        end
      end
    end
    if not changed then
      battle:emit({ kind = "message", text = romText(battle.data, "_NothingHappenedText", "Nothing happened!") })
      return
    end
    local name = target.isPlayer and target.name or Strings("Enemy %s", target.name)
    battle:emit({ kind = "message", text = Strings("%s's stat\nchanges were\nremoved!", name) })
  end)

  ------------------------------------------------------------------
  -- Phase 15 of the missing-effects plan: self stat-stage boosts, plus
  -- the target-directed drops that share the same primitive.
  --
  -- WHY THESE WERE DEAD. national_dex tags each of these 19 moves with a
  -- real `statChanges` list, but `statChance = 0` -- an unconditional
  -- whole-move change, not a secondary. installMovepoolEffects's generic
  -- branch only fires when `statChance > 0` (main.lua's own `statChance`
  -- computation), so none of them was ever applied. Their real Showdown
  -- shape is the flat `boosts` map on a Status move (moves.ts, cited per
  -- move below), which is exactly what the primary()/applyChange helpers
  -- above already express: attack/defense/spa/spd land in modern_combat
  -- .lua's own store (the one computeModernDamage reads), speed takes the
  -- native path (Battle:changeStageAgainstMist on Gen 2, NativeMoveEffects
  -- .changeStage on Gen 1).
  --
  -- FOUR OF THEM ALREADY HAD A NATIVE EFFECT ID (Baby-Doll Eyes, Feather
  -- Dance, Howl, Shelter -- national_dex's effectModeled = true). That is
  -- NOT the same as working: the native effect writes the ENGINE's own
  -- stage table, and computeModernDamage reads ONLY modern_combat's store
  -- (its own rawStat/stagesFor header), so on Gen 2 a native Growl-style
  -- drop never reached the modern damage formula. Repointing them here is
  -- the real fix, not redundancy; it also closes Feather Dance's Gen-1
  -- dead record (gen1EffectModeled = false).
  --
  -- FIVE HAVE A REAL SECOND MECHANIC beyond the flat boosts, handled by
  -- their own bespoke record below rather than primary(): Fillet Away and
  -- Belly Drum cost HP, Captivate is gender-gated, Gear Up / Magnetic
  -- Flux only reach Plus/Minus holders, Tidy Up also clears hazards and
  -- Substitutes, Geomancy charges for a turn, and Curse is two moves in
  -- one body (a self boost or a curse, by the user's own type).
  ------------------------------------------------------------------

  -- The raw mon behind whichever generation's battler this is (Gen 1
  -- hands a wrapper, Gen 2 the mon itself -- the convention modern_hazards
  -- .lua's own monOf documents).
  local function monOf(who) return who and (who.mon or who) or nil end

  local function emitMsg(battle, text)
    if battle and battle.emit then battle:emit({ kind = "message", text = text }) end
  end

  local function failMsg(battle) emitMsg(battle, Strings("But it failed!")) end

  local function nameOf(battle, who)
    if battle and battle.monName then
      local ok, nm = pcall(battle.monName, battle, who)
      if ok and nm then return nm end
    end
    local m = monOf(who)
    return (m and m.name) or "?"
  end

  -- The CURRENT stage of one stat, read from whichever store actually
  -- holds it: modern_combat's atk/def/spa/spd bucket, or native speed
  -- (Gen 2 battle.stages[side].speed, Gen 1 mon.stages.speed). Used only
  -- to tell a real change from a capped no-op, which changeStage's
  -- message array cannot (it returns "won't rise anymore" either way).
  local function stageValue(battle, who, stat, gen2)
    if stat == "speed" or stat == "accuracy" or stat == "evasion" then
      if gen2 then
        local side = battle.sideOf and battle:sideOf(who)
        local bucket = side and battle.stages and battle.stages[side]
        return (bucket and bucket[stat]) or 0
      end
      local m = monOf(who)
      return (m and m.stages and m.stages[stat]) or 0
    end
    local s = mod.exports.stagesFor and mod.exports.stagesFor(battle, who) or {}
    return s[stat] or 0
  end

  -- Apply a set of changes to ONE recipient, emitting every message and
  -- reporting whether any stage actually moved. `changes` entries use the
  -- same {self=, stat=, delta=, native=} shape applyChange already takes;
  -- user/target are both pointed at `who` so direction is carried only by
  -- `self` (a Plus/Minus ally is a "self" recipient for our purposes).
  local function runChanges(n, who, changes)
    local nn = { battle = n.battle, user = who, target = who, gen2 = n.gen2 }
    local moved = false
    for _, ch in ipairs(changes) do
      local before = stageValue(n.battle, who, ch.stat, n.gen2)
      for _, msg in ipairs(applyChange(nn, ch) or {}) do emitMsg(n.battle, msg) end
      if stageValue(n.battle, who, ch.stat, n.gen2) ~= before then moved = true end
    end
    return moved
  end

  -- A stat boost applied to the user's OWN SIDE, one recipient at a time.
  -- Howl is national_dex target "user-and-allies" (real Showdown
  -- `target: "allies"`, moves.ts:9016 -- the user AND every adjacent
  -- ally). Coaching is the games' own "all adjacent allies but NOT the
  -- user" (Bulbapedia, Coaching: "boosts the Attack and Defense of all
  -- allies (but not the user) ... fails in a Single Battle or when no ally
  -- is present"); Showdown labels it `adjacentAlly` (one ally, which
  -- coincides in doubles), but the all-allies-except-self reading is the
  -- real rule and is what `includeUser = false` gives here. `includeUser`
  -- defaults to true (the user-and-allies shape).
  --
  -- Adjacency is the engine's real N-way seam, so the recipient set is the
  -- user plus literally-adjacent allies in doubles/triples and the whole
  -- team in the 4v4/boss/horde layouts -- no per-layout wiring here. Each
  -- recipient runs through runChanges (messages emit on both
  -- generations); the move fails only when no recipient's stage moved.
  local function teamBoostMove(effectId, changes, includeUser)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      run = function(a, b, c)
        local n = normalize(a, b, c)
        local battle = n.battle
        local recipients = {}
        if includeUser ~= false then recipients[#recipients + 1] = n.user end
        local requestAdjacency = mod.exports.requestAdjacency
        if requestAdjacency then
          local ok, adj = pcall(requestAdjacency, battle, n.user, nil)
          if ok and adj and adj.allies then
            for _, ally in ipairs(adj.allies) do recipients[#recipients + 1] = ally end
          end
        end
        local any = false
        for _, who in ipairs(recipients) do
          if runChanges(n, who, changes) then any = true end
        end
        if not any then failMsg(n.battle) end
      end,
    })
  end

  -- Flat, guaranteed self boosts. Every one is Showdown's `boosts` map on
  -- a Status move; the citation beside each move is its block in moves.ts.
  primary("GMAX_QUIVERDANCE_EFFECT", { -- moves.ts:14539-14543
    { self = true, stat = "spa", delta = 1 }, { self = true, stat = "spd", delta = 1 },
    { self = true, stat = "speed", delta = 1, native = true },
  })
  primary("GMAX_VICTORYDANCE_EFFECT", { -- moves.ts:20382-20386
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "defense", delta = 1 },
    { self = true, stat = "speed", delta = 1, native = true },
  })
  primary("GMAX_TAILGLOW_EFFECT", { { self = true, stat = "spa", delta = 3 } }) -- moves.ts:18832
  primary("GMAX_WORKUP_EFFECT", { -- moves.ts:21039-21042
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "spa", delta = 1 },
  })
  -- Autotomize's real second half (halving the user's weight, moves.ts:898-
  -- 902) is NOT modelled: this engine tracks no weight stat in the modern
  -- damage path (Heavy Slam / Low Kick read none either). Honest partial.
  primary("GMAX_AUTOTOMIZE_EFFECT", { { self = true, stat = "speed", delta = 2, native = true } }) -- moves.ts:894-896
  primary("GMAX_DEFENDORDER_EFFECT", { -- moves.ts:3413-3416
    { self = true, stat = "defense", delta = 1 }, { self = true, stat = "spd", delta = 1 },
  })
  primary("GMAX_SHELTER_EFFECT", { { self = true, stat = "defense", delta = 2 } }) -- moves.ts:16320
  -- Howl targets user-and-allies (moves.ts:9016) -- the user AND every
  -- adjacent ally, so it is a real side-wide boost (in singles that is the
  -- user alone, which is all the native two-battler fallback reports).
  teamBoostMove("GMAX_HOWL_EFFECT", { { self = true, stat = "attack", delta = 1 } })
  -- Target-directed drops. primary() sets accuracyChecked for these (a
  -- self buff must not roll against the foe's evasion); applyChange's
  -- fromEnemy rule makes them Mist/Substitute/ability-gated.
  primary("GMAX_TICKLE_EFFECT", { { stat = "attack", delta = -1 }, { stat = "defense", delta = -1 } }) -- moves.ts:19614-19617
  primary("GMAX_FEATHERDANCE_EFFECT", { { stat = "attack", delta = -2 } }) -- moves.ts:5163
  primary("GMAX_BABYDOLLEYES_EFFECT", { { stat = "attack", delta = -1 } }) -- moves.ts:958-960

  ------------------------------------------------------------------
  -- Captivate -- SpA -2, but only against an OPPOSITE known gender;
  -- same gender or either genderless fails (moves.ts:2189-2191, the
  -- real onTryImmunity; the engine's mon.gender is the full lowercase
  -- "male"/"female"/"unknown").
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_CAPTIVATE_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local u, t = monOf(n.user), monOf(n.target)
      local ug, tg = u and u.gender, t and t.gender
      local function known(g) return g == "male" or g == "female" end
      if not (known(ug) and known(tg) and ug ~= tg) then failMsg(n.battle); return end
      for _, msg in ipairs(applyChange(n, { stat = "spa", delta = -2 }) or {}) do
        emitMsg(n.battle, msg)
      end
    end,
  })

  ------------------------------------------------------------------
  -- Fillet Away -- Atk/SpA/Spe +2 each, then pay half max HP. Fails if
  -- the user is at or below half HP or has 1 max HP (moves.ts:5281-5285);
  -- Showdown boosts FIRST and returns null without paying when no boost
  -- landed, so the HP cost is gated on `moved` here too.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_FILLETAWAY_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local m = monOf(n.user)
      local maxHp = m and (m.maxHp or (m.stats and m.stats.hp))
      if not (m and maxHp and maxHp > 1 and (m.hp or 0) > math.floor(maxHp / 2)) then
        failMsg(n.battle); return
      end
      local moved = runChanges(n, n.user, {
        { self = true, stat = "attack", delta = 2 },
        { self = true, stat = "spa", delta = 2 },
        { self = true, stat = "speed", delta = 2, native = true },
      })
      if not moved then failMsg(n.battle); return end
      local cost = math.max(1, math.floor(maxHp / 2))
      m.hp = math.max(0, (m.hp or 0) - cost)
      if n.battle.emit then
        n.battle:emit({ kind = "damage", side = n.battle:sideOf(n.user), amount = cost, hp = m.hp, anim = false })
      end
      emitMsg(n.battle, Strings("%s cut its own HP to power up!", nameOf(n.battle, n.user)))
    end,
  })

  ------------------------------------------------------------------
  -- Belly Drum -- fail when HP is at/below half, max HP is 1 (Shedinja
  -- clause), or Attack is already maxed; else pay half max HP and set
  -- Attack to +6 (moves.ts:1224-1227, a +12 boost clamped by the same
  -- changeStage the cart's own cap uses).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_BELLYDRUM_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local m = monOf(n.user)
      local maxHp = m and (m.maxHp or (m.stats and m.stats.hp))
      local atk = stageValue(n.battle, n.user, "attack", n.gen2)
      if not (m and maxHp and maxHp > 1 and (m.hp or 0) > math.floor(maxHp / 2) and atk < 6) then
        failMsg(n.battle); return
      end
      local cost = math.max(1, math.floor(maxHp / 2))
      m.hp = math.max(0, (m.hp or 0) - cost)
      if n.battle.emit then
        n.battle:emit({ kind = "damage", side = n.battle:sideOf(n.user), amount = cost, hp = m.hp, anim = false })
      end
      for _, msg in ipairs(changeStage(n.battle, n.user, "attack", 12, false, n.gen2) or {}) do
        emitMsg(n.battle, msg)
      end
      emitMsg(n.battle, Strings("%s cut its HP and maximized its Attack!", nameOf(n.battle, n.user)))
    end,
  })

  ------------------------------------------------------------------
  -- Curse -- two moves in one body (moves.ts:3277-3303). A non-Ghost
  -- user trades a Spe stage for Atk +1 / Def +1 (refused only when BOTH
  -- raises are capped); a Ghost user pays half its max HP -- the cut can
  -- faint it -- to set the `cursed` volatile on the target. The volatile
  -- rides the same mon.volatile bucket the engine's own tickSeedAndCurse
  -- residual reads (tickSeedAndCurse is Gen 2 only; the Gen 1 residual
  -- has no curse arm -- a documented, pre-existing engine limit).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_CURSE_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user = n.user
      local ghost = false
      local curTypesOf = mod.exports.curTypesOf
      for _, t in ipairs(curTypesOf and curTypesOf(user, n.gen2) or {}) do
        if t == "GHOST" then ghost = true end
      end
      if not ghost then
        local atk = stageValue(n.battle, user, "attack", n.gen2)
        local def = stageValue(n.battle, user, "defense", n.gen2)
        if atk >= 6 and def >= 6 then failMsg(n.battle); return end
        runChanges(n, user, {
          { self = true, stat = "speed", delta = -1, native = true },
          { self = true, stat = "attack", delta = 1 },
          { self = true, stat = "defense", delta = 1 },
        })
        return
      end
      local target = n.target
      local tm = monOf(target)
      local um = monOf(user)
      if not (tm and um) then failMsg(n.battle); return end
      tm.volatile = tm.volatile or {}
      local vol = tm.volatile
      if tm.vanished or (tm.substitute or 0) > 0 or (tm.substituteHP or 0) > 0 or vol.cursed then
        failMsg(n.battle); return
      end
      vol.cursed = true
      local maxHp = um.maxHp or (um.stats and um.stats.hp) or 1
      local cost = math.max(1, math.floor(maxHp / 2))
      um.hp = math.max(0, (um.hp or 0) - cost)
      if n.battle.emit then
        n.battle:emit({ kind = "damage", side = n.battle:sideOf(user), amount = cost, hp = um.hp, anim = false })
      end
      emitMsg(n.battle, Strings("%s cut its own HP and put a CURSE on %s!",
        nameOf(n.battle, user), nameOf(n.battle, target)))
    end,
  })

  ------------------------------------------------------------------
  -- Tidy Up -- remove every Substitute on the field and both sides'
  -- hazards, then Atk +1 / Spe +1 to the user; succeeds if ANY of those
  -- happened (moves.ts:19629-19650). Native Spikes lives in battle.spikes
  -- [side] (a 0-3 count, modern_hazards.lua's own upgrade); the four
  -- mod-owned hazards live in battle.hazards[side].
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_TIDYUP_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      local did = false
      local all = (mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle))
        or { battle.player, battle.enemy }
      for _, who in ipairs(all) do
        local m = monOf(who)
        if m then
          if (m.substitute or 0) > 0 then m.substitute = nil; did = true end
          if (m.substituteHP or 0) > 0 then m.substituteHP = nil; did = true end
        end
      end
      for _, side in ipairs({ "player", "enemy" }) do
        if mod.exports.hazardsFor then
          local h = mod.exports.hazardsFor(battle, side)
          if h.stealthRock or h.toxicSpikes > 0 or h.sharpSteel or h.stickyWeb then
            h.stealthRock, h.toxicSpikes, h.sharpSteel, h.stickyWeb = false, 0, false, false
            did = true
          end
        end
        if battle.spikes and (battle.spikes[side] or 0) > 0 then
          battle.spikes[side] = 0
          did = true
        end
      end
      local moved = runChanges(n, n.user, {
        { self = true, stat = "attack", delta = 1 },
        { self = true, stat = "speed", delta = 1, native = true },
      })
      if not (did or moved) then failMsg(n.battle) end
    end,
  })

  ------------------------------------------------------------------
  -- Gear Up / Magnetic Flux -- +1 Atk/+1 SpA and +1 Def/+1 SpD to every
  -- Plus/Minus holder on the user's side (moves.ts:6484-6497 / :10831-
  -- 10845). In singles the user is the only candidate, so it lands on
  -- itself when it holds Plus or Minus and fails otherwise.
  ------------------------------------------------------------------
  local function sideBoostMove(effectId, changes)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      run = function(a, b, c)
        local n = normalize(a, b, c)
        local battle = n.battle
        local abilityIdOf = mod.exports.abilityIdOf
        local side = battle.sideOf and battle:sideOf(n.user)
        local all = (mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle))
          or { n.user }
        local any = false
        for _, who in ipairs(all) do
          local sameSide = (not side) or (not battle.sideOf) or (battle:sideOf(who) == side)
          local id = sameSide and abilityIdOf and abilityIdOf(who)
          if id == "PLUS" or id == "MINUS" then
            if runChanges(n, who, changes) then any = true end
          end
        end
        if not any then failMsg(n.battle) end
      end,
    })
  end
  sideBoostMove("GMAX_GEARUP_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "spa", delta = 1 },
  })
  sideBoostMove("GMAX_MAGNETICFLUX_EFFECT", {
    { self = true, stat = "defense", delta = 1 }, { self = true, stat = "spd", delta = 1 },
  })

  -- Coaching -- Atk +1 / Def +1 to every adjacent ALLY, never the user
  -- (Bulbapedia: "boosts the Attack and Defense of all allies (but not
  -- the user) ... fails in a Single Battle or when no ally is present").
  -- national_dex's own record (target "user-and-allies", statChanges
  -- Atk+1/Def+1) is close but imprecise about the user; Showdown's
  -- `adjacentAlly` is imprecise about the count -- the game's
  -- all-allies-except-self rule is what this encodes (in doubles the one
  -- ally, in triples/4v4 the adjacent wing(s)). No ally means it fails.
  teamBoostMove("GMAX_COACHING_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "defense", delta = 1 },
  }, false)

  ------------------------------------------------------------------
  -- Geomancy -- a real two-turn charge, then SpA/SpD/Spe +2 each
  -- (moves.ts:6543-6552). The charge rides the generic `charge` seam
  -- (the same one Solar Beam uses): turn one announces and flips to the
  -- release turn via BattleState's own charge branch, turn two runs the
  -- boosts. The Gen 2 charge table is the one the native dispatch reads.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_GEOMANCY_EFFECT", {
    kind = "primary",
    charge = { anim = "XSTATITEM_ANIM", enemyAnim = "XSTATITEM_DUPLICATE_ANIM" },
    run = function(a, b, c)
      local n = normalize(a, b, c)
      runChanges(n, n.user, {
        { self = true, stat = "spa", delta = 2 },
        { self = true, stat = "spd", delta = 2 },
        { self = true, stat = "speed", delta = 2, native = true },
      })
    end,
  })
  pcall(function()
    require("src.battle.gen2.Effects").CHARGE.GMAX_GEOMANCY_EFFECT = { text = "%s is absorbing power!" }
  end)

  mod.log:info("galar_gmax_dex: modern_movepool_stages loaded")
end
