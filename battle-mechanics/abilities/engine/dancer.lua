-- Dispatch engine for abilities/data/dancer.lua -- see that file's own
-- header for the real mechanic and its one honest simplification.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags,
    "dancer: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  local allActiveBattlers = mod.exports.allActiveBattlers
  assert(abilityIdOf and allActiveBattlers,
    "dancer: ability_dispatch.lua and move_targeting.lua must load first")

  -- Per-battle recursion guard -- prevents a Dancer's own copied use
  -- from cascading into a second round of copies (see this file's own
  -- data header on the real, honest scope cut this represents).
  local guard = setmetatable({}, { __mode = "k" })

  local function cascade(battle, nativeFn, attacker, defender, moveId)
    if guard[battle] then return end
    local flags = moveFlags(moveId)
    if not (flags and flags.dance) then return end
    guard[battle] = true
    local ok, err = pcall(function()
      for _, mon in ipairs(allActiveBattlers(battle) or {}) do
        if mon and mon ~= attacker and (mon.hp or 0) > 0 and data.DANCER
            and abilityIdOf(mon) == "DANCER" then
          battle:emit({ kind = "message", text = Strings("The DANCE was mirrored!") })
          nativeFn(battle, mon, defender, moveId)
        end
      end
    end)
    guard[battle] = nil
    if not ok then mod.log:warn("g9-battle-engine: dancer cascade failed: %s", tostring(err)) end
  end

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
    local nativeUseMoveDancer = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      local result = nativeUseMoveDancer(self, attacker, defender, moveId)
      cascade(self, nativeUseMoveDancer, attacker, defender, moveId)
      return result
    end
  end

  local BattleState = require("src.battle.BattleState")
  local nativePerformMoveDancer = rawget(BattleState, "performMove")
  if type(nativePerformMoveDancer) == "function" then
  function BattleState:performMove(user, target, moveInst, isCalled)
    local result = nativePerformMoveDancer(self, user, target, moveInst, isCalled)
    local moveId = moveInst and moveInst.id
    if moveId then
      cascade(self, function(battle, mon, tgt, id)
        nativePerformMoveDancer(battle, mon, tgt, moveInst, true)
      end, user, target, moveId)
    end
    return result
  end
  end

  mod.log:info("g9-battle-engine: dancer installed (DANCER)")
end
