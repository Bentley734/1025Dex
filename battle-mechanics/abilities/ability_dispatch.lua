-- The ability-execution primitive: this mod's first real integration of
-- national_dex's ability DATA (dex.exports.abilityById, 0.30.0+) into
-- actual battle behavior. Nothing before this session executed an ability
-- anywhere in this engine -- confirmed directly (a dedicated research pass
-- grepped the whole base engine and every installed mod): mon.ability
-- exists only as save/display data (stats/engine_modern_stats.lua's own
-- generation/toggle functions, the SummaryMenu page-3 readout), never read
-- by combat logic.
--
-- We do not register abilities -- national_dex already owns the species-
-- ability associations (statsBySpecies(id).abilities) and the ability
-- behavior text (abilityById(id)) -- we only WIRE what's already there
-- into the primitives this mod already has (changeStage, setMonTypes,
-- etc.), the exact same "patch, never register" discipline this mod's own
-- SUBEFFECTS.md already states for moves.
--
-- MODULARITY, explicit user directive: data and engine stay entirely
-- separate for the whole ability system, this file included. abilities/
-- data/*.lua files are pure tables (no logic, no mod.exports -- loaded via
-- loadSibling the same way combat/moves_new.lua's own plain data table
-- already is) keyed by ability id; abilities/engine/*.lua files are pure
-- dispatch logic, each reading exactly one data file and calling exactly
-- one existing primitive. This file is the one exception living outside
-- that split -- it IS the primitive every engine file depends on
-- (abilityIdOf/abilityBehaviorOf), not a per-ability dispatcher itself.
--
-- ROUND 186 -- battle-scoped ability snapshot. Every ability-changing move
-- and ability in this mod writes through setAbility (below), which is
-- combat-only. The pre-round-186 restore captured a mon's own ability
-- lazily the FIRST time that mon was changed and put it back on switch-out
-- and battle end -- but battle end only covered the two ACTIVE battlers, so
-- a benched mon that had been changed and then withdrawn before the fight
-- ended could keep the changed ability into the save. This round gives the
-- ability slot the same explicit battle-scoped lifecycle round 184 gave raw
-- stats: at battle.started (priority 1000 -- ahead of every switch-in
-- ability and ahead of Gen 2's own ability generation at priority 0) EVERY
-- party member with a real ability, on both sides, is snapshotted, and the
-- snapshot is returned on switch-out (the outgoing AND the incoming mon),
-- on faint, and on battle end (the whole roster). Lazy capture inside
-- setAbility still covers a mon whose ability is generated or first changed
-- after the sweep (Gen 2 player abilities in particular, which
-- gen2_modern_stats.lua only generates at battle.started priority 0).
return function(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.abilityById,
    "ability_dispatch: national_dex (with abilityById) must be installed")

  -- Neutralizing Gas (Phase 8, other bucket): a real, global "no other
  -- Pokémon's ability functions while this one is active" field effect.
  -- Built HERE, directly inside abilityIdOf's own real definition --
  -- this file's own header already declares itself the one exception
  -- living outside the data/engine split, the single real choke point
  -- every ability check in this whole mod goes through. A wrap
  -- installed by a LATER-loading engine file was tried and rejected:
  -- every existing engine file captures `local abilityIdOf =
  -- mod.exports.abilityIdOf` ONCE, at its own install time -- a later
  -- reassignment of mod.exports.abilityIdOf would never reach any of
  -- those already-captured locals, a confirmed dead end for a
  -- suppression effect that has to be globally visible.
  --
  -- Self-contained by necessity: this function must keep working
  -- correctly from the moment it's first exported, long before
  -- move_targeting.lua's own allActiveBattlers exists -- so the field-
  -- wide holder scan below is a lazy mod.exports lookup, and "which
  -- battle is this" is tracked locally via battle.started/battle.ended
  -- rather than threaded in as a parameter (abilityIdOf's own real
  -- signature, called from dozens of sites across this mod, is
  -- mon-only -- adding a battle parameter would mean touching every one
  -- of those call sites instead of the one real source).
  --
  -- Real, confirmed exemptions checked here: the holder's own
  -- Neutralizing Gas is always active for itself; Comatose and Disguise
  -- (both real, built abilities in this mod) are real Showdown
  -- exemptions too. Every OTHER real exemption (Multitype, Stance
  -- Change, Schooling, Shields Down, RKS System, Battle Bond, Power
  -- Construct, Ice Face, Zen Mode, As One, Gulp Missile) is a form-
  -- changing or single-species ability this mod doesn't build at all
  -- (battle_forms' own standing scope) -- moot here, not omitted.
  local NGAS_EXEMPT = { NEUTRALIZINGGAS = true, COMATOSE = true, DISGUISE = true }
  local ngasBattle = nil
  mod.events:on("battle.started", function(ev) ngasBattle = ev and ev.battle end)
  mod.events:on("battle.ended", function(ev)
    if ev and ev.battle == ngasBattle then ngasBattle = nil end
  end)
  local function rawAbilityId(name)
    if type(name) ~= "string" then return nil end
    local id = name:upper():gsub("[^%w]", "")
    return id ~= "" and id or nil
  end
  local function neutralizingGasActive()
    if not ngasBattle then return false end
    local allActiveBattlers = mod.exports.allActiveBattlers
    if not allActiveBattlers then return false end
    for _, other in ipairs(allActiveBattlers(ngasBattle) or {}) do
      if other and (other.hp or 0) > 0 and rawAbilityId(other.ability) == "NEUTRALIZINGGAS" then
        return true
      end
    end
    return false
  end

  -- Ignore-ability (Phase 18, missing-effects plan): Showdown's real
  -- `move.ignoreAbility` family (Moongeist Beam / Sunsteel Strike, both
  -- `ignoreAbility: true` -- moves.ts:12229 / :18432). Unlike Mold
  -- Breaker (a persistent ATTACKER-side family the ability sites have to
  -- consult individually, see modern_combat.lua's own
  -- attackerIgnoresDefenderAbility) this is a single-move, single-target
  -- suppression the move's own damage computation must completely blind
  -- every ability read to. That has to happen inside abilityIdOf --
  -- the one real choke point every ability check in this mod funnels
  -- through -- for the same reason Neutralizing Gas lives here: every
  -- engine file captures `local abilityIdOf = mod.exports.abilityIdOf`
  -- ONCE at its own install time, so a later reassignment would never
  -- reach those captured locals. A single module-local `ignoredAbilityMon`
  -- set by combat/modern_guard_contact.lua's own battle.damage wrap for
  -- the duration of one damage computation (and cleared immediately
  -- after, error or not) is the only mechanism that reaches a
  -- computeModernDamage call stack that already holds an
  -- abilityIdOf reference from install time. Checked AFTER the
  -- raw-id lookup (so a mon with no ability still returns nil, and the
  -- suppression never invents an id) and deliberately OUTSIDE the
  -- Neutralizing Gas exemption list -- ignoring an ability is the entire
  -- point of this move family, so even an NGAS-exempt form ability is
  -- suppressed while the flag is held.
  local ignoredAbilityMon = nil
  function mod.exports.setIgnoredAbilityMon(mon)
    ignoredAbilityMon = mon
  end

  -- mon.ability stores a display name ("Intimidate", "As One (Glastrier)");
  -- national_dex's own ids strip everything but letters/digits and
  -- uppercase (confirmed directly against real records: "As One
  -- (Glastrier)" -> ASONEGLASTRIER, "Dauntless Shield" -> DAUNTLESSSHIELD).
  local function abilityIdOf(mon)
    mon=mon and (mon.mon or mon)
    local id = rawAbilityId(mon and mon.ability)
    if not id then return nil end
    if mon ~= nil and mon == ignoredAbilityMon then return nil end
    if not NGAS_EXEMPT[id] and neutralizingGasActive() then return nil end
    return id
  end
  mod.exports.abilityIdOf = abilityIdOf

  -- The real national_dex behavior record for mon's current ability, or
  -- nil (no ability set, or national_dex has no record for it). A COPY,
  -- like every other national_dex reply -- callers may read but should
  -- never assume mutating it does anything.
  function mod.exports.abilityBehaviorOf(mon)
    local id = abilityIdOf(mon)
    if not id then return nil end
    return nationalDex.exports.abilityById(id)
  end

  ------------------------------------------------------------------
  -- Raw mon behind a Gen 1 battler wrapper (or the mon itself on Gen 2, or
  -- a raw mon handed in directly). Every real ability read/write in this mod
  -- lands on the RAW party mon -- stats/engine_modern_stats.lua writes
  -- `mon.ability`, and a Gen 1 battler is a throwaway wrapper
  -- (BattleState.lua's makeBattler never copies .ability; confirmed
  -- directly) -- so unwrapping is required or a change would land on a
  -- table that is discarded at switch-out. combat/modern_party_support.lua's
  -- own g9RawMon is the shared version; this local one is identical and
  -- exists because ability_dispatch installs before that file (lazy
  -- mod.exports lookups are used everywhere else in this file for the same
  -- reason, but this helper is needed by setAbility itself, which must work
  -- from install time).
  ------------------------------------------------------------------
  local function rawMon(who)
    return (who and (who.mon or who)) or nil
  end
  mod.exports.rawAbilityMon = rawMon

  ------------------------------------------------------------------
  -- setAbility: the real "no mechanism exists to change a mon's own
  -- ability" gap this whole ability system's own standing TODO named
  -- (Skill Swap/Worry Seed/Entrainment/Gastro Acid as moves; Trace/Mummy/
  -- Wandering Spirit/Receiver/Power of Alchemy as abilities) -- closed
  -- directly rather than re-deferred: abilityIdOf/abilityBehaviorOf both
  -- already re-derive from `mon.ability` LIVE, on every call, and
  -- stats/engine_modern_stats.lua's own real Ability Capsule-equivalent
  -- (ModernStats.toggleHiddenAbility/toggleRegularAbility) already proves
  -- writing a real national_dex display name straight into `mon.ability`
  -- is exactly how this engine expects an ability change to be made --
  -- there was never a missing primitive, only a missing generic entry
  -- point covering an ARBITRARY new ability id (not just the two a
  -- species already knows), which is all this adds.
  --
  -- COMBAT-ONLY STATE, explicit user instruction: every real use of this
  -- (moves and abilities alike) is a battle effect, never a permanent
  -- change. Round 186 made this an explicit battle-scoped snapshot (see
  -- the file header): the mon's own pre-battle ability is recorded in
  -- `mon.__g9AbilityBaseline` -- along with `__g9AbilityBaselineSet`, a
  -- separate boolean guard so a mon with genuinely NO natural ability
  -- restores correctly to "no ability" instead of reading as never
  -- captured, and `__g9AbilityBaselineBattle`, a plain NUMBER (round 276;
  -- it used to hold the battle object itself) which scopes the snapshot to
  -- ONE battle so a stale baseline from an abandoned fight is refreshed by
  -- the next battle.started sweep. It is captured up front for the whole
  -- party and lazily here for any mon the sweep could not cover (no
  -- ability yet at battle start), then returned on switch-out, faint, and
  -- battle end.
  --
  -- BOSS IMMUNITY, explicit user instruction: gated on the SAME
  -- `bossFightHas(battle, "ability")` flag combat/boss_fight.lua already
  -- reserved and documented as "NOT YET ENFORCED ANYWHERE... there is
  -- nothing in this codebase today that would try to change a boss's
  -- ability" -- that flag already existed for exactly this, so this is
  -- wiring the existing reserved gate, not adding a new one. Checked on the
  -- ORIGINAL `who` (before unwrapping) so battle:sideOf still sees the
  -- battler the engine handed in; it is Gen-2-only by construction anyway
  -- (Gen 1's sideOf never compares equal to "enemy").
  -- A battle identity that is safe to serialize: a weak-keyed map hands
  -- every battle a monotonically-assigned number, so the scope marker left
  -- on the mon is a number rather than the battle object. This is the SAME
  -- scheme combat/move_usability.lua already uses for its own scope marker
  -- (see its __g9UsabilityBattle comment): on Gen 2 battle.party IS
  -- save.party, and the battle holds mon-keyed maps (turn_order's
  -- battle.__g9ChosenMoves), so a battle reference on a party mon closes a
  -- cycle the save writer cannot walk -- it has no cycle detection on the
  -- write side and dies with a "stack overflow". nil (a setAbility call
  -- with no battle at hand) gets the fixed id 0, which is exactly its
  -- meaning: no battle scope. A mon still carrying a table here from an
  -- older build reads as a different id and is simply re-captured, so the
  -- change is self-healing.
  local battleIds = setmetatable({}, { __mode = "k" })
  local lastBattleId = 0
  local function battleIdOf(battle)
    if battle == nil then return 0 end
    local id = battleIds[battle]
    if not id then
      lastBattleId = lastBattleId + 1
      id = lastBattleId
      battleIds[battle] = id
    end
    return id
  end

  local function captureAbilityBaseline(mon, battle)
    if type(mon) ~= "table" then return false end
    local id = battleIdOf(battle)
    if mon.__g9AbilityBaselineSet and mon.__g9AbilityBaselineBattle == id then
      return false
    end
    mon.__g9AbilityBaseline = mon.ability
    mon.__g9AbilityBaselineSet = true
    mon.__g9AbilityBaselineBattle = id
    return true
  end
  mod.exports.captureAbilityBaseline = captureAbilityBaseline

  -- Put the mon's own ability back and drop the battle-scoped state. Safe to
  -- call on anything (battler wrapper or raw mon); a no-op returning false
  -- for a mon that carries no baseline.
  local function restoreNaturalAbility(who)
    local mon = rawMon(who)
    if type(mon) ~= "table" or not mon.__g9AbilityBaselineSet then return false end
    mon.ability = mon.__g9AbilityBaseline
    mon.__g9AbilityBaseline = nil
    mon.__g9AbilityBaselineSet = nil
    mon.__g9AbilityBaselineBattle = nil
    return true
  end
  mod.exports.restoreNaturalAbility = restoreNaturalAbility

  mod.exports.setAbility = function(battle, who, newId)
    if not who then return false end
    -- Real N-way check (2026-08-28): any enemy-side battler protected,
    -- not just the literal battle.enemy object -- same generalization
    -- combat/boss_fight_status.lua's own fix uses.
    if battle and mod.exports.bossFightHas and mod.exports.bossFightHas(battle, "ability")
        and battle:sideOf(who) == "enemy" then
      return false
    end
    local mon = rawMon(who)
    if type(mon) ~= "table" then return false end
    captureAbilityBaseline(mon, battle)
    if newId == nil then
      mon.ability = nil -- Gastro Acid-style suppression: the ability slot goes inert, not swapped
      return nil
    end
    local record = nationalDex.exports.abilityById(newId)
    if not (record and type(record.name) == "string" and record.name ~= "") then return false end
    mon.ability = record.name
    return newId
  end

  ------------------------------------------------------------------
  -- On-demand switch-in ability trigger (round 338).
  --
  -- Every switch-in ability engine in this mod (Intimidate's stat drops and
  -- the weather/terrain/primal setters, Trace, Download, Forewarn, Frisk,
  -- Hospitality, RKS System, Commander, Multitype, ...) already subscribes
  -- to battle.started + battle.battler_switched and applies its effect for
  -- ONE mon from a local `apply...` function. Transform/Imposter needs the
  -- EXACT same effect for the generic case (a real switch-in trigger like
  -- Intimidate must fire once when the ability is copied), but it must NOT
  -- drag in the whole battler_switched surface (entry hazards, weather
  -- re-application, Ability-slot restores...), which is why re-emitting that
  -- event is wrong.
  --
  -- Instead each engine registers its own per-mon apply function here, once,
  -- at install time; fireSwitchInAbility re-runs them for a single mon. The
  -- order is registration order (the same boot order the real switch-in
  -- sweep uses), and every call is pcall-guarded so one misbehaving family
  -- can never break the transform that triggered it.
  ------------------------------------------------------------------
  local switchInTriggers = {}
  function mod.exports.registerSwitchInAbility(fn)
    if type(fn) == "function" then switchInTriggers[#switchInTriggers + 1] = fn end
    return fn
  end

  -- Runs every registered switch-in family for one mon. `who` may be a
  -- battler wrapper or a raw mon; the engines (and the battle scene's own
  -- g9.request_adjacency seam, which resolves the caster by `battler.mon ==
  -- caster`) are written for the RAW mon, exactly as Gen 2 and the scene
  -- already hand them -- so the wrapper is unwrapped here.
  function mod.exports.fireSwitchInAbility(battle, who)
    if not battle or not who then return 0 end
    local mon = rawMon(who) or who
    if type(mon) ~= "table" then return 0 end
    local ran = 0
    for i = 1, #switchInTriggers do
      local ok, err = pcall(switchInTriggers[i], battle, mon)
      if ok then
        ran = ran + 1
      else
        mod.log:warn("g9-battle-engine: switch-in ability trigger %d failed: %s",
          i, tostring(err))
      end
    end
    return ran
  end

  ------------------------------------------------------------------
  -- Battle-boundary sweeps (round 186). Each battle mon is visited once,
  -- deduped by raw mon, across the active battlers, the scene's own
  -- battlersByMon cache, and every party list either generation exposes
  -- (Gen 2 battle.party IS save.party; Gen 1's real save party is
  -- battle.game.save.party, alongside the scoped battle.playerParty).
  ------------------------------------------------------------------
  local function eachBattleMon(battle, fn)
    if type(battle) ~= "table" then return end
    local seen = {}
    local function visit(who)
      local mon = rawMon(who)
      if type(mon) == "table" and not seen[mon] then
        seen[mon] = true
        fn(mon)
      end
    end
    visit(battle.player)
    visit(battle.enemy)
    local allActiveBattlers = mod.exports.allActiveBattlers
    if allActiveBattlers then
      local actives = allActiveBattlers(battle)
      for i = 1, #(actives or {}) do visit(actives[i]) end
    end
    local byMon = battle.battlersByMon
    if type(byMon) == "table" then
      for _, b in pairs(byMon) do visit(b) end
    end
    local parties = { battle.party, battle.playerParty, battle.enemyParty }
    local game = battle.game
    local saveParty = game and game.save and game.save.party
    if type(saveParty) == "table" then parties[#parties + 1] = saveParty end
    for p = 1, #parties do
      local party = parties[p]
      if type(party) == "table" then
        for i = 1, #party do visit(party[i]) end
      end
    end
  end

  -- Only a mon that ALREADY has an ability is snapshotted at battle start:
  -- Gen 2 player abilities are generated later (gen2_modern_stats.lua's own
  -- battle.started handler at the default priority), and snapshotting a nil
  -- there would make the restore blank out an ability generated afterwards.
  -- A nil-ability mon is captured lazily by setAbility instead, the first
  -- time anything actually changes it. Returns how many were recorded.
  local function snapshotAbilities(battle)
    if type(battle) ~= "table" then return 0 end
    local captured = 0
    eachBattleMon(battle, function(mon)
      if mon.ability ~= nil and captureAbilityBaseline(mon, battle) then
        captured = captured + 1
      end
    end)
    return captured
  end
  mod.exports.snapshotAbilities = snapshotAbilities

  -- battle.started at priority 1000: ahead of every switch-in ability handler
  -- (default priority 0) and ahead of Gen 2's own ability generation, so a
  -- leading Trace etc. has its true natural ability recorded before anything
  -- writes to the slot -- the same early slot modern_held_item_api's own
  -- item snapshot uses.
  mod.events:on("battle.started", function(ev)
    if ev and ev.battle then snapshotAbilities(ev.battle) end
  end, 1000)

  -- Priority 10: ahead of the default-priority switch-in ability handlers
  -- (abilities/engine/ability_copy.lua's Trace in particular), so the
  -- incoming mon is back to its natural ability BEFORE that ability's own
  -- switch-in effect runs. Events.lua sorts descending but is NOT stable, so
  -- this has to be a real priority, not a registration-order accident.
  mod.events:on("battle.battler_switched", function(ev)
    if not ev then return end
    restoreNaturalAbility(ev.previous)
    restoreNaturalAbility(ev.battler)
  end, 10)

  -- Faint restores LAST (-1000): the ability a mon had at the moment it
  -- fainted is what a default-priority faint handler should observe (e.g. an
  -- adjacent Receiver copying it), so those all run before the slot is
  -- handed back.
  mod.events:on("battle.fainted", function(ev)
    if ev then
      restoreNaturalAbility(ev.battler or ev.mon or ev.target or ev.pokemon)
    end
  end, -1000)

  -- Battle end restores the WHOLE roster on both sides, not just the two
  -- active battlers (the pre-round-186 gap). -1000 is the same last-listener
  -- slot modern_held_item_api's own item restore uses.
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local restored = 0
    eachBattleMon(battle, function(mon)
      if restoreNaturalAbility(mon) then restored = restored + 1 end
    end)
    if restored > 0 then
      mod.log:info("g9-battle-engine: ability_dispatch restored %d "
        .. "battle-scoped ability slot(s)", restored)
    end
  end, -1000)

  mod.log:info("g9-battle-engine: ability_dispatch installed (abilityIdOf, abilityBehaviorOf, setAbility, boss-immune + battle-scoped party snapshot/restore)")
end
