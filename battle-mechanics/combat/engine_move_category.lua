-- Physical/Special/Status resolution for a move record, for display
-- (SummaryMenu page 2, anywhere else a moveset with PP is shown) -- not
-- used by the native damage calc, which already has its own answer for
-- this (Damage.isSpecial / TypeChart.category, unchanged, untouched here).
--
-- Native Gen 1 moves (the engine's own generated moves.lua, machine-
-- generated from the ROM) have no category field at all: Gen 1 determines Physical/Special
-- purely from the move's TYPE, via the same data-driven lookup the native
-- damage calc already uses (TypeChart.category, src/battle/TypeChart.lua)
-- -- reused here rather than reimplemented. Status moves are power = 0 in
-- this data (confirmed directly, e.g. GROWL), checked before the type
-- lookup so a status move's type doesn't misreport it as Physical/Special.
--
-- Showdown-originated moves (anything not among the original 165, reached
-- through a Showdown-backed battle) carry their own real category field
-- from Showdown's movedex -- that field is populated onto the move record
-- by the Phase 4 data-mapping work (ShowdownTeam.lua and whatever loads
-- Showdown move data for Lua), read directly here rather than guessed at
-- from type, since Gen 4+ broke the strict type-implies-category rule
-- (e.g. Focus Blast/Special vs Close Combat/Physical, both Fighting).
--
-- Lives in GalarGmaxDex's own folder, not the engine tree -- loaded once
-- by main.lua into mod.exports.MoveCategory (see engine_modern_stats.lua's
-- own header for the full reasoning, including why this moved off
-- package.preload).

local TypeChart = require("src.battle.TypeChart")

local MoveCategory = {}

-- "Physical" | "Special" | "Status", or nil if moveDef is missing/unusable.
function MoveCategory.of(moveDef)
  if type(moveDef) ~= "table" then return nil end

  -- A move carrying its own category is authoritative -- never overridden by
  -- the type-based guess below. The field is spelled lower-case by
  -- national_dex's generated registry and the G-Max move table
  -- ("physical"/"special"/"status"), and capitalised by Showdown-originated
  -- records, so accept BOTH spellings (and either field name). Only accepting
  -- the capitalised spelling made every lower-case record fall through to the
  -- Gen 2/3 type split -- which modern records deliberately break (a DARK or
  -- FIRE move can be Physical: Foul Play, Crunch, Fire Fang, Waterfall...).
  local own = moveDef.category
  if type(own) ~= "string" then own = moveDef.damageClass end
  if type(own) == "string" then
    local lc = own:lower()
    if lc == "physical" then return "Physical" end
    if lc == "special" then return "Special" end
    if lc == "status" then return "Status" end
  end

  if (moveDef.power or 0) == 0 then
    return "Status"
  end

  local cat = TypeChart.category(moveDef.type)
  if cat == "special" then return "Special" end
  if cat == "physical" then return "Physical" end
  return nil
end

-- Convenience: resolve straight from a move id via the merged move
-- registry (data.moves), the same table SummaryMenu/PartyMenu already read
-- move definitions from.
function MoveCategory.forId(data, moveId)
  if not (data and data.moves and moveId) then return nil end
  return MoveCategory.of(data.moves[moveId])
end

return MoveCategory
