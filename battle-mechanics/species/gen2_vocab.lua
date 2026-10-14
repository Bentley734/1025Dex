-- Gen 2 vocabulary normalization -- rewriting Gen 1 id spellings into Gold's.
--
-- THE BUG THIS EXISTS FOR, stated precisely because the fix must not be
-- broader than the cause.
--
-- Two id spaces that are the same nouns with different spellings, and one
-- data source that only ever speaks the older one:
--
--   growth_rates         Red  MEDIUM_FAST           Gold GROWTH_MEDIUM_FAST
--   moves (cart-owned)   mod  METALCLAW             Gold METAL_CLAW
--
-- The engine deliberately does not unify them (src/mods/Schemas.lua's own
-- note: Gold's extractor writes GROWTH_MEDIUM_FAST where Red's writes
-- MEDIUM_FAST, and both growth spaces key by their own cart's names).  A record carrying the
-- Gen 1 spelling on a Gold boot is therefore a genuinely unresolved
-- `f.id(...)` reference, and Schemas.crossValidate reports every one:
--
--   national_dex: pokemon.CHIKORITA.growthRate: unresolved reference to
--     growth_rates "MEDIUM_FAST"
--
-- national_dex IS generation-aware -- src/gen2shape.lua reshapes baseStats,
-- learnset -> levelMoves, species -> into and frontSize -> picSize for Gold
-- -- but it does not translate these two, and its generated records give
-- every one of its ~1238 registrations growthRate = "MEDIUM_FAST".  This
-- mod's own learnset pass -- combat/learnset_ownership.lua -- reads
-- national_dex's unfiltered movesFull, which spells the cart-owned Gen 2
-- moves without separators (METALCLAW) while Gold registers them with them
-- (METAL_CLAW).  Confirmed by direct extraction, not assumed: of the 827
-- distinct move ids in national_dex's extras, exactly 45 differ from a Gold
-- id only by separators, and those are the ones that dangle.
--
-- WHY THIS MOD DOES THE TRANSLATING rather than national_dex.  This mod
-- already declares games=[gen1,gen2], already depends on national_dex, and
-- already owns the learnset patch pass that writes the worst of it.
-- Reshaping what it reads on a Gold boot is the same defensive job
-- src/mods/Gen2Compat.lua does for engine modules, one level up.  The
-- growthRate half is another mod's record, so it is fixed by a reapply()
-- sweep AFTER national_dex has registered -- the same shape
-- stats/reapply_national_dex_stats.lua already uses to reach national_dex's
-- records from here.
--
-- TWO MECHANISMS, and the split is deliberate -- it is what keeps this from
-- being a guess:
--
--   * SAME WORD, DIFFERENT SEPARATORS (cart-owned moves).  normalise()
--     strips everything but [A-Z0-9], so METALCLAW == METAL_CLAW.  A
--     reverse index over the LIVE registry resolves them, and a normalised
--     form claimed by two different live ids resolves to nothing (never
--     picked between) -- exactly the rule national_dex's own
--     src/moverepair.lua already applies to the same class of id.
--   * DIFFERENT WORD (growth rates).  Separator stripping cannot see
--     MEDIUM_FAST -> GROWTH_MEDIUM_FAST, so the rule is the one the engine's
--     own Schemas comment states: Gold prefixes.  Every candidate is still
--     checked against the LIVE registry before it is used, so this can only
--     ever point at an id that actually exists.
--
-- A resolved target is only ever an id the live registry already holds.
-- An id neither mechanism can resolve is returned UNCHANGED -- a genuine
-- typo stays a genuine, reported typo rather than being silently waved
-- through, which is the property Schemas.crossValidate was built to keep.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local isGen2 = GameVersion.generation(GameVersion.get()) == 2

  local M = {}

  -- Same normalisation national_dex's src/moves.lua and src/moverepair.lua
  -- register through, so an id this module resolves is an id that module
  -- would have resolved too.
  local function normalise(id)
    if type(id) ~= "string" then return nil end
    return (id:upper():gsub("[^A-Z0-9]", ""))
  end
  M.normalise = normalise

  -- The live ids of one registry.  Registry:each() is the sanctioned walk
  -- and returns an iterator that skips tombstoned ids; it is pcall-guarded
  -- rather than trusted (a shape change must cost this module its index,
  -- never the load), and both a table-returning and a function-returning
  -- shape are tolerated because tools/tests build stand-in registries.
  local function idsOf(registry)
    local ids, seen = {}, {}
    if type(registry) ~= "table" then return ids end
    local ok, iter = pcall(function() return registry:each() end)
    if not ok or iter == nil then return ids end
    local function add(id)
      if type(id) == "string" and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
    if type(iter) == "function" then
      for id in iter do add(id) end
    elseif type(iter) == "table" then
      for _, id in ipairs(iter) do add(id) end
    end
    return ids
  end

  -- Built lazily on first use, then memoized: the registries are still
  -- being written to while mods load, so an index taken at install time
  -- would miss every id a later file of this mod registers.
  local indexes = {}
  local function index(name)
    if indexes[name] then return indexes[name] end
    local exact, byNorm = {}, {}
    for _, id in ipairs(idsOf(mod.content and mod.content[name])) do
      exact[id] = true
      local key = normalise(id)
      if key and key ~= "" then
        local prior = byNorm[key]
        if prior == nil then byNorm[key] = id
        elseif prior ~= id then byNorm[key] = false end -- ambiguous
      end
    end
    indexes[name] = { exact = exact, byNorm = byNorm }
    return indexes[name]
  end

  local function held(name, id)
    local idx = index(name)
    return idx.exact[id] and true or false
  end

  -- Separator-only resolution.  An exact live hit wins outright (so an id
  -- the registry already holds is never rewritten), then the normalised
  -- reverse index; false marks an ambiguous normalised form.
  local function sameWord(name, id)
    if type(id) ~= "string" then return id end
    if held(name, id) then return id end
    local key = normalise(id)
    local hit = key and index(name).byNorm[key]
    if type(hit) == "string" then return hit end
    return id
  end

  -- Prefix resolution: try the id, then `<prefix>..id`, both against the
  -- live registry.
  local function prefixed(name, id, prefix)
    if type(id) ~= "string" then return id end
    if held(name, id) then return id end
    local candidate = prefix .. id
    if held(name, candidate) then return candidate end
    return id
  end

  function M.growthRate(id) return prefixed("growth_rates", id, "GROWTH_") end
  function M.moveId(id) return sameWord("moves", id) end

  -- The dangling references a record still carries, normalised.  Answers a
  -- patch table (possibly empty) plus how many fields it rewrote.  Move
  -- lists are only rebuilt when a ref actually resolves differently, so a
  -- correctly-spelled record never pays for a patch.
  local function recordPatch(record)
    local patch, changed = {}, 0
    if type(record.growthRate) == "string" then
      local fixed = M.growthRate(record.growthRate)
      if fixed ~= record.growthRate then patch.growthRate = fixed changed = changed + 1 end
    end
    for _, listField in ipairs({ "levelMoves", "learnset", "eggMoves", "tmhm" }) do
      local list = record[listField]
      if type(list) == "table" and #list > 0 then
        local out, n = {}, 0
        for i, entry in ipairs(list) do
          if type(entry) == "table" and type(entry.move) == "string" then
            local fixed = M.moveId(entry.move)
            if fixed ~= entry.move then
              local copy = {}
              for k, v in pairs(entry) do copy[k] = v end
              copy.move = fixed
              out[i] = copy
              n = n + 1
            else
              out[i] = entry
            end
          elseif type(entry) == "string" then
            local fixed = M.moveId(entry)
            out[i] = fixed
            if fixed ~= entry then n = n + 1 end
          else
            out[i] = entry
          end
        end
        if n > 0 then patch[listField] = out changed = changed + n end
      end
    end
    return patch, changed
  end
  M.recordPatch = recordPatch

  -- The sweep.  Runs after national_dex has registered (this mod depends on
  -- it, so it loads first) and after every one of this mod's own patches.
  -- Patches a record only when a reference in it actually resolves
  -- differently, so an engine-owned or already-correct record is never
  -- touched -- no new op, no new error attribution.
  function M.reapply()
    if not isGen2 then return 0, 0 end
    local registry = mod.content and mod.content.pokemon
    if type(registry) ~= "table" then return 0, 0 end
    local changedRecords, changedFields = 0, 0
    -- Collect first, patch second: patching while walking :each() would
    -- invalidate the very cache the walk is reading through.
    local ids = idsOf(registry)
    for _, id in ipairs(ids) do
      local ok, record = pcall(function() return registry:get(id) end)
      if ok and type(record) == "table" then
        local patch, n = recordPatch(record)
        if n > 0 then
          if pcall(function() registry:patch(id, patch) end) then
            changedRecords = changedRecords + 1
            changedFields = changedFields + n
          end
        end
      end
    end
    return changedRecords, changedFields
  end

  M.isGen2 = isGen2
  return M
end
