-- Universal Gen-1 move-effect guard (round 179, 2026-09-17).
--
-- THE BUG THIS EXISTS FOR. Reported live as:
--   src/battle/BattleState.lua:4411: bad argument #1 to 'ipairs'
--   (table expected, got nil)
--   ... [C] error <- src/mods/Hooks.lua:87 update <- main.lua:838 update
-- Gen 1's BattleState:performMove (:4383-4413) dispatches a pure status
-- move's effect as `local msgs = record.run(ctx)` and then walks the
-- RETURN value with `for _, m in ipairs(msgs)`. EffectRegistry.runDamaging
-- (:342-346) does the exact same thing for a damaging move's secondary
-- run. So ANY registered move_effects record whose `run` returns nil --
-- or throws before it can return -- takes the whole battle down with an
-- ipairs(nil) error. This is NOT Transform-specific: the native
-- TRANSFORM_EFFECT record returns a proper message list. It is a class of
-- bug shared by the mod's Gen-2-shaped effect handlers.
--
-- WHY IT HAPPENS (measured, not guessed). A signature census of every
-- record with a `.run` (scratch/sim/probe_runsig.lua, round 179) found
-- exactly five calling conventions across 192 records:
--   (1) run(ctx)                              168 records -- Gen 1's own
--       shape; most of these are written as `local c = normalize(a,b,c)`
--       and are correct on BOTH engines.
--   (2) run(a,b,c,d,e)                          6 records -- GMAX_PROTECT,
--       GMAX_ENDURE, GMAX_MAX_GUARD, GALAR_METALBURST, GALAR_MIRRORCOAT,
--       GALAR_COUNTER -- dual-gen, already return tables.
--   (3) run(battle,attacker,defender,def,moveId,sureHit)      14 records
--       -- Gen 2's positional shape: GALAR_TRICKROOM, GALAR_WONDERROOM,
--       GALAR_MAGICROOM, G9_PARTINGSHOT, G9_TELEPORT, the five G9_*TERRAIN
--       effects, G9_SOAK, G9_MAGICPOWDER, G9_CONVERSION, G9_REFLECTTYPE,
--       G9_CAMOUFLAGE.
--   (4) run(battle,attacker,defender)                           2 records
--       -- GALAR_AFTERYOU, GALAR_QUASH.
--   (5) run(a,b,c,def,moveId,sureHit)                           2 records
--       -- G9_BATONPASS, G9_LOCKON -- normalize-style, returned nil.
-- On Gen 1 every class-(3)/(4) handler receives the ctx FACADE as
-- `battle`, so its very first `battle:emit(...)` / `battle:monName(...)`
-- call is an "attempt to call method (a nil value)" -- thrown before any
-- return -- and a whole family of class-(1) handlers end their body on a
-- bare `emit(battle, text)` helper that is a silent no-op on Gen 1 (Gen 1
-- BattleState has no :emit at all), so they fall off the end and return
-- nil. Both routes land on the same ipairs(nil).
--
-- THE FIX, and why it is shape-agnostic. This file never tries to GUESS an
-- id or a calling convention by name -- it does not use `debug` (the mod
-- sandbox removes it: src/mods/Sandbox.lua's deny list names `debug`),
-- and it does not hardcode the 16 broken ids. Instead it wraps every
-- record's `run` so that it is handed a FACADE whose first parameter works
-- for both conventions at once, and normalizes whatever comes back:
--
--   * The facade proxies every field of the real ctx (so
--     `normalize(a,b,c)`'s `a.battle`/`a.user`/`a.target` reads, and the
--     secondary path's engine-filled `ctx.rawDamage`/`ctx.totalDealt`/
--     `ctx.brokeSub`/`ctx.hits`/`ctx.hitSfx`, all still resolve), and
--     falls back to the real BattleState for anything the ctx lacks --
--     BINDING methods to the BattleState as `self` so a Gen-2-shaped
--     handler's `battle:emit(...)` / `battle:monName(...)` /
--     `battle:data` all reach the real battle instead of indexing a nil
--     method off the ctx facade.
--   * `run` is called inside pcall and its result coerced to a table: nil
--     or a non-table becomes `{}` (an empty message list -- no crash), and
--     a real error becomes `{ failed = true }` (Gen 1's own
--     primaryEffectFailed reads `.failed` and cancels the move animation,
--     which is the honest visual for an effect that could not run). One
--     warn per effect id, so a broken handler is visible in the log once
--     instead of crashing the battle forever.
--
-- THREE PARTIAL ADAPTER SHIMS, INSTALLED ONLY IF MISSING. Gen 1's
-- BattleState genuinely lacks three methods Gen 2's Battle has and the
-- class-(1)/(3)/(4) handlers reach for:
--   :emit(event)  -- Gen 2 queues events for the screen; Gen 1 has no
--     event queue. The shim routes the message-bearing kinds
--     ("message", "move", or any event carrying `.text`) straight into
--     Gen 1's own :sayNext, which is exactly the queue position the
--     returned message list is about to be appended to, so emitted text
--     and returned text keep their natural order. It returns the event so
--     callers that chain `return battle:emit(...)` (the common shape, and
--     the second nil source) still hand the engine a table.
--   :monName(who) -- Gen 2's name accessor, accepting either a raw mon or
--     a Gen 1 battler wrapper (battler.mon unwrapped), so
--     `battle:monName(defender)` reads the same name for both shapes.
--   :volatile(who) -- Gen 2's per-mon state table. Gen 1 builds a fresh
--     battler wrapper per switch, so storing the table on the wrapper has
--     Gen 2's exact "a switch takes it away" lifecycle for free (and no
--     native Gen 1 code reads a `volatile` field, so nothing is shadowed).
-- None of the three is installed if the method already exists, so on a
-- Gen 2 boot (where Battle owns real versions) nothing here touches them.
--
-- SCOPE: Gen 1 only, deliberately. Gen 2's dispatch
-- (gen2/Battle.lua:1750-1754) calls `handler(self, attacker, defender,
-- def, moveId, sureHit)` and IGNORES the return value, so the ipairs(nil)
-- class cannot occur there; and `Battle.moveEffectRecordFor` is
-- save/restored BY VALUE by combat/modern_combat_protect.lua (it captures
-- the function at its own boot and reassigns it after the call), so a
-- later wrap of that name would be silently clobbered on the first
-- protected status move -- leaving Gen 2 alone is both sufficient and
-- safer than fighting that restore.
--
-- NOT A REPLACEMENT FOR REAL WIRING. The guard makes 65 currently-broken
-- handlers non-fatal; it does not pretend they are correct. The ones that
-- genuinely need Gen-1 semantics still get them explicitly where that is
-- real work (class-(3)'s sprite/type moves via the shared primitives, and
-- Transform/Imposter via combat/modern_transform.lua, which boots just
-- before this file). Everything else degrades to a silent no-op plus one
-- warn, which is a far better failure mode than a black-screen crash.
return function(mod)
  assert(mod and mod.exports, "modern_effect_guard: mod table required")

  local okState, BattleState = pcall(require, "src.battle.BattleState")
  BattleState = okState and BattleState or nil
  if not BattleState then
    mod.log:warn("g9-battle-engine: [modern_effect_guard] src.battle.BattleState not loadable; guard not installed")
    return
  end
  if BattleState.__g9EffectGuardInstalled then
    mod.log:info("g9-battle-engine: [modern_effect_guard] already installed; skipped")
    return
  end
  BattleState.__g9EffectGuardInstalled = true

  ------------------------------------------------------------------
  -- The two partial adapter shims (only if the real method is absent).
  ------------------------------------------------------------------
  if BattleState.emit == nil then
    -- Gen 1's closest analogue to Gen 2's Battle:emit: the message
    -- queue. Only the kinds that carry displayable text are forwarded;
    -- a kindless event with a text field is forwarded too, since that is
    -- how several handlers spell a plain message. The event itself is
    -- always returned (as Gen 2's own Battle:emit does) so a handler that
    -- ends `return battle:emit({...})` still returns a table.
    function BattleState:emit(event)
      if type(event) == "table" then
        local kind = event.kind
        if kind == nil or kind == "message" or kind == "move" or kind == "text" then
          if event.text ~= nil then self:sayNext(event.text) end
        elseif event.text ~= nil then
          self:sayNext(event.text)
        end
      elseif type(event) == "string" then
        self:sayNext(event)
      end
      return event
    end
  end

  if BattleState.monName == nil then
    -- Gen 2's Battle:monName, accepting a raw mon OR a Gen 1 battler
    -- wrapper (battler.mon), so the same call site reads correctly on
    -- both engines.
    function BattleState:monName(who)
      if not who then return "?" end
      if who.mon then who = who.mon end
      return who.nickname or who.name or who.species or "?"
    end
  end

  if BattleState.volatile == nil then
    -- Gen 2's Battle:volatile -- "hangs off the mon rather than the
    -- battle so a switch takes it away" (gen2/Battle.lua:1094-1100).
    -- Gen 1 builds a FRESH battler wrapper in makeBattler on every switch
    -- (BattleState.lua:588), so the same storage on the wrapper has
    -- exactly the same lifecycle for free. Nothing in the Gen 1 engine
    -- reads a `volatile` field, so this cannot collide with native state.
    function BattleState:volatile(who)
      if type(who) ~= "table" then return {} end
      who.volatile = who.volatile or {}
      return who.volatile
    end
  end

  ------------------------------------------------------------------
  -- The facade: one first argument that satisfies BOTH conventions.
  ------------------------------------------------------------------
  -- ctx is the caller's own table (EffectRegistry.makeCtx on Gen 1, or
  -- the small table built below for a positional caller). Real battle is
  -- ctx.battle. Reads prefer ctx (so engine-filled per-hit fields and the
  -- ctx's own helpers win), then the battle; a battle FUNCTION reached
  -- through the fallback is cached on the facade bound to the battle, so
  -- `facade:method(...)` really calls `battle:method(...)`.
  local function makeFacade(ctx, realBattle)
    local facade = {
      battle = realBattle,
      user = ctx.user, target = ctx.target, move = ctx.move,
      moveInst = ctx.moveInst, moveId = ctx.moveId,
    }
    return setmetatable(facade, {
      __index = function(t, key)
        local v = ctx[key]
        if v ~= nil then return v end
        if realBattle == nil then return nil end
        v = realBattle[key]
        if type(v) == "function" then
          local bound = function(_, ...) return v(realBattle, ...) end
          rawset(t, key, bound)
          return bound
        end
        return v
      end,
    })
  end

  ------------------------------------------------------------------
  -- Result normalization + the per-record wrapped run.
  ------------------------------------------------------------------
  local warned = {}

  local function normalizeResult(effectId, ok, res)
    if not ok then
      if effectId ~= nil and not warned[effectId] then
        warned[effectId] = true
        mod.log:warn("g9-battle-engine: [modern_effect_guard] move effect %s run() errored; guarded as a no-op (%s)",
          tostring(effectId), tostring(res))
      end
      -- `.failed` is Gen 1's own signal (primaryEffectFailed) to skip the
      -- effect's animation -- the right visual for an effect that could
      -- not run at all.
      return { failed = true }
    end
    if type(res) ~= "table" then return {} end
    return res
  end

  local function normalizeCall(effectId, call, ...)
    local ok, res = pcall(call, ...)
    return normalizeResult(effectId, ok, res)
  end

  local function wrappedRun(original, effectId)
    return function(...)
      local a, b, c, d, e = ...

      -- Gen 1's own dispatch hands one ctx table whose .battle is set; a
      -- positional (Gen 2-shaped) call hands the battle first with no
      -- .battle of its own. Anything else (a bare pcall probe) is passed
      -- through untouched.
      local ctx
      if type(a) == "table" and a.battle ~= nil then
        ctx = a
      elseif type(a) == "table" then
        ctx = { battle = a, user = b, target = c, move = d, moveInst = d, moveId = e }
      else
        return normalizeCall(effectId, original, ...)
      end

      local facade = makeFacade(ctx, ctx.battle)
      return normalizeCall(effectId, original, facade,
        ctx.user, ctx.target, ctx.move, ctx.move and ctx.move.id, false)
    end
  end

  ------------------------------------------------------------------
  -- protectMoveEffectRecord: the one exported primitive. Returns the
  -- record unchanged when it has no run, else a shallow copy whose run is
  -- the guarded wrapper. Copies are memoized per source record (weak
  -- keys) and invalidated if the source's run is ever replaced, so
  -- patching a record later still gets a fresh guard.
  ------------------------------------------------------------------
  local cache = setmetatable({}, { __mode = "k" })

  local function protectMoveEffectRecord(rec, effectId)
    if type(rec) ~= "table" or type(rec.run) ~= "function" then return rec end
    local hit = cache[rec]
    if hit and hit.run == rec.run and hit.effectId == effectId then return hit.copy end
    local copy = {}
    for k, v in pairs(rec) do copy[k] = v end
    copy.run = wrappedRun(rec.run, effectId)
    cache[rec] = { run = rec.run, copy = copy, effectId = effectId }
    return copy
  end

  mod.exports.protectMoveEffectRecord = protectMoveEffectRecord

  ------------------------------------------------------------------
  -- Install: the single lookup both Gen 1 dispatch sites share.
  -- performMove resolves the record once (`self:effectRecord(move.effect)`
  -- at BattleState.lua:4258) and both the power==0 primary branch (:4383)
  -- and EffectRegistry.runDamaging's secondary branch (:342) receive that
  -- same table -- so wrapping the lookup covers both crash sites with one
  -- seam. `self.data.move_effects` is the merged registry view, so a
  -- record any mod contributed is guarded too.
  ------------------------------------------------------------------
  local nativeEffectRecord = BattleState and rawget(BattleState, "effectRecord")
  if type(nativeEffectRecord) ~= "function" then
    -- Gen 2: the engine resolves `src.battle.BattleState` to its Gen-2
    -- facade, which has no effectRecord (Gold owns move_effects dispatch via
    -- Battle.moveEffectRecordFor, not BattleState:effectRecord). This guard
    -- is the Gen-1 crash shield, so a Gen-2 boot simply has nothing to
    -- install -- a clean skip, not a guarded failure (round 349).
    mod.exports.effectGuardInstalled = false
    mod.log:info("g9-battle-engine: modern_effect_guard skipped -- the live "
      .. "src.battle.BattleState has no effectRecord (Gen-2 facade); the "
      .. "record-run guard covers Gen-1 dispatch only")
    return
  end
  function BattleState:effectRecord(effect)
    return protectMoveEffectRecord(nativeEffectRecord(self, effect), effect)
  end

  mod.exports.effectGuardInstalled = true
  mod.log:info("g9-battle-engine: modern_effect_guard installed (record-run guard + Gen-1 emit/monName shims)")
end
