-- Dispatch engine for abilities/data/priority_change.lua -- Phase 5 of
-- the ability roadmap, the smallest bucket (3 abilities). The boost
-- AMOUNT is read LIVE from national_dex's own abilityBehaviorOf; only
-- WHICH MOVES qualify is hardcoded, and only because none of the three
-- records' own effect entries actually carry a usable filter --
-- confirmed by direct read, not assumed:
--   PRANKSTER's own notes: "Only applies to non-damaging (status)
--     moves, not all moves" -- real field confirmed via a direct dump of
--     a live moveById record (RECOVER): `damageClass = "status"` --
--     NOT `category` ("heal" on that same record, a totally different
--     PokeAPI classification that happens to also be truthy here and
--     would have been the wrong field to key off).
--   TRIAGE's own notes: "applies only to this Pokémon's healing moves"
--     -- the same record's own `healing = 50` field, confirmed real.
--   GALEWINGS is expressible=false in national_dex's own data (no
--     move-type filter field exists in the schema at all) but its own
--     notes state the real condition plainly: "Priority boost only
--     applies to Flying-type moves."
--
-- Registers into combat/turn_order.lua's own registerPriorityModifier
-- chain (the same composable shape combat/modern_combat.lua's
-- registerDamageModifier already is) rather than computing priority
-- itself anywhere.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "priority_change: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local isGen2Battle = mod.exports.isGen2Battle
  local curTypesOf = mod.exports.curTypesOf
  local registerPriorityModifier = mod.exports.registerPriorityModifier
  assert(abilityIdOf and abilityBehaviorOf and isGen2Battle and curTypesOf and registerPriorityModifier,
    "priority_change: ability_dispatch.lua, modern_combat.lua, and turn_order.lua must load first")

  -- The live priority_change effect's own `amount` for this mon's
  -- ability, plus the ability id itself (so the caller knows which
  -- move-filter to apply) -- nil, nil if the mon doesn't carry one.
  local function amountFor(mon)
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return nil, nil end
    local record = abilityBehaviorOf(mon)
    local behavior = record and record.behaviour
    for _, eff in ipairs(behavior and behavior.effects or {}) do
      if eff.kind == "priority_change" and eff.amount then return eff.amount, id end
    end
    return nil, nil
  end

  -- pranksterBoosts(moveId): the real condition, exported so the
  -- Dark-type immunity check below shares this exact definition instead
  -- of a second, possibly-drifting copy of it.
  local function pranksterBoosts(moveId)
    local info = moveById(moveId)
    return info ~= nil and info.damageClass == "status"
  end
  mod.exports.pranksterBoosts = pranksterBoosts

  local function triageBoosts(moveId)
    local info = moveById(moveId)
    return info ~= nil and (info.healing or 0) > 0
  end

  registerPriorityModifier("priority_change", function(battle, moveId, caster, def)
    local amount, id = amountFor(caster)
    if not amount then return 0 end
    if id == "PRANKSTER" then return pranksterBoosts(moveId) and amount or 0 end
    if id == "TRIAGE" then return triageBoosts(moveId) and amount or 0 end
    if id == "GALEWINGS" then return (def and def.type == "FLYING") and amount or 0 end
    return 0
  end)

  ------------------------------------------------------------------
  -- Real Gen 7+ rule, explicitly requested this phase, NOT modeled in
  -- national_dex's own data at all (PRANKSTER's own record carries only
  -- the priority_change effect, no immunity/interaction entry of its
  -- own) -- verified against Pokemon Showdown's own real source
  -- (sim/battle-actions.ts, hitStepTryImmunity) rather than built from
  -- memory: the check there is
  --   `move.pranksterBoosted && pokemon.hasAbility('prankster') &&
  --    !targets[i].isAlly(pokemon) && !this.dex.getImmunity('prankster', target)`
  -- fired PER TARGET inside the same generic immunity pipeline every
  -- other type-immunity check goes through -- which is exactly why a
  -- side/field-targeting status move (Stealth Rock/Spikes/Toxic Spikes:
  -- target="opponents-field"; Reflect/Tailwind: target="users-field";
  -- Recover: target="user" -- all confirmed via a direct dump of real
  -- national_dex move records) never reaches it at all: there is no
  -- opposing POKEMON target for the immunity pipeline to check in the
  -- first place. Restricting this block to target=="selected-pokemon"
  -- (the same real archetype combat/move_targeting.lua's own resolver
  -- already keys off) reproduces that exact shape rather than the
  -- naive "any move with a defender" version, which would have wrongly
  -- blocked a Prankster user's own Stealth Rock/Reflect/Tailwind against
  -- a Dark-type opponent. The source's own `!targets[i].isAlly(pokemon)`
  -- exclusion is preserved too (`defender ~= attacker`, and forward-
  -- ready for a real ally slot once one exists -- this engine has none
  -- today, so it's currently a no-op guard, not dead code).
  --
  -- Wrapped at Battle:useMove -- the same real choke point modern_
  -- terrain.lua's own Psychic Terrain block and combat/
  -- modern_combat_protect.lua's Protect block already use for "this
  -- move does nothing against this target" -- chains safely with both
  -- regardless of load order (each captures whatever it wrapped as its
  -- own "native" and delegates to it when its own condition doesn't
  -- apply, the same monkeypatch-chain convention this whole mod already
  -- uses throughout).
  ------------------------------------------------------------------
  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if defender and defender ~= attacker and abilityIdOf(attacker) == "PRANKSTER"
          and pranksterBoosts(moveId) then
        local info = moveById(moveId)
        if info and info.target == "selected-pokemon" then
          local gen2 = isGen2Battle(self)
          for _, t in ipairs(curTypesOf(defender, gen2)) do
            if t == "DARK" then
              self:emit({ kind = "message", text = Strings("But it failed!") })
              return
            end
          end
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  mod.log:info("g9-battle-engine: priority_change installed (PRANKSTER, TRIAGE, GALEWINGS + Prankster/Dark-type immunity)")
end
