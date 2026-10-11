-- View modes for the Gen 1 Pokédex LISTING: the engine's own numerical order,
-- alphabetical, and the species this save has actually recorded.  SELECT
-- cycles them and the mode is named on the title row beside POKéDEX.  START
-- opens the search (src/dexsearchview.lua).
--
-- With the national dex on, that screen is 1025 rows ordered by a number a
-- player mostly does not know.  Every other way into a species is by NAME --
-- the party, a trade, a conversation about one -- so a list that can only be
-- entered by its number is a list that has to be walked.
--
-- WHICH KEY.  The engine's list reads UP, DOWN, LEFT, RIGHT, A and B, plus
-- SELECT only when someone has set `onSelectKey` on it, which
-- src/ui/PokedexMenu.lua does not (src/ui/ListMenu.lua:137-179), so SELECT and
-- START are both free here.
--
-- The modes originally took START and the SEARCH took SELECT.  They swapped,
-- because the search is the feature that has to answer to ONE key across both
-- games: Gold's #DEX opens its own search with START
-- (src/ui/gen2/PokedexMenu.lua:383) and cannot be moved off it without losing
-- the cart's OPTION key, and on a desktop keyboard START is Escape while
-- SELECT is Tab -- so leaving Gen 1 on SELECT meant the same feature opening
-- with a different key depending on which game had booted.
--
-- The swap costs these modes the safer key and is still the right way round.
-- useful_dex 1.3.0 binds onSelectKey on this very list, so SELECT is the
-- contested one -- and a view mode that goes quiet next to a neighbour is a
-- convenience lost, while a search that did the same would be a feature simply
-- absent for those players.  Nothing binds START on this screen, so the search
-- works whatever else is installed.
--
-- The one thing that cannot be shared is WHO OWNS THE ROW ORDER.  A neighbour
-- that binds SELECT on this list is switching views of its own, and two owners
-- of one item array cannot both be right, so this stands down out loud when it
-- finds one (see the first-update check in `augment`) rather than fighting for
-- a screen it does not need to own.
--
-- Everything above M.apply is pure -- no love, no engine module, no mod handle
-- -- so the ordering, the filter and the cursor arithmetic are driven by tests
-- with plain tables.
--
-- A "row" here is one line of the listing: { dex = number, name = string,
-- known = boolean }, one per dex number the engine drew, in the engine's own
-- order.  A FORM is not a row and never becomes one: build_national_dex.py
-- numbers the 326 of them far above the real roster and src/nationaldex.lua
-- keeps dexSize off those numbers on purpose (see its FORM_DEX_BASE comment),
-- so `for n = 1, dexSize` never reaches them.  They stay where a player finds
-- them, on the entry page under LEFT/RIGHT, and sorting the listing by name
-- cannot pull twenty-six Alcremies in between two species.

local M = {}

-- ------------------------------------------------------------- pure logic

-- The cycle, in order, and the tag drawn for each.  Numerical is first and is
-- what a list opens in: it is the order the engine builds, the order the
-- entry pages number by and the order every guide ever written uses, so a
-- player who never presses START sees the screen they saw before this mod.
M.MODES = { "num", "alpha", "seen" }

-- The tag names the KEY as well as the mode.  Which view you are in is the
-- half that stops alphabetical reading as a corrupted list, but a player who
-- arrived somewhere by accident also needs to know what gets them back, and
-- the title row has room for both: POKéDEX ends at cell 7 and the longest of
-- these ends at cell 18 of 20.
M.TAG = { num = "SELECT NUM", alpha = "SELECT A-Z", seen = "SELECT SEEN" }

-- The key a row sorts by.  Uppercased because the two halves of this list are
-- typed differently -- the cart's own 151 are "PIKACHU" and every species this
-- mod adds is "Chikorita" -- and a byte-wise sort would file all 874 newcomers
-- after all 151 natives and still call itself alphabetical.  ASCII-only by
-- design: string.upper leaves the multi-byte glyphs alone, so NIDORAN♀ and
-- NIDORAN♂ sort by their bytes, next to each other and always the same way
-- round, which is all this needs of them.
function M.sortKey(row)
  local name = type(row) == "table" and row.name or nil
  if type(name) ~= "string" then return "" end
  return name:upper()
end

function M.dexOf(row)
  local dex = type(row) == "table" and row.dex or nil
  return type(dex) == "number" and dex or 0
end

-- Alphabetical, over the rows a player can actually read.
--
-- An unrecorded row prints "052 -----", and a name nobody can see is a name
-- nobody can look up.  Sorting those rows by their real name would scatter
-- blanks through the list in an order the screen never explains, and it would
-- leak, in position, precisely the names the dashes are there to withhold.  So
-- the recorded rows sort by name and the rest follow in dex order: every
-- species is still reachable in this mode, which matters because dropping them
-- would make A-Z a second filter and there is already one of those.
--
-- Ties break on the dex number rather than on luck.  table.sort is not stable,
-- and two rows that compare equal both ways round is also the shape LuaJIT
-- rejects outright as an invalid order function.
function M.alphabetical(rows)
  local known, unknown = {}, {}
  if type(rows) ~= "table" then return known end
  for index, row in ipairs(rows) do
    if type(row) == "table" and row.known then
      known[#known + 1] = index
    else
      unknown[#unknown + 1] = index
    end
  end
  table.sort(known, function(a, b)
    local left, right = M.sortKey(rows[a]), M.sortKey(rows[b])
    if left ~= right then return left < right end
    return M.dexOf(rows[a]) < M.dexOf(rows[b])
  end)
  for _, index in ipairs(unknown) do known[#known + 1] = index end
  return known
end

-- Only the species this save has a record of.
--
-- `known` comes from the two tables the engine itself keeps -- save.pokedex.
-- seen and save.pokedex.owned -- because those are the only seen/caught state
-- Gen 1 has, and it is the same pair src/ui/PokedexMenu.lua consults to decide
-- whether a row gets a name or five dashes.  So this view is exactly the rows
-- that are not dashes, and exactly as long as the number the engine's own
-- footer is already calling SEEN at the bottom of the screen.
function M.recorded(rows)
  local out = {}
  if type(rows) ~= "table" then return out end
  for index, row in ipairs(rows) do
    if type(row) == "table" and row.known then out[#out + 1] = index end
  end
  return out
end

-- The next mode START moves to, skipping any view with nothing in it.
--
-- The skip is not tidiness.  A list with no items is a screen where the
-- engine's own update pops the stack on the next A or B (ListMenu.lua:143-150),
-- so cycling onto an empty recorded view on a save that has recorded nothing
-- would turn the very next button press into "the Pokédex closed itself".
-- `has` is a per-mode truth table; nil means all of them are available.
function M.nextMode(mode, has)
  local at = 1
  for index, name in ipairs(M.MODES) do
    if name == mode then at = index end
  end
  for step = 1, #M.MODES do
    local candidate = M.MODES[((at - 1 + step) % #M.MODES) + 1]
    if has == nil or has[candidate] then return candidate end
  end
  return mode
end

-- Where the cursor goes when the view changes.
--
-- On the same species, whenever the new view still has it: a mode change is a
-- change of route, not a change of destination, and someone who pressed START
-- while looking at Dragonite is asking where Dragonite sits alphabetically.
-- Only the recorded view can drop the row under the cursor, and then the
-- nearest one at or after its dex number is the closest thing to standing
-- still -- the neighbouring species is what was around the cursor anyway.
-- Past the end of the list, the last row.
function M.cursorFor(view, rows, target)
  if type(view) ~= "table" or #view == 0 then return 1 end
  for position, index in ipairs(view) do
    if index == target then return position end
  end
  local wanted = M.dexOf(type(rows) == "table" and rows[target] or nil)
  local after, afterDex, last, lastDex = nil, nil, nil, nil
  for position, index in ipairs(view) do
    local dex = M.dexOf(type(rows) == "table" and rows[index] or nil)
    if dex >= wanted and (afterDex == nil or dex < afterDex) then
      after, afterDex = position, dex
    end
    if lastDex == nil or dex > lastDex then last, lastDex = position, dex end
  end
  return after or last or 1
end

-- Scroll that keeps the cursor on the screen row it was already on.
--
-- The engine syncs scroll itself, but only far enough to drag the cursor back
-- into view (ListMenu.lua:102-107), which after a jump from row 900 to row 12
-- means the cursor lands on the top or bottom edge of the screen.  Holding the
-- row is what makes a mode change read as the list moving under a cursor that
-- stayed put, and it costs one clamp: never past the end of the list, never
-- off the window in either direction.
function M.scrollFor(index, screenRow, count, window)
  if type(index) ~= "number" or type(count) ~= "number"
    or type(window) ~= "number" or window < 1 then
    return 0
  end
  local row = type(screenRow) == "number" and screenRow or 1
  local scroll = index - math.max(1, math.min(row, window))
  scroll = math.min(scroll, math.max(0, count - window))
  if index - scroll > window then scroll = index - window end
  if index - scroll < 1 then scroll = index - 1 end
  return math.max(0, scroll)
end

-- ------------------------------------------------------------ engine patch

-- Required lazily and guarded, exactly the way src/dexpage.lua's requireAll
-- is: a missing or reshaped module costs this feature and nothing else, and
-- no headless caller of the pure half above pulls love or src.* in behind it.
local function requireAll()
  local names = { "src.render.Font", "src.core.Strings" }
  local found = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    found[name] = value
  end
  return found
end

local function report(mod, message)
  if mod and mod.log and type(mod.log.info) == "function" then
    mod.log:info(message)
  end
end

-- The rows the engine drew, described again from the same two sources it used.
--
-- Deliberately a re-derivation rather than a reading of the built items: the
-- label is "025 PIKACHU" or "025 -----" and parsing a name back out of it
-- would depend on the number width, on the neighbour that may have written it,
-- and on a species whose name starts with a digit never existing.  Both loops
-- below are the ones in src/ui/PokedexMenu.lua:16-26, so the answer lines up
-- row for row -- and when it does not, that mismatch is the guard that stops
-- this reordering a list it does not understand.
function M.describe(game)
  local constants = type(game.data.constants) == "table"
    and game.data.constants or {}
  -- BOTH homes of dexSize, because this function now answers for both games
  -- and the mod's own patch lands in a different one on each.
  -- src/nationaldex.lua calls mod.content.constants:patch("dexSize", ...);
  -- src/mods/Schemas.lua:485 routes the constants registry to `gen2Constants`
  -- on a Gen 2 boot, so on Gold the value is at data.gen2Constants.dexSize and
  -- data.constants.dexSize is never written at all.
  --
  -- Reading only Gen 1's home is why Gold's search covered 151 species: the
  -- lookup missed, the literal fallback below answered, and the search quietly
  -- described a Kanto-sized dex while the listing behind it held 1025 rows.
  -- src/gen2dexlist.lua's header already recorded that the patch "succeeds and
  -- means nothing" because nothing read it back -- this is the reader.
  local gen2 = type(game.data.gen2Constants) == "table"
    and game.data.gen2Constants or {}
  local size = type(constants.dexSize) == "number" and constants.dexSize
    or type(gen2.dexSize) == "number" and gen2.dexSize
    or 151
  local byDex = {}
  for _, def in pairs(game.data.pokemon) do
    if type(def) == "table" and def.dex then byDex[def.dex] = def end
  end
  local dex = type(game.save) == "table" and game.save.pokedex or nil
  local seen = type(dex) == "table" and type(dex.seen) == "table"
    and dex.seen or {}
  -- BOTH spellings of the caught table, because this function now answers for
  -- both games and they do not agree on the name: Gen 1 keeps `owned`
  -- (src/ui/PokedexMenu.lua reads it), Gold keeps `caught`
  -- (src/core/gen2/Save.lua:216 builds `pokedex = { seen = {}, caught = {} }`).
  -- Reading only Gen 1's name left the caught half permanently empty on Gold.
  --
  -- That was survivable HERE and nowhere worth relying on: `known` is a
  -- seen-or-caught test and nothing can be caught without first being seen, so
  -- the rows came out right by luck rather than by reading the save. A caller
  -- that ever needs caught on its own -- a "caught only" view, a completion
  -- count -- would have got silence, so the missing name is fixed rather than
  -- documented.
  local owned = type(dex) == "table" and type(dex.owned) == "table"
    and dex.owned or {}
  local caught = type(dex) == "table" and type(dex.caught) == "table"
    and dex.caught or {}
  -- The engine stops the listing at the highest number the player has SEEN,
  -- not at the end of the roster -- engine/menus/pokedex.asm:200-216, which
  -- src/ui/PokedexMenu.lua started honouring on 2026-08-27 (its `maxSeen`).
  -- Describing every claimed number instead made this disagree with the list
  -- it is describing by exactly the rows past the frontier, and a mismatch is
  -- what makes the view modes stand down: reordering a list this did not
  -- build would put the wrong species under the cursor.
  local maxSeen = 0
  for n = 1, size do
    local def = byDex[n]
    if type(def) == "table"
      and (owned[def.id] or caught[def.id] or seen[def.id]) then
      maxSeen = n
    end
  end
  local rows = {}
  for n = 1, math.min(size, maxSeen) do
    local def = byDex[n]
    if type(def) == "table" then
      rows[#rows + 1] = {
        dex = n,
        name = type(def.name) == "string" and def.name or tostring(def.id),
        known = (owned[def.id] or caught[def.id] or seen[def.id])
          and true or false,
        -- Carried for the search, which filters on typing.  Read here rather
        -- than by a second describer of its own: two functions reading these
        -- same two tables is how two answers to one question drift apart.
        types = type(def.types) == "table" and def.types or {},
      }
    end
  end
  return rows
end
local describe = M.describe

-- The row count, whichever shape this engine keeps it in.
--
-- It was a plain field when this was written and became a method on
-- 2026-08-27 (src/ui/PokedexMenu.lua's `function PokedexMenu:rows()`).  The
-- guard below asked for a number, so from that build onward it answered "not
-- this engine's own list" about the engine's OWN list: the view modes stood
-- down on every boot, START did nothing, and the only thing that said so was
-- an info line the fused launcher swallows.  A shape check that cannot pass
-- is worse than no check, because it fails quietly and looks deliberate.
local function rowCount(list)
  local value = type(list) == "table" and list.rows or nil
  if type(value) == "number" then return value end
  if type(value) == "function" then
    local ok, count = pcall(value, list)
    if ok and type(count) == "number" then return count end
  end
  return nil
end

local function augment(list, mod)
  local modules = requireAll()
  if not modules then
    report(mod, "the Pokédex listing's view modes need the font and string "
      .. "modules and this engine did not hand them over -- the list keeps "
      .. "dex order and START does nothing")
    return false
  end
  local Font = modules["src.render.Font"]
  local Strings = modules["src.core.Strings"]

  local game = type(list) == "table" and list.game or nil
  if type(list) ~= "table" or type(list.items) ~= "table"
    or type(list.update) ~= "function" or type(list.draw) ~= "function"
    or type(list.index) ~= "number" or type(list.scroll) ~= "number"
    or rowCount(list) == nil
    or type(game) ~= "table" or type(game.data) ~= "table"
    or type(game.data.pokemon) ~= "table" then
    report(mod, "the Pokédex listing is not this engine's own list -- view "
      .. "modes reorder its item array and its cursor, and standing down is "
      .. "the only safe answer to a screen of a shape this cannot read")
    return false
  end

  local rows = describe(game)
  if #rows == 0 then
    report(mod, "the Pokédex listing has no species in dex range -- there is "
      .. "nothing for the view modes to order, so START does nothing")
    return false
  end
  if #rows ~= #list.items then
    report(mod, ("the Pokédex listing has %d rows where the dex numbers this "
      .. "engine holds make %d -- another mod is choosing the rows, and "
      .. "reordering a list this one did not build would put the wrong "
      .. "species under the cursor, so the view modes stand down")
      :format(#list.items, #rows))
    return false
  end

  -- The numerical view is the identity, and its items array is the very one
  -- the constructor built: switching back to NUM restores the original object,
  -- not a copy of it, so a neighbour holding a reference to that array still
  -- holds the array the player is looking at.
  local numerical = {}
  for index = 1, #rows do numerical[index] = index end
  local original = list.items

  local views = { num = numerical }
  local function viewFor(mode)
    local view = views[mode]
    if view == nil then
      if mode == "alpha" then
        view = M.alphabetical(rows)
      elseif mode == "seen" then
        view = M.recorded(rows)
      else
        view = numerical
      end
      views[mode] = view
    end
    return view
  end

  local function itemsFor(view)
    if view == numerical then return original end
    local items = {}
    for position, index in ipairs(view) do items[position] = original[index] end
    return items
  end

  local mode, current = "num", numerical

  local function switch(self, wanted)
    local view = viewFor(wanted)
    if type(view) ~= "table" or #view == 0 then return false end
    -- Which SPECIES the cursor is on has to be read before anything moves,
    -- and it is read in ROW terms -- the item under the cursor belongs to
    -- current[index], whatever order the current view happens to be in.
    local at = math.max(1, math.min(self.index, #current))
    local target = current[at] or 1
    local screenRow = self.index - self.scroll
    local items = itemsFor(view)
    local position = M.cursorFor(view, rows, target)
    self.items = items
    self.index = position
    self.scroll = M.scrollFor(position, screenRow, #items, rowCount(self) or 0)
    mode, current = wanted, view
    return true
  end

  local off = false
  local checked = false

  local originalUpdate = list.update
  list.update = function(self, dt)
    -- The neighbour check runs on the first frame rather than at install
    -- time, because a mod that REPLACES the dex screen builds this very list
    -- inside its own factory and decorates what comes back -- useful_dex
    -- 1.3.0's list IS the engine's, with wrap and an onSelectKey written onto
    -- it afterwards -- so at the moment this file runs there is nothing to
    -- see.  Before the original update, so the first press of anything is
    -- already judged by the answer.
    if not checked then
      checked = true
      -- Ours does not count: this mod's own search binds this field, and
      -- treating that as a neighbour arriving would switch the view modes off
      -- on the frame they were installed.
      if type(self.onSelectKey) == "function" then
        off = true
        report(mod, "another mod has bound SELECT on the Pokédex listing, "
          .. "which is where a dex mod puts its own view switching -- two "
          .. "owners of one row order cannot both be right, so this mod's "
          .. "list modes stand down and leave the screen to it")
      end
    end
    originalUpdate(self, dt)
    if off then return end
    local input = self.game and self.game.input
    if type(input) ~= "table" or type(input.wasPressed) ~= "function" then
      return
    end
    -- START opens the SEARCH, and it is START in both games now.
    --
    -- Gold's #DEX opens its search with START (its own cart does:
    -- game/src/ui/gen2/PokedexMenu.lua:383), and on a desktop keyboard START
    -- is Escape while SELECT is Tab (game/src/core/Input.lua) -- so leaving
    -- Gen 1 on SELECT meant one feature answering to two different keys
    -- depending on which game was booted.  The view modes moved to SELECT to
    -- free this one; see the onSelectKey install below.
    --
    -- The swap also takes the search out of the neighbour fight entirely.
    -- useful_dex 1.3.0 binds onSelectKey and nothing binds START on this
    -- screen, so the search now works whatever else is installed, and only the
    -- view modes stand down.  That is the right way round: the modes are a
    -- convenience, and a search a player cannot open is a feature that is
    -- simply absent.
    if input:wasPressed("start") and M.openSearch then
      M.openSearch(self, rows, mod)
    end

    -- SELECT cycles the view modes, read HERE rather than through the list's
    -- own onSelectKey hook.  That hook fires inside ListMenu's update
    -- (src/ui/ListMenu.lua:165), so switching from it reorders the item array
    -- half way through the engine's own input pass and the cursor and scroll
    -- it syncs afterwards no longer describe the list underneath them.  Read
    -- after originalUpdate, the switch lands on a settled list.
    --
    -- A neighbour that owns onSelectKey is still respected: the check above
    -- sets `off` on the first frame and this whole block stops running, so
    -- SELECT never changes hands twice on one press.
    --
    -- Availability is asked for at the press rather than kept, because the
    -- answer builds the views themselves and a dex opened and closed without
    -- ever pressing SELECT should never have paid to sort 1025 rows.
    if input:wasPressed("select") then
      local wanted = M.nextMode(mode, {
        num = true,
        alpha = #viewFor("alpha") > 0,
        seen = #viewFor("seen") > 0,
      })
      if wanted ~= mode then switch(self, wanted) end
    end
  end

  local originalDraw = list.draw
  list.draw = function(self)
    originalDraw(self)
    if off then return end
    -- The list has already drawn by the time this runs, so a tag that threw
    -- costs the tag and leaves the screen standing -- which is the whole
    -- reason it is drawn after rather than woven in.
    pcall(function()
      local tag = Strings(M.TAG[mode] or M.TAG.num)
      love.graphics.setColor(0, 0, 0, 1)
      -- Right margin, on the title's own row: the list draws POKéDEX at
      -- (8, 4) and its first entry at y = 24, so this is the one line on the
      -- screen with nothing else on it.
      Font.draw(tag, 160 - 8 - Font.width(tag), 4)
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end

  -- SELECT opens the search.  Marked, so the neighbour check above knows this
  -- handler is this mod's and does not switch the view modes off against it.
  --
  -- Only when nobody else holds the key: useful_dex 1.3.0 binds SELECT on
  -- this very list, and a mod that got here first keeps it.  Said out loud
  -- rather than silently, because a feature that is simply absent on some
  -- installs is the kind of thing this project has paid days for.
  return true
end

-- Open a species' entry page from a search result.
--
-- Through the LISTING's own item rather than through a second route into the
-- entry screen: the item the constructor built already carries whatever a
-- neighbour decorated it with, and a second way in is a second thing to keep
-- in step with the first.
--
-- A built item ({ label, ball, value } -- src/ui/PokedexMenu.lua) carries no
-- dex NUMBER of its own: `value` is the species id when the row is seen or
-- owned and nil otherwise, and an id is not a name -- "NIDORAN_F" is the id
-- of a species displayed as NIDORAN♀, and every alternate form's id is a
-- spelling ("RATTATA_ALOLA") no listing ever prints.  The label, though, is
-- built as ("%0Nd %s"):format(n, ...) for every row
-- regardless of seen state (PokedexMenu.lua's numFmt), so the dex number at
-- its head is the one thing every item is guaranteed to carry.  And "open
-- this entry" is `onChoose` -- the callback A already drives (ListMenu.lua)
-- -- opening the same DATA/CRY/AREA menu a manual selection would, rather
-- than a shortcut into DexEntryMenu that only this path takes.
--
-- `mod` is optional and only ever used to report the miss below: every other
-- early return here is a shape guard (not a list, no items, no dex number to
-- look for) rather than something a player did, but a dex number no item's
-- label carries is a real outcome -- a neighbour relabelled the rows -- and
-- rule 6 is that a guard which refuses to do something says so out loud, so
-- this is the one path that reports.
function M.openEntry(list, row, mod)
  if type(list) ~= "table" or type(row) ~= "table" then return false end
  local items = type(list.items) == "table" and list.items or nil
  if not items then return false end
  local dex = M.dexOf(row)
  if dex == 0 then return false end
  for index, item in ipairs(items) do
    local label = type(item) == "table" and item.label or nil
    local number = type(label) == "string" and tonumber(label:match("^(%d+)"))
      or nil
    if number == dex then
      list.index = index
      list.scroll = M.scrollFor(index, 1, #items, list.rows or 7)
      if type(list.onChoose) == "function" then list.onChoose(item, list) end
      return true
    end
  end
  report(mod, ("a search result picked dex #%d, but no item on the listing "
    .. "carries that number in its label -- another mod has relabelled the "
    .. "rows, so the entry does not open rather than guessing at the wrong "
    .. "one"):format(dex))
  return false
end

-- Adds the view modes to one built listing, or answers false having said why.
-- Never throws: the caller is a constructor patch riding under a neighbour's
-- screen, and a throw there degrades that screen to the builtin one and costs
-- its owner every feature it came with.
function M.apply(list, mod)
  local ok, applied = pcall(augment, list, mod)
  if not ok then
    report(mod, ("the Pokédex listing's view modes failed to install (%s) -- "
      .. "the list keeps dex order and nothing else changes")
      :format(tostring(applied)))
    return false
  end
  return applied and true or false
end

setmetatable(M, { __call = function(_, list, mod) return M.apply(list, mod) end })

return M
