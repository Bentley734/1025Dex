-- Phase 9 of the missing-effects pipeline: trapping additions.
--
-- Showdown source of truth (scratch/showdown/moves.ts -- read by direct
-- extraction this session; line numbers cited per clause):
--   meanlook (11493-11510): Normal, Status, basePower 0, accuracy true,
--     flags { reflectable, mirror, metronome }, `onHit(target, source) ->
--     target.addVolatile('trapped', source, move, 'trapper')`.
--   block (1511-1527): Normal, Status, basePower 0, accuracy true, the same
--     onHit as Mean Look.
--   spiderweb (17467-17484): Bug, Status, basePower 0, accuracy true, the
--     same onHit again.
--   jawlock (9790-9802): Dark, Physical, 80 BP, accuracy 100,
--     flags { contact, protect, mirror, metronome, bite }, onHit ->
--     `source.addVolatile('trapped', target, ...)` AND
--     `target.addVolatile('trapped', source, ...)` -- BOTH sides pinned.
--   anchorshot (376-395): Steel, Physical, 80 BP, accuracy 100,
--     `secondary: { chance: 100, onHit -> target.addVolatile('trapped',
--     source, ...) if source.isActive }`.
--   spiritshackle (17621-17638): Ghost, Physical, 80 BP, accuracy 100, the
--     identical secondary to Anchor Shot.
--   octolock (12961-12993): Fighting, Status, basePower 0, accuracy 100,
--     `onTryImmunity(target) -> this.dex.getImmunity('trapped', target)`
--     (so Octolock FAILS outright against a natural trapping-immune target),
--     `volatileStatus: 'octolock'`, whose condition.onStart emits
--     `-start move: Octolock`, onResidualOrder 14, and onResidual lowers
--     `{ def: -1, spd: -1 }` on the holder while the source is active (else
--     deletes the volatile with a [silent] -end).
--
-- WHY THESE ARE NOT `GALAR_TRAP_EFFECT`. The `trapped` volatile itself
-- (scratch/showdown/conditions.ts:208-216) has NO chip damage and NO
-- duration -- it only pins the holder (onTrapPokemon -> pokemon.tryTrap()).
-- That is genuinely different from `partiallytrapped` (conditions.ts:222-253,
-- the 1/8-per-turn chip family: Wrap/Bind/Fire Spin/Whirlpool/...), which
-- this mod already models through GALAR_TRAP_EFFECT's native `wrapCount`
-- (main.lua:516-556). Routing a pin move through GALAR_TRAP_EFFECT would
-- hand it an unearned per-turn chip, so these use the engine's own pin
-- instead (below).
--
-- `pokemon.tryTrap` (pokemon.ts:1607-1611):
--     if (!this.runStatusImmunity('trapped')) return false;
-- i.e. a natural immunity to `trapped` (Ghost, Gen 6+) silently refuses the
-- pin. The mod's own Octolock entry therefore fails outright against such a
-- target (its real onTryImmunity`), and the others simply do not pin it.
--
-- DESIGN -- the game's own pin is `Battle:switchLocked` (gen2/Battle.lua:
-- 4010-4013), which returns true when its target's volatile carries
-- `trapsTarget`; the canonical setter is native `EFFECT_MEAN_LOOK`
-- (:2879-2888, `self:volatile(attacker).trapsTarget = true`), and
-- `Battle:breakTrapsOnSend` (:4000-4005) clears the opponent's `trapsTarget`
-- on a send -- so the pin follows the trapper mon exactly as it should: it
-- dies with the trapper, and a fresh send on the trapped side clears it.
-- Writing that same, real field is therefore the faithful port.
--
-- Gen 1 has no switch gate at all (see abilities/engine/trap_abilities.lua's
-- own header: there is no "can I switch" choke point upstream of
-- `resolveSwitch`), so the Gen 1 half records a marker on the target and
-- documents the gap rather than faking a refusal -- the same honest partial
-- GMAX.TERROR already uses (gigantamax/max_move_subeffects.lua:610-622).
--
-- Datagen note: MEANLOOK and SPIDERWEB are the canonical native pin moves,
-- and national_dex leaves both at `effect = "EFFECT_NORMAL_HIT"` with
-- `effectModeled = false` (registry_gen2.lua:460 and :711), so they are just
-- as dead here as Block/Octolock. They are wired in this same phase because
-- they are literally the same mechanic, not left as a second-class gap.
return function(mod)
  local Strings = require("src.core.Strings")
  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local sideOfWho = mod.exports.sideOfWho
  local isGen2Battle = mod.exports.isGen2Battle
  local curTypesOf = mod.exports.curTypesOf
  local changeStage = mod.exports.changeStage
  assert(normalize and displayNameFor and sideOfWho and isGen2Battle,
    "modern_trap_moves: combat/modern_combat.lua must load first")
  assert(curTypesOf and changeStage,
    "modern_trap_moves: combat/modern_combat.lua must load first")

  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil

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

  -- The mon opposing `who` -- the native 1v1 default target when a primary
  -- run handler was handed no explicit defender.
  local function opposingActive(battle, who)
    if not (battle and who) then return nil end
    local side = sideOfWho(battle, who, true)
    return side == "player" and battle.enemy or battle.player
  end

  local function fail(battle)
    emit(battle, Strings("But it failed!"))
  end

  ------------------------------------------------------------------
  -- The `trapped` pin. On Gen 2 this is the native field itself; on Gen 1 the
  -- marker is recorded on the trapped mon (see this file's header).
  ------------------------------------------------------------------
  -- Natural trapping immunity (`pokemon.tryTrap` -> `runStatusImmunity
  -- ('trapped')` -> `dex.getImmunity('trapped')`, pokemon.ts:1607-1611):
  -- Ghost-types are immune to being trapped as of Gen 6, which is the
  -- mechanics generation this mod ports. Nil-safe because a harness/species
  -- record without a live type read must not crash the trap path.
  local function cannotBeTrapped(mon, gen2)
    local m = rawMon(mon)
    if type(m) ~= "table" then return false end
    if type(curTypesOf) ~= "function" then return false end
    local ok, types = pcall(curTypesOf, m, gen2)
    if not ok or type(types) ~= "table" then return false end
    for _, t in ipairs(types) do
      if t == "GHOST" then return true end
    end
    return false
  end
  mod.exports.trapCannotBeTrapped = cannotBeTrapped

  -- Has `trapper` already pinned `target`? (Showdown's `addVolatile` returns
  -- false when the volatile is already present, which is what makes Block /
  -- Mean Look / Spider Web / Octolock fail on a recast.)
  local function isPinned(battle, trapper, target, gen2)
    if not (battle and trapper and target) then return false end
    if not gen2 then
      local m = rawMon(target)
      return type(m) == "table" and m.g9Trapped ~= nil
    end
    return battle:volatile(trapper).trapsTarget == true
  end
  mod.exports.trapIsPinned = isPinned

  -- Publish the real pin. Returns true when this call actually applied it.
  local function pin(battle, trapper, target, gen2)
    if not (battle and trapper and target) then return false end
    if cannotBeTrapped(target, gen2) then return false end
    if isPinned(battle, trapper, target, gen2) then return false end
    if not gen2 then
      local m = rawMon(target)
      if type(m) == "table" then m.g9Trapped = rawMon(trapper) or true end
    else
      -- gen2/Battle.lua:2884 -- the exact native write.
      battle:volatile(trapper).trapsTarget = true
    end
    return true
  end
  mod.exports.trapApplyPin = pin

  -- Is `mon` one of the battlers currently on the field? Used by Octolock's
  -- residual to mirror Showdown's `source.isActive` check; consults the real
  -- N-way roster first so a scene battle is covered, then the native pair.
  local function isOnField(battle, mon)
    if not (battle and mon) then return false end
    if mon == battle.player or mon == battle.enemy then return true end
    local all = mod.exports.allActiveBattlers
    if type(all) ~= "function" then return false end
    local ok, list = pcall(all, battle)
    if not ok or type(list) ~= "table" then return false end
    for _, who in ipairs(list) do
      if rawMon(who) == mon then return true end
    end
    return false
  end

  -- Every mon that could be carrying a mod-owned per-mon trap field: the live
  -- N-way roster when the scene exposes one, plus both party arrays so a
  -- benched holder can never be silently skipped. pcall-guarded as a whole,
  -- the same reason status_condition_cleanup.lua's sweep is.
  local function trapRoster(battle)
    local out, seen = {}, {}
    local function add(who)
      local m = rawMon(who)
      if type(m) == "table" and not seen[m] then
        seen[m] = true
        out[#out + 1] = m
      end
    end
    add(battle.player)
    add(battle.enemy)
    for _, party in ipairs({ battle.party, battle.enemyParty, battle.playerParty }) do
      if type(party) == "table" then
        for i = 1, #party do add(party[i]) end
      end
    end
    local all = mod.exports.allActiveBattlers
    if type(all) == "function" then
      pcall(function()
        for _, who in ipairs(all(battle) or {}) do add(who) end
      end)
    end
    return out
  end

  ------------------------------------------------------------------
  -- MEAN LOOK / BLOCK / SPIDER WEB -- a plain status pin, the exact native
  -- Mean Look mechanic (Share no wrapper: kind="primary", run). The record is
  -- shared by all three; the move id is irrelevant to the pin itself.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_TRAP_PIN_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not battle then return end
      local target = n.target or opposingActive(battle, user)
      if not (user and target) then return end
      -- Native EFFECT_MEAN_LOOK's own repeat/vanished guard (Battle.lua:2880
      -- -2883): already pinned -> fail; a vanished (Fly/Dig) target can't be
      -- caught either. Showdown's Ghost immunity (`cannotBeTrapped`) folds
      -- into the same failure.
      if cannotBeTrapped(target, n.gen2) or isPinned(battle, user, target, n.gen2) then
        return fail(battle)
      end
      pin(battle, user, target, n.gen2)
      emit(battle, Strings("%s can't escape now!", displayNameFor(battle, target, n.gen2)))
    end,
  })

  ------------------------------------------------------------------
  -- OCTOLOCK -- pin + a real Def/SpD -1 residual while the source is active.
  -- The volatile lives on the holder as direct fields (`octolockActive` /
  -- `octolockSource`), so combat/status_condition_cleanup.lua's SWITCH_SCOPED
  -- list can drop it on a switch-out exactly like every other mod volatile.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_OCTOLOCK_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not battle then return end
      local target = n.target or opposingActive(battle, user)
      if not (user and target) then return end
      local m = rawMon(target)
      if type(m) ~= "table" then return end
      -- Showdown's onTryImmunity: Octolock fails outright against a natural
      -- trapping immunity, and re-adding the volatile on a holder that
      -- already has it also fails (addVolatile returns false).
      if cannotBeTrapped(target, n.gen2) or m.octolockActive then
        return fail(battle)
      end
      pin(battle, user, target, n.gen2)
      m.octolockActive = true
      m.octolockSource = rawMon(user)
      emit(battle, Strings("%s can't escape now!", displayNameFor(battle, target, n.gen2)))
    end,
  })

  -- onResidualOrder 14: def -1 / spd -1 each end of turn while the source is
  -- still on the field and alive; otherwise the volatile ends silently
  -- (`-end ... '[partiallytrapped]', '[silent]'` -- no message).
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local gen2 = isGen2Battle(battle)
    for _, m in ipairs(trapRoster(battle)) do
      if m.octolockActive then
        local src = m.octolockSource
        local srcAlive = src and (src.hp or 0) > 0 and isOnField(battle, src)
        if not srcAlive then
          m.octolockActive, m.octolockSource = nil, nil
        else
          for _, stat in ipairs({ "defense", "spd" }) do
            local lines = changeStage(battle, m, stat, -1, true, gen2)
            for _, line in ipairs(lines or {}) do emit(battle, line) end
          end
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- JAWLOCK / ANCHOR SHOT / SPIRIT SHACKLE -- DAMAGING pins. The trap only
  -- applies on a landed, non-zero hit, so these carry an empty kind="full"
  -- record (invisible to Gen 2's `if handler then handler(); return`
  -- pre-emption -- gen2/Battle.lua:1750-1755) and the pin rides the real
  -- battle.damage_dealt event, the exact Rapid Spin precedent
  -- (combat/modern_hazards.lua:295-300). A Substitute soaks the hit inside
  -- Battle:dealDamage BEFORE that event is emitted, so a subbed target is
  -- correctly never pinned.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_JAWLOCK_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GALAR_ANCHORSHOT_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GALAR_SPIRITSHACKLE_EFFECT", { kind = "full" })

  -- Which damaging moves pin, and whether they pin their own user too.
  -- Jaw Lock's real onHit adds the volatile to BOTH mons (moves.ts:9799-9801).
  local DAMAGE_TRAPS = {
    JAWLOCK = { both = true },
    ANCHORSHOT = {},
    SPIRITSHACKLE = {},
  }

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local moveId = ev.moveId or (ev.move and ev.move.id)
    local spec = moveId and DAMAGE_TRAPS[moveId]
    if not spec then return end
    local target, user = ev.target, ev.user
    if not (target and user) then return end
    if (ev.damage or 0) <= 0 then return end
    local gen2 = isGen2Battle(battle)
    local applyOk, err = pcall(function()
      if pin(battle, user, target, gen2) then
        emit(battle, Strings("%s can't escape now!", displayNameFor(battle, target, gen2)))
      end
      if spec.both and pin(battle, target, user, gen2) then
        emit(battle, Strings("%s can't escape now!", displayNameFor(battle, user, gen2)))
      end
    end)
    if not applyOk then
      mod.log:warn("g9-battle-engine: modern_trap_moves: damage pin failed: %s",
        tostring(err))
    end
  end)

  -- National Dex owns every one of these moves' base stats; only the effect
  -- slot is repointed here. The pin status moves get their bespoke record;
  -- the damaging ones get an empty kind="full" record so the damage path is
  -- untouched and the trap rides the damage_dealt listener above.
  mod.content.moves:patch("MEANLOOK", { effect = "GALAR_TRAP_PIN_EFFECT" })
  mod.content.moves:patch("BLOCK", { effect = "GALAR_TRAP_PIN_EFFECT" })
  mod.content.moves:patch("SPIDERWEB", { effect = "GALAR_TRAP_PIN_EFFECT" })
  mod.content.moves:patch("OCTOLOCK", { effect = "GALAR_OCTOLOCK_EFFECT" })
  mod.content.moves:patch("JAWLOCK", { effect = "GALAR_JAWLOCK_EFFECT" })
  mod.content.moves:patch("ANCHORSHOT", { effect = "GALAR_ANCHORSHOT_EFFECT" })
  mod.content.moves:patch("SPIRITSHACKLE", { effect = "GALAR_SPIRITSHACKLE_EFFECT" })

  mod.log:info("g9-battle-engine: modern_trap_moves installed "
    .. "(MEANLOOK, BLOCK, SPIDERWEB, JAWLOCK, ANCHORSHOT, SPIRITSHACKLE, OCTOLOCK)")
end
