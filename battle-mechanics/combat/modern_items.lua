-- Part B Phase 5, second batch: item-interaction moves -- Fling, Knock
-- Off, Covet, Incinerate, Bug Bite, Pluck, Recycle, Belch.
--
-- Primitives confirmed by direct source read before writing anything
-- (background research this session, then several follow-up checks):
--   Held item field: Gen 2 mons carry a real string item id directly on
--   the raw mon (`mon.item`, src/battle/gen2/Mon.lua:296). Gen 1 has no
--   native item field anywhere in the engine (`src/pokemon/Pokemon.lua`),
--   so this mod stores one in a save slot -- `mon.g9HeldItem`, owned by
--   combat/modern_held_item_api.lua (round 98) -- and every read/write
--   here goes through the gen-aware itemOf/setItemOf pair below. Round 99
--   made BOTH writers/readers generation-aware: before that, a stored Gen-1
--   item could be read by the modifiers but every remover wrote `mon.item`
--   (a Gen-2-only field), so item-removal moves were no-ops for Gen 1.
--   Reads/writes route through the API's effectiveHeldItemOf /
--   HELD_ITEM_SAVED_FIELD when it has booted, with the same inlined field
--   fallback so this file also behaves standalone.
--   Item removal: no dedicated function exists anywhere in the engine --
--   the only real precedent (Berserk Gene, gen2/Battle.lua:3434-3435) is
--   a plain field assignment. Same primitive, via setItemOf.
--   battle.damage_dealt: confirmed identical shape to modern_hazards.lua's
--   own use (battle, user, target, move/moveId, damage) -- fires only
--   AFTER a landed, non-immune hit, the correct point for "on-hit" item
--   side effects (Knock Off/Covet/Bug Bite/Pluck/Fling's own consumption).
--   battle.damage (mod.hooks:wrap, NOT mod.events:on): a genuine cross-gen
--   wrap-hook, confirmed via Runtime.call("battle.damage", ...) present
--   on BOTH BattleState.lua:2335 (Gen 1) and gen2/Battle.lua:1119 (Gen 2)
--   with matching (dmg, info) return shape. modern_combat_protect.lua's
--   own Part B already establishes the pattern this file reuses for a
--   genuine pre-damage FAIL (Fling/Incinerate/Belch's conditions): wrap
--   at a priority above modern_combat.lua's own formula hook (0) and
--   short-circuit to `0, {crit=false, typeMult=0}` without calling
--   next() -- reusing EffectRegistry.lua's/gen2 Battle.lua's own already-
--   correct zero-damage handling ("It doesn't affect %s!") rather than
--   building new fail-message plumbing. Real Fling/Incinerate/Belch show
--   "But it failed!" specifically, not that text -- a known, minor,
--   deliberate reuse of the existing generic path rather than new
--   infrastructure, same tradeoff Protect's own file already made.
--   registerPowerOverride / registerDamageModifier (both modern_combat.lua
--   exports): the real per-move variable-power and final-multiplier
--   chains (Flail/Power Trip/Heat Crash precedent for the former, STAB/
--   weather precedent for the latter) -- Fling's item-dependent power and
--   Knock Off's 1.5x-if-item-present boost use these, not a move_effects
--   .run (which would hit Gen 2's "any .run field preempts damage"
--   gotcha modern_hazards.lua's own header already documents).
--   held_item.trigger (Battle:heldEffect, gen2/Battle.lua:815-826): the
--   real, mod-hookable chokepoint every native held-item effect goes
--   through, including the end-of-turn HELD_BERRY auto-heal. Used here
--   (read-only, always passes its own effect/parameter through unchanged)
--   purely to learn WHEN the native residual tick is about to actually
--   consume a berry, so Recycle/Belch have real state to work from.
--
-- GEN-1 BOUNDARIES (honest, not faked): reads/writes/removal/messages all
-- work on Gen 1 through the item API. Two things stay Gen-2-only because
-- Gen 1 genuinely has no data for them: (1) Berry Juice's residual and the
-- held_item.trigger auto-eat (the Gen-1 Berry Juice tick lives in
-- combat/modern_gen1_held_items.lua instead); (2) Bug Bite/Pluck's berry
-- EFFECT -- Gen 1's BattleState has no `itemDef`, so the berry is still
-- eaten and the target still loses it, but no heal/cure is applied (the
-- same "no Gen-1 berry data" boundary modern_gen1_held_items.lua's header
-- records). Belch's ggdConsumedBerryThisBattle is set by Bug Bite/Pluck
-- on both generations (Showdown's own `source.ateBerry = true`).
return function(mod)
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")
  -- Gen 1 has no src.battle.gen2 tree (src/mods/Loader.lua crossGenerationDenial
  -- refuses every src.*.gen2.* require on a Gen-1 boot), so the Gen-2 Battle
  -- class is resolved guardedly. The ONE place this module reads it
  -- (BUG BITE/PLUCK's HELD_STATUS_CURES taxonomy, applyEatenBerryEffect below)
  -- is Gen-2-only data anyway -- a Gen-1 boot has no berry taxonomy to read,
  -- the same boundary this file's own header records. Without this guard the
  -- whole module failed to boot on Gen 1, which cascaded through the "must load
  -- first" asserts of combat/modern_gen1_held_items.lua -- the module that
  -- gives Gen 1 its item Speed and turn-order priority -- leaving every Gen-1
  -- held-item combat effect, turn-order priority included, dead.
  local okBattle2, Battle2 = pcall(require, "src.battle.gen2.Battle")
  Battle2 = okBattle2 and Battle2 or nil

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  local registerDamageModifier = mod.exports.registerDamageModifier
  local registerPowerOverride = mod.exports.registerPowerOverride
  assert(normalize and displayNameFor and isGen2Battle and registerDamageModifier
    and registerPowerOverride, "modern_items: combat/modern_combat.lua must load first")

  -- The one real accessor for "does this battler currently hold an item,"
  -- so Frisk/Magician/Pickpocket/etc. reuse it rather than re-deriving
  -- the field rule. `gen2` says which generation's slot to read:
  --   * Gen 2 -> the raw mon's own `mon.item` (gen2/Mon.lua:458), the
  --     read this file used to be hard-wired to.
  --   * Gen 1 (gen2 false/nil) -> the saved slot modern_held_item_api
  --     owns, `mon.g9HeldItem` -- Gen 1 has no item field anywhere in
  --     the engine (src/pokemon/Pokemon.lua), so the id only exists
  --     because that API put it there. This used to return nil
  --     unconditionally for Gen 1, which is exactly why a stored Gen-1
  --     item had no combat effect anywhere (round 99).
  -- Routed through modern_held_item_api.effectiveHeldItemOf once that
  -- sibling has booted (it owns the slot name), with the same field
  -- fallback inlined so this file also behaves before it loads. `who`
  -- may be a raw mon or a Gen-1 battler wrapper (the wrapper's `.mon`
  -- carries the slot).
  local function itemOf(who, gen2)
    local effective = mod.exports.effectiveHeldItemOf
    if effective then return effective(who, gen2) end
    local m = who and (who.mon or who) or nil
    if not m then return nil end
    if gen2 then return m.item end
    return m.g9HeldItem
  end
  mod.exports.itemOf = itemOf

  -- The held-item WRITE: the exact mirror of itemOf above. Gen 2 writes the
  -- raw mon's own `item` (the native field gen2/Mon.lua owns); Gen 1 writes
  -- the saved slot modern_held_item_api owns (`g9HeldItem`) -- read back
  -- through that API's own HELD_ITEM_SAVED_FIELD export, looked up at CALL
  -- time since the API boots after this file, with the same literal fallback
  -- itemOf uses so the two readers/writers can never drift. Every
  -- item-removal/steal/give move below funnels through this one writer, so a
  -- Gen-1 removal can never accidentally write a Gen-2-only field. This is
  -- the round-99 gap: itemOf already READ a stored Gen-1 item, but every
  -- remover wrote `mon.item` directly, so a Gen-1 held item was permanent.
  -- `who` may be a raw mon or a Gen-1 battler wrapper (its `.mon` is the
  -- target). Returns the raw mon, or nil for a non-table.
  local function setItemOf(who, item, gen2)
    local m = who and (who.mon or who) or nil
    if type(m) ~= "table" then return nil end
    if gen2 then
      m.item = item
    else
      m[mod.exports.HELD_ITEM_SAVED_FIELD or "g9HeldItem"] = item
    end
    return m
  end
  mod.exports.setItemOf = setItemOf

  -- itemLabel(battle, itemId): the human-readable label every removal message
  -- uses. Gen 2's Battle carries the native item defs (`battle:itemDef`), so
  -- this reads the real name; Gen 1's BattleState has no itemDef at all (its
  -- own header notes this), so the id itself is the label -- correct, just
  -- not pretty, and never a crash. Centralized so no removal path can
  -- nil-index on a Gen-1 battle.
  local function itemLabel(battle, itemId)
    if battle and battle.itemDef then
      local def = battle:itemDef(itemId)
      if def and def.name then return def.name end
    end
    return itemId
  end
  mod.exports.itemLabel = itemLabel

  -- abilityIdOf, but for an ITEM-MOVE caller: abilityIdOf reads `mon.ability`
  -- off whatever it is handed, and a Gen-1 battler is a WRAPPER whose real mon
  -- is `.mon` (src/battle/BattleState.lua:588 makeBattler -- a wrapper has no
  -- `ability` field of its own). Gen 2's battler IS the raw mon, so unwrapping
  -- is a no-op there. Without this, every Sticky Hold / Klutz gate on a
  -- Gen-1 item removal silently read nil and never blocked.
  local function heldAbilityIdOf(who)
    local abilityIdOf = mod.exports.abilityIdOf
    if not abilityIdOf then return nil end
    return abilityIdOf(who and (who.mon or who) or who)
  end
  mod.exports.heldAbilityIdOf = heldAbilityIdOf

  -- Phase 26: Showdown's short status ids (the `fling.status` fact) -> the
  -- words Gen 2's own Battle:applyStatus accepts (gen2/Battle.lua:3396:
  -- "paralyze"/"poison"/"toxic"/"burn"/"sleep"/"freeze").
  local FLING_STATUS = {
    psn = "poison", tox = "toxic", par = "paralyze",
    brn = "burn", slp = "sleep", frz = "freeze",
  }

  -- Ripen (Phase 8, other bucket): "this Pokemon's berries have double
  -- the effect" -- real scope is the EATER's own ability, whichever
  -- berry it's eating and whoever it originally belonged to (Bug Bite/
  -- Pluck stealing an opponent's berry still doubles if the EATER is the
  -- Ripen holder) -- confirmed via Showdown's own onEatItem hook being
  -- keyed off the eating Pokemon, not the item's original holder.
  -- Defined up here (not alongside applyEatenBerryEffect further down)
  -- so the held_item.trigger wrap below -- the native auto-eat path --
  -- can call it too.
  local function ripenParameter(eater, parameter)
    local abilityIdOf = mod.exports.abilityIdOf
    if abilityIdOf and abilityIdOf(eater) == "RIPEN" then return parameter * 2 end
    return parameter
  end
  -- Cheek Pouch (Phase 8, other bucket): "whenever this Pokemon eats a
  -- Berry, it also restores 1/3 of its own max HP" -- a flat bonus heal
  -- ADDED to the berry's own real effect, not a replacement, and fires
  -- regardless of what the berry itself actually did (even a status-cure
  -- berry with no HP component of its own still heals 1/3 here).
  local function applyCheekPouch(battle, eater)
    local abilityIdOf = mod.exports.abilityIdOf
    if not (abilityIdOf and abilityIdOf(eater) == "CHEEKPOUCH") then return end
    local maxHp = eater.maxHp or (eater.stats and eater.stats.hp)
    if not (maxHp and maxHp > 0) then return end
    battle:heal(eater, math.max(1, math.floor(maxHp / 3)), { anim = "RECOVER" })
  end

  ------------------------------------------------------------------
  -- Item classification. All ids below are real, ROM-extracted Gen 2
  -- Gold/Silver constant names (tools/rom_manifest_gold.json's own
  -- itemOrder, not invented).
  --
  -- Phase 25 (item-effects plan) updated what is OWNED vs what the API
  -- supplies. national_dex's own `itemFlags` (data/items/generated/
  -- flags.lua) DOES carry `isBerry` / `isPokeball` / `fling` -- so the
  -- old "no such flag exists anywhere" claim is only true of the ROM's
  -- own item schema (R.items), not of the fact source this project now
  -- reads. That lets two tables go:
  --   * BALL_ITEMS -- replaced by `isPokeballItem(id)`. The old table
  --     listed 13 ids and wrongly included LIGHT_BALL: Showdown's
  --     `lightball` is NOT `isPokeball` (and IS flingable, 30 + par), so
  --     the old set made Light Ball unflingable. Real, fixed bug.
  --   * ITEM_FLING_POWER -- replaced by `itemFlingFacts(id).basePower`
  --     (below). The 26 hand-read values all match the API exactly; the
  --     API additionally covers 11 items the table omitted (the five
  --     evolution stones, SUN_STONE, UP_GRADE, SPELL_TAG, THICK_CLUB).
  -- What stays hardcoded is genuinely API-blind: the ten berries are
  -- Showdown "True Past" items absent from flags.lua (so KNOWN_BERRIES
  -- is still needed as the authoritative set, with `isBerryItem` layered
  -- on top for any modern berry the API does know), and Mail / Apricorns
  -- / held key items have no schema field at all.
  ------------------------------------------------------------------
  local KNOWN_BERRIES = {
    BERRY = true, GOLD_BERRY = true, MYSTERYBERRY = true,
    PSNCUREBERRY = true, PRZCUREBERRY = true, BURNT_BERRY = true,
    ICE_BERRY = true, BITTER_BERRY = true, MINT_BERRY = true,
    MIRACLEBERRY = true,
  }
  -- Exported alongside itemOf above -- same reuse reason.
  mod.exports.knownBerries = KNOWN_BERRIES
  -- isBerry(itemId): the shared berry predicate. The hardcoded Gen-2 set
  -- is authoritative (the API cannot see those ten), and `isBerryItem`
  -- from combat/modern_item_facts.lua widens it to any modern berry
  -- (a real benefit for Bug Bite / Pluck / Incinerate / Tea Time).
  local isBerryItem = mod.exports.isBerryItem
  local function isBerry(itemId)
    if KNOWN_BERRIES[itemId] then return true end
    return (isBerryItem and isBerryItem(itemId)) or false
  end
  local MAIL_ITEMS = {
    FLOWER_MAIL = true, SURF_MAIL = true, LITEBLUEMAIL = true, PORTRAITMAIL = true,
    LOVELY_MAIL = true, EON_MAIL = true, MORPH_MAIL = true, BLUESKY_MAIL = true,
    MUSIC_MAIL = true, MIRAGE_MAIL = true,
  }
  local APRICORN_ITEMS = {
    RED_APRICORN = true, BLU_APRICORN = true, YLW_APRICORN = true,
    GRN_APRICORN = true, WHT_APRICORN = true, BLK_APRICORN = true,
    PNK_APRICORN = true,
  }
  local KEY_ITEMS_HELD_UNLIKELY = {
    TOWN_MAP = true, BICYCLE = true, CARD_KEY = true, BASEMENT_KEY = true,
    PASS = true, COIN_CASE = true, ITEMFINDER = true, S_S_TICKET = true,
  }

  local isPokeballItem = mod.exports.isPokeballItem
  local itemFact = mod.exports.itemFact
  local function isUnflingable(itemId)
    if MAIL_ITEMS[itemId] or APRICORN_ITEMS[itemId]
        or KEY_ITEMS_HELD_UNLIKELY[itemId] then
      return true
    end
    if itemId:match("^TM_") ~= nil then return true end
    -- Phase 25: Poké Balls are unflingable via the API's own `isPokeball`
    -- fact, not the old hand table (which also wrongly caught LIGHT_BALL).
    if isPokeballItem and isPokeballItem(itemId) then return true end
    local facts = itemFact and itemFact(itemId)
    if type(facts) == "table" then
      -- Showdown's real rule: an item with no `fling` fact cannot be flung.
      -- (A berry carries no explicit fling field but is always flingable at
      -- 10, so it is exempted.)
      if isBerry(itemId) then return false end
      return facts.fling == nil
    end
    -- API-blind (a Gen-2 berry/bow, or a mod-registered modern item the
    -- fact source does not model): berries are flingable, everything else
    -- keeps the permissive default and uses DEFAULT_FLING_POWER below.
    return false
  end
  mod.exports.isUnflingable = isUnflingable

  -- Real games also exempt Mail from Knock Off/Thief/Covet removal --
  -- everything else in this dataset (stat items, berries, hold-battle
  -- items) is a normal removable/stealable item.
  local function isUnremovable(itemId)
    return MAIL_ITEMS[itemId] == true
  end
  -- Exported alongside itemOf/knownBerries above -- same reuse reason
  -- (Magician/Pickpocket's own real steal both respect this exact same
  -- Mail exemption Knock Off/Thief/Covet already established).
  mod.exports.isUnremovable = isUnremovable

  -- Real per-item Fling power. Phase 25 (item-effects plan): these values
  -- now come from national_dex's own `fling.basePower` fact through the
  -- combat/modern_item_facts.lua id bridge, NOT from a hand-maintained
  -- table. The 26 values this file used to hardcode were verified to match
  -- the API exactly (26/26), and the API additionally covers 11 items the
  -- table omitted (MOON_STONE, FIRE_STONE, THUNDERSTONE, WATER_STONE,
  -- LEAF_STONE, SUN_STONE, UP_GRADE, SPELL_TAG, THICK_CLUB, and the two
  -- balls-adjacent cases). Berries carry no explicit `fling` field in
  -- Showdown -- every `isBerry` item gets a flat 10 generically -- so that
  -- 10 is still applied here. Anything the API does not know falls back to
  -- DEFAULT_FLING_POWER. The removed table's own research note (the raw
  -- data/items.ts direct-read discipline it was built under) is preserved
  -- by the audit document `combat/ITEM_EFFECTS_AUDIT.md` section 6.
  local DEFAULT_FLING_POWER = 30

  local itemFlingFacts = mod.exports.itemFlingFacts
  local function flingPowerOf(itemId)
    local facts = itemFlingFacts and itemFlingFacts(itemId)
    if facts and facts.basePower then return facts.basePower end
    if isBerry(itemId) then return 10 end
    return DEFAULT_FLING_POWER
  end
  -- Exported for the harness and for any later item phase that needs the
  -- same Fling-power answer (a pure function -- safe to call anywhere).
  mod.exports.flingPowerOf = flingPowerOf

  ------------------------------------------------------------------
  -- Shared consumed-item tracking (Recycle needs to know what a mon's
  -- own held item most recently was before it disappeared; Belch needs
  -- to know only THAT one was consumed at some point this battle).
  -- Deliberately keyed on the mon table itself, not battle.hazards-style
  -- per-side state -- Gen 2 mon tables are the persistent party members
  -- (same table across many battles), so these two fields are cleared
  -- explicitly on battle.started below rather than relying on a fresh
  -- table each battle.
  --
  -- Populated from ONE real, native consumption path: the end-of-turn
  -- HELD_BERRY auto-heal (Battle:tickHeldItem, gen2/Battle.lua:4498-
  -- 4505), observed here via the held_item.trigger hook (the same
  -- chokepoint that native tick itself goes through) rather than by
  -- polling. This hook only OBSERVES -- it always returns c.effect/
  -- c.parameter unchanged, so it can never alter engine behavior, only
  -- record it. The HP-threshold re-check below mirrors the native tick's
  -- own gate exactly (mon.hp*2 <= maxHp) so this only marks an item
  -- consumed when the native tick is actually about to consume it too,
  -- not merely eligible in principle.
  --
  -- INTERACTION TODO: this is the ONLY consumption path modeled. If a
  -- future move/mechanic adds another way for a mon to consume its own
  -- item (Stuff Cheeks, Natural Gift, a low-HP-triggered attack-boost
  -- berry) it will need its own ggdLastConsumedItem/ggdConsumedBerry
  -- ThisBattle write, following this same shape -- neither field updates
  -- itself automatically for a path that doesn't go through
  -- held_item.trigger's "residual" case.
  ------------------------------------------------------------------
  -- Unnerve/As One family (Phase 7, prevent bucket): "opposing Pokémon
  -- cannot eat held Berries" -- the real, confirmed AUTO-EAT block only
  -- (Bug Bite/Pluck's own forced eating is explicitly unaffected per
  -- national_dex's own real text: "Affected Pokémon can still use Bug
  -- Bite or Pluck to eat a target's Berry" -- a different code path,
  -- applyEatenBerryEffect below, never routed through held_item.trigger
  -- at all). Checked via Battle:heldEffect's own real hook contract: a
  -- non-string returned effect reads as "no effect" to Battle
  -- :tickHeldItem's own native caller (`if not effect then return end`,
  -- confirmed by direct source read) -- so short-circuiting BEFORE the
  -- existing next(c) call, rather than after, is what actually blocks
  -- consumption instead of merely skipping this file's own bookkeeping.
  local UNNERVE_FAMILY = { UNNERVE = true, ASONEGLASTRIER = true, ASONESPECTRIER = true }
  mod.hooks:wrap("held_item.trigger", function(next, c)
    -- KLUTZ (Phase 11): "prevents using OR benefiting from a held item at
    -- all" -- the real passive held-item suppression primitive the old
    -- abilities/data/klutz.lua marker named as missing. Battle:heldEffect
    -- is the ONE chokepoint every native held-item read goes through
    -- (Quick Claw's priority, Scope Lens's crit, King's Rock's flinch,
    -- Bright Powder's accuracy, Focus Band's endure, the end-of-turn
    -- Leftovers/Berry/cure residual, ... -- all the trigger kinds that
    -- hook documents), and a non-string returned effect is read as "no
    -- effect" by every one of those callers, so short-circuiting HERE
    -- disables the whole item for a Klutz holder. Fling/Recycle are
    -- gated separately (their own checks elsewhere in this file) because
    -- they read the item id directly rather than through this hook.
    if c.mon and c.battle then
      local abilityIdOf = mod.exports.abilityIdOf
      if abilityIdOf and abilityIdOf(c.mon) == "KLUTZ" then
        return nil, 0
      end
    end
    if c.trigger == "residual" and c.effect == "HELD_BERRY" and c.mon and c.battle then
      local abilityIdOf = mod.exports.abilityIdOf
      local allActiveBattlers = mod.exports.allActiveBattlers
      if abilityIdOf and allActiveBattlers then
        local eaterSide = c.battle:sideOf(c.mon)
        for _, opp in ipairs(allActiveBattlers(c.battle)) do
          if opp and c.battle:sideOf(opp) ~= eaterSide and UNNERVE_FAMILY[abilityIdOf(opp)] then
            return nil, 0
          end
        end
      end
      local maxHp = c.mon.maxHp or (c.mon.stats and c.mon.stats.hp) or 0
      if (c.mon.hp or 0) * 2 <= maxHp then
        c.mon.ggdLastConsumedItem = c.item
        c.mon.ggdConsumedBerryThisBattle = true
        -- Ripen/Cheek Pouch (Phase 8, other bucket): this is the real
        -- native auto-eat consumption point -- mutating c.parameter here
        -- (BEFORE next(c) returns it up through Battle:heldEffect's own
        -- real contract, confirmed by direct source read: its base case
        -- literally returns c.effect/c.parameter) genuinely doubles the
        -- native heal itself, not just this file's own bookkeeping.
        c.parameter = ripenParameter(c.mon, c.parameter or 0)
        applyCheekPouch(c.battle, c.mon)
      end
    end
    return next(c)
  end, 0)

  -- Reset the consumed-item bookkeeping at battle start. Gen 2 mon tables are
  -- the persistent party members (the same table across many battles), so both
  -- parties are cleared explicitly. Gen 1 has no battle.party list at all --
  -- its battlers WRAP the real save mons -- so the active battlers and the
  -- player's save party are cleared too; otherwise a ggdLastConsumedItem left
  -- over from a previous battle would let Recycle resurrect a long-gone item
  -- on the next one.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local function reset(m)
      if type(m) == "table" then
        m.ggdLastConsumedItem = nil
        m.ggdConsumedBerryThisBattle = nil
      end
    end
    if isGen2Battle(battle) then
      for _, mon in ipairs(battle.party or {}) do reset(mon) end
      for _, mon in ipairs(battle.enemyParty or {}) do reset(mon) end
      return
    end
    reset(battle.player and (battle.player.mon or battle.player))
    reset(battle.enemy and (battle.enemy.mon or battle.enemy))
    local save = battle.game and battle.game.save
    for _, list in ipairs({ battle.party, battle.playerParty, save and save.party }) do
      if type(list) == "table" then
        for i = 1, #list do reset(list[i] and (list[i].mon or list[i])) end
      end
    end
  end)

  ------------------------------------------------------------------
  -- BERRY_JUICE (Phase 29): heal a flat 20 HP when at or below half max,
  -- then consume itself. It is NOT one of the native HELD_BERRY berries,
  -- so it never passes through the held_item.trigger residual chokepoint
  -- the auto-eat path above observes -- it needs its own residual. Real
  -- behaviour (items.ts:447 berryjuice): an onUpdate that heals 20 and
  -- calls useItem() whenever hp <= maxhp/2. Modelled on the real
  -- battle.turn_ended event (the same residual hook Black Sludge's 1/16
  -- tick uses) with the identical hp*2 <= maxHp gate the native berry
  -- tick uses. It records ggdLastConsumedItem so Recycle can restore it,
  -- but deliberately NOT ggdConsumedBerryThisBattle: Berry Juice is not a
  -- Berry, so it must not enable Belch.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not (battle and isGen2Battle(battle)) then return end
    for _, mon in ipairs({ battle.player, battle.enemy }) do
      if mon and (mon.hp or 0) > 0 and itemOf(mon, true) == "BERRY_JUICE" then
        local maxHp = mon.stats and mon.stats.hp
        if maxHp and maxHp > 0 and mon.hp * 2 <= maxHp then
          local tryHeal = mod.exports.g9TryHeal
          if tryHeal then
            tryHeal(battle, mon, 20)
          else
            mon.hp = math.min(maxHp, mon.hp + 20)
          end
          mon.ggdLastConsumedItem = "BERRY_JUICE"
          mon.item = nil
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- Stub-audit markers: one empty kind="full" record per move (the
  -- established Blizzard/Rapid Spin precedent for "real damage, real
  -- effect lives in a side hook, not in .run"), patched onto each move
  -- purely so moves_new.lua's own effect field stops reading
  -- NO_ADDITIONAL_EFFECT -- that field is this project's own stub marker
  -- (Task #9's re-audit), and every move below is fully implemented even
  -- though none of the actual logic lives inside these records.
  ------------------------------------------------------------------
  for _, id in ipairs({
    "GALAR_FLING_EFFECT", "GALAR_KNOCKOFF_EFFECT", "GALAR_COVET_EFFECT",
    "GALAR_INCINERATE_EFFECT", "GALAR_BUGBITE_EFFECT", "GALAR_BELCH_EFFECT",
  }) do
    mod.content.move_effects:register(id, { kind = "full" })
  end
  mod.content.moves:patch("FLING", { effect = "GALAR_FLING_EFFECT" })
  mod.content.moves:patch("KNOCKOFF", { effect = "GALAR_KNOCKOFF_EFFECT" })
  mod.content.moves:patch("COVET", { effect = "GALAR_COVET_EFFECT" })
  mod.content.moves:patch("INCINERATE", { effect = "GALAR_INCINERATE_EFFECT" })
  mod.content.moves:patch("BUGBITE", { effect = "GALAR_BUGBITE_EFFECT" })
  mod.content.moves:patch("PLUCK", { effect = "GALAR_BUGBITE_EFFECT" })
  mod.content.moves:patch("BELCH", { effect = "GALAR_BELCH_EFFECT" })

  ------------------------------------------------------------------
  -- FLING: real per-item power via registerPowerOverride (Flail/Power
  -- Trip's own mechanism, not a move_effects .run -- see header). The
  -- fail case (no item, or an unflingable one) is a genuine pre-damage
  -- block via the battle.damage wrap below, same tier as Protect's own
  -- block (priority 40, deliberately just under Protect's 50 -- if a
  -- target is Protected AND Fling would otherwise fail, Protect's own
  -- hook runs first and its block message wins, which reads more
  -- sensibly than a "you have nothing to throw" message on a move that
  -- was going to be blocked anyway).
  ------------------------------------------------------------------
  registerPowerOverride("FLING", function(ctx)
    local item = itemOf(ctx.user, ctx.gen2)
    if not item or isUnflingable(item) then return nil end
    return flingPowerOf(item)
  end)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local moveId = (ctx.move and ctx.move.id) or ctx.moveId
    if moveId == "FLING" then
      local gen2 = isGen2Battle(ctx.battle)
      local item = itemOf(ctx.user, gen2)
      -- Klutz (Phase 7, prevent bucket): "prevents using or benefiting
      -- from its held item, Fling included" -- real, confirmed exclusion
      -- named in Fling's own real text.
      local klutzed = heldAbilityIdOf(ctx.user) == "KLUTZ"
      if not item or isUnflingable(item) or klutzed then
        return 0, { crit = false, typeMult = 0, effectiveness = 0 }
      end
    end
    return next(ctx)
  end, 40)

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    if not (battle and moveId == "FLING" and ev.user) then return end
    local gen2 = isGen2Battle(battle)
    local ok, err = pcall(function()
      local item = itemOf(ev.user, gen2)
      if not item then return end
      local facts = itemFlingFacts and itemFlingFacts(item)
      setItemOf(ev.user, nil, gen2)
      battle:emit({ kind = "message",
        text = Strings("%s threw its %s!", displayNameFor(battle, ev.user, gen2), itemLabel(battle, item)) })
      -- Phase 26: the flung item's real on-hit riders. Showdown's Fling
      -- applies the thrown item's own `fling.status` / `fling.volatileStatus`
      -- to the target (Poison Barb -> psn, King's Rock -> flinch, Light
      -- Ball -> par). The facts come from the id bridge, so an underscore
      -- ROM id resolves. A target that fainted to the throw takes nothing.
      -- Gen 1: `battle:applyStatus` does not exist on BattleState and the
      -- volatile store is the wrapper's own field, so the flinch is
      -- written to the battler's own `flinched` field and the status rider
      -- is skipped -- the two real guards below already cover both, so no
      -- extra gating is needed. The HP gate unwraps the battler first:
      -- `target.hp` is a Gen-2 raw-mon field, and a Gen-1 wrapper carries
      -- its HP as `.mon.hp`.
      local target = ev.target
      local tm = target and (target.mon or target)
      if not (facts and target and tm and (tm.hp or 0) > 0) then return end
      if facts.volatileStatus == "flinch" then
        -- The engine's own dual flinch convention (main.lua's installMovepool
        -- Effects flinchChance block, and abilities/engine/hit_taken.lua's
        -- setFlinched): Gen 2 keeps it in battle:volatile, Gen 1 on the
        -- battler's own field. Route through that shared setFlinched
        -- primitive when it has booted -- it carries the round-27 Dynamax/
        -- Gigantamax flinch immunity and the Steadfast reaction in one
        -- place. Fall back to the raw write only on a stale engine, still
        -- gated on Dynamax so a Max'd target is never flinched either way.
        local setFlinched = mod.exports.setFlinched
        local isDyn = mod.exports.isDynamaxed
        if not (isDyn and isDyn(target)) then
          if setFlinched then
            setFlinched(battle, target, gen2)
          elseif gen2 then
            local vol = battle.volatile and battle:volatile(target)
            if vol then vol.flinched = true end
          else
            target.flinched = true
          end
        end
      end
      local status = facts.status and FLING_STATUS[facts.status]
      if status and battle.applyStatus then
        pcall(function() battle:applyStatus(target, status, ev.user) end)
      end
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_items: Fling item-clear failed: %s", tostring(err))
    end
  end)

  ------------------------------------------------------------------
  -- KNOCK OFF: 1.5x power when the target holds a removable item
  -- (real Gen 6+ rule, applies under the golden rule regardless of
  -- Gen 2's own native move list never having had this move), plus
  -- removing the item on a landed hit.
  ------------------------------------------------------------------
  registerDamageModifier("knockoff_item_present", 100, function(ctx)
    if ctx.move.id ~= "KNOCKOFF" then return 1.0 end
    local item = itemOf(ctx.target, ctx.gen2)
    return (item and not isUnremovable(item)) and 1.5 or 1.0
  end)

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    if not (battle and moveId == "KNOCKOFF" and ev.target) then return end
    local gen2 = isGen2Battle(battle)
    local ok, err = pcall(function()
      local item = itemOf(ev.target, gen2)
      -- Sticky Hold (Phase 7, prevent bucket): real, unconditional block
      -- on item removal by another Pokémon.
      local stickyHeld = heldAbilityIdOf(ev.target) == "STICKYHOLD"
      if not item or isUnremovable(item) or stickyHeld then return end
      setItemOf(ev.target, nil, gen2)
      battle:emit({ kind = "message",
        text = Strings("%s knocked off %s's %s!", displayNameFor(battle, ev.user, gen2), displayNameFor(battle, ev.target, gen2), itemLabel(battle, item)) })
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_items: Knock Off item-clear failed: %s", tostring(err))
    end
  end)

  ------------------------------------------------------------------
  -- COVET: steal the target's item if the user currently holds none.
  -- No existing steal-item precedent anywhere in the engine or mod
  -- (confirmed this session) -- built from the same gen-aware
  -- setItemOf primitive Knock Off/Fling/Berserk Gene all already use.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    if not (battle and moveId == "COVET" and ev.user and ev.target) then return end
    local gen2 = isGen2Battle(battle)
    local ok, err = pcall(function()
      if itemOf(ev.user, gen2) then return end
      local item = itemOf(ev.target, gen2)
      local stickyHeld = heldAbilityIdOf(ev.target) == "STICKYHOLD"
      if not item or isUnremovable(item) or stickyHeld then return end
      setItemOf(ev.target, nil, gen2)
      setItemOf(ev.user, item, gen2)
      battle:emit({ kind = "message",
        text = Strings("%s stole %s's %s!", displayNameFor(battle, ev.user, gen2), displayNameFor(battle, ev.target, gen2), itemLabel(battle, item)) })
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_items: Covet item-steal failed: %s", tostring(err))
    end
  end)

  ------------------------------------------------------------------
  -- INCINERATE: real rule is a genuine pre-damage FAIL (no damage at
  -- all, not just "no effect") when the target isn't holding a berry --
  -- same battle.damage wrap tier as Fling above. On a successful hit,
  -- the berry is destroyed outright (setItemOf target,nil), no effect
  -- applied to either side -- unlike Bug Bite/Pluck below, Incinerate
  -- does not eat it.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    if ((ctx.move and ctx.move.id) or ctx.moveId) == "INCINERATE" then
      local gen2 = isGen2Battle(ctx.battle)
      local item = itemOf(ctx.target, gen2)
      if not item or not isBerry(item) then
        return 0, { crit = false, typeMult = 0, effectiveness = 0 }
      end
    end
    return next(ctx)
  end, 40)

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    if not (battle and moveId == "INCINERATE" and ev.target) then return end
    local gen2 = isGen2Battle(battle)
    local ok, err = pcall(function()
      local item = itemOf(ev.target, gen2)
      if not item or not isBerry(item) then return end
      setItemOf(ev.target, nil, gen2)
      battle:emit({ kind = "message",
        text = Strings("%s's %s was burned up!", displayNameFor(battle, ev.target, gen2), itemLabel(battle, item)) })
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_items: Incinerate berry-destroy failed: %s", tostring(err))
    end
  end)

  ------------------------------------------------------------------
  -- BUG BITE / PLUCK: eat the target's berry immediately on a landed
  -- hit -- the user gets the berry's own effect (mirroring the real
  -- native heldEffect taxonomy directly off Battle.HELD_STATUS_CURES,
  -- gen2/Battle.lua:4462-4468, applied to the EATER instead of the
  -- item's own holder, rather than re-deriving/guessing the mapping),
  -- and the target loses the item same as Knock Off. Real games don't
  -- pre-gate these on damage (no fail-if-no-berry rule like Incinerate
  -- has) -- an ordinary hit against a non-berry-holder just deals
  -- ordinary damage with no bonus effect, so no battle.damage wrap here.
  ------------------------------------------------------------------
  local function applyEatenBerryEffect(battle, eater, def, eaterName)
    local effect, parameter = def.heldEffect, ripenParameter(eater, def.heldParameter or 0)
    applyCheekPouch(battle, eater)
    if effect == "HELD_BERRY" then
      battle:heal(eater, parameter > 0 and parameter or 10, { anim = "RECOVER" })
      return true
    end
    local cure = Battle2 and Battle2.HELD_STATUS_CURES[effect]
    if effect == "HELD_HEAL_STATUS" then cure = eater.status end
    if cure and eater.status == cure then
      eater.status = nil
      eater.statusTurns = nil
      eater.toxicCounter = nil
      battle:emit({ kind = "status", side = battle:sideOf(eater), status = nil,
        text = Strings("%s's status was cured!", eaterName) })
      return true
    end
    if (effect == "HELD_HEAL_CONFUSION" or effect == "HELD_HEAL_STATUS")
        and battle:volatile(eater).confuseCount then
      battle:volatile(eater).confuseCount = nil
      battle:emit({ kind = "message", text = Strings("%s's confusion was cured!", eaterName) })
      return true
    end
    return false
  end
  -- Phase 8: Tea Time (combat/modern_field_effects.lua) makes every active
  -- mon eat its held Berry, so it reuses this exact berry-effect applier
  -- rather than a second copy of the status-cure/heal taxonomy.
  mod.exports.applyEatenBerryEffect = applyEatenBerryEffect

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    if not (battle and (moveId == "BUGBITE" or moveId == "PLUCK")
        and ev.user and ev.target) then return end
    local gen2 = isGen2Battle(battle)
    local ok, err = pcall(function()
      local item = itemOf(ev.target, gen2)
      if not item or not isBerry(item) then return end
      -- Gen 2's Battle carries the native berry defs, so the eater gets the
      -- berry's real heldEffect; Gen 1's BattleState has no itemDef (its own
      -- header notes this), so the berry is still eaten and the target still
      -- loses it, but no effect is applied -- the same "no Gen-1 berry data"
      -- boundary modern_gen1_held_items.lua's own header records.
      local def = battle.itemDef and battle:itemDef(item)
      setItemOf(ev.target, nil, gen2)
      local userName = displayNameFor(battle, ev.user, gen2)
      battle:emit({ kind = "message",
        text = Strings("%s ate %s's %s!", userName, displayNameFor(battle, ev.target, gen2), itemLabel(battle, item)) })
      -- Showdown's own Bug Bite/Pluck tail (moves.ts:1918-1929, :13447-1358):
      -- `if (item.onEat) source.ateBerry = true;` -- the EATER's berry-eaten
      -- flag, which is what Belch's own onTry reads (moves.ts:1210). Mirrors
      -- onto the eater's ggdConsumedBerryThisBattle on BOTH generations (the
      -- field lives on the mon, so a Gen-1 wrapper's `.mon` carries it).
      local eater = gen2 and ev.user or (ev.user.mon or ev.user)
      if type(eater) == "table" then eater.ggdConsumedBerryThisBattle = true end
      if def then applyEatenBerryEffect(battle, ev.user, def, userName) end
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_items: Bug Bite/Pluck berry-eat failed: %s", tostring(err))
    end
  end)

  ------------------------------------------------------------------
  -- CORROSIVE GAS (missing-effects phase 10): a non-damaging status move
  -- that DESTROYS the target's held item. Transcribed directly from
  -- Showdown moves.ts:2914-2934 --
  --   onHit(target, source) {
  --     const item = target.takeItem(source);
  --     if (item) this.add('-enditem', target, item.name,
  --       '[from] move: Corrosive Gas', `[of] ${source}`);
  --     else this.add('-fail', target, 'move: Corrosive Gas');
  --   }
  -- -- i.e. it is item removal, NOT ability removal, so it lives here
  -- beside Knock Off/Thief/Covet rather than in
  -- combat/modern_ability_change_moves.lua (the pipeline plan's Phase 10
  -- entry mislabelled it "target loses its ability"; corrected there too).
  -- Pokemon.takeItem (pokemon.ts) runs the `TakeItem` event, which is
  -- exactly what Sticky Hold refuses (abilities.ts `onTakeItem: false`)
  -- and what this engine's Mail/`isUnremovable` exemption also refuses --
  -- the same two checks Knock Off already applies, reused verbatim.
  -- A pure status move, so kind="primary"+run is safe (the Gen 2
  -- .run-preempts-damage gotcha only bites DAMAGING moves).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_CORROSIVEGAS_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      -- Gen 2's dispatch ignores a run() handler's return value, so the Gen 2
      -- lines are emitted here; Gen 1 returns the list (the exact
      -- cross-generation convention modern_stat_manipulation.lua's finish()
      -- uses). Reads/writes go through the gen-aware itemOf/setItemOf pair,
      -- so this genuinely destroys a stored Gen-1 item too (round 99) -- it
      -- used to always fail on Gen 1.
      local function done(lines)
        if n.gen2 then
          for i = 1, #lines do
            n.battle:emit({ kind = "message", text = lines[i] })
          end
          return {}
        end
        return lines
      end
      local failed = { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      local target = n.target
      local item = target and itemOf(target, n.gen2)
      local stickyHeld = target and heldAbilityIdOf(target) == "STICKYHOLD"
      if not item or isUnremovable(item) or stickyHeld then return done(failed) end
      setItemOf(target, nil, n.gen2)
      return done({ Strings("%s's %s was\ncorroded away!",
        displayNameFor(n.battle, target, n.gen2), itemLabel(n.battle, item)) })
    end,
  })
  mod.content.moves:patch("CORROSIVEGAS", { effect = "GALAR_CORROSIVEGAS_EFFECT" })

  ------------------------------------------------------------------
  -- RECYCLE: non-damaging status move -- safe to use kind="primary"+run
  -- the way modern_hazards.lua's own Stealth Rock/Toxic Spikes setters
  -- do (that Gen 2 .run-preempts-damage gotcha only matters for
  -- DAMAGING moves). Restores ggdLastConsumedItem if the user currently
  -- holds no item and has one tracked; fails otherwise (already holding
  -- an item, or nothing tracked yet -- both real fail conditions).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_RECYCLE_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user = n.user
      -- ggdLastConsumedItem lives on the raw mon; on Gen 1 n.user is the
      -- battler wrapper, so unwrap it (the same field Recycle reads on Gen 2).
      local um = n.gen2 and user or (user and (user.mon or user))
      local restored = um and um.ggdLastConsumedItem
      if itemOf(user, n.gen2) or not restored or heldAbilityIdOf(user) == "KLUTZ" then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      setItemOf(user, restored, n.gen2)
      um.ggdLastConsumedItem = nil
      return { Strings("%s found a\n%s!",
        displayNameFor(n.battle, user, n.gen2), itemLabel(n.battle, restored)) }
    end,
  })
  mod.content.moves:patch("RECYCLE", { effect = "GALAR_RECYCLE_EFFECT" })

  ------------------------------------------------------------------
  -- BELCH: real rule is a genuine pre-damage FAIL unless the user has
  -- consumed (not necessarily still missing) a berry at some point this
  -- battle -- same battle.damage wrap tier as Fling/Incinerate. Power is
  -- already fixed (120) in moves_new.lua, no override needed once the
  -- fail-gate passes.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    if ((ctx.move and ctx.move.id) or ctx.moveId) == "BELCH" then
      local gen2 = isGen2Battle(ctx.battle)
      -- The flag lives on the raw mon; Gen 1's ctx.user is the battler wrapper.
      local user = gen2 and ctx.user or (ctx.user and (ctx.user.mon or ctx.user))
      if not user or not user.ggdConsumedBerryThisBattle then
        return 0, { crit = false, typeMult = 0, effectiveness = 0 }
      end
    end
    return next(ctx)
  end, 40)

  mod.log:info("galar_gmax_dex: modern_items loaded (Fling, Knock Off, Covet, "
    .. "Incinerate, Bug Bite, Pluck, Corrosive Gas, Recycle, Belch; Fling "
    .. "item secondaries; Berry Juice)")
end
