-- Held-item COMBAT effects, Phase 1: auditing the items Gen 2 already
-- has real, ROM-driven behavior for (Quick Claw, Focus Band, King's
-- Rock, BrightPowder, the Charcoal-family type-boost items, Scope Lens,
-- Leftovers) against real Pokemon Showdown Gen 9 logic, and overriding
-- every real divergence found. Explicit standing rule (2026-08-28,
-- confirmed directive): "we override item behavior for native items,
-- always, imperative, in terms of combat" -- this mod OWNS combat item
-- behavior outright, the same principle combat/legacy_move_takeover.lua
-- already established for the nine classic damage moves ("it's
-- imperative all damage goes through us, else we lose turn order
-- control"). Gen 1 stores held items in the mod-owned save slot
-- `mon.g9HeldItem` (combat/modern_held_item_api.lua), and round 99 made this
-- file's per-item readers gen-aware: BrightPowder, Scope Lens and the crit
-- items (Lucky Punch/Stick) now read and enforce on BOTH generations (via the
-- local `heldItemAny`). The items whose real native mechanism is the
-- Gen-2-only `held_item.trigger` hook -- Quick Claw, Focus Band, King's
-- Rock's roll, Leftovers, the berry auto-eat -- stay Gen-2 here on purpose;
-- their Gen-1 behaviour is combat/modern_gen1_held_items.lua's job precisely
-- because Gen 1 has no such hook.
--
-- Real mechanism: `held_item.trigger` (gen2/Battle.lua's own real,
-- already-mod-hookable choke point EVERY native held-item effect goes
-- through -- Quick Claw's priority roll, Scope Lens/type-boost's damage
-- check, Focus Band's endure check, King's Rock's flinch roll,
-- BrightPowder's accuracy check, Leftovers/Berry's residual tick, all
-- funnel through this ONE function, `Battle:heldEffect`). Its own real
-- contract (that function's own header comment): a wrap returning
-- (effect, parameter) SUBSTITUTES the item's real behavior at that
-- trigger; returning a non-string effect reads as "no effect," the
-- clean way to fully suppress a native mechanic this file replaces with
-- a differently-shaped one instead (BrightPowder, Scope Lens below).
--
-- Real values verified against Showdown's own actual source
-- (data/items.ts, smogon/pokemon-showdown master branch, fetched and
-- read this same pass -- the same direct-read discipline this session's
-- Leech Seed/Magic Guard/legacy-move work already established, not
-- assumed from memory) rather than guessed:
--   QUICK_CLAW  -- real Gen 9: 1/8 chance (12.5%), NOT a flat priority-
--     tie win -- modern Quick Claw is `onFractionalPriority`, adding a
--     +0.1 fractional priority BEFORE the whole-number priority/speed
--     compare. In a 2-battler engine with no other fractional-priority
--     source, this reduces to the exact same real-world OUTCOME as
--     Gen 2's own native "consulted only once priority ties" shape
--     (0.1 can win a tie against an equal whole-number priority, but
--     can never overcome a real +1 priority-point move) -- so only the
--     PROBABILITY needed correcting, not the trigger site itself. Gen
--     2's own native byte was 60/256 (~23.4%); real modern is 1/8 =
--     32/256 exactly.
--   FOCUS_BAND  -- real Gen 9: 1/10 (10%), applies only to Move-sourced
--     lethal damage (`effect.effectType === 'Move'`) -- Gen 2's own
--     native check already only fires from inside `hitOnce`'s own
--     "endure" trigger, which only ever runs for a move hit, so no
--     extra gate needed there. Native byte was 30/256 (~11.7%); real
--     modern is 1/10, nearest achievable on this same 0-256 roll scale
--     is 26/256 (~10.16%, the closest integer byte to true 10%).
--   KINGS_ROCK  -- real Gen 9: 10% (was 30/256, ~11.7%, on the native
--     byte scale -- same rounding as Focus Band, 26/256). Real modern
--     rule ALSO only ADDS the flinch chance to a move's own secondary
--     list if that move doesn't already carry a flinch secondary of its
--     own (`if (secondary.volatileStatus === 'flinch') return`) -- so a
--     King's Rock holder using Rock Slide/Headbutt/Bite/Iron Head (the
--     EFFECT_FLINCH_HIT family) should NOT also get King's Rock's own
--     separate roll on top. Gen 2's own native check (BattleCommand_
--     HeldFlinch) has no such exemption -- confirmed by direct read, a
--     real, genuine double-dip bug fixed here by checking the currently
--     resolving move's own effect (via `battle:volatile(attacker)
--     .lastMove`, written by `Battle:useMove` before `hitOnce` ever
--     runs -- the same real field Disable/Encore/Mirror Move already
--     rely on, reused rather than building new state) against
--     EFFECT_FLINCH_HIT before honoring the item at all.
--   BRIGHTPOWDER -- real Gen 9: a genuine MULTIPLICATIVE ~90% accuracy
--     factor (`chainModify([3686, 4096])`), not an additive penalty.
--     Gen 2's own native check (`Battle:moveAccuracy`) subtracts a flat
--     byte (20, scaled to the percent domain) from the accuracy number
--     BEFORE the roll -- a genuinely different SHAPE, not just a
--     different number (a flat -7.8-ish points is a much smaller nerf
--     against a high-accuracy move and a much bigger one against a
--     low-accuracy move than a real 10% multiplicative cut). Since the
--     two shapes can't be reconciled by adjusting the native byte
--     parameter alone, this file suppresses the native check entirely
--     (returns a non-string effect at the "accuracy" trigger) and
--     re-implements it as a real `registerAccuracyModifier` entry
--     instead (the same real, already-sanctioned multiplier chain
--     abilities/engine/accuracy_multiplier.lua's own Compound Eyes/
--     Hustle/Victory Star already use) -- the correct shape, not an
--     approximation forced into the wrong mechanism.
--   Type-boost items (CHARCOAL, MYSTIC_WATER, MIRACLE_SEED, MAGNET,
--     NEVERMELTICE, BLACKBELT_I, POISON_BARB, SOFT_SAND, SHARP_BEAK,
--     TWISTEDSPOON, BLACKGLASSES, HARD_STONE, METAL_COAT, DRAGON_FANG,
--     SILVERPOWDER) -- real Gen 9: +20% (`chainModify([4915, 4096])`,
--     confirmed via Charcoal's own real source entry), a real
--     GENERATIONAL buff over Gen 2's own native +10%. **STALE AS
--     ORIGINALLY WRITTEN HERE**: the fix below (overriding the native
--     "damage" trigger's own parameter) was confirmed DEAD CODE the very
--     next pass (combat/modern_held_items_phase2.lua's own header) --
--     computeModernDamage never reads the native itemBoostPercent field
--     at all. Real, reachable fix now lives in that file's own
--     "held_item_type_boost" registerDamageModifier entry instead; this
--     file's own "damage" trigger no longer touches these items.
--   SCOPE_LENS -- real Gen 9: +1 crit stage, the same real family Focus
--     Energy's own +2 stages already belongs to. Gen 2's own native
--     HELD_CRITICAL_UP check feeds Gen 2's own OWN crit LADDER (a
--     completely different system -- speed-based odds, no discrete
--     stages at all) -- but that native roll is CONFIRMED DEAD CODE
--     under this mod already: combat/modern_combat.lua's own
--     computeModernDamage (the real handler this mod installs on
--     "battle.damage") independently re-rolls its own crit via a SECOND
--     "battle.crit" call using its own real Gen 6+ stage system
--     (modernCritStage/modernCritRoll, confirmed by direct read: it
--     never consults ctx.opts.critical, the field Gen 2's own native
--     pre-roll would have populated), so whatever the native ladder
--     decided is silently discarded whenever this mod's own damage path
--     runs -- meaning Scope Lens currently does NOTHING under this mod,
--     a real, confirmed bug of the exact same shape ("registered
--     somewhere real code never reaches") this same day's earlier
--     Wonder-Guard-reachability review already found twice. Fixed by
--     registering a real `registerCritStageModifier` entry instead --
--     the correct, already-live system, not the dead native one.
--   LEFTOVERS -- checked, NOT changed: real Gen 9 is `baseMaxhp / 16`
--     per turn, identical to Gen 2's own native `HELD_LEFTOVERS` heal
--     amount (`gen2/Battle.lua:4901`, confirmed by direct read) -- the
--     one item in this batch that was already correct.
return function(mod)
  local itemOf = mod.exports.itemOf
  local isGen2Battle = mod.exports.isGen2Battle
  local registerAccuracyModifier = mod.exports.registerAccuracyModifier
  local registerCritStageModifier = mod.exports.registerCritStageModifier
  assert(itemOf and isGen2Battle and registerAccuracyModifier and registerCritStageModifier,
    "modern_held_items: combat/modern_items.lua, combat/modern_combat.lua and "
      .. "abilities/engine/accuracy_multiplier.lua must all load first")

  -- Either generation's held-item slot: Gen 2's native mon.item first, else
  -- Gen 1's saved g9HeldItem (via the gen-aware itemOf). A mon cannot hold
  -- both (Gen 1 has no .item field anywhere in the engine), so this is
  -- unambiguous -- and it keeps the accuracy/crit chains working on
  -- modernCritRoll's direct-call path, where the ctx carries no battle to
  -- derive a generation from.
  local function heldItemAny(who)
    return itemOf(who, true) or itemOf(who, false)
  end

  -- Raw mon behind a Gen-1 battler wrapper, or the mon itself on Gen 2.
  local function rawMon(who) return who and (who.mon or who) or nil end

  ------------------------------------------------------------------
  -- Quick Claw / Focus Band / King's Rock / type-boost items / Bright
  -- Powder -- one shared "held_item.trigger" wrap, keyed on (item id,
  -- trigger), since every one of these overrides is a plain
  -- substitution the real hook contract already supports directly.
  ------------------------------------------------------------------
  mod.hooks:wrap("held_item.trigger", function(next, c)
    if c.trigger == "priority" and c.item == "QUICK_CLAW" then
      return "HELD_QUICK_CLAW", 32 -- real 1/8 (12.5%), was 60/256 (~23.4%)
    end
    if c.trigger == "endure" and c.item == "FOCUS_BAND" then
      return "HELD_FOCUS_BAND", 26 -- real 1/10 (10%), was 30/256 (~11.7%)
    end
    if c.trigger == "flinch" and c.item == "KINGS_ROCK" then
      -- Real modern rule: no-op if the CURRENT move already carries its
      -- own flinch secondary (EFFECT_FLINCH_HIT -- Rock Slide, Headbutt,
      -- Bite, Iron Head, Zen Headbutt, ...). c.mon here is the
      -- ATTACKER (the "flinch" trigger's own real contract, confirmed:
      -- BattleCommand_HeldFlinch checks the item on whoever's move just
      -- connected), so its own volatile lastMove is the move actually
      -- resolving right now.
      local lastMoveId = c.battle and c.mon and c.battle:volatile(c.mon).lastMove
      local moveDef = lastMoveId and c.battle:moveDef(lastMoveId)
      if moveDef and moveDef.effect == "EFFECT_FLINCH_HIT" then
        return nil, 0
      end
      return "HELD_FLINCH", 26 -- real 10%, was 30/256 (~11.7%)
    end
    if c.trigger == "damage" and c.item then
      -- Type-boost family: the PARAMETER correction that used to live
      -- here (10 -> TYPE_BOOST_REAL_PERCENT) is GONE as of the Phase 2
      -- pass (combat/modern_held_items_phase2.lua) -- confirmed genuine
      -- dead code, same shape as Scope Lens just below: this native
      -- "damage" trigger only ever feeds Damage.calc's own
      -- itemBoostPercent field, and computeModernDamage (the function
      -- that REPLACES native damage computation once this mod's own
      -- "battle.damage" wrap is installed) never reads that field at
      -- all (confirmed, direct grep of the whole function). Real fix
      -- now lives in modern_held_items_phase2.lua's own
      -- "held_item_type_boost" registerDamageModifier entry -- the
      -- actually-reachable chain -- so this trigger no longer touches
      -- the type-boost family at all; native keeps its own real
      -- (harmless, unreached) +10% value undisturbed.
      -- Scope Lens: suppress the native crit-ladder contribution
      -- entirely (confirmed dead code under this mod's own modern crit
      -- path -- see this file's own header) rather than leave a stale,
      -- never-honored native value in place; the real effect is
      -- registered below via registerCritStageModifier instead.
      if c.item == "SCOPE_LENS" then
        return nil, 0
      end
    end
    if c.trigger == "accuracy" and c.item == "BRIGHTPOWDER" then
      -- Suppress the native flat-byte subtraction entirely -- real
      -- modern BrightPowder is multiplicative (registerAccuracyModifier
      -- entry below), a shape the native accuracy-byte parameter can't
      -- express (see this file's own header).
      return nil, 0
    end
    return next(c)
  end, 0)

  ------------------------------------------------------------------
  -- BrightPowder -- real multiplicative ~90% accuracy factor, via the
  -- same real registerAccuracyModifier chain Compound Eyes/Hustle/
  -- Victory Star already use (abilities/engine/accuracy_multiplier.lua).
  -- ctx.target is the intended victim of the incoming move -- BrightPowder
  -- is the DEFENDER's own held item, same convention as native
  -- moveAccuracy's own `self:heldEffect(defender, "accuracy")`.
  ------------------------------------------------------------------
  registerAccuracyModifier("brightpowder", 0, function(ctx)
    if not ctx.target then return 1.0 end
    if heldItemAny(ctx.target) ~= "BRIGHTPOWDER" then return 1.0 end
    return 3686 / 4096
  end)

  ------------------------------------------------------------------
  -- Scope Lens -- real +1 crit stage, the same real chain Focus Energy's
  -- own +2 already lives on (combat/modern_combat.lua's own
  -- modernCritStage). ctx.user here is the attacker (this crit chain's
  -- own established convention, confirmed via Focus Energy's own
  -- `ctx.user.focusEnergy` check right above where this chain runs).
  ------------------------------------------------------------------
  registerCritStageModifier("scopelens", function(ctx)
    if not ctx.user then return 0 end
    return heldItemAny(ctx.user) == "SCOPE_LENS" and 1 or 0
  end)

  ------------------------------------------------------------------
  -- Lucky Punch / Stick (Phase 28) -- the other two real crit items, the
  -- ones the Scope Lens work above left behind. Both are +2 crit stages
  -- (items.ts:3517 luckypunch, :6092 stick), unlike Scope Lens's +1, and
  -- both are species-locked: Lucky Punch only helps Chansey, Stick only
  -- Farfetch'd. The species list is read from national_dex's own `itemUser`
  -- fact through combat/modern_item_facts.lua (`itemSpeciesMatch`), so the
  -- gate is data-driven rather than a second hand table; a hardcoded
  -- fallback covers a load order without the facts module. This is a
  -- COMPANION entry to the Scope Lens one above -- modernCritStage sums
  -- every registered entry, so the two compose (a mon holds one item, so
  -- only ever one of them is non-zero).
  ------------------------------------------------------------------
  local function critSpeciesAllowed(id, species)
    local match = mod.exports.itemSpeciesMatch
    if match then
      local ok, res = pcall(match, id, species)
      if ok and res ~= nil then return res end
    end
    if id == "LUCKY_PUNCH" then return species == "CHANSEY" end
    if id == "STICK" then return species == "FARFETCHD" or species == "FARFETCH_D" end
    return false
  end
  local function critItemStage(id, species)
    if (id == "LUCKY_PUNCH" or id == "STICK") and critSpeciesAllowed(id, species) then
      return 2
    end
    return 0
  end
  registerCritStageModifier("crititems", function(ctx)
    if not ctx.user then return 0 end
    local m = rawMon(ctx.user)
    return critItemStage(heldItemAny(ctx.user), m and m.species)
  end)
  -- Exported (pure) so the harness can assert the species gate directly.
  mod.exports.critItemStage = critItemStage
  mod.exports.critSpeciesAllowed = critSpeciesAllowed

  mod.log:info("g9-battle-engine: modern_held_items installed, Phase 1 native-item "
    .. "audit (QUICK_CLAW, FOCUS_BAND, KINGS_ROCK, BRIGHTPOWDER, the type-boost family, "
    .. "SCOPE_LENS corrected to real Gen 9 values/shapes; LEFTOVERS verified unchanged; "
    .. "Phase 28 LUCKY_PUNCH/STICK +2 crit)")
end
