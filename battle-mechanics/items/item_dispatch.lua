-- Legacy item dispatcher. Superseded by the combat/modern_* item layer;
-- kept only because combat/damage_pipeline.lua still requires and calls it.
-- Phase 30 (item-effects plan) fixed its held-item read: it used to look at
-- `mon.heldItem`, a field that does not exist anywhere in this engine -- a
-- Gen 2 mon stores its item on `mon.item` (gen2/Mon.lua:296). It stayed
-- inert either way because items/data/items_battle.lua is a no-op stub, but
-- the wrong field would have silently ignored any future data entry.
return function(mod)
    local items_battle = require("items/data/items_battle")

    local function dispatch(event)
        -- Process items for both attacker and defender if applicable
        local targets = {
            { role = "attacker", mon = event.attacker },
            { role = "defender", mon = event.defender }
        }

        for _, target in ipairs(targets) do
            local mon = target.mon
            if mon and mon.item then
                local item_id = mon.item
                local effect = items_battle[item_id]

                if effect then
                    if event.type == "onDamageCalculate" then
                        -- Check if the item modifies damage for the role (e.g., Leftovers for defender)
                        if effect.onDamageCalculate then
                            local res = effect.onDamageCalculate(event, target.role)
                            if res == "INTERRUPT" then return "INTERRUPT" end
                        end
                    end

                    if event.type == "onSwitchIn" and effect.onSwitchIn then
                        effect.onSwitchIn(event)
                    end
                end
            end
        end

        return nil
    end

    return {
        dispatch = dispatch
    }
end
