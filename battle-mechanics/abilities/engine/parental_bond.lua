-- Dispatch engine for abilities/data/parental_bond.lua -- see that
-- file's own header for the real mechanic and the ownership correction
-- behind why this is buildable at all.
--
-- ROUND 68 (category-3 flag audit): the eligibility test below used to
-- APPROXIMATE Showdown's own exemption list (status / power<=0 /
-- maxHits>0 / an OHKO id set) and silently missed four of the real
-- conditions smogon/pokemon-showdown's own `parentalbond.onPrepareHit`
-- checks (data/abilities.ts:3170-3176, fetched and read directly for
-- this round):
--     if (move.category === 'Status' || move.multihit ||
--         move.flags['noparentalbond'] || move.flags['charge'] ||
--         move.flags['futuremove'] || move.spreadHit || move.isZ ||
--         move.isMax) return;
-- national_dex carries every one of those flags on its own
-- `moveFlags(id)` payload (generated from Showdown's moves.json), so the
-- three real FLAG ones are now read live instead of being inferred:
--   noparentalbond -- Dragon Darts, Dynamax Cannon, Endeavor, Explosion,
--     Final Gambit, Fling, Ice Ball, Rollout, Self-Destruct.
--   charge        -- the 17 two-turn moves (Fly/Dig/Dive/Bounce/Sky
--     Attack/Solar Beam/...).
--   futuremove    -- Doom Desire / Future Sight.
-- `isZ`/`isMax` have no equivalent seam worth wiring: this mod has no
-- Z-moves, and Dynamax's Max Moves are battle_forms' own ids that are not
-- formula-damage moves this ability ever reaches. `spreadHit` is NOT a
-- flag but a RUNTIME answer in Showdown (set by trySpreadMoveHit only
-- when a spread move actually ends up with 2+ targets), which matters:
-- Earthquake IS doubled by Parental Bond in singles, and is NOT in a
-- multi-foe scene. That is reproduced from the live opposing roster
-- below, not from the move's static target archetype alone.
--
-- SPECIAL CASE (explicit user instruction, 2026-09-10): OHKO moves
-- (Fissure, Guillotine, Horn Drill, Sheer Cold) and Final Gambit are
-- called out on purpose, and the naive reading of the OHKO half is WRONG,
-- so it is spelled out here:
--   Final Gambit carries the real `noparentalbond` flag that is now read
--   below, and its power=0 record is ALSO already excluded by the power
--   guard -- either one alone is sufficient.
--   The four OHKO moves keep the explicit id set below, but note that
--   smogon/pokemon-showdown's own `parentalbond.onPrepareHit` (read
--   directly this round) does NOT test `move.ohko` at all -- its only
--   exclusions are Status / multihit / noparentalbond / charge /
--   futuremove / spreadHit / isZ / isMax. An OHKO move therefore DOES get
--   `move.multihit = 2` set in Showdown, yet still resolves as ONE hit:
--   hit 1 deals target.maxhp (battle-actions.ts:1606) and
--   `hitStepMoveHitLoop` breaks as soon as the target's HP is gone
--   (battle-actions.ts:893). national_dex surfaces none of this as a
--   `flags` entry (Fissure's own record is power=0, no flags), and this
--   file's power guard already excludes every OHKO move for that exact
--   same observable result. The id set below is a second, explicit lock
--   on the user's named special case -- never an inferred Showdown rule.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "parental_bond: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "parental_bond: ability_dispatch.lua must load first")

  -- Real, confirmed exemptions (see this file's own data header) --
  -- same OHKO id list every other phase this session already uses.
  -- Both real spellings of each OHKO move: national_dex's registered id
  -- may carry a separator (HORN_DRILL, SHEER_COLD) while the engine's own
  -- id drops it (HORNDRILL, SHEERCOLD), and a record can expose either as
  -- .id or .strippedId -- so both are checked against both.
  local OHKO_MOVES = {
    FISSURE = true,
    GUILLOTINE = true,
    HORNDRILL = true, HORN_DRILL = true,
    SHEERCOLD = true, SHEER_COLD = true,
  }

  -- moveFlags is a SEPARATE national_dex lookup from moveById and is
  -- keyed by the move's REGISTERED id (the dex's own api key, e.g.
  -- SLEEP_POWDER, not the separator-free strippedId). Tries the id it is
  -- handed first, then the record's own canonical id/strippedId, so a
  -- caller spelling the move either way still resolves. Optional on
  -- purpose: a national_dex build without moveFlags leaves this nil and
  -- the three flag exclusions simply do not apply (the old inference
  -- behaviour), never a boot failure.
  local function flagsOf(moveId)
    if not (moveFlags and moveId) then return nil end
    local ok, f = pcall(moveFlags, moveId)
    if ok and f then return f end
    local ok2, info = pcall(moveById, moveId)
    if ok2 and info then
      for _, key in ipairs({ info.id, info.strippedId }) do
        if key and key ~= moveId then
          local ok3, f2 = pcall(moveFlags, key)
          if ok3 and f2 then return f2 end
        end
      end
    end
    return nil
  end

  -- Showdown's own runtime spreadHit answer, from the live roster rather
  -- than the move's static target archetype: a spread move only counts
  -- when 2+ OPPOSING battlers are actually active. Uses the same exported
  -- roster/side primitives every other N-way check in this mod already
  -- relies on (move_targeting.lua / modern_combat.lua), and degrades to
  -- "not spread" (the single-target answer) if those are absent.
  local SPREAD_TARGETS = {
    ["all-opponents"] = true, ["all-other-pokemon"] = true, ["all-pokemon"] = true,
  }
  local function isSpreadAgainstMultipleFoes(battle, user, info, gen2)
    if not (info and SPREAD_TARGETS[info.target]) then return false end
    local allActiveBattlers = mod.exports.allActiveBattlers
    local sideOfWho = mod.exports.sideOfWho
    if not (allActiveBattlers and sideOfWho and user) then return false end
    local mine = sideOfWho(battle, user, gen2)
    local foes = 0
    for _, who in ipairs(allActiveBattlers(battle) or {}) do
      if who ~= user and sideOfWho(battle, who, gen2) ~= mine then
        local m = who.mon or who
        if (m and (m.hp or 0) > 0) then foes = foes + 1 end
      end
    end
    return foes >= 2
  end

  -- Returns eligible(bool), info-record (second return only when the
  -- move resolved at all, so the caller can run the runtime spread test
  -- without a second lookup).
  local function eligibleMove(moveId)
    local ok, info = pcall(moveById, moveId)
    if not (ok and info) then return false end
    if info.damageClass == "status" then return false end
    if (info.power or 0) <= 0 then return false end -- excludes fixed-damage moves (Seismic Toss family) for free
    if (info.maxHits or 0) > 0 then return false end -- already a multi-hit move
    if OHKO_MOVES[info.id] or OHKO_MOVES[info.strippedId] then return false end
    -- Showdown's own three real flag exclusions (see this file's header).
    local flags = flagsOf(moveId)
    if flags and (flags.noparentalbond or flags.charge or flags.futuremove) then return false end
    return true, info
  end

  local function hpOf(m) local r = m and (m.mon or m); return r and (r.hp or 0) or 0 end

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move = ctx.move
    local user = ctx.user
    local gen2 = ctx.gen2
    if not (data.PARENTALBOND and move and move.id and user and abilityIdOf(user) == "PARENTALBOND") then
      return next(ctx)
    end
    local eligible, info = eligibleMove(move.id)
    if not eligible then return next(ctx) end
    -- Runtime spread exclusion (Showdown `move.spreadHit`): only when the
    -- move is a spread archetype AND 2+ opposing battlers are really
    -- active. Earthquake in singles is NOT spread and stays doubled.
    if isSpreadAgainstMultipleFoes(ctx.battle, user, info, gen2) then
      return next(ctx)
    end

    -- Hit 1: the real, full-power hit, exactly as it would resolve
    -- without this ability at all.
    local dmg1, info1 = next(ctx)
    dmg1 = dmg1 or 0

    -- OWNERSHIP: we read the target's own CURRENT hp directly (the
    -- same primitive this mod's own damage-application helpers already
    -- use everywhere else) to decide, ourselves, whether hit 1 alone
    -- would have knocked the target out -- no dependency on the native
    -- caller having already subtracted anything.
    local hpBefore = hpOf(ctx.target)
    if hpBefore > 0 and dmg1 >= hpBefore then
      return dmg1, info1 -- real rule: the first hit fainted the target, no second hit
    end

    -- Hit 2: real 25% power, its own independent pass through the
    -- WHOLE downstream chain (type conversion, STAB, crit roll, type
    -- effectiveness, Protect -- everything below this wrap's own
    -- priority) -- achieved by temporarily scaling the shared move
    -- object's own `.power` field and restoring it immediately after
    -- (even on error), the same swap-and-restore idiom
    -- type_override_moves.lua's own header already established this
    -- same phase.
    local origPower = move.power
    move.power = math.max(1, math.floor((origPower or 0) * 0.25))
    local ok, dmg2, info2 = pcall(next, ctx)
    move.power = origPower
    if not ok then
      mod.log:warn("g9-battle-engine: parental_bond second hit failed: %s", tostring(dmg2))
      return dmg1, info1
    end
    dmg2 = dmg2 or 0

    -- Combined into ONE number/info pair -- this engine's own
    -- battle.damage contract returns exactly one of each per call, so
    -- two mechanically separate hits (real Showdown shows two distinct
    -- animations/messages, and each independently rolls its own
    -- secondary-effect chance) collapse to one combined total and one
    -- combined battle.damage_dealt firing here -- a real, honest
    -- simplification: the AGGREGATE damage is correct, the per-hit
    -- granularity (two messages, two independent secondary-effect
    -- rolls) is not reproduced.
    return dmg1 + dmg2, info1
  end, 210)

  mod.log:info("g9-battle-engine: parental_bond installed (PARENTALBOND; Showdown onPrepareHit exclusions read live from national_dex moveFlags: noparentalbond/charge/futuremove + runtime spreadHit)")
end
