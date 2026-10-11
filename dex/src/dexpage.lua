-- Pokédex STATS page and alternate-form browsing, patched onto the engine's
-- DexEntryMenu in memory.  game/src/ui/DexEntryMenu.lua is the engine's own
-- file and is never edited -- src/compat_monpic.lua and src/backoffset.lua
-- (the sprite mod) are the established pattern for this: the class is a
-- plain table, so replacing a few of its fields is an in-memory patch for
-- the life of the process, and an engine running without this mod is
-- untouched.
--
-- Page 1 is the engine's own entry page and stays exactly as it was: same
-- renderer (DexEntryMenu.render), same layout, same data.  Page 2 is new --
-- DOWN from page 1 reaches it, UP returns -- and shows the record's type(s)
-- and abilities next to its base stats, with the same sprite kept on screen so
-- the art and the numbers read together.  DOWN again carries on into a strip
-- of text pages built from this mod's own published API: its whole evolution
-- family with the species being looked at marked in it, where that record
-- evolves from and into (every branch, Eevee's eight included), then its
-- complete modern level-up learnset and the machine/egg/tutor lists beside
-- it.  A long section simply runs on into more pages of the same strip, so
-- there is one way down and one way back up whatever a species carries, and
-- a species that carries nothing has no pages there to reach.
-- LEFT/RIGHT on *any* page cycles the
-- species' alternate forms (base first, then whatever this mod's own
-- national-dex data registered with a matching baseSpecies), which swaps
-- the sprite/types/stats -- name, kind, No., height/weight and the
-- description stay the base species' own throughout, exactly like the real
-- games never re-describe MEGA CHARIZARD X as its own dex entry.
--
-- A form's `dex` field is a synthetic id (build_national_dex.py's
-- FORM_DEX_BASE, 20000+) invented purely so a form can register without
-- colliding with its base species in PokedexMenu's byDex lookup -- it is
-- NEVER a real dex number and must never reach the screen.  Nothing here
-- reads it: self.def (what page 1's No. is drawn from) stays pinned to the
-- base species record for as long as the page is open, so that constraint
-- holds by construction rather than by a check that has to remember to fire.
--
-- The pure logic below (buildFormList / statRows) has no love/engine
-- dependency and no closure over `mod`, so tests/national_dex_test.lua loads
-- this file directly and exercises both without a running game.

local M = {}

-- ------------------------------------------------------------- pure logic

-- The ordered list LEFT/RIGHT cycles through for the species anchored at
-- `baseId`: the base species id first, then every record in `pokemon` whose
-- baseSpecies matches, sorted by id.  Sorted rather than left in whatever
-- order a `pairs` walk produces, because `pairs` over a hash part makes no
-- promise at all -- without a stable sort the LEFT/RIGHT order (and thus
-- what a saved key-press muscle memory lands on) could reshuffle between
-- one session and the next with nothing in the save file having changed.
function M.buildFormList(pokemon, baseId)
  local list = { baseId }
  if type(pokemon) ~= "table" or baseId == nil then return list end
  local forms = {}
  for id, record in pairs(pokemon) do
    if type(record) == "table" and record.baseSpecies == baseId then
      forms[#forms + 1] = id
    end
  end
  table.sort(forms)
  for _, id in ipairs(forms) do list[#list + 1] = id end
  return list
end

local function num(v) return type(v) == "number" and v or 0 end

-- The one place that decides whether a species/form record carries this
-- mod's Sp.Atk/Sp.Def split, and what the two values are.  statRows below
-- goes through here rather than reading record.spAttack/record.spDefense
-- itself, and so does the party summary's stats box
-- (src/summarystats.lua, wired to this exact function by main.lua) -- one
-- lookup shared by both screens means they cannot end up disagreeing about
-- which records have the split.
function M.splitStats(record)
  if type(record) == "table"
    and type(record.spAttack) == "number"
    and type(record.spDefense) == "number" then
    return record.spAttack, record.spDefense
  end
  return nil, nil
end

-- Ordered { label, value } stat rows for `record` under the mod's STATS
-- option ("gen1" | "modern"), TOTAL appended last and equal to the sum of
-- the rows actually shown.
--
-- "modern" needs BOTH spAttack and spDefense on the record to mean anything
-- -- a species/form the split never reached (any record from a source other
-- than this mod's build tool, or one built before the split existed)
-- degrades to the gen1 collapsed-SPC rows instead of printing a blank
-- number or throwing on a nil arithmetic operand.
function M.statRows(record, statsMode)
  local base = (type(record) == "table" and record.baseStats) or {}
  local spAttack, spDefense = M.splitStats(record)
  local split = statsMode == "modern" and spAttack ~= nil and spDefense ~= nil
  local rows
  if split then
    -- Speed last, so the two Special rows sit together and read as the pair
    -- they are.  Kept identical to the party summary's split layout
    -- (src/summarystats.lua) on purpose: the two screens show the same stats
    -- for the same mon, and a reader comparing them should not have to
    -- re-find a row that moved.  The gen1 rows below keep the ROM's own
    -- order, which is not ours to rearrange.
    rows = {
      { "HP", num(base.hp) }, { "ATK", num(base.attack) },
      { "DEF", num(base.defense) }, { "SP.A", num(spAttack) },
      { "SP.D", num(spDefense) }, { "SPD", num(base.speed) },
    }
  else
    rows = {
      { "HP", num(base.hp) }, { "ATK", num(base.attack) },
      { "DEF", num(base.defense) }, { "SPD", num(base.speed) },
      { "SPC", num(base.special) },
    }
  end
  local total = 0
  for _, row in ipairs(rows) do total = total + row[2] end
  rows[#rows + 1] = { "TOTAL", total }
  return rows
end

-- Two ordinary slots and one hidden is the whole of PokeAPI's model, and
-- three rows is what the space on both pages was measured against.  A record
-- that somehow carried a fourth would push the Gen 1 block off the bottom of
-- the screen and Gold's over its HP row, so the extra is dropped in one place
-- rather than differently on each page.
M.ABILITY_ROWS = 3

-- Every ability a species CAN have, as { name, hidden } in the order both
-- STATS pages list them, or nil when there is nothing to print.
--
-- Ordinary slots first by slot number, the hidden one last.  All of them,
-- because they are ALTERNATIVES and not a set a mon owns: an individual
-- Totodile has Torrent or Sheer Force and never both, and its hidden Sheer
-- Force is a third way the same species can turn up.  Printing only the
-- lowest slot -- what this page did before -- answered "what is it usually
-- met with", which is a question about one mon; a dex entry is about the
-- species, so it has to name every possibility.  613 of the 1351 records
-- this mod ships carry all three and another 375 carry two.
--
-- Hidden is ranked last and marked rather than mixed in: it is a real way to
-- meet the species but not one an ordinary encounter offers, and sorting it
-- among the others by its slot number would say the three are interchangeable.
-- The mark is the drawing side's business (M.HIDDEN_MARK); the flag is
-- carried through so both games mark the same row.
--
-- Upper-cased because everything beside it on these pages is -- the TYPE rows
-- come back from TypeChart.displayName as FIRE/FLYING and the stat labels
-- are literals -- while the source spells abilities title-cased ("Solar
-- Power").  The longest name in the payload is 16 glyphs ("Neutralizing
-- Gas"), which is what the indent on both pages is budgeted against.
function M.abilityRows(abilities)
  if type(abilities) ~= "table" then return nil end
  local kept = {}
  for index, entry in ipairs(abilities) do
    if type(entry) == "table" and type(entry.name) == "string"
      and entry.name ~= "" then
      kept[#kept + 1] = {
        name = entry.name:upper(), hidden = entry.hidden and true or false,
        -- an entry with no slot at all sorts behind every numbered one rather
        -- than winning by default -- the order IS what tells the slots apart
        slot = type(entry.slot) == "number" and entry.slot or math.huge,
        -- table.sort is not stable, so two entries the rules above cannot
        -- separate keep the order the payload gave them instead of whichever
        -- one the sort happened to land on
        index = index,
      }
    end
  end
  if #kept == 0 then return nil end
  table.sort(kept, function(a, b)
    if a.hidden ~= b.hidden then return b.hidden end
    if a.slot ~= b.slot then return a.slot < b.slot end
    return a.index < b.index
  end)
  local rows = {}
  for _, entry in ipairs(kept) do
    if #rows >= M.ABILITY_ROWS then break end
    rows[#rows + 1] = { name = entry.name, hidden = entry.hidden }
  end
  return rows
end

-- ------------------------------------------------------ the paged extras
--
-- Pages 3 and beyond are one vertical STRIP of text pages, all built the
-- same way: a title line, up to ROWS_PER_PAGE rows under it, nothing else.
-- Evolutions come first and the movelist after, because the movelist is the
-- long one -- Garchomp's runs to sixteen pages -- and a player walking DOWN to see
-- what a mon evolves into must not have to walk through all of them to get
-- there.
--
-- A section that has no rows produces no page at all, which is what makes
-- "draw nothing rather than an empty frame" true by construction: a species
-- with no evolution data simply has no evolution page in its strip, and one
-- with no data at all has no strip.
--
-- Everything here is pure: the pages, their rows and every coordinate are
-- decided without love, without the engine and without a species record, so
-- a test can assert what a page WOULD print and where before anything is on
-- a screen.

-- The GB font's cell.  Every width budget below is counted in whole cells
-- rather than pixels, because that is the unit the sheet is built in (8px
-- fixed) and the unit a "does this fit" question is actually asked in.
M.COLUMN = 8
M.LEFT = 8
M.RIGHT = 152
-- One cell in from the left margin: the stop the evolution line's first stage
-- and the STATS page's ability rows both start at, which leaves the margin
-- column free for the mark each of them puts there.
M.INDENT = 16

-- The evolution line marks the species being looked at with this, in the
-- margin column the names are indented past.  Every name on that page starts
-- in the same column whether or not it is the marked one, so the shape of the
-- family is read off the indents alone and the mark never shifts a row.
--
-- A glyph rather than a word, so unlike a section title it is not put through
-- the string catalog: there is nothing in it to translate.
--
-- It is the filled arrow ($ED) because that is what the Gen 1 font HAS -- the
-- same tile every menu in the engine parks its cursor on (src/ui/Theme.lua
-- cursor = 0xED), which is exactly what this mark means here.  A plain ">" is
-- not in charmap.asm at all, and Font.encode turns a character it has no tile
-- for into a SPACE, so the ">" that used to be here never reached the screen.
M.MARKER = "▶"
M.MARK_X = M.LEFT
-- The hidden-ability mark, one cell left of M.MARK_X so a blank cell always
-- separates it from the name it qualifies (see the ability block's draw).
M.ABILITY_MARK_X = M.LEFT - 8

-- The STATS page's ability rows: the hidden one is marked in the margin the
-- names are indented past, the same column and the same idea as the evolution
-- line's mark above.  One cell is all that margin is, which is why the mark
-- is a letter and not the word -- and why, like the mark above, it does not
-- go through the string catalog: a translation of it would not fit either.
M.HIDDEN_MARK = "H"

-- Indent stops for the line, one cell per stage.  Clamped because the indent
-- is what pays for a name's width: the deepest chain in this payload is three
-- stages, and a deeper one arriving later must cost a few glyphs off the end
-- of a name rather than push it off the right margin.
M.LINE_MAX_DEPTH = 4

-- How many cells a line starting at `x` has before the right margin.
-- Derived rather than written down twice: moving a margin has to move the
-- budget with it, or a line silently starts running off the screen.
function M.columnsAt(x)
  return math.floor((M.RIGHT - x) / M.COLUMN)
end

M.COLUMNS = M.columnsAt(M.LEFT)   -- 18, the width of a full-width line
M.TITLE_Y = 8               -- clear of the form chrome, which owns y = 0
M.ROW_TOP = 20
M.ROW_STEP = 10             -- the row pitch the STATS page already uses
-- ROW_TOP + 11 * ROW_STEP + 8 = 138, so the twelfth row's glyphs still land
-- inside a 144px screen with two pixels to spare.
M.ROWS_PER_PAGE = 12

-- `text` cut to at most `columns` cells.  Cut rather than ellipsised: the
-- overruns in this payload are one or two characters on the longest move
-- names, and spending a cell on "..." would truncate a dozen names that
-- otherwise fit whole.
function M.fit(text, columns)
  if type(text) ~= "string" then return "" end
  if columns < 1 then return "" end
  if #text <= columns then return text end
  return text:sub(1, columns)
end

-- Everything these pages print is capitals -- the TYPE rows, the section
-- titles, the names M.abilityRows already cases -- so a title-cased move or
-- a lowercase form slug lands in the middle of that as an obvious foreign
-- body.  Applied here rather than in src/displayname.lua's registration path
-- because these names never go NEAR the species registry: the movelist reads
-- the API's own move shards and the evolution line reads the evolution
-- shards, both of which keep the source's spelling on purpose so a consumer
-- of mod.exports gets the canonical name rather than this screen's idea of
-- it.  Same rule as that file states, and for its reasons: only a-z moves,
-- so "é", "♀" and "’" reach the screen as the glyphs the font has for them
-- instead of the space Font.encode substitutes for one it lacks.
local function shown(text)
  if type(text) ~= "string" then return "" end
  return (text:gsub("[a-z]", string.upper))
end
M.shown = shown

-- What the level column prints for one level-up row.
--
-- PokeAPI records a move a species gets the MOMENT it evolves as level 0 --
-- Charizard's Air Slash, 335 rows across this payload -- and printing "0"
-- would name a level that does not exist and that no player can reach.  The
-- column says what actually happens instead.
function M.levelText(level)
  if type(level) ~= "number" or level < 1 then return "EVO" end
  return tostring(math.floor(level))
end

-- Ordered method sections, keyed by the field the extras payload carries
-- them under.  Level-up is not in this list because its rows carry a level
-- column and these do not.
local METHOD_SECTIONS = {
  { key = "machine", title = "MACHINE" },
  { key = "egg", title = "EGG" },
  { key = "tutor", title = "TUTOR" },
  { key = "other", title = "OTHER" },
}

-- The level-up section for one API record, or nil when the record has no
-- level-up moves at all.
--
-- Named on its own rather than left as moveSections' first entry because it
-- is the one section a caller asks for BY ITSELF: Gold's LVL view shows the
-- level-up list and nothing else from the movelist (src/gen2dexlist.lua), and
-- reaching for out[1] there would silently hand it MACHINE for any species
-- whose level-up list is empty -- 85 records in this payload.
--
-- The payload's own order is kept.  tools/build_national_dex.py emits the
-- level-up list ascending by level and then by name, and re-sorting here
-- would only be a second opinion about learn order that can drift from the
-- one the data was built with.
--
-- The name is budgeted against the level beside it rather than given a
-- fixed column: at 18 cells a 16-character name and a two-digit level fill
-- the line exactly (56 rows in this payload do), and a fixed split would
-- have truncated every one of them to make room for a gap nothing needs --
-- the font's glyphs are 5px in an 8px cell, so adjacent cells already read
-- as separated.
function M.levelUpSection(shaped)
  if type(shaped) ~= "table" then return nil end
  local rows = {}
  local full = type(shaped.movesFull) == "table" and shaped.movesFull or {}
  for _, entry in ipairs(full) do
    if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
      local level = M.levelText(entry.level)
      rows[#rows + 1] = {
        text = M.fit(shown(entry.name), M.COLUMNS - #level), x = M.LEFT,
        right = level, rightLabel = tonumber(level) == nil,
      }
    end
  end
  if #rows == 0 then return nil end
  return { title = "LEVEL UP", rows = rows }
end

-- The movelist's sections for one API record (statsBySpecies' reply), in the
-- order the strip shows them.  A section with nothing in it is omitted
-- rather than emitted empty.
function M.moveSections(shaped)
  local out = {}
  if type(shaped) ~= "table" then return out end
  local levelUp = M.levelUpSection(shaped)
  if levelUp then out[#out + 1] = levelUp end
  local byMethod = type(shaped.movesByMethod) == "table" and shaped.movesByMethod or {}
  for _, section in ipairs(METHOD_SECTIONS) do
    local list = type(byMethod[section.key]) == "table" and byMethod[section.key] or {}
    local rows = {}
    for _, entry in ipairs(list) do
      if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
        rows[#rows + 1] = { text = M.fit(shown(entry.name), M.COLUMNS),
                            x = M.LEFT }
      end
    end
    if #rows > 0 then out[#out + 1] = { title = section.title, rows = rows } end
  end
  return out
end

-- ------------------------------------------------- the trigger column
--
-- The family page prints, beside each species, an abbreviation of the step
-- INTO it.  Not the method sentence: the sentences are what kept this off
-- the page in the first place, because folding them in costs sixteen extra
-- rows on Eevee (Sylveon's alone wraps to five at that indent) and splits
-- exactly the family the page exists to show whole.  A token that fits
-- beside the name costs no rows at all, so all 341 chains still land on one
-- unsplit page.  The sentence is still there for anything that wants it --
-- it is `text` on the evolutionsOf record this page was handed.
--
-- The token is read off the default method's STRUCTURED FIELDS, never off
-- its sentence.  build_evolutions.py composes that sentence from the same
-- fields, so parsing it back would be a second, worse copy of a mapping that
-- already exists, and one that breaks the day the wording changes.

-- What a use-item step prints: the word that tells the items apart, capped
-- at the column.  The generic "STONE" was tried first and is wrong for
-- exactly the page this layout is justified by -- five of Eevee's eight
-- branches are stones, and five identical rows answer none of the question a
-- player opened the page with.  Applin's three apples and Charcadet's two
-- armours are the same problem one tier down.
--
-- An item that is not here prints ITEM.  That is the honest answer for one
-- this table has not met rather than a guess at its name, and it is what a
-- payload rebuilt against a newer PokeAPI will print for anything new until
-- someone adds a word for it.
M.ITEM_WORD = {
  ["water-stone"] = "WATER", ["fire-stone"] = "FIRE",
  ["thunder-stone"] = "THNDR", ["leaf-stone"] = "LEAF",
  ["moon-stone"] = "MOON", ["sun-stone"] = "SUN", ["ice-stone"] = "ICE",
  ["dusk-stone"] = "DUSK", ["dawn-stone"] = "DAWN", ["shiny-stone"] = "SHINY",
  ["black-augurite"] = "AUGUR", ["cracked-pot"] = "POT",
  ["metal-alloy"] = "ALLOY", ["peat-block"] = "PEAT",
  ["scroll-of-darkness"] = "DARK", ["scroll-of-waters"] = "WATER",
  ["sweet-apple"] = "SWEET", ["tart-apple"] = "TART",
  ["syrupy-apple"] = "SYRUP", ["auspicious-armor"] = "AUSPIC",
  ["malicious-armor"] = "MALIC", ["galarica-cuff"] = "CUFF",
  ["galarica-wreath"] = "WREATH", ["unremarkable-teacup"] = "TEACUP",
}

-- Appended when the method carries a condition the token does not mention at
-- all, and printed alone when no rule can name the method: "there is more to
-- this than the column can say".  Alolan Raticate is L20 AND at night, and a
-- bare L20 beside it would be a claim the payload does not make.
--
-- A question mark rather than a star or a plus because those two are not in
-- the Gen 1 font's charmap -- Font.encode turns a glyph it has no tile for
-- into a SPACE, so the mark would silently not be there at all.
M.MORE = "?"

-- Fields the token never has to account for: two are the method's own
-- bookkeeping, `text` is the sentence this column exists to avoid, and
-- `trigger` is accounted for separately -- each rule below names the triggers
-- it speaks for, because the trigger can BE the unnamed condition.  Maushold
-- arrives as level 25 under the trigger "other", and a bare L25 beside it
-- would drop the very part the payload is telling us it cannot describe.
local UNSPOKEN_EXEMPT = {
  trigger = true, text = true, versionGroup = true, isDefault = true,
}

-- Trigger sets, named once so a rule and its triggers cannot drift apart.
local LEVEL_UP = { ["level-up"] = true }
local USE_ITEM = { ["use-item"] = true }
local TRADE = { ["trade"] = true }
-- Primeape's Rage Fist is "use-move" and complete; Wyrdeer's is
-- "agile-style-move", where the battle style is a condition MOVE cannot say.
local MOVE_TRIGGERS = { ["level-up"] = true, ["use-move"] = true }

-- The method a step is shown as.  PokeAPI's default is the way the evolution
-- works TODAY -- build_evolutions.py sorts it first for that reason -- and
-- every multi-method step in this payload is one current way plus the ways
-- older games did it: Leafeon's six are a Leaf Stone and five mossy rocks
-- retired with their generations, Magnezone's seven are one stone and six
-- magnetic fields.  They are not alternatives a player can choose between
-- now, so a marker meaning "more than one way" would send someone looking
-- for a rock that this game does not have.  The default, alone, is the
-- answer to "how do I get this one".
local function defaultMethod(group)
  local methods = type(group) == "table" and group.methods
  if type(methods) ~= "table" then return nil end
  for _, method in ipairs(methods) do
    if method.isDefault then return method end
  end
  return methods[1]
end

-- The column for one step, and whether it is a word rather than a number.
--
-- Precedence is by how far the condition narrows down what to actually do: a
-- level and an item are exact, a trade or a held item is a specific act, a
-- known move and a time of day are coarser, and friendship is a hidden gauge
-- that says least of all.  Ordering it that way is what keeps Eevee's eight
-- branches eight different tokens -- put friendship first and Espeon,
-- Umbreon and Sylveon all print HAPPY, which is three rows saying nothing.
--
-- The second return marks the tokens that are WORDS this mod authors, so the
-- drawer can put them through the string catalog exactly as it does the EVO
-- token beside a move.  A level is a number with an L on it and is not
-- translatable; there is no catalog with a hundred of them in it.
function M.triggerText(group)
  local method = defaultMethod(group)
  if not method then return nil end
  local token, word, spoken, triggers
  local level = tonumber(method.level)
  if level and level >= 1 then
    token, word = "L" .. math.floor(level), false
    spoken, triggers = { level = true }, LEVEL_UP
  elseif method.trigger == "use-item" and type(method.item) == "string" then
    token, word = M.ITEM_WORD[method.item] or "ITEM", true
    spoken, triggers = { item = true }, USE_ITEM
  elseif method.trigger == "trade" then
    token, word, spoken, triggers = "TRADE", true, {}, TRADE
  elseif method.heldItem then
    token, word = "HOLD", true
    spoken, triggers = { heldItem = true }, LEVEL_UP
  elseif method.knownMove or method.knownMoveType or method.usedMove then
    token, word = "MOVE", true
    spoken = { knownMove = true, knownMoveType = true, usedMove = true,
               minMoveCount = true }
    triggers = MOVE_TRIGGERS
  elseif type(method.timeOfDay) == "string" and method.timeOfDay ~= "" then
    token, word = method.timeOfDay:upper(), true
    spoken, triggers = { timeOfDay = true }, LEVEL_UP
  elseif method.minHappiness then
    token, word = "HAPPY", true
    spoken, triggers = { minHappiness = true }, LEVEL_UP
  elseif method.minSteps then
    token, word = "WALK", true
    spoken, triggers = { minSteps = true }, LEVEL_UP
  elseif method.partySpecies or method.partyType then
    token, word = "PARTY", true
    spoken, triggers = { partySpecies = true, partyType = true }, LEVEL_UP
  elseif method.trigger == "spin" then
    -- The data source's own word for it, not a coinage: Alcremie's method is
    -- literally "Spin around".
    token, word, spoken, triggers = "SPIN", true, {}, { spin = true }
  else
    -- Shedinja's spare Poke Ball, Kingambit's three defeated Bisharp,
    -- Gholdengo's coins.  Each is a one-off with no short name that is not
    -- an invention, so the column says it cannot say.
    return M.MORE, true
  end
  if not triggers[method.trigger] then return token .. M.MORE, word end
  for field, value in pairs(method) do
    if value ~= nil and not UNSPOKEN_EXEMPT[field] and not spoken[field] then
      return token .. M.MORE, word
    end
  end
  return token, word
end

-- Every species in one record's family, in the order the line is drawn:
-- { id, name, depth, current, trigger, triggerWord } with depth 1 at the root.
--
-- `trigger` is the column for the step INTO this species and therefore comes
-- off the SAME edge that decided its parent and its indent -- never off the
-- steps out of it.  The root has none, because nothing evolves into it.  Read
-- the two apart and every trigger lands one species off, which is a page that
-- looks entirely reasonable and tells a player the wrong level for every
-- Pokemon on it.
--
-- Built by walking the PARENT LINKS depth-first, not by printing `chain` in
-- the order it arrives.  `chain` is a breadth-first walk (build_evolutions.py
-- stages it that way so `stage` means something), so Wurmple's arrives as
-- WURMPLE, SILCOON, CASCOON, BEAUTIFLY, DUSTOX -- printed in that order under
-- stage indents it would file Beautifly beneath Cascoon, which is a claim
-- about which cocoon becomes which moth, and the wrong one.  Depth-first puts
-- each branch under the species it actually comes from.
--
-- `lookup` answers another chain member's own evolutionsOf record.  A
-- parameter rather than a call so the whole walk is exercisable without a
-- running mod, and optional: a member it cannot answer for is still drawn,
-- because the edge that reaches it carries its name.
--
-- The record handed in is the one the page belongs to and is used as-is -- a
-- FORM's own record, when a form is selected, so a form with a line its base
-- species does not have (Galarian Yamask becomes Runerigus; Yamask becomes
-- Cofagrigus) walks its own chain and never the base species'.
function M.evolutionLine(evo, lookup)
  local nodes = {}
  if type(evo) ~= "table" or type(evo.id) ~= "string" then return nodes end
  local selfId = evo.id

  -- The members, in the payload's own order: `chain` first (root first, so
  -- the root is met before anything it produces), then this record and its
  -- immediate neighbours, which is all there is to go on for a payload
  -- carrying no chain at all.
  local members, isMember = {}, {}
  local function member(id)
    if type(id) ~= "string" or isMember[id] then return end
    isMember[id] = true
    members[#members + 1] = id
  end
  if type(evo.chain) == "table" then
    for _, id in ipairs(evo.chain) do member(id) end
  end
  member(selfId)
  if type(evo.evolvesFrom) == "table" then member(evo.evolvesFrom.id) end
  if type(evo.evolvesInto) == "table" then
    for _, entry in ipairs(evo.evolvesInto) do
      if type(entry) == "table" then member(entry.id) end
    end
  end

  local records = { [selfId] = evo }
  if type(lookup) == "function" then
    for _, id in ipairs(members) do
      if records[id] == nil then
        local ok, found = pcall(lookup, id)
        records[id] = (ok and type(found) == "table") and found or false
      end
    end
  end

  local names, children, parentOf, stepInto = {}, {}, {}, {}
  local function note(id, name)
    if type(id) == "string" and type(name) == "string" and name ~= ""
      and names[id] == nil then
      names[id] = name
    end
  end
  -- One parent per species -- build_evolutions.py refuses to emit a second --
  -- so the first edge into a node wins and the mirror of it (the child's own
  -- evolvesFrom saying the same thing) adds nothing but the name.
  --
  -- `step` is the group that DESCRIBES this edge, and both callers below pass
  -- the one for the step into `toId`: a record's evolvesFrom and its parent's
  -- matching evolvesInto entry carry the same method list, so whichever of
  -- the two the walk meets first says the same thing.  It is stored with the
  -- parent link and not separately, so the trigger a species prints and the
  -- indent it prints at can never come from different edges.
  local function edge(fromId, toId, name, step)
    if type(fromId) ~= "string" or type(toId) ~= "string" then return end
    note(toId, name)
    if parentOf[toId] ~= nil or fromId == toId then return end
    parentOf[toId] = fromId
    stepInto[toId] = step
    local kids = children[fromId]
    if not kids then kids = {}; children[fromId] = kids end
    kids[#kids + 1] = toId
  end

  for _, id in ipairs(members) do
    local record = records[id]
    if type(record) == "table" then
      note(id, record.name)
      local from = record.evolvesFrom
      if type(from) == "table" then
        note(from.id, from.name)
        edge(from.id, id, record.name, from)
      end
      if type(record.evolvesInto) == "table" then
        for _, entry in ipairs(record.evolvesInto) do
          if type(entry) == "table" then edge(id, entry.id, entry.name, entry) end
        end
      end
    end
  end

  local visited = {}
  local function visit(id, depth)
    if visited[id] then return end
    visited[id] = true
    local record = records[id]
    local name = shown(type(record) == "table" and type(record.name) == "string"
      and record.name ~= "" and record.name or names[id] or id)
    local trigger, word = M.triggerText(stepInto[id])
    nodes[#nodes + 1] = { id = id, name = name, depth = depth,
                          current = id == selfId or nil,
                          trigger = trigger, triggerWord = word or nil }
    for _, kid in ipairs(children[id] or {}) do visit(kid, depth + 1) end
  end
  for _, id in ipairs(members) do
    if not visited[id] and parentOf[id] == nil then visit(id, 1) end
  end
  -- A member the walk never reached would be a species silently dropped off
  -- its own family page.  It cannot happen with a payload this build tool
  -- emitted -- it refuses a component with no root -- but a dropped species
  -- is the one failure this page could not be seen to have.
  for _, id in ipairs(members) do
    if not visited[id] then visit(id, 1) end
  end
  return nodes
end

-- The name is budgeted against the trigger beside it rather than given a
-- fixed column, exactly as a move name is budgeted against its level: the
-- widest token in this payload is six cells, and a fixed split would have
-- truncated every name on the page to reserve room the short tokens never
-- use.  No gap is spent between them -- the font's glyphs are 5px in an 8px
-- cell, so adjacent cells already read as separated.
--
-- Measured against this payload, the column costs one character off exactly
-- one real species name (Electivire, at the deepest indent, beside TRADE?);
-- everything else it shortens is a slug-shaped FORM name that the names-only
-- page was already cutting.
local function lineRows(nodes)
  local rows = {}
  for _, node in ipairs(nodes) do
    local depth = node.depth
    if depth > M.LINE_MAX_DEPTH then depth = M.LINE_MAX_DEPTH end
    local x = M.INDENT + (depth - 1) * M.COLUMN
    local trigger = node.trigger
    rows[#rows + 1] = {
      text = M.fit(node.name, M.columnsAt(x) - #(trigger or "")), x = x,
      mark = node.current,
      right = trigger, rightLabel = trigger and node.triggerWord or nil,
    }
  end
  return rows
end

-- The evolution section for one evolutionsOf() reply: ONE page, the whole
-- family, with the step into each species beside its name.
--
-- It used to be three -- the line, then EVOLVES FROM and EVOLVES INTO, each
-- carrying one method sentence.  For Ivysaur that was three pages for one
-- fact, and the two extra pages sat between a player and the movelist below
-- them.  The trigger column carries what those pages were for: EVOLVES FROM
-- existed to answer "how do I get THIS species", and that answer is now the
-- token on the marked row.
--
-- What the collapse gives up is precision, and it gives it up visibly.
-- "Level up at night with friendship 160 or more" becomes NIGHT?, and the
-- question mark is the page saying so rather than a silent truncation.  The
-- full sentence has not gone anywhere -- it is `text` on the evolutionsOf
-- record -- but nothing in the game prints it any more.
--
-- EVERY branch is still drawn, however many there are.  Eevee has eight, and
-- nine rows still fit under twelve, so the family a player opens this page
-- for is never cut in half.
--
-- nil in (a form with no line of its own answers nil, and must never borrow
-- its base species') yields no section and therefore no page.  So does a
-- record whose family is only itself -- 207 species in this payload carry an
-- evolution record with no edges on it at all, and a lone marked name under
-- an EVOLUTION title would say they have a family, which they do not.
function M.evolutionSections(evo, lookup)
  local out = {}
  if type(evo) ~= "table" then return out end
  local nodes = M.evolutionLine(evo, lookup)
  if #nodes > 1 then
    out[#out + 1] = { title = "EVOLUTION", rows = lineRows(nodes) }
  end
  return out
end

-- Sections cut into pages of `rowsPerPage` rows, ROWS_PER_PAGE by default.  A
-- section never shares a page with the next one: the title is the only thing
-- telling a player what they are looking at, and two sections under one title
-- would make it a lie.
--
-- The row count is a parameter and not simply the constant because the SAME
-- sections are cut for two different boxes: this screen's twelve rows, and
-- the fourteen Gold's taller dex box leaves under its own header
-- (src/gen2dexlist.lua).  Passing the number keeps one cutter for both rather
-- than a second copy of the arithmetic that decides where a page ends and
-- what its counter says.
function M.paginate(sections, rowsPerPage)
  local perPage = M.ROWS_PER_PAGE
  if type(rowsPerPage) == "number" and rowsPerPage >= 1 then
    perPage = math.floor(rowsPerPage)
  end
  local pages = {}
  for _, section in ipairs(sections or {}) do
    local rows = section.rows or {}
    local count = math.ceil(#rows / perPage)
    for index = 1, count do
      local page = { title = section.title, index = index, count = count, rows = {} }
      for offset = 1, perPage do
        local row = rows[(index - 1) * perPage + offset]
        if not row then break end
        page.rows[offset] = row
      end
      pages[#pages + 1] = page
    end
  end
  return pages
end

-- The whole strip below the STATS page, for one species or form.
function M.buildPages(shaped, evo, lookup, rowsPerPage)
  local sections = M.evolutionSections(evo, lookup)
  for _, section in ipairs(M.moveSections(shaped)) do
    sections[#sections + 1] = section
  end
  return M.paginate(sections, rowsPerPage)
end

-- One page's draws: { text, x, y } for a left-anchored one and
-- { text, y, align = "right" } for one measured off the right margin, which
-- only the drawer can place because only it knows the loaded font's widths.
--
-- `localise` marks the strings this mod AUTHORS -- the section titles, the
-- EVO token and the evolution line's word triggers -- so the drawer can put
-- them through the engine's string catalog.  A move name and a species name
-- are data and are drawn as the payload spells them, a level and an L-plus-a
-- level are numbers, and the line's marker is a glyph with nothing in it to
-- translate.
function M.layoutPage(page)
  local out = {}
  if type(page) ~= "table" then return out end
  out[#out + 1] = { text = page.title, x = M.LEFT, y = M.TITLE_Y, localise = true }
  -- Only when the section really does run over: a "1/1" on every short
  -- section would be noise on a screen with none to spare.
  if (page.count or 1) > 1 then
    out[#out + 1] = { text = page.index .. "/" .. page.count, y = M.TITLE_Y,
                      align = "right" }
  end
  local y = M.ROW_TOP
  for _, row in ipairs(page.rows or {}) do
    out[#out + 1] = { text = row.text, x = row.x or M.LEFT, y = y }
    if row.mark then
      out[#out + 1] = { text = M.MARKER, x = M.MARK_X, y = y }
    end
    if row.right then
      out[#out + 1] = { text = row.right, y = y, align = "right",
                        localise = row.rightLabel or nil }
    end
    y = y + M.ROW_STEP
  end
  return out
end

-- "MEGA_X" -> "MEGA X".  build_national_dex.py's `form` field is the raw
-- PokeAPI slug suffix (underscored, upper-cased); this is display-only.
-- Which species id to ask a sprite set for, and which form spelling(s) to
-- ask under, for `record`.  Returns lookupId, form, altForm -- altForm being
-- the underscore-squashed spelling older sets were built with (MEGAX for
-- MEGA_X), or nil when squashing changes nothing.  Pure so the ordering can
-- be asserted without a running game; see loadArt for why the alternate
-- exists at all.
function M.formCandidates(record, speciesId)
  if type(record) ~= "table" or type(record.baseSpecies) ~= "string"
    or type(record.form) ~= "string" then
    return speciesId, nil, nil
  end
  local squashed = record.form:gsub("_", "")
  if squashed == record.form then return record.baseSpecies, record.form, nil end
  return record.baseSpecies, record.form, squashed
end

local function prettyForm(form)
  return (form or ""):gsub("_", " ")
end

-- ------------------------------------------------------------ engine patch

-- Every module this needs is required once here, guarded exactly the way
-- compat_monpic.lua probes BattleState: a missing or reshaped module means
-- this feature quietly does not install rather than taking the mod load
-- down, and none of these calls happen at the top of the file, so a
-- headless test that only wants buildFormList/statRows never touches love
-- or src.* at all.
local function requireAll()
  local names = {
    "src.ui.DexEntryMenu", "src.render.Font", "src.core.Strings",
    "src.pokemon.Sprites", "src.battle.TypeChart", "src.render.PaletteFX",
  }
  local mods = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    mods[name] = value
  end
  return mods
end

-- `generation` is the booting game (1 unless Gold said otherwise); it gates
-- the neighbour seam at the bottom of this function and nothing else, because
-- Gold's #DEX is its own class under its own screen id and never builds the
-- one this file patches.  nil means Gen 1, the same assumption main.lua makes
-- when it could not ask.
function M.install(mod, generation)
  local mods = requireAll()
  if not mods then return false end
  local DexEntryMenu = mods["src.ui.DexEntryMenu"]
  local Font = mods["src.render.Font"]
  local Strings = mods["src.core.Strings"]
  local Sprites = mods["src.pokemon.Sprites"]
  local TypeChart = mods["src.battle.TypeChart"]
  local PaletteFX = mods["src.render.PaletteFX"]
  if type(DexEntryMenu.new) ~= "function"
    or type(DexEntryMenu.draw) ~= "function"
    or type(DexEntryMenu.update) ~= "function" then
    return false
  end

  -- Resolve a form's own art through the same seam battle art uses, so the
  -- sprite mod's per-form art (or its fallback to the engine's own) applies
  -- here unchanged -- this page never picks an image path itself.
  -- A FORM must be asked for as "base species, wearing form X" -- never by
  -- its own compound id.  A sprite set keys form art at entry.forms[FORM]
  -- underneath the BASE species (universal_sprites' Registry:registerForm),
  -- so a lookup for CHARIZARD_MEGA_X matches no entry at all and falls
  -- through to this mod's placeholder, while CHARIZARD carrying form=MEGA_X
  -- finds art that is already built and sitting on disk.
  --
  -- ctx.mon.form is the engine's own route for saying so: Sprites.path
  -- forwards opts.mon to the hook untouched, and the registry reads
  -- ctx.form or ctx.mon.form when it walks its precedence steps.  Passing a
  -- one-field stand-in rather than a real mon is safe -- every other reader
  -- of ctx.mon guards its own field access.
  --
  -- Asking under the base species also improves the MISS case: a form with
  -- no art of its own now falls back to its base species' artwork, which is
  -- always present, instead of the "?" placeholder.  Mega Charizard X with
  -- no mega art shows a Charizard, which is the right answer.
  local function askArt(game, lookupId, form)
    local ok, path, trueColor = pcall(Sprites.path, game.data, lookupId,
      "front", { kind = "dex", mon = form and { form = form } or nil })
    if not ok then return nil, false end
    return path, trueColor and true or false
  end

  -- Sets built before the form ids settled carry their keys with the
  -- underscores squashed out -- MEGAX for MEGA_X, POMPOM for POM_POM,
  -- GALARZEN for GALAR_ZEN -- because the build tool derived them from
  -- filenames that omit the hyphen, and the registry's key cleaner
  -- uppercases and replaces punctuation but never INSERTS an underscore.
  -- The two spellings can therefore never meet, and the miss is SILENT: the
  -- lookup just falls through to the base species' own art, so Mega
  -- Charizard X quietly shows an ordinary Charizard.  Measured against the
  -- installed sets: 5 forms in gen5ani and 14 in gen5, including both
  -- Charizard and both Mewtwo megas -- the first things anyone checks.
  --
  -- A form miss is detectable rather than guessed at: it returns exactly
  -- what the base species alone returns.  When that happens, try the
  -- squashed spelling before giving up.
  local function loadArt(game, speciesId, record)
    local lookupId, form, altForm = M.formCandidates(record, speciesId)
    local path, trueColor = askArt(game, lookupId, form)
    if altForm then
      local basePath = askArt(game, lookupId, nil)
      if path == basePath then
        local altPath, altTrue = askArt(game, lookupId, altForm)
        if altPath and altPath ~= basePath then
          path, trueColor = altPath, altTrue
        end
      end
    end
    if not path then return nil, false end
    local ok2, img = pcall(love.graphics.newImage, path)
    if not ok2 or not img then return nil, false end
    return img, trueColor and true or false
  end

  -- Point `self` at forms[index]: swaps the sprite, types and stats to that
  -- entry's, and (for a non-base form) records its label.  Index 1 is
  -- always the base species and reuses the art the original constructor
  -- already loaded rather than resolving it a second time.
  local function applyForm(self, index)
    self.formIndex = index
    local id = self.forms[index]
    self.formId = id
    if id == self.baseSpeciesId then
      self.sprite = self.baseSprite
      self.spriteTrueColor = self.baseSpriteTrueColor
      self.formRecord = self.def
      self.formLabel = nil
      return
    end
    local pokemon = self.game.data and self.game.data.pokemon
    local record = pokemon and pokemon[id]
    -- A form id that no longer resolves (another mod's data changed under
    -- us mid-session) falls back to the base record rather than leaving
    -- formRecord nil -- statRows/type drawing both already tolerate a
    -- non-table record, but reusing the base keeps the page showing SOME
    -- real numbers instead of a blank stats column.
    self.formRecord = record or self.def
    self.formLabel = record and record.form or nil
    local sprite, trueColor = loadArt(self.game, id, record)
    self.sprite = sprite or self.baseSprite
    self.spriteTrueColor = sprite and trueColor or self.baseSpriteTrueColor
  end

  -- Anchor the form list on whatever species `self.def` currently names, and
  -- select the base entry.  Both the list and the art LEFT/RIGHT falls back
  -- to are species-specific, so this has to run again every time something
  -- moves `self.def` -- a list left over from the previous species would
  -- cycle to the forms of a mon that is no longer on the page.
  local function captureForms(self)
    self.baseSpeciesId = self.def.baseSpecies or self.def.id
    self.baseSprite = self.sprite
    self.baseSpriteTrueColor = self.spriteTrueColor
    self.forms = M.buildFormList(self.game and self.game.data
      and self.game.data.pokemon, self.baseSpeciesId)
    applyForm(self, 1)
  end

  -- One LEFT/RIGHT step through self.forms, wrapping at both ends.  Returns
  -- true only when the selection actually moved, so a caller with its own
  -- per-form state to repair can tell a press apart from a quiet frame.
  local function cycleForms(self, input)
    local forms = self.forms
    if not forms or #forms < 2 then return false end
    local n = #forms
    if input:wasPressed("left") then
      applyForm(self, ((self.formIndex - 2) % n) + 1)
      return true
    elseif input:wasPressed("right") then
      applyForm(self, (self.formIndex % n) + 1)
      return true
    end
    return false
  end

  -- Is a Pokédex entry the screen being put together, or the screen already
  -- standing?  Both halves are needed and they are different moments: a
  -- replacement screen resolves its pic inside its own constructor, BEFORE
  -- anything is pushed, and again later when the player steps to another
  -- species with the screen already live.  Read by the Sprites.path seam at
  -- the bottom of this function; inert until a neighbour claims the screen.
  local building = false
  local stacked = 0

  local originalNew = DexEntryMenu.new
  function DexEntryMenu.new(game, speciesOrOpts, onDone)
    -- Set before the vanilla constructor rather than after, because a
    -- replacement screen delegates to it and then resolves its own art on
    -- the way back out -- the window has to already be open by then.
    building = true
    local self = originalNew(game, speciesOrOpts, onDone)
    -- Everything below is additive state for page 2 / form browsing.  A
    -- failure here must never take the vanilla page down with it, so it is
    -- entirely inside one pcall; on failure the page behaves exactly like a
    -- species with no forms (page 2 still works, just with nothing to
    -- cycle -- see the #5 constraint on degrading safely).
    local ok = pcall(function()
      if type(self) ~= "table" or type(self.def) ~= "table" then
        error("no species record", 0)
      end
      self.page = 1
      captureForms(self)
    end)
    if not ok and type(self) == "table" then
      self.page = self.page or 1
      self.forms = self.forms or {}
      self.formIndex = self.formIndex or 1
    end
    return self
  end

  -- Small "there is another one of these" hint, only when there is anywhere
  -- to cycle to, plus the selected form's own label -- never shown for the
  -- base entry, which must look exactly like it did before this mod existed.
  --
  -- ONE arrow, on the right margin.  This used to be a "<" and a ">" pair and
  -- neither ever drew: neither character is in charmap.asm, and Font.encode
  -- turns a character it has no tile for into a SPACE.  The right-hand one
  -- comes back as the arrow the font really has ($ED, M.MARKER); the left one
  -- cannot come back at all, because the Gen 1 sheet's only arrows are ▷, ▶
  -- and ▼ and none of them points that way.  A left hint that pointed right
  -- would be worse than the nothing that is there now, and RIGHT reaches every
  -- form anyway -- the cycle wraps.
  local function drawFormChrome(self)
    love.graphics.setColor(0, 0, 0, 1)
    if self.forms and #self.forms > 1 then
      Font.draw(M.MARKER, 152, 0)
    end
    if self.formLabel then
      Font.draw(prettyForm(self.formLabel), 16, 0)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- The ability rows for whichever record the page is showing, memoised.
  --
  -- Abilities are the one thing this page needs that the registered record
  -- does not carry: the whole extras payload lives in
  -- data/species/generated/extras/ shards instead (see src/api.lua's
  -- extras-load banner -- bolted onto all 1351 records they once pushed
  -- national.lua past LuaJIT's 65,536-constant ceiling and the mod loaded
  -- with no species at all).  src/api.lua is the only reader of those
  -- shards, so this page asks it through the surface any other mod would
  -- rather than opening the files a second time and owning a second cache
  -- of them.
  --
  -- Read off mod.exports at DRAW time rather than captured here: main.lua
  -- installs this file before src/api.lua publishes anything, so a capture
  -- taken now would be nil for the life of the process.
  --
  -- Memoised per species/form id because statsBySpecies deep-copies the
  -- entire record and its extras -- the right price for a cross-mod call
  -- and far too much to pay every frame, when the answer is a handful of
  -- short strings that cannot change while the game runs.  `false` is stored
  -- for "asked, nothing to show", so a species with no ability data costs one
  -- lookup rather than one per frame.
  --
  -- One entry answers BOTH the ability rows and the whole page strip below
  -- it, from one statsBySpecies call: the movelist comes out of the same
  -- deep-copied reply the ability does, so asking twice would pay for the
  -- copy twice to read two fields of one table.  The pages are built the
  -- moment the STATS page first draws rather than when the player first
  -- walks down to them -- laying out Garchomp's seventeen pages is a few
  -- hundred table stores, once, against holding the copied record alive for
  -- every species browsed in a session, which is the far larger bill.
  local extras = {}
  local NOTHING = { abilities = false, pages = {} }

  -- Every evolution record this page has asked for, by id, `false` standing
  -- for "asked, there is nothing".  Keyed by id rather than held on the
  -- species being shown, because drawing ONE species' family reads its
  -- relatives' records too, and a relative is very often the next species the
  -- player steps to -- Bulbasaur, Ivysaur and Venusaur cost three lookups
  -- between them rather than nine.  evolutionsOf deep-copies a whole record
  -- per call, which is why the second ask has to be a table read.
  local chains = {}

  local function evolutionFor(id)
    if type(id) ~= "string" then return nil end
    local found = chains[id]
    if found == nil then
      found = false
      local ask = mod.exports and mod.exports.evolutionsOf
      if type(ask) == "function" then
        local ok, reply = pcall(ask, id)
        if ok and type(reply) == "table" then found = reply end
      end
      chains[id] = found
    end
    return found or nil
  end

  local function extrasFor(record)
    local id = type(record) == "table" and record.id or nil
    if type(id) ~= "string" then return NOTHING end
    local found = extras[id]
    if found == nil then
      local abilities, shaped = false, nil
      local stats = mod.exports and mod.exports.statsBySpecies
      if type(stats) == "function" then
        local ok, reply = pcall(stats, id)
        if ok and type(reply) == "table" then
          shaped = reply
          abilities = M.abilityRows(reply.abilities) or false
        end
      end
      -- Asked for by the record's OWN id, base species and form alike.  A
      -- form with no line of its own answers nil and gets no evolution page:
      -- Mega Charizard X does not evolve from Charmeleon at level 36, and
      -- falling back to the base species' chain here would say it does.  The
      -- family drawn from it is walked with the same lookup, so a form's line
      -- is its own line all the way out to its ends.
      local evo = evolutionFor(id)
      -- A page strip that cannot be built costs the strip and nothing else:
      -- the ability rows above it, and page 2 with it, still draw.
      local ok, pages = pcall(M.buildPages, shaped, evo, evolutionFor)
      found = { abilities = abilities, pages = ok and pages or {} }
      extras[id] = found
    end
    return found
  end

  local function abilitiesFor(record)
    return extrasFor(record).abilities or nil
  end

  -- The strip for whichever record the page is showing -- self.formRecord,
  -- never self.def, so the movelist and the evolutions follow the selected
  -- form exactly as the abilities and the stats beside them do.
  local function pagesFor(self)
    return extrasFor(self.formRecord or self.def).pages
  end

  -- The last page in the strip for what is currently selected.  Page 1 is
  -- the engine's own entry, page 2 the STATS page -- both always there --
  -- and 3 upwards are whatever pagesFor built.
  local function lastPage(self)
    return 2 + #pagesFor(self)
  end

  -- DOWN/UP walk the strip, LEFT/RIGHT cycle forms.  The engine's own A/B
  -- pop-the-stack handling must run completely untouched -- originalUpdate
  -- is called directly, unguarded, so a reshaped engine update still pops
  -- exactly like it always has even if everything below it fails.
  --
  -- DOWN carrying on past the STATS page is the whole navigation scheme, and
  -- it is deliberately not a new key: DOWN already meant "further into this
  -- species" the moment page 2 existed, the movelist's own paging is more of
  -- the same walk rather than a second idiom layered on top, and LEFT/RIGHT
  -- keep the one job they have.  Neither end wraps -- the strip has a top
  -- and a bottom a player can feel, and a DOWN that silently landed back on
  -- the entry page would read as the screen having closed and reopened.
  --
  -- No key is rebound: A and B still pop, and the engine's own update never
  -- reads a direction at all.
  local originalUpdate = DexEntryMenu.update
  function DexEntryMenu:update(dt)
    local wasA, wasB = false, false
    pcall(function()
      local input = self.game.input
      wasA, wasB = input:wasPressed("a"), input:wasPressed("b")
    end)
    originalUpdate(self, dt)
    if wasA or wasB then return end
    pcall(function()
      local input = self.game.input
      local page = type(self.page) == "number" and self.page or 1
      if input:wasPressed("down") then
        -- page 2 is always there, so the first step down never has to ask
        -- the API how deep this species goes
        if page == 1 then
          self.page = 2
        elseif page >= 2 and page < lastPage(self) then
          self.page = page + 1
        end
      elseif input:wasPressed("up") then
        if page > 1 then self.page = page - 1 end
      end
      -- A form keeps the DEPTH the player was reading at rather than being
      -- sent back to the top: the sections come in the same order for every
      -- form, so a step sideways lands on the same kind of page, and
      -- resetting would punish exactly the comparison LEFT/RIGHT is for.
      -- Clamped, because a form's strip can be shorter than its neighbour's.
      if cycleForms(self, input) and type(self.page) == "number"
        and self.page > 2 then
        self.page = math.min(self.page, lastPage(self))
      end
    end)
  end

  -- Page 2: sprite kept in the same spot page 1 draws it, TYPE1/TYPE2 and
  -- the abilities in the space page 1 gives its description text, BASE STATS
  -- where page 1 puts name/kind/No/HT/WT.  Reads self.formRecord (falling
  -- back to self.def), never self.def directly, so a selected form's own
  -- types, abilities and stats show even though self.def itself never moves
  -- off the base species (see the file banner on why that has to stay
  -- true) -- and the abilities are looked up from that same record's id, so
  -- they cannot drift away from the numbers printed beside them.
  local function drawStatsPage(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    local sprite = self.sprite
    if sprite then
      local y = math.max(0, 60 - sprite:getHeight())
      love.graphics.draw(sprite, 8, y)
      if self.spriteTrueColor then
        PaletteFX.markTrueColor(8, y, sprite:getDimensions())
      end
    end
    love.graphics.setColor(0, 0, 0, 1)
    local record = self.formRecord or self.def
    local types = (type(record) == "table" and record.types) or {}
    local ty = 72
    if types[1] then
      Font.draw(Strings("TYPE1/"), 8, ty)
      Font.draw(TypeChart.displayName(types[1]), 8, ty + 10)
      ty = ty + 20
    end
    if types[2] then
      Font.draw(Strings("TYPE2/"), 8, ty)
      Font.draw(TypeChart.displayName(types[2]), 8, ty + 10)
      ty = ty + 20
    end
    -- The abilities go in the space below the types, under a label of their
    -- own, and the block FLOWS with the types rather than sitting at a fixed
    -- line: a form can have a type its base species does not (Ampharos is
    -- ELECTRIC, its mega ELECTRIC/DRAGON), and an anchored block would leave
    -- a hole on one of the two.
    --
    -- ABILITY_STEP is 8 and not the 10 the type rows use, because that is
    -- what the arithmetic leaves.  Two types put the label at y=112 and three
    -- ability rows is the worst case the payload has (613 records carry three,
    -- 298 of those two-typed); at 10 the third row would start at 142 and its
    -- glyphs would run to 150 on a 144px screen.  At 8 -- the font cell, and
    -- the pitch every tile-grid screen in the game is written on -- it starts
    -- at 136 and ends exactly on the bottom edge.  A tighter block also reads
    -- as one thing, which is what these rows are: alternatives, not a list of
    -- what a mon carries.
    --
    -- Names are indented one cell so the margin can hold the hidden mark, the
    -- same shape as the evolution page's line, and the hidden row is the only
    -- one that ever draws in that column.
    --
    -- A record with no ability data draws nothing at all -- 14 of the forms
    -- this mod ships have none -- because a bare ABILITIES/ label over empty
    -- lines reads as "this one has none", which is a statement, and a wrong
    -- one.
    local ABILITY_STEP = 8
    local abilities = abilitiesFor(record)
    if abilities then
      Font.draw(Strings("ABILITIES/"), M.LEFT, ty)
      local ay = ty + ABILITY_STEP
      for _, row in ipairs(abilities) do
        -- One cell further left than the evolution page's marker, because
        -- this one sits beside a WORD rather than a row of them: at M.MARK_X
        -- the H lands in the cell immediately before the name and the two
        -- read as one -- HSNIPER, HSHEER FORCE.  The blank cell between is
        -- what makes it a mark instead of a first letter, and taking it from
        -- the margin rather than the name costs no name a character.
        if row.hidden then Font.draw(M.HIDDEN_MARK, M.ABILITY_MARK_X, ay) end
        Font.draw(row.name, M.INDENT, ay)
        ay = ay + ABILITY_STEP
      end
    end
    Font.draw(Strings("BASE STATS"), 72, 8)
    local rows = M.statRows(record, mod.options:get("stats"))
    local ry = 20
    for _, row in ipairs(rows) do
      Font.draw(Strings(row[1]), 72, ry)
      local text = tostring(row[2])
      Font.draw(text, 152 - Font.width(text), ry)
      ry = ry + 10
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- Pages 3 and up: a title line and its rows, and nothing this function
  -- decides for itself.  Where each string goes was settled by M.layoutPage
  -- without a screen in the room; the only placement left here is the
  -- right-aligned column, which needs the loaded font's own widths -- the
  -- same measure-then-place the STATS page's numbers use.
  local function drawTextPage(self, page)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(0, 0, 0, 1)
    for _, item in ipairs(M.layoutPage(page)) do
      local text = item.localise and Strings(item.text) or item.text
      local x = item.x
      if item.align == "right" then x = M.RIGHT - Font.width(text) end
      Font.draw(text, x, item.y)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local originalDraw = DexEntryMenu.draw
  function DexEntryMenu:draw()
    -- drawStatsPage failing for any reason (a shape this file did not
    -- anticipate, an image call throwing) falls back to the vanilla page
    -- rather than a broken one -- originalDraw fills the whole canvas
    -- white as its first act, so it cleanly covers whatever a half-drawn
    -- page 2 left behind.
    if self.page == 2 and pcall(drawStatsPage, self) then
      pcall(drawFormChrome, self)
      return
    end
    -- A page number with no page behind it falls back the same way.  It
    -- should not happen -- update clamps on every route that can shorten the
    -- strip -- but the fallback is the vanilla entry, which is a page, and
    -- the alternative is a blank screen with no way off it.
    if type(self.page) == "number" and self.page > 2 then
      local ok, pages = pcall(pagesFor, self)
      local page = ok and pages[self.page - 2] or nil
      if page and pcall(drawTextPage, self, page) then
        pcall(drawFormChrome, self)
        return
      end
    end
    originalDraw(self)
    pcall(drawFormChrome, self)
  end

  -- ------------------------------------------- when a neighbour owns the page
  --
  -- Screens.resolve prefers the screens registry over src/ui/DexEntryMenu, so
  -- a mod that REGISTERS "DexEntryMenu" replaces the stacked screen outright
  -- instead of patching it.  Such a screen still builds a real DexEntryMenu
  -- underneath and delegates to it -- so everything above still runs -- but it
  -- draws its own pages and reads its own input, which means the STATS page
  -- above is bypassed for as long as it is installed.  That is its screen to
  -- own and nothing here fights it for the stack.  Form browsing is a
  -- different case and comes back on keys the neighbour leaves free; see
  -- "borrowing LEFT/RIGHT back" below.
  --
  -- The PIC is a different matter, because neither side can see the whole of
  -- it.  A replacement screen resolves its own art and is free to ask under
  -- whatever ctx.kind it likes -- one shipped mod asks under "battle" so that
  -- battle-art hooks apply to its page.  A sprite mod grants full-colour art
  -- its opt-out from the four-shade SGB pass per KIND, keyed on a whitelist of
  -- still-image screens that has "dex" on it and deliberately not "battle" --
  -- withholding it there is what stops a voxel battle mod's billboard
  -- alternating shaded and unshaded frame to frame.  Put together, the entry
  -- asked for its pic under the one kind that is refused, and drew 96px colour
  -- art crushed to four shades on every open.  Both neighbours are right about
  -- the thing they can see; this mod is the one that can see both.
  --
  -- So correct the CONTEXT rather than the art: while a Pokédex entry is being
  -- built or is on the stack, a pic lookup is a dex lookup whoever asks for it
  -- and whatever they name it.  Relabelling in Sprites.path puts the answer
  -- ahead of every pokemon.sprite hook, so it does not matter which mod
  -- wrapped that hook first or whether one is installed at all.
  --
  -- Deliberately not a wider grant and not a kind blacklist: outside the
  -- window every lookup keeps exactly the answer it had before, and a kind
  -- nobody has invented yet is covered by where it is asked from rather than
  -- by a list somebody has to remember to extend.
  --
  -- Gen 1 only.  Gold's #DEX is its own class under its own screen id, builds
  -- this one never, and must not gain a seam it cannot use.
  if generation ~= 2 then
    local neighbourOwnsEntry = false

    local function dexWindow()
      return neighbourOwnsEntry and (building or stacked > 0)
    end

    -- ------------------------------------------ borrowing LEFT/RIGHT back
    --
    -- The pages are the neighbour's and stay the neighbour's, but the two
    -- directions form browsing needs are not in use.  useful_dex 1.3.0 reads
    -- exactly four buttons on the entry -- B pops, A cycles data/movelist,
    -- UP/DOWN page the movelist or step the seen species -- so LEFT and RIGHT
    -- can carry forms again without taking a key off a feature that has one.
    -- Rebinding a key a neighbour already used would be trading its feature
    -- for ours, which is not a trade this mod gets to make.
    --
    -- The instance is augmented, never the class and never the files: the
    -- registered factory is wrapped in memory for one boot, and everything
    -- below is written onto the object that wrap returns.  Registering the id
    -- a second time is not an alternative -- screens are a record registry
    -- and a duplicate register raises (src/mods/Registry.lua).
    -- ------------------------------- the numbers on the neighbour's page
    --
    -- Selecting a form has to move what the page PRINTS, not just its art.
    -- The neighbour draws its stat rows out of a table it built once for the
    -- species (useful_dex 1.3.0 caches it in setSpecies and prints it, total
    -- included, straight from the cache), and it reads its type rows off its
    -- own `def`.  Neither moves when LEFT/RIGHT selects a form, so both are
    -- substituted for the length of one draw call and restored immediately
    -- after -- see the draw wrap below for why that window is so tight.
    --
    -- Row key -> the field it comes from on a record's baseStats.  Only the
    -- five a Gen 1 page prints are listed, deliberately: an unrecognised key
    -- means the page is printing a number whose form value this cannot know,
    -- and the whole substitution is declined rather than applied to the rows
    -- it does recognise.  A column where some numbers moved to the form and
    -- the rest stayed the base species' would be a worse lie than a column
    -- where none of them moved.
    local STAT_FIELD = {
      HP = "hp", ATK = "attack", DEF = "defense",
      SPD = "speed", SPC = "special",
    }

    local statsDeclined = false
    local function declineStats()
      if statsDeclined then return end
      statsDeclined = true
      mod.log:info("the Pokédex entry screen another mod owns prints stat "
        .. "rows this mod cannot map onto a form -- its art and label still "
        .. "cycle, the numbers beside them stay the base species'")
    end

    -- `record`'s stats in the shape the neighbour built for the base species,
    -- or nil when that shape is not one this can move.  The rows keep the
    -- neighbour's own keys and order -- this is its page and its layout, and
    -- the STATS option's split rows are not ours to impose on it -- and every
    -- other field of its table is carried across untouched, since it may be
    -- read somewhere this cannot see.  The total is recomputed from the rows
    -- actually substituted rather than copied, or it would still be the base
    -- species' sum sitting under the form's numbers.
    local function formStats(cached, record)
      if type(cached) ~= "table" or type(cached.stats) ~= "table" then
        return nil
      end
      if #cached.stats == 0 then return nil end
      local base = record.baseStats
      if type(base) ~= "table" then return nil end
      local rows, total = {}, 0
      for i, row in ipairs(cached.stats) do
        if type(row) ~= "table" then return nil end
        local field = STAT_FIELD[row.key]
        local value = field and base[field]
        if type(value) ~= "number" then return nil end
        rows[i] = { key = row.key, value = value }
        total = total + value
      end
      local swapped = {}
      for key, value in pairs(cached) do swapped[key] = value end
      swapped.stats, swapped.bst = rows, total
      return swapped
    end

    -- A stand-in record for the same one draw: the base species' own fields
    -- with the types replaced, never the form record itself.  Name, kind,
    -- HT/WT, the owned lookup and above all the No. are read from this same
    -- table, and a form's `dex` is a synthetic key that must never be printed
    -- (see the file banner).  Copying the base rather than pointing at the
    -- form keeps that true by construction instead of by a check.
    local function formDef(baseDef, record)
      local swapped = {}
      for key, value in pairs(baseDef) do swapped[key] = value end
      if type(record.types) == "table" then swapped.types = record.types end
      return swapped
    end

    local function augmentable(screen)
      return type(screen) == "table"
        and type(screen.update) == "function"
        and type(screen.draw) == "function"
        and type(screen.vanilla) == "table"
        and type(screen.vanilla.def) == "table"
        and type(screen.vanilla.forms) == "table"
    end

    local function augment(screen)
      local delegate = screen.vanilla

      -- Re-anchor on the art the NEIGHBOUR resolved rather than on what the
      -- vanilla constructor loaded: a replacement screen looks the pic up a
      -- second time on the way out of its own constructor and writes the
      -- result onto the delegate, so the sprite captured during construction
      -- is already stale.  Cycling back to the base form has to land on the
      -- image the player was actually looking at, not on an earlier one.
      local function reanchor() pcall(captureForms, delegate) end
      reanchor()

      -- Stepping the seen species moves the delegate's def and sprite
      -- wholesale, and the form list anchored on the old species has to go
      -- with it.  Wrapped on the instance, so the neighbour's class keeps
      -- the method it shipped with for any other screen sharing it.
      if type(screen.setSpecies) == "function" then
        local originalSetSpecies = screen.setSpecies
        screen.setSpecies = function(s, ...)
          originalSetSpecies(s, ...)
          reanchor()
        end
      end

      local originalUpdate = screen.update
      screen.update = function(s, dt)
        originalUpdate(s, dt)
        pcall(function()
          -- Only over the page that shows a pic.  The movelist is built for
          -- one species and cycling underneath it would swap art nobody can
          -- see while leaving the rows describing the entry before.
          if s.view == "moves" then return end
          if not cycleForms(delegate, s.game.input) then return end
          -- A neighbour may be driving an ANIMATED base sprite, rewriting
          -- the delegate's sprite from another mod's frame files as it goes.
          -- Left running it would paint over a selected form frame by frame,
          -- so it is parked while one is shown and rebuilt by the
          -- neighbour's own code on the way back to the base entry.
          if delegate.formIndex ~= 1 then
            s.crystalAnimation = nil
          elseif type(s.setupCrystalAnimation) == "function" then
            pcall(s.setupCrystalAnimation, s)
          end
        end)
      end

      -- What the selected form's page needs, memoised.  The key is the
      -- identity of everything it was derived from, so it is rebuilt after a
      -- cycle AND after the neighbour rebuilds its own table for another
      -- species, while an unchanged frame costs one comparison.  Invalidating
      -- from the update wrap instead would have to guess at every route that
      -- can move the neighbour's state; this cannot go stale.
      local view, viewFrom = nil, nil

      local function substitution(s)
        local record = delegate.formRecord
        if delegate.formIndex == 1 or type(record) ~= "table" then return nil end
        if rawequal(record, delegate.def) then return nil end
        if type(s.stats) ~= "table" or type(s.def) ~= "table" then return nil end
        if view and rawequal(viewFrom.record, record)
          and rawequal(viewFrom.stats, s.stats)
          and rawequal(viewFrom.def, s.def) then
          return view
        end
        local stats = formStats(s.stats, record)
        if not stats then
          declineStats()
          return nil
        end
        view = { stats = stats, def = formDef(s.def, record) }
        viewFrom = { record = record, stats = s.stats, def = s.def }
        return view
      end

      local originalDraw = screen.draw
      screen.draw = function(s)
        local savedStats, savedDef = s.stats, s.def
        local swapped = false
        -- The movelist page is built for one species and prints no stats, so
        -- there is nothing there for a form to move: it draws untouched.
        if s.view ~= "moves" then
          local ok, substituted = pcall(substitution, s)
          if ok and substituted then
            s.stats, s.def = substituted.stats, substituted.def
            swapped = true
          end
        end
        local ok, err = pcall(originalDraw, s)
        -- Restored before anything else can run, the throwing path included.
        -- A swap left standing would not merely mis-draw one frame: the
        -- neighbour's own cached table would be gone and its `def` would be a
        -- stand-in, so every species the player stepped to afterwards would
        -- be captioned with one form's numbers.
        if swapped then s.stats, s.def = savedStats, savedDef end
        if not ok then error(err, 0) end
        if s.view ~= "moves" then pcall(drawFormChrome, delegate) end
      end
    end

    -- Swap `.new` on the record in place rather than putting a fresh table
    -- into data.screens: Screens.resolve caches the record TABLE and reads
    -- `.new` off it at every build, so an in-place swap takes effect whether
    -- or not something already resolved this id, while a replacement table
    -- would be ignored by an already-warmed cache.  A bare function is a
    -- legal record too (src/ui/Screens.lua resolve), and that one has no
    -- field to swap, so it is boxed instead.
    -- Whether form browsing actually came back cannot be known at load: the
    -- registry holds a factory, and only the screen it builds says whether
    -- there is anything to hang forms off.  So the load-time line reports the
    -- part that is already settled -- the STATS page is the neighbour's now --
    -- and the first entry the player opens reports the rest, once, whichever
    -- way it went.
    local announced = false
    local function announce(message)
      if announced then return end
      announced = true
      mod.log:info(message)
    end

    local function wrapEntryFactory(screens)
      local record = screens.DexEntryMenu
      local originalNew
      if type(record) == "table" and type(record.new) == "function" then
        originalNew = record.new
      elseif type(record) == "function" then
        originalNew = record
      else
        return false
      end
      local function wrapped(...)
        local screen = originalNew(...)
        -- A factory that throws is degraded to the builtin screen
        -- (src/ui/Screens.lua build), which would drop the neighbour's whole
        -- feature set on the floor.  Nothing added here may be the reason
        -- that happens, so the augmentation is guarded end to end.
        if augmentable(screen) then
          pcall(augment, screen)
          announce("form browsing is back on LEFT/RIGHT over the Pokédex "
            .. "entry screen another mod owns -- the two directions it reads "
            .. "nowhere itself")
        else
          announce("the Pokédex entry screen another mod supplies is not "
            .. "shaped to carry form browsing -- leaving it as it is")
        end
        return screen
      end
      if type(record) == "table" then
        record.new = wrapped
      else
        screens.DexEntryMenu = { new = wrapped }
      end
      return true
    end

    -- Asked after every mod has registered and the screens registry has been
    -- merged into data.screens, so the answer does not depend on load order.
    -- A registry hit means some mod replaced the screen; the builtin is the
    -- require fallback and never appears there.  It is also the one moment
    -- the factory can be wrapped: every registration is in, and nothing has
    -- opened a Pokédex yet.
    mod.events:on("mods.loaded", function(payload)
      local screens = payload and payload.data and payload.data.screens
      neighbourOwnsEntry = screens ~= nil and screens.DexEntryMenu ~= nil
      if not neighbourOwnsEntry then return end
      mod.log:info("another mod owns the Pokédex entry screen -- its pages "
        .. "replace this mod's STATS page; species data and dex art still "
        .. "come from here")
      local ok, wrapped = pcall(wrapEntryFactory, screens)
      if not (ok and wrapped) then
        announce("that mod supplies no entry factory this one can extend -- "
          .. "form browsing stays off while it is installed")
      end
    end)

    -- screen.pushed/popped carry the state with the id Screens.build stamped
    -- on it, so this counts a neighbour's screen exactly as it counts the
    -- builtin.  The build window closes on the NEXT push whatever that push
    -- is: a construction that never reaches the stack (a screen that threw and
    -- degraded) must not leave the window propped open behind it.
    mod.events:on("screen.pushed", function(payload)
      local state = payload and payload.state
      if state and state.screenId == "DexEntryMenu" then
        stacked = stacked + 1
      end
      building = false
    end)
    mod.events:on("screen.popped", function(payload)
      local state = payload and payload.state
      if state and state.screenId == "DexEntryMenu" then
        stacked = math.max(0, stacked - 1)
      end
      building = false
    end)

    local function alreadyDex(opts)
      return type(opts) == "table" and opts.kind == "dex"
    end

    local originalPath = Sprites.path
    function Sprites.path(data, species, side, opts)
      if dexWindow() and not alreadyDex(opts) then
        -- a copy, never a write into the caller's table: a screen that keeps
        -- one options table around would otherwise be silently retyped for
        -- every lookup it ever makes, including the ones after it closes
        local relabelled = { kind = "dex" }
        if type(opts) == "table" then
          for key, value in pairs(opts) do relabelled[key] = value end
          relabelled.kind = "dex"
        end
        opts = relabelled
      end
      return originalPath(data, species, side, opts)
    end
  end

  -- :sgbPalettes is deliberately left untouched: it keys its zone off
  -- self.def.id, and self.def stays the base species for the page's whole
  -- lifetime by design (see the file banner) -- reusing that same read
  -- automatically keeps working with no code of ours in the path at all,
  -- for a display mode (Super Game Boy) narrow enough that duplicating the
  -- engine's own palette lookup here would only be one more place for the
  -- two to drift apart.

  return true
end

setmetatable(M, { __call = function(_, mod, generation)
  return M.install(mod, generation)
end })

return M
