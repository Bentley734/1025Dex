-- 1025Dex battle mechanics; adapted from Gen9Dex release 4.8.1 (GPL-3.0-or-later).
-- Only the battle-mechanics component is licensed under GPL; it consumes the
-- bundled 1025Dex read API and owns no species/assets or battle UI.
do
 local api=...
 local original=api.find
 api.find=function(a,b)
  local id=b or a
  if id=='national_dex'then return {id='1025dex',exports=api.exports,version='1.3.0'}end
  if id=='g9-battle-engine'then return {id=api.id,exports=api.exports,version='1.3.0'}end
  return original(a,b)
 end
end
-- =============================================================================
-- g9-battle-engine boot (round 6 rebuild)
--
-- Faithful restoration of the canonical (tectorifter/Gen9Dex) boot sequence:
-- every subsystem is loaded in the same data-then-engine order the real
-- main.lua uses, but each install is pcall-guarded so a broken subsystem
-- logs a warning and the boot ALWAYS continues (standing rule: the mod must
-- never crash the boot). The guard also means the mod keeps loading even if
-- an optional dependency (battle_forms, modern_type_framework, ...) is
-- absent -- an absent subsystem simply logs and the rest of the engine still
-- comes up.
--
-- Deliberate scope notes (see src/README.md, round 6):
--   * The canonical main.lua's INLINE phases are now reproduced too:
--     movepool sub-effect wiring (wireMovepoolSubEffects +
--     installMovepoolEffects), and move-name display -- all pcall-guarded.
--     All 150 sibling files referenced from the entry load (142 canonical
--     repo siblings via loadSibling, byte-identical to tectorifter/
--     Gen9Dex, plus 8 round-4 damage-brain files via require).
--   * trainers/temp_test_registrations.lua (test artifact) is skipped;
--     gigantamax/gimmick_dynamax.lua stays CANONICAL-DISABLED (round 12):
--     battle_forms owns Dynamax/Gigantamax activation and mechanics end to
--     end (its own src/dynamax.lua + hpscale.lua + maxmoves.lua), so the
--     full parallel Dynamax engine gimmick_dynamax would double-count --
--     instead we boot gigantamax/dynamax_battle.lua, the consume-only
--     processor reading battle_forms' dynamax_applied/dynamax_reverted
--     trigger (Dynamax Level drive into battle_forms' own HP stamp; the
--     Showdown-verified Max/G-Max move secondaries live in
--     gigantamax/max_move_subeffects.lua, processed exactly like every
--     other move in this mod).
--     installGigantamaxMoves (canonical-disabled) and derivedHeightWeight
--     (only used by postgame_species.lua, which this fork doesn't ship)
--     are intentionally skipped.
--   * mod.exports.isMoveDataComplete is the canonical completeness gate
--     (ported below) so combat/learnset_ownership.lua works unchanged.
--
-- Exports that end up live after this boot (set by the files themselves,
-- not faked here): resolveTurnActions, computeTurnOrder,
-- registerPriorityModifier, orderSwitchInMons, orderActiveBattlers,
-- registerTrainer, hasRegisteredTrainer, askBattleChoice,
-- battleChoiceActive, cancelBattleChoice, abilityIdOf, abilityBehaviorOf,
-- setAbility, requestAdjacency, requestSwitch, setMonTypes,
-- registerDamageModifier, changeStage, currentWeather, setWeather,
-- setMonDynamaxLevel, setGigantamaxFactor, setTeraType, getTeraType,
-- isTerastallized, ShowdownPrimitives, ModernStats, MoveCategory,
-- damagePipeline, moveUsability/moveUsabilityReason/moveUsabilityFlag/
-- registerMoveUsabilityGate/itemMoveBanned, and every register*Modifier chain.
-- =============================================================================
-- >>> gen1recomp-mod-studio require-bridge (managed block; the studio re-adds/repairs this on every build — keep it intact) <<<
-- gen1recomp runs ONLY this entry file (Loader.lua calls chunk(api)), and
-- require() resolves engine modules only -- never a .lua inside the mod.
-- This bridge routes require("dir/file") through api:read + loadstring so
-- sibling sub-files load under the mod sandbox, cached per RESOLVED FILE
-- (a sibling returning function(mod) is called with the api, and the same
-- file loaded via two spellings is not double-run). Engine requires pass
-- through to the sandboxed require unchanged.
do
  local api = ...
  local engineRequire = require
  local loaded, seen = {}, {}
  local compile = loadstring or load
  local function tryRead(file)
    local ok, body = pcall(api.read, api, file)
    return ok and body or nil
  end
  local function siblingFile(name)
    local file = name:match("%.lua$") and name or name .. ".lua"
    if tryRead(file) ~= nil then return file end
    if not name:match("^src%.") and not name:match("/") and not name:match("%.lua$") and name:match("%.") then
      local dotted = name:gsub("%.", "/") .. ".lua"
      if tryRead(dotted) ~= nil then return dotted end
    end
    return nil
  end
  require = function(name, ...)
    local file = siblingFile(name)
    if file then
      if seen[file] then return loaded[file] end
      local body = tryRead(file)
      local chunk, err = compile(body, "@" .. tostring(api.path) .. "/" .. file)
      if not chunk then error("[require-bridge] " .. file .. " failed to compile: " .. tostring(err), 0) end
      local ok, result = pcall(chunk)
      if not ok then error("[require-bridge] " .. file .. " errored while loading: " .. tostring(result), 0) end
      if type(result) == "function" then
        local ok2, result2 = pcall(result, api)
        if not ok2 then error("[require-bridge] " .. file .. " errored in its entry function: " .. tostring(result2), 0) end
        result = result2
      end
      seen[file], loaded[file] = true, result
      return result
    end
    return engineRequire(name, ...)
  end
end
-- <<< gen1recomp-mod-studio require-bridge >>>

local function isMoveDataComplete(liveRecord)
  if not liveRecord then return false end
  local hasAilment = liveRecord.ailment and liveRecord.ailment ~= "none"
  local isConfusion = liveRecord.ailment == "confusion"
  local hasStatChange = #(liveRecord.statChanges or {}) > 0
  local hasDrain = (liveRecord.drain or 0) ~= 0
  local hasHeal = (liveRecord.healing or 0) ~= 0
  local hasMultiTurn = (liveRecord.minTurns or 0) > 0 or (liveRecord.maxTurns or 0) > 0
  local needsCustomEngineering = (hasAilment and not isConfusion)
    or hasStatChange or hasDrain or hasHeal or hasMultiTurn
  if not needsCustomEngineering then return true end
  return liveRecord.effect ~= nil and liveRecord.effect ~= "NO_ADDITIONAL_EFFECT"
end

-- Moves whose national_dex record carries a statChanges/statChance pair that
-- this generic secondary listener must NOT apply, because their real
-- mechanic is owned by a bespoke handler elsewhere in this mod. Checked at
-- the top of the listener, keyed by move id.
--
-- SYRUPBOMB (combat/modern_stat_manipulation.lua): national_dex's own record
-- has statChance=100 with a Speed -1, but its `shortEffect` is the empty
-- string, so this file's own `saysUsers`/`saysTargets` direction heuristic
-- reads `statSelfDirected` as false (NOT nil) and the generic branch below
-- would apply a one-time target Speed -1 on the hit. The real move coats the
-- target for exactly 3 end-of-turn Speed -1 ticks instead; that file's own
-- listener is the only correct application.
local GENERIC_SECONDARY_EXEMPT = { SYRUPBOMB = true }

local function installMovepoolEffects(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "installMovepoolEffects: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById

  -- Round 15 (2026-09-08, direct user report): recoil/drain must be a
  -- fraction of the TARGET's REAL HP LOST, never the raw (unclamped-on-
  -- overkill) damage the engine computes. Gen 2's dealDamage emits
  -- battle.damage_dealt with the potential damage even on a KO (the
  -- target's hp is clamped to 0 but the `damage` in the event is not) --
  -- e.g. a 60-damage Light of Ruin against a 40-HP target reports 60,
  -- but the target really only lost 40, so a 50% recoil must be 20, not
  -- 30. Showdown's rule: recoil/drain = fraction of min(potential,
  -- pre-hit HP). The battle.damage hook fires BEFORE the hit is applied
  -- on both engines (the same sanctioned extension point damage_brain's
  -- pipeline wraps at 500), so this wrap snapshots the target's pre-hit
  -- HP at 510 -- above the pipeline, harmless either way since HP is
  -- still pre-hit throughout -- and the drain branch below clamps the
  -- event's damage to that snapshot. Weak-keyed so a finished battle's
  -- mon objects can be collected.
  local preHitHp = setmetatable({}, { __mode = "k" })
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local t = ctx and ctx.target
    local m = t and (t.mon or t)
    if m then preHitHp[m] = m.hp or 0 end
    return next(ctx)
  end, 510)

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target
    local user = ev and ev.user
    local damage = ev and ev.damage
    if not (battle and moveId and target) then return end
    -- Moves whose real secondary is owned by a bespoke handler elsewhere
    -- (see GENERIC_SECONDARY_EXEMPT above) must not also get the generic
    -- stat-change applied here.
    if GENERIC_SECONDARY_EXEMPT[moveId] then return end
    local ok, info = pcall(moveById, moveId)
    if not (ok and info) then return end
    local flinchChance = (info.flinchChance or 0) > 0 and info.flinchChance or nil
    local confuseChance = (info.ailment == "confusion" and (info.ailmentChance or 0) > 0)
      and info.ailmentChance or nil
    -- Generic secondary status (poison/burn/paralysis/freeze/sleep) --
    -- confusion is handled separately above (a volatile, not a major
    -- status). Always opponent-directed: no real move self-inflicts a
    -- status via its own secondary chance. STANDARD_AILMENT maps
    -- national_dex's own canonical spelling to each engine's real,
    -- confirmed status-string convention (see this mod's own
    -- NATIONAL_DEX_API_REFERENCE.md -- Gen 1 codes vs Gen 2 words,
    -- neither matching national_dex's own spelling directly).
    -- toxic (badly poisoned) is its own real status, not "poison" --
    -- Gen 1's StatusRegistry.inflict takes it via opts.toxic=true on the
    -- SAME "PSN" code (confirmed real, src/battle/Status.lua's own PSN
    -- record: `if opts.toxic then target.toxicCounter = 1 ... end`);
    -- Gen 2 has a genuinely separate status word for it ("toxic", not
    -- "poison" -- confirmed real, gen2/Battle.lua's own Battle.STATUSES
    -- .toxic). isToxic below threads that through.
    local STANDARD_AILMENT = {
      poison = { gen1 = "PSN", gen2 = "poison" }, burn = { gen1 = "BRN", gen2 = "burn" },
      paralysis = { gen1 = "PAR", gen2 = "paralyze" }, freeze = { gen1 = "FRZ", gen2 = "freeze" },
      sleep = { gen1 = "SLP", gen2 = "sleep" },
      toxic = { gen1 = "PSN", gen2 = "toxic", isToxic = true },
    }
    -- TOXIC's own real move record carries ailment="poison" (confirmed
    -- via direct national_dex dump), not "toxic" -- a real, confirmed
    -- data inconsistency against Malignant Chain's own correctly-tagged
    -- "toxic" ailment for the identical real mechanic -- so this one
    -- move id needs an explicit override rather than trusting the
    -- ailment field alone. Every other move's own real ailment value is
    -- still read live, unconditionally.
    local ailmentKey = (moveId == "TOXIC") and "toxic" or info.ailment
    local ailmentCodes = STANDARD_AILMENT[ailmentKey]
    local ailmentChance = (ailmentCodes and (info.ailmentChance or 0) > 0) and info.ailmentChance
      or (ailmentCodes and moveId == "TOXIC" and 100) or nil
    -- Generic secondary stat change. Direction (self vs opponent) has no
    -- structured field at all in national_dex's own data -- a real,
    -- confirmed PokeAPI limitation, not something this mod failed to
    -- read -- but the prose `shortEffect` text reliably says "the
    -- user's"/"the target's" (verified against Overheat/Superpower/
    -- Close Combat/Fleur Cannon/V-create -- self -- vs Acid/Mud Shot --
    -- opponent -- before writing this), so direction is still read live,
    -- not hardcoded per move.
    local STAT_KEY = { attack = "attack", defense = "defense",
      ["special-attack"] = "spa", ["special-defense"] = "spd",
      speed = "speed", accuracy = "accuracy", evasion = "evasion" }
    local statChance = ((info.statChance or 0) > 0 and #(info.statChanges or {}) > 0)
      and info.statChance or nil
    -- national_dex's own prose text uses a curly apostrophe (U+2019),
    -- not a straight one -- confirmed by direct dump, not assumed --
    -- checked for both defensively in case a future shard mixes them.
    local function saysUsers(text)
      return text:find("user's") ~= nil or text:find("user\226\128\153s") ~= nil
    end
    local function saysTargets(text)
      return text:find("target's") ~= nil or text:find("target\226\128\153s") ~= nil
    end
    local shortEffect = info.shortEffect or ""
    local statSelfDirected = statChance and saysUsers(shortEffect) and not saysTargets(shortEffect)
    -- Generic drain/recoil -- positive `drain` heals the user a fraction
    -- of the damage just dealt, negative is recoil (self-damage). Gated
    -- on this gen's own real modeled flag (gen1EffectModeled/
    -- gen2EffectModeled): when true, this move's real behavior already
    -- runs natively for THIS gen (Absorb/Mega Drain/Giga Drain/Leech
    -- Life/Dream Eater's own drain included) -- applying again here
    -- would double it. When false, nothing else handles it for this gen
    -- (confirmed: no remaining mod-patched drain/recoil effect exists
    -- anywhere in this codebase as of this migration -- the two that
    -- used to, GALAR_RECOIL_EFFECT_3/2 and GALAR_DRAIN_EFFECT_75, are
    -- retired, see combat/modern_movepool_damage.lua's own header).
    local drainPercent = (info.drain or 0) ~= 0 and info.drain or nil
    if not (flinchChance or confuseChance or ailmentChance or statChance or drainPercent) then return end
    local applyOk, err = pcall(function()
      -- isGen2Battle is looked up lazily (not hoisted to a local at the
      -- top of this file) because installMovepoolEffects runs during
      -- Phase 2, before combat/modern_combat.lua (Phase 6+) has loaded
      -- and populated mod.exports -- this closure only runs later,
      -- during a real battle, by which point every mod has finished
      -- loading.
      local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle)
      -- RNG convention genuinely differs by engine, confirmed directly:
      -- Gen 1's battle.rng(a, b) (BattleState.lua:596, `love.math.random
      -- (a, b)`) is inclusive-both-ends. Gen 2 has NO .rng field at all
      -- (confirmed, zero matches in gen2/Battle.lua) -- its real
      -- primitive is battle.random(n), a single-arg roll returning
      -- 0..n-1 (gen2/Battle.lua:220 `self.random = opts.random or
      -- function(n) return rand(nil, n) end`), and every native Gen 2
      -- percent-chance check uses exactly `rand(self.random, 100) <
      -- chance` (e.g. gen2/Battle.lua:1815/1821/1850) -- battle.random
      -- (100) < chance here mirrors that same, real, established idiom.
      local function percentRoll(chance)
        if gen2 then return battle.random(100) < chance end
        return battle.rng(1, 100) <= chance
      end
      local function rangeRoll(lo, hi)
        if gen2 then return lo + battle.random(hi - lo + 1) end
        return battle.rng(lo, hi)
      end
      -- Phase 3a (abilities/engine/status_immunity.lua): INNERFOCUS/
      -- OWNTEMPO gates, looked up lazily for the same reason isGen2Battle
      -- above is -- this closure only runs during a real battle, by which
      -- point status_immunity.lua has finished loading regardless of
      -- install order.
      local hasStatusImmunity = mod.exports.hasStatusImmunity
      -- Real, confirmed double-application guard, added after an initial
      -- pass missed it (caught by direct review, not assumed correct):
      -- this gen's own real modeled flag. When true, THIS move's real
      -- effect already runs natively for THIS gen (a real EFFECT_X_HIT-
      -- style handler, confirmed by the earlier move-completeness audit
      -- excluding exactly these moves from needing new work at all) --
      -- ailment/statChange must NOT also roll independently on top of
      -- that, the same reasoning already applied to drain below. Flinch/
      -- confusion are exempt from this gate on purpose: national_dex's
      -- own gen1Effect/gen2Effect ids never model flinch/confusion chance
      -- at all (confirmed earlier this session, the original reason this
      -- listener was built generic in the first place), so there is
      -- nothing native for those two to collide with.
      local modeled = gen2 and info.gen2EffectModeled or ((not gen2) and info.gen1EffectModeled)
      -- Phase 7 (prevent bucket): Sheer Force/Shield Dust -- both real
      -- "the secondary/extra effects of [these] moves never happen"
      -- abilities, and this generic listener (flinch/ailment/confuse/
      -- stat-change) is the exact real definition of "secondary effect"
      -- for every move that reaches it -- not drain/recoil, which is the
      -- move's own primary mechanic, not a chance-based extra (real Sheer
      -- Force, confirmed via Showdown source, leaves draining moves'
      -- drain untouched). Sheer Force is the attacking side (its own
      -- separate +30% power boost is a damage_dealt_multiplier-kind
      -- effect, a different phase's own bucket, not built here); Shield
      -- Dust is the defending side.
      local abilityIdOf = mod.exports.abilityIdOf
      local secondarySuppressed = abilityIdOf
        and ((user and abilityIdOf(user) == "SHEERFORCE") or (target and abilityIdOf(target) == "SHIELDDUST"))
      if secondarySuppressed then
        flinchChance, confuseChance, ailmentChance, statChance = nil, nil, nil, nil
      end
      -- Phase 8: Serene Grace -- doubles the SAME real secondary-effect
      -- pool this listener already owns (flinch/ailment/confuse/stat-
      -- change), the attacking side, capped at 100 so a doubled 60%+
      -- chance never rolls against an out-of-range denominator. Real,
      -- confirmed exclusion (Showdown source + national_dex's own notes):
      -- Secret Power's own terrain-dependent secondary is explicitly
      -- unaffected -- excluded by move id rather than guessed silently
      -- correct.
      if abilityIdOf and user and moveId ~= "SECRETPOWER" and abilityIdOf(user) == "SERENEGRACE" then
        if flinchChance then flinchChance = math.min(100, flinchChance * 2) end
        if confuseChance then confuseChance = math.min(100, confuseChance * 2) end
        if ailmentChance then ailmentChance = math.min(100, ailmentChance * 2) end
        if statChance then statChance = math.min(100, statChance * 2) end
      end
      if flinchChance and percentRoll(flinchChance)
          and not (hasStatusImmunity and hasStatusImmunity(target, "flinch", battle)) then
        -- Route through abilities/engine/hit_taken.lua's exported setFlinched
        -- when that file is loaded: STEADFAST must raise the target's Speed
        -- on the same flinch that lands here. Falls back to the plain native
        -- write if hit_taken.lua hasn't booted (it loads after this file).
        local setFlinched = mod.exports.setFlinched
        if setFlinched then
          setFlinched(battle, target, gen2)
        elseif gen2 then
          battle:volatile(target).flinched = true
        else
          target.flinched = true
        end
      end
      if confuseChance and percentRoll(confuseChance)
          and not (hasStatusImmunity and hasStatusImmunity(target, "confusion", battle)) then
        if gen2 then
          -- Route through the real Battle:applyConfusion (gen2/Battle.lua:
          -- 3452) rather than writing volatile.confuseCount directly.
          -- combat/modern_terrain.lua wraps that exact dotted entry point
          -- precisely because every native confusion source funnels
          -- through it -- writing the field here bypassed that wrap, so
          -- Misty Terrain failed to block a move secondary's confusion (a
          -- real, flagged gap this closes). `user` is passed as the source
          -- so the native Safeguard cross-side check fires exactly as it
          -- does for any other infliction, and the native already-confused
          -- guard replaces the old manual one. Fallback kept for the odd
          -- minimal battle stub with no applyConfusion method.
          if battle.applyConfusion then
            battle:applyConfusion(target, nil, user)
          else
            local vol = battle:volatile(target)
            if not vol.confuseCount then vol.confuseCount = rangeRoll(2, 5) end
          end
        elseif not target.confusedTurns then
          target.confusedTurns = rangeRoll(2, 5)
        end
      end
      -- Generic secondary status (poison/burn/paralysis/freeze/sleep) --
      -- always opponent-directed, reuses the exact primitives Phase 0/3
      -- already made generic and dual-gen-aware: StatusRegistry.inflict
      -- (Gen 1, with opts.secondary+opts.moveType so its own real
      -- same-type-can't-be-secondary-inflicted rule applies for free)
      -- and Battle:applyStatus (Gen 2). Both already respect ability
      -- immunity (status_immunity.lua wraps these same functions) and
      -- the one-status-at-a-time rule natively -- nothing to re-check
      -- here.
      --
      -- Phase 11 (Corrosion): but NEITHER primitive enforces the real
      -- TYPE-based status immunity -- confirmed by direct read of
      -- gen2/Battle.lua:3396-3438, whose applyStatus never consults the
      -- target's types -- so this site checks it itself via
      -- modern_combat.lua's own statusTypeImmune (a Fire-type can't be
      -- burned, a Poison-/Steel-type can't be poisoned). The one real
      -- pierce is Corrosion: Showdown's Pokemon#setStatus skips the
      -- immunity entirely when the inflicting source holds it and the
      -- status is psn/tox (sim/pokemon.ts:1710) -- corrosionPiercesPoison
      -- below.
      local typeImmune = mod.exports.statusTypeImmune
        and mod.exports.statusTypeImmune(battle, target, ailmentKey)
      local corrosionPierce = mod.exports.corrosionPiercesPoison
        and mod.exports.corrosionPiercesPoison(user)
      if ailmentChance and not modeled and not (typeImmune and not corrosionPierce)
          and percentRoll(ailmentChance) then
        local landed
        if gen2 then
          landed = battle:applyStatus(target, ailmentCodes.gen2, moveId)
        else
          local StatusRegistry = require("src.battle.StatusRegistry")
          StatusRegistry.inflict(battle, target, ailmentCodes.gen1,
            { secondary = true, moveType = info.type, source = moveId, toxic = ailmentCodes.isToxic })
          local raw = target and (target.mon or target)
          landed = raw and raw.status ~= nil
        end
        -- Phase 11 (Poison Puppeteer): a target poisoned by Pecharunt's
        -- OWN MOVE also becomes confused. Showdown's ability hook
        -- (abilities.ts:3357-3365) fires only when the inflicting source
        -- IS the ability holder, the target isn't the source, the status
        -- is psn/tox, and the effect is a Move -- which is exactly this
        -- generic secondary path (an ABILITY-inflicted poison, e.g.
        -- Poison Touch, is an Ability effect and deliberately does NOT
        -- trigger it). The real `source.baseSpecies.name !== "Pecharunt"`
        -- guard is honored (national_dex assigns Poison Puppeteer only
        -- to Pecharunt, so it is belt-and-braces, but it keeps the ability
        -- faithful if it is ever copied). Confusion respects Own Tempo via
        -- the same hasStatusImmunity gate the generic confusion branch
        -- above uses.
        if landed and (ailmentKey == "poison" or ailmentKey == "toxic") and user
            and mod.exports.abilityIdOf and mod.exports.abilityIdOf(user) == "POISONPUPPETEER"
            and target ~= user
            and not (hasStatusImmunity and hasStatusImmunity(target, "confusion", battle)) then
          local rawUser = user.mon or user
          local species = rawUser and rawUser.species
          if species == nil or tostring(species):upper():gsub("[^%w]", "") == "PECHARUNT" then
            if gen2 then
              -- Same real entry point as the generic confusion branch
              -- above: routing this through Battle:applyConfusion lets
              -- Misty Terrain block a Poison Puppeteer confusion too
              -- (Showdown's mistyterrain condition nullifies 'confusion'
              -- via onTryAddVolatile), with `user` -- the ability holder --
              -- as the inflicting source.
              if battle.applyConfusion then
                battle:applyConfusion(target, nil, user)
              else
                local vol = battle:volatile(target)
                if not vol.confuseCount then vol.confuseCount = rangeRoll(2, 5) end
              end
            elseif not target.confusedTurns then
              target.confusedTurns = rangeRoll(2, 5)
            end
          end
        end
      end
      -- Generic secondary stat change -- reuses changeStage (Phase 0's
      -- own shared primitive, Contrary/Simple-aware since Phase 8) for
      -- attack/defense/spa/spd, and Gen 2's native
      -- changeStageAgainstMist for speed/accuracy/evasion -- the exact
      -- same NATIVE_STATS split abilities/engine/switchin_stat_change
      -- .lua's own header already documents and this file's own
      -- STAT_KEY mirrors. Silently skipped (not guessed) when the prose
      -- text names neither "user's" nor "target's", or names both --
      -- a wrong direction is a real gameplay bug, an unbuilt effect is
      -- just an honest gap.
      if statChance and not modeled and percentRoll(statChance) and statSelfDirected ~= nil then
        local changeStage = mod.exports.changeStage
        -- NATIVE_STATS (speed/accuracy/evasion): combat/modern_combat
        -- .lua's own changeStage store (confirmed by direct read of its
        -- ensureStageState) only ever tracks attack/defense/spa/spd --
        -- writing "speed" through it would be recorded nowhere anything
        -- reads back, a silent no-op. Gen 2 has a real, proven route for
        -- these three (Battle:changeStageAgainstMist, the same one
        -- abilities/engine/switchin_stat_change.lua's own NATIVE_STATS
        -- branch already uses).
        --
        -- Gen 1 CLOSED (2026-08-27) -- an earlier pass here claimed no
        -- confirmed store existed; that was wrong, found by checking the
        -- wrong file (BattleState.lua) and stopping instead of also
        -- checking Damage.lua, the actual accuracy-formula consumer.
        -- Real, confirmed, direct field: `mon.stages.speed`/`.accuracy`/
        -- `.evasion` (src/battle/Damage.lua:88-94 reads
        -- `attacker.stages.speed`, :121-122 reads `attacker.stages
        -- .accuracy`/`defender.stages.evasion` directly) -- a plain,
        -- clamped -6..6 number per mon, exactly the same shape Gen 2's
        -- own native stage table already is. Written directly here,
        -- gated by the same boss-fight statsDrop protection changeStage
        -- itself already checks (bossStatsDropBlocked) -- Mist's own
        -- check is NOT replicated here (that logic is private to
        -- modern_combat.lua's own closure, not exported, and Mist
        -- blocking a hostile speed/accuracy/evasion drop specifically is
        -- a narrower edge case than the boss-protection rule) -- a
        -- smaller, named simplification, not a silent gap.
        local NATIVE_STATS = { speed = true, accuracy = true, evasion = true }
        for _, sc in ipairs(info.statChanges or {}) do
          local statKey = STAT_KEY[sc.stat]
          if statKey and sc.change and changeStage then
            local who = statSelfDirected and user or target
            local fromEnemy = not statSelfDirected
            if who then
              if NATIVE_STATS[statKey] then
                -- Real Foresight/Miracle Eye rule: blocks the TARGET's
                -- own future evasion raises while active (the "current
                -- boost reset to 0" half lives in combat/modern_status_
                -- volatiles.lua's own Foresight/Miracle Eye handlers).
                local evasionBlocked = statKey == "evasion" and sc.change > 0
                  and (who.foresighted or who.miracleEyed)
                -- Phase 7 (prevent bucket): Clear Body/Full Metal Body/
                -- White Smoke/Hyper Cutter/Big Pecks/Keen Eye/Mind's Eye/
                -- Flower Veil's real "can't have this stat lowered by an
                -- opponent" family, same shared definition Gen 2's own
                -- changeStageAgainstMist wrap (stage_change_transform.lua)
                -- already uses -- Gen 1 has no Mist-equivalent check to
                -- piggyback on here (see this block's own pre-existing
                -- note above), so this is checked directly.
                local statDropBlockedByAbility = mod.exports.statDropBlockedByAbility
                local abilityBlocked = fromEnemy and sc.change < 0 and statDropBlockedByAbility
                  and statDropBlockedByAbility(who, gen2, statKey)
                if evasionBlocked or abilityBlocked then
                  -- no-op
                elseif gen2 then
                  battle:changeStageAgainstMist(user, who, statKey, sc.change)
                elseif not (mod.exports.bossStatsDropBlocked and mod.exports.bossStatsDropBlocked(battle, who, sc.change)) then
                  who.stages = who.stages or {}
                  who.stages[statKey] = math.max(-6, math.min(6, (who.stages[statKey] or 0) + sc.change))
                end
              else
                changeStage(battle, who, statKey, sc.change, fromEnemy, gen2)
              end
            end
          end
        end
      end
      if drainPercent and (damage or 0) > 0 and user then
        -- Reuses the SAME `modeled` flag computed once above (flinch's
        -- own comment) rather than a second, redundant computation.
        if not modeled then
          local m = user.mon or user
          local maxHp = m.stats and m.stats.hp
          -- Round 15: clamp the raw event damage to the target's REAL HP
          -- lost (pre-hit HP captured by the battle.damage wrap above) --
          -- overkill on a KO otherwise overstates recoil AND drain-heal
          -- (Light of Ruin at 60 vs a 40-HP target must recoil 20, not
          -- 30). Falls back to the raw damage when no snapshot exists
          -- (damage no move owns -- Counter/Future Sight/Spikes -- which
          -- never pairs with a drain move anyway).
          local tMon = target and (target.mon or target)
          local realDamage = damage
          local pre = tMon and preHitHp[tMon]
          if pre then realDamage = math.min(damage, pre) end
          local amount = math.max(1, math.floor(realDamage * math.abs(drainPercent) / 100))
          if drainPercent > 0 then
            -- Heal Block / boss "healblock": drain-healing is gated like every
            -- other recovery.
            local tryHeal = mod.exports.g9TryHeal
            if tryHeal then
              tryHeal(battle, user, amount)
            elseif maxHp then
              m.hp = math.min(maxHp, (m.hp or 0) + amount)
            end
          else
            -- Real recoil immunities: Rock Head (blocks recoil
            -- unconditionally, no other effect to this ability) and
            -- Magic Guard (abilities/engine/damage_immunity.lua's own
            -- indirect-damage scope, extended here -- recoil isn't
            -- direct move damage to an opponent, the same real rule
            -- that already covers status residual/sand chip).
            local abilityIdOf = mod.exports.abilityIdOf
            local userAbility = abilityIdOf and abilityIdOf(user)
            if userAbility ~= "ROCKHEAD" and userAbility ~= "MAGICGUARD" then
              m.hp = math.max(0, (m.hp or 0) - amount)
            end
          end
        end
      end
    end)
    if not applyOk then
      mod.log:warn("galar_gmax_dex: installMovepoolEffects: flinch/confuse failed: %s",
        tostring(err))
    end
  end)

  -- Unconditional registration, genuinely independent of any per-move
  -- data -- every real trap move (ailment="trap" on national_dex: Sand
  -- Tomb, Bind, Wrap, Clamp, Fire Spin, Whirlpool, Thunder Cage, Snap
  -- Trap, Magma Storm, Infestation) gets its live record patched to
  -- point at it (see wireMovepoolSubEffects below).
  --
  -- Gen 2 half REBUILT ENTIRELY (2026-08-27 for the dispatch shape, then
  -- 2026-09-08 for the damage bug -- direct user report, "magma storm is
  -- dealing no damage"): confirmed by direct source read that Gen 2
  -- already has a complete, real, working trap mechanic of its own
  -- (Battle:tickWrap -- real 1/16 max HP chip per turn,
  -- switchLocked/runRefused pins, breakTrapsOnSend cleanup -- ALL
  -- already implemented and consumed correctly, gen2/Battle.lua). Its
  -- own trigger (`def.effect == "EFFECT_TRAP_TARGET"`) never fires for
  -- these moves because national_dex's own base registry assigns them
  -- plain EFFECT_NORMAL_HIT instead (confirmed directly, registry_gen2
  -- .lua) -- rather than fight that string match, this writes the exact
  -- same real fields Battle:tickWrap and friends already consume
  -- (`wrapCount`/`wrapMove`/`wrapMoveId`, via battle:volatile) directly.
  -- We decide a target is now trapped; the engine's own pre-existing
  -- machinery does everything downstream of that decision, exactly the
  -- "native only executes what it's told" split this session's own
  -- combat/modern_status_turn_loss.lua already established.
  --
  -- THIS record must NOT carry a `.run` field: Gen 2's dispatch calls
  -- ANY move_effects record with a `.run` field BEFORE its own damage
  -- path and returns immediately once it does (gen2/Battle.lua:1533-1538,
  -- `if handler then handler(...); return end`) -- true regardless of
  -- what the handler body does. The old kind="secondary"+run shape here
  -- meant every one of these damaging trap moves dealt ZERO damage on
  -- Gen 2 (the trap was applied, then the move returned before ever
  -- reaching its own damage code). Same fix this mod already applied to
  -- Rapid Spin (modern_hazards.lua) and every damaging-move stat change
  -- (modern_movepool_stages.lua): kind="full" (no run) is invisible to
  -- that check on both engines, so the move deals ordinary damage, and
  -- the trap is applied by a battle.damage_dealt listener below -- fires
  -- AFTER a landed, non-zero hit on both engines, exactly the "the hit
  -- actually landed" condition a trap needs.
  mod.content.move_effects:register("GALAR_TRAP_EFFECT", { kind = "full" })

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target
    local eff = ev and ev.move and ev.move.effect
    if not (battle and moveId and target and eff == "GALAR_TRAP_EFFECT") then return end
    if (ev.damage or 0) <= 0 then return end
    local applyOk, applyErr = pcall(function()
      -- isGen2Battle is looked up lazily (not hoisted to a local at the
      -- top of this file) because installMovepoolEffects runs during
      -- Phase 2, before combat/modern_combat.lua (Phase 6+) has loaded
      -- and populated mod.exports -- this closure only runs later,
      -- during a real battle, by which point every mod has finished
      -- loading.
      local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle)
      local m = target.mon or target
      if gen2 then
        local state = battle:volatile(m)
        if not state.wrapCount and (state.substitute or 0) <= 0 then
          state.wrapCount = battle.random(2) + 4 -- 4-5 turns, real modern duration
          state.wrapMove = moveId
          state.wrapMoveId = moveId
        end
      else
        -- Approximated duration (4-5 turns); real Gen 1 Bind/Wrap use a
        -- per-turn release roll this engine's equivalent wasn't confirmed.
        -- Already-trapped guard mirrors Gen 2's `not state.wrapCount` -- a
        -- second landed trap move must not reset the clock.
        if not m.trappingTurns then
          m.trappingTurns = battle.rng(4, 5)
          m.boundTurns = m.trappingTurns
          m.trapMove = moveId
        end
      end
    end)
    if not applyOk then
      mod.log:warn("g9-battle-engine: GALAR_TRAP_EFFECT listener failed: %s",
        tostring(applyErr))
    end
  end)
end

-- bypassesProtect (Feint's own flag, Phase 3 of the move-effect
-- completion pipeline) -- a plain data flag, not schema-declared on
-- R.moves (Schemas.lua:824-846) but preserved anyway by that schema's
-- own record-mode leniency (same "unknown top-level fields ride through"
-- behavior modern_movepool_damage.lua's header already confirmed for
-- R.move_effects); modern_combat_protect.lua's battle.damage hook reads
-- it off the live move record, patched on by wireMovepoolSubEffects
-- below rather than registered as part of a full move entry. national_
-- dex has no equivalent field -- this mod invented it, it belongs here
-- as a small hardcoded map, not a file.
local BYPASSES_PROTECT = {
  FEINT = true,
  -- Phase 18 (missing-effects plan): the protect-breaking family. Phantom
  -- Force / Shadow Force (moves.ts:13308 / :16074, both `breaksProtect:
  -- true` -- the two-turn vanish moves punch through a shield on release)
  -- and Hyperspace Hole (moves.ts:9194, `breaksProtect: true`, also
  -- `bypasssub` -- a real Substitute pierce this file does not model, see
  -- combat/modern_guard_contact.lua's own honest-partial note).
  PHANTOMFORCE = true,
  SHADOWFORCE = true,
  HYPERSPACEHOLE = true,
}

-- Phase 18 (missing-effects plan): the two move-record flags Showdown's
-- own `ignoreDefensive` / `ignoreEvasion` / `ignoreAbility` families carry.
-- Read live by combat/modern_combat.lua's damage formula (ignoreDefensive),
-- combat/modern_guard_contact.lua's battle.accuracy / battle.damage wraps
-- (ignoreEvasion / ignoreAbility). Kept as small hardcoded maps here for the
-- same reason BYPASSES_PROTECT is one: national_dex has no equivalent
-- fields, so this mod owns the vocabulary and wireMovepoolSubEffects stamps
-- it onto the live record.
local IGNORE_DEFENSIVE = { CHIPAWAY = true, SACREDSWORD = true, DARKESTLARIAT = true }
local IGNORE_EVASION = { CHIPAWAY = true, SACREDSWORD = true, DARKESTLARIAT = true }
local IGNORE_ABILITY = { MOONGEISTBEAM = true, SUNSTEELSTRIKE = true }

-- Every move whose real custom effect handler (registered elsewhere in
-- this mod, with REAL run/afterDamage/charge logic -- verified one by
-- one, not assumed) depends on ITS OWN move record's `effect` field
-- actually pointing at that handler. This table is EXACTLY what used to
-- be carried silently by moves_new.lua's own per-move `effect` field,
-- copied onto the live record by the old generic wireMovepoolSubEffects
-- loop -- removing that loop without this table would have silently
-- broken every one of these (confirmed real regression caught and fixed
-- in the same session it was introduced: re-audited every mod.content.
-- move_effects:register call in this codebase after the fact, checked
-- each one's actual body for real logic vs. an empty {kind="full"}
-- stub-audit marker -- the empty ones (Acrobatics/Venoshock/Assurance/
-- Heat Crash/Heavy Slam/Power Trip/Flail/Endeavor/Twister/Blizzard/
-- Rapid Spin) need NO patch at all: their real mechanic runs
-- unconditionally off ctx.move.id inside a registerDamageModifier entry
-- or a battle.damage_dealt listener, never through this field -- and two
-- more (GGD_MAXGUARD_EFFECT, GMAX_CUDDLE_EFFECT) belong to moves this mod
-- or gmax_moves.lua already registers/patches directly, with no
-- national_dex record at all, so they were never in scope here).
local CUSTOM_EFFECT_PATCH = {
  -- main.lua's own GALAR_TRAP_EFFECT (installMovepoolEffects above) --
  -- every real trap move (ailment="trap" on national_dex), not just
  -- Sand Tomb, now that the Gen 2 dispatch bug is fixed
  -- Metal Burst / Mirror Coat / Counter (the counter family). combat/
  -- modern_movepool_counter.lua registers GALAR_METALBURST_EFFECT and
  -- GALAR_MIRRORCOAT_EFFECT in full and nothing pointed at them, so those
  -- moves kept national_dex's EFFECT_NORMAL_HIT and the handlers were
  -- unreachable. COUNTER is the Gen 2 half: its own live record effect is
  -- the native "EFFECT_COUNTER", which Gen 2's own dispatch (base-gen2-
  -- Battle.lua's hardcoded COUNTER/MIRROR_COAT table) consumes DIRECTLY,
  -- bypassing mod.content.move_effects entirely -- repointing it at the
  -- registered GALAR_COUNTER_EFFECT reroutes Gen 2's Counter through this
  -- mod's own record (run -> battle.damage -> dealDamage). On Gen 1 the
  -- patch is inert-but-harmless: EffectRegistry's hardcoded `if move.id
  -- == "COUNTER"` branch (confirmed, this file's own header) runs FIRST
  -- and ignores the effect field entirely, so Gen 1 Counter stays the
  -- native, documented exception -- see modern_movepool_counter.lua.
  METALBURST = "GALAR_METALBURST_EFFECT",
  MIRRORCOAT = "GALAR_MIRRORCOAT_EFFECT",
  COUNTER = "GALAR_COUNTER_EFFECT",
  SANDTOMB = "GALAR_TRAP_EFFECT",
  BIND = "GALAR_TRAP_EFFECT",
  WRAP = "GALAR_TRAP_EFFECT",
  CLAMP = "GALAR_TRAP_EFFECT",
  FIRE_SPIN = "GALAR_TRAP_EFFECT",
  WHIRLPOOL = "GALAR_TRAP_EFFECT",
  THUNDERCAGE = "GALAR_TRAP_EFFECT",
  SNAPTRAP = "GALAR_TRAP_EFFECT",
  MAGMASTORM = "GALAR_TRAP_EFFECT",
  INFESTATION = "GALAR_TRAP_EFFECT",
  -- combat/modern_status_volatiles.lua -- real Showdown-verified bespoke
  -- volatiles (Leech Seed, Nightmare, Ingrain, Yawn, Disable, Embargo,
  -- Heal Block/Psychic Noise, Throat Chop, Perish Song, Foresight/
  -- Miracle Eye/Odor Sleuth, Smack Down/Thousand Arrows, Telekinesis,
  -- Uproar). Odor Sleuth reuses Foresight's own real mechanic (Ghost-
  -- immunity negation); Thousand Arrows reuses Smack Down's (Flying-
  -- immunity-to-Ground negation) -- both genuinely share the identical
  -- real effect, confirmed against national_dex's own prose text, not
  -- duplicated code.
  LEECH_SEED = "GALAR_LEECHSEED_EFFECT",
  SAPPYSEED = "GALAR_LEECHSEED_EFFECT",
  NIGHTMARE = "GALAR_NIGHTMARE_EFFECT",
  INGRAIN = "GALAR_INGRAIN_EFFECT",
  YAWN = "GALAR_YAWN_EFFECT",
  DISABLE = "GALAR_DISABLE_EFFECT",
  EMBARGO = "GALAR_EMBARGO_EFFECT",
  HEALBLOCK = "GALAR_HEALBLOCK_EFFECT",
  PSYCHICNOISE = "GALAR_PSYCHICNOISE_EFFECT",
  THROATCHOP = "GALAR_THROATCHOP_EFFECT",
  PERISHSONG = "GALAR_PERISHSONG_EFFECT",
  FORESIGHT = "GALAR_FORESIGHT_EFFECT",
  ODORSLEUTH = "GALAR_FORESIGHT_EFFECT",
  MIRACLEEYE = "GALAR_MIRACLEEYE_EFFECT",
  SMACKDOWN = "GALAR_SMACKDOWN_EFFECT",
  THOUSANDARROWS = "GALAR_SMACKDOWN_EFFECT",
  TELEKINESIS = "GALAR_TELEKINESIS_EFFECT",
  UPROAR = "GALAR_UPROAR_EFFECT",
  ELECTROSHOT = "GALAR_ELECTROSHOT_EFFECT",
  STOCKPILE = "GALAR_STOCKPILE_EFFECT",
  SWALLOW = "GALAR_SWALLOW_EFFECT",
  -- SPITUP is NOT here -- it needs no custom .effect at all, wired
  -- entirely through registerPowerOverride + a battle.damage_dealt
  -- listener instead (see combat/modern_status_volatiles.lua's own
  -- Stockpile/Swallow/Spit Up section for why).
  -- Raging Fury shares Outrage's own exact real mechanic (2-3 turn
  -- rampage lock, then self-confuse) -- reused directly, not
  -- duplicated. Same Gen 2 honest gap as Outrage itself (see combat/
  -- modern_movepool_damage.lua's own header for why).
  RAGINGFURY = "GALAR_OUTRAGE_EFFECT",
  -- combat/modern_weather.lua
  RAINDANCE = "GALAR_RAINDANCE_EFFECT",
  SUNNYDAY = "GALAR_SUNNYDAY_EFFECT",
  SANDSTORM = "GALAR_SANDSTORM_EFFECT",
  SNOWSCAPE = "GALAR_SNOWSCAPE_EFFECT",
  SOLARBEAM = "GALAR_SOLARBEAM_EFFECT",
  -- combat/modern_movepool_damage.lua
  -- DRAININGKISS's own GALAR_DRAIN_EFFECT_75 patch retired 2026-08-27 --
  -- superseded by installGenericDrainRecoil's live `drain` field read
  -- (see this file's own header), which is also dual-gen-correct where
  -- that one wasn't.
  HEALPULSE = "GALAR_HEALPULSE_EFFECT",
  LIFEDEW = "GALAR_LIFEDEW_EFFECT",
  SYNTHESIS = "GALAR_SYNTHESIS_EFFECT",
  MOONLIGHT = "GALAR_MOONLIGHT_EFFECT",
  MORNINGSUN = "GALAR_MORNINGSUN_EFFECT",
  SHOREUP = "GALAR_SHOREUP_EFFECT",
  FLORALHEALING = "GALAR_FLORALHEALING_EFFECT",
  PURIFY = "GALAR_PURIFY_EFFECT",
  LUNARBLESSING = "GALAR_LUNARBLESSING_EFFECT",
  PAINSPLIT = "GALAR_PAINSPLIT_EFFECT",
  BOUNCE = "GALAR_BOUNCE_EFFECT",
  OUTRAGE = "GALAR_OUTRAGE_EFFECT",
  -- combat/modern_bide.lua (round 341): the store-and-release counter.
  -- national_dex replaces the cart's own BIDE effect id with a power-0
  -- NO_ADDITIONAL_EFFECT / EFFECT_NORMAL_HIT record, so the native machine
  -- never started and the move did nothing; this re-homes it under a
  -- cross-generation id (Showdown gen7 semantics -- see that file's header).
  BIDE = "GALAR_BIDE_EFFECT",
  ETERNABEAM = "GALAR_ETERNABEAM_EFFECT",
  -- combat/modern_movepool_status.lua
  FLATTER = "GMAX_FLATTER_EFFECT",
  SWAGGER = "GMAX_SWAGGER_EFFECT",
  -- combat/modern_status_effects.lua
  ATTRACT = "GMAX_ATTRACT_EFFECT",
  TAUNT = "GMAX_TAUNT_EFFECT",
  TORMENT = "GMAX_TORMENT_EFFECT",
  -- combat/modern_hazards.lua
  STEALTHROCK = "GALAR_STEALTHROCK_EFFECT",
  TOXICSPIKES = "GALAR_TOXICSPIKES_EFFECT",
  STICKYWEB = "GALAR_STICKYWEB_EFFECT",
  -- combat/modern_ability_change_moves.lua
  SKILLSWAP = "GALAR_SKILLSWAP_EFFECT",
  WORRYSEED = "GALAR_WORRYSEED_EFFECT",
  ENTRAINMENT = "GALAR_ENTRAINMENT_EFFECT",
  GASTROACID = "GALAR_GASTROACID_EFFECT",
  ROLEPLAY = "GALAR_ROLEPLAY_EFFECT",
  SIMPLEBEAM = "GALAR_SIMPLEBEAM_EFFECT",
  DOODLE = "GALAR_DOODLE_EFFECT",
  -- combat/modern_movepool_stages.lua -- primary() (pure status moves)
  AROMATICMIST = "GMAX_AROMATICMIST_EFFECT",
  BULKUP = "GMAX_BULKUP_EFFECT",
  CALMMIND = "GMAX_CALMMIND_EFFECT",
  CHARGE = "GMAX_CHARGE_EFFECT",
  CHARM = "GMAX_CHARM_EFFECT",
  COIL = "GMAX_COIL_EFFECT",
  CONFIDE = "GMAX_CONFIDE_EFFECT",
  COSMICPOWER = "GMAX_COSMICPOWER_EFFECT",
  COTTONGUARD = "GMAX_COTTONGUARD_EFFECT",
  COTTONSPORE = "GMAX_COTTONSPORE_EFFECT",
  DECORATE = "GMAX_DECORATE_EFFECT",
  DRAGONDANCE = "GMAX_DRAGONDANCE_EFFECT",
  EERIEIMPULSE = "GMAX_EERIEIMPULSE_EFFECT",
  FAKETEARS = "GMAX_FAKETEARS_EFFECT",
  HONECLAWS = "GMAX_HONECLAWS_EFFECT",
  IRONDEFENSE = "GMAX_IRONDEFENSE_EFFECT",
  METALSOUND = "GMAX_METALSOUND_EFFECT",
  NASTYPLOT = "GMAX_NASTYPLOT_EFFECT",
  NOBLEROAR = "GMAX_NOBLEROAR_EFFECT",
  PLAYNICE = "GMAX_PLAYNICE_EFFECT",
  ROCKPOLISH = "GMAX_ROCKPOLISH_EFFECT",
  SCARYFACE = "GMAX_SCARYFACE_EFFECT",
  SHIFTGEAR = "GMAX_SHIFTGEAR_EFFECT",
  SWEETSCENT = "GMAX_SWEETSCENT_EFFECT",
  TARSHOT = "GMAX_TARSHOT_EFFECT",
  TEARFULLOOK = "GMAX_TEARFULLOOK_EFFECT",
  -- combat/modern_movepool_stages.lua -- secondary() (damaging moves)
  ACIDSPRAY = "GMAX_ACIDSPRAY_EFFECT",
  ANCIENTPOWER = "GMAX_ANCIENTPOWER_EFFECT",
  APPLEACID = "GMAX_APPLEACID_EFFECT",
  BREAKINGSWIPE = "GMAX_BREAKINGSWIPE_EFFECT",
  BUGBUZZ = "GMAX_BUGBUZZ_EFFECT",
  BULLDOZE = "GMAX_BULLDOZE_EFFECT",
  CLOSECOMBAT = "GMAX_CLOSECOMBAT_EFFECT",
  CRUNCH = "GMAX_CRUNCH_EFFECT",
  DRUMBEATING = "GMAX_DRUMBEATING_EFFECT",
  ENERGYBALL = "GMAX_ENERGYBALL_EFFECT",
  FIRELASH = "GMAX_FIRELASH_EFFECT",
  FLAMECHARGE = "GMAX_FLAMECHARGE_EFFECT",
  FLASHCANNON = "GMAX_FLASHCANNON_EFFECT",
  GRAVAPPLE = "GMAX_GRAVAPPLE_EFFECT",
  HAMMERARM = "GMAX_HAMMERARM_EFFECT",
  LEAFSTORM = "GMAX_LEAFSTORM_EFFECT",
  LEAFTORNADO = "GMAX_LEAFTORNADO_EFFECT",
  LIQUIDATION = "GMAX_LIQUIDATION_EFFECT",
  LUNGE = "GMAX_LUNGE_EFFECT",
  METALCLAW = "GMAX_METALCLAW_EFFECT",
  PLAYROUGH = "GMAX_PLAYROUGH_EFFECT",
  POWERUPPUNCH = "GMAX_POWERUPPUNCH_EFFECT",
  RAZORSHELL = "GMAX_RAZORSHELL_EFFECT",
  ROCKSMASH = "GMAX_ROCKSMASH_EFFECT",
  ROCKTOMB = "GMAX_ROCKTOMB_EFFECT",
  SPIRITBREAK = "GMAX_SPIRITBREAK_EFFECT",
  STEELWING = "GMAX_STEELWING_EFFECT",
  STRUGGLEBUG = "GMAX_STRUGGLEBUG_EFFECT",
  SUPERPOWER = "GMAX_SUPERPOWER_EFFECT",
  -- combat/modern_movepool_stages.lua -- Clear Smog (its own registration)
  CLEARSMOG = "GMAX_CLEARSMOG_EFFECT",
  -- combat/modern_move_flags.lua -- the MINIMIZE move itself: evasion +2
  -- through each engine's native stage path, plus the "minimized" volatile
  -- that the eight minimizer-hitting moves read (Body Slam, Stomp, ...).
  -- See that file's own section 5 for the Showdown citation.
  MINIMIZE = "GALAR_MINIMIZE_EFFECT",
  -- combat/modern_stat_manipulation.lua (round 70, missing-effects phase 2)
  -- -- stat-stage and stat-source manipulation. Every one of these is a
  -- move national_dex leaves at EFFECT_NORMAL_HIT / NO_ADDITIONAL_EFFECT
  -- with no generic bucket able to express it (a swap/split needs both
  -- battlers' stages or raw stats at once; Topsy-Turvy needs the whole
  -- stage table; Power Shift needs a toggleable raw-stat state; Strength
  -- Sap and Syrup Bomb are their own bespoke mechanics).
  POWERSWAP = "GALAR_POWERSWAP_EFFECT",
  GUARDSWAP = "GALAR_GUARDSWAP_EFFECT",
  HEARTSWAP = "GALAR_HEARTSWAP_EFFECT",
  SPEEDSWAP = "GALAR_SPEEDSWAP_EFFECT",
  POWERSPLIT = "GALAR_POWERSPLIT_EFFECT",
  GUARDSPLIT = "GALAR_GUARDSPLIT_EFFECT",
  POWERSHIFT = "GALAR_POWERSHIFT_EFFECT",
  STRENGTHSAP = "GALAR_STRENGTHSAP_EFFECT",
  TOPSYTURVY = "GALAR_TOPSYTURVY_EFFECT",
  ACUPRESSURE = "GALAR_ACUPRESSURE_EFFECT",
  SYRUPBOMB = "GALAR_SYRUPBOMB_EFFECT",
  SHELLSMASH = "GMAX_SHELLSMASH_EFFECT",
  SPICYEXTRACT = "GMAX_SPICYEXTRACT_EFFECT",
  -- combat/modern_crit_override.lua (round 71, missing-effects phase 3) --
  -- Laser Focus only; the five always-crit moves need no effect entry (their
  -- override lives in the crit-stage chain, keyed off the `alwaysCrit` field
  -- main.lua itself patches from national_dex's critRate sentinel).
  LASERFOCUS = "GALAR_LASERFOCUS_EFFECT",
  -- Dragon Cheer (4.6.7): the ally-side crit volatile, now that real
  -- ally slots exist. Retired from combat/structural_exemptions.lua.
  DRAGONCHEER = "GALAR_DRAGONCHEER_EFFECT",
  -- combat/modern_movepool_stages.lua -- Phase 15 (missing-effects plan):
  -- self stat-stage boosts plus the target-directed drops sharing the
  -- primitive. national_dex leaves all 19 at statChance = 0, so the
  -- generic secondary listener never applied them; Baby-Doll Eyes /
  -- Feather Dance / Howl / Shelter already carried a native effect id but
  -- that wrote the engine's own stage table, which computeModernDamage
  -- never reads -- repointing them at the modern store is the real fix.
  QUIVERDANCE = "GMAX_QUIVERDANCE_EFFECT",
  VICTORYDANCE = "GMAX_VICTORYDANCE_EFFECT",
  TAILGLOW = "GMAX_TAILGLOW_EFFECT",
  WORKUP = "GMAX_WORKUP_EFFECT",
  AUTOTOMIZE = "GMAX_AUTOTOMIZE_EFFECT",
  DEFENDORDER = "GMAX_DEFENDORDER_EFFECT",
  SHELTER = "GMAX_SHELTER_EFFECT",
  HOWL = "GMAX_HOWL_EFFECT",
  -- Coaching (4.6.7): Atk +1 / Def +1 to every adjacent ALLY (never
  -- the user) -- the real game rule, which national_dex's own
  -- "user-and-allies" label and Showdown's `adjacentAlly` each only half
  -- describe. Wired through modern_movepool_stages.lua's teamBoostMove.
  COACHING = "GMAX_COACHING_EFFECT",
  TICKLE = "GMAX_TICKLE_EFFECT",
  FEATHERDANCE = "GMAX_FEATHERDANCE_EFFECT",
  BABYDOLLEYES = "GMAX_BABYDOLLEYES_EFFECT",
  CAPTIVATE = "GMAX_CAPTIVATE_EFFECT",
  FILLETAWAY = "GMAX_FILLETAWAY_EFFECT",
  BELLYDRUM = "GMAX_BELLYDRUM_EFFECT",
  CURSE = "GMAX_CURSE_EFFECT",
  TIDYUP = "GMAX_TIDYUP_EFFECT",
  GEARUP = "GMAX_GEARUP_EFFECT",
  MAGNETICFLUX = "GMAX_MAGNETICFLUX_EFFECT",
  GEOMANCY = "GMAX_GEOMANCY_EFFECT",
  -- combat/modern_recovery_moves.lua -- Phase 16 (missing-effects plan):
  -- Roost is repointed so its two halves (the native 50% heal plus the
  -- Flying-type drop for the turn) resolve in one handler; Aqua Ring has
  -- no native effect at all, so its volatile lives entirely there.
  -- Heal Order / Milk Drink / Slack Off are deliberately ABSENT: their
  -- plain 50% heal is already handled natively on both generations
  -- (national_dex gen1EffectModeled/gen2EffectModeled = true), so
  -- repointing them would only replace a working handler with a copy.
  ROOST = "GALAR_ROOST_EFFECT",
  AQUARING = "GALAR_AQUARING_EFFECT",
  -- combat/modern_charge_moves.lua -- Phase 17 (missing-effects plan): the
  -- three charge moves repointed at their own charge-record ids (the Solar
  -- Beam / Bounce mechanism). Ice Ball / Rollout / Echoed Voice need no
  -- effect entry -- their power ladders run through registerPowerOverride
  -- alone -- and Shell Trap / Beak Blast need none either (their arming and
  -- reaction live on the turn_started/damage_dealt events).
  SOLARBLADE = "GALAR_SOLARBLADE_EFFECT",
  METEORBEAM = "GALAR_METEORBEAM_EFFECT",
  SKYDROP = "GALAR_SKYDROP_EFFECT",
  -- combat/modern_guard_contact.lua -- Phase 18 (missing-effects plan): the
  -- two vanish-and-strike moves repointed at their own charge-record ids
  -- (the Sky Drop shape). Their `breaksProtect` flag is applied separately
  -- via BYPASSES_PROTECT above; the ignore-ability/evasion flags are read
  -- live off the record by the guard/contact handlers.
  PHANTOMFORCE = "GALAR_PHANTOMFORCE_EFFECT",
  SHADOWFORCE = "GALAR_SHADOWFORCE_EFFECT",
}

-- Completeness, read ENTIRELY from national_dex's own modern fields --
-- no hardcoded per-move exemption list at all (confirmed directly:
-- Feint and Round, the two moves that used to need a special-cased
-- exemption under the old PBS-functionCode model, both come back
-- completely empty on every one of these fields already -- neither
-- "bypasses Protect" nor "doubles-only ally bonus" is a secondary-effect
-- TYPE national_dex's schema tracks at all, so there was never anything
-- here for them to be stubbed on in the first place).
--
-- flinchChance / confusion / multiHit are each handled GENERICALLY for
-- every move in the whole roster now (installMovepoolEffects reads
-- flinch/confusion live; this file's own wireMovepoolSubEffects derives
-- and patches multiHit live) -- a move needing ONLY one of those three
-- is complete with zero registration of its own. Anything else (a real
-- non-confusion ailment, a stat change, drain, healing, or a multi-turn
-- charge) needs a REAL custom effect actually registered and patched
-- onto the live record by some file in this mod -- confirmed this
-- already happens for e.g. Protect/Detect (modern_combat_protect.lua)
-- and Trick Room (combat/trick_room.lua), both picked up here for free
-- since this reads the LIVE record, not a static snapshot.
local function wireMovepoolSubEffects(mod)
  installMovepoolEffects(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById
      and nationalDex.exports.listMoves,
    "wireMovepoolSubEffects: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local patched = 0
  for _, id in ipairs(nationalDex.exports.listMoves()) do
    if mod.content.moves:get(id) then
      local ok, info = pcall(moveById, id)
      if ok and info then
        local patch = {}
        if BYPASSES_PROTECT[id] then patch.bypassesProtect = true end
        if IGNORE_DEFENSIVE[id] then patch.ignoreDefensive = true end
        if IGNORE_EVASION[id] then patch.ignoreEvasion = true end
        if IGNORE_ABILITY[id] then patch.ignoreAbility = true end
        if CUSTOM_EFFECT_PATCH[id] then patch.effect = CUSTOM_EFFECT_PATCH[id] end
        -- critRate is the number of +1 crit-stage bumps the move itself
        -- grants (confirmed: Cross Poison critRate=1, a real high-crit
        -- move; Axe Kick/Baddy Bad critRate=0, ordinary) -- >=1 maps onto
        -- this engine's own boolean highCrit field. A value of exactly 6 is
        -- national_dex's sentinel for Showdown's `willCrit: true` (all 833
        -- records: 0 ordinary, 1 the 25 real high-crit moves, 6 exactly the
        -- five always-crit moves -- Wicked Blow, Surging Strikes, Frost
        -- Breath, Storm Throw, Flower Trick), which combat/
        -- modern_crit_override.lua reads as `alwaysCrit` (a guaranteed crit,
        -- still negated by Battle Armor / Shell Armor like Showdown's own
        -- CriticalHit event). A critRate>=6 move whose dex accuracy is 0 is
        -- also marked sureHit (Flower Trick's Showdown `accuracy: true`).
        local critRate = info.critRate or 0
        if critRate >= 6 then
          patch.alwaysCrit = true
          if (info.accuracy or 1) <= 0 then patch.sureHit = true end
        elseif critRate >= 1 then
          patch.highCrit = true
        end
        -- multiHit: a fixed count (minHits==maxHits, e.g. Double Hit's
        -- 2-2) is just that count twice; the real 2-5 range (Bullet Seed,
        -- Rock Blast, Double Iron Bash) is the well-known, generation-
        -- independent 3/8·3/8·1/8·1/8 weighted distribution -- confirmed
        -- directly against national_dex's OWN effect text for these
        -- moves ("Has a 3/8 chance each to hit 2 or 3 times, and a 1/8
        -- chance each to hit 4 or 5 times"), not guessed. Any other
        -- min/max combination this roster doesn't currently use falls
        -- through to an unweighted flat range rather than silently
        -- guessing a distribution with no confirmed source.
        local minHits, maxHits = info.minHits or 0, info.maxHits or 0
        if minHits > 0 and maxHits > 0 then
          if minHits == maxHits then
            patch.multiHit = { minHits, minHits }
          elseif minHits == 2 and maxHits == 5 then
            patch.multiHit = { 2, 2, 2, 3, 3, 3, 4, 5 }
          else
            local range = {}
            for n = minHits, maxHits do range[#range + 1] = n end
            patch.multiHit = range
          end
        end
        if next(patch) then
          mod.content.moves:patch(id, patch)
          patched = patched + 1
        end
      end
    end
  end
  return patched
end

-- =============================================================================
-- Phase 3: Gigantamax moves -- fed to dynamax, not registered here
-- =============================================================================
-- dynamax now owns both the actual move registration (mod.content.moves)
-- and the species -> move Gigantamax substitution rule (computeMaxMoveId's
-- own type-matching check) -- see dynamax/main.lua's "Gigantamax moves"
-- section. This mod's job is just handing over its own data: the 32 new
-- moves' definitions (gmax_moves.lua) and which species uses which move
-- (gmax_data.lua's own gmaxMove field, already used for dex text/height
-- too). Registration is skipped entirely if dynamax isn't loaded -- the
-- whole Gigantamax mechanic is inert without it either way, same
-- reasoning installGmaxAssetPacks's own reapplyGmaxSprites already
-- applies to sprites below.


return function(mod)
  -- --------------------------------------------------------------------------
  -- Helpers
  -- --------------------------------------------------------------------------
  mod.exports.__bootReport = mod.exports.__bootReport or { loaded = {}, failed = {} }

  local function loadSibling(file)
    local body = mod:read(file)
    assert(body, "missing sibling file: " .. file)
    local compile = loadstring or load
    local chunk, err = compile(body, "@" .. tostring(mod.path) .. "/" .. file)
    assert(chunk, file .. " failed to compile: " .. tostring(err))
    return chunk()
  end

  local function boot(label, fn)
    local ok, res
    if debug and debug.traceback then
      ok, res = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
    else
      ok, res = pcall(fn)
    end
    if not ok then
      mod.log:warn("g9-battle-engine: [" .. label .. "] failed to initialize: " .. tostring(res))
      mod.exports.__bootReport.failed[label] = tostring(res)
      return nil
    end
    mod.exports.__bootReport.loaded[label] = true
    return res
  end

  -- --------------------------------------------------------------------------
  -- Gen 2 TypeChart bootstrap (Leer crash fix, 2026-09-08). Gen 1's
  -- BattleState:new calls TypeChart.load(game.data) itself, but Gen 2 never
  -- does -- its BattleState only reads the chart fields directly off its own
  -- data -- so in a Gen 2 battle every mod call to TypeChart.effectiveness /
  -- TypeChart.rows threw "TypeChart.load not called" (any move that reached
  -- modern_combat's resolvedTypeMult, e.g. Leer's stat-drop path, hard-crashed
  -- the battle). Load the chart from the live battle data on battle.started,
  -- at priority 1000 -- above every mod handler (ANTICIPATION's switch-in scan
  -- registers at 0) and before any move is processed. Gen 2 emits
  -- battle.started from the Battle constructor, Gen 1 from BattleState:enter
  -- (after its own load); both are idempotent here.
  -- --------------------------------------------------------------------------
  local TypeChart = require("src.battle.TypeChart")
  local typeChartLoaded = false
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle or typeChartLoaded then return end
    local data = battle.data
    if not (data and data.type_chart and data.type_chart.matchups) then return end
    local ok, err = pcall(TypeChart.load, data)
    if ok then
      typeChartLoaded = true
    else
      mod.log:warn("g9-battle-engine: TypeChart.load failed on battle.started: " .. tostring(err))
    end
  end, 1000)

  -- --------------------------------------------------------------------------
  -- Phase A: modern stats infra (engine_modern_stats / engine_move_category
  -- are loaded here so every later file can consume the exports, matching
  -- canonical main.lua).
  -- --------------------------------------------------------------------------
  mod.exports.ModernStats = mod.exports.ModernStats or loadSibling("stats/engine_modern_stats.lua")
  mod.exports.MoveCategory = mod.exports.MoveCategory or loadSibling("combat/engine_move_category.lua")
  mod.exports.isMoveDataComplete = isMoveDataComplete

  -- --------------------------------------------------------------------------
  -- Damage Numbers option read (round 105). options.lua row
  -- "damage_numbers" (renamed from show_hp_lost_messages); exposed so
  -- g9-Battle-Scene can gate its floating damage/recovery numbers on the
  -- same option the Mod Manager shows. mod.options:get is read LAZILY
  -- here (the schema is defined later, in debug_options' boot), and the
  -- option is only ever consulted at battle/event time, long after boot.
  -- --------------------------------------------------------------------------
  mod.exports.damageNumbersEnabled = function()
    return mod.options:get("damage_numbers") == "true"
  end

  -- 1512 Total EV scope read. options.lua row "ev_total_1512"; "off" unless
  -- the stored value is one of the three enabled scopes. Read lazily like
  -- damageNumbersEnabled above -- consulted at edit/grant/scrub time, long
  -- after boot. Both this mod and g9-battle-sample read the scope through
  -- here (the sample via mod.find("g9-battle-engine").exports) instead of
  -- touching the option directly, so the value vocabulary lives in one
  -- place. Side caps themselves are ModernStats.evTotalCap (pure).
  mod.exports.evScope = function()
    local ok, v = pcall(function() return mod.options:get("ev_total_1512") end)
    if ok and (v == "enemy" or v == "player" or v == "both") then return v end
    return "off"
  end

  -- Runtime debug log overlay (debug/overlay.lua). Booted FIRST so its
  -- mod.log tee captures every later subsystem's boot lines too. Paints the
  -- latest log lines over the frame (render.hud, both generations) while the
  -- RUNTIME DEBUG LOG option is ON; OFF costs one option read per frame.
  do end

  -- Frame-tick recursion brake (round 262).  Installed FIRST, before any
  -- subsystem wraps a hook, so its core.update link is in the chain from the
  -- very first frame.  Priority 100000 makes it the outermost link, which is
  -- what lets it coalesce a re-entrant frame request before any other wrap
  -- runs -- see core/tick_guard.lua for the whole design.
  boot("tick_guard", function() return loadSibling("core/tick_guard.lua")(mod) end)

  -- Keep native save normalization and stats generation.
  do end
  do end
  do end
  -- Eggs are Pokemon too: every egg found on a save load, on game.ready, in the
  -- live party at battle start, or the moment one of the three egg builders
  -- returns it, gets a generated nature/ability/IVs, zeroed EVs, the name "egg"
  -- and HP 0 -- an egg is a FAINTED Pokemon for every battle purpose. See
  -- stats/egg_normalize.lua.
  do end

  -- Pokecenter nurse takeover (round 296): full heal to the MODERN max on both
  -- generations, the pokeball machine skipped, the player facing south when the
  -- conversation ends, the pokerus report + its flag/phone-call sequencing kept,
  -- and the shortened chat gated on g9-gui's SHORT HEAL CHAT option. See
  -- overworld/pokecenter_heal.lua.
  do end

  do end
  local realBaseExpData = nil
  do end

  -- Gen 2 vocabulary normalisation (species/gen2_vocab.lua): the single place
  -- this mod translates Gen 1 id spellings -- MEDIUM_FAST and METALCLAW --
  -- into the spellings Gold actually registers (GROWTH_MEDIUM_FAST,
  -- METAL_CLAW). Its registry indexes are built lazily on first use, so
  -- loading it here (ahead of both consumers below) is sufficient. On Gen 1
  -- every method is a no-op -- the id already matches the live registry
  -- exactly and is returned unchanged -- so the callers need no generation
  -- branch of their own.
  local vocab = boot("gen2_vocab", function() return loadSibling("species/gen2_vocab.lua")(mod) end)

  -- Movepool sub-effect wiring: reads every move's live national_dex
  -- record and patches custom .effect / .multiHit / .highCrit /
  -- .bypassesProtect onto whatever's registered (canonical
  -- wireMovepoolSubEffects + installMovepoolEffects). If national_dex is
  -- absent it just skips (guarded); the battle.damage_dealt listener only
  -- ever runs during a real battle.
  boot("movepool_sub_effects", function()
    return wireMovepoolSubEffects(mod)
  end)

  -- Multi-hit guarantee (2026-09-10, direct user report: "multi hit moves like
  -- double kick are dealing damage once only"). wireMovepoolSubEffects patches
  -- `multiHit` only onto records the content registry owns, and Gen 2
  -- dispatches the count off the effect STRING -- so a cart-owned Gen-1
  -- multi-hit move and a Gen-2 move whose effect is EFFECT_NORMAL_HIT both
  -- resolve as one hit. This sister file enforces the count from
  -- national_dex's live minHits/maxHits at each generation's own execution
  -- seam. See combat/multi_hit.lua.
  boot("multi_hit", function()
    return loadSibling("combat/multi_hit.lua")(mod)
  end)

  -- Move-effect id-space completion now runs at the very END of the boot (see
  -- the Phase G block below): it must seed a marker only for ids NOTHING else
  -- registered, so it has to see every modern_* module's own move_effects
  -- registration first. Running it here -- before those modules -- made it
  -- seed a bare marker for each effect id a patched move record references,
  -- and the module that then tried to register the REAL record failed with
  -- "move_effects already registered". See combat/move_effect_markers.lua.

  -- Learnset ownership: the real teachability gate. Its install returns a
  -- table with .isUsable / .reapplyLearnsets; reapplyLearnsets() patches
  -- content at load (canonical calls it once here).
  local learnsetOwnership = boot("learnset_ownership", function()
    local install = loadSibling("combat/learnset_ownership.lua")
    local tbl = install(mod, vocab)
    -- Teachability is applied once, after the final effect registrations.
    return tbl
  end)

  -- Gen 2 vocabulary sweep. Runs once national_dex has registered AND this
  -- mod's own patches above have landed, because the ids it resolves are
  -- the registries' own: national_dex ships every one of its ~1238 species
  -- records with growthRate = "MEDIUM_FAST" (Red's spelling; Gold keys
  -- growth_rates as GROWTH_*), and the learnset pass just wrote move ids
  -- through the same live registry. Re-resolving every registered species
  -- record through gen2_vocab collapses those dangling references in one
  -- pass. A record whose references already exist is left untouched (no
  -- patch op, no crossValidate attribution). No-op on Gen 1.
  boot("gen2_vocab_sweep", function()
    if not vocab or not vocab.reapply then return 0 end
    local changedRecords, changedFields = vocab.reapply()
    if changedRecords and changedRecords > 0 then
      mod.log:info(string.format(
        "g9-battle-engine: gen2_vocab: normalised %d dangling reference(s) across %d registered species records",
        changedFields, changedRecords))
    end
    return changedRecords
  end)

  -- Gigantamax / Dynamax / Tera state APIs (storage + public setters;
  -- activation stays battle_forms' scope end to end -- round 12: this mod
  -- no longer provides its own Dynamax activation; the gimmick_ring +
  -- dynamax_trigger self-triggers added in round 11 are deleted and the
  -- canonical Phase 14 unlock condition's comment now applies in full:
  -- "proper hooks into whichever other mod now owns Gigantamax activation
  -- (and GimmickRing's replacement)" -- that mod is battle_forms, and
  -- dynamax_battle.lua below is the consume-only consumer of its trigger).
  local gmaxData = nil
  gmaxData = nil
  do end
  do end

  -- Dynamax combat-property processor (round 13): consumes battle_forms'
  -- dynamax_applied / dynamax_reverted trigger (its src/formapi.lua
  -- exports.events, fired from its own src/dynamax.lua apply/teardown) and
  -- processes the Dynamax combat properties battle_forms deliberately
  -- leaves open -- Dynamax Level drive (mirrored into battle_forms' own
  -- battleFormsDynamaxLevel HP-volume stamp). Reads mod.exports lazily at
  -- battle time, so it has no
  -- install-time dependency on modern_combat/modern_terrain (the old "Must
  -- load AFTER ... to capture their changeStage/setWeather/... at install
  -- time" claim was wrong -- those are looked up inside the handlers, not
  -- captured here).
  do end

  -- Max Move / G-Max Move sub-effects (round 13): the Showdown-verified
  -- secondaries of every battle_forms Max/G-Max move, processed exactly like
  -- every other move in this mod (kind="full" records + a shared
  -- battle.damage_dealt listener keyed on move.effect). Discovery walks
  -- mod.content.moves and patches each BATTLE_FORMS_MAX*/GMAX* id's own
  -- effect field; battle_forms (priority 80) has fully registered its moves
  -- before this mod's entry (priority 95) runs, so the patch loop is
  -- synchronous -- the same ordering modern_combat_protect.lua relies on.
  -- See max_move_subeffects.lua's own header for the full mechanics list.
  do end

  do end

  -- Stats display screen (UI; guarded).  The wide 256x144 two-column party
  -- STATS takeover (stats/modern_stats_screen.lua) was REMOVED in round 189.
  -- It wrapped "ui.party.submenu" and repointed the party menu's STATS action
  -- at itself, which shadowed the game's native party summary screen -- so
  -- nothing that replaces the summary (g9-gui) could ever be reached.  STATS
  -- is left completely alone now and opens the native party summary.
  -- adv_stats (Adv.Stats) is this mod's in-party-menu stats reader and is
  -- unaffected.
  do end
  do end

  -- --------------------------------------------------------------------------
  -- Phase B: the combat core (canonical order).
  -- --------------------------------------------------------------------------
  boot("showdown_primitives", function() return loadSibling("combat/showdown_primitives.lua")(mod) end)
  boot("switch_primitives", function() return loadSibling("combat/switch_primitives.lua")(mod) end)
  boot("switch_vanilla_bridge", function() return loadSibling("combat/switch_vanilla_bridge.lua")(mod) end)
  boot("field_duration", function() return loadSibling("combat/field_duration.lua")(mod) end)

  -- Ability dispatch: needs national_dex (with abilityById, 0.30.0+). Hard
  -- dep in the real game; guarded so the boot still continues if it is ever
  -- absent.
  -- Ability callbacks may carry a party mon; native Gen 1 status writes
  -- require the corresponding live battler wrapper.
  if require('src.core.GameVersion').generation()==1 then
    local SR=require('src.battle.StatusRegistry')
    local inflict=SR.inflict
    SR.inflict=function(battle,target,status,opts)
      if target and not target.mon then
        if battle.player and battle.player.mon==target then target=battle.player
        elseif battle.enemy and battle.enemy.mon==target then target=battle.enemy end
      end
      return inflict(battle,target,status,opts)
    end
  end
  boot("ability_dispatch", function() return loadSibling("abilities/ability_dispatch.lua")(mod) end)
  boot("interaction_memory", function() return loadSibling("combat/interaction_memory.lua")(mod) end)

  -- The terminal damage formula (priority-0 battle.damage wrap, never calls
  -- next). THIS is the Showdown-formula core of the engine.
  boot("modern_combat", function() return loadSibling("combat/modern_combat.lua")(mod) end)

  -- combat/move_usability.lua (round 100): the engine -> scene "can this mon
  -- pick this move, and if not why not" query (moveUsability /
  -- registerMoveUsabilityGate). Booted HERE, right after modern_combat,
  -- because it only needs modern_combat's isGen2Battle/isGen1Battle/
  -- displayNameFor/MoveCategory -- and it MUST exist before every file that
  -- registers a condition gate through it (modern_action_order's Fake Out,
  -- modern_side_protection's First Impression, modern_faint_sacrifice's Last
  -- Resort), the earliest of which is modern_action_order ~150 lines below.
  -- Its item reads are lazy (modern_items boots later) so nothing here is
  -- order-sensitive.
  boot("move_usability", function() return loadSibling("combat/move_usability.lua")(mod) end)

  boot("legacy_move_takeover", function() return loadSibling("combat/legacy_move_takeover.lua")(mod) end)
  boot("move_targeting", function() return loadSibling("combat/move_targeting.lua")(mod) end)
  do end
  do end
  -- Heal Block (the move) + the boss-fight "healblock" flag: the ONE gate
  -- every HP-recovery source routes through, both generations. Boots right
  -- after boss_fight_status because it reads bossFightHas (combat/
  -- boss_fight.lua) and wraps the native heal primitives (Gen 1 MoveEffects
  -- .RECORDS.HEAL_EFFECT, Gen 2 Battle:heal/MOVE_EFFECT_RECORDS.EFFECT_HEAL).
  boot("heal_block", function() return loadSibling("combat/heal_block.lua")(mod) end)

  boot("switchin_stat_change", function()
    local data = loadSibling("abilities/data/stat_change_switchin.lua")
    -- Third arg: the intimidate-guard inclusion table (abilities/data/
    -- intimidate_guard.lua) -- OBLIVIOUS's entry-cure plus Intimidate's
    -- OBLIVIOUS/GUARDDOG/RATTLED target-side guards live there, not in
    -- the stat-change table.
    local ig = loadSibling("abilities/data/intimidate_guard.lua")
    return loadSibling("abilities/engine/switchin_stat_change.lua")(mod, data, ig)
  end)
  boot("modern_combat_protect", function() return loadSibling("combat/modern_combat_protect.lua")(mod) end)

  boot("status_immunity", function()
    local data = loadSibling("abilities/data/status_immunity.lua")
    return loadSibling("abilities/engine/status_immunity.lua")(mod, data)
  end)
  boot("modern_status_turn_loss", function() return loadSibling("combat/modern_status_turn_loss.lua")(mod) end)
  boot("type_immunity", function()
    local data = loadSibling("abilities/data/type_immunity.lua")
    return loadSibling("abilities/engine/type_immunity.lua")(mod, data)
  end)
  boot("gym_badge_buff", function() return loadSibling("combat/gym_badge_buff.lua")(mod) end)
  boot("stat_multiplier", function()
    local data = loadSibling("abilities/data/stat_multiplier.lua")
    return loadSibling("abilities/engine/stat_multiplier.lua")(mod, data)
  end)

  -- Tera combat mechanics; needs tera_state's getTeraType (loaded above).
  -- Read the existing transformation stamp without selecting a type or owning
  -- another mod's options, storage or activation. Generic type changes need
  -- this predicate even when no transformation mod is installed.
  mod.exports.getTeraType=function(mon)
    mon=mon and (mon.mon or mon)
    return mon and (mon.teraType or mon.battleFormsTeraType)
  end
  boot("modern_tera", function() return loadSibling("combat/modern_tera.lua")(mod) end)
  boot("type_override_primitives", function() return loadSibling("combat/type_override_primitives.lua")(mod) end)
  boot("onmove_type_change", function()
    local data = loadSibling("abilities/data/type_change_onmove.lua")
    return loadSibling("abilities/engine/onmove_type_change.lua")(mod, data)
  end)
  boot("ondamage_type_change", function()
    local data = loadSibling("abilities/data/type_change_ondamage.lua")
    return loadSibling("abilities/engine/ondamage_type_change.lua")(mod, data)
  end)
  boot("switchin_multitype", function()
    local data = loadSibling("abilities/data/multitype_switchin.lua")
    return loadSibling("abilities/engine/switchin_multitype.lua")(mod, data)
  end)
  boot("forecast_weather", function()
    local data = loadSibling("abilities/data/forecast_weather.lua")
    return loadSibling("abilities/engine/forecast_weather.lua")(mod, data)
  end)
  boot("mimicry_terrain", function()
    local data = loadSibling("abilities/data/mimicry_terrain.lua")
    return loadSibling("abilities/engine/mimicry_terrain.lua")(mod, data)
  end)
  boot("damage_multiplier_abilities", function()
    local data = loadSibling("abilities/data/damage_multiplier.lua")
    return loadSibling("abilities/engine/damage_multiplier.lua")(mod, data)
  end)

  -- Turn order: the multi-battler seam g9-Battle-Scene hard-asserts on
  -- (mod.exports.resolveTurnActions). Loading this is what fixes the scene
  -- mods' connectivity.
  -- Round 67 (2026-09-12): the end-of-turn residual phase + faint
  -- announcement for scene-driven battles -- the other half of the turn loop
  -- turn_order.lua's resolveTurnActions opens. Booted just before turn_order
  -- so its exports exist by the time resolveTurnActions runs (that lookup is
  -- lazy, but this keeps the intent obvious).
  boot("turn_residuals", function() return loadSibling("combat/turn_residuals.lua")(mod) end)
  -- Gen 1 owns these operations as pure modules, rather than methods.
  local State=require('src.battle.BattleState')
  if State.performMove and not State.effectiveSpeed then
    function State:effectiveSpeed(who)
      if not who.mon then
        if self.player and self.player.mon==who then who=self.player
        elseif self.enemy and self.enemy.mon==who then who=self.enemy
        else return who.stats and who.stats.speed or 0 end
      end
      return require('src.battle.TurnOrder').effectiveSpeed(who)
    end
    function State:roller()return function(n)return self.rng(0,n-1)end end
  end
  boot("turn_order", function() return loadSibling("combat/turn_order.lua")(mod) end)
  boot("priority_change", function()
    local data = loadSibling("abilities/data/priority_change.lua")
    return loadSibling("abilities/engine/priority_change.lua")(mod, data)
  end)
  boot("heal", function()
    local data = loadSibling("abilities/data/heal.lua")
    return loadSibling("abilities/engine/heal.lua")(mod, data)
  end)
  boot("crit_change", function()
    local data = loadSibling("abilities/data/crit_change.lua")
    return loadSibling("abilities/engine/crit_change.lua")(mod, data)
  end)
  boot("accuracy_multiplier", function()
    local data = loadSibling("abilities/data/accuracy_multiplier.lua")
    return loadSibling("abilities/engine/accuracy_multiplier.lua")(mod, data)
  end)
  boot("stage_change_transform", function()
    local data = loadSibling("abilities/data/stage_change_transform.lua")
    return loadSibling("abilities/engine/stage_change_transform.lua")(mod, data)
  end)
  boot("damage_immunity", function()
    local data = loadSibling("abilities/data/damage_immunity.lua")
    return loadSibling("abilities/engine/damage_immunity.lua")(mod, data)
  end)
  boot("status_cure", function()
    local data = loadSibling("abilities/data/status_cure.lua")
    return loadSibling("abilities/engine/status_cure.lua")(mod, data)
  end)
  -- combat/modern_move_flags.lua (round 68, category-3 flag audit): reads
  -- the cantusetwice/defrost/powder/minimize flags live from national_dex
  -- and installs the MoveFlag rules at each engine's real execution gate.
  -- Booted HERE, right after status_cure: its Status.beforeMove / canAct /
  -- useMove wraps then sit BELOW modern_status_effects' own wraps
  -- (installed later) and power.lua's (later still) -- those call through
  -- to it with moveId forwarded (see modern_status_effects' own comment) --
  -- and cureStatusOf (status_cure, boots just above) is already exported
  -- for the defrost branch.
  boot("modern_move_flags", function() return loadSibling("combat/modern_move_flags.lua")(mod) end)
  boot("contact_retaliation", function()
    local data = loadSibling("abilities/data/contact_retaliation.lua")
    return loadSibling("abilities/engine/contact_retaliation.lua")(mod, data)
  end)
  boot("modern_status_volatiles", function() return loadSibling("combat/modern_status_volatiles.lua")(mod) end)
  boot("trick_room", function() return loadSibling("combat/trick_room.lua")(mod) end)
  boot("modern_movepool_stages", function() return loadSibling("combat/modern_movepool_stages.lua")(mod) end)
  -- combat/modern_stat_manipulation.lua (round 70, missing-effects phase 2):
  -- the stat-stage/raw-stat swap-split-Shift-Topsy family plus Strength Sap,
  -- Acupressure, Shell Smash, Spicy Extract and Syrup Bomb. Booted right
  -- after modern_movepool_stages: both need modern_combat's stage store and
  -- changeStage, and this file extends the same "stat manipulation" area
  -- that helper owns.
  boot("modern_stat_manipulation", function() return loadSibling("combat/modern_stat_manipulation.lua")(mod) end)
  -- combat/modern_crit_override.lua (round 71, missing-effects phase 3): the
  -- five always-crit moves (national_dex critRate 6) plus Laser Focus's
  -- guaranteed-crit volatile and Flower Trick's sure-hit. Booted right after
  -- modern_stat_manipulation; it needs modern_combat's registerCritStageModifier
  -- chain and the battle.accuracy hook (both installed far earlier).
  boot("modern_crit_override", function() return loadSibling("combat/modern_crit_override.lua")(mod) end)
  -- combat/modern_damage_source.lua (missing-effects phase 4): the
  -- damage-stat source overrides -- Body Press (user's Defense) and Foul
  -- Play (target's Attack). Needs modern_combat's registerDamageSourceOverride
  -- seam (installed far earlier), so it boots after modern_crit_override.
  boot("modern_damage_source", function() return loadSibling("combat/modern_damage_source.lua")(mod) end)
  -- combat/modern_action_order.lua (missing-effects phase 5): the chosen-
  -- move fail gates (Sucker Punch/Thunderclap/Upper Hand/Fake Out/Focus
  -- Punch) and the live reorder seam (After You/Quash). Needs turn_order's
  -- phase-5 exports (chosenMoveOf/prioritizeActor/deprioritizeActor) and
  -- modern_combat_protect's Battle.useMove wrap, so it boots after both --
  -- modern_damage_source is simply the last phase milestone before it.
  boot("modern_action_order", function() return loadSibling("combat/modern_action_order.lua")(mod) end)
  -- combat/modern_party_support.lua + combat/modern_faint_sacrifice.lua
  -- (missing-effects phase 6): party recovery/sacrifice (Aromatherapy,
  -- Heal Bell, Jungle Healing, Refresh, Take Heart, Wish, Revival
  -- Blessing, Healing Wish, Lunar Dance, Memento, Destiny Bond, Grudge,
  -- Last Resort). They need status_cure's cureStatusOf (loaded above),
  -- modern_combat's changeStage/normalize/displayNameFor, and
  -- modern_action_order's registerFailGate seam, so they boot right after
  -- it.
  boot("modern_party_support", function() return loadSibling("combat/modern_party_support.lua")(mod) end)
  boot("modern_faint_sacrifice", function() return loadSibling("combat/modern_faint_sacrifice.lua")(mod) end)
  boot("modern_movepool_status", function() return loadSibling("combat/modern_movepool_status.lua")(mod) end)
  boot("modern_movepool_damage", function() return loadSibling("combat/modern_movepool_damage.lua")(mod) end)
  -- combat/modern_recovery_moves.lua (missing-effects phase 16): the heal
  -- family -- Roost (repointed so the 50% heal and the Flying-type drop
  -- for the turn resolve together) and Aqua Ring (a 1/16 end-of-turn self
  -- volatile with no native effect at all). It wraps modern_tera's own
  -- defensiveTypesOf export (booted far earlier) and reads modern_combat's
  -- normalize/displayNameFor, so it sits with the other movepool heals.
  boot("modern_recovery_moves", function() return loadSibling("combat/modern_recovery_moves.lua")(mod) end)
  -- combat/modern_charge_moves.lua (missing-effects phase 17): charge moves
  -- (Solar Blade / Meteor Beam / Sky Drop), the consecutive-use power
  -- ladders (Ice Ball / Rollout / Echoed Voice) and the two priority-charge
  -- reactions (Shell Trap / Beak Blast). It needs modern_combat's
  -- registerPowerOverride/changeStage, modern_action_order's registerFailGate
  -- (booted earlier) and the engine's battle.charge_required hook, so it
  -- boots right after modern_recovery_moves.
  boot("modern_charge_moves", function() return loadSibling("combat/modern_charge_moves.lua")(mod) end)
  boot("modern_movepool_counter", function() return loadSibling("combat/modern_movepool_counter.lua")(mod) end)
  -- combat/modern_bide.lua (round 341): Bide's store-and-release. Boots with
  -- the other movepool entries; it reads modern_combat's normalize/
  -- displayNameFor and legacy_move_takeover's routeThroughBattleDamage (both
  -- installed far earlier), and move_usability.lua's bide gate is resolved
  -- lazily at battle time, so load order between the two does not matter.
  boot("modern_bide", function() return loadSibling("combat/modern_bide.lua")(mod) end)
  -- (missing-effects phase 13): conditional / variable power (Avalanche,
  -- Bolt Beak/Fishious Rend, Hex, Facade, Brine, Payback, Fusion Bolt/
  -- Flare, Lashout, Psyblade, Expanding Force, Retaliate, Smellingsalts,
  -- Wake-Up Slap, Rising Voltage, the Eruption family, Return/
  -- Frustration, Rage Fist, Stored Power, Last Respects, Fury Cutter).
  -- Needs only modern_combat's registerDamageModifier/
  -- registerPowerOverride/stagesFor/sideOfWho/resolvedTypeMult exports
  -- (all present by now), so it sits with the other movepool entries.
  -- cureStatusOf (Smellingsalts/Wake-Up Slap) is looked up lazily at
  -- event time, since status_cure.lua may load later in the boot order.
  boot("modern_power_conditions", function() return loadSibling("combat/modern_power_conditions.lua")(mod) end)
  -- combat/modern_fallback_moves.lua: hardcoded move records for moves the
  -- move data (national_dex) does not supply, plus the runtime power a record
  -- cannot express. The one entry is PIKA_PAPOW (the fourth Let's Go
  -- partner-Pikachu move national_dex omits): it registers the Electric/special
  -- record when the registry has none and wires its friendship-based power
  -- (floor(happiness / 2.5), 1..102). Needs only modern_combat's
  -- registerPowerOverride, so it boots here with the other power entries.
  boot("modern_fallback_moves", function() return loadSibling("combat/modern_fallback_moves.lua")(mod) end)
  boot("modern_status_effects", function() return loadSibling("combat/modern_status_effects.lua")(mod) end)
  boot("status_condition_cleanup", function() return loadSibling("combat/status_condition_cleanup.lua")(mod) end)
  boot("inflict_status", function()
    local data = loadSibling("abilities/data/inflict_status.lua")
    return loadSibling("abilities/engine/inflict_status.lua")(mod, data)
  end)
  boot("prevent_priority_fail", function()
    local data = loadSibling("abilities/data/prevent_priority_fail.lua")
    return loadSibling("abilities/engine/prevent_priority_fail.lua")(mod, data)
  end)
  boot("trap_abilities", function()
    local data = loadSibling("abilities/data/trap_abilities.lua")
    return loadSibling("abilities/engine/trap_abilities.lua")(mod, data)
  end)
  boot("prevent_misc", function()
    local data = loadSibling("abilities/data/prevent_misc.lua")
    return loadSibling("abilities/engine/prevent_misc.lua")(mod, data)
  end)
  boot("aroma_veil", function()
    local data = loadSibling("abilities/data/aroma_veil.lua")
    return loadSibling("abilities/engine/aroma_veil.lua")(mod, data)
  end)
  boot("good_as_gold", function()
    local data = loadSibling("abilities/data/good_as_gold.lua")
    return loadSibling("abilities/engine/good_as_gold.lua")(mod, data)
  end)
  boot("long_reach", function()
    local data = loadSibling("abilities/data/long_reach.lua")
    return loadSibling("abilities/engine/long_reach.lua")(mod, data)
  end)
  boot("pressure", function()
    local data = loadSibling("abilities/data/pressure.lua")
    return loadSibling("abilities/engine/pressure.lua")(mod, data)
  end)
  boot("ability_copy", function()
    local data = loadSibling("abilities/data/ability_copy.lua")
    return loadSibling("abilities/engine/ability_copy.lua")(mod, data)
  end)
  boot("modern_ability_change_moves", function() return loadSibling("combat/modern_ability_change_moves.lua")(mod) end)
  boot("modern_switch_moves", function() return loadSibling("combat/modern_switch_moves.lua")(mod) end)
  -- combat/modern_force_switch.lua (round 69, missing-effects phase 1):
  -- Dragon Tail / Circle Throw target-directed drag. Booted right after
  -- modern_switch_moves: both need modern_combat's exports and
  -- switch_primitives' requestSwitch/switchMonAtSide, and both are
  -- "self/target leaves the field after a damaging hit" effects kept
  -- together at the same point in the boot.
  boot("modern_force_switch", function() return loadSibling("combat/modern_force_switch.lua")(mod) end)
  boot("modern_terrain", function() return loadSibling("combat/modern_terrain.lua")(mod) end)
  boot("switchin_terrain", function()
    local data = loadSibling("abilities/data/terrain_switchin.lua")
    return loadSibling("abilities/engine/switchin_terrain.lua")(mod, data)
  end)
  boot("modern_type_change_moves", function() return loadSibling("combat/modern_type_change_moves.lua")(mod) end)
  boot("modern_weather", function() return loadSibling("combat/modern_weather.lua")(mod) end)
  boot("switchin_weather", function()
    local data = loadSibling("abilities/data/weather_switchin.lua")
    return loadSibling("abilities/engine/switchin_weather.lua")(mod, data)
  end)
  boot("switchin_primal_weather", function()
    local data = loadSibling("abilities/data/primal_weather_switchin.lua")
    return loadSibling("abilities/engine/switchin_primal_weather.lua")(mod, data)
  end)
  boot("modern_hazards", function() return loadSibling("combat/modern_hazards.lua")(mod) end)
  -- combat/modern_side_conditions.lua (missing-effects phase 7): Court
  -- Change (swap both sides' side conditions), Brick Break/Psychic Fangs
  -- (shatter the defender's screens before the hit), Defog (clear the
  -- target side's screens+hazards, the user side's hazards and the
  -- terrain), Magic Coat / Snatch (one-turn interception volatiles read
  -- by the Battle.useMove wrap) and Imprison (a usableMoves filter). It
  -- reads modern_hazards' hazardsFor store and wraps Battle:useMove /
  -- Battle:usableMoves, so it boots right after modern_hazards.
  boot("modern_side_conditions", function() return loadSibling("combat/modern_side_conditions.lua")(mod) end)
  -- combat/modern_item_facts.lua (item-effects phase 24): the ROM-vs-
  -- Showdown item-id bridge (norm + the BLACKBELT_I rename) and the
  -- nil-tolerant itemFlags accessors -- itemFact / itemFlingFacts /
  -- isBerryItem / isPokeballItem / itemSpeciesMatch -- plus the True-Past
  -- override table for the thirteen items flags.lua cannot describe (the
  -- ten Gen-2 berries, Pink/Polkadot Bow, Berserk Gene). It registers no
  -- behaviour and reads no held item itself; it exists so every later item
  -- phase shares one id rewrite instead of re-deriving it. Booted before
  -- modern_items, which consumes it.
  boot("modern_item_facts", function() return loadSibling("combat/modern_item_facts.lua")(mod) end)
  boot("modern_items", function() return loadSibling("combat/modern_items.lua")(mod) end)
  -- combat/modern_held_item_api.lua (round 98): the public held-item storage
  -- API + cross-battle restore. Gen 1 gets a saved `mon.g9HeldItem` slot
  -- (setHeldItem / getHeldItem / clearHeldItem) because the engine gives it
  -- no item field at all; both generations get a player-party equipment
  -- snapshot on battle.started and a battle.ended restore of any item that
  -- was flung / stolen / lost / consumed during the fight (on Gen 2
  -- `Battle.party IS save.party`, so those `mon.item = nil` writes would
  -- otherwise delete it from the save for good). It reads only
  -- modern_combat's isGen2Battle, so it boots right after modern_items.
  boot("modern_held_item_api", function() return loadSibling("combat/modern_held_item_api.lua")(mod) end)
  -- combat/modern_type_modify_moves.lua (missing-effects phase 14): the
  -- onModifyType / onModifyMove family -- Hidden Power, Judgment,
  -- Multi-Attack, Revelation Dance, Techno Blast, Natural Gift, Raging
  -- Bull, Weather Ball, Terrain Pulse, Tera Blast, Tera Starstorm and
  -- Photon Geyser. It wraps battle.damage (the Aerilate-family seam) and
  -- registers power overrides, reading modern_items' itemOf lazily, so it
  -- boots right after modern_items.
  boot("modern_type_modify_moves", function() return loadSibling("combat/modern_type_modify_moves.lua")(mod) end)
  -- combat/modern_field_effects.lua (missing-effects phase 8): Gravity, Ion
  -- Deluge, Electrify, Mud/Water Sport, Nature Power, Powder, Tailwind,
  -- Aurora Veil, Lucky Chant, Fairy Lock and Tea Time. It reads
  -- modern_combat's normalize/currentWeather/registerDamageModifier,
  -- modern_weather's weather state, field_duration's resolveFieldDuration,
  -- modern_side_conditions' screens table (it rides Aurora Veil/Lucky
  -- Chant/Tailwind in there so Court Change/Defog/Brick Break see them) and
  -- modern_items' berry applier (Tea Time), and wraps Battle:useMove /
  -- Battle:effectiveSpeed / Battle:switchLocked, so it boots right after
  -- modern_items.
  boot("modern_field_effects", function() return loadSibling("combat/modern_field_effects.lua")(mod) end)
  -- combat/modern_trap_moves.lua (missing-effects phase 9): the non-chip
  -- trapping family -- Mean Look / Block / Spider Web (status pins), Jaw Lock
  -- (pins BOTH sides), Anchor Shot / Spirit Shackle (damaging pins) and
  -- Octolock (pin + a real Def/SpD -1 residual). It reads modern_combat's
  -- normalize/displayNameFor/curTypesOf/changeStage and move_targeting's
  -- allActiveBattlers, so it boots after both.
  boot("modern_trap_moves", function() return loadSibling("combat/modern_trap_moves.lua")(mod) end)
  -- combat/modern_guard_contact.lua (missing-effects phase 18): the guard /
  -- contact interaction family -- Phantom Force / Shadow Force / Hyperspace
  -- Hole protect-breaking (via the bypassesProtect flag stamped by
  -- wireMovepoolSubEffects), the ignore-defensive/evasion/ability families,
  -- and the on-hit side effects (terrain clear, Spikes/Stealth Rock
  -- layering, Thousand Waves' trap, Freezy Frost's reset, Fell Stinger's KO
  -- boost, Poltergeist/Steel Roller fail gates). It reads
  -- modern_combat's damage formula + setIgnoredAbilityMon, modern_action_
  -- order's registerFailGate (both booted earlier), and
  -- modern_side_conditions' clearTerrain / modern_hazards' hazardsFor /
  -- modern_trap_moves' trapApplyPin, so it boots right after
  -- modern_trap_moves.
  boot("modern_guard_contact", function() return loadSibling("combat/modern_guard_contact.lua")(mod) end)
  -- combat/modern_item_moves.lua (missing-effects phase 19): the item /
  -- held-item interaction family -- Trick / Switcheroo's item swap, Bestow's
  -- item give, Thief's steal, Spectral Thief's boost steal (a pre-damage
  -- battle.damage wrap), Core Enforcer's ability suppression and Plasma
  -- Fists' Ion Deluge pseudo-weather (plus Flame Burst's ally splash, a real
  -- no-op in 1-vs-1). It reads modern_items' isUnremovable, modern_combat's
  -- stagesFor/changeStage/resolvedTypeMult, modern_ability_change_moves'
  -- CANNOT_SUPPRESS and ability_dispatch's setAbility -- all booted earlier,
  -- so it boots right after modern_guard_contact.
  boot("modern_item_moves", function() return loadSibling("combat/modern_item_moves.lua")(mod) end)
  -- combat/modern_pivot_moves.lua (missing-effects phase 20): pivots and
  -- move-copying -- Baton Pass's mod-stage carry, Shed Tail / Chilly
  -- Reception's self-switch, Assist/Copycat/Instruct's nested useMove,
  -- Sketch's move-slot rewrite, Lock-On/Mind Reader's native-handler
  -- re-point, and Psych Up / Psycho Shift. It reads modern_combat's
  -- normalize/stagesFor/setWeather/canSetWeather/statusTypeImmune,
  -- switch_primitives' requestSwitch and field_duration's resolver -- all
  -- booted earlier -- so it boots right after modern_item_moves.
  boot("modern_pivot_moves", function() return loadSibling("combat/modern_pivot_moves.lua")(mod) end)
  -- combat/modern_status_moves.lua (missing-effects phase 21): status /
  -- volatile infliction residue -- Spite / Eerie Spell's PP drain, Sparkling
  -- Aria's burn-cure rider, Forest's Curse / Trick-or-Treat's added-type slot,
  -- Power Trick's raw Atk/Def swap, and Magnet Rise's Ground-immunity
  -- volatile. It reads modern_combat's normalize/displayNameFor/isGen2Battle/
  -- canonicalStatusOf (the last two also edited there for the Magnet Rise
  -- immunity), status_condition_cleanup's SWITCH_SCOPED list (two fields
  -- added) and type_override_primitives' canChangeType -- all booted earlier,
  -- so it boots right after modern_pivot_moves.
  boot("modern_status_moves", function() return loadSibling("combat/modern_status_moves.lua")(mod) end)
  -- combat/modern_side_protection.lua (missing-effects phase 22): field /
  -- side protection and delayed moves -- Safeguard (forwarded to the base
  -- engine's own native EFFECT_SAFEGUARD), Wide Guard / Quick Guard /
  -- Crafty Shield / Mat Block (per-side duration-1 guard flags read by
  -- one more Battle.useMove wrap), Future Sight / Doom Desire (a
  -- two-turn side-scheduled hit resolved on battle.turn_ended) and
  -- Present (a registerPowerOverride roll + a battle.damage heal tier),
  -- plus the First Impression fail gate and Grassy Glide's terrain
  -- priority. It reads modern_combat's sideOfWho/normalize/curTypesOf/
  -- MoveCategory, modern_action_order's registerFailGate,
  -- turn_order's registerPriorityModifier, modern_combat_protect's new
  -- armStallChain export and modern_terrain's battle.terrain -- all
  -- booted earlier -- so it boots right after modern_status_moves
  -- (before the held-item pool, so its useMove wrap sits closest to the
  -- native leaf among the move-blocking wraps).
  boot("modern_side_protection", function() return loadSibling("combat/modern_side_protection.lua")(mod) end)
  -- combat/modern_self_effects.lua (missing-effects phase 23): the
  -- `self:`-directed move effects -- the eight recharge moves (Gen 2
  -- volatile.recharge / Gen 1 mustRecharge), Mind Blown / Steel Beam's
  -- half-max-HP recoil, Misty Explosion's selfdestruct (plus its own
  -- Misty-Terrain 1.5x), Glaive Rush's drawback volatile (double damage
  -- via registerDamageModifier, can't-miss via the battle.accuracy hook),
  -- Baddy Bad / Glitzy Glow's Reflect / Light Screen, and Sparkly Swirl's
  -- whole-side status cure. It adds one more Battle.useMove wrap (the
  -- recoil/selfdestruct must fire through Protect/miss/immunity) and
  -- reads modern_combat's registerDamageModifier/curTypesOf/sideOfWho,
  -- modern_party_support's g9NameOf/g9RawMon/g9MaxHpOf/g9SidePartyOf,
  -- status_cure's cureStatusOf and field_duration's resolveFieldDuration
  -- -- all booted earlier -- so it boots right after modern_side_protection.
  boot("modern_self_effects", function() return loadSibling("combat/modern_self_effects.lua")(mod) end)
  boot("modern_held_items", function() return loadSibling("combat/modern_held_items.lua")(mod) end)
  boot("modern_held_items_phase2", function() return loadSibling("combat/modern_held_items_phase2.lua")(mod) end)
  -- combat/modern_gen1_held_items.lua (round 99): the GEN-1 side of the
  -- held-item combat wiring. The damage/stat/crit/accuracy item families were
  -- made dual-generation in the two files above; this file owns only the
  -- mechanics Gen 1 lacks a native analogue for -- item Speed + Quick
  -- Claw/Lagging Tail turn-order priority (patches src/battle/TurnOrder),
  -- Focus Sash/Focus Band survive-at-1 (its own battle.damage wrap above
  -- damage_pipeline), King's Rock flinch, and Leftovers/Berry Juice residual.
  -- It reads modern_held_item_api's set/clear/effective accessors and
  -- modern_combat's isGen2Battle, so it boots after both (and after
  -- turn_order, whose registerPriorityModifier chain it does not touch).
  boot("modern_gen1_held_items", function() return loadSibling("combat/modern_gen1_held_items.lua")(mod) end)
  boot("skill_link", function()
    local data = loadSibling("abilities/data/skill_link.lua")
    return loadSibling("abilities/engine/skill_link.lua")(mod, data)
  end)
  boot("other_misc", function()
    local data = loadSibling("abilities/data/other_misc.lua")
    return loadSibling("abilities/engine/other_misc.lua")(mod, data)
  end)
  boot("item_interaction", function()
    local data = loadSibling("abilities/data/item_interaction.lua")
    return loadSibling("abilities/engine/item_interaction.lua")(mod, data)
  end)
  boot("switch_priority_misc", function()
    local data = loadSibling("abilities/data/switch_priority_misc.lua")
    return loadSibling("abilities/engine/switch_priority_misc.lua")(mod, data)
  end)
  boot("other_misc2", function()
    local data = loadSibling("abilities/data/other_misc2.lua")
    return loadSibling("abilities/engine/other_misc2.lua")(mod, data)
  end)
  boot("truant", function()
    local data = loadSibling("abilities/data/truant.lua")
    return loadSibling("abilities/engine/truant.lua")(mod, data)
  end)
  boot("magic_bounce", function()
    local data = loadSibling("abilities/data/magic_bounce.lua")
    return loadSibling("abilities/engine/magic_bounce.lua")(mod, data)
  end)
  boot("dancer", function()
    local data = loadSibling("abilities/data/dancer.lua")
    return loadSibling("abilities/engine/dancer.lua")(mod, data)
  end)
  boot("emergency_exit", function()
    local data = loadSibling("abilities/data/emergency_exit.lua")
    return loadSibling("abilities/engine/emergency_exit.lua")(mod, data)
  end)
  boot("type_override_moves", function()
    local data = loadSibling("abilities/data/type_override_moves.lua")
    return loadSibling("abilities/engine/type_override_moves.lua")(mod, data)
  end)
  boot("parental_bond", function()
    local data = loadSibling("abilities/data/parental_bond.lua")
    return loadSibling("abilities/engine/parental_bond.lua")(mod, data)
  end)
  boot("form_combat_effects", function()
    local data = loadSibling("abilities/data/form_combat_effects.lua")
    return loadSibling("abilities/engine/form_combat_effects.lua")(mod, data)
  end)

  -- --------------------------------------------------------------------------
  -- Phase B14: round-14 ability family -- the 56 remaining national_dex
  -- abilities, grouped by their engine. Engines wrap the real battle
  -- surfaces (battle.damage, damage_dealt/fainted/turn_ended events, the
  -- held-item eater) rather than dispatching from a central table; data-only
  -- boots are acknowledgment markers for abilities implemented by editing a
  -- shared primitive directly (see each data file's own header for where).
  -- --------------------------------------------------------------------------
  boot("absorb", function()
    local data = loadSibling("abilities/data/absorb.lua")
    return loadSibling("abilities/engine/absorb.lua")(mod, data)
  end)
  boot("ko_boost", function()
    local data = loadSibling("abilities/data/ko_boost.lua")
    return loadSibling("abilities/engine/ko_boost.lua")(mod, data)
  end)
  boot("hit_taken", function()
    local data = loadSibling("abilities/data/hit_taken.lua")
    return loadSibling("abilities/engine/hit_taken.lua")(mod, data)
  end)
  boot("cudchew", function()
    local data = loadSibling("abilities/data/cudchew.lua")
    return loadSibling("abilities/engine/cudchew.lua")(mod, data)
  end)
  boot("form_change_scope", function()
    return loadSibling("abilities/data/form_change_scope.lua")
  end)
  boot("overworld_only", function()
    return loadSibling("abilities/data/overworld_only.lua")
  end)
  boot("redirect_immunity", function()
    return loadSibling("abilities/data/redirect_immunity.lua")
  end)
  boot("corrosion", function()
    return loadSibling("abilities/data/corrosion.lua")
  end)

  -- --------------------------------------------------------------------------
  -- Phase 0 (missing-effects plan): structural-exemption registry. Names the
  -- handful of moves whose real mechanic needs a second allied battler and is
  -- therefore impossible to observe in singles (Ally Switch, Dragon Cheer,
  -- Follow Me, Helping Hand, Rage Powder, Spotlight) so future audits do not
  -- re-flag them as gaps. See combat/structural_exemptions.lua and
  -- combat/NATIVE_COVERAGE.md. It registers no hooks -- it only publishes
  -- mod.exports.structuralExemptions / isStructurallyExempt.
  -- --------------------------------------------------------------------------
  boot("structural_exemptions", function()
    return loadSibling("combat/structural_exemptions.lua")(mod)
  end)

  -- --------------------------------------------------------------------------
  -- Phase C: UI / scene siblings (guarded; they need the engine's render and
  -- screen surfaces). Round 104 (2026-09-10) emptied this phase: the custom
  -- menu/party screens (ui/custom_menu_takeover.lua, ui/custom_party_scene.lua)
  -- and their shared theme (ui/ui_theme.lua) were removed with the
  -- custom_menu_scene option. The stat screens (stats/*_screen.lua) boot
  -- earlier in the file.
  -- --------------------------------------------------------------------------

  -- --------------------------------------------------------------------------
  -- Phase D: ecosystem-facing surfaces (the connectivity fixes).
  -- --------------------------------------------------------------------------
  -- Custom trainer roster registration API -- Sample-Battle-Scene-G9 calls
  -- g9dex.exports.registerTrainer / hasRegisteredTrainer.
  do end

  -- Move-availability gate: the outermost input-blocking wrap. Needs
  -- learnset_ownership's isUsable (loaded above; degraded gracefully if nil).
  boot("move_availability_gate", function()
    local install = loadSibling("combat/move_availability_gate.lua")
    return install(mod, learnsetOwnership and learnsetOwnership.isUsable or function() return true end)
  end)

  -- Two-choice in-battle prompt primitive (askBattleChoice / battleChoiceActive
  -- / cancelBattleChoice).
  boot("battle_prompt", function() return loadSibling("combat/battle_prompt.lua")(mod) end)

  -- Debug options screen: defines this mod's options schema. The screen is
  -- reached from the engine's own mod manager (mods list -> this mod -> options).
  -- Round 199 removed the START-menu debug row that used to be inserted here.
  do end

  -- --------------------------------------------------------------------------
  -- Phase E: this mod's damage brain (round-4, kept). Wraps battle.damage at
  -- priority 500 -- ABOVE every canonical wrap (the terminal Showdown formula
  -- sits at 0) -- so next(ctx) resolves the whole chain down to the formula,
  -- then routes the final number through the item / reflection systems.
  -- Ability side effects are NOT routed through .dispatch here anymore: the
  -- canonical ability engines self-hook via the battle.damage / accuracy /
  -- event buses, so no separate dispatcher is needed (and the canonical
  -- ability_dispatch exports no .dispatch).
  -- --------------------------------------------------------------------------
  boot("damage_brain", function()
    local damage_reflection = require("combat/damage/reflection")
    -- Phase 30 (item-effects plan): the old items/ tree's side-effect-only
    -- loads are gone -- each returned a table nothing consumed and
    -- registered no hook. combat/damage_pipeline (below) still requires the
    -- two files it genuinely uses (items/item_dispatch and
    -- items/engine/damage_modifiers), so nothing live is lost.
    local damage_pipeline = require("combat/damage_pipeline")
    damage_pipeline.ability_system = nil
    mod.exports.damagePipeline = damage_pipeline

    mod.hooks:wrap("battle.damage", function(next, ctx)
      return damage_pipeline.process(next, ctx)
    end, 500)
  end)

  -- --------------------------------------------------------------------------
  -- Phase F: "wired-elsewhere" ability ledger (round 10). The 13 files below
  -- are documentation markers, not dispatch engines: each ability they name
  -- is implemented by editing the shared primitive directly (the files' own
  -- headers say exactly where -- e.g. sniper in modern_combat.lua's crit
  -- block, scrappy in modern_status_volatiles.lua's type_immunity_negation).
  -- Loading them as data at boot makes that acknowledgment part of the mod's
  -- live state: mod.exports.abilitiesWiredElsewhere holds every ability id
  -- declared handled-elsewhere, so a future subsystem (or a debug session)
  -- can confirm an ability was accounted for instead of reading 13 headers.
  -- Pure data tables, pcall-guarded per file; a missing marker logs a warn
  -- and the boot always continues.
  -- --------------------------------------------------------------------------
  boot("abilities_wired_elsewhere_ledger", function()
    local ledger = mod.exports.abilitiesWiredElsewhere
    if type(ledger) ~= "table" then ledger = {}; mod.exports.abilitiesWiredElsewhere = ledger end
    local markers = {
      "abilities/data/air_lock.lua",
      "abilities/data/klutz.lua",
      "abilities/data/mega_sol.lua",
      "abilities/data/mindseye.lua",
      "abilities/data/mirror_armor.lua",
      "abilities/data/mold_breaker.lua",
      "abilities/data/neutralizing_gas.lua",
      "abilities/data/opportunist.lua",
      "abilities/data/piercing_drill.lua",
      "abilities/data/scrappy.lua",
      "abilities/data/sniper.lua",
      "abilities/data/unaware.lua",
      "abilities/data/unseen_fist.lua",
    }
    for _, file in ipairs(markers) do
      local ok, tbl = pcall(loadSibling, file)
      if ok and type(tbl) == "table" then
        for id in pairs(tbl) do ledger[id] = true end
      else
        mod.log:warn("g9-battle-engine: [abilities_wired_elsewhere_ledger] " .. file .. " not loaded: " .. tostring(tbl))
      end
    end
    return ledger
  end)

  -- combat/modern_primary_status_moves.lua (round 398): the generic driver
  -- for ailment-carrying PURE STATUS moves national_dex leaves as a
  -- placeholder on the active generation -- reported directly by the user
  -- ("will-o-wisp ... applied it on gen 1 and it didn't say fail nor applied
  -- burn"). It reads the move's own ailment/accuracy/statChanges live and
  -- wires each qualifying move to a real kind="primary" record with the
  -- engine's own fail/success wording. Booted HERE, at the very end of the
  -- modern_* sequence and just before the move-effect guard, so its
  -- live-record check sees every bespoke patch already applied (it can
  -- never double-drive a move another module owns) and so its records exist
  -- before the guard captures the effect-record lookup. Must stay ahead of
  -- move_effect_markers, which seeds a marker for any effect id with no
  -- record of its own. See that file's own header.
  boot("modern_primary_status_moves", function()
    return loadSibling("combat/modern_primary_status_moves.lua")(mod)
  end)

  -- --------------------------------------------------------------------------
  -- Phase G (round 179): Transform / Imposter / Illusion, then the
  -- universal move-effect guard. modern_transform MUST boot before the
  -- guard: it patches BattleState:effectRecord for TRANSFORM_EFFECT, and
  -- the guard (loaded last) captures that patched lookup as its native and
  -- wraps it once more -- so the transformed record's run gets the guard's
  -- nil/error normalization as the outermost layer, and every other
  -- effect record gets it directly. See each file's own header.
  -- --------------------------------------------------------------------------
  boot("modern_transform", function()
    return loadSibling("combat/modern_transform.lua")(mod)
  end)
  boot("modern_effect_guard", function()
    return loadSibling("combat/modern_effect_guard.lua")(mod)
  end)

  -- --------------------------------------------------------------------------
  -- Move-effect id-space completion, LAST (round 349). The loader's
  -- crossValidate pass reads every `moves.<id>.effect` as a reference into the
  -- CURRENT generation's move_effects registry, and the engine's own seed runs
  -- from src.mods.Builtins BEFORE any mod registers a move -- so a modded
  -- move's effect id (Gen 1's NO_ADDITIONAL_EFFECT no-op, or any id a re-owned
  -- national_dex record carries) would otherwise dangle and log one line per
  -- move. It seeds a bare kind="full" marker for ids with no record, and it
  -- MUST run after every modern_* module: those modules register the REAL
  -- records for ids the patched move records reference (GALAR_MINIMIZE_EFFECT,
  -- GALAR_BIDE_EFFECT, GMAX_AROMATICMIST_EFFECT, ...), and seeding a marker
  -- first made `effects:register` reject the real record.
  -- See combat/move_effect_markers.lua.
  -- --------------------------------------------------------------------------
  boot("move_effect_markers", function()
    return loadSibling("combat/move_effect_markers.lua")(mod)
  end)

  -- --------------------------------------------------------------------------
  -- Reapply teachability after every effect handler has been installed.
  assert(loadSibling("bridge/status_moves.lua"))(mod)
  assert(loadSibling("bridge/learnsets.lua"))(mod)
  if mod.exports.reapplyLearnsets then mod.exports.reapplyLearnsets()end
  assert(loadSibling("bridge/abilities.lua"))(mod)
  assert(loadSibling("bridge/move_tutor.lua"))(mod)

  -- Boot summary
  -- --------------------------------------------------------------------------
  local loadedCount = 0
  for _ in pairs(mod.exports.__bootReport.loaded) do loadedCount = loadedCount + 1 end
  local failedCount = 0
  for _ in pairs(mod.exports.__bootReport.failed) do failedCount = failedCount + 1 end
  mod.log:info(string.format(
    "g9-battle-engine loaded: %d/%d subsystems booted (%d guarded failures); exports live: resolveTurnActions=%s registerTrainer=%s hasRegisteredTrainer=%s askBattleChoice=%s damagePipeline=%s",
    loadedCount, loadedCount + failedCount, failedCount,
    tostring(type(mod.exports.resolveTurnActions) == "function"),
    tostring(type(mod.exports.registerTrainer) == "function"),
    tostring(type(mod.exports.hasRegisteredTrainer) == "function"),
    tostring(type(mod.exports.askBattleChoice) == "function"),
    tostring(type(mod.exports.damagePipeline) == "table")))
end
