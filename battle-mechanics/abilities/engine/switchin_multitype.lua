-- Dispatch engine for abilities/data/multitype_switchin.lua -- Phase 1.8,
-- the first of this directory's "passive, derived-type" abilities
-- (Multitype, Forecast, Mimicry), deferred from Phase 1 pending their own
-- design pass.
--
-- PLATE_TYPE is the one genuinely new (non-duplicated) piece: national_dex
-- 's own MULTITYPE record describes its effect only in prose ("the type
-- matching its held Plate"), with no structured Plate->type table --
-- built here from national_dex's own ITEM registry instead (confirmed by
-- direct read, data/items/generated/api/*.lua: each of the 16 real
-- elemental Plates carries an explicit "Held by a Multitype Pokemon:
-- Holder's type becomes <Type>" effect line). BLANKPLATE and LEGENDPLATE
-- are deliberately excluded -- confirmed neither carries that effect line
-- at all (Blank Plate has no effect; Legend Plate only boosts Judgment's
-- power).
--
-- Explicit user correction, this session: unlike Forecast/Mimicry,
-- Multitype does NOT reactively re-check mid-battle. Arceus's type is
-- fixed to whichever Plate it's holding the moment it enters battle, the
-- same way its FORM is fixed then -- not something the real games ever
-- re-derive live while it's already out (the same is true of Genesect's
-- Drives, cited by the user as a parallel case, though Genesect's own
-- Drives affect Techno Blast's type, not Genesect's own typing, so it
-- isn't wired here at all). Switch-in only, the same two-event pattern
-- (battle.started + battle.battler_switched) every other switch_in
-- ability engine in this directory already uses -- no weather/terrain/
-- item-change listener, unlike abilities/engine/forecast_weather.lua and
-- abilities/engine/mimicry_terrain.lua.
--
-- Reuses combat/type_override_primitives.lua's setMonTypes/canChangeType
-- (Tera always blocks; self-activated Dynamax is unaffected) -- the same
-- primitives Protean/Libero/Soak/Color Change already go through.
return function(mod, data)
  local setMonTypes = mod.exports.setMonTypes
  local canChangeType = mod.exports.canChangeType
  local abilityIdOf = mod.exports.abilityIdOf
  assert(setMonTypes and canChangeType and abilityIdOf,
    "switchin_multitype: type_override_primitives.lua and ability_dispatch.lua must load first")

  local PLATE_TYPE = {
    FLAMEPLATE = "FIRE", SPLASHPLATE = "WATER", ZAPPLATE = "ELECTRIC",
    MEADOWPLATE = "GRASS", ICICLEPLATE = "ICE", FISTPLATE = "FIGHTING",
    TOXICPLATE = "POISON", EARTHPLATE = "GROUND", SKYPLATE = "FLYING",
    MINDPLATE = "PSYCHIC", INSECTPLATE = "BUG", STONEPLATE = "ROCK",
    SPOOKYPLATE = "GHOST", DRACOPLATE = "DRAGON", DREADPLATE = "DARK",
    IRONPLATE = "STEEL", PIXIEPLATE = "FAIRY",
  }

  local function applySwitchInAbility(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0) then return end
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return end
    if not canChangeType(battle, mon, { viaOpponent = false }) then return end
    local plateType = mon.item and PLATE_TYPE[mon.item]
    setMonTypes(battle, mon, { plateType or "NORMAL" })
  end

  -- Round 338: Transform/Imposter re-run this for the ability it copied.
  mod.exports.registerSwitchInAbility(applySwitchInAbility)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    if battle.player then applySwitchInAbility(battle, battle.player) end
    if battle.enemy then applySwitchInAbility(battle, battle.enemy) end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local mon = ev and ev.battler
    if battle and mon then applySwitchInAbility(battle, mon) end
  end)

  mod.log:info("g9-battle-engine: switchin_multitype ability engine installed (MULTITYPE)")
end
