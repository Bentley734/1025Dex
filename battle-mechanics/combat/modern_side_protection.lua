-- Phase 22 of the missing-effects pipeline: field/side protection and
-- delayed moves.
--
-- Showdown source of truth (scratch/showdown/*.ts -- read by direct
-- extraction, line numbers cited per clause):
--   safeguard (moves.ts:15576-15629): Normal, Status, power 0, target
--     "allySide", `sideCondition: 'safeguard'`, `condition.duration` 5
--     (7 with Persistent). Its real teeth are `onSetStatus` (a hostile
--     setStatus is refused -- `target !== source` -- with an `-activate`
--     only for a real Move or Synchronize, NOT for a move's own
--     secondary) and `onTryAddVolatile` (the same refusal for confusion
--     and yawn). This mod does NOT reimplement any of that: the base
--     Gold engine already owns the whole mechanic (gen2/Battle.lua's
--     EFFECT_SAFEGUARD at :2716 sets `screens[side].safeguard =
--     SCREEN_TURNS`, Battle:safeguarded at :3345, Battle:applyStatus's
--     own Safeguard gate at :3404, Battle:applyConfusion's at :3456, a
--     damaging move's secondary status gate at :2096, and the screen
--     tick at :5195). national_dex shadows the move with
--     `effect = "EFFECT_NORMAL_HIT"` (effectModeled = false), which is
--     the ONLY reason Safeguard does nothing today -- so Phase 22 only
--     re-points the move at a real effect that forwards to the native
--     handler (with a direct fallback so a build without that handler
--     still sets the native field). Court Change / Defog / Brick Break
--     already read `screens[side].safeguard` (combat/modern_side_
--     conditions.lua), so they keep working unchanged.
--   wideguard (moves.ts:20809-20853): Rock, Status, priority +3,
--     `sideCondition`, `condition.duration` 1, `onTryHitPriority` 4.
--     Blocks a move whose target is `allAdjacent` / `allAdjacentFoes`
--     (national_dex's "all-other-pokemon" / "all-opponents") unless
--     `checkMoveBypassesProtect` (battle.ts:1300) lets it through --
--     which for this call (blockStatus defaults true) needs the move's
--     own `protect` flag plus no HitProtect veto. `onHitSide` adds
--     `stall` to the source.
--   quickguard (moves.ts:14490-14534): Fighting, Status, priority +3,
--     duration 1. Blocks a move whose EFFECTIVE priority is > 0.1 --
--     the comment is explicit that Prankster/Gale Wings boosts count,
--     so the live `Battle:movePriority(moveId, attacker)` is the right
--     read -- again gated on the move's `protect` flag. `onHitSide`
--     adds `stall`.
--   craftyshield (moves.ts:3143-3172): Fairy, Status, priority +3,
--     duration 1, `onTryHitPriority` 3. Blocks `move.category ===
--     'Status'` unless the target is `self` or `all` -- and, notably,
--     WITHOUT any checkMoveBypassesProtect call, so even a bypassing
--     move is not exempt here.
--   matblock (moves.ts:10984-11033): Fighting, Status, priority 0,
--     duration 1, `onTryHitPriority` 3, `isNonstandard: Past`. Blocks
--     any non-`self` move that `checkMoveBypassesProtect(..., false)`
--     lets through -- with blockStatus false that means only a
--     NON-Status move carrying the `protect` flag. `onTry` fails when
--     `source.activeMoveActions > 1` ("only works on your first turn
--     out").
--   futuresight (moves.ts:6392-6424) / doomdesire (moves.ts:3847-3879):
--     both `onTry` add a `futuremove` slot condition to the TARGET's
--     side (fails if one is already there) and return NOT_FAIL -- no
--     immediate damage. The slot condition (conditions.ts:379-425)
--     stores the move/source, sets `endingTurn = turn - 1 + 2`, and on
--     end removes Protect/Endure then lands the hit against whoever is
--     in the slot. Damage is NOT stored: it is recomputed at resolution
--     from the original source's stats against the current occupant.
--     Future Sight is Psychic 120 Special, Doom Desire Steel 140
--     Special.
--   present (moves.ts:13920-13942): Normal, Physical, power 0, accuracy
--     90. `onModifyMove` rolls `random(10)`: < 2 (20%) heals the target
--     `[1,4]` and infiltrates; else basePower 40 / 80 / 120. Physical,
--     so the base-power override replaces the recorded 0.
--   firstimpression (moves.ts:5474-5490): Bug, Physical, priority +2,
--     `onTry` fails when `source.activeMoveActions > 1`.
--   grassyglide (moves.ts:7656-7668): Grass, Physical, priority 0,
--     `onModifyPriority` +1 while `field.isTerrain('grassyterrain')` and
--     `source.isGrounded()`. Its damage is already native -- only the
--     priority is missing, so this file adds no move record for it.
--   hail (moves.ts:8070-8084): deliberately DEFERRED. This mod's own
--     combat/modern_weather.lua header records the standing instruction
--     that "we won't bring hail yet" -- Snow (Snowscape) is Gen 9's real
--     replacement and is the only Ice weather this mod builds. HAIL stays
--     unwired, on purpose, rather than shipping a second Ice weather that
--     every Ice-ability switch-in would then have to disambiguate.
--
-- ENGINE SEAMS (all already exist; this file adds no second turn model):
--   * Guard state is per-SIDE (`battle.g9Guards[side]`), created lazily,
--     cleared at each `battle.turn_ended` -- Showdown's duration-1 side
--     conditions tick at the owner's side residual.
--   * A blocked move is nullified through the same `Battle.moveEffectFor`
--     substitution seam combat/modern_combat_protect.lua Part D and
--     combat/modern_action_order.lua's fail gate already established: for
--     the one native call the move's own effect record is replaced by a
--     `kind="primary"` record whose `run` emits the guard line, so PP is
--     still spent and "X used Y!" is still announced (gen2/Battle.lua:
--     1464 announcement, :1750 the dispatch that a `run` record
--     pre-empts).
--   * Safeguard forwards to the base engine's own EFFECT_SAFEGUARD.
--   * Future Sight / Doom Desire are scheduled on the battle object and
--     resolved at `battle.turn_ended`, using the engine's own Damage.calc
--     (the same call the native EFFECT_FUTURE_SIGHT makes) and
--     `Battle:dealDamage`. The base engine's native EFFECT_FUTURE_SIGHT
--     (gen2/Battle.lua:2487) is already shadowed by national_dex today
--     and stores on the USER's volatile with a 4-turn fuse; this file
--     deliberately implements the shared, current-Showdown 2-turn fuse
--     for BOTH moves instead, the same "cross-gen rule prefers the
--     current Showdown behaviour" call modern_weather.lua documented for
--     its own starters.
--   * Present rides `registerPowerOverride` (base power) plus one
--     `battle.damage` wrap (the heal tier), and styles Grassy Glide
--     through `registerPriorityModifier`.
--
-- Gen 1: inert. Every move wired here is a modern/Gen-2 id and this mod's
-- production target is Gen 2 only.
return function(mod)
  -- Gen 1 has no Gen-2 Battle class and the sandbox refuses the name there
  -- (src/mods/Loader.lua crossGenerationDenial). Guarded like modern_combat's
  -- own gen2 require so this file boots on Gen 1 and can still register its
  -- First Impression SELECTION gate (round 100); `Battle` is nil on Gen 1, so
  -- the Gen-2 useMove / guard wraps below are skipped -- Gen 1 resolves through
  -- BattleState:performMove, a path they never covered.
  local gen2Ok, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok and Battle or nil
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
  local moveFlags = nationalDex and nationalDex.exports and nationalDex.exports.moveFlags

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local sideOfWho = mod.exports.sideOfWho
  local curTypesOf = mod.exports.curTypesOf
  local MoveCategory = mod.exports.MoveCategory
  local registerFailGate = mod.exports.registerFailGate
  local registerPriorityModifier = mod.exports.registerPriorityModifier
  local registerPowerOverride = mod.exports.registerPowerOverride
  assert(normalize and displayNameFor and sideOfWho,
    "modern_side_protection: combat/modern_combat.lua must load first")
  assert(registerFailGate and registerPriorityModifier and registerPowerOverride,
    "modern_side_protection: combat/turn_order.lua and combat/modern_action_order.lua must load first")

  ------------------------------------------------------------------
  -- Shared helpers (same unwrap/name idioms the rest of this mod uses).
  ------------------------------------------------------------------
  local function emit(battle, text)
    if battle and battle.emit then
      battle:emit({ kind = "message", text = text })
    end
  end

  local function rawMon(who)
    return who and (who.mon or who) or nil
  end

  local function nameOf(battle, who)
    if displayNameFor then
      local ok, n = pcall(displayNameFor, battle, who, true)
      if ok and n then return n end
    end
    local m = rawMon(who)
    return (m and (m.name or m.species)) or "The Pokemon"
  end

  local function otherSide(side)
    return side == "enemy" and "player" or "enemy"
  end

  local function moveInfo(moveId)
    if not (moveById and moveId) then return nil end
    local ok, info = pcall(moveById, moveId)
    if ok and type(info) == "table" then return info end
    return nil
  end

  local function hasFlag(moveId, flag)
    if not (moveFlags and moveId) then return false end
    local ok, flags = pcall(moveFlags, moveId)
    if not ok or type(flags) ~= "table" then return false end
    return flags[flag] == true
  end

  local function categoryOf(def)
    if not (MoveCategory and MoveCategory.of and def) then return nil end
    local ok, cat = pcall(MoveCategory.of, def)
    if ok then return cat end
    return nil
  end

  local function isStatusMove(def)
    local cat = categoryOf(def)
    if cat ~= nil then return cat == "Status" end
    -- Fall back to "no base power" when the category helper is absent.
    return def ~= nil and (def.power or 0) <= 0
  end

  local function targetOf(battle, moveId, def)
    local info = moveInfo(moveId)
    if info and info.target then return info.target end
    if def and def.target then return def.target end
    if battle and battle.moveDef then
      local ok, live = pcall(function() return battle:moveDef(moveId) end)
      if ok and live and live.target then return live.target end
    end
    return nil
  end

  -- The same "grounded" read combat/modern_terrain.lua's own isGrounded
  -- uses (Phase 8 Gravity's gravityGrounded field plus the Flying type).
  local function isGrounded(who)
    local m = rawMon(who)
    if m and m.gravityGrounded then return true end
    if curTypesOf then
      for _, t in ipairs(curTypesOf(who, true)) do
        if t == "FLYING" then return false end
      end
    end
    return true
  end

  ------------------------------------------------------------------
  -- GUARD STATE -- one table per side, duration 1, cleared at turn end.
  ------------------------------------------------------------------
  local function guardsOf(battle, side)
    battle.g9Guards = battle.g9Guards or { player = {}, enemy = {} }
    battle.g9Guards[side] = battle.g9Guards[side] or {}
    return battle.g9Guards[side]
  end

  ------------------------------------------------------------------
  -- guardBlockReason(battle, attacker, defender, moveId) -> key | nil.
  -- Pure decision function (exported so the harness can exercise every
  -- branch without standing up the damage pipeline). `key` is one of
  -- "wideguard"/"quickguard"/"craftyshield"/"matblock".
  --
  -- The order mirrors Showdown's onTryHitPriority (Wide Guard 4, Quick
  -- Guard 4, Crafty Shield 3, Mat Block 3); the two priority-4 shields
  -- are checked first. `defender ~= attacker` is the singles stand-in
  -- for every "target === 'self'" early-return in those condition
  -- blocks (Crafty Shield's `['self','all'].includes(move.target)` and
  -- Mat Block's `move.target === 'self'`), and `target ~= "user"` /
  -- `target ~= "all-pokemon"` additionally exempts a real field-wide
  -- status move whose resolved `defender` is still the other battler.
  ------------------------------------------------------------------
  local function guardBlockReason(battle, attacker, defender, moveId)
    if not (battle and attacker and defender and defender ~= attacker and moveId) then
      return nil
    end
    local side = sideOfWho(battle, defender, true)
    local guards = battle.g9Guards and battle.g9Guards[side]
    if not guards then return nil end

    local def
    if battle.moveDef then
      local ok, live = pcall(function() return battle:moveDef(moveId) end)
      if ok then def = live end
    end
    -- Feint / Z-Moves (this mod's own bypassesProtect marker) ignore the
    -- whole shield family, exactly like they ignore Protect.
    if def and def.bypassesProtect then return nil end

    -- Unseen Fist (contact) / Piercing Drill carve-out, the same one
    -- combat/modern_combat_protect.lua Part B applies to Protect itself.
    local abilityIdOf = mod.exports.abilityIdOf
    local makesContact = mod.exports.makesContact
    if makesContact and makesContact(moveId, attacker) then
      if abilityIdOf and abilityIdOf(attacker) == "UNSEENFIST" then return nil end
    end

    local flagProtect = hasFlag(moveId, "protect")
    local target = targetOf(battle, moveId, def)
    local status = isStatusMove(def)

    if guards.wideGuard
        and (target == "all-other-pokemon" or target == "all-opponents")
        and flagProtect then
      return "wideguard"
    end

    if guards.quickGuard and flagProtect and battle.movePriority then
      local ok, prio = pcall(function() return battle:movePriority(moveId, attacker) end)
      if ok and type(prio) == "number" and prio > 0.1 then
        return "quickguard"
      end
    end

    if guards.craftyShield and status
        and target ~= "user" and target ~= "all-pokemon" then
      return "craftyshield"
    end

    if guards.matBlock and not status
        and target ~= "user" and flagProtect then
      return "matblock"
    end

    return nil
  end
  mod.exports.guardBlockReason = guardBlockReason

  ------------------------------------------------------------------
  -- The four guard moves themselves. Each is a power-0 status move, so
  -- a kind="primary" record with a run sets the side flag and announces
  -- it, exactly like modern_weather's weatherStarter. Wide Guard / Quick
  -- Guard also feed the shared Protect stall chain (Showdown's own
  -- onHitSide).
  --
  -- Mat Block's first-turn-out rule is checked INSIDE run (after native
  -- useMove has already emitted battle.move_used and incremented
  -- __g9MoveActions), so the count already includes this use and `> 1`
  -- is literally Showdown's `source.activeMoveActions > 1`. (The
  -- fail-gate seam used by First Impression below runs one step
  -- EARLIER, before that increment, so it needs the equivalent `> 0`.)
  ------------------------------------------------------------------
  local GUARDS = {
    WIDEGUARD = {
      effect = "G9_WIDEGUARD_EFFECT", key = "wideGuard", stall = true,
      start = "Wide Guard protects the team!", blocked = "Wide Guard protected the team!",
    },
    QUICKGUARD = {
      effect = "G9_QUICKGUARD_EFFECT", key = "quickGuard", stall = true,
      start = "Quick Guard protects the team!", blocked = "Quick Guard protected the team!",
    },
    CRAFTYSHIELD = {
      effect = "G9_CRAFTYSHIELD_EFFECT", key = "craftyShield",
      start = "Crafty Shield protects the team!", blocked = "Crafty Shield protected the team!",
    },
    MATBLOCK = {
      effect = "G9_MATBLOCK_EFFECT", key = "matBlock",
      start = "Mat Block protects the team!", blocked = "Mat Block protected the team!",
    },
  }
  do
    for guardMoveId, cfg in pairs(GUARDS) do
      mod.content.move_effects:register(cfg.effect, {
        kind = "primary",
        run = function(a, b, c)
          local n = normalize(a, b, c)
          local battle, user = n.battle, n.user
          if not (battle and user) then return end
          if guardMoveId == "MATBLOCK" then
            -- moves.ts:11003 `if (source.activeMoveActions > 1)`.
            local mu = user.mon or user
            if (mu.__g9MoveActions or 0) > 1 then
              emit(battle, Strings("But it failed!"))
              return
            end
          end
          local side = sideOfWho(battle, user, true)
          guardsOf(battle, side)[cfg.key] = true
          if cfg.stall then
            local armStallChain = mod.exports.armStallChain
            if armStallChain then
              local ok, err = pcall(armStallChain, battle, user)
              if not ok then
                mod.log:warn("g9-battle-engine: modern_side_protection: "
                  .. "stall-chain arm failed (%s)", tostring(err))
              end
            end
          end
          emit(battle, Strings(cfg.start))
        end,
      })
      mod.content.moves:patch(guardMoveId, { effect = cfg.effect })
    end
  end

  local GUARD_BLOCK_TEXT = {
    wideguard = "Wide Guard protected the team!",
    quickguard = "Quick Guard protected the team!",
    craftyshield = "Crafty Shield protected the team!",
    matblock = "Mat Block protected the team!",
  }

  ------------------------------------------------------------------
  -- The interception seam: one more Battle.useMove wrap, outermost of
  -- the chain because this file boots last of the combat files. A
  -- blocked move still spends PP and is still announced; only its
  -- effect is swapped for the guard's line (same reasoning and shape as
  -- combat/modern_combat_protect.lua Part D and combat/modern_action_
  -- order.lua's fail gate -- see either file's own header).
  ------------------------------------------------------------------
  -- Gen 2 only: the guard-block useMove wrap. Skipped when the Gen-2 class is
  -- absent (Gen 1).
  if Battle then
  local nativeUseMove = Battle.useMove
  function Battle:useMove(attacker, defender, moveId)
    local reason
    local ok = pcall(function()
      reason = guardBlockReason(self, attacker, defender, moveId)
    end)
    if not ok then reason = nil end
    if not reason then
      return nativeUseMove(self, attacker, defender, moveId)
    end

    local def = self.moveDef and self:moveDef(moveId)
    local gatedEffect = def and def.effect
    if not gatedEffect then
      return nativeUseMove(self, attacker, defender, moveId)
    end

    local prevRecordFor = Battle.moveEffectRecordFor
    Battle.moveEffectRecordFor = function(data, effect)
      if effect == gatedEffect then
        return {
          kind = "primary",
          run = function(battle)
            emit(battle, Strings(GUARD_BLOCK_TEXT[reason]))
          end,
        }
      end
      return prevRecordFor(data, effect)
    end
    local callOk, callErr = pcall(nativeUseMove, self, attacker, defender, moveId)
    Battle.moveEffectRecordFor = prevRecordFor
    if not callOk then
      mod.log:warn("g9-battle-engine: modern_side_protection: "
        .. "guard block errored (%s)", tostring(callErr))
      error(callErr, 0)
    end
  end
  end -- if Battle

  ------------------------------------------------------------------
  -- SAFEGUARD -- forward to the engine's own EFFECT_SAFEGUARD (see the
  -- file header: the whole mechanic is already native). The fallback
  -- mirrors it exactly (fail when already up, otherwise set the native
  -- screen counter and announce) so a build whose MOVE_EFFECTS lacks the
  -- handler still wires the move.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_SAFEGUARD_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local native = Battle and Battle.MOVE_EFFECTS and Battle.MOVE_EFFECTS.EFFECT_SAFEGUARD
      if native then
        local ok = pcall(native, battle, user)
        if ok then return end
      end
      battle.screens = battle.screens or { player = {}, enemy = {} }
      local side = sideOfWho(battle, user, true)
      local screens = battle.screens[side] or {}
      battle.screens[side] = screens
      if (screens.safeguard or 0) > 0 then
        emit(battle, Strings("But it failed!"))
        return
      end
      screens.safeguard = (Battle and Battle.SCREEN_TURNS) or 5
      emit(battle, Strings("%s's team became cloaked in mystical mist!", nameOf(battle, user)))
    end,
  })
  mod.content.moves:patch("SAFEGUARD", { effect = "GALAR_SAFEGUARD_EFFECT" })

  ------------------------------------------------------------------
  -- FUTURE SIGHT / DOOM DESIRE -- scheduled on the target's side, lands
  -- `endingTurn = turn - 1 + 2` later (conditions.ts:383), i.e. one turn
  -- after the use turn as this engine counts turns. Damage is computed
  -- once at schedule time with the engine's own Damage.calc (the same
  -- call the native EFFECT_FUTURE_SIGHT makes) and stored, then applied
  -- to whoever is standing on the side when it lands -- the engine's own
  -- established Future Sight shape; Showdown recomputes at resolution
  -- against the current occupant, a small named difference that only
  -- matters if the target switches (the fused damage would keep the old
  -- target's type matchup).
  ------------------------------------------------------------------
  local FUTURE_MOVES = {
    FUTURESIGHT = {
      effect = "G9_FUTURESIGHT_EFFECT", power = 120, moveType = "PSYCHIC",
      start = "%s foresaw an attack!",
      hit = "%s took the FUTURE SIGHT attack!",
      fail = "The FUTURE SIGHT attack did not hit!",
    },
    DOOMDESIRE = {
      effect = "G9_DOOMDESIRE_EFFECT", power = 140, moveType = "STEEL",
      start = "%s chose a doomed fate!",
      hit = "%s took the DOOM DESIRE attack!",
      fail = "The DOOM DESIRE attack did not hit!",
    },
  }

  local function futureStore(battle, side)
    battle.g9FutureMoves = battle.g9FutureMoves or { player = {}, enemy = {} }
    battle.g9FutureMoves[side] = battle.g9FutureMoves[side] or {}
    return battle.g9FutureMoves[side]
  end

  -- Roll the attack's damage the way gen2/Battle.lua's own
  -- EFFECT_FUTURE_SIGHT does: the engine's real Damage.calc when the data
  -- is available, else a plain base formula so a test/harness battle
  -- still schedules a positive number.
  local function rollFutureDamage(battle, source, target, cfg)
    local sm, tm = rawMon(source), rawMon(target)
    local level = (sm and sm.level) or 1
    local sStats, tStats = (sm and sm.stats) or {}, (tm and tm.stats) or {}
    local function pick(stats, a, b)
      return stats[a] or stats[b]
    end
    local okDamage, Damage = pcall(require, "src.battle.gen2.Damage")
    if okDamage and Damage and Damage.calc then
      local types = battle.data and battle.data.type_chart and battle.data.type_chart.types
      local matchups = battle.matchupsAgainst and battle:matchupsAgainst(target)
      local okCalc, dmg = pcall(Damage.calc, {
        level = level, power = cfg.power, moveType = cfg.moveType,
        attacker = {
          specialAttack = pick(sStats, "spa", "specialAttack"),
          types = (sm and sm.types) or {},
          stages = battle.stages and battle.stages[sideOfWho(battle, source, true)],
        },
        defender = {
          specialDefense = pick(tStats, "spd", "specialDefense"),
          types = (tm and tm.types) or {},
          stages = battle.stages and battle.stages[sideOfWho(battle, target, true)],
        },
        types = types, matchups = matchups, random = battle.random,
      })
      if okCalc and type(dmg) == "number" and dmg > 0 then return dmg end
    end
    local atk = pick(sStats, "spa", "specialAttack") or 1
    local dfn = pick(tStats, "spd", "specialDefense") or 1
    local d = math.floor(math.floor(2 * level / 5) + 2)
    d = math.floor(math.floor(d * cfg.power * atk / math.max(1, dfn)) / 50) + 2
    return math.max(1, d)
  end

  do
    for futureMoveId, cfg in pairs(FUTURE_MOVES) do
      mod.content.move_effects:register(cfg.effect, {
        kind = "primary",
        run = function(a, b, c)
          local n = normalize(a, b, c)
          local battle, user, target = n.battle, n.user, n.target
          if not (battle and user) then return end
          if not target or target == user then
            target = battle.enemy or battle.player
          end
          if not target then return end
          local side = sideOfWho(battle, target, true)
          local list = futureStore(battle, side)
          if #list > 0 then
            emit(battle, Strings("But it failed!"))
            return
          end
          list[#list + 1] = {
            move = futureMoveId,
            source = user,
            damage = rollFutureDamage(battle, user, target, cfg),
            resolveTurn = (battle.turn or 0) + 1,
          }
          emit(battle, Strings(cfg.start, nameOf(battle, user)))
        end,
      })
      mod.content.moves:patch(futureMoveId, { effect = cfg.effect })
    end
  end

  local function resolveFutureMoves(battle)
    local stores = battle.g9FutureMoves
    if not stores then return end
    local turn = battle.turn or 0
    for _, side in ipairs({ "player", "enemy" }) do
      local list = stores[side]
      if list and #list > 0 then
        local keep = {}
        for _, fm in ipairs(list) do
          if turn >= (fm.resolveTurn or 0) then
            local cfg = FUTURE_MOVES[fm.move] or {}
            local target = battle[side]
            if (not target) or (target.hp or 0) <= 0 or target == fm.source then
              emit(battle, Strings(cfg.fail or "The attack did not hit!"))
            else
              -- conditions.ts:394-395: the future attack strips Protect
              -- and Endure before landing.
              if battle.volatile then
                local vol = battle:volatile(target)
                if vol then vol.endure = nil end
              end
              target.protected = nil
              target.maxGuarded = nil
              emit(battle, Strings(cfg.hit or "%s was hit!", nameOf(battle, target)))
              if battle.dealDamage then
                battle:dealDamage(fm.source, target, fm.damage or 1, {})
              else
                target.hp = math.max(0, (target.hp or 0) - (fm.damage or 1))
              end
            end
          else
            keep[#keep + 1] = fm
          end
        end
        stores[side] = keep
      end
    end
  end
  mod.exports.resolveFutureMoves = resolveFutureMoves

  ------------------------------------------------------------------
  -- PRESENT -- the 10-way roll: 20% heal the target 1/4, else 40/80/120
  -- base power. Rolled once per use (on battle.move_used, before the
  -- damage path) and cached on the user, so the override and the heal
  -- branch read the SAME number -- Showdown rolls once in onModifyMove.
  ------------------------------------------------------------------
  registerPowerOverride("PRESENT", function(ctx)
    local roll = (ctx.user and ctx.user.__g9PresentRoll) or 0
    if roll < 2 then return 0 end
    if roll < 6 then return 40 end
    if roll < 9 then return 80 end
    return 120
  end)

  mod.events:on("battle.move_used", function(ev)
    if not (ev and ev.battle and ev.user) then return end
    if ev.moveId ~= "PRESENT" then return end
    local r = ev.battle.random
    ev.user.__g9PresentRoll = (r and r(10)) or 0
  end)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    if ctx and ctx.move and ctx.move.id == "PRESENT" and ctx.user and ctx.target then
      local roll = ctx.user.__g9PresentRoll
      if type(roll) == "number" and roll >= 0 and roll < 2 then
        local m = rawMon(ctx.target)
        local stats = m and m.stats
        local maxHp = (stats and stats.hp) or (m and m.maxHp)
        if m and maxHp and maxHp > 0 then
          local amount = math.max(1, math.floor(maxHp / 4))
          local tryHeal = mod.exports.g9TryHeal
          if tryHeal then
            if tryHeal(ctx.battle, ctx.target, amount) > 0 then
              emit(ctx.battle, Strings("%s regained health!", nameOf(ctx.battle, ctx.target)))
            end
          else
            m.hp = math.min(maxHp, (m.hp or 0) + amount)
            emit(ctx.battle, Strings("%s regained health!", nameOf(ctx.battle, ctx.target)))
          end
        end
        -- Deals no damage at all in the heal tier.
        return 0, { crit = false, typeMult = 1 }
      end
    end
    return next(ctx)
  end, 45)

  ------------------------------------------------------------------
  -- FIRST IMPRESSION -- "only works on the first turn out". Registered
  -- through the shared registerFailGate seam, which runs BEFORE native
  -- useMove emits battle.move_used -- so at gate time __g9MoveActions
  -- holds COMPLETED move actions only, and the Showdown test
  -- (`activeMoveActions > 1`, i.e. completed + 1 > 1) is completed > 0.
  ------------------------------------------------------------------
  local function firstImpressionBlocked(attacker)
    -- Unwrap the Gen-1 battler wrapper to the RAW mon -- the same table
    -- modern_action_order.lua's bookkeeping writes and move_usability.lua reads.
    local m = attacker and (attacker.mon or attacker) or nil
    return (m and m.__g9MoveActions or 0) > 0
  end
  registerFailGate("FIRSTIMPRESSION", function(battle, attacker, defender, moveId)
    if firstImpressionBlocked(attacker) then return "fail" end
    return nil
  end)

  -- The same condition, answered at SELECTION time for a battle scene
  -- (round 100): combat/move_usability.lua's registerMoveUsabilityGate, the
  -- menu-side twin of registerFailGate. Guarded so an older/trimmed boot
  -- (no move_usability) simply keeps the resolution-time failure.
  local registerMoveUsabilityGate = mod.exports.registerMoveUsabilityGate
  if registerMoveUsabilityGate then
    registerMoveUsabilityGate("FIRSTIMPRESSION", function(battle, mon)
      if firstImpressionBlocked(mon) then
        return { flag = "condition",
          reason = Strings("First Impression only works on the user's first turn out!") }
      end
      return nil
    end)
  end

  ------------------------------------------------------------------
  -- GRASSY GLIDE -- priority +1 on Grassy Terrain while grounded. Its
  -- damage is already native, so only the priority modifier is added.
  ------------------------------------------------------------------
  registerPriorityModifier("grassy_glide", function(battle, moveId, caster, def)
    if moveId ~= "GRASSYGLIDE" then return 0 end
    if not (battle and battle.terrain == "GRASSY") then return 0 end
    if not isGrounded(caster) then return 0 end
    return 1
  end)

  ------------------------------------------------------------------
  -- Turn-end cleanup: the duration-1 guards expire, and any due future
  -- attack lands. Also re-seated clean on battle.started (a battle
  -- object is per-battle, so this is belt-and-braces, but it keeps a
  -- reused test battle honest).
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    if battle.g9Guards then
      for _, side in ipairs({ "player", "enemy" }) do
        local g = battle.g9Guards[side]
        if g then
          g.wideGuard = nil
          g.quickGuard = nil
          g.craftyShield = nil
          g.matBlock = nil
        end
      end
    end
    resolveFutureMoves(battle)
  end)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    battle.g9Guards = { player = {}, enemy = {} }
    battle.g9FutureMoves = { player = {}, enemy = {} }
  end)

  mod.log:info("g9-battle-engine: modern_side_protection installed "
    .. "(SAFEGUARD, WIDEGUARD, QUICKGUARD, CRAFTYSHIELD, MATBLOCK, "
    .. "FUTURESIGHT, DOOMDESIRE, PRESENT, FIRSTIMPRESSION, GRASSYGLIDE; "
    .. "HAIL deliberately deferred)")
end
