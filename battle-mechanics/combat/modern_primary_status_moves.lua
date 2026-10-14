-- Ailment-carrying PURE STATUS moves that national_dex registers as a
-- placeholder on one or both generations, and that NOTHING else in this mod
-- wires. Reported directly by the user (2026-10-07):
--
--   "make sure sub effects and effects are being driven, also fails/success
--    of status moves such as will-o-wisp, applied it on gen 1 and it didn't
--    say fail nor applied burn."
--
-- THE GAP, read straight off the engine source rather than guessed:
--
--   national_dex registers every move outside the running cart's own roster
--   (src/moves.lua: "A move the running cart already describes is left
--   ALONE"). A modern move whose real behaviour national_dex cannot model
--   for the ACTIVE generation is registered with that generation's most
--   inert effect -- Gen 1 "NO_ADDITIONAL_EFFECT", Gen 2 "EFFECT_NORMAL_HIT"
--   -- plus `genNEffectModeled = false` as a PLACEHOLDER marker.
--
--   On Gen 1 both ids resolve to a record whose `kind` is "full"
--   (MoveEffects.full.NO_ADDITIONAL_EFFECT = {} -> a bare kind="full"
--   record). BattleState:performMove's power==0 dispatch is
--
--     if move.power == 0 and record.kind == "primary" and record.run then
--       ... run it, honour accuracyChecked, print its messages ...
--       return
--     end
--     if move.power == 0 and not (record and record.kind == "full") then
--       ... print "But, it failed!" ...
--       return
--     end
--     EffectRegistry.runDamaging(self, ctx, record)
--
--   so a power-0 move carrying the kind="full" placeholder takes NEITHER
--   the primary branch NOR the failure branch -- it is handed to the
--   DAMAGING pipeline, which for a power-0 move deals nothing and prints
--   nothing. That is exactly the reported symptom: Will-O-Wisp on Gen 1
--   said neither "But it failed!" nor "was burned!" -- it was silently
--   swallowed. (Gen 2's dispatch, gen2/Battle.lua:1750, has the same
--   shape: a record with no run/status is a no-op that falls through to
--   the damage path.)
--
--   This file's own roster is tiny and is computed LIVE -- every move
--   national_dex marks unmodeled for the active generation, that the running
--   cart does NOT own, whose `ailment` is one of the five real major
--   statuses, and whose live record still points at the no-op effect after
--   every other module has run. As of this writing that is exactly:
--     * WILLOWISP   -- burn,     gen1EffectModeled=false, gen2EffectModeled=true
--                      (Gen 2's native EFFECT_BURN already runs it, so Gen 2
--                      is deliberately left alone -- the same honest "native
--                      needs no wiring" call modern_status_moves.lua's own
--                      header makes, now scoped per generation instead of
--                      per move)
--     * TOXICTHREAD -- poison,   gen1EffectModeled=false, gen2EffectModeled=false
--                      AND a Speed -1 stat rider (its "sub effect")
--   Nothing is hardcoded per move: WILLOWISP's Gen 2 entry is skipped by the
--   same `gen2EffectModeled` read that keeps every other native handler
--   intact, and a future dataset that models either one drops it from this
--   pass automatically.
--
-- WHY A GENERIC PASS AND NOT TWO BESPOKE HANDLERS
-- The user's instruction is the same one every phase of this pipeline has
-- followed: do not act as a second data owner. The move's real payload --
-- which status, at what accuracy, with which stat riders -- is read from
-- national_dex's own api record (`ailment`, `accuracy`, `statChanges`,
-- `shortEffect`), never transcribed here. A future national_dex build that
-- flips one of these `modeled` flags, or adds a new modern ailment move,
-- changes what this file wires with no edit.
--
-- MESSAGES / FAILURE, per generation, matching each engine's own real
-- status-move handler rather than inventing a third wording:
--   Gen 1 (MoveEffects.lua's own `statusMove`): target already statused ->
--     "It didn't affect %s!" (except an already-asleep target facing sleep ->
--     "%s's already asleep!"); a poisoned target behind a Substitute ->
--     "It didn't affect"; the shared StatusRegistry.inflict returns no
--     messages (type immunity via Status.canInflict, etc.) -> "But, it
--     failed!"; otherwise its own onInflict landing text.
--   Gen 2: type immunity is checked here (Battle:applyStatus never consults
--     the target's types) and prints the engine's own "It doesn't affect
--     %s..." line; everything else -- Safeguard, one-major-status-at-a-time,
--     the landing text -- is Battle:applyStatus's own real behaviour, which
--     already emits its message and returns false on a refusal.
-- Accuracy is left to Gen 1's performMove (record.accuracyChecked), so a
-- missed Will-O-Wisp prints the engine's "attack missed!" and applies
-- nothing. On Gen 2 a `.run` record is dispatched before the accuracy roll
-- (gen2/Battle.lua:1750) -- a real, pre-existing engine shape every one of
-- this mod's primary records shares; it is moot for this pass because the
-- only Gen-2 move wired here (TOXICTHREAD) has 100 accuracy, and the one
-- with real miss chance (WILLOWISP) is native on Gen 2 and never reaches
-- this file.
return function(mod)
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  local statusTypeImmune = mod.exports.statusTypeImmune
  local corrosionPiercesPoison = mod.exports.corrosionPiercesPoison
  local changeStage = mod.exports.changeStage
  local bossStatsDropBlocked = mod.exports.bossStatsDropBlocked
  assert(normalize and displayNameFor and isGen2Battle and statusTypeImmune
      and changeStage,
    "modern_primary_status_moves: combat/modern_combat.lua must load first")

  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById
      and nationalDex.exports.listMoves,
    "modern_primary_status_moves: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById

  -- national_dex's own canonical ailment spelling -> each engine's real,
  -- confirmed status-string convention. Identical map to main.lua's own
  -- STANDARD_AILMENT (Gen 1 three-letter codes vs Gen 2 words), kept local
  -- because this file has no boot-order dependency on that closure.
  local CODES = {
    burn = { gen1 = "BRN", gen2 = "burn" },
    poison = { gen1 = "PSN", gen2 = "poison" },
    toxic = { gen1 = "PSN", gen2 = "toxic", isToxic = true },
    paralysis = { gen1 = "PAR", gen2 = "paralyze" },
    freeze = { gen1 = "FRZ", gen2 = "freeze" },
    sleep = { gen1 = "SLP", gen2 = "sleep" },
  }

  local function emit(battle, text)
    if not (battle and text) then return end
    if battle.emit then
      battle:emit({ kind = "message", text = text })
    elseif battle.sayNext then
      battle:sayNext(text)
    end
  end

  -- Gen 2 discards a run()'s return value -- the handler must emit its own
  -- lines. Gen 1 returns the list for performMove's sayNext loop.
  local function finish(battle, gen2, lines)
    if gen2 then
      for i = 1, #lines do emit(battle, lines[i]) end
      return {}
    end
    return lines
  end

  -- Speed / accuracy / evasion live on each engine's OWN native stage store
  -- (Gen 1: battler.stages, read by Damage.lua/TurnOrder.lua; Gen 2:
  -- Battle:changeStageAgainstMist), NOT on modern_combat's changeStage store
  -- -- the same split main.lua's own generic stat branch and
  -- modern_movepool_stages.lua's changeNativeStage both document. Kept to
  -- the real primitives rather than a third write path.
  local NATIVE_STATS = { speed = true, accuracy = true, evasion = true }
  local function applyStat(n, who, stat, delta, fromEnemy)
    if not who then return {} end
    if bossStatsDropBlocked and bossStatsDropBlocked(n.battle, who, delta) then
      return { romText(n.battle.data, "_NothingHappenedText", "Nothing happened!") }
    end
    if NATIVE_STATS[stat] then
      if n.gen2 then
        if type(n.battle.changeStageAgainstMist) == "function" then
          n.battle:changeStageAgainstMist(n.user, who, stat, delta)
        end
        return {}
      end
      local NativeMoveEffects = require("src.battle.MoveEffects")
      return NativeMoveEffects.changeStage(n.battle, who, stat, delta, fromEnemy)
    end
    return changeStage(n.battle, who, stat, delta, fromEnemy, n.gen2) or {}
  end

  ------------------------------------------------------------------
  -- One record per qualifying move. The closure captures the move's own
  -- canonical status, its stat riders and their direction, all read from
  -- national_dex -- so the handler needs no ctx.move introspection and
  -- stays identical in shape on both engines.
  ------------------------------------------------------------------
  local function makeRecord(moveId, canonical, statChanges, statsSelfDirected)
    local codes = CODES[canonical]
    return {
      kind = "primary",
      -- Gen 1's performMove runs MoveHitTest for an accuracyChecked primary
      -- record (no 100% early-out), so a missed Will-O-Wisp is a real miss.
      accuracyChecked = true,
      run = function(a, b, c)
        local n = normalize(a, b, c)
        local battle, user, target = n.battle, n.user, n.target
        if not (battle and target) then return {} end
        local gen2 = n.gen2
        local mon = gen2 and target or target.mon
        if not mon then return {} end
        local display = displayNameFor(battle, target, gen2)

        local function statLines()
          local lines = {}
          for _, sc in ipairs(statChanges or {}) do
            local who = statsSelfDirected and n.user or n.target
            local fromEnemy = (not statsSelfDirected) and (sc.change or 0) < 0
            for _, m in ipairs(applyStat(n, who, sc.stat, sc.change, fromEnemy)) do
              lines[#lines + 1] = m
            end
          end
          return lines
        end

        -- Gen 2: type immunity is OURS to state (Battle:applyStatus never
        -- consults types); everything else the native primitive owns, and it
        -- emits its own reason on a refusal.
        if gen2 then
          if statusTypeImmune(battle, target, canonical) then
            local pierce = (canonical == "poison" or canonical == "toxic")
              and corrosionPiercesPoison and corrosionPiercesPoison(user)
            if not pierce then
              return finish(battle, true,
                { Strings("It doesn't affect %s...", battle:monName(target)) })
            end
          end
          if battle.applyStatus and not battle:applyStatus(target, codes.gen2, user) then
            return {}
          end
          -- A real stat rider is independent of the status half (Toxic
          -- Thread drops Speed even against a target it cannot poison).
          return finish(battle, true, statLines())
        end

        -- Gen 1: mirror MoveEffects.lua's own `statusMove` handler exactly.
        local prior = mon.status
        if prior then
          if canonical == "sleep" and prior == "SLP" then
            return { romText(battle.data, "_AlreadyAsleepText",
              "%s's\nalready asleep!", display) }
          end
          return { romText(battle.data, "_DidntAffectText",
            "It didn't affect\n%s!", display) }
        end
        if canonical == "poison" and (target.substituteHP or 0) > 0 then
          return { romText(battle.data, "_DidntAffectText",
            "It didn't affect\n%s!", display) }
        end
        local StatusRegistry = require("src.battle.StatusRegistry")
        local msgs = StatusRegistry.inflict(battle, target, codes.gen1, {
          toxic = codes.isToxic,
          source = moveId,
        })
        if #msgs == 0 then
          -- The status could not land (type/ability immunity, Substitute,
          -- ...): the engine's own status-move failure line.
          return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
        end
        for _, m in ipairs(statLines()) do msgs[#msgs + 1] = m end
        return msgs
      end,
    }
  end

  ------------------------------------------------------------------
  -- The live roster sweep. Runs after every other module (see main.lua's
  -- boot order), so the live-record check below sees every bespoke patch
  -- already applied and can never double-drive a move.
  ------------------------------------------------------------------
  local GameVersion = require("src.core.GameVersion")
  local gen2 = GameVersion.generation(GameVersion.get()) == 2

  local movesApi = mod.content and mod.content.moves
  local effectsApi = mod.content and mod.content.move_effects
  if not (movesApi and effectsApi) then
    mod.log:warn("g9-battle-engine: modern_primary_status_moves: content "
      .. "registries unavailable, no primary status move wired")
    return
  end

  local wired, skipped = {}, 0
  local function statsSelfDirected(info)
    -- A self-directed stat rider is one whose real target is the user. Read
    -- off the move's own target archetype rather than the English prose: no
    -- direction guessing for a mechanic we are about to write.
    local t = info.target
    return t == "user" or t == "user-or-ally" or t == "user-and-allies"
  end

  for _, id in ipairs(nationalDex.exports.listMoves()) do
    local ok, info = pcall(moveById, id)
    if ok and type(info) == "table" then
      local canonical = info.ailment
      local live = movesApi:get(id)
      local modeled = gen2 and info.gen2EffectModeled or info.gen1EffectModeled
      local inert = live and (live.effect == nil
        or live.effect == "NO_ADDITIONAL_EFFECT"
        or live.effect == "EFFECT_NORMAL_HIT")
      if CODES[canonical]
          and not info.engineMove
          and (info.power or 0) == 0
          and modeled ~= true
          and inert then
        local effectId = "G9_PRIMARY_STATUS_" .. id
        effectsApi:register(effectId,
          makeRecord(id, canonical, info.statChanges, statsSelfDirected(info)))
        movesApi:patch(id, { effect = effectId })
        wired[#wired + 1] = id .. "(" .. canonical .. ")"
      else
        skipped = skipped + 1
      end
    end
  end

  ------------------------------------------------------------------
  -- Coverage audit (the user's other half: "make sure sub effects and
  -- effects are being driven"). A power-0 move that is NOT cart-owned,
  -- whose generation says unmodeled, whose live record STILL points at a
  -- no-op effect after every module has run, and that carries a real
  -- mechanical payload, is a move the engine will silently swallow -- the
  -- exact class this file just fixed for Will-O-Wisp. Nothing here changes
  -- behaviour; it only makes the residue visible on the log and on
  -- mod.exports.statusCoverageGaps instead of failing mutely in a battle.
  ------------------------------------------------------------------
  local function hasPayload(info)
    if info.ailment and info.ailment ~= "none" then return true end
    if #(info.statChanges or {}) > 0 then return true end
    if (info.flinchChance or 0) > 0 then return true end
    if (info.drain or 0) ~= 0 or (info.healing or 0) ~= 0 then return true end
    if (info.multiHit or 0) > 0 or (info.minTurns or 0) > 0
        or (info.maxTurns or 0) > 0 then return true end
    if (info.critRate or 0) >= 6 then return true end
    return false
  end

  local gaps = {}
  for _, id in ipairs(nationalDex.exports.listMoves()) do
    local ok, info = pcall(moveById, id)
    if ok and type(info) == "table" and not info.engineMove
        and (info.power or 0) == 0 then
      local modeled = gen2 and info.gen2EffectModeled or info.gen1EffectModeled
      local live = movesApi:get(id)
      local inert = live and (live.effect == nil
        or live.effect == "NO_ADDITIONAL_EFFECT"
        or live.effect == "EFFECT_NORMAL_HIT")
      if modeled ~= true and inert and hasPayload(info) then
        gaps[#gaps + 1] = id
      end
    end
  end

  mod.exports.primaryStatusWired = wired
  mod.exports.primaryStatusMoveCount = #wired
  mod.exports.statusCoverageGaps = gaps
  mod.log:info(string.format(
    "g9-battle-engine: modern_primary_status_moves: drove %d ailment "
      .. "status move(s) on gen %d [%s] (%d other roster moves left to "
      .. "their own owners)",
    #wired, gen2 and 2 or 1,
    #wired > 0 and table.concat(wired, ", ") or "none", skipped))
  if #gaps > 0 then
    local shown = {}
    for i = 1, math.min(#gaps, 12) do shown[i] = gaps[i] end
    mod.log:warn(string.format(
      "g9-battle-engine: modern_primary_status_moves: %d power-0 move(s) "
        .. "carrying a real status/stat/drain payload still resolve to a "
        .. "no-op effect after all wiring [%s%s] -- see "
        .. "mod.exports.statusCoverageGaps",
      #gaps, table.concat(shown, ", "), #gaps > 12 and ", ..." or ""))
  end
end
