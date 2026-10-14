-- Terrain: Electric/Grassy/Misty/Psychic. Neither generation this mod runs
-- had any terrain concept at all (Terrain is Gen 6+) -- same "nothing
-- native to defer to or collide with" situation combat/trick_room.lua's
-- own header already documents, and this file follows that exact
-- precedent: Gen 2 only (this mod's own manifest scope), no dual-gen
-- branching, field state lives directly on the battle object
-- (battle.terrain/battle.terrainTurns), duration ticks off the real
-- battle.turn_ended event.
--
-- SOURCES: smogon/pokemon-showdown's own data/moves.ts, fetched directly
-- (not recalled from memory) -- electricterrain/grassyterrain/
-- mistyterrain/psychicterrain's own `condition` blocks, current Gen 9
-- Showdown behavior.
--
-- GROUNDED, stated honestly: this file's own isGrounded only checks for
-- the Flying type (curTypesOf, Transform/Tera-aware, already this mod's
-- own established primitive). Real terrain also respects Levitate,
-- Air Balloon, Iron Ball, Gravity, Ingrain, and Roost's temporary
-- grounding -- none of those exist in this engine yet (no ability system,
-- no Air Balloon/Iron Ball item effects, no Gravity move, no Ingrain), so
-- every terrain rule here is exactly as accurate as "is this mon a Flying
-- type right now" and no further -- a real, known gap, not silently
-- assumed complete.
--
-- SEMI-INVULNERABLE: battle:volatile(mon).vanished, the same real Gen 2
-- field a mid-Fly/Dig target already carries (confirmed elsewhere in this
-- mod, e.g. modern_movepool_status.lua's substitutedOut-adjacent checks) --
-- every real terrain rule exempts a semi-invulnerable target/attacker, not
-- guessed at here.
return function(mod)
  local Strings = require("src.core.Strings")
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  local curTypesOf = mod.exports.curTypesOf
  local registerDamageModifier = mod.exports.registerDamageModifier
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local FIELD_BASE_TURNS = mod.exports.FIELD_BASE_TURNS
  local FIELD_EXTENDED_TURNS = mod.exports.FIELD_EXTENDED_TURNS
  assert(curTypesOf and registerDamageModifier, "modern_terrain: combat/modern_combat.lua must load first")
  assert(resolveFieldDuration and FIELD_BASE_TURNS and FIELD_EXTENDED_TURNS,
    "modern_terrain: combat/field_duration.lua must load first")

  local function isGrounded(mon)
    -- Phase 8 Gravity (combat/modern_field_effects.lua): a grounded field
    -- makes every active mon count as grounded for terrain purposes too.
    if mon and (mon.gravityGrounded or (mon.mon and mon.mon.gravityGrounded)) then
      return true
    end
    for _, t in ipairs(curTypesOf(mon, true)) do
      if t == "FLYING" then return false end
    end
    return true
  end

  local function isSemiInvulnerable(battle, mon)
    return battle:volatile(mon).vanished == true
  end

  local function affectedByTerrain(battle, mon)
    return isGrounded(mon) and not isSemiInvulnerable(battle, mon)
  end

  ------------------------------------------------------------------
  -- The four starter moves. Same "already this exact terrain -> fails,
  -- a DIFFERENT one already up -> replaces it" rule this mod's own
  -- weatherStarter (modern_weather.lua) already establishes for weather --
  -- real current Showdown treats both the same way. accuracyChecked left
  -- unset: terrain affects the whole field, not the opponent specifically,
  -- same reasoning as every other field-wide primary() move in this mod.
  ------------------------------------------------------------------
  local TERRAIN_EXTEND_ITEM = "TERRAINEXTENDER"

  -- The generic terrain-setting primitive every terrain source shares -- a
  -- move today (terrainStarter below), an ability (abilities/engine/
  -- switchin_terrain.lua) once one exists: "already this exact terrain ->
  -- no-op, a DIFFERENT one already up -> replaces it," the real duration
  -- resolution (Terrain Extender included), and the field message.
  -- Extracted here, per explicit user directive to keep data and engine
  -- modular, so a move and an ability never duplicate this logic --
  -- returns false on the no-op case rather than emitting a failure message
  -- itself, since a move and an ability report "no effect" differently
  -- (a move says "But it failed!"; a real ability re-check is silent).
  function mod.exports.setTerrain(battle, setter, key, startText)
    if battle.terrain == key then return false end
    -- Boss-fight "mistyTerrain" protection (combat/boss_fight.lua): once
    -- active, only the boss's own side (battle.enemy) may ever touch
    -- terrain -- the player's side is refused outright (returns false,
    -- same "no-op" shape as the already-this-terrain case above), mirroring
    -- weather's own boss-lock tier in modern_combat.lua's canSetWeather.
    -- Real N-way check (2026-08-28): any enemy-side battler authorized,
    -- not just the literal battle.enemy object -- same generalization
    -- modern_combat.lua's own canSetWeather fix uses.
    local bossLocking = mod.exports.bossFightHas and mod.exports.bossFightHas(battle, "mistyTerrain")
    if bossLocking and battle:sideOf(setter) ~= "enemy" then return false end
    battle.terrain = key
    battle.terrainTurns = resolveFieldDuration(setter, FIELD_BASE_TURNS,
      FIELD_EXTENDED_TURNS, TERRAIN_EXTEND_ITEM)
    -- The boss's own terrain-set, under this protection, becomes
    -- permanent -- no per-mon "ends when the setter leaves" tracking
    -- needed here the way weather's primal lock has: unlike weather,
    -- nothing else in this file ever clears terrain except the turnTurns
    -- countdown itself, and math.huge never reaches it (Lua's own
    -- math.huge - 1 == math.huge).
    if bossLocking and battle:sideOf(setter) == "enemy" then
      battle.terrainTurns = math.huge
      battle.terrainBossLocked = true
    end
    battle:emit({ kind = "message", text = Strings(startText) })
    -- Shared notification (same idiom modern_combat.lua's own setWeather
    -- just added for this session's Phase 1.8): fired on every explicit
    -- terrain change this function makes. Terrain's own natural expiry
    -- is a DIRECT field write in this file's own battle.turn_ended
    -- listener below, not routed through this function -- that listener
    -- fires this same event itself, so between the two, every terrain
    -- transition on either generation is covered (unlike weather, Gen 2
    -- has no native terrain concept at all to collide with or be
    -- unreachable behind -- Terrain is Gen 6+, this mod's own decrement
    -- is the only mechanism on either engine).
    mod.events:emit("mod.1025dex.terrain_changed", { battle = battle, key = key })
    return true
  end

  local function terrainStarter(effectId, key, startText)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      run = function(battle, attacker, defender, def, moveId, sureHit)
        if not mod.exports.setTerrain(battle, attacker, key, startText) then
          battle:emit({ kind = "message", text = Strings("But it failed!") })
        end
      end,
    })
  end

  terrainStarter("G9_ELECTRICTERRAIN_EFFECT", "ELECTRIC", "An electric current ran across the battlefield!")
  terrainStarter("G9_GRASSYTERRAIN_EFFECT", "GRASSY", "Grass grew to cover the battlefield!")
  terrainStarter("G9_MISTYTERRAIN_EFFECT", "MISTY", "Mist swirled around the battlefield!")
  terrainStarter("G9_PSYCHICTERRAIN_EFFECT", "PSYCHIC", "The battlefield got weird!")

  mod.content.moves:patch("ELECTRICTERRAIN", { effect = "G9_ELECTRICTERRAIN_EFFECT" })
  mod.content.moves:patch("GRASSYTERRAIN", { effect = "G9_GRASSYTERRAIN_EFFECT" })
  mod.content.moves:patch("MISTYTERRAIN", { effect = "G9_MISTYTERRAIN_EFFECT" })
  mod.content.moves:patch("PSYCHICTERRAIN", { effect = "G9_PSYCHICTERRAIN_EFFECT" })

  ------------------------------------------------------------------
  -- Duration + Grassy Terrain's own residual heal, both off battle.
  -- turn_ended (the same real turn-boundary event trick_room.lua's own
  -- decrement uses). Real PS runs the per-mon heal (onResidualOrder: 5)
  -- BEFORE the terrain's own duration/end-message pass (onFieldResidual
  -- Order: 27) within the same residual phase -- mirrored here by healing
  -- first, decrementing after, so Grassy Terrain still heals on the exact
  -- turn it expires, same as real games.
  ------------------------------------------------------------------
  local TERRAIN_END_TEXT = {
    ELECTRIC = "The electricity disappeared from the battlefield.",
    GRASSY = "The grass disappeared from the battlefield.",
    MISTY = "The mist disappeared from the battlefield.",
    PSYCHIC = "The weirdness disappeared from the battlefield.",
  }

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle or not battle.terrain then return end

    if battle.terrain == "GRASSY" then
      for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
        if mon and (mon.hp or 0) > 0 and affectedByTerrain(battle, mon) then
          local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp
          if mon.hp < maxHp then
            local healed = math.max(1, math.floor(maxHp / 16))
            local tryHeal = mod.exports.g9TryHeal
            local restored
            if tryHeal then
              restored = tryHeal(battle, mon, healed)
            else
              mon.hp = math.min(maxHp, mon.hp + healed)
              restored = healed
            end
            if restored > 0 then
              battle:emit({ kind = "message",
                text = Strings("%s's HP was restored by the Grassy Terrain!", battle:monName(mon)) })
            end
          end
        end
      end
    end

    battle.terrainTurns = (battle.terrainTurns or 0) - 1
    if battle.terrainTurns <= 0 then
      local ended = battle.terrain
      battle.terrain = nil
      battle.terrainTurns = nil
      battle:emit({ kind = "message", text = Strings(TERRAIN_END_TEXT[ended] or "The terrain disappeared.") })
      -- Direct field write, not routed through setTerrain (see that
      -- function's own header) -- fired here instead, so every terrain
      -- transition is covered between the two emission points.
      mod.events:emit("mod.1025dex.terrain_changed", { battle = battle, key = nil })
    end
  end)

  ------------------------------------------------------------------
  -- Electric Terrain: a grounded, non-semi-invulnerable target can't be
  -- put to sleep. Misty Terrain: a grounded, non-semi-invulnerable target
  -- can't be inflicted with ANY major status, and can't be confused.
  --
  -- Wraps Battle:applyStatus/Battle:applyConfusion -- the real, dotted,
  -- class-level entry points every native and mod status/confusion source
  -- funnels through (confirmed, gen2/Battle.lua:2978/3026). The old
  -- caveat that this mod's own generic confusion secondary (main.lua's
  -- installMovepoolEffects) wrote battle:volatile(target).confuseCount
  -- directly -- and so slipped past this wrap -- is CLOSED (plan phase
  -- 12): main.lua now routes both that branch and Poison Puppeteer's own
  -- confusion through Battle:applyConfusion, keeping the direct write only
  -- as a fallback for a minimal battle stub with no applyConfusion method.
  ------------------------------------------------------------------
  if Battle then
    local nativeApplyStatus = Battle.applyStatus
    function Battle:applyStatus(mon, status, source)
      if self.terrain == "ELECTRIC" and status == "slp" and affectedByTerrain(self, mon) then
        self:emit({ kind = "message", text = Strings("The Electric Terrain prevents sleep!") })
        return false
      end
      if self.terrain == "MISTY" and affectedByTerrain(self, mon) then
        self:emit({ kind = "message", text = Strings("The Misty Terrain protects against status!") })
        return false
      end
      return nativeApplyStatus(self, mon, status, source)
    end

    local nativeApplyConfusion = Battle.applyConfusion
    function Battle:applyConfusion(mon, turns, source)
      if self.terrain == "MISTY" and affectedByTerrain(self, mon) then
        self:emit({ kind = "message", text = Strings("The Misty Terrain protects against confusion!") })
        return false
      end
      return nativeApplyConfusion(self, mon, turns, source)
    end

    ------------------------------------------------------------------
    -- Psychic Terrain: a grounded, non-semi-invulnerable target can't be
    -- hit by a positive-priority move used against it (self-targeted moves
    -- are never blocked -- irrelevant in this singles-only engine anyway,
    -- since attacker and defender are never the same battler here).
    --
    -- Known simplification: real Showdown still spends the move's PP and
    -- announces it (onTryHit nullifies only the move's own effect, the same
    -- "doesn't affect" shape modern_combat_protect.lua's Part D reuses for
    -- Protect). This wrap instead skips the native call entirely on a
    -- block -- no PP cost, no "used MOVE!" line -- a real, simpler behavior
    -- than the exact PS rule, not silently passed off as identical.
    ------------------------------------------------------------------
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if self.terrain == "PSYCHIC" and defender and defender ~= attacker then
        -- caster-aware since Phase 5 (abilities/engine/priority_change.lua):
        -- real Psychic Terrain also blocks a Prankster-boosted status move,
        -- which only reads as priority > 0 once movePriority knows WHO is
        -- using it -- without attacker here this would silently miss that
        -- real interaction (the move's own base priority is 0).
        local priority = self:movePriority(moveId, attacker)
        if priority and priority > 0 and affectedByTerrain(self, defender) then
          self:emit({ kind = "message",
            text = Strings("%s surrounds itself with psychic terrain!", self:monName(defender)) })
          return
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  ------------------------------------------------------------------
  -- Damage modifiers, one registerDamageModifier entry covering all four
  -- terrains (same "one entry, branch on the field state" shape modern_
  -- combat.lua's own old "weather" entry used before weather moved to its
  -- real pre-crit inline stage -- see that file's weatherDamageMultiplier).
  -- Priority 105: above STAB's 100 -- terrain and STAB never gate on the
  -- same condition, so relative order between them doesn't change the
  -- result, but this keeps every field-wide modifier grouped above the
  -- per-hit ones by convention.
  --
  -- 5325/4096 (~1.3x) is real current Showdown's own terrain-boost
  -- fraction (confirmed directly, same chainModify literal on all three
  -- boosting terrains) -- not a rounded 1.3, the exact fraction.
  ------------------------------------------------------------------
  local WEAKENED_BY_GRASSY = { EARTHQUAKE = true, BULLDOZE = true, MAGNITUDE = true }

  registerDamageModifier("terrain", 105, function(ctx)
    local battle, terrain = ctx.battle, ctx.battle and ctx.battle.terrain
    if not terrain then return 1.0 end
    local move = ctx.move
    if terrain == "ELECTRIC" then
      if move.type == "ELECTRIC" and affectedByTerrain(battle, ctx.user) then
        return 5325 / 4096
      end
    elseif terrain == "GRASSY" then
      if WEAKENED_BY_GRASSY[move.id] and affectedByTerrain(battle, ctx.target) then
        return 0.5
      end
      if move.type == "GRASS" and isGrounded(ctx.user) then
        return 5325 / 4096
      end
    elseif terrain == "MISTY" then
      if move.type == "DRAGON" and affectedByTerrain(battle, ctx.target) then
        return 0.5
      end
    elseif terrain == "PSYCHIC" then
      if move.type == "PSYCHIC" and affectedByTerrain(battle, ctx.user) then
        return 5325 / 4096
      end
    end
    return 1.0
  end)

  mod.log:info("g9-battle-engine: modern_terrain installed (Electric/Grassy/Misty/Psychic)")
end
