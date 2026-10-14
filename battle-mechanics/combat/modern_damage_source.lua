-- Phase 4 of the missing-effects pipeline: damage-stat SOURCE overrides --
-- the moves that do not read their own category's stat pair.
--
-- Showdown source of truth (scratch/showdown/):
--   battle-actions.ts getDamage (1671-1676):
--     const attacker = move.overrideOffensivePokemon === 'target' ? target : source;
--     const defender = move.overrideDefensivePokemon === 'source' ? source : target;
--     let attackStat: StatIDExceptHP = move.overrideOffensiveStat || (isPhysical ? 'atk' : 'spa');
--     const defenseStat: StatIDExceptHP = move.overrideDefensiveStat || (isPhysical ? 'def' : 'spd');
--   and (1710-1711) the reads themselves:
--     let attack  = attacker.calculateStat(attackStat, attacker.boosts[attackStat], 1, source);
--     let defense = defender.calculateStat(defenseStat, defender.boosts[defenseStat], 1, target);
--   i.e. the effective attacker's OWN stat stage on the effective stat is
--   used, not the original user's.
--   moves.ts bodypress (1572-1585): `overrideOffensiveStat: 'def'` -- the
--     user attacks with its own DEFENSE (stat and stage).
--   moves.ts foulplay (6145-6157): `overrideOffensivePokemon: 'target'` --
--     the move reads the TARGET's Attack stat and the TARGET's own Attack
--     stage, while the defensive side stays the target's Defense.
--   The defensive-side equivalents -- Psyshock / Psystrike / Secret Sword
--   (`overrideDefensiveStat: 'def'`, moves.ts 14270/14284/15951) -- were
--   already implemented inline in modern_combat.lua (so they are not
--   re-registered here).
--
-- The seam is modern_combat.lua's `registerDamageSourceOverride(id, fn)`:
-- fn(ctx) may return any subset of { atkMon, atkStat, defMon, defStat },
-- and computeModernDamage applies it to BOTH the raw stat read and the
-- stat-stage read. Two consequences of doing it there, matching Showdown:
--   * burn's x0.5 is keyed on the move being Physical (battle-actions.ts:
--     1816), independent of the read stat, so a burned Body Press user is
--     still halved;
--   * the ModifyAtk/ModifySpA events (held items, abilities) run against
--     the move's CATEGORY stat (battle-actions.ts:1713), so Choice Band
--     still boosts Body Press.
return function(mod)
  local registerDamageSourceOverride = mod.exports.registerDamageSourceOverride
  assert(registerDamageSourceOverride,
    "modern_damage_source: combat/modern_combat.lua must load first")

  ------------------------------------------------------------------
  -- Body Press -- attack with the user's own Defense (stat and stage).
  ------------------------------------------------------------------
  registerDamageSourceOverride("BODYPRESS", function(ctx)
    return { atkStat = "defense" }
  end)

  ------------------------------------------------------------------
  -- Foul Play -- the offensive mon becomes the TARGET: its Attack stat and
  -- its own Attack stage are read, while the defensive side remains the
  -- target's Defense. (A Foul Play user's own Attack boosts are therefore
  -- ignored; the target's are what matter.)
  ------------------------------------------------------------------
  registerDamageSourceOverride("FOULPLAY", function(ctx)
    return { atkMon = ctx.target }
  end)

  mod.log:info("g9-battle-engine: modern_damage_source installed "
    .. "(Body Press reads the user's Defense; Foul Play reads the target's Attack)")
end
