-- Terastallization's own combat mechanics: everything battle_forms's own
-- src/tera.lua does NOT already give us for free, per explicit user scope
-- (2026-08-20) -- "any and all sub effects and effects are to be handled
-- by battle engine, we are the bible and process of combat," the same
-- ruling that put Protect/Max Guard here (combat/modern_combat_protect.lua).
--
-- WHAT BATTLE_FORMS ALREADY HANDLES, confirmed by direct read of its own
-- src/tera.lua: the menu cell, the once-per-battle registry slot, TERA
-- BLAST's type substitution, and -- the important one -- DEFENSIVE typing
-- for the 18 standard types. `battler.curTypes`/`mon.formTypes = { id }`
-- (src/tera.lua:346-354) already fully replaces every resistance/
-- weakness/immunity with the chosen type's own, for free, through the
-- exact same field this mod's own curTypesOf() already reads for type
-- effectiveness (modern_combat.lua:897-904) -- nothing to add there for a
-- standard type.
--
-- WHAT IT DOES NOT HANDLE, and this file fixes:
--
-- 1. STAB. battle_forms's curTypes override is defensive-only in its own
--    design intent, but curTypesOf() is the SAME list modern_combat.lua's
--    "stab" damage modifier reads for the ATTACKER's own types
--    (modern_combat.lua:143-148) -- so once Terastallized, "stab" silently
--    starts reading ONLY the tera type, losing the original type(s)'
--    STAB entirely. Real Gen 9 keeps both: original types keep their
--    1.5x, and if the Tera Type happens to match one of them, THAT type's
--    STAB rises to 2.0x instead (corroborated against Pokemon Showdown's
--    own mechanic, not invented here) -- e.g. a Water-type Pokemon
--    Terastallizing into Water does not "change nothing" the way
--    battle_forms's own header muses for the defensive side; Water moves
--    go from 1.5x to a real 2.0x. A brand-new Tera Type (not one of the
--    mon's own) gets the ordinary 1.5x, same as any other type match --
--    never stacked with the original types' own 1.5x, since a move only
--    ever has one type. "stab" itself is patched (see modern_combat.lua's
--    own header, which already reserved this exact seam) to defer
--    entirely -- return 1.0 -- whenever this file reports the attacker
--    Terastallized, so this file's own "tera_stab" (priority 110, above
--    "stab"'s 100) is the only STAB source active during Tera and there is
--    no double-counting.
--
-- 2. Stellar's own unique rules, corroborated against Bulbapedia's and
--    Pokemon Showdown's documented Gen 9 behavior:
--    a. Defensively, Stellar is the one Tera Type that does NOT replace
--       typing -- a Stellar-Terastallized Pokemon keeps its ORIGINAL
--       types' resistances/weaknesses/immunities in full, and is
--       ADDITIONALLY always weak to Stellar-type moves specifically, on
--       top of whatever its real types already are or aren't weak to.
--       battle_forms structurally cannot represent this (its own
--       mechanism is "replace with one type," full stop) -- and, per
--       explicit user answer this session, Stellar is not reachable
--       through battle_forms's own menu at all (its TERA_CHOICES list
--       never included it), so this is this mod's own domain end to end.
--    b. Offensively, a Stellar Terastallization boosts every move's own
--       type once each: 2x for the Pokemon's original type(s), 1.2x
--       (4915/4096, the real Showdown fraction, not a rounded 1.2) for
--       every other type including Stellar itself -- tracked per Pokemon
--       per Terastallization, consumed the first time each type is used.
--    c. A Pokemon hacked into Stellar typing without Terastallizing would
--       default to Poison defensively per Bulbapedia -- not implemented:
--       nothing in this engine can set a real, permanent Stellar type
--       outside of this mechanic (no Conversion/Conversion 2 exists here),
--       so the case cannot occur and there is nothing to guard against.
--
-- NOT IMPLEMENTED, both confirmed absent from this codebase entirely
-- (grepped) rather than silently stubbed: Transform/Imposter (no such
-- move/ability exists anywhere in this mod or the base engine) would need
-- to refuse against a Stellar-Terastallized Pokemon; Tera Starstorm
-- (Terapagos's own signature move, Terapagos is not a species this roster
-- includes) would need to hit both foes when Stellar. Both are dead
-- specification until either exists to attach to.
--
-- REACHABILITY, stated plainly: Stellar has no in-game trigger yet. This
-- file builds the full mechanic (defensive override, attack economy, the
-- Tera Blast variant below) against tera_state.lua's own per-mon storage,
-- but nothing here adds a menu cell or other way for a player to actually
-- pick STELLAR and have a real Terastallization happen. That is real,
-- separate, not-yet-requested work -- either battle_forms's own menu
-- cell would need to learn about a type its author never gave it a slot
-- for, or this mod needs its own trigger. The 18 standard types need none
-- of that: they Terastallize today through battle_forms's existing menu,
-- and everything in this file (STAB fix included) already applies to them.
--
-- DETECTION, redesigned (2026-08-20) around a real activation signal
-- instead of inferring one. The previous version detected Terastallization
-- by diffing curTypes/formTypes against the species' own types -- worked
-- for the 18 standard types (their whole mechanism IS that field), but
-- could never see Stellar at all (deliberately touches neither field) and
-- carried a real, if narrow, false-negative gap even for standard types
-- (a monotype mon Terastallizing into its own type is indistinguishable
-- from never having Terastallized, since the live list reads identical
-- either way).
--
-- Signal, confirmed landed in battle_forms v0.75.1 (the exact version the
-- user keeps in src/battle_forms.zip): battle_forms's own formapi emits
-- `mod.battle_forms.tera_applied` (its exported name constant
-- M.TERA_APPLIED, formapi.lua) at the exact point its src/tera.lua
-- activate() commits -- for all three branches (Stellar, Gen 2, Gen 1),
-- from its once-per-battle transformation call site (deps.api.tera(true,
-- { mon = mon, data = battle.data }) -> formapi.tera -> emit). The
-- payload (formapi's payload() helper) carries the REAL mon object --
-- confirmed for Gen 2: src/battlerof.lua's own M.mon() is a pure
-- pass-through, so this is the actual, persistent party-slot table, not
-- a name or a copy -- object identity is what makes this reliable even
-- between two Pokemon sharing a species and a name, which a name-text
-- match never could be -- plus teraType, species, form, isPlayer, and a
-- `tera` field that is truthy exactly when Terastallized. It carries NO
-- `battle` field (formapi's payload is deliberately battle-independent),
-- so this listener keys off `mon` alone. DELIBERATELY not the resolved
-- type: we keep our own per-mon Tera Type (tera_state.lua) as the one
-- source of truth for WHAT type, and only ever take WHETHER-AND-WHO from
-- battle_forms's own signal.
--
-- STATUS: live as of round 7 (2026-09-06). The event fires for every
-- real Terastallization through battle_forms's own menu, and this file's
-- STAB fix / Stellar handling / Tera Blast Stellar variant now activate
-- for real on it -- no longer the accepted-inert placeholder it was when
-- the dev had not yet landed the emit.
return function(mod)
  local isGen2Battle = mod.exports.isGen2Battle
  local changeStage = mod.exports.changeStage
  local registerDamageModifier = mod.exports.registerDamageModifier
  local getTeraType = mod.exports.getTeraType
  assert(isGen2Battle and changeStage and registerDamageModifier,
    "modern_tera: combat/modern_combat.lua must load first")
  assert(getTeraType, "modern_tera: gigantamax/tera_state.lua must load first")

  -- The mon's TRUE, un-overridden species types -- battle.data.pokemon[id]
  -- read directly rather than through Battle:speciesDef(mon), because Gen
  -- 2 forms support (battle_forms's own src/gen2forms.lua) wraps THAT
  -- method to read mon.formTypes when present, which is exactly the field
  -- standard-type Terastallization itself writes -- going through the
  -- wrapped method would hand back the OVERRIDDEN type, not the original
  -- one this file needs to retain STAB for and, for Stellar, to defend
  -- with. Direct table access bypasses any method-level wrap entirely,
  -- whoever installed it.
  local function originalTypesOf(battle, who)
    local id = who and who.species
    local rec = id and battle and battle.data and battle.data.pokemon and battle.data.pokemon[id]
    return (rec and rec.types) or {}
  end
  mod.exports.originalTypesOf = originalTypesOf

  -- Set only by the mod.battle_forms.tera_applied listener below -- never
  -- inferred, never guessed. `who` is always the real mon object (Gen 2
  -- has no battler wrapper, confirmed via curTypesOf's own convention
  -- elsewhere in this mod), the same one the event itself carries, so
  -- this is a plain, direct field read.
  local function activeTeraType(battle, who, gen2)
    if not (who and who.teraActive) then return nil end
    local ok, value = pcall(getTeraType, who, battle)
    return ok and value or nil
  end
  mod.exports.activeTeraType = activeTeraType
  mod.exports.isTerastallized = function(battle, who, gen2)
    return activeTeraType(battle, who, gen2) ~= nil
  end

  -- The one real trigger. See file header -- battle_forms's own formapi
  -- event (M.TERA_APPLIED), confirmed landed in the version we run
  -- against; fires from every activate() branch with a real `mon`.
  mod.events:on("mod.battle_forms.tera_applied", function(ev)
    local mon = ev and ev.mon
    if not mon then return end
    -- battle_forms is loaded (it just emitted), so this is the last chance
    -- to guarantee the dev-option gate is in place if battle_forms somehow
    -- booted after us and no battle.started ran before this activation.
    if mod.exports.ensureBattleFormsGate then mod.exports.ensureBattleFormsGate() end
    mon.teraActive = true
    -- A fresh Terastallization always gets its full Stellar economy back
    -- -- battle_forms's own once-per-battle transformation limit means
    -- this only ever fires once per battle in practice, but clearing here
    -- rather than assuming that stays true costs nothing and can't be
    -- wrong either way.
    mon.teraStellarUsedTypes = nil
  end)

  -- Ends on fainting and with the battle -- confirmed real Tera duration
  -- rule, matching battle_forms's own src/tera.lua header ("survives
  -- switching, where Dynamax ends on one, and it ends on fainting and
  -- with the battle") -- so this deliberately does NOT clear on
  -- battle.battler_switched. `battler` is the mon itself on Gen 2
  -- (confirmed, gen2/Battle.lua:2989's own comment on this exact event).
  mod.events:on("battle.fainted", function(ev)
    local mon = ev and ev.battler
    if not mon then return end
    mon.teraActive = nil
    mon.teraStellarUsedTypes = nil
  end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon then
        mon.teraActive = nil
        mon.teraStellarUsedTypes = nil
      end
    end
  end)

  ------------------------------------------------------------------
  -- OWNERSHIP ENFORCEMENT (round 9, 2026-09-06). Per explicit user
  -- instruction, battle_forms must never decide a Tera type -- it only
  -- reports WHEN one triggers. Two sides to that here:
  --
  -- 1. ensureBattleFormsGate (gigantamax/tera_state.lua) forces battle_forms'
  --    TERA TYPE option to AUTO unconditionally, so its dev choice can never
  --    override our stored types. Re-ensured on every
  --    battle.started and on the tera_applied event because battle_forms is
  --    an optional dependency that may boot before OR after us -- by the
  --    time a battle runs (or an activation event fires) it is certainly
  --    loaded, and the call is idempotent.
  --
  -- 2. ensureTeraStamps pre-stamps every mon that could Terastallize --
  --    getTeraType() -> mon.battleFormsTeraType -- at battle start and on
  --    every switch-in, so battle_forms' own DVs-derived fallback
  --    (src/teratype.lua, reached only when the stamp is absent) is
  --    unreachable: the stamp is always present and always equals OUR type.
  --    Without this, a mon nobody had ever viewed in a stats screen (no
  --    stored value yet, no stamp) would get battle_forms' DVs answer
  --    deployed, which can differ from the type this mod's own getTeraType
  --    would roll for it -- two sources of truth for one mechanic, the
  --    exact incoherence the user reported.
  --
  --    `who` here may be a Gen 1 battler WRAPPER ({ mon = mon, ... },
  --    BattleState.lua's makeBattler) or the mon itself on Gen 2 -- the
  --    wrapper's own `mon` field is the discriminator, the identical check
  --    battle_forms' own src/battlerof.lua uses (a raw Pokemon record never
  --    carries one). Resolved before stamping so the fields land on the
  --    real, persistent mon in both engines.
  local function monOf(battlerOrMon)
    if type(battlerOrMon) ~= "table" then return nil end
    if battlerOrMon.mon ~= nil then return battlerOrMon.mon end
    return battlerOrMon
  end

  local function stampMon(mon, battle)
    if type(mon) ~= "table" or not mon.species then return end
    pcall(getTeraType, mon, battle)
  end

  -- Exported so the boot harness can exercise it directly; also the seam
  -- any other subsystem can reuse to guarantee a fresh roster is stamped.
  -- Roster discovery is pcall-guarded (a battle-scene mod's adjacency
  -- answer is a live query that could throw) and battle.player/enemy are
  -- always added explicitly (deduped) -- they are guaranteed members of
  -- any 1v1, and allActiveBattlers alone can transiently report only one
  -- of them before a scene mod has wrapped the adjacency hook.
  mod.exports.ensureTeraStamps = function(battle)
    if not (battle and battle.player) then return false end
    local roster, seen = {}, {}
    local function add(who)
      local mon = monOf(who)
      if type(mon) ~= "table" or seen[mon] then return end
      seen[mon] = true
      roster[#roster + 1] = mon
    end
    local ok = pcall(function()
      local all = mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or nil
      if type(all) == "table" then for _, w in ipairs(all) do add(w) end end
    end)
    add(battle.player)
    if battle.enemy then add(battle.enemy) end
    for _, mon in ipairs(roster) do stampMon(mon, battle) end
    return true
  end

  mod.events:on("battle.started", function(ev)
    if mod.exports.ensureBattleFormsGate then mod.exports.ensureBattleFormsGate() end
    mod.exports.ensureTeraStamps(ev and ev.battle)
  end)
  mod.events:on("battle.battler_switched", function(ev)
    if mod.exports.ensureBattleFormsGate then mod.exports.ensureBattleFormsGate() end
    stampMon(monOf(ev and ev.battler), ev and ev.battle)
  end)

  ------------------------------------------------------------------
  -- STAB. See file header for the exact rule and why "stab" itself has
  -- to defer -- modern_combat.lua's own body was given that defer check
  -- when this file's seam was reserved; nothing to edit there beyond
  -- that one guard.
  ------------------------------------------------------------------
  registerDamageModifier("tera_stab", 110, function(ctx)
    local teraType = activeTeraType(ctx.battle, ctx.user, ctx.gen2)
    if not teraType then return 1.0 end -- not terastallized: "stab" (100) handles this hit unmodified
    local original = originalTypesOf(ctx.battle, ctx.user)
    local matchesOriginal = false
    for _, t in ipairs(original) do
      if t == ctx.move.type then matchesOriginal = true break end
    end
    local matchesTera = (ctx.move.type == teraType)
    if matchesTera and matchesOriginal then return 2.0 end
    if matchesTera or matchesOriginal then return 1.5 end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- Stellar's own attack economy: 2x each original type once, 1.2x
  -- (4915/4096) every other type once, tracked per mon per
  -- Terastallization. Applies to every move's own type, STAB-eligible or
  -- not (a Stellar-Terastallized Normal move still gets its 1.2x) -- a
  -- separate multiplier from tera_stab above, not a replacement for it.
  ------------------------------------------------------------------
  local STELLAR_OTHER_BOOST = 4915 / 4096

  local function stellarUsageOf(gen2, who)
    local mon = gen2 and who or (who and who.mon) or who
    if not mon then return nil end
    mon.teraStellarUsedTypes = mon.teraStellarUsedTypes or {}
    return mon.teraStellarUsedTypes
  end

  registerDamageModifier("tera_stellar_boost", 105, function(ctx)
    local teraType = activeTeraType(ctx.battle, ctx.user, ctx.gen2)
    if teraType ~= "STELLAR" then return 1.0 end
    local used = stellarUsageOf(ctx.gen2, ctx.user)
    if not used or used[ctx.move.type] then return 1.0 end
    used[ctx.move.type] = true
    local original = originalTypesOf(ctx.battle, ctx.user)
    for _, t in ipairs(original) do
      if t == ctx.move.type then return 2.0 end
    end
    return STELLAR_OTHER_BOOST
  end)

  ------------------------------------------------------------------
  -- Stellar defensive override + always-weak-to-Stellar. Both hooked
  -- through modern_combat.lua's own small, explicit call-through (its own
  -- header comment already names this exact seam) so the actual type-
  -- effectiveness computation stays in one place -- this file only ever
  -- supplies the two answers, never duplicates the formula.
  ------------------------------------------------------------------
  mod.exports.defensiveTypesOf = function(battle, who, gen2, liveTypes)
    local teraType = activeTeraType(battle, who, gen2)
    if teraType ~= "STELLAR" then return liveTypes end
    return originalTypesOf(battle, who)
  end

  mod.exports.stellarWeaknessMultiplier = function(battle, who, gen2, moveType)
    if moveType ~= "STELLAR" then return 1.0 end
    if activeTeraType(battle, who, gen2) ~= "STELLAR" then return 1.0 end
    return 2.0
  end

  ------------------------------------------------------------------
  -- Tera Blast's own Stellar variant: registered here rather than by
  -- battle_forms (its own data/terablast.lua never lists STELLAR among
  -- the 18 types it builds a variant for, confirmed by reading it
  -- directly) -- the id follows its exact naming convention
  -- (BATTLE_FORMS_TERA_BLAST_ + type) purely so it slots into the same
  -- substitution family if/when Stellar reachability is wired up; this
  -- mod does not consume battle_forms's own substitution machinery
  -- itself. 100 power (Bulbapedia's confirmed Gen 9 value for the
  -- Stellar variant, vs. the ordinary 80), Special, unchanged accuracy/PP
  -- -- and the self stat-drop side effect, applied once per use via
  -- battle.damage_dealt (the same hook modern_hazards.lua's Rapid Spin
  -- clear already keys off a specific move id through).
  ------------------------------------------------------------------
  -- STELLAR itself has to exist as a type_chart IDENTITY record (name +
  -- category only) before any move can declare `type = "STELLAR"` --
  -- moves:register validates `type` against f.id("type_chart")
  -- (src/mods/Schemas.lua:829). Deliberately registers NO matchup rows
  -- alongside it -- TypeChart.effectiveness/.rows only ever consult rows,
  -- never the identity record, so this alone is what keeps Stellar
  -- resistance/weakness/immunity-free everywhere in the engine, not a
  -- separate mechanism. Real games categorize both Stellar-type moves
  -- (Tera Blast, Tera Starstorm) as Special.
  do
    local ok, err = pcall(function()
      mod.content.type_chart:register("STELLAR", { name = "STELLAR", category = "special" })
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_tera: STELLAR type_chart identity registration skipped (%s)",
        tostring(err))
    end
  end

  local TERA_BLAST_STELLAR_ID = "BATTLE_FORMS_TERA_BLAST_STELLAR"
  do
    local ok, err = pcall(function()
      mod.content.moves:register(TERA_BLAST_STELLAR_ID, {
        id = TERA_BLAST_STELLAR_ID,
        name = "TERA BLAST",
        type = "STELLAR",
        power = 100,
        category = "special",
        accuracy = 100,
        pp = 5,
        effect = "NO_ADDITIONAL_EFFECT",
      })
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: modern_tera: %s registration skipped (%s)",
        TERA_BLAST_STELLAR_ID, tostring(err))
    end
  end

  mod.events:on("battle.damage_dealt", function(ev)
    if not (ev and ev.moveId == TERA_BLAST_STELLAR_ID and ev.user and ev.battle) then return end
    local gen2 = isGen2Battle(ev.battle)
    changeStage(ev.battle, ev.user, "attack", -1, false, gen2)
    changeStage(ev.battle, ev.user, "spa", -1, false, gen2)
  end)

  mod.log:info("galar_gmax_dex: modern_tera loaded (STAB fix, Stellar defense/economy, Tera Blast Stellar)")
end
