-- One central "what a switch (or the end of a battle) takes away" pass for
-- the turn-counted status conditions THIS MOD owns (ROUND 33).
--
-- The real problem this closes: on Gen 2 the battle's active battlers ARE
-- plain party-mon tables (`battle.player == save.party[1]`, and
-- `Battle.party IS save.party` -- gen2/Battle.lua's own words), and the
-- engine's `Battle:clearVolatile(mon)` only nils `mon.volatile`. Everything
-- native keeps in that volatile store is therefore dropped on a switch for
-- free, and everything this mod keeps in a DIRECT field on the mon table
-- (Leech Seed, Disable, Yawn, Perish Song, Telekinesis, Heal Block,
-- Embargo, Throat Chop, Nightmare, Ingrain, Foresight, Miracle Eye, Smack
-- Down, Stockpile, the Outrage/Uproar lock) is NOT -- it survived every
-- switch, and worse, every BATTLE, because the party table is the save
-- file. Real Showdown clears every one of these on switch (`noCopy`
-- volatiles / onSwitchIn resets), so a seeded or disabled mon that leaves
-- the field must come back clean. (`wonderRoomActive` is deliberately NOT
-- in this list -- combat/trick_room.lua owns that one, because its value
-- must be RE-APPLIED to a mon switching IN while the room is up, not
-- simply cleared; splitting the two responsibilities keeps either file
-- from undoing the other's write.)
--
-- toxicCounter is the other half. Real Showdown's `tox` (data/conditions.ts)
-- has BOTH `onStart` and `onSwitchIn` set `effectState.stage = 0`, so a
-- badly-poisoned mon that switches out restarts its ramp at 1/16 on the
-- way back in. The native Gen 2 `Battle.STATUSES.toxic` never resets
-- `mon.toxicCounter` anywhere (only selfdestruct/Rest written a nil
-- counter), so before this file the ramp simply continued from wherever it
-- was -- confirmed by direct read, not assumed.
--
-- Hooked on the engine's own real events, the same ones the rest of this
-- mod already consumes:
--   battle.battler_switched -- emitted by every Gen 2 switch path
--     (Battle:switch / switchEnemy / forcedReplacement / switchFainted)
--     and by Gen 1's BattleState resolveSwitch/switch sites, with
--     `previous` (whoever left) and `battler` (whoever walked in).
--   battle.started / battle.ended -- the cross-battle sweep: nothing a
--     battle wrote may be left on a party table (the exact principle
--     gen2/Battle.lua's own `clearAllVolatiles` header already states),
--     and a battle that ended mid-Leech-Seed or mid-Disable must not hand
--     the next battle or the save file a stale counter.
return function(mod)
  -- Every direct-on-the-mon field this mod owns that is switch-scoped in
  -- the real games. Deliberately excludes the major-status bookkeeping
  -- (`status`, Gen 2 `statusTurns`, Gen 1 `sleepTurns`): a status persists
  -- through a switch in the real games, so its counter must too -- only
  -- the VOLATILE conditions reset.
  local SWITCH_SCOPED = {
    -- native badly-poisoned ramp (see this file's header)
    "toxicCounter",
    -- combat/modern_status_volatiles.lua
    "disableTurns", "disabledMoveId",
    "yawnTurns", "perishSongTurns", "telekinesisTurns",
    -- combat/modern_status_moves.lua (round 90, missing-effects phase 21):
    -- Magnet Rise's own 5-turn Ground-immunity counter (the exact
    -- Telekinesis shape, above) and the single added-type slot Forest's
    -- Curse / Trick-or-Treat write -- both real switch-scoped volatiles.
    "magnetRiseTurns", "addedType",
    "healBlockTurns", "embargoTurns", "throatChopTurns",
    "leechSeeded", "leechSeedSource",
    "nightmare", "ingrained",
    "foresighted", "miracleEyed", "groundedByMove",
    "thrashTurns", "thrashMove", "thrashAnnounced",
    "stockpileLayers",
    -- combat/modern_stat_manipulation.lua (round 70): the Syrup Bomb coat.
    -- Its own battle.turn_ended listener already ends the coat when the
    -- source leaves the field, but a target that SWITCHES OUT must also come
    -- back clean (the real volatile is noCopy), so it belongs here too.
    -- Power Shift's fields are deliberately NOT here -- that file's own
    -- battler_switched listener exists precisely to SWAP THE RAW STATS BACK,
    -- which a plain nil-out here could not do.
    "syrupBombTurns", "syrupBombSource",
    -- combat/modern_crit_override.lua (round 71): Laser Focus's guaranteed-crit
    -- volatile. A switch-out must clear it (the real volatile is switch-scoped).
    "laserFocusTurns",
    -- combat/modern_crit_override.lua (4.6.7): Dragon Cheer's
    -- ally-side crit volatile and its frozen Dragon-type flag. Both are
    -- switch-scoped in the real games (dropped by clearVolatile), so a mon
    -- that leaves the field must come back un-cheered.
    "dragonCheer", "dragonCheerDragon",
    -- combat/modern_trap_moves.lua (round 77, missing-effects phase 9): the
    -- Octolock coat. Its own battle.turn_ended listener ends it when the
    -- source leaves the field, but a target that SWITCHES OUT must also come
    -- back clean (the real volatile is a noCopy volatile, so a switch drops
    -- it) -- and the Gen 1 `g9Trapped` marker is switch-scoped for the same
    -- reason (the pin dies with the send, like the native trapsTarget does).
    "octolockActive", "octolockSource", "g9Trapped",
    -- combat/modern_recovery_moves.lua (round 85, missing-effects phase 16):
    -- Aqua Ring ends on switch-out (real Showdown drops the volatile; only
    -- Baton Pass carries it, and Baton Pass has no handler yet), so a mon
    -- that leaves must come back un-ringed. __g9RoostActive is the Roost
    -- Flying-type-drop flag: its own battle.turn_ended listener clears it
    -- after one turn, but a mon forced out mid-turn must not leave a stale
    -- drop on the party table either (the party table IS the save file).
    "aquaRing", "__g9RoostActive",
    -- combat/modern_charge_moves.lua (round 86, missing-effects phase 17):
    -- the two rolling power ladders and the Defense Curl marker that
    -- doubles them are all switch-scoped (real Showdown volatiles, dropped
    -- by clearVolatile), as are Beak Blast / Shell Trap's per-turn arming
    -- flags -- a switch can only happen mid-turn through a forced switch,
    -- and a mon that leaves must not carry a stale arm or ladder back in.
    "__g9IceBallUses", "__g9IceBallTurn",
    "__g9RolloutUses", "__g9RolloutTurn",
    "__g9DefenseCurl", "__g9BeakBlastArmed",
    "__g9ShellTrapArmed", "__g9ShellTrapHit",
  }

  local function clearSwitchScoped(mon)
    if type(mon) ~= "table" then return end
    for i = 1, #SWITCH_SCOPED do mon[SWITCH_SCOPED[i]] = nil end
  end
  -- Exported for tests and for any future caller that needs the exact same
  -- list without re-spelling it (the same reuse convention
  -- modern_status_effects.lua's own `tryAttract` export already follows).
  mod.exports.clearSwitchScopedStatus = clearSwitchScoped
  mod.exports.SWITCH_SCOPED_STATUS_FIELDS = SWITCH_SCOPED

  -- Cross-battle sweep: the active pair, both party rosters, and (for a
  -- real doubles/triples roster) every mon allActiveBattlers reports.
  -- pcall-guarded as a whole because allActiveBattlers consults the scene
  -- mod's own requestAdjacency hook, which need not be live at
  -- battle.ended time.
  local function sweepBattle(battle)
    if type(battle) ~= "table" then return end
    clearSwitchScoped(battle.player)
    clearSwitchScoped(battle.enemy)
    for _, party in ipairs({ battle.party, battle.enemyParty, battle.playerParty }) do
      if type(party) == "table" then
        for i = 1, #party do clearSwitchScoped(party[i]) end
      end
    end
    local allActive = mod.exports.allActiveBattlers
    if allActive then
      pcall(function()
        local actives = allActive(battle)
        for i = 1, #(actives or {}) do clearSwitchScoped(actives[i]) end
      end)
    end
  end

  mod.events:on("battle.battler_switched", function(ev)
    if not (ev and ev.battle) then return end
    clearSwitchScoped(ev.previous)
    clearSwitchScoped(ev.battler)
  end)

  mod.events:on("battle.started", function(ev)
    sweepBattle(ev and ev.battle)
  end)
  mod.events:on("battle.ended", function(ev)
    sweepBattle(ev and ev.battle)
  end)

  mod.log:info("g9-battle-engine: status_condition_cleanup installed (%d switch-scoped status fields reset on switch + battle start/end, toxic ramp reset included)", #SWITCH_SCOPED)
end
