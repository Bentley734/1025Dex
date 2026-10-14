-- Type-modifying moves -- the real Showdown `onModifyType` / `onModifyMove`
-- family (missing-effects plan, Phase 14). Twelve moves whose TYPE (and, for
-- two of them, whose CATEGORY or base POWER) depends on live battle state at
-- the moment they are used:
--
--   HIDDENPOWER, JUDGMENT, MULTIATTACK, REVELATIONDANCE, TECHNOBLAST,
--   NATURALGIFT, RAGINGBULL, WEATHERBALL, TERRAINPULSE, TERABLAST,
--   TERASTARSTORM, PHOTONGEYSER.
--
-- All twelve are national_dex records with a NORMAL (or PSYCHIC for Photon
-- Geyser) stub type and no handler; the real type is decided per use. Each
-- one's rule is transcribed straight from Showdown with a `file:line`
-- citation beside it, never recalled.
--
-- WHERE THE CHANGE HAPPENS. Real Showdown runs `onModifyType` through its
-- `ModifyType` event BEFORE damage is computed, so STAB and type
-- effectiveness both see the new type (battle-actions.ts getDamage reads
-- `move.type` after the event). This engine has no such event, but its
-- existing Aerilate/Pixilate family (abilities/engine/type_override_moves.lua)
-- already established the seam this file reuses: wrap `battle.damage`,
-- mutate `ctx.move.type` on the shared move record for exactly one
-- synchronous call, and restore it afterwards. Everything downstream --
-- computeModernDamage's STAB modifier, its `resolvedTypeMult` effectiveness
-- read, AND gen2-Battle's own "It doesn't affect" gate (which is driven off
-- the returned `info.effectiveness`, gen2-Battle.lua:1264) -- all read the
-- SAME mutated `move.type`, so the conversion is fully effective, not just a
-- cosmetic number swap. The same wrapper also mutates `ctx.move.category`
-- for Photon Geyser / Tera Blast (their real `onModifyMove` picks
-- Physical/Special off the higher raw offensive stat).
--
-- POWER. Four of the twelve also change base POWER, which is a different
-- seam (registerPowerOverride -- the Phase 13 convention): Weather Ball and
-- Terrain Pulse DOUBLE their 50 in the matching field, Tera Blast is 100
-- instead of 80 for a Stellar Terastallization, and Natural Gift takes its
-- power from the held berry. Those are registered below beside the type
-- rules so the whole move lives in one place.
--
-- ITEMS. Judgment / Multi-Attack / Techno Blast / Natural Gift read the
-- held item's real Showdown "facts" -- `onPlate` / `onMemory` / `onDrive` /
-- `naturalGift` -- which national_dex exposes through its own
-- `itemFlags(id)` accessor (national_dex's data/items/generated/flags.lua,
-- a separate payload from the item catalogue exactly like move flags are
-- separate from moveById; see national_dex's own api.lua header). Its type
-- strings are Showdown's Title-case ("Fire", "Psychic"), so they are
-- normalized to this engine's id convention ("FIRE", "PSYCHIC_TYPE") before
-- use. `battle.magicRoomActive` and the holder's Klutz suppress the item
-- exactly as Showdown's `ignoringItem()` does.
--
-- GEN 1 is untouched: everything here keys off a gen2 battle's shared move
-- record, and the wrapper is a no-op when no rule matches.
return function(mod)
  local isGen2Battle = mod.exports.isGen2Battle
  local curTypesOf = mod.exports.curTypesOf
  local currentWeather = mod.exports.currentWeather
  local rawStat = mod.exports.rawStat
  local registerPowerOverride = mod.exports.registerPowerOverride
  local isTerastallized = mod.exports.isTerastallized
  local getTeraType = mod.exports.getTeraType
  assert(isGen2Battle and curTypesOf and currentWeather and rawStat
    and registerPowerOverride,
    "modern_type_modify_moves: combat/modern_combat.lua must load first")

  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports,
    "modern_type_modify_moves: national_dex must be loaded first")
  -- itemFlags may be absent on an older national_dex; every read below
  -- tolerates nil and simply leaves the move's stored type/power alone.
  local itemFlags = nationalDex.exports.itemFlags
  -- Phase 24: item facts are read through combat/modern_item_facts.lua's
  -- id bridge (normalize + the BLACKBELT_I rename + the True-Past override
  -- table), so a ROM underscore id like KINGS_ROCK or LIGHT_BALL finally
  -- resolves instead of returning nil. That module boots before this one;
  -- it is resolved lazily at damage time anyway, and the raw accessor
  -- below remains as a fallback for any load order lacking it.

  ------------------------------------------------------------------
  -- Shared helpers. `itemOf` is exported by combat/modern_items.lua,
  -- which boots AFTER this file, so it is looked up lazily at damage
  -- time rather than captured here (the same discipline
  -- modern_power_conditions.lua's cureStatusOf lookup uses).
  ------------------------------------------------------------------
  local function abilityIdOf(mon)
    local fn = mod.exports.abilityIdOf
    return fn and fn(mon) or nil
  end

  local function heldItemId(who, gen2)
    local fn = mod.exports.itemOf
    return fn and fn(who, gen2) or nil
  end

  -- Showdown's `pokemon.ignoringItem()`: Magic Room (a battle field state,
  -- battle.magicRoomActive -- trick_room.lua) suppresses every held item,
  -- and a Klutz holder ignores its own. Both are read the way the rest of
  -- this mod reads them (modern_held_items_phase2.lua:319/365 use the
  -- same magicRoomActive field; klutz.lua's own gate is abilityIdOf).
  local function ignoresItem(battle, who, gen2)
    if battle and battle.magicRoomActive then return true end
    return abilityIdOf(who) == "KLUTZ"
  end

  -- The real facts record for a mon's held item, or nil when it has no
  -- item / is ignoring it / the item genuinely carries no facts. Phase 24:
  -- routed through the item-facts id bridge so underscore ROM ids resolve.
  local function itemFactRecord(battle, who, gen2)
    local id = heldItemId(who, gen2)
    if not id then return nil end
    if ignoresItem(battle, who, gen2) then return nil end
    local bridged = mod.exports.itemFact
    if bridged then
      local ok, rec = pcall(bridged, id)
      if ok and type(rec) == "table" then return rec end
    end
    if not itemFlags then return nil end
    local ok, rec = pcall(itemFlags, id)
    if ok and type(rec) == "table" then return rec end
    return nil
  end

  -- Showdown's Title-case type names ("Fire", "Psychic") -> this engine's
  -- id spelling. Psychic is the one real mismatch (national_dex and the
  -- type chart both call it PSYCHIC_TYPE); everything else is just upper.
  local function typeId(name)
    if type(name) ~= "string" then return nil end
    local up = name:upper()
    if up == "PSYCHIC" then return "PSYCHIC_TYPE" end
    return up
  end

  -- "Grounded", the SAME rule combat/modern_terrain.lua's own local
  -- isGrounded (and modern_power_conditions.lua's copy) already applies to
  -- every terrain effect: Gravity's field flag grounds a mon, otherwise a
  -- live Flying type does not. That file's header documents the known limit
  -- honestly (Levitate / Air Balloon / Magnet Rise are not modelled), and
  -- Terrain Pulse is a terrain rule, so it must agree with terrain itself.
  local function grounded(who, gen2)
    if who and (who.gravityGrounded or (who.mon and who.mon.gravityGrounded)) then
      return true
    end
    for _, t in ipairs(curTypesOf(who, gen2)) do
      if t == "FLYING" then return false end
    end
    return true
  end

  local function terrainOf(battle)
    return battle and battle.terrain
  end

  -- The live Tera type, but ONLY while actually Terastallized (Tera Blast /
  -- Tera Starstorm's real gate). getTeraType answers a stored value for any
  -- mon; isTerastallized is the "is the Tera ACTIVE right now" question.
  local function activeTeraType(battle, who, gen2)
    if not (isTerastallized and isTerastallized(battle, who, gen2)) then return nil end
    if not getTeraType then return nil end
    local ok, value = pcall(getTeraType, who, battle)
    if ok and type(value) == "string" and value ~= "" then return value end
    return nil
  end

  ------------------------------------------------------------------
  -- Per-move TYPE rules. Each returns an engine type id to apply, or nil
  -- to leave the record's stored type alone. Citations beside each rule.
  ------------------------------------------------------------------

  -- Weather Ball: Fire in sun, Water in rain, Rock in sand, Ice in
  -- hail/snow (moves.ts:20700-20719). No weather -> Normal (the record's
  -- own stored type), i.e. nil here.
  local WEATHER_BALL_TYPE = { SUN = "FIRE", RAIN = "WATER", SAND = "ROCK", SNOW = "ICE" }

  -- Terrain Pulse: Electric / Grass / Fairy / Psychic on the matching
  -- terrain, but ONLY while the user is grounded (moves.ts:19273-19286).
  local TERRAIN_PULSE_TYPE = {
    ELECTRIC = "ELECTRIC", GRASSY = "GRASS", MISTY = "FAIRY", PSYCHIC = "PSYCHIC_TYPE",
  }

  -- Raging Bull's type is fixed by the user's Paldean Tauros form
  -- (moves.ts:14645-14658); any other species keeps the record's Normal.
  -- This engine's species ids are its own spelling, so both the
  -- Showdown hyphenated form and the engine's underscore form are matched;
  -- a species this engine does not build simply never matches, which is the
  -- honest answer (its Raging Bull is Normal, exactly the base record).
  local RAGING_BULL_TYPE = {
    ["TAUROS-PALDEA-COMBAT"] = "FIGHTING", ["TAUROS_PALDEA_COMBAT"] = "FIGHTING",
    ["TAUROS-PALDEA-BLAZE"] = "FIRE", ["TAUROS_PALDEA_BLAZE"] = "FIRE",
    ["TAUROS-PALDEA-AQUA"] = "WATER", ["TAUROS_PALDEA_AQUA"] = "WATER",
  }

  local TYPE_RULES = {}

  -- Hidden Power: `move.type = pokemon.hpType || 'Dark'` (moves.ts:8637-8639).
  -- This engine has no stored hpType field, but its own Gen 2 Hidden Power
  -- routine already derives the real type from the mon's DVs
  -- (gen2-Battle.lua:556 Battle:hiddenPower -> the 16-entry table at :543),
  -- which is the faithful per-mon answer here. A mon with no DVs (a fixture
  -- or a modern-only mon) falls back to Showdown's own default, Dark.
  TYPE_RULES.HIDDENPOWER = function(ctx)
    local battle = ctx.battle
    if battle and battle.hiddenPower then
      local ok, _, t = pcall(battle.hiddenPower, battle, ctx.user)
      if ok and type(t) == "string" then return t end
    end
    return "DARK"
  end

  -- Judgment: the held Plate's `onPlate` type, else Normal (moves.ts:9827-9833).
  TYPE_RULES.JUDGMENT = function(ctx)
    local rec = itemFactRecord(ctx.battle, ctx.user, ctx.gen2)
    return rec and typeId(rec.onPlate) or nil
  end

  -- Multi-Attack: the held Memory disc's `onMemory` type (moves.ts:12498-12501;
  -- Showdown reads it through a `Memory` event, which is exactly the
  -- item-held `onMemory` field here).
  TYPE_RULES.MULTIATTACK = function(ctx)
    local rec = itemFactRecord(ctx.battle, ctx.user, ctx.gen2)
    return rec and typeId(rec.onMemory) or nil
  end

  -- Techno Blast: the held Drive's `onDrive` type (moves.ts:19075-19078).
  TYPE_RULES.TECHNOBLAST = function(ctx)
    local rec = itemFactRecord(ctx.battle, ctx.user, ctx.gen2)
    return rec and typeId(rec.onDrive) or nil
  end

  -- Natural Gift: the held Berry's `naturalGift.type` (moves.ts:12572-12577).
  TYPE_RULES.NATURALGIFT = function(ctx)
    local rec = itemFactRecord(ctx.battle, ctx.user, ctx.gen2)
    local gift = rec and rec.naturalGift
    return gift and typeId(gift.type) or nil
  end

  -- Revelation Dance: the user's own first current type (moves.ts:15039-15045).
  -- curTypesOf is Transform/Tera-aware, matching Showdown's `pokemon.getTypes()`.
  TYPE_RULES.REVELATIONDANCE = function(ctx)
    local types = curTypesOf(ctx.user, ctx.gen2)
    return types and types[1] or nil
  end

  -- Weather Ball / Terrain Pulse / Tera Blast / Tera Starstorm / Raging Bull.
  TYPE_RULES.WEATHERBALL = function(ctx)
    return WEATHER_BALL_TYPE[currentWeather(ctx.battle, ctx.gen2)]
  end
  TYPE_RULES.TERRAINPULSE = function(ctx)
    if not grounded(ctx.user, ctx.gen2) then return nil end
    return TERRAIN_PULSE_TYPE[terrainOf(ctx.battle)]
  end
  TYPE_RULES.TERABLAST = function(ctx)
    return activeTeraType(ctx.battle, ctx.user, ctx.gen2)
  end
  TYPE_RULES.TERASTARSTORM = function(ctx)
    -- Only Terapagos-Stellar becomes Stellar (moves.ts:19247-19249); any
    -- other species keeps the record's Normal. Both species-id spellings
    -- are matched, same reasoning as Raging Bull above.
    local species = ctx.user and ctx.user.species
    if species == "TERAPAGOS-STELLAR" or species == "TERAPAGOS_STELLAR" then
      return "STELLAR"
    end
    return nil
  end
  TYPE_RULES.RAGINGBULL = function(ctx)
    return ctx.user and RAGING_BULL_TYPE[ctx.user.species] or nil
  end

  ------------------------------------------------------------------
  -- Per-move CATEGORY rules (the real onModifyMove half). Photon Geyser
  -- and Tera Blast flip to Physical when the user's raw Attack exceeds its
  -- raw Special Attack (moves.ts:13344-13346, :19233-19237); Tera
  -- Starstorm does the same for Terapagos-Stellar (moves.ts:19248). The
  -- category is written Title-case because that is the spelling
  -- MoveCategory.of recognises (see its own header).
  ------------------------------------------------------------------
  local CATEGORY_RULES = {}
  local function physicallyStronger(user, gen2)
    return (rawStat(user, "attack", gen2) or 0) > (rawStat(user, "spa", gen2) or 0)
  end
  CATEGORY_RULES.PHOTONGEYSER = function(ctx)
    if physicallyStronger(ctx.user, ctx.gen2) then return "Physical" end
    return nil
  end
  CATEGORY_RULES.TERABLAST = function(ctx)
    if activeTeraType(ctx.battle, ctx.user, ctx.gen2) and physicallyStronger(ctx.user, ctx.gen2) then
      return "Physical"
    end
    return nil
  end
  CATEGORY_RULES.TERASTARSTORM = function(ctx)
    local species = ctx.user and ctx.user.species
    if (species == "TERAPAGOS-STELLAR" or species == "TERAPAGOS_STELLAR")
        and physicallyStronger(ctx.user, ctx.gen2) then
      return "Physical"
    end
    return nil
  end

  ------------------------------------------------------------------
  -- The live type/category swap. Priority 150 sits just inside the
  -- ability seam (type_override_moves, priority 200), so an ability's own
  -- conversion runs first and this can still refine the result; both
  -- restore the shared record afterwards.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move = ctx.move
    local id = move and move.id
    if not (move and id) then return next(ctx) end

    local typeFn = TYPE_RULES[id]
    local catFn = CATEGORY_RULES[id]
    if not (typeFn or catFn) then return next(ctx) end

    local origType, origCategory = move.type, move.category
    local changed = false

    if typeFn then
      local newType = typeFn(ctx)
      if newType and newType ~= move.type then
        move.type = newType
        changed = true
      end
    end
    if catFn then
      local newCat = catFn(ctx)
      if newCat and newCat ~= move.category then
        move.category = newCat
        changed = true
      end
    end
    if not changed then return next(ctx) end

    local ok, dmg, info = pcall(next, ctx)
    move.type = origType
    move.category = origCategory
    if not ok then
      mod.log:warn("g9-battle-engine: modern_type_modify_moves failed: %s",
        tostring(dmg))
      return 0, { crit = false, typeMult = 0 }
    end
    return dmg, info
  end, 150)

  ------------------------------------------------------------------
  -- The power half. registerPowerOverride substitutes the base power
  -- BEFORE the formula, the Phase 13 convention (a trailing multiplier
  -- would compound the formula's own floor()s in the wrong order).
  ------------------------------------------------------------------

  -- Weather Ball doubles (50 -> 100) in ANY real weather (moves.ts:20721-20740).
  registerPowerOverride("WEATHERBALL", function(ctx)
    local base = (ctx.move and ctx.move.power) or 50
    if currentWeather(ctx.battle, ctx.gen2) then return base * 2 end
    return base
  end)

  -- Terrain Pulse doubles (50 -> 100) on ANY terrain while grounded
  -- (moves.ts:19287-19292).
  registerPowerOverride("TERRAINPULSE", function(ctx)
    local base = (ctx.move and ctx.move.power) or 50
    if terrainOf(ctx.battle) and grounded(ctx.user, ctx.gen2) then return base * 2 end
    return base
  end)

  -- Tera Blast: 100 for a Stellar Terastallization, else its stored 80
  -- (moves.ts:19207-19212).
  registerPowerOverride("TERABLAST", function(ctx)
    local base = (ctx.move and ctx.move.power) or 80
    if activeTeraType(ctx.battle, ctx.user, ctx.gen2) == "STELLAR" then return 100 end
    return base
  end)

  -- Natural Gift takes its power from the held berry's real value
  -- (moves.ts:12578-12590); with no berry it keeps the record's own number.
  -- Honest partial: Showdown FAILS the move outright when no berry is held
  -- (onPrepareHit returns false); this engine's fail-gate seam is not
  -- applied here, so it plays as an ordinary Normal move instead. Documented
  -- in the plan.
  registerPowerOverride("NATURALGIFT", function(ctx)
    local base = (ctx.move and ctx.move.power) or 80
    local rec = itemFactRecord(ctx.battle, ctx.user, ctx.gen2)
    local gift = rec and rec.naturalGift
    if gift and gift.basePower then return gift.basePower end
    return base
  end)

  -- Exposed so a harness/driver can assert the dispatch tables without
  -- running a whole damage roll (the twelve-id list is the phase's contract).
  mod.exports.typeModifyRules = TYPE_RULES
  mod.exports.typeModifyCategories = CATEGORY_RULES

  mod.log:info("g9-battle-engine: modern_type_modify_moves installed "
    .. "(HIDDENPOWER, JUDGMENT, MULTIATTACK, REVELATIONDANCE, TECHNOBLAST, "
    .. "NATURALGIFT, RAGINGBULL, WEATHERBALL, TERRAINPULSE, TERABLAST, "
    .. "TERASTARSTORM, PHOTONGEYSER)")
end
