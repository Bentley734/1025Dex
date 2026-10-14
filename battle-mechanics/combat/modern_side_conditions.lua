-- Phase 7 of the missing-effects pipeline: side conditions, screens and
-- hazard manipulation.
--
-- Showdown source of truth (scratch/showdown/moves.ts -- read by direct
-- extraction this session; line numbers cited per clause):
--   courtchange (3032-3098): Normal, Status, basePower 0, accuracy 100,
--     `target: "all"`, `flags: { mirror: 1, metronome: 1 }` (NOTE: NOT
--     reflectable -- Magic Coat/Magic Bounce deliberately do not bounce
--     it). `onHitField(target, source)` builds the fixed swappable list
--     `['mist','lightscreen','reflect','spikes','safeguard','tailwind',
--     'toxicspikes','stealthrock','waterpledge','firepledge',
--     'grasspledge','stickyweb','auroraveil','luckychant',
--     'gmaxsteelsurge','gmaxcannonade','gmaxvinelash','gmaxwildfire',
--     'gmaxvolcalith']`, lifts every matching condition off BOTH sides
--     into temps, then puts each side's temp onto the OTHER side. `success`
--     is true iff anything at all moved; `if (!success) return false;`
--     then emits `-swapsideconditions` and `-activate move: Court Change`.
--   brickbreak (1822-1837) and psychicfangs (14061-14076): damaging,
--     `onTryHit(pokemon)` removes `reflect`/`lightscreen`/`auroraveil`
--     from `pokemon.side` -- "will shatter screens through sub, before
--     you hit". `onTryHit` runs before the accuracy roll and before the
--     damage calculation, so the move's OWN hit is not screened.
--   defog (3448-3481): Flying, Status, basePower 0, `accuracy: true`,
--     `flags: { protect: 1, reflectable: 1, mirror: 1, bypasssub: 1,
--     metronome: 1 }`, `target: "normal"`. `onHit(target, source)`:
--     `if (!target.volatiles['substitute'] || move.infiltrates) success =
--     !!this.boost({evasion: -1})`; then removes `['reflect','lightscreen',
--     'auroraveil','safeguard','mist', ...hazards]` from the TARGET's
--     side, `[...hazards]` from the SOURCE's side (hazards = spikes,
--     toxicspikes, stealthrock, stickyweb, gmaxsteelsurge), calls
--     `this.field.clearTerrain()`, and returns `success`.
--   magiccoat (10692-10731): Psychic, Status, basePower 0, `accuracy:
--     true`, `priority: 4`, `flags: { metronome: 1 }` -- NOT
--     reflectable (a coat can't bounce a coat). `volatileStatus:
--     'magiccoat'`, `condition.duration = 1`. `onTryHitPriority: 2
--     onTryHit(target, source, move)`: if `target === source` or
--     `move.hasBounced` or `!move.flags['reflectable']` or the target is
--     semi-invulnerable, do nothing; else re-run the move with
--     `target`/`source` swapped (one bounce per move).
--   snatch (17105-17151): Dark, Status, basePower 0, `accuracy: true`,
--     `priority: 4`, `flags: { bypasssub: 1, mustpressure: 1, noassist:
--     1, failcopycat: 1 }`. `volatileStatus: 'snatch'`, `duration 1`.
--     `onAnyPrepareHitPriority: -1 onAnyPrepareHit(source, target,
--     move)`: if the move has `flags.snatch` and `move.sourceEffect ~=
--     'snatch'`, the snatch holder removes its volatile and uses the move
--     itself (i.e. steals any self/field status move the opponent threw).
--   imprison (9490-9535): Psychic, Status, basePower 0, `accuracy:
--     true`, `flags: { snatch: 1, bypasssub: 1, metronome: 1,
--     mustpressure: 1 }`. `volatileStatus: 'imprison'`, `noCopy: true`.
--     `onFoeDisableMove(pokemon)` disables every move in the holder's
--     `moveSlots` on the FOE; `onFoeBeforeMove` cancels the move if the
--     holder knows it. i.e. while active, the opponent cannot use any
--     move the holder also knows.
--
-- Design notes for this engine:
--   * Court Change / Defog / Magic Coat / Snatch / Imprison are power-0
--     status moves, so they use the Gen 2 primary dispatch (`kind =
--     "primary"`, a `run` handler, return value discarded --
--     combat/SUBEFFECTS.md). Brick Break / Psychic Fangs are DAMAGING:
--     a primary record with a `run` would bypass the damage path
--     entirely (gen2/Battle.lua:1750-1755 -- `handler(...); return`), so
--     they get an empty `kind = "full"` record (exactly Rapid Spin's
--     precedent in combat/modern_hazards.lua:295-300) and the screen
--     shatter is wired through the class-level `Battle:useMove` wrap
--     instead.
--   * The `Battle:useMove` wrap is the established interception seam
--     (modern_combat_protect.lua Part D, abilities/engine/magic_bounce.lua,
--     combat/modern_action_order.lua). Magic Coat is literally the
--     single-turn, flag-gated twin of the Magic Bounce ability, so it
--     reuses that file's exact redirect shape: swap attacker/defender and
--     re-dispatch through the captured native `useMove`, guarded against a
--     second bounce. Snatch is the same shape, but the thief becomes both
--     attacker and defender because the stolen move is self/field-targeted.
--   * This engine models genuinely side-keyed state as:
--       screens = battle.screens[side] = { lightScreen, reflect, safeguard }
--         (gen2/Battle.lua:364, :854-857, Battle.LINK_SCREENS at :5389 --
--          the engine's own definitive swappable-screen list),
--       native spikes = battle.spikes[side] (a 0-3 layer count), and
--       this mod's own hazards = battle.hazards[side] = { stealthRock,
--         toxicSpikes, sharpSteel, stickyWeb } (combat/modern_hazards.lua's
--         exported hazardsFor accessor).
--     Tailwind, Aurora Veil and Lucky Chant were added to this same table by
--     Phase 8's combat/modern_field_effects.lua, so they are swapped too. The
--     remaining names in Showdown's swappable list (the pledge/gmax side
--     conditions) are still not modelled, so Court Change moves everything
--     that IS -- see the honest partials in the plan.
--   * Mist is a per-MON volatile here (gen2/Battle.lua:2043), not a side
--     condition the way Showdown stores it, so Court Change does not swap
--     it; that asymmetry is noted rather than faked.
return function(mod)
  local Strings = require("src.core.Strings")

  local normalize = mod.exports.normalize
  local displayNameFor = mod.exports.displayNameFor
  local sideOfWho = mod.exports.sideOfWho
  local isGen2Battle = mod.exports.isGen2Battle
  assert(normalize and displayNameFor and sideOfWho and isGen2Battle,
    "modern_side_conditions: combat/modern_combat.lua must load first")

  local hazardsFor = mod.exports.hazardsFor
  assert(hazardsFor,
    "modern_side_conditions: combat/modern_hazards.lua must load first")

  local nationalDex = mod.find and mod.find("national_dex")
  local moveFlags = nationalDex and nationalDex.exports and nationalDex.exports.moveFlags

  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil

  ------------------------------------------------------------------
  -- Shared helpers.
  ------------------------------------------------------------------

  local function emit(battle, text)
    if battle and battle.emit then
      battle:emit({ kind = "message", text = text })
    end
  end

  -- Accept either a bare mon or a battler wrapper (every helper in this
  -- mod's party-wide files uses this same unwrap).
  local function rawMon(who)
    return who and (who.mon or who) or nil
  end

  local function otherSide(side)
    return side == "enemy" and "player" or "enemy"
  end

  -- The live screens table for a side, created lazily exactly the way the
  -- native constructor seeds it (gen2/Battle.lua:364 self.screens =
  -- { player = {}, enemy = {} }).
  local function screensOf(battle, side)
    battle.screens = battle.screens or { player = {}, enemy = {} }
    battle.screens[side] = battle.screens[side] or {}
    return battle.screens[side]
  end

  local function spikesOf(battle, side)
    local s = battle.spikes and battle.spikes[side]
    return s or 0
  end

  local function setSpikes(battle, side, n)
    battle.spikes = battle.spikes or {}
    battle.spikes[side] = n
  end

  -- The mod's own hazard store fields, in one place so Court Change/Defog
  -- can't drift from each other. combat/modern_hazards.lua owns the table
  -- shape (hazardsFor above); these names are the exact fields the Rapid
  -- Spin clear already writes (modern_hazards.lua:322-326).
  local HAZARD_FIELDS = { "stealthRock", "toxicSpikes", "sharpSteel", "stickyWeb" }

  local function hasAnyHazard(h)
    return h.stealthRock == true or (h.toxicSpikes or 0) > 0
      or h.sharpSteel == true or h.stickyWeb == true
  end

  local function clearHazards(h)
    h.stealthRock = false
    h.toxicSpikes = 0
    h.sharpSteel = false
    h.stickyWeb = false
  end

  -- national_dex's flag reader, nil-safe and pcall-guarded (a harness/engine
  -- without the flag payload must not crash the interception path).
  local function hasFlag(moveId, flag)
    if not (moveFlags and moveId) then return false end
    local ok, flags = pcall(moveFlags, moveId)
    if not ok or type(flags) ~= "table" then return false end
    return flags[flag] == true
  end

  -- The mon currently active on the side OPPOSITE `attacker` -- the only
  -- candidate that can intercept attacker's move (Magic Coat/Snatch).
  -- battle.player/battle.enemy are the engine's own live pointers.
  local function opposingActive(battle, attacker)
    if not (battle and attacker) then return nil end
    local side = sideOfWho(battle, attacker, true)
    if side == "player" then return battle.enemy end
    return battle.player
  end

  -- The terrain-end vocabulary, mirrored from combat/modern_terrain.lua's
  -- own TERRAIN_END_TEXT (that table is file-local; Defog has to clear the
  -- field the same way the duration tick does).
  local TERRAIN_END_TEXT = {
    ELECTRIC = "The electricity disappeared from the battlefield.",
    GRASSY = "The grass disappeared from the battlefield.",
    MISTY = "The mist disappeared from the battlefield.",
    PSYCHIC = "The weirdness disappeared from the battlefield.",
  }

  local function clearTerrain(battle)
    if not (battle and battle.terrain) then return false end
    local ended = battle.terrain
    battle.terrain = nil
    battle.terrainTurns = nil
    emit(battle, Strings(TERRAIN_END_TEXT[ended] or "The terrain disappeared."))
    mod.events:emit("mod.1025dex.terrain_changed", { battle = battle, key = nil })
    return true
  end
  -- Exported (Phase 18, missing-effects plan): Ice Spinner / Steel Roller
  -- both end with Showdown's own `this.field.clearTerrain()` (moves.ts:
  -- 9418 / :17894), and this file already owns the one real terrain-end
  -- routine (Defog's own use of it, just below). combat/
  -- modern_guard_contact.lua reuses this exact function rather than
  -- re-deriving the end-of-terrain text/state-clearing a second time.
  mod.exports.clearTerrain = clearTerrain

  ------------------------------------------------------------------
  -- COURT CHANGE -- swap the swappable side conditions between the two
  -- sides. `target: "all"` is a field-wide effect in a 1v1 engine; the
  -- "source side" is the user's side and the "target side" its foe.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_COURTCHANGE_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local side = sideOfWho(battle, user, true)
      local foe = otherSide(side)
      local success = false

      -- screens (lightScreen / reflect / safeguard), the engine's own
      -- Battle.LINK_SCREENS list.
      local mine, theirs = screensOf(battle, side), screensOf(battle, foe)
      -- Phase 8 (combat/modern_field_effects.lua) stores Tailwind, Aurora Veil
      -- and Lucky Chant in this same per-side table, and all three are in
      -- Showdown's courtchange swap list, so they move with the rest.
      for _, field in ipairs({ "lightScreen", "reflect", "safeguard",
          "auroraVeil", "luckyChant", "tailwind" }) do
        local mv, tv = mine[field] or 0, theirs[field] or 0
        if mv > 0 or tv > 0 then success = true end
        mine[field], theirs[field] = tv, mv
      end

      -- native Spikes layer count.
      local mySpikes, theirSpikes = spikesOf(battle, side), spikesOf(battle, foe)
      if mySpikes > 0 or theirSpikes > 0 then success = true end
      setSpikes(battle, side, theirSpikes)
      setSpikes(battle, foe, mySpikes)

      -- this mod's own hazards.
      local myH, theirH = hazardsFor(battle, side), hazardsFor(battle, foe)
      if hasAnyHazard(myH) or hasAnyHazard(theirH) then success = true end
      for _, field in ipairs(HAZARD_FIELDS) do
        myH[field], theirH[field] = theirH[field], myH[field]
      end

      if not success then
        emit(battle, Strings("But it failed!"))
        return
      end
      emit(battle, Strings("%s swapped the battle effects on both sides!",
        displayNameFor(battle, user, true)))
    end,
  })

  ------------------------------------------------------------------
  -- BRICK BREAK / PSYCHIC FANGS -- shatter the defender's screens before
  -- the hit lands. The empty kind="full" record leaves the ordinary
  -- damage path untouched (national_dex's own damage data still applies);
  -- the shatter rides the useMove wrap below so it happens BEFORE the
  -- damage formula reads screenActive -- i.e. the move's own hit is not
  -- halved by the screen it just broke, matching Showdown's onTryHit.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_BRICKBREAK_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GALAR_PSYCHICFANGS_EFFECT", { kind = "full" })

  local SHATTER_MOVES = { BRICKBREAK = true, PSYCHICFANGS = true }

  -- Remove reflect/lightscreen from the defender's side (Showdown only
  -- names those two plus auroraveil, which this engine doesn't model --
  -- safeguard is deliberately NOT touched). True iff anything was up.
  local function shatterScreens(battle, attacker, defender)
    if not (battle and defender) then return false end
    local side = sideOfWho(battle, defender, true)
    local screens = screensOf(battle, side)
    local broke = false
    if (screens.reflect or 0) > 0 then screens.reflect = 0; broke = true end
    if (screens.lightScreen or 0) > 0 then screens.lightScreen = 0; broke = true end
    -- Showdown's brickbreak/psychicfangs onTryHit also removes auroraveil.
    if (screens.auroraVeil or 0) > 0 then screens.auroraVeil = 0; broke = true end
    if broke then
      emit(battle, Strings("%s shattered the opposing screens!",
        displayNameFor(battle, attacker, true)))
    end
    return broke
  end

  ------------------------------------------------------------------
  -- DEFOG -- clear the target side's screens + hazards, the user side's
  -- hazards, lower the target's evasion (unless it's behind a
  -- Substitute), and clear the terrain.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_DEFOG_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user, target = n.battle, n.user, n.target
      if not (battle and user) then return end
      if not target or target == user then target = battle.enemy or battle.player end
      local success = false

      -- The evasion drop, skipped behind a Substitute (bypasssub not
      -- modelled -- this engine's changeStage already handles the
      -- Substitute/Mist gate when it runs).
      local targetVol = target and target.volatile
      local behindSub = targetVol and (targetVol.substitute or 0) > 0
      if target and not behindSub then
        pcall(function()
          mod.exports.changeStage(battle, target, "evasion", -1, true, true)
        end)
        success = true
      end

      -- Target side: screens + every hazard.
      local foe = otherSide(sideOfWho(battle, user, true))
      local foeScreens = screensOf(battle, foe)
      -- Showdown's defog removeAll list for screens:
      -- reflect/lightscreen/auroraveil/safeguard/mist. Aurora Veil is Phase
      -- 8's (combat/modern_field_effects.lua); Tailwind and Lucky Chant are
      -- deliberately NOT cleared (not in defog's list).
      for _, field in ipairs({ "lightScreen", "reflect", "safeguard", "auroraVeil" }) do
        if (foeScreens[field] or 0) > 0 then foeScreens[field] = 0; success = true end
      end
      local foeH = hazardsFor(battle, foe)
      if hasAnyHazard(foeH) then
        clearHazards(foeH)
        emit(battle, Strings("It blew away the hazards around %s's team!",
          displayNameFor(battle, target or user, true)))
        success = true
      end
      if spikesOf(battle, foe) > 0 then
        setSpikes(battle, foe, 0)
        success = true
      end

      -- User side: every hazard (not screens -- Showdown's removeAll list).
      local selfSide = sideOfWho(battle, user, true)
      local selfH = hazardsFor(battle, selfSide)
      if hasAnyHazard(selfH) then
        clearHazards(selfH)
        success = true
      end
      if spikesOf(battle, selfSide) > 0 then
        setSpikes(battle, selfSide, 0)
        success = true
      end

      -- Field: terrain.
      if clearTerrain(battle) then success = true end

      if not success then
        emit(battle, Strings("But it failed!"))
        return
      end
      emit(battle, Strings("%s blew away the obstacles!",
        displayNameFor(battle, user, true)))
    end,
  })

  ------------------------------------------------------------------
  -- MAGIC COAT -- arm a one-turn volatile; the useMove wrap below bounces
  -- the next reflectable move aimed at this side back at its user.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_MAGICCOAT_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local m = rawMon(user)
      m.volatile = m.volatile or {}
      m.volatile.magiccoat = true
      emit(battle, Strings("%s covered itself with a mysterious veil!",
        displayNameFor(battle, user, true)))
    end,
  })

  ------------------------------------------------------------------
  -- SNATCH -- arm a one-turn volatile; the useMove wrap below steals the
  -- next snatchable (self/field status) move the opponent throws.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_SNATCH_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local m = rawMon(user)
      m.volatile = m.volatile or {}
      m.volatile.snatch = true
      emit(battle, Strings("%s waits to snatch a move!",
        displayNameFor(battle, user, true)))
    end,
  })

  ------------------------------------------------------------------
  -- IMPRISON -- record the user's current moveset in a persistent volatile;
  -- the usableMoves wrap below removes those moves from the opponent.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_IMPRISON_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local battle, user = n.battle, n.user
      if not (battle and user) then return end
      local holder = rawMon(user)
      holder.volatile = holder.volatile or {}
      local ids = {}
      for _, ms in ipairs(holder.moves or {}) do
        if ms.id then ids[ms.id] = true end
      end
      holder.volatile.imprison = true
      holder.volatile.imprisonMoves = ids
      emit(battle, Strings("%s sealed the opponent's moves!",
        displayNameFor(battle, user, true)))
    end,
  })

  ------------------------------------------------------------------
  -- The interception seam. One class-level wrap handles both the Brick
  -- Break shatter (keyed on the move id, before native) and the Magic
  -- Coat / Snatch redirects (keyed on the opposing active's volatile).
  ------------------------------------------------------------------
  if Battle then
    local nativeUseMove = Battle.useMove
    local bouncing = setmetatable({}, { __mode = "k" })

    local function tryIntercept(battle, attacker, moveId)
      local interceptor = opposingActive(battle, attacker)
      if not (interceptor and interceptor ~= attacker) then return nil end
      local vol = rawMon(interceptor).volatile
      if not vol then return nil end

      -- Magic Coat: bounce a reflectable move back at its user. The guard
      -- is per battle+move so a coat-vs-coat edge can't loop (Showdown caps
      -- a move at one bounce, and the bounced move's own coat is consumed).
      if vol.magiccoat and hasFlag(moveId, "reflectable") then
        local guard = bouncing[battle]
        if guard and guard[moveId] then return nil end
        vol.magiccoat = nil
        emit(battle, Strings("%s bounced the move back!",
          displayNameFor(battle, interceptor, true)))
        bouncing[battle] = guard or {}
        bouncing[battle][moveId] = true
        local result = nativeUseMove(battle, interceptor, attacker, moveId)
        if bouncing[battle] then bouncing[battle][moveId] = nil end
        return result
      end

      -- Snatch: steal a snatch-flagged self/field move. The thief becomes
      -- both attacker and defender because that move targets its own user
      -- (Swords Dance/Recover/Reflect/...).
      if vol.snatch and hasFlag(moveId, "snatch") then
        local guard = bouncing[battle]
        if guard and guard[moveId] then return nil end
        vol.snatch = nil
        emit(battle, Strings("%s snatched the move!",
          displayNameFor(battle, interceptor, true)))
        bouncing[battle] = guard or {}
        bouncing[battle][moveId] = true
        local result = nativeUseMove(battle, interceptor, interceptor, moveId)
        if bouncing[battle] then bouncing[battle][moveId] = nil end
        return result
      end

      return nil
    end

    function Battle:useMove(attacker, defender, moveId)
      if moveId and attacker then
        if SHATTER_MOVES[moveId] and defender and defender ~= attacker then
          local ok, err = pcall(shatterScreens, self, attacker, defender)
          if not ok then
            mod.log:warn("g9-battle-engine: modern_side_conditions: "
              .. "screen shatter failed: %s", tostring(err))
          end
        end
        local ok, handed = pcall(tryIntercept, self, attacker, moveId)
        if not ok then
          mod.log:warn("g9-battle-engine: modern_side_conditions: "
            .. "interception failed: %s", tostring(handed))
        elseif handed ~= nil then
          return handed
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  ------------------------------------------------------------------
  -- The per-mon ban list Imprison applies to the opposing side. Reads the
  -- real party arrays (battle.party / battle.enemyParty), exactly the
  -- whole-side scope combat/modern_party_support.lua introduced.
  ------------------------------------------------------------------
  local function imprisonedMovesAgainst(battle, mon)
    if not (battle and mon) then return nil end
    local side = sideOfWho(battle, mon, true)
    local foes = (side == "player") and (battle.enemyParty or {}) or (battle.party or {})
    local banned
    for _, other in ipairs(foes) do
      local m = rawMon(other)
      local vol = m and m.volatile
      if vol and vol.imprison then
        banned = banned or {}
        for id in pairs(vol.imprisonMoves or {}) do banned[id] = true end
      end
    end
    return banned
  end

  if Battle then
    local nativeUsableMoves = Battle.usableMoves
    function Battle:usableMoves(mon)
      local out
      if type(nativeUsableMoves) == "function" then
        out = nativeUsableMoves(self, mon)
      else
        out = {}
        for _, mv in ipairs((mon and mon.moves) or {}) do out[#out + 1] = mv end
      end
      local banned = imprisonedMovesAgainst(self, mon)
      if not banned then return out end
      local filtered = {}
      for _, mv in ipairs(out or {}) do
        if not (mv and mv.id and banned[mv.id]) then filtered[#filtered + 1] = mv end
      end
      return filtered
    end
  end

  ------------------------------------------------------------------
  -- Turn-end expiry for the one-turn volatiles (Showdown duration 1).
  -- Native switch handling already drops a mon's whole volatile table
  -- (gen2/Battle.lua:1114), so this only has to cover the end of the turn
  -- the move was used on.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local allActive = mod.exports.allActiveBattlers
    local list = allActive and allActive(battle) or { battle.player, battle.enemy }
    for _, who in ipairs(list) do
      local m = rawMon(who)
      local vol = m and m.volatile
      if vol then
        vol.magiccoat = nil
        vol.snatch = nil
      end
    end
  end)

  mod.content.moves:patch("COURTCHANGE", { effect = "GALAR_COURTCHANGE_EFFECT" })
  mod.content.moves:patch("BRICKBREAK", { effect = "GALAR_BRICKBREAK_EFFECT" })
  mod.content.moves:patch("PSYCHICFANGS", { effect = "GALAR_PSYCHICFANGS_EFFECT" })
  mod.content.moves:patch("DEFOG", { effect = "GALAR_DEFOG_EFFECT" })
  mod.content.moves:patch("MAGICCOAT", { effect = "GALAR_MAGICCOAT_EFFECT" })
  mod.content.moves:patch("SNATCH", { effect = "GALAR_SNATCH_EFFECT" })
  mod.content.moves:patch("IMPRISON", { effect = "GALAR_IMPRISON_EFFECT" })

  mod.log:info("g9-battle-engine: modern_side_conditions installed "
    .. "(COURTCHANGE, BRICKBREAK, PSYCHICFANGS, DEFOG, MAGICCOAT, SNATCH, IMPRISON)")
end
