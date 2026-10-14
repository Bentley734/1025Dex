-- =============================================================================
-- Player held-item storage + post-battle restore API (round 98)
--   mod.exports.setHeldItem(mon, itemId)   -- Gen 1: equip (persists in save)
--   mod.exports.getHeldItem(mon)           -- Gen 1: ask what it holds
--   mod.exports.clearHeldItem(mon)         -- Gen 1: remove
--   mod.exports.effectiveHeldItemOf(mon, gen2)
--   mod.exports.snapshotHeldItems(battle) / restoreHeldItems(battle)
-- =============================================================================
--
-- WHAT THIS IS
-- The engine gives Gen 1 no way to store a held item, so any mod that wants
-- held items on a Gen-1 save (a "hold / switch / remove" tool, an item-granting
-- NPC, a randomizer, ...) has nowhere to put the id. This file owns that
-- storage: a plain, namespaced string field on the mon table, persisted in the
-- save exactly like every other mon field. Gen-1 callers use setHeldItem /
-- getHeldItem / clearHeldItem; the item survives save/reload and can be
-- changed at any time.
--
-- It ALSO owns the battle-scoped item RESTORE both generations need. This
-- mod's own item moves remove a battler's item outright on a landed hit -- a
-- plain `mon.item = nil` / `m.item = nil` assignment (combat/modern_items.lua
-- Knock Off / Fling / Incinerate / Bug Bite / Pluck, combat/modern_item_moves.
-- lua's takeItem, the end-of-turn berry eaters). On Gen 2 that write is not
-- transient: `Battle.party IS save.party` (gen2/Battle.lua:463's own words),
-- so a flung/knocked-off/consumed item is genuinely DELETED from the save and
-- never comes back. Gen 1 has no native held-item mechanic at all, so the
-- removal is whatever a caller mod does. In both cases this file snapshots the
-- player's party equipment at `battle.started` and, at `battle.ended`, hands
-- back any item that was there before the battle and is gone now -- the
-- flinged / thieved / lost / consumed case, restored after the battle.
--
-- THE GEN-1 SAVE SLOT, AND WHY IT SURVIVES
--   * A Gen-1 mon is a plain Lua table ("so it serializes straight into the
--     save", src/pokemon/Pokemon.lua:1) with species/level/exp/dvs/statExp/
--     stats/hp/catchRate/status/moves -- and NO item field anywhere
--     (src/pokemon/Pokemon.lua, whole file). So this file adds one:
--     `mon.g9HeldItem` (mod.exports.HELD_ITEM_SAVED_FIELD names it).
--   * src/core/SaveSerializer.lua:12-51 writes EVERY key of a table (keys are
--     sorted, and a string key matching ^[%a_][%w_]*$ is emitted as `k = v`),
--     so `g9HeldItem = "LEFTOVERS"` round-trips through the save untouched.
--   * The load-time validator does not strip it either: SaveData.validate's
--     scrubKnownMon (src/core/SaveData.lua:2324-2400) only clamps dvs /
--     statExp / level, calls Stats.ensure, and prunes unrunnable move slots --
--     it never enumerates or removes unknown mon keys. This mod's own
--     stats/save_scrub.lua wrapper adds modern-field clamps on top and is
--     likewise additive-only.
--   * Gen 2 needs no new field: its `mon.item` (src/battle/gen2/Mon.lua:458)
--     is that save's own held-item slot and already persists. Per the round-98
--     brief, Gen 2 participation here is RESTORE ONLY -- this file never
--     invents a parallel Gen-2 field and never writes `mon.item` outside the
--     battle-end restore.
--
-- THE RESTORE (both generations, player's party only)
--   * `battle.started` runs at priority 1000 (before every mod handler that
--     could touch a party mon) and records { mon -> current item } for every
--     item-holding member of the player's party. Nothing is recorded for a
--     mon that holds nothing at battle start.
--   * `battle.ended` runs at priority -1000 (Events.lua:11-22 sorts listeners
--     descending by priority, so this is the LAST ended handler) and, for each
--     recorded mon, writes the item back ONLY if the mon now holds nothing.
--     An item that survived the battle is left exactly as it is, and an item a
--     mon GAINED during the battle (Bestow/Trick/Recycle) is never clobbered --
--     this restores losses, it does not rewind equipment.
--   * Player scope: on Gen 2 that is `battle.party` (= save.party); on Gen 1 it
--     is the real save party (`battle.game.save.party`), the trainer-scoped
--     view `battle.playerParty` (src/battle/BattleState.lua:765
--     `playerPartyView = playerParty or save.party`) and the active battler,
--     deduped. The enemy roster is deliberately out of scope -- it is rebuilt
--     for every encounter and never enters the save.
--
-- PRIOR ART REUSED, not re-invented:
--   * combat/modern_items.lua's own `itemOf(who, gen2)` is the Gen-2-only
--     reader (`gen2 and who.item or nil`); this file does not change it.
--     `effectiveHeldItemOf` is the gen-aware reader the two-gen restore needs.
--   * combat/status_condition_cleanup.lua is the pattern for a cross-battle
--     sweep over the player's party on battle.started/battle.ended (its
--     `sweepBattle`); this file applies the same "the party table IS the save
--     file" principle to the item slot.
return function(mod)
  local isGen2Battle = mod.exports.isGen2Battle
  assert(isGen2Battle,
    "modern_held_item_api: combat/modern_combat.lua must load first")

  -- Raw mon behind a Gen 1 battler wrapper, or the mon itself on Gen 2
  -- (the shared g9RawMon from modern_party_support.lua, with the same
  -- one-liner as a fallback if that file did not boot).
  local g9RawMon = mod.exports.g9RawMon
  local function rawMon(who)
    if g9RawMon then return g9RawMon(who) end
    return who and (who.mon or who) or nil
  end

  -- The Gen-1 saved-stat slot. Public so a caller mod can read/write the raw
  -- field (or migrate it) without guessing the name; the accessors below are
  -- the supported path.
  local SAVED_FIELD = "g9HeldItem"
  mod.exports.HELD_ITEM_SAVED_FIELD = SAVED_FIELD

  -- effectiveHeldItemOf(who, gen2): the item `who` currently holds, whichever
  -- generation's slot that is. Gen 2 -> the native mon.item; Gen 1 -> the
  -- g9HeldItem save slot. `gen2` omitted defaults to the Gen-1 slot (this
  -- file's own API); the battle restore always passes the battle's real
  -- generation explicitly.
  local function effectiveHeldItemOf(who, gen2)
    local m = rawMon(who)
    if not m then return nil end
    if gen2 then return m.item end
    return m[SAVED_FIELD]
  end
  mod.exports.effectiveHeldItemOf = effectiveHeldItemOf

  ------------------------------------------------------------------
  -- Gen-1 accessors. setHeldItem writes the slot (so the value is part of
  -- the mon's saved stats from the next save onward); clearHeldItem -- or
  -- setHeldItem(mon, nil) -- removes it on request. All three accept a raw
  -- mon table or a battler wrapper (`who.mon`), and all three are no-ops
  -- returning false on a non-table.
  ------------------------------------------------------------------
  local function getHeldItem(who)
    local m = rawMon(who)
    return (m and m[SAVED_FIELD]) or nil
  end
  local function setHeldItem(who, itemId)
    local m = rawMon(who)
    if type(m) ~= "table" then return false end
    if itemId ~= nil and type(itemId) ~= "string" then return false end
    m[SAVED_FIELD] = itemId
    return true
  end
  local function clearHeldItem(who)
    local m = rawMon(who)
    if type(m) ~= "table" then return false end
    m[SAVED_FIELD] = nil
    return true
  end
  mod.exports.getHeldItem = getHeldItem
  mod.exports.setHeldItem = setHeldItem
  mod.exports.clearHeldItem = clearHeldItem

  ------------------------------------------------------------------
  -- The player's party, deduped. Gen 2: battle.party (IS save.party).
  -- Gen 1: the real save party plus the scoped playerParty view (either may
  -- be absent), plus whichever mon is on the field. The active battler is
  -- visited first so a Gen-1 wrapper contributes its .mon.
  ------------------------------------------------------------------
  local function eachPlayerMon(battle, fn)
    if type(battle) ~= "table" then return end
    local seen = {}
    local function visit(who)
      local m = rawMon(who)
      if type(m) == "table" and not seen[m] then
        seen[m] = true
        fn(m)
      end
    end
    visit(battle.player)
    local game = battle.game
    local saveParty = game and game.save and game.save.party
    for _, list in ipairs({ battle.party, battle.playerParty, saveParty }) do
      if type(list) == "table" then
        for i = 1, #list do visit(list[i]) end
      end
    end
  end

  -- snapshotHeldItems(battle): record every player-party mon that holds an
  -- item RIGHT NOW. Stored on the (transient) battle table, so an abandoned
  -- battle cannot leak a stale snapshot into the next one. Returns the list.
  local function snapshotHeldItems(battle)
    if type(battle) ~= "table" then return {} end
    local gen2 = isGen2Battle(battle)
    local snap = {}
    eachPlayerMon(battle, function(m)
      local item = effectiveHeldItemOf(m, gen2)
      if item ~= nil then snap[#snap + 1] = { mon = m, item = item } end
    end)
    battle.g9HeldItemSnapshot = snap
    return snap
  end
  mod.exports.snapshotHeldItems = snapshotHeldItems

  -- restoreHeldItems(battle): give back every recorded item that is now
  -- missing. A mon whose item survived -- or that picked one up mid-battle --
  -- is left alone. Clears the snapshot either way. Returns how many were put
  -- back.
  local function restoreHeldItems(battle)
    if type(battle) ~= "table" then return 0 end
    local gen2 = isGen2Battle(battle)
    local snap = battle.g9HeldItemSnapshot
    battle.g9HeldItemSnapshot = nil
    if type(snap) ~= "table" then return 0 end
    local restored = 0
    for i = 1, #snap do
      local entry = snap[i]
      local m = entry.mon
      if type(m) == "table" and effectiveHeldItemOf(m, gen2) == nil then
        if gen2 then m.item = entry.item else m[SAVED_FIELD] = entry.item end
        restored = restored + 1
      end
    end
    return restored
  end
  mod.exports.restoreHeldItems = restoreHeldItems

  ------------------------------------------------------------------
  -- The two battle boundaries. 1000 on started is the same early slot the
  -- TypeChart bootstrap uses (main.lua); -1000 on ended makes this the last
  -- listener, so every other ended handler still sees the real post-battle
  -- item state before it is handed back.
  ------------------------------------------------------------------
  mod.events:on("battle.started", function(ev)
    if not (ev and ev.battle) then return end
    snapshotHeldItems(ev.battle)
  end, 1000)

  mod.events:on("battle.ended", function(ev)
    if not (ev and ev.battle) then return end
    local restored = restoreHeldItems(ev.battle)
    if restored > 0 then
      mod.log:info("g9-battle-engine: modern_held_item_api restored %d "
        .. "held item(s) to the player's party after battle", restored)
    end
  end, -1000)

  mod.log:info("g9-battle-engine: modern_held_item_api installed "
    .. "(Gen-1 held-item save slot '" .. SAVED_FIELD .. "' + public "
    .. "get/set/clear API; player-party held-item snapshot on battle.started "
    .. "and restore of flinged/thieved/lost/consumed items on battle.ended, "
    .. "Gen 1 and Gen 2)")
end
