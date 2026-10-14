-- =============================================================================
-- MOVE USABILITY -- the ONE engine -> scene "can this Pokemon pick this move
-- right now, and if not, why not" query. (Round 100, user directive: "comms
-- between engine and scene: choice flag: only first move selected can be used,
-- switch in re-enables swapping moves. ban move type flag: items that for
-- example disable the use of status move but buffs a stat. and ensure that
-- moves like fakeout and lastresort can't be valid for use if their conditions
-- aren't fulfilled, so realistically, we need a way to tell scene to know
-- 'this move is invalid' so it sends the expected text to game and keep player
-- aware".)
-- =============================================================================
-- WHY THIS FILE EXISTS
-- The engine already ENFORCES every one of these rules at RESOLUTION time:
--   * Choice Band/Specs/Scarf  -> combat/modern_held_items_phase2.lua's
--     `Battle2:forcedMove`/`Battle2:useMove` monkeypatch
--     (`mon.ggdChoiceLockedMove`).
--   * Assault Vest's Status-move ban -> the same file's `Battle2:usableMoves`
--     filter, and combat/modern_status_effects.lua drives Taunt/Torment.
--   * Fake Out / First Impression / Last Resort -> the shared `registerFailGate`
--     seam (combat/modern_action_order.lua, combat/modern_side_protection.lua,
--     combat/modern_faint_sacrifice.lua), which announces the move, spends its
--     PP and prints "But it failed!".
-- But NONE of that is visible to a custom battle scene: g9-Battle-Scene builds
-- its own move menu from its own `Combat.allMoves` (a PP filter over the raw
-- move slots), so a Choice-locked mon was offered every move, an Assault Vest
-- holder was offered its Status moves, and Fake Out/Last Resort showed as
-- ordinary selectable moves -- the player only learned the rule after the move
-- had already spent its PP and fizzled. This file is the missing "talk to the
-- scene" half: ONE pure query that answers "selectable, or blocked with this
-- player-facing text", plus a registry so each move's OWNER keeps owning its
-- rule (exactly the `registerFailGate` pattern, one level up).
--
-- The query is read-only. Enforcement stays exactly where it already is; this
-- file adds no second resolution path and no second menu. A caller that ignores
-- it still gets today's resolution-time behaviour.
--
-- CONTRACT (all values plain data -- the scene JSON-ish-consumes it):
--   mod.exports.moveUsability(battle, mon, moveId)
--     -> nil                          -- selectable, no engine restriction
--     -> { reason = <string>,         -- player-facing refusal text
--          flag   = "choice"         -- why, for a caller that wants to style
--                 | "banned"          it differently
--                 | "volatile"
--                 | "condition" }
--   mod.exports.moveUsabilityReason(battle, mon, moveId) -> nil | string
--   mod.exports.moveUsabilityFlag(battle, mon, moveId)   -> nil | string
--   mod.exports.registerMoveUsabilityGate(moveId, fn)
--     fn(battle, mon, moveId, gen2) -> nil | { reason=, flag= }
--   mod.exports.moveUsabilityGateOf(moveId) -> fn | nil
--
-- `mon` may be a raw mon OR a battler wrapper (the scene's own battler table
-- has `.mon`); everything below unwraps once through `rawMon`. PP is DELIBERATELY
-- not consulted: a 0-PP move is the scene's own concern (its `usable` flag),
-- and this query only answers "would the RULES let it be chosen". The one
-- exception is the Choice lock, where "the locked move has run out of PP" is
-- itself the rule that frees the lock (Showdown: a Choice lock is dropped when
-- the locked move can no longer be selected).
-- =============================================================================
return function(mod)
  local Strings = require("src.core.Strings")

  local isGen2Battle = mod.exports.isGen2Battle
  local isGen1Battle = mod.exports.isGen1Battle
  local displayNameFor = mod.exports.displayNameFor
  local MoveCategory = mod.exports.MoveCategory
  assert(isGen2Battle and isGen1Battle,
    "move_usability: combat/modern_combat.lua must load first")

  -- ==========================================================================
  -- SHARED READS
  -- ==========================================================================

  -- Raw mon behind a Gen-1 battler wrapper, or the mon itself on Gen 2 (the
  -- same unwrap every sibling file uses).
  local function rawMon(who) return who and (who.mon or who) or nil end

  -- Same positive Gen-2/Gen-1 identity checks modern_combat.lua exports; the
  -- mon-shape fallback (curStats only ever exists on a Gen-1 battler, .stats
  -- only ever on a real mon) covers a caller that hands this file a battle it
  -- cannot identify (the Max Guard ctx.battle lesson).
  local function gen2Of(battle, mon)
    local ok, r = pcall(isGen2Battle, battle)
    if ok and r then return true end
    ok, r = pcall(isGen1Battle, battle)
    if ok and r then return false end
    local m = rawMon(mon)
    return m ~= nil and m.curStats == nil and m.stats ~= nil
  end

  -- The mon's display name. Gen 1 has no player/foe flag on the RAW mon, so
  -- the side is read off `mon.multiSide` (the signal the scene tags every
  -- battler with, and the one move_targeting.lua's own N-way sideOf override
  -- reads) with `battle:sideOf` as the backup.
  local function nameOf(battle, mon, gen2)
    local m = rawMon(mon)
    if not m then return Strings("The Pokemon") end
    if gen2 then
      if displayNameFor then
        local ok, n = pcall(displayNameFor, battle, m, true)
        if ok and n then return n end
      end
      return m.name or m.species or Strings("The Pokemon")
    end
    local name = m.name or m.species or Strings("The Pokemon")
    local side = m.multiSide
    if not side and battle and battle.sideOf then
      local ok, s = pcall(battle.sideOf, battle, m)
      if ok then side = s end
    end
    if side == "enemy" then return Strings("Enemy %s", name) end
    return name
  end

  -- national_dex's own move record -- the project's standing source of truth
  -- for category/priority flags.
  local function dexMoveInfo(moveId)
    local nationalDex = mod.find and mod.find("national_dex")
    local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
    if not (moveById and moveId) then return nil end
    local ok, info = pcall(moveById, moveId)
    if ok and type(info) == "table" then return info end
    return nil
  end

  -- national_dex's own move FLAGS (contact/heal/sound/...), resolved lazily
  -- for the heal-block gate below.
  local function moveFlagsOf(moveId)
    local nationalDex = mod.find and mod.find("national_dex")
    local moveFlags = nationalDex and nationalDex.exports and nationalDex.exports.moveFlags
    if not (moveFlags and moveId) then return nil end
    local ok, flags = pcall(moveFlags, moveId)
    if ok and type(flags) == "table" then return flags end
    return nil
  end

  -- The live move def: the battle's own moveDef first (Gen 2), then
  -- national_dex, then the battle's raw data table.
  local function moveDefOf(battle, moveId)
    if battle and battle.moveDef then
      local ok, def = pcall(function() return battle:moveDef(moveId) end)
      if ok and def then return def end
    end
    local info = dexMoveInfo(moveId)
    if info then return info end
    if battle and battle.data and battle.data.moves then
      return battle.data.moves[moveId]
    end
    return nil
  end

  local function moveNameOf(battle, moveId)
    local def = moveDefOf(battle, moveId)
    return (def and def.name) or moveId
  end

  -- national_dex's OWN damage-class spelling ("status"/"physical"/"special"),
  -- then MoveCategory.of, then the power==0 convention. This is the SAME
  -- chain combat/modern_held_items_phase2.lua's Assault Vest filter already
  -- used, so the query and the enforcement can never disagree about what a
  -- Status move is.
  local function categoryOf(battle, moveId)
    local info = dexMoveInfo(moveId)
    if info and info.damageClass then return info.damageClass end
    local def = moveDefOf(battle, moveId)
    if MoveCategory and MoveCategory.of and def then
      local ok, cat = pcall(MoveCategory.of, def)
      if ok and cat then return tostring(cat):lower() end
    end
    if def and (def.power or 0) == 0 then return "status" end
    return nil
  end

  -- Taunt is enforced in combat/modern_status_effects.lua by the engine's own
  -- `(def.power or 0) == 0` test, so the menu must read the SAME test or it
  -- would offer a move the engine then refuses.
  local function isStatusByPower(battle, moveId)
    local def = moveDefOf(battle, moveId)
    return def ~= nil and (def.power or 0) == 0
  end

  local function moveSlotOf(mon, moveId)
    for _, ms in ipairs(mon.moves or {}) do
      if ms and ms.id == moveId then return ms end
    end
    return nil
  end

  -- ==========================================================================
  -- HELD ITEMS
  -- ==========================================================================
  -- itemOf boots in combat/modern_items.lua, AFTER this file (this file must
  -- boot right after modern_combat so registerMoveUsabilityGate exists before
  -- the condition owners register), so every item read is resolved lazily at
  -- CALL time -- never captured at boot -- with the raw field layout inlined
  -- as the pre-boot fallback.
  local function itemFor(battle, mon)
    local itemOf = mod.exports.itemOf
    if itemOf then
      local ok, item = pcall(itemOf, mon, gen2Of(battle, mon))
      if ok then return item end
    end
    local m = rawMon(mon)
    if not m then return nil end
    if gen2Of(battle, mon) then return m.item end
    return m.g9HeldItem
  end

  local function itemLabelOf(battle, itemId)
    local itemLabel = mod.exports.itemLabel
    if itemLabel then
      local ok, label = pcall(itemLabel, battle, itemId)
      if ok and label then return label end
    end
    return itemId
  end

  local CHOICE_ITEMS = {
    CHOICE_BAND = true, CHOICE_SPECS = true, CHOICE_SCARF = true,
  }

  --------------------------------------------------------------------------
  -- "BAN A MOVE TYPE" -- the item-carried flag the user asked for. One table
  -- entry per item is the whole wiring: `categories` lists the national_dex
  -- damage classes the item forbids (a stat boost is the item's own separate
  -- effect, already live through the stat-multiplier family), `exceptions`
  -- lists move ids the ban does not cover. Assault Vest is the real one
  -- (Showdown items.ts: "Prevents the holder from selecting any status moves";
  -- the real Me First exception is `move.id !== 'mefirst'`). Any future
  -- item that bans a move category is one more row here.
  --------------------------------------------------------------------------
  local ITEM_MOVE_BANS = {
    ASSAULT_VEST = {
      categories = { status = true },
      exceptions = { MEFIRST = true },
    },
  }

  -- mod.exports.itemMoveBanned(battle, mon, moveId) -> nil | {flag,item,reason}
  -- Exported so combat/modern_held_items_phase2.lua's native `usableMoves`
  -- filter (a separate enforcement seam) is driven by THIS one definition
  -- rather than a second copy of the Status test.
  function mod.exports.itemMoveBanned(battle, mon, moveId)
    local m = rawMon(mon)
    if not (m and moveId) then return nil end
    if battle and battle.magicRoomActive then return nil end -- Magic Room suppresses held items
    local item = itemFor(battle, m)
    local rule = item and ITEM_MOVE_BANS[item]
    if not rule then return nil end
    if rule.exceptions and rule.exceptions[moveId] then return nil end
    if not rule.categories[categoryOf(battle, moveId)] then return nil end
    return {
      flag = "banned",
      item = item,
      reason = Strings("%s can't use %s while holding the %s!",
        nameOf(battle, m, gen2Of(battle, m)), moveNameOf(battle, moveId), itemLabelOf(battle, item)),
    }
  end

  -- ==========================================================================
  -- BUILT-IN GATES -- the three rules the engine already enforces at
  -- resolution, restated as selection-time answers.
  -- ==========================================================================

  --------------------------------------------------------------------------
  -- CHOICE BAND / CHOICE SPECS / CHOICE SCARF -- locked to the first move
  -- used, cleared by a switch (the loop is closed by the battle.move_used /
  -- battle.battler_switched listeners below, which set/clear the SAME
  -- `mon.ggdChoiceLockedMove` field modern_held_items_phase2.lua owns, so the
  -- scene and the resolution path can never disagree).
  --------------------------------------------------------------------------
  local function choiceGate(battle, mon, moveId)
    if battle and battle.magicRoomActive then return nil end -- Magic Room suppresses the lock
    local locked = mon.ggdChoiceLockedMove
    if not locked then return nil end
    local item = itemFor(battle, mon)
    if not (item and CHOICE_ITEMS[item]) then
      -- The item is gone (stolen/knocked off/consumed) -- the lock dies with it.
      mon.ggdChoiceLockedMove = nil
      return nil
    end
    if locked == moveId then return nil end
    -- Showdown frees the lock the moment the locked move can no longer be
    -- selected (a real, documented Choice behaviour -- PP exhausted means the
    -- mon is free to pick again rather than being frozen out).
    local slot = moveSlotOf(mon, locked)
    if not slot or (slot.pp or 0) <= 0 then
      mon.ggdChoiceLockedMove = nil
      return nil
    end
    return {
      flag = "choice",
      locked = locked,
      reason = Strings("%s is locked into %s!",
        nameOf(battle, mon, gen2Of(battle, mon)), moveNameOf(battle, locked)),
    }
  end

  local function itemBanGate(battle, mon, moveId)
    return mod.exports.itemMoveBanned(battle, mon, moveId)
  end

  --------------------------------------------------------------------------
  -- TAUNT / TORMENT -- Gen-2 volatiles (combat/modern_status_effects.lua
  -- already refuses them at useMove; this is the matching menu answer). No
  -- Gen-1 arm: that file's own enforcement is Gen-2-gated too.
  --------------------------------------------------------------------------
  local function volatileGate(battle, mon, moveId, gen2)
    if not (battle and gen2) then return nil end
    local vol = mon.volatile
    if type(vol) ~= "table" then return nil end
    local name = nameOf(battle, mon, true)
    if vol.tauntTurns and isStatusByPower(battle, moveId) then
      return {
        flag = "volatile",
        reason = Strings("%s can't use %s after the taunt!",
          name, moveNameOf(battle, moveId)),
      }
    end
    if vol.tormented and vol.lastMove == moveId then
      return {
        flag = "volatile",
        reason = Strings("%s can't use the same move twice in a row!", name),
      }
    end
    return nil
  end

  --------------------------------------------------------------------------
  -- HEAL BLOCK / the boss-fight "healblock" flag (combat/heal_block.lua owns
  -- the rule and the turn counter; this is only its selection-time answer,
  -- both generations). A move carrying national_dex's `heal` flag is refused
  -- while the mon cannot restore HP.
  --------------------------------------------------------------------------
  local function healBlockGate(battle, mon, moveId)
    local healBlocked = mod.exports.healBlocked
    if not healBlocked then return nil end
    local ok, blocked = pcall(healBlocked, battle, mon)
    if not (ok and blocked) then return nil end
    local flags = moveFlagsOf(moveId)
    if not (flags and flags.heal) then return nil end
    return {
      flag = "healblock",
      reason = Strings("%s can't use healing moves!",
        nameOf(battle, mon, gen2Of(battle, mon))),
    }
  end

  --------------------------------------------------------------------------
  -- BIDE (combat/modern_bide.lua owns the mechanic).  While the store is
  -- counting down the user is LOCKED: only BIDE itself may be selected
  -- (Showdown's `onLockMove: 'bide'`; the cart's fightLockedAction, which
  -- skips the move menu entirely).  The scene builds its own menu, so this
  -- is the query that tells it every OTHER move is forbidden -- without it
  -- the player could pick Tackle mid-Bide and the store would never resolve.
  -- Gen 2 reads the engine's own volatile (the state modern_bide's run sets).
  -- Gen 1 reads the native battler's `bideTurns` -- the field the cart's own
  -- continueBide consumes -- reached through the scene's mon -> battler map
  -- (native.lua's battlersByMon), which the query has because the scene hands
  -- it the real BattleState it built.
  --------------------------------------------------------------------------
  local function bideGate(battle, mon, moveId, gen2)
    if moveId == "BIDE" then return nil end
    local active = false
    if gen2 then
      local vol = mon.volatile
      active = type(vol) == "table" and vol.bideTurns ~= nil
    else
      local map = battle and battle.battlersByMon
      local battler = type(map) == "table" and map[mon] or nil
      active = battler ~= nil and battler.bideTurns ~= nil
    end
    if not active then return nil end
    return {
      flag = "volatile",
      reason = Strings("%s is locked into %s!",
        nameOf(battle, mon, gen2), moveNameOf(battle, "BIDE")),
    }
  end

  -- ==========================================================================
  -- THE QUERY
  -- ==========================================================================
  local gates = {}
  -- Registry, keyed by move id -- the same shape (and the same rationale) as
  -- combat/modern_action_order.lua's registerFailGate: the move that owns a
  -- condition owns the selection-time answer too, so the two can never drift.
  function mod.exports.registerMoveUsabilityGate(moveId, fn)
    assert(type(moveId) == "string" and type(fn) == "function",
      "registerMoveUsabilityGate: (moveId, fn) required")
    if gates[moveId] then return end
    gates[moveId] = fn
  end
  function mod.exports.moveUsabilityGateOf(moveId) return gates[moveId] end

  -- --------------------------------------------------------------------------
  -- PER-BATTLE SCOPING. Every rule above reasons about state the OWNER module
  -- keeps on the RAW MON -- `__g9MoveActions` (modern_action_order), the
  -- per-slot `__g9Used` marks (modern_faint_sacrifice), the Choice lock
  -- `ggdChoiceLockedMove`, `__g9LostFocus`. Those owners clear it on the
  -- engine's own lifecycle events (`battle.started` resets the leads,
  -- `battle.battler_switched` resets a switch-in, `battle.turn_started`
  -- clears the focus flag). A native battle emits all of them. A REPLACEMENT
  -- scene need not: g9-Battle-Scene's Gen-1 model builds a real BattleState
  -- by hand (`native.lua` N.buildBattle) and never runs the native
  -- constructor's `battle.started`, so a party mon -- which persists across
  -- battles -- carries last battle's counters into the next one and a move
  -- like Fake Out is wrongly refused on the new battle's first turn.
  --
  -- Rather than depend on a scene emitting an event it may never emit, scope
  -- this state to the battle HERE: the first time this query sees a given mon
  -- in a NEW battle, clear every per-battle field it reads. Cheap (one number
  -- compare per call) and it can never wipe state mid-battle, since within a
  -- battle `mon.__g9UsabilityBattle` already equals this battle's id.
  --
  -- ROUND 113 -- the marker must NOT be the battle TABLE itself. `m` here is
  -- the RAW party mon -- the exact table SaveSerializer walks as save.party --
  -- so writing the live battle onto it leaked the whole battle object into the
  -- save: mon -> battle -> battle.party (== save.party) -> mon is a cycle, and
  -- battle.__g9ChosenMoves (combat/turn_order.lua) is keyed BY mon tables.
  -- Saving after ANY battle therefore died inside SaveSerializer's writer --
  -- infinite recursion ("stack overflow") on Gen 1, or its key sort reaching
  -- two table keys ("attempt to compare two table values") on Gen 2 once two
  -- actors had chosen a move. A plain, monotonically-assigned number carries
  -- the identical "is this the same battle?" answer and serializes as a
  -- number, so nothing battle-scoped ever reaches the save. Self-healing for
  -- any mon still holding a stale table marker from an older build: a table
  -- never equals a number, so the next query overwrites it.
  -- --------------------------------------------------------------------------
  local battleIds = setmetatable({}, { __mode = "k" })
  local lastBattleId = 0
  local function battleIdOf(battle)
    local id = battleIds[battle]
    if not id then
      lastBattleId = lastBattleId + 1
      id = lastBattleId
      battleIds[battle] = id
    end
    return id
  end

  local function scopeToBattle(m, battle)
    local id = battleIdOf(battle)
    if m.__g9UsabilityBattle == id then return end
    m.__g9UsabilityBattle = id
    m.__g9MoveActions = nil
    m.__g9LostFocus = nil
    m.ggdChoiceLockedMove = nil
    for _, ms in ipairs(m.moves or {}) do ms.__g9Used = nil end
  end

  function mod.exports.moveUsability(battle, mon, moveId)
    local who = mon
    local m = rawMon(mon)
    if not (battle and m and moveId) then return nil end
    scopeToBattle(m, battle)
    local gen2 = gen2Of(battle, m)

    -- healBlockGate gets the ORIGINAL battler (wrapper or raw mon): the heal
    -- volatile can live on either shape, and heal_block.lua's predicate reads
    -- both, so unwrapping here would hide a wrapper-held flag.
    local res = choiceGate(battle, m, moveId)
      or itemBanGate(battle, m, moveId)
      or healBlockGate(battle, who, moveId)
      or bideGate(battle, m, moveId, gen2)
      or volatileGate(battle, m, moveId, gen2)
    if res then return res end

    local fn = gates[moveId]
    if fn then
      local ok, r = pcall(fn, battle, m, moveId, gen2)
      if ok and type(r) == "table" and r.reason then return r end
    end
    return nil
  end

  function mod.exports.moveUsabilityReason(battle, mon, moveId)
    local res = mod.exports.moveUsability(battle, mon, moveId)
    return res and res.reason or nil
  end

  function mod.exports.moveUsabilityFlag(battle, mon, moveId)
    local res = mod.exports.moveUsability(battle, mon, moveId)
    return res and res.flag or nil
  end

  -- ==========================================================================
  -- CHOICE LOCK BOOKKEEPING
  -- ==========================================================================
  -- Gen 2 already sets/clears this from modern_held_items_phase2.lua's own
  -- `Battle2:useMove` / `battle.battler_switched` patches; the listeners below
  -- are the GEN-1 arm of the same rule (Gen 1's move path is the scene's own
  -- `BattleState:performMove`, which emits `battle.move_used` -- see
  -- combat/modern_move_flags.lua's own header for that contract) and are
  -- idempotent on Gen 2.
  mod.events:on("battle.move_used", function(ev)
    local battle = ev and ev.battle
    local user = rawMon(ev and ev.user)
    if not (battle and user) then return end
    if ev.isCalled then return end -- a Metronome/Sleep Talk pick never sets the lock
    if battle.magicRoomActive then return end
    local item = itemFor(battle, user)
    if not (item and CHOICE_ITEMS[item]) then return end
    local id = (ev.move and ev.move.id) or ev.moveId
    if id then user.ggdChoiceLockedMove = id end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local prev = rawMon(ev and ev.previous)
    if prev then prev.ggdChoiceLockedMove = nil end
  end)

  mod.log:info("g9-battle-engine: move_usability installed (engine -> scene "
    .. "selection validity: Choice lock, item move-type bans incl. Assault Vest, "
    .. "Taunt/Torment, and the fakeout/firstimpression/lastresort condition gates)")
end
