-- Modern moves: the 833-move roster as engine `moves` records, and the
-- optional widening of species learnsets onto the part of that roster this
-- engine can actually execute.
--
-- Two jobs, and the split between them is the whole safety argument:
--
--   REGISTRATION is unconditional and covers every move.  A move nothing can
--   learn is inert, so registering all of them costs a player nothing -- and
--   it is what makes the MOVES option safe to turn off again.
--   src/core/SaveData.lua strips any move id from a saved party that
--   data.moves does not hold, so a roster that appears only while the option
--   is on would delete moves off a player's team the moment they turned it
--   back off.  The ids are always there instead.
--
--   LEARNSET WIDENING is what the MOVES option gates, and it is filtered:
--   only a move whose `effectModeled` is true may ever reach a learnset.  A
--   blocked move is registered carrying the generation's most inert effect
--   (plain damage) and `effectModeled = false`, which is a PLACEHOLDER, not
--   an implementation -- so the filter below is the only thing standing
--   between that placeholder and a player's party.  Do not add a second path
--   into a learnset that does not go through allowedMove().
--
-- Which effect each move gets, and which ones are blocked, is decided at
-- build time by tools/build_moves.py -- see that file's module docstring for
-- the two-pass curation and why PokeAPI's own metadata cannot be trusted on
-- its own.  Nothing here re-derives it.
--
-- ONE PLACE WHERE "INERT" WAS NOT LITERALLY TRUE, and it is Gen 2 only:
-- Gold's Metronome builds its pool by walking data.moves for every record
-- with a `power` field (src/battle/gen2/Battle.lua:679-688, Battle:moveOrder),
-- so a registered move can be CALLED without anything having learnt it -- and
-- every record this mod registers has a power, a status move carrying 0.  Red's
-- Metronome does not walk anything: src/battle/MoveEffects.lua:701-710 rolls
-- ctx.data.constants.moveOrder, the ROM's own ordered list, which this mod
-- never writes to.  So the reach is Gold's alone, and a rolled placeholder
-- would resolve as plain damage with the move's real type, power and accuracy.
--
-- installMetronomeFilter below closes that: it wraps Gold's own pool builder
-- and drops the records carrying `effectModeled = false`, leaving Metronome
-- rolling the cart's roster plus the curated part of this one.  Registration
-- stays unconditional, so the SaveData argument above is untouched.

local M = {}

local LEARNSET_INDEX = "data/moves/generated/learnsets/index.lua"
-- must match build_moves.py's write_shards() zero-padding: the index stores a
-- bare shard number and the filename has to be reconstructable from it
local SHARD_WIDTH = 3

local function shardPath(number)
  return string.format("data/moves/generated/learnsets/%0" .. SHARD_WIDTH
    .. "d.lua", number)
end

-- Reads and runs one of this mod's generated data files, or nil.  pcalled
-- rather than asserted for the same reason src/api.lua's loader is: a shard
-- that will not load must cost the player the moves in it, never the load.
local function loadDataModule(mod, name)
  local source = mod:read(name)
  if not source then return nil end
  local chunk = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then return nil end
  local ok, result = pcall(chunk)
  if not ok then return nil end
  return result
end
M.loadDataModule = loadDataModule

-- Two move ids are the SAME move when they differ only in separators.  Gold
-- and Red spell the ROM's own names differently in places (DYNAMICPUNCH beside
-- SLUDGE_BOMB), and this mod's own ids drop separators entirely, so comparing
-- the raw strings would register a second Sludge Bomb next to the cart's.
function M.normaliseId(id)
  if type(id) ~= "string" then return nil end
  return (id:upper():gsub("[^A-Z0-9]", ""))
end

-- Every move id the running game already holds, normalised.  registry:each()
-- is the sanctioned walk and reports the engine's own records as well as any
-- mod's; it is pcall-guarded rather than trusted, because a shape change there
-- must cost this mod its collision check, not the load.  An empty answer is
-- the SAFE direction to fail in only for registration order -- claim() below
-- still refuses to overwrite an id that exists.
function M.existingIds(registry)
  local seen = {}
  local ok, result = pcall(function() return registry:each() end)
  if not ok then return seen end
  local ids
  if type(result) == "function" then
    ids = {}
    for id in result do ids[#ids + 1] = id end
  elseif type(result) == "table" then
    ids = result
  else
    return seen
  end
  for _, id in ipairs(ids) do
    local key = M.normaliseId(id)
    -- The ACTUAL id, not `true`.  Callers that only wanted a yes/no still get
    -- a truthy value, and the one that needs to know WHICH spelling the cart
    -- uses can now ask -- see M.install's own translation table and the bug it
    -- exists to close.
    if key and seen[key] == nil then seen[key] = id end
  end
  return seen
end

-- ------------------------------------------------------------- learnset math

-- The merged level-up rows for one species: everything the record already
-- teaches, plus every allowed modern row it does not.  A move already on the
-- record keeps its EXISTING level -- the cart's own progression wins, because
-- widening the roster is not licence to reschedule what a player already had.
--
-- `allowed` is the filter described at the top of this file.  It is passed in
-- rather than closed over so a test can hand this pure function a set of its
-- own and prove the filter is what decides, not the data.
--- `translate` maps this mod's own spelling of a move onto the one the running
--- cart actually registered it under, and it is the whole fix for a bug worth
--- describing because the shape of it is not obvious.
---
--- normaliseId strips punctuation, so this mod's RAPIDSPIN matches the cart's
--- RAPID_SPIN and M.install correctly SKIPS registering over it -- the cart's
--- Rapid Spin is a real implementation with the ROM's own animation and index.
--- But the learnset shards still say RAPIDSPIN, and nothing translated that
--- into the id the game can actually resolve.  A species widened with such a
--- row got a move slot naming a record that does not exist, which the Gen 2
--- mon builder reads as `pp = moveDef and moveDef.pp or 0` -- so the move
--- showed up in the FIGHT menu at 0/0 PP and could never be used.
---
--- Gen 2 only, and not because the code differs: Gold and Silver own 253 moves
--- to Red's 165, and the extra ones are exactly the Gen 2 additions (Rapid
--- Spin, Scary Face, Giga Drain, Metal Claw, ...) that this mod otherwise
--- registers itself.  On Red they collide with nothing, so every id resolves.
function M.mergeRows(existing, additions, allowed, translate)
  local rows, seen = {}, {}
  for _, row in ipairs(existing or {}) do
    if type(row) == "table" and type(row.move) == "string" then
      local level = type(row.level) == "number" and row.level or 1
      if not seen[row.move] then
        seen[row.move] = true
        rows[#rows + 1] = { level = level, move = row.move }
      end
    end
  end
  local added = 0
  for _, row in ipairs(additions or {}) do
    if type(row) == "table" and type(row.move) == "string"
      and allowed[row.move] then
      -- Translated BEFORE the dedup, so a species whose existing rows already
      -- name the cart's spelling does not also gain this mod's spelling of the
      -- same move -- which would be one move listed twice, one of them dead.
      local moveId = (translate and translate[row.move]) or row.move
      if not seen[moveId] then
        seen[moveId] = true
        local level = type(row.level) == "number" and row.level or 1
        rows[#rows + 1] = { level = math.max(1, level), move = moveId }
        added = added + 1
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.move < b.move
  end)
  return rows, added
end

-- ------------------------------------------------- Gold's Metronome pool

-- Drops this mod's placeholders out of a Metronome pool, and hands the pool
-- straight back untouched when it cannot tell what it is looking at.
--
-- `order` is the array Gold built (move ids) and `moves` is the live
-- data.moves it built them from; a record is a placeholder only when it says
-- so itself, because `effectModeled = false` is the ONE thing that separates a
-- placeholder from a move that genuinely is plain damage.  The engine's own
-- records carry no marker at all and are kept, which is the right default: a
-- cart move is a move the engine executes.
--
-- Returns the SAME table when nothing was dropped.  That is not a
-- micro-optimisation but the contract the wrapper below leans on -- it is how
-- a second call tells "already filtered" from "filtered something", so the
-- pool is still built once per battle rather than rebuilt per roll.
function M.filterMoveOrder(order, moves)
  if type(order) ~= "table" or type(moves) ~= "table" then return order end
  local kept, dropped = {}, 0
  for index = 1, #order do
    local id = order[index]
    local record = moves[id]
    if type(record) == "table" and record.effectModeled == false then
      dropped = dropped + 1
    else
      kept[#kept + 1] = id
    end
  end
  if dropped == 0 then return order end
  -- An empty pool is worse than an unfiltered one: Effects.metronomePick
  -- (src/battle/gen2/Effects.lua:490-502) answers nil for a zero-length list
  -- and Gold turns that into "But it failed!" every single time.  If filtering
  -- would take everything, this is not a dataset this filter understands.
  if #kept == 0 then return order end
  return kept, dropped
end

-- The class-level marker.  The class is process-global and this module table
-- is not -- main.lua compiles src/moves.lua per load -- so a second load would
-- otherwise stack a second wrapper on the first.  The class is the only table
-- both loads can see.
local METRONOME_MARKER = "nationalDexMetronomeFiltered"

-- Wraps Gold's pool builder.  Answers ok, reason: false plus a word for why
-- rather than an error, and every refusal that is not simply "this is Red"
-- says so on the log before it returns.
--
-- The class is reached by its REAL name.  A mod's require is NOT redirected on
-- a Gold boot (src/mods/Loader.lua:190-215 only maps Gen 1 names onto Gen 2
-- adapters), so asking for anything less specific would hand back Gen 1's
-- battle and this would patch code Gold never runs.  Nothing here probes for
-- which methods exist to decide where it is: `generation` is handed in.
function M.installMetronomeFilter(generation, log)
  local function warn(...)
    if log and log.warn then log:warn(...) end
  end
  -- Gen 1 rolls the ROM's own ordered list and never sees this mod's roster,
  -- so there is nothing to filter and nothing to say.
  if generation ~= 2 then return false, "gen1" end

  local ok, Battle = pcall(require, "src.battle.gen2.Battle")
  if not ok or type(Battle) ~= "table" then
    warn("Gold's battle class could not be read, so Metronome keeps its "
      .. "unfiltered pool and may roll a placeholder move")
    return false, "require"
  end
  if rawget(Battle, METRONOME_MARKER) then return false, "already" end

  local original = rawget(Battle, "moveOrder")
  if type(original) ~= "function" then
    warn("Gold's battle class has no moveOrder to wrap -- the engine changed "
      .. "shape; Metronome keeps its unfiltered pool")
    return false, "shape"
  end

  local patched = function(self, ...)
    local order = original(self, ...)
    local moves = type(self) == "table" and type(self.data) == "table"
      and self.data.moves or nil
    local filtered = M.filterMoveOrder(order, moves)
    -- Battle:moveOrder memoises into self._moveOrder; overwriting that with
    -- the filtered list is what keeps the cost at one pass per battle instead
    -- of one per Metronome roll.
    if filtered ~= order and type(self) == "table" then
      self._moveOrder = filtered
    end
    return filtered
  end

  Battle.moveOrder = patched

  -- Read back, and read back what the ENGINE will read: an instance resolves
  -- moveOrder through the metatable, so a class table that accepted the write
  -- and still answers with the original would look installed from here and be
  -- absent in a battle.  The probe is behavioural rather than an identity
  -- check for the same reason -- it proves the placeholder is gone from a pool
  -- this filter actually built.
  local probe = setmetatable({ data = { moves = {
    KEPT = { id = "KEPT", power = 40 },
    DROPPED = { id = "DROPPED", power = 40, effectModeled = false },
  } } }, Battle)
  local built = probe.moveOrder and probe:moveOrder() or nil
  local sawKept, sawDropped = false, false
  for _, id in ipairs(type(built) == "table" and built or {}) do
    if id == "KEPT" then sawKept = true end
    if id == "DROPPED" then sawDropped = true end
  end
  if not sawKept or sawDropped then
    Battle.moveOrder = original
    warn("the Metronome pool filter did not take (kept=%s dropped=%s) -- it "
      .. "has been removed and Gold's own pool is back in place",
      tostring(sawKept), tostring(sawDropped))
    return false, "readback"
  end

  Battle[METRONOME_MARKER] = true
  return true, "installed"
end

-- ---------------------------------------------------------------- the driver
--
-- Returned as a MODULE with a __call, not as a bare function, so the pure
-- helpers above (normaliseId, mergeRows, existingIds) are reachable from a
-- test with plain tables -- the same shape src/gen2shape.lua and src/api.lua
-- already use, and for the same reason.

function M.install(mod, payload, generation, widen, display)
  if type(payload) ~= "table" or type(payload.moves) ~= "table" then
    mod.log:error("the move payload is missing or malformed -- reinstall the "
      .. "mod zip; no modern move is registered this boot")
    return
  end

  local registered, skipped, failed, stubbed = 0, 0, 0, 0
  local firstError
  local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then
      failed = failed + 1
      if not firstError then firstError = tostring(err) end
    end
    return ok
  end

  -- ---- Gen 2 stub effects.
  --
  -- Gold implements far more move effects than it REGISTERS: src/battle/gen2/
  -- Battle.lua seeds a `move_effects` record for each effect with a standalone
  -- handler, while the ones steered from inside the damage pipeline -- the
  -- stat tables, hit counts, drain, recoil, flinch, and plain damage itself --
  -- are dispatched on the effect STRING and have no record at all.  A mod's
  -- record referencing one of those ids is an unresolved f.id("move_effects")
  -- and Schemas.crossValidate makes that a hard error, so the ids this mod
  -- uses are registered here first.
  --
  -- THIS ASSERTS SOMETHING ABOUT THE ENGINE, deliberately and out loud: that a
  -- record carrying `kind = "primary"` and neither `run` nor `status` behaves
  -- exactly as no record does.  Gold reads the record at exactly two points in
  -- useMove -- once for `record.run` (nil here, so the move falls through to
  -- the damage path) and once for `record.status` on a primary and a secondary
  -- (nil here, so nothing is applied) -- and every string comparison against
  -- def.effect elsewhere reads the move, never the record.  So the stub is a
  -- fall-through and the hardcoded implementation keeps running underneath it.
  -- If a future Gold build starts dispatching on the record's presence, these
  -- stubs stop being no-ops and this block is the first place to look.
  if generation == 2 and type(payload.stubEffects) == "table" then
    for _, id in ipairs(payload.stubEffects) do
      if mod.content.move_effects:get(id) == nil then
        if safe(function()
          mod.content.move_effects:register(id, { kind = "primary" })
        end) then
          stubbed = stubbed + 1
        end
      end
    end
  end

  -- ---- the roster.
  --
  -- A move the running cart already describes is left ALONE, not overridden:
  -- the cart's Tackle is a real implementation with the ROM's own animation
  -- and index, and replacing it with a PokeAPI-derived record would be this
  -- mod rewriting the base game to say what it already says.  Red ships 165
  -- of these and Gold 251, which is also why the check is a runtime one
  -- against the live registry rather than a list baked in at build time.
  local existing = M.existingIds(mod.content.moves)
  local allowed = {}
  -- This mod's spelling -> the cart's, for every move it stood aside for.
  -- Empty on a game that owns none of them, which is why Red never saw the
  -- bug this closes.
  local translate = {}
  for id, record in pairs(payload.moves) do
    local key = M.normaliseId(id)
    if key and existing[key] then
      skipped = skipped + 1
      local cartId = existing[key]
      if type(cartId) == "string" and cartId ~= id then translate[id] = cartId end
      -- An id the cart owns is an id the ENGINE implements, so it is allowed
      -- into a widened learnset regardless of what this mod's own curation
      -- said about the PokeAPI description of it.
      allowed[id] = true
    elseif safe(function()
      -- The cart's own moves print THUNDERBOLT in the FIGHT menu and this
      -- payload spells its moves "Aqua Jet", so an added move stands out
      -- from the ones beside it in exactly the way an added species used to
      -- stand out in the dex.  Only the records this branch REGISTERS are
      -- cased: the branch above leaves a move the cart already owns
      -- completely alone, and the cart already capitalises it.
      if display then record.name = display.upper(record.name) end
      mod.content.moves:register(id, record)
    end) then
      registered = registered + 1
      if record.effectModeled == true then allowed[id] = true end
    end
  end

  -- ---- Gold's Metronome pool, once the placeholders are actually in it.
  --
  -- Ordered after registration because the wrapper is only worth installing
  -- when there is something for it to drop, and it is the same records above
  -- that put them in reach: Gold's pool is data.moves itself.
  local metronome, metronomeReason = M.installMetronomeFilter(generation,
    mod.log)

  -- ---- learnset widening, only when the player asked for it.
  local widened, movesAdded = 0, 0
  if widen then
    local index = loadDataModule(mod, LEARNSET_INDEX)
    if type(index) ~= "table" then
      mod.log:warn("MOVES=ALL is set but the learnset index could not be read "
        .. "-- learnsets are left exactly as they were")
    else
      local shards = {}
      local function shard(number)
        if shards[number] == nil then
          local loaded = loadDataModule(mod, shardPath(number))
          shards[number] = (type(loaded) == "table") and loaded or false
        end
        return shards[number] or nil
      end

      -- Gold keeps ONE `levelMoves` table where Red keeps `learnset` plus a
      -- separate `level1Moves`; src/gen2shape.lua already reshapes this mod's
      -- own records that way, so the field name is all that differs here.
      local field = generation == 2 and "levelMoves" or "learnset"
      for speciesId, number in pairs(index) do
        local rows = shard(number)
        rows = rows and rows[speciesId]
        if rows then
          local record
          local ok, value = pcall(function()
            return mod.content.pokemon:get(speciesId)
          end)
          if ok and type(value) == "table" then record = value end
          if record then
            local merged, added = M.mergeRows(record[field], rows, allowed,
                                              translate)
            if added > 0 then
              if safe(function()
                mod.content.pokemon:patch(speciesId, { [field] = merged })
              end) then
                widened = widened + 1
                movesAdded = movesAdded + added
              end
            end
          end
        end
      end
    end
  end

  mod.log:info("moves gen=%d registered=%d cart-owned=%d stubs=%d "
    .. "widened=%d (+%d rows) failed=%d metronome=%s", generation, registered,
    skipped, stubbed, widened, movesAdded, failed, tostring(metronomeReason))
  if failed > 0 then
    mod.log:warn("%d move registration(s) skipped; first: %s", failed,
      tostring(firstError))
  end
  return { registered = registered, cartOwned = skipped, stubs = stubbed,
           widened = widened, rowsAdded = movesAdded, failed = failed,
           metronome = metronome, metronomeReason = metronomeReason }
end

setmetatable(M, { __call = function(_, ...) return M.install(...) end })

return M
