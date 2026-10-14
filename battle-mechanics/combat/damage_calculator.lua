-- Showdown-based Damage Calculation Core
-- Formula: (((2 * Level / 5 + 2) * Power * (Attack / Defense)) / 50) + 2
-- Self-contained: stat reads go straight to attacker.stats.attack / attacker.attack
-- with a safe fallback, so this never touches the ability stat_multiplier chain
-- (the real multipliers live in modern_combat's registerDamageModifier stack).

local M_DAMAGE_CALC = {}

local function statOf(mon, key)
  if not mon then return 10 end
  if mon.stats and type(mon.stats[key]) == "number" then return mon.stats[key] end
  if type(mon[key]) == "number" then return mon[key] end
  return 10
end

function M_DAMAGE_CALC.calculate_base_damage(attacker, defender, move)
  local level = (attacker and attacker.level) or 100
  local power = (move and move.power) or 0

  local attack = statOf(attacker, "attack")
  local defense = statOf(defender, "defense")

  -- Prevent division by zero
  if defense <= 0 then defense = 1 end

  -- Base damage formula (Simplified Showdown version for Gen 1/2 context)
  local base_damage = ((2 * level / 5 + 2) * power * (attack / defense)) / 50
  base_damage = base_damage + 2
  if base_damage < 1 then base_damage = 1 end

  return math.floor(base_damage)
end

return M_DAMAGE_CALC
