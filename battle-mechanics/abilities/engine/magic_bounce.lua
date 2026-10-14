-- Dispatch engine for abilities/data/magic_bounce.lua -- see that
-- file's own header for the real scope and grounding.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags,
    "magic_bounce: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  local displayNameFor = mod.exports.displayNameFor
  local isGen2Battle = mod.exports.isGen2Battle
  local sideOfWho = mod.exports.sideOfWho
  assert(abilityIdOf and displayNameFor and isGen2Battle and sideOfWho,
    "magic_bounce: ability_dispatch.lua and modern_combat.lua must load first")

  -- Real Showdown logic, verified before writing anything here (this
  -- file's own first draft approximated with damageClass=="status" and
  -- target=="selected-pokemon" -- WRONG, caught by explicit user
  -- correction: real Magic Bounce gates on ONE flag, `reflectable`
  -- (national_dex's own moveFlags(id).reflectable -- confirmed real and
  -- live, sourced directly from Showdown's own moves.json, e.g.
  -- STEALTHROCK's own real flags record: {metronome=true,
  -- mustpressure=true, reflectable=true}). That single flag already
  -- covers BOTH single-target status moves (Thunder Wave, Toxic, Will-
  -- O-Wisp -- all confirmed reflectable=true) AND field-wide entry-
  -- hazard moves (Stealth Rock, Spikes, Toxic Spikes, Sticky Web --
  -- ALL confirmed reflectable=true too) uniformly -- there was never a
  -- real reason to exclude hazards by target-string, and doing so was
  -- this file's own real bug, not a deliberate scope cut.
  --
  -- Hazards bouncing correctly is a property of the redirect mechanism
  -- itself, not something this file has to special-case: combat/
  -- modern_hazards.lua's own real setters (GALAR_STEALTHROCK_EFFECT
  -- etc.) resolve WHICH SIDE gets the hazard via
  -- `n.battle:sideOf(n.target)` -- i.e. off whoever the CURRENT move's
  -- target argument is, not a fixed field. Once this file's own whole-
  -- move redirect swaps attacker<->defender and re-dispatches through
  -- the real native entry point, that same setter naturally reads the
  -- NEW target (the original attacker) and sets the hazard on THEIR
  -- side -- exactly the real, correct Magic Bounce outcome, with zero
  -- extra code needed here for the hazard case specifically.
  --
  -- Real side check added too (Showdown's own onAllyTryHitSide
  -- explicitly excludes an ally's own move from bouncing, only an
  -- OPPONENT's move bounces) -- this engine's own real N-way
  -- battle:sideOf makes that check free to add correctly.
  local function bounceable(battle, moveId, attacker, defender, gen2)
    if not (data.MAGICBOUNCE and abilityIdOf(defender) == "MAGICBOUNCE") then return false end
    -- Real Showdown: an ally's own move never bounces, only an
    -- opponent's -- sideOfWho (modern_combat.lua) is the one real
    -- accessor that correctly handles both generations' own side
    -- representations (Gen 2's plain "player"/"enemy" strings vs. Gen
    -- 1's own side-record object), rather than a raw battle:sideOf call
    -- that only means the Gen 2 shape.
    if battle and sideOfWho(battle, attacker, gen2) == sideOfWho(battle, defender, gen2) then
      return false
    end
    local flags = moveFlags(moveId)
    return flags ~= nil and flags.reflectable == true
  end

  -- Recursion guard: prevents an infinite bounce if the move somehow
  -- gets redirected onto ANOTHER Magic Bounce holder (or reflects back
  -- onto a holder facing itself in an edge case) -- real Showdown caps
  -- a move at exactly one bounce. Keyed per-battle so two unrelated
  -- battles (never actually concurrent in this engine, but cheap
  -- insurance) can't cross-contaminate each other's guard state.
  local bounced = setmetatable({}, { __mode = "k" })

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMoveBounce = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      local guard = bounced[self]
      if defender and attacker and defender ~= attacker and not (guard and guard[moveId])
          and bounceable(self, moveId, attacker, defender, true) then
        self:emit({ kind = "message",
          text = Strings("%s bounced the move back!", displayNameFor(self, defender, true)) })
        bounced[self] = guard or {}
        bounced[self][moveId] = true
        local ok, err = pcall(nativeUseMoveBounce, self, defender, attacker, moveId)
        bounced[self][moveId] = nil
        if not ok then mod.log:warn("g9-battle-engine: magic_bounce redirect failed: %s", tostring(err)) end
        return
      end
      return nativeUseMoveBounce(self, attacker, defender, moveId)
    end
  end

  local BattleState = require("src.battle.BattleState")
  local nativePerformMoveBounce = rawget(BattleState, "performMove")
  local boundGen1 = setmetatable({}, { __mode = "k" })
  if type(nativePerformMoveBounce) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    local moveId = moveInst and moveInst.id
    local guard = boundGen1[self]
    if moveId and target and user and target ~= user and not (guard and guard[moveId])
        and bounceable(self, moveId, user, target, false) then
      self:sayNext(Strings("%s bounced the move back!", displayNameFor(self, target, false)))
      boundGen1[self] = guard or {}
      boundGen1[self][moveId] = true
      local ok, err = pcall(nativePerformMoveBounce, self, target, user, moveInst, isCalled)
      boundGen1[self][moveId] = nil
      if not ok then mod.log:warn("g9-battle-engine: magic_bounce redirect failed: %s", tostring(err)) end
      return
    end
    return nativePerformMoveBounce(self, user, target, moveInst, isCalled)
  end
  end

  mod.log:info("g9-battle-engine: magic_bounce installed (MAGICBOUNCE)")
end
