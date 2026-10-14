-- Explicit user directive (2026-08-28): "taking control over them is not
-- duplication, it's centralizing... it's imperative all damage goes
-- through us, else we lose turn order control." Nine real, classic
-- moves (Seismic Toss, Night Shade, Dragon Rage, Sonic Boom, Psywave,
-- Super Fang, the three OHKO moves) all currently resolve their damage
-- through a native short-circuit
-- (`record.chooseDamage` on Gen 1, `Effects.fixedDamage` on Gen 2) that
-- computes a number and hands it straight to the HP-subtraction
-- function -- confirmed by direct source read -- NEVER through
-- `Runtime.call("battle.damage", ...)`, the one real, shared choke
-- point this mod's entire ability system (Protect, every type-immunity
-- ability, Sturdy, Wonder Guard, contact-retaliation, Mold Breaker's
-- own bypass, everything) is built on. Confirmed, concretely: Sturdy
-- currently does NOT save a Gen 1 mon from one of these moves at full
-- HP, because `battle.damage` -- the ONLY place Sturdy's own check
-- lives (abilities/engine/damage_immunity.lua) -- never even runs for
-- them today.
--
-- Fixed here by monkeypatching each move's own real damage-choosing
-- function to route its number through Runtime.call("battle.damage",
-- ...) directly -- the exact same real, sanctioned technique this
-- mod's own combat/modern_combat.lua already uses for battle.crit
-- (confirmed, that file's own header: "Runtime.call('battle.damage',
-- vanilla, ctx) already exists in the core engine for exactly this
-- purpose") -- NOT a new pattern invented here, and NOT re-deriving the
-- formula: every one of these moves keeps its own real fixed-amount
-- math, just handed to the SAME hook chain every other move already
-- goes through, so Protect/Sturdy/type-immunity abilities all get a
-- real chance to intercept it for the first time.
--
-- Real, confirmed GEN 1-SPECIFIC bugs fixed alongside the routing
-- (verified by direct source read, not assumed):
--   1. Seismic Toss/Night Shade/Dragon Rage/Sonic Boom/Super Fang
--      natively skip type-effectiveness/immunity ENTIRELY on Gen 1
--      (MoveEffects.lua's own comment, confirmed: "no immunity check:
--      SetDamageEffects skips AdjustDamageForMoveType" -- Super Fang,
--      Normal-type, incorrectly hits Ghost-types; the same real bug
--      class every one of these five shares). Gen 2's own native
--      implementation ALREADY checks this correctly (gen2/Battle.lua's
--      own real `Damage.typeMultiplier(...) == 0` gate) -- this fix is
--      genuinely Gen 1-only, matching the user's own precise scoping.
--   2. Gen 1's OHKO gate is SPEED-based ("fails against faster
--      opponents," MoveEffects.lua's own comment, confirmed) -- real
--      modern OHKO accuracy is LEVEL-based instead
--      (`(userLevel-targetLevel)*2 + baseAccuracy`, fails outright if
--      targetLevel > userLevel, no Speed involved at all). Gen 2's own
--      native OHKO is ALREADY level-based (gen2/Battle.lua's own real
--      comment: "fails outright against a higher-level target, and the
--      level difference is worth two accuracy points each") -- again,
--      genuinely Gen 1-only.
--   3. Psywave's real Gen 1 (AND Gen 2 -- confirmed, gen2/Effects.lua
--      has the identical shape) formula, `rand(1, floor(level*1.5)-1)`,
--      can roll as low as 1 regardless of level and never reaches the
--      real ceiling; real modern Psywave is
--      `floor(level * random(50,150) / 100)`, a genuinely different
--      range. Fixed for BOTH generations since both share the same
--      real bug, unlike the two Gen-1-only items above.
--
-- EXTENDED 2026-08-28, same directive, "the rest of the moves... Pokemon
-- Showdown logic for generation 9": Sheer Cold (a real OHKO move built
-- fresh via battle.accuracy + battle.damage wraps, sidestepping the
-- Gen 1/2 native effect-string mismatch entirely -- see its own section
-- below), Final Gambit, Nature's Madness/Ruination (all three genuinely
-- new to this engine, no native record on either generation at all),
-- and Counter's own real category-based (not Gen 1's authentic-but-
-- outdated type-based) rule, via a whole-registry `counterable` bulk
-- patch rather than touching the native dispatcher.
--
-- EXTENDED AGAIN 2026-08-28, same day, "review abilities similar to
-- these" (following the Magic Guard full-audit): confirmed EVERY move
-- in this file bypassed Wonder Guard entirely -- registerPostEffectivenessModifier's
-- own chain (combat/modern_combat.lua, Wonder Guard/Filter/Solid Rock/
-- Prism Armor/Tinted Lens/Neuroforce/Tera Shell's shared real primitive)
-- lives ONLY inside computeModernDamage's own internal formula branch,
-- which none of these fixed-damage/OHKO moves ever call (they compute
-- their own number and hand it straight to routeThroughBattleDamage
-- instead). Fixed via two new exports from modern_combat.lua:
-- `resolvedTypeMult` (the real, fully-resolved defender type multiplier,
-- also now folding in a SEPARATE confirmed dead-code bug this same
-- review found -- Foresight/Miracle Eye/Smack Down/Scrappy/Mind's Eye's
-- own real immunity negation and Telekinesis's own real immunity grant
-- were unreachable even for NORMAL-formula moves, see that file's own
-- header) and `applyPostEffectivenessModifiers` (an explicit-allow-list
-- runner over that same chain -- ONLY Wonder Guard's own entry applies
-- to a fixed-damage move in real Showdown, confirmed via Bulbapedia/
-- Smogon sourcing: Filter/Solid Rock/etc. are SCALING modifiers a fixed
-- amount never receives). Also fixed alongside it: Final Gambit had NO
-- type-immunity check at all before this pass -- a real, confirmed bug
-- (unconditional self-faint even against a Fighting-immune Ghost-type).
-- Gen 2's own dealDamage wrap gets Wonder Guard's gate but NOT the
-- negation half -- a real, honestly-flagged, structural gap (see that
-- section's own comment) matching Magic Guard's own documented Gen 2
-- gaps in scope and cause.
--
-- ROUND 16 ("make sure all our moves are going through our damage deliver
-- method"): a real-engine source audit (this mod never edits gen1recomp's
-- own tree; the source was pulled down and read directly) found that the
-- nine moves above were routed but CLOBBERED in the real engine -- the
-- number routeThroughBattleDamage passes rides as the hook chain's BASE,
-- at the bottom, reachable only if every wrap calls next() down to it, and
-- modern_combat.lua's terminal formula wrap (priority 0) never does. So in
-- the real engine Seismic Toss dealt computeModernDamage's power=1
-- placeholder result (~2 damage) and a power=0 record dealt 0 -- invisible
-- to the old harness, whose Runtime.call shim invoked the base directly
-- and never ran the real chain. Fixed by a shared priority-1 battle.damage
-- wrap (same tier, same shape as SHEERCOLD/FINALGAMBIT/NATURESMADNESS
-- below) that re-derives each move's real number itself and returns
-- WITHOUT calling next, so modern_combat can never clobber it -- and the
-- COUNTER family (Metal Burst/Mirror Coat/Counter), until now the one real
-- remaining bypass (Gen 1 chooseDamage and Gen 2 run both delivered
-- directly, never through battle.damage), now routes through the same
-- chain via the exported routeThroughBattleDamage. Gen 1's native
-- hardcoded `if move.id == "COUNTER"` branch (EffectRegistry) remains the
-- one documented, engine-level exception a mod cannot reach.
--
-- ROUND 17 ("time to fix these... just pass a damage that would faint the
-- pokemon if the move requires it so"): the three OHKO moves' true damage is
-- now the TARGET'S REAL MAX HP -- real Showdown (battle-actions.ts,
-- `if (move.ohko) return this.battle.gen === 3 ? target.hp : target.maxhp`)
-- deals maxhp, not a magic 65535 -- chosen over current HP on purpose: the
-- target may heal after this number is computed but before it lands, and the
-- damage must still guarantee the faint. Every special-damage number this
-- file delivers also marks its info trueDamage=true, which the damage
-- pipeline reads (combat/damage_pipeline.lua) to apply the ONLY Showdown
-- final-damage multiplier that really scales a fixed number -- Life Orb
-- (onModifyDamage, priority 100; Seismic Toss is confirmed boosted) -- while
-- NEVER applying Choice Band/Specs (onModifyAtk/SpA, pre-formula STAT
-- multipliers) or Silk Scarf (onBasePower) to a fixed number. This resolves
-- the round-16 "known accepted limitation": Life Orb scaling fixed numbers is
-- actually Showdown-FAITHFUL and stays; Choice/type-boost gating is the real
-- fix. Sheer Cold additionally got its real Showdown (ohko:'Ice') rules:
-- fails outright against an Ice-type target (hard immunity, checked in its
-- own battle.damage wrap), and 20/30 accuracy -- 20 when the user is not
-- Ice-type, 30 when it is (battle.accuracy wrap, gen 7+ rule). Sturdy's own
-- OHKO block (full 0-damage block, Showdown onTryHit) and Focus Sash's
-- 1-HP save are handled in abilities/engine/damage_immunity.lua +
-- combat/damage_pipeline.lua respectively -- see those files' round-17
-- headers.
return function(mod)
  local Runtime = require("src.mods.Runtime")
  local TypeChart = require("src.battle.TypeChart")

  -- Routes an already-computed (dmg, info) pair through the real,
  -- shared "battle.damage" hook chain -- Protect/type-immunity/Sturdy/
  -- everything else registered on it gets first refusal, exactly as if
  -- this had been a normal formula-driven hit; the base function at the
  -- bottom of the chain just returns the pre-computed number untouched
  -- if nothing above it intercepts.
  local function routeThroughBattleDamage(battle, user, target, move, dmg, info, gen2)
    return Runtime.call("battle.damage", function() return dmg, info end,
      { battle = battle, user = user, target = target, move = move,
        opts = {}, rng = battle.rng or (battle.roller and battle:roller()), gen2 = gen2 })
  end
  -- Exported (round 16) so the counter family's own Gen 1 chooseDamage /
  -- Gen 2 run (combat/modern_movepool_counter.lua) can route through the
  -- SAME chain these fixed-damage moves use -- the whole mod's one shared
  -- battle.damage entry point for special-damage moves.
  mod.exports.routeThroughBattleDamage = routeThroughBattleDamage

  -- Round 17: the real max-HP number an OHKO move must deal. Showdown deals
  -- target.maxhp (battle-actions.ts `if (move.ohko) return ... target.maxhp`
  -- on Gen 4+), NOT a magic huge number -- and maxhp, not current HP, on
  -- purpose: the target may heal after this number is computed but before it
  -- lands, and the damage must still faint it. Battler shapes differ by
  -- engine -- Gen 1 battler carries .mon, Gen 2 battler IS the mon -- so read
  -- .mon first, then stats.hp / maxhp / hp as fallbacks.
  local function maxHpOf(who)
    local m = (who and who.mon) or who
    return (m and ((m.stats and m.stats.hp) or m.maxhp or m.hp)) or 65535
  end

  local function typeImmune(moveType, targetTypes)
    return targetTypes and TypeChart.effectiveness(moveType, targetTypes) == 0
  end

  -- Real, fully-resolved type multiplier for one of these fixed-damage/
  -- OHKO moves -- routes through combat/modern_combat.lua's own
  -- `resolvedTypeMult` (added 2026-08-28, Wonder-Guard-reachability
  -- review) instead of the raw `typeImmune` helper above, so Foresight/
  -- Miracle Eye/Smack Down/Scrappy/Mind's Eye's real immunity negation
  -- and Telekinesis's real immunity grant both apply here exactly like
  -- they do for every normal-formula move, not just a bare natural-
  -- type-chart lookup. Falls back to the raw `typeImmune` shape (mult
  -- 0 or 10) only if modern_combat.lua genuinely hasn't loaded yet --
  -- shouldn't happen given real load order, but this file has no hard
  -- `assert` on that export and shouldn't crash boot if it's ever
  -- missing.
  local function resolvedMult(battle, user, target, gen2, moveType, targetTypesFallback)
    local resolvedTypeMult = mod.exports.resolvedTypeMult
    if resolvedTypeMult then
      return resolvedTypeMult(battle, user, target, gen2, moveType)
    end
    return typeImmune(moveType, targetTypesFallback) and 0 or 10
  end

  -- Wonder Guard's own real hard gate (blocks anything not super
  -- effective, fixed-damage/OHKO moves included -- confirmed real,
  -- Shedinja's own textbook Psywave/Fissure/Metal Burst immunity) --
  -- the ONLY entry from computeModernDamage's own postEffectivenessModifiers
  -- chain that real Showdown applies to these moves; see
  -- applyPostEffectivenessModifiers's own header in modern_combat.lua for
  -- why Filter/Solid Rock/Tinted Lens/Neuroforce/Tera Shell are
  -- deliberately NOT included here.
  local function wonderGuardAdjust(battle, user, target, move, mult, gen2, dmg)
    local applyPostEffectivenessModifiers = mod.exports.applyPostEffectivenessModifiers
    if not applyPostEffectivenessModifiers then return dmg end
    return applyPostEffectivenessModifiers({
      battle = battle, user = user, target = target, move = move,
      mult = mult, gen2 = gen2, damage = dmg,
    }, { "wonderguard" })
  end

  ------------------------------------------------------------------
  -- GEN 1
  ------------------------------------------------------------------
  local MoveEffects = require("src.battle.MoveEffects")

  local specialDamageRecord = MoveEffects.full and MoveEffects.full.SPECIAL_DAMAGE_EFFECT
  if specialDamageRecord then
    specialDamageRecord.chooseDamage = function(ctx)
      -- ctx.target.curTypes, NOT ctx.target.mon.curTypes -- confirmed
      -- real shape: this mod's own established curTypesOf accessor
      -- (combat/modern_combat.lua) reads Gen 1's own curTypes straight
      -- off the battler wrapper itself, matching the native
      -- immuneMsg helper this same file (MoveEffects.lua) already uses
      -- for OHKO_EFFECT's own real immunity check -- level/hp are the
      -- ones nested under .mon, not curTypes.
      local mult = resolvedMult(ctx.battle, ctx.user, ctx.target, false, ctx.move.type, ctx.target.curTypes)
      if mult == 0 then
        return 0, { crit = false, typeMult = 0 }
      end
      local dmg
      local id = ctx.move.id
      if id == "SEISMIC_TOSS" or id == "NIGHT_SHADE" then
        dmg = math.max(1, ctx.user.mon.level or 1)
      elseif id == "PSYWAVE" then
        dmg = math.max(1, math.floor((ctx.user.mon.level or 1) * ctx.rng(50, 150) / 100))
      elseif id == "SONICBOOM" then
        dmg = 20
      elseif id == "DRAGON_RAGE" then
        dmg = 40
      else
        dmg = math.max(1, math.floor(ctx.move.power or 0)) -- real fallback, matches native EFFECT_STATIC_DAMAGE's own shape
      end
      dmg = wonderGuardAdjust(ctx.battle, ctx.user, ctx.target, ctx.move, mult, false, dmg)
      return routeThroughBattleDamage(ctx.battle, ctx.user, ctx.target, ctx.move, dmg,
        { crit = false, typeMult = 10, trueDamage = true }, false)
    end
  end

  local superFangRecord = MoveEffects.full and MoveEffects.full.SUPER_FANG_EFFECT
  if superFangRecord then
    superFangRecord.chooseDamage = function(ctx)
      local mult = resolvedMult(ctx.battle, ctx.user, ctx.target, false, ctx.move.type, ctx.target.curTypes)
      if mult == 0 then
        return 0, { crit = false, typeMult = 0 }
      end
      local dmg = math.max(1, math.floor((ctx.target.mon.hp or 1) / 2))
      dmg = wonderGuardAdjust(ctx.battle, ctx.user, ctx.target, ctx.move, mult, false, dmg)
      return routeThroughBattleDamage(ctx.battle, ctx.user, ctx.target, ctx.move, dmg,
        { crit = false, typeMult = 10, trueDamage = true }, false)
    end
  end

  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")
  local ohkoRecord = MoveEffects.full and MoveEffects.full.OHKO_EFFECT
  if ohkoRecord then
    -- Real modern accuracy: base 30 (this cart's own real OHKO base,
    -- confirmed unchanged across every generation) + 2 per level the
    -- user is ABOVE the target; fails outright (not just "misses") if
    -- the target is a higher level, checked ahead of any roll.
    ohkoRecord.gate = function(ctx)
      local mult = resolvedMult(ctx.battle, ctx.user, ctx.target, false, ctx.move.type, ctx.target.curTypes)
      if mult == 0 then
        local name = ctx.target.isPlayer and ctx.target.name or Strings("Enemy %s", ctx.target.name)
        return false, romText(ctx.battle.data, "_DoesntAffectMonText",
          "It doesn't affect\n%s!", name)
      end
      local userLevel = ctx.user.mon.level or 1
      local targetLevel = ctx.target.mon.level or 1
      if targetLevel > userLevel then
        return false, romText(ctx.battle.data, "_ButItFailedText", "But, it failed!")
      end
      return true
    end
    ohkoRecord.chooseDamage = function(ctx)
      local mult = resolvedMult(ctx.battle, ctx.user, ctx.target, false, ctx.move.type, ctx.target.curTypes)
      local dmg = wonderGuardAdjust(ctx.battle, ctx.user, ctx.target, ctx.move, mult, false, maxHpOf(ctx.target))
      return routeThroughBattleDamage(ctx.battle, ctx.user, ctx.target, ctx.move, dmg,
        { crit = false, typeMult = 10, ohko = true, trueDamage = true }, false)
    end
  end

  ------------------------------------------------------------------
  -- GEN 2 -- same real "bypasses battle.damage" architectural gap, but
  -- WITHOUT Gen 1's own two extra bugs: confirmed by direct source read
  -- that Gen 2's own native fixed-damage type-immunity check (gen2/
  -- Battle.lua's own real `Damage.typeMultiplier(...) == 0` gate,
  -- checked ahead of dealDamage) and its own OHKO accuracy (gen2/
  -- Battle.lua's own real comment: "fails outright against a higher-
  -- level target, and the level difference is worth two accuracy
  -- points each") are ALREADY correct -- only the routing needs fixing
  -- here, plus the identical real Psywave formula bug Gen 1 has (gen2/
  -- Effects.lua's own fixedDamage carries the SAME real
  -- `random(ceiling-1)+1` shape).
  --
  -- Effects.fixedDamage itself (the function Gen 1's own equivalent
  -- monkeypatch targets) can't be used as the hook point here: its own
  -- real signature (`effect, attacker, defender, random, power`) is
  -- called from deep inside Battle:useMove with no battle/self
  -- reference passed in at all, confirmed by direct read -- there is no
  -- way to build a real battle.damage ctx from inside it. Battle
  -- :dealDamage (a real method, `self` included) is the next real choke
  -- point EVERY one of these calls funnels through on its way to
  -- actually subtracting HP -- confirmed by direct read of both the
  -- fixed-damage call site (Battle.lua:1764) and EFFECT_OHKO's own
  -- (Battle.lua:2424), both passing `{move=def, moveId=...}` as opts --
  -- so this wraps THAT instead, keyed off `opts.move.effect`, careful to
  -- only touch the five real ids below and leave every other real
  -- dealDamage call (recoil, residual status, Aftermath, Struggle,
  -- everything else that never sets opts.move to one of these) 100%
  -- untouched.
  ------------------------------------------------------------------
  local gen2Ok_Battle2, Battle2 = pcall(require, "src.battle.gen2.Battle")
  Battle2 = gen2Ok_Battle2 and Battle2 or nil
  if Battle2 then
    local FIXED_EFFECT_IDS = {
      EFFECT_LEVEL_DAMAGE = true, EFFECT_SUPER_FANG = true,
      EFFECT_PSYWAVE = true, EFFECT_STATIC_DAMAGE = true, EFFECT_OHKO = true,
    }
    local nativeDealDamage = Battle2.dealDamage
    function Battle2:dealDamage(attacker, defender, damage, opts)
      local effect = opts and opts.move and opts.move.effect
      if effect and FIXED_EFFECT_IDS[effect] then
        if effect == "EFFECT_PSYWAVE" then
          -- Real modern formula, same fix as Gen 1's own (this file's own
          -- header) -- self.random(n) returns 0..n-1 (confirmed by
          -- gen2/Effects.lua's own real fixedDamage usage), so
          -- self.random(101)+50 gives a real inclusive [50,150] range.
          damage = math.max(1, math.floor((attacker.level or 1)
            * (self.random(101) + 50) / 100))
        end
        -- Wonder Guard's own real hard gate (2026-08-28, Wonder-Guard-
        -- reachability review). NOT re-checking plain type immunity here
        -- -- native Gen 2 already resolved that BEFORE ever calling
        -- dealDamage (this file's own header, "Gen 2's own native fixed-
        -- damage type-immunity check ... is ALREADY correct") -- so
        -- resolvedMult below feeds Wonder Guard's super-effective check
        -- only. Real, confirmed, honestly-flagged gap left open: that
        -- native pre-check has no knowledge of this mod's own Foresight/
        -- Miracle Eye/Smack Down/Scrappy/Mind's Eye negation fields, so a
        -- Scrappy user's Super Fang/Seismic-Toss-family hit against a
        -- Ghost-type on GEN 2 specifically still wrongly whiffs at the
        -- native layer before this wrap ever runs -- Gen 1's own
        -- equivalent (this file's own MoveEffects.chooseDamage overrides
        -- above) does NOT have this gap, since THIS mod owns that gate
        -- directly there. Same class of gap as Magic Guard's own
        -- documented Gen 2 recoil/sandstorm-chip gaps (abilities/engine/
        -- damage_immunity.lua's own header) -- no clean extension point
        -- inside Gen 2's native pre-dealDamage accuracy/immunity check
        -- without touching gen1recomp-dev's own source, which this mod
        -- never does.
        local resolvedTypeMult = mod.exports.resolvedTypeMult
        local mult = resolvedTypeMult and resolvedTypeMult(self, attacker, defender, true, opts.move.type)
          or (typeImmune(opts.move.type, defender.types) and 0 or 10)
        if effect == "EFFECT_OHKO" then
          -- Round 17 (Showdown, gen 4+): OHKO damage = the target's MAX HP,
          -- not a magic huge number -- must guarantee the faint even if the
          -- target heals after this number is computed but before it lands.
          damage = maxHpOf(defender)
        end
        damage = wonderGuardAdjust(self, attacker, defender, opts.move, mult, true, damage)
        local adjusted, info = routeThroughBattleDamage(self, attacker, defender,
          opts.move, damage, { crit = false, typeMult = 10, ohko = effect == "EFFECT_OHKO", trueDamage = true }, true)
        return nativeDealDamage(self, attacker, defender, adjusted, opts)
      end
      return nativeDealDamage(self, attacker, defender, damage, opts)
    end
  end

  ------------------------------------------------------------------
  -- SHEER COLD -- un-deferred 2026-08-28 (explicit user directive: "the
  -- rest of the moves, based on Pokemon Showdown logic for generation
  -- 9"). The original "no native record on either engine" blocker is
  -- real, but it turns out not to matter: unlike the nine moves above,
  -- this one needs NO native record to hook at all -- a `battle.damage`
  -- wrap keyed on `ctx.move.id` (this mod's OWN choice of id string,
  -- since national_dex already registers Sheer Cold as a real, playable
  -- move with no working native effect behind it either) reaches it
  -- exactly the same way computeModernDamage's own base formula would
  -- have, and `battle.accuracy` (a real, separate, already-hookable
  -- extension point -- confirmed shared, same ctx keys, both engines,
  -- accuracy_multiplier.lua's own header) covers the real level-based
  -- gate directly, with no dependency on either engine's own
  -- "OHKO_EFFECT" vs "EFFECT_OHKO" naming at all.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    local moveId = (ctx.move and ctx.move.id) or ctx.moveId
    if moveId ~= "SHEERCOLD" then return next(ctx) end
    local isGen2Battle = mod.exports.isGen2Battle
    local gen2 = isGen2Battle and ctx.battle and isGen2Battle(ctx.battle)
    local user, target = ctx.user, ctx.target
    local userLevel = gen2 and user.level or (user.mon and user.mon.level) or 1
    local targetLevel = gen2 and target.level or (target.mon and target.mon.level) or 1
    if targetLevel > userLevel then return false end
    -- Round 17 (Showdown, gen 7+): Sheer Cold's real accuracy is 20 when
    -- the user is NOT Ice-type, 30 when it is. Applied as a 2/3 factor on
    -- the engine's real base accuracy (the move's own accuracy stat).
    local curTypesOf = mod.exports.curTypesOf
    local userTypes = curTypesOf and curTypesOf(user, gen2)
    local userIce = false
    if userTypes then
      for _, t in ipairs(userTypes) do
        if t == "ICE" then userIce = true break end
      end
    end
    if not userIce and type(ctx.accuracy) == "number" then
      ctx.accuracy = math.floor(ctx.accuracy * 2 / 3)
    end
    return next(ctx)
  end, 0)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local moveId = ctx.move and ctx.move.id
    if moveId ~= "SHEERCOLD" then return next(ctx) end
    local isGen2Battle = mod.exports.isGen2Battle
    local gen2 = isGen2Battle and ctx.battle and isGen2Battle(ctx.battle)
    local curTypesOf = mod.exports.curTypesOf
    local targetTypes = curTypesOf and curTypesOf(ctx.target, gen2)
    -- Round 17 (Showdown, ohko:'Ice'): Sheer Cold fails outright against an
    -- Ice-type target -- a hard immunity, not a damage reduction.
    if targetTypes then
      for _, t in ipairs(targetTypes) do
        if t == "ICE" then return 0, { crit = false, typeMult = 0 } end
      end
    end
    local mult = resolvedMult(ctx.battle, ctx.user, ctx.target, gen2, ctx.move.type, targetTypes)
    if mult == 0 then
      return 0, { crit = false, typeMult = 0 }
    end
    local dmg = wonderGuardAdjust(ctx.battle, ctx.user, ctx.target, ctx.move, mult, gen2, maxHpOf(ctx.target))
    return dmg, { crit = false, typeMult = 10, ohko = true, trueDamage = true }
  end, 1)

  ------------------------------------------------------------------
  -- FINAL GAMBIT -- real Showdown: the user faints, dealing damage to
  -- the target equal to its OWN current HP (read and self-applied
  -- BEFORE the target's own damage is returned, matching real
  -- Showdown's own real order: `directDamage(pokemon.hp, ...)` happens
  -- first, then that same number becomes the returned damage). Only
  -- actually faints the user if the hit genuinely lands (wrapped INSIDE
  -- the "battle.damage" chain, so Protect/type-immunity above this
  -- still correctly refuse the whole thing, self-faint included -- a
  -- blocked Final Gambit costs nothing).
  --
  -- Real type-immunity check ADDED 2026-08-28 (Wonder-Guard-reachability
  -- review): Final Gambit is a real FIGHTING-type move (national_dex's
  -- own move data, confirmed) -- a Ghost-type target is naturally immune
  -- to Fighting, and real Bulbapedia sourcing confirms the user does NOT
  -- faint when the move fails this way ("If Final Gambit doesn't hit the
  -- opponent due to missing, type immunity, or protection, ... the user
  -- will not faint"). The original version here had NO type check at
  -- all -- a real, confirmed bug (unconditional self-faint + damage
  -- even against a Ghost-type) fixed alongside Wonder Guard's own gate.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local moveId = ctx.move and ctx.move.id
    if moveId ~= "FINALGAMBIT" then return next(ctx) end
    local isGen2Battle = mod.exports.isGen2Battle
    local gen2 = isGen2Battle and ctx.battle and isGen2Battle(ctx.battle)
    local curTypesOf = mod.exports.curTypesOf
    local targetTypes = curTypesOf and curTypesOf(ctx.target, gen2)
    local mult = resolvedMult(ctx.battle, ctx.user, ctx.target, gen2, ctx.move.type, targetTypes)
    if mult == 0 then
      return 0, { crit = false, typeMult = 0 }
    end
    local user = ctx.user
    local m = user.mon or user
    local hp = m.hp or 0
    if hp <= 0 then return 0, { crit = false, typeMult = 0 } end
    local dmg = wonderGuardAdjust(ctx.battle, ctx.user, ctx.target, ctx.move, mult, gen2, hp)
    m.hp = 0
    return dmg, { crit = false, typeMult = 10, trueDamage = true }
  end, 1)

  ------------------------------------------------------------------
  -- NATURE'S MADNESS / RUINATION -- real Showdown: both share the
  -- identical real formula, halving the target's CURRENT hp (floored,
  -- minimum 1) -- confirmed the same real fixed-damage shape, just two
  -- different move ids/generations for the identical mechanic.
  --
  -- Type-immunity/Wonder-Guard check added 2026-08-28 for consistency
  -- with every other move in this file (Wonder-Guard-reachability
  -- review) -- low real-world impact (Fairy/Dark, these moves' real
  -- types, have no natural 0x immunity anywhere in the current type
  -- chart, confirmed), but a genuinely typed damaging move should still
  -- resolve type interactions the same real way every other one here
  -- does, not skip the check just because it happens to rarely matter.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local moveId = ctx.move and ctx.move.id
    if moveId ~= "NATURESMADNESS" and moveId ~= "RUINATION" then return next(ctx) end
    local isGen2Battle = mod.exports.isGen2Battle
    local gen2 = isGen2Battle and ctx.battle and isGen2Battle(ctx.battle)
    local curTypesOf = mod.exports.curTypesOf
    local targetTypes = curTypesOf and curTypesOf(ctx.target, gen2)
    local mult = resolvedMult(ctx.battle, ctx.user, ctx.target, gen2, ctx.move.type, targetTypes)
    if mult == 0 then
      return 0, { crit = false, typeMult = 0 }
    end
    local m = ctx.target.mon or ctx.target
    local dmg = math.max(1, math.floor((m.hp or 1) / 2))
    dmg = wonderGuardAdjust(ctx.battle, ctx.user, ctx.target, ctx.move, mult, gen2, dmg)
    return dmg, { crit = false, typeMult = 10, trueDamage = true }
  end, 1)

  ------------------------------------------------------------------
  -- ROUND 16: the authoritative number for the FIXED-DAMAGE family (the
  -- nine moves whose chooseDamage/dealDamage above route through
  -- battle.damage) AND the COUNTER family (Metal Burst / Mirror Coat /
  -- Counter, whose own chooseDamage/run in modern_movepool_counter.lua
  -- now route too). One shared battle.damage wrap at priority 1 -- above
  -- modern_combat.lua's terminal formula wrap (0), same tier the
  -- SHEERCOLD/FINALGAMBIT/NATURESMADNESS wraps already sit in, returning
  -- WITHOUT calling next so computeModernDamage can never run for them.
  --
  -- WHY THIS EXISTS (the real-engine bug this round's source audit
  -- uncovered): routeThroughBattleDamage's precomputed number rides in as
  -- the chain's BASE function, at the very BOTTOM of the hook chain --
  -- reachable only if every wrap calls next() down to it. modern_combat
  -- .lua wraps battle.damage at priority 0 and NEVER calls next (this
  -- mod's own documented, explicit decision: "this formula is the only
  -- damage path, unconditionally"), so that base was unreachable in the
  -- real engine and every fixed-damage move landed as computeModernDamage's
  -- power=1 placeholder formula result (~2 damage for Seismic Toss, 0 for
  -- a power=0 record). The old harness could not catch this -- its
  -- Runtime.call shim invoked the fallback directly, never the real chain.
  -- This wrap re-derives each move's real number itself (so it survives),
  -- exactly like the three priority-1 wraps above; the routed base value
  -- is now only a graceful fallback if this wrap is ever absent.
  --
  -- Real Showdown formulas, matching what the Gen 1 chooseDamage overrides
  -- above already computed (and Gen 2's own native fixed-damage already
  -- does): level damage for Seismic Toss/Night Shade, the modern
  -- floor(level*random(50,150)/100) for Psywave, flat 20/40 for Sonic
  -- Boom/Dragon Rage, floor(target HP / 2) for Super Fang, the target's
  -- MAX HP for the three OHKO moves (round 17, Showdown gen 4+), and the
  -- counter family's
  -- floor(taken * num / den) from the same "damage taken this turn by
  -- category" state its own chooseDamage/run read, the mod's own
  -- accumulator (user.counterTookThisTurn/counterTookKind fed by
  -- modern_movepool_counter.lua's battle.damage_dealt listener -- the
  -- single source of truth on BOTH generations; the native volatile
  -- tookThisTurn is deliberately NOT read -- see the round-21c note in
  -- the counter branch below: it's a running total AND never cleared for
  -- non-lead battlers in g9-Battle-Scene's multi-battler rosters, so it
  -- leaked stale damage into every spammed counter). Type immunity (Counter's
  -- Fighting vs Ghost, Mirror Coat's Psychic vs Dark) and Wonder Guard
  -- are resolved here exactly like SHEERCOLD above, via the shared
  -- resolvedMult/wonderGuardAdjust helpers.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local moveId = ctx.move and ctx.move.id
    if not moveId then return next(ctx) end
    local isGen2Battle = mod.exports.isGen2Battle
    local gen2 = isGen2Battle and ctx.battle and isGen2Battle(ctx.battle)
    local curTypesOf = mod.exports.curTypesOf
    local targetTypes = curTypesOf and curTypesOf(ctx.target, gen2)

    local FIXED_DAMAGE = {
      SEISMIC_TOSS = "LEVEL", NIGHT_SHADE = "LEVEL",
      PSYWAVE = "PSYWAVE", SONICBOOM = 20, DRAGON_RAGE = 40,
      SUPER_FANG = "SUPER_FANG",
      FISSURE = "OHKO", GUILLOTINE = "OHKO", HORNDRILL = "OHKO",
    }
    local fixedKind = FIXED_DAMAGE[moveId]
    local counterParams
    if not fixedKind then
      local counterFamilyParams = mod.exports.counterFamilyParams
      counterParams = counterFamilyParams and counterFamilyParams[moveId]
      if not counterParams then return next(ctx) end
    end

    local mult = resolvedMult(ctx.battle, ctx.user, ctx.target, gen2, ctx.move.type, targetTypes)
    if mult == 0 then
      return 0, { crit = false, typeMult = 0 }
    end

    local level = gen2 and ctx.user.level or (ctx.user.mon and ctx.user.mon.level) or 1
    local dmg
    if fixedKind == "LEVEL" then
      dmg = math.max(1, level)
    elseif fixedKind == "PSYWAVE" then
      local rng = ctx.rng
      dmg = math.max(1, math.floor(level * (rng and rng(50, 150) or 100) / 100))
    elseif fixedKind == "SUPER_FANG" then
      local m = ctx.target.mon or ctx.target
      dmg = math.max(1, math.floor((m.hp or 1) / 2))
    elseif fixedKind == "OHKO" then
      dmg = maxHpOf(ctx.target)
    elseif fixedKind then -- a flat number (SONICBOOM / DRAGON_RAGE)
      dmg = fixedKind
    else -- counter family
      -- ROUND 21c: re-derive from the mod's OWN last-hit accumulator
      -- (modern_movepool_counter.lua) so this wrap and the run agree -- and
      -- NOTHING ELSE. ROUND 21b kept the native volatile tookThisTurn as a
      -- fallback; that was the leak: the engine clears it only for
      -- battle.player/battle.enemy at turn start, so in g9-Battle-Scene's
      -- real multi-battler rosters a non-lead battler's volatile held stale
      -- damage forever and every spammed counter re-answered it even with
      -- nothing hitting the user this turn. battle.damage_dealt fires for
      -- every landed hit, so nil here genuinely means "no hit this turn".
      taken = ctx.user.counterTookThisTurn or 0
      takenKind = ctx.user.counterTookKind
      if taken <= 0 then return 0, { crit = false, typeMult = 10 } end
      if counterParams.kind and takenKind ~= counterParams.kind then
        return 0, { crit = false, typeMult = 10 }
      end
      dmg = math.min(65535, math.max(1,
        math.floor(taken * counterParams.num / counterParams.den)))
    end

    dmg = wonderGuardAdjust(ctx.battle, ctx.user, ctx.target, ctx.move, mult, gen2, dmg)
    return dmg, { crit = false, typeMult = 10, trueDamage = true, ohko = (fixedKind == "OHKO") or nil }
  end, 1)

  ------------------------------------------------------------------
  -- COUNTER -- real modern rule: counts the last CATEGORY=Physical
  -- move taken, not "Normal or Fighting-TYPE" (Gen 1's own real native
  -- check, confirmed by direct read of EffectRegistry.lua -- a real
  -- fact about the authentic cartridge, not a bug on ITS OWN terms, but
  -- not modern-accurate either). The native dispatcher's own hardcoded
  -- `if move.id == "COUNTER"` branch has no `record`-shaped extension
  -- point to monkeypatch (confirmed, see this file's own header) -- but
  -- its own real condition ALREADY checks a genuine, real, per-move
  -- DATA OVERRIDE first (`lm.counterable`, confirmed by direct read)
  -- before ever falling back to the type check, so this closes the gap
  -- without touching that function at all: every real move gets its own
  -- correct `counterable` flag patched directly, matching its own real
  -- damageClass, using the exact same whole-registry bulk-patch pattern
  -- combat/modern_combat_protect.lua's own Z-Move heuristic already
  -- established (pcall-guarded, both the whole pass and each individual
  -- patch, logged count).
  ------------------------------------------------------------------
  do
    local nationalDex = mod.find and mod.find("national_dex")
    local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
    if moveById and mod.content and mod.content.moves then
      local runOk, runErr = pcall(function()
        local patched = 0
        for id in mod.content.moves:each() do
          if type(id) == "string" then
            local ok, info = pcall(moveById, id)
            if ok and info and info.damageClass then
              local physical = info.damageClass == "physical"
              local patchOk = pcall(function()
                mod.content.moves:patch(id, { counterable = physical })
              end)
              if patchOk then patched = patched + 1 end
            end
          end
        end
        mod.log:info("g9-battle-engine: legacy_move_takeover: Counter's own real "
          .. "counterable flag patched onto %d move(s) (category-based, real modern rule, "
          .. "replacing Gen 1's own real type-based cartridge check)", patched)
      end)
      if not runOk then
        mod.log:warn("g9-battle-engine: legacy_move_takeover: Counter counterable "
          .. "bulk-patch errored, skipped (%s)", tostring(runErr))
      end
    end
  end

  mod.log:info("g9-battle-engine: legacy_move_takeover installed, both generations "
    .. "(SEISMICTOSS, NIGHTSHADE, DRAGONRAGE, SONICBOOM, PSYWAVE, SUPERFANG, "
    .. "FISSURE/GUILLOTINE/HORNDRILL centralized through battle.damage; SHEERCOLD, "
    .. "FINALGAMBIT, NATURESMADNESS/RUINATION built fresh; COUNTER family (METALBURST, "
    .. "MIRRORCOAT, COUNTER) now routed through battle.damage too; the shared priority-1 "
    .. "wrap re-derives every fixed/counter number so modern_combat's terminal formula "
    .. "can never clobber it in the real engine; COUNTER's own real counterable flag "
    .. "bulk-patched; Wonder Guard's real hard gate reachable for all of the above via "
    .. "resolvedTypeMult/applyPostEffectivenessModifiers, FINALGAMBIT's missing "
    .. "type-immunity check fixed alongside it)")
end
