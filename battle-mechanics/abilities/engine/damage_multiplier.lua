-- Dispatch engine for abilities/data/damage_multiplier.lua -- Phase 2:
-- damage_dealt_multiplier/damage_taken_multiplier abilities, wired onto
-- combat/modern_combat.lua's own registerDamageModifier (pre-
-- effectiveness) and its new companion registerPostEffectivenessModifier
-- (for the handful that need the REAL, final type multiplier -- see that
-- export's own header for why registerDamageModifier can't express those
-- at all). Every factor/moveType read live from abilityBehaviorOf, never
-- copied into this mod's own data -- same discipline every prior phase
-- already established.
--
-- Still deferred (see abilities/data/damage_multiplier.lua's own header
-- for the exact reasons): Aerilate/Pixilate/Galvanize/Refrigerate (need
-- a move-type override primitive this mod doesn't have). Electromorphosis/
-- Wind Power/Hustle/Fur Coat/Ice Scales/Stakeout/Sheer Force are built
-- below (Sheer Force and Hustle each only half -- see their own
-- sections). Battery/Power Spot/Friend Guard/Steely Spirit (ally-scope)
-- are also built below, un-deferred 2026-08-28 once requestAdjacency's
-- own real .allies list existed. Phase 14 close-out: FLUFFY/ANALYTIC/
-- FLASHFIRE's boost half are built below too (Flash Fire was formerly
-- in the deferred list above -- its immunity half is built in
-- abilities/engine/absorb.lua, the charge flag it sets is read here).
--
-- MOVE FLAGS -- confirmed real and live (2026-08-27): national_dex's own
-- move-flags data (data/moves/generated/flags.lua, sourced directly from
-- Showdown's own moves.json) is real and reachable through the PROPER
-- api surface, mod.exports.moveFlags(id) -- a SEPARATE lookup from
-- moveById, NOT a field on its reply (src/api.lua's own header: "the two
-- payloads have different owners" -- moveById reads the PokeAPI-sourced
-- sharded tree, moveFlags reads Showdown's own flags file, either can be
-- rebuilt without the other). Returns the flag SET directly
-- ({contact=true, punch=true, ...}), never nested under a `.flags` key --
-- confirmed against real records (Bullet Punch/Comet Punch: punch=true;
-- Crunch: bite=true; Aura Sphere: pulse=true; Sacred Sword: slicing=true)
-- before wiring any of this. Iron Fist, Mega Launcher, Strong Jaw,
-- Sharpness, and Tough Claws are ALL real now, reading this live, no
-- placeholder left for any of them.
--
-- Reckless's recoil half was never placeholder (negative `drain`, same
-- signed field draining moves use positive -- Brave Bird: drain = -33).
-- Its crash-damage half (Jump Kick/High Jump Kick -- damage on a MISS,
-- not a landed hit) genuinely has NO flag in Showdown's own real
-- vocabulary either -- confirmed directly: High Jump Kick's own live
-- flags record is {contact=true, gravity=true, metronome=true,
-- mirror=true, protect=true}, no crash-shaped entry at all. Showdown
-- itself special-cases these two moves by id rather than a flag, so this
-- file does the same -- a fixed, tiny, real list, not a guess standing
-- in for missing data.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local registerDamageModifier = mod.exports.registerDamageModifier
  local registerPostEffectivenessModifier = mod.exports.registerPostEffectivenessModifier
  local curTypesOf = mod.exports.curTypesOf
  local currentWeather = mod.exports.currentWeather
  local isGen2Battle = mod.exports.isGen2Battle
  local requestAdjacency = mod.exports.requestAdjacency
  assert(abilityIdOf and abilityBehaviorOf and registerDamageModifier
      and registerPostEffectivenessModifier and curTypesOf and currentWeather
      and isGen2Battle and requestAdjacency,
    "damage_multiplier: modern_combat.lua, move_targeting.lua, and ability_dispatch.lua must load first")

  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById
      and nationalDex.exports.moveFlags,
    "damage_multiplier: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local moveFlags = nationalDex.exports.moveFlags

  -- All of this ability's effects (a flat array, since a few -- Sand
  -- Force's three types, Water Bubble's two-directional pair, Thick
  -- Fat's two types -- carry more than one damage_*_multiplier entry).
  -- Filtered to the requested kind only; nil if the mon has no id, isn't
  -- in this phase's inclusion list, or has none of that kind.
  local function multiplierEffects(mon, kind)
    if not mon then return nil end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return nil end
    local record = abilityBehaviorOf(mon)
    local effects = record and record.behaviour and record.behaviour.effects
    if not effects then return nil end
    local out
    for _, effect in ipairs(effects) do
      if effect.kind == kind then
        out = out or {}
        out[#out + 1] = effect
      end
    end
    return out
  end

  local function hpFractionAtOrBelow(mon, num, den)
    local hp = mon.hp or 0
    local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or hp
    return maxHp > 0 and hp * den <= maxHp * num
  end

  local function atFullHp(mon)
    local hp = mon.hp or 0
    local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or hp
    return maxHp > 0 and hp >= maxHp
  end

  ------------------------------------------------------------------
  -- Flat/HP-gated type multipliers, damage DEALT (Steelworker, Rocky
  -- Payload, Transistor, Fire Mane, Dragon's Maw -- always on; Blaze,
  -- Overgrow, Torrent, Swarm -- HP at or below 1/3; Water Bubble's own
  -- Water-boost half). One shared handler: every one of these is
  -- "factor when move.type == effect.moveType [and this HP condition]",
  -- read entirely from the matching live effect entry.
  ------------------------------------------------------------------
  local HP_GATED = { BLAZE = true, OVERGROW = true, TORRENT = true, SWARM = true }

  registerDamageModifier("ability_type_boost_dealt", 90, function(ctx)
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    if not effects then return 1.0 end
    local id = abilityIdOf(ctx.user)
    if HP_GATED[id] and not hpFractionAtOrBelow(ctx.user, 1, 3) then return 1.0 end
    for _, effect in ipairs(effects) do
      if effect.moveType and effect.moveType:upper() == ctx.move.type and effect.factor then
        return effect.factor
      end
    end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- Flat type multipliers, damage TAKEN (Thick Fat's two types,
  -- Purifying Salt's Ghost half, Water Bubble's Fire-taken half).
  ------------------------------------------------------------------
  registerDamageModifier("ability_type_boost_taken", 90, function(ctx)
    local effects = multiplierEffects(ctx.target, "damage_taken_multiplier")
    if not effects then return 1.0 end
    for _, effect in ipairs(effects) do
      if effect.moveType and effect.moveType:upper() == ctx.move.type and effect.factor then
        return effect.factor
      end
    end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- Full-HP-gated flat multipliers, damage TAKEN (Multiscale, Shadow
  -- Shield -- both "0.5x while at full HP", no moveType filter).
  ------------------------------------------------------------------
  registerDamageModifier("ability_full_hp_taken", 90, function(ctx)
    local effects = multiplierEffects(ctx.target, "damage_taken_multiplier")
    if not effects then return 1.0 end
    if not atFullHp(ctx.target) then return 1.0 end
    for _, effect in ipairs(effects) do
      if not effect.moveType and effect.factor then return effect.factor end
    end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- Technician: 1.5x when the move's own base power is 60 or less.
  -- Reads the factor live (Technician's own effect entry), the
  -- threshold is real Showdown data, not this mod's own guess.
  ------------------------------------------------------------------
  registerDamageModifier("technician", 90, function(ctx)
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    if not effects then return 1.0 end
    if abilityIdOf(ctx.user) ~= "TECHNICIAN" then return 1.0 end
    if (ctx.move.power or 0) > 60 then return 1.0 end
    return effects[1] and effects[1].factor or 1.0
  end)

  ------------------------------------------------------------------
  -- Sand Force: 1.3x Rock/Ground/Steel moves while a sandstorm is up.
  -- (The separate "immune to sandstorm chip damage" half of this
  -- ability is kind="other" -- not a damage multiplier, out of this
  -- phase's scope, not silently dropped.)
  ------------------------------------------------------------------
  registerDamageModifier("sand_force", 90, function(ctx)
    if abilityIdOf(ctx.user) ~= "SANDFORCE" then return 1.0 end
    if currentWeather(ctx.battle, ctx.gen2) ~= "SAND" then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    if not effects then return 1.0 end
    for _, effect in ipairs(effects) do
      if effect.moveType and effect.moveType:upper() == ctx.move.type and effect.factor then
        return effect.factor
      end
    end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- Dark Aura / Fairy Aura: field-wide -- boosts EVERY Dark/Fairy move
  -- used by EITHER battler, as long as the aura-holder is somewhere on
  -- the field (which in this 2-battler engine just means "is either
  -- battle.player or battle.enemy"), not gated on the aura-holder being
  -- the one attacking.
  ------------------------------------------------------------------
  local function fieldAuraFactor(battle, moveType)
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon then
        local effects = multiplierEffects(mon, "damage_dealt_multiplier")
        if effects then
          for _, effect in ipairs(effects) do
            if effect.moveType and effect.moveType:upper() == moveType and effect.factor then
              return effect.factor
            end
          end
        end
      end
    end
    return nil
  end

  -- Aura Break (Phase 8, other bucket): a real, confirmed gap this file
  -- left open until now -- fieldAuraFactor above applies Dark Aura/Fairy
  -- Aura's own boost unconditionally, never checking for Aura Break's
  -- real "flips a would-be-boosted aura move to a 2/3 REDUCTION instead"
  -- effect anywhere. Scoped to the exact real rule: only flips a move
  -- that an aura would ACTUALLY have boosted (fieldAuraFactor found a
  -- real factor) -- Aura Break does nothing to a move no aura touches.
  local function auraBreakActive(battle)
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and abilityIdOf(mon) == "AURABREAK" then return true end
    end
    return false
  end

  registerDamageModifier("field_aura", 90, function(ctx)
    local factor = fieldAuraFactor(ctx.battle, ctx.move.type)
    if not factor then return 1.0 end
    if auraBreakActive(ctx.battle) then return 2 / 3 end
    return factor
  end)

  ------------------------------------------------------------------
  -- Battery / Power Spot / Friend Guard / Steely Spirit -- real ally-
  -- scope multipliers, un-deferred now that requestAdjacency's own real
  -- ally list exists (this file's own header used to mark all four as
  -- blocked pending a future multi-battler mod that has since landed --
  -- stale, fixed here rather than left standing).
  --
  -- Battery: real Showdown scope is narrower than this record's own
  -- generic effect text ("Ally Pokémon's moves") states -- confirmed
  -- against Showdown's own source, Special-category moves only. Applied
  -- here even though the structured `factor`/`kind` fields alone don't
  -- carry that restriction, per this project's own standing rule that
  -- Showdown's real source wins over an imprecise dex-text summary.
  -- Power Spot: same 1.3x, no category restriction, real and confirmed.
  -- Neither affects the holder's own moves (both real texts explicit).
  ------------------------------------------------------------------
  registerDamageModifier("battery_powerspot", 90, function(ctx)
    local mult = 1.0
    for _, ally in ipairs(requestAdjacency(ctx.battle, ctx.user, nil).allies) do
      local id = abilityIdOf(ally)
      if id == "BATTERY" and data.BATTERY and ctx.category == "Special" then
        local effects = multiplierEffects(ally, "damage_dealt_multiplier")
        if effects and effects[1] and effects[1].factor then mult = mult * effects[1].factor end
      elseif id == "POWERSPOT" and data.POWERSPOT then
        local effects = multiplierEffects(ally, "damage_dealt_multiplier")
        if effects and effects[1] and effects[1].factor then mult = mult * effects[1].factor end
      end
    end
    return mult
  end)

  -- Friend Guard -- damage TAKEN, real confirmed stacking (national_dex's
  -- own notes: "stacks if multiple allied Pokémon have it"), so every
  -- qualifying ally multiplies in, not just the first match.
  registerDamageModifier("friendguard", 90, function(ctx)
    if not data.FRIENDGUARD then return 1.0 end
    local mult = 1.0
    for _, ally in ipairs(requestAdjacency(ctx.battle, ctx.target, nil).allies) do
      if abilityIdOf(ally) == "FRIENDGUARD" then
        local effects = multiplierEffects(ally, "damage_taken_multiplier")
        if effects and effects[1] and effects[1].factor then mult = mult * effects[1].factor end
      end
    end
    return mult
  end)

  -- Steely Spirit -- unlike Battery/Power Spot, real text is explicit
  -- this boosts the HOLDER's own Steel moves too ("the Pokémon AND its
  -- allies"), and real Showdown confirms it stacks across multiple
  -- holders on the same side.
  registerDamageModifier("steelyspirit", 90, function(ctx)
    if not (data.STEELYSPIRIT and ctx.move.type == "STEEL") then return 1.0 end
    local mult = 1.0
    local roster = { ctx.user }
    for _, ally in ipairs(requestAdjacency(ctx.battle, ctx.user, nil).allies) do
      roster[#roster + 1] = ally
    end
    for _, mon in ipairs(roster) do
      if abilityIdOf(mon) == "STEELYSPIRIT" then
        local effects = multiplierEffects(mon, "damage_dealt_multiplier")
        for _, effect in ipairs(effects or {}) do
          if effect.moveType and effect.moveType:upper() == "STEEL" and effect.factor then
            mult = mult * effect.factor
          end
        end
      end
    end
    return mult
  end)

  ------------------------------------------------------------------
  -- Rivalry: 1.25x against a same-gender target, 0.75x against an
  -- opposite-gender one, no effect if either is genderless (mon.gender
  -- nil).
  ------------------------------------------------------------------
  registerDamageModifier("rivalry", 90, function(ctx)
    if abilityIdOf(ctx.user) ~= "RIVALRY" then return 1.0 end
    local userGender, targetGender = ctx.user.gender, ctx.target.gender
    if not (userGender and targetGender) then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    if not effects then return 1.0 end
    local same = userGender == targetGender
    for _, effect in ipairs(effects) do
      local wantsSame = effect.when and effect.when:find("same gender") ~= nil
      if wantsSame == same and effect.factor then return effect.factor end
    end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- Move-flag abilities (Iron Fist, Mega Launcher, Strong Jaw, Sharpness,
  -- Tough Claws) -- real and live, see this file's own header. Reads the
  -- move's own flag SET via the proper moveFlags(id) export, never
  -- moveById's own reply (a different payload entirely).
  ------------------------------------------------------------------
  local FLAG_ABILITY = {
    IRONFIST = "punch", MEGALAUNCHER = "pulse", STRONGJAW = "bite",
    SHARPNESS = "slicing", TOUGHCLAWS = "contact",
  }

  registerDamageModifier("ability_move_flag", 90, function(ctx)
    local id = abilityIdOf(ctx.user)
    local flagName = id and FLAG_ABILITY[id]
    if not flagName then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    if not effects then return 1.0 end
    local flags = moveFlags(ctx.move.id)
    if not (flags and flags[flagName]) then return 1.0 end
    return effects[1] and effects[1].factor or 1.0
  end)

  -- Reckless: two real move properties, neither placeholder. Recoil is a
  -- negative `drain` value (confirmed, Brave Bird: drain = -33 -- same
  -- signed axis draining moves use positive). Crash damage (Jump Kick/
  -- High Jump Kick -- damage on a MISS, not a landed hit) has no flag in
  -- Showdown's own real vocabulary at all (confirmed: High Jump Kick's
  -- live flags are {contact=true, gravity=true, metronome=true,
  -- mirror=true, protect=true}, nothing crash-shaped) -- Showdown itself
  -- special-cases these two moves by id rather than a flag, so this does
  -- the same: a fixed, tiny, real list, not a stand-in for missing data.
  -- Supercell Slam (Phase 18, missing-effects plan) joined this list the
  -- same way: Showdown marks it `hasCrashDamage: true` (moves.ts:18446),
  -- which is exactly the flag the Reckless damage boost is defined over.
  -- Its own crash-on-miss self-damage is still a documented gap (no
  -- "the move missed" event reaches a mod -- see combat/
  -- modern_guard_contact.lua's honest-partials note), but the boost half
  -- is real and now applies.
  local CRASH_DAMAGE_MOVES = { JUMPKICK = true, HIGHJUMPKICK = true, SUPERCELSLAM = true }

  registerDamageModifier("reckless", 90, function(ctx)
    if abilityIdOf(ctx.user) ~= "RECKLESS" then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    if not effects then return 1.0 end
    local moveInfo = moveById(ctx.move.id)
    local hasRecoil = moveInfo and (moveInfo.drain or 0) < 0
    local hasCrash = CRASH_DAMAGE_MOVES[ctx.move.id] == true
    if not (hasRecoil or hasCrash) then return 1.0 end
    return effects[1] and effects[1].factor or 1.0
  end)

  ------------------------------------------------------------------
  -- Effectiveness-tier abilities: Neuroforce/Tinted Lens (dealt),
  -- Filter/Solid Rock/Prism Armor (taken) -- need the REAL, final type
  -- multiplier, which registerDamageModifier can never see (it runs
  -- before that multiplier is computed at all). See modern_combat.lua's
  -- own registerPostEffectivenessModifier header for the full grounding.
  ------------------------------------------------------------------
  -- Real, confirmed bug fixed 2026-08-28 (Wonder-Guard-reachability
  -- review): ctx.mult is TypeChart.effectiveness's own x10-scaled return
  -- value (10=neutral, 20=2x, 5=0.5x -- see combat/modern_combat.lua's
  -- own require("src.battle.TypeChart") and that module's own header).
  -- All three checks below compared it against a 0..1-scaled `1.0`
  -- instead -- Neuroforce/Filter-family's `> 1.0` was true for every
  -- non-immune hit (a 0.5x-resisted hit reads mult=5, still > 1.0), so
  -- both fired on EVERY hit instead of only super-effective ones;
  -- Tinted Lens's `< 1.0` was FALSE for every real not-very-effective
  -- hit (the smallest real non-zero value on this scale is 2, from a
  -- quad-resist, never below 1.0), so it never fired at all. All three
  -- abilities' own real core function was broken since this mod first
  -- shipped them, not just unreachable for the newly-centralized
  -- fixed-damage moves this review started from.
  registerPostEffectivenessModifier("neuroforce", 0, function(ctx)
    if abilityIdOf(ctx.user) ~= "NEUROFORCE" then return 1.0 end
    if not (ctx.mult and ctx.mult > 10) then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  registerPostEffectivenessModifier("tinted_lens", 0, function(ctx)
    if abilityIdOf(ctx.user) ~= "TINTEDLENS" then return 1.0 end
    if not (ctx.mult and ctx.mult > 0 and ctx.mult < 10) then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  local TAKEN_SUPER_EFFECTIVE = { FILTER = true, SOLIDROCK = true, PRISMARMOR = true }

  registerPostEffectivenessModifier("resist_super_effective_taken", 0, function(ctx)
    local id = abilityIdOf(ctx.target)
    if not (id and TAKEN_SUPER_EFFECTIVE[id]) then return 1.0 end
    if not (ctx.mult and ctx.mult > 10) then return 1.0 end
    local effects = multiplierEffects(ctx.target, "damage_taken_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  ------------------------------------------------------------------
  -- Phase 2 continued (2026-08-27) -- abilities re-scoped from
  -- "deferred" to "buildable" now that the real move-flags data landed
  -- and a category check turned out to already be available:
  --
  -- Hustle/Fur Coat/Ice Scales -- all three were deferred believing no
  -- physical/special filter existed anywhere in this pipeline. Wrong,
  -- caught on review: registerDamageModifier's own ctx already carries
  -- `category` ("Physical"/"Special", MoveCategory.of's own convention,
  -- confirmed directly against modern_combat.lua:928), it just hadn't
  -- been read by anything in this file yet. Hustle's damage half is
  -- built here; its OTHER half (0.8x accuracy on physical moves) is a
  -- genuinely different hook (an accuracy-modifier chain) this mod
  -- doesn't have yet -- Phase 6 territory (accuracy_multiplier), not
  -- silently completed alongside the damage half.
  ------------------------------------------------------------------
  registerDamageModifier("category_filtered_taken", 90, function(ctx)
    local id = abilityIdOf(ctx.target)
    if id ~= "FURCOAT" and id ~= "ICESCALES" then return 1.0 end
    local wantCategory = id == "FURCOAT" and "Physical" or "Special"
    if ctx.category ~= wantCategory then return 1.0 end
    local effects = multiplierEffects(ctx.target, "damage_taken_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  registerDamageModifier("hustle_damage_half", 90, function(ctx)
    if abilityIdOf(ctx.user) ~= "HUSTLE" then return 1.0 end
    if ctx.category ~= "Physical" then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  ------------------------------------------------------------------
  -- Electromorphosis / Wind Power: charged by being hit (Electromorphosis
  -- by anything; Wind Power only by a wind-flagged move, confirmed real:
  -- Aeroblast/Air Cutter/Icy Wind all carry wind=true), consumed by the
  -- next Electric-type move the charged mon uses -- a real, one-shot
  -- state, not a standing multiplier, so it's tracked as a volatile flag
  -- (same dual-engine field convention main.lua's own flinch handler
  -- already uses: battle:volatile(mon) on Gen 2, a plain mon field on
  -- Gen 1) rather than expressed through the effect data itself.
  ------------------------------------------------------------------
  local CHARGE_ON_HIT = { ELECTROMORPHOSIS = true, WINDPOWER = true }

  local function setCharged(battle, mon)
    if isGen2Battle and isGen2Battle(battle) then
      battle:volatile(mon).electroCharge = true
    else
      mon.electroCharge = true
    end
  end
  local function isCharged(battle, mon)
    if isGen2Battle and isGen2Battle(battle) then
      return battle:volatile(mon).electroCharge == true
    end
    return mon.electroCharge == true
  end
  local function clearCharged(battle, mon)
    if isGen2Battle and isGen2Battle(battle) then
      battle:volatile(mon).electroCharge = nil
    else
      mon.electroCharge = nil
    end
  end

  mod.events:on("battle.damage_dealt", function(ev)
    local battle, target = ev and ev.battle, ev and ev.target
    if not (battle and target and (target.hp or 0) > 0) then return end
    local id = abilityIdOf(target)
    if not (id and CHARGE_ON_HIT[id]) then return end
    if id == "WINDPOWER" then
      local moveId = ev.move and ev.move.id or ev.moveId
      local flags = moveId and moveFlags(moveId)
      if not (flags and flags.wind) then return end
    end
    setCharged(battle, target)
  end)

  registerDamageModifier("electric_charge", 90, function(ctx)
    local id = abilityIdOf(ctx.user)
    if not (id and CHARGE_ON_HIT[id]) then return 1.0 end
    if ctx.move.type ~= "ELECTRIC" then return 1.0 end
    if not isCharged(ctx.battle, ctx.user) then return 1.0 end
    clearCharged(ctx.battle, ctx.user)
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  ------------------------------------------------------------------
  -- Stakeout: 2x against a target that switched in THIS turn. Tracked
  -- the same way -- set on switch-in, cleared at the next real
  -- battle.turn_started (not battle.turn_ended: a mon switching in
  -- mid-turn after a KO must still count for the REST of that same
  -- turn's remaining hits, and turn_started for the NEXT turn is the
  -- correct clear point regardless of when during the current turn the
  -- switch actually happened).
  ------------------------------------------------------------------
  local function setSwitchedInThisTurn(battle, mon)
    if isGen2Battle and isGen2Battle(battle) then
      battle:volatile(mon).switchedInThisTurn = true
    else
      mon.switchedInThisTurn = true
    end
  end

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    if battle.player then setSwitchedInThisTurn(battle, battle.player) end
    if battle.enemy then setSwitchedInThisTurn(battle, battle.enemy) end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local battle, mon = ev and ev.battle, ev and ev.battler
    if battle and mon then setSwitchedInThisTurn(battle, mon) end
  end)
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon then
        if isGen2Battle and isGen2Battle(battle) then
          battle:volatile(mon).switchedInThisTurn = nil
        else
          mon.switchedInThisTurn = nil
        end
      end
    end
  end)

  registerDamageModifier("stakeout", 90, function(ctx)
    if abilityIdOf(ctx.user) ~= "STAKEOUT" then return 1.0 end
    local switchedIn
    if isGen2Battle and isGen2Battle(ctx.battle) then
      switchedIn = ctx.battle:volatile(ctx.target).switchedInThisTurn == true
    else
      switchedIn = ctx.target.switchedInThisTurn == true
    end
    if not switchedIn then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  ------------------------------------------------------------------
  -- Sheer Force: damage half only HERE. 1.3x whenever the move used
  -- has a real chance-based secondary effect, read live off
  -- national_dex's own moveById (ailmentChance/statChance/flinchChance
  -- > 0 -- confirmed these are exactly what the ability's own real
  -- effect text describes as "an effect chance," not guessed). The
  -- OTHER half -- Sheer Force also REMOVES that secondary effect --
  -- lives in main.lua's own generic secondary listener
  -- (installMovepoolEffects): `secondarySuppressed` nils the
  -- flinch/confuse/ailment/stat-chance pool whenever the attacker is a
  -- Sheer Force holder (or the defender is Shield Dust), which IS the
  -- exact definition of "secondary effect" for every move that reaches
  -- that listener. So both halves are built; this file owns only the
  -- power half, and the two are deliberately split by which primitive
  -- they edit (the damage chain vs. the secondary-application site).
  ------------------------------------------------------------------
  registerDamageModifier("sheer_force_damage_half", 90, function(ctx)
    if abilityIdOf(ctx.user) ~= "SHEERFORCE" then return 1.0 end
    local moveInfo = moveById(ctx.move.id)
    if not moveInfo then return 1.0 end
    local hasChanceEffect = (moveInfo.ailmentChance or 0) > 0
      or (moveInfo.statChance or 0) > 0 or (moveInfo.flinchChance or 0) > 0
    if not hasChanceEffect then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  ------------------------------------------------------------------
  -- FLUFFY (Phase 14): damage TAKEN -- 0.5x from contact moves, 2x
  -- from Fire moves. Both factors are real structured entries (read
  -- live via multiplierEffects), only the two CONDITIONS are this
  -- file's own: contact (the mod's own makesContact primitive, so a
  -- Long Reach attacker is correctly not halved -- looked up lazily at
  -- dispatch time, not captured at install, since long_reach.lua loads
  -- later in main.lua's boot sequence than this file) and Fire type.
  ------------------------------------------------------------------
  registerDamageModifier("fluffy", 90, function(ctx)
    local id = abilityIdOf(ctx.target)
    if not (id and data.FLUFFY and id == "FLUFFY") then return 1.0 end
    local effects = multiplierEffects(ctx.target, "damage_taken_multiplier")
    if not effects then return 1.0 end
    local mult = 1.0
    for _, effect in ipairs(effects) do
      if effect.moveType and effect.moveType:upper() == ctx.move.type and effect.factor then
        mult = mult * effect.factor
      elseif not effect.moveType and effect.factor and ctx.move.id
          and mod.exports.makesContact and mod.exports.makesContact(ctx.move.id, ctx.user) then
        mult = mult * effect.factor
      end
    end
    return mult
  end)

  ------------------------------------------------------------------
  -- ANALYTIC (Phase 14): 1.3x when this Pokémon moves last in the
  -- turn. Tracked via battle.move_used (fires just before each move
  -- resolves, so by the time this mon's own move is being resolved the
  -- flag is set for every mon that already acted this turn): cleared
  -- for all actives at battle.turn_started, set on move_used. The
  -- boost applies iff EVERY other active has already moved -- i.e. the
  -- user is acting last. Real Showdown exclusion (Future Sight / Doom
  -- Desire never boost) is NOT modeled -- those moves in this mod
  -- resolve outside the normal damage pipeline, so they are simply
  -- never seen by this modifier; documented, not silently completed.
  ------------------------------------------------------------------
  local function movedThisTurn(battle, mon)
    if isGen2Battle and isGen2Battle(battle) then
      return battle:volatile(mon).movedThisTurn == true
    end
    return mon.movedThisTurn == true
  end
  mod.events:on("battle.move_used", function(ev)
    local battle, user = ev and ev.battle, ev and ev.user
    if not (battle and user) then return end
    if isGen2Battle and isGen2Battle(battle) then
      battle:volatile(user).movedThisTurn = true
    else
      user.movedThisTurn = true
    end
  end)
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon then
        if isGen2Battle and isGen2Battle(battle) then
          battle:volatile(mon).movedThisTurn = nil
        else
          mon.movedThisTurn = nil
        end
      end
    end
  end)
  registerDamageModifier("analytic", 90, function(ctx)
    local id = abilityIdOf(ctx.user)
    if not (id and data.ANALYTIC and id == "ANALYTIC") then return 1.0 end
    for _, other in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(ctx.battle) or { ctx.battle.player, ctx.battle.enemy }) do
      if other and other ~= ctx.user and movedThisTurn(ctx.battle, other) == false then
        return 1.0
      end
    end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    return (effects and effects[1] and effects[1].factor) or 1.0
  end)

  ------------------------------------------------------------------
  -- FLASHFIRE boost half (Phase 14): 1.5x Fire moves after being hit
  -- by a Fire move. The immunity half and the charge flag itself live
  -- in abilities/engine/absorb.lua (battle:volatile(mon).flashFire-
  -- Charged on Gen 2, mon.flashFireCharged on Gen 1), which also
  -- clears the charge when the holder leaves the field -- the real
  -- "until it leaves battle" scope.
  ------------------------------------------------------------------
  local function flashFireCharged(battle, mon)
    if isGen2Battle and isGen2Battle(battle) then
      return battle:volatile(mon).flashFireCharged == true
    end
    return mon.flashFireCharged == true
  end
  registerDamageModifier("flashfire_boost", 90, function(ctx)
    local id = abilityIdOf(ctx.user)
    if not (id and data.FLASHFIRE and id == "FLASHFIRE") then return 1.0 end
    if ctx.move.type ~= "FIRE" then return 1.0 end
    if not flashFireCharged(ctx.battle, ctx.user) then return 1.0 end
    local effects = multiplierEffects(ctx.user, "damage_dealt_multiplier")
    for _, effect in ipairs(effects or {}) do
      if effect.moveType and effect.moveType:upper() == "FIRE" and effect.factor then
        return effect.factor
      end
    end
    return 1.0
  end)

  mod.log:info("g9-battle-engine: damage_multiplier ability engine installed (Phase 2 + Phase 14: FLUFFY, ANALYTIC, FLASHFIRE boost)")
end
