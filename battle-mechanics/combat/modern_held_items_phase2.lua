-- Held-item COMBAT effects, Phase 2: non-consumable items (explicit user
-- directive, 2026-08-28: "start with non consumables first"). None of
-- these have any real precedent on the Gold/Silver cartridge (confirmed
-- via `tools/rom_manifest_gold.json`'s own real itemOrder -- zero
-- matches for any id this file registers) except LIGHT_BALL, THICK_CLUB
-- and METAL_POWDER, which ARE real, already-holdable native items with
-- NO combat behavior wired anywhere in this engine at all (confirmed:
-- zero references to any of the three, or to the real native
-- `HELD_METAL_POWDER` effect string, anywhere in gen1recomp-dev's own
-- source) -- a real, confirmed gap, not assumed.
--
-- Every other item here is registered fresh via `mod.content.items
-- :register` (the real, sanctioned registration mechanism -- id/name/
-- price/tossable is the whole real schema, confirmed against
-- src/mods/Schemas.lua's own R.items). This file owns
-- the COMBAT effect only -- how a player actually acquires one of these
-- in-game (shop, wild find, etc.) is a real, explicitly out-of-scope
-- concern, the same "we don't handle X, we handle combat effect"
-- boundary this whole session's ability work already established for
-- transformations.
--
-- REAL BUG FOUND AND FIXED IN THIS SAME PASS: Phase 1's own type-boost-
-- item fix (combat/modern_held_items.lua, Charcoal family) is confirmed
-- DEAD CODE under this mod -- `computeModernDamage` (combat/
-- modern_combat.lua, the real function that REPLACES native damage
-- computation once this mod's own "battle.damage" wrap is installed)
-- never reads `heldEffect`/`itemBoostPercent`/any `HELD_*` string
-- anywhere in its own body (confirmed, direct grep of the whole
-- function: zero matches) -- the exact same "registered somewhere real
-- code never reaches" bug class as Scope Lens, Wonder Guard's own scale
-- bug, and the Foresight/Scrappy negation dead code, all found earlier
-- this same day. Re-implemented here via a real `registerDamageModifier`
-- entry (the same live chain STAB/weather already use) instead --
-- covers BOTH the Phase 1 native family (Charcoal etc.) and this
-- phase's new species-locked orbs/Soul Dew in one place, since they're
-- the identical real mechanic.
--
-- Real values verified against Showdown's own actual `data/items.ts`
-- source (smogon/pokemon-showdown master branch, fetched and read this
-- same pass), not memory -- summary per item; see each section's own
-- comment for the literal source fields that grounded it.
return function(mod)
  local itemOf = mod.exports.itemOf
  local isGen2Battle = mod.exports.isGen2Battle
  local registerDamageModifier = mod.exports.registerDamageModifier
  local registerPostEffectivenessModifier = mod.exports.registerPostEffectivenessModifier
  local registerPriorityModifier = mod.exports.registerPriorityModifier
  local resolvedTypeMult = mod.exports.resolvedTypeMult
  assert(itemOf and isGen2Battle and registerDamageModifier and registerPostEffectivenessModifier
      and registerPriorityModifier and resolvedTypeMult,
    "modern_held_items_phase2: combat/modern_items.lua, combat/modern_combat.lua and "
      .. "combat/turn_order.lua must all load first")

  local gen2Ok_Battle2, Battle2 = pcall(require, "src.battle.gen2.Battle")
  Battle2 = gen2Ok_Battle2 and Battle2 or nil

  local function hpOf(mon) return (mon.mon or mon) end
  local function damageFraction(mon, fraction)
    local m = hpOf(mon)
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0) then return end
    m.hp = math.max(0, (m.hp or 0) - math.max(1, math.floor(maxHp * fraction)))
  end
  -- Raw mon behind a Gen-1 battler wrapper, or the mon itself on Gen 2
  -- (round 99). species/transformed/maxHp all live on the raw mon in both
  -- generations -- a Gen-1 wrapper only exposes .mon/.def/.curStats/.stages
  -- (src/battle/BattleState.lua makeBattler), so every species gate below
  -- reads through this rather than off `user.species`.
  local function rawMon(who) return who and (who.mon or who) or nil end

  ------------------------------------------------------------------
  -- New item registrations. tossable=true matches the real native
  -- item schema; price 0 since none of these have a real in-game shop
  -- presence yet (out of
  -- this file's own combat-effect scope). pcall-guarded per item and as
  -- a whole block, same defensive pattern Counter's own bulk patch
  -- (combat/legacy_move_takeover.lua) already established -- a name
  -- collision here should never take the whole mod down.
  ------------------------------------------------------------------
  local NEW_ITEMS = {
    { id = "CHOICE_BAND", name = "Choice Band" },
    { id = "CHOICE_SPECS", name = "Choice Specs" },
    { id = "CHOICE_SCARF", name = "Choice Scarf" },
    { id = "LIFE_ORB", name = "Life Orb" },
    { id = "ASSAULT_VEST", name = "Assault Vest" },
    { id = "EVIOLITE", name = "Eviolite" },
    { id = "EXPERT_BELT", name = "Expert Belt" },
    { id = "ROCKY_HELMET", name = "Rocky Helmet" },
    { id = "BLACK_SLUDGE", name = "Black Sludge" },
    { id = "LIGHT_CLAY", name = "Light Clay" },
    { id = "QUICK_POWDER", name = "Quick Powder" },
    { id = "IRON_BALL", name = "Iron Ball" },
    { id = "LAGGING_TAIL", name = "Lagging Tail" },
    { id = "FULL_INCENSE", name = "Full Incense" },
    { id = "DEEP_SEA_TOOTH", name = "Deep Sea Tooth" },
    { id = "DEEP_SEA_SCALE", name = "Deep Sea Scale" },
    { id = "SOUL_DEW", name = "Soul Dew" },
    { id = "ADAMANT_ORB", name = "Adamant Orb" },
    { id = "LUSTROUS_ORB", name = "Lustrous Orb" },
    { id = "GRISEOUS_ORB", name = "Griseous Orb" },
  }
  do
    local registered, present = 0, 0
    for _, def in ipairs(NEW_ITEMS) do
      -- Skip an id another mod already registered (battle_forms owns
      -- GRISEOUS_ORB for Giratina's held-file form and loads first at
      -- priority 80). The engine's six-field stub is meant for ids nothing
      -- else carries, so the existing richer record wins and the duplicate
      -- no longer logs an "items already registered" failure (round 349).
      local existing = type(mod.content.items.get) == "function"
        and mod.content.items:get(def.id) or nil
      if existing ~= nil then
        present = present + 1
      else
        local ok, err = pcall(function()
          mod.content.items:register(def.id, {
            id = def.id, name = def.name, price = 0, tossable = true,
          })
        end)
        if ok then registered = registered + 1
        else mod.log:warn("g9-battle-engine: modern_held_items_phase2: "
          .. "item registration failed for %s (%s)", def.id, tostring(err)) end
      end
    end
    mod.log:info("g9-battle-engine: modern_held_items_phase2: %d/%d new items "
      .. "registered (%d already present from another mod)",
      registered, #NEW_ITEMS, present)
  end

  ------------------------------------------------------------------
  -- Type-boost family (Charcoal etc., Phase 1's own real item family --
  -- see this file's own header for why that fix had to move here) plus
  -- the four species-locked orbs. Real Gen 9 value for every entry:
  -- +20% (`chainModify([4915,4096])`, confirmed via Charcoal/Adamant
  -- Orb/Soul Dew's own real source entries). Registered at the same
  -- real chain STAB/weather already use, priority 90 (below both --
  -- order among registerDamageModifier entries doesn't change the final
  -- product, this just keeps it grouped near the other flat real-item/
  -- ability multipliers).
  ------------------------------------------------------------------
  local TYPE_BOOST_ITEMS = {
    CHARCOAL = "FIRE", MYSTIC_WATER = "WATER", MIRACLE_SEED = "GRASS",
    MAGNET = "ELECTRIC", NEVERMELTICE = "ICE", BLACKBELT_I = "FIGHTING",
    POISON_BARB = "POISON", SOFT_SAND = "GROUND", SHARP_BEAK = "FLYING",
    TWISTEDSPOON = "PSYCHIC", BLACKGLASSES = "DARK", HARD_STONE = "ROCK",
    METAL_COAT = "STEEL", DRAGON_FANG = "DRAGON", SILVERPOWDER = "BUG",
    -- Phase 27: the family's conspicuous hole -- Ghost. Real value is the
    -- same 1.2x as every other entry (items.ts:5898 `chainModify([4915,4096])`).
    SPELL_TAG = "GHOST",
  }
  -- Species-locked: item id -> { species = real Gen2 species id, types = {a,b} }
  local SPECIES_TYPE_BOOST_ITEMS = {
    ADAMANT_ORB = { species = "DIALGA", types = { STEEL = true, DRAGON = true } },
    LUSTROUS_ORB = { species = "PALKIA", types = { WATER = true, DRAGON = true } },
    GRISEOUS_ORB = { species = "GIRATINA", types = { GHOST = true, DRAGON = true } },
    -- Real Gen 9 Soul Dew (Bulbapedia, verified): a move-power boost, NOT
    -- the old Gen 3-6 stat-boost version -- the mechanic changed in Gen 7
    -- specifically to make the item tournament-legal, and this project's
    -- own standing rule is always the highest generation's real version.
    SOUL_DEW = { species = "LATIOS", altSpecies = "LATIAS", types = { PSYCHIC = true, DRAGON = true } },
  }
  local function heldItemTypeBoostMultiplier(ctx)
    -- Round 99: runs for BOTH generations now (ctx.gen2 comes off the
    -- damage ctx computeModernDamage publishes). Gen 1 reads the item via
    -- the saved g9HeldItem slot and its species off the raw mon behind the
    -- battler wrapper.
    local gen2 = ctx.gen2 and true or false
    local item = itemOf(ctx.user, gen2)
    if not item then return 1.0 end
    local plainType = TYPE_BOOST_ITEMS[item]
    if plainType and ctx.move.type == plainType then return 4915 / 4096 end
    local locked = SPECIES_TYPE_BOOST_ITEMS[item]
    if locked and locked.types[ctx.move.type] then
      local species = rawMon(ctx.user) and rawMon(ctx.user).species
      if species and (species == locked.species
          or (locked.altSpecies and species == locked.altSpecies)) then
        return 4915 / 4096
      end
    end
    -- Phase 27: Pink Bow / Polkadot Bow -- the two True-Past Normal items.
    -- items.ts:8070/8083 are `onBasePower` returning `basePower * 1.1` for
    -- a Normal move. flags.lua omits them (True Past), so the value is
    -- hand-written; 1.1 on this file's 4096-denominator damage chain is
    -- 4506/4096, the same approximation this whole 1.2 family already uses.
    if (item == "PINK_BOW" or item == "POLKADOT_BOW") and ctx.move.type == "NORMAL" then
      return 4506 / 4096
    end
    return 1.0
  end
  registerDamageModifier("held_item_type_boost", 90, heldItemTypeBoostMultiplier)
  -- Exported (pure, no battle write) so the harness can assert the type-boost
  -- family -- including the phase-27 Spell Tag / bow additions -- directly.
  mod.exports.heldItemTypeBoostMultiplier = heldItemTypeBoostMultiplier

  ------------------------------------------------------------------
  -- LIFE_ORB -- real 1.3x damage on every hit (`chainModify([5324,4096])`)
  -- plus 1/10 max HP recoil on any landed, non-Status hit, self-inflicted
  -- regardless of whether the hit was blocked/immune-to-zero (real
  -- Showdown: `onAfterMoveSecondarySelf`, fires once per move use, not
  -- gated on damage actually landing) -- checked via `battle.damage_dealt`
  -- instead (this mod's own real "landed, non-zero hit" event), a
  -- narrower real condition than Showdown's own (a hit that whiffs
  -- outright or is fully immune won't trigger recoil here, where real
  -- Showdown's recoil is independent of that) -- an honest, small,
  -- flagged divergence rather than building a new move-use-level hook
  -- for one item.
  ------------------------------------------------------------------
  registerDamageModifier("life_orb", 85, function(ctx)
    if itemOf(ctx.user, ctx.gen2) ~= "LIFE_ORB" then return 1.0 end
    return 5324 / 4096
  end)
  mod.events:on("battle.damage_dealt", function(ev)
    local user = ev and ev.user
    local move = ev and ev.move
    if not (user and move and ev.battle and (ev.damage or 0) > 0) then return end
    local gen2 = isGen2Battle(ev.battle)
    if itemOf(user, gen2) ~= "LIFE_ORB" then return end
    local nationalDex = mod.find and mod.find("national_dex")
    local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
    if not moveById then return end
    local ok, info = pcall(moveById, move.id)
    if ok and info and info.damageClass == "status" then return end
    damageFraction(user, 1 / 10)
  end)

  ------------------------------------------------------------------
  -- EXPERT_BELT -- real 1.2x on a super-effective hit only
  -- (`chainModify([4915,4096])`, gated on `typeMod > 0`). The REAL
  -- resolved type multiplier only exists after computeModernDamage's own
  -- per-row TypeChart.rows() scaling -- the same reason Wonder Guard/
  -- Filter/Tinted Lens live on registerPostEffectivenessModifier instead
  -- of registerDamageModifier (see that primitive's own header,
  -- modern_combat.lua) -- registered here on the same real chain.
  ------------------------------------------------------------------
  registerPostEffectivenessModifier("expertbelt", 0, function(ctx)
    if not ctx.user then return 1.0 end
    if itemOf(ctx.user, ctx.gen2) ~= "EXPERT_BELT" then return 1.0 end
    if ctx.mult and ctx.mult > 10 then return 4915 / 4096 end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- ROCKY_HELMET -- real 1/6 max HP contact damage back to a PHYSICAL
  -- attacker, same real primitive/pattern Iron Barbs already established
  -- (abilities/engine/contact_retaliation.lua's own real makesContact
  -- check).
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local target = ev and ev.target
    local user = ev and ev.user
    local move = ev and ev.move
    if not (target and user and move and ev.battle and (ev.damage or 0) > 0) then return end
    local gen2 = isGen2Battle(ev.battle)
    if itemOf(target, gen2) ~= "ROCKY_HELMET" then return end
    local nationalDex = mod.find and mod.find("national_dex")
    local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
    if not moveById then return end
    local ok, info = pcall(moveById, move.id)
    if not (ok and info and info.damageClass == "physical") then return end
    local makesContact = mod.exports.makesContact
    if makesContact and makesContact(move.id, user) then damageFraction(user, 1 / 6) end
  end)

  ------------------------------------------------------------------
  -- BLACK_SLUDGE -- real: heals 1/16 max HP per turn for a Poison-type
  -- holder, damages 1/8 max HP per turn for anyone else
  -- (`pokemon.hasType('Poison')`). No native precedent (unlike
  -- Leftovers) -- built fresh on the real `battle.turn_ended` event
  -- every other end-of-turn residual in this mod already uses
  -- (combat/modern_status_volatiles.lua's own Leech Seed tick, for one).
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    local curTypesOf = mod.exports.curTypesOf
    for _, who in ipairs({ battle.player, battle.enemy }) do
      local mon = rawMon(who)
      if mon and (mon.hp or 0) > 0 and itemOf(who, gen2) == "BLACK_SLUDGE" then
        local maxHp = mon.stats and mon.stats.hp
        if maxHp and maxHp > 0 then
          local isPoison = false
          for _, t in ipairs(curTypesOf and curTypesOf(who, gen2) or {}) do
            if t == "POISON" then isPoison = true end
          end
          if isPoison then
            local tryHeal = mod.exports.g9TryHeal
            if tryHeal then
              tryHeal(battle, who, math.max(1, math.floor(maxHp / 16)))
            else
              mon.hp = math.min(maxHp, mon.hp + math.max(1, math.floor(maxHp / 16)))
            end
          else
            mon.hp = math.max(0, mon.hp - math.max(1, math.floor(maxHp / 8)))
          end
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- LIGHT_CLAY -- real: extends Reflect/Light Screen (and Aurora Veil,
  -- not modeled in this engine at all yet -- a real, pre-existing gap,
  -- not introduced here) from the real base 5 turns
  -- (`Battle.SCREEN_TURNS`, gen2/Battle.lua, confirmed unchanged from
  -- Gen 2's own real native value) to 8. Monkeypatched onto the two real
  -- native `Battle.MOVE_EFFECTS` entries directly (a plain table-field
  -- override, the same sanctioned runtime-override technique combat/
  -- legacy_move_takeover.lua's own Battle2:dealDamage patch already
  -- established -- not an edit to gen1recomp-dev's own source file).
  ------------------------------------------------------------------
  if Battle2 then
    local nativeLightScreen = Battle2.MOVE_EFFECTS.EFFECT_LIGHT_SCREEN
    Battle2.MOVE_EFFECTS.EFFECT_LIGHT_SCREEN = function(self, attacker)
      local result = nativeLightScreen(self, attacker)
      local side = self.screens[self:sideOf(attacker)]
      if (side.lightScreen or 0) > 0 and itemOf(attacker, true) == "LIGHT_CLAY" then
        side.lightScreen = 8
      end
      return result
    end
    local nativeReflect = Battle2.MOVE_EFFECTS.EFFECT_REFLECT
    Battle2.MOVE_EFFECTS.EFFECT_REFLECT = function(self, attacker)
      local result = nativeReflect(self, attacker)
      local side = self.screens[self:sideOf(attacker)]
      if (side.reflect or 0) > 0 and itemOf(attacker, true) == "LIGHT_CLAY" then
        side.reflect = 8
      end
      return result
    end
  end

  ------------------------------------------------------------------
  -- Stat multipliers -- Choice Band/Specs (1.5x Atk/SpA), Assault Vest
  -- (1.5x SpD), Eviolite (1.5x Def AND SpD for a real NFE species,
  -- checked live via national_dex's own evolutionsOf -- a species with
  -- at least one real evolvesInto entry), Light Ball (2x Atk/SpA,
  -- Pikachu only -- real, confirmed, previously-unwired native item),
  -- Thick Club (2x Atk, Cubone/Marowak only -- same), Deep Sea Tooth
  -- (2x SpA, Clamperl only), Deep Sea Scale (2x SpD, Clamperl only),
  -- Metal Powder (2x Def, untransformed Ditto only -- real, confirmed,
  -- previously-unwired native item, native effect string
  -- HELD_METAL_POWDER exists in the ROM's own item name table but was
  -- never actually dispatched anywhere in gen1recomp-dev's own source).
  -- Inserted directly into computeModernDamage's own atk/dfn
  -- computation, same real insertion point Snow's own Ice-type Defense
  -- boost and burn's own Attack halving already use (both a few lines
  -- below this same real spot).
  ------------------------------------------------------------------
  local function nfe(speciesId)
    local nationalDex = mod.find and mod.find("national_dex")
    local evolutionsOf = nationalDex and nationalDex.exports and nationalDex.exports.evolutionsOf
    local evo = evolutionsOf and speciesId and evolutionsOf(speciesId)
    return evo and evo.evolvesInto and #evo.evolvesInto > 0
  end
  -- atkEventStat (optional): the move's CATEGORY stat ("attack"/"spa"), as
  -- opposed to atkStat, which is the stat actually READ from the mon. They
  -- differ only for a damage-source override (Phase 4, modern_damage_source
  -- .lua -- Body Press reads Defense while still being a Physical move).
  -- Real Showdown's ModifyAtk/ModifySpA events run against the category
  -- stat (battle-actions.ts:1713) and every item below is an onModifyAtk/
  -- onModifySpA handler (items.ts:974-975 etc.), so an unconditional
  -- Choice Band boosts Body Press too. Defaulting to atkStat keeps every
  -- non-overridden move byte-identical.
  mod.exports.applyHeldItemStatMultiplier = function(ctx, user, target, atkStat, defStat, atk, dfn, atkEventStat)
    -- Round 99: works for BOTH generations. `ctx.gen2` is published by
    -- computeModernDamage now (it used to be absent on the outer ctx, which
    -- silently early-returned here on EVERY generation and left Choice
    -- Band/Specs/Scarf, Assault Vest, Eviolite, Light Ball, Thick Club,
    -- Deep Sea Tooth/Scale and Metal Powder inert everywhere). The item
    -- and species gates below go through the gen-aware itemOf + rawMon.
    local gen2 = ctx.gen2 and true or false
    -- Magic Room (combat/trick_room.lua) suppresses every held item's effect
    -- for its duration; this is the mod's own stat-multiplier entry, not the
    -- native heldEffect path the room already nils out, so it needs its own
    -- gate.
    if ctx.battle and ctx.battle.magicRoomActive then return atk, dfn end
    local userStat = atkEventStat or atkStat
    local userItem = itemOf(user, gen2)
    local targetItem = itemOf(target, gen2)
    local userMon = rawMon(user) or {}
    local targetMon = rawMon(target) or {}
    if userItem == "CHOICE_BAND" and userStat == "attack" then
      atk = math.floor(atk * 1.5)
    elseif userItem == "CHOICE_SPECS" and userStat == "spa" then
      atk = math.floor(atk * 1.5)
    elseif userItem == "LIGHT_BALL" and userMon.species == "PIKACHU"
        and (userStat == "attack" or userStat == "spa") then
      atk = math.floor(atk * 2)
    elseif userItem == "THICK_CLUB" and userStat == "attack"
        and (userMon.species == "CUBONE" or userMon.species == "MAROWAK") then
      atk = math.floor(atk * 2)
    elseif userItem == "DEEP_SEA_TOOTH" and userStat == "spa" and userMon.species == "CLAMPERL" then
      atk = math.floor(atk * 2)
    end
    if targetItem == "ASSAULT_VEST" and defStat == "spd" then
      dfn = math.floor(dfn * 1.5)
    elseif targetItem == "EVIOLITE" and (defStat == "defense" or defStat == "spd")
        and nfe(targetMon.species) then
      dfn = math.floor(dfn * 1.5)
    elseif targetItem == "DEEP_SEA_SCALE" and defStat == "spd" and targetMon.species == "CLAMPERL" then
      dfn = math.floor(dfn * 2)
    elseif targetItem == "METAL_POWDER" and defStat == "defense" and targetMon.species == "DITTO"
        and not targetMon.transformed then
      dfn = math.floor(dfn * 2)
    end
    return atk, dfn
  end

  ------------------------------------------------------------------
  -- Speed -- Choice Scarf (1.5x), Quick Powder (2x, untransformed Ditto
  -- only), Iron Ball (0.5x, unconditional). Monkeypatched onto the real
  -- native `Battle:battleStat` (gen2/Battle.lua) -- the ONE real, shared
  -- choke point both combat/turn_order.lua's own effectiveSpeedFor AND
  -- native code everywhere else read "speed" through -- keyed strictly
  -- on `key == "speed"` so this never touches the "attack"/
  -- "specialAttack"/etc. reads the same method also serves (those go
  -- through this file's own applyHeldItemStatMultiplier above instead,
  -- a completely separate real code path).
  ------------------------------------------------------------------
  if Battle2 then
    local nativeBattleStat = Battle2.battleStat
    function Battle2:battleStat(mon, key)
      local value = nativeBattleStat(self, mon, key)
      if key ~= "speed" or not mon then return value end
      if self.magicRoomActive then return value end -- Magic Room suppresses held items
      local item = itemOf(mon, true)
      if item == "CHOICE_SCARF" then
        return math.floor(value * 1.5)
      elseif item == "QUICK_POWDER" and mon.species == "DITTO" and not mon.transformed then
        return math.floor(value * 2)
      elseif item == "IRON_BALL" then
        return math.floor(value * 0.5)
      end
      return value
    end
  end

  ------------------------------------------------------------------
  -- IRON_BALL -- real second half: grounds the holder (negates a
  -- natural Flying-type immunity to Ground-type moves), via the same
  -- real `resolvedTypeMult` negation primitive Smack Down/Telekinesis
  -- already use (combat/modern_combat.lua) -- Iron Ball is just one more
  -- real way to become "grounded," alongside that move's own volatile
  -- flag. Honest narrower scope, same shape as Smack Down's own: real
  -- Iron Ball also grounds the holder against Spikes/Toxic Spikes/Arena
  -- Trap, none of which check this same signal yet -- not built here,
  -- flagged rather than silently claimed complete.
  ------------------------------------------------------------------
  mod.exports.ironBallGrounds = function(mon, gen2)
    return itemOf(mon, gen2) == "IRON_BALL"
  end

  ------------------------------------------------------------------
  -- LAGGING_TAIL / FULL_INCENSE -- real -0.1 fractional priority
  -- (`onFractionalPriority: -0.1`, confirmed both items share the
  -- identical real value/shape). Registered on the same real
  -- registerPriorityModifier chain Stall/Quick Draw's own fractional
  -- offset already uses (abilities/engine/switch_priority_misc.lua) --
  -- the one real, live mechanism that actually intercepts BEFORE the
  -- whole-number priority/Speed compare, not just the final coinflip
  -- tiebreak.
  ------------------------------------------------------------------
  registerPriorityModifier("lagging_tail", function(battle, moveId, caster, def)
    if not caster then return 0 end
    if battle and battle.magicRoomActive then return 0 end -- Magic Room suppresses held items
    local item = itemOf(caster, true)
    if item == "LAGGING_TAIL" or item == "FULL_INCENSE" then return -0.1 end
    return 0
  end)

  ------------------------------------------------------------------
  -- CHOICE_BAND / CHOICE_SPECS / CHOICE_SCARF -- real move-lock: once
  -- the holder uses a move, it can only select that same move again
  -- until it switches out (or the move runs out of PP, at which point
  -- real Showdown frees the lock -- see the forcedMove patch below for
  -- why that falls out for free). Monkeypatched onto the real native
  -- `Battle:forcedMove` (gen2/Battle.lua) -- the SAME real function
  -- Encore/Bide/Rollout-lock already answer through, and the one
  -- `Battle:usableMoves` (the real move-menu filter) already consults,
  -- so patching just this one function correctly restricts BOTH actual
  -- move execution AND the move menu, with no separate menu-side patch
  -- needed. A brand-new own field (`ggdChoiceLockedMove`), NOT the
  -- native `state.encore` field -- aliasing onto Encore's own real
  -- field would corrupt its own separate duration/messaging semantics
  -- if the two ever overlapped on the same mon.
  ------------------------------------------------------------------
  if Battle2 then
    local nativeForcedMove = Battle2.forcedMove
    function Battle2:forcedMove(mon)
      local native = nativeForcedMove(self, mon)
      if native then return native end
      if self.magicRoomActive then return nil end -- Magic Room suppresses the Choice lock
      local locked = mon.ggdChoiceLockedMove
      if not locked then return nil end
      for _, move in ipairs(mon.moves or {}) do
        if move.id == locked and (move.pp or 0) > 0 then return locked end
      end
      mon.ggdChoiceLockedMove = nil
      return nil
    end
  end

  -- Direct monkeypatch of the real native `Battle:useMove(attacker,
  -- defender, moveId)` -- confirmed the real, whole-move entry point
  -- (NOT a named "battle.useMove" Runtime hook -- no such hook exists,
  -- confirmed by direct grep of every real Runtime.call("battle....")
  -- site in gen2/Battle.lua), the exact same real function combat/
  -- interaction_memory.lua's own recorder already wraps this same way
  -- earlier this session. `self.copyDepth` guard matches that file's
  -- own real established precedent for "don't let a called/copied move
  -- (Metronome, Mirror Move, Sleep Talk) overwrite state meant for the
  -- TOP-LEVEL move the player actually selected" -- the same real guard
  -- native `lastMove` tracking uses for an identical problem.
  if Battle2 then
    local nativeUseMove = Battle2.useMove
    function Battle2:useMove(attacker, defender, moveId)
      local result = nativeUseMove(self, attacker, defender, moveId)
      if attacker and moveId and (self.copyDepth or 0) == 0 and not self.magicRoomActive then
        local item = itemOf(attacker, true)
        if item == "CHOICE_BAND" or item == "CHOICE_SPECS" or item == "CHOICE_SCARF" then
          attacker.ggdChoiceLockedMove = moveId
        end
      end
      return result
    end
  end

  mod.events:on("battle.battler_switched", function(ev)
    local mon = ev and ev.previous
    if mon then mon.ggdChoiceLockedMove = nil end
  end)

  ------------------------------------------------------------------
  -- ASSAULT_VEST -- real second half: bans selecting a Status move
  -- outright (real exception, Me First, checked by id -- `move.id !==
  -- 'mefirst'`). Monkeypatched onto the real native `Battle:usableMoves`
  -- (gen2/Battle.lua) -- the same real move-menu filter Choice's own
  -- lock above already flows through for free via forcedMove, but this
  -- ban isn't a "locked to one move," it's "some moves are never
  -- selectable," which forcedMove's own shape can't express -- needs
  -- its own, separate filter pass over the returned list.
  ------------------------------------------------------------------
  if Battle2 then
    local nativeUsableMoves = Battle2.usableMoves
    function Battle2:usableMoves(mon)
      local out = nativeUsableMoves(self, mon)
      if self.magicRoomActive then return out end -- Magic Room suppresses held items
      -- The "does this item forbid this kind of move" test now lives in ONE
      -- place -- combat/move_usability.lua's itemMoveBanned (round 100) -- so
      -- this native menu filter and the engine->scene moveUsability query can
      -- never disagree about what an Assault Vest (or any future move-type-
      -- banning item) forbids. Resolved lazily; the pre-move_usability fallback
      -- below is the original Assault-Vest-only filter, kept for an older boot.
      local banned = mod.exports.itemMoveBanned
      local filtered = {}
      if not banned then
        if itemOf(mon, true) ~= "ASSAULT_VEST" then return out end
        local nationalDex = mod.find and mod.find("national_dex")
        local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
        if not moveById then return out end
        for _, move in ipairs(out) do
          local ok, info = pcall(moveById, move.id)
          if move.id == "MEFIRST" or not (ok and info and info.damageClass == "status") then
            filtered[#filtered + 1] = move
          end
        end
        return filtered
      end
      for _, move in ipairs(out) do
        if not banned(self, mon, move.id) then filtered[#filtered + 1] = move end
      end
      return filtered
    end
  end

  mod.log:info("g9-battle-engine: modern_held_items_phase2 installed (non-consumable "
    .. "combat items: Choice Band/Specs/Scarf, Life Orb, Assault Vest, Eviolite, Expert Belt, "
    .. "Rocky Helmet, Black Sludge, Light Clay, Quick Powder, Iron Ball, Lagging Tail, "
    .. "Full Incense, Deep Sea Tooth/Scale, Soul Dew, the three Sinnoh orbs; Light Ball/"
    .. "Thick Club/Metal Powder's own previously-unwired native combat effect; Phase 1's "
    .. "dead-code type-boost-item fix corrected. Big Root explicitly deferred -- needs a "
    .. "real drain-heal interception point this engine doesn't expose yet, see PROGRESS.md)")
end
