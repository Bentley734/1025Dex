-- Phase 6 of the missing-effects pipeline: party recovery and sacrifice.
--
-- Showdown source of truth (scratch/showdown/moves.ts -- read by direct
-- extraction this session; line numbers cited per clause):
--   aromatherapy (556-590): Grass, Status, `accuracy: true`, target
--     "allyTeam". `onHit(target, source)`: `this.add('-activate', source,
--     'move: Aromatherapy')`, then for EVERY member of
--     `target.side.pokemon` (plus allySide in a multi-side format) --
--     skipping the source itself and, unless ability-suppressed, a
--     Sap Sipper / Good as Gold holder or a Substitute holder without
--     infiltrate -- call `ally.cureStatus()`, tracking `success`; returns
--     it. i.e. a whole-side status cure that succeeds if ANY ally (or the
--     user) had a status.
--   healbell (8241-8273): Normal, Status, `accuracy: true`, target
--     "allyTeam", sound move. Same shape, but its ability exemptions are
--     Soundproof instead of Sap Sipper (both are ally-side immunities
--     this engine has no separate ally slot to reach in a 1v1 battle).
--   junglehealing (9857-9872): Grass, Status, `accuracy: true`, target
--     "allies". `onHit(pokemon)`: `const success = !!this.heal(this.modify(
--     pokemon.maxhp, 0.25)); return pokemon.cureStatus() || success;`
--     i.e. heal 25% max HP AND cure status, succeeding if either landed.
--   refresh (14916-14934): Normal, Status, `accuracy: true`, target
--     "self". `onHit(pokemon)`: `if (['', 'slp', 'frz'].includes(
--     pokemon.status)) return false; pokemon.cureStatus();` i.e. FAILS when
--     the user has no status OR a Sleep/Freeze one (Gen 3+ rule); cures
--     every other major status (brn/par/psn/tox).
--   takeheart (18930-18945): Psychic, Status, `accuracy: true`, target
--     "self". `onHit(pokemon)`: `const success = !!this.boost({spa: 1,
--     spd: 1}); return pokemon.cureStatus() || success;` i.e. +1 SpA, +1
--     SpD, AND cure the user, succeeding if either landed.
--   wish (20916-20952): Normal, Status, `accuracy: true`, target "self".
--     `slotCondition: 'Wish'`. The slot condition's `onStart` records
--     `hp = source.maxhp / 2` and the starting turn; `onResidual` (order
--     4) does NOTHING on the turn it was set (`if (turn <= startingTurn)
--     return`); `onEnd` heals the CURRENT MON IN THAT SLOT by the stored
--     half-max when the condition expires at the end of the FOLLOWING
--     turn. So: set on turn N, heals the slow slot's occupant at the end
--     of turn N+1.
--   revivalblessing (15111-15137): Normal, Status, `accuracy: true`,
--     target "self". `onTryHit(source)` returns false when the user's side
--     has NO fainted party member (`!side.pokemon.filter(ally =>
--     ally.fainted).length`), i.e. the move fails outright when there is
--     nobody to revive; otherwise the real revive is the side.ts
--     implementation (restores a chosen fainted member to half max HP).
--
-- Design notes for this engine:
--   * These are all power-0 status moves, so they go through the normal
--     Gen 2 primary dispatch (a `kind="primary"` move_effects record with
--     a `run` field -- gen2/Battle.lua:1750). Because a run() handler's
--     RETURN VALUE is discarded on Gen 2 (see combat/SUBEFFECTS.md), every
--     message is emitted with `battle:emit` directly rather than returned.
--   * `accuracyChecked` is left unset for the self/side moves (Aromatherapy,
--     Heal Bell, Jungle Healing, Refresh, Take Heart, Wish, Revival
--     Blessing): these must never roll a miss against the opponent, and the
--     Gen 1 dispatch treats `accuracyChecked = true` on a dexterity-0 move
--     as a real roll (combat/modern_stat_manipulation.lua:96-99). Memento,
--     in the sibling file, targets the opponent and DOES set it.
--   * "Whole party" reads battle.party / battle.enemyParty directly, the
--     same real arrays every other party-wide effect already uses
--     (modern_combat_protect.lua:543-544, max_move_subeffects.lua:600-602),
--     plus the active roster via requestAdjacency for a scene-driven
--     multi-battler battle.
return function(mod)
  local Strings = require("src.core.Strings")

  local cureStatusOf = mod.exports.cureStatusOf
  assert(cureStatusOf,
    "modern_party_support: abilities/engine/status_cure.lua must load first")
  assert(mod.exports.changeStage and mod.exports.displayNameFor
    and mod.exports.isGen2Battle,
    "modern_party_support: combat/modern_combat.lua must load first")

  local changeStage = mod.exports.changeStage
  local displayNameFor = mod.exports.displayNameFor

  ------------------------------------------------------------------
  -- Shared helpers, exported for the sibling sacrifice file (and any
  -- future party-wide effect) so there is exactly one definition of
  -- "which party", "the active mon on a side", "heal a fraction", and
  -- "does this side have a living bench".
  ------------------------------------------------------------------

  -- display name, tolerant of every battle shape (mirrors
  -- modern_action_order.lua's own nameOf).
  local function nameOf(battle, mon)
    local ok, n = pcall(displayNameFor, battle, mon, true)
    if ok and n then return n end
    if battle and battle.monName then
      local ok2, n2 = pcall(function() return battle:monName(mon) end)
      if ok2 and n2 then return n2 end
    end
    return (mon and (mon.name or mon.species)) or "The Pokemon"
  end
  mod.exports.g9NameOf = nameOf

  local function rawMon(who)
    return who and (who.mon or who) or nil
  end
  mod.exports.g9RawMon = rawMon

  local function maxHpOf(who)
    local m = rawMon(who)
    return m and (m.maxHp or (m.stats and m.stats.hp)) or nil
  end
  mod.exports.g9MaxHpOf = maxHpOf

  -- The real party array for `mon`'s side. `side` nil (no sideOf -- a
  -- bare unit test) defaults to the player side, same as every other
  -- side-reading helper in this mod.
  local function sidePartyOf(battle, mon)
    if not battle then return {} end
    local side = battle.sideOf and battle:sideOf(mon) or "player"
    if side == "enemy" then return battle.enemyParty or {} end
    return battle.party or {}
  end
  mod.exports.g9SidePartyOf = sidePartyOf

  -- The mon currently active on `side` ("player"/"enemy"). Reads the
  -- real battle.player/battle.enemy pointers, falling back to a
  -- side-tagged scan of the active roster.
  local function activeOf(battle, side)
    if side == "enemy" then return battle and battle.enemy end
    return battle and battle.player
  end
  mod.exports.g9ActiveOf = activeOf

  -- user + every adjacent ally (requestAdjacency is N-way when a scene
  -- mod is present, native two-battler fallback otherwise).
  local function alliesAndSelf(battle, user)
    local out = { user }
    local requestAdjacency = mod.exports.requestAdjacency
    if requestAdjacency then
      local ok, adj = pcall(requestAdjacency, battle, user, nil)
      if ok and adj and adj.allies then
        for _, ally in ipairs(adj.allies) do out[#out + 1] = ally end
      end
    end
    return out
  end
  mod.exports.g9AlliesAndSelf = alliesAndSelf

  -- Heal `num/den` of max HP on a living, not-already-full mon. Returns
  -- the actual amount healed (0 when fainted/at full/no max). Matches
  -- Showdown's Pokemon#heal "return the amount, false on a no-op"
  -- contract closely enough for every caller here.
  local function healFraction(battle, who, num, den)
    local m = rawMon(who)
    if not m then return 0 end
    local maxHp = maxHpOf(m)
    if not maxHp or maxHp <= 0 then return 0 end
    if (m.hp or 0) <= 0 then return 0 end
    if m.hp >= maxHp then return 0 end
    local amount = math.max(1, math.floor(maxHp * num / den))
    local healed = math.min(amount, maxHp - m.hp)
    local tryHeal = mod.exports.g9TryHeal
    if tryHeal then
      healed = tryHeal(battle, who, healed)
    else
      m.hp = m.hp + healed
    end
    return healed
  end
  mod.exports.g9HealFraction = healFraction

  -- Heal a FLAT amount on a living, not-already-full mon; returns the
  -- amount actually healed. Showdown's Wish slot condition stores
  -- `hp = source.maxhp / 2` at use time and later restores exactly that
  -- stored amount to whoever occupies the slot (moves.ts:20927-20949),
  -- regardless of the replacement's own max HP -- so a flat amount, not
  -- a fraction of the current occupant's max, is the faithful shape.
  local function healAmount(battle, who, amount)
    local m = rawMon(who)
    if not m or not amount or amount <= 0 then return 0 end
    local maxHp = maxHpOf(m)
    if not maxHp or maxHp <= 0 then return 0 end
    if (m.hp or 0) <= 0 then return 0 end
    if m.hp >= maxHp then return 0 end
    local healed = math.min(amount, maxHp - m.hp)
    local tryHeal = mod.exports.g9TryHeal
    if tryHeal then
      healed = tryHeal(battle, who, healed)
    else
      m.hp = m.hp + healed
    end
    return healed
  end
  mod.exports.g9HealAmount = healAmount

  -- Does `mon`'s side have any LIVING bench member (a party mon other
  -- than the active one, alive, not an egg)? The eligibility test
  -- Healing Wish / Lunar Dance / a faint replacement all need, mirroring
  -- Showdown's `this.canSwitch(side)`.
  local function canSwitchOut(battle, mon)
    for _, other in ipairs(sidePartyOf(battle, mon)) do
      local m = rawMon(other)
      if m and m ~= rawMon(mon) and (m.hp or 0) > 0 and not m.isEgg then
        return true
      end
    end
    return false
  end
  mod.exports.g9CanSwitchOut = canSwitchOut

  local function emit(battle, text)
    if battle and battle.emit then
      battle:emit({ kind = "message", text = text })
    end
  end

  ------------------------------------------------------------------
  -- AROMATHERAPY / HEAL BELL -- whole-side status cure. Showdown's
  -- onHit walks target.side.pokemon; here the "target side" of an
  -- allyTeam move is the USER's side, so the party array of sideOf(user)
  -- plus the active roster is the faithful scope (identical shape to
  -- GMAX.SWEETNESS in gigantamax/max_move_subeffects.lua:600-604, which
  -- is the same idea already shipped for a Max Move).
  ------------------------------------------------------------------
  local function sideCureAll(battle, user)
    local cured = 0
    local function try(who)
      if who and cureStatusOf(who) then cured = cured + 1 end
    end
    for _, mon in ipairs(sidePartyOf(battle, user)) do try(mon) end
    for _, ally in ipairs(alliesAndSelf(battle, user)) do try(ally) end
    return cured
  end

  local function registerSideCure(effectId, label)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      run = function(a, b, c)
        local n = mod.exports.normalize(a, b, c)
        local battle, user = n.battle, n.user
        local cured = sideCureAll(battle, user)
        if cured <= 0 then
          emit(battle, Strings("But it failed!"))
          return
        end
        emit(battle, Strings("%s's team was cured of its status conditions!",
          nameOf(battle, user)))
      end,
    })
    return label
  end
  registerSideCure("GALAR_AROMATHERAPY_EFFECT", "AROMATHERAPY")
  registerSideCure("GALAR_HEALBELL_EFFECT", "HEALBELL")

  ------------------------------------------------------------------
  -- JUNGLE HEALING -- heal 25% and cure, on the user and every ally.
  -- Succeeds if ANY recipient was healed OR cured (moves.ts:9869-9871).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_JUNGLEHEALING_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = mod.exports.normalize(a, b, c)
      local battle, user = n.battle, n.user
      local success = false
      for _, ally in ipairs(alliesAndSelf(battle, user)) do
        local healed = healFraction(battle, ally, 1, 4)
        local cured = cureStatusOf(ally)
        if healed > 0 then
          emit(battle, Strings("%s's HP was restored!", nameOf(battle, ally)))
        end
        if healed > 0 or cured then success = true end
      end
      if not success then
        emit(battle, Strings("But it failed!"))
      end
    end,
  })

  ------------------------------------------------------------------
  -- REFRESH -- self status cure, but only for the curable set: fail on
  -- no status, and fail on Sleep/Freeze (moves.ts:14922-14925). The
  -- engine's own status strings are the full lowercase words
  -- ("sleep"/"freeze" -- see abilities/engine/status_cure.lua's own
  -- header on the two engines' field conventions).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_REFRESH_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = mod.exports.normalize(a, b, c)
      local battle, user = n.battle, n.user
      local m = rawMon(user)
      local st = m and m.status
      if not st or st == "sleep" or st == "freeze" then
        emit(battle, Strings("But it failed!"))
        return
      end
      cureStatusOf(user)
      emit(battle, Strings("%s became healthy again!", nameOf(battle, user)))
    end,
  })

  ------------------------------------------------------------------
  -- TAKE HEART -- +1 SpA, +1 SpD, and cure the user. Showdown boosts
  -- first (so the "won't go higher" messages print even at +6) and then
  -- cures; success is either. Both halves always attempt.
  ------------------------------------------------------------------
  local function applyStage(battle, who, stat, delta)
    local lines = changeStage(battle, who, stat, delta, true, true) or {}
    for _, line in ipairs(lines) do emit(battle, line) end
  end

  mod.content.move_effects:register("GALAR_TAKEHEART_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = mod.exports.normalize(a, b, c)
      local battle, user = n.battle, n.user
      applyStage(battle, user, "spa", 1)
      applyStage(battle, user, "spd", 1)
      if cureStatusOf(user) then
        emit(battle, Strings("%s became healthy again!", nameOf(battle, user)))
      end
    end,
  })

  ------------------------------------------------------------------
  -- WISH -- a slot condition that heals the CURRENT occupant of the
  -- user's slot at the end of the FOLLOWING turn. Stored on the battle
  -- keyed by side (the "slot" in a 1v1 engine is exactly the side).
  -- turns = 2 because the end-of-turn pass runs once per turn: the first
  -- pass (same turn the wish was made) decrements 2 -> 1 with no heal
  -- (Showdown's `turn <= startingTurn` guard), the second pass (turn+1)
  -- decrements 1 -> 0 and heals -- the real "next turn" timing.
  ------------------------------------------------------------------
  local function wishesOn(battle)
    battle.__g9Wishes = battle.__g9Wishes or {}
    return battle.__g9Wishes
  end
  mod.exports.g9WishesOn = wishesOn

  mod.content.move_effects:register("GALAR_WISH_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = mod.exports.normalize(a, b, c)
      local battle, user = n.battle, n.user
      local maxHp = maxHpOf(user)
      if not maxHp then return end
      local side = battle.sideOf and battle:sideOf(user) or "player"
      wishesOn(battle)[side] = {
        hp = math.max(1, math.floor(maxHp / 2)),
        turns = 2,
      }
      emit(battle, Strings("%s made a wish!", nameOf(battle, user)))
    end,
  })

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    local wishes = battle and battle.__g9Wishes
    if not wishes then return end
    for side, wish in pairs(wishes) do
      wish.turns = (wish.turns or 0) - 1
      if wish.turns <= 0 then
        wishes[side] = nil
        local target = activeOf(battle, side)
        local healed = healAmount(battle, target, wish.hp)
        if healed and healed > 0 then
          emit(battle, Strings("%s's wish came true! Its HP was restored!",
            nameOf(battle, target)))
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- REVIVAL BLESSING -- fail when the user's side has nobody fainted;
  -- otherwise revive the first fainted party member to half max HP
  -- (moves.ts:15117-15119 gates it; the revive itself is side.ts's, here
  -- the natural 1v1 reduction of "restore a chosen fainted mon").
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_REVIVALBLESSING_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = mod.exports.normalize(a, b, c)
      local battle, user = n.battle, n.user
      local party = sidePartyOf(battle, user)
      local target
      for _, mon in ipairs(party) do
        local m = rawMon(mon)
        if m and (m.hp or 0) <= 0 and not m.isEgg then target = m break end
      end
      if not target then
        emit(battle, Strings("But it failed!"))
        return
      end
      local maxHp = maxHpOf(target) or 0
      target.hp = math.max(1, math.floor(maxHp / 2))
      target.fainted = false
      target.status = nil
      target.statusTurns = nil
      target.toxicCounter = nil
      emit(battle, Strings("%s was revived!", nameOf(battle, target)))
    end,
  })

  mod.content.moves:patch("AROMATHERAPY", { effect = "GALAR_AROMATHERAPY_EFFECT" })
  mod.content.moves:patch("HEALBELL", { effect = "GALAR_HEALBELL_EFFECT" })
  mod.content.moves:patch("JUNGLEHEALING", { effect = "GALAR_JUNGLEHEALING_EFFECT" })
  mod.content.moves:patch("REFRESH", { effect = "GALAR_REFRESH_EFFECT" })
  mod.content.moves:patch("TAKEHEART", { effect = "GALAR_TAKEHEART_EFFECT" })
  mod.content.moves:patch("WISH", { effect = "GALAR_WISH_EFFECT" })
  mod.content.moves:patch("REVIVALBLESSING", { effect = "GALAR_REVIVALBLESSING_EFFECT" })

  mod.log:info("g9-battle-engine: modern_party_support installed "
    .. "(AROMATHERAPY, HEALBELL, JUNGLEHEALING, REFRESH, TAKEHEART, WISH, "
    .. "REVIVALBLESSING)")
end
