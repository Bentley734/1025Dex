-- combat/move_effect_markers.lua -- complete the CURRENT generation's
-- move_effects id space for the move records this mod owns.
--
-- WHY THIS EXISTS
-- src.mods.Loader runs Schemas.crossValidate once after the merge, and that
-- pass reads every `moves.<id>.effect` in the registry as a reference into
-- `move_effects` (src/mods/Schemas.lua's catalog: effect = f.id("move_effects")).
-- The id space it checks against is the BOOT'S OWN generation: Schemas.GEN2
-- routes move_effects to gen2MoveEffects, because Gold reimplements the system
-- and names its effects EFFECT_* (src/battle/gen2/Battle.lua
-- registerMoveEffectsInto). Gen 1's do-nothing damaging effect is
-- NO_ADDITIONAL_EFFECT; Gold's is EFFECT_NORMAL_HIT. They are DIFFERENT id
-- spaces and neither contains the other's names.
--
-- The engine does seed a bare kind="full" marker for every effect id a move
-- uses -- registerMoveEffectsInto walks `data.moves` for exactly this reason --
-- but it runs from src.mods.Builtins at boot, BEFORE any mod has registered a
-- move. So an id that only a MODDED move carries is never seeded, and every
-- move record that references it reads as
--   "<mod>: moves.<id>.effect: unresolved reference to move_effects \"<id>\""
-- one line per move: this mod's patched Max/G-Max rows and battle_forms'
-- BATTLE_FORMS_* rows (all effect = "NO_ADDITIONAL_EFFECT"), plus any
-- national_dex move this mod re-owns whose own effect id has no Gold record
-- (STONEEDGE -> "EFFECT_ALWAYS_CRIT").
--
-- WHAT THIS DOES
-- Registers the same bare kind="full" marker the engine registers for its own
-- ROM moves:
--   * "NO_ADDITIONAL_EFFECT" -- the Gen 1 no-op. On Gen 1 this is a REAL
--     vanilla record (src/battle/MoveEffects.lua's MoveEffects.full table), so
--     the `:get(id) == nil` guard below skips it and a Gen 1 boot is untouched.
--     On Gold it is absent, so it is seeded here -- and because resolution is
--     global, that one registration also resolves every OTHER mod's move that
--     carries it (battle_forms' BATTLE_FORMS_* rows included).
--   * every effect id a move record THIS mod owns references that has no
--     record in the current registry (the STONEEDGE case).
--
-- A kind="full" marker is exactly the engine's own choice (see the long note
-- above registerMoveEffectsInto): it is a MISS at both of
-- Battle.moveEffectRecordFor's call sites -- a record with no run and no
-- status falls through to the generic damage path -- so seeding it cannot
-- change a battle's behaviour, only the validator's view of the id space.
-- Registering a record that already exists is skipped, so nothing collides
-- with the engine's own seeded ids and two mods can never collide with each
-- other on this pass.
--
-- WHY `each()` AND NOT THE OP LOG (4.4.3)
-- 4.4.2 walked `moves.ops`, the raw Registry's per-id op list -- but a mod
-- never holds the raw registry. `mod.content.moves` is Loader:_contentApi's
-- closure (src/mods/Loader.lua), whose entire surface is
-- register / override / patch / remove / get / each. `ops` is simply not
-- there, so the 4.4.2 guard's `type(moves.ops) == "table"` was false on
-- every real boot and the sweep silently seeded only the no-op marker. That
-- is what left a single Gold boot line behind: battle_forms'
-- src/speciesbasemoves.lua re-spells STONEEDGE's effect as Gold's own
-- "EFFECT_ALWAYS_CRIT" (game/src/battle/gen2/Battle.lua:hitOnce's
-- high-crit marker, absent from Battle.MOVE_EFFECT_RECORDS, so nothing
-- seeds it), this mod then patches the same record's `highCrit` and so
-- becomes its last writer, and the log attributes the dangling id to us.
-- battle_forms loads at priority 80, this mod at 95 (Loader.lua:71 --
-- priority ascending), so that effect write is already in the shared
-- registry by the time this file runs and `each()` sees it.
--
-- `each()` is the registry's own merged view: base ids first, then op-only
-- ids, each folded through get(). It is a superset of the ids crossValidate
-- scans (it scans the op log, and a mod's ops are exactly what made an id
-- appear), and it is one fold per record -- the same read
-- wireMovepoolSubEffects already makes for the whole roster on this boot.
-- A raw Registry (this file's own test double) is accepted too, via the old
-- op-log walk, so both shapes stay covered.
return function(mod)
  local effects = mod.content and mod.content.move_effects
  local moves = mod.content and mod.content.moves
  if not (effects and type(effects.register) == "function"
      and type(effects.get) == "function") then
    return 0
  end

  local added, seeded = 0, {}
  local function ensure(id)
    if type(id) ~= "string" or id == "" then return end
    if effects:get(id) ~= nil then return end
    effects:register(id, { kind = "full" })
    added = added + 1
    seeded[#seeded + 1] = id
  end

  -- Gen 1's no-op marker first: this mod's own move records and its peers'
  -- both lean on it, so it is seeded even when this mod owns no such move.
  ensure("NO_ADDITIONAL_EFFECT")

  -- Then every effect id the move records in the registry carry. `each()` is
  -- the public content API's own merged view (base ids + op-only ids, folded);
  -- the raw op-log walk is kept as the fallback for a raw Registry, which is
  -- what the test doubles hand in. Either way this covers every id this mod
  -- wrote (wireMovepoolSubEffects' patches, the modern_* siblings' repoints)
  -- and every peer write that landed before this boot, without a hardcoded
  -- list. Wrapped in pcall so a registry shape neither branch knows cannot
  -- take the no-op marker down with it.
  if moves and type(moves.get) == "function" then
    local swept = pcall(function()
      if type(moves.each) == "function" then
        for _, record in moves:each() do
          if type(record) == "table" then ensure(record.effect) end
        end
      elseif type(moves.ops) == "table" then
        for id in pairs(moves.ops) do
          local record = moves:get(id)
          if type(record) == "table" then ensure(record.effect) end
        end
      end
    end)
    if not swept and mod.log and type(mod.log.warn) == "function" then
      mod.log:warn("g9-battle-engine: move_effect_markers: the move sweep "
        .. "failed; only the no-op marker was seeded this boot")
    end
  end

  if added > 0 and mod.log and type(mod.log.info) == "function" then
    mod.log:info(string.format(
      "g9-battle-engine: move_effect_markers: seeded %d move_effects "
        .. "id-space marker(s) [%s] for modded move records (the engine's own "
        .. "seed runs before mods register, so a modded move's effect id "
        .. "would otherwise dangle in the loader's cross-reference pass)",
      added, table.concat(seeded, ", ")))
  end
  return added
end
