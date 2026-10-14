-- Interaction memory: a real, general "who did what to whom, most
-- recently" primitive -- explicit user design (2026-08-28), built
-- specifically to close Mirror Armor without the invasive alternative
-- (threading a new "source" parameter through modern_combat.lua's own
-- changeStage and its ~10+ existing call sites). A per-battle, in-
-- combat-only ring buffer, capped at 8 entries -- generous headroom
-- over this engine's own real roster ceiling (a boss fight's own
-- multi-ally layout is the largest real format this mod has), evicting
-- the oldest record once full rather than growing unbounded.
--
-- Two operations only, per the real, narrow need:
--   recordInteraction(battle, source, target, kind, id) -- push one
--     record. `source`/`target` are real battler references (the same
--     objects abilityIdOf/changeStage already key off everywhere else
--     in this mod) -- no synthetic "unique identifier" is needed since
--     Lua table identity already IS a real, stable, unique key for the
--     lifetime of a battle. `kind` is "move"/"ability" (a free string,
--     not a closed enum -- a future item-triggered interaction can pass
--     "item" without touching this file). `id` is the move/ability id
--     for a future consumer that cares which one.
--   lastInteractionAgainst(battle, target) -- the most recent record
--     whose `target` is this exact mon, or nil. A linear scan of at
--     most 8 entries -- deliberately not indexed further, there is no
--     real need to at this scale.
--
-- Cleared per-battle on battle.ended (own weak-keyed table, battle
-- itself as the key) so nothing leaks across battles via a persistent
-- save-file mon object the way a mon-level field would risk.
return function(mod)
  local MAX_SLOTS = 8
  local memory = setmetatable({}, { __mode = "k" })

  mod.exports.recordInteraction = function(battle, source, target, kind, id)
    if not (battle and source and target) then return end
    local log = memory[battle]
    if not log then
      log = {}
      memory[battle] = log
    end
    log[#log + 1] = { source = source, target = target, kind = kind, id = id }
    if #log > MAX_SLOTS then table.remove(log, 1) end
  end

  mod.exports.lastInteractionAgainst = function(battle, target)
    local log = battle and memory[battle]
    if not log then return nil end
    for i = #log, 1, -1 do
      if log[i].target == target then return log[i] end
    end
    return nil
  end

  mod.events:on("battle.ended", function(ev)
    if ev and ev.battle then memory[ev.battle] = nil end
  end)

  ------------------------------------------------------------------
  -- Generic move-use recorder: every real move use, either generation,
  -- logged as a "move"-kind interaction (attacker -> defender) -- the
  -- same whole-move native entry points (Battle:useMove/BattleState
  -- :performMove) Aroma Veil/Magic Bounce/Dancer already wrap safely
  -- this same phase, composing the same way (this wrap captures
  -- whatever those already installed as ITS OWN "native", so load
  -- order among all of them only changes which layer runs closest to
  -- the real native call, never correctness).
  ------------------------------------------------------------------
  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMoveRecorder = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if attacker and defender and attacker ~= defender then
        mod.exports.recordInteraction(self, attacker, defender, "move", moveId)
      end
      return nativeUseMoveRecorder(self, attacker, defender, moveId)
    end
  end

  local BattleState = require("src.battle.BattleState")
  local nativePerformMoveRecorder = rawget(BattleState, "performMove")
  if type(nativePerformMoveRecorder) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    if user and target and user ~= target and moveInst then
      mod.exports.recordInteraction(self, user, target, "move", moveInst.id)
    end
    return nativePerformMoveRecorder(self, user, target, moveInst, isCalled)
  end
  end

  mod.log:info("g9-battle-engine: interaction_memory installed "
    .. "(recordInteraction, lastInteractionAgainst, 8-slot per-battle ring buffer)")
end
