return {
    -- Mapping of Item ID -> Battle Effect Logic
    -- Based on Showdown mechanics

    ["LEFTY_SIDES"] = {
        onDamageCalculate = function(event, role)
            if role == "defender" then
                -- Leftovers: Logic handled in separate pipeline or here
                -- For simplicity in dispatch, we mark it; the pipeline handles the actual HP gain
            end
            return nil
        end
    },

    ["IRON_BALL"] = {
        onDamageCalculate = function(event, role)
            if role == "attacker" then
                -- Example: Item that might reduce speed/power
            end
            return nil
        end
    },

    ["FOCUS_SASH"] = {
        onDamageCalculate = function(event, role)
            -- Focus Sash logic goes here
            return nil
        end
    }
}
