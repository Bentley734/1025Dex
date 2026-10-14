-- Missing-effects plan, Phase 18: guard / contact interaction & ignore-ability.
-- Verified against Showdown's own real source this pass (data/moves.ts, each
-- record read directly) plus this engine's own move/damage pipeline. The
-- twenty-one moves fall into five groups; each real mechanic:
--
--   PROTECT-BREAKERS (breaksProtect:true)
--     PHANTOMFORCE (moves.ts:13308), SHADOWFORCE (moves.ts:16074) -- both are
--       also CHARGE moves (flags charge:1, a two-turn vanish, onInvulnerability
--       false) whose release ignores any shield. HYPERSPACEHOLE (moves.ts:9194)
--       -- a plain special attack that breaks Protect and carries `bypasssub`.
--   IGNORE-DEFENSIVE + IGNORE-EVASION
--     CHIPAWAY (moves.ts:2421), SACREDSWORD (moves.ts:15561), DARKESTLARIAT
--       (moves.ts:3324) -- `ignoreDefensive:true, ignoreEvasion:true`: the
--       attacker's move ignores the defender's positive Def/SpD stage boosts
--       AND the defender's evasion stage.
--   IGNORE-ABILITY
--     MOONGEISTBEAM (moves.ts:12229), SUNSTEELSTRIKE (moves.ts:18432) --
--       `ignoreAbility:true`: the move completely ignores the TARGET's ability
--       while it is being resolved.
--   DAMAGE-FORMULA ODDITIES (implemented in combat/modern_combat.lua's own
--   computeModernDamage, not here -- listed for completeness)
--     FLYINGPRESS (moves.ts:5936, onEffectiveness adds Flying's chart),
--       SYNCHRONOISE (moves.ts:18709, onTryImmunity unless the target shares a
--       type), FALSESWIPE (moves.ts:5140, onDamage caps at target.hp-1).
--   ON-HIT / ON-TRY RIDERS (all here)
--     POLTERGEIST (moves.ts:13596) onTry: fails unless the target holds an item.
--     STEELROLLER (moves.ts:17894) onTry: fails unless a terrain is up; onHit
--       clears the terrain.
--     ICESPINNER (moves.ts:9418) onAfterHit clears the terrain.
--     THOUSANDWAVES (moves.ts:19357) onHit pins the target (the Ghost-type
--       trapped immunity is real Gen 6+ behavior).
--     FREEZYFROST (moves.ts:6223) onHit: clearallboost on every active mon.
--     CEASELESSEDGE (moves.ts:2220) onAfterHit lays one Spikes on the foe side
--       (Sheer Force-gated; secondary:{} so it is Sheer Force-boosted).
--     STONEAXE (moves.ts:18070) onAfterHit lays Stealth Rock on the foe side.
--     FELLSTINGER (moves.ts:5203) onAfterMoveSecondarySelf: +3 Attack if the
--       target fainted.
--     ORDERUP (moves.ts:13041) onAfterMoveSecondarySelf: a stat boost chosen by
--       the COMMANDING Tatsugiri's forme.
--
-- SEAMS USED, all pre-existing:
--   * The protect break rides the same `bypassesProtect` flag Feint already
--     uses (modern_combat_protect.lua's battle.damage hook reads it off the
--     live move record). main.lua's wireMovepoolSubEffects stamps it from
--     BYPASSES_PROTECT; the two charge moves additionally get their own
--     charge record (the Sky Drop shape) via CUSTOM_EFFECT_PATCH.
--   * ignoreDefensive is read directly by computeModernDamage (it zeroes the
--     effective defender's Def/SpD stage for the computation only), the same
--     hole Unaware's attacker half already plugs -- no seam needed.
--   * ignoreEvasion rides the real `battle.accuracy` hook (the same hook
--     abilities/engine/accuracy_multiplier.lua's own evasion-ignore family
--     uses) by zeroing the defender's native evasion stage for the duration
--     of one roll and restoring it immediately after.
--   * ignoreAbility rides a battle.damage wrap that sets ability_dispatch's
--     own `ignoredAbilityMon` for the duration of the computation -- the ONE
--     choke point every ability check in this mod goes through (see that
--     file's own comment for why a local there, not a second dispatch).
--   * The on-hit riders are `battle.damage_dealt` listeners keyed by move id
--     (the Rapid Spin / Shell Trap precedent), so they can never eat the hit.
--     Hazards reuse modern_hazards' own `hazardsFor` store and its exact
--     message text; Spikes reuse the engine/`spikesOf` store the mod already
--     treats as canonical (`battle.spikes[side]`, 0-3 layers); the terrain
--     clear reuses modern_side_conditions' exported `clearTerrain`; the pin
--     reuses modern_trap_moves' `trapApplyPin`; the Fell Stinger boost reuses
--     `changeStage` exactly as abilities/engine/ko_boost.lua's own KO-reward
--     family does.
--   * Poltergeist / Steel Roller's fail conditions ride modern_action_order's
--     reusable `registerFailGate` seam (announced, PP spent, marked missed).
--
-- HONEST PARTIALS (documented, not faked):
--   * HYPERSPACEHOLE: the protect break is wired, but the real `bypasssub`
--     half (it hits through Substitute) is not -- this engine's Substitute
--     redirection is not a seam this mod hooks, the same documented gap every
--     other bypasssub move in this codebase already carries (see
--     combat/modern_stat_manipulation.lua's own bypasssub notes).
--   * ORDERUP: needs the Commander ability / a commanding Tatsugiri forme to
--     choose which stat rises, neither of which this mod models, so the move
--     deals its plain damage and no boost -- the whole real effect is
--     unobservable here, not half-faked.
--   * SUPERCELSAM's crash-on-miss (onMoveFail, half max HP to the user) is NOT
--     implemented: this engine exposes no "the move missed" event to a mod,
--     and there is no honest way to detect it from the damage path. The move
--     is added to the Reckless damage-boost list (abilities/engine/
--     damage_multiplier.lua's CRASH_DAMAGE_MOVES), which is the same real
--     `hasCrashDamage` flag Showdown reads, but the self-damage half is a
--     documented gap rather than a guess.
--   * CEASELESSEDGE's Spikes are fully functional on Gen 2 (native
--     Battle:spikesDamage, which modern_hazards.lua already upgraded to the
--     Gen 9 3-layer curve). Gen 1 has no switch-in Spikes damage anywhere in
--     this engine (modern_hazards' own header names this), so on Gen 1 the
--     layers are recorded but never tick -- consistent with that file's
--     documented "Gen 1 has no hazard concept" stance.
--   * The Poltergeist / Steel Roller fail gates run inside Battle:useMove, so
--     they are Gen 2-only, exactly like the Shell Trap gate (see
--     combat/modern_charge_moves.lua's own note); the riders themselves fire
--     on both generations.
return function(mod)
  local registerFailGate = mod.exports.registerFailGate
  local resetStages = mod.exports.resetStages
  local changeStage = mod.exports.changeStage
  local isGen2Battle = mod.exports.isGen2Battle
  local allActiveBattlers = mod.exports.allActiveBattlers
  assert(registerFailGate and resetStages and changeStage and isGen2Battle,
    "modern_guard_contact: combat/modern_combat.lua and "
    .. "combat/modern_action_order.lua must load first")

  local Strings = require("src.core.Strings")

  local function gen2Of(battle)
    return isGen2Battle and isGen2Battle(battle) or false
  end

  -- Raw mon behind a Gen 1 battler wrapper, or the mon itself on Gen 2.
  local function rawMon(who)
    return who and (who.mon or who) or nil
  end

  -- A message through whichever channel the engine uses: Gen 2's event emit,
  -- or Gen 1's sayNext (the exact split modern_hazards' own Rapid Spin uses).
  local function say(battle, text, gen2)
    if not (battle and text) then return end
    if gen2 then
      if battle.emit then battle:emit({ kind = "message", text = text }) end
    elseif battle.sayNext then
      battle:sayNext(text)
    elseif battle.emit then
      battle:emit({ kind = "message", text = text })
    end
  end

  local function nameOf(battle, mon, gen2)
    local displayNameFor = mod.exports.displayNameFor
    if displayNameFor then
      local ok, n = pcall(displayNameFor, battle, mon, gen2)
      if ok and n then return n end
    end
    return (mon and (mon.name or mon.species
      or (mon.mon and mon.mon.name))) or "The Pokemon"
  end

  ------------------------------------------------------------------
  -- Phantom Force / Shadow Force: the two-turn vanish. Same `charge`
  -- record shape modern_charge_moves.lua's own Sky Drop uses (the engine's
  -- charge machinery is user-side semi-invulnerability), plus the matching
  -- Gen 2 announce entry. Their `bypassesProtect` flag is stamped separately
  -- by main.lua, so the release ignores a shield as Showdown's real
  -- breaksProtect does.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_PHANTOMFORCE_EFFECT", {
    kind = "full",
    charge = { invulnerable = true, anim = "TELEPORT" },
  })
  mod.content.move_effects:register("GALAR_SHADOWFORCE_EFFECT", {
    kind = "full",
    charge = { invulnerable = true, anim = "TELEPORT" },
  })
  local gen2Ok_Gen2Effects, Gen2Effects = pcall(require, "src.battle.gen2.Effects")
  Gen2Effects = gen2Ok_Gen2Effects and Gen2Effects or nil
  if Gen2Effects then
    Gen2Effects.CHARGE.GALAR_PHANTOMFORCE_EFFECT =
      { text = "%s vanished instantly!", vanish = true }
    Gen2Effects.CHARGE.GALAR_SHADOWFORCE_EFFECT =
      { text = "%s vanished instantly!", vanish = true }
  end

  ------------------------------------------------------------------
  -- ignoreEvasion (Chip Away / Sacred Sword / Darkest Lariat). The move
  -- record's own flag is read live. The engine applies the real evasion
  -- stage inside nextFn (Gen 2 reads battle.stages[side].evasion; Gen 1
  -- reads defender.stages.evasion in Damage.accuracyThreshold), so the only
  -- faithful way to ignore it is to zero the native stage for the duration
  -- of the roll and restore it immediately after -- the exact
  -- zero-and-restore idiom abilities/engine/accuracy_multiplier.lua's own
  -- Keen Eye / Unaware family already established. Priority 100 puts this
  -- wrap outside every existing accuracy wrap (that file is 0,
  -- modern_crit_override is 45, modern_move_flags is 50), so a move both
  -- flags compose cleanly. pcall-guarded so a downstream error still
  -- restores the saved stages before re-raising.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.accuracy", function(nextFn, ctx)
    local move = ctx and ctx.move
    if not (move and move.ignoreEvasion) then return nextFn(ctx) end
    local saved = {}
    local function stash(store, key)
      if store then
        saved[#saved + 1] = { store = store, key = key, value = store[key] }
        store[key] = 0
      end
    end
    local battle = ctx.battle
    if battle and battle.stages and ctx.target and battle.sideOf then
      local side = battle:sideOf(ctx.target)
      stash(side and battle.stages[side], "evasion")
    end
    -- Gen 1's battler wrapper carries the stage table the Gen 1 accuracy
    -- roll reads (Damage.accuracyThreshold: defender.stages.evasion).
    if ctx.target and ctx.target.stages then
      stash(ctx.target.stages, "evasion")
    end
    local ok, result = pcall(nextFn, ctx)
    for i = #saved, 1, -1 do
      saved[i].store[saved[i].key] = saved[i].value
    end
    if not ok then error(result, 0) end
    return result
  end, 100)

  ------------------------------------------------------------------
  -- ignoreAbility (Moongeist Beam / Sunsteel Strike). Sets ability_dispatch's
  -- single module-local `ignoredAbilityMon` to the target for the duration of
  -- one damage computation, so EVERY ability read inside computeModernDamage
  -- (Filter/Solid Rock/Prism Armor, Multiscale, Wonder Guard, Sturdy, the
  -- type-immunity family, ...) sees no ability on that mon -- exactly
  -- Showdown's `move.ignoreAbility`. Cleared immediately after, error or not.
  -- Priority 100 keeps it outside modern_combat's own formula hook (0) and
  -- the protect hook (50), so the suppression is in force for all of them.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move = ctx and ctx.move
    if not (move and move.ignoreAbility) then return next(ctx) end
    local setIgnored = mod.exports.setIgnoredAbilityMon
    if not setIgnored then return next(ctx) end
    setIgnored(ctx.target)
    local ok, dmg, info = pcall(next, ctx)
    setIgnored(nil)
    if not ok then error(dmg, 0) end
    return dmg, info
  end, 100)

  ------------------------------------------------------------------
  -- Freezy Frost's clearallboost: every active mon's boosts (the mod's own
  -- modern store AND the native accuracy/evasion/speed store) reset to 0,
  -- matching Showdown's `pokemon.clearBoosts()`. Split per generation the
  -- same way every other stage touch in this mod is: Gen 2 reads
  -- battle.stages[side], Gen 1 reads the battler wrapper's own .stages.
  ------------------------------------------------------------------
  local function clearAllBoosts(battle, mon, gen2)
    resetStages(battle, mon, gen2)
    local store
    if gen2 then
      local side = battle.sideOf and battle:sideOf(mon)
      store = side and battle.stages and battle.stages[side]
    else
      store = mon and mon.stages
    end
    if store then
      for key in pairs(store) do store[key] = 0 end
    end
  end

  ------------------------------------------------------------------
  -- The on-hit / on-try riders. One listener, keyed by move id, so the
  -- TableLookup stays small and every entry is a real Showdown callback.
  -- User-side effects require the user to have survived the hit
  -- (Showdown's onAfterHit / onAfterSubDamage `source.hp` guard where one
  -- exists); target-side effects check the real dealt damage.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    local moveId = ev and (ev.moveId or (ev.move and ev.move.id))
    if not (battle and user and target and moveId) then return end
    if (ev.damage or 0) <= 0 or user == target then return end
    local gen2 = gen2Of(battle)
    local userAlive = ((user.mon or user).hp or user.hp or 0) > 0

    local ok, err = pcall(function()
      if moveId == "ICESPINNER" then
        -- onAfterHit / onAfterSubDamage: clear the terrain (source.hp guard).
        if userAlive then
          local clearTerrain = mod.exports.clearTerrain
          if clearTerrain then clearTerrain(battle) end
        end

      elseif moveId == "STEELROLLER" then
        -- onHit: clear the terrain. (Its onTry "needs a terrain" gate lives
        -- below, on Battle:useMove, so reaching here already means one was up.)
        local clearTerrain = mod.exports.clearTerrain
        if clearTerrain then clearTerrain(battle) end

      elseif moveId == "THOUSANDWAVES" then
        local trapApplyPin = mod.exports.trapApplyPin
        if trapApplyPin then trapApplyPin(battle, user, target, gen2) end

      elseif moveId == "FREEZYFROST" then
        local list = allActiveBattlers and allActiveBattlers(battle)
          or { battle.player, battle.enemy }
        for _, mon in ipairs(list) do
          if mon and (mon.hp or (mon.mon and mon.mon.hp) or 0) > 0 then
            clearAllBoosts(battle, mon, gen2)
          end
        end

      elseif moveId == "FELLSTINGER" then
        -- onAfterMoveSecondarySelf: +3 Attack if the target fainted. The
        -- event fires after the HP deduction, so hp<=0 means this move
        -- landed the KO -- the same test abilities/engine/ko_boost.lua's
        -- own MOXIE family uses.
        local targetHp = (target.mon or target).hp or target.hp or 0
        if targetHp <= 0 then
          for _, line in ipairs(changeStage(battle, user, "attack", 3, false, gen2) or {}) do
            say(battle, line, gen2)
          end
        end
      end
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: modern_guard_contact: %s rider failed: %s",
        tostring(moveId), tostring(err))
    end

    -- Hazards are a separate step because both use modern_hazards' own store
    -- and its exact message text, and each refuses to re-lay what is
    -- already fully laid.
    local ok2, err2 = pcall(function()
      local hazardsFor = mod.exports.hazardsFor
      if not hazardsFor then return end
      if moveId == "STONEAXE" then
        local side = battle:sideOf(target)
        local h = hazardsFor(battle, side)
        if not h.stealthRock then
          h.stealthRock = true
          say(battle, Strings("Pointed stones\nfloat in the air\naround %s's team!",
            nameOf(battle, target, gen2)), gen2)
        end
      elseif moveId == "CEASELESSEDGE" then
        -- Native Spikes store (battle.spikes[side], 0-3 layers -- the same
        -- store modern_side_conditions' own spikesOf/setSpikes reads).
        local side = battle:sideOf(target)
        battle.spikes = battle.spikes or {}
        local layers = battle.spikes[side] or 0
        if type(layers) ~= "number" then layers = 0 end
        if layers < 3 then
          battle.spikes[side] = layers + 1
          say(battle, Strings("Spikes were scattered all around!"), gen2)
        end
      end
    end)
    if not ok2 then
      mod.log:warn("g9-battle-engine: modern_guard_contact: %s hazard rider failed: %s",
        tostring(moveId), tostring(err2))
    end
  end)

  ------------------------------------------------------------------
  -- Fail gates. Both are real Showdown onTry conditions; each returns nil to
  -- let the move proceed or "fail" to be announced-and-marked-missed through
  -- modern_action_order's reusable wrap (PP still spent, exactly like the
  -- real move). Gen 2 (the wrap lives inside Battle:useMove).
  ------------------------------------------------------------------
  local function itemOf(who)
    -- Gen 2 hands the raw mon (.item); Gen 1 hands a battler wrapper whose
    -- mon carries it. modern_items' own itemOf export is gen2-flag-scoped,
    -- so read the field directly here (the exact field Showdown's `!!target
    -- .item` tests).
    return who and (who.item or (who.mon and who.mon.item)) or nil
  end

  -- Exported as their own named functions (not inline closures) so the
  -- harness can exercise the two real predicates directly -- the same
  -- "extract the decision, register it, test it" shape modern_charge_moves'
  -- applyChargeTurnBonus already uses.
  function mod.exports.poltergeistGate(battle, attacker, defender)
    -- onTry: `return !!target.item` -- fails unless the target holds an item.
    if itemOf(defender) then return nil end
    return "fail"
  end
  function mod.exports.steelRollerGate(battle, attacker, defender)
    -- onTry: `return !this.field.isTerrain('')` -- fails with no terrain up.
    if battle and battle.terrain then return nil end
    return "fail"
  end

  registerFailGate("POLTERGEIST", mod.exports.poltergeistGate)
  registerFailGate("STEELROLLER", mod.exports.steelRollerGate)

  mod.log:info("g9-battle-engine: modern_guard_contact installed "
    .. "(Phantom Force / Shadow Force / Hyperspace Hole protect-break; Chip Away / "
    .. "Sacred Sword / Darkest Lariat ignore-defensive+evasion; Moongeist Beam / "
    .. "Sunsteel Strike ignore-ability; Ice Spinner / Steel Roller terrain clear; "
    .. "Thousand Waves trap; Freezy Frost reset; Ceaseless Edge Spikes; Stone Axe "
    .. "Stealth Rock; Fell Stinger KO boost; Poltergeist / Steel Roller fail gates)")
end
