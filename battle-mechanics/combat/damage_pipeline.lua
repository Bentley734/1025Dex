-- Damage pipeline: the dispatch brain for this mod. Loaded by main.lua AFTER
-- the item system and ability_dispatch are booted; process(next, ctx) is the
-- battle.damage wrap at priority 500 (above modern_combat's formula at 0, which
-- never calls next), so next(ctx) resolves the whole chain down to the formula
-- and the dispatchers below see the final number.
local damage_calc = require("combat/damage_calculator")
local item_combat = require("items/item_dispatch")
local damage_modifiers = require("items/engine/damage_modifiers")
local damage_reflection = require("combat/damage/reflection")

return function(mod)
  local M_DAMAGE_PIPELINE = {
    calculate_base_damage = function(attacker, defender, move)
      return damage_calc.calculate_base_damage(attacker, defender, move)
    end,
  }

  -- The Order of Operations for Showdown-style damage. The engine's battle.damage
  -- ctx uses ctx.user / ctx.target / ctx.move (NOT attacker/defender).
  function M_DAMAGE_PIPELINE.process(next, ctx)
    local dmg, info = next(ctx)
    if type(dmg) ~= "number" then dmg = 0 end

    local ev = {
      type = "onDamageCalculate",
      attacker = ctx.user,
      defender = ctx.target,
      move = ctx.move,
      damage = dmg,
      -- Round 17: set by every special-damage move's info.trueDamage flag
      -- (legacy_move_takeover's fixed/OHKO/counter numbers) -- read here so
      -- damage_modifiers below can apply Showdown's Life Orb to a fixed
      -- number while NEVER applying Choice/type-boost (those are pre-formula
      -- multipliers in Showdown).
      specialDamage = (info and info.trueDamage) or nil,
    }
    if ev.move and ev.move.category then
      ev.category = tostring(ev.move.category):upper()
    end

    -- 1. Item system first (held items can grant immunities / interrupts)
    local item_res = item_combat.dispatch(ev)
    if item_res == "INTERRUPT" then
      return 0, info
    end

    -- 2. Flat damage modifiers (Life Orb / Choice items)
    local boosted = damage_modifiers.calculate(ev, dmg)
    if type(boosted) == "number" then
      dmg = boosted
      ev.damage = dmg
    end

    -- 2b. "Survive at 1 HP" -- STURDY / FOCUS SASH. Round 17: moved here
    -- from abilities/engine/damage_immunity.lua's own battle.damage wrap
    -- (priority 40, which runs BELOW this 500 wrap on the way up) so the
    -- clamp sees the FINAL damage -- Showdown's own onDamage event runs at
    -- priority -30/-40, AFTER Life Orb's onModifyDamage at 100, and a Life
    -- Orb user must not be able to boost a capped hp-1 back into a KO.
    -- Sturdy's OHKO block (full 0-damage block, Showdown onTryHit) stays in
    -- damage_immunity; this stage is only the survive-at-1 half, shared by
    -- Sturdy and Focus Sash (Sash consumes itself -- the one real
    -- difference, Showdown items.ts onDamage `useItem`).
    local defender = ev.defender
    if defender and dmg and dmg > 0 then
      local m = defender.mon or defender
      local maxHp = (m.stats and m.stats.hp) or m.maxhp
      local hp = m.hp or 0
      local atFull = maxHp and hp == maxHp and hp > 1
      if atFull and dmg >= hp and ev.move and ev.attacker ~= defender then
        local abilityIdOf = mod.exports.abilityIdOf
        local sturdy = abilityIdOf and abilityIdOf(defender) == "STURDY"
        local sash = defender.item == "FOCUS_SASH"
        if sturdy or sash then
          if sash then defender.item = nil end
          dmg = hp - 1
          ev.damage = dmg
        end
      end
    end

    -- 3. Ability system (side-effect routing: stat multipliers, prevention)
    if M_DAMAGE_PIPELINE.ability_system then
      M_DAMAGE_PIPELINE.ability_system.dispatch(ev)
    end

    -- 4. Damage reflection (Counter family only). Contact recoil -- Iron
    -- Barbs / Rough Skin (abilities/engine/contact_retaliation.lua) and
    -- Rocky Helmet (combat/modern_held_items_phase2.lua) -- is applied as
    -- real secondary damage from the post-hit `battle.damage_dealt` event,
    -- never from inside this wrap (that would re-enter battle.damage).
    local reflect = damage_reflection.calculate(ev)
    if reflect and reflect.reflected then
      mod.log:info(string.format("Damage reflection: %d from %s (move-owned)", reflect.damage, reflect.source))
    end

    return dmg, info
  end

  return M_DAMAGE_PIPELINE
end
