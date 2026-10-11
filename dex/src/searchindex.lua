-- The generated reverse index (data/species/generated/search_index.lua),
-- read back.
--
-- The search needs to answer "which species learn Earthquake" between two
-- keystrokes.  The extras shards cannot: they are 9.2 MB across 35 files and
-- are lazily loaded one shard at a time precisely because reading them all is
-- expensive.  So tools/build_national_dex.py inverts them once at build time
-- and this file reads the result.
--
-- Each dex list arrives as ONE comma-separated string rather than an array,
-- because ~900 moves averaging ~80 species is ~72,000 number constants in a
-- single chunk and LuaJIT's ceiling is 65,536 -- the same ceiling that cost
-- the withdrawn 0.8.0 build every species it had.  Splitting a string is the
-- price of staying under it, and it is paid once per term and then cached.
--
-- Pure: the payload is handed in, never read from disk here, so the tests
-- drive this with plain tables and main.lua owns the one mod:read.

local M = {}

-- Parsed sets, keyed by payload table then by "kind:term".  Per-payload
-- rather than one global cache: a reload builds a second payload in the same
-- process, and one cache serving both would answer the new payload's
-- questions with the old one's data.  Weak keys so a dropped payload does not
-- pin its sets in memory for the life of the process.
local caches = setmetatable({}, { __mode = "k" })

local FIELDS = {
  ability = { dex = "abilityDex", names = "abilityNames" },
  move    = { dex = "moveDex",    names = "moveNames" },
}

local function tableFor(payload, kind, which)
  local field = FIELDS[kind]
  if type(payload) ~= "table" or not field then return nil end
  local found = payload[field[which]]
  return type(found) == "table" and found or nil
end

-- The dex numbers holding `term`, as a set, or nil when the index has never
-- heard of the term.  nil and an empty set are different answers and the
-- caller depends on the difference: "nothing learns this" is a search that
-- ran, "this is not a move" is a term that has to be read another way.
--
-- The cache is keyed on `payload` itself, not on some derived id, which is
-- why it has to be checked and populated AFTER the string lookup below
-- rather than before: a term this payload does not have must keep answering
-- nil on every call rather than being remembered as an empty table the first
-- time it is asked, which would erase the nil/empty distinction this
-- function exists to preserve.
function M.dexSet(payload, kind, term)
  local packed = tableFor(payload, kind, "dex")
  local value = packed and packed[term] or nil
  if type(value) ~= "string" then return nil end

  local cache = caches[payload]
  if not cache then
    cache = {}
    caches[payload] = cache
  end
  local key = kind .. ":" .. term
  local hit = cache[key]
  if hit then return hit end

  local set = {}
  for digits in value:gmatch("%d+") do
    local number = tonumber(digits)
    if number then set[number] = true end
  end
  cache[key] = set
  return set
end

-- The spelling the DATA source uses, for printing.  The player typed
-- "gigadrain"; the screen should say "Giga Drain".
function M.displayName(payload, kind, term)
  local names = tableFor(payload, kind, "names")
  local value = names and names[term] or nil
  return type(value) == "string" and value or nil
end

-- Agrees with dexSet by construction: both read the packed table off the
-- same tableFor helper and both require the entry to be a string, so a
-- malformed entry (a number, say, where build_national_dex.py should have
-- written a comma-separated string) is "unknown" to both rather than a crash
-- to one and a false positive to the other.
function M.has(payload, kind, term)
  local packed = tableFor(payload, kind, "dex")
  return type(packed) == "table" and type(packed[term]) == "string"
end

return M
