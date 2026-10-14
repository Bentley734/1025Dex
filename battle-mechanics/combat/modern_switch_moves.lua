-- Self-switch moves: U-turn, Volt Switch, Flip Turn -- damaging moves whose
-- whole real "effect" is that the user leaves the field for a replacement
-- right after the hit lands, battle still ongoing. Parting Shot (below) is
-- the same switch primitive again, but on a pure status move with its own
-- stat-drop half. Teleport (below that) is a native Gen 2 move extended
-- for the real Gen 8+ rule change: a guaranteed self-switch in a trainer/
-- link battle, not the classic "fails outright unless wild" behavior.
-- Baton Pass needs no entry here: it is already a real, working native
-- Gen 2 effect (Battle.MOVE_EFFECTS.EFFECT_BATON_PASS) and this mod never
-- re-registers a move that already works.
--
-- Move-effect shape for the three damaging moves: same on-hit-secondary
-- convention this codebase already uses for Flinch/Confuse (main.lua's
-- installMovepoolEffects) and every hazard/item move in modern_hazards.lua/
-- modern_items.lua -- `kind = "full"` with NO `run` field, so the move's
-- own damage always lands normally on Gen 2 (any move_effects record
-- carrying a `run` field pre-empts the whole damage path on this engine's
-- real dispatch, SUBEFFECTS.md's own documented gotcha) -- and the actual
-- switch request happens from a battle.damage_dealt listener, fired only
-- after a real, landed, non-immune hit. combat/switch_primitives.lua's own
-- requestSwitch never yields or pauses (see that file's own header for why
-- -- this mod is self-contained, and the "pause mid-round" design this
-- session briefly went through needed an engine change this project
-- doesn't allow), so calling it straight from this pcall-wrapped listener
-- (Events:emit, src/mods/Events.lua) is safe -- it only ever does a plain
-- field write and an emit, nothing that a pcall boundary could break.
return function(mod)
  local Strings = require("src.core.Strings")
  local SWITCH_MOVES = { UTURN = true, VOLTSWITCH = true, FLIPTURN = true }

  for id in pairs(SWITCH_MOVES) do
    local effectId = "G9_SELFSWITCH_" .. id
    mod.content.move_effects:register(effectId, { kind = "full" })
    mod.content.moves:patch(id, { effect = effectId })
  end

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and (ev.moveId or (ev.move and ev.move.id))
    local user = ev and ev.user
    if not (battle and user and moveId and SWITCH_MOVES[moveId]) then return end
    if (user.hp or 0) <= 0 then return end -- fainted on its own hit somehow; nothing to switch
    mod.exports.requestSwitch(battle, user, { reason = moveId })
  end)

  ------------------------------------------------------------------
  -- Parting Shot: a pure status move (power=0), dispatched via a
  -- move_effects `run` handler -- called directly from Battle:useMove's
  -- own dispatch (SUBEFFECTS.md's own citation, gen2/Battle.lua:1533-1538),
  -- not through Events:emit, so requestSwitch is exactly as safe to call
  -- straight from here as it is from the battle.damage_dealt listener
  -- above.
  --
  -- Real rule (confirmed against the actual current Pokemon Showdown
  -- source, data/moves.ts's own partingshot.onHit -- fetched directly, not
  -- recalled from memory): attempts -1 Attack/-1 Special Attack on the
  -- target; the self-switch only happens if that stat change is not a
  -- complete no-op. Known simplification: this engine's own changeStage
  -- primitive (modern_combat.lua's export, reused by every other stat-drop
  -- move in combat/modern_movepool_stages.lua) does not report back
  -- whether a given call actually changed anything on Gen 2 -- the switch
  -- below always fires once the move is used, same as every other
  -- self-switch move here, rather than the rarer "target already at -6/-6
  -- on both stats" edge case correctly cancelling it. Not silently passed
  -- off as the exact PS rule.
  ------------------------------------------------------------------
  mod.content.move_effects:register("G9_PARTINGSHOT_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(battle, attacker, defender, def, moveId, sureHit)
      mod.exports.changeStage(battle, defender, "attack", -1, true, true)
      mod.exports.changeStage(battle, defender, "spa", -1, true, true)
      battle:emit({ kind = "message", text = Strings("%s left the battlefield!", battle:monName(attacker)) })
      mod.exports.requestSwitch(battle, attacker, { reason = moveId })
    end,
  })
  mod.content.moves:patch("PARTINGSHOT", { effect = "G9_PARTINGSHOT_EFFECT" })

  ------------------------------------------------------------------
  -- Teleport: native Gen 2 already has a real EFFECT_TELEPORT handler
  -- (gen2/Battle.lua's own Battle.MOVE_EFFECTS.EFFECT_TELEPORT) -- the
  -- classic escape-from-a-wild-battle move, which fails outright in any
  -- trainer/link battle. Real Gen 8+ Showdown changed that: in a trainer/
  -- link battle Teleport is now a guaranteed self-switch instead of a
  -- failure.
  --
  -- Wired the SAME proven way every other move in this mod is (Trick Room,
  -- Attract/Taunt/Torment, Parting Shot above): register a new effect id
  -- and :patch TELEPORT's own move record to point at it -- NOT by trying
  -- to mutate the native "EFFECT_TELEPORT" record in place. Confirmed by
  -- direct read this session (src/mods/Registry.lua's own :register/
  -- append) that the move_effects registry stores whatever table it was
  -- handed BY REFERENCE at boot time (Battle.registerMoveEffectsInto,
  -- gen2/Battle.lua:2743, runs once during engine load, well before any
  -- mod code) -- so reassigning Battle.MOVE_EFFECT_RECORDS.EFFECT_TELEPORT
  -- to a different table LATER, from mod code, would only change what
  -- that field points to going forward; the registry's own already-
  -- captured reference to the ORIGINAL table would still win every lookup
  -- (Battle.moveEffectRecordFor checks the registry's merged table FIRST),
  -- making the reassignment silently invisible to real dispatch. The
  -- proven :register+:patch pattern sidesteps that failure mode entirely,
  -- the same way it already does for every other move here.
  --
  -- The wild-battle branch is reached by reading Battle.MOVE_EFFECT_RECORDS
  -- .EFFECT_TELEPORT.run directly (never overwritten, so this always finds
  -- the real native table) and calling it -- byte-for-byte native, not
  -- reimplemented -- still the classic level-ladder escape roll (identical
  -- to EFFECT_FORCE_SWITCH's), not modern's separate change to a flat
  -- 100%-guaranteed escape. A distinct, real, honest gap, left alone here
  -- rather than silently folded into this fix.
  ------------------------------------------------------------------
  do
    local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
    Battle = gen2Ok_Battle and Battle or nil
    if Battle then
      mod.content.move_effects:register("G9_TELEPORT_EFFECT", {
        kind = "primary",
        run = function(battle, attacker, defender, def, moveId, sureHit)
          if not battle.wild then
            battle:emit({ kind = "message", text = Strings("%s teleported away!", battle:monName(attacker)) })
            mod.exports.requestSwitch(battle, attacker, { reason = moveId })
            return
          end
          local native = Battle.MOVE_EFFECT_RECORDS.EFFECT_TELEPORT
          return native and native.run and native.run(battle, attacker, defender, def, moveId, sureHit)
        end,
      })
      mod.content.moves:patch("TELEPORT", { effect = "G9_TELEPORT_EFFECT" })
    end
    end

  mod.log:info("g9-battle-engine: modern_switch_moves installed (UTURN, VOLTSWITCH, FLIPTURN, PARTINGSHOT, TELEPORT)")
end
