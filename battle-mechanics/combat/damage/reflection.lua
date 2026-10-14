-- Implements Showdown-based damage reflection logic
-- Rule: Calculate true damage via Showdown formulas, pass results to engine
--
-- NOTE: contact-recoil ability/item effects -- Iron Barbs and Rough Skin
-- (abilities/engine/contact_retaliation.lua) and Rocky Helmet (combat/
-- modern_held_items_phase2.lua) -- are deliberately NOT here. Showdown
-- applies them from `onDamagingHit`, AFTER the hit has resolved, so this
-- mod applies them as real secondary damage from the post-hit
-- `battle.damage_dealt` event. Doing it from inside this battle.damage
-- wrap would re-enter the wrap (recursion) and, for the Counter family,
-- double-apply damage those moves already deal themselves (combat/
-- modern_movepool_counter.lua). This module therefore only reports the
-- Counter family.
return {
  calculate = function(event)
    if not event then return { reflected = false } end
    local attacker = event.attacker
    local damage = event.damage or 0
    local move = event.move

    local reflection_damage = 0
    local reflection_source = nil

    -- 1. Move-based Reflection (Active)
    -- Logic: Counter (Physical) and Mirror Coat (Special)
    -- These typically reflect 100% of damage back if the condition is met
    if move and move.id == "COUNTER" and event.category == "PHYSICAL" then
      reflection_damage = damage
      reflection_source = "MOVE_COUNTER"
    elseif move and move.id == "MIRROR_COAT" and event.category == "SPECIAL" then
      reflection_damage = damage
      reflection_source = "MOVE_MIRROR_COAT"
    end

    if reflection_damage > 0 then
      -- We return a structure that the damage_pipeline can use to trigger
      -- a second damage event in the correct order.
      return {
        reflected = true,
        damage = reflection_damage,
        source = reflection_source,
        target = attacker,
      }
    end

    return { reflected = false }
  end,
}
