-- Dispatch engine for abilities/data/ability_copy.lua -- Phase 8 of the
-- ability roadmap (TRACE, MUMMY, LINGERINGAROMA, WANDERINGSPIRIT,
-- RECEIVER, POWEROFALCHEMY). Every real change goes through
-- mod.exports.setAbility (abilities/ability_dispatch.lua) --
-- combat-only (restores the mon's own natural ability on switch-out/
-- battle-end) and boss-immune (refuses outright against battle.enemy),
-- both already enforced there, not duplicated here.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags,
    "ability_copy: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  local setAbility = mod.exports.setAbility
  assert(abilityIdOf and setAbility, "ability_copy: ability_dispatch.lua must load first")

  ------------------------------------------------------------------
  -- TRACE
  ------------------------------------------------------------------
  local TRACE_EXCLUDED = {
    FLOWERGIFT = true, FORECAST = true, MULTITYPE = true,
    TRACE = true, WONDERGUARD = true,
  }
  -- Real N-way random opponent -- explicit user request (2026-08-28):
  -- Trace's own real text is "copies a RANDOM opposing Pokémon's
  -- ability," which only ever had one real choice in the native
  -- two-battler case (the hard-binary `opponentOf` this replaces). Reuses
  -- requestAdjacency (combat/move_targeting.lua), the same real primitive
  -- every other N-way-aware trigger in this mod now goes through, so a
  -- doubles/triples Trace correctly rolls among however many real
  -- opponents are actually out.
  local function randomOpponentOf(battle, mon)
    local requestAdjacency = mod.exports.requestAdjacency
    if not requestAdjacency then
      return (mon == battle.player) and battle.enemy or battle.player
    end
    local enemies = requestAdjacency(battle, mon, nil).enemies
    local alive = {}
    for _, e in ipairs(enemies) do
      if (e.hp or 0) > 0 then alive[#alive + 1] = e end
    end
    if #alive == 0 then return nil end
    return alive[love.math.random(1, #alive)]
  end
  local function applyTrace(battle, mon)
    if not (battle and mon and (mon.hp or 0) > 0) then return end
    if abilityIdOf(mon) ~= "TRACE" or not data.TRACE then return end
    local opp = randomOpponentOf(battle, mon)
    local oppId = opp and abilityIdOf(opp)
    if not oppId or TRACE_EXCLUDED[oppId] then return end
    setAbility(battle, mon, oppId)
  end

  -- Round 338: Transform/Imposter can copy TRACE itself, so its own
  -- switch-in copy must be reachable on demand too.
  mod.exports.registerSwitchInAbility(applyTrace)

  -- Same real N-way dual-trigger shape every other switch-in ability
  -- engine in this mod now uses (abilities/engine/switchin_stat_change
  -- .lua's own header): battle.started covers however many battlers led
  -- together, in real fastest-first application order; battle.battler_
  -- switched covers every switch after that.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local allActiveBattlers = mod.exports.allActiveBattlers
    local orderActiveBattlers = mod.exports.orderActiveBattlers
    local roster = allActiveBattlers and allActiveBattlers(battle) or { battle.player, battle.enemy }
    local ordered = orderActiveBattlers and orderActiveBattlers(battle, roster) or roster
    for _, mon in ipairs(ordered) do applyTrace(battle, mon) end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local mon = ev and ev.battler
    if battle and mon then applyTrace(battle, mon) end
  end)

  ------------------------------------------------------------------
  -- MUMMY / WANDERINGSPIRIT -- both real on-contact-taken, reusing the
  -- same battle.damage_dealt + moveFlags(id).contact primitive this
  -- mod's other contact-triggered abilities already use (abilities/
  -- engine/inflict_status.lua's 30%-on-contact family, contact_
  -- retaliation.lua's Iron Barbs/Aftermath).
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target -- the ability holder
    local user = ev and ev.user -- the attacker
    if not (battle and moveId and target and user and (ev.damage or 0) > 0) then return end
    -- Long Reach (Phase 7): the real "did this attacker's move make
    -- contact" answer, ability-aware.
    local makesContact = mod.exports.makesContact
    if not (makesContact and makesContact(moveId, user)) then return end
    local id = abilityIdOf(target)

    if id == "MUMMY" and data.MUMMY then
      if abilityIdOf(user) ~= "MULTITYPE" then
        setAbility(battle, user, "MUMMY")
      end
      return
    end

    if id == "LINGERINGAROMA" and data.LINGERINGAROMA then
      if abilityIdOf(user) ~= "MULTITYPE" then
        setAbility(battle, user, "LINGERINGAROMA")
      end
      return
    end

    if id == "WANDERINGSPIRIT" and data.WANDERINGSPIRIT then
      local holderOld = abilityIdOf(target)
      local attackerOld = abilityIdOf(user)
      if holderOld and attackerOld and holderOld ~= attackerOld then
        -- Applied in two steps, second gated on the first's own real
        -- success: the only realistic refusal here is boss-immunity
        -- (both ids already resolve, since both were just read live off
        -- real mons), and a boss-protected swap must refuse WHOLE, not
        -- change the non-boss side while leaving the boss's own slot
        -- untouched -- a real half-swap bug, not a cosmetic one.
        local userChanged = setAbility(battle, user, holderOld)
        if userChanged ~= false then
          setAbility(battle, target, attackerOld)
        end
      end
      return
    end
  end)

  ------------------------------------------------------------------
  -- RECEIVER / POWEROFALCHEMY -- real trigger is "an adjacent ally
  -- faints"; copies that ally's own (pre-faint) ability onto whichever
  -- one of these two the holder actually has. Real Showdown picks the
  -- first ally (by slot) that carries either ability when more than one
  -- qualifies -- this mod's own requestAdjacency already returns allies
  -- in a stable, real slot order, so a plain first-match loop matches
  -- that rule for free, no extra sort needed.
  ------------------------------------------------------------------
  mod.events:on("battle.fainted", function(ev)
    local battle, fainted = ev and ev.battle, ev and ev.battler
    if not (battle and fainted) then return end
    local faintedAbility = abilityIdOf(fainted)
    if not faintedAbility then return end
    local requestAdjacency = mod.exports.requestAdjacency
    if not requestAdjacency then return end
    for _, ally in ipairs(requestAdjacency(battle, fainted, nil).allies) do
      if (ally.hp or 0) > 0 then
        local id = abilityIdOf(ally)
        if (id == "RECEIVER" and data.RECEIVER) or (id == "POWEROFALCHEMY" and data.POWEROFALCHEMY) then
          setAbility(battle, ally, faintedAbility)
          break
        end
      end
    end
  end)

  mod.log:info("g9-battle-engine: ability_copy installed (TRACE, MUMMY, LINGERINGAROMA, "
    .. "WANDERINGSPIRIT, RECEIVER, POWEROFALCHEMY)")
end
