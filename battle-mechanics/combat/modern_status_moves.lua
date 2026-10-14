-- Phase 21 of the missing-effects pipeline: status/volatile infliction
-- residue -- the nine remaining status-family moves whose real effect
-- national_dex leaves unmodeled. They split into five shapes:
--
--   PP DRAIN (Spite, Eerie Spell)
--     Spite is a status move that cuts the target's LAST-USED move's PP by
--     up to 4 (failing outright when nothing is deducted); Eerie Spell is a
--     damaging move whose 100% secondary does the same by up to 3. Both read
--     the target's real last move -- Gen 2's volatile(mon).lastMove, Gen 1's
--     battler.lastMove -- the same field Disable/Instruct already read. The
--     slot match + deduct is exactly Showdown's Pokemon#deductPP (sim/
--     pokemon.ts:888-900: subtract `amount`, clamp at 0, RETURN the amount
--     actually removed -- 0 means the move fails).
--
--   STATUS CURE RIDER (Sparkling Aria)
--     A damaging Water move whose secondary marks each hit target, then
--     cures that target's burn after the move resolves (moves.ts:17358-17388
--     -- the volatile is only a marker so Shield Dust / Sheer Force behave,
--     and onAfterMove cures a burned target that actually took the marker).
--     In this engine's 1-vs-1 shape that reduces to: on a landed hit, cure
--     the target's burn.
--
--   TYPE ADDITION (Forest's Curse, Trick-or-Treat)
--     Adds Grass / Ghost to the target WITHOUT replacing its existing types
--     (moves.ts:6126-6145 / 19913-19934), failing if the target already has
--     that type. Showdown models it as a single `addedType` slot
--     (pokemon.ts:2132-2136): a second add REPLACES the first, and
--     getTypes() appends it to the base list. This is the one mechanic
--     combat/type_override_primitives.lua's own header explicitly names as
--     out of its scope (that primitive only ever REPLACES the whole list),
--     so this file owns a small `addMonType` that appends and books the
--     added type on mon.addedType.
--
--   RAW-STAT SWAP (Power Trick)
--     A self volatile that swaps the user's stored Attack and Defense
--     (moves.ts:13812-13845): onStart swaps, onEnd swaps back, onRestart
--     removes it. Functionally the same mechanic as Power Shift (which
--     combat/modern_stat_manipulation.lua already models), so this file
--     mirrors that file's shape -- raw stats on `mon.stats`, swapped back on
--     switch-out by its OWN listeners (deliberately NOT in
--     status_condition_cleanup's SWITCH_SCOPED list, which could only nil a
--     flag, never swap the stats back).
--
--   GROUND IMMUNITY VOLATILE (Magnet Rise)
--     A self volatile, duration 5, granting immunity to Ground-type moves
--     (moves.ts:10854-10891). Fails under ingrain / smackdown / Gravity. The
--     turn counter rides on the mon (like Telekinesis's telekinesisTurns),
--     and the immunity is resolved where Telekinesis's own is -- combat/
--     modern_combat.lua's resolvedTypeMult.
--
-- Two of the plan's nine need NO wiring at all, recorded honestly rather
-- than faked:
--   * WILLOWISP is already native on Gen 2 -- national_dex's registry_gen2
--     gives it `effect = "EFFECT_BURN", effectModeled = true`, and Gen 2's
--     own EFFECT_BURN applies the burn. Nothing is repointed for it HERE.
--     (Its Gen 1 entry IS unmodeled -- national_dex registers it with the
--     inert NO_ADDITIONAL_EFFECT placeholder -- and that Gen-1 half is now
--     owned by combat/modern_primary_status_moves.lua, which wires every
--     ailment status move national_dex leaves unmodeled for the running
--     generation. Round 398; see that file's own header.)
--   * POLLENPUFF's only real effect beyond its plain 90-BP damage is an
--     ALLY heal (moves.ts:13563-13586: `if (source.isAlly(target))`). This
--     engine's default format is 1-vs-1, where a target is never the user's
--     ally, so the heal has no reachable trigger -- the identical structural
--     no-op class as Flame Burst's ally splash in phase 19. Its damage is
--     native and correct.
--
-- Showdown source of truth (scratch/showdown/*, cited per clause above):
--   willowisp (20888), spite (17640), forestscurse (6126), trickortreat
--   (19913), powertrick (13812), magnetrise (10854), eeriespell (4459),
--   sparklingaria (17358), pollenpuff (13563); pokemon.ts deductPP (888),
--   addType/getTypes (2132/2138).
--
-- Gen 1: this mod's own manifest declares gen2 only, so the type/stat
-- machinery targets Gen 2's raw-mon fields; every handler still routes
-- through normalize() and reads the Gen 1 last-move field so a Gen 1 caller
-- cannot crash, but the type-add / raw-stat / immunity halves are gated to
-- what each generation actually stores (the same honest split
-- combat/modern_stat_manipulation.lua documents).
return function(mod)
  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  local canonicalStatusOf = mod.exports.canonicalStatusOf
  local canChangeType = mod.exports.canChangeType
  assert(normalize and displayNameFor and isGen2Battle,
    "modern_status_moves: combat/modern_combat.lua must load first")

  local Strings = require("src.core.Strings")

  local nationalDex = mod.find and mod.find("national_dex")
  local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById

  ------------------------------------------------------------------
  -- Shared helpers (mirroring modern_pivot_moves.lua's own locally
  -- re-declared shapes so this file has no boot-order dependency on it).
  ------------------------------------------------------------------

  local function monOf(who, gen2)
    if not who then return nil end
    return (gen2 and who) or who.mon
  end

  local function say(battle, text)
    if not (battle and text) then return end
    if battle.emit then
      battle:emit({ kind = "message", text = text })
    elseif battle.sayNext then
      battle.sayNext(text)
    end
  end

  -- Gen 2's dispatch discards a run()'s return value, so the handler emits
  -- each line itself; Gen 1 returns the list for performMove's sayNext loop.
  local function finish(battle, lines)
    if isGen2Battle(battle) then
      for i = 1, #lines do say(battle, lines[i]) end
      return {}
    end
    return lines
  end

  local function failed(battle)
    say(battle, Strings("But it failed!"))
    if not isGen2Battle(battle) then return { Strings("But it failed!") } end
    return {}
  end

  local function moveNameOf(battle, moveId)
    if not moveId then return "move" end
    local ok, def = pcall(battle.moveDef, battle, moveId)
    if ok and def and def.name then return def.name end
    if moveById then
      local ok2, info = pcall(moveById, moveId)
      if ok2 and info and info.name then return info.name end
    end
    return tostring(moveId)
  end

  -- The target's own last-used move id, from whichever field its
  -- generation stores it in (the same probe modern_status_volatiles.lua's
  -- Disable handler and modern_pivot_moves.lua's Instruct handler use).
  local function lastMoveOf(battle, who, gen2)
    if not who then return nil end
    if gen2 and type(battle.volatile) == "function" then
      local vol = battle:volatile(who)
      return vol and vol.lastMove or nil
    end
    return who.lastMove or (who.mon and who.mon.lastMove)
  end

  -- The real move slot for an id on the raw mon (Gen 2: mon.moves, the same
  -- save-file slot table Sketch rewrites).
  local function moveSlotOf(mon, moveId)
    if not (mon and moveId) then return nil end
    for _, slot in ipairs(mon.moves or {}) do
      if slot and slot.id == moveId then return slot end
    end
    return nil
  end

  -- Showdown Pokemon#deductPP (pokemon.ts:888-900): subtract up to `amount`,
  -- clamp at 0, return the amount ACTUALLY removed (0 = nothing happened).
  local function deductPP(slot, amount)
    local pp = (slot and slot.pp) or 0
    if pp <= 0 then return 0 end
    local take = math.min(amount, pp)
    slot.pp = pp - take
    return take
  end

  local function hasSubstitute(battle, who, gen2)
    if not who then return false end
    if gen2 then
      if type(battle.volatile) ~= "function" then return false end
      local vol = battle:volatile(who)
      return (vol and vol.substitute or 0) > 0
    end
    return (who.substituteHP or 0) > 0
  end

  local function cureStatus(mon)
    if not mon then return end
    mon.status = nil
    mon.statusTurns = nil
    mon.toxicCounter = nil
    mon.sleepTurns = nil
  end

  ------------------------------------------------------------------
  -- Type addition: a single added-type slot (Showdown's `addedType`).
  ------------------------------------------------------------------
  local function typesOf(mon)
    if not mon then return nil end
    return mon.types or mon.curTypes
  end

  local function hasMonType(mon, wanted)
    for _, t in ipairs(typesOf(mon) or {}) do
      if t == wanted then return true end
    end
    return false
  end

  -- Appends newType to the mon's live type list. A previous added type is
  -- removed first (Showdown keeps exactly ONE addedType slot), so casting
  -- Forest's Curse then Trick-or-Treat swaps Grass for Ghost rather than
  -- stacking three types. Returns false when the mon already has the type.
  function mod.exports.addMonType(mon, newType)
    if not (mon and newType) then return false end
    local types = typesOf(mon)
    if type(types) ~= "table" then return false end
    if hasMonType(mon, newType) then return false end
    local prev = mon.addedType
    if prev and prev ~= newType then
      for i = #types, 1, -1 do
        if types[i] == prev then table.remove(types, i) end
      end
    end
    types[#types + 1] = newType
    mon.addedType = newType
    return true
  end
  mod.exports.hasMonType = hasMonType

  local function registerAddType(effectId, moveId, wanted, label)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      accuracyChecked = true,
      run = function(a, b, c)
        local n = normalize(a, b, c)
        local battle, user, target = n.battle, n.user, n.target
        if not (battle and user and target) then return end
        local gen2 = isGen2Battle(battle)
        local targetMon = monOf(target, gen2)
        if not targetMon then return failed(battle) end
        if hasSubstitute(battle, target, gen2) then return failed(battle) end
        if canChangeType and not canChangeType(battle, targetMon, { viaOpponent = true }) then
          return failed(battle)
        end
        if hasMonType(targetMon, wanted) then return failed(battle) end
        if not mod.exports.addMonType(targetMon, wanted) then return failed(battle) end
        return finish(battle, { Strings("%s's type\nchanged to %s!",
          displayNameFor(battle, target, gen2), label) })
      end,
    })
    mod.content.moves:patch(moveId, { effect = effectId })
  end

  registerAddType("G9_FORESTSCURSE_EFFECT", "FORESTSCURSE", "GRASS", "Grass")
  registerAddType("G9_TRICKORTREAT_EFFECT", "TRICKORTREAT", "GHOST", "Ghost")

  ------------------------------------------------------------------
  -- SPITE -- cut the target's last-used move's PP by up to 4.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_SPITE_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user and target) then return end
      local gen2 = isGen2Battle(battle)
      local last = lastMoveOf(battle, target, gen2)
      if not last or last == "STRUGGLE" then return failed(battle) end
      local targetMon = monOf(target, gen2)
      local slot = moveSlotOf(targetMon, last)
      if not slot then return failed(battle) end
      local deducted = deductPP(slot, 4)
      if deducted <= 0 then return failed(battle) end
      return finish(battle, { Strings("%s's %s\nhad its PP reduced!",
        displayNameFor(battle, target, gen2), moveNameOf(battle, last)) })
    end,
  })
  mod.content.moves:patch("SPITE", { effect = "G9_SPITE_EFFECT" })

  ------------------------------------------------------------------
  -- POWER TRICK -- swap the user's stored Attack and Defense.
  ------------------------------------------------------------------
  -- Same raw-stat shape as modern_stat_manipulation.lua's Power Shift, but
  -- under its own fields so the two volatiles can never collide.
  local function rawStatOf(mon, key)
    local stats = mon and mon.stats
    return stats and stats[key] or nil
  end
  local function setRawStat(mon, key, value)
    if mon and mon.stats then mon.stats[key] = value end
  end

  local function revertPowerTrick(battle, who, gen2)
    local m = monOf(who, gen2)
    if not (m and m.powerTrickActive) then return end
    local pre = m.powerTrickPre
    if pre then
      setRawStat(m, "attack", pre.attack)
      setRawStat(m, "defense", pre.defense)
    end
    m.powerTrickActive = nil
    m.powerTrickPre = nil
  end
  mod.exports.revertPowerTrick = revertPowerTrick

  mod.content.move_effects:register("G9_POWERTRICK_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      local user = n.user or n.target
      if not (battle and user) then return end
      local gen2 = isGen2Battle(battle)
      local m = monOf(user, gen2)
      if not m or not m.stats then return failed(battle) end
      if m.powerTrickActive then
        -- Showdown's onRestart removes the volatile -> the swap-back. A
        -- second use toggles the trick off rather than swapping again.
        revertPowerTrick(battle, user, gen2)
        return finish(battle, { Strings("%s's Power\nTrick wore off!",
          displayNameFor(battle, user, gen2)) })
      end
      local atk = rawStatOf(m, "attack") or 0
      local def = rawStatOf(m, "defense") or 0
      m.powerTrickPre = { attack = atk, defense = def }
      setRawStat(m, "attack", def)
      setRawStat(m, "defense", atk)
      m.powerTrickActive = true
      return finish(battle, { Strings("%s switched its\nAttack and Defense!",
        displayNameFor(battle, user, gen2)) })
    end,
  })
  mod.content.moves:patch("POWERTRICK", { effect = "G9_POWERTRICK_EFFECT" })

  -- Battle end must hand the raw stats back too (the party table is the
  -- save file, so a leaked swap would persist past the battle).
  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    revertPowerTrick(battle, ev.previous, isGen2Battle(battle))
  end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    local actives = (mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle))
      or { battle.player, battle.enemy }
    for i = 1, #actives do revertPowerTrick(battle, actives[i], gen2) end
    local parties = { battle.party, battle.enemyParty, battle.playerParty }
    for p = 1, #parties do
      local party = parties[p]
      if type(party) == "table" then
        for i = 1, #party do revertPowerTrick(battle, party[i], gen2) end
      end
    end
  end)

  ------------------------------------------------------------------
  -- MAGNET RISE -- 5-turn Ground immunity, self.
  ------------------------------------------------------------------
  -- The counter + the resolvedTypeMult check mirror Telekinesis's own
  -- (see combat/modern_status_volatiles.lua), and "magnetRiseTurns" is added
  -- to status_condition_cleanup.lua's SWITCH_SCOPED list so a switch drops
  -- the volatile like the real one.
  mod.content.move_effects:register("G9_MAGNETRISE_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      local user = n.user or n.target
      if not (battle and user) then return end
      local gen2 = isGen2Battle(battle)
      local m = monOf(user, gen2)
      if not m then return failed(battle) end
      if m.ingrained or m.groundedByMove or (battle.gravityTurns or 0) > 0 then
        return failed(battle)
      end
      m.magnetRiseTurns = 5
      return finish(battle, { Strings("%s levitated\nwith electromagnetism!",
        displayNameFor(battle, user, gen2)) })
    end,
  })
  mod.content.moves:patch("MAGNETRISE", { effect = "G9_MAGNETRISE_EFFECT" })

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local actives = (mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle))
      or { battle.player, battle.enemy }
    for _, who in ipairs(actives) do
      local m = monOf(who, isGen2Battle(battle))
      if m and m.magnetRiseTurns then
        m.magnetRiseTurns = m.magnetRiseTurns - 1
        if m.magnetRiseTurns <= 0 then m.magnetRiseTurns = nil end
      end
    end
  end)

  ------------------------------------------------------------------
  -- Damage-move riders: Eerie Spell's PP secondary, Sparkling Aria's burn
  -- cure. Neither move is repointed -- their damage is already native
  -- (national_dex registers both EFFECT_NORMAL_HIT / effectModeled=true),
  -- so a run() record would pre-empt the damage. Both ride the same
  -- battle.damage_dealt seam the phase-18/19 on-hit riders use.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    local moveId = ev and (ev.moveId or (ev.move and ev.move.id))
    if not (battle and user and target and moveId) then return end
    if (ev.damage or 0) <= 0 or user == target then return end
    local gen2 = isGen2Battle(battle)
    local ok, err = pcall(function()
      if moveId == "EERIESPELL" then
        -- secondary.onHit, 100%: -3 PP on the target's last-used move.
        local last = lastMoveOf(battle, target, gen2)
        if not last or last == "STRUGGLE" then return end
        local slot = moveSlotOf(monOf(target, gen2), last)
        if not slot then return end
        local deducted = deductPP(slot, 3)
        if deducted <= 0 then return end
        say(battle, Strings("%s's %s\nhad its PP reduced!",
          displayNameFor(battle, target, gen2), moveNameOf(battle, last)))

      elseif moveId == "SPARKLINGARIA" then
        -- onAfterMove: cure a burned target that took the secondary marker.
        local targetMon = monOf(target, gen2)
        local status = canonicalStatusOf and canonicalStatusOf(targetMon)
        if targetMon and status == "burn" then
          cureStatus(targetMon)
          say(battle, Strings("%s's burn\nwas cured!",
            displayNameFor(battle, target, gen2)))
        end
      end
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: modern_status_moves: %s rider failed: %s",
        tostring(moveId), tostring(err))
    end
  end)

  mod.log:info("g9-battle-engine: modern_status_moves installed "
    .. "(SPITE, EERIESPELL, SPARKLINGARIA, FORESTSCURSE, TRICKORTREAT, "
    .. "POWERTRICK, MAGNETRISE; WILLOWISP gen2-native, POLLENPUFF ally-only; "
    .. "WILLOWISP's unmodeled Gen-1 half lives in modern_primary_status_moves)")
end
