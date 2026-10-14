-- Gen 9 Showdown-accurate combat primitives -- the verb set every move
-- effect built from national_dex's own moveById data (dex.exports.moveById,
-- read for its modern fields -- ailment/ailmentChance/flinchChance/
-- statChance/statChanges/drain/healing/critRate/minHits/maxHits/minTurns/
-- maxTurns -- gen1Effect/gen2Effect and their Modeled flags are explicitly
-- NOT consulted, per explicit user decision) will be wired onto. This file
-- has no knowledge of any specific move or effect label; it only knows how
-- to apply damage, healing, status, volatiles, and stat boosts once
-- something else has decided that one of those should happen.
--
-- SOURCES: smogon/pokemon-showdown's own sim/pokemon.ts and sim/battle.ts
-- (fetched 2026-08-23 from the real, MIT-licensed public repo, not
-- recalled from memory), specifically Pokemon#damage/#heal/#setStatus/
-- #cureStatus/#trySetStatus/#addVolatile/#removeVolatile/#boostBy/#faint
-- and Battle#randomChance. MIT-licensed: see THIRD-PARTY-NOTICES.md.
--
-- SCOPE: only meant to be consulted while g9-battle-engine's own Gen
-- 9 combat-mode toggle is on for a given battle -- native Gen2 combat
-- (gen2/Battle.lua's own useMove/dealDamage/accuracyRoll/applyStatus/
-- changeStage) stays the real, unmodified fallback path when it's off.
-- This file makes no attempt to detect or branch on that toggle itself;
-- the caller decides which pipeline is live.
--
-- STORAGE: reads/writes native Gen2 mon fields directly rather than
-- inventing a parallel mon shape -- mon.hp (plain number), mon.status
-- (plain string, one real major status at a time -- "brn"/"par"/"psn"/
-- "tox"/"slp"/"frz", confirmed matching the shape Battle:applyStatus
-- already enforces, gen2/Battle.lua:2970-3008 -- "one major status at a
-- time" is native's own real rule, not invented here) and mon.volatile
-- (native's own per-mon lazily-created bag, gen2/Battle.lua:991-994,
-- already cleared on switch-out by Battle:clearVolatile). Confusion,
-- flinch, and every other non-major-status effect are volatiles, not
-- statuses -- native's own Battle:applyStatus already special-cases
-- confusion out of mon.status for exactly this reason (:2972-2975), and
-- this file follows the same split. The new 7-stat boost table
-- (atk/def/spa/spd/spe/accuracy/evasion, replacing this mod's own
-- collapsed single-"special"-stage stopgap in modern_combat.lua) lives at
-- mon.volatile.boosts, for the same free switch-out/faint cleanup every
-- other volatile here gets. Native stays the storage substrate ("native
-- as a primitive toggle" -- the standing combat-ownership decision); this
-- file owns the RULES, not a second copy of the bookkeeping.
--
-- mon.volatile itself is NOT created here -- every primitive that touches
-- it requires the caller to have already called the engine's own
-- volatile(mon) accessor at least once (the same expectation every other
-- volatile-reading code in this codebase already has). This file has no
-- dependency on the Battle class and never reaches for self:volatile(...)
-- itself.
return function(mod)
  local Primitives = {}

  local MAJOR_STATUSES = {
    brn = true, par = true, psn = true, tox = true, slp = true, frz = true,
  }

  local STAT_KEYS = { "atk", "def", "spa", "spd", "spe", "accuracy", "evasion" }

  local MAX_STAGE = 6

  ------------------------------------------------------------------
  -- Battle#randomChance(numerator, denominator) -- the literal roll
  -- behind every ailmentChance/flinchChance/statChance field on a
  -- national_dex moveById record. `random` is a 0..n-1 roller (this
  -- engine's own established convention -- gen2/Battle.lua's
  -- self.random/roller()), accepted explicitly rather than reached for
  -- globally so this stays a pure function, callable outside a live
  -- battle (e.g. a future test suite) with any roller handed in.
  ------------------------------------------------------------------
  function Primitives.randomChance(numerator, denominator, random)
    if type(random) ~= "function" then return false end
    if not (numerator and denominator) or denominator <= 0 then return false end
    if numerator <= 0 then return false end
    if numerator >= denominator then return true end
    return random(denominator) < numerator
  end

  -- Convenience for the common shape moveById's own ailmentChance/
  -- flinchChance/statChance fields already carry: a plain 0-100 percent,
  -- not a fraction.
  function Primitives.percentChance(chance, random)
    return Primitives.randomChance(chance or 0, 100, random)
  end

  ------------------------------------------------------------------
  -- damage / heal -- Pokemon#damage / Pokemon#heal (sim/pokemon.ts)
  ------------------------------------------------------------------

  -- Returns the actual damage applied (0 if the mon is already fainted or
  -- `amount` is not a positive number; never more than the mon's own
  -- current HP). Faints the mon via Primitives.faint when HP hits zero --
  -- the caller does not need its own separate faint check afterward.
  function Primitives.damage(mon, amount, source, effect)
    if not mon or (mon.hp or 0) <= 0 then return 0 end
    if type(amount) ~= "number" or amount ~= amount or amount <= 0 then return 0 end
    -- Real rule: any positive fractional damage still takes at least 1 HP.
    if amount < 1 then amount = 1 end
    amount = math.floor(amount)
    local dealt = math.min(amount, mon.hp)
    mon.hp = mon.hp - dealt
    if mon.hp <= 0 then Primitives.faint(mon, source, effect) end
    return dealt
  end

  -- Returns the actual amount healed, or false when the mon can't be
  -- healed right now (fainted, or already at full HP).
  function Primitives.heal(mon, amount, source, effect)
    if not mon or (mon.hp or 0) <= 0 then return false end
    if type(amount) ~= "number" or amount ~= amount or amount <= 0 then return false end
    local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp
    if mon.hp >= maxHp then return false end
    amount = math.floor(amount)
    if amount < 1 then amount = 1 end
    local healed = math.min(amount, maxHp - mon.hp)
    mon.hp = mon.hp + healed
    return healed
  end

  ------------------------------------------------------------------
  -- faint -- Pokemon#faint (sim/pokemon.ts). Idempotent: a mon already
  -- flagged fainted answers false on a second call rather than re-firing
  -- whatever a caller hangs off a real faint.
  ------------------------------------------------------------------
  function Primitives.faint(mon, source, effect)
    if not mon or mon.fainted then return false end
    mon.hp = 0
    mon.fainted = true
    return true
  end

  function Primitives.isFainted(mon)
    return mon == nil or mon.fainted == true or (mon.hp or 0) <= 0
  end

  ------------------------------------------------------------------
  -- status -- Pokemon#setStatus / #cureStatus / #trySetStatus
  -- (sim/pokemon.ts). One major status at a time, matching native's own
  -- real rule (gen2/Battle.lua:2984-2988).
  ------------------------------------------------------------------

  -- status: one of MAJOR_STATUSES' keys ("brn"/"par"/"psn"/"tox"/"slp"/
  -- "frz"). Returns false without changing anything if the mon already
  -- carries a different major status -- a second one never overwrites.
  function Primitives.setStatus(mon, status, source, sourceEffect)
    if not mon or (mon.hp or 0) <= 0 then return false end
    if status and not MAJOR_STATUSES[status] then return false end
    if mon.status then return false end
    mon.status = status
    return true
  end

  function Primitives.cureStatus(mon)
    if not mon or (mon.hp or 0) <= 0 or not mon.status then return false end
    mon.status = nil
    return true
  end

  -- Only applies `status` when the mon has no major status of its own yet
  -- -- otherwise a no-op success, matching Pokemon#trySetStatus's own
  -- "prefer whatever's already there" contract.
  function Primitives.trySetStatus(mon, status, source, sourceEffect)
    if not mon then return false end
    return Primitives.setStatus(mon, mon.status or status, source, sourceEffect)
  end

  ------------------------------------------------------------------
  -- volatiles -- Pokemon#addVolatile / #removeVolatile (sim/pokemon.ts).
  -- Confusion, flinch, attract, taunt, torment, and everything else that
  -- is not one of the six major statuses lives here, keyed by whatever
  -- string the caller chooses (e.g. "confusion", "flinch"). `data` is
  -- carried on the volatile as-is (a duration counter, a source
  -- reference, or plain `true` for a flag with no state of its own).
  ------------------------------------------------------------------

  function Primitives.addVolatile(mon, key, data)
    if not mon or (mon.hp or 0) <= 0 or not mon.volatile then return false end
    if mon.volatile[key] ~= nil then return false end -- already active
    mon.volatile[key] = data or true
    return true
  end

  function Primitives.removeVolatile(mon, key)
    if not mon or not mon.volatile or mon.volatile[key] == nil then return false end
    mon.volatile[key] = nil
    return true
  end

  function Primitives.hasVolatile(mon, key)
    return mon ~= nil and mon.volatile ~= nil and mon.volatile[key] ~= nil
  end

  function Primitives.getVolatile(mon, key)
    return mon and mon.volatile and mon.volatile[key] or nil
  end

  ------------------------------------------------------------------
  -- boostBy -- Pokemon#boostBy (sim/pokemon.ts). The real 7-slot stage
  -- table, replacing this mod's own collapsed single-"special"-stage
  -- stopgap (modern_combat.lua's stageKeyFor, flagged as a stopgap since
  -- the 2026-08-12 combat-ownership decision). Stored at
  -- mon.volatile.boosts for the same free switch-out/faint cleanup every
  -- other volatile here gets.
  ------------------------------------------------------------------

  local function boostsOf(mon)
    mon.volatile.boosts = mon.volatile.boosts or {}
    return mon.volatile.boosts
  end

  -- boosts: { atk = 1, spd = -2, ... } -- any subset of STAT_KEYS.
  -- Returns a table of the ACTUAL delta applied per stat named in
  -- `boosts` (clamped to [-6, 6], so this can read less than requested,
  -- or 0, at the cap) -- the same "tell the caller what really happened"
  -- contract Pokemon#boostBy has, for a "Stat won't go any higher!"
  -- message to key off.
  function Primitives.boostBy(mon, boosts)
    if not mon or (mon.hp or 0) <= 0 or not mon.volatile then return {} end
    local current = boostsOf(mon)
    local applied = {}
    for _, stat in ipairs(STAT_KEYS) do
      local delta = boosts[stat]
      if delta and delta ~= 0 then
        local before = current[stat] or 0
        local after = math.max(-MAX_STAGE, math.min(MAX_STAGE, before + delta))
        applied[stat] = after - before
        current[stat] = after
      end
    end
    return applied
  end

  function Primitives.stageOf(mon, stat)
    if not mon or not mon.volatile or not mon.volatile.boosts then return 0 end
    return mon.volatile.boosts[stat] or 0
  end

  -- Real Showdown rule: stages reset to 0 on switch-out/faint. Native's
  -- own Battle:clearVolatile already wipes mon.volatile wholesale on
  -- switch-out (gen2/Battle.lua:1004-1008), which takes boosts down with
  -- it for free -- this is only for a caller that needs to reset stages
  -- WITHOUT clearing every other volatile too (e.g. a mid-battle
  -- Haze-style effect).
  function Primitives.clearBoosts(mon)
    if not mon or not mon.volatile then return end
    mon.volatile.boosts = nil
  end

  mod.exports.ShowdownPrimitives = Primitives
  mod.log:info("g9-battle-engine: showdown_primitives installed (Gen 9 toggle-mode verb set: damage/heal/faint/status/volatile/boost/chance)")
end
