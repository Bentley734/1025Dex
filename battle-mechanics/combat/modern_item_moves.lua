-- Missing-effects plan, Phase 19: item / held-item interaction.
--
-- Verified against Showdown's own real source this pass (data/moves.ts, each
-- record read directly) plus this engine's item primitives
-- (combat/modern_items.lua, which owns the mod's held-item vocabulary --
-- the gen-aware itemOf/setItemOf pair, isUnremovable, itemLabel). Eight moves,
-- six real mechanics:
--
--   ITEM SWAP (Trick / Switcheroo)
--     TRICK (moves.ts:19866), SWITCHEROO (moves.ts:18645) -- onTryImmunity
--       fails when the target has Sticky Hold; onHit takes the target's item
--       then the user's, aborts (restoring BOTH) when either take is refused
--       or both are empty, else swaps the two.
--   ITEM GIVE (Bestow)
--     BESTOW (moves.ts:1237) -- onHit: fail when the target already holds an
--       item or the user has nothing to give; the user's item moves across.
--   ITEM STEAL-ON-HIT (Thief)
--     THIEF (moves.ts:19303) -- onAfterHit: if the user holds nothing, steal
--       the target's removable item (the exact Covet shape modern_items
--       already ships, Thief being its twin).
--   BOOST STEAL (Spectral Thief)
--     SPECTRALTHIEF (moves.ts:17415, `stealsBoosts: true`; the real mechanic
--       is battle-actions.ts:781-809 hitStepStealBoosts) -- before the hit
--       resolves, every POSITIVE stage the target has is copied onto the user
--       and zeroed on the target.
--   ABILITY SUPPRESSION-ON-HIT (Core Enforcer)
--     COREENFORCER (moves.ts:2874) -- onHit / onAfterSubDamage: suppress the
--       target's ability (Gastro Acid's suppression) unless it carries
--       `cantsuppress`, just switched in, or has yet to move this turn.
--   PSEUDO-WEATHER (Plasma Fists)
--     PLASMAFISTS (moves.ts:13389) -- `pseudoWeather: 'iondeluge'`: sets Ion
--       Deluge for the rest of the turn, so every Normal-type move becomes
--       Electric (combat/modern_field_effects.lua's own `battle.ionDelugeTurns`
--       + `effectiveMoveType`).
--   ALLY SPLASH (Flame Burst)
--     FLAMEBURST (moves.ts:5564) -- onHit: 1/16 max HP to each of the target's
--       ADJACENT ALLIES. In this engine's 1-vs-1 reduction a target has no
--       allies, so the loop is genuinely empty: the move keeps its plain,
--       already-correct damage and nothing else happens (recorded honestly,
--       not faked).
--
-- SEAMS USED, all pre-existing:
--   * Item reads/writes go through combat/modern_items.lua's gen-aware
--     itemOf/setItemOf pair -- Gen 2's raw `mon.item`, Gen 1's `g9HeldItem`
--     save slot (combat/modern_held_item_api.lua) -- so every move here acts
--     on BOTH generations. The removal refusal is that file's exported
--     `isUnremovable` (the Mail exemption) plus Sticky Hold (the real
--     TakeItem refusal); the ability check unwraps a Gen-1 battler wrapper
--     first (abilities live on the raw mon), the same fix modern_items.lua's
--     heldAbilityIdOf makes.
--   * Ability suppression reuses abilities/ability_dispatch.lua's `setAbility`
--     (the same call the Gastro Acid move makes) and
--     combat/modern_ability_change_moves.lua's exported CANNOT_SUPPRESS set,
--     so Core Enforcer and the ability-change moves can never drift apart.
--   * Spectral Thief's atk/def/spa/spd reads/writes ride
--     combat/modern_combat.lua's `stagesFor` + `changeStage`; the native
--     speed/accuracy/evasion half writes the same per-side (Gen 2) /
--     per-mon (Gen 1) stage store abilities/engine/accuracy_multiplier.lua and
--     modern_movepool_stages.lua already use.
--   * Plasma Fists sets `battle.ionDelugeTurns` directly -- the field
--     modern_field_effects.lua's own Ion Deluge sets and its turn_ended tick
--     clears.
--   * Every on-hit rider is a `battle.damage_dealt` listener keyed by move id
--     (the modern_items / Phase 18 precedent), so it can never eat the hit.
--
-- HONEST PARTIALS (documented, not faked):
--   * Core Enforcer and Flame Burst's real `onAfterSubDamage` half is not
--     modelled: this engine's dealDamage absorbs a Substitute hit and returns
--     BEFORE it emits battle.damage_dealt (gen2/Battle.lua dealDamage's own
--     substitute branch), so there is no sub-damage seam to hang the effect
--     on -- the same documented gap every bypasssub move here carries.
--   * Gen 1 acts on the stored `g9HeldItem` item for real (round 99): Trick /
--     Switcheroo / Bestow / Thief / Corrosive-Gas-style removal all move the
--     saved item, and the riders run. Core Enforcer unwraps to the raw mon
--     (that is where `ability` lives). Nothing here is a Gen-1 no-op any more.
--   * Bestow carries `bypasssub` in Showdown; Substitute redirection is not a
--     seam this mod hooks (same gap as above).
return function(mod)
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  local changeStage = mod.exports.changeStage
  local stagesFor = mod.exports.stagesFor
  local resolvedTypeMult = mod.exports.resolvedTypeMult
  local isUnremovable = mod.exports.isUnremovable
  local abilityIdOf = mod.exports.abilityIdOf
  local setAbility = mod.exports.setAbility
  local cantsuppress = mod.exports.CANNOT_SUPPRESS
  -- modern_items.lua's round-99 gen-aware item read/write pair + label. This
  -- file used to read `m.item` directly, which is why every move below was
  -- gated `if not n.gen2 then fail` (a Gen-1 mon has no `item` field, so a
  -- stored Gen-1 item was permanent). itemOf reads the `g9HeldItem` save slot
  -- on Gen 1, setItemOf writes it, and itemLabel gives the no-itemDef Gen-1
  -- message a safe fallback.
  local itemOf = mod.exports.itemOf
  local setItemOf = mod.exports.setItemOf
  local itemLabel = mod.exports.itemLabel
  assert(normalize and displayNameFor and isGen2Battle and changeStage
    and stagesFor and isUnremovable and abilityIdOf and setAbility
    and itemOf and setItemOf and itemLabel,
    "modern_item_moves: combat/modern_combat.lua, combat/modern_items.lua and "
    .. "abilities/ability_dispatch.lua must load first")

  local function gen2Of(battle)
    return isGen2Battle and isGen2Battle(battle) or false
  end

  -- Raw mon behind a Gen 1 battler wrapper, or the mon itself on Gen 2.
  local function rawMon(who)
    return who and (who.mon or who) or nil
  end

  local function itemIdOf(who, gen2)
    return itemOf(who, gen2)
  end

  local function say(battle, text)
    if battle and text and battle.emit then
      battle:emit({ kind = "message", text = text })
    end
  end
  local function nameOf(battle, who, gen2)
    if displayNameFor then
      local ok, n = pcall(displayNameFor, battle, who, gen2)
      if ok and n then return n end
    end
    return (who and who.name) or "The Pokemon"
  end
  local function itemName(battle, item)
    return itemLabel(battle, item)
  end

  -- Pokemon.takeItem's own contract: an item string on success, false when the
  -- take is refused (Sticky Hold -- the real TakeItem refusal -- or this mod's
  -- Mail `isUnremovable` exemption), nil when there is nothing to take.
  -- `gen2` selects the read/write slot (modern_items' gen-aware itemOf/
  -- setItemOf), and the ability check unwraps a Gen-1 battler wrapper for the
  -- same reason heldAbilityIdOf does in modern_items (a wrapper has no
  -- `ability` field of its own).
  local function takeItem(who, gen2)
    local item = itemIdOf(who, gen2)
    if not item then return nil end
    local ability = abilityIdOf and abilityIdOf(rawMon(who))
    if isUnremovable(item) or ability == "STICKYHOLD" then return false end
    setItemOf(who, nil, gen2)
    return item
  end

  -- finish/fail: Gen 2's dispatch ignores a run() handler's return value (so
  -- the Gen 2 lines are emitted here), Gen 1 returns the list -- the exact
  -- cross-generation convention modern_stat_manipulation.lua's own finish()
  -- established.
  local function finish(n, lines)
    if n.gen2 then
      for i = 1, #lines do say(n.battle, lines[i]) end
      return {}
    end
    return lines
  end
  local function fail(n)
    return finish(n, { romText(n.battle.data, "_ButItFailedText", "But, it failed!") })
  end

  ------------------------------------------------------------------
  -- Trick / Switcheroo. Both read the SAME real handler (moves.ts shows
  -- their onHit bodies are byte-identical); only the message name differs.
  ------------------------------------------------------------------
  local function itemSwapRun(a, b, c)
    local n = normalize(a, b, c)
    local battle, user, target = n.battle, n.user, n.target
    -- onTryImmunity: `return !target.hasAbility('stickyhold')`.
    if abilityIdOf(rawMon(target)) == "STICKYHOLD" then return fail(n) end
    local yourItem = takeItem(target, n.gen2)
    local myItem = takeItem(user, n.gen2)
    if yourItem == false or myItem == false
        or (yourItem == nil and myItem == nil) then
      -- Restore whatever actually was taken before aborting.
      if yourItem and yourItem ~= false then setItemOf(target, yourItem, n.gen2) end
      if myItem and myItem ~= false then setItemOf(user, myItem, n.gen2) end
      return fail(n)
    end
    if myItem then setItemOf(target, myItem, n.gen2) end
    if yourItem then setItemOf(user, yourItem, n.gen2) end
    return finish(n, { Strings("%s switched items\\nwith %s!",
      nameOf(battle, user, n.gen2), nameOf(battle, target, n.gen2)) })
  end
  mod.content.move_effects:register("GALAR_TRICK_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = itemSwapRun,
  })
  mod.content.move_effects:register("GALAR_SWITCHEROO_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = itemSwapRun,
  })
  mod.content.moves:patch("TRICK", { effect = "GALAR_TRICK_EFFECT" })
  mod.content.moves:patch("SWITCHEROO", { effect = "GALAR_SWITCHEROO_EFFECT" })

  ------------------------------------------------------------------
  -- Bestow. accuracy:true (never misses), so no accuracyChecked -- the same
  -- rule modern_stat_manipulation's registerPrimary documents for a move the
  -- dex gives no accuracy number.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_BESTOW_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if itemIdOf(target, n.gen2) then return fail(n) end
      local myItem = takeItem(user, n.gen2)
      if not myItem or myItem == false then return fail(n) end
      setItemOf(target, myItem, n.gen2)
      return finish(n, { Strings("%s received\\n%s from %s!",
        nameOf(battle, target, n.gen2), itemName(battle, myItem),
        nameOf(battle, user, n.gen2)) })
    end,
  })
  mod.content.moves:patch("BESTOW", { effect = "GALAR_BESTOW_EFFECT" })

  ------------------------------------------------------------------
  -- Spectral Thief's boost steal. battle-actions.ts:781-809
  -- hitStepStealBoosts copies every POSITIVE stage onto the user, emits
  -- -clearpositiveboost, then zeroes them on the target. Runs BEFORE the
  -- damage step (the real hit-step order), so the stolen Attack boosts the
  -- very hit that takes it. Exported as its own named function (not an inline
  -- closure) so the harness can exercise it directly -- the same
  -- "extract the decision, register it, test it" shape Phase 18's fail gates
  -- use.
  ------------------------------------------------------------------
  -- The native speed/accuracy/evasion store for a battler (the four
  -- atk/def/spa/spd live in modern_combat's own stagesFor bucket; these three
  -- stay native -- the boundary modern_movepool_stages.lua's own stageValue
  -- documents). Gen 2: battle.stages[side]; Gen 1: the wrapper's own .stages.
  local function nativeStageStore(battle, who, gen2)
    if gen2 then
      local side = battle.sideOf and battle:sideOf(who)
      if not side then return nil end
      battle.stages = battle.stages or { player = {}, enemy = {} }
      battle.stages[side] = battle.stages[side] or {}
      return battle.stages[side]
    end
    local m = rawMon(who)
    if not m then return nil end
    m.stages = m.stages or {}
    return m.stages
  end
  local NATIVE_BOOST_LABEL = { speed = "Speed", accuracy = "accuracy", evasion = "evasiveness" }

  function mod.exports.spectralThiefStealBoosts(battle, user, target, gen2)
    gen2 = gen2 or gen2Of(battle)
    if not (battle and user and target and user ~= target) then return false end
    local tStages = stagesFor(battle, target) or {}
    local stolen, nativeStolen, any = {}, {}, false
    for _, stat in ipairs({ "attack", "defense", "spa", "spd" }) do
      local stage = tStages[stat] or 0
      if stage > 0 then stolen[stat] = stage; any = true end
    end
    local nStore = nativeStageStore(battle, target, gen2)
    if nStore then
      for _, stat in ipairs({ "speed", "accuracy", "evasion" }) do
        local stage = nStore[stat] or 0
        if stage > 0 then nativeStolen[stat] = stage; any = true end
      end
    end
    if not any then return false end
    for stat, stage in pairs(stolen) do
      -- changeStage with fromEnemy=false: neither half is a "hostile drop",
      -- so Mist/Substitute and Defiant/Competitive must not gate or answer it
      -- (Showdown's own boost()/setBoost() are direct writes).
      for _, line in ipairs(changeStage(battle, user, stat, stage, false, gen2) or {}) do
        say(battle, line)
      end
      for _, line in ipairs(changeStage(battle, target, stat, -stage, false, gen2) or {}) do
        say(battle, line)
      end
    end
    local uStore = nativeStageStore(battle, user, gen2)
    local ttStore = nativeStageStore(battle, target, gen2)
    for stat, stage in pairs(nativeStolen) do
      if uStore then
        uStore[stat] = math.max(-6, math.min(6, (uStore[stat] or 0) + stage))
      end
      if ttStore then
        ttStore[stat] = math.max(-6, math.min(6, (ttStore[stat] or 0) - stage))
      end
      say(battle, Strings("%s's\\n%s rose!", nameOf(battle, user, gen2),
        NATIVE_BOOST_LABEL[stat] or stat))
      say(battle, Strings("%s's\\n%s fell!", nameOf(battle, target, gen2),
        NATIVE_BOOST_LABEL[stat] or stat))
    end
    say(battle, Strings("%s stole\\n%s's stat boosts!",
      nameOf(battle, user, gen2), nameOf(battle, target, gen2)))
    return true
  end

  -- The pre-damage half. Priority 100 keeps it outside modern_combat's own
  -- formula hook (0) and modern_guard_contact's ignore-ability wrap (100, a
  -- different move so never both), so the steal lands BEFORE the hit is
  -- computed -- exactly hitStepStealBoosts' position ahead of
  -- hitStepMoveHitLoop. Showdown checks type immunity (hitStepTypeImmunity)
  -- before the steal step, so an immune hit never steals; resolvedTypeMult is
  -- the mod's own fully-resolved replacement for that check.
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move = ctx and ctx.move
    local moveId = move and move.id or (ctx and ctx.moveId)
    if moveId ~= "SPECTRALTHIEF" then return next(ctx) end
    local battle, user, target = ctx.battle, ctx.user, ctx.target
    local gen2 = gen2Of(battle)
    -- Runs for both generations (round 99): the steal itself is built purely
    -- from modern_combat's cross-gen stagesFor/changeStage plus the native
    -- stage store, which nativeStageStore already serves per-generation. It
    -- used to be Gen-2-gated purely as a "Gen 1 has no items" assumption.
    if user and target and user ~= target then
      local immune = false
      if resolvedTypeMult and move.type then
        local mt = move.type
        local eff = mod.exports.effectiveMoveType
        if eff then mt = eff(battle, user, mt, moveId) end
        local mult = resolvedTypeMult(battle, user, target, gen2, mt)
        if mult ~= nil and mult <= 0 then immune = true end
      end
      if not immune then
        local ok, err = pcall(mod.exports.spectralThiefStealBoosts, battle, user, target, gen2)
        if not ok then
          mod.log:warn("g9-battle-engine: modern_item_moves: Spectral Thief "
            .. "boost steal failed: %s", tostring(err))
        end
      end
    end
    return next(ctx)
  end, 100)

  ------------------------------------------------------------------
  -- Core Enforcer's ability suppression. Showdown: skip when the target's
  -- ability is `cantsuppress`, when it newly switched in, or when it is still
  -- to move this turn -- then add the gastroacid volatile. This engine's
  -- Gastro Acid move suppresses by calling setAbility(..., nil) directly, so
  -- Core Enforcer makes the SAME call. `newlySwitched` is subsumed: a mon that
  -- just switched in has not moved this turn, so the moved-this-turn test
  -- already covers it.
  ------------------------------------------------------------------
  local function movedThisTurn(battle, who)
    -- The flag combat/modern_power_conditions.lua's own battle.move_used
    -- listener writes -- the direct analogue of Showdown's queue.willMove
    -- returning null once the mon has acted. Gen 1 stores it on whichever
    -- object that listener received, so accept the battler OR its raw mon.
    if gen2Of(battle) then return battle:volatile(who).movedThisTurn == true end
    if who and who.movedThisTurn == true then return true end
    local m = rawMon(who)
    return (m and m.movedThisTurn == true) or false
  end

  local function coreEnforcerSuppress(battle, target, gen2)
    -- Abilities live on the RAW mon (stats/engine_modern_stats.lua writes
    -- `mon.ability`), and a Gen-1 battler is a wrapper -- so unwrap before
    -- both the read and the setAbility call, or the suppression would land on
    -- a throwaway wrapper table.
    local m = rawMon(target) or target
    local tid = abilityIdOf(m)
    if not tid then return false end
    if cantsuppress and cantsuppress[tid] then return false end
    if not movedThisTurn(battle, target) then return false end
    local changed = setAbility(battle, m, nil)
    if changed == false then return false end
    say(battle, Strings("%s's ability\\nwas suppressed!", nameOf(battle, target, gen2)))
    return true
  end
  mod.exports.coreEnforcerSuppress = coreEnforcerSuppress

  ------------------------------------------------------------------
  -- Flame Burst's ally splash. Real code, genuinely no targets in 1-vs-1: a
  -- target side has no other active battler, so the loop runs empty. Kept
  -- faithful (a same-side, non-target active) so a future multi-battler
  -- engine inherits the real behaviour rather than a hardcoded no-op.
  ------------------------------------------------------------------
  local function flameBurstSplash(battle, user, target, gen2)
    -- Lazy lookup (the same pattern modern_field_effects' own activeList
    -- uses), so the harness can exercise this against a stubbed roster.
    local list = mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle)
      or { battle.player, battle.enemy }
    local tSide = battle.sideOf and battle:sideOf(target)
    for _, who in ipairs(list) do
      if who and who ~= target and battle:sideOf(who) == tSide then
        local m = rawMon(who)
        local maxHp = (m and (m.maxHp or (m.stats and m.stats.hp))) or 0
        local dmg = math.max(1, math.floor(maxHp / 16))
        m.hp = math.max(0, (m.hp or 0) - dmg)
        if battle.emit then
          battle:emit({ kind = "damage", side = tSide, amount = dmg,
            hp = m.hp, anim = false })
        end
      end
    end
  end
  mod.exports.flameBurstSplash = flameBurstSplash

  ------------------------------------------------------------------
  -- The on-hit riders. One battle.damage_dealt listener keyed by move id, so
  -- the lookup stays small and every entry is a real Showdown callback. All
  -- run on both generations (round 99): item reads/writes are gen-aware
  -- (itemOf/setItemOf), Core Enforcer's suppression unwraps to the raw mon
  -- that actually carries `ability`, and the Plasma Fists / Flame Burst
  -- effects are generation-independent field/splash writes.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    local moveId = ev and (ev.moveId or (ev.move and ev.move.id))
    if not (battle and user and target and moveId) then return end
    if (ev.damage or 0) <= 0 or user == target then return end
    local gen2 = gen2Of(battle)
    local ok, err = pcall(function()
      if moveId == "THIEF" then
        if itemIdOf(user, gen2) then return end
        local item = takeItem(target, gen2)
        if not item or item == false then return end
        setItemOf(user, item, gen2)
        say(battle, Strings("%s stole %s's\\n%s!",
          nameOf(battle, user, gen2), nameOf(battle, target, gen2),
          itemName(battle, item)))

      elseif moveId == "COREENFORCER" then
        coreEnforcerSuppress(battle, target, gen2)

      elseif moveId == "PLASMAFISTS" then
        if (battle.ionDelugeTurns or 0) <= 0 then
          battle.ionDelugeTurns = 1
          say(battle, Strings("A deluge of ions showers the battlefield!"))
        end

      elseif moveId == "FLAMEBURST" then
        flameBurstSplash(battle, user, target, gen2)
      end
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: modern_item_moves: %s rider failed: %s",
        tostring(moveId), tostring(err))
    end
  end)

  ------------------------------------------------------------------
  -- Stub-audit markers: one empty kind="full" record per damaging move (the
  -- established Fling/Knock Off precedent for "real damage, real effect lives
  -- in a side hook, not in .run"), patched onto each move purely so
  -- moves_new.lua's own effect field stops reading NO_ADDITIONAL_EFFECT --
  -- this project's own stub marker. Every real effect above is fully
  -- implemented even though none of the logic lives inside these records.
  ------------------------------------------------------------------
  for _, id in ipairs({
    "GALAR_THIEF_EFFECT", "GALAR_COREENFORCER_EFFECT",
    "GALAR_SPECTRALTHIEF_EFFECT", "GALAR_PLASMAFISTS_EFFECT",
    "GALAR_FLAMEBURST_EFFECT",
  }) do
    mod.content.move_effects:register(id, { kind = "full" })
  end
  mod.content.moves:patch("THIEF", { effect = "GALAR_THIEF_EFFECT" })
  mod.content.moves:patch("COREENFORCER", { effect = "GALAR_COREENFORCER_EFFECT" })
  mod.content.moves:patch("SPECTRALTHIEF", { effect = "GALAR_SPECTRALTHIEF_EFFECT" })
  mod.content.moves:patch("PLASMAFISTS", { effect = "GALAR_PLASMAFISTS_EFFECT" })
  mod.content.moves:patch("FLAMEBURST", { effect = "GALAR_FLAMEBURST_EFFECT" })

  mod.log:info("g9-battle-engine: modern_item_moves installed "
    .. "(Trick / Switcheroo swap, Bestow give, Thief steal, Spectral Thief "
    .. "boost steal, Core Enforcer suppression, Plasma Fists ion deluge, "
    .. "Flame Burst ally splash)")
end
