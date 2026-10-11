-- The Gen 1 Pokédex SEARCH screen: a free-text field, the reading of what was
-- typed underneath it, and the matching rows below that.
--
-- Everything above M.new is pure -- no love, no engine module, no mod handle
-- -- so the typing, the edit buffer, the cap and the layout fit are driven by
-- tests with plain strings and stub functions, the same arrangement
-- src/dexview.lua and src/dexsearch.lua use.

local M = {}

-- ------------------------------------------------------------- pure typing
--
-- Characters are built from key NAMES rather than from love.textinput,
-- because love.textinput never reaches Game: main.lua routes it only to the
-- importer and the save editor (game/main.lua:829).  The engine's own dev
-- console types the same way and for the same reason
-- (game/src/dev/Console.lua:21 KEY_CHARS), so this table starts as that one --
-- but every output is checked against RENDERABLE below rather than assumed,
-- because a shifted symbol the console types (the '@' over 2, the '_' under
-- -, the '{' over [) has no tile in game/data/generated/font.lua and would
-- draw as a hole in the row instead of the character a player pressed.

-- The full set of characters this field may ever hold, taken by reading
-- game/data/generated/font.lua's charmap directly rather than assuming ASCII
-- punctuation carries over.  Confirmed present as single-character entries:
-- every letter and digit, space, and  , . / - : ; ' ! " ( ) ? [ ].
-- Confirmed ABSENT (checked, not guessed): + * & @ # $ % ^ _ { } < > \ | ~ `
-- and the bare '=' -- none of those has a glyph, so a key table that echoed
-- one would print a blank tile where a character belongs.
M.RENDERABLE = {}
for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do M.RENDERABLE[c] = true end
for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do M.RENDERABLE[c] = true end
for c in ("0123456789"):gmatch(".") do M.RENDERABLE[c] = true end
for _, c in ipairs({
  " ", ",", ".", "/", "-", ":", ";", "'", "!", "\"", "(", ")", "?", "[", "]",
}) do
  M.RENDERABLE[c] = true
end

-- keypressed name -> { unshifted, shifted }.  Modelled on Console's
-- KEY_CHARS, but with every shifted symbol the font cannot draw left out
-- rather than mapped: 2/3/4/5/6/7/8 have no shifted entry at all (@ # $ % ^
-- & * are all missing from the charmap), and -, [, ], , and . keep only
-- their unshifted side (_, {, }, <, > are missing too).
local KEY_CHARS = {
  space = { " ", " " },
  ["1"] = { "1", "!" }, ["2"] = { "2" }, ["3"] = { "3" }, ["4"] = { "4" },
  ["5"] = { "5" }, ["6"] = { "6" }, ["7"] = { "7" }, ["8"] = { "8" },
  ["9"] = { "9", "(" }, ["0"] = { "0", ")" },
  ["-"] = { "-" }, [";"] = { ";", ":" }, ["'"] = { "'", "\"" },
  [","] = { "," }, ["."] = { "." }, ["/"] = { "/", "?" },
  ["["] = { "[" }, ["]"] = { "]" },
}

-- The character a key press means, or nil for a key that is not one, or
-- whose meaning has no glyph.
--
-- '=' is handled on its own rather than through KEY_CHARS.  Shift-equals is
-- where a PC keyboard keeps the '+' this feature was described with, and '+'
-- has no glyph.  '/' is renderable, sits on both games' naming grids
-- (src/ui/NamingScreen.lua's GRID_UPPER/GRID_LOWER row 5) and means exactly
-- the same thing to Search.tokenise as '+' would have -- so the keyboard and
-- the pad converge on one separator instead of diverging on two.  The
-- numpad plus agrees for the same reason.  Bare '=' (no shift) has no
-- renderable meaning at all and is dropped.
function M.charFor(key, shift)
  if type(key) ~= "string" then return nil end
  if key:match("^%l$") then
    local char = shift and key:upper() or key
    return M.RENDERABLE[char] and char or nil
  end
  if key == "=" then
    return shift and "/" or nil
  end
  if key == "kp+" then return "/" end
  local digit = key:match("^kp(%d)$")
  if digit then return digit end
  local pair = KEY_CHARS[key]
  if not pair then return nil end
  local char = shift and pair[2] or pair[1]
  return (char and M.RENDERABLE[char]) and char or nil
end

-- 20 cells across the canvas at the font's flat 8px advance.  The field
-- draws at x=8 -- this screen's left margin, the same one its own title row
-- and dexview's tag row keep -- so 18 glyphs reach x=152, eight pixels short
-- of the right edge: the matching margin on the other side.  The 19th cell,
-- drawn only while the field has focus, is the trailing cursor, and it lands
-- exactly on that same 8px margin rather than past it -- a full field with
-- its cursor showing still ends flush with the convention the rest of the
-- screen uses.
M.MAX_LEN = 18

-- The field after one key press.  Backspace on an empty field is a player
-- who has already deleted everything, not an error.
function M.edit(text, key, shift)
  local buffer = type(text) == "string" and text or ""
  if key == "backspace" then
    return buffer:sub(1, math.max(0, #buffer - 1))
  end
  local char = M.charFor(key, shift)
  if not char then return buffer end
  if #buffer >= M.MAX_LEN then return buffer end
  return buffer .. char
end

-- ------------------------------------------------------------- pure layout
--
-- Cut `text` down to whatever `budget` pixels actually hold, measured by
-- `widthFn` (Font.width on the real screen; a stub that counts characters in
-- tests).  Whole characters come off the tail one at a time rather than a
-- guessed byte count, because 8px-per-glyph is only true of the tile font --
-- a translation's TTF is not, and Font.width is the one source of truth
-- either way.  "TYPE FIRE, TYPE FLYING" is 22 characters; at 8px a glyph
-- that is 176px against a 160px canvas, so every string this screen draws
-- goes through this rather than being trusted to fit.
function M.fit(text, budget, widthFn)
  text = type(text) == "string" and text or ""
  if type(widthFn) ~= "function" then return text end
  if type(budget) ~= "number" then return text end
  while #text > 0 and widthFn(text) > budget do
    text = text:sub(1, #text - 1)
  end
  return text
end

-- ------------------------------------------------------------ the screen
--
-- A state on game.stack.  Game:keypressed hands the raw key to
-- stack:top():onKeyPressed WHENEVER THE FIELD IS PRESENT, no matter what it
-- does with the key (game/src/core/Game.lua:614-617 -- the check is
-- `top.onKeyPressed`, not "did it consume anything").  A screen that defines
-- that method permanently therefore owns the keyboard permanently: every
-- physical key stops reaching Input:keypressed, which is the ONLY thing that
-- turns a key into a GB button press for update()'s own input:wasPressed
-- polling below -- so B, the d-pad and SELECT would go dead for a keyboard
-- player the instant this screen opened, while a gamepad (which never routes
-- through love.keypressed at all) looked completely unaffected.
--
-- `onKeyPressed` is therefore an INSTANCE field this screen installs and
-- removes itself, present only while self.focus == "field" -- the one state
-- where there is text to type -- and nil otherwise, so navigating the
-- results reaches Input exactly like any other screen would.
-- src/ui/BindingsMenu.lua's beginCapture/endCapture is the same pattern for
-- the same reason (its own doc comment names Game's raw-input routing
-- directly).  See Screen:syncCapture.
--
-- Required lazily and guarded, the way src/dexview.lua's requireAll is: a
-- missing font, string, naming or input module costs this screen and
-- nothing else, and no headless caller of the pure half above pulls love or
-- src.* in behind it.
local function requireAll()
  local names = { "src.render.Font", "src.core.Strings", "src.ui.NamingScreen",
                  "src.ui.Theme", "src.core.Input" }
  local found = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    found[name] = value
  end
  return found
end

local function shiftDown()
  return love and love.keyboard and love.keyboard.isDown
    and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift"))
end

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

-- Seven rows of results, the same window both listings use, so a search
-- result and the listing behind it read as the same kind of screen.
local RESULT_ROWS = 7

-- Never throws: a caller that hands this a shape it cannot use gets nil back
-- and logs it itself, the way the rest of this mod's optional seams degrade
-- (src/dexview.lua's M.apply).  This module has no mod handle to log
-- through, so declining quietly and letting the caller say why is the only
-- option that does not invent a second logging contract.
function M.new(game, opts)
  local modules = requireAll()
  if not modules then return nil end
  opts = type(opts) == "table" and opts or {}
  if type(opts.Search) ~= "table" or type(opts.rows) ~= "table" then
    return nil
  end
  local self = setmetatable({
    game = game,
    screenId = "NationalDexSearch",
    Font = modules["src.render.Font"],
    Strings = modules["src.core.Strings"],
    NamingScreen = modules["src.ui.NamingScreen"],
    Theme = modules["src.ui.Theme"],
    Input = modules["src.core.Input"],
    Search = opts.Search,
    vocab = opts.vocab,
    rows = opts.rows,
    onPick = opts.onPick,
    text = "",
    focus = "field",       -- field | results
    index = 1,
    scroll = 0,
    matches = {},
  }, Screen)
  self:refresh()
  self:syncCapture()
  return self
end

-- Re-run the query.  Called on every keystroke: this is what "live" means,
-- and it is affordable because the name and type filters read records
-- already in memory and the move/ability ones read the generated index
-- rather than the 9.2 MB of extras shards behind it (src/searchindex.lua).
function Screen:refresh()
  self.query = self.Search.parse(self.text, self.vocab)
  self.matches = self.Search.match(self.rows, self.query, self.vocab)
  self.index = math.min(self.index, math.max(1, #self.matches))
  self.scroll = math.max(0, math.min(self.scroll,
    math.max(0, #self.matches - RESULT_ROWS)))
end

-- The keyboard path, installed on `self` -- never on the Screen class table
-- -- only while the field has focus.  See the big comment above requireAll
-- for why it cannot be a permanent method.
--
-- A key becomes TEXT (M.charFor answers something, or it is backspace) or it
-- gets FORWARDED to Input:keypressed, never both.  That split matters
-- because several of Input's default bindings collide head-on with
-- characters a real query needs: space is bound to the A button, and 'x' and
-- backspace are both bound to B (game/src/core/Input.lua DEFAULT_BINDINGS).
-- Typing "giga drain" or a species name with an x in it must not also queue
-- an A press on every space, and deleting a typo must not also pop the
-- screen -- so anything this field can hold is swallowed here and nothing
-- else touches Input for that keystroke.  Escape is carved out before that
-- split rather than folded into it: GB B's only two keyboard bindings (x,
-- backspace) are BOTH things the field consumes as text, so a keyboard
-- player mid-query would otherwise have no physical key left that reaches
-- B at all.  Everything else -- the d-pad, tab (SELECT), and any key this
-- field has no use for -- reaches Input:keypressed exactly as it would have
-- if this screen had never defined onKeyPressed, which is what lets
-- update()'s own input:wasPressed polling keep working while the field is
-- focused.
local function captureKey(self, key)
  if key == "escape" then
    self.game.stack:pop()
    return
  end
  local shift = shiftDown()
  if key == "backspace" or M.charFor(key, shift) ~= nil then
    local before = self.text
    self.text = M.edit(self.text, key, shift)
    if self.text ~= before then self:refresh() end
    return
  end
  self.Input:keypressed(key)
end

-- Keeps self.onKeyPressed in step with self.focus: present (captureKey)
-- while the field can take text, nil the instant it cannot, so Game's
-- top.onKeyPressed check (game/src/core/Game.lua:615) only ever finds a
-- truthy field for as long as there is somewhere for a typed character to
-- go.  Called once at construction and again at both focus transitions in
-- update() below.
function Screen:syncCapture()
  self.onKeyPressed = (self.focus == "field") and captureKey or nil
end

function Screen:update(_dt)
  local input = self.game and self.game.input
  if type(input) ~= "table" or type(input.wasPressed) ~= "function" then
    return
  end

  -- START closes what START opened, and B closes it too.
  --
  -- The toggle is Gold's own convention rather than an invention: the cart's
  -- search is opened with START and left with `b or start`
  -- (game/src/ui/gen2/PokedexMenu.lua:383, 1329), so the key that reaches a
  -- screen is the key that leaves it.  Both games open this screen with START
  -- now -- Escape on a desktop keyboard -- so both leave it the same way.
  --
  -- Closing on the same press cannot bounce straight back in: the listing
  -- underneath reads START too, but StateStack:update runs ONLY the top state
  -- (src/core/StateStack.lua:60-63), so the frame this pops on is a frame the
  -- listing never updates, and wasPressed has gone false by the next one.
  if input:wasPressed("b") or input:wasPressed("start") then
    self.game.stack:pop()
    return
  end

  -- LEFT/RIGHT advance the first ambiguous term and re-run the match, read on
  -- BOTH halves of the screen: a player who has already walked into the
  -- results is exactly the player who just noticed the guess was wrong, and
  -- making them walk back to the field to fix it would defeat the point of
  -- the reading row.
  --
  -- This used to be SELECT, which now closes the screen.  LEFT/RIGHT are free
  -- on both games' search screens and are what the cart already used to step
  -- a value here -- its TYPE1/TYPE2 wheels moved on exactly these two keys
  -- (game/src/ui/gen2/PokedexMenu.lua:1325-1328) -- so the gesture is the
  -- screen's own rather than a third convention.
  if input:wasPressed("select") then
    if self.Search.cycle(self.query) then
      self.matches = self.Search.match(self.rows, self.query, self.vocab)
      self.index = math.min(self.index, math.max(1, #self.matches))
      self.scroll = math.max(0, math.min(self.scroll,
        math.max(0, #self.matches - RESULT_ROWS)))
    end
    return
  end

  if self.focus == "field" then
    -- A on the field is the pad's way in: the engine's own naming screen,
    -- pushed on the stack, which pops itself and hands the string back
    -- through onDone.  `default` (not `initial` -- src/ui/NamingScreen.lua
    -- has no such field) is what NamingScreen falls back to on an empty
    -- confirm, which is the closest this screen can come to "leave what was
    -- already typed alone" without inventing prefill the naming grid does
    -- not support.  `maxLen`, not `maxLength`: that is the field
    -- NamingScreen.new actually reads.
    if input:wasPressed("a") then
      self.game.stack:push(self.NamingScreen.new(self.game, {
        title = self.Strings("SEARCH"),
        maxLen = M.MAX_LEN,
        default = self.text,
        onDone = function(value)
          if type(value) == "string" then
            self.text = value
            self:refresh()
          end
        end,
      }))
      return
    end
    if input:wasPressed("down") and #self.matches > 0 then
      self.focus = "results"
      self:syncCapture()
    end
    return
  end

  -- focus == "results"
  if input:wasPressed("up") then
    if self.index <= 1 then
      self.focus = "field"
      self:syncCapture()
    else
      self.index = self.index - 1
      if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
    end
    return
  end
  if input:wasPressed("down") then
    if self.index < #self.matches then
      self.index = self.index + 1
      if self.index - self.scroll > RESULT_ROWS then
        self.scroll = self.index - RESULT_ROWS
      end
    end
    return
  end
  if input:wasPressed("a") then
    local row = self.rows[self.matches[self.index]]
    if row and self.onPick then self.onPick(row) end
  end
end

function Screen:draw()
  local Font, Strings, Theme = self.Font, self.Strings, self.Theme
  love.graphics.setColor(0, 0, 0, 1)

  -- "SEARCH" is this screen's own authored label, so it goes through
  -- Strings; self.text is what the PLAYER typed and Search.summary/the row
  -- labels below are DATA (a query reading, a species name) -- none of that
  -- belongs in the translation catalog, the same distinction
  -- src/ui/DexEntryMenu.lua draws between Strings("No.") and def.name.
  Font.draw(Strings("SEARCH"), 8, 4)

  -- The field text is measured like every other string on this screen
  -- (Font.width, not a character count).  MAX_LEN is only arithmetically
  -- safe under the shipped tile font's flat 8px advance -- Font.lua also
  -- supports a per-page `advance` override and a whole ttf table for a
  -- translation, either of which could make 18 glyphs wider than the row.
  -- The budget stops one glyph short of the row's own right margin so the
  -- cursor drawn after the text always lands on-canvas too.
  local fieldBudget = 160 - 8 - 8 - 8 -- canvas, left margin, right margin, cursor
  local fieldText = M.fit(self.text, fieldBudget, Font.width)
  Font.draw(fieldText, 8, 16)
  if self.focus == "field" then
    -- Every cursor on this screen is the tile the rest of the engine draws
    -- its own with (Theme.cursor, the filled arrow charmap.asm calls $ED --
    -- ListMenu.lua:246, Menu.lua:140, NamingScreen.lua:209).  '_' and '>'
    -- both fall through Font.encode to the space glyph and log "font: no
    -- glyph for" doing it -- confirmed by this file's own RENDERABLE table
    -- above, which already lists both as absent from the charmap.
    -- drawCode takes a raw glyph code, never a string, so it never goes
    -- through that lookup at all.
    Font.drawCode(Theme.cursor, 8 + Font.width(fieldText), 16)
  end

  -- The empty field says what it is for.
  --
  -- An empty row next to a cursor is the one thing on this screen that gives
  -- no sign of being a text field at all -- the first build shipped exactly
  -- that, and it read as a broken screen rather than as an invitation.  The
  -- prompt is drawn only while the field is genuinely empty, so it can never
  -- be mistaken for something the player typed, and it sits AFTER the cursor
  -- so the caret still marks where the first letter will land.
  if self.text == "" then
    Font.draw(M.fit(Strings("NAME OR TYPE"), fieldBudget - 8, Font.width),
      8 + Font.width(fieldText) + 8, 16)
  end

  local count = tostring(#self.matches)
  local countX = 160 - 8 - Font.width(count)
  -- Budget for the reading row stops short of the count column by a 4px
  -- gap, so a long reading truncates before it can run under the number
  -- rather than overlapping it.
  local summary = M.fit(self.Search.summary(self.query), countX - 8 - 4, Font.width)
  if summary ~= "" then Font.draw(summary, 8, 28) end
  Font.draw(count, countX, 28)

  for offset = 1, RESULT_ROWS do
    local position = self.scroll + offset
    local row = self.rows[self.matches[position]]
    if not row then break end
    local y = 40 + (offset - 1) * 8
    local label = ("%03d %s"):format(row.dex,
      row.known and row.name or "-----")
    -- Row text starts at x=16 (room for the cursor tile at x=8) and stops
    -- 8px short of the right edge, matching every other margin on this
    -- screen; a name long enough to reach it truncates instead of running
    -- off, which a generated species list makes an ordinary case rather
    -- than an edge one.
    label = M.fit(label, 160 - 8 - 16, Font.width)
    Font.draw(label, 16, y)
    if self.focus == "results" and position == self.index then
      Font.drawCode(Theme.cursor, 8, y)
    end
  end

  -- The key legend, below the seven result rows and inside the bottom margin.
  --
  -- Not decoration.  Every other way into this dex announces itself -- the
  -- listing prints its own title and its view-mode tag, and Gold's old search
  -- printed TYPE1, TYPE2, BEGIN SEARCH!! and CANCEL -- while this screen is a
  -- field, a cursor and a number.  Without a legend the first thing a player
  -- meets is a box that gives no sign of taking input at all.
  --
  -- SELECT is named only while a term is actually ambiguous.  Naming a key
  -- that does nothing on the current query is worse than naming none: it
  -- invites a press, nothing moves, and the player learns to distrust the row.
  --
  -- Written to the same rules as every other string here: measured and
  -- truncated, and built only from characters the charmap carries.
  if self.Search.ambiguous(self.query) then
    Font.draw(M.fit(Strings("SELECT SWAPS"), 160 - 16, Font.width), 8, 104)
  end
  Font.draw(M.fit(Strings(self.focus == "field"
    and "A TYPE  B BACK" or "A OPEN  B BACK"), 160 - 16, Font.width), 8, 116)

  love.graphics.setColor(1, 1, 1, 1)
end

return M
