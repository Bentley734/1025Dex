-- Bridges combat/switch_primitives.lua's player-side switch request into
-- vanilla's own battle scene. A self-switch effect sets battle.forcedSwitch
-- = true and emits {kind="switch-request", side=, mon=, text=} -- native
-- runTurn (gen1recomp-dev's own gen2/Battle.lua, completely unmodified)
-- already knows how to end a round on forcedSwitch, exactly the way a real
-- faint or a Roar/Whirlwind drag-out already do, so by the time this event
-- reaches BattleState:advanceQueue the round is already fully over -- there
-- is nothing to "resume". This file's only job is opening a real party pick
-- and, once the player chooses, performing a plain Battle:switch(index) --
-- native, unmodified, the exact same call BattleState:openParty's own
-- forced branch already makes for a faint.
--
-- Deliberately its own small party-menu opener rather than a call to
-- BattleState:openParty(true): openParty's own onCancel/refusal reopen
-- logic (the "refuse-switch" phase) is hardcoded to call openParty itself
-- again, and touching that native flow to redirect it would mean editing
-- BattleState.lua -- this mod stays self-contained by never doing that,
-- accepting the resulting minor UX gap this file's own header already
-- notes: an invalid pick (egg, fainted, already the active mon) reopens
-- the list at once here, with no interstitial "no will to fight"-style
-- line, instead of native's own timed message first.
return function(mod)
  local Strings = require("src.core.Strings")
  local gen2Ok_BattleState, BattleState = pcall(require, "src.ui.gen2.BattleState")
  if not gen2Ok_BattleState then
    mod.log:info("g9-battle-engine: switch_vanilla_bridge requires Gen 2; skipped on this Gen 1 game")
    return
  end
  local Screens = require("src.ui.Screens")

  local function openVoluntarySwitchMenu(self)
    local stack = self.game and self.game.stack
    if not stack then return end -- headless: nothing to pick from
    self.phase = "submenu"
    Screens.push(self.game, "Gen2PartyMenu", {
      prompt = "which",
      battleSubmenu = false,
      onCancel = function()
        -- A self-switch move guarantees a switch, same as a faint -- there
        -- is nothing real to cancel back to.
        stack:pop()
        openVoluntarySwitchMenu(self)
      end,
      onChoose = function(index, mon)
        stack:pop()
        if mon.isEgg or (mon.hp or 0) <= 0 or mon == self.battle.player then
          return openVoluntarySwitchMenu(self)
        end
        self.battle:switch(index)
        self:pushAll(self.battle:takeEvents())
        self.phase = "resolving"
        self:advanceQueue()
      end,
    })
  end

  local vanillaAdvanceQueue = BattleState.advanceQueue
  function BattleState:advanceQueue()
    local head = self.queue[1]
    if head and head.kind == "switch-request" then
      table.remove(self.queue, 1)
      self.message = head.text or (Strings("%s must switch!", self:name(head.mon)))
      self.messageTimer = 0
      openVoluntarySwitchMenu(self)
      return
    end
    return vanillaAdvanceQueue(self)
  end

  mod.log:info("g9-battle-engine: switch_vanilla_bridge installed (switch-request -> real party pick -> Battle:switch)")
end
