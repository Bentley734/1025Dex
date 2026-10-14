-- Dispatch engine for abilities/data/hit_taken.lua -- Phase 14 (ability
-- audit close-out), the "when hit" family. See that file's own header
-- for the full real-mechanic grounding (each entry is confirmed
-- against national_dex's own records AND Showdown).
--
-- TRIGGER SHAPE: almost everything here fires off battle.damage_dealt
-- (the landed, non-zero damaging-hit event -- Counter/Future Sight/
-- hazard damage never triggers these, matching real Showdown where
-- those sources don't count as "hit by a move"). The holder is ev.target
-- (the one who took the hit), the attacker ev.user.
--
-- GEN-NATIVE SPEED RULE: speed stage changes (Steam Engine, Rattled,
-- Weak Armor, Angershell's speed half, and the hostile -1 speed drops
-- of Cotton Down/Gooey/Tangling Hair) are written to each generation's
-- REAL native speed store -- never through mod.exports.changeStage,
-- which by this mod's own established boundary only owns atk/def/spa/
-- spd (same convention switch_priority_misc.lua's BATTLE BOND half and
-- switchin_stat_change.lua's NATIVE_STATS split already establish):
--   Gen 2: battle:changeStageAgainstMist(attacker, victim, "speed", n)
--          -- emits its own message internally.
--   Gen 1: victim.stages.speed, clamped -6..6 (Damage.lua's own real
--          accuracy/speed-formula consumer).
-- Self-raises skip the Mist gate argument entirely (changeStageAgainstMist
-- only ever blocks a HOSTILE drop), and self-inflicted drops (Weak Armor,
-- Angershell) can never be boss-gated or Mist-gated -- real and safe.
--
-- ATOMICITY: each handler runs in its own event. Any battle emitting
-- damage_dealt twice for one hit (boss fights, multihit) sees the stat
-- change fire per hit, which is real for STAMINA/Weak Armor etc. The
-- half-HP-crossing abilities (Berserk, Angershell) are explicitly
-- gated to fire ONCE per move via a cumulative per-move damage map
-- below, matching real Showdown (which tracks the move's total damage
-- across hits, then crosses half HP once).
return function(mod, data)
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  local changeStage = mod.exports.changeStage
  local allActiveBattlers = mod.exports.allActiveBattlers
  local requestAdjacency = mod.exports.requestAdjacency
  local recordInteraction = mod.exports.recordInteraction
  assert(abilityIdOf and displayNameFor and isGen2Battle and changeStage
      and allActiveBattlers and requestAdjacency and recordInteraction,
    "hit_taken: ability_dispatch.lua, modern_combat.lua, move_targeting.lua, "
      .. "and interaction_memory.lua must load first")
  local setTerrain = mod.exports.setTerrain
  local currentWeather = mod.exports.currentWeather
  local canSetWeather = mod.exports.canSetWeather
  local setWeather = mod.exports.setWeather
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local FIELD_BASE_TURNS = mod.exports.FIELD_BASE_TURNS
  local FIELD_EXTENDED_TURNS = mod.exports.FIELD_EXTENDED_TURNS
  local makesContact = mod.exports.makesContact
  assert(setTerrain and currentWeather and canSetWeather and setWeather
      and resolveFieldDuration and makesContact,
    "hit_taken: modern_terrain.lua, modern_weather.lua, field_duration.lua, "
      .. "and long_reach.lua must load first")

  local function hpOf(m) return (m and (m.mon or m) or {}).hp or 0 end
  local function maxHpOf(m)
    local mon = m and (m.mon or m) or {}
    return mon.maxHp or (mon.stats and mon.stats.hp) or 1
  end

  -- Real gen-native speed raise (positive self-raise; never Mist-gated --
  -- Mist only ever blocks a hostile drop).
  local function raiseSpeed(battle, mon, gen2, stages)
    stages = stages or 1
    if gen2 then
      battle:changeStageAgainstMist(mon, mon, "speed", stages)
    else
      mon.stages = mon.stages or {}
      local cur = mon.stages.speed or 0
      mon.stages.speed = math.max(-6, math.min(6, cur + stages))
    end
  end

  -- Real gen-native hostile speed drop (source = the ability holder, so
  -- Mist protects the victim, matching Showdown).
  local function dropSpeed(battle, source, victim, gen2, stages)
    stages = stages or 1
    if gen2 then
      battle:changeStageAgainstMist(source, victim, "speed", -stages)
    else
      victim.stages = victim.stages or {}
      local cur = victim.stages.speed or 0
      victim.stages.speed = math.max(-6, math.min(6, cur - stages))
    end
  end

  local function speedMessage(battle, mon, verb)
    return Strings("%s's Speed " .. verb .. "!",
      displayNameFor(battle, mon, isGen2Battle(battle)))
  end

  ------------------------------------------------------------------
  -- BERSERK / ANGERSHELL -- fire once when the move (cumulative across
  -- hits) first pushes HP below half. Real Showdown: totalDamage tracks
  -- the move's summed damage so a multihit crossing half triggers once.
  ------------------------------------------------------------------
  local perMoveDamage = {} -- weak-ish keyed map, cleared each turn
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for k in pairs(perMoveDamage) do perMoveDamage[k] = nil end
  end)
  local function halfHpHandler(battle, target, user, moveId, damage, gen2)
    local id = abilityIdOf(target)
    if not (id == "BERSERK" or id == "ANGERSHELL") then return end
    if hpOf(target) <= 0 then return end -- must survive the hit
    local key = tostring(battle) .. "|" .. tostring(target) .. "|"
      .. tostring(user) .. "|" .. tostring(moveId)
    local total = (perMoveDamage[key] or 0) + (damage or 0)
    perMoveDamage[key] = total
    local maxHp = maxHpOf(target)
    local pre = math.min(maxHp, hpOf(target) + total)
    local post = hpOf(target)
    if not (post > 0 and post <= maxHp / 2 and pre > maxHp / 2) then return end
    if id == "BERSERK" then
      for _, line in ipairs(changeStage(battle, target, "spa", 1, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
    else
      -- Angershell: -1 Def, -1 Sp.Def, +1 Atk, +1 Sp.Atk, +1 Speed.
      -- Drops are self-inflicted: fromEnemy=false, so no boss gate, no Mist.
      for _, line in ipairs(changeStage(battle, target, "defense", -1, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
      for _, line in ipairs(changeStage(battle, target, "spd", -1, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
      for _, line in ipairs(changeStage(battle, target, "attack", 1, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
      for _, line in ipairs(changeStage(battle, target, "spa", 1, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
      raiseSpeed(battle, target, gen2, 1)
      battle:emit({ kind = "message", text = speedMessage(battle, target, "rose") })
    end
  end

  ------------------------------------------------------------------
  -- COTTONDOWN / GOOEY / TANGLINGHAIR -- hostile speed drops. Cotton
  -- Down: every OTHER active Pokémon (both sides, self excluded).
  -- Gooey/Tangling Hair: the attacker, contact moves only.
  ------------------------------------------------------------------
  local function cottonDown(battle, target, gen2)
    if hpOf(target) <= 0 then return end
    local dropped = false
    for _, foe in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if foe and foe ~= target and hpOf(foe) > 0 then
        recordInteraction(battle, target, foe, "ability", "COTTONDOWN")
        dropSpeed(battle, target, foe, gen2, 1)
        dropped = true
      end
    end
    if dropped then
      battle:emit({ kind = "message",
        text = Strings("%s's Cotton Down lowered every active Pokémon's Speed!", displayNameFor(battle, target, gen2)) })
    end
  end
  local function gooeyLike(battle, target, user, moveId, gen2)
    if hpOf(target) <= 0 or not user then return end
    if not (makesContact and makesContact(moveId, user)) then return end
    recordInteraction(battle, target, user, "ability", abilityIdOf(target))
    dropSpeed(battle, target, user, gen2, 1)
  end

  ------------------------------------------------------------------
  -- SANDSPIT -- sets Sandstorm when hit (copy of switchin_weather's
  -- own applySwitchInAbility shape, with a fixed SAND value).
  ------------------------------------------------------------------
  local function sandSpit(battle, target, gen2)
    if hpOf(target) <= 0 then return end
    if currentWeather(battle, true) == "SAND" then return end
    if not canSetWeather(battle, false, target) then return end
    local turns = resolveFieldDuration(target, FIELD_BASE_TURNS, FIELD_EXTENDED_TURNS, "SMOOTHROCK")
    setWeather(battle, true, "SAND", turns, target)
    battle:emit({ kind = "message", text = Strings("%s's ability changed the weather!", battle:monName(target)) })
  end

  ------------------------------------------------------------------
  -- MAIN -- battle.damage_dealt: every when-hit reaction.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    if not (battle and user and target and (ev.damage or 0) > 0) then return end
    local move = ev.move
    local moveType = move and move.type
    local moveId = move and move.id
    local gen2 = isGen2Battle(battle)
    local id = abilityIdOf(target)
    if not (id and data[id]) then return end

    if id == "STAMINA" then
      if hpOf(target) <= 0 then return end
      for _, line in ipairs(changeStage(battle, target, "defense", 1, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
    elseif id == "WATERCOMPACTION" and moveType == "WATER" then
      if hpOf(target) <= 0 then return end
      for _, line in ipairs(changeStage(battle, target, "defense", 2, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
    elseif id == "STEAMENGINE" and (moveType == "FIRE" or moveType == "WATER") then
      if hpOf(target) <= 0 then return end
      raiseSpeed(battle, target, gen2, 3)
      battle:emit({ kind = "message", text = speedMessage(battle, target, "rose sharply") })
    elseif id == "JUSTIFIED" and moveType == "DARK" then
      if hpOf(target) <= 0 then return end
      for _, line in ipairs(changeStage(battle, target, "attack", 1, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
    elseif id == "RATTLED" and (moveType == "DARK" or moveType == "BUG" or moveType == "GHOST") then
      if hpOf(target) <= 0 then return end
      raiseSpeed(battle, target, gen2, 1)
      battle:emit({ kind = "message", text = speedMessage(battle, target, "rose") })
    elseif id == "ANGERPOINT" and ev.crit then
      if hpOf(target) <= 0 then return end
      for _, line in ipairs(changeStage(battle, target, "attack", 6, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
    elseif id == "WEAKARMOR" and ev.kind == "physical" then
      if hpOf(target) <= 0 then return end
      for _, line in ipairs(changeStage(battle, target, "defense", -1, false, gen2) or {}) do
        battle:emit({ kind = "message", text = line })
      end
      raiseSpeed(battle, target, gen2, 2)
      battle:emit({ kind = "message", text = speedMessage(battle, target, "rose sharply") })
    elseif id == "BERSERK" or id == "ANGERSHELL" then
      halfHpHandler(battle, target, user, moveId, ev.damage, gen2)
    elseif id == "COTTONDOWN" then
      cottonDown(battle, target, gen2)
    elseif id == "GOOEY" or id == "TANGLINGHAIR" then
      gooeyLike(battle, target, user, moveId, gen2)
    elseif id == "SANDSPIT" then
      sandSpit(battle, target, gen2)
    elseif id == "SEEDSOWER" then
      if hpOf(target) <= 0 then return end
      setTerrain(battle, target, "GRASSY", "Grass grew to cover the battlefield!")
    end
  end)

  ------------------------------------------------------------------
  -- STEADFAST -- +1 Speed when this Pokémon flinches. There is no
  -- generic flinch EVENT in the base engine; the two real places a
  -- flinch is applied (main.lua's own flinchChance block and
  -- abilities/engine/inflict_status.lua's own Stench) both write the
  -- native volatile directly. This mod exports one shared primitive
  -- they both route through, so Steadfast is correct at every flinch
  -- site at once.
  ------------------------------------------------------------------
  mod.exports.setFlinched = function(battle, mon, gen2)
    if not mon then return end
    -- Round 27 (2026-09-10): a Dynamaxed/Gigantamax Pokemon cannot be
    -- flinched -- explicit user directive, and the same single exception
    -- Showdown's own Dynamax volatile makes (conditions.ts' dynamax
    -- onTryAddVolatile returns null for flinch). Guarded at this one choke
    -- point so every real flinch site that routes here is covered at once;
    -- a caller that still writes the volatile directly must gate itself.
    local isDyn = mod.exports.isDynamaxed
    if isDyn and isDyn(mon) then return end
    if gen2 then
      battle:volatile(mon).flinched = true
    else
      mon.flinched = true
    end
    if mon and data.STEADFAST and abilityIdOf(mon) == "STEADFAST" then
      raiseSpeed(battle, mon, gen2 or isGen2Battle(battle), 1)
      battle:emit({ kind = "message",
        text = speedMessage(battle, mon, "rose") })
    end
  end

  mod.log:info("g9-battle-engine: hit_taken installed (STAMINA, WATERCOMPACTION, "
    .. "STEAMENGINE, JUSTIFIED, RATTLED, ANGERPOINT, WEAKARMOR, STEADFAST, BERSERK, "
    .. "ANGERSHELL, COTTONDOWN, GOOEY, TANGLINGHAIR, SANDSPIT, SEEDSOWER)")
end
