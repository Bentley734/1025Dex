-- Phase 4 of the move-effect completion pipeline: weather. Wires
-- moves_new.lua's RAINDANCE/SUNNYDAY/SANDSTORM/SNOWSCAPE (weather
-- starters), BLIZZARD (Snow accuracy exception) and SOLARBEAM (Sun
-- charge-skip) to real, Showdown-checked behavior, on top of the
-- weather STATE (battle.weather/battle.weatherTurns, currentWeather/
-- setWeather/WEATHER_TURNS) and the Sun/Rain Fire/Water damage
-- modifier that combat/modern_combat.lua itself now owns (see that
-- file's own "Phase 4" header block -- state and the flat damage
-- multiplier live there because computeModernDamage needs them inline
-- for Snow's Ice-type Defense boost anyway). This file owns the
-- WIRING: the four starter moves, Thunder/Blizzard's accuracy
-- exception, Solar Beam's charge-skip, and Sand's end-of-turn chip.
-- Must load after modern_combat.lua (consumes its exports).
--
-- Explicitly OUT of scope, per this session's own instruction, not
-- silently added:
--   Hail / the classic "Hail" move and weather value -- "we won't bring
--     hail yet." Snow (Snowscape) is Gen 9's real replacement and is
--     the only Ice-flavored weather this file builds.
--   Sand's old Rock-type Sp. Def boost (real in Gen 4-8, explicitly
--     called out as out of scope in the plan itself).
--   Synthesis's weather-conditional heal fraction -- modern_movepool_
--     damage.lua's own header already flagged this as Phase 4's job to
--     come back for; still not touched here (not in this session's
--     explicit "what to build" list) -- Synthesis stays the flat 1/2
--     it shipped with in Phase 2.
--   Blizzard's real 10% freeze secondary -- a genuine Showdown
--     mechanic, but not requested this pass (only the accuracy
--     exception was) -- GALAR_BLIZZARD_EFFECT below is deliberately
--     empty, not a partial implementation pretending to be whole.
--
-- Gen 2 native weather, confirmed by direct read of gen2/Battle.lua/
-- Effects.lua before writing anything here (not assumed):
--   Rain Dance/Sunny Day/Sandstorm already exist as native Gen 2 moves
--   whose effect field is the literal "EFFECT_RAIN_DANCE"/"EFFECT_
--   SUNNY_DAY"/"EFFECT_SANDSTORM" string, dispatched through Battle.
--   MOVE_EFFECT_RECORDS (built from Battle.MOVE_EFFECTS, gen2/Battle.lua
--   :1896-1906) -- these ALREADY set self.weather/self.weatherTurns
--   correctly and ALREADY apply real (if Gen-2-cart-accurate, not
--   Gen9-current) Fire/Water damage multipliers and sandstorm chip via
--   Effects.lua, entirely independent of any move_effects registration.
--   BUT per this session's "Confirmed current state": these three ids
--   are registered by national_dex today (unconditionally, ~833 modern
--   moves, real power/accuracy/type, placeholder effect), which SHADOWS
--   whatever native registration existed underneath -- so today, before
--   this file, RAINDANCE/SUNNYDAY/SANDSTORM's live `effect` field is
--   national_dex's stub, NOT "EFFECT_RAIN_DANCE" et al, and Gen 2's own
--   native weather dispatch for these three is ALREADY unreachable
--   (shadowed), not something this file newly breaks. Overriding them
--   with real GALAR_* effect ids (below) doesn't sever an already-
--   working native path; it fills a gap that was already there. Same
--   reasoning modern_movepool_damage.lua's own header already applies
--   to Bounce/Outrage/Eternabeam.
--
--   Once overridden, GalarGmaxDex's own handlers below are the ONLY
--   thing setting battle.weather/battle.weatherTurns on Gen 2 -- but
--   they write into the exact same two REAL native fields, using Gen
--   2's own lowercase value convention, so every other native consumer
--   already keyed off self.weather (Effects.weatherHealFraction,
--   gen2/Ai.lua's sun check, the EFFECT_SOLARBEAM sun-skip at gen2/
--   Battle.lua:1460) keeps working automatically for rain/sun/sandstorm
--   -- see modern_combat.lua's own "Phase 4" header for the full
--   grounding. Gen 2's own Fire/Water weatherPercent computation
--   (gen2/Battle.lua:1091-1098) is DEAD regardless of any of this,
--   though: modern_combat.lua's battle.damage hook fully replaces
--   Gen 2's native damage calc too (confirmed, gen2/Battle.lua:1108-
--   1119 routes through the exact same hook BattleState:computeDamage
--   uses on Gen 1, and modern_combat.lua's own header says its hook
--   "never calls next()") -- which is exactly why this project needs
--   its OWN "weather" registerDamageModifier entry (modern_combat.lua)
--   at all, on both generations.
--
-- Gen 2 gap, honestly flagged, not silently assumed away: Solar Beam's
-- Sun charge-skip is native-hardcoded on Gen 2 (`Effects.CHARGE[def.
-- effect]` and the literal `def.effect == "EFFECT_SOLARBEAM"` check,
-- gen2/Battle.lua:1455-1462) -- checked BEFORE Gen 2's generic move_
-- effects merge even runs, keyed purely off the literal native effect
-- string. Overriding SOLARBEAM's effect field to GALAR_SOLARBEAM_EFFECT
-- (required so Gen 1 gets a real charge at all -- national_dex's stub
-- has none) makes that native check stop matching, so Gen 2 Solar Beam
-- falls through to an ordinary, un-charged, un-skipped hit -- same as
-- today (per the "already shadowed by national_dex" note above, this
-- native path is not reachable today either), so no regression, but
-- also no fix: Gen 2 Solar Beam remains uncharged after this file, the
-- same class of gap Bounce/Outrage/Eternabeam already carry.
return function(mod)
  local BattleState = require("src.battle.BattleState")
  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local currentWeather = mod.exports.currentWeather
  local setWeather = mod.exports.setWeather
  local canSetWeather = mod.exports.canSetWeather
  local curTypesOf = mod.exports.curTypesOf
  local isGen2Battle = mod.exports.isGen2Battle
  assert(normalize and displayNameFor and currentWeather and setWeather
      and canSetWeather and curTypesOf and isGen2Battle,
    "modern_weather: combat/modern_combat.lua must load first")

  ------------------------------------------------------------------
  -- Weather starters: Rain Dance, Sunny Day, Sandstorm, Snowscape.
  -- kind="primary" (power=0 status moves), same shape as GMAX_AMNESIA_
  -- EFFECT/GMAX_GROWTH_EFFECT in modern_combat.lua -- fires whole and
  -- unconditionally via BattleState:performMove's own pure-status-move
  -- block on Gen 1, and via the generic moveEffectRecordFor merge on
  -- Gen 2 (see this file's own header). accuracyChecked is left unset:
  -- these moves affect the whole field, not the opponent specifically
  -- (same "self/field-only, never miss" reasoning modern_movepool_
  -- stages.lua's own primary() already establishes for pure self-buffs).
  --
  -- "Already this exact weather -> fails" (real current Showdown: any
  -- weather move fails outright, no refresh, when that same weather is
  -- already up) applies uniformly to all four -- Gen 2's own native
  -- handler only special-cased this for sandstorm (gen2/Battle.lua:
  -- 1898, a cart-specific quirk), but this project's cross-gen rule
  -- prefers the current, uniform Showdown behavior.
  ------------------------------------------------------------------
  -- Real item per weather (confirmed against national_dex's own item
  -- catalogue, 0.31.0+: DAMPROCK/HEATROCK/SMOOTHROCK/ICYROCK, each "Held:
  -- [weather] by the holder lasts 8 rounds instead of 5"). Icy Rock is the
  -- real Snow extender in current Showdown (PokeAPI's own item text still
  -- says "hailstorm" -- pre-Gen-9 wording, not re-verified for the rename;
  -- the item id and the 5->8 mechanic are what's confirmed).
  local WEATHER_EXTEND_ITEM = {
    RAIN = "DAMPROCK", SUN = "HEATROCK", SAND = "SMOOTHROCK", SNOW = "ICYROCK",
  }
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local FIELD_BASE_TURNS = mod.exports.FIELD_BASE_TURNS
  local FIELD_EXTENDED_TURNS = mod.exports.FIELD_EXTENDED_TURNS
  assert(resolveFieldDuration and FIELD_BASE_TURNS and FIELD_EXTENDED_TURNS,
    "modern_weather: combat/field_duration.lua must load first")

  local function weatherStarter(effectId, key, startText)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      run = function(a, b, c)
        local n = normalize(a, b, c)
        if currentWeather(n.battle, n.gen2) == key then
          return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
        end
        -- Phase 1.5: Desolate Land/Primordial Sea/Delta Stream's own
        -- irreplaceable field state blocks every plain weather move the
        -- same way it blocks a plain weather ability -- see
        -- modern_combat.lua's own canSetWeather header for the full rule.
        -- Boss-fight "sun" protection rides the same check (setterMon
        -- lets it tell the boss's own side from the player's).
        if not canSetWeather(n.battle, false, n.user) then
          return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
        end
        -- Round 99: the setter is passed on BOTH generations now. Round 98
        -- gave Gen 1 a real held-item save slot, and field_duration.lua's
        -- resolveFieldDuration resolves it itself (its setterItem reads the
        -- native `.item` first for Gen 2, then falls back to the saved slot),
        -- so a Gen-1 Damp Rock/Heat Rock/Smooth Rock/Icy Rock stretches SET
        -- weather 5 -> 8 turns exactly like Gen 2. The wrapper is safe to
        -- pass: setterItem unwraps `.mon` before it ever reads a field.
        local turns = resolveFieldDuration(n.user,
          FIELD_BASE_TURNS, FIELD_EXTENDED_TURNS, WEATHER_EXTEND_ITEM[key])
        setWeather(n.battle, n.gen2, key, turns, n.user)
        return { Strings(startText) }
      end,
    })
  end

  weatherStarter("GALAR_RAINDANCE_EFFECT", "RAIN", "It started\nto rain!")
  weatherStarter("GALAR_SUNNYDAY_EFFECT", "SUN", "The sunlight\ngot bright!")
  weatherStarter("GALAR_SANDSTORM_EFFECT", "SAND", "A sandstorm\nbrewed!")
  weatherStarter("GALAR_SNOWSCAPE_EFFECT", "SNOW", "It started\nto snow!")

  ------------------------------------------------------------------
  -- Blizzard: deliberately EMPTY kind="full" record -- no run, no
  -- afterDamage, no chooseDamage, no gate, no charge. Exists only so
  -- BLIZZARD's moves_new.lua `effect` field has a real, registered
  -- (schema-valid) id to point at, satisfying isMoveDataComplete
  -- without touching Blizzard's own damage at all. A kind="secondary"+
  -- run record -- even an empty one -- would be reached by Gen 2's
  -- dispatch BEFORE its damage path and eat the whole move (the same
  -- "any .run-bearing record preempts Gen 2 damage" rule modern_
  -- movepool_status.lua's own header documents); a run-less "full"
  -- record is invisible to that check on both engines (confirmed,
  -- modern_movepool_damage.lua's own header, re-verified against
  -- EffectRegistry.runDamaging directly: every stage field it reads --
  -- gate/chooseDamage/afterDamage/onMiss -- is nil-safe), so Blizzard
  -- deals perfectly ordinary damage on both, with the accuracy
  -- exception layered on separately below.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_BLIZZARD_EFFECT", { kind = "full" })

  ------------------------------------------------------------------
  -- Solar Beam: kind="full" + charge only (no run, same "doesn't eat
  -- Gen 2 damage" reasoning as Blizzard above -- though Gen 2 doesn't
  -- reach this move's charge at all regardless, per this file's own
  -- header). charge shape copied from native CHARGE_EFFECT (MoveEffects
  -- .lua:556) -- the SAME generic non-invulnerable charge Solar Beam,
  -- Skull Bash, Sky Attack and Razor Wind all originally shared -- not
  -- Fly's invulnerable one. The charge-turn announcement text still
  -- resolves correctly regardless of this custom effect id, since
  -- BattleState.lua's own CHARGE_TEXT table is keyed by MOVE id
  -- ("SOLARBEAM"), not effect id (confirmed, BattleState.lua:416-423).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_SOLARBEAM_EFFECT", {
    kind = "full",
    charge = { anim = "XSTATITEM_ANIM", enemyAnim = "XSTATITEM_DUPLICATE_ANIM" },
  })

  -- Gen 2 charge turn, closed 2026-08-27 (this file's own header above
  -- used to document this as a real, accepted gap -- "Gen 2 Solar Beam
  -- remains uncharged"): Effects.CHARGE is a plain, mutable Lua table
  -- Gen 2's own native move-execution gate already reads generically by
  -- effect id (confirmed real, gen2/Battle.lua), the exact same
  -- primitive this session's Bounce fix (combat/modern_movepool_damage
  -- .lua) already proved safe for a damaging move -- adding a key here
  -- carries none of the move-id schema-validation risk a native id
  -- string would. The real sun-skip optimization stays Gen 1-only
  -- (SUN_SKIPS_CHARGE above) -- Gen 2 Solar Beam now genuinely charges
  -- for 2 turns even in sun, a real, smaller, separately-flagged gap,
  -- not silently dropped.
  do local ok, E = pcall(require, "src.battle.gen2.Effects"); if ok and E then E.CHARGE.GALAR_SOLARBEAM_EFFECT = { text = "%s took in sunlight!" } end end

  ------------------------------------------------------------------
  -- Solar Beam's real Sun skip-the-charge-turn. No sanctioned hook
  -- exists for this (checked: BattleState:performMove's charge branch,
  -- :3602, is a plain field read with no Runtime.call around it, unlike
  -- battle.damage/battle.accuracy) -- so this wraps performMove
  -- directly, the same established, precedented technique modern_
  -- combat_protect.lua's own Part D and gimmick_dynamax.lua's Max Guard
  -- streak-reset already use on this exact method. Forcing user.
  -- charging/chargeReady to already be "true" for THIS moveInst before
  -- delegating makes nativePerformMove's own `releasing` check (its
  -- very first statement) true, which skips the `record.charge and not
  -- releasing` branch entirely and falls straight through to an
  -- ordinary hit -- exactly "skip the charge turn, hit immediately".
  -- Gen 1 only (isGen2Battle guard) -- see file header for Gen 2.
  ------------------------------------------------------------------
  -- Phase 17 (combat/modern_charge_moves.lua): Solar Blade shares Solar
  -- Beam's exact real sun rule (Showdown moves.ts:17261's own
  -- `['sunnyday','desolateland'].includes(attacker.effectiveWeather())`),
  -- so it rides the identical skip here rather than a second wrap of
  -- performMove. The same documented Gen 2 limitation applies (the skip
  -- is Gen 1 only; Gen 2 charges through its own Effects.CHARGE system).
  local SUN_SKIPS_CHARGE = { SOLARBEAM = true, SOLARBLADE = true }
  local nativePerformMove = rawget(BattleState, "performMove")
  if type(nativePerformMove) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    -- Mega Sol (Phase 8, other bucket): real text is "can use its moves
    -- AS IF the weather were harsh sunlight" -- broader than just the
    -- Fire/Water damage multiplier (combat/modern_combat.lua's own real
    -- weather modifier), so every other real sun-move interaction this
    -- engine already models gets the same personal-only override,
    -- checked alongside the real field weather rather than replacing it.
    local abilityIdOf = mod.exports.abilityIdOf
    local megaSol = user and abilityIdOf and abilityIdOf(user) == "MEGASOL"
    if moveInst and SUN_SKIPS_CHARGE[moveInst.id] and not isGen2Battle(self)
        and (currentWeather(self, false) == "SUN" or megaSol) then
      user.charging = moveInst
      user.chargeReady = true
    end
    return nativePerformMove(self, user, target, moveInst, isCalled)
  end
  end

  ------------------------------------------------------------------
  -- Thunder (Rain) / Blizzard (Snow): real accuracy exception, both
  -- generations, via the sanctioned battle.accuracy hook (confirmed
  -- shared: BattleState.lua:2320-2329 on Gen 1, gen2/Battle.lua:2002-
  -- 2019 on Gen 2 -- "the same hook... with the same ctx keys", per
  -- that file's own comment) -- the real mechanism this pipeline's
  -- earlier phases point at for "a move never misses", not a new one.
  -- Priority -10, deliberately BELOW the chain's default (0, Hooks.lua:
  -- 24) -- so a higher-priority hook that forces a miss for its own
  -- reason (gimmick_dynamax.lua's Max Guard check is exactly this
  -- shape, also on battle.accuracy) runs OUTER/first and can short-
  -- circuit to false WITHOUT ever calling this hook's next(), meaning
  -- Max Guard-style protection always wins over this weather bypass --
  -- verified against Hooks.lua directly (chain sorted priority
  -- DESCENDING, higher runs first) rather than assumed.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    local move = ctx.move
    local moveId = (move and move.id) or ctx.moveId
    local weather = currentWeather(ctx.battle, isGen2Battle(ctx.battle))
    if moveId == "THUNDER" and weather == "RAIN" then return true end
    if moveId == "BLIZZARD" and weather == "SNOW" then return true end
    return next(ctx)
  end, -10)

  ------------------------------------------------------------------
  -- Gen 1's own weather tick: duration countdown/expiry plus Sand's
  -- end-of-turn chip, structurally mirroring Gen 2's real native
  -- tickWeather (gen2/Battle.lua:4275-4304) -- decrement first; if it
  -- reaches 0, clear and stop (no chip that final tick, matching native
  -- exactly); otherwise chip if the weather is Sand. Gen 1 has no
  -- existing end-of-turn hook for any of this (it never had weather) --
  -- battle.turn_ended (Runtime.emit'd as the LAST statement of
  -- BattleState:endOfTurn, confirmed BattleState.lua:2572, after the
  -- residual/status sweep) is the same real turn-boundary event modern_
  -- movepool_counter.lua's own Part C already reuses (there for battle.
  -- turn_STARTED; this is its end-of-turn twin) -- not a new hook.
  --
  -- Sand chip: 1/16 max HP (real current Showdown fraction, Gen 3+ --
  -- confirmed the same fraction Status.residual already uses for Leech
  -- Seed's own 1/16 drain, Status.lua:276), to every battler whose OWN
  -- current type isn't Ground/Steel/Rock. Immunity and damage both
  -- reuse real primitives: curTypesOf (Transform/Conversion-aware,
  -- modern_combat.lua) and the same direct mon.hp manipulation Status.
  -- residual itself uses (bypasses Substitute on purpose -- weather
  -- chip, like status residual damage, hits the Pokemon itself in every
  -- real generation, not a Substitute). Skips a semi-invulnerable
  -- (mid-Fly/Dig) target, mirroring Gen 2 native's own `not self:
  -- volatile(mon).vanished` check exactly (gen2/Battle.lua:4288) --
  -- medium confidence this still matches CURRENT Gen 9 Showdown on this
  -- one narrow point specifically (not independently re-verified beyond
  -- the real, working Gen 2 native precedent), flagged rather than
  -- silently assumed.
  --
  -- Gen 2: native tickWeather ALREADY runs a real, working end-of-turn
  -- pass (duration, messages, sandstorm chip) through this exact same
  -- turn-boundary machinery (it runs earlier in the SAME round, before
  -- battle.turn_ended fires) -- reused wholesale, not duplicated: this
  -- hook explicitly skips Gen 2 (isGen2Battle guard) to avoid double-
  -- ticking, and Gen2Effects.sandstormDamage below is patched in place
  -- (1/8 cart-accurate -> 1/16 current-Showdown) so that ALREADY-real
  -- pass produces the current fraction instead of a second, parallel
  -- implementation.
  ------------------------------------------------------------------
  local SAND_IMMUNE = { GROUND = true, STEEL = true, ROCK = true }
  local WEATHER_END_TEXT = {
    RAIN = "The rain\nstopped.", SUN = "The sunlight\nfaded.",
    SAND = "The sandstorm\nsubsided.", SNOW = "The snow\nstopped.",
  }

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle or isGen2Battle(battle) then return end
    local weather = currentWeather(battle, false)
    if not weather then return end
    battle.weatherTurns = (battle.weatherTurns or 0) - 1
    if battle.weatherTurns <= 0 then
      battle:sayNext(Strings(WEATHER_END_TEXT[weather] or "The weather\ncleared up."))
      setWeather(battle, false, nil)
      return
    end
    if weather ~= "SAND" then return end
    -- Phase 8 (abilities/engine/damage_immunity.lua): SANDFORCE/
    -- SANDRUSH/SANDVEIL/MAGICGUARD all block this same chip -- real,
    -- ability-level immunity, on top of the pre-existing type-based one
    -- above. Looked up lazily (abilities/ability_dispatch.lua always
    -- loads before this closure ever runs, during a real battle, but
    -- this file's own install order relative to it isn't asserted on).
    -- OVERCOAT (Phase 7, prevent bucket) added 2026-08-27: its real,
    -- current-Showdown effect is "immune to weather chip damage" in
    -- general (its own national_dex text still says "sandstorm, hail,
    -- etc.", a legacy PokeAPI description) -- Sand is the ONLY weather
    -- this engine actually chips for (this mod's own weather roster is
    -- Snow, not Hail, and real modern Snow deals no residual damage at
    -- all, matching this engine's own already-correct behavior), so
    -- Overcoat's real effect here reduces exactly to this one table.
    local SAND_CHIP_IMMUNE_ABILITY = {
      SANDFORCE = true, SANDRUSH = true, SANDVEIL = true, MAGICGUARD = true,
      OVERCOAT = true,
    }
    for _, who in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if who and who.mon and who.mon.hp > 0 and not who.invulnerable then
        local immune = false
        for _, t in ipairs(curTypesOf(who, false)) do
          if SAND_IMMUNE[t] then immune = true; break end
        end
        if not immune then
          local abilityIdOf = mod.exports.abilityIdOf
          local id = abilityIdOf and abilityIdOf(who)
          if id and SAND_CHIP_IMMUNE_ABILITY[id] then immune = true end
        end
        if not immune then
          local dmg = math.max(1, math.floor(who.mon.stats.hp / 16))
          who.mon.hp = math.max(0, who.mon.hp - dmg)
          battle:drainNext(who, who.mon.hp)
          battle:sayNext(Strings("%s is buffeted\nby the sandstorm!", displayNameFor(battle, who, false)))
          if who.mon.hp <= 0 then battle:onFaint(who) end
        end
      end
    end
  end)

  local gen2EffectsOk, Gen2Effects = pcall(require, "src.battle.gen2.Effects")
  if gen2EffectsOk and Gen2Effects then
    -- Real current Showdown sandstorm chip is 1/16 max HP -- Gen2Effects
    -- .sandstormDamage still implements the ORIGINAL Gen 2 cart value
    -- (1/8, halved starting Gen 3; confirmed gen2/Effects.lua:334-340).
    -- This project's cross-gen rule prefers current Showdown behavior,
    -- so only the fraction is patched -- the mechanism (native
    -- tickWeather's own real, working end-of-turn pass: message,
    -- animation, fainting via the round's own resolveFaints, all intact)
    -- is reused as-is, per this file's header.
    Gen2Effects.sandstormDamage = function(maxHp)
      return math.max(1, math.floor((maxHp or 16) / 16))
    end
    -- Snow, added as pure new DATA (not a new field) into Gen 2's own
    -- text tables so native tickWeather's generic countdown/expiry
    -- messaging (keyed by self.weather's VALUE) reads correctly for
    -- "snow" too -- see modern_combat.lua's own header for why this is
    -- safe (tickWeather never special-cases weather values besides
    -- "sandstorm", so introducing "snow" as pure data needs no control-
    -- flow change).
    Gen2Effects.WEATHER_START_TEXT.snow = "It started to snow!"
    Gen2Effects.WEATHER_TURN_TEXT.snow = "The snow is falling down."
    Gen2Effects.WEATHER_END_TEXT.snow = "The snow stopped."
  end

  mod.log:info("galar_gmax_dex: modern_weather loaded")
end
