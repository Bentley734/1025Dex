-- Gold's #DEX: the beyond-251 species in the listing, and alternate-form
-- browsing on the entry screen.
--
-- Why this file exists at all, and why none of it is a constant patch:
--
-- On Gen 1 the listing's length is a constant.  src/ui/PokedexMenu.lua:26
-- walks `for n = 1, constants.dexSize or 151`, so src/nationaldex.lua's
-- mod.content.constants:patch("dexSize", ...) is the whole feature.  Neither
-- half of that holds on Gold:
--
--   * The patch does not land where Gen 1's does.  src/mods/Schemas.lua:485
--     routes the `constants` registry to `gen2Constants` on a Gen 2 boot, so
--     the write reaches data.gen2Constants.dexSize instead of
--     data.constants.dexSize.  `dexSize` is not among R.constants.gen2Keys
--     either (Schemas.lua:1866-1882 -- that catalog is the ordered ROM lists
--     plus a fixed handful), so it merges as a mod's own unrecognised key.
--     No error is raised and nothing reads it back: the patch succeeds and
--     means nothing.
--   * Even landing it in data.constants would change nothing, because Gold's
--     screen never reads dexSize.  src/ui/gen2/PokedexMenu.lua sizes its list
--     from the ROM's own dex table: :order() (line 244) and :rebuild() (257)
--     build self.rows out of data.gen2Pokedex.entries, and a species with no
--     entry there is skipped outright (line 264, `if entry then`).
--
-- And data.gen2Pokedex has no registry pointing at it -- it is loaded straight
-- from the ROM cache in src/core/Game2.lua:879 and appears nowhere in
-- Schemas.GEN2.  There is therefore no sanctioned content route to widen
-- Gold's dex, which is what leaves an in-memory patch of Gold's own class as
-- the only seam, the same technique src/dexpage.lua uses on Gen 1.
--
-- The class is reached by its REAL name.  A mod's require is not redirected on
-- a Gold boot -- both generations ship in one archive, so
-- require("src.ui.PokedexMenu") would hand back Gen 1's class here and this
-- file would patch something Gold never draws.  Nothing below chooses its
-- behaviour by probing which methods exist, for the same reason: that probe
-- answers "yes" on the wrong class.  M.install refuses to run at all unless
-- the caller says generation 2.
--
-- Everything above M.install is pure -- no love, no engine module, no mod
-- handle -- so tests exercise it with plain tables.  M.spriteArt, the last of
-- them, holds to that at file scope and reaches for one engine module only
-- from inside the closure it returns, once a draw has actually asked.
--
-- The pic is the second thing Gold's dex resolves for itself and never asks
-- about: see M.spriteArt for why the sprite mod cannot reach this screen, and
-- the drawPic patch for why the art also has to be drawn here rather than
-- handed back to the cart's own draw.
--
-- The third arm is the two actions this mod adds to the entry screen's action
-- bar and the pages behind them: STAT, the Gen 2 counterpart of the Gen 1
-- STATS page, and LVL, the species' evolution line and the moves it learns by
-- levelling.  Its own section below carries the measurements that decide how a
-- fifth and a sixth word fit on a row that was already full, and why the bar
-- scrolls rather than being respelled.
--
-- Why they are BAR SLOTS rather than Gen 1's walk-down-a-strip: on this game
-- UP and DOWN are already spoken for on the entry screen -- they cycle a
-- species' alternate forms, which is the arm above -- and LEFT/RIGHT are the
-- cart's own action bar.  There is no direction left to enter a strip with
-- that is not being taken off something a player already uses.  The bar is
-- the screen's own way of offering another page, so the pages are offered
-- there; the WALKING survives inside the LVL view, where UP and DOWN are free
-- and page it exactly as the Gen 1 strip pages.

local M = {}

-- ------------------------------------------------------------- pure logic

-- Gold's dex box is 18 columns wide and ClearBox(2,11) gives the description
-- three rows per page, stepped by the <NEXT> marker
-- (src/ui/gen2/PokedexMenu.lua:983-996).  This mod's dex text is flowing prose
-- written for Gen 1's own wrapper, so it has to be broken to that shape here
-- or it draws off the right edge of the window.
local LINE_COLS, PAGE_LINES = 18, 3

-- Splits on spaces, and hard-splits a single word longer than the box rather
-- than letting it overhang -- a chemical-formula-length token is rare in dex
-- prose but costs one branch to survive.
function M.wrapLines(text)
  local lines, current = {}, ""
  local function flush()
    if current ~= "" then lines[#lines + 1] = current end
    current = ""
  end
  for word in tostring(text or ""):gmatch("%S+") do
    while #word > LINE_COLS do
      flush()
      lines[#lines + 1] = word:sub(1, LINE_COLS)
      word = word:sub(LINE_COLS + 1)
    end
    local candidate = current == "" and word or (current .. " " .. word)
    if #candidate <= LINE_COLS then
      current = candidate
    else
      flush()
      current = word
    end
  end
  flush()
  return lines
end

-- The entry's two pages, each already <NEXT>-joined the way the ROM's own
-- strings arrive.  Anything past six lines is dropped: the screen has nowhere
-- to put it, and a third page is not a thing Gold's PAGE action can reach.
function M.wrapPages(text)
  local lines = M.wrapLines(text)
  local function page(from)
    local out = {}
    for i = from, math.min(from + PAGE_LINES - 1, #lines) do
      out[#out + 1] = lines[i]
    end
    return table.concat(out, "<NEXT>")
  end
  return page(1), page(1 + PAGE_LINES)
end

-- Both numbers the entry screen prints are PrintNum fields holding the DIGITS
-- rather than a physical measure: the height word is four digits with two in
-- front of the point (204 draws as 2'04") and the weight word five with four
-- in front (150 draws as 15.0 lb).  src/import/RomExtractorGen2.lua:4437-4442
-- is where the cart's own values get that treatment; this mod's records carry
-- feet and inches separately, so the height is folded the same way.
--
-- The weight arrives in the engine's own unit -- tenths of a pound, what a
-- species record's dexEntry.weight has always meant and what
-- src/nationaldex.lua now folds the payload's whole pounds into -- so it is
-- already the digits this field wants and is only rounded.
function M.heightWord(dexEntry)
  local d = type(dexEntry) == "table" and dexEntry or {}
  local feet = type(d.heightFt) == "number" and d.heightFt or 0
  local inches = type(d.heightIn) == "number" and d.heightIn or 0
  return math.floor(feet) * 100 + math.floor(inches)
end

function M.weightWord(dexEntry)
  local d = type(dexEntry) == "table" and dexEntry or {}
  local tenths = type(d.weight) == "number" and d.weight or 0
  return math.floor(tenths + 0.5)
end

-- One synthetic row of data.gen2Pokedex.entries, in the shape the extractor
-- writes (RomExtractorGen2.lua:4450-4454) and the screen reads back:
-- { id, dex, kind, height, weight, text, text2 }.
function M.entryFor(record, description)
  local page1, page2 = M.wrapPages(description)
  local dexEntry = record.dexEntry
  return {
    id = record.id,
    dex = record.dex,
    kind = (type(dexEntry) == "table" and dexEntry.kind) or "",
    height = M.heightWord(dexEntry),
    weight = M.weightWord(dexEntry),
    text = page1,
    text2 = page2,
  }
end

-- Which species in the merged roster the cart's dex has no row for, in dex
-- order.  Deliberately "whatever `entries` is missing" rather than "anything
-- above 251": with the NATIONAL DEX option off this mod registers nothing
-- beyond the cart's own roster, so the same walk adds nothing and Gold's list
-- stays exactly the 251 it shipped with -- the option stays the only control,
-- and no second Gen 2-specific switch has to agree with it.
--
-- Two records are passed over.  A FORM is never a list row: its `dex` is
-- deliberately its BASE species' number (src/nationaldex.lua), so admitting
-- one would put a second claim on a number already in the list.  And a
-- species whose number some existing entry already holds is skipped too --
-- :order() indexes by `entry.dex` (PokedexMenu.lua:251-252), so a collision
-- silently replaces the row already there instead of adding one.
function M.newSpecies(pokemon, entries)
  entries = type(entries) == "table" and entries or {}
  local claimed = {}
  for _, entry in pairs(entries) do
    if type(entry) == "table" and type(entry.dex) == "number" then
      claimed[entry.dex] = true
    end
  end
  local out = {}
  if type(pokemon) ~= "table" then return out end
  for id, record in pairs(pokemon) do
    if type(record) == "table" and record.form == nil
      and type(record.dex) == "number"
      and entries[id] == nil and not claimed[record.dex] then
      claimed[record.dex] = true
      out[#out + 1] = { id = id, record = record }
    end
  end
  -- Sorted by dex number so the listing reads in national order and, more
  -- importantly, so the order is the same on every boot: a `pairs` walk over
  -- a hash part promises nothing, and an unstable list would reshuffle under
  -- a player between sessions with nothing in the save having changed.
  table.sort(out, function(a, b)
    if a.record.dex == b.record.dex then return a.id < b.id end
    return a.record.dex < b.record.dex
  end)
  return out
end

-- --------------------------------------------- how far a page jump travels
--
-- LEFT/RIGHT move Gold's listing by one visible page, and "one page" is the
-- number of rows that listing windows -- VISIBLE_ROWS in
-- src/ui/gen2/PokedexMenu.lua, a file-local the class exports nowhere.
--
-- MEASURED off the class rather than copied here as a literal.  A literal is a
-- second copy of a number this mod does not own, and an engine release that
-- rewindowed the listing (or a widescreen mode that showed more of it) would
-- leave the page jump stepping by the old size with nothing anywhere saying
-- so.  :ensureVisible scrolls exactly far enough to bring `index` into view
-- (PokedexMenu.lua:278-286), so a probe placed far down a long list comes back
-- with scroll = index - VISIBLE_ROWS and the window size falls out of the
-- subtraction.
--
-- The probe is a plain table because that method reads index, scroll and rows
-- and touches nothing else, which is also what keeps this half of the file
-- free of the engine.
local PROBE_ROWS, PROBE_INDEX = 1000, 500

-- The window size, or nil for a class this cannot read -- never a guess.
function M.visibleRows(ensureVisible)
  if type(ensureVisible) ~= "function" then return nil end
  local rows = {}
  for index = 1, PROBE_ROWS do rows[index] = true end
  local probe = { rows = rows, index = PROBE_INDEX, scroll = 0 }
  if not pcall(ensureVisible, probe) then return nil end
  if type(probe.scroll) ~= "number" then return nil end
  local visible = PROBE_INDEX - probe.scroll
  -- A one-row page is a page jump that is not one, and a page as long as the
  -- probe means the method did not do the thing this reads it as having done.
  -- Either answer is "stand down", not "assume seven".
  if visible ~= math.floor(visible) or visible < 2 or visible >= PROBE_INDEX then
    return nil
  end
  return visible
end

-- ------------------------------------------------------- the STATS action
--
-- Gold's entry screen ends in an action bar the player walks with LEFT/RIGHT
-- (src/ui/gen2/PokedexMenu.lua:333-336), and the fifth entry added to it here
-- is this mod's Gen 2 counterpart of the Gen 1 STATS page (src/dexpage.lua).
-- The bar is drawn as ONE string at tile column 1 of row 17, with the arrow
-- parked in the blank cell in FRONT of the selected word (the cart's own
-- ENTRY_ACTION_X = { 1, 6, 11, 15 } are exactly those cells), so a slot costs
-- one cell for the arrow plus one per letter.
--
-- The row is already full, and that is measured rather than assumed.  The
-- entry screen draws under G.translate(-SCX, 0) with SCX = 5
-- (PokedexMenu.lua:903); the font cell is a fixed 8 pixels
-- (src/render/Font.lua's GLYPH advance, which Font.advanceOf returns for every
-- ROM font page); and the cart's " PAGE AREA CRY PRNT" is 19 cells drawn at
-- column 1, so it runs from x = 1*8 - 5 = 3 to x = 155 on a 160-pixel screen.
-- Three pixels spare on the left, five on the right.  A twentieth cell would
-- end at 163, and this screen has no scissor -- PokedexMenu:drawWidescreen
-- scales drawPanel straight into the window -- so it would print OUTSIDE the
-- console frame rather than being clipped.
--
-- 19 cells is therefore the entire budget, and the four words with their four
-- arrow cells already spend all of it: (1+4)+(1+4)+(1+3)+(1+4) = 19.  Adding
-- " STAT" asks for 24.  No abbreviation rescues that -- five slots need five
-- arrow cells, which leaves 14 cells for five words, so even five three-letter
-- labels overflow by one.
--
-- So the bar SCROLLS, which is this screen's own answer to a list that does
-- not fit: the listing beside it shows seven of its rows and moves the window
-- to keep the cursor on screen.  Four slots are shown and the window moves
-- only when the arrow reaches the fifth, so the bar is the cart's own
-- " PAGE AREA CRY PRNT" -- character for character, arrow column for arrow
-- column -- on four of the five positions, and reads " AREA CRY PRNT STAT"
-- only while the new action is selected.
--
-- STAT and not STATS, because BOTH windows have to fit the same 19 cells: the
-- second one measures (1+4)+(1+3)+(1+4)+(1+N) = 15 + N, so the new word gets
-- four letters and a fifth would push it off the screen.
--
-- A SIXTH slot -- LVL, the evolution line and the level-up learnset -- adds a
-- third window and no new problem, because the window is what pays for it.
-- The three the bar can show now measure:
--
--   slots 1-4  " PAGE AREA CRY PRNT"  (1+4)+(1+4)+(1+3)+(1+4) = 19
--   slot  5    " AREA CRY PRNT STAT"  (1+4)+(1+3)+(1+4)+(1+4) = 19
--   slot  6    " CRY PRNT STAT LVL"   (1+3)+(1+4)+(1+4)+(1+3) = 18
--
-- So the widest is still the cart's own row and nothing new can overflow it.
-- The third window being SHORT is the one thing the sixth slot really
-- changed, and it is not cosmetic: the cart clears 18 columns and lets its
-- own 19-cell string cover the nineteenth, so a window that stops at 18 would
-- leave the "T" of the cart's PRNT standing in that last cell.  See
-- drawActionBar, which clears the row's whole width for that reason.
--
-- LVL and not MOVES or LEVEL, for the same measurement: at (1+5) the third
-- window is 20 cells and prints off the side of the console.

-- The engine's own four in its own order (PokedexMenu.lua:51), and ours after
-- them.  That order is load bearing rather than cosmetic: A on slots 1-4 is
-- dispatched by the ENGINE's own branch off this very index, so a bar that
-- listed them in another order would fire the wrong action.
M.BAR_ACTIONS = { "PAGE", "AREA", "CRY", "PRNT", "STAT", "LVL" }
M.STATS_ACTION = "STAT"
M.MOVES_ACTION = "LVL"
-- How many slots are shown at once, the tile column the row starts at, and
-- the budget derived above.
M.BAR_SLOTS = 4
M.BAR_COLUMN = 1
M.BAR_COLUMNS = 19

-- The bar a boot actually gets.  The sixth slot is only offered when the
-- pages behind it can be built at all: src/dexpage.lua's section builders are
-- handed to M.install and a mod file that failed to load leaves them nil, and
-- a slot that opens an empty screen is worse than a slot that is not there.
-- The five-slot bar is exactly what this screen shipped with before LVL
-- existed, so declining costs the new feature and nothing else.
function M.barActions(withMoves)
  if withMoves then return M.BAR_ACTIONS end
  local out = {}
  for _, action in ipairs(M.BAR_ACTIONS) do
    if action ~= M.MOVES_ACTION then out[#out + 1] = action end
  end
  return out
end

-- One step of the arrow, wrapping both ways exactly as the cart's own does
-- (PokedexMenu.lua:334-336) -- only over five entries rather than four.
function M.barStep(index, step, count)
  count = count or #M.BAR_ACTIONS
  if count < 1 then return 1 end
  if type(index) ~= "number" or index < 1 or index > count then index = 1 end
  return ((index - 1 + (step or 0)) % count) + 1
end

-- Which slot the visible window starts at.  Stateless: with five entries and
-- four slots there is exactly one thing a window can do, so remembering where
-- it was last frame would only be a second answer to disagree with this one.
function M.barWindow(selected, slots, count)
  if slots >= count then return 1 end
  if selected <= slots then return 1 end
  return math.min(selected - slots + 1, count - slots + 1)
end

-- The bar for one selection: the single string the screen prints at
-- M.BAR_COLUMN, the column its arrow parks in, and the arrow column of every
-- slot the window shows (nil for one it does not).  `width` is what the row
-- actually costs, so a caller -- or a test -- can hold it against
-- M.BAR_COLUMNS rather than trusting the arithmetic above.
function M.barLayout(selected, actions, slots)
  actions = type(actions) == "table" and actions or M.BAR_ACTIONS
  local count = #actions
  slots = math.min(type(slots) == "number" and slots or M.BAR_SLOTS, count)
  if type(selected) ~= "number" or selected < 1 or selected > count then
    selected = 1
  end
  local first = M.barWindow(selected, slots, count)
  local parts, arrows, column = {}, {}, M.BAR_COLUMN
  for offset = 0, slots - 1 do
    local index = first + offset
    local label = actions[index]
    arrows[index] = column
    -- The leading space IS the arrow's cell; the cart's own string is spelled
    -- the same way and its arrow table is the reason why.
    parts[#parts + 1] = " " .. label
    column = column + 1 + #label
  end
  return {
    text = table.concat(parts),
    arrow = arrows[selected] or M.BAR_COLUMN,
    arrows = arrows,
    first = first,
    width = column - M.BAR_COLUMN,
  }
end

-- ------- what the STATS page reads
--
-- Gold's records spell the split `baseStats.specialAttack` /
-- `specialDefense` (src/import/RomExtractorGen2.lua:786, and src/gen2shape.lua
-- writes the mod's own records that way for the same schema), while this
-- mod's Gen 1 shape carries a collapsed `baseStats.special` with the real
-- split alongside it as `spAttack` / `spDefense`.  Both are accepted, in that
-- order, so this reads a Gold record, a reply from mod.exports.statsBySpecies
-- and a Gen 1-shaped record alike -- and a record that only ever had the
-- collapsed number shows it under both Special rows rather than a blank.
function M.statValues(record)
  local base = (type(record) == "table" and record.baseStats) or {}
  -- Walked with select rather than over a packed table: the first candidate is
  -- routinely nil (a Gold record has no `special`, a Gen 1 one no
  -- `specialAttack`) and ipairs stops dead on the first hole, which reads every
  -- fallback below it as absent.
  local function pick(...)
    for index = 1, select("#", ...) do
      local value = select(index, ...)
      if type(value) == "number" then return value end
    end
    return 0
  end
  local special = base.special
  local top = type(record) == "table" and record or {}
  return {
    hp = pick(base.hp),
    attack = pick(base.attack),
    defense = pick(base.defense),
    specialAttack = pick(base.specialAttack, top.spAttack, special),
    specialDefense = pick(base.specialDefense, top.spDefense, special),
    speed = pick(base.speed),
  }
end

-- The labels are Gold's OWN (src/ui/gen2/SummaryMenu.lua:100), spelled the way
-- the cart's STATUS screen spells them, so a player reading both screens is
-- reading one vocabulary.  HP leads because this is a base-stat block rather
-- than a live mon's, where HP is a bar instead of a row.
M.STAT_ROWS = {
  { "HP", "hp" }, { "ATTACK", "attack" }, { "DEFENSE", "defense" },
  { "SPCL.ATK", "specialAttack" }, { "SPCL.DEF", "specialDefense" },
  { "SPEED", "speed" },
}

-- Ordered { label, value } rows for one record, TOTAL last and equal to the
-- sum of the rows above it.
--
-- Always the six modern stats, with no equivalent of the Gen 1 page's STATS
-- option: Gold's own records are split records, there is no collapsed Special
-- on this game to show instead, and the cart's SUMMARY already prints
-- SPCL.ATK and SPCL.DEF beside every mon in the party.  An option choosing
-- between one Special number and two has nothing to choose here.
function M.statRows(record)
  local values = M.statValues(record)
  local rows, total = {}, 0
  for _, row in ipairs(M.STAT_ROWS) do
    local value = values[row[2]] or 0
    rows[#rows + 1] = { row[1], value }
    total = total + value
  end
  rows[#rows + 1] = { "TOTAL", total }
  return rows
end

-- data/types/names.asm, by way of src/ui/gen2/SummaryMenu.lua:107-110: a type
-- prints as its own id except the two the ROM extractor has to spell around.
-- This mod registers plain ids ("GRASS", "PSYCHIC"), the extractor's own
-- records can carry either, and one table covers both.
M.TYPE_NAMES = { PSYCHIC_TYPE = "PSYCHIC", CURSE_TYPE = "???" }

-- The one or two type names to print for a record.
function M.typeNames(record)
  local types = (type(record) == "table" and record.types) or {}
  local function name(id)
    if type(id) ~= "string" or id == "" then return nil end
    return M.TYPE_NAMES[id] or id:upper()
  end
  local first, second = name(types[1]), name(types[2])
  -- PrintMonTypes' .hide_type_2: a single-typed mon really carries the same
  -- type twice, and the second name is blanked rather than printed twice.
  if second == first then second = nil end
  return first, second
end

-- ------------------------------------------------------- the LVL view
--
-- What the sixth action opens: the species' evolution line, then the moves it
-- learns by levelling, paged in that order.  The same two sections the Gen 1
-- strip shows first (src/dexpage.lua), built by that file's own functions and
-- handed to M.install -- neither the trigger tokens, the indents, the level
-- column nor the "a section with no rows is no page at all" rule is written
-- a second time here.  MACHINE, EGG, TUTOR and OTHER are deliberately not
-- shown: they are 79, and up to 110, rows of a list nobody walks a dex to
-- read, and leaving them out is what keeps this view four pages at its worst
-- instead of twenty.
--
-- Evolutions come FIRST for the reason Gen 1 puts them first: the level-up
-- list is the long one, and a player opening this to see what a mon becomes
-- must not have to page through its moves to get there.
--
-- The geometry is the STATS page's own box -- 16 interior rows by 18 interior
-- columns, every row a bordered box fits on Gold's 18-row screen -- with a
-- title row and the rule under it spent on the header, exactly as the entry
-- screen and the STATS page spend theirs.  That leaves 14 rows for content,
-- against the twelve Gen 1's 144-pixel screen affords, which is why the cut
-- is a parameter of dexpage's paginate rather than its constant.
M.PAGE_INTERIOR_ROWS = 16
M.PAGE_COLUMNS = 18
-- The first and last interior columns: column 0 is the box's own border.
M.PAGE_LEFT = 1
M.PAGE_RIGHT = 18
M.PAGE_TITLE_ROW = 1
M.PAGE_RULE_ROW = 2
M.PAGE_FIRST_ROW = 3
M.PAGE_ROWS = M.PAGE_INTERIOR_ROWS - M.PAGE_FIRST_ROW + 1

-- What a species with neither an evolution family nor a level-up list gets.
--
-- The rule that a section with no rows produces no page still holds -- there
-- is no EVOLUTION page and no LEVEL UP page here -- but the VIEW is reached
-- from a bar slot rather than by walking into it, so it cannot answer by not
-- existing the way Gen 1's strip does.  A player who pressed A is owed a
-- screen that says why it is empty; a bordered box with nothing in it reads
-- as a bug, and refusing to open reads as a broken button.
M.EMPTY_TITLE = "NO DATA"

-- src/dexpage.lua lays its rows out in PIXELS on a screen whose left margin
-- is x = 8 and whose right margin is x = 152; Gold's box runs from tile
-- column 1 to tile column 18.  Those are the same eighteen cells -- the font
-- cell is a fixed 8 pixels on both games -- so a row's column is its x over
-- 8, and every width dexpage already fitted its text to survives the trip
-- unchanged.  Clamped to the box because a deeper indent than that file's
-- LINE_MAX_DEPTH allows must cost glyphs off a name rather than print into
-- the border.
function M.columnOf(x)
  local column = math.floor((type(x) == "number" and x or 0) / 8)
  if column < M.PAGE_LEFT then return M.PAGE_LEFT end
  if column > M.PAGE_RIGHT then return M.PAGE_RIGHT end
  return column
end

-- Where a right-aligned string starts so that it ENDS on the box's last
-- column -- the level beside a move, the trigger beside an evolution, the
-- page counter beside a title.  Pure arithmetic rather than a font
-- measurement, which the Gen 1 page needs and this one does not: every ROM
-- font page advances a fixed 8 pixels, so on a tile grid a string of n
-- glyphs occupies exactly n cells.
function M.rightColumn(text)
  local column = M.PAGE_RIGHT - #tostring(text or "") + 1
  if column < M.PAGE_LEFT then return M.PAGE_LEFT end
  return column
end

-- One page's draws, in Gold's own tile coordinates: { text, x, y } for a
-- string and { cursor = true, x, y } for the mark on the current species,
-- which is a TILE and not a glyph.  Nothing here measures anything or knows
-- what a palette is, so a test asserts what a page would print and where
-- before a screen is involved.
--
-- The mark is the engine's own cursor tile for the same reason the Gen 1 page
-- uses its font's $ED: it is what every menu in the game parks on a chosen
-- row, and it is exactly what this mark means.  Drawn through Chrome's cursor
-- helper rather than printed as text -- Gold's charmap has no ">" either, and
-- Font.encode turns a glyph with no tile into a space.
--
-- `formLabel` is the browsed form's name, and it goes on the RULE row rather
-- than beside the title: the title row's right end already belongs to the
-- page counter, and a base species -- the common case -- has no label at all,
-- so the rule stays unbroken until there is something to say.
function M.pageLayout(page, formLabel)
  local out = {}
  if type(page) ~= "table" then return out end
  out[#out + 1] = { text = page.title or "", x = M.PAGE_LEFT,
                    y = M.PAGE_TITLE_ROW }
  -- Only when the section really does run over: a "1/1" on every short
  -- section would be noise on a screen with none to spare.
  if (page.count or 1) > 1 then
    local counter = tostring(page.index or 1) .. "/" .. tostring(page.count)
    out[#out + 1] = { text = counter, x = M.rightColumn(counter),
                      y = M.PAGE_TITLE_ROW }
  end
  if type(formLabel) == "string" and formLabel ~= "" then
    out[#out + 1] = { text = formLabel, x = M.rightColumn(formLabel),
                      y = M.PAGE_RULE_ROW }
  end
  local y = M.PAGE_FIRST_ROW
  for _, row in ipairs(page.rows or {}) do
    out[#out + 1] = { text = row.text, x = M.columnOf(row.x), y = y }
    if row.mark then
      out[#out + 1] = { cursor = true, x = M.PAGE_LEFT, y = y }
    end
    if row.right then
      out[#out + 1] = { text = row.right, x = M.rightColumn(row.right), y = y }
    end
    y = y + 1
  end
  return out
end

-- The view's pages for one record: its family, then its level-up list.
--
-- `builders` is src/dexpage.lua's own three functions, handed in rather than
-- required, so this file cannot end up with a second opinion about what an
-- evolution line looks like.  `evo` is that record's evolutionsOf reply and
-- `lookup` answers the same for its relatives; `shaped` is its
-- statsBySpecies reply.  All four are optional and a missing one costs its
-- own section and nothing else.
function M.movePages(builders, evo, lookup, shaped)
  local sections = {}
  if type(builders) == "table" then
    if type(builders.evolutionSections) == "function" then
      local ok, list = pcall(builders.evolutionSections, evo, lookup)
      if ok and type(list) == "table" then
        for _, section in ipairs(list) do sections[#sections + 1] = section end
      end
    end
    if type(builders.levelUpSection) == "function" then
      local ok, section = pcall(builders.levelUpSection, shaped)
      if ok and type(section) == "table" then sections[#sections + 1] = section end
    end
  end
  local pages
  if type(builders) == "table" and type(builders.paginate) == "function" then
    local ok, built = pcall(builders.paginate, sections, M.PAGE_ROWS)
    pages = ok and type(built) == "table" and built or nil
  end
  pages = pages or {}
  if #pages == 0 then
    pages[1] = { title = M.EMPTY_TITLE, index = 1, count = 1, rows = {} }
  end
  return pages
end

-- One step through the pages, CLAMPED at both ends.  The same rule the Gen 1
-- strip holds to: the list has a top and a bottom a player can feel, and an
-- UP that silently landed on the last page would read as the screen having
-- closed and reopened.
function M.pageStepTo(page, step, count)
  if type(count) ~= "number" or count < 1 then return 1 end
  local index = (type(page) == "number" and page or 1) + (step or 0)
  if index < 1 then return 1 end
  if index > count then return count end
  return index
end

-- ------------------------------------------- a type label's real id
--
-- The free-text search (src/gen2dexsearch.lua) classifies a term against the
-- DISPLAY names a player reads on screen, and matches it against a species
-- record's own `types`.  Those two are spelled in different alphabets, and
-- for one type of the eighteen the spellings differ: the display name is
-- PSYCHIC while every record -- the cart's own, extracted through the ROM's
-- type table (src/import/RomExtractorGen2.lua:1516), and this mod's
-- generated data alike -- carries the CONSTANT id PSYCHIC_TYPE.  A raw string
-- compare therefore leaves PSYCHIC a guaranteed "not found", the same bug
-- Gold's own cart wheel had before this mod retired it -- fixed here because
-- reconciling the two spellings is not particular to the wheel that first
-- needed it.
--
-- Derived from M.TYPE_NAMES rather than spelled a second time, so the table
-- that prints a type and the table that searches for one cannot drift apart.
M.SEARCH_TYPE_IDS = {}
for id, label in pairs(M.TYPE_NAMES) do M.SEARCH_TYPE_IDS[label] = id end

-- The id a record would carry for a display label.  Every other type is its
-- own id, so an unmapped label is returned unchanged.
function M.searchTypeId(label)
  if type(label) ~= "string" then return label end
  return M.SEARCH_TYPE_IDS[label] or label
end

-- ------------------------------------------------- the sprite mod's art

-- The id of the neighbour this asks, and the export it asks through.
M.SPRITE_MOD = "universal_sprites"

-- Gold's dex draws the CART's pic and offers no seam to change it:
-- src/ui/gen2/PokedexMenu.lua:400 reads record.spriteFront through
-- Assets.image and raises no hook, which is why a sprite mod cannot reach
-- this screen from its own side and why the reach has to be made from here.
--
-- Returns a resolver -- (pokemon, speciesId, data, mon) -> path, trueColor --
-- or nil when there is nothing to ask.  The whole integration is OPTIONAL: no
-- neighbour, a disabled one, or one with no art for a species all answer nil
-- and Gold's own pic is drawn exactly as before.
--
-- `mon` is a LIVE mon table where the caller has one (the party summary does,
-- the dex does not) and nil otherwise.  The registry reads shininess off its
-- DVs (dev/src/registry.lua:139), which is the only way a shiny gets its own
-- art; dev/src/compat_monpic.lua:169 hands the battler's mon over for exactly
-- that reason.  A species with no shiny variant falls through to the plain
-- front, so passing it can only add art, never lose it.
--
-- TWO questions are asked, of two different places, because neither can
-- answer the other's:
--
--   * WHETHER, and WHICH art -- universal_sprites' own `resolveSprite`
--     export (dev/src/api.lua), the same activeRegistry():resolve call its
--     battle path makes.  nil means "we have nothing for this species", and
--     it is the only lookup that can say so: the engine's Sprites.path hands
--     back the vanilla path in that case, which is indistinguishable from a
--     mod answering with art that happens to be the cart's.
--   * HOW to draw it -- the trueColor flag off the engine's own
--     pokemon.sprite seam, which is where the sprite mod publishes its RENDER
--     STYLE decision (a four-shade NATIVE set answers false and MUST keep the
--     GBC palette; full-colour art answers true and must not).  No export
--     carries that, and guessing it wrong is visible either way round: a
--     shaded full-colour pic, or a grey one.
--
-- Resolved lazily and re-asked until it answers, the way
-- dev/src/compat_voxel.lua reaches its own neighbour: mod:find is nil until
-- the other mod has run, and load order between two mods is not ours to pin.
function M.spriteArt(find, formCandidates, sprites)
  if type(find) ~= "function" then return nil end
  local resolve
  local function export()
    if resolve then return resolve end
    local ok, handle = pcall(find, M.SPRITE_MOD)
    if not ok or type(handle) ~= "table" or type(handle.exports) ~= "table" then
      return nil
    end
    local fn = handle.exports.resolveSprite
    if type(fn) ~= "function" then return nil end
    resolve = fn
    return fn
  end

  -- The engine module is required HERE rather than at file scope: this file
  -- is loaded by every boot, Gen 1 included, and the pure half above is
  -- driven by tests that must never pull an engine module in.
  local loadedSprites = sprites
  local function spritesModule()
    if loadedSprites ~= nil then return loadedSprites or nil end
    local ok, value = pcall(require, "src.pokemon.Sprites")
    loadedSprites = (ok and type(value) == "table") and value or false
    return loadedSprites or nil
  end

  return function(pokemon, speciesId, data, mon)
    local fn = export()
    if not fn then return nil, false end
    -- A FORM is asked for as "base species, wearing form X", never by its own
    -- compound id -- the registry keys form art underneath the BASE species,
    -- so CHARIZARD_MEGA_X matches no entry at all.  Same rule, and the same
    -- squashed-spelling retry, as src/dexpage.lua's own art lookup; sharing
    -- that function is what keeps the two games spelling a form alike.
    local record = type(pokemon) == "table" and pokemon[speciesId] or nil
    local lookupId, form, altForm = speciesId, nil, nil
    if type(formCandidates) == "function" then
      local ok, base, id, alt = pcall(formCandidates, record, speciesId)
      if ok and type(base) == "string" then
        lookupId, form, altForm = base, id, alt
      end
    end
    -- ctx.form wins over ctx.mon.form in the registry (registry.lua:37-41), so
    -- the form decided above is still the one asked for even with a mon here.
    local monArg = type(mon) == "table" and mon or nil
    local function ask(formId)
      local ok, path = pcall(fn, { species = lookupId, side = "front",
        kind = "dex", form = formId, mon = monArg })
      if not ok or type(path) ~= "string" or path == "" then return nil end
      return path
    end
    local path = ask(form)
    -- A form miss is silent -- it returns exactly what the base species
    -- alone returns -- so it is detected rather than guessed at.
    if altForm and path == ask(nil) then
      local alt = ask(altForm)
      if alt and alt ~= path then path, form = alt, altForm end
    end
    if not path then return nil, false end

    -- Full colour unless the sprite mod says otherwise.  Its own hook answers
    -- for the ctx it is given, so the form is passed on too and the flag
    -- describes the very art resolved above.  The flag is only read when the
    -- seam answered with a PATH: Sprites.path returns `nil, false` for a
    -- species it cannot resolve at all, and reading that as "shade it" would
    -- crush the art on exactly the species this feature exists for.  An
    -- unreadable answer therefore keeps the default -- art supplied for this
    -- is full colour, and the failure that costs a player something is
    -- shading it, not leaving it alone.
    local trueColor = true
    local module = spritesModule()
    if module and type(module.path) == "function" then
      local ok, resolved, flag = pcall(module.path, data, lookupId, "front",
        { kind = "dex", mon = form and { form = form } or nil })
      if ok and type(resolved) == "string" and flag == false then
        trueColor = false
      end
    end
    return path, trueColor
  end
end

-- ------------------------------ drawing supplied art, shared between screens

-- Gold's #DEX and Gold's party summary both have to fit foreign art into a
-- tile block the cart sized for its own pics, and both have to get it past a
-- palette shader that would ruin it.  The three below are that shared half;
-- src/gen2summary.lua is handed this module and calls them.  They live here
-- rather than in a fourth file because the dex arm is where they were written
-- and where their reasoning is already spelled out -- a second copy is how the
-- two screens would end up disagreeing about what a sprite set looks like.
--
-- None of them touches love at file scope: this file loads on a Gen 1 boot
-- too, and the pure half above is driven by tests with no engine in them.

-- Cached per menu instance and per species, image and all: a menu is reused
-- for every mon the player opens and this is asked once per frame per drawn
-- pic.  `false` is a remembered MISS -- a species the neighbour has nothing
-- for must not be re-asked (and re-file-checked) every frame.  The cache
-- field is this mod's own name on a class it does not own.
function M.artFor(owner, species, resolveArt, pokemon, data, mon)
  if type(resolveArt) ~= "function" or type(owner) ~= "table" then return nil end
  local cache = owner.nationalDexArt
  if not cache then cache = {} owner.nationalDexArt = cache end
  -- Shininess is part of the key, not just of the question: one summary menu
  -- walks a whole party, and a shiny and an ordinary mon of the same species
  -- resolve to different art.  A caller with no mon (the dex) keys on the
  -- species alone, exactly as before.
  local key = species
  if type(mon) == "table" and mon.shiny then key = species .. "\0shiny" end
  local hit = cache[key]
  if hit == nil then
    hit = false
    local ok, path, trueColor = pcall(resolveArt, pokemon, species, data, mon)
    if ok and type(path) == "string" and path ~= "" then
      -- love.graphics.newImage rather than Assets.image: Assets keys its
      -- cache by a path it resolves under the engine's own asset roots, and
      -- this one is absolute and inside another mod's directory.
      local loaded, image = pcall(love.graphics.newImage, path)
      if loaded and image then
        hit = { image = image, trueColor = trueColor and true or false }
      end
    end
    cache[key] = hit
  end
  return hit or nil
end

-- Run `body` with no shader bound, restoring whatever was bound before.
--
-- This is the palette bypass and the reason both draws are reimplemented
-- rather than delegated.  Each screen wraps its pic in GbcPalette.with(colors,
-- body) UNCONDITIONALLY (PokedexMenu.lua:480-484, SummaryMenu.lua:906-910),
-- and that shader is a shade substitution: it recovers a 0..3 shade index from
-- the red channel and replaces it with one of four palette entries, so
-- full-colour art comes back wearing two colours -- a full-colour Totodile
-- rendered red.  The battle screen already has the opt-out neither of them has
-- (src/ui/gen2/BattleState.lua:631 skips the wrap for trueColor art); this is
-- that same opt-out, on the two screens that never got one.
--
-- Captured and restored rather than merely cleared, exactly as GbcPalette.with
-- does: a caller further up may have one bound.
function M.unshaded(body)
  local G = love.graphics
  local previous = G.getShader and G.getShader() or nil
  if G.setShader then G.setShader() end
  local ok, err = pcall(body)
  if G.setShader then G.setShader(previous) end
  if not ok then error(err, 0) end
end

-- Where a w x h image goes inside a `box`-pixel square whose top-left corner
-- is (originX, originY).  Returns scale, x, y -- or nil for an image with no
-- usable dimensions, which the caller reads as "draw the cart's pic instead".
--
-- Fitted to the box, NEVER enlarged.  The cart's own pics are 5x5, 6x6 or 7x7
-- tiles and PadFrontpic centres them; a sprite set's are whatever the art dump
-- ships (96px is ordinary), and the engine's answer to that --
-- battle_sprite_scales -- is a BATTLE registry keyed to a battle box, not to
-- either of these.  So the box itself decides: at 1:1 a 96px pic would cover
-- the column of text beside it on both screens.
--
-- Centred both ways.  The cart's own pics stand on the block's bottom edge
-- (PIC_PAD pads a 5x5 pic downward) so that a small mon shares a ground line
-- with a big one, and this followed that at first -- but a sprite set's art is
-- not drawn to that convention: it arrives already trimmed to its own bounds
-- at whatever aspect the dump ships, so bottom-pinning it leaves a wide, short
-- sprite sitting on the floor with all the empty space above it.  Centring is
-- the honest fit for art whose framing this mod does not control.  Only ever
-- applied to art this mod supplied; the cart's own pics never reach here.
function M.artPlacement(w, h, box, originX, originY)
  if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
    return nil
  end
  local scale = math.min(box / w, box / h, 1)
  return scale, originX + math.floor((box - w * scale) / 2),
    originY + math.floor((box - h * scale) / 2)
end

-- ------------------------------------------------------------ engine patch

-- Required once, guarded exactly the way src/dexpage.lua guards its own
-- imports: a missing or reshaped module means this feature does not install
-- rather than taking the mod load down, and nothing here runs at file scope,
-- so a headless test that only wants the pure half above never touches love.
local function requireGen2Menu()
  local names = { "src.ui.gen2.PokedexMenu", "src.render.GbcPalette",
    "src.world.gen2.Palettes", "src.ui.gen2.Chrome" }
  local mods = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    mods[name] = value
  end
  return mods
end

-- installed guards against a second install patching the patch -- main.lua
-- calls this once, but the class is process-global and a reload would
-- otherwise stack wrappers until the call depth mattered.
local installed = false

-- `generation` is handed in rather than probed here.  See the file banner: the
-- one thing this must never do is decide it is on Gold because a Gold-shaped
-- method answered.  `resolveArt` is M.spriteArt's closure, already holding
-- whatever it needed of the mod API.
-- `scroll` is src/dexscroll.lua, handed in for its GEN2 profile and its rate
-- lookup.  Optional like every other integration here: without it the listing
-- keeps stepping one row per press, which is what Gold shipped.
-- `mod` is the mod handle, taken for exactly one thing: mod.exports is where
-- src/api.lua publishes statsBySpecies, and that is read at DRAW time rather
-- than captured here because api.lua installs after this file does -- a
-- capture taken now would be nil for the life of the process, which is the
-- same reason src/dexpage.lua reads it late.
-- `abilityRows` is src/dexpage.lua's own, handed over rather than copied, so
-- the two games cannot end up disagreeing about which of a species' abilities
-- are shown or in what order -- the same arrangement `buildFormList` already
-- has.  Its M.HIDDEN_MARK comes with it for the same reason: the mark on the
-- hidden row is one decision, not one per screen.
-- `pageBuilders` is the rest of that file's pure half -- evolutionSections,
-- levelUpSection and paginate -- for the LVL view, on the same terms.  Absent
-- or incomplete, the sixth bar slot is not offered at all and says so in the
-- log: an action that opens a screen with nothing on it is worse than one
-- that is not on the bar.
function M.install(generation, buildFormList, resolveArt, scroll, mod,
                   abilityRows, hiddenMark, pageBuilders)
  if generation ~= 2 then return false end
  if installed then return false end
  local mods = requireGen2Menu()
  if not mods then return false end
  local PokedexMenu = mods["src.ui.gen2.PokedexMenu"]
  local GbcPalette = mods["src.render.GbcPalette"]
  local Palettes = mods["src.world.gen2.Palettes"]
  local Chrome = mods["src.ui.gen2.Chrome"]
  if type(PokedexMenu.rebuild) ~= "function"
    or type(PokedexMenu.update) ~= "function"
    or type(PokedexMenu.picFor) ~= "function"
    or type(PokedexMenu.drawPic) ~= "function"
    or type(PokedexMenu.drawPanel) ~= "function"
    or type(PokedexMenu.drawEntry) ~= "function"
    or type(PokedexMenu.cursorVisible) ~= "function"
    or type(PokedexMenu.printNumString) ~= "function"
    or type(PokedexMenu.beginSearch) ~= "function"
    or type(PokedexMenu.drawEntryBody) ~= "function" then
    return false
  end

  -- The dex-page text this mod registered.  On a Gen 2 boot the `text`
  -- registry routes to gen2Text (Schemas.lua:486), so that -- not data.text --
  -- is where a record's dexEntry.text id resolves.
  local function describe(data, record)
    local dexEntry = record.dexEntry
    local id = type(dexEntry) == "table" and dexEntry.text or nil
    if type(id) ~= "string" then return "" end
    local text = data and data.gen2Text and data.gen2Text[id]
    return type(text) == "string" and text or ""
  end

  -- Builds this menu's own view of the dex table, once per instance.  A COPY
  -- rather than a write into data.gen2Pokedex: that table is shared by
  -- reference with src/ui/gen2/Pokegear.lua:1306, and growing the table it
  -- walks is a side effect this feature has no business having.
  local function augment(self)
    if self.nationalDexView then
      self.dex = self.nationalDexView
      return
    end
    local base = self.dex
    if type(base) ~= "table" or type(base.entries) ~= "table" then return end
    local added = M.newSpecies(self.pokemon, base.entries)
    if #added == 0 then return end

    local entries = {}
    for id, entry in pairs(base.entries) do entries[id] = entry end
    local data = self.game and self.game.data
    local ids = {}
    for _, item in ipairs(added) do
      entries[item.id] = M.entryFor(item.record, describe(data, item.record))
      ids[#ids + 1] = item.id
    end

    local view = {}
    for key, value in pairs(base) do view[key] = value end
    view.entries = entries
    -- Gold opens in NEW (Johto) order and offers A-Z beside it, and :order()
    -- returns those precomputed lists untouched when they exist
    -- (PokedexMenu.lua:248-249).  Widening only `entries` would therefore fix
    -- nothing a player actually sees on the screen the dex opens on.  The new
    -- ids are APPENDED to the cart's own lists rather than merged into them:
    -- the ROM's ordering is not ours to rearrange, and a player who knows
    -- where MEGANIUM sits in the Johto list should still find it there.
    view.newOrder = M.appended(base.newOrder, ids)
    view.alphabeticalOrder = M.appended(base.alphabeticalOrder,
      M.byName(self.pokemon, ids))
    self.nationalDexView = view
    self.dex = view
  end

  local originalRebuild = PokedexMenu.rebuild
  function PokedexMenu:rebuild()
    -- Before, not after: rebuild reads self.dex to build the rows, and every
    -- mode change comes back through here.
    pcall(augment, self)
    originalRebuild(self)
  end

  -- OLD (national) mode has no precomputed list: :order() builds one by
  -- indexing each species at its own dex NUMBER (PokedexMenu.lua:251-252),
  -- which leaves a hole wherever a number has no species -- and :rebuild()
  -- walks that result with ipairs, which stops dead at the first hole.  The
  -- cart never exposed this because its own 251 numbers are contiguous.  A
  -- national roster is only contiguous while every species registers, and
  -- src/nationaldex.lua guards each registration individually precisely
  -- because one can fail; a single skipped species would otherwise truncate
  -- the entire listing from that number on.  Compacting is a no-op on a
  -- gapless list, so this costs the healthy case nothing.
  local originalOrder = PokedexMenu.order
  function PokedexMenu:order()
    local list = originalOrder(self)
    if type(list) ~= "table" then return list end
    local highest = 0
    for index in pairs(list) do
      if type(index) == "number" and index > highest then highest = index end
    end
    local compact, count = {}, 0
    for index = 1, highest do
      if list[index] ~= nil then
        count = count + 1
        compact[count] = list[index]
      end
    end
    return compact
  end

  -- ------- the SEARCH screen
  --
  -- Retired here: the cart's two type wheels only ever expressed what
  -- src/gen2dexsearch.lua's free-text field now says in passing --
  -- fire+flying is what TYPE1/TYPE2 meant, and every other term (a name, a
  -- move, an ability) is something the wheels could not reach at all.  That
  -- file installs its own updateSearch/drawSearch/beginSearch and is wired
  -- in from main.lua; this file's part is just the hand-off below, at the
  -- exact point the cart's own update() has already decided the view is
  -- "search".

  -- ------- alternate forms
  --
  -- NOT on LEFT/RIGHT, which is the one place this deliberately parts company
  -- with the Gen 1 page (src/dexpage.lua).  On Gold those two keys are
  -- already taken: they walk the arrow across PAGE / AREA / CRY / PRNT
  -- (PokedexMenu.lua:333-336), and the comment directly above that code
  -- records what happens when something else claims them -- "quietly makes
  -- three of the four actions unreachable -- AREA among them".  Rebinding
  -- them here would re-break the cart's own entry screen, and would do it
  -- only for the species that have forms, which is the worst version of it.
  -- UP/DOWN are read by no branch of the entry view, so they are free, and
  -- they keep the browsing bidirectional.
  local function formsFor(self, species)
    if self.formBase == species then return self.formList end
    local list = { species }
    if type(buildFormList) == "function" then
      local ok, built = pcall(buildFormList, self.pokemon, species)
      if ok and type(built) == "table" and #built > 0 then list = built end
    end
    self.formBase = species
    self.formList = list
    self.formIndex = 1
    self.formId = species
    return list
  end

  local function cycleForm(self, step)
    local row = self:current()
    if not row then return end
    local list = formsFor(self, row.species)
    if #list < 2 then return end
    self.formIndex = ((self.formIndex - 1 + step) % #list) + 1
    self.formId = list[self.formIndex]
  end

  -- ------- hold UP/DOWN to fast-scroll the listing, LEFT/RIGHT to page it
  --
  -- Gold reads UP and DOWN as EDGES only (src/ui/gen2/PokedexMenu.lua:373-380
  -- -- `input:wasPressed`, one row, then `return`), so holding one moves the
  -- cursor once and stops.  That is the whole of the cart's listing input on
  -- those keys; there is no held-frame counter on this class to lean on the
  -- way the Gen 1 list has one, so the counter is kept here, under this mod's
  -- own name on a class it does not own.
  --
  -- LEFT and RIGHT it reads NOWHERE on this view: that same branch runs B,
  -- SELECT, START, UP, DOWN and A and then falls off the end, and the only
  -- LEFT/RIGHT this class binds at all are the entry screen's action bar
  -- (:333-336), the AREA map and the UNOWN screen -- none of which is the
  -- listing.  So the page jump takes two free keys rather than a neighbour's,
  -- and it is bound on the LIST view alone: the entry bar below still walks on
  -- exactly the keys it walked on before.
  --
  -- The row profile is src/dexscroll.lua's GEN2 and the page profile its PAGE,
  -- the same table Gen 1's page jump runs on -- one gesture, one clock.
  local profile = type(scroll) == "table" and scroll.GEN2 or nil
  local pageProfile = type(scroll) == "table" and scroll.PAGE or nil
  local rateFor = type(scroll) == "table" and scroll.rate or nil
  local delayFor = type(scroll) == "table" and scroll.delay or nil

  -- One page is however many rows this class windows, measured off the class
  -- itself.  A measurement that fails takes the page jump down with it --
  -- LEFT/RIGHT go back to doing what the cart does with them here, which is
  -- nothing -- and says so, because a feature that is silently present on one
  -- game and absent on the other is the version of this that costs a player an
  -- evening working out which.
  local pageRows = nil
  if pageProfile and rateFor and delayFor then
    pageRows = M.visibleRows(PokedexMenu.ensureVisible)
    if not pageRows and mod and mod.log then
      mod.log:info("Gold's #DEX listing does not report how many rows it "
        .. "shows -- LEFT/RIGHT stay unbound there rather than jumping by a "
        .. "page size this mod guessed at")
    end
  end

  -- One repeat step, with the SAME wrap the engine's own branch does -- up on
  -- the first row lands on the last and down on the last returns to the first.
  -- Repeated rather than called: those two lines sit inside the update branch
  -- and this class exposes no cursor helper, and a held direction that stopped
  -- dead at an end while a tapped one wrapped would be the two disagreeing
  -- about the same list.
  local function holdStep(self, dir)
    local rows = self.rows
    if type(rows) ~= "table" or #rows == 0 then return end
    if dir == "up" then
      self.index = self.index > 1 and self.index - 1 or #rows
    else
      self.index = self.index < #rows and self.index + 1 or 1
    end
    self:ensureVisible()
  end

  -- One page, CLAMPED at both ends rather than wrapped.
  --
  -- The rows above wrap because the cart's own UP/DOWN wrap and a held
  -- direction disagreeing with a tapped one would be worse than no hold at
  -- all.  This jump has no cart behaviour to match, so what it copies is Gen
  -- 1's, which clamps: src/ui/ListMenu.lua:95-98 wraps only for a list whose
  -- owner asked for it and the dex list does not (src/ui/PokedexMenu.lua:49).
  -- Held at six pages a second a wrapping jump would cycle 1025 rows forever
  -- and never arrive; clamped, holding RIGHT reaches the last page and waits
  -- there, which is what a player holding it is asking for.
  local function pageStep(self, step)
    local rows = self.rows
    if type(rows) ~= "table" or #rows == 0 then return end
    local index = (self.index or 1) + step * pageRows
    self.index = math.max(1, math.min(#rows, index))
    self:ensureVisible()
  end

  local function clearHold(self)
    self.nationalDexHoldDir, self.nationalDexHoldFrames = nil, 0
  end

  local function listHold(self)
    local input = self.game and self.game.input
    if not input or type(input.isDown) ~= "function" then return clearHold(self) end
    -- B closed the listing on this very frame.  A direction still under the
    -- player's thumb must not walk the cursor on the way out.
    if input:wasPressed("b") then return clearHold(self) end
    if input:wasPressed("up") then
      self.nationalDexHoldDir, self.nationalDexHoldFrames = "up", 0
    elseif input:wasPressed("down") then
      self.nationalDexHoldDir, self.nationalDexHoldFrames = "down", 0
    elseif pageRows and input:wasPressed("left") then
      -- Unlike UP/DOWN, the FIRST step of a page jump is taken here too: the
      -- engine's own branch has already run and read neither key, so nothing
      -- else on this frame is going to move the cursor.
      pageStep(self, -1)
      self.nationalDexHoldDir, self.nationalDexHoldFrames = "left", 0
    elseif pageRows and input:wasPressed("right") then
      pageStep(self, 1)
      self.nationalDexHoldDir, self.nationalDexHoldFrames = "right", 0
    end
    local dir = self.nationalDexHoldDir
    if not (dir and input:isDown(dir)) then return clearHold(self) end
    -- WHICH profile depends on what is held, exactly as the Gen 1 arm decides
    -- it (src/dexscroll.lua's accelerate): a page carries seven rows, so it
    -- cannot be timed by the clock that carries one.
    local paging = dir == "left" or dir == "right"
    local held = paging and pageProfile or profile
    -- The same arithmetic the Gen 1 list already runs
    -- (src/ui/ListMenu.lua:186-189): nothing repeats until `delay` frames have
    -- passed, and one step goes by every `rate` frames after that.  The rate is
    -- asked for the count being tested, so a tier boundary lands on the frame
    -- it names rather than one after it.
    local frames = (self.nationalDexHoldFrames or 0) + 1
    self.nationalDexHoldFrames = frames
    local afterDelay = frames - delayFor(held)
    if afterDelay >= 0 and afterDelay % rateFor(held, frames) == 0 then
      if paging then
        pageStep(self, dir == "left" and -1 or 1)
      else
        holdStep(self, dir)
      end
    end
  end

  -- ------- the fifth and sixth actions, and the pages behind them
  --
  -- `view` is this mod's own name on a field the class owns, for the same
  -- reason every cache field here is: the engine's own update and drawPanel
  -- both fall through to the LISTING for a view they do not know, so an
  -- unrecognised value has to be intercepted before either of them sees it --
  -- and a plain word like "stats" is a name a later engine release could
  -- reasonably want for something else.
  local STATS_VIEW = "nationalDexStats"
  local MOVES_VIEW = "nationalDexMoves"

  -- Whether the sixth slot is offered at all, decided ONCE here and read back
  -- off the module's own builder table rather than assumed.  A partial table
  -- counts as no table: every one of the three is needed to produce a page,
  -- and half a feature that opens a blank box is the version of this a player
  -- would have to file a bug about.
  local builders = nil
  if type(pageBuilders) == "table"
    and type(pageBuilders.evolutionSections) == "function"
    and type(pageBuilders.levelUpSection) == "function"
    and type(pageBuilders.paginate) == "function" then
    builders = pageBuilders
  elseif mod and mod.log then
    mod.log:info("Gold's #DEX entry keeps its five actions -- the evolution "
      .. "and level-up page builders this mod hands to its Gen 2 screen did "
      .. "not arrive, so the LVL action is not on the bar rather than being "
      .. "there and opening nothing")
  end

  local ACTIONS = M.barActions(builders ~= nil)
  local ACTION_COUNT = #ACTIONS
  -- Which slot is which, off the list actually installed rather than off a
  -- literal: with the sixth slot declined the fifth is still the last, and a
  -- hard-coded 6 would then dispatch a slot the bar does not have.
  local STATS_SLOT, MOVES_SLOT
  for index, action in ipairs(ACTIONS) do
    if action == M.STATS_ACTION then STATS_SLOT = index end
    if action == M.MOVES_ACTION then MOVES_SLOT = index end
  end

  -- The stats page's own keys, which are the AREA page's
  -- (PokedexMenu:updateArea, :818-824): A or B goes back to the entry screen.
  -- UP/DOWN keep cycling forms here too -- comparing a form's numbers against
  -- its base species' is most of what this page is for, and being sent back
  -- to the entry screen to change form and then in again would make that
  -- comparison cost four presses instead of one.
  local function statsInput(self)
    local input = self.game and self.game.input
    if not input then return end
    if input:wasPressed("a") or input:wasPressed("b") then
      self.view = "entry"
      return
    end
    if input:wasPressed("up") then
      cycleForm(self, -1)
    elseif input:wasPressed("down") then
      cycleForm(self, 1)
    end
  end

  -- The pages the LVL view is showing, for whatever record is on screen.
  -- Declared here and assigned beside the cache that builds them: the input
  -- below has to clamp against how many there are, and it belongs next to the
  -- other views' input rather than three hundred lines away from it.
  local movePagesFor

  -- The LVL view's keys.
  --
  -- A and B leave, exactly as they do on the STATS page and the cart's own
  -- AREA map -- one way out of every page this mod adds.
  --
  -- UP/DOWN page, which is the Gen 1 strip's own gesture (src/dexpage.lua)
  -- and is free HERE even though it is not free on the entry screen: this is
  -- a view of its own, the branch below owns its input outright, and the
  -- entry screen's form cycling is not reached from it.  Nothing a player
  -- already uses is rebound -- UP/DOWN on the entry screen still cycle forms,
  -- and the only reason they can page here is that this screen did not exist
  -- until now.
  --
  -- LEFT/RIGHT cycle forms, which is the Gen 1 page's own binding for them
  -- and leaves the whole view following the selection: the pages are built
  -- from the SHOWN record, so a mega's own family and its own level-up list
  -- are what a player lands on.  There is no action bar on this page for them
  -- to walk instead -- the bar belongs to the entry screen, and A or B is
  -- what gets back to it.
  --
  -- The page index is CLAMPED after a form step rather than reset: the
  -- sections come in the same order for every form, so a step sideways lands
  -- on the same kind of page, and resetting would punish exactly the
  -- comparison LEFT/RIGHT is for.  A form with fewer pages than its
  -- neighbour is what the clamp is for.
  local function movesInput(self)
    local input = self.game and self.game.input
    if not input then return end
    if input:wasPressed("a") or input:wasPressed("b") then
      self.view = "entry"
      return
    end
    local count = #movePagesFor(self)
    if input:wasPressed("down") then
      self.movePage = M.pageStepTo(self.movePage, 1, count)
    elseif input:wasPressed("up") then
      self.movePage = M.pageStepTo(self.movePage, -1, count)
    elseif input:wasPressed("left") or input:wasPressed("right") then
      cycleForm(self, input:wasPressed("left") and -1 or 1)
      self.movePage = M.pageStepTo(self.movePage, 0, #movePagesFor(self))
    end
  end

  local originalUpdate = PokedexMenu.update
  function PokedexMenu:update(dt)
    -- Owned outright rather than wrapped: the engine's update has no branch
    -- for this view and would run the LISTING's keys under it -- B would close
    -- the whole dex and A would reopen an entry.
    if self.view == STATS_VIEW or self.view == MOVES_VIEW then
      -- The entry bar's arrow blink is counted at the top of the engine's own
      -- update (:310) so it keeps ticking on a frame with no input; a frame
      -- spent on this page must not stall it, or the arrow comes back frozen.
      self.entryBlink = (self.entryBlink or 0) + 1
      pcall(self.view == STATS_VIEW and statsInput or movesInput, self)
      return
    end
    local entryView = self.view == "entry" and not self.newEntry
    local up, down = false, false
    local left, right, aPressed = false, false, false
    if entryView then
      pcall(function()
        local input = self.game and self.game.input
        if not input then return end
        up, down = input:wasPressed("up"), input:wasPressed("down")
        left, right = input:wasPressed("left"), input:wasPressed("right")
        aPressed = input:wasPressed("a")
      end)
    end
    -- The slot the arrow was on BEFORE the engine walked it over its own four.
    local wasAction = self.entryAction
    local wasView = self.view
    originalUpdate(self, dt)
    -- The bar the player is walking has six entries and the engine's has
    -- four, so its answer is recomputed from the slot the arrow started on
    -- rather than nudged afterwards: from PRNT its RIGHT wraps to PAGE, and
    -- there is no correction that turns that into "on to STAT" without
    -- knowing where the arrow was.  The engine's own elseif chain is mirrored
    -- exactly -- a frame with RIGHT down never reaches the A branch -- so a
    -- press cannot both move the arrow and fire what it moved off.
    if entryView then
      if right or left then
        self.entryAction = M.barStep(wasAction, right and 1 or -1, ACTION_COUNT)
      elseif aPressed and wasAction == STATS_SLOT then
        -- The engine's own A branch already ran and did nothing at all: its
        -- ENTRY_ACTIONS has four entries, so ENTRY_ACTIONS[5] is nil and every
        -- arm of its dispatch was skipped.  This is the whole of the action.
        self.view = STATS_VIEW
      elseif aPressed and MOVES_SLOT and wasAction == MOVES_SLOT then
        -- Always from the FIRST page.  The player asked to see this species'
        -- pages, not to resume wherever the last species' were left, and the
        -- first page is the evolution line whenever there is one.
        self.view = MOVES_VIEW
        self.movePage = 1
      end
    end
    -- Opening an entry always starts on the base species.  Without this the
    -- selection is sticky across the whole session: browse to MEGA VENUSAUR,
    -- back out, and every later visit to BULBASAUR would open already showing
    -- the mega.  Gen 1's page gets this for free by rebuilding its form state
    -- in the constructor (src/dexpage.lua) -- Gold reuses one menu instance
    -- for every species, so the reset has to be explicit.
    if self.view == "entry" and wasView ~= "entry" then
      self.formBase, self.formList, self.formIndex, self.formId = nil, nil, 1, nil
    end
    -- START just opened the search screen.  gen2dexsearch.lua's own
    -- beginSearch (once main.lua has wired it in) builds the free-text
    -- screen's rows and vocabulary from the LIVE listing, and it has to run
    -- exactly once here rather than inside updateSearch itself -- every frame
    -- the screen stayed open would rebuild the listing behind the query the
    -- player is mid-typing.  Gated on the class-level marker gen2dexsearch.lua
    -- sets once it has actually taken over beginSearch: if it never installed
    -- (a mod file missing, or main.lua not wired yet -- see Task 11) this
    -- stays silent and the cart's own SEARCH screen behaves exactly as it did
    -- before this file ever patched it.
    if self.view == "search" and wasView ~= "search"
        and self.nationalDexSearchInstalled
        and type(self.beginSearch) == "function" then
      if not pcall(self.beginSearch, self) and mod and mod.log then
        mod.log:info("Gold's #DEX search screen failed to open -- the "
          .. "listing is unchanged and the screen stays on the cart's own "
          .. "SEARCH view")
      end
    end
    -- After the engine's own pass, and only while the entry screen is still
    -- the live view -- so a press that closed the page cannot also move a
    -- form underneath it.
    if (up or down) and self.view == "entry" then
      pcall(cycleForm, self, up and -1 or 1)
    end
    -- Only while the listing is the live view.  A opening an entry, SELECT
    -- opening OPTION and START opening SEARCH all leave on a frame where a
    -- direction may still be held, and the else arm is what makes the hold
    -- die there rather than resuming when the player comes back -- returning
    -- to a listing has to feel like arriving at it, not like walking into a
    -- scroll already in progress.
    --
    -- The SEARCH results are this same view: Pokedex_SearchForMons replaces
    -- self.rows and sets the view back to "list"
    -- (src/ui/gen2/PokedexMenu.lua:1352-1356), so a result set long enough to
    -- want fast-scrolling gets it with no second case here.
    if profile and rateFor and delayFor and self.view == "list" then
      pcall(listHold, self)
    else
      clearHold(self)
    end
  end

  -- Which record's art the screen is actually showing: the browsed form while
  -- one is selected, the row's own species otherwise.  Both halves below read
  -- it, so the pic and the palette decision can never disagree about what is
  -- on screen.
  local function shownSpecies(self, species)
    local formId = self.formId
    if formId and formId ~= species and self.formBase == species then
      return formId
    end
    return species
  end

  -- The selected form's own art, resolved by asking the engine's own lookup
  -- for the FORM's record -- which reuses its path cache and its Unown
  -- special case rather than reimplementing either.  Falls back to the base
  -- species whenever the form has no art of its own, so a form this mod
  -- registered without a picture shows its base rather than a blank box.
  local originalPicFor = PokedexMenu.picFor
  function PokedexMenu:picFor(species)
    local shown = shownSpecies(self, species)
    if shown ~= species then
      local ok, image = pcall(originalPicFor, self, shown)
      if ok and image then return image end
    end
    return originalPicFor(self, species)
  end

  -- ------- the sprite mod's art on Gold's dex
  --
  -- The lookup, the palette bypass and the fit are M.artFor / M.unshaded /
  -- M.artPlacement above, shared with the party summary arm.
  local function modArt(self, species)
    return M.artFor(self, species, resolveArt, self.pokemon,
      self.game and self.game.data)
  end

  -- The 7x7 tile block Pokedex_PlaceFrontpicTopLeftCorner lays for the pic,
  -- in pixels (PokedexMenu.lua:436-452).
  local PIC_BOX = 7 * 8

  -- Gold's own drawPic, for one image it cannot resolve itself.  The blank
  -- square is kept because the art is fitted INSIDE the block rather than
  -- filling it, and that fill (PokedexMenu.lua:470-472) is what puts a solid
  -- colour behind the pic instead of the panel; the palette it reads is
  -- picked the same way for the same reason (:459-467) -- the listing draws
  -- every mon through the question-mark palette, the entry screen through the
  -- species' own two colours.
  local function drawModPic(self, row, art, tx, ty, ownColors)
    local G = love.graphics
    local colors
    if ownColors then
      colors = self.palettes and Palettes.monColors(self.palettes, row.species)
    else
      colors = self.gfx and self.gfx.questionMarkPalette
    end
    -- The backdrop follows the same rule as the draw below: palette art keeps
    -- the cart's coloured square, full-colour art does not.  That square is
    -- lifted from the palette's own lightest entry, which behind a two-shade
    -- ROM pic reads as the pic's background and behind a full-colour sprite
    -- reads as a coloured card it has been placed on -- Totodile on a green
    -- tile.  Black instead, which is what the rest of the list panel already
    -- is, so the art sits on the panel rather than on a swatch.
    if art.trueColor then
      G.setColor(0, 0, 0, 1)
    else
      local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
      G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
    end
    G.rectangle("fill", tx * 8, ty * 8, PIC_BOX, PIC_BOX)

    local image = art.image
    local scale, x, y = M.artPlacement(image:getWidth(), image:getHeight(),
      PIC_BOX, tx * 8, ty * 8)
    if not scale then return end
    G.setColor(1, 1, 1, 1)
    local function body() G.draw(image, x, y, 0, scale, scale) end
    -- A four-shade NATIVE set is art the palette is RIGHT for, and it comes
    -- through this same seam, so the flag decides rather than the source.
    if art.trueColor or not (colors and GbcPalette.available()) then
      M.unshaded(body)
    else
      GbcPalette.with(colors, body)
    end
  end

  local originalDrawPic = PokedexMenu.drawPic
  function PokedexMenu:drawPic(row, tx, ty, ownColors)
    -- An unseen species is the question mark, never a mon's art -- the dex
    -- must not leak what the player has not met.
    local art = row and row.seen
      and modArt(self, shownSpecies(self, row.species)) or nil
    if not art then return originalDrawPic(self, row, tx, ty, ownColors) end
    -- A failure here falls back to the cart's own pic rather than leaving the
    -- block empty: this is an optional integration and the screen behind it
    -- works without it.
    if pcall(drawModPic, self, row, art, tx, ty, ownColors) then return end
    originalDrawPic(self, row, tx, ty, ownColors)
  end

  -- The browsed form's label, prettied, or nil when the row's own species is
  -- what is on screen.  One function because two screens print it -- the entry
  -- page in the category slot and the stats page under the name -- and a
  -- second copy is how they would end up spelling MEGA X two ways.
  local function formLabel(self, species)
    local formId = self.formId
    if not (formId and species and formId ~= species
      and self.formBase == species) then
      return nil
    end
    local record = self.pokemon and self.pokemon[formId]
    local label = type(record) == "table" and record.form or nil
    if type(label) ~= "string" then return nil end
    return (label:gsub("_", " "))
  end

  -- ------- the action bar, redrawn over the cart's own
  --
  -- The engine prints its four-word row and parks its arrow with
  -- ENTRY_ACTION_X, which has four entries -- so on the fifth slot its arrow
  -- falls back to column 1 and its string never mentions STAT.  Rather than
  -- reimplement the whole of drawEntryBody to change one row, the row is
  -- blanked and reprinted: exactly the ClearBox the cart itself lays there
  -- (PokedexMenu.lua:924, 18 columns from column 1) and then this bar's own
  -- window over it.  On the four slots the cart already had, what lands is
  -- character-for-character what it drew -- see M.barLayout's own note.
  --
  -- Column 0's end cap is left alone: the blank starts at column 1, which is
  -- where the cart's does, and the cap is part of the frame rather than of the
  -- bar.
  local BAR_ROW = 17
  -- One layout per slot, built on first use.  There are six of them and the
  -- bar is laid out once per frame the entry screen is up, so this is the
  -- difference between six tables for the life of the process and six a
  -- frame for as long as a player reads a dex entry.
  local barCache = {}
  local function barFor(slot)
    local key = type(slot) == "number" and slot or 0
    local layout = barCache[key]
    if not layout then
      layout = M.barLayout(slot, ACTIONS, M.BAR_SLOTS)
      barCache[key] = layout
    end
    return layout
  end

  local function drawActionBar(self)
    local layout = barFor(self.entryAction)
    -- The row's WHOLE width, and one column wider than the ClearBox the cart
    -- lays here (PokedexMenu.lua:924, 18 columns from column 1).  The cart can
    -- stop at 18 because its own 19-cell string covers the nineteenth cell
    -- itself -- Chrome.printThrough paints its own ground behind every string
    -- -- and so could this bar while its every window was also 19 cells.  The
    -- sixth slot's window is 18 (see M.BAR_ACTIONS' measurements), so that
    -- last cell now has to be cleared rather than covered, or the "T" the
    -- cart's own PRNT left there stands beside this mod's shorter row.
    --
    -- _NewPokedexEntry's own ByteFill of this row is 19 wide
    -- (pokedex.asm:2540-2545), so 19 is the cart's own answer to "the whole
    -- bar row" rather than a column borrowed from somewhere else.
    self:blank(M.BAR_COLUMN, BAR_ROW, M.BAR_COLUMNS, 1)
    self:text(layout.text, M.BAR_COLUMN, BAR_ROW)
    -- Blinking and drawn through the dex's inverted palette, because that is
    -- what the cart's arrow does on this bar (PokedexMenu.lua:944-947) and a
    -- fifth entry that marked itself differently would read as a different
    -- kind of thing.
    if self:cursorVisible() then
      Chrome.cursorThrough(layout.arrow, BAR_ROW,
        self.gfx and self.gfx.palette, true)
    end
  end

  -- A form's label goes where the base species' category sits.  Nothing else
  -- on the page moves: No., name, height, weight and the description stay the
  -- BASE species' own, because `entry` here is still the row's own dex record
  -- and this only ever replaces one string on a copy of it.  That is the same
  -- rule src/dexpage.lua holds to -- a form must never print its synthetic
  -- `dex` key -- and it holds here by construction, since nothing in this
  -- function can reach a form record's `dex` at all.
  local originalBody = PokedexMenu.drawEntryBody
  function PokedexMenu:drawEntryBody(row, entry)
    local label = row and formLabel(self, row.species) or nil
    if label and type(entry) == "table" then
      local copy = {}
      for key, value in pairs(entry) do copy[key] = value end
      copy.kind = label
      entry = copy
    end
    originalBody(self, row, entry)
    -- After, so it lands over the cart's own row.  _NewPokedexEntry fills that
    -- row away and shows no bar at all (:926-927), and neither does this.
    if not self.newEntry then pcall(drawActionBar, self) end
  end

  -- ------- the STATS page, and the LVL view's pages beside it
  --
  -- Every evolution record either page has asked for, by id, `false` standing
  -- for "asked, there is nothing".  Keyed by id rather than held with the
  -- species being shown, because drawing ONE species' family reads its
  -- relatives' records too, and a relative is very often the next species the
  -- player steps to -- Bulbasaur, Ivysaur and Venusaur cost three lookups
  -- between them rather than nine.  evolutionsOf deep-copies a whole record
  -- per call, which is why the second ask has to be a table read.  The same
  -- arrangement, for the same reason, as src/dexpage.lua's own.
  local chains = {}
  local function evolutionFor(id)
    if type(id) ~= "string" then return nil end
    local found = chains[id]
    if found == nil then
      found = false
      local ask = mod and mod.exports and mod.exports.evolutionsOf
      if type(ask) == "function" then
        local ok, reply = pcall(ask, id)
        if ok and type(reply) == "table" then found = reply end
      end
      chains[id] = found
    end
    return found or nil
  end

  -- Everything the page prints for one species or form, built once and kept:
  -- statsBySpecies deep-copies a whole record and its extras, which is the
  -- right price for a cross-mod call and far too much to pay every frame for
  -- an answer that cannot change while the game runs.  Cached on the module's
  -- own closure rather than per menu instance for the same reason the answer
  -- is stable -- species data is not a property of a screen.  A species the
  -- API has nothing for is remembered too, as the page built from what the
  -- menu already holds, so a miss costs one call rather than one per frame.
  --
  -- Asked for by the SHOWN record's id, form and base species alike, so a
  -- browsed form's own numbers and its own ability are what appear.  The reply
  -- is also the fallback's alternative rather than its replacement: with no
  -- API to ask -- src/api.lua failed to load, or a species it has nothing for
  -- -- the registered record on the menu itself still carries base stats and
  -- typing, and only the ability rows are lost.
  local pages = {}
  local function statsPage(self, id)
    if type(id) ~= "string" then return nil end
    local page = pages[id]
    if page == nil then
      local reply
      local lookup = mod and mod.exports and mod.exports.statsBySpecies
      if type(lookup) == "function" then
        local ok, answer = pcall(lookup, id)
        if ok and type(answer) == "table" then reply = answer end
      end
      local record = reply or (self.pokemon and self.pokemon[id]) or nil
      local abilities
      if reply and type(abilityRows) == "function" then
        local ok, list = pcall(abilityRows, reply.abilities)
        if ok and type(list) == "table" and #list > 0 then abilities = list end
      end
      local first, second = M.typeNames(record)
      page = { rows = M.statRows(record), type1 = first, type2 = second,
               abilities = abilities }
      -- The LVL view's pages come out of the SAME reply, in the same entry:
      -- the level-up list and the abilities are two fields of one deep copy,
      -- and asking statsBySpecies twice would pay for that copy twice.  They
      -- are laid out the moment either page is first built rather than when
      -- the player walks onto them -- four pages at the very worst is a few
      -- hundred table stores, once, against holding the copied record alive
      -- for every species browsed in a session.
      --
      -- Asked for by the record's OWN id, base species and form alike.  A
      -- form with no line of its own answers nil and gets no evolution page:
      -- Mega Charizard X does not evolve from Charmeleon at level 36, and
      -- falling back to the base species' chain here would say it does.
      if builders then
        page.movePages = M.movePages(builders, evolutionFor(id), evolutionFor,
          reply)
      else
        page.movePages = {}
      end
      pages[id] = page
    end
    return page
  end

  -- The LVL view's pages for whatever record is on screen -- the browsed form
  -- while one is selected, so the family and the learnset follow the
  -- selection exactly as the stats and the abilities beside them do.
  -- Assigned rather than declared: the name was reserved above, beside the
  -- input that walks these pages.
  movePagesFor = function(self)
    local row = self:current()
    if not row then return {} end
    local page = statsPage(self, shownSpecies(self, row.species))
    return (page and page.movePages) or {}
  end

  -- The page's furniture, in Gold's own units.  Pokedex_PlaceBorder is b
  -- interior rows by c interior columns; the entry screen's box is 15 by 18
  -- and leaves the screen's last row for its action bar.  This page has no
  -- action bar, so it takes that row: 16 interior rows, which is every row a
  -- bordered box can have on an 18-row screen.
  --
  -- It needs all sixteen.  Name, category, two type lines, an ABILITIES label,
  -- up to three ability rows and the seven stat rows are fifteen rows of
  -- content, so exactly one is left for a rule, and it goes under the header
  -- where the cart's own entry screen puts its one (PokedexMenu.lua:921).  The
  -- rule that used to sit between the ability and the stats is what the two
  -- extra ability rows cost; the blank rows a species with fewer abilities
  -- leaves behind separate them instead.
  --
  -- Unlike the entry screen this page is NOT drawn under the 5-pixel scroll
  -- (PokedexMenu:drawArea does the same for the same reason), so its columns
  -- are the screen's own.
  local STATS_INTERIOR_ROWS = 16
  local STATS_DIVIDER = { 3 }
  local ROW_NAME, ROW_KIND = 1, 2
  local ROW_TYPE, ROW_TYPE2 = 4, 5
  local ROW_ABILITY_LABEL, ROW_ABILITY_FIRST = 6, 7
  local ROW_STATS = 10
  -- The dex sheet's own '№' pair and the rule tile, out of
  -- PokedexMenu.lua:70-71 and :76 -- neither is exported and neither is a font
  -- glyph, so they are named here and simply do not draw on a cache with no
  -- dex sheet in it.
  local TILE_NO_1, TILE_NO_2, TILE_RULE = 0x5c, 0x5d, 0x61
  -- The sheet's background cell, which every dex screen fills from
  -- (PokedexMenu.lua:61) and which is likewise not exported.
  local TILE_BG_ID = 0x32
  -- Values are right-aligned into a four-wide field ending at the box's last
  -- column: four rather than three because TOTAL runs past 999 on the strongest
  -- records this mod carries, and one field for every row keeps the column
  -- straight.
  local VALUE_COLUMN, VALUE_WIDTH = 15, 4

  -- The box both of this mod's pages stand in, drawn once for the two of them
  -- so they cannot end up different sizes -- every row coordinate on either
  -- page is counted off this interior.
  local function drawBox(self)
    if self:styled() then
      self:fill(TILE_BG_ID, 0, 0, Chrome.SCREEN_W, Chrome.SCREEN_H)
      self:border(0, 0, STATS_INTERIOR_ROWS, 18)
    else
      -- A cache imported before the dex sheet was extracted has no tiles at
      -- all, and the two calls above would then paint the page BLACK -- fill
      -- draws nothing, but :border's interior is a blank rectangle -- with
      -- black text printed onto it.  PokedexMenu:drawPlain answers exactly
      -- this with Chrome's own white box, so this page does too rather than
      -- being the one dex screen that goes dark on an old cache.
      Chrome.clear()
      Chrome.box(0, 0, Chrome.SCREEN_W, Chrome.SCREEN_H)
    end
  end

  local function drawStats(self)
    local row = self:current()
    if not row then return end
    local shown = shownSpecies(self, row.species)
    local page = statsPage(self, shown)
    if not page then return end

    drawBox(self)

    self:text(self:monName(row.species), 1, ROW_NAME)
    -- The BASE species' number, off the row's own dex entry -- the row never
    -- moves onto a form (M.newSpecies refuses to list one), so the synthetic
    -- `dex` a form carries is not reachable from here at all.  Same rule, and
    -- the same construction, as the entry screen beside it.
    local entry = self.dex and self.dex.entries and self.dex.entries[row.species]
    self:tile(TILE_NO_1, 13, ROW_NAME)
    self:tile(TILE_NO_2, 14, ROW_NAME)
    self:text(PokedexMenu.printNumString(
      (type(entry) == "table" and entry.dex) or 0, 3, true), 15, ROW_NAME)

    -- The form's label where the entry screen puts it, and the species'
    -- category when no form is browsed, so the two pages name the same thing
    -- in the same place.
    local label = formLabel(self, row.species)
      or (type(entry) == "table" and entry.kind) or ""
    self:text(label, 1, ROW_KIND)

    for _, y in ipairs(STATS_DIVIDER) do
      for x = 1, 18 do self:tile(TILE_RULE, x, y) end
    end

    self:text("TYPE", 1, ROW_TYPE)
    if page.type1 then self:text(page.type1, 7, ROW_TYPE) end
    if page.type2 then self:text(page.type2, 7, ROW_TYPE2) end

    -- Every ability the species can have, one per row, the hidden one marked
    -- in column 1 -- the margin the names were already indented past.  The
    -- label is plural because the rows are alternatives: an individual
    -- Totodile has Torrent or Sheer Force, never both, so ABILITY over three
    -- names would be a claim about the mon rather than about the species.
    --
    -- A record with no ability data prints neither the label nor a row: a
    -- bare ABILITIES over empty rows reads as "this one has none", which is a
    -- statement, and a wrong one.  src/dexpage.lua's page holds to the same
    -- rule for the same reason, and to the same order, because both pages ask
    -- its abilityRows.
    if page.abilities then
      self:text("ABILITIES", 1, ROW_ABILITY_LABEL)
      for index, row in ipairs(page.abilities) do
        local y = ROW_ABILITY_FIRST + index - 1
        -- Name at column 3, not 2, so a blank cell always separates it from
        -- the mark: at column 2 the H abuts the name and the two read as one
        -- word -- HSHEER FORCE.  The gap has to come out of the name here
        -- rather than the margin, because column 0 is the box border and the
        -- mark cannot move further left.  Every name is indented, marked or
        -- not, so the column stays straight.
        if row.hidden and type(hiddenMark) == "string" then
          self:text(hiddenMark, 1, y)
        end
        self:text(row.name, 3, y)
      end
    end

    for index, stat in ipairs(page.rows) do
      local y = ROW_STATS + index - 1
      self:text(stat[1], 1, y)
      self:text(PokedexMenu.printNumString(stat[2], VALUE_WIDTH, false),
        VALUE_COLUMN, y)
    end
  end

  -- ------- the LVL page
  --
  -- A title, the rule under it, and up to fourteen rows -- and not one
  -- coordinate decided here.  M.pageLayout settled where every string goes
  -- without a screen in the room, including the right-aligned columns, which
  -- this page can do purely where the Gen 1 one has to measure a proportional
  -- font first: on a tile grid a glyph is a cell.
  --
  -- The marked row's mark is Gold's own cursor tile through the dex's
  -- inverted palette, drawn steadily rather than on the entry bar's blink --
  -- it marks a row rather than inviting a press.
  local function drawMoves(self)
    local row = self:current()
    if not row then return end
    local list = movePagesFor(self)
    -- Clamped on the way IN as well as on every step, so a page index left
    -- over from a longer form cannot outlive the selection that produced it.
    local index = M.pageStepTo(self.movePage, 0, #list)
    self.movePage = index
    local page = list[index]
    if not page then return end

    drawBox(self)
    for x = M.PAGE_LEFT, M.PAGE_RIGHT do
      self:tile(TILE_RULE, x, M.PAGE_RULE_ROW)
    end
    for _, item in ipairs(M.pageLayout(page, formLabel(self, row.species))) do
      if item.cursor then
        Chrome.cursorThrough(item.x, item.y, self.gfx and self.gfx.palette, true)
      else
        self:text(item.text, item.x, item.y)
      end
    end
  end

  local originalPanel = PokedexMenu.drawPanel
  function PokedexMenu:drawPanel()
    local draw
    if self.view == STATS_VIEW then
      draw = drawStats
    elseif self.view == MOVES_VIEW then
      draw = drawMoves
    else
      return originalPanel(self)
    end
    local G = love.graphics
    -- Every dex screen starts from a full-screen fill (:1420-1423), so the
    -- frame under this one is the same black the others sit on.
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
    local ok = pcall(draw, self)
    -- A page that could not be drawn falls back to the screen the player came
    -- from rather than to a black rectangle they cannot read their way out of.
    if not ok then pcall(function() self:drawEntry() end) end
    G.setColor(1, 1, 1, 1)
  end

  installed = true
  return true
end

-- Kept beside newSpecies rather than inside install: both are list shaping
-- with no engine in them, and the tests drive them directly.
function M.appended(list, ids)
  if type(list) ~= "table" then return nil end
  local out = {}
  for index, value in ipairs(list) do out[index] = value end
  for _, id in ipairs(ids) do out[#out + 1] = id end
  return out
end

-- The added ids sorted by the name the screen actually prints, so the A-Z tail
-- reads alphabetically even though the ids themselves are not the display
-- names.  Falls back to the id when a record has no name, which is also what
-- PokedexMenu:monName does (line 397).
function M.byName(pokemon, ids)
  local out = {}
  for index, id in ipairs(ids) do out[index] = id end
  local function nameOf(id)
    local record = type(pokemon) == "table" and pokemon[id] or nil
    local name = type(record) == "table" and record.name or nil
    return type(name) == "string" and name:upper() or tostring(id)
  end
  table.sort(out, function(a, b)
    local na, nb = nameOf(a), nameOf(b)
    if na == nb then return a < b end
    return na < nb
  end)
  return out
end

setmetatable(M, { __call = function(_, generation, buildFormList, resolveArt,
                                    scroll, mod, abilityRows, hiddenMark,
                                    pageBuilders)
  return M.install(generation, buildFormList, resolveArt, scroll, mod,
    abilityRows, hiddenMark, pageBuilders)
end })

return M
