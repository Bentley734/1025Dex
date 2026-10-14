-- Dispatch engine for abilities/data/long_reach.lua -- Phase 7 of the
-- ability roadmap. Exports one shared primitive, `mod.exports
-- .makesContact(moveId, attacker)`, real "the real answer, ability
-- included" definition of contact -- confirmed 4 real call sites in this
-- mod check a raw `moveFlags(id).contact` to mean "did the ATTACKER's
-- own move make contact" (abilities/engine/contact_retaliation.lua's
-- Iron Barbs/Aftermath, abilities/engine/ability_copy.lua's Mummy/
-- Wandering Spirit trigger, abilities/engine/inflict_status.lua's
-- Static/Flame Body/Poison Point trigger) -- each updated here to go
-- through this one function instead of the raw flag, so Long Reach is
-- correct everywhere at once rather than four separate patches that
-- could drift.
--
-- Two other real `.contact` reads in this same mod were checked and
-- confirmed NOT relevant: abilities/engine/inflict_status.lua's own
-- Poison Touch/Toxic Chain/Stench block reads the HOLDER's own contact-
-- ness gated on ITS OWN ability id already being Poison Touch/Toxic
-- Chain/Stench, which a Long Reach holder (a different ability) never
-- reaches in the first place -- not touched.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags,
    "long_reach: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "long_reach: ability_dispatch.lua must load first")

  mod.exports.makesContact = function(moveId, attacker)
    local flags = moveFlags(moveId)
    if not (flags and flags.contact) then return false end
    if data.LONGREACH and attacker and abilityIdOf(attacker) == "LONGREACH" then return false end
    return true
  end

  mod.log:info("g9-battle-engine: long_reach installed (LONGREACH, exports makesContact)")
end
