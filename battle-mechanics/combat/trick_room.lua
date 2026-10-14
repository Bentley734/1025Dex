-- The three "dimension" field effects -- Trick Room, Magic Room and Wonder
-- Room -- owned together here because they share one shape (a 5-turn
-- whole-field condition, re-using it toggles it off, a boss fight may lock
-- it permanently) and one move-ban/flag surface.
--
-- EVERY mechanic below is verified against real Pokemon Showdown source
-- (data/moves.ts's own trickroom/magicroom/wonderroom `condition` objects,
-- fetched and read locally this pass, not recalled):
--   - all three `duration: 5`; using one counts as the first of those five;
--     using it again while it is active removes it (`onFieldRestart` ->
--     `this.field.removePseudoWeather(...)`), a toggle, not a refresh.
--   - Trick Room reverses SPEED order within a priority bracket. Priority
--     itself is national_dex's to own (explicit user rule) and
--     combat/turn_order.lua's own movePriority reads it straight from
--     national_dex -- this file patches only the sub-effect that runs.
--   - Magic Room suppresses every held item's effect for the duration
--     (Showdown: `Pokemon.ignoringItem()`).
--   - Wonder Room swaps every active Pokemon's Defense and Sp. Def for the
--     duration (Showdown: "Swapping defenses partially implemented in
--     sim/pokemon.js:Pokemon#calculateStat and Pokemon#getStat").
--
-- Gen 2 has NO native concept of any of these -- all three are Generation
-- IV moves, and this engine recompiles Gold/Silver. Unlike weather
-- (combat/modern_weather.lua's own header: Gen 2's native tickWeather
-- already runs a real duration pass, so that file skips Gen 2 to avoid
-- double-ticking), there is nothing native here to defer to or collide
-- with -- the duration countdowns below are the only mechanisms that will
-- ever run them, with no Gen2-skip guard needed.
--
-- Storage: Trick Room and Magic Room are field state on the battle object
-- (battle.trickRoomActive/battle.trickRoomTurns, battle.magicRoomActive/
-- battle.magicRoomTurns), the same convention weather's own
-- battle.weather/battle.weatherTurns already uses. Wonder Room's swap is
-- per-battler, so it sets a `wonderRoomActive` flag on each ACTIVE mon
-- (re-applied to every switch-in while the room is up, cleared the moment
-- the room ends) -- that flag is what combat/modern_combat.lua's own
-- `rawStat` reads to swap the def/spd key. It is deliberately NOT in
-- combat/status_condition_cleanup.lua's switch-scoped list: a switch must
-- re-APPLY it, not clear it, so this file owns the field end to end.
--
-- Boss-fight "dimension" protections (combat/boss_fight.lua), four
-- independent flags, not one combined "dimension" flag:
--   dimensionLock -- bans all three room moves from being used at all.
--     Does NOT activate any of them itself -- a pure "no room
--     shenanigans" gate.
--   trickRoom / magicRoom / wonderRoom -- the battle is permanently in
--     that room from the moment the flag is set (battle.<room>Active /
--     <room>Turns written directly in combat/boss_fight.lua's own
--     setBossFightProtections, since it is an immediate environmental
--     fact, not something contingent on the move being cast) AND bans
--     ONLY that room's own move (so it cannot be toggled back off).
-- All four compose freely (checked together in the single Battle:useMove
-- wrap below): trickRoom alone leaves Magic/Wonder Room castable by either
-- side; trickRoom + dimensionLock together removes room-move access
-- entirely for the rest of the fight.
return function(mod)
  local Strings = require("src.core.Strings")
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  -- No real item extends any room in any current generation, and no
  -- ability is modeled for Persistent -- this still runs through the SAME
  -- resolveFieldDuration primitive weather/terrain use, with
  -- extendingItem=nil, so it always resolves to FIELD_BASE_TURNS (5) today
  -- but needs no rewrite if a future id is ever assigned here.
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local FIELD_BASE_TURNS = mod.exports.FIELD_BASE_TURNS
  local FIELD_EXTENDED_TURNS = mod.exports.FIELD_EXTENDED_TURNS
  assert(resolveFieldDuration and FIELD_BASE_TURNS and FIELD_EXTENDED_TURNS,
    "trick_room: combat/field_duration.lua must load first")

  local TRICKROOM_EFFECT_ID = "GALAR_TRICKROOM_EFFECT"
  local TRICKROOM_START_TEXT = "%s twisted\nthe dimensions!"
  local TRICKROOM_END_TEXT = "The twisted\ndimensions returned\nto normal!"
  local MAGICROOM_EFFECT_ID = "GALAR_MAGICROOM_EFFECT"
  local MAGICROOM_START_TEXT = "It created a bizarre area\nin which Pokémon's held items\nlose their effects!"
  local MAGICROOM_END_TEXT = "The bizarre area\nwas removed!"
  local WONDERROOM_EFFECT_ID = "GALAR_WONDERROOM_EFFECT"
  local WONDERROOM_START_TEXT = "It created a bizarre area\nin which Pokémon's Defense and\nSp. Def stats are swapped!"
  local WONDERROOM_END_TEXT = "The bizarre area\nwas removed!"

  ------------------------------------------------------------------
  -- The three moves' own effects. Real Gen 2 kind="primary" records (see
  -- this mod's own combat/SUBEFFECTS.md for why -- kind="full"+perform is
  -- Gen 1's shape and silently does nothing under Gen 2's real dispatch,
  -- the exact bug Protect/Max Guard shipped with once already).
  -- accuracyChecked left unset: each affects the whole field, not the
  -- opponent specifically, the same "self/field-only, never miss"
  -- reasoning modern_weather.lua's own starters already establish.
  ------------------------------------------------------------------
  mod.content.move_effects:register(TRICKROOM_EFFECT_ID, {
    kind = "primary",
    run = function(battle, attacker, defender, def, moveId, sureHit)
      if battle.trickRoomActive then
        battle.trickRoomActive = false
        battle.trickRoomTurns = nil
        battle:emit({ kind = "message", text = Strings(TRICKROOM_END_TEXT) })
        return
      end
      battle.trickRoomActive = true
      battle.trickRoomTurns = resolveFieldDuration(attacker, FIELD_BASE_TURNS,
        FIELD_EXTENDED_TURNS, nil)
      battle:emit({ kind = "message", text = Strings(TRICKROOM_START_TEXT, battle:monName(attacker)) })
    end,
  })

  ------------------------------------------------------------------
  -- Wonder Room's per-battler flag. `rawStat` (combat/modern_combat.lua)
  -- swaps the "defense"/"spd" key it reads whenever the mon it is handed
  -- carries this flag, which is exactly Showdown's own getStat swap --
  -- including the stat-stage interaction (a Defense boost keeps boosting
  -- whatever value now sits in the Defense slot, which is what
  -- Pokemon#calculateStat does after the storedStats swap).
  ------------------------------------------------------------------
  local function applyWonderRoomToMon(mon, on)
    if type(mon) == "table" then mon.wonderRoomActive = on or nil end
  end
  local function applyWonderRoomToActives(battle, on)
    if type(battle) ~= "table" then return end
    local allActive = mod.exports.allActiveBattlers
    if allActive then
      pcall(function()
        local roster = allActive(battle) or {}
        for i = 1, #roster do applyWonderRoomToMon(roster[i], on) end
      end)
    end
    applyWonderRoomToMon(battle.player, on)
    applyWonderRoomToMon(battle.enemy, on)
  end
  mod.exports.applyWonderRoomToActives = applyWonderRoomToActives

  mod.content.move_effects:register(WONDERROOM_EFFECT_ID, {
    kind = "primary",
    run = function(battle, attacker, defender, def, moveId, sureHit)
      if battle.wonderRoomActive then
        battle.wonderRoomActive = false
        battle.wonderRoomTurns = nil
        applyWonderRoomToActives(battle, false)
        battle:emit({ kind = "message", text = Strings(WONDERROOM_END_TEXT) })
        return
      end
      battle.wonderRoomActive = true
      battle.wonderRoomTurns = resolveFieldDuration(attacker, FIELD_BASE_TURNS,
        FIELD_EXTENDED_TURNS, nil)
      applyWonderRoomToActives(battle, true)
      battle:emit({ kind = "message", text = Strings(WONDERROOM_START_TEXT, battle:monName(attacker)) })
    end,
  })

  ------------------------------------------------------------------
  -- Magic Room's item suppression, wired at the ONE real Gen 2 choke
  -- point every held-item effect is read through -- Battle:heldEffect
  -- (gen2/Battle.lua:890), which leftovers/berries/King's Rock/the whole
  -- native arm already consult, and which this mod's own held_item.trigger
  -- hook sits inside. Returning nil,0 there while the room is up makes
  -- every item read as no-effect for the duration, which IS Showdown's
  -- `ignoringItem()`. The mod's own stat-multiplier path
  -- (modern_held_items_phase2.lua) is gated at its own entry, since it
  -- reads the item directly rather than through heldEffect.
  ------------------------------------------------------------------
  if Battle then
    if not Battle.__galarMagicRoomHeldEffectWrapped then
      Battle.__galarMagicRoomHeldEffectWrapped = true
      local nativeHeldEffect = Battle.heldEffect
      function Battle:heldEffect(mon, trigger)
        if self.magicRoomActive then return nil, 0 end
        return nativeHeldEffect(self, mon, trigger)
      end
    end
  end

  mod.content.move_effects:register(MAGICROOM_EFFECT_ID, {
    kind = "primary",
    run = function(battle, attacker, defender, def, moveId, sureHit)
      if battle.magicRoomActive then
        battle.magicRoomActive = false
        battle.magicRoomTurns = nil
        battle:emit({ kind = "message", text = Strings(MAGICROOM_END_TEXT) })
        return
      end
      battle.magicRoomActive = true
      battle.magicRoomTurns = resolveFieldDuration(attacker, FIELD_BASE_TURNS,
        FIELD_EXTENDED_TURNS, nil)
      battle:emit({ kind = "message", text = Strings(MAGICROOM_START_TEXT, battle:monName(attacker)) })
    end,
  })

  -- National Dex already owns all three moves' real base stats (Psychic,
  -- status, 0 power, never-miss accuracy, PP) AND Trick Room's priority
  -- (-7) -- priority is national_dex's to own (explicit user rule). So the
  -- only thing patched here is what is actually this mod's domain: which
  -- sub-effect runs.
  mod.content.moves:patch("TRICKROOM", { effect = TRICKROOM_EFFECT_ID })
  mod.content.moves:patch("MAGICROOM", { effect = MAGICROOM_EFFECT_ID })
  mod.content.moves:patch("WONDERROOM", { effect = WONDERROOM_EFFECT_ID })

  ------------------------------------------------------------------
  -- Durations: battle.turn_ended, the same real turn-boundary event
  -- modern_weather.lua's own decrement uses -- reused, not a new hook. No
  -- isGen2Battle guard: unlike weather, nothing native exists here to
  -- avoid double-ticking against. The turn the room was cast fires its own
  -- turn_ended, which is what makes "using it counts as the first of the
  -- five" come out right (5 stored -> 4 turns left after the cast turn).
  ------------------------------------------------------------------
  local function tickRoom(battle, activeField, turnsField, onExpire)
    if not battle or not battle[activeField] then return end
    -- A boss-fight permanent room stores math.huge here; huge - 1 is still
    -- huge, so it never reaches the <= 0 arm and never expires.
    battle[turnsField] = (battle[turnsField] or 0) - 1
    if battle[turnsField] <= 0 then
      battle[activeField] = false
      battle[turnsField] = nil
      onExpire()
    end
  end

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    tickRoom(battle, "trickRoomActive", "trickRoomTurns", function()
      battle:emit({ kind = "message", text = Strings(TRICKROOM_END_TEXT) })
    end)
    tickRoom(battle, "magicRoomActive", "magicRoomTurns", function()
      battle:emit({ kind = "message", text = Strings(MAGICROOM_END_TEXT) })
    end)
    tickRoom(battle, "wonderRoomActive", "wonderRoomTurns", function()
      applyWonderRoomToActives(battle, false)
      battle:emit({ kind = "message", text = Strings(WONDERROOM_END_TEXT) })
    end)
  end)

  -- Wonder Room must follow each switch-in / switch-out for as long as it
  -- is up: the mon coming in gets the swap, the mon leaving loses it.
  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    applyWonderRoomToMon(ev.previous, false)
    applyWonderRoomToMon(ev.battler, battle.wonderRoomActive)
  end)

  -- A battle that starts or ends while a (boss-permanent) room is set must
  -- not leak that room's per-mon flags onto the party tables -- the same
  -- "nothing a battle wrote is left on a save table" rule
  -- combat/status_condition_cleanup.lua enforces for its own fields.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    applyWonderRoomToActives(battle, battle.wonderRoomActive)
  end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    applyWonderRoomToActives(battle, false)
  end)

  ------------------------------------------------------------------
  -- Boss-fight room-move ban: dimensionLock bans all three; trickRoom/
  -- magicRoom/wonderRoom each ban only their own move. Same "skip the
  -- native call entirely, no PP cost" simplification modern_terrain.lua's
  -- own Psychic Terrain block already establishes as this project's
  -- accepted shape for a move that "can't be used" at all. Blanket ban
  -- regardless of which side is attempting it, matching the literal spec
  -- ("the battle doesn't allow using dimension moves"), not just a
  -- player-vs-boss restriction.
  --
  -- FIXED 2026-09-10 (user: "there's still one of the flags that prevents
  -- attacks from being done at all, all moves fail"): the guard used to be
  -- `if flags.dimensionLock or (ownFlag and flags[ownFlag])`, so a boss
  -- carrying dimensionLock had `flags.dimensionLock` read for EVERY move --
  -- not just room moves -- and returned "But it failed!" before the native
  -- move ever ran. dimensionLock is a ROOM-move gate, so the move must be
  -- one of the three room moves for ANY of the four flags to apply; the
  -- whole condition is now gated on `ownFlag` being non-nil first.
  ------------------------------------------------------------------
  local ROOM_MOVE_FLAG = { TRICKROOM = "trickRoom", MAGICROOM = "magicRoom", WONDERROOM = "wonderRoom" }
  if Battle then
    local nativeUseMoveForRooms = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      local flags = self.bossFightFlags
      if flags then
        -- `ownFlag` is nil for every non-room move, so no flag can ever ban
        -- an ordinary attack -- only the three dimension moves reach the
        -- ban arm, and only under dimensionLock or their own room's flag.
        local ownFlag = ROOM_MOVE_FLAG[moveId]
        if ownFlag and (flags.dimensionLock or flags[ownFlag]) then
          self:emit({ kind = "message", text = Strings("But it failed!") })
          return
        end
      end
      return nativeUseMoveForRooms(self, attacker, defender, moveId)
    end
  end

  mod.log:info("g9-battle-engine: trick_room installed (real 5-turn Trick/Magic/Wonder Room, -7 priority, toggle-off, Magic Room item suppression, Wonder Room Def/SpD swap, boss-fight dimension protections)")
end
