-- Dispatch engine for abilities/data/type_change_ondamage.lua (Color
-- Change) -- no ability-specific data lives here beyond the id set itself.
--
-- Trigger: battle.damage_dealt, the same real event fired only after a
-- landed, non-immune, non-Substitute-absorbed hit (combat/modern_combat.lua
-- 's own dealDamage) -- already exactly matches national_dex's own Color
-- Change notes ("Doesn't trigger on damage blocked by Substitute or on
-- indirect damage... only the last hit of a multi-hit move counts") with
-- no extra gating needed: a Substitute-absorbed or indirect hit never
-- raises this event at all, and a multi-hit move raises it once per real
-- hit, so the final call is naturally the last one to run.
--
-- Reuses mod.exports.setMonTypes/canChangeType (combat/
-- type_override_primitives.lua) -- no once-per-switch-in limit here,
-- unlike Protean/Libero: national_dex's own Color Change record carries no
-- such note, and real Color Change legitimately retriggers on every hit
-- that lands.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local setMonTypes = mod.exports.setMonTypes
  local canChangeType = mod.exports.canChangeType
  assert(abilityIdOf and setMonTypes and canChangeType,
    "ondamage_type_change: ability_dispatch.lua and type_override_primitives.lua must load first")

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local target = ev and ev.target
    local moveType = ev and (ev.move and ev.move.type)
    if not (battle and target and moveType) then return end
    if (target.hp or 0) <= 0 then return end
    local id = abilityIdOf(target)
    if not (id and data[id]) then return end
    -- viaOpponent=false: Color Change is the BEARER's own ability reacting
    -- to being hit, not an opponent's move directly imposing a type change
    -- the way Soak does -- explicit user grouping: "self (protean, libero,
    -- and moves)" vs "target (soak, others)" for the Dynamax asymmetry
    -- this gate implements. Being hit is merely the trigger; the change
    -- itself is self-sourced, same category as Protean/Libero.
    if not canChangeType(battle, target, { viaOpponent = false }) then return end
    setMonTypes(battle, target, { moveType })
    battle:emit({ kind = "message",
      text = Strings("%s transformed into the %s type!", battle:monName(target), moveType) })
  end)

  mod.log:info("g9-battle-engine: ondamage_type_change ability engine installed (COLORCHANGE)")
end
