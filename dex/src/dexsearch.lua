-- The Pokédex search query: what a typed line MEANS and what it matches.
--
-- Everything in this file is pure -- no love, no engine module, no mod handle
-- -- for the same reason src/dexview.lua and src/dexscroll.lua are: the
-- interesting half of a search is the classification and the match, and those
-- are driven by tests with plain tables rather than by standing a screen up.
--
-- A "row" here is one line of a listing, the same shape src/dexview.lua
-- describes: { dex = number, name = string, known = boolean, types = { ... } }.
-- Forms are not rows and never become them.

local M = {}

-- ------------------------------------------------------------- normalising
--
-- One spelling for a typed term and an indexed name alike: lowercase,
-- alphanumerics only.  "Giga Drain", "giga-drain" and "GIGADRAIN" are one
-- key, and so are "Ho-Oh", "Mr. Mime" and "Farfetch'd" however a player
-- reaches them -- which matters more than it looks, because the two naming
-- grids and a PC keyboard do not offer the same punctuation.
--
-- tools/build_national_dex.py's normalise_term does exactly this, and the two
-- MUST agree: a name normalised one way at build time and another at search
-- time is a term that silently matches nothing.
--
-- Output is ASCII-only, but a Latin accented letter is FOLDED to its base
-- letter first rather than simply dropped -- Flabébé has no other spelling a
-- keyboard can reach, so "flabbb" or "flabébé" both leave it unsearchable
-- while "flabebe" is exactly what a player types.  A symbol with no Latin
-- base at all, like the multi-byte glyphs in NIDORAN♀ / NIDORAN♂ or the
-- curly apostrophe in some spellings of Farfetch'd, has nothing to fold to
-- and is still dropped -- which leaves both Nidoran forms answering
-- "nidoran", the right answer for a player who cannot type either symbol.
--
-- FOLD is keyed on the raw two-byte UTF-8 sequence of each accented letter,
-- both cases.  LuaJIT's string:lower() below is byte-wise and ASCII-only --
-- it does not decode UTF-8 -- so an uppercase É (0xC3 0x89) survives it
-- untouched and needs its own entry here, not just é's (0xC3 0xA9); folding
-- after :lower() only saves entries for the plain ASCII letters, not these.
-- Ÿ is the one letter in range that is not adjacent to its lowercase form in
-- Latin-1 (it lives at U+0178, 0xC5 0xB8), hence the separate gsub for it.
local FOLD = {
  ["\xC3\x80"] = "a", ["\xC3\x81"] = "a", ["\xC3\x82"] = "a", ["\xC3\x83"] = "a",
  ["\xC3\x84"] = "a", ["\xC3\x85"] = "a", ["\xC3\xA0"] = "a", ["\xC3\xA1"] = "a",
  ["\xC3\xA2"] = "a", ["\xC3\xA3"] = "a", ["\xC3\xA4"] = "a", ["\xC3\xA5"] = "a",
  ["\xC3\x87"] = "c", ["\xC3\xA7"] = "c",
  ["\xC3\x88"] = "e", ["\xC3\x89"] = "e", ["\xC3\x8A"] = "e", ["\xC3\x8B"] = "e",
  ["\xC3\xA8"] = "e", ["\xC3\xA9"] = "e", ["\xC3\xAA"] = "e", ["\xC3\xAB"] = "e",
  ["\xC3\x8C"] = "i", ["\xC3\x8D"] = "i", ["\xC3\x8E"] = "i", ["\xC3\x8F"] = "i",
  ["\xC3\xAC"] = "i", ["\xC3\xAD"] = "i", ["\xC3\xAE"] = "i", ["\xC3\xAF"] = "i",
  ["\xC3\x91"] = "n", ["\xC3\xB1"] = "n",
  ["\xC3\x92"] = "o", ["\xC3\x93"] = "o", ["\xC3\x94"] = "o", ["\xC3\x95"] = "o",
  ["\xC3\x96"] = "o", ["\xC3\xB2"] = "o", ["\xC3\xB3"] = "o", ["\xC3\xB4"] = "o",
  ["\xC3\xB5"] = "o", ["\xC3\xB6"] = "o",
  ["\xC3\x99"] = "u", ["\xC3\x9A"] = "u", ["\xC3\x9B"] = "u", ["\xC3\x9C"] = "u",
  ["\xC3\xB9"] = "u", ["\xC3\xBA"] = "u", ["\xC3\xBB"] = "u", ["\xC3\xBC"] = "u",
  ["\xC3\x9D"] = "y", ["\xC3\xBD"] = "y", ["\xC3\xBF"] = "y", ["\xC5\xB8"] = "y",
}

-- gsub answers two values, the string and a replacement count, and this
-- always has to answer one: a caller anywhere in the middle of an argument
-- list would silently drop the count anyway, but the LAST argument of a call
-- expands every value a function returns, and a stray count landing there
-- would either fail a comparison outright or -- worse, if it ever landed
-- somewhere Lua coerces a number to a string -- pass one for the wrong
-- reason.  The parentheses around the call force exactly one.  The two
-- intermediate gsubs below are safe without that guard: chaining a method
-- call off their result already truncates to the first value on its own.
function M.normalise(text)
  if type(text) ~= "string" then return "" end
  local folded = text:lower():gsub("\xC3[\x80-\xBF]", FOLD):gsub("\xC5\xB8", "y")
  return (folded:gsub("[^a-z0-9]", ""))
end

-- ------------------------------------------------------------- tokenising
--
-- Terms are separated by '+', ',' or '/' and ANDed.  Three separators rather
-- than one because of what a PAD can type: both naming grids carry ',' and
-- '/' and NEITHER carries '+' (src/ui/NamingScreen.lua and
-- src/ui/gen2/NamingScreen.lua, both transcriptions of
-- data/text/alphabets.asm), so a player without a keyboard reaches one of the
-- other two or expresses only one term for ever.
--
-- A space is NOT a separator: move names contain them, and splitting on one
-- turns "giga drain" into two terms matching nothing.  normalise drops it
-- anyway, so a term keeps its spaces or loses them to no effect.
--
-- `text` is only ever a gmatch SUBJECT here, never a pattern, so a player
-- typing a Lua pattern metacharacter ('%', '-', '.', ...) cannot change what
-- this splits on or reach into normalise's own pattern -- it just rides
-- through as an ordinary character and normalise strips or keeps it same as
-- any other.
--
-- Empty terms are dropped rather than preserved.  A trailing separator is the
-- state the field is in halfway through typing "fire+", and an empty term
-- that matched nothing would blank the results a player is still reading.
-- The '+' appended before splitting exists so the LAST term has a separator
-- to be captured against too; it costs one extra empty capture at the very
-- end (and one more per already-trailing separator), which the empty-term
-- drop below absorbs for free.
--
-- '+' stays a separator here even though the engine's charmap cannot draw it
-- (data/generated/font.lua) and the field itself will therefore never hold
-- one -- the screen's key mapping converts a '+' keypress to '/' before it
-- reaches the buffer.  It is kept accepting '+' anyway because it is the
-- character the feature is described with to a player, and because a saved
-- query or some future caller that builds `text` outside that key mapping
-- may still carry one.  Accepting a byte that never actually appears costs
-- nothing.
function M.tokenise(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for chunk in (text .. "+"):gmatch("([^+,/]*)[+,/]") do
    local term = M.normalise(chunk)
    if term ~= "" then out[#out + 1] = term end
  end
  return out
end

-- ---------------------------------------------------------- classification
--
-- The ladder, in order.  A term is measured against all four vocabularies and
-- keeps EVERY reading that fits, in this order -- the first is what the
-- screen uses and the rest are what SELECT cycles through.  Discarding them
-- would leave a wrong guess with no way back, which is the one thing the
-- printed reading exists to prevent.
--
-- WHY THIS ORDER.  Name leads because it is the only vocabulary a player can
-- be certain their term belongs to: they have just seen the species in a
-- battle or a trade and are spelling what they saw.  Type follows because
-- eighteen names known by heart beat several hundred that are not.  Ability
-- trails because it is the vocabulary these games never print anywhere
-- outside the pages this mod itself added, so a player typing one has almost
-- certainly come from those pages and knows what they are asking for.
--
-- It is a first guess, not a ruling.  'dragon' reading as a name finds
-- Dragonair and Dragonite rather than the Dragon types, which is wrong about
-- as often as it is right -- and is exactly what the label and M.cycle undo.
M.READINGS = { "name", "type", "move", "ability" }

local Index = nil
-- Injected by main.lua rather than required: a mod's own files load as chunks
-- through mod:read, not through package.path, so require() cannot see a
-- sibling of this mod.  Tests hand in the real module the same way.
function M.useIndex(module) Index = module end

-- A PREFIX, not an exact match: "chari" is what a player has typed by the
-- time they can see whether they meant Charizard.  Linear over `names`
-- rather than a trie -- this runs once per term on a keystroke, not once per
-- row per frame, and 1025 string comparisons is not the cost a live search
-- needs to worry about; M.match below, which runs a term against every row,
-- is the one that would matter and it does not call this at all.
local function nameMatches(term, vocab)
  local names = type(vocab) == "table" and vocab.names or nil
  if type(names) ~= "table" then return false end
  if names[term] then return true end
  for name in pairs(names) do
    if name:sub(1, #term) == term then return true end
  end
  return false
end

-- Every reading a term fits, in ladder order.  A reading is
-- { kind = "type", term = "fire", display = "FIRE" }.
function M.classify(term, vocab)
  local out = {}
  if type(term) ~= "string" or term == "" or type(vocab) ~= "table" then
    return out
  end
  if nameMatches(term, vocab) then
    out[#out + 1] = { kind = "name", term = term, display = term:upper() }
  end
  if type(vocab.types) == "table" and vocab.types[term] then
    out[#out + 1] = { kind = "type", term = term, display = term:upper() }
  end
  for _, kind in ipairs({ "move", "ability" }) do
    if Index and Index.has(vocab.payload, kind, term) then
      local display = Index.displayName(vocab.payload, kind, term) or term
      out[#out + 1] = { kind = kind, term = term, display = display:upper() }
    end
  end
  return out
end

-- What the screen prints under the field.  The kind is named as well as the
-- value because the value alone cannot say which of two readings won: a row
-- reading "PSYCHIC" tells a player nothing they did not already type.
function M.label(reading)
  if type(reading) ~= "table" or type(reading.kind) ~= "string" then
    return "?"
  end
  return reading.kind:upper() .. " " .. tostring(reading.display or reading.term)
end

-- -------------------------------------------------------------- the query
--
-- A query is { text = the raw field contents, terms = { term, ... } }, where
-- a term is { raw, readings, at, reading }.  `at` is which of `readings` is
-- live and is what M.cycle moves; `reading` is that entry, cached so callers
-- do not index two tables to print one row.
function M.parse(text, vocab)
  local query = { text = type(text) == "string" and text or "", terms = {} }
  for _, raw in ipairs(M.tokenise(text)) do
    local readings = M.classify(raw, vocab)
    query.terms[#query.terms + 1] = {
      raw = raw,
      readings = readings,
      at = 1,
      -- nil for a term in no vocabulary.  Carried rather than dropped: a
      -- query that silently ignored a word would answer a question the
      -- player did not ask, and answer it confidently.
      reading = readings[1],
    }
  end
  return query
end

-- The row printed under the field: every term's reading, in order.  The
-- separator is comma-space rather than the middle dot an earlier version
-- used: the engine's real charmap (data/generated/font.lua) has no glyph for
-- '\xC2\xB7', so it drew blank or fell back silently, and this row exists to
-- be read.  Comma reads as a second term if it lands INSIDE the field, which
-- is exactly why tokenise treats it as a separator there -- but this string
-- is never fed back through tokenise, only printed, so the same character is
-- unambiguous here.
function M.summary(query)
  if type(query) ~= "table" or type(query.terms) ~= "table" then return "" end
  local parts = {}
  for _, term in ipairs(query.terms) do
    parts[#parts + 1] = term.reading and M.label(term.reading)
      or ("? " .. tostring(term.raw):upper())
  end
  return table.concat(parts, ", ")
end

function M.unreadable(query)
  if type(query) ~= "table" or type(query.terms) ~= "table" then return false end
  for _, term in ipairs(query.terms) do
    if not term.reading then return true end
  end
  return false
end

function M.ambiguous(query)
  if type(query) ~= "table" or type(query.terms) ~= "table" then return false end
  for _, term in ipairs(query.terms) do
    if #term.readings > 1 then return true end
  end
  return false
end

-- SELECT: an odometer over the ambiguous terms, first term as the ones place.
--
-- Advance the first ambiguous term.  If that advance does NOT wrap it back to
-- its first reading, stop there -- a player pressing SELECT sees exactly one
-- thing change.  If it DOES wrap, that wrap is a carry: the first term has
-- shown everything it has to show, so the next ambiguous term advances too
-- (and can itself carry into the one after, same rule, same reason).  Without
-- the carry, a second ambiguous term could only ever be reached by mutating
-- it directly -- SELECT would spin the first term forever and never uncover
-- the second one's own wrong guess.
function M.cycle(query)
  if type(query) ~= "table" or type(query.terms) ~= "table" then return false end
  local moved = false
  for _, term in ipairs(query.terms) do
    if #term.readings > 1 then
      local wrapping = term.at == #term.readings
      term.at = term.at % #term.readings + 1
      term.reading = term.readings[term.at]
      moved = true
      if not wrapping then return true end
    end
  end
  return moved
end

-- --------------------------------------------------------------- matching

local function rowHasType(row, term)
  local types = type(row) == "table" and row.types or nil
  if type(types) ~= "table" then return false end
  -- Either slot.  A player asking for fire+flying means a species holding
  -- both, not one whose first type happens to be Fire -- Moltres is
  -- FLYING/FIRE and belongs in that answer as squarely as Charizard does.
  for _, id in ipairs(types) do
    if M.normalise(id) == term then return true end
  end
  return false
end

local function rowMatches(row, reading, vocab)
  if type(reading) ~= "table" then return false end
  if reading.kind == "name" then
    local name = M.normalise(type(row) == "table" and row.name or nil)
    return name:sub(1, #reading.term) == reading.term
  end
  if reading.kind == "type" then
    return rowHasType(row, reading.term)
  end
  -- move / ability, both answered by the generated index, and both keyed on
  -- the DEX NUMBER rather than the row's position: the listing skips numbers
  -- no species claims, so the two are not interchangeable.
  local payload = type(vocab) == "table" and vocab.payload or nil
  local set = Index and Index.dexSet(payload, reading.kind, reading.term) or nil
  local dex = type(row) == "table" and row.dex or nil
  return (set and type(dex) == "number" and set[dex]) and true or false
end

-- The row INDICES matching every term of the query, in listing order.
--
-- Indices rather than rows, because the caller owns the item array these
-- index into -- the same arrangement src/dexview.lua's views use, so a
-- search result and a view mode are the same kind of thing to the screen
-- underneath.
--
-- An empty query matches NOTHING rather than everything: the screen opens on
-- an empty field, and answering that with all 1025 rows is the listing the
-- player just left.
--
-- An unreadable term poisons the whole query rather than being skipped.
-- Answering "fire" to someone who asked for fire and something else is worse
-- than answering nothing, because it looks like it worked.
--
-- Rows are walked in the outer loop and terms in the inner one, each row
-- bailing at its first failing term -- fire+flying rejects a Water/Poison row
-- on the first check and never asks it about the second type at all.
-- rowHasType's own loop is at most two iterations (a species has at most two
-- types) and rowMatches' name/move/ability branches are each O(1) past the
-- normalise call, so one keystroke over 1025 rows is at most a few thousand
-- cheap comparisons -- nowhere near the cost a per-frame concern would need.
function M.match(rows, query, vocab)
  local out = {}
  if type(rows) ~= "table" or type(query) ~= "table"
    or type(query.terms) ~= "table" then
    return out
  end
  -- An empty query matches EVERYTHING, and this is the second answer to that
  -- question rather than the first.  It used to match nothing, on the
  -- reasoning that all 1025 rows are the listing the player just left -- and
  -- the screen that reasoning produced was a black box holding a cursor and
  -- the number 0.  A player cannot tell that from a search that ran and
  -- failed, so the one state every player sees first was the one state that
  -- looked broken.
  --
  -- Starting from everything and narrowing is also what a search is: the rows
  -- are the thing being filtered, so showing them before the first keystroke
  -- explains the screen without a word of help text.
  --
  -- UNRECORDED rows are included here and nowhere else, and the split is the
  -- point rather than an oversight.  An empty query is not a search, it is the
  -- listing standing still: those rows print as dashes exactly as they do on
  -- the screen the player just left, so nothing is revealed that was not
  -- already on show.  The moment a term exists the rule below applies and the
  -- dashes drop out, because a name nobody can see is a name nobody may look
  -- up.  Keeping them for the empty state is also what stops a fresh save --
  -- which has recorded almost nothing -- from opening on the same blank screen
  -- this branch exists to fix.
  if #query.terms == 0 then
    for index = 1, #rows do out[index] = index end
    return out
  end
  if M.unreadable(query) then return out end
  for index, row in ipairs(rows) do
    -- RECORDED species only, once a query is actually being made.
    --
    -- A row the save has no record of prints "052 -----", and this mod's own
    -- listing already refuses to sort those by their real names because doing
    -- so "would leak, in position, precisely the names the dashes are there to
    -- withhold" (src/dexview.lua's alphabetical view).  A search that matched
    -- them leaks the same thing more directly: typing "chari" and getting a
    -- hit at #006 tells a player a species exists there and how its name
    -- starts, and typing "fire" counts the Fire types for them.
    --
    -- It is also what the screen this replaced did -- Gold's cart search reads
    -- seen species only -- so honouring it keeps a player's dex the record of
    -- what they have met rather than a table of contents for the whole game.
    if row.known then
      local all = true
      for _, term in ipairs(query.terms) do
        if not rowMatches(row, term.reading, vocab) then
          all = false
          break
        end
      end
      if all then out[#out + 1] = index end
    end
  end
  return out
end

return M
