-- Move targeting resolver -- the seam described in combat/
-- MULTI_BATTLE_HOOKS.md's own header ("we own combat resolution... you
-- own only which battlers exist"), extended from turn order to
-- targeting: this engine does not know or track battlefield position at
-- all (confirmed standing answer this session), so it never computes
-- adjacency itself.
--
-- REDESIGNED 2026-08-27: the first pass of this file had battle scene
-- calling a query function (moveNeedsAdjacency) before deciding whether
-- to call the resolver -- rightly rejected. That put a comparator over
-- move data on battle scene's side for a fact only this mod needs to
-- know in the first place. WE own the move's real target archetype
-- (national_dex's own `target` field); WE are the one deciding whether
-- a given move-use needs anything beyond the one target the caller
-- already has. Battle scene's only job is to answer a request IF one
-- ever arrives, never to decide when that should happen.
--
-- The trigger is therefore on OUR side, fired through the same hook bus
-- combat/turn_order.lua already uses for battle.turn_order (confirmed
-- generic, not engine-exclusive: src/mods/Runtime.lua's Runtime.call/
-- Hooks:call takes a name, a vanilla fallback, and the call args; any
-- code can fire one, any mod can intercept one via mod.hooks:wrap).
-- mod.exports.resolveMoveTargets below calls Runtime.call("g9.
-- request_adjacency", ...) ITSELF, and only for the two archetypes that
-- genuinely cannot be satisfied by the one already-known target --
-- battle scene never inspects a moveId or a flag to decide whether to
-- respond; it just implements one handler that reports real battlefield
-- position whenever asked:
--
--   mod.hooks:wrap("g9.request_adjacency", function(nextFn, battle, caster, moveId)
--     return { allies = {...}, enemies = {...} }  -- real roster, caster excluded
--   end, 0, "your-mod-id")
--
-- No comparator on that side at all -- it answers a position query, full
-- stop. A battle-scene mod that hasn't wrapped the hook yet (today's
-- only real format, 1v1) gets the built-in fallback below instead, which
-- degrades correctly to the native two-battler case with zero wiring.
--
-- Real PokeAPI/Showdown target archetypes, confirmed directly against
-- live national_dex records before writing any of this (not guessed):
--   "selected-pokemon" -- the overwhelming majority of moves (confirmed:
--     Axe Kick, Bullet Seed, Cross Poison, and every other single-target
--     move sampled this session). The caller already knows who this is
--     -- same role as useMove's own `defender` parameter -- so this
--     never needs the adjacency hook at all, distance-flagged or not.
--     moveFlags(id).distance only matters to whatever UI builds the
--     target picker (it may offer any battler, not just adjacent ones)
--     -- a battle-scene concern, not something this resolver re-validates
--     after the fact.
--   "all-other-pokemon" -- Earthquake, Surf (confirmed directly): hits
--     every adjacent battler except the caster, both sides at once --
--     "user as center." Genuinely needs the real roster -- triggers the
--     hook.
--   "all-opponents" -- Muddy Water (confirmed directly): every adjacent
--     enemy, never allies. Also triggers the hook.
-- Flame Burst was checked as a candidate fourth archetype ("requires a
-- target, splashes to the target's own adjacent allies") and confirmed
-- NOT to be one -- its own live record is plain target="selected-
-- pokemon"; the splash is a custom secondary effect in its prose `effect`
-- text, not a targeting type national_dex's own `target` field
-- expresses. Not built here for that reason -- it belongs with this
-- mod's own per-move secondary-effect work, not the generic targeting
-- resolver.
return function(mod)
  local Runtime = require("src.mods.Runtime")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "move_targeting: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById

  -- Built-in fallback for "g9.request_adjacency" when no battle-scene mod
  -- has wrapped it yet -- today's only real format, the native two-
  -- battler engine. caster is always either battle.player or
  -- battle.enemy here (no third slot exists in this engine, confirmed in
  -- MULTI_BATTLE_HOOKS.md), so the other one is the only possible real
  -- adjacent enemy and there are no allies to report at all. Correct
  -- degradation, not a guess: an all-other-pokemon/all-opponents move in
  -- a 1v1 fight really does only ever have the one enemy to hit.
  local function rawSide(b)
    if b == nil then return nil end
    return b.mon or b
  end
  local function nativeFallbackAdjacency(battle, caster)
    -- Gen 1 battlers are wrappers around a raw mon (`battle.player.mon`),
    -- while Gen 2's battlers ARE the raw mon, and a battle-scene mod's own
    -- g9.request_adjacency always answers with RAW mons (`battler.mon`). This
    -- fallback therefore answers raw mons too, and matches the caster in
    -- either form -- otherwise `allActiveBattlers`, the switch-in/ally-scope
    -- ability seam (which hands engines raw mons and guards on `.hp`), and
    -- `resolveMoveTargets` (whose Gen-1 consumers pass their targets straight
    -- into `battle:useMove` and read `.hp`) would each receive a wrapper that
    -- carries neither `.hp` nor `.ability`.
    local playerMon = rawSide(battle.player)
    local casterMon = rawSide(caster)
    if caster == battle.player or caster == playerMon or casterMon == playerMon then
      return { allies = {}, enemies = { rawSide(battle.enemy) } }
    end
    return { allies = {}, enemies = { rawSide(battle.player) } }
  end

  -- requestAdjacency(battle, caster, moveId) -> { allies = {...}, enemies = {...} }
  -- The shared primitive underneath resolveMoveTargets, also exported
  -- directly for anything else that needs real adjacent-battler position
  -- and isn't itself resolving a move's target list -- switch-in
  -- abilities with a "foes" scope (Intimidate/Intrepid Sword/Dauntless
  -- Shield) are the first real case: they need "every adjacent enemy,"
  -- the same question a spread MOVE asks, just triggered by a switch-in
  -- instead of a move-use. moveId is optional here (nil for a non-move
  -- trigger) -- a wrapped handler never inspects it anyway (see this
  -- file's own header: "no move-awareness... it answers a position
  -- query"), so the ability case and the move case share the exact same
  -- hook and the exact same battle-scene-side contract, with nothing new
  -- for battle scene to implement.
  mod.exports.requestAdjacency = function(battle, caster, moveId)
    local adjacency = Runtime.call("g9.request_adjacency", nativeFallbackAdjacency, battle, caster, moveId)
    adjacency = adjacency or {}
    return { allies = adjacency.allies or {}, enemies = adjacency.enemies or {} }
  end

  -- requestOpposite(battle, caster) -> the single battler DIRECTLY OPPOSITE
  -- the caster's own battlefield slot, or nil when that exact opposing slot
  -- is empty or its occupant is not standing. This is the position question
  -- Pokemon Showdown's Imposter asks -- `pokemon.side.foe.active[pokemon
  -- .position]` (abilities.ts:2123): the ability transforms into the foe in
  -- the SAME slot column, and does NOTHING when there is no such foe. It
  -- never falls back to a different foe and never to an ally.
  --
  -- Answered by the SAME battle-scene seam as requestAdjacency (the
  -- `g9.request_opposite` hook), so this engine still tracks no battlefield
  -- position itself: the scene owns its columns (battle_screen.lua's
  -- playerBattlers[i]/enemyBattlers[i] are index-aligned) and answers the
  -- hook. A scene that has not wrapped it gets nativeFallbackOpposite below
  -- -- in a 1-vs-1 fight the one other battler IS the one directly opposite.
  -- caster may be an engine battler or a raw mon (the engine's callers pass
  -- the raw mon, matching the adjacency contract).
  local function nativeFallbackOpposite(battle, caster)
    if not (battle and battle.player) then return nil end
    local raw = rawSide(caster)
    local playerMon = rawSide(battle.player)
    local enemyMon = rawSide(battle.enemy)
    if raw == playerMon then return enemyMon end
    if raw == enemyMon then return playerMon end
    -- caster is not one of the two native slots: a plain native battle has no
    -- other battler to be opposite at all.
    return nil
  end
  mod.exports.requestOpposite = function(battle, caster)
    return Runtime.call("g9.request_opposite", nativeFallbackOpposite, battle, caster)
  end

  ------------------------------------------------------------------
  -- allActiveBattlers(battle): the real, N-way "every mon currently in
  -- this battle" roster -- explicit user request (2026-08-28), the fix
  -- for the ~26 sites across this mod that used to hardcode `{battle
  -- .player, battle.enemy}` to mean "everyone in the battle," which was
  -- only ever true for the native two-battler case and silently missed
  -- battler #2/#3 the moment g9-Battle-Scene's own real doubles/triples
  -- rosters (confirmed live this session) were in play. Built on the
  -- SAME real primitive already answering this question for targeting
  -- (requestAdjacency) rather than a second, parallel roster-discovery
  -- mechanism -- {battle.player} + its own allies + its own enemies IS
  -- everyone, since requestAdjacency's own contract already guarantees
  -- "real roster, caster excluded" for both halves. Degrades correctly
  -- to exactly {battle.player, battle.enemy} with zero wiring on the
  -- native two-battler fallback (allies=empty, enemies={the other one}),
  -- so every one of those ~26 call sites keeps its own existing alive-
  -- ness/logic untouched -- only the iterable source changes.
  mod.exports.allActiveBattlers = function(battle)
    if not (battle and battle.player) then return {} end
    local out = { battle.player }
    local adjacency = mod.exports.requestAdjacency(battle, battle.player, nil)
    for _, m in ipairs(adjacency.allies) do out[#out + 1] = m end
    for _, m in ipairs(adjacency.enemies) do out[#out + 1] = m end
    return out
  end

  ------------------------------------------------------------------
  -- Battle:sideOf, made real N-way aware -- explicit user request
  -- (2026-08-28), closing the exact gap this mod's own MULTI_BATTLE_HOOKS
  -- .md already named: the native method is a hard binary (`(mon == self
  -- .player) and "player" or "enemy"`), so any battler beyond the primary
  -- pair got silently tagged "enemy" regardless of its real side --
  -- confirmed to matter for real, live consumers of this exact method:
  -- native dealDamage's own event tagging, and this mod's own hazards
  -- switch-in code (combat/modern_hazards.lua calls battle:sideOf(mon)
  -- directly).
  --
  -- Reads a plain per-mon tag, `mon.multiSide`, a real string ("player"/
  -- "enemy") a battle-scene mod sets on the actual mon table when it
  -- constructs that battler -- g9-Battle-Scene's own combat.lua now does
  -- exactly this (Combat.newBattler). Falls through to the native binary
  -- check when the tag is absent, so this is fully backward compatible:
  -- a plain native battle (no scene mod tagging anything) behaves
  -- identically to before. Gen 2 only -- g9-Battle-Scene (the one real
  -- multi-battler consumer confirmed to exist) is itself Gen 2-only
  -- (manifest.json: games = ["gen2"]); Gen 1's own BattleState:sideOf is
  -- untouched, an honest, currently-moot gap (no Gen 1 multi-battler
  -- caller exists to fix this for yet).
  local gen2Ok_Battle, Battle = pcall(require, "src.battle.gen2.Battle")
  Battle = gen2Ok_Battle and Battle or nil
  if Battle then
    local nativeSideOfMulti = Battle.sideOf
    function Battle:sideOf(mon)
      -- nil guard, checked before ever reaching the native ternary: the
      -- native `(mon == self.player) and "player" or "enemy"` answers
      -- "enemy" for a nil mon too (nil is never == self.player), a real,
      -- pre-existing quirk that's harmless for every EXISTING caller (every
      -- one of them already only ever calls sideOf with a real mon) but
      -- would misclassify a genuinely absent setter/caster as enemy-side
      -- for a NEW caller that passes one through unchecked -- "no mon, no
      -- side" is the more correct answer, so it's short-circuited here
      -- rather than trusted to the native fallback.
      if not mon then return nil end
      if mon.multiSide then return mon.multiSide end
      return nativeSideOfMulti(self, mon)
    end
  end

  -- resolveMoveTargets(battle, caster, moveId, chosenTarget) -> array of
  -- real battlers, possibly empty. chosenTarget is whatever single mon
  -- the caller already has in hand -- the same thing it would otherwise
  -- pass straight to battle:useMove as the defender -- never a separately
  -- built "adjacency bundle." We only reach past it, via requestAdjacency
  -- above, for the two archetypes that structurally need more than one
  -- target.
  mod.exports.resolveMoveTargets = function(battle, caster, moveId, chosenTarget)
    local info = moveById(moveId)
    local realTarget = info and info.target or "selected-pokemon"

    if realTarget ~= "all-other-pokemon" and realTarget ~= "all-opponents" then
      if chosenTarget then return { chosenTarget } end
      return {}
    end

    local adjacency = mod.exports.requestAdjacency(battle, caster, moveId)
    local allies = adjacency.allies
    local enemies = adjacency.enemies

    if realTarget == "all-other-pokemon" then
      local out = {}
      for _, m in ipairs(allies) do out[#out + 1] = m end
      for _, m in ipairs(enemies) do out[#out + 1] = m end
      return out
    end

    -- "all-opponents"
    local out = {}
    for _, m in ipairs(enemies) do out[#out + 1] = m end
    return out
  end

  -- isSpreadMove(moveId) -> boolean. The one targeting fact a battle
  -- scene's UI genuinely needs to know on ITS side -- to skip its target
  -- picker for moves that structurally need no pick (LEER, Muddy Water,
  -- Earthquake, Surf, ...) -- kept here next to resolveMoveTargets so
  -- both stay driven by the same single source of truth, national_dex's
  -- own `target` archetype. resolveTurnActions also consults it to decide
  -- whether to expand a queued action's single placeholder target.
  mod.exports.isSpreadMove = function(moveId)
    local info = moveById(moveId)
    local t = info and info.target or "selected-pokemon"
    return t == "all-opponents" or t == "all-other-pokemon"
  end

  ------------------------------------------------------------------
  -- ROUND 26 (2026-09-10): mid-turn faint redirection. In a
  -- multi-battler battle two actions can pick the SAME target, and the
  -- first one to resolve can faint it before the second is delivered.
  -- The real rule (and the user's explicit spec): a move aimed at a FOE
  -- redirects to another live adjacent foe; a move aimed at an ALLY has
  -- no other legal recipient and simply FAILS (Heal Pulse aimed at an
  -- ally that fainted first fails -- it must never "revive" the corpse
  -- by healing it, and an enemy move must never be applied to a fainted
  -- mon at all). combat/turn_order.lua's resolveTurnActions consults
  -- these three helpers at resolution time; they live here, next to the
  -- rest of the target-archetype knowledge, so the whole "who can this
  -- move hit" domain stays in one place.
  ------------------------------------------------------------------

  -- targetArchetypeOf(moveId) -> national_dex's own `target` string, with
  -- the same "selected-pokemon" default resolveMoveTargets/isSpreadMove
  -- use. The single fact every redirection decision below is built on.
  mod.exports.targetArchetypeOf = function(moveId)
    local info = moveById(moveId)
    return (info and info.target) or "selected-pokemon"
  end

  -- Archetypes whose single chosen recipient IS on the caster's own side
  -- and cannot be swapped for anyone else: Helping Hand and Aromatic Mist
  -- ("ally"), Acupressure ("user-or-ally"). A fainted chosen target means
  -- the move FAILS. Deliberately NOT including "all-allies" /
  -- "user-and-allies" here -- those affect the whole side and their
  -- chosen target is only a UI placeholder, so they still resolve with
  -- the rest of the side intact.
  local ALLY_RECIPIENT_ARCHETYPES = {
    ["ally"] = true,
    ["user-or-ally"] = true,
  }
  mod.exports.isAllyDirectedMove = function(moveId)
    return ALLY_RECIPIENT_ARCHETYPES[mod.exports.targetArchetypeOf(moveId)] == true
  end

  -- isAllyOnlyMove(moveId) -> boolean. True for a move whose ONLY legal
  -- recipient is on the caster's own side: the inherently ally-directed
  -- archetypes ("ally" -- Helping Hand, Aromatic Mist; "user-or-ally" --
  -- Acupressure) plus the selected-pokemon HEAL moves (Heal Pulse / Floral
  -- Healing -- national_dex files them under "selected-pokemon" with
  -- category="heal", healing=50, but Showdown gives them `adjacentAlly`). A
  -- battle scene's target picker must offer NO foe for one of these, and in
  -- singles (no ally) the move is USED and FAILS rather than being silently
  -- applied to the lone enemy -- the reported Helping Hand / Heal Pulse bug.
  mod.exports.isAllyOnlyMove = function(moveId)
    local info = moveById(moveId)
    local archetype = (info and info.target) or "selected-pokemon"
    if archetype == "ally" or archetype == "user-or-ally" then return true end
    if archetype == "selected-pokemon"
        and ((info.healing or 0) > 0 or info.category == "heal") then
      return true
    end
    return false
  end

  -- isAllyTargetable(moveId) -> boolean. True when the move can legally be
  -- aimed at one of the caster's OWN adjacent mons -- the set a battle
  -- scene's target picker should offer allies for. Covers isAllyOnlyMove
  -- above, PLUS every selected-pokemon move that is not a damaging attack: a
  -- status/support single-target move can be aimed at an adjacent ally
  -- exactly as the cartridges and Showdown allow (Transform -- any adjacent
  -- Pokemon including an ally; Thunder Wave, Toxic, Trick, Skill Swap,
  -- Instruct, ...). national_dex's own `damageClass == "status"` is the
  -- authoritative marker for those, and it is what excludes a variable-power
  -- DAMAGING move like Seismic Toss (damageClass "physical", no power) from
  -- the ally list. This is what makes Transform targetable at an ally in the
  -- scene: it is a status move, so before this round it fell through the old
  -- heal-only check and its picker listed foes only.
  --
  -- A DAMAGING move is deliberately NOT offered an ally, even the one that
  -- is genuinely ally-supportive -- Pollen Puff. Its ally half (a 50% heal,
  -- moves.ts:13563-13586) is still an unimplemented structural no-op in this
  -- engine (combat/modern_status_moves.lua records it), so offering an ally
  -- for it would run the native DAMAGE path against that ally. It stays
  -- foe-only until its heal half is wired.
  mod.exports.isAllyTargetable = function(moveId)
    if mod.exports.isAllyOnlyMove(moveId) then return true end
    local info = moveById(moveId)
    if not info then return false end
    local archetype = info.target or "selected-pokemon"
    if archetype ~= "selected-pokemon" then return false end
    return info.damageClass == "status"
  end

  -- needsTargetChoice(moveId) -> boolean. True only for the archetypes that
  -- genuinely require the player to pick ONE recipient: a single selected
  -- target (attacks, and Heal Pulse-shaped selected-pokemon heals), the
  -- inherently ally-directed "ally"/"user-or-ally" moves, and Me First's
  -- "selected-pokemon-me-first". Every other national_dex target archetype
  -- resolves without any pick -- "user" (Protect, Swords Dance, Recover,
  -- self-boosts), "users-field" (Reflect/Light Screen/Tailwind/Mist), the
  -- opponents/entire-field spreads, "all-allies"/"user-and-allies",
  -- "random-opponent", "fainting-pokemon", "specific-move", and the
  -- field-side "opponents-field" (Spikes/Toxic Spikes/Sticky Web) -- so a
  -- battle scene's target picker must be SKIPPED for them. This is the
  -- single authority the scene consults; without it a doubles battle asked
  -- the player to choose a foe for Protect and every other self/field move
  -- (the regression this export fixes). The scene still queues a real
  -- placeholder recipient (the first live foe) for these, exactly as it
  -- already does for spread moves, so field-side moves that need the
  -- correct defending side (Spikes) resolve on the right half of the
  -- field. Returned as a plain boolean so the scene can pcall it like the
  -- rest of these exports.
  local CHOICE_TARGET_ARCHETYPES = {
    ["selected-pokemon"] = true,
    ["selected-pokemon-me-first"] = true,
    ["ally"] = true,
    ["user-or-ally"] = true,
  }
  mod.exports.needsTargetChoice = function(moveId)
    return CHOICE_TARGET_ARCHETYPES[mod.exports.targetArchetypeOf(moveId)] == true
  end

  -- pickAdjacentEnemy(battle, caster, moveId) -> one live adjacent enemy,
  -- or nil when none is left standing. Used when a single-target move's
  -- chosen target fainted mid-turn: the real games redirect the move to
  -- a random remaining adjacent foe (never to an ally). Random through
  -- the battle's own roller -- the same RNG source computeTurnOrder uses
  -- for a speed tie -- so a redirect is reproducible from the battle's
  -- seed like every other random choice in this mod.
  mod.exports.pickAdjacentEnemy = function(battle, caster, moveId)
    local adjacency = mod.exports.requestAdjacency(battle, caster, moveId)
    local liveEnemies = {}
    for _, m in ipairs(adjacency.enemies or {}) do
      if m and (m.hp or 0) > 0 then liveEnemies[#liveEnemies + 1] = m end
    end
    if #liveEnemies == 0 then return nil end
    if #liveEnemies == 1 then return liveEnemies[1] end
    local roller = battle and battle.roller and battle:roller()
    if type(roller) == "function" then
      local index = (roller(#liveEnemies) or 0) + 1
      return liveEnemies[index] or liveEnemies[1]
    end
    return liveEnemies[1]
  end

  mod.log:info("g9-battle-engine: move_targeting installed (resolveMoveTargets, isSpreadMove, allActiveBattlers, N-way Battle:sideOf, faint-redirect helpers)")
end
