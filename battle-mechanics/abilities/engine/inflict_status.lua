-- Dispatch engine for abilities/data/inflict_status.lua -- the
-- inflict_status bucket (16 real abilities), never touched by any
-- earlier phase despite the ability roadmap otherwise covering 6 of the
-- 8 real-count-weighted kind buckets by this point. Amounts/chances
-- read live from national_dex's own abilityBehaviorOf except where its
-- own `notes` field flags a real inaccuracy -- see abilities/data/
-- inflict_status.lua's own header for each one, verified against
-- Pokemon Showdown's own real source before building anything.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags
      and nationalDex.exports.moveById,
    "inflict_status: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  local curTypesOf = mod.exports.curTypesOf
  local isGen2Battle = mod.exports.isGen2Battle
  local tryAttract = mod.exports.tryAttract
  assert(abilityIdOf and curTypesOf and isGen2Battle and tryAttract,
    "inflict_status: ability_dispatch.lua, modern_combat.lua, and modern_status_effects.lua must load first")

  local STATUS_CODES = {
    burn = { gen1 = "BRN", gen2 = "burn" }, poison = { gen1 = "PSN", gen2 = "poison" },
    paralysis = { gen1 = "PAR", gen2 = "paralyze" }, toxic = { gen1 = "PSN", gen2 = "toxic", isToxic = true },
    sleep = { gen1 = "SLP", gen2 = "sleep" },
  }
  local function inflict(battle, gen2, mon, canonical, moveType, source)
    local codes = STATUS_CODES[canonical]
    if not codes then return end
    -- Phase 11 (Corrosion): the real TYPE-based status immunity (Fire can't
    -- be burned, Poison/Steel can't be poisoned) that neither status
    -- primitive enforces -- see combat/modern_combat.lua's own
    -- statusTypeImmune header. `source` is the inflicting mon where the
    -- call site knows it; Corrosion pierces the poison half exactly as it
    -- does on the move-secondary path.
    local statusTypeImmune = mod.exports.statusTypeImmune
    if statusTypeImmune and statusTypeImmune(battle, mon, canonical) then
      local corrosionPiercesPoison = mod.exports.corrosionPiercesPoison
      local pierce = (canonical == "poison" or canonical == "toxic")
        and corrosionPiercesPoison and corrosionPiercesPoison(source)
      if not pierce then return end
    end
    if gen2 then
      battle:applyStatus(mon, codes.gen2, "ability")
    else
      local StatusRegistry = require("src.battle.StatusRegistry")
      -- Deliberately NOT passing opts.secondary/opts.moveType: this is
      -- an ability trigger, never a real move, so the move-type immunity
      -- exemption (e.g. Electric can't secondary-paralyze Ground) never
      -- applies here in the first place -- Static's own real note
      -- ("still paralyzes attackers normally immune to Electric-type
      -- effects") is naturally already true, not a special case to add.
      StatusRegistry.inflict(battle, mon, codes.gen1, { source = "ability", toxic = codes.isToxic })
    end
  end
  local function currentStatusOf(mon, gen2)
    local m = mon.mon or mon
    return m.status
  end

  local function isGrassType(mon, gen2)
    for _, t in ipairs(curTypesOf(mon, gen2)) do
      if t == "GRASS" then return true end
    end
    return false
  end

  ------------------------------------------------------------------
  -- Real 30%-on-contact-taken family: Cute Charm, Flame Body, Poison
  -- Point, Static. All confirmed identical real shape (Showdown's own
  -- `randomChance(3, 10)`, gated on `checkMoveMakesContact`).
  ------------------------------------------------------------------
  local ON_CONTACT_STATUS = { FLAMEBODY = "burn", POISONPOINT = "poison", STATIC = "paralysis" }
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target -- the ability holder
    local user = ev and ev.user -- the attacker
    if not (battle and moveId and target and user and (ev.damage or 0) > 0) then return end
    local id = abilityIdOf(target)
    if not (id and data[id]) then return end
    -- Long Reach (Phase 7): the real "did this attacker's move make
    -- contact" answer, ability-aware.
    local makesContact = mod.exports.makesContact
    if not (makesContact and makesContact(moveId, user)) then return end
    local gen2 = isGen2Battle(battle)

    if id == "CUTECHARM" then
      local roll = gen2 and battle.random(10) or (battle.rng(1, 10) - 1)
      if roll < 3 then tryAttract(battle, user, target, gen2) end
      return
    end

    local statusName = ON_CONTACT_STATUS[id]
    if statusName then
      local roll = gen2 and battle.random(10) or (battle.rng(1, 10) - 1)
      if roll < 3 and not currentStatusOf(user, gen2) then
        inflict(battle, gen2, user, statusName, nil, target)
      end
      return
    end

    if id == "EFFECTSPORE" then
      if isGrassType(user, gen2) then return end
      if currentStatusOf(user, gen2) then return end
      local roll = gen2 and battle.random(100) or (battle.rng(1, 100) - 1)
      if roll < 11 then inflict(battle, gen2, user, "sleep", nil, target)
      elseif roll < 21 then inflict(battle, gen2, user, "paralysis", nil, target)
      elseif roll < 30 then inflict(battle, gen2, user, "poison", nil, target) end
      return
    end
  end)

  ------------------------------------------------------------------
  -- Poison Touch / Toxic Chain: the HOLDER's own ability, triggers on
  -- its OWN move connecting -- checked against ev.user (the holder is
  -- the attacker here), status lands on ev.target.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target
    local user = ev and ev.user
    if not (battle and moveId and target and user and (ev.damage or 0) > 0) then return end
    local id = abilityIdOf(user)
    if not (id and data[id]) then return end
    local gen2 = isGen2Battle(battle)

    if id == "POISONTOUCH" then
      local flags = moveFlags(moveId)
      if not (flags and flags.contact) then return end
      if currentStatusOf(target, gen2) then return end
      local roll = gen2 and battle.random(10) or (battle.rng(1, 10) - 1)
      if roll < 3 then inflict(battle, gen2, target, "poison", nil, user) end
      return
    end

    if id == "TOXICCHAIN" then
      if currentStatusOf(target, gen2) then return end
      local roll = gen2 and battle.random(10) or (battle.rng(1, 10) - 1)
      if roll < 3 then inflict(battle, gen2, target, "toxic", nil, user) end
      return
    end

    if id == "STENCH" then
      local info = moveById(moveId)
      if info and (info.flinchChance or 0) > 0 then return end -- real: never stacks with a move's own flinch chance
      local roll = gen2 and battle.random(10) or (battle.rng(1, 10) - 1)
      if roll < 1 then
        -- Route through abilities/engine/hit_taken.lua's exported
        -- setFlinched when loaded (STEADFAST reaction), else plain native
        -- write. hit_taken.lua boots after this file, so read lazily.
        local setFlinched = mod.exports.setFlinched
        if setFlinched then
          setFlinched(battle, target, gen2)
        elseif not (mod.exports.isDynamaxed and mod.exports.isDynamaxed(target)) then
          if gen2 then
            battle:volatile(target).flinched = true
          else
            target.flinched = true
          end
        end
      end
      return
    end
  end)

  ------------------------------------------------------------------
  -- Spicy Spray: 100%, burns whatever hits the holder, no contact
  -- requirement.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local target = ev and ev.target
    local user = ev and ev.user
    if not (battle and target and user and (ev.damage or 0) > 0) then return end
    if abilityIdOf(target) ~= "SPICYSPRAY" or not data.SPICYSPRAY then return end
    local gen2 = isGen2Battle(battle)
    if not currentStatusOf(user, gen2) then inflict(battle, gen2, user, "burn", nil, target) end
  end)

  ------------------------------------------------------------------
  -- Synchronize: passes a hostile burn/paralysis/poison/toxic the
  -- holder receives back onto whoever inflicted it. Wrapped at the
  -- SAME two real status-infliction primitives status_immunity.lua
  -- already wraps (StatusRegistry.inflict/Battle:applyStatus) -- runs
  -- AFTER the native call so it only fires once the status has actually
  -- landed, matching Synchronize's own real onAfterSetStatus timing.
  -- Real exclusions (confirmed via Showdown source): self-inflicted
  -- (Rest), Toxic Spikes (an indirect, non-move/ability source), sleep/
  -- freeze (both explicitly excluded from the real ability).
  --
  -- WHO INFLICTED IT: neither of this mod's own status primitives
  -- threads the attacking battler through (opts.source is a move id
  -- string, not a battler reference -- confirmed, every real call site
  -- in this codebase), so the exact real inflicter can never be pinned
  -- down precisely -- a genuine, permanent limitation, not something
  -- N-way rework fixes. UPDATED 2026-08-28 (was a hardcoded 2-battler
  -- pair, `(mon == battle.player) and battle.enemy or battle.player`):
  -- now picks a REAL RANDOM opposing battler via requestAdjacency
  -- (combat/move_targeting.lua) -- correct for the real two-battler case
  -- (only one possible answer) and a defensible, real generalization for
  -- a genuine multi-battler fight (some real opponent, not silently
  -- always "whichever mon happens to be battle.enemy"). Works for both
  -- engines uniformly: no battle-scene mod wraps the adjacency hook for
  -- Gen 1 (g9-Battle-Scene, the one real multi-battler consumer, is
  -- itself Gen 2-only), so a Gen 1 call always lands on the same native
  -- two-battler fallback requestAdjacency already has built in.
  ------------------------------------------------------------------
  local SYNC_CANONICAL = { PSN = "poison", BRN = "burn", PAR = "paralysis", TOX = "poison" }
  local SYNC_CANONICAL_GEN2 = { poison = "poison", burn = "burn", paralyze = "paralysis", toxic = "toxic" }
  local function otherBattler(battle, mon)
    local requestAdjacency = mod.exports.requestAdjacency
    if not requestAdjacency then
      return (mon == battle.player) and battle.enemy or battle.player
    end
    local enemies = requestAdjacency(battle, mon, nil).enemies
    if #enemies == 0 then return nil end
    return enemies[love.math.random(1, #enemies)]
  end

  -- Reflection calls are tagged with a dedicated "synchronize" source
  -- (NOT the shared "ability" tag every other inflict() call in this
  -- file uses) -- checking `~= "ability"` here would have been wrong in
  -- a different way than infinite recursion: it would have silently
  -- blocked Synchronize from EVER reacting to Flame Body/Static/Poison
  -- Point/etc (every one of which also tags its own call "ability"),
  -- not just prevented a mirror-match Synchronize-vs-Synchronize loop.
  -- Only the reflection itself is excluded from triggering again.
  local StatusRegistry = require("src.battle.StatusRegistry")
  local nativeSyncInflict = StatusRegistry.inflict
  StatusRegistry.inflict = function(battle, target, status, opts)
    local result = nativeSyncInflict(battle, target, status, opts)
    if #result > 0 and abilityIdOf(target) == "SYNCHRONIZE" and data.SYNCHRONIZE
        and (not opts or opts.source ~= "synchronize") then
      local canonical = SYNC_CANONICAL[status]
      local attacker = otherBattler(battle, target)
      if canonical and attacker ~= target and not currentStatusOf(attacker, false) then
        StatusRegistry.inflict(battle, attacker, STATUS_CODES[canonical].gen1,
          { source = "synchronize", toxic = STATUS_CODES[canonical].isToxic })
      end
    end
    return result
  end

  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  if Battle then
    local nativeSyncApplyStatus = Battle.applyStatus
    function Battle:applyStatus(mon, status, source)
      local result = nativeSyncApplyStatus(self, mon, status, source)
      if result and abilityIdOf(mon) == "SYNCHRONIZE" and data.SYNCHRONIZE and source ~= "synchronize" then
        local canonical = SYNC_CANONICAL_GEN2[status]
        local attacker = otherBattler(self, mon)
        if canonical and attacker ~= mon and not currentStatusOf(attacker, true) then
          Battle.applyStatus(self, attacker, STATUS_CODES[canonical].gen2, "synchronize")
        end
      end
      return result
    end
  end

  mod.log:info("g9-battle-engine: inflict_status installed (CUTECHARM, EFFECTSPORE, FLAMEBODY, POISONPOINT, STATIC, POISONTOUCH, TOXICCHAIN, STENCH, SYNCHRONIZE, SPICYSPRAY)")
end
