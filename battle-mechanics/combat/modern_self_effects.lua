-- Phase 23 of the missing-effects pipeline: the `self:`-directed move
-- effects -- recharge, selfdestruct, mind-blown recoil, the Glaive Rush
-- drawback volatile, the LGPE screen setters and Sparkly Swirl's team cure.
--
-- Showdown source of truth (scratch/showdown/*.ts -- read by direct
-- extraction, line numbers cited per clause):
--   * recharge: blastburn (moves.ts:1414, `self: {volatileStatus:
--     'mustrecharge'}` at :1424), frenzyplant (:6243/:6253), gigaimpact
--     (:6574/:6584), hydrocannon (:9056/:9066), meteorassault
--     (:11724/:11735), prismaticlaser (:13946/:13956), roaroftime
--     (:15173/:15183), rockwrecker (:15308/:15318). The volatile
--     (conditions.ts:364-379) blocks the holder's next move
--     (onBeforeMovePriority 11, "X must recharge!") and is consumed the
--     turn it fires. There is NO "skip recharge when the target faints"
--     clause in current Showdown -- that skip was a Gen 1-only rule.
--   * mindblown (moves.ts:11877) / steelbeam (:17877): both carry
--     `mindBlownRecoil: true` plus an `onMoveFail` that applies
--     `Math.round(source.maxhp / 2)`; battle-actions.ts:1382 is the
--     hit-path half (`recoilDamage = Math.round(pokemon.maxhp / 2)`).
--     So the user loses half its MAX HP once the move resolves -- hit OR
--     miss/fail/immune. Magic Guard blocks that loss (its onDamage
--     refuses any effect whose effectType is not 'Move',
--     abilities.ts:2465-2472 -- this recoil's effect is the move's own
--     Condition), Rock Head does NOT (it only refuses
--     `effect.id === 'recoil'`, abilities.ts:3906-3912).
--   * mistyexplosion (moves.ts:12133): `selfdestruct: "always"`
--     (battle-actions.ts:500 -- the user faints when the move is used,
--     regardless of accuracy/Protect/immunity), plus its own
--     `onBasePower` (:12143) 1.5x while the field is Misty Terrain and
--     the source is grounded.
--   * glaiverush (moves.ts:6648): `self: {volatileStatus: 'glaiverush'}`;
--     the condition (`noCopy`) makes every move aimed at the holder
--     always hit (`onAccuracy` -> true) AND deal double damage
--     (`onSourceModifyDamage` -> chainModify(2)), and is removed by
--     `onBeforeMovePriority: 100` before the holder attacks again.
--   * baddybad (moves.ts:968) / glitzyglow (:6695): LGPE special attacks
--     whose `self: {sideCondition: 'reflect' | 'lightscreen'}` puts the
--     matching screen on the USER's side after the move connects.
--   * sparklyswirl (moves.ts:17390): LGPE special attack whose
--     `self.onHit` cures the status of the user's WHOLE side
--     (`source.side.pokemon`, bar an ally behind a Substitute).
--
-- ENGINE SEAMS (all already exist; this file adds no second turn model):
--   * Gen 2 recharge is the native `volatile(mon).recharge` flag --
--     gen2/Battle.lua:984 `checkTurn` clears it and spends the turn,
--     :1981 the native EFFECT_HYPER_BEAM sets it (`dealt > 0`). Gen 1 is
--     `mon.mustRecharge` (MoveEffects.lua:665 HYPER_BEAM_EFFECT; read by
--     BattleState.lua:2107). Both flags are set by this file's own real
--     logic instead of a native effect id, because national_dex shadows
--     all eight recharge moves at EFFECT_NORMAL_HIT.
--   * Selfdestruct: Gen 2 native is `Battle:selfdestructUser`
--     (gen2/Battle.lua:1410), but it is keyed strictly on
--     `def.effect == "EFFECT_SELFDESTRUCT"`; Gen 1 native is
--     `BattleState:selfDestruct` (BattleState.lua:4441) via
--     EXPLODE_EFFECT. Neither id matches this move, so this file
--     reproduces the faint itself (Gen 2 on the useMove wrap, Gen 1 on
--     the record's own onMiss/afterDamage).
--   * The post-resolution hook is one more `Battle.useMove` wrap: the
--     mind-blown recoil and the Misty Explosion faint must fire even when
--     the move was protected, missed, or immune, so a
--     `battle.damage_dealt` listener is not enough for those two. The
--     recharge / screen / Glaive Rush / cure riders DO use
--     `battle.damage_dealt` -- they only fire on a real hit, which is
--     exactly Showdown's `self` semantics.
--   * Glaive Rush's double damage is a `registerDamageModifier` entry and
--     its can't-miss is a `battle.accuracy` wrap (the same hooks Phase 18
--     and the crit override already own). The volatile lives in
--     `mon.volatile`, which `Battle:clearVolatile` (gen2/Battle.lua:1112)
--     wipes on a switch, matching `noCopy` -- and is cleared at the
--     holder's next `battle.move_used`, matching onBeforeMovePriority 100.
--
-- Gen 1: the eight recharge moves and the mind-blown / selfdestruct
-- self-damage also get a real Gen 1 `afterDamage`/`onMiss` record; the
-- screen / glaive-rush / team-cure halves are Gen 2-only (their state is
-- the Gen 2 `battle.screens` table and the Gen 2 volatile store, the same
-- Gen-2-state line Phase 7's modern_side_conditions.lua already draws),
-- and Gen 1 simply keeps the move's ordinary damage -- not a regression.
return function(mod)
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  local Strings = require("src.core.Strings")

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local sideOfWho = mod.exports.sideOfWho
  local isGen2Battle = mod.exports.isGen2Battle
  local curTypesOf = mod.exports.curTypesOf
  local registerDamageModifier = mod.exports.registerDamageModifier
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local nameOf = mod.exports.g9NameOf
  local rawMon = mod.exports.g9RawMon
  local maxHpOf = mod.exports.g9MaxHpOf
  local sidePartyOf = mod.exports.g9SidePartyOf
  local cureStatusOf = mod.exports.cureStatusOf
  local Primitives = mod.exports.ShowdownPrimitives
  assert(normalize and displayNameFor and sideOfWho and registerDamageModifier,
    "modern_self_effects: combat/modern_combat.lua must load first")
  assert(nameOf and rawMon and maxHpOf,
    "modern_self_effects: combat/modern_party_support.lua must load first")

  local function emit(battle, text)
    if battle and battle.emit then
      battle:emit({ kind = "message", text = text })
    end
  end

  -- Per-mon volatile accessor (same shape, and same pointer-safe reason,
  -- as combat/modern_faint_sacrifice.lua's own g9VolatileOf: never calls
  -- the method, so a headless battle stub that omits `volatile` can't
  -- crash these listeners).
  local function volatileOf(who)
    local m = rawMon(who)
    if not m then return {} end
    m.volatile = m.volatile or {}
    return m.volatile
  end
  if not mod.exports.g9VolatileOf then mod.exports.g9VolatileOf = volatileOf end

  local function gen2Of(battle)
    return (isGen2Battle and isGen2Battle(battle)) or false
  end

  -- The same "grounded" read combat/modern_terrain.lua's own isGrounded
  -- uses (Gravity's gravityGrounded field plus the Flying type).
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
  -- RECHARGE -- the eight Hyper Beam-shaped moves. Gen 2 sets the
  -- native `volatile.recharge` flag (consumed by checkTurn); Gen 1 sets
  -- `mustRecharge` through a real afterDamage record (the GEN 1 half of
  -- the same design already used for Eternabeam in
  -- modern_movepool_damage.lua). Both fire on a landed hit only
  -- (Showdown's `self` applies on a successful connect).
  ------------------------------------------------------------------
  local RECHARGE_MOVES = {
    BLASTBURN = true, FRENZYPLANT = true, GIGAIMPACT = true,
    HYDROCANNON = true, METEORASSAULT = true, PRISMATICLASER = true,
    ROAROFTIME = true, ROCKWRECKER = true,
  }

  local function setRecharge(battle, user)
    local m = rawMon(user)
    if not m then return end
    if gen2Of(battle) then
      volatileOf(m).recharge = true
    else
      m.mustRecharge = true
    end
  end
  mod.exports.g9SetRecharge = setRecharge

  -- Gen 1 half. Deliberately unconditional on a hit (current Showdown has
  -- no KO exemption for these moves) -- unlike Eternabeam's older record
  -- in modern_movepool_damage.lua, which copies the native Gen 1
  -- HYPER_BEAM_EFFECT and therefore keeps the Gen 1 "skip on KO".
  mod.content.move_effects:register("GALAR_RECHARGE_EFFECT", {
    kind = "full",
    afterDamage = function(ctx)
      local user = ctx and ctx.user
      if user then user.mustRecharge = true end
    end,
  })
  for id in pairs(RECHARGE_MOVES) do
    mod.content.moves:patch(id, { effect = "GALAR_RECHARGE_EFFECT" })
  end

  ------------------------------------------------------------------
  -- MIND BLOWN / STEEL BEAM -- the user loses half its MAX HP once the
  -- move resolves, hit or miss (battle-actions.ts:1382 + each move's own
  -- onMoveFail). Magic Guard blocks it; Rock Head does not.
  ------------------------------------------------------------------
  local MIND_BLOWN_MOVES = { MINDBLOWN = true, STEELBEAM = true }

  local function mindBlownRecoil(battle, user)
    local m = rawMon(user)
    if not m then return end
    local maxHp = maxHpOf(m)
    if not maxHp or maxHp <= 0 then return end
    -- Magic Guard: real damage refusal (any effect that isn't a Move).
    local abilityIdOf = mod.exports.abilityIdOf
    if abilityIdOf and abilityIdOf(user) == "MAGICGUARD" then return end
    -- Math.round(maxhp / 2).
    local amount = math.max(1, math.floor(maxHp / 2 + 0.5))
    local dealt
    if Primitives and Primitives.damage then
      dealt = Primitives.damage(m, amount, user, "MIND_BLOWN_RECOIL")
    else
      dealt = math.min(amount, (m.hp or 0))
      m.hp = math.max(0, (m.hp or 0) - amount)
      if m.hp <= 0 then m.fainted = true end
    end
    if dealt and dealt > 0 then
      if battle.emit then
        battle:emit({ kind = "damage", side = sideOfWho(battle, user, true),
          amount = dealt, hp = m.hp, anim = false })
      end
      emit(battle, Strings("%s is damaged by the recoil!", nameOf(battle, user)))
    end
  end
  mod.exports.g9MindBlownRecoil = mindBlownRecoil

  -- Gen 1 half -- same half-max-HP loss through the record's onMiss
  -- (miss/immune/protected) and afterDamage (a real hit).
  local function gen1MindBlownRecoil(ctx)
    local battle = ctx and ctx.battle
    local m = rawMon(ctx and ctx.user)
    if not (battle and m) then return end
    local maxHp = maxHpOf(m)
    if not maxHp or maxHp <= 0 then return end
    local abilityIdOf = mod.exports.abilityIdOf
    if abilityIdOf and abilityIdOf(ctx.user) == "MAGICGUARD" then return end
    local amount = math.max(1, math.floor(maxHp / 2 + 0.5))
    m.hp = math.max(0, (m.hp or 0) - amount)
    if m.hp <= 0 then m.fainted = true end
  end

  mod.content.move_effects:register("GALAR_MINDBLOWN_EFFECT", {
    kind = "full",
    onMiss = gen1MindBlownRecoil,
    afterDamage = gen1MindBlownRecoil,
  })
  for id in pairs(MIND_BLOWN_MOVES) do
    mod.content.moves:patch(id, { effect = "GALAR_MINDBLOWN_EFFECT" })
  end

  ------------------------------------------------------------------
  -- MISTY EXPLOSION -- `selfdestruct: "always"` (the user faints once the
  -- move is used, Protect/miss/immunity notwithstanding). Gen 2 does it
  -- on the useMove wrap below; Gen 1 gets a real onMiss/afterDamage pair
  -- forwarding to the engine's own BattleState:selfDestruct.
  ------------------------------------------------------------------
  local function selfdestructMon(battle, user)
    local m = rawMon(user)
    if not m or (m.hp or 0) <= 0 then return end
    local lost = m.hp or 0
    -- Native move_effects/selfdestruct.asm:6-12: status, both HP bytes
    -- and its own Leech Seed go with the user.
    m.status, m.statusTurns = nil, nil
    m.toxicCounter = nil
    m.hp = 0
    volatileOf(m).leechSeed = nil
    if battle.emit then
      battle:emit({ kind = "damage", side = sideOfWho(battle, user, true),
        amount = lost, hp = 0, anim = false })
    end
    if Primitives and Primitives.faint then
      Primitives.faint(m)
    else
      m.fainted = true
    end
  end
  mod.exports.g9SelfdestructMon = selfdestructMon

  local function gen1MistySelfdestruct(ctx)
    local battle = ctx and ctx.battle
    if battle and battle.selfDestruct then
      battle:selfDestruct(ctx.user)
    else
      local m = rawMon(ctx and ctx.user)
      if m then m.hp = 0; m.fainted = true end
    end
  end

  mod.content.move_effects:register("GALAR_MISTYEXPLOSION_EFFECT", {
    kind = "full",
    onMiss = gen1MistySelfdestruct,
    afterDamage = gen1MistySelfdestruct,
  })
  mod.content.moves:patch("MISTYEXPLOSION", { effect = "GALAR_MISTYEXPLOSION_EFFECT" })

  ------------------------------------------------------------------
  -- MISTY EXPLOSION's terrain boost -- its own `onBasePower` 1.5x while
  -- Misty Terrain is up and the user is grounded (moves.ts:12143). Misty
  -- Terrain itself does NOT boost Fairy moves in current Showdown
  -- (moves.ts:12185 only weakens Dragon), so this is genuinely
  -- move-specific.
  ------------------------------------------------------------------
  local function mistyExplosionTerrainMultiplier(battle, user, moveId)
    if moveId ~= "MISTYEXPLOSION" then return 1.0 end
    if not (battle and battle.terrain == "MISTY") then return 1.0 end
    if not isGrounded(user) then return 1.0 end
    return 1.5
  end
  mod.exports.g9MistyExplosionTerrainMultiplier = mistyExplosionTerrainMultiplier

  registerDamageModifier("misty_explosion_terrain", 100, function(ctx)
    return mistyExplosionTerrainMultiplier(ctx and ctx.battle, ctx and ctx.user,
      ctx and ctx.move and ctx.move.id)
  end)

  ------------------------------------------------------------------
  -- GLAIVE RUSH -- the drawback volatile. While the user holds it, every
  -- incoming move always hits and deals double damage; it is cleared
  -- before the holder's next move.
  ------------------------------------------------------------------
  local function glaiveRushActive(who)
    return volatileOf(who).glaiverush == true
  end
  mod.exports.g9GlaiveRushActive = glaiveRushActive

  local function glaiveRushMultiplier(target)
    if glaiveRushActive(target) then return 2.0 end
    return 1.0
  end
  mod.exports.g9GlaiveRushMultiplier = glaiveRushMultiplier

  registerDamageModifier("glaive_rush", 90, function(ctx)
    return glaiveRushMultiplier(ctx and ctx.target)
  end)

  -- Can't-miss (conditions.ts's glaiverush.onAccuracy). Returning true is
  -- the same sure-hit contract modern_crit_override's `sureHit` wrap uses.
  mod.hooks:wrap("battle.accuracy", function(nextFn, ctx)
    if ctx and ctx.target and glaiveRushActive(ctx.target) then return true end
    return nextFn(ctx)
  end, 100)

  ------------------------------------------------------------------
  -- BADDY BAD / GLITZY GLOW -- the LGPE screen setters. A `self` side
  -- condition puts Reflect / Light Screen on the user's own side after
  -- the move connects; Light Clay stretches 5 -> 8 via the shared
  -- resolveFieldDuration primitive, exactly like the native screens.
  ------------------------------------------------------------------
  local SCREEN_MOVES = {
    BADDYBAD = "reflect",
    GLITZYGLOW = "lightScreen",
  }

  local function screensOf(battle, side)
    battle.screens = battle.screens or { player = {}, enemy = {} }
    battle.screens[side] = battle.screens[side] or {}
    return battle.screens[side]
  end

  local function setScreen(battle, user, key)
    local side = sideOfWho(battle, user, true)
    local sc = screensOf(battle, side)
    local base = (Battle and Battle.SCREEN_TURNS) or 5
    local setter = rawMon(user)
    sc[key] = resolveFieldDuration and resolveFieldDuration(setter, base, 8, "LIGHT_CLAY")
      or base
    return sc[key]
  end
  mod.exports.g9SetScreen = setScreen

  ------------------------------------------------------------------
  -- SPARKLY SWIRL's team cure -- Showdown cures `source.side.pokemon`
  -- (the whole side, bar a Substitute). Reuses status_cure.lua's own
  -- cureStatusOf and the G-Max Sweetness whole-side loop shape.
  ------------------------------------------------------------------
  local function sparklySwirlCure(battle, user)
    if not cureStatusOf then return end
    local party = sidePartyOf(battle, user)
    for _, mon in ipairs(party) do pcall(cureStatusOf, mon) end
    local active = rawMon(user)
    if active then pcall(cureStatusOf, active) end
    emit(battle, Strings("%s cured its team's status conditions!",
      nameOf(battle, user)))
  end
  mod.exports.g9SparklySwirlCure = sparklySwirlCure

  ------------------------------------------------------------------
  -- Stub-audit markers for the four fully `self`-driven damaging moves
  -- whose real logic above lives in a side hook, not in a record body --
  -- the established Fling/Knock Off precedent (see
  -- combat/modern_item_moves.lua). Each is an empty `kind="full"` record
  -- with NO `run`, so Gen 2's damage path is untouched; patching them
  -- retires their national_dex EFFECT_NORMAL_HIT placeholder.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_BADDYBAD_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GALAR_GLITZYGLOW_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GALAR_GLAIVERUSH_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GALAR_SPARKLYSWIRL_EFFECT", { kind = "full" })
  mod.content.moves:patch("BADDYBAD", { effect = "GALAR_BADDYBAD_EFFECT" })
  mod.content.moves:patch("GLITZYGLOW", { effect = "GALAR_GLITZYGLOW_EFFECT" })
  mod.content.moves:patch("GLAIVERUSH", { effect = "GALAR_GLAIVERUSH_EFFECT" })
  mod.content.moves:patch("SPARKLYSWIRL", { effect = "GALAR_SPARKLYSWIRL_EFFECT" })

  ------------------------------------------------------------------
  -- The post-resolution riders. Recharge / screens / Glaive Rush / cure
  -- fire on a real landed hit (battle.damage_dealt); the recharge half is
  -- Gen 2-only (Gen 1 already has the record above).
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    local moveId = ev and (ev.moveId or (ev.move and ev.move.id))
    if not (battle and user and target and moveId) then return end
    if (ev.damage or 0) <= 0 or user == target then return end
    local ok, err = pcall(function()
      if RECHARGE_MOVES[moveId] then
        if gen2Of(battle) then setRecharge(battle, user) end
      elseif SCREEN_MOVES[moveId] then
        setScreen(battle, user, SCREEN_MOVES[moveId])
        emit(battle, SCREEN_MOVES[moveId] == "reflect"
          and Strings("%s's team became shielded!", nameOf(battle, user))
          or Strings("%s's team became cloaked in light!", nameOf(battle, user)))
      elseif moveId == "GLAIVERUSH" then
        volatileOf(user).glaiverush = true
      elseif moveId == "SPARKLYSWIRL" then
        sparklySwirlCure(battle, user)
      end
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: modern_self_effects: %s rider failed: %s",
        tostring(moveId), tostring(err))
    end
  end)

  -- Glaive Rush wears off at the holder's next move (onBeforeMovePriority
  -- 100). battle.move_used fires at the start of the holder's useMove, and
  -- the move's own damage_dealt listener re-applies it if it is Glaive
  -- Rush again -- the exact order Showdown's onBeforeMove + self volatile
  -- produce.
  mod.events:on("battle.move_used", function(ev)
    local battle, user = ev and ev.battle, ev and ev.user
    if not (battle and user) then return end
    local vol = rawMon(user) and rawMon(user).volatile
    if vol and vol.glaiverush then vol.glaiverush = nil end
  end)

  ------------------------------------------------------------------
  -- The post-resolution useMove wrap: Mind Blown / Steel Beam recoil and
  -- Misty Explosion's selfdestruct must fire regardless of hit, miss,
  -- Protect or immunity, so they cannot ride a damage_dealt listener.
  -- Installed outermost at boot (this file is the last combat blocker
  -- booted before the held-item pool), so it runs after every inner
  -- effect has resolved.
  ------------------------------------------------------------------
  if Battle then
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      local result = nativeUseMove(self, attacker, defender, moveId)
      local ok, err = pcall(function()
        if moveId == "MISTYEXPLOSION" then
          selfdestructMon(self, attacker)
        elseif MIND_BLOWN_MOVES[moveId] then
          mindBlownRecoil(self, attacker)
        end
      end)
      if not ok then
        mod.log:warn("g9-battle-engine: modern_self_effects: after-use hook failed: %s",
          tostring(err))
      end
      return result
    end
  end

  mod.log:info("g9-battle-engine: modern_self_effects installed "
    .. "(recharge x8, MINDBLOWN/STEELBEAM recoil, MISTYEXPLOSION, "
    .. "GLAIVERUSH, BADDYBAD, GLITZYGLOW, SPARKLYSWIRL)")
end
