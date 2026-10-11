-- Repairing move slots this mod already broke.
--
-- src/moves.lua stops NEW learnset rows naming a move the running game cannot
-- resolve.  It does nothing for a Pokemon that already learned one, and that
-- is not a detail: a move slot is save data.  `id`, `pp` and `maxPp` are
-- written into the save when the move is learned and nothing re-derives them
-- afterwards, so a Rolycoly that learned RAPIDSPIN before the fix keeps
-- RAPIDSPIN at 0/0 for the rest of that playthrough, on every load, forever.
--
-- WHY NOT A MIGRATION, which is the sanctioned route and was the first choice.
-- SaveData.runMigrations only runs a mod's chain when the save carries a
-- modData slice for that mod (`if modSave and recorded then`), and this mod
-- writes none -- a real Silver save's modData holds one entry, and it belongs
-- to somebody else.  Adding a slice purely to unlock a migration would mean
-- writing to every save that loads in order to fix the few that need it.
--
-- So this runs at save.loaded instead, and is deliberately the narrowest
-- repair that can work:
--
--   * it only ever looks at a slot whose id the merged move table CANNOT
--     resolve.  A working slot is never touched, whoever wrote it.
--   * it only rewrites when the normalised form of that id matches exactly one
--     real move.  An id that matches nothing is left alone -- it may belong to
--     another mod that has not loaded yet, and guessing would be worse than
--     the 0/0 it replaces.
--   * PP is restored to the record's full value rather than preserved, because
--     the broken slot's PP was 0 and stayed 0: the move could never be used,
--     so there is no spent PP to respect.
--
-- It cannot make things worse in the case it does nothing about, which is the
-- property that matters for something that edits a player's save on load.
local M = {}

local deps = nil

function M.bind(modules) deps = modules end

-- Same normalisation src/moves.lua registers through, so an id this repair
-- resolves is an id that module would have translated.
local function normalise(id)
  if type(id) ~= "string" then return nil end
  return (id:upper():gsub("[^A-Z0-9]", ""))
end

--- normalised id -> the single real move id it names, built from the merged
--- move table.  A normalised form claimed by more than one real id is dropped
--- rather than picked between: two moves that differ only in punctuation is a
--- situation this mod has no business resolving silently.
function M.index(moves)
  if type(moves) ~= "table" then return nil end
  local byKey, ambiguous = {}, {}
  for id, record in pairs(moves) do
    if type(id) == "string" and type(record) == "table" then
      local key = normalise(id)
      if key then
        if byKey[key] ~= nil and byKey[key] ~= id then
          ambiguous[key] = true
        else
          byKey[key] = id
        end
      end
    end
  end
  for key in pairs(ambiguous) do byKey[key] = nil end
  return byKey
end

--- Repairs one Pokemon, answering how many slots changed.
function M.repairMon(mon, moves, index)
  if type(mon) ~= "table" or type(mon.moves) ~= "table" then return 0 end
  local fixed = 0
  for _, slot in ipairs(mon.moves) do
    if type(slot) == "table" and type(slot.id) == "string"
      and moves[slot.id] == nil then
      local key = normalise(slot.id)
      local real = key and index[key]
      local record = real and moves[real]
      if record then
        slot.id = real
        local pp = tonumber(record.pp)
        if pp then
          slot.pp = pp
          slot.maxPp = pp
        end
        fixed = fixed + 1
      end
    end
  end
  return fixed
end

-- Every Pokemon a save holds. Party and boxes both, because a broken slot
-- follows the Pokemon into storage and a player who boxed their Rolycoly
-- before this shipped is exactly the person it has to reach.
local function eachMon(save, fn)
  for _, mon in ipairs((save and save.party) or {}) do fn(mon) end
  for _, box in ipairs((save and save.boxes) or {}) do
    if type(box) == "table" then
      -- Two shapes seen in the wild: a bare array of mons, and a record with
      -- its own `mons` list. Walking whichever is there costs nothing and
      -- means this does not quietly skip half a player's storage.
      for _, mon in ipairs(box.mons or box) do fn(mon) end
    end
  end
end

--- The whole repair. Answers the number of slots fixed, and says so when it
--- fixed anything -- a save being edited on load is worth a line in the log
--- even when the edit is a correction.
function M.run(save, moves)
  local index = M.index(moves)
  if not index then return 0 end
  local fixed, mons = 0, 0
  eachMon(save, function(mon)
    local n = M.repairMon(mon, moves, index)
    if n > 0 then mons = mons + 1 end
    fixed = fixed + n
  end)
  if fixed > 0 and deps and deps.log then
    deps.log:info("national_dex: repaired %d unusable move slot(s) across %d "
      .. "Pokemon -- these named a move under a spelling this game does not "
      .. "register, and sat at 0/0 PP", fixed, mons)
  end
  return fixed
end

return M
