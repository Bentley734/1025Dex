-- Part B Phase 5: entry hazards -- Spikes, Stealth Rock, Toxic Spikes,
-- Sharp Steel, Sticky Web, Rapid Spin. First of the ~49 confirmed-remaining
-- moves_new.lua stubs (see this session's own re-audit: PROTECT/DETECT
-- and the pure multiHit moves were false positives already handled
-- elsewhere, bringing the real count from the original ~68 estimate
-- down to 49).
--
-- Two different ownership models coexist here, chosen per the project's
-- golden rule (Gen 9 always wins a generational collision; non-
-- colliding native behavior is additive, never silently replaced):
--   Stealth Rock, Toxic Spikes, Sharp Steel: genuine Gen 4+/8+ additions
--   neither generation ever had natively, so they get their own new
--   per-side state here (battle.hazards), the same "own it outright"
--   pattern modern_weather.lua established for field state.
--   Spikes: Gen 2 has REAL native Spikes (src/battle/gen2/Battle.lua:
--   2041-2047 EFFECT_SPIKES, :3599-3613 Battle:spikesDamage) -- a
--   genuine Gen 2 cart move, not a gap. But native Spikes is Gen 2's
--   ORIGINAL, single-layer/flat-1/8 behavior; Gen 9 Spikes stacks up to
--   3 layers at 1/8 -> 1/6 -> 1/4. That is a real generational
--   collision (this engine's Gen 2-native rule vs. the current Gen 9
--   rule), so per the golden rule the native functions are monkeypatched
--   in place further down -- overridden to match Gen 9, not shadowed by
--   a second, competing hazard system the way Stealth Rock/Toxic
--   Spikes/Sharp Steel are.
--   Gen 1 has no hazard concept at all, same "own it outright" case as
--   Gen 1 weather.
--
-- Primitives, all confirmed by direct source read:
--   Switch-in hook: battle.battler_switched, confirmed IDENTICAL payload
--   shape on both generations (src/battle/BattleState.lua:2456-2459 Gen
--   1, src/battle/gen2/Battle.lua:3405-3407 Gen 2 -- that Gen 2 site's
--   own comment: "the payload BattleState:resolveSwitch emits on Gen 1").
--   battle:sideOf(who) also confirmed on both (src/battle/
--   EffectRegistry.lua:77 ctx.side wraps it for Gen 1; gen2/Battle.lua's
--   own spikesDamage calls self:sideOf(mon) directly) -- one cross-gen
--   side key ("player"/"enemy"), not two separate lookups.
--   curTypesOf/isGen2Battle: exported by modern_combat.lua, already the
--   established cross-gen live-type accessor (Transform/Conversion-
--   aware) used by modern_weather.lua's own Sand immunity check.
--   Stealth Rock / Sharp Steel damage: TypeChart.effectiveness(<type>,
--   types), a x10-scaled multiplier (confirmed src/battle/TypeChart.lua
--   :57-69) -- divided back to a real fraction for the Showdown formula
--   maxHP * effectiveness / 8. Confirmed identical shape for Sharp Steel
--   directly against Showdown's own data/moves.ts gmaxsteelsurge
--   condition (this session): "const steelHazard = ...Stealth Rock...
--   steelHazard.type = 'Steel'; ... this.damage(pokemon.maxhp *
--   (2**typeMod) / 8)" -- literally Stealth Rock's own formula re-typed
--   to Steel, which is exactly this file's own TypeChart.effectiveness
--   ("STEEL", types)/10 * maxHp/8 below.
--   Poison infliction: Gen 1's real StatusRegistry.inflict (src/battle/
--   StatusRegistry.lua:21-56, same primitive MoveEffects.lua's own
--   POISON_EFFECT/TOXIC-family moves use) and Gen 2's real
--   Battle:applyStatus (gen2/Battle.lua:2895-2926, same primitive every
--   native Gen 2 status move uses).
--   Native Spikes override: Battle.MOVE_EFFECTS.EFFECT_SPIKES and
--   Battle:spikesDamage are plain fields/methods on the Gen 2 Battle
--   CLASS table (require("src.battle.gen2.Battle")), not per-instance --
--   reassigning them after the fact affects every past and future
--   instance identically, the same monkeypatch shape
--   combat/modern_combat_protect.lua's own Part D already established
--   for BattleState.performMove.
--
-- INTERACTION TODO: Toxic Spikes' real immunity is Poison (absorbs,
-- removes the hazard), Flying-type OR Levitate (unaffected, hazard
-- stays), Steel-type (unaffected in current Showdown). Only the TYPE
-- half (Poison/Flying/Steel) is checked here -- Levitate is an ABILITY
-- exemption, and this codebase has no battle-effective abilities
-- anywhere yet (confirmed this session while building PROGRESS.md:
-- ModernStats only ASSIGNS abilities as identity data, nothing in
-- combat/ gives one an effect) -- so a Levitate mon currently gets
-- poisoned by Toxic Spikes same as any other grounded non-immune type.
-- Depends on: a real battle-effective abilities system existing at all.
-- Revisit this exact spot (the isFlyingOrSteel check below) once it does.
--
-- INTERACTION TODO: Sharp Steel is defined below (state + switch-in
-- damage) but nothing sets h.sharpSteel = true yet. Its only real cause,
-- G-Max Steelsurge, already exists as move data (Copperajah's signature,
-- gigantamax/gmax_moves.lua:59, functionCode =
-- "DamageTargetAddSteelsurgeToFoeSide") but its effect is still
-- NO_ADDITIONAL_EFFECT -- wiring it is a Gigantamax-system task (needs
-- the G-max-active/Copperajah-using-its-signature gating that lives in
-- gigantamax/, not this file), not this hazards batch. Depends on: that
-- gating existing to check against. Revisit by registering a
-- GALAR_GMAXSTEELSURGE_EFFECT (same kind="primary" shape as
-- GALAR_STEALTHROCK_EFFECT below, just h.sharpSteel and STEEL-flavored
-- text) once that gate is available.
return function(mod)
  local TypeChart = require("src.battle.TypeChart")
  local StatusRegistry = require("src.battle.StatusRegistry")
  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")
  local gen2Ok_Battle2, Battle2 = pcall(require, "src.battle.gen2.Battle")
  Battle2 = gen2Ok_Battle2 and Battle2 or nil

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local curTypesOf = mod.exports.curTypesOf
  local isGen2Battle = mod.exports.isGen2Battle
  assert(normalize and displayNameFor and curTypesOf and isGen2Battle,
    "modern_hazards: combat/modern_combat.lua must load first")

  local function hazardsFor(battle, side)
    battle.hazards = battle.hazards or {}
    local h = battle.hazards[side]
    if not h then
      h = { stealthRock = false, toxicSpikes = 0, sharpSteel = false, stickyWeb = false }
      battle.hazards[side] = h
    end
    return h
  end
  -- Exported (Phase 8, other bucket, Toxic Debris) -- the one real
  -- shared accessor for this file's own hazards table, so an ability
  -- that sets Toxic Spikes reuses the exact same 2-layer cap rather than
  -- re-deriving it.
  mod.exports.hazardsFor = hazardsFor

  -- Mon-shaped accessor for whichever generation's battler this is --
  -- Gen 1 hands a wrapper (battler.mon), Gen 2 hands the raw mon
  -- directly (confirmed this exact distinction earlier this session,
  -- src/battle/gen2/Battle.lua's own comment: "battler is the mon itself
  -- here: Gen 2's engine has no battler wrapper").
  local function monOf(battler, gen2)
    return gen2 and battler or battler.mon
  end

  -- Real grounding exemption for the three hazards that actually care
  -- about it (native Spikes, Toxic Spikes, Sticky Web -- Stealth Rock and
  -- Sharp Steel hit everyone regardless, real mechanic, no exemption at
  -- all): Flying-type, or an ability that grants the same airborne status
  -- Levitate does. Closes this file's own pre-existing INTERACTION TODO
  -- (written before this mod had any battle-effective ability system at
  -- all) -- LEVITATE itself isn't built as its own Ground-move-type-
  -- immunity ability anywhere in this mod yet (a real, separate,
  -- un-numbered gap), but checking its id here for hazard-grounding
  -- purposes is still correct and forward-safe the moment it is.
  -- EELEVATE's own real effect text is explicit about this exact
  -- exemption ("immune to Ground-type moves, as well as the Spikes,
  -- Toxic Spikes, and Sticky Web statuses"), so it's included alongside
  -- Levitate rather than assumed already covered by its own typing.
  local GROUND_IMMUNE_ABILITY = { LEVITATE = true, EELEVATE = true }
  local function isGroundedForHazards(mon, gen2, types)
    -- Phase 8 Gravity (combat/modern_field_effects.lua): while the field
    -- effect is up every active mon is grounded, so a Flying-type/Levitate
    -- mon that would normally float over Spikes/Toxic Spikes/Sticky Web is
    -- hit by them. Checked before the type/ability exemptions below, which is
    -- exactly what "grounded" overrides. `mon` may be a raw mon or a battler
    -- wrapper here (both call shapes exist in this file), so both are probed.
    if mon and (mon.gravityGrounded or (mon.mon and mon.mon.gravityGrounded)) then
      return true
    end
    for _, t in ipairs(types) do
      if t == "FLYING" then return false end
    end
    local abilityIdOf = mod.exports.abilityIdOf
    local id = abilityIdOf and abilityIdOf(mon)
    if id and GROUND_IMMUNE_ABILITY[id] then return false end
    return true
  end

  ------------------------------------------------------------------
  -- Setters: kind="primary", same shape modern_weather.lua's own
  -- weatherStarter uses for a field-wide status move -- fires whole and
  -- unconditionally (Gen 1's pure-status-move block / Gen 2's generic
  -- merge), targets the OPPOSING side from whoever used the move.
  -- accuracyChecked left unset: field-effect moves never miss, same
  -- reasoning modern_weather.lua/modern_movepool_stages.lua's own
  -- primary() already establishes.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_STEALTHROCK_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local side = n.battle:sideOf(n.target)
      local h = hazardsFor(n.battle, side)
      if h.stealthRock then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      h.stealthRock = true
      return { Strings("Pointed stones\nfloat in the air\naround %s's team!",
        displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })

  mod.content.move_effects:register("GALAR_TOXICSPIKES_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local side = n.battle:sideOf(n.target)
      local h = hazardsFor(n.battle, side)
      if h.toxicSpikes >= 2 then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      h.toxicSpikes = h.toxicSpikes + 1
      return { Strings("Poison spikes\nscatter around\n%s's team!",
        displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })

  -- Sticky Web -- real Gen 6+ hazard, single layer (doesn't stack), -1
  -- Speed stage to any grounded Pokémon switching in. Confirmed via
  -- Showdown's own data/moves.ts stickyweb condition: onEntryHazard
  -- boosts = { spe = -1 }, no immunity beyond the same grounding check
  -- every other grounded-only hazard already uses.
  mod.content.move_effects:register("GALAR_STICKYWEB_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local side = n.battle:sideOf(n.target)
      local h = hazardsFor(n.battle, side)
      if h.stickyWeb then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      h.stickyWeb = true
      return { Strings("A sticky web\nspreads out\nunder %s's team!",
        displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })

  ------------------------------------------------------------------
  -- Native Spikes upgrade: Gen 2's own SpikesDamage/EFFECT_SPIKES are a
  -- single, non-stacking layer at a flat 1/8 max HP -- accurate to Gen 2
  -- at the time, but stacking (up to 3 layers, 1/8 -> 1/6 -> 1/4) was
  -- added Gen 3 and is Spikes' real Gen 9 Showdown behavior (confirmed
  -- directly against data/moves.ts's own spikes condition:
  -- onSideStart/onSideRestart layering up to effectState.layers == 3,
  -- damageAmounts = {0, 3, 4, 6} as those-many 24ths of maxhp -- i.e.
  -- 3/24, 4/24, 6/24 = 1/8, 1/6, 1/4). Per the golden rule this
  -- overrides the native functions in place rather than adding a
  -- parallel mod-owned hazard the way Stealth Rock/Toxic Spikes/Sharp
  -- Steel do above/below -- Spikes already has real native state
  -- (self.spikes) to upgrade, not a gap to fill.
  --
  -- self.spikes[side] is repurposed from a boolean to a 0-3 layer count
  -- (nil/0 = none). The only other native reader of this field
  -- (gen2/Battle.lua:664's enemySpikes snapshot) only ever uses it in a
  -- truthy check, which reads identically for 1/2/3 as it did for
  -- `true`, so nothing else needs to change.
  --
  -- Grounding: CLOSED 2026-08-27 -- Flying-type OR Levitate/Eelevate,
  -- via this file's own shared isGroundedForHazards (defined above,
  -- now that this mod's ability system is battle-effective). Gravity/
  -- Iron Ball/Ingrain overriding a normally-airborne mon back to grounded,
  -- and Heavy-Duty Boots' universal exemption, remain real, separate,
  -- honestly-named gaps -- Gravity/Ingrain aren't implemented anywhere in
  -- this engine, and Heavy-Duty Boots isn't part of Gen 2's real ROM item
  -- roster at all (confirmed this session, tools/rom_manifest_gold.json's
  -- itemOrder has no such id), so that second half is structurally moot
  -- here, not deferred.
  ------------------------------------------------------------------
  if Battle2 then
    Battle2.MOVE_EFFECTS.EFFECT_SPIKES = function(self, attacker, defender)
      local side = self:sideOf(defender)
      local layers = self.spikes[side] or 0
      if layers >= 3 then
        self:markMissed()
        self:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      self.spikes[side] = layers + 1
      self:emit({ kind = "message", text = Strings("Spikes were scattered all around!") })
    end
  end

  -- Showdown's own [0, 3, 4, 6] table (24ths of maxhp), re-keyed 1-3
  -- instead of 0-3 since Lua has no meaningful "0 layers" damage call.
  local SPIKES_DAMAGE_24THS = { [1] = 3, [2] = 4, [3] = 6 }

  if Battle2 then
    function Battle2:spikesDamage(mon)
      local side = self:sideOf(mon)
      local layers = self.spikes[side] or 0
      if layers <= 0 or (mon.hp or 0) <= 0 then return end
      local def = self:speciesDef(mon)
      local types = (def and def.types) or mon.types or {}
      if not isGroundedForHazards(mon, true, types) then return end
      -- Magic Guard, real Showdown rule, fixed 2026-08-28 -- same real
      -- predicate the Stealth Rock/Sharp Steel blocks above use.
      local magicGuardBlocksHazard = mod.exports.magicGuardBlocksHazard
      if magicGuardBlocksHazard and magicGuardBlocksHazard(mon) then return end
      local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 8
      local fraction = SPIKES_DAMAGE_24THS[layers] or SPIKES_DAMAGE_24THS[3]
      local damage = math.max(1, math.floor(fraction * maxHp / 24))
      mon.hp = math.max(0, mon.hp - damage)
      self:emit({ kind = "message",
        text = Strings("%s is hurt by SPIKES!", self:monName(mon)) })
      self:emit({ kind = "damage", side = side, amount = damage, hp = mon.hp,
        anim = false })
    end
  end

  ------------------------------------------------------------------
  -- Rapid Spin: real damaging move -- CANNOT use kind="secondary"+run
  -- the way a chance-based secondary (GALAR_FLINCH_EFFECT_<chance>) does.
  -- Confirmed directly, modern_movepool_status.lua's own header:
  -- Gen 2's dispatch calls ANY move_effects record with a .run field
  -- BEFORE its own damage path and returns immediately once it does
  -- (gen2/Battle.lua:1533-1538, `if handler then handler(...); return
  -- end`) -- true regardless of what the handler's body does, so an
  -- internal `if gen2 then return end` guard does NOT stop Gen 2 from
  -- having already skipped its own damage code by the time the guard
  -- runs. A kind="secondary" Rapid Spin would deal ZERO damage on Gen 2
  -- -- exactly the trap this file's own Blizzard/Solar Beam precedent
  -- (modern_weather.lua) already worked around with an empty kind="full"
  -- record. Same fix here: kind="full" (no run field, invisible to that
  -- check on both engines, confirmed via EffectRegistry.runDamaging
  -- being nil-safe on every stage field) lets Rapid Spin deal perfectly
  -- ordinary damage on both generations, and the hazard-clear is wired
  -- through battle.damage_dealt instead -- confirmed identical payload
  -- on both engines (gen2/Battle.lua:1242-1246, EffectRegistry.lua:
  -- 286-289: battle/user/target/move+moveId/damage), fired AFTER damage
  -- regardless of generation, so it can never eat the hit.
  --
  -- INTERACTION TODO: clears every hazard on the USER's own side;
  -- binding-effect removal (Wrap/Bind/Fire Spin/etc.) deliberately NOT
  -- included here -- this move's own functionCode was
  -- "RemoveUserBindingAndEntryHazards", the binding half is a distinct
  -- mechanic from hazards and stays out of THIS task's scope, not
  -- silently dropped. Depends on: a trapping/binding-moves pass existing
  -- (none of Wrap/Bind/Fire Spin/Clamp/Sand Tomb/Whirlpool/Infestation
  -- are implemented yet -- Task #3 in this phase's tracker touches
  -- switch-conditional moves but binding itself isn't scoped to any
  -- pending batch yet). Revisit this exact registration once that lands.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_RAPIDSPIN_EFFECT", { kind = "full" })

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    if not (battle and moveId == "RAPIDSPIN" and ev.user) then return end
    local ok, err = pcall(function()
      local side = battle:sideOf(ev.user)
      local h = hazardsFor(battle, side)
      local gen2 = isGen2Battle(battle)
      -- Native Spikes lives in battle.spikes[side] (a 0-3 layer count,
      -- see the EFFECT_SPIKES/spikesDamage override above), separate
      -- from this file's own mod-owned h table -- Gen 9 Rapid Spin
      -- clears every entry hazard on the user's side, native Spikes
      -- included, so both have to be checked and cleared together.
      local hasSpikes = gen2 and battle.spikes and (battle.spikes[side] or 0) > 0
      if not (h.stealthRock or h.toxicSpikes > 0 or h.sharpSteel or h.stickyWeb or hasSpikes) then return end
      h.stealthRock = false
      h.toxicSpikes = 0
      h.sharpSteel = false
      h.stickyWeb = false
      if hasSpikes then battle.spikes[side] = 0 end
      local text = Strings("%s blew away\nhazards\nwith its spin!",
        displayNameFor(battle, ev.user, gen2))
      if gen2 then
        battle:emit({ kind = "message", text = text })
      else
        battle:sayNext(text)
      end
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_hazards: Rapid Spin hazard-clear failed: %s",
        tostring(err))
    end
  end)

  ------------------------------------------------------------------
  -- Switch-in resolution: Stealth Rock damage, then Toxic Spikes
  -- poison/absorption. Runs once per real send-out (voluntary switch,
  -- forced replacement after faint, AI switch -- battle.battler_switched
  -- fires from every one of those sites on both generations, confirmed
  -- via direct source read of every Runtime.emit call site).
  ------------------------------------------------------------------
  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local battler = ev and ev.battler
    if not (battle and battler) then return end
    local ok, err = pcall(function()
      local gen2 = isGen2Battle(battle)
      local mon = monOf(battler, gen2)
      if not mon or (mon.hp or 0) <= 0 then return end
      local side = battle:sideOf(battler)
      local h = hazardsFor(battle, side)
      local types = curTypesOf(battler, gen2)
      local name = displayNameFor(battle, battler, gen2)
      -- Magic Guard, real Showdown rule, fixed 2026-08-28: this same
      -- ability already blocks status residual/Gen 1 sand/recoil/
      -- confusion self-hit (abilities/engine/damage_immunity.lua's own
      -- real fixes) -- entry hazards are the same real "indirect
      -- damage" family, checked once here for both blocks below via
      -- that file's own small exported predicate.
      local magicGuardBlocksHazard = mod.exports.magicGuardBlocksHazard
      local hazardImmune = magicGuardBlocksHazard and magicGuardBlocksHazard(mon)

      -- Stealth Rock: maxHP * effectiveness(ROCK vs types) / 8, current
      -- Showdown formula (src/battle/TypeChart.lua's own x10 scale
      -- divided back to a real fraction). A 4x-weak mon can faint from
      -- this alone, same as real games -- not clamped beyond the
      -- ordinary max(0, hp-damage) floor.
      if h.stealthRock and not hazardImmune then
        local mult = TypeChart.effectiveness("ROCK", types) / 10
        if mult > 0 then
          local maxHp = (mon.stats and mon.stats.hp) or mon.maxHp or 1
          local damage = math.max(1, math.floor(maxHp * mult / 8))
          if gen2 then
            mon.hp = math.max(0, mon.hp - damage)
            battle:emit({ kind = "message",
              text = Strings("%s is hurt by pointed stones!", name) })
            battle:emit({ kind = "damage", side = side, amount = damage,
              hp = mon.hp, anim = false })
          else
            battle:applyDamage(battler, damage)
            battle:drainNext(battler, battler.mon.hp)
            battle:sayNext(Strings("%s is hurt\nby pointed stones!", name))
            if battler.mon.hp <= 0 then battle:onFaint(battler) end
          end
        end
      end

      -- Sharp Steel: same shape as Stealth Rock above, STEEL instead of
      -- ROCK -- confirmed identical formula against Showdown's own
      -- gmaxsteelsurge condition (see header). mon.hp re-checked since
      -- Stealth Rock above may have already fainted this mon. Nothing
      -- currently sets h.sharpSteel (see header INTERACTION TODO) -- this
      -- block is real, working, and simply never triggers yet.
      if h.sharpSteel and (mon.hp or 0) > 0 and not hazardImmune then
        local mult = TypeChart.effectiveness("STEEL", types) / 10
        if mult > 0 then
          local maxHp = (mon.stats and mon.stats.hp) or mon.maxHp or 1
          local damage = math.max(1, math.floor(maxHp * mult / 8))
          if gen2 then
            mon.hp = math.max(0, mon.hp - damage)
            battle:emit({ kind = "message",
              text = Strings("%s is hurt by the sharp steel!", name) })
            battle:emit({ kind = "damage", side = side, amount = damage,
              hp = mon.hp, anim = false })
          else
            battle:applyDamage(battler, damage)
            battle:drainNext(battler, battler.mon.hp)
            battle:sayNext(Strings("%s is hurt\nby the sharp steel!", name))
            if battler.mon.hp <= 0 then battle:onFaint(battler) end
          end
        end
      end

      -- Toxic Spikes: Poison absorbs (removes the hazard, no poison for
      -- the absorber); Flying or Steel are unaffected (hazard stays,
      -- nothing happens to them); otherwise poisoned -- regular at 1
      -- layer, badly poisoned (toxic) at 2. mon.hp re-checked after
      -- Stealth Rock/Sharp Steel above in case either alone fainted this
      -- mon.
      if h.toxicSpikes > 0 and (mon.hp or 0) > 0 then
        local isPoison, isSteel = false, false
        for _, t in ipairs(types) do
          if t == "POISON" then isPoison = true end
          if t == "STEEL" then isSteel = true end
        end
        -- Grounding half (Flying/Levitate/Eelevate) CLOSED 2026-08-27 --
        -- this file's own shared isGroundedForHazards, now that abilities
        -- are battle-effective. Steel's own exemption stays a separate
        -- check: it's about poison-type immunity, not grounding, so it
        -- must NOT be folded into that same helper.
        local unaffected = isSteel or not isGroundedForHazards(battler, gen2, types)
        if isPoison then
          h.toxicSpikes = 0
          battle:sayNext(Strings("%s absorbed\nthe poison spikes!", name))
        elseif not unaffected then
          local badly = h.toxicSpikes >= 2
          if gen2 then
            -- Confirmed via gen2/Battle.lua:2785-2798: Gen 2 has real
            -- separate "poison"/"toxic" status ids (unlike Gen 1, which
            -- has only "PSN" plus an escalation flag -- see below).
            battle:applyStatus(mon, badly and "toxic" or "poison", "TOXICSPIKES")
          else
            -- Confirmed via src/battle/Status.lua:101-112: Gen 1 has no
            -- separate "TOX" status string at all -- it's always "PSN",
            -- and opts.toxic=true is what makes onInflict seed
            -- battler.toxicCounter=1 (the same escalating-damage flag
            -- Status.lua's own damageOverTime residual reads), exactly
            -- what the real move TOXIC itself sets. Passing a literal
            -- "TOX" here (an earlier draft of this file did, before this
            -- was checked) would have gone through canInflict, matched
            -- no real status record, and silently done nothing.
            local msgs = StatusRegistry.inflict(battle, battler, "PSN",
              { source = "TOXICSPIKES", toxic = badly })
            for _, m in ipairs(msgs) do battle:sayNext(m) end
          end
        end
      end

      -- Sticky Web: real -1 Speed stage to a grounded switch-in, no
      -- accuracy check (a field effect, not a move targeting the mon).
      -- Speed is a NATIVE_STATS stat in this engine (never routes through
      -- combat/modern_combat.lua's own changeStage, same split this
      -- mod's own code documents in several other places) -- Gen 2 goes
      -- through Battle:changeStageAgainstMist (Mist-aware, Clear Body/
      -- White Smoke/Full Metal Body/Hyper Cutter-aware via that
      -- function's own Phase 7 extension); Gen 1 writes battler.stages
      -- .speed directly -- the wrapper itself, NOT battler.mon (real,
      -- confirmed field location: this is the same object Foresight/
      -- Miracle Eye's own evasion-cap fix and main.lua's own NATIVE_STATS
      -- branch both write .stages onto, src/battle/Damage.lua's own
      -- attacker.stages.speed read is against this same wrapper) --
      -- gated by the same statDropBlockedByAbility helper and boss-fight
      -- protection every other opponent-directed stat drop in this mod
      -- already checks.
      if h.stickyWeb and (mon.hp or 0) > 0 and isGroundedForHazards(battler, gen2, types) then
        local statDropBlockedByAbility = mod.exports.statDropBlockedByAbility
        local blocked = statDropBlockedByAbility and statDropBlockedByAbility(battler, gen2, "speed")
        if not blocked then
          if gen2 then
            -- attacker=nil (not `battler`): changeStageAgainstMist only
            -- ever uses this param for a `target ~= attacker` hostility
            -- check (Mist/Clear Body-family), never dereferences it --
            -- passing the target itself here would have made this read
            -- as a SELF-inflicted change, skipping both of those checks
            -- entirely, wrong for an environmental hazard.
            battle:changeStageAgainstMist(nil, battler, "speed", -1)
          elseif not (mod.exports.bossStatsDropBlocked and mod.exports.bossStatsDropBlocked(battle, battler, -1)) then
            battler.stages = battler.stages or {}
            battler.stages.speed = math.max(-6, (battler.stages.speed or 0) - 1)
          end
          battle:sayNext(Strings("%s was\ncaught in a sticky web!", name))
        end
      end
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_hazards: switch-in resolution failed: %s",
        tostring(err))
    end
  end)

  mod.log:info("galar_gmax_dex: modern_hazards loaded (Spikes upgraded to Gen 9 "
    .. "stacking, Stealth Rock, Toxic Spikes, Sharp Steel, Sticky Web defined, Rapid Spin, "
    .. "Flying/Levitate/Eelevate grounding exemption)")
end
