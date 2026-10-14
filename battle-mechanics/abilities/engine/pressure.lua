-- Dispatch engine for abilities/data/pressure.lua -- Phase 8 of the
-- ability roadmap.
--
-- Neither engine has PP deduction as its own standalone, named method --
-- it is one inline statement deep inside a much larger function on both
-- sides (`move.pp = (move.pp or 1) - 1` inside Gen 2's own
-- Battle:useMove; `moveInst.pp = math.max(0, moveInst.pp - 1)` inside Gen
-- 1's own BattleState:performMove), each already guarded by real
-- exclusion conditions (charging/rampaging/rolling/biding/called on Gen
-- 2; continuation/struggle/called/enemyUnlimitedPP on Gen 1) this file
-- has no reason to duplicate. Both are wrapped at their real, whole-
-- function level (the same real choke points this mod's own Electro
-- Shot Gen 1 charge fix and Prankster/Embargo/rampage-lock Gen 2 fixes
-- already prove safe) with a plain BEFORE/AFTER read of the move's own
-- `.pp` field -- if it dropped by exactly 1 (meaning the native
-- deduction branch actually ran this attempt, whatever its own reason),
-- Pressure deducts one more per Pressure source. This observes the real
-- outcome rather than re-implementing the native exclusion logic a
-- second time, so it can never drift out of sync with either engine's
-- own real rules for when PP is and isn't spent.
--
-- ROUND 68 (category-3 flag audit): the real `mustpressure` move flag is
-- now read live from national_dex's own moveFlags payload. Showdown marks
-- six moves with it -- Imprison, Snatch, Spikes, Stealth Rock, Tera Blast,
-- Toxic Spikes (confirmed against the generated flags.lua: exactly those
-- six). A normal move only triggers Pressure when it targets the Pressure
-- holder, so the old `defender == the Pressure holder` test silently
-- missed every self/field-targeting move. Showdown's own rule
-- (abilities.ts:3441 `onDeductPP: if (target.isAlly(source)) return;`,
-- fed from `getMoveTargets`' pressureTargets, which `mustpressure` sets to
-- the whole opposing side -- battle-actions.ts:467-484) is: for a
-- mustpressure move, ANY opposing active Pressure holder adds one PP,
-- whatever the move's own target archetype is. That is reproduced here
-- with combat/move_targeting.lua's real roster primitive, so it is
-- N-way-correct in multi-battler battles too.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "pressure: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "pressure: ability_dispatch.lua must load first")

  -- moveFlags is keyed by national_dex's own registered spelling and is a
  -- separate lookup from moveById; try the id handed in, then the record's
  -- own id/strippedId (the same resolution parental_bond.lua uses).
  local flagCache = {}
  local function flagsOf(moveId)
    if type(moveId) ~= "string" then return nil end
    local cached = flagCache[moveId]
    if cached ~= nil then
      if cached == false then return nil end
      return cached
    end
    local found
    if moveFlags then
      local ok, f = pcall(moveFlags, moveId)
      if ok and type(f) == "table" then found = f end
      if not found then
        local ok2, info = pcall(moveById, moveId)
        if ok2 and type(info) == "table" then
          for _, key in ipairs({ info.id, info.strippedId }) do
            if key and key ~= moveId then
              local ok3, f2 = pcall(moveFlags, key)
              if ok3 and type(f2) == "table" then found = f2 break end
            end
          end
        end
      end
    end
    flagCache[moveId] = found or false
    return found
  end

  -- Real target archetypes a NORMAL move's Pressure extra PP applies to,
  -- sourced directly from Showdown's own `getMoveTargets` (sim/pokemon.ts,
  -- fetched and read this round):
  --     let pressureTargets = targets;
  --     if (move.target === 'foeSide') pressureTargets = [];
  --     if (move.flags['mustpressure']) pressureTargets = this.foes();
  -- `targets` is the move's own real, resolved target Pokemon set, so a
  -- move that targets an opposing Pokemon charges Pressure and a move that
  -- targets only itself / its own side / the bare field does not. The one
  -- explicit carve-out is Showdown's `foeSide` ("opponents-field" in
  -- national_dex's own spelling: Spikes / Stealth Rock / Sticky Web / Toxic
  -- Spikes), which is emptied on purpose -- that is exactly the gap the
  -- `mustpressure` flag exists to fill (dex-moves.ts: "Additional PP is
  -- deducted due to Pressure when it ordinarily would not"). So this set is
  -- national_dex's spellings for Showdown's opponent-directed archetypes
  -- (normal/adjacentFoe/any -> selected-pokemon; allAdjacentFoes ->
  -- all-opponents; all/randomNormal -> all-other-pokemon / all-pokemon /
  -- random-opponent), and deliberately omits "opponents-field" plus every
  -- self/own-side/field archetype ("user", "user-or-ally", "user-and-allies",
  -- "all-allies", "ally", "users-field", "entire-field", "specific-move",
  -- "fainting-pokemon"). A `mustpressure` move ignores this set entirely.
  local PRESSURE_TARGETS = {
    ["selected-pokemon"] = true, ["selected-pokemon-me-first"] = true,
    ["all-opponents"] = true, ["all-other-pokemon"] = true,
    ["all-pokemon"] = true, ["random-opponent"] = true,
  }
  local function targetsOpponent(moveId)
    local info = moveById(moveId)
    return info ~= nil and PRESSURE_TARGETS[info.target] == true
  end

  -- How many extra PP Pressure takes for this use: the count of real
  -- Pressure SOURCES. Normal moves: the single target, when it is an
  -- opposing Pressure holder. mustpressure moves: every opposing active
  -- Pressure holder, whatever the move targeted.
  local function extraPPSources(battle, attacker, defender, moveId, gen2)
    local flags = flagsOf(moveId)
    if flags and flags.mustpressure then
      local allActiveBattlers = mod.exports.allActiveBattlers
      local sideOfWho = mod.exports.sideOfWho
      if not (allActiveBattlers and sideOfWho and battle and attacker) then
        return 0
      end
      local mine = sideOfWho(battle, attacker, gen2)
      local n = 0
      for _, who in ipairs(allActiveBattlers(battle) or {}) do
        if who and who ~= attacker and sideOfWho(battle, who, gen2) ~= mine
            and abilityIdOf(who) == "PRESSURE" then
          n = n + 1
        end
      end
      return n
    end
    if defender and defender ~= attacker and abilityIdOf(defender) == "PRESSURE"
        and targetsOpponent(moveId) then
      return 1
    end
    return 0
  end

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMovePressure = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      local move = attacker and self:findMove(attacker, moveId)
      local ppBefore = move and move.pp
      local result = nativeUseMovePressure(self, attacker, defender, moveId)
      if move and ppBefore and (move.pp or 0) == ppBefore - 1 then
        local extra = extraPPSources(self, attacker, defender, moveId, true)
        if extra > 0 then
          move.pp = math.max(0, move.pp - extra)
        end
      end
      return result
    end
  end

  local BattleState = require("src.battle.BattleState")
  local nativePerformMovePressure = rawget(BattleState, "performMove")
  if type(nativePerformMovePressure) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    local ppBefore = moveInst and moveInst.pp
    local result = nativePerformMovePressure(self, user, target, moveInst, isCalled)
    if moveInst and ppBefore and (moveInst.pp or 0) == ppBefore - 1 then
      local extra = extraPPSources(self, user, target, moveInst.id, false)
      if extra > 0 then
        moveInst.pp = math.max(0, moveInst.pp - extra)
      end
    end
    return result
  end
  end

  mod.log:info("g9-battle-engine: pressure installed (PRESSURE, both engines; mustpressure read live from national_dex moveFlags)")
end
