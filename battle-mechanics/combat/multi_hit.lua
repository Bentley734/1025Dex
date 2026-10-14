-- combat/multi_hit.lua -- the engine's own guarantee that EVERY multi-hit
-- move resolves the right number of hits, on both generations.
--
-- WHY THIS EXISTS
-- national_dex carries the real hit count on every move record (minHits /
-- maxHits), and main.lua's wireMovepoolSubEffects already patches a
-- `multiHit` distribution onto the live record for every move the content
-- registry owns. Two real gaps were left over:
--
--   * Gen 1 -- the patch only lands on a record `mod.content.moves` owns.
--     A move the CART owns (national_dex deliberately leaves cart-owned
--     moves alone -- src/moves.lua's existingIds/claim rule) is never in
--     that registry, so it never receives the patch. A cart-owned
--     multi-hit move therefore depends entirely on its ROM effect record
--     still carrying a `hitCount` AND, when that record is missing (an
--     effect id the boot's merged registry does not hold), on the move
--     record itself already carrying `multiHit`. Neither is guaranteed --
--     EffectRegistry.hitCount only falls back to `ctx.move.multiHit`, and
--     NATIVE_ATTACK_TWICE's own `hitsFrom(ctx.move.multiHit or 2, ctx)` is
--     the only thing standing between Double Kick and a single hit.
--   * Gen 2 -- Gold dispatches the hit count off the EFFECT STRING
--     (`Effects.hitCount(def.effect, roller)`) and has no record for the
--     multi-hit family at all (gen2/Effects.lua's own header). national_dex
--     tags only some moves with Gold's own multi-hit effect ids
--     (EFFECT_DOUBLE_HIT / EFFECT_MULTI_HIT / EFFECT_POISON_MULTI_HIT /
--     EFFECT_TRIPLE_KICK) -- the rest carry EFFECT_NORMAL_HIT and so
--     resolve as a single hit, no matter what `multiHit` was patched onto
--     them.
--
-- WHAT THIS DOES
-- Builds ONE plan table from national_dex's live records (id -> the real
-- hit distribution, keyed by both the record's own id and its
-- separator-stripped spelling) and enforces it at each generation's own
-- execution seam:
--
--   * Gen 1: wraps EffectRegistry.runDamaging to set `ctx.move.multiHit`
--     from the plan immediately before the native pipeline reads it. This
--     is the exact field both native branches consume (record.hitCount's
--     two multi-hit effects, and hitCount's own fallback), so it cannot
--     miss regardless of which effect record the boot resolved.
--   * Gen 2: wraps Battle:useMove and, for a planned move whose live
--     effect is NOT already a native multi-hit id, temporarily routes
--     Effects.hitCount to the plan's distribution for the duration of that
--     one call. The effect string is untouched, so no other Gold effect
--     dispatch changes.
--
-- Skill Link's real Gen-1 behaviour (a 2-5-hit move always hits five) is
-- folded into the Gen-1 write, which is the seam it was always meant to
-- land on -- its old patch targeted MoveEffects.full, the table the
-- battle does not dispatch on.
return function(mod)
  -- Lua 5.1/LuaJIT expose `unpack`; 5.2+ only `table.unpack`.
  local unpack = table.unpack or unpack

  local nationalDex = mod.find and mod.find("national_dex")
  if not (nationalDex and nationalDex.exports and nationalDex.exports.moveById
      and nationalDex.exports.listMoves) then
    mod.log:warn("g9-battle-engine: [multi_hit] national_dex unavailable; "
      .. "multi-hit counts left to each generation's own dispatch")
    return 0
  end
  local moveById = nationalDex.exports.moveById

  local function normalise(id)
    if type(id) ~= "string" then return nil end
    return (id:upper():gsub("[^A-Z0-9]", ""))
  end

  -- One plan per multi-hit move. `dist` is always a list (so one code path
  -- rolls it); `isTwoToFive` marks the single family Skill Link widens.
  local plans = {}
  local planned = 0
  local function planFor(id)
    local ok, info = pcall(moveById, id)
    if not (ok and info) then return nil end
    local lo, hi = info.minHits or 0, info.maxHits or 0
    if not (lo > 0 and hi > 0) then return nil end
    if lo == hi then
      return { dist = { lo, lo } }
    end
    if lo == 2 and hi == 5 then
      -- The generation-independent 3/8 . 3/8 . 1/8 . 1/8 distribution
      -- (confirmed against national_dex's own effect text for these moves).
      return { dist = { 2, 2, 2, 3, 3, 3, 4, 5 }, isTwoToFive = true }
    end
    local dist = {}
    for n = lo, hi do dist[#dist + 1] = n end
    return { dist = dist }
  end
  for _, id in ipairs(nationalDex.exports.listMoves()) do
    local plan = planFor(id)
    if plan then
      plans[id] = plan
      local key = normalise(id)
      if key then plans[key] = plan end
      planned = planned + 1
    end
  end
  local function planOf(id)
    return plans[id] or plans[normalise(id)]
  end

  local function skillLinkUser(ctx)
    local abilityIdOf = mod.exports.abilityIdOf
    if type(abilityIdOf) ~= "function" or not ctx or not ctx.user then return false end
    local ok, id = pcall(abilityIdOf, ctx.user)
    return ok and id == "SKILLLINK"
  end

  -- ------------------------------------------------------------------
  -- Gen 1: the native damaging pipeline.
  -- ------------------------------------------------------------------
  local okReg, EffectRegistry = pcall(require, "src.battle.EffectRegistry")
  if okReg and type(EffectRegistry) == "table"
      and type(EffectRegistry.runDamaging) == "function"
      and not EffectRegistry.__g9MultiHitWrapped then
    EffectRegistry.__g9MultiHitWrapped = true
    local nativeRunDamaging = EffectRegistry.runDamaging
    function EffectRegistry.runDamaging(battle, ctx, record)
      local move = ctx and ctx.move
      local plan = move and planOf(move.id)
      if plan then
        if plan.isTwoToFive and skillLinkUser(ctx) then
          move.multiHit = 5
        else
          move.multiHit = plan.dist
        end
      end
      return nativeRunDamaging(battle, ctx, record)
    end
  end

  -- ------------------------------------------------------------------
  -- Gen 2: Gold's string-dispatched hit count.
  -- ------------------------------------------------------------------
  local okBattle, Battle2 = pcall(require, "src.battle.gen2.Battle")
  local okEffects, Gen2Effects = pcall(require, "src.battle.gen2.Effects")
  if okBattle and okEffects and type(Battle2) == "table"
      and type(Gen2Effects) == "table"
      and type(Battle2.useMove) == "function"
      and type(Gen2Effects.hitCount) == "function"
      and not Battle2.__g9MultiHitWrapped then
    Battle2.__g9MultiHitWrapped = true
    local nativeUseMove = Battle2.useMove
    local nativeHitCount = Gen2Effects.hitCount
    local NATIVE_MULTI = {
      EFFECT_MULTI_HIT = true, EFFECT_DOUBLE_HIT = true,
      EFFECT_POISON_MULTI_HIT = true, EFFECT_TRIPLE_KICK = true,
    }
    -- LIFO so a nested useMove (Metronome/Copycat) restores cleanly.
    local stack = {}
    Gen2Effects.hitCount = function(effect, random)
      local top = stack[#stack]
      if top then
        local n = #top
        local index
        if type(random) == "function" then
          index = random(n)
        else
          index = math.random(n) - 1
        end
        if type(index) ~= "number" or index < 0 then index = 0 end
        return top[(index % n) + 1]
      end
      return nativeHitCount(effect, random)
    end
    function Battle2:useMove(attacker, defender, moveId)
      local plan = moveId and planOf(moveId)
      local def
      if plan and type(self.moveDef) == "function" then
        def = self:moveDef(moveId)
      end
      if not (plan and type(def) == "table" and not NATIVE_MULTI[def.effect]) then
        return nativeUseMove(self, attacker, defender, moveId)
      end
      stack[#stack + 1] = plan.dist
      local res = { pcall(nativeUseMove, self, attacker, defender, moveId) }
      stack[#stack] = nil
      if not res[1] then error(res[2], 0) end
      return unpack(res, 2)
    end
  end

  mod.log:info(string.format(
    "g9-battle-engine: multi_hit installed (%d multi-hit move(s) planned; "
      .. "Gen 1 runDamaging wrap + Gen 2 useMove/hitCount wrap)", planned))
  return planned
end
