-- Heal Block (the move) + the boss-fight "healblock" flag -- ONE gate for
-- every real HP-recovery source, both generations.
--
-- WHAT WAS WRONG (fixed here):
--   * The Heal Block MOVE (GALAR_HEALBLOCK_EFFECT, modern_status_volatiles
--     .lua) was only ever enforced by a `Battle:useMove` monkeypatch in that
--     same file -- which requires src.battle.gen2.Battle UNGUARDED, so the
--     whole file (Heal Block included) failed to boot on a Gen 1 game. On
--     Gen 1 the move existed in national_dex but did nothing at all.
--   * Even where it did install, it only refused moves carrying the `heal`
--     flag. Items (Potion/Berry Juice/Leftovers), abilities (absorb family,
--     Regenerator-style heals), drain, Grassy Terrain, Wish, Ingrain, Aqua
--     Ring and Leech Seed all still restored HP on a blocked mon.
--   * The boss-fight `healblock` flag (combat/boss_fight.lua) was a
--     DOCUMENTED NO-OP: nothing read it anywhere.
--
-- THE RULE (real Showdown `healblock` condition, `onTryHeal`): while a mon
-- is heal-blocked it cannot restore HP by ANY means. The boss flag applies
-- that same ban to the PLAYER's side of the field (explicit user rule,
-- 2026-09-10: "blocking recovering hp on ally side" -- "ally" in this
-- project's own vocabulary is the player's own side). A blocked heal is
-- BLOCKED -- it is never converted into damage (the antiDrain flag owns the
-- "corrected into self-harm" shape; this one does not).
--
-- THE PRIMITIVE: `mod.exports.healBlocked(battle, who)` answers the single
-- question, and `mod.exports.g9TryHeal(battle, who, amount)` is the one
-- write path every mod heal site now routes through. Native heals that this
-- mod does not own are caught by wrapping the generation's own heal
-- entry point (Gen 1 MoveEffects.RECORDS.HEAL_EFFECT.run; Gen 2 Battle:heal
-- and MOVE_EFFECT_RECORDS.EFFECT_HEAL). Both reads accept a battler wrapper
-- or a raw mon, and check the flag on EITHER (the two shapes this mod's
-- own status fields have historically landed on).
return function(mod)
  local Strings = require("src.core.Strings")
  local displayNameFor = mod.exports.displayNameFor
  local bossFightHas = mod.exports.bossFightHas
  local isGen2Battle = mod.exports.isGen2Battle
  local isGen1Battle = mod.exports.isGen1Battle

  local function rawMon(who) return who and (who.mon or who) or nil end

  -- "player"/"enemy"/nil, uniformly across both generations. Gen 1's
  -- BattleState:sideOf returns a side-record OBJECT (not a string), so it is
  -- deliberately NOT used here -- the battler wrapper's own isPlayer (set at
  -- makeBattler construction) is the reliable Gen 1 signal, `multiSide` is
  -- the scene tag, and identity against battle.player/enemy is the last
  -- resort.
  local function sideOf(battle, who)
    if not (battle and who) then return nil end
    local wrapper = who.mon and who or nil
    if wrapper and wrapper.isPlayer ~= nil then
      return wrapper.isPlayer and "player" or "enemy"
    end
    local m = rawMon(who)
    if not m then return nil end
    if m.multiSide then return m.multiSide end
    if m.isPlayer ~= nil then return m.isPlayer and "player" or "enemy" end
    if m == rawMon(battle.player) then return "player" end
    if m == rawMon(battle.enemy) then return "enemy" end
    if isGen2Battle and battle.sideOf then
      local ok, s = pcall(battle.sideOf, battle, who)
      if ok and (s == "player" or s == "enemy") then return s end
    end
    return nil
  end
  mod.exports.healBlockSideOf = sideOf

  -- The one predicate. Checks the volatile on BOTH the wrapper and the raw
  -- mon (the two shapes this mod's own fields have landed on), then the boss
  -- flag against the player's side.
  local function healBlocked(battle, who)
    if not (battle and who) then return false end
    local wrapper = who.mon and who or nil
    local m = rawMon(who)
    if (wrapper and (wrapper.healBlockTurns or 0) > 0)
      or (m and (m.healBlockTurns or 0) > 0) then
      return true
    end
    if bossFightHas and bossFightHas(battle, "healblock")
      and sideOf(battle, who) == "player" then
      return true
    end
    return false
  end
  mod.exports.healBlocked = healBlocked

  local function nameOf(battle, who)
    if displayNameFor then
      local gen2 = isGen2Battle and isGen2Battle(battle)
      local ok, n = pcall(displayNameFor, battle, who, gen2)
      if ok and n then return n end
    end
    local m = rawMon(who)
    return (m and (m.name or m.species)) or "The Pokemon"
  end

  -- Emit the blocked line, but at most once per mon per turn -- a blocked
  -- residual (Leftovers + Grassy Terrain + Leech Seed all on one mon) should
  -- read as one message, not three.
  local function notifyHealBlocked(battle, who)
    local m = rawMon(who)
    if not m then return end
    local turn = battle.turnCount or battle.turn or 0
    if m.__g9HealBlockNotifiedTurn == turn then return end
    m.__g9HealBlockNotifiedTurn = turn
    if battle.emit then
      battle:emit({ kind = "message",
        text = Strings("%s was prevented from healing!", nameOf(battle, who)) })
    end
  end
  mod.exports.notifyHealBlocked = notifyHealBlocked

  -- The single mod-side heal write path. Returns the HP actually restored
  -- (0 when blocked, or when already at full). `amount` is the desired
  -- positive heal.
  local function g9TryHeal(battle, who, amount)
    local m = rawMon(who)
    if not (battle and m) then return 0 end
    amount = math.floor(amount or 0)
    if amount <= 0 then return 0 end
    if healBlocked(battle, who) then
      notifyHealBlocked(battle, who)
      return 0
    end
    local maxHp = (m.stats and m.stats.hp) or m.maxHp or m.hp or 0
    if maxHp <= 0 then return 0 end
    local before = m.hp or 0
    if before >= maxHp then return 0 end
    m.hp = math.min(maxHp, before + amount)
    return m.hp - before
  end
  mod.exports.g9TryHeal = g9TryHeal

  -- Convenience read for the many call sites that only want the predicate and
  -- resolve it lazily (they boot before this file).
  mod.exports.g9HealBlocked = healBlocked

  ------------------------------------------------------------------
  -- MOVE-SELECTION gate: the scene menu (combat/move_usability.lua reads its
  -- registry) and combat/turn_order.lua's resolution backstop. A heal-flagged
  -- move is refused while healBlocked. Registered as a per-move gate lazily
  -- on first query is not possible (the registry is keyed by id and reads a
  -- fixed function), so this goes through a dedicated built-in hook that
  -- move_usability.lua calls for every move.
  ------------------------------------------------------------------
  mod.exports.healBlockMoveRefused = function(battle, mon, moveId)
    if not (battle and mon and moveId) then return nil end
    if not healBlocked(battle, mon) then return nil end
    local nationalDex = mod.find and mod.find("national_dex")
    local moveFlags = nationalDex and nationalDex.exports and nationalDex.exports.moveFlags
    if not moveFlags then return nil end
    local ok, flags = pcall(moveFlags, moveId)
    if not (ok and type(flags) == "table" and flags.heal) then return nil end
    return { flag = "healblock",
      reason = Strings("%s can't use healing moves!", nameOf(battle, mon)) }
  end

  ------------------------------------------------------------------
  -- NATIVE HEAL HIJACKS
  ------------------------------------------------------------------

  -- Gen 1: the native move-heal entry point (Recover/Rest/Soft-Boiled/
  -- Synthesis-family and every national_dex move mapped to HEAL_EFFECT).
  -- `ctx.user` is the battler wrapper. Blocked => the move fails outright
  -- (no Rest sleep, no partial heal), matching the real "Heal Block prevents
  -- the move" behaviour.
  do
    local ok, MoveEffects = pcall(require, "src.battle.MoveEffects")
    local record = ok and MoveEffects and MoveEffects.RECORDS
      and MoveEffects.RECORDS.HEAL_EFFECT
    if record and type(record.run) == "function" then
      local nativeRun = record.run
      record.run = function(ctx)
        local battle = ctx and ctx.battle
        local user = ctx and ctx.user
        if battle and user and healBlocked(battle, user) then
          notifyHealBlocked(battle, user)
          return { Strings("%s was prevented from healing!", nameOf(battle, user)) }
        end
        return nativeRun(ctx)
      end
    end
  end

  -- Gen 2: Battle:heal is the native HP-restore primitive, so wrapping it
  -- covers every native item/ability/residual heal that goes through it, and
  -- MOVE_EFFECT_RECORDS.EFFECT_HEAL is wrapped separately so a blocked Rest
  -- does not put its user to sleep first (the run records are the same table
  -- objects the merged live registry holds by reference, so this override is
  -- seen by both).
  local gen2ok, Battle = pcall(require, "src.battle.gen2.Battle")
  if gen2ok and type(Battle) == "table" then
    if type(Battle.heal) == "function" then
      local nativeHeal = Battle.heal
      function Battle:heal(mon, amount, opts)
        if mon and healBlocked(self, mon) then
          notifyHealBlocked(self, mon)
          return 0
        end
        return nativeHeal(self, mon, amount, opts)
      end
    end
    local records = Battle.MOVE_EFFECT_RECORDS
    local healRecord = records and records.EFFECT_HEAL
    if type(healRecord) == "table" and type(healRecord.run) == "function" then
      local nativeHealRun = healRecord.run
      healRecord.run = function(self, attacker, target, moveId)
        if attacker and healBlocked(self, attacker) then
          notifyHealBlocked(self, attacker)
          if self.markMissed then self:markMissed() end
          self:emit({ kind = "message",
            text = Strings("%s was prevented from healing!", nameOf(self, attacker)) })
          return
        end
        return nativeHealRun(self, attacker, target, moveId)
      end
    end
  end

  -- Gen 2 effect records are created once at boot from MOVE_EFFECTS; the
  -- merged live registry may hold a COPY for a mod-patched effect, so also
  -- wrap the MOVE_EFFECTS function itself when it exists.
  if gen2ok and type(Battle) == "table" and type(Battle.MOVE_EFFECTS) == "table"
    and type(Battle.MOVE_EFFECTS.EFFECT_HEAL) == "function" then
    local nativeEffectHeal = Battle.MOVE_EFFECTS.EFFECT_HEAL
    Battle.MOVE_EFFECTS.EFFECT_HEAL = function(self, attacker, target, moveInst, moveId)
      if attacker and healBlocked(self, attacker) then
        notifyHealBlocked(self, attacker)
        if self.markMissed then self:markMissed() end
        self:emit({ kind = "message",
          text = Strings("%s was prevented from healing!", nameOf(self, attacker)) })
        return
      end
      return nativeEffectHeal(self, attacker, target, moveInst, moveId)
    end
  end

  mod.log:info("g9-battle-engine: heal_block installed "
    .. "(Heal Block move + boss 'healblock' flag; all recovery sources gated, "
    .. "blocked never converted to damage; player side is the boss flag's target)")
end
