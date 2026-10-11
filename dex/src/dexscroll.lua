-- Hold UP or DOWN on a Pokédex LISTING and the cursor accelerates the longer
-- the direction is held; hold LEFT or RIGHT on either listing and its page
-- jump repeats too, on a clock of its own.  With the national dex on, that
-- list is 1025 rows long and every screen that draws it moves the cursor one
-- row per press.
--
-- Three profiles live here and only two things are shared between them: the
-- shape (a delay, then a repeat rate, then faster tiers) and M.rate / M.delay,
-- which read a profile.  The NUMBERS are three separate tables -- see GEN1,
-- GEN2 and PAGE below for what each of them is measured against.  GEN1 and
-- GEN2 currently hold the same numbers and are still written out twice, for
-- the reason spelled out over GEN2.
--
-- Only the Gen 1 arm is installed from this file.  Gold's listing is its own
-- class and every patch of it lives in src/gen2dexlist.lua, so that file is
-- handed this module and drives GEN2 and PAGE itself; the alternative was a
-- second wrapper of the same method from a second file, which is how two
-- patches of one class end up disagreeing about who runs first.
--
-- Everything above M.install is pure -- no love, no engine module, no mod
-- handle -- so the tier arithmetic is driven by tests with plain numbers.

local M = {}

-- ------------------------------------------------------------- pure logic

-- A profile is { delay = frames before the first repeat, tiers = { { held,
-- rate }, ... } }, where `rate` is the number of frames between repeats once
-- the direction has been held for `held` frames.  Frames, not seconds:
-- src/core/FixedStep.lua advances game logic in whole 1/60s steps whatever the
-- display is doing, and the engine's own list repeat counts the same unit.
--
-- The rate a tier names is also the overshoot it costs.  Reaction time is
-- roughly a fifth of a second, so a player who sees the row they wanted go
-- past releases about 12 frames later: at one row per frame that is a dozen
-- rows of backtracking, and at one row every four it is three.  That, rather
-- than how fast a cursor can be made to move, is what picks the numbers below
-- -- a scroll nobody can stop on the row they were aiming at is not a faster
-- way to arrive anywhere.
--
-- Gen 1.  The delay is the engine's OWN (src/ui/ListMenu.lua:21 REPEAT_DELAY
-- 16), copied rather than chosen: it is already what this engine means by a
-- held list everywhere else, and a bit over a quarter second is long enough
-- that a brisk tap never repeats.
--
-- The RATES are this mod's own, and every one of them is a frame slower than
-- the first pass at this profile (6 / 4 / 3).  That pass came back from play
-- as still a shade too quick to stop on a row, which is the one failure this
-- table exists to avoid: the rate a tier names is the overshoot it costs, so a
-- profile a player cannot stop on has bought nothing with its speed.
--
-- 7 frames -- 8.6 rows a second -- is the opening one, which is the rate a
-- player is actually using when the target is a few rows from where the cursor
-- already sits.  90 held frames (a second and a half, by which point a dozen
-- rows have gone by and the direction is still down) goes to 5, and 240 (four
-- seconds) to 4, which is the top and is the engine's OWN flat rate
-- (src/ui/ListMenu.lua:22 REPEAT_RATE): nothing in this dex is driven harder
-- than a stock list of this engine's, and every row still stands for four
-- frames, so the numbers going past stay readable and stopping on one of them
-- is a thing a player can do.
--
-- It can afford to stop at 4 because crossing the list is not this profile's
-- job.  LEFT/RIGHT jump a whole page on this screen and no other list of this
-- engine's turns that on (src/ui/PokedexMenu.lua:58 `pageJump = true`) -- and
-- they repeat while held, which is what PAGE below is for.
M.GEN1 = { delay = 16, tiers = { { 0, 7 }, { 90, 5 }, { 240, 4 } } }

-- Gold.  The same numbers, and that is the change rather than an oversight.
--
-- They used to be sooner and quicker at every tier (10, then 5 / 3 / 2), and
-- the reason was a real one: src/ui/gen2/PokedexMenu.lua:358-392 reads B,
-- SELECT, START, UP, DOWN and A on that screen and LEFT/RIGHT nowhere, so a
-- held direction was the only way to cross 1025 rows at all.  That reason is
-- gone -- src/gen2dexlist.lua now binds the same LEFT/RIGHT page jump Gen 1
-- has, on the PAGE clock below -- and with it goes the case for Gold being the
-- one listing in the engine that scrolls faster than every other.  Its old top
-- tier was a row every two frames, thirty a second, which came back from play
-- as unusable rather than as fast: a scrollbar (SCROLLBAR_X/TRAVEL, :130-132)
-- tells a player roughly where they are, which is not the same as letting them
-- stop where they meant to.
--
-- Both listings window seven rows and now offer a player the same two tools,
-- so there is nothing left for them to disagree about and they hold the same
-- clock.  Written out twice rather than aliased to GEN1: they are two screens
-- of two different games, and retuning one of them must not silently retune
-- the other from a line that does not mention it.
M.GEN2 = { delay = 16, tiers = { { 0, 7 }, { 90, 5 }, { 240, 4 } } }

-- The page jump, held -- one profile for both games, because it is one gesture
-- doing one thing.  Gen 1's jump is the engine's own (ListMenu.lua:126-129
-- moves the cursor by self.rows); Gold's class has none, so
-- src/gen2dexlist.lua steps it by the row count that listing windows.  Seven
-- rows either way.
--
-- One repeat here is therefore not one row but SEVEN, which is why this cannot
-- be the row profile under another name and why the feature was left on taps
-- alone until it had one: armed at the row numbers a held LEFT crosses 60 rows
-- a second before any tier arrives, and 105 once one does.
--
-- 20 frames of delay, longer than the row delay on purpose.  A tapped page
-- jump is a deliberate single action -- a player taps RIGHT to read the next
-- seven rows -- and a press firm enough to hold for a third of a second must
-- not skip the page they meant to read.
--
-- Then one page every 10 frames: six pages a second, 42 rows a second, so the
-- far end of 1025 rows is about 25 seconds away and this stays the tool for
-- crossing the list while the row profile stays the tool for landing on a row.
-- A page holds perfectly still for its ten frames, which is what makes that
-- throughput legible when the same rows streaming past one at a time would not
-- be.  No tiers: at seven rows a step the list is not long enough to need a
-- second gear, and accelerating would only make the far end harder to stop at.
M.PAGE = { delay = 20, tiers = { { 0, 10 } } }

-- Frames between repeats for a direction that has now been held `frames`
-- steps.  The last tier whose threshold has been reached wins, so the table
-- reads in the order the tiers arrive.  Guarded rather than indexed: this is
-- handed to a class patch of the engine's, and answering a safe 1-frame-per-
-- step for a malformed profile is worse than answering the slowest rate there
-- is, so an unusable profile falls back to the engine's own 4.
function M.rate(profile, frames)
  local tiers = type(profile) == "table" and profile.tiers or nil
  if type(tiers) ~= "table" or type(frames) ~= "number" then return 4 end
  local rate = nil
  for i = 1, #tiers do
    local tier = tiers[i]
    if type(tier) == "table" and type(tier[1]) == "number"
      and type(tier[2]) == "number" and frames >= tier[1] then
      rate = tier[2]
    end
  end
  if type(rate) ~= "number" then return 4 end
  -- A rate of 0 would be a division by zero inside the engine's modulus, and
  -- a fractional one would never be 0 modulo anything -- both are "this list
  -- never repeats again", which is the one answer this must not give.
  return math.max(1, math.floor(rate))
end

-- Frames a profile waits before its first repeat, floored at TWO.
--
-- The floor is what makes switching profiles mid-hold safe.  The engine reads
-- repeatDelay in the middle of its own update and this module writes it at the
-- end of one, so the frame a NEW direction is edged on is still measured
-- against the delay the previous direction left behind -- there is nowhere
-- earlier to write it from without reimplementing the engine's branch.  On
-- that one frame the held count is exactly 1, so any delay of 2 or more cannot
-- fire; a delay of 1 or 0 would turn the stale frame into an instant repeat
-- and a tapped page jump into a double one.  Falls back to the engine's own 16
-- for a profile it cannot read, for the same reason M.rate falls back to 4.
function M.delay(profile)
  local frames = type(profile) == "table" and profile.delay or nil
  if type(frames) ~= "number" then return 16 end
  return math.max(2, math.floor(frames))
end

-- ------------------------------------------------------------ engine patch

-- Applies the Gen 1 profile to one built list, or answers false for an object
-- that is not the engine's list at all.  The engine already owns the whole
-- mechanism -- src/ui/ListMenu.lua:181-193 counts the held frames, and
-- navPressed behind it owns wrap, clamping and the scroll sync -- and it reads
-- self.repeatDelay and self.repeatRate back off the instance on EVERY frame.
-- So the tier is applied by writing that field, and none of the cursor
-- arithmetic is reimplemented here.  navPressed is a file-local anyway; a copy
-- of it is exactly how a held direction and a tapped one would end up
-- disagreeing about what happens at the ends of the list.
--
-- The wrap is written onto the INSTANCE, never onto ListMenu: the bag, the
-- shops, the PC and the box are all the same class, and none of them asked
-- for this.
-- ------------------------------------------- a screen that counts nothing
--
-- src/ui/PokedexMenu.lua was a ListMenu until engine 48d8a4e9 (2026-08-27)
-- rewrote it as its own class.  It kept its cursor, its scroll sync and its
-- page jump; what it lost was the machinery accelerate() below leans on --
-- holdFrames, keyRepeat, repeatDelay/repeatRate.  Its update now reads edges
-- and nothing else, so there is no counter to write a tier into and the whole
-- feature simply stopped applying to the Gen 1 dex.
--
-- WHAT THIS DOES NOT DO IS REIMPLEMENT THE MOVEMENT.  The reason accelerate()
-- writes a field instead of moving a cursor is that navPressed owns wrap,
-- clamping and the scroll sync, and a copy of it is how a held direction and
-- a tapped one end up disagreeing about the ends of a list.  That reasoning
-- did not change when the counter went away -- so this counts the frames the
-- screen no longer counts, and then hands the work back by calling the
-- screen's OWN update behind an input that reports the held direction as
-- freshly pressed.  Every row it crosses is moved by the same branch a tap
-- moves, through the same syncScroll and the same pageScroll clamp.  A tap
-- and a hold cannot drift apart here because there is only one of them.
--
-- The proxy forwards everything else to the real input untouched, so a screen
-- reading some other button on that pass sees the truth about it; only
-- wasPressed(dir) is answered, and only on a frame the tier says to repeat.
local DIRECTIONS = { "up", "down", "left", "right" }

local function edgeProxy(input, dir)
  return setmetatable({}, { __index = function(_, key)
    if key == "wasPressed" then
      return function(_, button) return button == dir end
    end
    local value = input[key]
    if type(value) == "function" then
      return function(_, ...) return value(input, ...) end
    end
    return value
  end })
end

local function driveByEdge(list, profile)
  if type(list) ~= "table" or type(list.update) ~= "function" then return false end
  if type(list.game) ~= "table" or type(list.game.input) ~= "table" then
    return false
  end
  local originalUpdate = list.update
  local dir, frames = nil, 0
  list.update = function(self, dt)
    originalUpdate(self, dt)
    local input = self.game and self.game.input
    if type(input) ~= "table" or type(input.isDown) ~= "function" then
      dir, frames = nil, 0
      return
    end
    local down = nil
    for i = 1, #DIRECTIONS do
      if input:isDown(DIRECTIONS[i]) then down = DIRECTIONS[i] break end
    end
    if down == nil then dir, frames = nil, 0 return end
    -- A fresh EDGE restarts the count, the same thing ListMenu.lua:205-215
    -- does when it sets holdDir/holdFrames on wasPressed.  Keying off the
    -- edge rather than off "the direction changed" is what makes a second
    -- hold of the SAME direction start over: the key came up in between, and
    -- a counter that kept running through that would arrive at its first
    -- repeat before the player had held anything.
    local edged = type(input.wasPressed) == "function" and input:wasPressed(down)
    if edged or down ~= dir then dir, frames = down, 1 return end
    frames = frames + 1
    -- LEFT and RIGHT do not move a row on these screens, they move a whole
    -- window, so they are clocked by PAGE rather than by the row profile --
    -- the same split accelerate() makes below, for the same reason.
    local held = (dir == "left" or dir == "right") and M.PAGE or profile
    local after = frames - M.delay(held)
    if after < 0 or after % M.rate(held, frames) ~= 0 then return end
    local real = self.game.input
    self.game.input = edgeProxy(real, dir)
    local ok, err = pcall(originalUpdate, self, dt)
    self.game.input = real
    if not ok then error(err, 0) end
  end
  return true
end

local function accelerate(list, profile)
  -- Only what this actually needs: an update to wrap, and the held-frame
  -- counter it reads.  repeatDelay/repeatRate used to be required as numbers
  -- too -- but they are ASSIGNED two lines below, and ListMenu only sets them
  -- from opts (ListMenu.lua:71-72), so a list whose caller passes neither
  -- carries nil and was refused for lacking the very fields this was about to
  -- write.  A precondition on a value you are about to overwrite can only
  -- reject; it can never protect.
  if type(list) ~= "table" or type(list.update) ~= "function" then
    return false
  end
  -- A screen with no held-frame counter of its own is driven by edges
  -- instead; see driveByEdge above for why that is not a second cursor.
  if type(list.holdFrames) ~= "number" then
    return driveByEdge(list, profile)
  end
  list.keyRepeat = true
  list.repeatDelay = M.delay(profile)
  list.repeatRate = M.rate(profile, 1)
  local originalUpdate = list.update
  list.update = function(self, dt)
    originalUpdate(self, dt)
    -- WHICH profile depends on what is held, because LEFT and RIGHT do not
    -- move a row on this screen -- they move a whole page -- and the engine
    -- has one repeatDelay/repeatRate pair per list, not one per direction.
    -- So the pair is rewritten every frame to suit the direction the engine
    -- has armed, which is the whole of how the page jump gets a slower clock
    -- than the rows without a second counter existing anywhere.
    --
    -- Nothing here arms a direction the engine did not: it only counts
    -- left/right while self.pageJump is set (ListMenu.lua:159-164), so a
    -- listing without the page jump never reaches PAGE at all, and no key
    -- changes hands either way.
    local held = (self.holdDir == "left" or self.holdDir == "right")
      and M.PAGE or profile
    self.repeatDelay = M.delay(held)
    -- Set for the NEXT frame, and holdFrames + 1 is precisely the count that
    -- frame's repeat will be tested against: the engine's block increments
    -- the counter and then measures it against repeatRate in the same pass,
    -- so writing the rate for the count already on the instance would apply
    -- every tier one frame early.
    self.repeatRate = M.rate(held, self.holdFrames + 1)
  end
  return true
end

-- installed guards against a second install wrapping the wrapper -- main.lua
-- calls this once, but the class is process-global and a reload would
-- otherwise stack constructors until the call depth mattered.
local installed = false

-- `generation` is handed in rather than probed.  A mod's require is NOT
-- redirected on a Gold boot, so require("src.ui.PokedexMenu") answers with Gen
-- 1's class there too and this patch would land on a screen Gold never draws;
-- Gold's own listing is reached by its real name from src/gen2dexlist.lua.
--
-- The seam is the CONSTRUCTOR of the Gen 1 dex list rather than the screen id,
-- and that is what makes it reach both screens a player can actually meet: a
-- mod that replaces the "PokedexMenu" screen still builds the engine's own dex
-- list underneath and decorates it (useful_dex 1.3.0 does exactly that -- its
-- DexList.new calls require("src.ui.PokedexMenu").new and then sets wrap and
-- its SELECT handler on what comes back).  Wrapping the id would have taken
-- the screen off such a neighbour; wrapping the constructor rides underneath
-- it and takes nothing.
--
-- No key changes hands.  UP, DOWN, LEFT and RIGHT are all already this list's
-- own -- the first two move the cursor and the other two jump a page, and all
-- four are read by the engine's branch, never by this file -- while SELECT,
-- the one key useful_dex binds on it, is read neither here nor by the view
-- modes riding along below, which take START instead (src/dexview.lua).
--
-- `augment` is src/dexview.lua's entry, handed in by main.lua rather than
-- installed from its own file.  Two wrappers of one constructor are two
-- patches arguing about which of them runs first, which is the same reason
-- Gold's listing is handed this module instead of wrapping its class again.
function M.install(mod, generation, augment)
  if generation == 2 then return false end
  if installed then return false end
  local ok, PokedexMenu = pcall(require, "src.ui.PokedexMenu")
  if not ok or type(PokedexMenu) ~= "table"
    or type(PokedexMenu.new) ~= "function" then
    return false
  end
  installed = true

  local declined = false
  local function decline()
    if declined then return end
    declined = true
    if mod and mod.log then
      mod.log:info("the Pokédex listing is not this engine's own list -- "
        .. "hold-to-scroll needs its held-frame counter and stands down "
        .. "rather than guessing at another screen's cursor")
    end
  end

  -- src/dexview.lua reports its own reason for standing down, and it has
  -- several; this one is only for the case it could not report at all,
  -- which is a throw out of a call that is written never to throw.
  local declinedView = false
  local function declineViewCrash()
    if declinedView then return end
    declinedView = true
    if mod and mod.log then
      mod.log:info("the Pokédex listing's view modes raised on the way in -- "
        .. "the list keeps dex order and START does nothing")
    end
  end

  local originalNew = PokedexMenu.new
  function PokedexMenu.new(game, opts)
    local list = originalNew(game, opts)
    -- A throw here would degrade a neighbour's screen to the builtin one
    -- (src/ui/Screens.lua build) and cost that mod every feature it came
    -- with, so the whole augmentation is guarded and a failure simply leaves
    -- the list stepping one row per press.
    local applied, ran = pcall(accelerate, list, M.GEN1)
    if not (applied and ran) then decline() end
    -- The view modes ride the same constructor and are guarded the same way,
    -- and they are applied AFTER the acceleration on purpose: hold-to-scroll
    -- writes repeatDelay/repeatRate from inside its own update wrapper, so
    -- wrapping that wrapper leaves the tier arithmetic running underneath
    -- whichever order the rows are currently in.
    if augment then
      if not pcall(augment, list, mod) then declineViewCrash() end
    end
    return list
  end
  return true
end

setmetatable(M, { __call = function(_, mod, generation, augment)
  return M.install(mod, generation, augment)
end })

return M
