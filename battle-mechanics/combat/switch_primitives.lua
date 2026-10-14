-- The one generic "this mon's own side switches out mid-move, battle keeps
-- going" primitive -- U-turn, Volt Switch, Baton Pass are the first real
-- callers, but per explicit user decision this is meant to be the SAME
-- entrypoint any future ability or item effect reaches for too, not a
-- moves-only mechanism.
--
-- HARD CONSTRAINT, explicit user correction this session: this mod must be
-- fully self-contained -- gen1recomp-dev's own engine source is NEVER
-- edited, only real, live Lua tables/methods on the shared Battle class are
-- monkeypatched from this mod's own code (the same established pattern
-- every other file here already uses -- Battle:useMove wraps, Battle.
-- moveEffectRecordFor swaps, Effects.BATON_PASS_DROPS table mutation).
-- That rules out the "pause mid-round inside a coroutine, resume the REST
-- of that same native round afterward" design this file went through
-- earlier this session: gen2/Battle.lua's own turn-resolution function
-- (runTurn) is a LOCAL, unexported closure -- not Battle.runTurn -- so no
-- mod, this one included, can reach inside it to inject a pause point.
-- Already documented before this session started, combat/
-- MULTI_BATTLE_HOOKS.md's own "What's still missing" section says exactly
-- this ("no mid-turn hook exists... not reachable from mod code as it
-- stands"). This file no longer tries to route around that.
--
-- What IS achievable, fully mod-side: the same mechanism a real faint (or
-- a Roar/Whirlwind drag-out) already uses -- the round ends AT the switch,
-- via the real, public battle.forcedSwitch field native runTurn already
-- checks (AFTER both sides' actions have run) to skip end-of-turn residual
-- and return early. Confirmed by direct read: runTurn always calls
-- enemyAttack()/playerAttack() for whichever side hasn't gone yet before
-- it ever checks forcedSwitch, so a player-side self-switch does NOT skip
-- the opponent's own action this round -- only the residual sweep (weather
-- chip, status damage, screen countdown, etc.) is skipped. That is the
-- one, real, honest gap versus current Showdown (which keeps residual
-- too), not silently passed off as exact.
return function(mod)
  local Strings = require("src.core.Strings")
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil

  -- Generalizes Battle:switch (player-only, native, left completely
  -- untouched) to the enemy side too -- added as a brand-new method via
  -- monkeypatch, since Battle has no enemy-side equivalent of its own.
  -- Mirrors Battle:switch's own real logic exactly (volatile clear on both
  -- the outgoing and incoming mon, fresh stages, the same "send"/battler_
  -- switched events, trap/Amulet Coin/Spikes on send-in).
  if Battle then
    function Battle:switchMonAtSide(side, index)
      if side == "player" then return self:switch(index) end
      local mon = self.enemyParty[index]
      if not mon or (mon.hp or 0) <= 0 then return false end
      if mon == self.enemy then return false end
      local previous = self.enemy
      self:clearVolatile(self.enemy)
      self:clearVolatile(mon)
      self.enemy = mon
      self.enemyIndex = index
      self.stages.enemy = Battle.newStages()
      self:emit({ kind = "send", side = "enemy", mon = mon,
        text = Strings("Go! %s!", self:monName(mon)) })
      local Runtime = require("src.mods.Runtime")
      Runtime.emit("battle.battler_switched", {
        battle = self, side = self:sideRecord(mon), battler = mon,
        previous = previous,
      })
      self:breakTrapsOnSend(mon)
      self:spikesDamage(mon)
      return true
    end
  end

  -- The default bench pick for a self-switch on the enemy's own side:
  -- first living, non-egg party member behind whoever is currently out --
  -- the exact rule native EFFECT_BATON_PASS already uses for its own
  -- (side-agnostic) pick, reused here as the fallback when no smarter
  -- chooser is registered.
  local function firstAliveBenchIndex(party, activeIndex)
    for index, mon in ipairs(party or {}) do
      if index ~= activeIndex and (mon.hp or 0) > 0 and not mon.isEgg then
        return index
      end
    end
    return nil
  end

  -- The "is there a battle-AI mod hooked in" on/off seam, exactly as
  -- explicitly scoped: a real battle-AI mod calls registerSwitchAiChooser
  -- once with a real chooser (battle, mon, bench) -> index; absent that,
  -- firstAliveBenchIndex's own plain fallback runs instead. A plain
  -- class-level field, not a priority list or provider registry -- there
  -- is exactly one thing here to decide (which bench mon comes in), and
  -- "is a smarter chooser present at all" is the only question worth
  -- asking, per explicit user decision.
  if Battle then Battle.switchAiChooser = nil end
  function mod.exports.registerSwitchAiChooser(fn)
    assert(type(fn) == "function", "registerSwitchAiChooser: fn must be a function")
    if Battle then Battle.switchAiChooser = fn end
  end

  -- The one generic entrypoint every self-switch effect (a move today, an
  -- ability/item once this engine has them) calls. `mon` is whichever
  -- battler is leaving; `opts.reason` is carried through to the emitted
  -- event only, for a UI or a future log to attribute the switch to a
  -- move/ability/item id -- this function has no knowledge of what
  -- triggered it.
  --
  -- Enemy side resolves synchronously, right here: there is no human
  -- waiting on a menu, so Battle.switchAiChooser (if set) or
  -- firstAliveBenchIndex's own plain fallback decides immediately.
  --
  -- Player side sets battle.forcedSwitch = true (real, native, public data
  -- -- runTurn already knows how to end a round on it), parks the leaving mon
  -- on battle.__g9PendingSelfSwitch, and emits a real switch-request event;
  -- the actual party pick happens later, driven by whichever scene is running
  -- (combat/switch_vanilla_bridge.lua for vanilla, g9-Battle-Scene's own
  -- battle_screen.lua otherwise), and is performed with a plain
  -- Battle:switch(index)/switchMonAtSide call. For native runTurn there is
  -- nothing to "resume" -- the round already ended the moment forcedSwitch
  -- made runTurn return early -- but combat/turn_order.lua (the resolver a
  -- replacement SCENE drives) reads __g9PendingSelfSwitch and, when the scene
  -- advertises battle.__g9SceneHandlesPivotSwitch, PAUSES the round there so
  -- the scene can perform the pick and resume the SAME round via
  -- mod.exports.resumeAfterPivot -- that is what makes a pivot's switch-in
  -- take the hits that were still pending (U-turn) versus none (Teleport).
  function mod.exports.requestSwitch(battle, mon, opts)
    assert(battle and mon, "requestSwitch: battle and mon are required")
    opts = opts or {}
    local side = battle:sideOf(mon)
    if side == "enemy" then
      local bench = {}
      for index, benchMon in ipairs(battle.enemyParty) do
        if index ~= battle.enemyIndex and (benchMon.hp or 0) > 0 and not benchMon.isEgg then
          bench[#bench + 1] = { index = index, mon = benchMon }
        end
      end
      if #bench == 0 then return false end
    local chosen = Battle and Battle.switchAiChooser and Battle.switchAiChooser(battle, mon, bench)
      chosen = chosen or firstAliveBenchIndex(battle.enemyParty, battle.enemyIndex)
      if not chosen then return false end
      return battle:switchMonAtSide("enemy", chosen)
    end

    -- Same "is there anyone to send in at all" guard as the enemy branch
    -- -- no point ending the round (or opening an empty party list) for a
    -- bench that has nothing living, non-egg, and not already out on it.
    if not firstAliveBenchIndex(battle.party, battle.playerIndex) then return false end

    -- The mon the player must replace.  combat/turn_order.lua's
    -- resolveTurnActions reads this at the forcedSwitch break so it can tell
    -- a pivot/drag that a mid-turn-capable scene should perform from the old
    -- "end the round here" behaviour, and the scene is handed the same mon on
    -- its own `pivot-switch` event.
    battle.__g9PendingSelfSwitch = { mon = mon, side = side, reason = opts.reason }
    battle.forcedSwitch = true
    battle:emit({ kind = "switch-request", side = "player", mon = mon,
      reason = opts.reason, text = opts.text })
    return true
  end

  mod.log:info("g9-battle-engine: switch_primitives installed (requestSwitch, registerSwitchAiChooser)")
end
