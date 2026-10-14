-- Dispatch engine for abilities/data/ko_boost.lua -- Phase 14 (ability
-- audit close-out), the KO-reward family. See that file's own header
-- for the full real-mechanic grounding. Real, confirmed trigger split:
--   MOXIE / CHILLINGNEIGH / GRIMNEIGH -- fire when THIS mon's own move
--   knocks out its target (battle.damage_dealt, move-caused only: the
--   KO must come from the move, not from hazards/recoil/weather -- the
--   same real move-causality rule BEAST BOOST/EELEVATE's own handler in
--   switch_priority_misc.lua already applies). Moxie and Chilling Neigh
--   raise Attack; Grim Neigh raises Sp. Atk.
--   SOULHEART -- +1 Sp. Atk whenever ANY Pokémon faints (either side,
--   real text says so), regardless of cause (battle.fainted).
--
-- All raises go through mod.exports.changeStage (fromEnemy=false, so no
-- boss gate / Mist interference on a positive self-raise), matching the
-- exact convention switch_priority_misc.lua's own BEAST BOOST handler
-- uses.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local isGen2Battle = mod.exports.isGen2Battle
  local changeStage = mod.exports.changeStage
  local allActiveBattlers = mod.exports.allActiveBattlers
  assert(abilityIdOf and isGen2Battle and changeStage and allActiveBattlers,
    "ko_boost: ability_dispatch.lua, modern_combat.lua must load first")

  local function hpOf(m) return (m and (m.mon or m) or {}).hp or 0 end

  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target = ev and ev.battle, ev and ev.user, ev and ev.target
    if not (battle and user and target and (ev.damage or 0) > 0) then return end
    local move = ev.move
    -- Move-caused KO only: BEAST BOOST's own real rule -- the KO must be
    -- landed by a move (move~=nil and move.id~=nil excludes Counter /
    -- Future Sight / hazards, which arrive with no move).
    if not (move and move.id) then return end
    if hpOf(target) > 0 then return end -- must actually have fainted it
    local id = abilityIdOf(user)
    local stat
    if data.MOXIE and id == "MOXIE" then stat = "attack"
    elseif data.CHILLINGNEIGH and id == "CHILLINGNEIGH" then stat = "attack"
    elseif data.GRIMNEIGH and id == "GRIMNEIGH" then stat = "spa"
    else return end
    for _, line in ipairs(changeStage(battle, user, stat, 1, false, isGen2Battle(battle)) or {}) do
      battle:emit({ kind = "message", text = line })
    end
  end)

  mod.events:on("battle.fainted", function(ev)
    local battle, fainted = ev and ev.battle, ev and ev.battler
    if not (battle and fainted) then return end
    local gen2 = isGen2Battle(battle)
    for _, mon in ipairs(allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and mon ~= fainted and hpOf(mon) > 0 and data.SOULHEART and abilityIdOf(mon) == "SOULHEART" then
        for _, line in ipairs(changeStage(battle, mon, "spa", 1, false, gen2) or {}) do
          battle:emit({ kind = "message", text = line })
        end
      end
    end
  end)

  mod.log:info("g9-battle-engine: ko_boost installed (MOXIE, CHILLINGNEIGH, GRIMNEIGH, SOULHEART)")
end
