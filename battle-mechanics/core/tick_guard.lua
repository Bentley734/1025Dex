-- core/tick_guard.lua -- the engine-tick recursion brake (round 262).
--
-- WHY THIS EXISTS
-- GAME SPEED runs the 1/60 logic step N times per rendered frame
-- (src/core/FixedStep.lua: Game:update feeds dt*speed into FixedStep:update,
-- whose while-loop calls the step callback once per whole step).  A
-- fast-forwarded conversation, menu or script therefore does N times the work
-- per real frame -- and, crucially, buys at least one whole step every single
-- frame even from a tiny leftover accumulator.
--
-- That turns an ordinary re-entrancy into a stack overflow.  If anything
-- inside a logic step synchronously pulls the FRAME loop back in -- a screen's
-- :update calling Game:update / PlatformHooks.update / love.update again, a
-- mod's core.update wrapper re-entering the chain, a menu callback re-opening
-- its own owner -- then FixedStep:update runs again INSIDE the step it is
-- already running.  At 1X the nested accumulator almost never reaches a whole
-- step, so the nested pass is a harmless no-op; at a high multiplier the
-- nested pass always buys steps, each of which can nest again, and the
-- nesting grows without bound until the Lua stack dies -- the "stack
-- overflow" whose traceback runs love.update (main.lua's PlatformHooks.update)
-- -> src/mods/Hooks.lua's core.update chain -> [C] error.  The user report is
-- exact: too many requests are allowed through, and at speed they are hoarded
-- until the stack overflows.
--
-- WHAT IT DOES
-- Three fail-open brakes.  "Fail-open" is the contract: a brake only skips
-- work that is already redundant or already pathological, logs a rate-limited
-- warning, and NEVER changes a healthy frame.  Every entry point is wrapped so
-- a failure here degrades to "guard absent", exactly like every other
-- subsystem in this mod.
--
--   1. core.update RE-ENTRANCY IS COALESCED, NOT RECURSED.  The frame loop's
--      one process-wide entry (main.lua -> src/core/PlatformHooks.update ->
--      Runtime.call("core.update", ...)) is wrapped outermost.  A call that
--      arrives while the chain is already running is parked in a ONE-SLOT
--      queue and returns immediately (debounce); the outermost call drains
--      that slot iteratively after it unwinds, so N nested frame requests cost
--      ONE stack frame instead of N.  This is the "decouple the trigger from
--      the execution" half of the fix: the re-entrant caller stops blocking on
--      a deeper frame, and the engine runs the genuinely-wanted extra frame
--      once, flat.
--
--   2. FixedStep:update HAS AN EXPLICIT RECURSION DEPTH LIMIT.  The shared
--      fixed-step driver (Gen 1, Gen 2 and Game 3 all call it) counts its own
--      nesting; past MAX_STEP_DEPTH the nested call is REFUSED rather than
--      recursed.  This catches a re-entry that bypassed the core.update chain
--      entirely (a direct Game:update, the test driver's stepping loop).  The
--      same wrap clamps self.maxAccum so a single call's catch-up ceiling can
--      never be raised above the engine's own 0.25s / 15-step cap -- a
--      throttle on how much wall-clock debt one frame may spend at once.
--
--   3. StateStack:push HAS A HARD STATE CEILING.  A screen that (through a
--      bug) re-opens itself every tick would otherwise hoard an unbounded
--      stack; past MAX_STACK_STATES further pushes are refused.  Normal play
--      never sees more than a couple of dozen states, so this cannot fire on a
--      healthy game -- it exists so "hoarding" has a floor.
--
-- EXPORTS
--   mod.exports.tickGuard.defer(fn, ...) -> boolean
--     Queue a task to run at the START of the next frame tick instead of now.
--     This is the general-purpose "asynchronous task queue" primitive: a
--     trigger handler that must not re-enter the frame loop (an NPC
--     interaction, a menu callback that wants to open another screen) calls
--     defer() and the work runs once, flat, on the next tick.  The queue is
--     bounded (MAX_DEFERRED); a full queue drops with a rate-limited warning
--     rather than growing without bound.
--   mod.exports.tickGuard.active() -> boolean, number
--     True while a frame tick is in progress, plus the current nesting depth.
--   mod.exports.tickGuard.stats() -> table
--     Counters for every brake (re-entrant ticks coalesced/suppressed, nested
--     steps refused, deferred tasks run/dropped, pushes refused).
--
-- Deliberately NOT done here: nothing in this file knows what a battle, an NPC
-- or a menu is.  It is a primitive, so it stays useful to every other
-- subsystem and every other mod on the same engine.
return function(mod)
  local unpack = table.unpack or unpack

  -- ------------------------------------------------------------------ ceilings
  -- A frame may nest this many core.update passes before further re-entries are
  -- dropped outright (the coalescer already collapses them; this is the hard
  -- stop behind it).  Normal play is depth 1, so 3 is unreachable when healthy.
  local MAX_TICK_DEPTH = 3
  -- Nested FixedStep:update passes refused past this depth.  Normal play is 1.
  local MAX_STEP_DEPTH = 4
  -- Worst-case frame tick: MAX_ACCUM (0.25s) / the 1/60s step = 15 steps.  The
  -- throttle below never lets one call spend more catch-up debt than that,
  -- whatever maxAccum some other code may have left behind.
  local MAX_STEPS_PER_CALL = 15
  -- Iterative drain budget: the most extra flat frames one outermost tick will
  -- run for its coalesced re-entries before it stops and waits for next frame.
  local MAX_DRAINS = 4
  -- Bounded task queue (see defer).
  local MAX_DEFERRED = 256
  -- The most states the screen stack may hold before further pushes are refused.
  local MAX_STACK_STATES = 256

  -- ------------------------------------------------------------------- state
  local tickDepth = 0            -- nested core.update passes right now
  local stepDepth = 0            -- nested FixedStep:update passes right now
  local pendingTick = nil        -- one-slot coalescer: { game = ..., dt = ... }
  local deferred, deferredN = {}, 0
  local stats = {
    ticks = 0,
    reentrantTicks = 0,    -- nested core.update calls seen
    reentrantDropped = 0,  -- nested calls dropped past MAX_TICK_DEPTH
    extraFrames = 0,       -- flat extra frames run by the drain
    nestedSteps = 0,       -- FixedStep passes refused past MAX_STEP_DEPTH
    deferredRun = 0,
    deferredDropped = 0,
    pushesRefused = 0,
  }
  local warnSeen = {}

  -- One rate-limited line per distinct trip: first occurrence, then one every
  -- 600 to prove it is still happening without flooding the mod manager's log.
  -- mod.log:warn runs its message through string.format, so a literal % in a
  -- message has to be doubled or the logger itself throws while reporting.
  local function warnRateLimited(key, message)
    local n = (warnSeen[key] or 0) + 1
    warnSeen[key] = n
    if n ~= 1 and n % 600 ~= 0 then return end
    local suffix = n > 1 and (" (x" .. n .. ")") or ""
    mod.log:warn("g9-battle-engine: tick_guard: "
      .. tostring(message):gsub("%%", "%%%%") .. suffix)
  end

  -- -------------------------------------------------------------------- queue
  local M = {}

  -- Queue fn to run at the start of the next frame tick.  Arguments are packed
  -- so a nil in the middle survives the round-trip.  A full queue is a dropped
  -- task, not a growing table and never an error.
  function M.defer(fn, ...)
    if type(fn) ~= "function" then return false end
    if deferredN >= MAX_DEFERRED then
      stats.deferredDropped = stats.deferredDropped + 1
      warnRateLimited("defer-full",
        "deferred task queue full; dropping the request")
      return false
    end
    local n = select("#", ...)
    deferredN = deferredN + 1
    deferred[deferredN] = { fn = fn, n = n, args = { ... } }
    return true
  end

  -- Run everything queued so far, once, flat.  Swap the table out first so a
  -- task that defers again lands in the NEXT frame's batch instead of
  -- extending this drain (a task that re-defers itself can never spin here).
  function M.drainDeferred()
    if deferredN == 0 then return end
    local batch = deferred
    deferred, deferredN = {}, 0
    for i = 1, #batch do
      local item = batch[i]
      local ok, err = pcall(item.fn, unpack(item.args, 1, item.n))
      if not ok then
        warnRateLimited("defer-error", "deferred task errored: " .. tostring(err))
      end
      stats.deferredRun = stats.deferredRun + 1
    end
  end

  function M.active()
    return tickDepth > 0, tickDepth
  end

  function M.stats()
    local out = {}
    for k, v in pairs(stats) do out[k] = v end
    out.tickDepth, out.stepDepth = tickDepth, stepDepth
    out.deferredQueued = deferredN
    return out
  end

  -- ------------------------------------------------- 1. core.update coalescer
  -- Outermost in the core.update chain (priority well above every gameplay
  -- wrap), so a re-entry is seen before any other link runs.  `next` is the
  -- rest of the chain and eventually the vanilla g:update(d).
  local function installTickCoalescer()
    mod.hooks:wrap("core.update", function(next, game, dt)
      if tickDepth > 0 then
        -- A frame request arrived from inside a frame.  Do not recurse: park
        -- it (one slot -- a burst debounces to a single extra frame) and hand
        -- control straight back to the step that asked.  The outermost call
        -- below will run it flat once it unwinds.
        stats.reentrantTicks = stats.reentrantTicks + 1
        if tickDepth < MAX_TICK_DEPTH then
          pendingTick = { game = game, dt = dt }
          warnRateLimited("reentrant-tick",
            "re-entrant core.update coalesced into one deferred frame")
        else
          stats.reentrantDropped = stats.reentrantDropped + 1
          warnRateLimited("reentrant-deep",
            "re-entrant core.update past the depth limit; dropped")
        end
        return
      end

      tickDepth = 1
      stats.ticks = stats.ticks + 1
      local drains = 0
      local curGame, curDt = game, dt
      local ok, err = pcall(function()
        M.drainDeferred()
        while true do
          if type(next) == "function" then next(curGame, curDt) end
          local pending = pendingTick
          if not pending or drains >= MAX_DRAINS then
            pendingTick = nil
            break
          end
          pendingTick = nil
          drains = drains + 1
          stats.extraFrames = stats.extraFrames + 1
          curGame = pending.game or curGame
          curDt = pending.dt or curDt
          M.drainDeferred()
        end
      end)
      tickDepth = 0
      pendingTick = nil
      if not ok then error(err, 0) end
    end, 100000)
  end

  -- ------------------------------------------------ 2. FixedStep depth limit
  -- The shared driver, so one wrap covers every generation.  The module table
  -- is the live singleton both Game and Game2 hold, so patching the method
  -- here reaches their call sites (they resolve .update at call time).
  local function installStepLimit()
    local okR, FixedStep = pcall(require, "src.core.FixedStep")
    if not (okR and type(FixedStep) == "table"
        and type(FixedStep.update) == "function") then
      return false
    end
    if FixedStep.__g9TickGuard then return true end
    FixedStep.__g9TickGuard = true
    local nativeUpdate = FixedStep.update
    local hardCap = tonumber(FixedStep.MAX_ACCUM) or 0.25
    -- One call may buy at most MAX_STEPS_PER_CALL whole steps; never below the
    -- engine's own ceiling, so this can only ever bite a raised maxAccum.
    local maxAccumClamp = (tonumber(FixedStep.STEP) or (1 / 60)) * MAX_STEPS_PER_CALL
    if maxAccumClamp < hardCap then maxAccumClamp = hardCap end

    function FixedStep:update(dt, speed)
      if stepDepth >= MAX_STEP_DEPTH then
        -- Explicit recursion depth limit: refuse to nest another step pass.
        stats.nestedSteps = stats.nestedSteps + 1
        warnRateLimited("nested-step",
          "nested FixedStep:update past the depth limit; refusing the pass")
        return
      end
      -- Throttle: one call may never spend more than the engine's own
      -- catch-up ceiling, even if something raised maxAccum.
      local accum = self and self.maxAccum
      if type(accum) == "number" and accum > maxAccumClamp then
        self.maxAccum = maxAccumClamp
      end
      stepDepth = stepDepth + 1
      local ok, err = pcall(nativeUpdate, self, dt, speed)
      stepDepth = stepDepth - 1
      if not ok then error(err, 0) end
    end
    return true
  end

  -- ------------------------------------------------- 3. StateStack hard ceiling
  local function installStackCeiling()
    local okR, StateStack = pcall(require, "src.core.StateStack")
    if not (okR and type(StateStack) == "table"
        and type(StateStack.push) == "function") then
      return false
    end
    if StateStack.__g9TickGuard then return true end
    StateStack.__g9TickGuard = true
    local nativePush = StateStack.push
    StateStack.push = function(self, state, ...)
      local states = self and self.states
      if type(states) == "table" and #states >= MAX_STACK_STATES then
        stats.pushesRefused = stats.pushesRefused + 1
        warnRateLimited("stack-full",
          "screen stack at the safety ceiling; refusing a push")
        return
      end
      return nativePush(self, state, ...)
    end
    return true
  end

  -- ------------------------------------------------------------------- install
  installTickCoalescer()
  local steps = installStepLimit()
  local stack = installStackCeiling()

  mod.exports.tickGuard = {
    defer = M.defer,
    drainDeferred = M.drainDeferred,
    active = M.active,
    stats = M.stats,
    MAX_TICK_DEPTH = MAX_TICK_DEPTH,
    MAX_STEP_DEPTH = MAX_STEP_DEPTH,
    MAX_DEFERRED = MAX_DEFERRED,
  }

  mod.log:info(
    "g9-battle-engine: tick_guard installed (core.update coalescer, FixedStep depth limit %s, stack ceiling %s; tickGuard.defer exported)",
    steps and "on" or "off", stack and "on" or "off")
end
