-- Dispatch engine for abilities/data/damage_immunity.lua -- Phase 8a of
-- the ability roadmap ("other" bucket, first batch). Real conditions are
-- read live wherever national_dex/this mod's own primitives already
-- expose them; see the data file's own header for the full per-ability
-- grounding and the honest MAGICGUARD scope note.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags,
    "damage_immunity: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  local registerPostEffectivenessModifier = mod.exports.registerPostEffectivenessModifier
  assert(abilityIdOf and registerPostEffectivenessModifier,
    "damage_immunity: ability_dispatch.lua and modern_combat.lua must load first")

  local function hpOf(mon) return (mon.mon or mon) end

  ------------------------------------------------------------------
  -- WONDERGUARD -- real final type multiplier (ctx.mult), the same
  -- primitive Phase 2's Tinted Lens/Filter family already proved out.
  ------------------------------------------------------------------
  registerPostEffectivenessModifier("wonderguard", 0, function(ctx)
    if abilityIdOf(ctx.target) ~= "WONDERGUARD" then return 1.0 end
    -- Mold Breaker/Teravolt/Turboblaze (Phase 8, other bucket; Phase 11
    -- shared primitive) -- combat/modern_combat.lua's one shared
    -- predicate, the same one abilities/engine/type_immunity.lua's own
    -- type-immunity family consults.
    if mod.exports.attackerIgnoresDefenderAbility
        and mod.exports.attackerIgnoresDefenderAbility(ctx.user) then
      return 1.0
    end
    -- Real, confirmed bug fixed 2026-08-28 (Wonder-Guard-reachability
    -- review): ctx.mult is TypeChart.effectiveness's own return value,
    -- confirmed x10-SCALED (10=neutral, 20=2x, 5=0.5x, own header:
    -- "Returns the combined x10 multiplier") -- comparing it against
    -- `1.0` meant this branch was true for literally every non-immune
    -- hit (even a 0.5x-resisted one reads as mult=5, still > 1.0),
    -- making this ability's own real core function -- "only super
    -- effective hits deal damage" -- completely non-functional since
    -- this mod first shipped it. The real neutral baseline on this
    -- scale is 10, not 1.0.
    if ctx.mult and ctx.mult > 10 then return 1.0 end
    return 0
  end)

  ------------------------------------------------------------------
  -- STURDY, BULLETPROOF/SOUNDPROOF/WINDRIDER, TELEPATHY, MAGICGUARD's
  -- move-caused half (nothing to gate there -- Magic Guard's own scope
  -- is INDIRECT damage; a move that lands normally still deals full
  -- damage to a Magic Guard holder, real confirmed rule) -- all share
  -- the same "battle.damage" wrap combat/modern_combat_protect.lua's own
  -- Protect block and combat/type_immunity.lua already use for "this hit
  -- does nothing." Priority 40, matching type_immunity.lua's own tier
  -- (below Protect's 50 -- a protected Sturdy/Bulletproof holder still
  -- goes through Protect's own block first, unaffected by this file).
  ------------------------------------------------------------------
  local FLAG_IMMUNITY = { BULLETPROOF = "bullet", SOUNDPROOF = "sound", WINDRIDER = "wind" }

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local target = ctx.target
    local user = ctx.user
    local move = ctx.move
    if not (target and move) then return next(ctx) end
    local id = abilityIdOf(target)

    -- Magic Guard, general self-hit half -- real, confirmed Showdown
    -- rule found and fixed 2026-08-28 (explicit user follow-up
    -- question, "does magic guard prevent all sources it should"):
    -- confusion self-hit is a REAL battle.damage computation
    -- (confirmed by direct read, BOTH engines -- Gen 1's own
    -- BattleState.lua self-hit code calls `self:computeDamage(user,
    -- user, ...)`, the exact same hooked function every normal hit
    -- goes through) with `user == target` -- a real, reliable, general
    -- signal for "this Pokemon is hitting itself," which is exactly
    -- the class of damage Magic Guard blocks, checked here ONCE rather
    -- than per-source. `id` above is TARGET's ability, already the
    -- right one to check for a self-hit (attacker and defender are the
    -- same mon).
    if id == "MAGICGUARD" and user and user == target then
      return 0, { crit = false, typeMult = 0 }
    end

    if id == "TELEPATHY" and user and ctx.battle and ctx.battle:sideOf(user) == ctx.battle:sideOf(target) then
      return 0, { crit = false, typeMult = 0 }
    end

    local wantFlag = id and FLAG_IMMUNITY[id]
    if wantFlag then
      local flags = moveFlags(move.id)
      -- Mold Breaker/Teravolt/Turboblaze (Phase 11): Bulletproof/
      -- Soundproof/Wind Rider are all `breakable` in Showdown, so a
      -- Mold Breaker attacker's move ignores them -- the same shared
      -- predicate type_immunity.lua/Wonder Guard use above.
      local ignored = mod.exports.attackerIgnoresDefenderAbility
        and mod.exports.attackerIgnoresDefenderAbility(user)
      if flags and flags[wantFlag] and not ignored then
        return 0, { crit = false, typeMult = 0 }
      end
    end

    if id == "STURDY" then
      -- Real bug fixed 2026-08-28, surfaced by a direct user question
      -- ("did you make sturdy immune to OHKO moves?"): this checked
      -- ONLY "OHKO_EFFECT", Gen 1's own real effect string
      -- (national_dex's own record for Fissure/Guillotine/Horn Drill:
      -- gen1Effect="OHKO_EFFECT") -- Gen 2's OWN real string for the
      -- identical move is different (gen2Effect="EFFECT_OHKO",
      -- confirmed by direct read, gen2/Battle.lua's own
      -- Battle.MOVE_EFFECTS.EFFECT_OHKO dispatch key) -- so this never
      -- matched on Gen 2 at all, a real gap present since Phase 8a and
      -- newly RELEVANT now that combat/legacy_move_takeover.lua's own
      -- centralizing fix is what makes an OHKO hit reach this check on
      -- Gen 2 in the first place.
      if move.effect == "OHKO_EFFECT" or move.effect == "EFFECT_OHKO" then
        return 0, { crit = false, typeMult = 0 }
      end
      -- Round 17: Sheer Cold (this mod's own fresh OHKO, no native effect
      -- string on either engine) is caught here via the shared
      -- info.ohko flag its own battle.damage wrap sets -- real Showdown
      -- Sturdy is `onTryHit: if (move.ohko) return null` (abilities.ts,
      -- confirmed): the OHKO is FULLY blocked (0 damage, no 1-HP save).
      -- The survive-at-1 clamp itself MOVED OUT to combat/damage_pipeline
      -- .lua (round 17): Showdown's onDamage runs at priority -30, AFTER
      -- Life Orb's onModifyDamage at 100, and this priority-40 wrap sits
      -- BELOW the pipeline (500) -- clamping here would let a Life Orb
      -- user boost the capped hp-1 back into a KO.
      local dmg, info = next(ctx)
      if info and info.ohko then
        return 0, { crit = false, typeMult = 0 }
      end
      return dmg, info
    end

    -- Disguise (Phase 7, prevent bucket): real damage-negation half only
    -- -- the first hit that would deal damage is voided entirely (0
    -- damage), tracked via a plain per-mon flag cleared on battle.ended
    -- below, same combat-only-state convention this whole ability system
    -- already uses. The COSMETIC half (Busted Form) is explicitly out of
    -- scope -- form-changing is battle_forms's own domain (this mod's
    -- own standing non-goal, PROGRESS.md's own header) -- a real,
    -- honestly-named simplification, not silently dropped: the mon just
    -- takes 0 damage on that one hit without visually changing form.
    if id == "DISGUISE" and data.DISGUISE then
      local m = hpOf(target)
      if not m.disguiseBusted then
        m.disguiseBusted = true
        return 0, { crit = false, typeMult = 0 }
      end
    end

    -- Ice Face (Phase 8, other bucket -- explicit user directive: the
    -- transformation/visual half stays out of scope, the combat effect
    -- doesn't). Real, confirmed shape, the same real damage-negation
    -- primitive Disguise already uses, with two real differences: only
    -- a PHYSICAL hit is negated (a special or status hit passes through
    -- normally, real confirmed rule), and the "used" flag resets when
    -- Snow begins (this engine's own real Gen 9 Snowscape, the
    -- confirmed replacement for old Hail -- see combat/modern_weather
    -- .lua's own header) rather than only on battle end.
    if id == "ICEFACE" and data.ICEFACE then
      local m = hpOf(target)
      local MoveCategory = mod.exports.MoveCategory
      local category = MoveCategory and MoveCategory.of(move) or "Physical"
      if not m.iceFaceBusted and category == "Physical" then
        m.iceFaceBusted = true
        return 0, { crit = false, typeMult = 0 }
      end
    end

    return next(ctx)
  end, 40)

  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs({ battle.player, battle.enemy }) do
      if mon then
        hpOf(mon).disguiseBusted = nil
        hpOf(mon).iceFaceBusted = nil
      end
    end
  end)

  -- Ice Face's own real reversion trigger: Snow being active resets a
  -- busted Ice Face back to ready. No real "weather changed" event
  -- exists anywhere in this mod to hook (confirmed by direct grep,
  -- combat/modern_weather.lua's own setWeather never emits one) -- so,
  -- same live-poll shape Protosynthesis/Quark Drive's own real
  -- persistence check already established this same phase, this checks
  -- fresh on battle.turn_started (fires every turn, both generations)
  -- rather than waiting on a discrete change event that doesn't exist.
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local currentWeather = mod.exports.currentWeather
    local isGen2Battle = mod.exports.isGen2Battle
    if not (currentWeather and isGen2Battle and currentWeather(battle, isGen2Battle(battle)) == "SNOW") then
      return
    end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and abilityIdOf(mon) == "ICEFACE" then hpOf(mon).iceFaceBusted = nil end
    end
  end)

  ------------------------------------------------------------------
  -- Status residual: Heatproof (halve burn) and Magic Guard (block
  -- poison/burn residual entirely) both patch the same two real
  -- functions Phase 6's Poison Heal already patches -- Gen 1's
  -- Status.RECORDS.PSN/BRN.residual and Gen 2's Battle.STATUSES.
  -- poison/toxic/burn.residual. Each layer captures whatever the
  -- PREVIOUS layer left behind as its own "native" and delegates when
  -- its own ability isn't present, so this composes correctly with
  -- Poison Heal regardless of which loaded first -- Magic Guard is
  -- wrapped LAST (outermost), so it's checked first and unconditionally
  -- wins over either.
  --
  -- Gen 1's own residual functions MUTATE mon.hp directly and return
  -- messages, not a damage number (confirmed by direct read of Status
  -- .lua's damageOverTime) -- Heatproof's own halving here uses the
  -- same "apply then correct" pattern combat/boss_fight_status.lua's
  -- antiDrain already established for exactly this shape, rather than
  -- re-deriving the native damage formula a second time. Gen 2's own
  -- residual functions are pure (return a number, Battle:tickStatus
  -- applies it) -- confirmed by direct read -- so Heatproof there is a
  -- plain halve of the returned number, no correction needed.
  ------------------------------------------------------------------
  local Status = require("src.battle.Status")
  -- Gen 2's own STATUSES table is needed only for the two Gen-2 residual
  -- patches below; a Gen 1 game refuses src.battle.gen2.Battle outright
  -- (crossGenerationDenial), so the require is guarded and every Gen-2-only
  -- patch below is skipped rather than failing this whole ability file.
  local gen2ok, Battle = pcall(require, "src.battle.gen2.Battle")

  -- Heatproof is burn-specific (confirmed real, its own effect never
  -- mentions poison) -- no poison-residual wrap needed for it at all,
  -- only Magic Guard's own PSN wrap further below.
  local nativeBrn = Status.RECORDS.BRN.residual
  Status.RECORDS.BRN.residual = function(battler, opponent, battle)
    local hpBefore = hpOf(battler).hp
    local msgs = nativeBrn(battler, opponent, battle)
    if abilityIdOf(battler) == "HEATPROOF" then
      local m = hpOf(battler)
      local dealt = hpBefore - (m.hp or 0)
      if dealt > 0 then
        local maxHp = m.stats and m.stats.hp
        m.hp = math.min(maxHp or m.hp, (m.hp or 0) + math.floor(dealt / 2))
      end
    end
    return msgs
  end

  local function patchGen2BurnResidual()
    if not (gen2ok and type(Battle) == "table") then return end
    local record = Battle.STATUSES.burn
    if not record then return end
    local native = record.residual
    record.residual = function(battle, mon, maxHp)
      local dmg, text = native(battle, mon, maxHp)
      if abilityIdOf(mon) == "HEATPROOF" and dmg then
        dmg = math.max(1, math.floor(dmg / 2))
      end
      return dmg, text
    end
  end
  patchGen2BurnResidual()

  -- Magic Guard, wrapped LAST (outermost) -- unconditional block of
  -- whatever's already there when present.
  local magicGuardPsn = Status.RECORDS.PSN.residual
  Status.RECORDS.PSN.residual = function(battler, opponent, battle)
    if abilityIdOf(battler) == "MAGICGUARD" then return {} end
    return magicGuardPsn(battler, opponent, battle)
  end
  local magicGuardBrn = Status.RECORDS.BRN.residual
  Status.RECORDS.BRN.residual = function(battler, opponent, battle)
    if abilityIdOf(battler) == "MAGICGUARD" then return {} end
    return magicGuardBrn(battler, opponent, battle)
  end
  local function magicGuardGen2(statusKey)
    if not (gen2ok and type(Battle) == "table") then return end
    local record = Battle.STATUSES[statusKey]
    if not record then return end
    local native = record.residual
    record.residual = function(battle, mon, maxHp)
      if abilityIdOf(mon) == "MAGICGUARD" then return 0 end
      return native(battle, mon, maxHp)
    end
  end
  magicGuardGen2("poison")
  magicGuardGen2("toxic")
  magicGuardGen2("burn")

  ------------------------------------------------------------------
  -- Magic Guard, recoil half -- real, confirmed Showdown rule, fixed
  -- 2026-08-28 (explicit user follow-up question). Gen 1 only: recoil's
  -- own real native record (RECOIL_EFFECT.afterDamage) is a real,
  -- monkeypatchable field on a standalone table, same shape every other
  -- native record this mod already patches. Gen 2's own recoil
  -- (confirmed by direct read, gen2/Battle.lua) is a plain inline
  -- mutation (`attacker.hp = math.max(0, attacker.hp - recoil)`) deep
  -- inside the same massive Battle:useMove this session's own Sheer
  -- Cold/Dancer/Magic Bounce work already established has no clean
  -- extension point -- a real, honestly-flagged, NOT-fixed-this-pass
  -- gap on that one generation specifically, not a guess shipped under
  -- time pressure.
  ------------------------------------------------------------------
  local MoveEffects = require("src.battle.MoveEffects")
  local recoilRecord = MoveEffects.full and MoveEffects.full.RECOIL_EFFECT
  if recoilRecord then
    local nativeRecoil = recoilRecord.afterDamage
    recoilRecord.afterDamage = function(ctx)
      if abilityIdOf(ctx.user) == "MAGICGUARD" then return end
      return nativeRecoil(ctx)
    end
  end

  ------------------------------------------------------------------
  -- Magic Guard, entry-hazard half -- real, confirmed Showdown rule,
  -- fixed 2026-08-28. combat/modern_hazards.lua's own Stealth Rock/
  -- Sharp Steel damage and Gen 2's own native Battle:spikesDamage
  -- override (that same file's own real "Native Spikes upgrade") both
  -- had ability identity available at their own real HP-mutation point
  -- already -- Magic Guard was simply never checked there. Exported
  -- here as one small, reusable predicate rather than duplicating the
  -- ability check in a second file.
  ------------------------------------------------------------------
  mod.exports.magicGuardBlocksHazard = function(mon)
    return abilityIdOf(mon) == "MAGICGUARD"
  end

  -- Gen 2's own sand-chip half (Phase 11). Magic Guard -- and, matching
  -- the Gen 1 path in combat/modern_weather.lua, the real Sand Force/
  -- Sand Rush/Sand Veil/Overcoat family -- block weather chip damage.
  -- The old note here called this unfixable without replacing
  -- Battle:tickWeather because Effects.sandstormDamage(maxHp) carries no
  -- mon identity; this IS that replacement, faithfully reproducing the
  -- native function (gen2/Battle.lua:5066-5097 -- duration decrement,
  -- expiry, per-turn text, the sand pass with its vanished skip and its
  -- damage/animation events) and adding exactly ONE gate: skip the chip
  -- for a mon whose ability is in SAND_CHIP_IMMUNE_ABILITY. The fraction
  -- still comes from Gen2Effects.sandstormDamage, so
  -- combat/modern_weather.lua's own 1/8 -> 1/16 patch (installed later
  -- in the boot, but read lazily here at call time) still applies.
  local Strings = require("src.core.Strings")
  local gen2EffectsOk, Gen2Effects = pcall(require, "src.battle.gen2.Effects")
  Gen2Effects = gen2EffectsOk and Gen2Effects or {}
  local SAND_CHIP_IMMUNE_ABILITY = {
    SANDFORCE = true, SANDRUSH = true, SANDVEIL = true, MAGICGUARD = true,
    OVERCOAT = true,
  }
  local nativeTickWeather = Battle and Battle.tickWeather
  if not (gen2ok and type(Battle) == "table" and type(nativeTickWeather) == "function") then
    nativeTickWeather = nil
  end
  if nativeTickWeather then
  function Battle:tickWeather()
    -- Every non-sand weather path is delegated straight to the engine's
    -- own untouched function -- only the sand case this gate exists for
    -- is reproduced below.
    if self.weather ~= "sandstorm" then return nativeTickWeather(self) end
    self.weatherTurns = self.weatherTurns - 1
    if self.weatherTurns <= 0 then
      self:emit({ kind = "weather", weather = nil,
        text = Strings(Gen2Effects.WEATHER_END_TEXT[self.weather]) })
      self.weather = nil
      return
    end
    self:emit({ kind = "message",
      text = Strings(Gen2Effects.WEATHER_TURN_TEXT[self.weather]) })
    for _, mon in ipairs({ self.player, self.enemy }) do
      if (mon.hp or 0) > 0 and not self:volatile(mon).vanished then
        local def = self:speciesDef(mon)
        local types = (def and def.types) or mon.types
        if Gen2Effects.sandstormHits(types)
            and not SAND_CHIP_IMMUNE_ABILITY[abilityIdOf(mon)] then
          local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 8
          local damage = Gen2Effects.sandstormDamage(maxHp)
          mon.hp = math.max(0, mon.hp - damage)
          self:emit({ kind = "message",
            text = Strings("%s is buffeted by the sandstorm!",
              self:monName(mon)) })
          -- .SandstormDamage plays ANIM_IN_SANDSTORM between two
          -- SwitchTurnCore calls, so it runs from the OTHER side.
          self:emit({ kind = "damage", side = self:sideOf(mon),
            amount = damage, hp = mon.hp, anim = "ANIM_IN_SANDSTORM" })
        end
      end
    end
  end
  end

  mod.log:info("g9-battle-engine: damage_immunity installed (STURDY, WONDERGUARD, BULLETPROOF, SOUNDPROOF, WINDRIDER, TELEPATHY, MAGICGUARD, HEATPROOF; MAGICGUARD/SANDFORCE/SANDRUSH/SANDVEIL/OVERCOAT Gen 2 sand-chip gate via Battle:tickWeather)")
end
