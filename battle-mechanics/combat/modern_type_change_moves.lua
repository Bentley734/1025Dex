-- change_type moves: Soak, Magic Powder, Burn Up, Double Shock, Conversion,
-- Reflect Type, Camouflage -- every real Pokemon Showdown move confirmed to
-- call Pokemon#setType (fetched directly from smogon/pokemon-showdown's own
-- data/moves.ts, grepped for every setType call site across the whole
-- file, not assumed from a partial list). Conversion 2 is registered but
-- deliberately left a stub -- see its own section below for the real,
-- honest reason.
--
-- Wiring shape splits in two, matching each move's own real nature:
--
-- Pure status moves (Soak, Magic Powder, Conversion, Reflect Type,
-- Camouflage -- all power=0): kind="primary" run handlers, dispatched
-- directly from Battle:useMove (SUBEFFECTS.md's own citation,
-- gen2/Battle.lua:1533-1538) -- a plain call chain, safe to call
-- mod.exports.setMonTypes straight from here.
--
-- Burn Up / Double Shock: real damaging moves (130/120 power) whose entire
-- "effect" is a self-type-change AFTER a landed hit, gated on the user
-- CURRENTLY having the type it's about to strip (Fire/Electric) -- real PS
-- fails the move outright (onTryMove) otherwise, no damage at all. Wired
-- the same two-part way combat/modern_switch_moves.lua's own U-turn/Volt
-- Switch/Flip Turn are: a Battle:useMove class-level wrap for the
-- pre-check (blocks before native runs, matching modern_terrain.lua's own
-- Psychic Terrain precedent for "fail outright, no damage"), and a
-- battle.damage_dealt listener for the post-hit type change (fired only
-- after a real, landed, non-immune hit -- never called straight off a
-- .run handler, since ANY move_effects record carrying `run` pre-empts
-- Gen 2's own damage path entirely, SUBEFFECTS.md's own documented
-- gotcha).
return function(mod)
  local Strings = require("src.core.Strings")
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  local curTypesOf = mod.exports.curTypesOf
  local setMonTypes = mod.exports.setMonTypes
  local canChangeType = mod.exports.canChangeType
  assert(curTypesOf and setMonTypes and canChangeType,
    "modern_type_change_moves: modern_combat.lua and type_override_primitives.lua must load first")

  local function isMonotype(types, only)
    return #types == 1 and types[1] == only
  end

  ------------------------------------------------------------------
  -- Soak: target becomes pure Water. Fails outright if already pure
  -- Water (real PS: `target.getTypes().join() === 'Water'` -- an exact
  -- single-type match, not "already has Water among its types").
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_SOAK_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(battle, attacker, defender, def, moveId, sureHit)
      if not canChangeType(battle, defender, { viaOpponent = true }) then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      if isMonotype(curTypesOf(defender, true), "WATER") then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      setMonTypes(battle, defender, { "WATER" })
      battle:emit({ kind = "message", text = Strings("%s transformed into a Water type!", battle:monName(defender)) })
    end,
  })
  mod.content.moves:patch("SOAK", { effect = "G9_SOAK_EFFECT" })

  ------------------------------------------------------------------
  -- Magic Powder: target becomes pure Psychic. Same exact-monotype fail
  -- condition as Soak.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_MAGICPOWDER_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(battle, attacker, defender, def, moveId, sureHit)
      if not canChangeType(battle, defender, { viaOpponent = true }) then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      if isMonotype(curTypesOf(defender, true), "PSYCHIC") then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      setMonTypes(battle, defender, { "PSYCHIC" })
      battle:emit({ kind = "message", text = Strings("%s transformed into a Psychic type!", battle:monName(defender)) })
    end,
  })
  mod.content.moves:patch("MAGICPOWDER", { effect = "G9_MAGICPOWDER_EFFECT" })

  ------------------------------------------------------------------
  -- Conversion: user becomes the type of its own FIRST move slot (real
  -- PS reads target.moveSlots[0] specifically, not "any known move") --
  -- confirmed target="self" so `defender` here IS the user's own side.
  -- Fails if that slot has no move, its type can't be found, or the user
  -- is already exactly that one type.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_CONVERSION_EFFECT", {
    kind = "primary",
    run = function(battle, attacker, defender, def, moveId, sureHit)
      if not canChangeType(battle, attacker, { viaOpponent = false }) then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      local firstSlot = attacker.moves and attacker.moves[1]
      local firstDef = firstSlot and battle.data.moves[firstSlot.id]
      local moveType = firstDef and firstDef.type
      if not moveType or isMonotype(curTypesOf(attacker, true), moveType) then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      setMonTypes(battle, attacker, { moveType })
      battle:emit({ kind = "message", text = Strings("%s transformed into the %s type!", battle:monName(attacker), moveType) })
    end,
  })
  mod.content.moves:patch("CONVERSION", { effect = "G9_CONVERSION_EFFECT" })

  ------------------------------------------------------------------
  -- Reflect Type: user copies the target's CURRENT type list wholesale.
  -- Fails if the target has no real types at all (e.g. mid-Burn Up on a
  -- once-monotype Fire mon) -- real PS's own addedType fallback to Normal
  -- is skipped, since this engine has no addedType/Forest's Curse
  -- mechanic to fall back from.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_REFLECTTYPE_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(battle, attacker, defender, def, moveId, sureHit)
      -- The gate applies to attacker (whose type is about to change), not
      -- defender (only ever a copy SOURCE here, not itself changed) -- a
      -- Terastallized/Dynamaxed target can still be copied FROM.
      if not canChangeType(battle, attacker, { viaOpponent = false }) then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      local targetTypes = curTypesOf(defender, true)
      if #targetTypes == 0 then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      setMonTypes(battle, attacker, targetTypes)
      battle:emit({ kind = "message",
        text = Strings("%s's type changed to match %s's!", battle:monName(attacker), battle:monName(defender)) })
    end,
  })
  mod.content.moves:patch("REFLECTTYPE", { effect = "G9_REFLECTTYPE_EFFECT" })

  ------------------------------------------------------------------
  -- Camouflage: user's type set by the active battle Terrain (real PS:
  -- Electric->Electric, Grassy->Grass, Misty->Fairy, Psychic->Psychic,
  -- none active->Normal) -- reuses combat/modern_terrain.lua's own real
  -- battle.terrain field directly (must load after it), not a separate
  -- lookup. Real PS's own OTHER environment sources (cave/water/sand
  -- surroundings from the overworld) don't exist as battle-visible state
  -- in this engine at all, so those branches are unreachable here --
  -- Camouflage always resolves to a Terrain type or Normal, never those
  -- others. A real, honest, narrower-than-PS gap, not silently assumed
  -- complete.
  ------------------------------------------------------------------
  local CAMOUFLAGE_TERRAIN_TYPE = { ELECTRIC = "ELECTRIC", GRASSY = "GRASS", MISTY = "FAIRY", PSYCHIC = "PSYCHIC" }
  mod.content.move_effects:register("G9_CAMOUFLAGE_EFFECT", {
    kind = "primary",
    run = function(battle, attacker, defender, def, moveId, sureHit)
      if not canChangeType(battle, attacker, { viaOpponent = false }) then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      local newType = (battle.terrain and CAMOUFLAGE_TERRAIN_TYPE[battle.terrain]) or "NORMAL"
      if isMonotype(curTypesOf(attacker, true), newType) then
        battle:emit({ kind = "message", text = Strings("But it failed!") })
        return
      end
      setMonTypes(battle, attacker, { newType })
      battle:emit({ kind = "message", text = Strings("%s transformed into the %s type!", battle:monName(attacker), newType) })
    end,
  })
  mod.content.moves:patch("CAMOUFLAGE", { effect = "G9_CAMOUFLAGE_EFFECT" })

  ------------------------------------------------------------------
  -- Burn Up / Double Shock: gate first (Battle:useMove wrap), type change
  -- after a landed hit (battle.damage_dealt listener) -- see this file's
  -- own header for why both pieces are needed and why neither can be a
  -- plain move_effects run handler.
  ------------------------------------------------------------------
  local SELF_TYPE_STRIP = {
    BURNUP = "FIRE",
    DOUBLESHOCK = "ELECTRIC",
  }

  for id in pairs(SELF_TYPE_STRIP) do
    mod.content.move_effects:register("G9_TYPESTRIP_" .. id, { kind = "full" })
    mod.content.moves:patch(id, { effect = "G9_TYPESTRIP_" .. id })
  end

  if Battle then
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      local requiredType = SELF_TYPE_STRIP[moveId]
      if requiredType then
        local has = false
        for _, t in ipairs(curTypesOf(attacker, true)) do
          if t == requiredType then has = true break end
        end
        if not has then
          self:emit({ kind = "message", text = Strings("But it failed!") })
          return
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and (ev.moveId or (ev.move and ev.move.id))
    local user = ev and ev.user
    local requiredType = moveId and SELF_TYPE_STRIP[moveId]
    if not (battle and user and requiredType) then return end
    if (user.hp or 0) <= 0 then return end
    -- Terastallized: damage already landed (real PS behavior -- Burn Up's
    -- own type-strip is a separate, later step from its damage), only the
    -- type-strip itself is skipped, silently -- no extra "but it failed"
    -- on top of a hit that otherwise connected normally.
    if not canChangeType(battle, user, { viaOpponent = false }) then return end
    local remaining = {}
    for _, t in ipairs(curTypesOf(user, true)) do
      if t ~= requiredType then remaining[#remaining + 1] = t end
    end
    setMonTypes(battle, user, remaining)
    battle:emit({ kind = "message", text = Strings("%s's %s type burned up!", battle:monName(user), requiredType:sub(1, 1) .. requiredType:sub(2):lower()) })
  end)

  ------------------------------------------------------------------
  -- Conversion 2: deliberately a stub, not a guess. Real PS picks a
  -- random type that RESISTS or is IMMUNE to the type of whichever move
  -- last hit the user (target.lastMoveUsed) -- this engine tracks neither
  -- piece today: no "type of the last move that hit this mon" tracker
  -- exists anywhere in this mod (mon.volatile.lastMove-style fields here
  -- record the LAST MOVE THE MON ITSELF USED, for Torment/Encore -- a
  -- different thing), and no reverse type-chart lookup ("which of the 18
  -- types resist type X") is exposed by this engine's own damage
  -- primitives, which only ever compute forward (attacker type vs.
  -- defender type), never enumerate the chart's own rows. Registered here
  -- as a real, schema-valid, non-eating "full" stub (so isMoveDataComplete
  -- doesn't misreport it) purely so CONVERSION2 doesn't fall through to an
  -- undocumented no-op -- building the real behavior needs both trackers
  -- first, genuinely new engineering, not folded into this pass.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_CONVERSION2_STUB", { kind = "full" })
  mod.content.moves:patch("CONVERSION2", { effect = "G9_CONVERSION2_STUB" })

  mod.log:info("g9-battle-engine: modern_type_change_moves installed (SOAK, MAGICPOWDER, CONVERSION, REFLECTTYPE, CAMOUFLAGE, BURNUP, DOUBLESHOCK; CONVERSION2 stubbed)")
end
