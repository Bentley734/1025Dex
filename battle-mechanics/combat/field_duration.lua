-- Shared "does the effect's own setter hold the item that stretches its
-- duration" primitive -- the real Pokemon Showdown mechanic behind Damp
-- Rock/Heat Rock/Smooth Rock/Icy Rock (weather) and Terrain Extender
-- (terrain): 5 turns normally, 8 when the mon that SET the effect is
-- holding the matching item at the moment it's set (confirmed directly
-- against the real, current Pokemon Showdown source -- data/moves.ts's own
-- durationCallback on electricterrain/grassyterrain/mistyterrain/
-- psychicterrain, all four an identical `source?.hasItem('terrainextender')
-- ? 8 : 5`, fetched directly rather than recalled from memory).
--
-- One function, reused by every field-effect setter (weather, terrain,
-- Trick Room) rather than three separate copies of the same "check .item,
-- pick a number" logic -- and, per explicit user decision, built to read
-- `setter.item` generically rather than "whichever move used it": the real
-- games extend this to an ABILITY holder too (Drizzle+Damp Rock, etc.),
-- and this engine has no ability system yet, but a future one only has to
-- pass its own ability-holder mon as `setter` here -- nothing about this
-- function's own contract needs to change when that day comes.
--
-- Round 99: "generically" now covers BOTH held-item slots. Gen 1 has no
-- native `.item` field (round 98 gave it the `g9HeldItem` save slot), so
-- reading `setter.item` alone left every Gen-1 setter permanently at base
-- turns -- a Gen-1 Damp Rock did nothing. `setterItem` below reads the
-- native field first (Gen 2 / engine-native setters, byte-identical to
-- before) and only then falls back to the API's gen-aware reader.
return function(mod)
  -- Real current Showdown's own base/extended pair -- shared, not
  -- redeclared per file, since every real field effect that has ANY
  -- extension at all (weather, terrain) uses this exact same 5/8 split.
  mod.exports.FIELD_BASE_TURNS = 5
  mod.exports.FIELD_EXTENDED_TURNS = 8

  -- The item a setter currently holds, whichever generation's slot that is.
  -- The native `setter.item` read comes first and is untouched, so every
  -- Gen-2 caller resolves exactly as before; the Gen-1 fallback goes through
  -- modern_held_item_api's own effectiveHeldItemOf (looked up at CALL time,
  -- with an inlined field-name fallback, exactly like modern_items.lua's own
  -- itemOf) so this file still works regardless of boot order. A Gen-1
  -- battler wrapper carries no `.item` at all, so the first branch is nil
  -- there and the fallback is what fires.
  local function setterItem(setter)
    if type(setter) ~= "table" then return nil end
    if setter.item ~= nil then return setter.item end
    local m = setter.mon or setter
    if type(m) ~= "table" then return nil end
    if m.item ~= nil then return m.item end
    local effective = mod.exports.effectiveHeldItemOf
    if effective then return effective(m, false) end
    return m[mod.exports.HELD_ITEM_SAVED_FIELD or "g9HeldItem"]
  end

  local function holdsExtender(setter, extendingItem)
    local item = setterItem(setter)
    if not (item and extendingItem) then return false end
    if type(extendingItem) == "table" then return extendingItem[item] == true end
    return item == extendingItem
  end

  -- setter: whichever mon caused the effect -- a move's own attacker
  -- today, an ability's own holder once this engine has abilities.
  -- extendingItem: a single item id string, a set of ids ({FOO=true,...}),
  -- or nil for an effect with no real extending item at all -- Trick Room,
  -- per explicit user decision ("we will have this exist too, but it will
  -- have no item in the future that triggers it, it's just future proof
  -- in case it becomes wanted"): always resolves to baseTurns until a real
  -- id is ever supplied here, no rewrite needed when one is.
  function mod.exports.resolveFieldDuration(setter, baseTurns, extendedTurns, extendingItem)
    if holdsExtender(setter, extendingItem) then return extendedTurns end
    return baseTurns
  end

  mod.log:info("g9-battle-engine: field_duration installed (resolveFieldDuration, FIELD_BASE_TURNS=5, FIELD_EXTENDED_TURNS=8)")
end
