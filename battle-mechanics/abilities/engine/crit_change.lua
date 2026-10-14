-- Dispatch engine for abilities/data/crit_change.lua -- Phase 6b of the
-- ability roadmap, the smallest bucket (2 abilities). Amounts are read
-- LIVE from national_dex's own abilityBehaviorOf. Registers into
-- combat/modern_combat.lua's own registerCritStageModifier chain (the
-- same real primitive Focus Energy/highCrit moves already feed into,
-- confirmed by direct read: modernCritStage sums every registered
-- modifier's own delta, clamped 0-3, and stage 3+ is a guaranteed hit
-- via CRIT_STAGE_DENOM[3]=1) -- not a new mechanism.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local canonicalStatusOf = mod.exports.canonicalStatusOf
  local registerCritStageModifier = mod.exports.registerCritStageModifier
  assert(abilityIdOf and abilityBehaviorOf and canonicalStatusOf and registerCritStageModifier,
    "crit_change: ability_dispatch.lua, status_immunity.lua, and modern_combat.lua must load first")

  local function amountFor(mon, id)
    local record = abilityBehaviorOf(mon)
    for _, eff in ipairs(record and record.behaviour and record.behaviour.effects or {}) do
      if eff.kind == "crit_change" then
        -- Two real shapes in this bucket: a numeric `amount` (Super
        -- Luck) or a boolean `always` (Merciless) -- neither record
        -- carries both, so this stays a single live read either way.
        if eff.amount then return eff.amount end
        if eff.always then return 3 end -- guarantees stage>=3, see header
      end
    end
    return nil
  end

  registerCritStageModifier("crit_change", function(ctx)
    local id = abilityIdOf(ctx.user)
    if not (id and data[id]) then return 0 end
    local delta = amountFor(ctx.user, id)
    if not delta then return 0 end
    if id == "MERCILESS" then
      -- Real Merciless condition, confirmed via its own notes (not
      -- expressed in the structured effect at all): guaranteed crit only
      -- when the TARGET is poisoned or badly poisoned. Reuses status_
      -- immunity.lua's own canonicalStatusOf rather than a second
      -- Gen1-code/Gen2-word adapter.
      if canonicalStatusOf(ctx.target) ~= "poison" then return 0 end
    end
    return delta
  end)

  mod.log:info("g9-battle-engine: crit_change installed (SUPERLUCK, MERCILESS)")
end
