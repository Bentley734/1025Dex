-- Dispatch engine for abilities/data/type_override_moves.lua -- see
-- that file's own header for the real mechanic and grounding.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local registerDamageModifier = mod.exports.registerDamageModifier
  assert(abilityIdOf and registerDamageModifier,
    "type_override_moves: ability_dispatch.lua and modern_combat.lua must load first")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags,
    "type_override_moves: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags

  -- Real 1.2x power boost, every id EXCEPT Normalize and Liquid Voice
  -- (confirmed: current Showdown gives Normalize no power boost at all,
  -- unlike its four/five siblings -- and Liquid Voice likewise converts
  -- without boosting).
  local POWER_BOOST_EXEMPT = { NORMALIZE = true, LIQUIDVOICE = true }

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move = ctx.move
    local id = ctx.user and abilityIdOf(ctx.user)
    local newType = id and data[id]
    if not (move and move.type and newType) then return next(ctx) end
    -- Normalize converts every move regardless of original type; the
    -- Aerilate family only converts a move that's still Normal-type;
    -- Liquid Voice converts only a move flagged sound (and never a
    -- Dynamax Max Move -- the shared `move` object for those carries no
    -- sound flag, and the gigantamax layer marks its user __g9Dynamaxed,
    -- both real reasons the real ability never touches Max Moves).
    if id == "LIQUIDVOICE" then
      local flags = moveFlags and moveFlags(move.id)
      if not (flags and flags.sound) or (ctx.user and ctx.user.__g9Dynamaxed) then
        return next(ctx)
      end
    elseif id ~= "NORMALIZE" and move.type ~= "NORMAL" then
      return next(ctx)
    end
    if move.type == newType then return next(ctx) end -- already this type, nothing to do
    local origType = move.type
    move.type = newType
    -- Real fix caught before shipping: registerDamageModifier's own
    -- chain (the power-boost half just below) runs from INSIDE the
    -- formula on a completely freshly-built ctx (confirmed by direct
    -- read, combat/modern_combat.lua's own damageModifiers loop) --
    -- checking "ctx.move.type == newType" there is NOT a safe signal
    -- on its own: a mon with Aerilate using a move that's NATURALLY
    -- Flying-type (never touched by the mutation above, since the gate
    -- right above this comment only fires for an originally-Normal
    -- move) would also read as move.type=="FLYING" and wrongly collect
    -- the boost. Marked directly on the shared `move` object instead
    -- (the one real reference both ctx's -- this wrap's and the
    -- modifier chain's own freshly-built one -- both point at), which
    -- correctly answers "was THIS hit's move genuinely converted," not
    -- just "does its type happen to match."
    move.ggdTypeOverridden = true
    local ok, dmg, info = pcall(next, ctx)
    move.type = origType
    move.ggdTypeOverridden = nil
    if not ok then
      mod.log:warn("g9-battle-engine: type_override_moves failed: %s", tostring(dmg))
      return 0, { crit = false, typeMult = 0 }
    end
    return dmg, info
  end, 200)

  registerDamageModifier("type_override_power", 90, function(ctx)
    local id = ctx.user and abilityIdOf(ctx.user)
    if id and not POWER_BOOST_EXEMPT[id] and data[id] and ctx.move and ctx.move.ggdTypeOverridden then
      return 1.2
    end
    return 1.0
  end)

  mod.log:info("g9-battle-engine: type_override_moves installed (AERILATE, PIXILATE, "
    .. "REFRIGERATE, GALVANIZE, DRAGONIZE, NORMALIZE, LIQUIDVOICE)")
end
