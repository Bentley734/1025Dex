-- Dispatch engine for abilities/data/contact_retaliation.lua -- Phase 8c
-- of the ability roadmap ("other" bucket).
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags
      and nationalDex.exports.moveById,
    "contact_retaliation: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "contact_retaliation: ability_dispatch.lua must load first")

  local function hpOf(mon) return (mon.mon or mon) end
  local function damageFraction(mon, fraction)
    local m = hpOf(mon)
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0) then return end
    m.hp = math.max(0, (m.hp or 0) - math.max(1, math.floor(maxHp * fraction)))
  end
  local function damageFlat(mon, amount)
    if not (amount and amount > 0) then return end
    local m = hpOf(mon)
    m.hp = math.max(0, (m.hp or 0) - amount)
  end

  ------------------------------------------------------------------
  -- IRONBARBS / ROUGHSKIN -- any landed contact hit, real national_dex
  -- moveFlags (the same `contact` flag combat/move_targeting.lua's own
  -- header catalogues, confirmed real earlier this session). Both are
  -- Showdown's identical `onDamagingHit` recoil -- `this.damage(source
  -- .baseMaxhp / 8, source, target)` (abilities.ts:2228 ironbarbs,
  -- abilities.ts:3942 roughskin): the ATTACKER loses 1/8 of its OWN max
  -- HP, the same basis `damageFraction(user, 1/8)` below already uses.
  -- Kept on one shared handler so the two can never drift apart.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local target = ev and ev.target
    local user = ev and ev.user
    local move = ev and ev.move
    if not (target and user and move and (ev.damage or 0) > 0) then return end
    local id = abilityIdOf(target)
    if id ~= "IRONBARBS" and id ~= "ROUGHSKIN" then return end
    -- Long Reach (Phase 7): the real "did this attacker's move make
    -- contact" answer, ability-aware -- see abilities/engine/long_reach
    -- .lua's own header.
    local makesContact = mod.exports.makesContact
    if makesContact and makesContact(move.id, user) then damageFraction(user, 1 / 8) end
  end)

  ------------------------------------------------------------------
  -- LIQUIDOOZE -- "apply then correct" (none of this engine's drain
  -- paths -- native or main.lua's own generic installMovepoolEffects
  -- handler -- expose a pre-heal interception point) against the move's
  -- own real, live `drain` field, not a hardcoded effect-id table.
  -- Reading `drain` directly means this covers EVERY real drain move
  -- generically -- natively-modeled ones (Absorb/Giga Drain/Leech Life/
  -- Dream Eater) and main.lua's own generically-handled ones alike --
  -- rather than only the handful an id list happened to name. Mirrors
  -- combat/boss_fight_status.lua's own antiDrain, migrated the same way.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local target = ev and ev.target
    local user = ev and ev.user
    local move = ev and ev.move
    local dealt = ev and ev.damage
    if not (target and user and move and dealt and dealt > 0) then return end
    if abilityIdOf(target) ~= "LIQUIDOOZE" then return end
    local ok, info = pcall(moveById, move.id)
    local drainPercent = ok and info and (info.drain or 0) > 0 and info.drain or nil
    if not drainPercent then return end
    local harm = math.max(1, math.floor(dealt * drainPercent / 100))
    damageFlat(user, harm)
    local battle = ev.battle
    if battle then
      battle:emit({ kind = "message",
        text = Strings("%s sucked up the ooze!", battle:monName(user)) })
    end
  end)

  ------------------------------------------------------------------
  -- AFTERMATH / INNARDSOUT -- both real on_faint retaliation, keyed off
  -- the KILLING hit specifically. Wrapped at "battle.damage" (priority
  -- 45 -- ABOVE type_immunity.lua's/damage_immunity.lua's own 40 tier,
  -- so this observes the TRULY FINAL damage number after Sturdy or a
  -- type block has already applied -- a hit Sturdy reduced to leave 1 HP
  -- must NOT be treated as lethal here, real on_faint scope) but BELOW
  -- Protect's own 50 (a fully-protected hit never reaches this at all,
  -- correct -- no faint, no retaliation).
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local dmg, info = next(ctx)
    local target = ctx.target
    local user = ctx.user
    if target and user and dmg then
      local m = hpOf(target)
      local hpBefore = m.hp or 0
      if hpBefore > 0 and dmg >= hpBefore then
        local id = abilityIdOf(target)
        -- Phase 7 (prevent bucket): Damp's own real "Aftermath will not
        -- take effect" clause, checked live rather than duplicated --
        -- abilities/engine/prevent_misc.lua's own anyBattlerHasDamp is the
        -- one real definition of "does either battler have Damp."
        local damp = mod.exports.anyBattlerHasDamp and ctx.battle
          and mod.exports.anyBattlerHasDamp(ctx.battle)
        if id == "AFTERMATH" and not damp then
          local makesContact = mod.exports.makesContact
          if makesContact and ctx.move and makesContact(ctx.move.id, user) then
            damageFraction(user, 1 / 4)
          end
        elseif id == "INNARDSOUT" then
          damageFlat(user, hpBefore)
        end
      end
    end
    return dmg, info
  end, 45)

  mod.log:info("g9-battle-engine: contact_retaliation installed (IRONBARBS, ROUGHSKIN, AFTERMATH, INNARDSOUT, LIQUIDOOZE)")
end
