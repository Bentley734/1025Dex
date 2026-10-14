-- Dispatch engine for abilities/data/trap_abilities.lua -- Phase 7 of the
-- ability roadmap (ARENATRAP, SHADOWTAG, MAGNETPULL, RUNAWAY).
--
-- GEN 2 ONLY, real reason (not a shortcut): Gen 2's own native trap
-- system already has exactly the real choke point this family needs --
-- `Battle:switchLocked()` (gen2/Battle.lua:3710), which TryPlayerSwitch's
-- own real cartridge logic (`.check_trapped`) already gates a VOLUNTARY
-- switch on, reading `self:volatile(self.enemy).trapsTarget` -- the same
-- flag Mean Look/Block/Spider Web already set. Wrapped (not written into
-- directly, to avoid colliding with a real Mean Look-set flag) so the
-- final answer is "native says locked, OR an ability says locked."
--
-- Gen 1 has no equivalent choke point in this engine at all -- confirmed
-- by direct read: `BattleState.lua` has exactly one public switch entry
-- point, `resolveSwitch(newMon)`, called directly by the menu layer with
-- no separate "can I switch" gate anywhere upstream of it (Gen 1's own
-- real trapping, Bind/Wrap/Fire Spin, blocks switching as a SIDE EFFECT
-- of locking the whole turn via `target.trappingTurns`'s "can't move"
-- check -- cartridge-accurate for a move-based trap, but not the shape an
-- ability-based trap needs, since the trapped mon must still be able to
-- attack normally). Refusing inside resolveSwitch itself is not attempted
-- here -- this codebase has no confirmed-safe way to abort a menu-driven
-- switch mid-flight without risking a silent hang, a real, structural gap
-- named rather than guessed around.
return function(mod, data)
  local abilityIdOf = mod.exports.abilityIdOf
  local curTypesOf = mod.exports.curTypesOf
  assert(abilityIdOf and curTypesOf,
    "trap_abilities: ability_dispatch.lua and modern_combat.lua must load first")

  local function hasType(mon, gen2, wanted)
    for _, t in ipairs(curTypesOf(mon, gen2)) do
      if t == wanted then return true end
    end
    return false
  end

  -- Real, confirmed per-ability exemption on the TARGET (the mon that
  -- would be trapped), checked in addition to Run Away's own blanket
  -- immunity below.
  local function exempt(id, holder, target, gen2)
    if id == "ARENATRAP" then
      -- Levitate's own Ground-move immunity isn't built anywhere in this
      -- ability system yet (a real, separate, un-numbered gap -- it's a
      -- type_immunity-kind ability, not part of this prevent-kind phase)
      -- -- exempted here by ability id directly rather than waiting on
      -- that, so this stays correct the moment it is built. Magnet
      -- Rise/Telekinesis-style TEMPORARY airborne isn't checked (a
      -- narrower, honestly smaller gap than "unbuilt").
      return hasType(target, gen2, "FLYING") or abilityIdOf(target) == "LEVITATE"
    end
    if id == "SHADOWTAG" then
      return hasType(target, gen2, "GHOST") or abilityIdOf(target) == "SHADOWTAG"
    end
    if id == "MAGNETPULL" then
      -- Inverted shape: Magnet Pull traps ONLY a Steel-type target.
      return not hasType(target, gen2, "STEEL")
    end
    return false
  end

  local function trapAbilityBlocks(battle, holder, target)
    if not (holder and target) then return false end
    local id = holder and abilityIdOf(holder)
    if not (id and data[id]) then return false end
    if abilityIdOf(target) == "RUNAWAY" and data.RUNAWAY then return false end
    local gen2 = true -- this whole file only ever runs on Gen 2, see header
    return not exempt(id, holder, target, gen2)
  end
  mod.exports.trapAbilityBlocks = trapAbilityBlocks

  local gen2BattleOk, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2BattleOk and Battle or nil
  if Battle then
  local nativeSwitchLocked = Battle.switchLocked
  function Battle:switchLocked()
    if nativeSwitchLocked(self) then return true end
    -- Real N-way check (2026-08-28): native switchLocked is itself
    -- parameterless (always "is self.player trapped" -- the real
    -- cartridge check has no concept of checking any other slot), so the
    -- fix here is on the HOLDER side -- any currently active enemy-side
    -- battler with a trap ability, not just literal self.enemy, can trap
    -- self.player. mod.exports.allActiveBattlers (combat/move_targeting
    -- .lua) is the real roster; falls back to the native pair if that
    -- primitive somehow isn't loaded yet.
    local allActiveBattlers = mod.exports.allActiveBattlers
    local roster = allActiveBattlers and allActiveBattlers(self) or { self.player, self.enemy }
    for _, holder in ipairs(roster) do
      if self:sideOf(holder) == "enemy" and trapAbilityBlocks(self, holder, self.player) then
        return true
      end
    end
    return false
  end
  end

  mod.log:info("g9-battle-engine: trap_abilities installed (ARENATRAP, SHADOWTAG, MAGNETPULL, RUNAWAY -- Gen 2 only)")
end
