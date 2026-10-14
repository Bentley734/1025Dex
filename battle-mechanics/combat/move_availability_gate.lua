-- Blocks selecting a move GalarGmaxDex hasn't implemented yet -- explicit
-- user instruction: treat it exactly like a 0-PP move, not a runtime
-- "fails when used" combat message. Confirmed real precedent, both
-- generations checked directly against engine source before writing this:
--   Gen 1, src/battle/BattleState.lua:2066-2069 (inside :update, phase
--   "moveSelect"): `elseif mv.pp <= 0 then self:say(...No PP left...);
--   self.phase = "messages"; self.afterQueue = "menu"` -- rejects, returns
--   to the move list, spends no turn.
--   Gen 2, src/ui/gen2/BattleState.lua:1867: `if (move.pp or 0) <= 0 then
--   return self:refuseMove(TEXT_NO_PP_LEFT) end` -- same shape, own
--   helper. Comment right above it (line 1865-1866): ".no_pp_left and
--   .move_disabled both end on jp MoveSelectionScreen: neither spends the
--   turn." -- exactly the behavior to replicate for an unusable move.
--
-- Both checks live inside their generation's giant native :update(dt),
-- not a separately-callable function, so this wraps :update itself and
-- intercepts BEFORE calling native for the one specific case (A pressed,
-- phase is move-select, no swap pending, the highlighted move fails
-- isMoveUsable) -- every other input (navigation, swap, B, a USABLE
-- move's A-press) falls straight through to native unchanged. This must
-- be installed AFTER every other :update wrap in main.lua's phase order
-- (sprite animation, custom_battle_scene, gimmick_dynamax) so it's the
-- outermost layer and actually runs first each frame -- an inner wrap
-- can't pre-empt input a wrap installed after it already consumed.
--
-- The `not self.moveSwapIndex` guard is defensive: Gen 2's own A-handler
-- confirmed completes a pending swap before ever reaching its PP check
-- (src/ui/gen2/BattleState.lua:1859-1866); Gen 1's swap flow wasn't
-- independently re-derived to the same certainty, so the guard is kept
-- for both generations rather than assumed unnecessary for one --
-- deferring to native whenever a swap might be in progress is always the
-- safe choice, never a behavior change if the guard turns out to be a
-- no-op there.
return function(mod, isMoveUsable)
  local Strings = require("src.core.Strings")
  local BattleState = require("src.battle.BattleState")
  if not BattleState.__galarMoveGateWrapped then
    BattleState.__galarMoveGateWrapped = true
    local nativeUpdate = BattleState.update
    function BattleState:update(dt)
      if self.phase == "moveSelect" and not self.moveSwapIndex
          and self.game and self.game.input and self.game.input:wasPressed("a") then
        local moves = self.player and self.player.curMoves
        local mv = moves and moves[self.moveIndex]
        if mv and mv.id and (mv.pp or 0) > 0
            and self.player.disabledSlot ~= self.moveIndex
            and not isMoveUsable(mv.id) then
          self:say(Strings("This move isn't\nready to use yet!"))
          self.phase = "messages"
          self.afterQueue = "menu"
          return
        end
      end
      return nativeUpdate(self, dt)
    end
  end

  local gen2Ok, Gen2BattleState = pcall(require, "src.ui.gen2.BattleState")
  if gen2Ok and type(Gen2BattleState) == "table" and not Gen2BattleState.__galarMoveGateWrapped then
    Gen2BattleState.__galarMoveGateWrapped = true
    local nativeGen2Update = Gen2BattleState.update
    function Gen2BattleState:update(dt)
      if self.phase == "moves" and not self.moveSwapIndex
          and self.game and self.game.input and self.game.input:wasPressed("a") then
        local moves = self.playerMoves and self:playerMoves()
        local mv = moves and moves[self.moveIndex]
        if mv and mv.id and (mv.pp or 0) > 0 and not isMoveUsable(mv.id) then
          self:refuseMove(Strings("This move isn't\nready to use yet!"))
          return
        end
      end
      return nativeGen2Update(self, dt)
    end
  elseif not gen2Ok then
    local GameVersion = require("src.core.GameVersion")
    if GameVersion.generation(GameVersion.get()) == 2 then
      mod.log:warn("galar_gmax_dex: move_availability_gate: src.ui.gen2.BattleState not available on a gen 2 boot: %s",
        tostring(Gen2BattleState))
    end
  end

  mod.log:info("galar_gmax_dex: move_availability_gate installed")
end
