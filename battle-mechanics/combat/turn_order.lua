-- Turn order: Generation 9 / Pokemon Showdown-accurate action sequencing,
-- owned entirely by this mod -- "we are the bible and process of combat"
-- applies here the same as everywhere else in combat/. Replaces
-- gen2/Battle.lua's own native comparator (priority from a small Gen-2
-- effect table with no Trick Room concept, then Quick Claw, then raw
-- Speed, then a coin-flip tie) through the engine's own sanctioned
-- extension point.
--
-- SOURCES, for the mechanic itself (verified 2026-08-20 against primary
-- sources, not assumed or taken from a single search summary -- the
-- first search this session returned the WRONG, outdated rule):
-- - https://github.com/smogon/pokemon-showdown/pull/6100 -- "Dynamic
--   speed updates for Gen 8," the actual Pokemon Showdown PR that
--   introduced re-sorting the remaining action queue by CURRENT speed
--   after each action resolves. Standing behavior through Gen 9.
--   Confirms Gen 7 and earlier computed order once at turn start and
--   never revisited it -- the older rule most casual sources describe.
-- - https://pokemondb.net/pokebase/250090/what-happens-if-there-is-speed-change-in-the-middle-of-a-turn
--   -- the pre-Gen-8 rule, for contrast; this is what a naive search
--   turns up first and is easy to mistake for the current rule.
-- - https://bulbapedia.bulbagarden.net/wiki/User:FIQ/Turn_sequence --
--   the exact Speed calculation formula (stat-stage multiplier,
--   paralysis's 2048/4096 factor as of Gen 7+).
-- - https://bulbapedia.bulbagarden.net/wiki/Priority -- priority
--   bracket / Speed-tiebreak general reference.
--
-- SCOPE, stated plainly: this file owns the STRUCTURAL comparator --
-- priority bracket, Trick-Room-aware Speed compare, random tie-break --
-- generically over an arbitrary list of actors. It does NOT compute
-- effective Speed itself (stat stages, paralysis, item/ability speed
-- multipliers like Choice Scarf or Swift Swim, or ability-based priority
-- like Prankster) -- that is a separate, much larger body of work
-- (dozens of items/abilities), out of scope here. Callers pass in
-- already-resolved speed/priority numbers; this file only decides ORDER
-- given those numbers. Today's one real caller (the battle.turn_order
-- wrap below) reuses the engine's own native Battle:effectiveSpeed and
-- Battle:movePriority. Battle:movePriority was a real, confirmed bug --
-- it read ONLY a small legacy table keyed by native effect id (Quick
-- Attack/Protect/Counter/etc.), silently treating every move outside that
-- legacy list as priority 0 and falling through to a raw Speed compare.
--
-- PRIORITY'S OWNER (explicit user rule, 2026-09-10): national_dex is the
-- absolute owner of a move's priority property; this engine only CONSUMES
-- it, never authors or overrides it. So movePriority now reads priority
-- from national_dex's own moveById(moveId) reply FIRST (cached per move
-- id below). That reply is authoritative for every move national_dex has
-- a record for, which is exactly the set of real moves.
--
-- WHY THE OLD PATHS COULDN'T BE TRUSTED (the reported Protect bug): the
-- live engine record (self:moveDef) is the CART's own gen2 record for a
-- move the cart already shipped. national_dex deliberately leaves such a
-- record ALONE rather than re-registering it (mod/src/moves.lua: "A move
-- the running cart already describes is left ALONE, not overridden"), so
-- that live record has NO `priority` field at all. This engine then repoints
-- several of those same moves' `effect` at its own handlers (e.g.
-- modern_combat_protect.lua patches PROTECT/DETECT onto GMAX_PROTECT_EFFECT),
-- which also defeats the legacy Battle.PRIORITY[effect] table -- so both
-- fallbacks missed and priority silently became 0. Reading national_dex's
-- own record sidesteps all of that: national_dex knows PROTECT is +4
-- regardless of what the cart record or the live effect id happen to be.
--
-- The two legacy paths are kept ONLY as a fallback for a move that
-- national_dex has no record for at all -- e.g. an engine-synthetic id like
-- BATTLE_FORMS_MAXGUARD. This mod stays self-contained -- gen1recomp-dev's
-- own source is never edited -- so the fix is a monkeypatch of
-- Battle.movePriority itself, right below, not an engine change.
-- effectiveSpeed's own accuracy (item/ability speed multipliers,
-- Prankster-style ability priority) remains genuinely out of scope, per
-- the paragraph above.
--
-- Trick Room is accepted as an input flag (opts.trickRoom), not
-- something this file activates or tracks -- combat/trick_room.lua owns
-- the real move effect (a real 5-turn activation, -7 priority, toggle-off
-- on reuse, confirmed against Bulbapedia) and writes the
-- battle.trickRoomActive field the wiring below reads. Kept as two
-- separate files on purpose: this one only ever needs to know the
-- CURRENT value of that flag, never how or when it gets set.
--
-- MULTI-BATTLER READINESS: see combat/MULTI_BATTLE_HOOKS.md for the real
-- contract. computeTurnOrder below is an INTERNAL PRIMITIVE, not the
-- integration point -- a future multi-battler mod should not call it
-- directly, since that would mean it derives priority/Speed/Trick-Room/
-- RNG itself, exactly the caller-side computation that doc's contract
-- exists to avoid. The actual seam is mod.exports.resolveTurnActions
-- (not yet built, spec'd in that doc) -- hand it battler identity only,
-- it derives everything else the same way this file's own
-- battle.turn_order wiring already does below. computeTurnOrder itself
-- IS already generic over N actors on either side, including asymmetric
-- formats (4v1, 1v5, 4vN) -- a flat list, no concept of "sides" anywhere
-- in it -- which is what makes it the right primitive for
-- resolveTurnActions to be built on. What is NOT yet possible is calling
-- it more than once per turn (a genuine mid-turn re-sort, matching PR
-- #6100 exactly) -- gen2/Battle.lua's own turn-resolution loop is a
-- hard-coded two-branch call with no second extension point between the
-- two actions, and nothing beyond 2 actors exists in this engine's data
-- model at all. Both are real engine-level gaps, not something reachable
-- from mod code as it stands -- see MULTI_BATTLE_HOOKS.md for the full
-- explanation and what a future multi-battler mod would need to bring.
return function(mod)
  local Strings = require("src.core.Strings")
  -- Gen 1 (round 100): there is no Gen-2 Battle/Damage class, and the
  -- sandbox's cross-generation denial refuses both names
  -- (src/mods/Loader.lua crossGenerationDenial), which used to abort this
  -- file's boot -- and, through its "must load first" asserts, the whole
  -- round-100 selection-gate chain (action_order -> side_protection ->
  -- faint_sacrifice). Guarded exactly like modern_combat.lua's own gen2
  -- requires: on Gen 1 both are nil, the Gen-2-only monkeypatch and the
  -- Gen-2 speed composition below are skipped, and everything this file
  -- OWNS for the selection gates (chosenMoveOf / prioritizeActor /
  -- deprioritizeActor / registerPriorityModifier and the gen-agnostic
  -- bookkeeping behind them) still installs. Gen-1 turn resolution runs
  -- through BattleState:performMove and never calls into resolveTurnActions.
  local okDmg, Damage = pcall(require, "src.battle.gen2.Damage")
  Damage = okDmg and Damage or nil
  local okBattle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = okBattle and Battle or nil
  -- The real runtime event bus, the same one native closeTurn emits
  -- battle.turn_ended through and the same one every mod.events:on listener
  -- receives from (see the round-sixty-seven end-of-turn block below).
  local okRuntime, Runtime = pcall(require, "src.mods.Runtime")
  Runtime = (okRuntime and type(Runtime) == "table") and Runtime or nil

  -- Real bug fix, monkeypatched rather than edited into the engine (see
  -- this file's own header). PRIORITY IS national_dex's TO OWN -- the
  -- explicit user rule -- so the resolution order is:
  --   1. national_dex's own moveById(moveId).priority, when that mod has a
  --      record for the move AND carries a numeric priority field. This is
  --      the authoritative answer for every real move. It is what makes
  --      PROTECT (+4), DETECT (+4), QUICK_ATTACK (+1), COUNTER (-5),
  --      MIRRORCOAT (-5), TRICKROOM (-7) etc. actually order correctly.
  --   2. Otherwise (no national_dex record -- e.g. an engine-synthetic id
  --      like BATTLE_FORMS_MAXGUARD -- or a record without a priority
  --      field): the live record's own def.priority if it carries one, then
  --      the legacy Battle.PRIORITY[def.effect] table, then 0.
  -- The old code ONLY did (2), which is exactly why the cart moves broke:
  -- national_dex leaves a cart-registered move's record alone (so the live
  -- record has no priority field), and this engine repoints several of
  -- those moves' `effect` at its own handlers, so Battle.PRIORITY missed
  -- too -- 0, then a raw Speed compare. national_dex's reply is unaffected
  -- by either.
  --
  -- The reply is cached per move id: moveById deep-copies its record on
  -- every call, and priority is a static property of the move (caster-
  -- dependent modifiers are applied separately, below), so re-reading it
  -- every turn would be pure waste.
  --
  -- Phase 5 (abilities/engine/priority_change.lua): registerPriorityModifier
  -- -- the same composable-chain shape registerDamageModifier already is
  -- (combat/modern_combat.lua), just for priority instead of damage.
  -- `caster` is a NEW, OPTIONAL 2nd param -- every existing call site
  -- (this file's own resolveTurnActions/battle.turn_order wrap below, plus
  -- combat/modern_terrain.lua's Psychic Terrain block) now passes it, but
  -- it defaults to nil for any other caller (e.g. tests/
  -- gen2_battle_ui_test.lua's own direct calls), which simply skips every
  -- modifier -- an ability can never change priority without knowing WHO
  -- is using the move, so "no caster given" correctly means "base priority
  -- only," identical to this function's pre-existing behavior.
  local priorityModifiers = {} -- { {id=, fn=fn(battle,moveId,caster,def)->delta}, ... }
  local function registerPriorityModifier(id, fn)
    assert(type(id) == "string" and id ~= "", "priority modifier id is required")
    assert(type(fn) == "function", "priority modifier must be a function")
    for i, entry in ipairs(priorityModifiers) do
      if entry.id == id then table.remove(priorityModifiers, i) break end
    end
    table.insert(priorityModifiers, { id = id, fn = fn })
  end
  mod.exports.registerPriorityModifier = registerPriorityModifier

  -- national_dex's own priority for a move id, or nil when it has no record
  -- for the move (or no numeric priority on it). Lazily resolves the mod's
  -- exports once, then caches each move's answer for the rest of the
  -- battle's lifetime. A cached `false` means "national_dex has no answer
  -- for this id" and is distinct from a cached 0 (which is a real, valid
  -- priority) -- so 0 is never confused with "not found."
  local nationalDexMoveById -- lazily-resolved function, or false once known-absent
  local dexPriorityCache = {}
  local function nationalDexPriority(moveId)
    if type(moveId) ~= "string" then return nil end
    local cached = dexPriorityCache[moveId]
    if cached ~= nil then
      if cached == false then return nil end
      return cached
    end
    if nationalDexMoveById == nil then
      local nd = mod.find and mod.find("national_dex")
      nationalDexMoveById = (nd and nd.exports and nd.exports.moveById) or false
    end
    -- national_dex genuinely absent: don't cache, so a later load (mod
    -- load order is not this file's to guarantee) can still be picked up.
    if not nationalDexMoveById then return nil end
    local ok, info = pcall(nationalDexMoveById, moveId)
    if not ok or type(info) ~= "table" or type(info.priority) ~= "number" then
      dexPriorityCache[moveId] = false
      return nil
    end
    dexPriorityCache[moveId] = info.priority
    return info.priority
  end

  -- priorityWithModifiers: the ONE priority algorithm this engine uses, on
  -- BOTH generations. national_dex owns a move's priority and is consumed
  -- first; `fallback` is the caller's own non-national_dex base -- Gen 2's
  -- live record + legacy effect table, Gen 1's own BattleState move record +
  -- the two native entries -- so a move national_dex has no record for (an
  -- engine-synthetic id like BATTLE_FORMS_MAXGUARD) still orders correctly
  -- on whichever engine is running. The registerPriorityModifier chain is
  -- applied on top (abilities/engine/priority_change.lua's Prankster/Gale
  -- Wings/Triage, switch_priority_misc's Stall/Quick Draw/Mycelium Might,
  -- modern_side_protection's Grassy Glide, modern_held_items_phase2's
  -- Lagging Tail). Battle:movePriority below and this file's own Gen-1
  -- resolver (resolveTurnActionsForGen1) are provably ONE algorithm, not two
  -- that can drift -- the same reason computeTurnOrder is shared.
  local function priorityWithModifiers(battle, moveId, caster, def, fallback)
    local base = nationalDexPriority(moveId)
    if base == nil then base = fallback or 0 end
    if caster then
      for _, entry in ipairs(priorityModifiers) do
        base = base + (entry.fn(battle, moveId, caster, def) or 0)
      end
    end
    return base
  end
  mod.exports.priorityWithModifiers = priorityWithModifiers

  -- Gen 1 has no Gen-2 Battle class to monkeypatch: its ordering is owned by
  -- resolveTurnActionsForGen1 below, which calls the SAME
  -- priorityWithModifiers this monkeypatch does.
  if Battle then
  function Battle:movePriority(moveId, caster)
    local def = self:moveDef(moveId)
    -- Fallback for a move national_dex has no record for (e.g. an
    -- engine-synthetic id): the live record's own field, then the legacy
    -- effect table. national_dex's own answer, when it has one, is consumed
    -- first inside priorityWithModifiers.
    local fallback = 0
    if def then
      if def.priority ~= nil then
        fallback = def.priority
      else
        fallback = Battle.PRIORITY[def.effect] or 0
      end
    end
    return priorityWithModifiers(self, moveId, caster, def, fallback)
  end
  end -- if Battle

  -- A never-nil 0..n-1 roller, the same convention Battle:roller() uses
  -- (gen2/Battle.lua) -- accepted as an explicit parameter rather than
  -- reached for globally, so this stays a pure function callable outside
  -- a live battle (e.g. a future test suite) with any roller handed in,
  -- including a stubbed one.
  local function fisherYatesShuffle(list, roller)
    for i = #list, 2, -1 do
      local j = roller(i) + 1 -- roller gives 0..i-1; Lua arrays are 1-indexed
      list[i], list[j] = list[j], list[i]
    end
  end

  -- Computes the real turn order for an arbitrary list of actors --
  -- generic over how many there are or how they split between sides, so
  -- 1v1, 2v2, 3v3, and asymmetric formats (4v1, 1v5, 4vN) all go through
  -- the identical code path with no special-casing anywhere. See
  -- combat/MULTI_BATTLE_HOOKS.md for the full contract and worked
  -- examples.
  --
  -- actors: array of { id = <opaque, anything>, priority = <integer>,
  --   speed = <number>, ... } -- any extra fields are preserved on the
  --   returned entries untouched, so a caller can carry its own metadata
  --   (which mon, which action, which side) through the sort for free.
  -- opts.trickRoom: boolean, default false. Reverses the SPEED
  --   comparison direction within a priority bracket only -- priority
  --   itself always resolves high-to-low regardless of Trick Room, the
  --   one rule that has never changed across every generation Trick
  --   Room has existed in.
  -- opts.roller: function(n) -> 0..n-1, REQUIRED whenever the actor list
  --   can contain a genuine tie (same priority AND same speed) --
  --   asserted rather than silently defaulted, since a silent fallback
  --   RNG would make tie-break outcomes depend on which Lua happens to
  --   be running rather than the battle's own seeded stream.
  --
  -- Returns a NEW array (the same actor tables, in resolved order) --
  -- never mutates the input array or its entries.
  local function computeTurnOrder(actors, opts)
    opts = opts or {}
    local trickRoom = opts.trickRoom == true
    assert(type(actors) == "table", "computeTurnOrder: actors must be a table")

    local list = {}
    for i, actor in ipairs(actors) do
      assert(type(actor) == "table", "computeTurnOrder: actor #" .. i .. " must be a table")
      assert(type(actor.priority) == "number", "computeTurnOrder: actor #" .. i .. " needs a numeric priority")
      assert(type(actor.speed) == "number", "computeTurnOrder: actor #" .. i .. " needs a numeric speed")
      list[i] = actor
    end
    if #list <= 1 then return list end

    -- Coarse sort: priority always high-to-low; speed high-to-low
    -- normally, low-to-high under Trick Room. A genuine tie (equal
    -- priority AND equal speed) is left unordered by this pass on
    -- purpose -- table.sort's comparator has to be a strict, transitive
    -- "less than," and one that randomly answers differently for the
    -- same pair on different calls is not one (it can corrupt the sort
    -- or throw "invalid order function for sorting"). Ties are resolved
    -- properly afterward instead.
    table.sort(list, function(a, b)
      if a.priority ~= b.priority then return a.priority > b.priority end
      if a.speed == b.speed then return false end
      if trickRoom then return a.speed < b.speed end
      return a.speed > b.speed
    end)

    -- Group consecutive equal (priority, speed) runs and shuffle each
    -- group with the battle's own RNG -- the real rule, confirmed this
    -- session against the actual PS source and the GitHub issue
    -- discussing it: a genuine tie is broken randomly through the
    -- battle's own RNG, not by side, turn count, or array position.
    local result = {}
    local i = 1
    while i <= #list do
      local j = i
      while j < #list and list[j + 1].priority == list[i].priority
          and list[j + 1].speed == list[i].speed do
        j = j + 1
      end
      if j > i then
        assert(type(opts.roller) == "function",
          "computeTurnOrder: a tie exists (priority=" .. tostring(list[i].priority) ..
          ", speed=" .. tostring(list[i].speed) .. ") and opts.roller was not provided")
        local bucket = {}
        for k = i, j do bucket[#bucket + 1] = list[k] end
        fisherYatesShuffle(bucket, opts.roller)
        for _, actor in ipairs(bucket) do result[#result + 1] = actor end
      else
        result[#result + 1] = list[i]
      end
      i = j + 1
    end
    return result
  end
  mod.exports.computeTurnOrder = computeTurnOrder

  ------------------------------------------------------------------
  -- GEN 1 TURN RESOLUTION -- the engine owns turn order on Gen 1 too.
  --
  -- THE GAP THIS CLOSES. g9-Battle-Scene's Gen-1 backend (native.lua)
  -- resolves a turn natively: it insertion-sorts the queued actions with the
  -- game's own src/battle/TurnOrder.firstMover and executes each with
  -- BattleState:performMove. Its header states the contract -- a
  -- gen-1-capable engine mod "takes over by exporting
  -- resolveTurnActionsForGen1(battle, acting), checked first" -- and the
  -- scene genuinely calls it (native.lua:790-795). Until now this engine
  -- never exported it, so EVERY priority rule this engine owns was silently
  -- Gen-2-only on Gen 1: Battle:movePriority above is installed only
  -- `if Battle` and there is no Gen-2 Battle class on a Gen-1 boot, so
  -- national_dex's authoritative priority and the whole
  -- registerPriorityModifier chain (Prankster/Gale Wings/Triage, Stall/Quick
  -- Draw/Mycelium Might, Grassy Glide) were never consulted. Native ordering
  -- read only the cart's own move record (`move.priority`, else the two
  -- native entries QUICK_ATTACK/COUNTER).
  --
  -- WHAT THIS OWNS. The ORDER DECISION only -- which actor acts first, given
  -- priority and effective Speed -- exactly the scope the Gen-2
  -- resolveTurnActions has. It does NOT reimplement a move: every action is
  -- executed through the scene's own `battle:useMove(mon, target, moveId)`
  -- (native BattleState:performMove -- accuracy, damage, effects, status, PP,
  -- the real thing), the same "call the native primitive" discipline the
  -- scene already applies to catch/EXP. The scene drains battle:takeEvents()
  -- itself after this returns, so this never touches the event queue.
  --
  -- PER-ACTOR COMPOSITION:
  --   priority = priorityWithModifiers (national_dex first; fallback = the
  --     actor's own native move record + the two Gen-1 native entries) plus
  --     the Gen-1 fractional ITEM offset -- Quick Claw +0.1, Lagging Tail /
  --     Full Incense -0.1 -- via combat/modern_gen1_held_items.lua's own
  --     exported helper, rolled once per actor for the turn. The modifier
  --     chain is the SAME one Gen 2 consumes, so ability priority orders
  --     Gen-1 turns identically. (The Gen-2 `lagging_tail` modifier reads the
  --     Gen-2 item slot and so returns 0 here; the native fractional helper
  --     is what covers Gen 1 -- no double count.)
  --   speed = the game's OWN native effective Speed
  --     (src/battle/TurnOrder.effectiveSpeed: stat stages, badge boost,
  --     status penalty, and -- because modern_gen1_held_items.lua replaces
  --     that module field -- Choice Scarf / Quick Powder / Iron Ball). Read
  --     LAZILY, at call time, never captured at load time: turn_order boots
  --     before modern_gen1_held_items installs that patch, so a load-time
  --     capture would silently read the un-patched speed.
  --
  -- ORDERING: computeTurnOrder -- the same primitive, RNG tie-break and
  -- Trick-Room reversal the Gen-2 path uses, so 1v1 and any future N-actor
  -- format are provably one algorithm.
  --
  -- `caster` handed to every priority modifier is the RAW MON (action.mon),
  -- never the Gen-1 battler wrapper: abilityIdOf reads mon.ability and a
  -- Gen-1 wrapper has no ability of its own (src/battle/BattleState.lua:588
  -- makeBattler -- confirmed; the exact trap combat/modern_items.lua's own
  -- heldAbilityIdOf exists to avoid). itemOf unwraps `.mon` on its own, so
  -- item-reading modifiers still work when handed either.
  ------------------------------------------------------------------
  local GEN1_NATIVE_PRIORITY = { QUICK_ATTACK = 1, COUNTER = -1 }

  local function gen1BattlerFor(battle, mon)
    local byMon = battle and battle.battlersByMon
    return (byMon and byMon[mon]) or mon
  end

  local function gen1MoveDef(battle, moveId)
    if not (battle and type(battle.moveDef) == "function") then return nil end
    local ok, def = pcall(battle.moveDef, battle, { id = moveId })
    if ok and type(def) == "table" then return def end
    return nil
  end

  local function gen1EffectiveSpeed(battle, mon)
    local who = gen1BattlerFor(battle, mon)
    local ok, TurnOrder = pcall(require, "src.battle.TurnOrder")
    if ok and type(TurnOrder) == "table" and type(TurnOrder.effectiveSpeed) == "function" then
      local okSpd, speed = pcall(TurnOrder.effectiveSpeed, who)
      if okSpd and type(speed) == "number" then return speed end
    end
    -- Fallback (engine module absent): raw Speed through the real stat-stage
    -- helper. Badge/status composition is the engine's and stays there.
    local stats = (who and who.curStats) or (mon and mon.stats) or {}
    local raw = stats.speed or 0
    local stage = (who and who.stages and who.stages.speed) or 0
    local okStats, Stats = pcall(require, "src.pokemon.Stats")
    if okStats and type(Stats) == "table" and type(Stats.applyStage) == "function" then
      local okStage, value = pcall(Stats.applyStage, raw, stage)
      if okStage and type(value) == "number" then return value end
    end
    return raw
  end

  local function gen1Priority(battle, moveId, mon)
    local def = gen1MoveDef(battle, moveId)
    local fallback
    if def and def.priority ~= nil then
      fallback = def.priority
    else
      fallback = GEN1_NATIVE_PRIORITY[moveId] or 0
    end
    local priority = priorityWithModifiers(battle, moveId, mon, def, fallback)
    local fractional = mod.exports.gen1ItemFractionalPriority
    if type(fractional) == "function" then
      local roller = battle and battle.rng
      local ok, delta = pcall(fractional, gen1BattlerFor(battle, mon),
        type(roller) == "function" and roller or nil)
      if ok and type(delta) == "number" then priority = priority + delta end
    end
    return priority
  end

  local function gen1AliveOpponent(battle, mon)
    local sideByMon = battle and battle.sideByMon
    local roster = battle and battle.rosterMons
    if not (sideByMon and roster) then return nil end
    local side = sideByMon[mon]
    for _, other in ipairs(roster) do
      if other ~= mon and sideByMon[other] ~= side and (other.hp or 0) > 0 then
        return other
      end
    end
    return nil
  end

  -- -- Gen-1 STEPWISE turn resolution ---------------------------------
  -- The scene displays a turn to the player one visible beat at a time
  -- (message by message, bar-move by bar-move), so it cannot afford to
  -- resolve the whole turn up front: every state change -- a stat copy, a
  -- sprite swap, a faint -- would land before the first message FOR it had
  -- been shown. That is what made a Transform's sprite/stat exchange appear
  -- to happen before a higher-priority move's announcement even though the
  -- messages themselves were already in the right order.
  --
  -- So the resolution is split in two. beginTurnActionsForGen1 computes the
  -- turn's real order (computeTurnOrder -- the SAME primitive, RNG
  -- tie-break and Trick-Room reversal the Gen-2 path uses) and stores it on
  -- the battle. The caller then alternates resolveNextActionForGen1 (one
  -- actor's useMove) with draining/displaying the events that action
  -- emitted. resolveTurnActionsForGen1 below remains the batch convenience
  -- wrapper over the same two primitives, so every path still runs one
  -- algorithm.
  --
  -- failAction (defined further down, next to the faint-redirection helpers)
  -- is forward-declared here so the Gen-1 stepwise path below can announce a
  -- move the battle scene already knows has no legal recipient -- see the
  -- `action.fail` branch in resolveNextActionForGen1.  It is only ever
  -- CALLED at runtime, by which point the assignment further down has run.
  local failAction

  mod.exports.beginTurnActionsForGen1 = function(battle, actingBattlers)
    if not (battle and type(actingBattlers) == "table") then return 0 end

    ------------------------------------------------------------------
    -- SCENE-DRIVEN TURN BOUNDARY (Gen 1) -- the Gen-1 twin of the
    -- increment resolveTurnActions performs for Gen 2 (see that
    -- function's own round-sixty-six block further below).
    --
    -- Gen 1's turn counter is `battle.turnCount` (native
    -- BattleState:resolveTurn bumps it at BattleState.lua:2821). A
    -- replacement battle scene never runs that native path -- for Gen 1
    -- it drives beginTurnActionsForGen1 + resolveNextActionForGen1
    -- instead -- so in every scene-driven Gen-1 battle `turnCount`
    -- stayed at nil/0 for the whole battle. That is exactly what
    -- re-broke combat/modern_combat_protect.lua's shared Protect stall
    -- chain: its battleTurnOf() reads `battle.turn` first and falls back
    -- to `battle.turnCount` on Gen 1, so with the counter pinned the
    -- chain's `consecutive` test (`protectChainTurn == turn - 1`) was
    -- always false, the denominator `x` was always 1, and
    -- `battle.rng(1, x) == 1` always succeeded -- Protect/Detect/Endure
    -- could never decay and never fail, no matter how many turns in a
    -- row they were used. (The same pinned value also collapsed the
    -- per-(turn, attacker) shield-rider de-dup key, and left
    -- modern_move_flags.lua's cantusetwice / heal_block.lua's turn reads
    -- pinned for Gen 1.)
    --
    -- This is the one place the boundary can be restored from inside the
    -- engine: the scene calls beginTurnActionsForGen1 exactly once per
    -- turn (the batch wrapper resolveTurnActionsForGen1 below calls it
    -- exactly once too). Native itself NEVER calls this function -- its
    -- own resolveTurn owns that increment -- so there is no double-count
    -- and a normal (non-scene) Gen-1 battle's turnCount is untouched.
    -- Gen 2 is deliberately not touched here: its arm lives in
    -- resolveTurnActions and is already correct.
    ------------------------------------------------------------------
    battle.turnCount = (battle.turnCount or 0) + 1

    local roller = battle.rng
    local tieRoller
    if type(roller) == "function" then
      tieRoller = function(n) return roller(0, n - 1) end
    end
    local actors = {}
    for _, action in ipairs(actingBattlers) do
      local mon = action and action.mon
      if mon and (mon.hp or 0) > 0 and action.move then
        actors[#actors + 1] = {
          id = action, -- identity: carry the caller's own entry through
          priority = gen1Priority(battle, action.move, mon),
          speed = gen1EffectiveSpeed(battle, mon),
        }
      end
    end
    local ordered = computeTurnOrder(actors, {
      -- combat/trick_room.lua writes this field; a scene-driven Gen-1 battle
      -- sees whatever set it (a boss-fight permanent room included).
      trickRoom = battle.trickRoomActive == true,
      roller = tieRoller,
    })
    -- Stored on the battle (not captured in a closure) so the cursor
    -- survives across the scene's independently-paced calls. A fresh
    -- beginTurnActionsForGen1 resets it.
    battle.__g9Gen1Order = ordered
    battle.__g9Gen1OrderCursor = 1
    return #ordered
  end

  -- Resolves the NEXT still-pending actor of the turn begun above -- exactly
  -- one useMove -- and returns true. Returns false once the order is
  -- exhausted (its signal to the caller that, N.resolveTurn's wrapper apart,
  -- the caller should run end-of-turn). Actors that have fainted since the
  -- order was computed are skipped without consuming a "resolved" return, so
  -- the caller's display loop never stalls on an action that cannot happen.
  mod.exports.resolveNextActionForGen1 = function(battle)
    local ordered = battle and battle.__g9Gen1Order
    local cursor = battle and battle.__g9Gen1OrderCursor
    if not (type(ordered) == "table" and type(cursor) == "number") then
      return false
    end
    while cursor <= #ordered do
      local actor = ordered[cursor]
      battle.__g9Gen1OrderCursor = cursor + 1
      cursor = cursor + 1
      local action = actor and actor.id
      local mon = action and action.mon
      if mon and (mon.hp or 0) > 0 then
        if action.fail then
          -- The battle scene already knows this action has no legal
          -- recipient from THIS slot (its own positional adjacency refused
          -- every candidate): the move is used and fails, announced and
          -- PP-spent, at its own place in the order -- and every OTHER
          -- action this turn still resolves.
          failAction(battle, mon, action.move)
        else
          local target = action.target
          if not target or (target.hp or 0) <= 0 then
            target = gen1AliveOpponent(battle, mon)
          end
          if target and (target.hp or 0) > 0 and type(battle.useMove) == "function" then
            battle:useMove(mon, target, action.move)
          end
        end
        return true
      end
    end
    battle.__g9Gen1Order = nil
    battle.__g9Gen1OrderCursor = nil
    return false
  end

  -- mod.exports.resolveTurnActionsForGen1(battle, acting) -- the scene's own
  -- batch hook (see this block's header). acting is the same flat contract
  -- the Gen-2 path takes: { { mon = <real mon>, move = <moveId>,
  -- target = <real mon> }, ... }. Returns nothing; the caller drains events.
  mod.exports.resolveTurnActionsForGen1 = function(battle, actingBattlers)
    if not (battle and type(actingBattlers) == "table") then return end
    mod.exports.beginTurnActionsForGen1(battle, actingBattlers)
    while mod.exports.resolveNextActionForGen1(battle) do end
  end

  ------------------------------------------------------------------
  -- PHASE 5 (missing-effects plan) -- chosen-move visibility and a live,
  -- mid-turn reorder seam, both built on the SAME `ordered` list
  -- resolveTurnActions below already computes. Nothing here invents a
  -- second turn model; it only exposes the one that exists.
  --
  -- WHY THIS LIVES HERE: Sucker Punch/Thunderclap/Upper Hand all read
  -- "what did the target CHOOSE to do this turn" (Showdown
  -- moves.ts suckerpunch:18398-18404 / thunderclap:19501 / upperhand:
  -- 20194-20200 -- `this.queue.willMove(target)` plus the chosen move's
  -- `.category`/`.priority`), and After You/Quash (moves.ts
  -- afteryou:202-213 / quash:14463-14472) reorder that same queue. The
  -- `actingBattlers` contract already attaches each battler's chosen
  -- move (`.move`) and target (`.target`) at QUEUE time -- this file just
  -- publishes it so a sub-effect can read it, and keeps the order list
  -- mutable so a sub-effect can move a pending actor.
  ------------------------------------------------------------------

  -- indexOfActorForMon(list, mon): the position of an actor whose own
  -- `.id` (the battler entry resolveTurnActions built) carries `mon`.
  -- Identity compare on the mon table, never on a name/id string.
  local function indexOfActorForMon(list, mon)
    for i, actor in ipairs(list) do
      local entry = actor and actor.id
      if entry and entry.mon == mon then return i end
    end
    return nil
  end

  -- chosenMoveOf(battle, mon): the move id `mon` is still WAITING to use
  -- this turn, or nil once it has acted (or when no queue was published
  -- at all). This is Showdown's `this.queue.willMove(mon)?.move`: a mon
  -- that has already moved this turn has been spliced out of the queue
  -- and reads nil. resolveTurnActions publishes the map at the top of
  -- each turn and clears a mon's entry as its action resolves; the native
  -- turn loop publishes it from the battle.turn_order hook instead (see
  -- combat/modern_action_order.lua), which is the only pre-move moment
  -- native exposes both chosen move ids.
  mod.exports.chosenMoveOf = function(battle, mon)
    local map = battle and battle.__g9ChosenMoves
    if not (map and mon) then return nil end
    return map[mon]
  end

  -- prioritizeActor(battle, mon)/deprioritizeActor(battle, mon): move a
  -- still-PENDING actor to act NEXT / LAST among the actors who have not
  -- yet acted this turn. Both return false (the caller turns that into a
  -- real move failure) when there is no live order list, when `mon` is
  -- not in it, or when `mon` has already acted -- Showdown quash:
  -- "If the target has already acted this turn, this move will fail"
  -- (moves.ts:14459) and afteryou's `if (!action) return false`
  -- (moves.ts:206). Already-next/already-last are a successful no-op.
  mod.exports.prioritizeActor = function(battle, mon)
    local list = battle and battle.__g9OrderedActors
    local idx = battle and battle.__g9OrderIndex
    if not (list and idx and mon) then return false end
    local target = indexOfActorForMon(list, mon)
    if not target or target <= idx then return false end
    if target == idx + 1 then return true end
    local actor = table.remove(list, target)
    table.insert(list, idx + 1, actor)
    return true
  end
  mod.exports.deprioritizeActor = function(battle, mon)
    local list = battle and battle.__g9OrderedActors
    local idx = battle and battle.__g9OrderIndex
    if not (list and idx and mon) then return false end
    local target = indexOfActorForMon(list, mon)
    if not target or target <= idx then return false end
    if target == #list then return true end
    local actor = table.remove(list, target)
    table.insert(list, actor)
    return true
  end

  ------------------------------------------------------------------
  -- mod.exports.orderSwitchInMons(battle, monA, monB) -- speed order for
  -- SIMULTANEOUS switch-in triggers (explicit user rule, this session's
  -- Phase 1.5 follow-up). The one case this engine's own event model
  -- batches two mons into a single handler call is battle.started (both
  -- leads entering together) -- every switch-in ability engine in
  -- abilities/engine/ processes that pair in ONE call, and until now all
  -- of them used a fixed player-then-enemy order regardless of Speed.
  --
  -- Real rule: simultaneous switch-in effects resolve FASTEST first. Every
  -- switch-in ability engine in this mod applies its own effect by
  -- unconditionally overwriting shared field state (weather, terrain) --
  -- so whichever one applies SECOND is the one left standing afterward,
  -- meaning the SLOWER of the two Pokemon's own trigger is what actually
  -- persists on a speed mismatch. This function returns the two mons in
  -- that fastest-first APPLICATION order; the second one returned is the
  -- one a caller should expect to "win" any exclusive, overwrite-shaped
  -- state.
  --
  -- Deliberately passes trickRoom=false unconditionally rather than
  -- reading battle.trickRoomActive: Trick Room (combat/trick_room.lua,
  -- a real, already-working system -- see this file's own header)
  -- reorders MOVE speed only, confirmed real-game behavior, and never
  -- touches switch-in/ability activation order, so this stays correct
  -- regardless of whether Trick Room happens to be up. Reuses this same
  -- file's own
  -- computeTurnOrder for its already-correct RNG tie-break (a genuine
  -- speed tie is broken by the battle's own roller, never by argument
  -- order) instead of a second, parallel comparator.
  ------------------------------------------------------------------
  mod.exports.orderSwitchInMons = function(battle, monA, monB)
    if not (battle and monA and monB) then return monA, monB end
    local actors = {
      { id = 1, priority = 0, speed = battle:effectiveSpeed(monA) },
      { id = 2, priority = 0, speed = battle:effectiveSpeed(monB) },
    }
    local ordered = computeTurnOrder(actors, { trickRoom = false, roller = battle:roller() })
    if ordered[1].id == 1 then return monA, monB end
    return monB, monA
  end

  ------------------------------------------------------------------
  -- mod.exports.orderActiveBattlers(battle, battlers) -> orderedBattlers
  -- The real N-way generalization of orderSwitchInMons above, explicit
  -- user request (2026-08-28): the fixed player-then-enemy switch-in
  -- ordering pattern every switch-in ability engine in this mod used
  -- (`local first, second = battle.player, battle.enemy; if order then
  -- ... end`) only ever covered exactly two simultaneous switch-ins --
  -- real Showdown doubles/triples resolves a whole LEAD of 4-6
  -- simultaneously-entering Pokemon in fastest-first application order,
  -- same rule, just more than two actors. Reuses computeTurnOrder
  -- directly (already asymmetric-ready by construction, this file's own
  -- header) rather than a parallel N-way comparator -- same fastest-
  -- first APPLICATION order convention orderSwitchInMons already
  -- established (the LAST battler returned is the one that "wins" any
  -- exclusive, overwrite-shaped shared state, e.g. weather/terrain).
  ------------------------------------------------------------------
  mod.exports.orderActiveBattlers = function(battle, battlers)
    if not (battle and type(battlers) == "table") then return battlers or {} end
    local actors, byId = {}, {}
    for i, mon in ipairs(battlers) do
      if mon then
        local actor = { id = i, priority = 0, speed = battle:effectiveSpeed(mon) }
        actors[#actors + 1] = actor
        byId[i] = mon
      end
    end
    local ordered = computeTurnOrder(actors, { trickRoom = false, roller = battle:roller() })
    local result = {}
    for i, entry in ipairs(ordered) do
      result[i] = byId[entry.id]
    end
    return result
  end

  ------------------------------------------------------------------
  -- mod.exports.resolveTurnActions(battle, actingBattlers) -- the real
  -- multi-battler integration seam MULTI_BATTLE_HOOKS.md specs and this
  -- was, until now, "not yet built." A caller (a multi-battler combat
  -- scene) hands us battler identity ONLY -- who's acting, on what
  -- target, with what move -- and we derive priority/Speed/Trick-Room/
  -- RNG order ourselves and drive battle:useMove(...) directly, per
  -- battler, in our own correctly-derived order. This deliberately never
  -- touches battle:takeTurn/runTurn (confirmed unexported, unwrappable,
  -- hard-coded to battle.player/battle.enemy) -- useMove itself is
  -- confirmed generic over attacker/defender (Battle.lua:1337 reads
  -- self:findMove(attacker,...)/self:volatile(attacker)/
  -- self:sideOf(attacker), never battle.player/battle.enemy directly),
  -- so any battler this caller controls flows through the real pipeline
  -- (STAB/Tera/Protect/Max Guard/every registerDamageModifier) exactly
  -- like today's player-vs-enemy fights, with zero new wiring needed on
  -- the damage side.
  --
  -- actingBattlers: a flat list, any length, either side --
  --   { { mon = <real mon table>, move = <moveId>, target = <real mon> },
  --     ... }
  -- `target` is the single chosen mon as of QUEUE time. If an earlier
  -- action this turn faints it, THIS function redirects/fails that action
  -- itself (see the ROUND 26 note below) -- the caller never has to
  -- pre-check aliveness, exactly the mid-turn knowledge update
  -- MULTI_BATTLE_HOOKS.md's own contract puts on this side of the seam.
  --
  -- SPEED, deliberately NOT read via battle:effectiveSpeed(mon): that
  -- method computes self.stages[self:sideOf(mon)] (Battle.lua:845-848),
  -- and sideOf is a hard binary -- `(mon == self.player) and "player" or
  -- "enemy"` (Battle.lua:434-436) -- so every battler that isn't
  -- literally battle.player or battle.enemy would silently share ONE
  -- stage bucket with whichever side it falls through to, corrupting
  -- stat-stage boosts across unrelated battlers the instant a real
  -- (3+ total battlers) format is used. Confirmed by direct read, not
  -- assumed -- this is exactly the class of gap MULTI_BATTLE_HOOKS.md's
  -- own "no real N-way sideOf" section warns about, one level deeper
  -- than the event-tagging case that doc calls out by name. Speed here
  -- instead composes battle:battleStat(mon,"speed") (genuinely per-mon,
  -- confirmed safe -- Battle.lua:762-764's only mon-identity check is a
  -- `mon == self.player` badge-boost gate, which is real Gen 2 behavior:
  -- badges only ever boost the human player's own team, correct for any
  -- battler either way) against g9-battle-engine's OWN per-mon
  -- stage store (mod.exports.ShowdownPrimitives.stageOf(mon, "spe"),
  -- combat/showdown_primitives.lua's mon.volatile.boosts table -- built
  -- for exactly this reason), through the same Damage.applyStage/
  -- Battle.statusPenaltyFor (paralysis halving) native's own
  -- effectiveSpeed composes, just keyed per-mon instead of per-side.
  ------------------------------------------------------------------
  local function effectiveSpeedFor(battle, mon)
    local Primitives = mod.exports.ShowdownPrimitives
    local raw = battle:battleStat(mon, "speed")
    local stage = Primitives and Primitives.stageOf(mon, "spe") or 0
    -- Both are Gen-2 modules (nil on Gen 1); the identity/native answer is
    -- the faithful fallback there, matching native Gen-1 effective speed.
    local boosted = Damage and Damage.applyStage(raw, stage) or raw
    return Battle and Battle.statusPenaltyFor(battle.data, mon, "speed", boosted) or boosted
  end

  ------------------------------------------------------------------
  -- ROUND 26 (2026-09-10): mid-turn faint redirection for SINGLE-TARGET
  -- actions. Two actions in one multi-battler turn can name the SAME
  -- target, and whichever resolves first can faint it before the later
  -- one is delivered -- which, before this, left the later action applying
  -- its move to a 0-HP corpse: a second attack landing on an already-
  -- fainted mon, or Heal Pulse "reviving" it just to have it re-faint.
  -- The real rule (the user's own explicit spec) is decided by the fainted
  -- target's SIDE at resolution time:
  --   * an ENEMY-directed move still has legal recipients, so it redirects
  --     to a random live adjacent foe (combat/move_targeting.lua's own
  --     pickAdjacentEnemy), and fails outright when none is left standing;
  --   * an ALLY-directed move (Heal Pulse aimed at an ally, plus the
  --     inherently ally-only Helping Hand / Aromatic Mist / Acupressure)
  --     has no alternate recipient at all -- it simply FAILS, spending its
  --     PP and announcing itself exactly like any other failed move, and
  --     never touching the fainted ally.
  -- Spread moves are deliberately untouched: resolveMoveTargets already
  -- re-expands them over the LIVE roster just below, which is the same
  -- redirection for free. This path only ever runs for a single-target
  -- action whose chosen target was alive when queued and is not anymore.
  ------------------------------------------------------------------

  local function findMoveSlot(mon, moveId)
    if not (mon and mon.moves) then return nil end
    for _, ms in ipairs(mon.moves) do
      if ms and ms.id == moveId then return ms end
    end
    return nil
  end

  -- The move was chosen and used, but has no valid recipient left: spend
  -- its PP, announce "X used Y!" (the same kind="move" event native
  -- useMove emits, kept as battle.moveEvent), mark it missed so the screen
  -- plays no attack animation, then the engine's own failuretext line.
  -- Mirrors Battle:useMove's own failed-move tail (Battle.lua:1470-1478,
  -- :1656-1660): the PP is charged because the move WAS used, and the
  -- announcement is kept so the player sees "used Heal Pulse!" followed by
  -- "But it failed!" rather than the action silently vanishing.
  failAction = function(battle, caster, moveId, failText)
    local moveSlot = findMoveSlot(caster, moveId)
    if moveSlot and (moveSlot.pp or 0) > 0 then
      moveSlot.pp = moveSlot.pp - 1
    end
    local def = battle.moveDef and battle:moveDef(moveId)
    local name = battle.monName and battle:monName(caster)
    if battle.emit then
      battle.moveEvent = battle:emit({ kind = "move",
        side = battle.sideOf and battle:sideOf(caster),
        move = moveId,
        text = Strings("%s\nused %s!", (name or "?"), ((def and def.name) or moveId)) })
      if battle.markMissed then battle:markMissed() end
      -- failText (round 100): a rule-specific refusal line from
      -- combat/move_usability.lua ("X is locked into Y!", "X can't use Y
      -- while holding the Assault Vest!"). Native's own generic tail when
      -- the caller has no specific text, exactly as before.
      battle:emit({ kind = "message", text = failText or Strings("But it failed!") })
    end
  end

  -- ROUND 107: Gen 2's own can-this-mon-act gauntlet. Native gen2/Battle.lua
  -- runs Battle:canAct (-> checkTurn) once per action and it is the ONLY
  -- place that consumes a Gen 2 `vol.flinched`, a `vol.recharge`, the sleep/
  -- freeze/paralysis arms, confusion's self-hit and attract. A replacement
  -- battle scene drives its own loop and calls resolveTurnActions instead of
  -- native runTurn, so none of that ever ran and a flinched/paralyzed/recharging
  -- Gen 2 mon acted anyway. Called here exactly ONCE per action (never per
  -- spread target -- checkTurn consumes the flag, so a second call for the
  -- same action would let the follow-up target through). checkTurn emits its
  -- own "X flinched!"/"X must recharge!" line, so a spent turn resolves to
  -- nothing and spends no PP. Returns true when the engine has no canAct.
  local function actorCanAct(battle, mon, moveId)
    if type(battle.canAct) ~= "function" then return true end
    local ok, can = pcall(battle.canAct, battle, mon, moveId)
    if not ok then return true end
    return can ~= false
  end

  -- resolveSingleTarget(battle, caster, moveId, chosen) -> targets, failed
  -- targets is the list to deliver to (empty when nothing is left); failed
  -- is true when the move has no valid recipient at all and must announce
  -- its failure instead. A chosen target still standing resolves exactly as
  -- it did before this round.
  local function resolveSingleTarget(battle, caster, moveId, chosen)
    if not chosen then return {}, false end
    if (chosen.hp or 0) > 0 then return { chosen }, false end
    local targeting = mod.exports
    if targeting.isAllyDirectedMove and targeting.isAllyDirectedMove(moveId) then
      return {}, true
    end
    if battle.sideOf and battle:sideOf(chosen) == battle:sideOf(caster) then
      return {}, true
    end
    local redirect = targeting.pickAdjacentEnemy
      and targeting.pickAdjacentEnemy(battle, caster, moveId)
    if redirect then return { redirect }, false end
    return {}, true
  end

  -- A self-switch effect (combat/switch_primitives.lua's own
  -- requestSwitch, U-turn/Volt Switch/Baton Pass-shaped) sets the real,
  -- public battle.forcedSwitch field -- the SAME one native runTurn
  -- already checks (after a faint, or a Roar/Whirlwind drag-out) to end a
  -- round early and skip residual. Honored here too, after each action:
  -- whoever hasn't acted yet this round simply doesn't, matching vanilla's
  -- own real behavior for the identical case (see switch_primitives.lua's
  -- own header for why "resume the rest of this same round afterward"
  -- isn't achievable from mod code at all -- runTurn is an unexported
  -- local closure no mod can reach into).
  mod.exports.resolveTurnActions = function(battle, actingBattlers)
    -- A resume call (mod.exports.resumeAfterPivot below) passes NO
    -- actingBattlers: it re-enters with the order list a pivot self-switch
    -- paused on, so the guard also accepts a battle carrying that pause.
    local pivotResume = battle and battle.__g9PivotPause
    if not (battle and (type(actingBattlers) == "table" or pivotResume)) then return end

    ------------------------------------------------------------------
    -- SCENE-DRIVEN TURN BOUNDARY (round sixty-six, 2026-09-12) -- the
    -- fix for the reported "protection moves' fail chance per success
    -- isn't working".
    --
    -- Native's own turn loop -- gen2/Battle.lua's unexported `runTurn` --
    -- is the ONLY thing that ever advanced `battle.turn`, with a single
    -- `self.turn = self.turn + 1` at its top (:4737, before it emits
    -- battle.turn_started at :4808). A replacement battle scene
    -- (g9-Battle-Scene) drives its OWN turn loop and calls THIS function
    -- for resolution instead of ever running native runTurn, so in every
    -- scene-driven battle `battle.turn` stayed at the value native's
    -- constructor gave it (`self.turn = 0`, :294) for the whole battle.
    --
    -- That is exactly what broke combat/modern_combat_protect.lua's
    -- shared Protect-family stall chain. Its `consecutive` test --
    -- `user.protectChainTurn == turn - 1`, where `turn = battle.turn` --
    -- can only ever be true if the number actually advances; with it
    -- pinned at 0 forever, `consecutive` was always false, the chain's
    -- denominator `x` was always 1, and `battle:roller()(1) == 0` always
    -- succeeded: Protect/Detect/Max Guard never decayed and never failed,
    -- no matter how many turns in a row they were used. (The same
    -- pinned-at-0 value also made Part B/Part D's per-(turn, attacker)
    -- contact-rider de-dup key collapse to a single "0" bucket, so a
    -- shield's rider could fire at most once per battle.)
    --
    -- This function is the one place the boundary can be restored from
    -- inside the engine: the scene calls resolveTurnActions exactly once
    -- per turn (g9-Battle-Scene's Screen:advanceResolving), so
    -- incrementing here reproduces native's one-increment-per-round
    -- semantics for scene-driven battles. Native itself NEVER calls this
    -- function -- its own runTurn owns that increment -- so there is no
    -- double-count and a normal (non-scene) battle's battle.turn is
    -- completely untouched by this line.
    ------------------------------------------------------------------
    -- (The increment itself now lives in the fresh-turn branch below, so a
    -- PIVOT PAUSE resume -- which is the SAME round -- cannot double-count.)

    -- Round sixty-seven: whether THIS round was ended early by a forced
    -- switch (Roar/Whirlwind/self-switch). Native runTurn skips its whole
    -- residual block on such a round (Battle.lua:5004-5010) while still
    -- emitting battle.turn_ended via closeTurn, so the end-of-turn wire at
    -- the bottom of this function mirrors that: no residuals, event still
    -- closes the round.
    local forcedSwitchHappened = false
    -- PIVOT PAUSE resume (see the block at the loop's forcedSwitch break and
    -- mod.exports.resumeAfterPivot): restore the exact order list the round
    -- stopped on and point every not-yet-acted actor whose chosen target was
    -- the mon that left at the mon the scene sent in.  Skipping the turn
    -- increment below is the whole reason this branch exists -- it is the
    -- SAME round continuing, not a new one.
    local chosen, ordered, orderIndex
    local pivotOutgoing = nil
    if pivotResume then
      ordered = pivotResume.ordered
      orderIndex = pivotResume.orderIndex
      chosen = pivotResume.chosen
      battle.__g9PivotPause = nil
      battle.__g9ChosenMoves = chosen
      battle.__g9OrderedActors = ordered
      if pivotResume.incoming then
        for i = orderIndex + 1, #ordered do
          local pendingEntry = ordered[i] and ordered[i].id
          if pendingEntry and pendingEntry.target == pivotResume.outgoing then
            pendingEntry.target = pivotResume.incoming
          end
        end
      end
      battle.forcedSwitch = nil
      battle.__g9PendingSelfSwitch = nil
    else

    battle.turn = (battle.turn or 0) + 1

    -- PHASE 5: publish every actor's chosen move for the whole turn, the
    -- `battle.__g9ChosenMoves[mon] = moveId` map mod.exports.chosenMoveOf
    -- reads. Built from the caller's own `actingBattlers` contract (each
    -- entry already carries `.move`), so a sub-effect can answer "did the
    -- target choose a damaging move?" without guessing. Cleared per-actor
    -- as each action resolves below, which is exactly Showdown's "already
    -- acted this turn -> willMove returns null" semantics.
    chosen = {}
    for _, entry in ipairs(actingBattlers) do
      if entry.mon and entry.move then chosen[entry.mon] = entry.move end
    end
    battle.__g9ChosenMoves = chosen

    local actors = {}
    for i, entry in ipairs(actingBattlers) do
      if entry.mon and (entry.mon.hp or 0) > 0 and entry.move then
        actors[#actors + 1] = {
          id = entry, -- the battler entry itself, not an index -- identity
          priority = battle:movePriority(entry.move, entry.mon),
          speed = effectiveSpeedFor(battle, entry.mon),
        }
      end
    end
    ordered = computeTurnOrder(actors, {
      trickRoom = battle.trickRoomActive == true, -- combat/trick_room.lua sets this for real; see this file's own header
      roller = battle:roller(),
    })
    -- PHASE 5: keep the computed order list and a live cursor reachable so
    -- a pending actor can be moved (After You -> next, Quash -> last) while
    -- the loop is still running. `ordered` is a plain array of actor
    -- records; moving a not-yet-visited element forward/back cannot
    -- disturb the elements already consumed (indices <= orderIndex), and
    -- the loop still visits every actor exactly once. An index-based
    -- `while` rather than `for ... ipairs` because reordering the array
    -- mid-iteration under `ipairs` is undefined; the two `break`s in the
    -- body (forced switch) exit this `while` exactly as before.
    orderIndex = 0
    battle.__g9OrderedActors = ordered
    end
    while orderIndex < #ordered do
      orderIndex = orderIndex + 1
      battle.__g9OrderIndex = orderIndex
      local actor = ordered[orderIndex]
      local entry = actor.id
      -- Mid-turn faint check: an earlier action in this same order may
      -- have dropped the actor or its own chosen target below 0 HP.
      -- Skipping here (rather than trusting the order computed before
      -- any of this turn's damage landed) is what MULTI_BATTLE_HOOKS.md's
      -- own contract promises -- "that knowledge updates who still
      -- counts as a valid remaining actor before we decide who's next."
      -- ROUND 100: a move the ENGINE's own rules forbid RIGHT NOW -- a Choice
      -- lock ("only the first move selected can be used") or an item move-type
      -- ban (Assault Vest's no-Status rule) -- is refused here as well as at
      -- the scene's move menu. The menu is the player-facing half (combat/
      -- move_usability.lua); this is the resolution backstop for a scripted or
      -- AI caller that queued the move without asking. The move is still
      -- announced and spends its PP through failAction, with the SAME reason
      -- text the menu would have shown. Condition gates (Fake Out/Last Resort)
      -- are deliberately NOT re-checked here: they own their own fail gates
      -- at the native useMove seam, which is the correct place for them.
      local moveUsability = mod.exports.moveUsability
      local blocked = moveUsability and moveUsability(battle, entry.mon, entry.move)
      -- ROUND 107: run Gen 2's pre-action gauntlet (recharge/sleep/freeze/
      -- flinch/confusion/attract/paralysis) exactly once per action. A
      -- spent turn emits its own message inside canAct and does nothing more.
      local canActNow = (entry.mon.hp or 0) > 0
        and actorCanAct(battle, entry.mon, entry.move)
      if (entry.mon.hp or 0) > 0 and canActNow == false then
        -- turn spent by status/recharge/flinch: no move, no PP, no announce
      elseif (entry.mon.hp or 0) > 0 and blocked
          and (blocked.flag == "choice" or blocked.flag == "banned"
            or blocked.flag == "healblock") then
        failAction(battle, entry.mon, entry.move, blocked.reason)
      elseif (entry.mon.hp or 0) > 0 and entry.fail then
        -- The battle scene already knows this action has no legal recipient
        -- from its slot -- a triple-battle wing whose only live foes are
        -- non-adjacent, so the scene's own positional adjacency offered no
        -- candidate (battle_screen.lua's updateMoveSelect).  The move is used
        -- and fails, announced and PP-spent, at its own place in the turn
        -- order; every OTHER actor this turn still resolves.  The scene used
        -- to abandon the whole selection on this case, so the two allied
        -- slots never got to choose.
        failAction(battle, entry.mon, entry.move)
      elseif (entry.mon.hp or 0) > 0 then
        -- Spread moves (all-opponents/all-other-pokemon: LEER, Muddy
        -- Water, Earthquake, Surf, ...) expand to EVERY adjacent target
        -- here, not the single placeholder target the caller queued --
        -- that is the entire point of combat/move_targeting.lua's
        -- resolveMoveTargets, and the reason a battle scene can queue one
        -- placeholder target for an AoE move and be correct. Each real
        -- target gets its own useMove; the count rides to the damage
        -- formula on a transient battle.__spreadTargetCount field
        -- (consumed by modern_combat.lua's spread_reduction modifier),
        -- and a mid-turn faint of the caster or a later target just skips
        -- whatever remains, lazily, same as single-target actions.
        local targets
        local failed = false
        if mod.exports.isSpreadMove and mod.exports.isSpreadMove(entry.move) then
          targets = mod.exports.resolveMoveTargets(battle, entry.mon, entry.move, entry.target)
        else
          -- Single-target: redirect to a live adjacent foe (or fail, for
          -- an ally-directed move) when this action's chosen target fainted
          -- to an earlier action this turn -- see resolveSingleTarget above.
          targets, failed = resolveSingleTarget(battle, entry.mon, entry.move, entry.target)
        end
        local live = {}
        for _, t in ipairs(targets) do
          if t and (t.hp or 0) > 0 then live[#live + 1] = t end
        end
        if #live == 0 then
          -- No valid recipient: the move is used (announced, PP spent) and
          -- fails.  For a single-target action that is a chosen target which
          -- fainted with no live adjacent foe to redirect to; for a SPREAD
          -- action it is a move that expanded to zero live targets (Surf in
          -- a triple with no adjacent opponent).  The spread case used to
          -- resolve to NOTHING here -- no announce, no PP, no line -- because
          -- the guard was `#live == 0 and failed` and the spread path never
          -- sets `failed`.  That is the reported "spread moves can't be used
          -- again, the mon just doesn't act".
          failAction(battle, entry.mon, entry.move)
        elseif #live > 0 then
          if #live > 1 then battle.__spreadTargetCount = #live end
          -- Native Battle:useMove is single-target: it re-runs the full
          -- per-use pipeline (PP decrement, the kind="move" announce
          -- event the screen animates off, and the move effect) once per
          -- call. A spread action expanding to N targets must therefore
          -- cost exactly ONE use, not N -- this is where LEER used to
          -- fire its animation twice and burn 2 PP per action in every
          -- multi-battler battle. Two re-normalizations:
          --   * PP: locate the move's slot on the caster, remember its
          --     value after the first call, top it back to 1 before each
          --     later call (so native's no-PP bail never trips on the
          --     last-PP case), then restore the first-call value after
          --     the loop -- net cost is always exactly 1 PP.
          --   * announce: drain the event queue and keep only the FIRST
          --     kind="move" event (which already carries the user's "used
          --     %s!" text and the first target's scene stamp). The
          --     per-target effect messages (each enemy's "defense fell!")
          --     are separate kind="message" events and survive unchanged
          --     -- one per target is exactly right for a spread move.
          --     The dedup must be scoped to THIS spread action's own
          --     events only: battle.events already holds every earlier
          --     actor's events from this same resolveTurnActions pass
          --     (tail-whip.lua reported a boss's Tail Whip announcing
          --     nothing while its targets' "defense fell!" lines still
          --     showed -- the drain had been keeping the FIRST move event
          --     in the whole queue, i.e. some earlier actor's "used X!",
          --     and silently dropping the spread caster's own). priorEvents
          --     is the queue length before this action's useMove loop, so
          --     events at or below it pass through untouched and only the
          --     NEW events are deduped -- the caster's own announce
          --     survives no matter how many actors already went this turn.
          local moveSlot
          if entry.mon.moves then
            for _, ms in ipairs(entry.mon.moves) do
              if ms and ms.id == entry.move then moveSlot = ms break end
            end
          end
          local priorEvents = battle.events and #battle.events or 0
          local ppAfterFirst
          local forced = false
          for i, t in ipairs(live) do
            if (entry.mon.hp or 0) > 0 then
              if i > 1 and moveSlot and (moveSlot.pp or 0) < 1 then
                moveSlot.pp = 1
              end
              battle:useMove(entry.mon, t, entry.move)
              if i == 1 and moveSlot then ppAfterFirst = moveSlot.pp end
              if battle.forcedSwitch then
                forced = true
                break
              end
            end
          end
          if moveSlot and ppAfterFirst ~= nil then
            moveSlot.pp = ppAfterFirst
          end
          if #live > 1 and battle.takeEvents and battle.emit then
            local allEvents = battle:takeEvents() or {}
            local keptMove
            for i, ev in ipairs(allEvents) do
              if i <= priorEvents then
                battle:emit(ev)
              elseif ev and ev.kind == "move" then
                if not keptMove then
                  keptMove = true
                  battle:emit(ev)
                end
              else
                battle:emit(ev)
              end
            end
          end
          battle.__spreadTargetCount = nil
          if forced then
            forcedSwitchHappened = true
            battle.forcedSwitch = nil
            -- The mon leaving the field.  switch_primitives.lua's
            -- requestSwitch parks it (battle.__g9PendingSelfSwitch) so a
            -- pivot (U-turn) and a drag (Dragon Tail) reach here alike;
            -- the actor is only the fallback.
            pivotOutgoing = (battle.__g9PendingSelfSwitch
              and battle.__g9PendingSelfSwitch.mon) or entry.mon
            break
          end
        end
      end
      -- PHASE 5: this actor has acted, so it is no longer "about to move"
      -- (Showdown: a moved mon is spliced out of the queue, willMove nil).
      -- Runs for every actor -- including a fainted one skipped above --
      -- except the `break`ing forced-switch path, where the trailing map
      -- teardown below covers it.
      if battle.__g9ChosenMoves then battle.__g9ChosenMoves[entry.mon] = nil end
    end
    -- PIVOT PAUSE: a forced switch the SCENE owns (the player's own bench
    -- pick).  g9-battle-engine cannot open a party menu, so when the paired
    -- scene advertises `battle.__g9SceneHandlesPivotSwitch` the round stops
    -- here -- WITHOUT tearing down the order and WITHOUT running the
    -- end-of-turn.  The scene performs the switch, then calls
    -- mod.exports.resumeAfterPivot, which re-enters this function, repoints
    -- the not-yet-acted entries at the mon that came in, and finishes the
    -- round (end-of-turn included).  A scene that does not advertise the
    -- flag keeps the old behaviour exactly: the round ends at the switch.
    --
    -- This is what makes the timing work for the player: Teleport (-6) acts
    -- last, so nothing is left pending and the switch-in is exposed only to
    -- entry effects; U-turn acting early leaves the opponent's move pending,
    -- and on resume it follows the SLOT to the switch-in.
    if pivotOutgoing and battle.__g9SceneHandlesPivotSwitch then
      if chosen then chosen[pivotOutgoing] = nil end
      battle.__g9PivotPause = {
        ordered = ordered, orderIndex = orderIndex, chosen = chosen,
        -- Residual deliberately NOT skipped on the resume: the leftover
        -- actors resolve first, and the end-of-turn weather/leftovers then
        -- tick the field as it stands -- i.e. the mon that actually came in.
        forcedSwitchHappened = false,
        outgoing = pivotOutgoing,
      }
      battle.__g9PendingSelfSwitch = nil
      if battle.emit then
        battle:emit({ kind = "pivot-switch", mon = pivotOutgoing,
          side = battle.sideOf and battle:sideOf(pivotOutgoing) or "player" })
      end
      return
    end
    -- The order list/cursor/chosen map are per-turn scratch; free them so
    -- a later resolveTurnActions on the same battle starts clean.
    battle.__g9OrderIndex = nil
    battle.__g9OrderedActors = nil
    battle.__g9ChosenMoves = nil

    ------------------------------------------------------------------
    -- END-OF-TURN WIRE (round sixty-seven, 2026-09-12) -- see
    -- combat/turn_residuals.lua's own header for the full evidence. The
    -- scene calls THIS function once per turn (g9-Battle-Scene's
    -- Screen:advanceResolving) and never native runTurn, so this is the one
    -- place the entire end-of-turn phase can be restored from inside the
    -- engine, exactly as the turn increment above restores native's own
    -- once-per-turn semantics.
    --
    -- Order mirrors native runTurn (Battle.lua:5001-5036): announce faints
    -- first (resolveFaints), then -- unless a forced switch ended the round
    -- early -- the residual sweep, then announce faints AGAIN (native's
    -- second resolveFaints, for anything a residual just dropped), then close
    -- the round with battle.turn_ended. announceFaints is idempotent
    -- (per-mon keyed in turn_residuals.lua), so its two calls cannot double-
    -- announce. Native itself NEVER calls this function -- its own runTurn
    -- owns the whole phase -- so a normal (non-scene) battle is completely
    -- untouched here; no double residual tick anywhere.
    ------------------------------------------------------------------
    local announceFaints = mod.exports.announceFaints
    local runEndOfTurn = mod.exports.runEndOfTurn
    if type(announceFaints) == "function" then pcall(announceFaints, battle) end
    if not forcedSwitchHappened and type(runEndOfTurn) == "function" then
      pcall(runEndOfTurn, battle)
      if type(announceFaints) == "function" then pcall(announceFaints, battle) end
    end

    -- battle.turn_ended: the closure native closeTurn emits for whichever of
    -- runTurn's exits was taken. Runtime.wants is native's own gate (only
    -- deliver when something listens); it is guarded rather than assumed so
    -- an engine without it still closes the round. `turn` rides along exactly
    -- as native sends it.
    if Runtime and type(Runtime.emit) == "function"
        and (type(Runtime.wants) ~= "function" or Runtime.wants("battle.turn_ended")) then
      Runtime.emit("battle.turn_ended", { battle = battle, turn = battle.turn })
    end
  end

  -- Resume a round a pivot self-switch paused (see the PIVOT PAUSE block in
  -- resolveTurnActions).  `incoming` is the mon the scene sent in: every
  -- actor that had not acted yet this round and whose chosen target was the
  -- mon that left is repointed at it, the rest of the round resolves, and the
  -- end-of-turn runs -- all through the SAME resolver, re-entered with the
  -- stored order list.  Returns false and does nothing when no pause is
  -- pending (so a caller can always call it defensively).
  mod.exports.resumeAfterPivot = function(battle, incoming, outgoing)
    local pause = battle and battle.__g9PivotPause
    if not pause then return false end
    pause.incoming = incoming or pause.incoming
    pause.outgoing = pause.outgoing or outgoing
    mod.exports.resolveTurnActions(battle, nil)
    return true
  end

  ------------------------------------------------------------------
  -- Today's one real caller: the native battle.turn_order hook
  -- (gen2/Battle.lua:4085-4098), which decides the whole turn's order
  -- once, before either action runs -- the only extension point this
  -- 2-battler engine currently exposes (see MULTI_BATTLE_HOOKS.md for
  -- why a real mid-turn re-sort needs more than this and doesn't exist
  -- yet). Replaces the native comparator with the SAME computeTurnOrder
  -- any future multi-battler caller will use, so the 2-actor case today
  -- and any future N-actor case are provably one algorithm, not two.
  ------------------------------------------------------------------
  -- CONFIRMED CRASH, this session (2026-08-27): "battle.turn_order" is
  -- NOT a Gen-2-exclusive hook name -- Gen 1's own BattleState:resolveTurn
  -- (src/battle/BattleState.lua:2736-2739) calls the identical hook name,
  -- and Runtime.wantsHook only checks whether ANYTHING is registered for
  -- that name, not which engine registered it -- so this wrap fires for
  -- Gen 1 battles too the instant it's installed. Gen 1's own call passes
  -- a completely different ctx shape (`{ rng = self.rng }`, confirmed by
  -- direct read -- no .battle field at all), so `local battle = ctx.battle`
  -- silently evaluated to nil and every following battle: call crashed
  -- (attempt to index a nil value) on the first turn of any Gen 1 battle.
  -- Gen 1 does not get Gen-9-accurate turn order from this file at all
  -- yet (that's real, separate work, not yet built) -- this guard only
  -- stops the crash by falling through to Gen 1's own native comparator
  -- (nextFn) whenever ctx doesn't look like Gen 2's own shape.
  mod.hooks:wrap("battle.turn_order",
    function(nextFn, playerBattler, playerMoveDef, enemyBattler, enemyMoveDef, ctx)
      local battle = ctx and ctx.battle
      if not battle then
        return nextFn(playerBattler, playerMoveDef, enemyBattler, enemyMoveDef, ctx)
      end
      local actors = {
        { id = "player", priority = battle:movePriority(ctx.playerMove, battle.player),
          speed = battle:effectiveSpeed(battle.player) },
        { id = "enemy", priority = battle:movePriority(ctx.enemyMove, battle.enemy),
          speed = battle:effectiveSpeed(battle.enemy) },
      }
      local ordered = computeTurnOrder(actors, {
        trickRoom = battle.trickRoomActive == true, -- combat/trick_room.lua sets this for real; see this file's own header
        roller = battle:roller(),
      })
      return ordered[1].id == "player"
    end, 0)

  mod.log:info("galar_gmax_dex: turn_order installed (Gen 9 priority/Trick-Room-aware/random-tie comparator)")
end
