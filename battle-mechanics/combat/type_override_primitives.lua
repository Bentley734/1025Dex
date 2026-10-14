-- Type override: the generic "this mon's own current type changes mid-
-- battle" primitive -- Soak/Magic Powder/Burn Up/Double Shock/Conversion/
-- Reflect Type/Camouflage (moves, wired in combat/modern_type_change_moves
-- .lua) today; Protean/Libero/Color Change/Forecast (abilities) once this
-- engine has an ability system, per explicit user decision reusing the
-- SAME entrypoint. Distinct from Terastallization (combat/modern_tera.lua)
-- -- its own separately-owned, stable system -- this primitive never
-- touches Tera's own formTypes field or vice versa.
--
-- LABEL: "change_type" -- not invented here. national_dex's own ability
-- data (0.30.0+, dex.exports.abilityById) already tags Protean/Libero/
-- Color Change/Forecast/Multitype with exactly this kind in their own
-- `behaviour.effects[].kind` field (confirmed directly, fetched from the
-- real data, not assumed) -- reused verbatim per the explicit rule "if
-- there's no label... we make the label ourselves": here, one already
-- exists, so it is not remade. National Dex's own move data has no
-- structured kind vocabulary at all (moveById's effect/shortEffect are
-- free text only) -- there IS no label to reuse for the move side, so
-- move-triggered cases key off this same "change_type" string by our own
-- choice, for one consistent vocabulary across both sources, per that same
-- rule's other half.
--
-- STORAGE: mutates mon.types directly, Gen 2 only (this mod's own
-- established scope for a mechanic neither engine had natively --
-- trick_room.lua/modern_terrain.lua's own precedent) -- the exact same
-- field mod.exports.curTypesOf already reads as the "live type list" for
-- STAB and every type-effectiveness check (modern_combat.lua's own
-- confirmed convention: curTypesOf(who, true) = who.types, cited directly
-- against Gen 2's own native STAB check, gen2/Damage.lua:249-253).
--
-- RESET: real Pokemon Showdown resets a type override the instant
-- clearVolatile runs (confirmed directly, smogon/pokemon-showdown's own
-- sim/pokemon.ts: clearVolatile's own last line is `this.setSpecies(this.
-- baseSpecies)`, and setSpecies itself calls `this.setType(species.types,
-- true)` -- i.e. on every switch, both sides, unconditionally, the same
-- lifecycle point stat boosts/Substitute/etc. already reset on). This
-- engine's own Battle:clearVolatile is already called on every real switch
-- path in this mod (Battle:switch's own two calls, native EFFECT_
-- BATON_PASS's own call on the passer, native EFFECT_FORCE_SWITCH's own
-- call on the dragged-out defender, combat/switch_primitives.lua's own
-- switchMonAtSide) -- so wrapping that ONE method, rather than hooking
-- every individual switch path separately, is what makes reset-on-switch
-- correct everywhere for free, mirroring real PS's own architecture
-- exactly.
return function(mod)
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil

  ------------------------------------------------------------------
  -- The dictionary: every real change_type source this project knows
  -- about, move and ability alike, keyed by id -- confirmed against
  -- national_dex's own data directly (moveById's effect text for the
  -- move side, abilityById's own behaviour.effects[].kind="change_type"
  -- for the ability side), not assembled from memory. `wired` says
  -- whether this id's actual behavior is implemented anywhere in this mod
  -- today; every `false` entry here is a real, known gap (no ability
  -- system exists yet; Conversion 2 needs new tracking -- see combat/
  -- modern_type_change_moves.lua's own header), not a silent omission.
  -- `timing`/`scope` describe HOW each case fires, per explicit user
  -- instruction that "each case (move/ability) define how it happens" --
  -- e.g. Protean/Libero apply at move-selection time, matching the
  -- move's own type, once per switch-in; Soak applies on-hit, to the
  -- TARGET, unconditionally. This table is read-only reference data --
  -- nothing in this file dispatches off it automatically; a caller (a
  -- move_effects handler today, a future ability hook) still does its own
  -- work and may consult this only to know it exists.
  ------------------------------------------------------------------
  mod.exports.TYPE_CHANGE_SOURCES = {
    -- Moves -- wired in combat/modern_type_change_moves.lua.
    SOAK = { source = "move", scope = "target", timing = "on_hit", wired = true },
    MAGICPOWDER = { source = "move", scope = "target", timing = "on_hit", wired = true },
    CONVERSION = { source = "move", scope = "self", timing = "on_hit", wired = true },
    CONVERSION2 = { source = "move", scope = "self", timing = "on_hit", wired = false,
      note = "needs a 'type of the last move that hit this mon' tracker and a reverse type-chart lookup, neither of which exist in this engine yet" },
    REFLECTTYPE = { source = "move", scope = "self", timing = "on_hit", wired = true },
    CAMOUFLAGE = { source = "move", scope = "self", timing = "on_hit", wired = true },
    BURNUP = { source = "move", scope = "self", timing = "on_hit_after_damage", wired = true },
    DOUBLESHOCK = { source = "move", scope = "self", timing = "on_hit_after_damage", wired = true },
    -- Abilities -- data only, not wired: no ability system exists in this
    -- engine yet. Kept here so the day one exists, the dictionary already
    -- has the real entries to build against instead of a fresh audit.
    PROTEAN = { source = "ability", scope = "self", timing = "on_move_selected",
      oncePerSwitchIn = true, wired = false,
      note = "matches the type of the move about to be used, applied before damage so STAB is correct" },
    LIBERO = { source = "ability", scope = "self", timing = "on_move_selected",
      oncePerSwitchIn = true, wired = false, note = "identical mechanic to Protean" },
    COLORCHANGE = { source = "ability", scope = "self", timing = "on_damaged", wired = false,
      note = "becomes the type of whatever move just hit it; doesn't trigger on Substitute-blocked or indirect damage" },
    -- Forecast, unlike Protean/Libero, has no oncePerSwitchIn limit of its
    -- own -- real Castform retriggers on EVERY weather change while it's
    -- on the field, not just once per switch-in (fires from a weather
    -- change caused by ANY mon, not only Castform's own move) -- so this
    -- field is deliberately absent here rather than copied from Protean's
    -- shape. Same Tera interaction as Protean/Libero regardless: once
    -- Castform is Terastallized, canChangeType blocks every further
    -- Forecast retrigger for the rest of the battle (per this file's own
    -- explicit user rule -- Terastallized blocks BOTH self- and
    -- opponent-triggered change_type, no exceptions), and a weather change
    -- that lands on the SAME turn Castform Terastallizes still applies
    -- Forecast's own type/form change BEFORE that turn's Tera activation
    -- -- the identical ordering canChangeType's own header documents for
    -- Protean/Libero, generalized from "move selection" to "whatever
    -- triggers Forecast," not a separate rule.
    FORECAST = { source = "ability", scope = "self", timing = "on_weather_change", wired = false,
      note = "species-locked to Castform; also changes form, not just type" },
    MULTITYPE = { source = "ability", scope = "self", timing = "static", wired = false,
      note = "type is derived from the held Plate rather than battle-triggered; species-locked to Arceus" },
  }

  -- Real base types for a mon, straight from its own species record --
  -- reused from combat/modern_tera.lua (must load after it) rather than
  -- re-deriving the same lookup a second time.
  local originalTypesOf = mod.exports.originalTypesOf
  assert(originalTypesOf, "type_override_primitives: combat/modern_tera.lua must load first")

  -- The one generic primitive every type-override effect calls (a move
  -- today, an ability once this engine has one). `types` is a plain array
  -- of type-id strings ({"WATER"} for Soak, etc.) -- always REPLACES the
  -- mon's whole type list, matching every real change_type move/ability
  -- (none of them add a type alongside the existing ones; Forest's Curse/
  -- Trick-or-Treat ADD a type instead and are a distinct, separate
  -- mechanic this primitive does not cover). Always stores a fresh copy,
  -- never the caller's own table reference, so two mons can never end up
  -- silently sharing one type-list table (Reflect Type's own real risk,
  -- copying directly off another mon's live list).
  function mod.exports.setMonTypes(battle, mon, types)
    assert(battle and mon and type(types) == "table", "setMonTypes: battle, mon, and types are required")
    local copy = {}
    for i,t in ipairs(types)do
      if t=='PSYCHIC' and battle.data.type_chart.types.PSYCHIC_TYPE then t='PSYCHIC_TYPE'end
      copy[i]=t
    end
    if not mod.exports.isGen2Battle(battle) then
      if not mon.mon then
        if battle.player and battle.player.mon==mon then mon=battle.player
        elseif battle.enemy and battle.enemy.mon==mon then mon=battle.enemy end
      end
      mon.curTypes=copy
    else mon.types=copy end
  end

  ------------------------------------------------------------------
  -- The gate: whether `mon`'s own type is allowed to change right now.
  -- Explicit user rules, this session:
  --
  -- 1. TERASTALLIZATION: once a mon is Terastallized, its type can never
  --    be changed again this battle -- neither by its own move/ability
  --    (Protean/Libero/Conversion/Camouflage/Burn Up/Double Shock/Reflect
  --    Type's self side) nor by an opponent's move targeting it (Soak/
  --    Magic Powder). Checked via combat/modern_tera.lua's own
  --    isTerastallized (must load before this file).
  --
  --    SAME-TURN ORDERING with Protean/Libero, stated explicitly by the
  --    user and not re-derivable from this gate alone -- a future ability
  --    hook must call this gate (and setMonTypes) BEFORE the same turn's
  --    Tera activation happens, never after: "user first changes type,
  --    setting their new base type... then comes tera activation, lastly
  --    comes move resolution (stab applications)." Checking isTerastallized
  --    at trigger time already produces this correctly AS LONG AS the
  --    caller's own sequencing is right -- Tera genuinely isn't active yet
  --    at the moment Protean/Libero would fire on the turn a mon does
  --    both, so this gate reads false (allowed) at exactly the right
  --    moment. This gate cannot enforce call-order itself; it can only
  --    answer correctly if asked at the correct point.
  --
  --    Forecast follows the identical rule, generalized from "move
  --    selection" to "whatever triggers Forecast" (a weather change, from
  --    any mon's move, not just Castform's own): a weather change landing
  --    on the same turn Castform Terastallizes still updates its type/form
  --    before that turn's Tera activation, the same "changes lock in
  --    first, Tera comes after" ordering, not a separate case. Once
  --    Castform IS Terastallized, this gate blocks every later Forecast
  --    retrigger for the rest of the battle, same as it blocks Protean/
  --    Libero from firing again.
  --
  -- 2. DYNAMAX/GIGANTAMAX, asymmetric on purpose: a Dynamaxed/Gigantamaxed
  --    mon can still change ITS OWN type (Protean/Libero keep working --
  --    Soak/Camouflage/etc. used BY a Dynamaxed mon are moot rather than
  --    blocked, since every one of its own status moves is substituted
  --    into Max Guard while Dynamaxed -- battle_forms's own src/
  --    substitute.lua, confirmed directly -- so Soak's own handler is
  --    simply never reached as the attacker; nothing to gate here). But a
  --    Dynamaxed/Gigantamaxed mon can NEVER have its type changed BY AN
  --    OPPONENT -- Soak/Magic Powder targeting a Dynamaxed mon always
  --    fails, the real Gen 8+ Dynamax immunity.
  --
  --    WIRED (2026-09-12, plan phase 12): battle_forms itself still
  --    exposes no queryable "is mon X dynamaxed right now" API (its own
  --    active-Dynamax state is a dynamax.lua-local `state` table, never
  --    put on mod.exports -- only armState, a different question, and
  --    the transforms registry are). It does not need to: this mod's OWN
  --    gigantamax/dynamax_battle.lua stamps `mon.__g9Dynamaxed = true`
  --    on battle_forms' dynamax_applied event and clears it on
  --    dynamax_reverted (dynamax_battle.lua:109/134), keyed on the LIVE
  --    mon identity battle_forms' own payload carries. The opponent-side
  --    check below reads that marker, so Soak/Magic Powder targeting a
  --    Dynamaxed mon now fails as the real Gen 8+ rule requires.
  ------------------------------------------------------------------
  function mod.exports.canChangeType(battle, mon, opts)
    opts = opts or {}
    if mod.exports.isTerastallized and mod.exports.isTerastallized(battle, mon, true) then
      return false
    end
    if opts.viaOpponent then
      -- Dynamax/Gigantamax immunity (real Gen 8+; closes the header TODO):
      -- a Dynamaxed mon can never have its type changed BY AN OPPONENT.
      -- The marker is this mod's own gigantamax/dynamax_battle.lua
      -- (mon.__g9Dynamaxed, set on battle_forms' dynamax_applied event and
      -- cleared on dynamax_reverted). Both call shapes are probed: Gen 1
      -- stores the raw mon at battle.player.mon, so a battler wrapper
      -- still matches through .mon -- the same both-shapes probe
      -- modern_hazards.lua's grounding check already uses.
      if mon and (mon.__g9Dynamaxed or (mon.mon and mon.mon.__g9Dynamaxed)) then
        return false
      end
      -- Boss-fight "type" protection (combat/boss_fight.lua): the boss's
      -- type can't be changed by an opponent-directed effect (Soak et al)
      -- while active -- opts.viaOpponent is exactly "imposed from
      -- outside," matching the user's "unless self activated" carve-out
      -- for free; the boss's own self-activated kit (Protean, Color
      -- Change, a self-targeted Conversion) never sets viaOpponent, so it
      -- stays unaffected without any extra check needed.
      -- Real N-way check (2026-08-28): any enemy-side battler protected,
      -- not just the literal battle.enemy object -- same generalization
      -- boss_fight_status.lua's own fix uses.
      if mon and battle:sideOf(mon) == "enemy" and mod.exports.bossFightHas
          and mod.exports.bossFightHas(battle, "type") then
        return false
      end
    end
    return true
  end

  -- The once-per-switch-in gate real Protean/Libero need (national_dex's
  -- own ability data notes this explicitly for both: "Only triggers once
  -- per time this Pokémon enters battle"). Stored in mon.volatile, which
  -- this engine's own Battle:clearVolatile already wipes wholesale on
  -- every switch (mon.volatile = nil) -- the same free reset every other
  -- switch-in-scoped flag in this mod already relies on, not a new
  -- mechanism. Unused until an ability system exists to call it, but built
  -- now so that future work only has to call these two functions, not
  -- invent the tracking.
  function mod.exports.hasUsedTypeChangeThisSwitchIn(battle, mon)
    return battle:volatile(mon).typeChangeUsedThisSwitchIn == true
  end
  function mod.exports.markTypeChangeUsedThisSwitchIn(battle, mon)
    battle:volatile(mon).typeChangeUsedThisSwitchIn = true
  end

  -- The rest of clearVolatile runs unmodified first; this only adds the
  -- type-reset step real PS's own clearVolatile->setSpecies->setType chain
  -- already does as its last step.
  if Battle then
    local nativeClearVolatile = Battle.clearVolatile
    function Battle:clearVolatile(mon)
      nativeClearVolatile(self, mon)
      if mon then mon.types = originalTypesOf(self, mon) end
    end
  end

  mod.log:info("g9-battle-engine: type_override_primitives installed (setMonTypes, reset-on-clearVolatile, once-per-switch-in tracking)")
end
