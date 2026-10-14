-- Damage multipliers for the pipeline's SPECIAL-DAMAGE path only (round 17
-- rewrite). Real Showdown facts this encodes (verified against smogon/
-- pokemon-showdown, items.ts):
--   * Life Orb (onModifyDamage, a FINAL-damage multiplier) DOES scale
--     fixed-damage moves -- Seismic Toss is confirmed boosted by Life Orb.
--     So Life Orb is applied here to any event flagged specialDamage=true
--     (every fixed/OHKO/counter number legacy_move_takeover delivers).
--   * Choice Band / Choice Specs (onModifyAtk/SpA) and Silk Scarf
--     (onBasePower) are PRE-FORMULA multipliers -- they multiply a STAT or
--     a BASE POWER before the damage formula runs, so a fixed number (which
--     never goes through the formula) must NOT receive them. This is the
--     round-16 "known accepted limitation" resolved: the real fix is gating
--     THESE, not Life Orb (whose scaling of fixed numbers is faithful).
--   * The NORMAL-formula path applies its own item multipliers internally
--     (modern_held_items_phase2.lua), so for non-special damage this
--     function is an identity -- it must never double-apply.
return {
    calculate = function(event, current_damage)
        if not event or not event.attacker then return current_damage end
        if type(current_damage) ~= "number" then return current_damage end
        if not event.specialDamage then return current_damage end
        local item = event.attacker.item
        if not item then return current_damage end
        -- "LIFE_ORB" is the real registered id (modern_held_items_phase2);
        -- legacy "LIFEORB" (the old items/ stub-tree id) accepted too.
        if item == "LIFE_ORB" or item == "LIFEORB" then
            return current_damage * 1.3
        end
        return current_damage
    end,
}
