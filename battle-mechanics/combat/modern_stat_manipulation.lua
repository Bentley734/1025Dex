-- Phase 2 of the missing-effects pipeline: stat-stage and stat-source
-- manipulation -- the moves whose real mechanic is a stage SWAP, a raw-stat
-- SPLIT or SWAP, a self stat SHIFT, a full INVERSION, a random boost, or a
-- cumulative Speed drop. None of these are expressible as the generic
-- signed-delta secondary the rest of this mod already wires
-- (main.lua's installMovepoolEffects + modern_movepool_stages.lua's
-- primary()/secondary()): a swap/split needs a raw READ and WRITE of both
-- battlers at once, Topsy-Turvy needs the whole stage table at once, and
-- Power Shift needs a persistent, toggleable raw-stat state.
--
-- Showdown source of truth (scratch/showdown/moves.ts), one citation per
-- move, all transcribed directly this round:
--   acupressure   (137-166)   onHit: collect every boost key whose value is
--                             < 6, `this.sample(stats)` one, +2 to it;
--                             `return false` (move fails) when none is
--                             eligible. target "adjacentAllyOrSelf"
--                             (self in singles), flags { metronome: 1 }
--                             only -- no protect, no reflectable, no mirror.
--   guardsplit    (7950-7972) onHit: floor average of the two mons'
--                             storedStats.def, written to both; same for
--                             .spd. flags { protect, allyanim, metronome },
--                             no bypasssub.
--   guardswap     (7973-7999) onHit: swap the def/spd BOOSTS via setBoost
--                             (a raw write -- see the next paragraph);
--                             flags include bypasssub.
--   heartswap     (8448-8476) onHit: swap every boost; bypasssub.
--   powershift    (13721-13758) volatileStatus 'powershift': onStart and
--                             onEnd each swap storedStats.atk <-> .def,
--                             onRestart calls removeVolatile -- so using it
--                             again while active TOGGLES IT OFF. target
--                             "self", flags { snatch }.
--   powersplit    (13760-13782) onHit: floor average of storedStats.atk,
--                             both written; same for .spa.
--   powerswap     (13783-13810) onHit: swap the atk/spa BOOSTS; bypasssub.
--   shellsmash    (16256-16278) boosts { def:-1, spd:-1, atk:+2, spa:+2,
--                             spe:+2 }, target "self".
--   speedswap     (17431-17450) onHit: swap storedStats.spe; bypasssub.
--   spicyextract  (17451-17468) boosts { atk:+2, def:-2 }, target "normal",
--                             flags protect/reflectable/mirror (no bypasssub).
--   strengthsap   (18175-18195) onHit: fail outright when the target's atk
--                             boost is exactly -6; read atk =
--                             target.getStat('atk', false, true) (stages
--                             included, ability modifiers excluded); boost
--                             atk -1 on the target; heal the USER by that
--                             atk amount; succeed if EITHER the heal or the
--                             drop happened (the heal is not gated on the
--                             drop landing).
--   syrupbomb     (18762-18794) secondary { chance: 100, volatileStatus:
--                             'syrupbomb' }; the volatile has duration 4 and
--                             onResidualOrder 14, and its onResidual boosts
--                             spe -1. battle.ts:515-517 decrements duration
--                             BEFORE running onResidual and runs `end`
--                             (not onResidual) on the tick that reaches 0,
--                             so duration 4 is exactly 3 applied -1 Spe
--                             ticks (turn of application + the next two).
--   topsyturvy    (19656-19676) onHit: negate every NONZERO boost; `return
--                             false` when every boost was already 0.
--
-- The swap/topsy family writes stages through readStage/writeStage (below),
-- which is a raw Pokemon#setBoost equivalent (pokemon.ts:1239-1244): no
-- clamp, no message, no Contrary/Simple, and no Defiant/Competitive or
-- Opportunist reaction. Everything that IS a real signed delta (Shell Smash,
-- Spicy Extract, Acupressure, Strength Sap's drop, Syrup Bomb's residual
-- tick) still goes through the exported changeStage, so Contrary/Simple,
-- Defiant/Competitive, the Mist/Substitute gate and the boss statsDrop rule
-- all apply exactly as they already do everywhere else in this mod.
--
-- Storage split, inherited from combat/modern_combat.lua's own stage-store
-- header (reused, not re-derived): this mod's stage store only ever tracks
-- attack/defense/spa/spd -- computeModernDamage reads those four from that
-- exact store -- so speed/accuracy/evasion MUST be written to each engine's
-- OWN native table: Gen 2 battle.stages[side] (gen2-Battle.lua:413
-- newStages: attack/defense/speed/specialAttack/specialDefense/accuracy/
-- evasion) and Gen 1 the battler wrapper's own who.stages (BattleState.lua
-- :618, read directly by Damage.lua:86/116-117). See NATIVE_STAGE below.
--
-- Raw stats (Power/Guard Split, Speed Swap, Power Shift) are read/written
-- through storedStat/setStoredStat, NOT through modern_combat.lua's rawStat:
-- Showdown's swaps/splits operate on Pokemon#storedStats, which is the
-- UNDERLYING stat -- Wonder Room swaps the KEY at read time in getStat
-- (pokemon.ts:596-604 and the wonderroom condition's own "swapping defenses
-- partially implemented in Pokemon#calculateStat/#getStat" note), it does
-- NOT rewrite storedStats. rawStat applies that key swap, so using it here
-- would average/swap the Wonder-Room-swapped value instead of the stored
-- one. setStoredStat also mirrors Gen 2's spa/spd onto the native
-- specialAttack/specialDefense keys (gen2_modern_stats.lua:75-77 keeps both
-- in sync), so a split does not silently desync the two consumers.
--
-- Round 184 -- battle scoping: Power Split and Guard Split AVERAGE the two
-- mons' stored stats in place (moves.ts powersplit 13760-13782 / guardsplit
-- 7950-7972 both write Pokemon#storedStats directly), so the averaged value
-- must live only while the split is in effect on the field and each mon must
-- get its OWN stats back the moment it leaves. Without a restore the write
-- was permanent: the averaged number stayed on the party mon after the fight
-- (and rode into the save). The fix is the same shape round 183 gave
-- Transform's copied stats -- but the pre-state is kept per STAT KEY on the
-- mon itself (__g9StatBaseline, NOT mon.volatile; see the Power Shift note
-- below for why), captured lazily the FIRST time any battle-scoped raw-stat
-- effect (Power Split / Guard Split / Power Shift) touches that key, and put
-- back on switch-out, faint, and battle end. Capturing per-key and only once
-- is what makes two effects interleaved on one mon (Power Shift then Power
-- Split, say) still revert to the mon's true pre-battle numbers rather than
-- to the other effect's snapshot. Power Shift's own powerShiftPre is kept
-- only for its mid-battle toggle (Showdown's onRestart removeVolatile swaps
-- the pair back immediately, with no switch involved).
--
-- Round 185 -- Speed Swap joins them. It is the same class of permanent
-- in-place write (moves.ts speedswap 13784-13806 writes Pokemon#storedStats
-- directly, then a native battle reverts by rebuilding its battler on switch
-- while g9-Battle-Scene reuses ONE engine battler per mon), so it now captures
-- the same per-key baseline before its swap and is reverted by the identical
-- switch / faint / battle-end listeners.
--
-- Gen 2 message note: a mod primary run()'s RETURN VALUE is discarded on Gen
-- 2 (gen2-Battle.lua:1750-1754 -- `handler(...); return`), so every handler
-- builds its message list once and finish() emits each line on Gen 2 while
-- returning the list for Gen 1's performMove to sayNext. The native speed/
-- accuracy/evasion route for Gen 2 (Battle:changeStageAgainstMist) emits its
-- OWN message, so those lines are never double-emitted by finish().
--
-- Accuracy: registerPrimary's accuracyChecked is deliberately set ONLY for
-- Strength Sap (real 100-accuracy move). Every other move here is either
-- self-targeted or a Showdown `accuracy: true` never-miss move, and a
-- national_dex accuracy of 0 with accuracyChecked=true would make Gen 1 roll
-- against a threshold of ~0 (Damage.accuracyThreshold's acc = 0 -> applyStage
-- clamps to 1) and miss almost every time -- the same latent bug
-- modern_movepool_stages.lua's generic primary() has for Confide/Decorate/
-- Play Nice, flagged to the user rather than copied here.
return function(mod)
  local NativeMoveEffects = require("src.battle.MoveEffects")
  local Stats = require("src.pokemon.Stats")
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")

  local normalize = mod.exports.normalize
  local changeStage = mod.exports.changeStage
  local stagesFor = mod.exports.stagesFor
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  assert(normalize and changeStage and stagesFor and displayNameFor and isGen2Battle,
    "modern_stat_manipulation: combat/modern_combat.lua must load first")

  -- All seven boost keys, in Showdown's own Pokemon#boosts insertion order
  -- (atk, def, spa, spd, spe, accuracy, evasion) -- the order Heart Swap and
  -- Acupressure iterate in.
  local ALL_BOOST_KEYS = { "attack", "defense", "spa", "spd", "speed", "accuracy", "evasion" }

  -- The three stats this mod's own store does NOT track (modern_combat.lua's
  -- stage-store header: computeModernDamage never reads them). A read or
  -- write for any of these goes straight to the engine's native table.
  local NATIVE_STAGE = { speed = true, accuracy = true, evasion = true }

  ------------------------------------------------------------------
  -- Small cross-generation helpers
  ------------------------------------------------------------------

  -- The underlying party-mon table (Gen 1's battler wrapper carries its mon
  -- as .mon; Gen 2's raw mon IS the table). Used only for fields that live on
  -- the mon itself (HP, and Power Shift's / Syrup Bomb's / the split
  -- baseline's stored state). Falls back to `who` itself for a raw mon handed
  -- in on Gen 1 (the battle.ended party sweep and the battler_switched
  -- payload both carry raw mons), the same `who.mon or who` modern_transform
  -- uses.
  local function monOf(who, gen2)
    if not who then return nil end
    if gen2 then return who end
    return who.mon or who
  end

  -- The real stat table a mon reads its stored stats from (Gen 1 wrapper:
  -- curStats, which IS mon.stats, BattleState.lua:620; Gen 2 raw mon: .stats).
  -- Falls back to .stats so a raw mon handed in on Gen 1 still resolves.
  local function statTableOf(who, gen2)
    if not who then return nil end
    if gen2 then return who.stats end
    return who.curStats or who.stats
  end

  -- Showdown storedStats reader: raw, no Wonder Room key swap (see header).
  local function storedStat(who, key, gen2)
    local stats = statTableOf(who, gen2)
    return stats and stats[key] or nil
  end

  -- Gen 2's native special-stat key aliases (gen2_modern_stats.lua keeps
  -- mon.stats.spa AND mon.stats.specialAttack in sync; this mod's own damage
  -- formula reads .spa, Gen 2's native code reads .specialAttack).
  local GEN2_SPECIAL_ALIAS = { spa = "specialAttack", spd = "specialDefense" }
  local function setStoredStat(who, key, value, gen2)
    local stats = statTableOf(who, gen2)
    if not stats then return false end
    stats[key] = value
    if gen2 then
      local alias = GEN2_SPECIAL_ALIAS[key]
      if alias then stats[alias] = value end
    end
    return true
  end

  -- Round 184: battle-scoped raw-stat baseline. Power Split / Guard Split /
  -- Power Shift rewrite stored stats for the rest of the fight, so the mon's
  -- own pre-modification value of each touched key is recorded here (once
  -- per key) and restored when the mon leaves the field or the battle ends.
  -- Keyed on the mon itself rather than mon.volatile for the same reason
  -- Power Shift's fields are: Gen 2's own switch path clears volatiles BEFORE
  -- emitting battle.battler_switched, so a volatile-held baseline would
  -- already be gone by the time the restore listener ran.
  local function captureStatBaseline(m, who, keys, gen2)
    if not (m and who) then return end
    local base = m.__g9StatBaseline
    if not base then base = {}; m.__g9StatBaseline = base end
    for i = 1, #keys do
      local k = keys[i]
      if base[k] == nil then
        base[k] = storedStat(who, k, gen2)
      end
    end
  end

  -- Put every touched key back and drop the battle-scoped state. Safe to call
  -- on anything (battler or raw mon); a no-op for a mon that carries no
  -- baseline. Also clears Power Shift's toggle state, so a mon that leaves
  -- with a shift still active cannot come back and mistake a later Power
  -- Shift for a toggle-off.
  local function revertStatBaseline(who, gen2)
    local m = monOf(who, gen2)
    if not m then return false end
    local base = m.__g9StatBaseline
    if base then
      for k, v in pairs(base) do
        if v ~= nil then setStoredStat(m, k, v, gen2) end
      end
      m.__g9StatBaseline = nil
    end
    m.powerShiftActive = nil
    m.powerShiftPre = nil
    return base ~= nil
  end
  mod.exports.revertStatBaseline = revertStatBaseline
  local function revertScopedStats(battle, who)
    if not (battle and who) then return end
    revertStatBaseline(who, isGen2Battle(battle))
  end

  -- Native speed/accuracy/evasion stage table (Gen 2 per-side
  -- battle.stages[side], Gen 1 per-wrapper who.stages).
  local function nativeStageTable(battle, who, gen2)
    if gen2 then
      local stages = battle and battle.stages
      if not stages then return nil end
      return stages[battle:sideOf(who)]
    end
    return who and who.stages
  end

  -- Raw stage read/write for any of the seven keys -- mod store for
  -- atk/def/spa/spd, native table for speed/accuracy/evasion. Deliberately
  -- raw (setBoost-shaped): the swap family must not clamp, emit, or trigger
  -- any ability reaction.
  local function readStageValue(n, who, stat)
    if NATIVE_STAGE[stat] then
      local tbl = nativeStageTable(n.battle, who, n.gen2)
      return (tbl and tbl[stat]) or 0
    end
    return stagesFor(n.battle, who)[stat] or 0
  end
  local function writeStageValue(n, who, stat, value)
    if NATIVE_STAGE[stat] then
      local tbl = nativeStageTable(n.battle, who, n.gen2)
      if tbl then tbl[stat] = value end
    else
      stagesFor(n.battle, who)[stat] = value
    end
  end

  -- Cross-generation single-message emit for code that runs OUTSIDE a run()
  -- handler (the Syrup Bomb residual / Power Shift revert listeners): Gen 2's
  -- Battle has emit, Gen 1's BattleState has no emit at all but does have
  -- sayNext -- the same dual path modern_hazards.lua:335-337 and
  -- modern_move_flags.lua:158-160 already use.
  local function say(battle, text)
    if not (battle and text) then return end
    if battle.emit then
      battle:emit({ kind = "message", text = text })
    elseif battle.sayNext then
      battle:sayNext(text)
    end
  end

  -- Collect a run() handler's messages and hand them back once: Gen 2 emits
  -- each line itself (its dispatch ignores the return value), Gen 1 returns
  -- the list for performMove's sayNext loop.
  local function finish(n, lines)
    if n.gen2 then
      for i = 1, #lines do
        n.battle:emit({ kind = "message", text = lines[i] })
      end
      return {}
    end
    return lines
  end

  -- Append one message list onto another (changeStage/changeNativeStage both
  -- return a list of strings, never emit themselves).
  local function collect(out, msgs)
    for i = 1, #(msgs or {}) do out[#out + 1] = msgs[i] end
  end

  -- A real signed delta on any stat: mod store for atk/def/spa/spd, native
  -- for speed/accuracy/evasion. Native routes through Gen 2's own
  -- Battle:changeStageAgainstMist (which emits its real message itself and
  -- respects Mist) and Gen 1's MoveEffects.changeStage, with the boss-fight
  -- statsDrop guard checked first on both -- the exact split
  -- modern_movepool_stages.lua's changeNativeStage already establishes.
  local function applyDelta(n, who, stat, delta, fromEnemy, out)
    if NATIVE_STAGE[stat] then
      if mod.exports.bossStatsDropBlocked and mod.exports.bossStatsDropBlocked(n.battle, who, delta) then
        out[#out + 1] = romText(n.battle.data, "_NothingHappenedText", "Nothing happened!")
        return
      end
      if n.gen2 then
        n.battle:changeStageAgainstMist(n.user, who, stat, delta)
      else
        collect(out, NativeMoveEffects.changeStage(n.battle, who, stat, delta, fromEnemy))
      end
      return
    end
    collect(out, changeStage(n.battle, who, stat, delta, fromEnemy, n.gen2))
  end

  -- A Substitute blocks every target-directed move here that lacks
  -- Showdown's bypasssub flag (the substitute condition's own
  -- onTryPrimaryHit, moves.ts:18340-18354: `if (target === source ||
  -- move.flags['bypasssub'] || move.infiltrates) return;`). Gen 2's
  -- substitute is a remaining-HP number in Battle:volatile; Gen 1 stores it
  -- as who.substituteHP (the same split modern_combat.lua's isProtectedFrom
  -- reads).
  local function hasSubstitute(battle, who, gen2)
    if not who then return false end
    if gen2 then
      if type(battle.volatile) ~= "function" then return false end
      local vol = battle:volatile(who)
      return (vol and vol.substitute or 0) > 0
    end
    return (who.substituteHP or 0) > 0
  end
  local function substituteBlocks(n, out)
    if hasSubstitute(n.battle, n.target, n.gen2) then
      out[#out + 1] = romText(n.battle.data, "_ButItFailedText", "But, it failed!")
      return true
    end
    return false
  end

  ------------------------------------------------------------------
  -- Boss-fight "statsDrop" protection for the DIRECT writes
  -- ------------------------------------------------------------------
  -- changeStage's own per-delta guard (bossStatsDropBlocked) never sees a
  -- swap/split/Topsy, which write raw values rather than signed deltas. The
  -- Clear Smog handler in modern_movepool_stages.lua already established the
  -- rule for exactly this shape: a protected boss may not have any stat
  -- WORSENED by a direct write, and the WHOLE effect is refused rather than
  -- partially applied (so the two sides can never desync). A direct write
  -- that only raises every affected stat is allowed through untouched.
  -- bossFightHas is Gen-2-only by construction (battle:sideOf returns a side
  -- object on Gen 1, so `== "enemy"` is never true there) -- correct, since
  -- boss fights are a Gen 2 feature.
  local function bossDropProtected(battle)
    return mod.exports.bossFightHas ~= nil and mod.exports.bossFightHas(battle, "statsDrop")
  end
  local function bossBlocksWrites(n, mutations, out, reader)
    if not bossDropProtected(n.battle) then return false end
    for i = 1, #mutations do
      local m = mutations[i]
      if n.battle:sideOf(m.who) == "enemy" and m.value < (reader(n, m.who, m.stat) or 0) then
        out[#out + 1] = romText(n.battle.data, "_NothingHappenedText", "Nothing happened!")
        return true
      end
    end
    return false
  end
  local function bossBlocksStageWrites(n, mutations, out)
    return bossBlocksWrites(n, mutations, out, readStageValue)
  end
  local function bossBlocksStatWrites(n, mutations, out)
    return bossBlocksWrites(n, mutations, out,
      function(nn, who, stat) return storedStat(who, stat, nn.gen2) end)
  end

  ------------------------------------------------------------------
  -- Registration helpers
  ------------------------------------------------------------------
  -- accuracyChecked is passed explicitly (see this file's own header note on
  -- the accuracy-0 trap): only Strength Sap has a real accuracy check.
  local function registerPrimary(effectId, accuracyChecked, runFn)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      accuracyChecked = accuracyChecked or nil,
      run = runFn,
    })
  end

  ------------------------------------------------------------------
  -- Stage swaps (Power Swap / Guard Swap / Heart Swap)
  ------------------------------------------------------------------
  -- Showdown swaps the BOOSTS (setBoost), not the raw stats. The message's
  -- stat list is Showdown's own `-swapboost` argument (moves.ts:
  -- 'atk, spa' / 'def, spd' / none for Heart Swap).
  local function swapStages(n, out, keys, listText)
    local user, target = n.user, n.target
    local mutations = {}
    for _, k in ipairs(keys) do
      local u = readStageValue(n, user, k)
      local t = readStageValue(n, target, k)
      mutations[#mutations + 1] = { who = user, stat = k, value = t }
      mutations[#mutations + 1] = { who = target, stat = k, value = u }
    end
    if bossBlocksStageWrites(n, mutations, out) then return end
    for i = 1, #mutations do
      local m = mutations[i]
      writeStageValue(n, m.who, m.stat, m.value)
    end
    local un = displayNameFor(n.battle, user, n.gen2)
    local tn = displayNameFor(n.battle, target, n.gen2)
    if listText then
      out[#out + 1] = Strings("%s swapped its\n%s\nwith %s!", un, listText, tn)
    else
      out[#out + 1] = Strings("%s swapped\nstat changes with\n%s!", un, tn)
    end
  end

  registerPrimary("GALAR_POWERSWAP_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    swapStages(n, out, { "attack", "spa" }, "Attack and Sp. Atk")
    return finish(n, out)
  end)
  registerPrimary("GALAR_GUARDSWAP_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    swapStages(n, out, { "defense", "spd" }, "Defense and Sp. Def")
    return finish(n, out)
  end)
  registerPrimary("GALAR_HEARTSWAP_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    swapStages(n, out, ALL_BOOST_KEYS, nil)
    return finish(n, out)
  end)

  ------------------------------------------------------------------
  -- Raw-stat swaps and splits (Speed Swap / Power Split / Guard Split)
  ------------------------------------------------------------------
  registerPrimary("GALAR_SPEEDSWAP_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    local u = storedStat(n.user, "speed", n.gen2) or 0
    local t = storedStat(n.target, "speed", n.gen2) or 0
    local mutations = {
      { who = n.user, stat = "speed", value = t },
      { who = n.target, stat = "speed", value = u },
    }
    if bossBlocksStatWrites(n, mutations, out) then return finish(n, out) end
    -- Round 185: Speed Swap is battle-scoped too. Record each mon's own
    -- pre-swap Speed (once per key) so switch-out / faint / battle end hand it
    -- back -- the same baseline Power Split / Guard Split / Power Shift use.
    for i = 1, #mutations do
      local mu = mutations[i]
      captureStatBaseline(monOf(mu.who, n.gen2), mu.who, { mu.stat }, n.gen2)
    end
    setStoredStat(n.user, "speed", t, n.gen2)
    setStoredStat(n.target, "speed", u, n.gen2)
    out[#out + 1] = Strings("%s swapped its\nSpeed with %s!",
      displayNameFor(n.battle, n.user, n.gen2),
      displayNameFor(n.battle, n.target, n.gen2))
    return finish(n, out)
  end)

  -- Power Split averages storedStats.atk + .spa (Showdown's own floor);
  -- Guard Split averages .def + .spd. Deliberately no bypasssub, so a
  -- Substitute refuses the whole move (substituteBlocks).
  local function splitStats(n, out, keys, phrase)
    if substituteBlocks(n, out) then return end
    local mutations = {}
    for _, k in ipairs(keys) do
      local u = storedStat(n.user, k, n.gen2) or 0
      local t = storedStat(n.target, k, n.gen2) or 0
      local avg = math.floor((u + t) / 2)
      mutations[#mutations + 1] = { who = n.user, stat = k, value = avg }
      mutations[#mutations + 1] = { who = n.target, stat = k, value = avg }
    end
    if bossBlocksStatWrites(n, mutations, out) then return end
    -- Round 184: the average is battle-scoped. Record each mon's own
    -- pre-split value of every key about to be touched (once per key) so
    -- switch-out / faint / battle end can hand the mon its own stats back.
    for i = 1, #mutations do
      local mu = mutations[i]
      captureStatBaseline(monOf(mu.who, n.gen2), mu.who, { mu.stat }, n.gen2)
    end
    for i = 1, #mutations do
      local m = mutations[i]
      setStoredStat(m.who, m.stat, m.value, n.gen2)
    end
    out[#out + 1] = Strings("%s shared its\n%s with %s!",
      displayNameFor(n.battle, n.user, n.gen2), phrase,
      displayNameFor(n.battle, n.target, n.gen2))
  end
  registerPrimary("GALAR_POWERSPLIT_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    splitStats(n, out, { "attack", "spa" }, "power")
    return finish(n, out)
  end)
  registerPrimary("GALAR_GUARDSPLIT_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    splitStats(n, out, { "defense", "spd" }, "guard")
    return finish(n, out)
  end)

  ------------------------------------------------------------------
  -- Power Shift: a toggling self atk <-> def raw-stat swap
  ------------------------------------------------------------------
  -- Showdown models it as a volatile whose onStart/onEnd swap and whose
  -- onRestart removes it (so re-use toggles OFF); clearing on switch-out runs
  -- the same swap-back as onEnd. The state lives on the mon itself (NOT in
  -- mon.volatile) because Gen 2's own switch path calls clearVolatile BEFORE
  -- emitting battle.battler_switched, so a volatile-held flag would already be
  -- gone by the time the restore listener runs -- the same direct-field
  -- reasoning status_condition_cleanup.lua's header documents. Restore +
  -- clear is handled by this file's own listeners (below), so Power Shift's
  -- fields are deliberately NOT in status_condition_cleanup's SWITCH_SCOPED
  -- list (a plain nil-out there could not swap the stats back).
  local function revertPowerShift(battle, who, gen2)
    local m = monOf(who, gen2)
    if not (m and m.powerShiftActive) then return end
    local pre = m.powerShiftPre
    if pre then
      setStoredStat(m, "attack", pre.attack, gen2)
      setStoredStat(m, "defense", pre.defense, gen2)
    end
    m.powerShiftActive = nil
    m.powerShiftPre = nil
  end
  mod.exports.revertPowerShift = revertPowerShift

  registerPrimary("GALAR_POWERSHIFT_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    local m = monOf(n.user, n.gen2)
    if not m then
      return finish(n, out)
    end
    if m.powerShiftActive then
      -- onRestart: removeVolatile -> the onEnd swap-back. Second use toggles
      -- the shift off rather than shifting again.
      revertPowerShift(n.battle, n.user, n.gen2)
      out[#out + 1] = Strings("%s's Power\nShift wore off!",
        displayNameFor(n.battle, n.user, n.gen2))
      return finish(n, out)
    end
    local atk = storedStat(m, "attack", n.gen2) or 0
    local def = storedStat(m, "defense", n.gen2) or 0
    local mutations = {
      { who = m, stat = "attack", value = def },
      { who = m, stat = "defense", value = atk },
    }
    if bossBlocksStatWrites(n, mutations, out) then return finish(n, out) end
    -- Round 184: also record the mon's own atk/def so the battle-scoped
    -- revert (switch / faint / battle end) can undo the shift even when a
    -- Power/Guard Split landed after it.
    captureStatBaseline(m, m, { "attack", "defense" }, n.gen2)
    m.powerShiftPre = { attack = atk, defense = def }
    setStoredStat(m, "attack", def, n.gen2)
    setStoredStat(m, "defense", atk, n.gen2)
    m.powerShiftActive = true
    out[#out + 1] = Strings("%s shifted\nits power!",
      displayNameFor(n.battle, n.user, n.gen2))
    return finish(n, out)
  end)

  ------------------------------------------------------------------
  -- Topsy-Turvy: negate every nonzero stage on the target
  ------------------------------------------------------------------
  registerPrimary("GALAR_TOPSYTURVY_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    if substituteBlocks(n, out) then return finish(n, out) end
    local mutations = {}
    for _, k in ipairs(ALL_BOOST_KEYS) do
      local v = readStageValue(n, n.target, k)
      if v ~= 0 then
        mutations[#mutations + 1] = { who = n.target, stat = k, value = -v }
      end
    end
    if #mutations == 0 then
      out[#out + 1] = romText(n.battle.data, "_ButItFailedText", "But, it failed!")
      return finish(n, out)
    end
    if bossBlocksStageWrites(n, mutations, out) then return finish(n, out) end
    for i = 1, #mutations do
      local m = mutations[i]
      writeStageValue(n, m.who, m.stat, m.value)
    end
    out[#out + 1] = Strings("%s's stat\nchanges were\ninverted!",
      displayNameFor(n.battle, n.target, n.gen2))
    return finish(n, out)
  end)

  ------------------------------------------------------------------
  -- Acupressure: +2 to one uniformly-random eligible stat of the user
  ------------------------------------------------------------------
  -- RNG: Gen 2's battle.random(n) is 0..n-1; Gen 1's battle.rng(lo, hi) is
  -- inclusive on both ends (the same split main.lua's own generic listener
  -- documents), so rng(0, n-1) gives the identical 0..n-1 index.
  local function rollIndex(battle, gen2, n)
    if n <= 0 then return nil end
    if gen2 then return battle.random(n) end
    return math.floor(battle.rng(0, n - 1))
  end

  registerPrimary("GALAR_ACUPRESSURE_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    local eligible = {}
    for _, k in ipairs(ALL_BOOST_KEYS) do
      if readStageValue(n, n.user, k) < 6 then eligible[#eligible + 1] = k end
    end
    if #eligible == 0 then
      out[#out + 1] = romText(n.battle.data, "_ButItFailedText", "But, it failed!")
      return finish(n, out)
    end
    local idx = rollIndex(n.battle, n.gen2, #eligible)
    applyDelta(n, n.user, eligible[(idx or 0) + 1], 2, false, out)
    return finish(n, out)
  end)

  ------------------------------------------------------------------
  -- Shell Smash / Spicy Extract: plain (but ordered, message-complete)
  -- multi-stat changes
  ------------------------------------------------------------------
  -- Showdown's `boosts` object is applied in insertion order: Shell Smash
  -- { def:-1, spd:-1, atk:+2, spa:+2, spe:+2 }; Spicy Extract { atk:+2,
  -- def:-2 }. Going through applyDelta (not the shared primary() helper)
  -- keeps the real per-stat message tier on Gen 2 -- the shared helper's
  -- Gen-2 return value is discarded, so those changes print nothing there.
  registerPrimary("GMAX_SHELLSMASH_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    applyDelta(n, n.user, "defense", -1, false, out)
    applyDelta(n, n.user, "spd", -1, false, out)
    applyDelta(n, n.user, "attack", 2, false, out)
    applyDelta(n, n.user, "spa", 2, false, out)
    applyDelta(n, n.user, "speed", 2, false, out)
    return finish(n, out)
  end)
  registerPrimary("GMAX_SPICYEXTRACT_EFFECT", false, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    if substituteBlocks(n, out) then return finish(n, out) end
    -- The +2 Atk is beneficial to the target (fromEnemy=false, so the
    -- Clear Body-style family and Mist never touch it); the -2 Def is
    -- hostile (fromEnemy=true) -- the same per-change direction rule
    -- modern_movepool_stages.lua's applyChange uses.
    applyDelta(n, n.target, "attack", 2, false, out)
    applyDelta(n, n.target, "defense", -2, true, out)
    return finish(n, out)
  end)

  ------------------------------------------------------------------
  -- Strength Sap: heal by the target's stage-included Attack, then drop it
  ------------------------------------------------------------------
  registerPrimary("GALAR_STRENGTHSAP_EFFECT", true, function(a, b, c)
    local n = normalize(a, b, c)
    local out = {}
    if substituteBlocks(n, out) then return finish(n, out) end
    local atkStage = readStageValue(n, n.target, "attack")
    if atkStage == -6 then
      -- Showdown: `if (target.boosts.atk === -6) return false;` -- the WHOLE
      -- move fails, heal included.
      out[#out + 1] = romText(n.battle.data, "_ButItFailedText", "But, it failed!")
      return finish(n, out)
    end
    -- atk is read BEFORE the drop (Showdown reads it into a local first).
    -- getStat('atk', false, true) = stored stat with stages applied and no
    -- ability modifiers; Stats.applyStage is this mod's own real stat-stage
    -- applier (the one computeModernDamage itself uses), so the heal matches
    -- every other stage-based number in this mod.
    local rawAtk = storedStat(n.target, "attack", n.gen2) or 0
    local healAmount = Stats.applyStage(rawAtk, atkStage)
    local before = atkStage
    applyDelta(n, n.target, "attack", -1, true, out)
    local dropped = readStageValue(n, n.target, "attack") < before
    -- The heal is independent of the drop (Showdown's `|| success`): it
    -- lands even when Clear Body/Mist/Substitute blocked the Atk drop.
    local m = monOf(n.user, n.gen2)
    local maxHp = m and m.stats and m.stats.hp
    local healed = false
    if m and maxHp and (m.hp or 0) < maxHp then
      local amount = math.min(maxHp - (m.hp or 0), math.max(0, healAmount))
      if amount > 0 then
        local tryHeal = mod.exports.g9TryHeal
        if tryHeal then
          healed = tryHeal(n.battle, n.user, amount) > 0
        else
          m.hp = (m.hp or 0) + amount
          healed = true
        end
      end
    end
    if healed then
      out[#out + 1] = Strings("%s's\nHP was restored!",
        displayNameFor(n.battle, n.user, n.gen2))
    end
    if not (healed or dropped) then
      out[#out + 1] = romText(n.battle.data, "_ButItFailedText", "But, it failed!")
    end
    return finish(n, out)
  end)

  ------------------------------------------------------------------
  -- Syrup Bomb: a 3-tick, source-linked Speed drop
  ------------------------------------------------------------------
  -- Damaging move (60 BP), so it is registered kind="full" with NO run field
  -- -- a `.run` on a damaging record pre-empts Gen 2's own damage path
  -- (gen2-Battle.lua:1750-1754), the systemic bug modern_movepool_stages.lua
  -- already documents. The coat is applied from a battle.damage_dealt
  -- listener (landed, non-zero hit) instead.
  --
  -- main.lua's generic secondary-stat listener ALSO reads SYRUPBOMB's
  -- statChanges/statChance off national_dex and would apply a one-time
  -- target Speed -1 on the same hit -- national_dex's own empty shortEffect
  -- makes statSelfDirected read as false (not nil), so that generic branch
  -- fires. SYRUPBOMB is added to a GENERIC_SECONDARY_EXEMPT set in main.lua
  -- so the real 3-tick residual below is the only application.
  mod.content.move_effects:register("GALAR_SYRUPBOMB_EFFECT", { kind = "full" })

  local SYRUP_BOMB_TICKS = 3

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local move = ev and ev.move
    local target = ev and ev.target
    local user = ev and ev.user
    if not (battle and move and move.effect == "GALAR_SYRUPBOMB_EFFECT" and target) then return end
    if (ev.damage or 0) <= 0 then return end
    local gen2 = isGen2Battle(battle)
    -- A Substitute takes the hit, so no coat (there is no bypasssub flag).
    if hasSubstitute(battle, target, gen2) then return end
    if target.syrupBombTurns then return end
    target.syrupBombTurns = SYRUP_BOMB_TICKS
    target.syrupBombSource = user
    say(battle, Strings("%s was covered\nin syrup!",
      displayNameFor(battle, target, gen2)))
  end)

  -- The residual (onResidualOrder 14 -- late, but a plain turn-ended pass is
  -- this engine's equivalent). The source must still be ON THE FIELD
  -- ("onUpdate: if source && !source.isActive -> removeVolatile"): a source
  -- that switched out or fainted ends the coat with no further tick, and the
  -- counter is consumed exactly SYRUP_BOMB_TICKS times (battle.ts:515-517).
  local function sourceOnField(actives, src, gen2)
    if not src then return false end
    local sm = monOf(src, gen2)
    if not (sm and (sm.hp or 0) > 0) then return false end
    for i = 1, #actives do
      local a = actives[i]
      if a == src or monOf(a, gen2) == sm then return true end
    end
    return false
  end

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    local actives = (mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle))
      or { battle.player, battle.enemy }
    for i = 1, #actives do
      local who = actives[i]
      if who and who.syrupBombTurns then
        local m = monOf(who, gen2)
        if not (m and (m.hp or 0) > 0) or not sourceOnField(actives, who.syrupBombSource, gen2) then
          who.syrupBombTurns = nil
          who.syrupBombSource = nil
        else
          local n = { battle = battle, user = who.syrupBombSource, target = who, gen2 = gen2 }
          local out = {}
          applyDelta(n, who, "speed", -1, true, out)
          for j = 1, #out do say(battle, out[j]) end
          who.syrupBombTurns = who.syrupBombTurns - 1
          if who.syrupBombTurns <= 0 then
            who.syrupBombTurns = nil
            who.syrupBombSource = nil
          end
        end
      end
    end
  end)

  -- Battle-scoped raw-stat restore (round 184). Power Shift's state and the
  -- Power/Guard Split baseline both live on the mon itself, so the switch
  -- path's own clearVolatile cannot reach them -- they are put back here when
  -- a mon leaves the field (switch or faint) and when the fight ends. The
  -- scene emits battle.battler_switched with a raw-mon payload and reuses one
  -- engine battler per mon, so these run on whatever identity the event
  -- carries (revertScopedStats/monOf accept a battler or a raw mon). A mon
  -- with no baseline is a no-op.
  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    revertScopedStats(battle, ev.previous)
    revertScopedStats(battle, ev.battler)
  end)
  mod.events:on("battle.fainted", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    revertScopedStats(battle, ev.battler or ev.mon or ev.target or ev.pokemon)
  end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    local seen = {}
    local function revertOne(who)
      if not who then return end
      local m = monOf(who, gen2)
      if not m or seen[m] then return end
      seen[m] = true
      revertStatBaseline(who, gen2)
    end
    revertOne(battle.player)
    revertOne(battle.enemy)
    local actives = (mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle))
      or { battle.player, battle.enemy }
    for i = 1, #actives do revertOne(actives[i]) end
    local byMon = battle.battlersByMon
    if type(byMon) == "table" then
      for _, b in pairs(byMon) do revertOne(b) end
    end
    local parties = { battle.party, battle.enemyParty, battle.playerParty }
    for p = 1, #parties do
      local party = parties[p]
      if type(party) == "table" then
        for i = 1, #party do revertOne(party[i]) end
      end
    end
  end)

  mod.log:info("g9-battle-engine: modern_stat_manipulation installed "
    .. "(POWERSWAP, GUARDSWAP, HEARTSWAP, SPEEDSWAP, POWERSPLIT, GUARDSPLIT, "
    .. "POWERSHIFT, STRENGTHSAP, TOPSYTURVY, ACUPRESSURE, SHELLSMASH, "
    .. "SPICYEXTRACT, SYRUPBOMB)")
end
