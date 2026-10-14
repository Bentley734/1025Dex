-- End-of-turn residuals for scene-driven battles -- the closing half of the
-- turn loop combat/turn_order.lua's resolveTurnActions opens.
--
-- WHY THIS FILE EXISTS (round sixty-seven, 2026-09-12)
--
-- Native gen2/Battle.lua's one unexported local `runTurn` is the ONLY thing
-- that ever ran the end-of-turn phase: after the attack phase it walks the
-- cart's own residual order -- weather, then each mon's status chip and the
-- Leech Seed / Curse residual, then wrap ticks, held items, Future Sight and
-- Perish Song, then the screens and the per-turn counters -- and finally
-- resolveFaints, all at Battle.lua:5012-5036. A replacement battle scene
-- (g9-Battle-Scene) drives its OWN turn loop and calls
-- mod.exports.resolveTurnActions for the attack half instead of ever running
-- native runTurn, so in every scene-driven battle NONE of that residual block
-- ever ran. That is the "turn-loop change" this file completes the wire for:
-- the attack half was already wired in round sixty-six (battle.turn now
-- advances); this is the other half.
--
-- The ~20 dead systems the missing phase was starving (all confirmed by
-- direct source read this session, not assumed):
--   * combat/modern_weather.lua:387-389 patches Gen2Effects.sandstormDamage
--     to the current 1/16 and adds snow text keys for a pass it explicitly
--     does NOT duplicate -- its own Gen 1 sand-chip listener returns early
--     for Gen 2 ("native tickWeather ALREADY runs a real, working end-of-turn
--     pass"). With no pass, sandstorm never chipped and never counted down.
--   * abilities/engine/heal.lua:140-155 patches Battle.STATUSES.poison
--     .residual / .toxic.residual for Poison Heal -- only ever reached
--     through native tickStatus.
--   * combat/modern_status_effects.lua:443-454 wraps Gen2Battle.tickCounters
--     to tick taunt -- only ever reached if native tickCounters is called.
--   * main.lua:519 and gigantamax/max_move_subeffects.lua:385 set native
--     state.wrapCount / state.wrapMove / state.wrapMoveId (the real trap
--     duration the engine's own header calls a live system) -- nothing but
--     native tickWrap ever ticks it down.
--   * combat/modern_held_items.lua relies on native tickHeldItem for
--     Leftovers/berries ("verified unchanged"), and
--     modern_held_items_phase2.lua:229 adds Black Sludge as a purely additive
--     new item with no native precedent.
--   * every `battle.turn_ended` listener in the mod -- Dry Skin / Rain Dish /
--     Ice Body (heal.lua:101), cud-chew, Forecast, terrain, Trick Room,
--     Dynamax countdown, ... -- needs the event this file emits.
--
-- This file does NOT reimplement any of that math. It calls the real native
-- residual methods on the live battle (so every mod patch to them -- the
-- Poison Heal residual replacement, the sandstorm fraction, the taunt tick --
-- rides along exactly as it does in a native fight) and emits the same
-- battle.turn_ended native closeTurn emits. It deliberately does NOT call
-- native Battle:resolveFaints: that method is hard-wired to the native
-- battle model (self.enemyParty / self.party, repointing self.enemy, endBattle,
-- awardPrizeMoney, choose-switch) and the scene owns exp, enemy replacement,
-- win/loss and the player's own switch prompt. Calling it would double-award
-- exp and drive the wrong model. What the scene genuinely lacks -- the faint
-- ANNOUNCEMENT (`kind="faint"` plus the real `battle.fainted` runtime event
-- that ~6 ability engines listen to) -- is provided here instead, as a
-- narrowly-scoped sweep that touches no HP, no exp and no battle outcome.
--
-- ONE IMPORTANT SCOPE NOTE: native's residual block reads only self.player
-- and self.enemy, which is all a native fight ever has. A scene-driven
-- doubles/triples/horde/bossFight has MORE (the scene keeps its real roster
-- in screen.playerBattlers / screen.enemyBattlers and exposes it to the
-- engine through the g9.request_adjacency hook). This file derives the real
-- N-way roster from that same primitive (mod.exports.allActiveBattlers) and
-- ticks every battler, so a Black Sludge or Leftovers on battler #3 actually
-- ticks in a double battle. The one place native's own field logic is
-- inherently two-mon (its sandstorm loop and leech-heal recipient) is noted
-- at its call site below.
return function(mod)
  ------------------------------------------------------------------
  -- Dependencies. All optional: a missing one costs a flavor string or a
  -- runtime event, never the phase (this whole file is pcall-guarded by the
  -- boot table in main.lua just like every other sibling, but the guards
  -- here are per-call so a single renamed native method can't take the
  -- whole sweep down).
  ------------------------------------------------------------------
  local okStrings, Strings = pcall(require, "src.core.Strings")
  Strings = (okStrings and type(Strings) == "function") and Strings or function(fmt, ...)
    local n = select("#", ...)
    if n == 0 then return fmt end
    local args = { ... }
    local i = 0
    return (tostring(fmt):gsub("%%[sd]", function()
      i = i + 1
      return tostring(args[i])
    end))
  end

  local okEffects, Effects = pcall(require, "src.battle.gen2.Effects")
  Effects = (okEffects and type(Effects) == "table") and Effects or {}

  -- The real runtime event bus. Native closeTurn emits battle.turn_ended
  -- through it, and every mod listener registers on the SAME bus via
  -- mod.events:on (Loader.lua's Runtime.install wires the two together --
  -- confirmed at g9-Battle-Scene's own battle_screen.lua:37-48), so this is
  -- the faithful way to close the round.
  local okRuntime, Runtime = pcall(require, "src.mods.Runtime")
  Runtime = (okRuntime and type(Runtime) == "table") and Runtime or nil

  local function isGen2(battle)
    local fn = mod.exports.isGen2Battle
    return (type(fn) == "function") and fn(battle) == true or false
  end

  ------------------------------------------------------------------
  -- The real roster. mod.exports.allActiveBattlers (combat/move_targeting
  -- .lua:120) is the engine's one N-way "everyone currently in this battle"
  -- primitive -- built on requestAdjacency, so it sees the scene's real
  -- doubles/triples/horde rosters and degrades to exactly
  -- {battle.player, battle.enemy} with no scene. Anything that fails is
  -- caught here and falls back to the native pair, so a missing hook costs
  -- the extras, never the two leads.
  ------------------------------------------------------------------
  local function rawRoster(battle)
    if not (battle and battle.player) then return {} end
    local out = {}
    local fn = mod.exports.allActiveBattlers
    if type(fn) == "function" then
      local ok, list = pcall(fn, battle)
      if ok and type(list) == "table" then
        for _, mon in ipairs(list) do
          if mon then out[#out + 1] = mon end
        end
        if #out > 0 then return out end
      end
    end
    out[#out + 1] = battle.player
    if battle.enemy and battle.enemy ~= battle.player then
      out[#out + 1] = battle.enemy
    end
    return out
  end

  -- Fastest-first, the same order the engine uses for switch-in triggers
  -- (mod.exports.orderActiveBattlers), so residual abilities/items across
  -- multiple battlers apply in real Speed order rather than roster order.
  local function orderedRoster(battle)
    local roster = rawRoster(battle)
    local fn = mod.exports.orderActiveBattlers
    if type(fn) == "function" and #roster > 1 then
      local ok, ordered = pcall(fn, battle, roster)
      if ok and type(ordered) == "table" and #ordered == #roster then
        return ordered
      end
    end
    return roster
  end

  -- Per-call guards: native's own methods already skip a fainted mon
  -- ((mon.hp or 0) > 0 in every tick), so this only has to survive a method
  -- that is absent or renamed -- a warn, not a dead phase.
  local function tickOne(battle, method, mon)
    local fn = battle and battle[method]
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, battle, mon)
    if not ok then
      mod.log:warn("g9-battle-engine: turn_residuals: " .. method
        .. " failed: " .. tostring(err))
    end
  end

  local function tickField(battle, method)
    local fn = battle and battle[method]
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, battle)
    if not ok then
      mod.log:warn("g9-battle-engine: turn_residuals: " .. method
        .. " failed: " .. tostring(err))
    end
  end

  ------------------------------------------------------------------
  -- Sandstorm over the EXTRA battlers. Native tickWeather loops exactly
  -- {self.player, self.enemy} (Battle.lua:5078) -- correct for a native fight,
  -- blind to a scene's battler #2/#3. Call it once for the duration countdown
  -- and the two leads' chip (so the engine's own patched
  -- Gen2Effects.sandstormDamage is what the leads take), then chip any
  -- remaining battler here with the same rule: not Rock/Ground/Steel, not
  -- semi-invulnerable (vanished), 1/16 max HP, the buffeted message and the
  -- ANIM_IN_SANDSTORM damage event. Type-based immunity comes from the same
  -- Effects.sandstormHits native uses when present.
  ------------------------------------------------------------------
  local SAND_IMMUNE = { GROUND = true, STEEL = true, ROCK = true }

  local function sandstormExtras(battle, roster)
    if battle.weather ~= "sandstorm" then return end
    for _, mon in ipairs(roster) do
      if mon ~= battle.player and mon ~= battle.enemy and (mon.hp or 0) > 0 then
        local vanished = false
        if type(battle.volatile) == "function" then
          local ok, state = pcall(battle.volatile, battle, mon)
          vanished = (ok and state and state.vanished) or false
        end
        if not vanished then
          local def = type(battle.speciesDef) == "function"
            and battle:speciesDef(mon) or nil
          local types = (def and def.types) or mon.types
          local hits
          if type(Effects.sandstormHits) == "function" then
            local ok, r = pcall(Effects.sandstormHits, types)
            hits = ok and r or false
          else
            hits = false
            for _, t in ipairs(types or {}) do
              if not SAND_IMMUNE[t] then hits = true break end
            end
          end
          if hits then
            local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 8
            local damage = math.max(1, math.floor(maxHp / 16))
            if type(Effects.sandstormDamage) == "function" then
              local ok, r = pcall(Effects.sandstormDamage, maxHp)
              if ok and type(r) == "number" then damage = r end
            end
            mon.hp = math.max(0, mon.hp - damage)
            if type(battle.emit) == "function" then
              local name = (type(battle.monName) == "function"
                and battle:monName(mon)) or mon.name or mon.species or "?"
              battle:emit({ kind = "message",
                text = Strings("%s is buffeted by the sandstorm!", name) })
              local side = type(battle.sideOf) == "function"
                and battle:sideOf(mon) or nil
              battle:emit({ kind = "damage", side = side, amount = damage,
                hp = mon.hp, anim = "ANIM_IN_SANDSTORM" })
            end
          end
        end
      end
    end
  end

  ------------------------------------------------------------------
  -- mod.exports.runEndOfTurn(battle) -- the residual pass itself, in the
  -- cart's own order (Battle.lua:5012-5036). Phase grouping is preserved
  -- (status + seed interleaved per mon, then wrap/held/future/perish grouped
  -- per phase, then screens once, then counters), generalized from native's
  -- hard-coded firstMon/secondMon to the real ordered roster. Every call is
  -- the genuine native method, so every engine patch to those methods rides
  -- along untouched.
  ------------------------------------------------------------------
  mod.exports.runEndOfTurn = function(battle)
    if not isGen2(battle) then return end
    local roster = orderedRoster(battle)
    -- Weather once: countdown + end message + the two leads' sand chip.
    tickField(battle, "tickWeather")
    -- ... then any battler beyond the native pair.
    sandstormExtras(battle, roster)
    -- Leech Seed / Curse picks its heal recipient as the OTHER side of
    -- player/enemy (Battle.lua:5150), which is inherently a two-mon frame;
    -- native leechSeed/cursed volatiles are never set by this mod anyway
    -- (modern_status_volatiles keeps its own mon.leechSeeded fields), so the
    -- call is native-parity only and cannot misroute a real engine heal.
    for _, mon in ipairs(roster) do
      tickOne(battle, "tickStatus", mon)
      tickOne(battle, "tickSeedAndCurse", mon)
    end
    for _, mon in ipairs(roster) do tickOne(battle, "tickWrap", mon) end
    for _, mon in ipairs(roster) do tickOne(battle, "tickHeldItem", mon) end
    for _, mon in ipairs(roster) do tickOne(battle, "tickFutureSight", mon) end
    for _, mon in ipairs(roster) do tickOne(battle, "tickPerish", mon) end
    tickField(battle, "tickScreens")
    for _, mon in ipairs(roster) do tickOne(battle, "tickCounters", mon) end
  end

  ------------------------------------------------------------------
  -- mod.exports.announceFaints(battle) -- the faint announcement the scene
  -- path is missing. Native resolveFaints emits `kind="faint"` plus
  -- Runtime.emit("battle.fainted", {battle, battler, side}) and then does all
  -- the model work (exp, replacement, endBattle) the scene owns itself. Only
  -- the first half is provided here, keyed per-mon so a mon is announced
  -- exactly once no matter how many times takeTurn / a residual pass sees it
  -- still at 0 HP. Idempotent by design: callers may (and do) call it both
  -- before and after the residual pass, matching native's own two resolveFaints
  -- calls, and the second call is a no-op for anything already announced.
  --
  -- Deliberately touches NO HP, NO exp and NO battle outcome -- the scene's
  -- own exp/replacement/win-loss flow is untouched, and the scene's
  -- `.fainted` guard lives on its own battler WRAPPER (Combat.newBattler),
  -- not on this raw mon, so setting mon.fainted here cannot consume an exp
  -- award.
  ------------------------------------------------------------------
  mod.exports.announceFaints = function(battle)
    if not isGen2(battle) then return end
    local announced = battle.__g9FaintAnnounced
    if type(announced) ~= "table" then
      announced = {}
      battle.__g9FaintAnnounced = announced
    end
    for _, mon in ipairs(rawRoster(battle)) do
      if (mon.hp or 0) <= 0 and not announced[mon] then
        announced[mon] = true
        -- Primitives.faint's own bookkeeping (showdown_primitives.lua:126):
        -- keep the raw mon's flag consistent even for a native residual that
        -- zeroed HP by direct write.
        mon.fainted = true
        local side = type(battle.sideOf) == "function"
          and battle:sideOf(mon) or nil
        local name = (type(battle.monName) == "function"
          and battle:monName(mon)) or mon.name or mon.species or "?"
        if type(battle.emit) == "function" then
          local template = battle.wild and "Wild %s fainted!" or "%s fainted!"
          battle:emit({ kind = "faint", side = side,
            text = Strings(template, name) })
        end
        if Runtime and type(Runtime.emit) == "function" then
          Runtime.emit("battle.fainted", { battle = battle, battler = mon,
            side = side })
        end
      end
    end
  end

  mod.log:info("g9-battle-engine: turn_residuals installed (scene end-of-turn residual pass + faint announcement + battle.turn_ended)")
end
