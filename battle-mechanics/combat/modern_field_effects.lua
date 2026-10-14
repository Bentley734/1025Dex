-- Phase 8 of the missing-effects pipeline: whole-field effects and the moves
-- that manipulate them -- Gravity, Ion Deluge, Electrify, Mud Sport, Water
-- Sport, Nature Power, Powder, Tailwind, Aurora Veil, Lucky Chant, Fairy Lock
-- and Tea Time.
--
-- The three "rooms" (Trick Room / Magic Room / Wonder Room) are NOT repeated
-- here: combat/trick_room.lua already owns them end to end (real 5-turn
-- toggles, Magic Room's item suppression, Wonder Room's Def/SpD swap), and
-- this phase closes the remaining field-effect gaps around them.
--
-- Showdown source of truth (scratch/showdown/moves.ts -- read by direct
-- extraction this session; line numbers cited per clause):
--   gravity (7755): Psychic/Status/0, accuracy: true, priority 0,
--     flags { nonsky, metronome }, `pseudoWeather: 'gravity'`, condition
--     `duration: 5` (Persistent -> 7). onFieldStart grounds everyone and
--     drops Fly/Bounce/Magnet Rise/Telekinesis; onModifyAccuracy
--     `chainModify([6840, 4096])` (x5/3); onBeforeMove fails a
--     `flags.gravity` move (Fly/Bounce/...).
--   iondeluge (9676): Electric/Status/0, accuracy: true, priority 1,
--     `pseudoWeather: 'iondeluge'`, `duration: 1`; onModifyType makes every
--     Normal-type move Electric.
--   electrify (4557): Electric/Status/0, accuracy: true, priority 0,
--     flags { protect, mirror, allyanim, metronome }, `volatileStatus:
--     'electrify'`, duration 1; onModifyType makes the target's next move
--     Electric (except Struggle).
--   mudsport (12456) / watersport (20628): Status/0, accuracy: true,
--     `pseudoWeather`, `duration: 5`; onBasePower `chainModify([1352,
--     4096])` against Electric (Mud) / Fire (Water). NOTE: 1352/4096 =
--     ~0.3301, NOT the 0.5 an informal plan summary implies -- transcribed
--     exactly from source, per the standing "Showdown is source of truth"
--     rule.
--   naturepower (12599): Normal/Status/0, accuracy: true; onTryHit
--     dispatches another move by terrain: electricterrain -> thunderbolt,
--     grassyterrain -> energyball, mistyterrain -> moonblast,
--     psychicterrain -> psychic, else triattack; callsMove: true.
--   powder (13660): Bug/Status/0, accuracy 100, priority 1,
--     flags { protect, reflectable, mirror, bypasssub, metronome, powder },
--     `volatileStatus: 'powder'`, duration 1; onTryMove: if the move is
--     Fire-type, announce, deal `maxhp / 4`, and fail the move.
--   tailwind (18876): Flying/Status/0, accuracy: true, `sideCondition:
--     'tailwind'`, `duration: 4` (Persistent -> 6); onModifySpe
--     `chainModify(2)`.
--   auroraveil (830): Ice/Status/0, accuracy: true, `sideCondition:
--     'auroraveil'`, `duration: 5` (Light Clay -> 8); onTry requires
--     `field.isWeather(['hail','snowscape'])`; onAnyModifyDamage halves the
--     hit unless it is a crit/infiltrates and the target's side does not
--     already have the matching screen (doubles uses 2732/4096).
--   luckychant (10502): Normal/Status/0, accuracy: true, `sideCondition:
--     'luckychant'`, `duration: 5`; `onCriticalHit: false`.
--   fairylock (5051): Fairy/Status/0, accuracy: true, `pseudoWeather:
--     'fairylock'`, `duration: 2`; onTrapPokemon.
--   teatime (19036): Normal/Status/0, accuracy: true; onHitField makes every
--     active mon eat its held Berry.
--
-- Design notes:
--   * Every whole-field effect is battle-scoped state (battle.<name>Turns),
--     the convention battle.weather/battle.trickRoomTurns already use. The
--     three side-scoped ones (Tailwind/Aurora Veil/Lucky Chant) live in the
--     engine's own battle.screens[side] table next to reflect/lightScreen/
--     safeguard, so Court Change's swap and Brick Break/Defog's clears in
--     combat/modern_side_conditions.lua reach them without a second store.
--   * Type overrides (Ion Deluge/Electrify) and Powder are wired through the
--     class-level Battle:useMove wrap: the damage path reads the move's own
--     `def.type`, so the override mutates that table for the duration of one
--     synchronous native call and restores it afterwards (pcall, so an error
--     can never leak a mutated move definition). This engine has no exported
--     move-type seam.
--   * Gravity's grounding is published as `mon.gravityGrounded` and read by
--     three existing groundedness checks (modern_combat.lua's
--     resolvedTypeMult, modern_hazards.lua's isGroundedForHazards,
--     modern_terrain.lua's isGrounded) -- the same real "grounded" concept
--     Smack Down's groundedByMove already uses, kept in a separate field so
--     ending Gravity can never clear a genuine Smack Down.
--   * Honest partials, flagged rather than faked: Gravity does not cancel an
--     in-flight Fly/Bounce/Magnet Rise/Telekinesis (those two-turn/volatile
--     states are only partly modelled here), and Tea Time reads the mod's
--     existing berry classification (combat/modern_items.lua's KNOWN_BERRIES)
--     rather than a schema flag, since the item schema has no isBerry field.
return function(mod)
  local Strings = require("src.core.Strings")
  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local sideOfWho = mod.exports.sideOfWho
  local isGen2Battle = mod.exports.isGen2Battle
  local currentWeather = mod.exports.currentWeather
  local registerDamageModifier = mod.exports.registerDamageModifier
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local FIELD_BASE_TURNS = mod.exports.FIELD_BASE_TURNS
  local FIELD_EXTENDED_TURNS = mod.exports.FIELD_EXTENDED_TURNS
  assert(normalize and displayNameFor and sideOfWho and isGen2Battle,
    "modern_field_effects: combat/modern_combat.lua must load first")
  assert(registerDamageModifier and currentWeather,
    "modern_field_effects: combat/modern_combat.lua must load first")
  assert(resolveFieldDuration and FIELD_BASE_TURNS and FIELD_EXTENDED_TURNS,
    "modern_field_effects: combat/field_duration.lua must load first")

  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  local knownBerries = mod.exports.knownBerries
  local applyEatenBerryEffect = mod.exports.applyEatenBerryEffect

  ------------------------------------------------------------------
  -- Shared helpers.
  ------------------------------------------------------------------
  local function emit(battle, text)
    if battle and battle.emit then
      battle:emit({ kind = "message", text = text })
    end
  end

  local function rawMon(who) return who and (who.mon or who) or nil end

  local function otherSide(side)
    return side == "enemy" and "player" or "enemy"
  end

  -- The live screens table for a side, created lazily exactly the way the
  -- native constructor seeds it and combat/modern_side_conditions.lua reads
  -- it. Tailwind/Aurora Veil/Lucky Chant ride here so Court Change's swap and
  -- the screen clears see them for free.
  local function screensOf(battle, side)
    battle.screens = battle.screens or { player = {}, enemy = {} }
    battle.screens[side] = battle.screens[side] or {}
    return battle.screens[side]
  end

  local function activeList(battle)
    local all = mod.exports.allActiveBattlers
    if all then return all(battle) or {} end
    return { battle.player, battle.enemy }
  end

  -- The single mon opposing `who` -- the default target for a self/field move
  -- whose run handler was handed no explicit defender (native 1v1 case).
  local function opposingActive(battle, who)
    if not (battle and who) then return nil end
    local side = sideOfWho(battle, who, true)
    return side == "player" and battle.enemy or battle.player
  end

  local function fail(battle)
    emit(battle, Strings("But it failed!"))
  end

  ------------------------------------------------------------------
  -- GRAVITY
  --   Field state battle.gravityTurns. Grounding is published per active mon
  --   as gravityGrounded (cleared when the field ends or the mon leaves).
  ------------------------------------------------------------------
  local function gravityActive(battle)
    return (battle and (battle.gravityTurns or 0) > 0) or false
  end
  mod.exports.gravityActive = gravityActive

  local function applyGravityToMon(mon, on)
    local m = rawMon(mon)
    if type(m) == "table" then m.gravityGrounded = on or nil end
  end

  local function applyGravityToActives(battle, on)
    if type(battle) ~= "table" then return end
    for _, who in ipairs(activeList(battle)) do applyGravityToMon(who, on) end
    applyGravityToMon(battle.player, on)
    applyGravityToMon(battle.enemy, on)
  end
  mod.exports.applyGravityToActives = applyGravityToActives

  mod.content.move_effects:register("GALAR_GRAVITY_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not battle then return end
      if gravityActive(battle) then return fail(battle) end
      -- Showdown's durationCallback (Persistent ability -> 7). No item can
      -- extend Gravity, so this always resolves to the base 5 today.
      battle.gravityTurns = resolveFieldDuration(user, FIELD_BASE_TURNS, 7, nil)
      applyGravityToActives(battle, true)
      emit(battle, Strings("Gravity intensified!"))
    end,
  })

  -- onModifyAccuracy chainModify([6840, 4096]) -- x5/3 in the percent domain
  -- Battle:moveAccuracy/Damage.rollHit read. Priority 40: outside the
  -- never-miss hooks (Move Flags' minimize at 50, which short-circuits before
  -- calling next) but inside the weather exception (priority -10), so a real
  -- "this move can never miss" verdict still wins.
  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    local battle = ctx and ctx.battle
    if not gravityActive(battle) then return next(ctx) end
    local acc = ctx.accuracy
    if type(acc) ~= "number" or acc <= 0 then return next(ctx) end
    ctx.accuracy = math.min(255, math.floor(acc * 6840 / 4096))
    return next(ctx)
  end, 40)

  ------------------------------------------------------------------
  -- ION DELUGE / ELECTRIFY -- type overrides read by the useMove wrap.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_IONDELUGE_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      if not battle then return end
      if (battle.ionDelugeTurns or 0) > 0 then return fail(battle) end
      battle.ionDelugeTurns = 1
      emit(battle, Strings("A deluge of ions showers the battlefield!"))
    end,
  })

  mod.content.move_effects:register("GALAR_ELECTRIFY_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, target = n.battle, n.target
      if not (battle and target) then return end
      local m = rawMon(target)
      m.volatile = m.volatile or {}
      m.volatile.electrify = true
      emit(battle, Strings("%s's moves have been electrified!", displayNameFor(battle, target, n.gen2)))
    end,
  })

  -- The effective type a single useMove call must run with. Electrify is the
  -- ATTACKER's own volatile (its next move); Ion Deluge is the whole field
  -- (every Normal-type move while it is up). Struggle is exempt from both,
  -- matching Showdown's `move.id !== 'struggle'` guard.
  local function effectiveMoveType(battle, attacker, baseType, moveId)
    if not baseType or moveId == "STRUGGLE" then return baseType end
    local m = rawMon(attacker)
    if m and m.volatile and m.volatile.electrify then return "ELECTRIC" end
    if (battle and (battle.ionDelugeTurns or 0) > 0) and baseType == "NORMAL" then
      return "ELECTRIC"
    end
    return baseType
  end
  mod.exports.effectiveMoveType = effectiveMoveType

  ------------------------------------------------------------------
  -- POWDER -- a one-turn volatile on the target; the useMove wrap blows up
  -- the target's own next Fire-type move.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_POWDER_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, target = n.battle, n.target
      if not (battle and target) then return end
      local m = rawMon(target)
      m.volatile = m.volatile or {}
      m.volatile.powder = true
      emit(battle, Strings("%s was covered in powder!", displayNameFor(battle, target, n.gen2)))
    end,
  })

  ------------------------------------------------------------------
  -- MUD SPORT / WATER SPORT -- whole-field power weakening.
  --   Showdown onBasePower chainModify([1352, 4096]) against Electric (Mud)
  --   / Fire (Water): ~0.3301, transcribed exactly (see file header).
  ------------------------------------------------------------------
  local SPORT_REDUCTION = 1352 / 4096
  local function sportMultiplier(battle, moveType)
    if not (battle and moveType) then return 1.0 end
    if moveType == "ELECTRIC" and (battle.mudSportTurns or 0) > 0 then
      return SPORT_REDUCTION
    end
    if moveType == "FIRE" and (battle.waterSportTurns or 0) > 0 then
      return SPORT_REDUCTION
    end
    return 1.0
  end
  mod.exports.sportMultiplier = sportMultiplier

  registerDamageModifier("mud_water_sport", 60, function(ctx)
    return sportMultiplier(ctx.battle, ctx.move and ctx.move.type)
  end)

  mod.content.move_effects:register("GALAR_MUDSPORT_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not battle then return end
      if (battle.mudSportTurns or 0) > 0 then return fail(battle) end
      battle.mudSportTurns = resolveFieldDuration(user, FIELD_BASE_TURNS, 5, nil)
      emit(battle, Strings("Electricity's power was weakened!"))
    end,
  })

  mod.content.move_effects:register("GALAR_WATERSPORT_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not battle then return end
      if (battle.waterSportTurns or 0) > 0 then return fail(battle) end
      battle.waterSportTurns = resolveFieldDuration(user, FIELD_BASE_TURNS, 5, nil)
      emit(battle, Strings("Fire's power was weakened!"))
    end,
  })

  ------------------------------------------------------------------
  -- NATURE POWER -- dispatch the terrain's move through the real useMove
  -- path (Showdown's actions.useMove with copyDepth set, the same guard
  -- Gen 2's own Metronome/Mirror Move recursion uses).
  ------------------------------------------------------------------
  local NATUREPOWER_BY_TERRAIN = {
    ELECTRIC = "THUNDERBOLT",
    GRASSY = "ENERGYBALL",
    MISTY = "MOONBLAST",
    PSYCHIC = "PSYCHIC",
  }
  mod.exports.naturePowerMoveFor = function(battle)
    return NATUREPOWER_BY_TERRAIN[(battle and battle.terrain) or ""] or "TRIATTACK"
  end

  mod.content.move_effects:register("GALAR_NATUREPOWER_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user) then return end
      if not target or target == user then target = opposingActive(battle, user) end
      local moveId = NATUREPOWER_BY_TERRAIN[battle.terrain or ""] or "TRIATTACK"
      -- copyDepth (the port's own "this move was called, don't charge its PP
      -- or set ramp/lock state" guard) around the nested dispatch.
      battle.copyDepth = (battle.copyDepth or 0) + 1
      local ok, err = pcall(battle.useMove, battle, user, target, moveId)
      battle.copyDepth = battle.copyDepth - 1
      if not ok then
        mod.log:warn("g9-battle-engine: modern_field_effects: "
          .. "Nature Power dispatch failed: %s", tostring(err))
      end
    end,
  })

  ------------------------------------------------------------------
  -- TAILWIND -- side condition, the side's Speed doubled.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_TAILWIND_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local side = sideOfWho(battle, user, n.gen2)
      local sc = screensOf(battle, side)
      if (sc.tailwind or 0) > 0 then return fail(battle) end
      -- Base 4 (Persistent -> 6); no item extends Tailwind.
      sc.tailwind = resolveFieldDuration(user, 4, 6, nil)
      emit(battle, Strings("The Tailwind blew from behind %s's team!", displayNameFor(battle, user, n.gen2)))
    end,
  })

  if Battle then
    local nativeEffectiveSpeed = Battle.effectiveSpeed
    function Battle:effectiveSpeed(mon)
      local speed
      if type(nativeEffectiveSpeed) == "function" then
        speed = nativeEffectiveSpeed(self, mon)
      else
        -- A harness/engine with no native method: fall back to the raw stat so
        -- Tailwind is still measurable without it.
        speed = (self.battleStat and self:battleStat(mon, "speed")) or 1
      end
      local side = self.sideOf and self:sideOf(mon)
      local sc = side and self.screens and self.screens[side]
      if sc and (sc.tailwind or 0) > 0 then return speed * 2 end
      return speed
    end
  end

  ------------------------------------------------------------------
  -- AURORA VEIL -- Ice screen, hail/snow only, halves damage.
  ------------------------------------------------------------------
  local function auroraVeilMultiplier(battle, target, category, crit)
    if not (battle and target) then return 1.0 end
    local side = sideOfWho(battle, target, true)
    local sc = screensOf(battle, side)
    if (sc.auroraVeil or 0) <= 0 then return 1.0 end
    -- Showdown: a crit (or Infiltrator) ignores it, and it does not stack on
    -- top of the matching screen the side already has.
    if crit then return 1.0 end
    local special = category == "Special"
    if special and (sc.lightScreen or 0) > 0 then return 1.0 end
    if (not special) and (sc.reflect or 0) > 0 then return 1.0 end
    return 0.5
  end
  mod.exports.auroraVeilMultiplier = auroraVeilMultiplier

  registerDamageModifier("aurora_veil", 70, function(ctx)
    return auroraVeilMultiplier(ctx.battle, ctx.target, ctx.category, ctx.crit)
  end)

  mod.content.move_effects:register("GALAR_AURORAVEIL_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      -- onTry: only usable in hail/snow (this project models Snow).
      if currentWeather(battle, isGen2Battle(battle)) ~= "SNOW" then
        return fail(battle)
      end
      local side = sideOfWho(battle, user, n.gen2)
      local sc = screensOf(battle, side)
      if (sc.auroraVeil or 0) > 0 then return fail(battle) end
      -- Light Clay extends 5 -> 8, exactly Showdown's durationCallback.
      sc.auroraVeil = resolveFieldDuration(user, FIELD_BASE_TURNS,
        FIELD_EXTENDED_TURNS, "LIGHT_CLAY")
      emit(battle, Strings("Aurora Veil made %s's team more resilient to attacks!", displayNameFor(battle, user, n.gen2)))
    end,
  })

  ------------------------------------------------------------------
  -- LUCKY CHANT -- side condition, no critical hits against the side.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_LUCKYCHANT_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local side = sideOfWho(battle, user, n.gen2)
      local sc = screensOf(battle, side)
      if (sc.luckyChant or 0) > 0 then return fail(battle) end
      sc.luckyChant = resolveFieldDuration(user, FIELD_BASE_TURNS, 5, nil)
      emit(battle, Strings("The Lucky Chant shielded %s's team from critical hits!", displayNameFor(battle, user, n.gen2)))
    end,
  })

  -- Showdown `onCriticalHit: false`: a crit aimed at a Lucky Chant side is
  -- simply suppressed, before any roll. Priority 100 -- authoritative, since
  -- this is a hard "cannot crit" verdict rather than a modifier.
  mod.hooks:wrap("battle.crit", function(next, ctx)
    local battle, target = ctx and ctx.battle, ctx and ctx.target
    if battle and target then
      local side = sideOfWho(battle, target, isGen2Battle(battle))
      local sc = battle.screens and battle.screens[side]
      if sc and (sc.luckyChant or 0) > 0 then return false end
    end
    return next(ctx)
  end, 100)

  ------------------------------------------------------------------
  -- FAIRY LOCK -- whole-field, nothing can flee for two turns.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_FAIRYLOCK_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      if not battle then return end
      if (battle.fairyLockTurns or 0) > 0 then return fail(battle) end
      battle.fairyLockTurns = 2
      emit(battle, Strings("No one will be able to flee the battlefield!"))
    end,
  })

  if Battle then
    local nativeSwitchLocked = Battle.switchLocked
    function Battle:switchLocked()
      local native = type(nativeSwitchLocked) == "function"
        and nativeSwitchLocked(self) or false
      if native then return true end
      if (self.fairyLockTurns or 0) > 0 then return true end
      return false
    end
  end

  ------------------------------------------------------------------
  -- TEA TIME -- every active mon eats its held Berry.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_TEATIME_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle = n.battle
      if not battle then return end
      local ate = false
      for _, who in ipairs(activeList(battle)) do
        local m = rawMon(who)
        local item = m and m.item
        if item and knownBerries and knownBerries[item] then
          local def = battle.itemDef and battle:itemDef(item)
          if def then
            m.item = nil
            m.ggdConsumedBerryThisBattle = true
            ate = true
            local nm = displayNameFor(battle, who, n.gen2)
            emit(battle, Strings("%s ate its %s!", nm, (def.name or item)))
            if applyEatenBerryEffect then
              pcall(applyEatenBerryEffect, battle, m, def, nm)
            end
          end
        end
      end
      if not ate then return fail(battle) end
      emit(battle, Strings("It's teatime!"))
    end,
  })

  ------------------------------------------------------------------
  -- POWDER + type overrides -- the single useMove interception.
  --   Order: compute the effective type, let Powder blow the move up (which
  --   spends the move's PP and shows "used X!" exactly like a real blocked
  --   move, then deals maxhp/4 and stops), otherwise mutate the shared move
  --   definition's type for the one synchronous native call and restore it.
  ------------------------------------------------------------------
  local function announceAndSpend(battle, attacker, moveId, def)
    if (battle.copyDepth or 0) == 0 and battle.findMove then
      local slot = battle:findMove(attacker, moveId)
      if slot and (slot.pp or 0) > 0 then slot.pp = slot.pp - 1 end
    end
    if battle.emit then
      battle.moveEvent = battle:emit({
        kind = "move",
        side = (battle.sideOf and battle:sideOf(attacker)) or "player",
        move = moveId,
        text = Strings("%s used %s!", (battle.monName and battle:monName(attacker) or "?"), ((def and def.name) or moveId)),
      })
    end
  end

  local function powderExplodes(battle, attacker)
    local m = rawMon(attacker)
    if not (m and m.volatile and m.volatile.powder) then return false end
    m.volatile.powder = nil
    local maxHp = m.maxHp or (m.stats and m.stats.hp) or 1
    local dmg = math.max(1, math.floor(maxHp / 4))
    m.hp = math.max(0, (m.hp or 0) - dmg)
    emit(battle, Strings("The powder exploded!"))
    if battle.emit then
      battle:emit({ kind = "damage",
        side = (battle.sideOf and battle:sideOf(attacker)) or "player",
        amount = dmg, hp = m.hp, anim = false })
    end
    return true
  end

  if Battle then
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if not (attacker and moveId) then
        return nativeUseMove(self, attacker, defender, moveId)
      end
      local def = self.moveDef and self:moveDef(moveId)
      local effType = def and effectiveMoveType(self, attacker, def.type, moveId)

      -- Powder: the target's own Fire move detonates instead of resolving.
      if effType == "FIRE" and rawMon(attacker)
          and rawMon(attacker).volatile and rawMon(attacker).volatile.powder then
        local ok, err = pcall(function()
          announceAndSpend(self, attacker, moveId, def)
          powderExplodes(self, attacker)
        end)
        if not ok then
          mod.log:warn("g9-battle-engine: modern_field_effects: "
            .. "Powder detonation failed: %s", tostring(err))
        end
        return
      end

      local restore
      if def and effType and def.type ~= effType then
        restore = def.type
        def.type = effType
      end
      local ok, result = pcall(nativeUseMove, self, attacker, defender, moveId)
      if restore then def.type = restore end
      if not ok then error(result, 0) end
      return result
    end
  end

  ------------------------------------------------------------------
  -- Durations. battle.turn_ended is the same real turn-boundary event
  -- modern_weather/trick_room decrement on. The turn the effect was set
  -- fires its own turn_ended, which is what makes "the casting turn counts
  -- as the first" come out right.
  ------------------------------------------------------------------
  local function tickField(battle, field, onExpire)
    if not battle or not battle[field] or battle[field] <= 0 then return end
    battle[field] = battle[field] - 1
    if battle[field] <= 0 then
      battle[field] = nil
      if onExpire then onExpire() end
    end
  end

  local function tickSide(battle, field, onExpire)
    local any = false
    for _, side in ipairs({ "player", "enemy" }) do
      local sc = battle.screens and battle.screens[side]
      if sc and sc[field] and sc[field] > 0 then
        sc[field] = sc[field] - 1
        any = true
        if sc[field] <= 0 then
          sc[field] = nil
          if onExpire then onExpire(side) end
        end
      end
    end
    return any
  end

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    tickField(battle, "gravityTurns", function()
      applyGravityToActives(battle, false)
      emit(battle, Strings("Gravity returned to normal!"))
    end)
    tickField(battle, "mudSportTurns", function()
      emit(battle, Strings("The effects of Mud Sport have faded."))
    end)
    tickField(battle, "waterSportTurns", function()
      emit(battle, Strings("The effects of Water Sport have faded."))
    end)
    tickField(battle, "ionDelugeTurns")
    tickField(battle, "fairyLockTurns", function()
      emit(battle, Strings("The effects of Fairy Lock have faded."))
    end)
    tickSide(battle, "tailwind", function()
      emit(battle, Strings("The Tailwind petered out!"))
    end)
    tickSide(battle, "auroraVeil", function()
      emit(battle, Strings("The Aurora Veil faded!"))
    end)
    tickSide(battle, "luckyChant", function()
      emit(battle, Strings("The Lucky Chant wore off!"))
    end)
    -- One-turn volatiles (Powder / Electrify), matching their duration: 1.
    for _, who in ipairs(activeList(battle)) do
      local m = rawMon(who)
      local vol = m and m.volatile
      if vol then
        vol.powder = nil
        vol.electrify = nil
      end
    end
  end)

  -- Gravity must follow each switch-in for as long as it is up.
  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    applyGravityToMon(ev.previous, false)
    applyGravityToMon(ev.battler, gravityActive(battle))
  end)

  -- Same "nothing a battle wrote is left on a party table" rule the mod's
  -- other field files enforce.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if battle then applyGravityToActives(battle, gravityActive(battle)) end
  end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if battle then applyGravityToActives(battle, false) end
  end)

  -- National Dex owns every one of these moves' base stats; the only field
  -- patched here is which sub-effect runs. The rooms are left to trick_room.
  mod.content.moves:patch("GRAVITY", { effect = "GALAR_GRAVITY_EFFECT" })
  mod.content.moves:patch("IONDELUGE", { effect = "GALAR_IONDELUGE_EFFECT" })
  mod.content.moves:patch("ELECTRIFY", { effect = "GALAR_ELECTRIFY_EFFECT" })
  mod.content.moves:patch("MUDSPORT", { effect = "GALAR_MUDSPORT_EFFECT" })
  mod.content.moves:patch("WATERSPORT", { effect = "GALAR_WATERSPORT_EFFECT" })
  mod.content.moves:patch("NATUREPOWER", { effect = "GALAR_NATUREPOWER_EFFECT" })
  mod.content.moves:patch("POWDER", { effect = "GALAR_POWDER_EFFECT" })
  mod.content.moves:patch("TAILWIND", { effect = "GALAR_TAILWIND_EFFECT" })
  mod.content.moves:patch("AURORAVEIL", { effect = "GALAR_AURORAVEIL_EFFECT" })
  mod.content.moves:patch("LUCKYCHANT", { effect = "GALAR_LUCKYCHANT_EFFECT" })
  mod.content.moves:patch("FAIRYLOCK", { effect = "GALAR_FAIRYLOCK_EFFECT" })
  mod.content.moves:patch("TEATIME", { effect = "GALAR_TEATIME_EFFECT" })

  mod.log:info("g9-battle-engine: modern_field_effects installed "
    .. "(GRAVITY, IONDELUGE, ELECTRIFY, MUDSPORT, WATERSPORT, NATUREPOWER, "
    .. "POWDER, TAILWIND, AURORAVEIL, LUCKYCHANT, FAIRYLOCK, TEATIME)")
end
