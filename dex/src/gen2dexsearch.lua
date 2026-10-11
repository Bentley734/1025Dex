-- Gold's Pokédex SEARCH screen.
--
-- The same query as Gen 1's (src/dexsearch.lua, shared rather than copied --
-- two matchers is how one search starts giving two games different answers),
-- drawn in Gold's own chrome.  It replaces the cart's two type wheels
-- outright: fire+flying is what TYPE1/TYPE2 expressed, and every other term
-- -- a name, a move, an ability -- is something the wheels could never reach.
--
-- A separate file from src/dexsearchview.lua because require() is NOT
-- redirected on a Gold boot: every engine class a mod names resolves to the
-- Gen 1 one unless it is asked for by its real Gen 2 name.  One file holding
-- both vocabularies would be wrong about one of the two games in every edit,
-- which is the same reason src/gen2dexlist.lua exists at all.

local M = {}

-- Named rather than required: this file cannot require a sibling of its own
-- mod (mod files load as chunks through mod:read), so main.lua hands the
-- module in.  The constant is here so a test can assert the two screens name
-- the same one.
M.SEARCH_MODULE = "src/dexsearch.lua"

-- Gold's listing windows seven rows and so does Gen 1's, so a result list is
-- the same shape of screen in both games.
M.RESULT_ROWS = 7

-- Whether the Game2 key dispatch below has already been wrapped.  install()
-- is called once per boot, but the class it patches is process-global and a
-- reload would otherwise stack wrappers until the call depth mattered -- the
-- same guard src/dexscroll.lua keeps for the same reason.
local Gen2Input = { installed = false }

-- Pokedex_DrawSearchScreenBG fills with this tile.  A local constant rather
-- than a reach into src/gen2dexlist.lua: that file keeps its own TILE_BG_ID
-- as a function local (around line 1794), not on its module table, and
-- exporting it purely to be read here would widen a surface for one number.
local TILE_BG = 0x32

-- The border this draws is the cart's own SEARCH box, unchanged
-- (Pokedex_DrawSearchScreenBG): a 14-interior-row, 18-interior-column frame
-- starting at (0, 2), which is exactly the eighteen rows the 20x18 GB grid
-- has once the title bar above it is accounted for.  Reusing its exact
-- dimensions is what keeps this screen inside the border a proven layout
-- already fits, rather than re-deriving one that might not.
local BOX_TOP, BOX_ROWS, BOX_COLS = 2, 14, 18

-- Column layout inside the box.  Column 0 and 19 are the border; column 1 is
-- the cursor gutter every Gold list uses (Chrome's own comment calls it that
-- for the ▶ this reuses); text starts at column 3 so a two-cell gap separates
-- the cursor from what it is pointing at, the same gap TYPE1/TYPE2 left for
-- the cart's own wheel labels.
local CURSOR_COL, TEXT_COL, TEXT_WIDTH = 1, 3, 16

-- Clips a string to `width` characters rather than let a query answer or a
-- species name run past the box's own border.  The font this screen prints
-- through is fixed-width (src/render/Font.lua's Font.width is #codes * 8 for
-- every page this mod's strings ever reach), so a character count is a cell
-- count and no pixel measurement is needed to know where to cut.
--
-- Not src/dexsearchview.lua's helper: that file belongs to the Gen 1 task
-- running alongside this one, and reaching into it would be one more thing
-- two screens have to agree on for a four-line function neither actually
-- shares logic with -- Gen 1 clips to its own font's cell width, not Gold's.
local function truncate(text, width)
  text = type(text) == "string" and text or ""
  if #text <= width then return text end
  return text:sub(1, width)
end

-- Guards a dev-mode hot reload from wrapping updateSearch/drawSearch a
-- second time around the first wrap -- src/dev/HotReload.lua re-runs every
-- mod file's top level, and a second install with no guard would capture the
-- FIRST install's wrapped methods as "original", chaining a new layer onto
-- the class every reload rather than replacing the layer that is already
-- there.
local installed = false

function M.install(PokedexMenu, deps)
  if installed then return false end
  if type(PokedexMenu) ~= "table" or type(deps) ~= "table" then return false end
  local Search = deps.Search
  if type(Search) ~= "table" or type(Search.parse) ~= "function"
    or type(Search.match) ~= "function" or type(Search.summary) ~= "function"
    or type(Search.cycle) ~= "function" then
    return false
  end
  -- Rows are the one thing this screen cannot function without -- without a
  -- describer there is nothing to search, and a screen that opened anyway
  -- would be a blank box with a working keyboard, which is worse than START
  -- doing nothing.
  if type(deps.describeRows) ~= "function" then return false end
  if type(PokedexMenu.updateSearch) ~= "function"
    or type(PokedexMenu.drawSearch) ~= "function"
    or type(PokedexMenu.beginSearch) ~= "function" then
    return false
  end
  -- Required here, guarded, rather than handed in: this file is only ever
  -- loaded on a Gold boot, so the Gen 2 name resolves to the Gen 2 class.
  local okChrome, Chrome = pcall(require, "src.ui.gen2.Chrome")
  if not okChrome or type(Chrome) ~= "table" then return false end

  -- The cap comes from src/dexsearchview.lua's M.MAX_LEN, handed over by
  -- main.lua: which key means which character, and how much of it fits on a
  -- row, are facts about a keyboard and a 160px canvas rather than about a
  -- generation, so the two screens must not carry separate numbers.
  --
  -- The fallback is deliberately SHORTER than that value rather than equal to
  -- it.  A second copy of the real number here is a number that goes stale
  -- the moment the other file retunes its own -- this comment already claimed
  -- 15 while that file said 18 -- and a cap that is too generous overflows
  -- the row, while one that is too tight merely stops a long query early.
  local maxLen = type(deps.MAX_LEN) == "number" and deps.MAX_LEN or 12

  -- Whether Game:keypressed reaches this instance at all is decided by
  -- whether self.onKeyPressed exists (game/src/core/Game.lua:614-617) -- not
  -- by what it does once called.  Defining it on the CLASS, as a method every
  -- view inherits, would intercept every physical key press on every one of
  -- this menu's views (list, entry, area, option) and stop them ever
  -- reaching Input:keypressed, because that dispatch never runs once a
  -- keypressed method is found.  So capture is an INSTANCE field, set only
  -- while the field is actually focused and cleared the moment it is not --
  -- syncCapture is the one place that decides which, called after every
  -- state change this screen makes.
  local captureKeys
  local function syncCapture(self)
    self.onKeyPressed =
      (self.view == "search" and self.nationalDexSearch
        and self.searchFocus == "field") and captureKeys or nil
  end

  -- Gold's own handle on Input, resolved once.  Capturing the keyboard means
  -- owning the whole of it: the dispatch below returns the moment it finds an
  -- onKeyPressed, so every key this function does not hand back is a key that
  -- never becomes a button press at all.
  -- deps.Input first so a headless test can hand in a recorder and assert
  -- what was forwarded; the require is the real boot's route.  Injected
  -- rather than reached for because a test cannot otherwise observe the
  -- hand-back at all -- and the hand-back, not the typing, is the half that
  -- silently strands a player when it is wrong.
  local Input = type(deps.Input) == "table" and deps.Input or nil
  if not Input then
    local okInput, required = pcall(require, "src.core.Input")
    if okInput and type(required) == "table" then Input = required end
  end

  -- Gold does not run on Game.  It runs on Game2, and the two disagree about
  -- who sees a key first:
  --
  --   Game:keypressed   (src/core/Game.lua:614-617)  gives stack:top() first
  --                     refusal through onKeyPressed, then falls to Input.
  --   Game2:keypressed  (src/core/Game2.lua:1724-1736) checks its host hotkeys
  --                     and goes straight to Input:keypressed.  It never looks
  --                     for onKeyPressed at all.
  --
  -- So on Gold a screen cannot take text however correctly it arms itself:
  -- every letter became a button press instead, and typing into the search
  -- field walked the cursor around because W, A, S and D are the d-pad.  The
  -- capture worked; nothing ever called it.
  --
  -- Game2's own comment says "A screen that is open owns the keyboard, the
  -- same way Game hands the top state first refusal" -- the intent is already
  -- written down, the dispatch to carry it out is just missing, so this adds
  -- it rather than inventing a policy.  Hotkeys keep winning first, because
  -- that same comment calls the display ladder a host control rather than a
  -- game button, and a screen taking text should not swallow it.
  --
  -- Scoped by construction: only a state that sets onKeyPressed is diverted,
  -- and on Gold this mod's search field is the only thing that ever does --
  -- and only while it holds focus.  Everything else reaches Input exactly as
  -- before.
  if not Gen2Input.installed then
    local okGame2, Game2 = pcall(require, "src.core.Game2")
    if okGame2 and type(Game2) == "table"
      and type(Game2.keypressed) == "function" then
      local originalKeypressed = Game2.keypressed
      function Game2:keypressed(key)
        local top = self.stack and self.stack:top()
        if top and type(top.onKeyPressed) == "function" then
          if type(self.hotkey) == "function" and self:hotkey(key) then return end
          top:onKeyPressed(key)
          return
        end
        return originalKeypressed(self, key)
      end
      Gen2Input.installed = true
    end
  end

  -- A key becomes TEXT or gets FORWARDED, never both -- the same split
  -- src/dexsearchview.lua makes, and for the same reason.  Several of Input's
  -- default bindings collide with characters a real query needs: space is
  -- bound to A, and 'x' and backspace are both bound to B
  -- (game/src/core/Input.lua DEFAULT_BINDINGS), so typing "giga drain" must
  -- not queue an A press on every space and deleting a typo must not pop the
  -- screen.
  --
  -- Everything else -- the d-pad, tab, any key the field has no use for --
  -- has to reach Input:keypressed exactly as it would if this screen defined
  -- no onKeyPressed at all.  Swallowing those was why a keyboard player could
  -- type into this field and then find DOWN, A and B all dead, with the
  -- on-screen keyboard the only thing that still worked.
  captureKeys = function(self, key)
    if key == "escape" then
      self.view = "list"
      syncCapture(self)
      return
    end
    local shift = type(deps.shiftDown) == "function" and deps.shiftDown() or false
    local isText = type(deps.charFor) == "function"
      and (key == "backspace" or deps.charFor(key, shift) ~= nil)
    if isText and type(deps.edit) == "function" then
      local before = self.searchText or ""
      self.searchText = deps.edit(before, key, shift)
      if self.searchText ~= before then self:refreshSearch() end
      return
    end
    if Input and type(Input.keypressed) == "function" then
      Input:keypressed(key)
    end
  end

  -- The rows and the vocabulary, built when the screen OPENS rather than at
  -- install time: the listing this reads is rebuilt whenever the mode
  -- changes (rebuild wraps deep in src/gen2dexlist.lua's own patch), so a
  -- vocabulary captured once at install would describe a list that no
  -- longer exists by the time a player actually searches it.
  --
  -- deps.describeRows is src/dexview.lua's M.describe, shared so both games
  -- decide what is on a listing with one function -- two describers reading
  -- the same two save tables is how two answers to one question drift apart.
  function PokedexMenu:beginSearch()
    self.nationalDexSearch = true
    local ok, rows = pcall(deps.describeRows, self.game)
    self.searchRows = (ok and type(rows) == "table") and rows or {}
    local vocab = { names = {}, types = {}, payload = deps.payload }
    for _, row in ipairs(self.searchRows) do
      vocab.names[Search.normalise(row.name)] = true
      for _, id in ipairs(row.types or {}) do
        vocab.types[Search.normalise(id)] = true
      end
    end
    self.searchVocab = vocab
    self.searchFocus = "field"
    self.searchIndex, self.searchScroll = 1, 0
    self:refreshSearch()
    syncCapture(self)
  end

  function PokedexMenu:refreshSearch()
    self.searchQuery = Search.parse(self.searchText or "", self.searchVocab)
    self.searchMatches = Search.match(self.searchRows or {}, self.searchQuery,
      self.searchVocab)
    self.searchIndex = math.max(1, math.min(self.searchIndex or 1,
      #self.searchMatches))
    self.searchScroll = math.max(0, math.min(self.searchScroll or 0,
      math.max(0, #self.searchMatches - M.RESULT_ROWS)))
    -- A query that just lost every match cannot leave the cursor sitting in
    -- an empty results pane -- SELECT can change the match count without the
    -- player ever pressing DOWN again to notice.
    if self.searchFocus == "results" and #self.searchMatches == 0 then
      self.searchFocus = "field"
    end
  end

  -- The pad's way into the field: Gold's own naming screen.  Nothing here
  -- invents a third keyboard -- the two that exist are the two the cartridges
  -- had.
  --
  -- The two classes differ in more than their grids, and BOTH differences bite
  -- a caller that assumes one from the other:
  --
  --   * opts.maxLength and opts.initial are this class's OWN option names
  --     (game/src/ui/gen2/NamingScreen.lua:97-108).  Gen 1's reads maxLen and
  --     has no prefill at all, and a caller passing Gen 1's spelling here gets
  --     the class default of 7 characters with no error to show for it.
  --   * WHO POPS.  Gen 1's screen pops itself and then calls back; Gold's
  --     accept() is only `if self.onDone then self.onDone(name) end`
  --     (game/src/ui/gen2/NamingScreen.lua:232-235) and never touches the
  --     stack.  The caller owns the pop, and owning it is not optional: END
  --     otherwise leaves the keyboard up for ever with no way back to the
  --     search, which is precisely what shipped in 0.22.0.
  function PokedexMenu:openSearchKeyboard()
    local NamingScreen = deps.NamingScreen
    if not NamingScreen then return end
    self.game.stack:push(NamingScreen.new(self.game, {
      prompt = "SEARCH",
      initial = self.searchText,
      maxLength = maxLen,
      onDone = function(value)
        -- Popped FIRST, before the value is read, which is the order
        -- game/src/ui/gen2/NamePick.lua:104 uses on this same class: the
        -- keyboard is finished either way, and leaving it on the stack while
        -- a refresh runs underneath it is how a screen ends up drawing over
        -- the one that is still meant to be on top.
        self.game.stack:pop()
        if type(value) == "string" then
          self.searchText = value
          self:refreshSearch()
        end
      end,
    }))
  end

  -- Open the entry for the row under the cursor.  Through the screen's own
  -- entry view rather than a second route into it: this class already knows
  -- how to show a species, and a second way in is a second thing to keep in
  -- step with the first.
  --
  -- Found by DEX NUMBER in a freshly rebuilt self.rows, not by the position
  -- searchRows happened to hold it at: self.rows is ordered by :order(),
  -- which is NEW (Johto) or A-Z order depending on the mode the player left
  -- the listing in, and searchRows -- deps.describeRows' own dex-NUMBER
  -- order -- agrees with that only by coincidence.  A captured index would
  -- open the wrong species the moment a player searched from anything but
  -- dex-number mode.
  function PokedexMenu:openSearchResult()
    local matched = self.searchRows[(self.searchMatches or {})[self.searchIndex]]
    if not matched then return end
    if type(self.rebuild) == "function" then pcall(self.rebuild, self) end
    local target = nil
    for index, row in ipairs(self.rows or {}) do
      if row.dex == matched.dex then
        target = index
        break
      end
    end
    if not target then return end
    self.index = target
    self.view = "entry"
    if type(self.ensureVisible) == "function" then pcall(self.ensureVisible, self) end
  end

  local function dispatchSearchInput(self, input)
    -- B or START, which is the CART's own pair on this screen: it opens the
    -- search with START (PokedexMenu.lua:383) and leaves it on
    -- `b or start` (PokedexMenu.lua:1329), so the key that reaches the screen
    -- is the key that leaves it.  Replacing the wheels dropped the START half
    -- and left B as the only way out -- a player who opened this screen with
    -- START and pressed it again to close found it did nothing.
    if input:wasPressed("b") or input:wasPressed("start") then
      self.view = "list"
      return
    end
    -- The reading swap.  Read on both halves of the screen, because a player
    -- who has already walked into the results is exactly the player who has
    -- just noticed the guess was wrong.
    -- LEFT/RIGHT rather than SELECT, matching Gen 1's screen key for key.
    -- SELECT is the cart's OPTION key on this menu and must stay free, and
    -- LEFT/RIGHT are what the cart's own search already used to step a value
    -- here (its TYPE1/TYPE2 wheels, PokedexMenu.lua:1325-1328), so this is
    -- the screen's own gesture rather than a third convention.
    if input:wasPressed("select") then
      if Search.cycle(self.searchQuery) then
        self.searchMatches = Search.match(self.searchRows, self.searchQuery,
          self.searchVocab)
        self.searchIndex, self.searchScroll = 1, 0
        -- The reading that just changed may have emptied the results the
        -- player was standing in.
        if self.searchFocus == "results" and #self.searchMatches == 0 then
          self.searchFocus = "field"
        end
      end
      return
    end
    if self.searchFocus == "field" then
      if input:wasPressed("a") then
        self:openSearchKeyboard()
        return
      end
      if input:wasPressed("down") and #(self.searchMatches or {}) > 0 then
        self.searchFocus = "results"
      end
      return
    end
    -- focus == "results": the ordinary dex list, one row per press.
    if input:wasPressed("up") then
      if (self.searchIndex or 1) <= 1 then
        self.searchFocus = "field"
      else
        self.searchIndex = self.searchIndex - 1
        if self.searchIndex - self.searchScroll < 1 then
          self.searchScroll = self.searchIndex - 1
        end
      end
      return
    end
    if input:wasPressed("down") then
      if self.searchIndex < #self.searchMatches then
        self.searchIndex = self.searchIndex + 1
        if self.searchIndex - self.searchScroll > M.RESULT_ROWS then
          self.searchScroll = self.searchIndex - M.RESULT_ROWS
        end
      end
      return
    end
    if input:wasPressed("a") then self:openSearchResult() end
  end

  local originalUpdateSearch = PokedexMenu.updateSearch
  function PokedexMenu:updateSearch(input)
    if not self.nationalDexSearch then
      return originalUpdateSearch and originalUpdateSearch(self, input)
    end
    dispatchSearchInput(self, input)
    -- Every branch above may have moved the focus or left the view
    -- altogether, and capture has to answer for whichever it was -- one call
    -- after the dispatch rather than one before each return, so a branch
    -- added later cannot forget it.
    syncCapture(self)
  end

  local originalDrawSearch = PokedexMenu.drawSearch
  function PokedexMenu:drawSearch()
    if not self.nationalDexSearch then
      return originalDrawSearch and originalDrawSearch(self)
    end
    self:fill(TILE_BG, 0, 0, Chrome.SCREEN_W, Chrome.SCREEN_H)
    self:border(0, BOX_TOP, BOX_ROWS, BOX_COLS)
    self:tile(0x3b, 0, 1)
    self:text(" SEARCH ", 1, 1)
    self:tile(0x3c, 9, 1)

    local fieldRow = BOX_TOP + 2
    if self.searchFocus == "field" then
      self:text("\xe2\x96\xb6", CURSOR_COL, fieldRow)
    end
    -- The empty field says what it is for.  An empty row beside a cursor is
    -- the one thing on this screen that gives no sign of being a text field,
    -- and the first build shipped exactly that -- it read as a broken screen
    -- rather than as an invitation.  Drawn only while the field is genuinely
    -- empty, so it can never be mistaken for something the player typed.
    local field = self.searchText or ""
    self:text(truncate(field ~= "" and field or "NAME OR TYPE", TEXT_WIDTH),
      TEXT_COL, fieldRow)

    local readingRow = fieldRow + 2
    self:text(truncate(Search.summary(self.searchQuery), 13), 1, readingRow)
    local count = tostring(#(self.searchMatches or {}))
    self:text(count, BOX_COLS + 1 - #count, readingRow)

    local firstResultRow = readingRow + 2
    for offset = 1, M.RESULT_ROWS do
      local position = (self.searchScroll or 0) + offset
      local row = self.searchRows[(self.searchMatches or {})[position]]
      if not row then break end
      local y = firstResultRow + offset - 1
      if self.searchFocus == "results" and position == self.searchIndex then
        self:text("\xe2\x96\xb6", CURSOR_COL, y)
      end
      self:text(truncate(("%03d %s"):format(row.dex,
        row.known and row.name or "-----"), TEXT_WIDTH), TEXT_COL, y)
    end

    -- The key legend, on the two interior rows the results cannot reach.
    --
    -- Not decoration.  The screen this replaced printed TYPE1, TYPE2, BEGIN
    -- SEARCH!! and CANCEL, so a player arriving on it could see what it was
    -- and how to work it; this one is a field, a cursor and a number, and
    -- without a legend the first thing a player meets is a black box that
    -- gives no sign of taking input at all.
    --
    -- SELECT is named only while a term is actually ambiguous.  Naming a key
    -- that does nothing on the current query is worse than naming none: it
    -- invites a press, the screen does not move, and the player learns to
    -- distrust the row.
    local legendRow = BOX_TOP + BOX_ROWS - 1
    if Search.ambiguous(self.searchQuery) then
      self:text(truncate("SELECT SWAPS", TEXT_WIDTH), TEXT_COL, legendRow)
    end
    self:text(truncate(self.searchFocus == "field"
      and "A TYPE  B BACK" or "A OPEN  B BACK", TEXT_WIDTH),
      TEXT_COL, legendRow + 1)
  end

  -- Set only once every wrap above has actually landed, so
  -- src/gen2dexlist.lua's own hook -- which calls self:beginSearch() the
  -- instant the view becomes "search" -- can tell whether that call reaches
  -- this file's beginSearch or the cart's own wheel-driven one.  Without the
  -- gate, calling beginSearch on the very frame START is pressed (before the
  -- player has touched anything) would run the CART's beginSearch on
  -- whatever self.searchType still holds, narrow the listing to one type and
  -- bounce straight back to "list" -- START would look broken rather than
  -- simply not yet wired to this file (see main.lua, Task 11).
  PokedexMenu.nationalDexSearchInstalled = true

  installed = true
  return true
end

setmetatable(M, { __call = function(_, PokedexMenu, deps)
  return M.install(PokedexMenu, deps)
end })

return M
