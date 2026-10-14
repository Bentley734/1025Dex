-- Dispatch engine for abilities/data/stat_change_switchin.lua -- that file
-- is only an inclusion list; scope/stat/stages are read LIVE from
-- national_dex's own abilityBehaviorOf here, at dispatch time, every time.
-- Nothing about the effect itself is duplicated into this mod's own data -- only
-- two things that genuinely aren't in national_dex's data at all:
--
-- 1. STAT_KEY: PokeAPI's own stat-name spelling (national_dex's behaviour.
--    effects[].stat, e.g. "special-attack") mapped to this engine's own
--    key convention (modern_combat.lua's changeStage store uses "spa",
--    confirmed against every other stat-changing MOVE in combat/
--    modern_movepool_stages.lua) -- a naming-convention adapter, not game
--    data.
-- 2. NATIVE_STATS: which of those keys route through Gen 2's own native
--    stage table (Battle:changeStageAgainstMist) instead of modern_combat
--    .lua's atk/def/spa/spd store -- that file's own header: speed/
--    accuracy/evasion were never held there at all. A pure function of
--    WHICH STAT is involved, so this is derived here rather than stored
--    per-ability anywhere.
--
-- Reuses combat/modern_combat.lua's own changeStage export (the same
-- primitive every stat-changing MOVE already goes through) and Gen 2's own
-- native Battle:changeStageAgainstMist directly for the three
-- native-store stats.
--
-- SUBSTITUTE, confirmed by direct source read after the user pasted
-- Intimidate's own real national_dex record ("This ability has no effect
-- on an opponent that has a Substitute"): modern_combat.lua's changeStage
-- already gates a hostile (fromEnemy) change on the target's Substitute
-- via isProtectedFrom, so INTIMIDATE/INTREPIDSWORD/DAUNTLESSSHIELD (all
-- non-native stats) already respect it correctly for free. Battle:
-- changeStageAgainstMist does NOT -- read directly, gen2/Battle.lua:2071-
-- 2079: it checks ONLY Mist, and the Battle:changeStage it delegates to
-- (gen2/Battle.lua:1299-1313) has no Substitute check anywhere in the
-- chain. Real, confirmed gap for the native-store stats (SUPERSWEETSYRUP's
-- own evasion drop) -- fixed explicitly below (a plain battle:volatile(
-- target).substitute read, the same field isProtectedFrom itself checks)
-- rather than trusted to the native call. A wider pre-existing gap in
-- combat/modern_movepool_stages.lua's own changeNativeStage (any MOVE
-- routing a hostile speed/accuracy/evasion change that way, e.g. Scary
-- Face/Cotton Spore/Sweet Scent) is flagged here but deliberately not
-- touched -- that file is a separate, earlier piece of work outside this
-- task's scope.
--
-- Triggers: battle.started (the very first send-out at battle start --
-- confirmed by direct read, gen2/Battle.lua:340, a SEPARATE event from any
-- switch) and battle.battler_switched (every switch after that). Both are
-- needed -- Intimidate firing only on MID-battle switches and never on the
-- lead Pokemon would be a real, observable bug. Every other switch_in
-- ability engine file in this directory reuses this exact same two-event
-- pattern.
--
-- Third argument (igData, optional): the inclusion table from abilities/data/
-- intimidate_guard.lua, passed through main.lua's boot call. It holds the
-- target-side guard family that exists ONLY in the presence of Intimidate
-- (OBLIVIOUS, GUARDDOG, RATTLED) plus OBLIVIOUS's own entry-cure, none of
-- which belong in this file's stat-change inclusion table. If omitted (an
-- older boot line), every igData check below reads empty and the plain
-- Intimidate path is preserved -- the file degrades safely.
return function(mod, data, igData)
  igData = igData or {}
  local changeStage = mod.exports.changeStage
  local bossStatsDropBlocked = mod.exports.bossStatsDropBlocked
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local requestAdjacency = mod.exports.requestAdjacency
  local isGen2Battle = mod.exports.isGen2Battle
  assert(changeStage and bossStatsDropBlocked and abilityIdOf and abilityBehaviorOf
      and requestAdjacency and isGen2Battle,
    "switchin_stat_change: modern_combat.lua and move_targeting.lua must load first")

  local STAT_KEY = {
    attack = "attack", defense = "defense",
    ["special-attack"] = "spa", ["special-defense"] = "spd",
    speed = "speed", accuracy = "accuracy", evasion = "evasion",
  }
  local NATIVE_STATS = { speed = true, accuracy = true, evasion = true }

  -- Applies one already-resolved (mon, target, stat, stages) change --
  -- the per-target body every foes-scope target in the loop below and
  -- the single self-target case both reduce to.
  -- Mirror Armor (Phase 8, other bucket): records this hostile switch-
  -- in trigger (Intimidate/Intrepid Sword/Dauntless Shield -- the ONLY
  -- real hostile-scope members of this whole file) into the shared
  -- interaction memory (combat/interaction_memory.lua) BEFORE the
  -- actual stage change runs, so a Mirror Armor holder's own
  -- changeStage check (modern_combat.lua) can find "who did this to me
  -- most recently" and redirect the drop back onto them.
  local recordInteraction = mod.exports.recordInteraction

  local function applyToOneTarget(battle, mon, target, stat, effect, fromEnemy)
    if not target or (target.hp or 0) <= 0 then return end
    local gen2 = isGen2Battle(battle)
    target=mod.exports.liveBattler(battle,target)
    if fromEnemy and recordInteraction then
      recordInteraction(battle, mon, target, "ability", abilityIdOf(mon))
    end
    -- changeStageAgainstMist has no Substitute check of its own (see this
    -- file's own header) -- applied here so a hostile native-store change
    -- respects it exactly like changeStage already does for the others.
    -- Never gates a self-targeted change: Substitute never blocks a mon
    -- buffing itself. Generation-aware field shapes, same split
    -- modern_combat.lua's own isProtectedFrom uses (Gen 1 keeps the flag
    -- on the battler wrapper, Gen 2 in Battle:volatile).
    if fromEnemy then
      local substituted
      if isGen2Battle(battle) then
        substituted = (battle:volatile(target).substitute or 0) > 0
      else
        substituted = (target.substituteHP or 0) > 0
      end
      if substituted then return end
    end
    -- Boss-fight "statsDrop" protection: checked here too, ahead of the
    -- native call -- see modern_combat.lua's own bossStatsDropBlocked
    -- header and this file's own header for why the native-store branch
    -- needs its own explicit gate rather than trusting the native call.
    if bossStatsDropBlocked(battle, target, effect.stages) then return end
    if NATIVE_STATS[stat] then
      battle:changeStageAgainstMist(mon, target, stat, effect.stages)
    else
      changeStage(battle, target, stat, effect.stages, fromEnemy, gen2)
    end
  end

  local function applySwitchInAbility(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0) then return end
    local gen2 = isGen2Battle(battle)
    local id = abilityIdOf(mon)
    -- OBLIVIOUS lives in abilities/data/intimidate_guard.lua (the
    -- intimidate-guard family), not in this file's own inclusion table, so
    -- it must clear the igData gate rather than the data gate below. On
    -- entry it cures its host of attraction and taunt -- Showdown's
    -- onSwitchIn for Oblivious ("This Pokémon cannot be infatuated or
    -- taunted"), and the Gen 1 port keeps the same Gen 3+ behaviour.
    if igData.OBLIVIOUS and id == "OBLIVIOUS" then
      if gen2 then
        battle:volatile(mon).attract = nil
        battle:volatile(mon).tauntTurns = nil
      else
        mon.attract = nil
        mon.tauntTurns = nil
      end
      return
    end
    if not (id and data[id]) then return end
    local record = abilityBehaviorOf(mon)
    local behavior = record and record.behaviour
    local effect = behavior and behavior.effects and behavior.effects[1]
    if not (effect and effect.kind == "stat_change" and effect.stat and effect.stages) then return end
    local stat = STAT_KEY[effect.stat]
    if not stat then return end
    local fromEnemy = behavior.scope == "foes"

    if not fromEnemy then
      applyToOneTarget(battle, mon, mon, stat, effect, false)
      return
    end

    -- Real Intimidate/Intrepid Sword/Dauntless Shield rule: every
    -- ADJACENT opponent, not "the" opponent -- a hard-binary opponentOf
    -- lookup was exactly the class of gap MULTI_BATTLE_HOOKS.md's own
    -- sideOf section warns about (correct only for today's 2-battler
    -- case, silently wrong the moment a real multi-battler format
    -- exists). Reuses the SAME "g9.request_adjacency" hook a spread MOVE
    -- uses -- moveId is nil here since nothing about the trigger is a
    -- move-use, and a wrapped handler never inspects it anyway. Falls
    -- through to move_targeting.lua's own native-fallback adjacency (the
    -- other of battle.player/battle.enemy) when no battle-scene mod has
    -- wrapped the hook, so this is exactly equivalent to the old
    -- opponentOf lookup for every format this engine runs today.
    local adjacency = requestAdjacency(battle, mon, nil)
    for _, target in ipairs(adjacency.enemies) do
      -- Intimidate's target-side guard family (abilities/data/
      -- intimidate_guard.lua). Only INTIMIDATE interacts with these
      -- three; Intrepid Sword/Dauntless Shield/Supersweet Syrup are
      -- unopposed self/first-target changes and keep the plain path.
      if id == "INTIMIDATE" then
        local tid = target and abilityIdOf(target)
        if igData.OBLIVIOUS and tid == "OBLIVIOUS" then
          -- immune to the drop, and no secondary effect at all
        elseif igData.GUARDDOG and tid == "GUARDDOG" then
          -- drop negated; the guard dog's Attack rises instead
          for _, line in ipairs(changeStage(battle, target, "attack", 1, false, gen2) or {}) do
            battle:emit({ kind = "message", text = line })
          end
        elseif igData.RATTLED and tid == "RATTLED" then
          -- drop lands, then Rattled's own Speed rises one stage (that
          -- store is Gen-native, so straight to the real native write --
          -- the same generation split hit_taken.lua's raiseSpeed uses)
          applyToOneTarget(battle, mon, target, stat, effect, true)
          if gen2 then
            battle:changeStageAgainstMist(target, target, "speed", 1)
          else
            target.stages = target.stages or {}
            target.stages.speed = math.max(-6, math.min(6, (target.stages.speed or 0) + 1))
          end
        else
          applyToOneTarget(battle, mon, target, stat, effect, true)
        end
      else
        applyToOneTarget(battle, mon, target, stat, effect, true)
      end
    end
  end

  -- Round 338: let Transform/Imposter re-run exactly this per-mon effect for
  -- the ability it just copied (see ability_dispatch's own registry header).
  mod.exports.registerSwitchInAbility(applySwitchInAbility)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    -- Speed order across the REAL, N-way roster, not a fixed player-then-
    -- enemy pair -- see combat/turn_order.lua's own orderActiveBattlers
    -- header for the full rule (real simultaneous switch-in resolution
    -- is fastest-first across however many battlers entered together,
    -- and since each of these overwrites shared state, the slowest
    -- mon's own trigger is what persists on a mismatch -- Intimidate/
    -- Intrepid Sword/Dauntless Shield/Supersweet Syrup don't overwrite
    -- each other's stat targets the way weather/terrain do, so this
    -- mostly matters for a future same-tier collision, but the ordering
    -- itself should still be correct rather than fixed). Both exports
    -- read lazily (not hoisted to a local at install time): this file
    -- loads before combat/turn_order.lua and combat/move_targeting.lua
    -- in main.lua's own sequence, but this closure only runs later,
    -- during a real battle, by which point every mod has finished
    -- loading.
    local allActiveBattlers = mod.exports.allActiveBattlers
    local orderActiveBattlers = mod.exports.orderActiveBattlers
    local roster = allActiveBattlers and allActiveBattlers(battle) or { battle.player, battle.enemy }
    local ordered = orderActiveBattlers and orderActiveBattlers(battle, roster) or roster
    for _, mon in ipairs(ordered) do applySwitchInAbility(battle, mon) end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local mon = ev and ev.battler
    if battle and mon then applySwitchInAbility(battle, mon) end
  end)

  mod.log:info("g9-battle-engine: switchin_stat_change installed (INTIMIDATE, INTREPIDSWORD, DAUNTLESSSHIELD, SUPERSWEETSYRUP, OBLIVIOUS/GUARDDOG/RATTLED intimidate-guard)")
end
