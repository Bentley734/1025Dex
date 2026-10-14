-- Phase 6 of the missing-effects pipeline (part 2): the self-faint and
-- faint-triggered sacrifices.
--
-- Showdown source of truth (scratch/showdown/moves.ts -- extracted by
-- direct read this session; line numbers cited per clause):
--   healingwish (8349-8383): Psychic, Status, `accuracy: true`, target
--     "self", `selfdestruct: "ifHit"`, `slotCondition: 'healingwish'`.
--     `onTryHit(source)`: `if (!this.canSwitch(source.side)) { ... return
--     this.NOT_FAIL; }` -- i.e. the move FAILS (and does not self-KO) when
--     the user's side has no healthy mon to switch in. The slot
--     condition's `onSwap(target)` heals the incoming mon to FULL and
--     clears its status.
--   lunardance (10564-10607): Psychic, Status, same gate, same
--     selfdestruct, `slotCondition: 'lunardance'`. Its `onSwap` also
--     restores every move slot's PP (`moveSlot.pp = moveSlot.maxpp`).
--   memento (11621-11639): Dark, Status, accuracy 100, target "normal",
--     `boosts: { atk: -2, spa: -2 }`, `selfdestruct: "ifHit"`. A normal
--     damaging-targeted debuff followed by the user fainting.
--   destinybond (3483-3526): Ghost, Status, target "self",
--     `volatileStatus: 'destinybond'`. `condition.onFaint(target,
--     source, effect)`: when the holder faints to a MOVE (`effect` is a
--     Move, not a futuremove), the source faints too -- a Dynamaxed
--     source is immune (no Dynamax in this mod, so that branch is
--     moot). `onBeforeMove` removes the volatile as soon as the holder
--     moves again.
--   grudge (7884-7923): Ghost, Status, target "self",
--     `volatileStatus: 'grudge'`. `condition.onFaint(target, source,
--     effect)`: when the holder faints to a MOVE, the move the source
--     just used has its PP set to 0. `onBeforeMove` removes the volatile
--     before the holder attacks again.
--   lastresort (10067-10091): Normal, Physical, 140 BP. `onTry(source)`:
--     fails unless the user knows at least 2 moves AND every OTHER known
--     move has already been used this battle (`moveSlot.used`).
--
-- Design notes:
--   * Faints done here (Memento/Healing Wish/Lunar Dance self-KO, and
--     Destiny Bond's retribution) are plain HP writes -- the engine's
--     own faint announcement already scans for `hp <= 0`
--     (combat/turn_residuals.lua's announceFaints) and turns them into
--     the real `kind="faint"` text plus the `battle.fainted` runtime
--     event, so this file never fakes that half.
--   * Destiny Bond and Grudge need to know WHAT faint-triggered move
--     killed the holder -- the engine's `battle.fainted` event carries
--     no source, so a `battle.damage_dealt` listener records the last
--     move-owned hit per target (`ev.moveId` present means a real move,
--     not residual chip -- Showdown's own "End-of-turn damage is
--     ignored" wording on both moves). A switch or a fresh battle clears
--     the record naturally because it is keyed per mon identity.
--   * Last Resort is a damage move that must simply FAIL sometimes; it
--     reuses combat/modern_action_order.lua's reusable fail-gate seam
--     (`registerFailGate`), so it is announced, spends PP, is marked
--     missed and prints "But it failed!" through the exact path Sucker
--     Punch/Focus Punch already use.
return function(mod)
  local Strings = require("src.core.Strings")

  local nameOf = mod.exports.g9NameOf
  local rawMon = mod.exports.g9RawMon
  local maxHpOf = mod.exports.g9MaxHpOf
  local sidePartyOf = mod.exports.g9SidePartyOf
  local canSwitchOut = mod.exports.g9CanSwitchOut
  local healFraction = mod.exports.g9HealFraction
  local changeStage = mod.exports.changeStage
  local registerFailGate = mod.exports.registerFailGate
  assert(nameOf and rawMon and maxHpOf and sidePartyOf and canSwitchOut
    and healFraction and changeStage,
    "modern_faint_sacrifice: combat/modern_party_support.lua and "
    .. "combat/modern_combat.lua must load first")
  assert(registerFailGate,
    "modern_faint_sacrifice: combat/modern_action_order.lua must load first")

  local function emit(battle, text)
    if battle and battle.emit then
      battle:emit({ kind = "message", text = text })
    end
  end

  local function faintMon(mon)
    local m = rawMon(mon)
    if not m then return false end
    local P = mod.exports.ShowdownPrimitives
    if P and P.faint then return P.faint(m) end
    if (m.hp or 0) <= 0 then return false end
    m.hp = 0
    m.fainted = true
    return true
  end

  local function isGen2(battle)
    local fn = mod.exports.isGen2Battle
    return fn and fn(battle) or true
  end

  -- Per-mon volatile accessor. The real Battle:volatile(mon) is exactly
  -- `mon.volatile = mon.volatile or {}; return mon.volatile` (see
  -- src/battle/gen2/Battle.lua, `function Battle:volatile`), so reading
  -- the mon's own table directly is identical -- and, unlike calling the
  -- method, it never crashes under a headless battle stub that omits
  -- `volatile`. That matters because these listeners fire on EVERY
  -- battle.fainted / battle.move_used across the whole engine, including
  -- scenes whose battle object is intentionally minimal.
  local function volatileOf(who)
    local m = rawMon(who)
    if not m then return {} end
    m.volatile = m.volatile or {}
    return m.volatile
  end
  mod.exports.g9VolatileOf = volatileOf

  ------------------------------------------------------------------
  -- Healing Wish / Lunar Dance -- self-KO + a pending replacement heal
  -- on the user's side. Stored on the battle keyed by side (the "slot"
  -- in a 1v1 engine is the side), consumed by the next switch-in on that
  -- side.
  ------------------------------------------------------------------
  local function pendingHealOn(battle)
    battle.__g9PendingHeal = battle.__g9PendingHeal or {}
    return battle.__g9PendingHeal
  end
  mod.exports.g9PendingHealOn = pendingHealOn

  local function registerWishSacrifice(effectId, kind, pp)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      run = function(a, b, c)
        local n = mod.exports.normalize(a, b, c)
        local battle, user = n.battle, n.user
        -- Showdown onTryHit: no healthy bench -> the move fails and the
        -- user does NOT faint.
        if not canSwitchOut(battle, user) then
          emit(battle, Strings("But it failed!"))
          return
        end
        local side = battle.sideOf and battle:sideOf(user) or "player"
        pendingHealOn(battle)[side] = { restoresPp = pp }
        emit(battle, Strings("%s sacrificed itself for its team!",
          nameOf(battle, user)))
        faintMon(user)
      end,
    })
    return kind
  end
  registerWishSacrifice("GALAR_HEALINGWISH_EFFECT", "healingwish", false)
  registerWishSacrifice("GALAR_LUNARDANCE_EFFECT", "lunardance", true)

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local incoming = ev and ev.battler
    local pending = battle and battle.__g9PendingHeal
    if not (pending and incoming) then return end
    local side = battle.sideOf and battle:sideOf(incoming) or "player"
    local entry = pending[side]
    if not entry then return end
    if (rawMon(incoming).hp or 0) <= 0 then return end
    pending[side] = nil
    local m = rawMon(incoming)
    local maxHp = maxHpOf(m)
    if maxHp and m.hp < maxHp then
      m.hp = maxHp
    end
    m.status = nil
    m.statusTurns = nil
    m.toxicCounter = nil
    if entry.restoresPp then
      for _, ms in ipairs(m.moves or {}) do
        -- Lunar Dance's own clause (`moveSlot.pp = moveSlot.maxpp` in
        -- Showdown) restores every slot to its MAXIMUM. The camel `maxPp` is
        -- the field the rest of the engine and the scene use; Gen 1 slots
        -- carry no maximum at all, so derive it the way the native games do
        -- (BattleState.lua: `def.pp + ppUps * floor(def.pp/5)`).
        local max = ms.maxPp
        if not max then
          local ok, def = pcall(battle.moveDef, battle, ms.id)
          local base = (ok and def and def.pp) or 0
          if base > 0 then
            max = base + (ms.ppUps or 0) * math.floor(base / 5)
          end
        end
        if max and (ms.pp or 0) < max then ms.pp = max end
      end
    end
    emit(battle, Strings("%s's HP and status were fully restored!",
      nameOf(battle, incoming)))
  end)

  ------------------------------------------------------------------
  -- MEMENTO -- -2 Atk / -2 SpA on the opponent, then the user faints.
  -- Target-directed, so accuracyChecked = true (a genuine miss should
  -- stop both the drop and the self-KO, matching `selfdestruct: "ifHit"`).
  ------------------------------------------------------------------
  local function applyStage(battle, who, stat, delta)
    local lines = changeStage(battle, who, stat, delta, true, true) or {}
    for _, line in ipairs(lines) do emit(battle, line) end
  end

  mod.content.move_effects:register("GALAR_MEMENTO_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = mod.exports.normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if target and target ~= user then
        applyStage(battle, target, "attack", -2)
        applyStage(battle, target, "spa", -2)
      end
      emit(battle, Strings("%s fainted to leave its mark!",
        nameOf(battle, user)))
      faintMon(user)
    end,
  })

  ------------------------------------------------------------------
  -- DESTINY BOND / GRUDGE -- a self volatile armed on use, triggered off
  -- the holder's own faint to a MOVE, cleared when the holder moves
  -- again (Showdown's onBeforeMove) or switches (native clearVolatile).
  ------------------------------------------------------------------
  local function lastHitOn(battle)
    battle.__g9LastMoveHit = battle.__g9LastMoveHit or {}
    return battle.__g9LastMoveHit
  end
  mod.exports.g9LastHitOn = lastHitOn

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local target = ev and ev.target
    if not (battle and target) then return end
    local moveId = ev.moveId or (ev.move and ev.move.id)
    if not moveId or (ev.damage or 0) <= 0 then return end
    lastHitOn(battle)[target] = { user = ev.user, moveId = moveId }
  end)

  mod.content.move_effects:register("GALAR_DESTINYBOND_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = mod.exports.normalize(a, b, c)
      local battle, user = n.battle, n.user
      volatileOf(user).destinybond = true
      emit(battle, Strings("%s is hoping to take its attacker down with it!",
        nameOf(battle, user)))
    end,
  })

  mod.content.move_effects:register("GALAR_GRUDGE_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = mod.exports.normalize(a, b, c)
      local battle, user = n.battle, n.user
      volatileOf(user).grudge = true
      emit(battle, Strings("%s is bearing a grudge!", nameOf(battle, user)))
    end,
  })

  -- The faint trigger for both. `battle.fainted` carries the model; the
  -- recorded last move-owned hit answers "what fainted it, and who used
  -- it". Residual chip never recorded a `moveId`, so it can't fire either.
  mod.events:on("battle.fainted", function(ev)
    local battle = ev and ev.battle
    local holder = ev and ev.battler
    if not (battle and holder) then return end
    local hits = battle.__g9LastMoveHit
    local hit = hits and hits[holder]
    if not hit or not hit.user or hit.user == holder then return end
    local vol = volatileOf(holder)
    if vol and vol.destinybond then
      vol.destinybond = nil
      local other = rawMon(hit.user)
      if other and (other.hp or 0) > 0 then
        emit(battle, Strings("%s took its attacker down with it!",
          nameOf(battle, holder)))
        faintMon(other)
      end
    end
    if vol and vol.grudge then
      vol.grudge = nil
      local other = rawMon(hit.user)
      if other then
        local did = false
        for _, ms in ipairs(other.moves or {}) do
          if ms.id == hit.moveId and (ms.pp or 0) > 0 then
            ms.pp = 0
            did = true
          end
        end
        if did then
          emit(battle, Strings("%s's %s had its PP drained to zero!",
            nameOf(battle, other), hit.moveId))
        end
      end
    end
  end)

  -- Clear the armed volatile the moment the holder moves again (any move
  -- but the arming one), matching onBeforeMove; also the per-mon used
  -- bookkeeping Last Resort reads.
  mod.events:on("battle.move_used", function(ev)
    local battle = ev and ev.battle
    local user = ev and ev.user
    if not (user) then return end
    local id = ev.move and ev.move.id
    for _, ms in ipairs(rawMon(user).moves or {}) do
      if ms.id == id then ms.__g9Used = true end
    end
    local m = rawMon(user)
    if not (m and m.volatile) then return end
    local vol = m.volatile
    if vol.destinybond and id ~= "DESTINYBOND" then vol.destinybond = nil end
    if vol.grudge and id ~= "GRUDGE" then vol.grudge = nil end
  end)

  ------------------------------------------------------------------
  -- LAST RESORT -- fails unless every OTHER known move has been used at
  -- least once this battle (and the user knows at least 2 moves). Rides
  -- modern_action_order.lua's reusable fail gate, so the move is still
  -- announced and spends its PP.
  ------------------------------------------------------------------
  local function lastResortBlocked(user)
    local m = rawMon(user)
    local moves = m and m.moves
    if not moves or #moves < 2 then return true end
    for _, ms in ipairs(moves) do
      if ms.id ~= "LASTRESORT" and not ms.__g9Used then return true end
    end
    return false
  end
  registerFailGate("LASTRESORT", function(battle, user)
    if lastResortBlocked(user) then return "fail" end
    return nil
  end)

  -- The same condition at SELECTION time (round 100): the menu-side twin of
  -- the fail gate above, via combat/move_usability.lua. One predicate, so a
  -- Last Resort the menu offers is exactly one the resolver will run.
  local registerMoveUsabilityGate = mod.exports.registerMoveUsabilityGate
  if registerMoveUsabilityGate then
    registerMoveUsabilityGate("LASTRESORT", function(battle, mon)
      if lastResortBlocked(mon) then
        return { flag = "condition",
          reason = Strings("Last Resort can only be used after the user has used all its other moves!") }
      end
      return nil
    end)
  end

  -- Showdown resets every move slot's `used` flag the moment a Pokemon
  -- enters the field (battle-actions.ts `switchIn`: `activeMoveActions = 0`
  -- followed by `for (const moveSlot of pokemon.moveSlots) moveSlot.used =
  -- false`) -- that is exactly the "since the user entered the field" wording
  -- national_dex's own Last Resort text carries (api/010.lua:27). Without
  -- this, the `__g9Used` marks set on battle.move_used would persist across a
  -- switch out and back, wrongly leaving Last Resort usable. Clear the flags
  -- for whoever walks in, and for both leads at battle start (the leads never
  -- emit battle.battler_switched -- the same gap modern_action_order.lua's own
  -- __g9MoveActions reset documents).
  local function clearUsedFlags(who)
    local m = rawMon(who)
    if not m then return end
    for _, ms in ipairs(m.moves or {}) do ms.__g9Used = nil end
  end
  mod.events:on("battle.battler_switched", function(ev)
    clearUsedFlags(ev and ev.battler)
  end)
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    local fn = mod.exports.allActiveBattlers
    local list = (fn and fn(battle)) or (battle and { battle.player, battle.enemy }) or {}
    for _, who in ipairs(list) do clearUsedFlags(who) end
  end)

  mod.content.moves:patch("HEALINGWISH", { effect = "GALAR_HEALINGWISH_EFFECT" })
  mod.content.moves:patch("LUNARDANCE", { effect = "GALAR_LUNARDANCE_EFFECT" })
  mod.content.moves:patch("MEMENTO", { effect = "GALAR_MEMENTO_EFFECT" })
  mod.content.moves:patch("DESTINYBOND", { effect = "GALAR_DESTINYBOND_EFFECT" })
  mod.content.moves:patch("GRUDGE", { effect = "GALAR_GRUDGE_EFFECT" })

  mod.log:info("g9-battle-engine: modern_faint_sacrifice installed "
    .. "(HEALINGWISH, LUNARDANCE, MEMENTO, DESTINYBOND, GRUDGE, LASTRESORT gate)")
end
