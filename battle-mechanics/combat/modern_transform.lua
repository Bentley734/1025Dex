-- Transform, Imposter and Illusion, wired honestly for Gen 1 (round 179,
-- 2026-09-17).
--
-- THREE separate user-reported defects, one file, because they overlap in
-- mechanics the user flagged ("risk by similarity of mechanics"):
--
--   (A) GEN 1 TRANSFORM CHANGES THE SPRITE. The move "passes" today -- the
--       stats/types/moves are copied by the engine's own native
--       TRANSFORM_EFFECT (scratch/engine-dev/MoveEffects.lua:353) -- but the
--       visible sprite does not change. Native DOES swap it, through
--       battle:actNext (transform.asm:31-53, speciesSprite + picFxFor).
--       What clobbers that single queued swap is a per-frame redraw: the
--       g9-battle-sprites mod replaces BattleState:drawPicsLayer and calls
--       ensureBattler on both battlers EVERY frame, and ensureBattler
--       rewrites `battler.sprite` from the mon's own species
--       (g9-battle-sprites/main.lua:1060-1131, monStem -> resolveStem(
--       mon.species)). So whatever Transform wrote is overwritten before the
--       next frame is drawn -- the sprite "doesn't change" even though the
--       swap ran. The fix (below) does not fight that mod: it records the
--       replaced species on the battler (`__g9DisplaySpecies`) and installs
--       an OUTERMOST drawPicsLayer wrapper, at runtime, that swaps
--       `mon.species` to the display species for the duration of one draw
--       and restores it afterwards. The sprites mod then resolves the
--       DISPLAY species and bakes its frames -- and with no sprites mod
--       installed the same wrapper is a harmless no-op (the native draw
--       reads battler.sprite, which we also set directly). mon.species is
--       NEVER permanently mutated: the catch path (storeCaughtMon) and the
--       dex (markSeen) read the real species.
--
--       ROUND 181: the display species is mirrored onto the MON as
--       `__g9DisplaySpecies` (and an Illusion disguise's name as
--       `__g9DisplayName`). A custom battle screen (g9-Battle-Scene) resolves
--       the art -- and, for an Illusion, the HUD name -- from the mon and never
--       calls drawPicsLayer at all, so the outermost wrapper above could not
--       reach it: it drew the real species and the override stayed invisible.
--       The mon fields are set/cleared together with the battler ones.
--
--       ROUND 183 (user report: "transform is changing name of pokemon/
--       nickname of pokemon, it shouldn't"). ROUND 181 ALSO renamed on
--       Transform; that departure is reverted here. A Transform now swaps ONLY
--       the sprite -- no display name is recorded for it, so `battler.name`,
--       `mon.__g9DisplayName` and the real nickname are left alone. Native
--       Gen 1 agrees (transform.asm copies no nickname and swaps only the pic).
--       An Illusion still announces its disguise by name (Showdown's behavior,
--       a different mechanic).
--
--   (C) TRANSFORM/IMPOSTER COPY REAL FINAL STATS *AND* STAT STAGES. The
--       engine's native Transform copies only attack/defense/speed/special
--       (the Gen 1 combined special), because the Gen 1 shape has no split
--       Sp. Atk/Sp. Def -- so a transformed mon in this modernization got
--       stale spa/spd and hit like its old self on modern damage. Showdown's
--       Pokemon#transformInto (sim/pokemon.ts:1270) copies ALL of
--       `storedStats` (atk/def/spa/spd/spe) and -- on Gen 1 specifically --
--       `modifiedStats` too ("Gen 1: Copy modified stats", :1302-1303), and
--       copies `boosts` (stat stages) as well. This engine's equivalent of
--       "storedStats" is `battler.curStats` (already computed from
--       IV/EV/nature by stats/engine_modern_stats.lua, so it IS the real
--       final modern stat) and its equivalent of `boosts` is TWO stores: the
--       native `battler.stages` (speed/accuracy/evasion) plus
--       modern_combat.lua's own per-mon bucket for attack/defense/spa/spd
--       (mod.exports.stagesFor). Both are copied, so the transformed mon's
--       EFFECTIVE stats match the target's -- which is the observable Gen 1
--       behavior. Stages are copied as stages, not baked into curStats: this
--       engine applies stages on top of curStats at use time (Stats.
--       applyStage), so baking them in and then copying them would square
--       the multiplier.
--
--       ROUND 183 SCOPING (same user report: the copy must last only "for the
--       current battle" and the mon must "recover its own stats ... after
--       battle or ... switched out ... or they faint"). The pre-transform
--       fields are snapshotted the first time a mon transforms
--       (snapshotTransform) and restored when it leaves the field or the fight
--       ends (revertTransform): base stats, types (=> sprite/nature/IV/EV,
--       which all feed mon.stats), moves and both stage stores. A NATIVE battle
--       already reverts by itself -- its switch/faint path builds a fresh
--       battler from the mon (makeBattler) -- but g9-Battle-Scene caches ONE
--       engine battler per mon (`battle.battlersByMon`) and REUSES it when the
--       same mon switches back in, so without this the copied fields survived
--       switch-outs and even whole battles. This applies to Transform AND
--       Imposter (both route through applyTransform).
--
--   (B) ILLUSION. Showdown's `illusion` (data/abilities.ts:2055): purely
--       COSMETIC -- it copies no stats and sets no transform. onBeforeSwitchIn
--       clears the old illusion, then walks the party DOWNWARD from the last
--       slot and disguises the holder as the first non-fainted party member
--       it finds AFTER the holder's own position (singles: the last party
--       member). It ends on a damaging hit (onDamagingHit), on faint
--       (onFaint) and on leaving the field (onEnd). Nothing in this project
--       implemented it (grep: no ILLUSION handler anywhere; battle_forms'
--       name in abilities/data/form_change_scope.lua was aspirational --
--       that mod implements no Illusion either). Wild holders follow the
--       user's explicit rule, which is NOT Showdown's party rule (a wild mon
--       has no party): the disguise is a random species drawn from the
--       CURRENT MAP'S OWN encounter table -- `battle.data.encounters[mapId]`
--       .grass.slots / .water.slots, exactly the table the encounter roller
--       read to pick this mon -- and NEVER the holder's own species, so box
--       E (which prints `self.introText`) announces a mon that could really
--       have spawned here. The announced text and the sprite both follow the
--       disguise; the name is restored the instant the illusion breaks.
--
-- IMPOSTER. Showdown's `imposter` (abilities.ts:2123) is just
-- onSwitchIn -> transformInto(opposing active). Implemented by running the
-- same applyTransform on switch-in, so Ditto (the one Gen 1 species whose
-- real ability list contains Imposter) gets the same stat/sprite/move copy
-- a manual Transform would give, including the gates below.
--
-- ROUND 338 -- THE COPIED MOVES AND THE COPIED ABILITY. Two user-reported
-- gaps, both routed through the same temporary-copy discipline:
--
--   (M) MOVES. `applyTransform` wrote the target's moves only to the engine
--       battler's `curMoves`, but a battle screen's move menu reads the RAW
--       mon (`g9-Battle-Scene`'s `Combat.allMoves` iterates
--       `battler.mon.moves`), and Gen 2's own move pipeline reads `mon.moves`
--       directly -- so a transformed mon kept showing (and using) its OWN
--       moves. The copy now lands on BOTH `battler.curMoves` and `mon.moves`,
--       as the target's four moves with CURRENT PP = 5 and MAX PP = the
--       respective move's own maximum (the Showdown rule: transform slots are
--       `pp = Math.min(5, move.pp)`, `maxpp = calculatePP(move, ppUps)`;
--       pokemon.ts:1326-1341). `snapshotTransform` records the mon's own
--       `moves` table and `revertTransform` puts it back intact -- PP,
--       PP-Up-increased maxima and all -- so fainting, switching out or the
--       battle ending restores the mon's four learned moves exactly as they
--       were (the temporary copy is never persisted into the save).
--
--   (A) ABILITY. Real Showdown transformInto ends with
--       `this.setAbility(pokemon.ability, this, null, true, true)`
--       (pokemon.ts:1352) -- the target's ability is copied for the duration
--       of the battle. SetAbility (abilities/ability_dispatch.lua) already
--       snapshots the mon's own natural ability and hands it back on
--       switch-out / faint / battle end, so the copy is battle-scoped for
--       free. And because `setAbility` with `isTransform` fires the new
--       ability's Start event, a copied switch-in trigger (Intimidate, a
--       weather/terrain setter, Trace, Download, ...) must activate ONCE as
--       part of the transform; `fireSwitchInAbility` replays exactly the
--       registered switch-in families the ordinary entry sweep runs, for
--       this one mon, without touching the unrelated battler_switched
--       surface (entry hazards, field re-application, ...). The same body
--       serves Imposter (its switch-in transform).
--
-- TRANSFORM GATES, from the same Showdown function: fails if the target is
-- fainted, if either side has an active illusion, or if the target is a
-- substitute. (Showdown's substitute gate is Gen 5+, so Gen 1 allows it --
-- kept per Showdown's own `&& this.battle.gen >= 5`.) Showdown Gen 1 also
-- permits re-transforming an already-transformed mon, so no
-- "already transformed" block is added.
--
-- SCOPE: Gen 1. A Gen 2 boot resolves `src.battle.BattleState` to the
-- Gen2Compat facade, and Gen 2's own native EFFECT_TRANSFORM (gen2/Battle.
-- lua) already copies split specialAttack/specialDefense and its own
-- Pokemon.new path fills abilities -- this file's newWild/newTrainer/event
-- wiring installs only when those Gen 1 constructors exist. The effect-record
-- patch below installs wherever `effectRecord` exists (Gen 1 and the test
-- harness), which is exactly where Gen 1 dispatches it from.
return function(mod)
  local Strings = require("src.core.Strings")
  assert(mod and mod.exports, "modern_transform: mod table required")

  local okState, BattleState = pcall(require, "src.battle.BattleState")
  BattleState = okState and BattleState or nil
  if not BattleState or type(rawget(BattleState, "effectRecord")) ~= "function" then
    mod.log:info("g9-battle-engine: [modern_transform] the live "
      .. "src.battle.BattleState has no effectRecord (the engine's Gen-2 "
      .. "facade); Transform's record patch is a Gen-1 dispatch concern, so "
      .. "there is nothing to patch on this boot -- skipped, not broken")
    return
  end

  local ModernStats = mod.exports.ModernStats
  local stagesFor = mod.exports.stagesFor
  local abilityIdOf = mod.exports.abilityIdOf

  local function monNameOf(who)
    if not who then return "?" end
    local mon = who.mon or who
    return mon.nickname or (mon.def and mon.def.name) or mon.name or mon.species or "?"
  end

  ------------------------------------------------------------------
  -- Round 338: the copied moveset.
  ------------------------------------------------------------------
  -- The target's move list, whichever generation's shape this battle keeps
  -- it in: a Gen 1 battler aliases its raw mon's moves through `curMoves`,
  -- while Gen 2's own move pipeline reads `mon.moves` directly.
  local function sourceMovesOf(target)
    if not target then return nil end
    if type(target.curMoves) == "table" and #target.curMoves > 0 then
      return target.curMoves
    end
    local mon = target.mon or target
    if type(mon.moves) == "table" and #mon.moves > 0 then return mon.moves end
    return nil
  end

  -- The MAXIMUM PP of a source move slot. Gen 2 slots carry a real `maxPp`
  -- (Mon.movesAtLevel / Trainers.party write `moveDef.pp`); Gen 1 slots are
  -- only `{id, pp, ppUps}` and derive the maximum from the move def plus the
  -- PP-Up count exactly like the games do -- `def.pp + ppUps * floor(def.pp/5)`,
  -- the same rule combat/modern_faint_sacrifice.lua reads. Showdown's own
  -- `calculatePP(move, ppUps)` produces the identical number.
  local function moveMaxPp(battle, slot)
    if type(slot) ~= "table" then return 5 end
    if slot.maxPp then return slot.maxPp end
    local def = slot.id and battle and battle.data and battle.data.moves
      and battle.data.moves[slot.id]
    local base = (type(def) == "table" and def.pp) or 0
    if base <= 0 then return slot.pp or 5 end
    return base + (slot.ppUps or 0) * math.floor(base / 5)
  end

  -- Builds the temporary "borrowed moves" list: the target's moves, each with
  -- current PP 5 (Showdown pokemon.ts:1326 `Math.min(5, move.pp)`) and the
  -- move's own maximum, flagged as a mimic clone exactly like the Gen 1 ROM
  -- copy (transform.asm's `.copyPPLoop`).
  local function buildMoveCopy(battle, target)
    local src = sourceMovesOf(target)
    if not src then return nil end
    local copy = {}
    for i = 1, #src do
      local mv = src[i]
      if type(mv) == "table" and mv.id then
        copy[#copy + 1] = {
          id = mv.id,
          pp = 5,
          maxPp = moveMaxPp(battle, mv),
          ppUps = 0,
          mimic = true,
        }
      end
    end
    if #copy == 0 then return nil end
    return copy
  end

  -- Copies `target`'s ability onto `user` for the rest of the battle and, when
  -- it actually changed, fires that ability's switch-in trigger once (a real
  -- Showdown `setAbility(..., isTransform)` fires the new ability's Start
  -- event). Returns true when an ability was written.
  local function copyAbility(battle, user, target)
    local setAbility = mod.exports.setAbility
    local fireTrigger = mod.exports.fireSwitchInAbility
    if not (setAbility and abilityIdOf) then return false end
    local targetId = abilityIdOf(target.mon or target)
    if not targetId then return false end
    local prevId = abilityIdOf(user.mon or user)
    if setAbility(battle, user, targetId) == false then return false end
    if fireTrigger and targetId ~= prevId then
      local ok, err = pcall(fireTrigger, battle, user)
      if not ok then
        mod.log:warn("g9-battle-engine: transform ability trigger failed: %s",
          tostring(err))
      end
    end
    return true
  end

  ------------------------------------------------------------------
  -- Display species: the one place a battler is told "draw as this".
  -- ------------------------------------------------------------------
  -- Species name for the front/back battle pic, in the species' OWN
  -- palette -- the same expression makeBattler uses
  -- (BattleState.lua:622-628), reused here rather than speciesSprite,
  -- because speciesSprite forces PAL_GRAYMON (correct for a TRANSFORMED
  -- mon, wrong for an Illusion disguise, which must simply look like the
  -- mon it claims to be).
  local function speciesInItsPalette(battle, species, isPlayer)
    if not (battle and battle.data and species) then return nil end
    local ok, img = pcall(function()
      local Sprites = require("src.pokemon.Sprites")
      local path, tc = Sprites.path(battle.data, species,
        isPlayer and "back" or "front", { kind = "battle" })
      local PaletteFX = require("src.render.PaletteFX")
      local colors = PaletteFX.monPal(battle.data, species)
      local name = colors and PaletteFX.monPalName(battle.data, species) or nil
      if name and PaletteFX.usesGbcPack() then name = "redpp:" .. name end
      return getImage(path, colors and { name = name, colors = colors } or nil, tc)
    end)
    return ok and img or nil
  end

  -- The gray-tinted pic native Transform uses (speciesSprite, transform.asm).
  local function graySprite(battle, species, isPlayer)
    if not (battle and battle.speciesSprite) then return nil end
    local ok, img = pcall(battle.speciesSprite, battle, species, isPlayer)
    return ok and img or nil
  end

  -- Runtime draw-time species swap. Installed at the first display use --
  -- i.e. after EVERY mod (including a sprite-overriding one) has booted --
  -- so this wrapper is the OUTERMOST drawPicsLayer and runs its swap
  -- before the inner (possibly sprites-mod) layer resolves its frames.
  local function ensureDisplayDraw()
    if not BattleState.drawPicsLayer then return end
    if BattleState.__g9DisplayDrawInstalled then return end
    BattleState.__g9DisplayDrawInstalled = true
    local inner = BattleState.drawPicsLayer
    function BattleState:drawPicsLayer(...)
      local swaps
      for _, b in ipairs({ self.enemy, self.player }) do
        if b and b.__g9DisplaySpecies and b.mon
           and b.mon.species ~= b.__g9DisplaySpecies then
          swaps = swaps or {}
          swaps[#swaps + 1] = { mon = b.mon, real = b.mon.species }
          b.mon.species = b.__g9DisplaySpecies
        end
      end
      if not swaps then return inner(self, ...) end
      local ok, err = pcall(inner, self, ...)
      for _, s in ipairs(swaps) do s.mon.species = s.real end
      if not ok then error(err, 0) end
    end
  end

  local function setDisplay(battle, battler, species, displayName, opts)
    if not (battler and species) then return false end
    battler.__g9DisplaySpecies = species
    -- Mirror onto the mon as well (round 181). The custom battle screen
    -- (g9-Battle-Scene) resolves each battler's art and HUD name from the MON,
    -- not the battler, and prewarmSlot can run without a battler at hand -- so
    -- the mon is the store that reaches every consumer. Harmless when there is
    -- no mon (a bare test stub), and always cleared by clearDisplay below.
    if battler.mon then battler.mon.__g9DisplaySpecies = species end
    if displayName ~= nil then
      battler.name = displayName
      if battler.mon then battler.mon.__g9DisplayName = displayName end
    end
    local img
    if opts and opts.gray then img = graySprite(battle, species, battler.isPlayer)
    else img = speciesInItsPalette(battle, species, battler.isPlayer) end
    if img then battler.sprite = img end
    ensureDisplayDraw()
    return true
  end

  local function clearDisplay(battle, who)
    if not who then return end
    -- `who` may be a battler OR a raw mon (the scene's switch payloads are the
    -- raw mon -- battle_screen.lua's Runtime.emit sites). The mon fields are
    -- the store every consumer reads, so they are always cleared; the battler
    -- fields only exist when a battler was passed.
    local mon = who.mon or who
    local isBattler = who.mon ~= nil
    mon.__g9DisplaySpecies = nil
    mon.__g9DisplayName = nil
    if not isBattler then return end
    local wasDisplay = who.__g9DisplaySpecies ~= nil
    who.__g9DisplaySpecies = nil
    if wasDisplay then
      who.name = (mon.nickname or (who.def and who.def.name)) or who.name
      local img = speciesInItsPalette(battle, mon.species, who.isPlayer)
      if img then who.sprite = img end
    end
  end
  mod.exports.clearBattlerDisplay = clearDisplay

  ------------------------------------------------------------------
  -- applyTransform: the shared Transform/Imposter body.
  ------------------------------------------------------------------
  local STAT_KEYS = { "attack", "defense", "speed", "special", "spa", "spd" }

  -- Showdown transformInto's own early-return block (pokemon.ts:1270-1282),
  -- restricted to the clauses that apply to Gen 1: fainted target, either
  -- side's active Illusion. Its substitute and already-transformed clauses
  -- are `this.battle.gen >= 5` / `>= 2` and are therefore NOT in force here
  -- (Gen 1 genuinely allows re-transforming, and Transform through a
  -- substitute to fail for other reasons does not block the copy).
  local function canTransform(user, target)
    if not (user and target and user.mon and target.mon) then return false end
    if (target.mon.hp or 0) <= 0 then return false end
    if user.__g9IllusionActive or target.__g9IllusionActive then return false end
    return true
  end
  mod.exports.canTransform = canTransform

  ------------------------------------------------------------------
  -- Transform scoping (round 183): snapshot the mon's own fields before the
  -- FIRST transform, restore them when it leaves the field / the fight ends.
  ------------------------------------------------------------------
  local function monOf(who)
    if not who then return nil end
    return who.mon or who
  end
  mod.exports.monOf = monOf

  -- The engine battler behind a payload that may be a battler OR a raw mon
  -- (the scene's battle.battler_switched carries the raw mon; battle_screen.lua
  -- Runtime.emit sites). Tries the scene's own cache first -- the exact store
  -- that makes the revert necessary, since it reuses one engine battler per mon
  -- for the whole fight -- then the native pair, then every active battler.
  local function battlerFor(battle, who)
    if not who then return nil end
    if who.mon then return who end
    local mon = who
    if not battle then return nil end
    local byMon = battle.battlersByMon
    if type(byMon) == "table" and byMon[mon] then return byMon[mon] end
    for _, b in ipairs({ battle.player, battle.enemy }) do
      if b and b.mon == mon then return b end
    end
    local fn = mod.exports.allActiveBattlers
    if fn then
      local ok, actives = pcall(fn, battle)
      if ok then
        for _, b in ipairs(actives or {}) do
          if b and b.mon == mon then return b end
        end
      end
    end
    return nil
  end

  -- The first transform's pre-state is the only one kept: re-transforming
  -- before switching out (Gen 1 allows it) must still revert to the mon's OWN
  -- fields, not to the previous copy.
  local function snapshotTransform(battle, user)
    local mon = monOf(user)
    if not mon then return nil end
    if mon.__g9TransformPre then return mon.__g9TransformPre end
    local pre = {
      -- Round 276: this used to hold the live engine battler
      -- (`battler = user` when user had a `.mon`), but a battler carries a
      -- strong `.mon` back-reference, so keeping it on the mon closed a save
      -- cycle (on Gen 2 battle.party IS save.party and SaveSerializer's
      -- writer has no cycle detection). Only the FACT that the caller handed
      -- in a battler is recorded; revertTransform re-resolves it from the
      -- battle, where the scene's reused battler is still reachable.
      hadBattler = user.mon ~= nil,
      curStats = user.curStats,
      curTypes = user.curTypes,
      curMoves = user.curMoves,
      monMoves = mon.moves,
      stages = user.stages,
      stagesModern = nil,
    }
    if battle and stagesFor then
      -- stagesFor returns the mon's OWN persistent bucket, mutated in place by
      -- applyTransform, so the snapshot must copy its contents.
      local copy = {}
      local ok, bucket = pcall(stagesFor, battle, user)
      if ok and type(bucket) == "table" then
        for k, v in pairs(bucket) do copy[k] = v end
      end
      pre.stagesModern = copy
    end
    mon.__g9TransformPre = pre
    return pre
  end
  mod.exports.snapshotTransform = snapshotTransform

  local function restoreBucket(battle, who, values)
    if not (battle and stagesFor and values) then return end
    local ok, bucket = pcall(stagesFor, battle, who)
    if not ok or type(bucket) ~= "table" then return end
    for k in pairs(bucket) do bucket[k] = nil end
    for k, v in pairs(values) do bucket[k] = v end
  end

  -- Puts the mon's own fields back and clears every display/flag the transform
  -- set. Safe to call on anything (battler or raw mon); a no-op when the mon
  -- never transformed.
  local function revertTransform(battle, who)
    local mon = monOf(who)
    if not mon then return false end
    local pre = mon.__g9TransformPre
    if not pre then return false end
    -- Round 276: the battler is re-resolved from the battle instead of being
    -- read off the snapshot (snapshotTransform no longer stores it, so the
    -- mon never holds a battler -> mon cycle). `who` itself is used when a
    -- battler was handed in; otherwise battlerFor finds the scene's reused
    -- battler via battle.battlersByMon. Only the fields a battler actually
    -- got at snapshot time are touched, so a mon that never had a wrapper
    -- behaves exactly as before.
    local b = pre.hadBattler
      and ((who.mon and who) or battlerFor(battle, mon))
      or nil
    if b then
      b.curStats = pre.curStats
      b.curTypes = pre.curTypes
      b.curMoves = pre.curMoves
      b.stages = pre.stages or {}
      b.transformed = nil
      clearDisplay(battle, b)
    else
      clearDisplay(battle, mon)
    end
    restoreBucket(battle, b or who, pre.stagesModern)
    -- Round 338: the mon's own learned moves (PP, PP-Up maxima and current
    -- values) come back exactly as snapshotted; a mon that had no moves table
    -- gets it cleared again rather than keeping the borrowed list.
    mon.moves = pre.monMoves
    mon.transformed = nil
    mon.__g9TransformPre = nil
    return true
  end
  mod.exports.revertTransform = revertTransform

  -- The foe DIRECTLY OPPOSITE `battler`'s own slot -- the real Imposter rule
  -- (Showdown abilities.ts:2123 transforms into `pokemon.side.foe.active
  -- [pokemon.position]`). Asked through the engine's own position seam,
  -- combat/move_targeting.lua's requestOpposite, which forwards to a battle
  -- scene's `g9.request_opposite` hook and otherwise answers the native
  -- two-battler case -- so this file still owns no position data. It never
  -- falls back to a different foe and NEVER to an ally: when the opposite
  -- slot is empty or its occupant is not standing, requestOpposite returns
  -- nil and this returns nil, exactly as Showdown's `if (!target) return
  -- false` leaves the ability unused.
  local function oppositeOpponentOf(battle, battler)
    if not (battle and battler) then return nil end
    local requestOpposite = mod.exports.requestOpposite
    if not requestOpposite then return nil end
    local raw = battler.mon or battler
    local ok, target = pcall(requestOpposite, battle, raw)
    if not ok or target == nil then return nil end
    local b = battlerFor(battle, target)
    if b and b ~= battler and b.mon and (b.mon.hp or 0) > 0 then return b end
    return nil
  end

  local function applyTransform(battle, user, target)
    if not (battle and canTransform(user, target)) then return false end

    -- Record the mon's own fields BEFORE anything below overwrites them, so
    -- switch-out / faint / battle-end can put them back (round 183). No-op if
    -- this mon already transformed (its original pre-state is kept).
    snapshotTransform(battle, user)

    -- Real final stats: copy every key of the target's live stat table,
    -- keeping only the user's own HP (Showdown: HP is not copied --
    -- pokemon.ts:1285 `this.hp` is left untouched). HP belongs to the
    -- Transform/Imposter USER and only ever to that user: the user's own
    -- current HP (`user.mon.hp`) is not touched here at all, and the
    -- `user.curStats` table this rebuilds gets the USER's max HP, never
    -- anything read off the target -- so every hp-ish key is filtered out
    -- of the target's table and then the user's max is stamped back in.
    local src = target.curStats
    if type(src) == "table" then
      local maxHp = (user.mon.stats and user.mon.stats.hp)
        or user.mon.maxHp or user.mon.hp
      local dst = { hp = maxHp }
      for k, v in pairs(src) do
        if k ~= "hp" and k ~= "maxHp" and k ~= "hpMax" then dst[k] = v end
      end
      for _, k in ipairs(STAT_KEYS) do
        if src[k] ~= nil then dst[k] = src[k] end
      end
      dst.hp = maxHp
      user.curStats = dst
    end

    -- Types (native behavior; this engine's Gen 1 type list is curTypes).
    if target.curTypes then
      user.curTypes = { target.curTypes[1], target.curTypes[2] }
    end

    -- Stat stages, both stores (see this file's header for why there are
    -- two and why they are copied as stages, never baked in).
    if target.stages then
      local dst = {}
      for k, v in pairs(target.stages) do dst[k] = v end
      user.stages = dst
    end
    if stagesFor then
      local from = stagesFor(battle, target)
      local to = stagesFor(battle, user)
      for k in pairs(to) do to[k] = nil end
      for k, v in pairs(from) do to[k] = v end
    end

    -- Moves (round 338): the target's four moves with current PP 5 and the
    -- move's own maximum, written to BOTH the engine battler's `curMoves` and
    -- the raw mon's `moves` -- a battle screen's move menu reads the mon, and
    -- Gen 2's own pipeline reads `mon.moves`, so the battler-only copy a
    -- transformed mon used to get kept showing (and using) its OWN move list.
    -- snapshotTransform/revertTransform put the mon's own list back intact on
    -- every exit.
    local moveCopy = buildMoveCopy(battle, target)
    if moveCopy then
      -- `curMoves` is a battler alias only (a Gen 2 raw mon must not gain one:
      -- battle.party IS save.party there); `mon.moves` is the store every
      -- move menu and pipeline actually reads.
      if user.mon then user.curMoves = moveCopy end
      local userMon = user.mon or user
      userMon.moves = moveCopy
    end

    -- Ability (round 338): copy the target's for the rest of the battle, and
    -- fire its switch-in trigger once if it changed (see this file's header).
    copyAbility(battle, user, target)

    -- The flags Quick Powder / Metal Powder read (they check
    -- mon.transformed on the raw mon; combat/modern_gen1_held_items.lua,
    -- modern_held_items_phase2.lua, modern_pivot_moves.lua).
    user.transformed = true
    if user.mon then user.mon.transformed = true end

    -- The sprite, as the target currently appears (a target that is itself
    -- disguised or transformed is gated out above). Round 183: the NAME is NOT
    -- copied -- native Gen 1 copies no nickname (transform.asm) and the user
    -- reported the rename as a defect, so `setDisplay` gets a nil display name
    -- and leaves `battler.name` / `mon.__g9DisplayName` / the real nickname
    -- untouched. Only the picture follows the transform (grayed, as native
    -- draws a transformed mon).
    local shown = target.__g9DisplaySpecies or target.mon.species
    setDisplay(battle, user, shown, nil, { gray = true })

    return true
  end
  mod.exports.applyTransform = applyTransform

  ------------------------------------------------------------------
  -- The TRANSFORM_EFFECT record patch. Wraps the engine's own native
  -- record (so its exact message and its queued actNext sprite swap are
  -- kept) and layers the modern stat/stage copy + display species on top.
  -- The lookup is wrapped -- never the registry entry -- so this cannot
  -- collide with the loader's own base seeding order.
  ------------------------------------------------------------------
  local TRANSFORM_EFFECT = "TRANSFORM_EFFECT"
  local transformCopies = setmetatable({}, { __mode = "k" })

  local function patchedTransformRecord(rec)
    local cacheable = type(rec) == "table"
    if cacheable and transformCopies[rec] then return transformCopies[rec] end
    local nativeRun = cacheable and rec.run or nil
    local copy = {}
    for k, v in pairs(rec or {}) do copy[k] = v end
    if copy.kind == nil then copy.kind = "primary" end
    copy.run = function(first, ...)
      local battle = (type(first) == "table" and first.battle) or first
      local user = type(first) == "table" and first.user or nil
      local target = type(first) == "table" and first.target or nil
      -- Gate BEFORE the native body runs: the native copy is not
      -- reversible, so a refused Transform must not half-apply it.
      if not canTransform(user, target) then
        local text = battle and battle.romText and battle:romText("_ButItFailedText", "But, it failed!")
          or "But, it failed!"
        return { text }
      end
      -- The native TRANSFORM_EFFECT reassigns user.curStats/curTypes/
      -- curMoves/stages ITSELF, so the pre-transform snapshot has to be taken
      -- BEFORE it runs -- otherwise the revert would restore the values native
      -- just wrote. (applyTransform also snapshots; snapshotTransform is
      -- idempotent, so the first call wins and this one covers the native
      -- reassignment.)
      snapshotTransform(battle, user)
      local msgs = {}
      if type(nativeRun) == "function" then
        local ok, res = pcall(nativeRun, first, ...)
        if ok and type(res) == "table" then msgs = res end
      end
      applyTransform(battle, user, target)
      if #msgs == 0 then
        local text
        if battle and battle.romText then
          text = battle:romText("_TransformedText", "%s\ntransformed into\n%s!",
            monNameOf(user), monNameOf(target))
        end
        msgs[1] = text or Strings("%s transformed into %s!", monNameOf(user), monNameOf(target))
      end
      return msgs
    end
    if cacheable then transformCopies[rec] = copy end
    return copy
  end

  local nativeEffectRecord = rawget(BattleState, "effectRecord")
  BattleState.effectRecord = function(self, effect)
    local rec = nativeEffectRecord(self, effect)
    if effect == TRANSFORM_EFFECT then return patchedTransformRecord(rec) end
    return rec
  end

  ------------------------------------------------------------------
  -- ILLUSION: disguise selection.
  ------------------------------------------------------------------
  -- Showdown onBeforeSwitchIn (abilities.ts:2055): the first non-fainted
  -- party member AFTER the holder's own position, walking down from the
  -- last slot. `party` is raw mon tables (Gen 1's playerPartyView /
  -- enemyParty), compared by identity against the holder's own mon.
  local function partyDisguise(party, holderMon)
    if type(party) ~= "table" or holderMon == nil then return nil end
    local pos
    for i, m in ipairs(party) do
      if m == holderMon then pos = i break end
    end
    if not pos then return nil end
    for i = #party, pos + 1, -1 do
      local m = party[i]
      if m and (m.hp or 0) > 0 and m.species then return m.species, m end
    end
    return nil
  end

  -- The user's wild rule: a random species from the map's own spawn
  -- table, never the holder's species.
  local function wildDisguise(battle, holderSpecies)
    local data = battle and battle.data
    local encounters = data and data.encounters
    if not encounters then return nil end
    local mapId = BattleState.currentMapId and BattleState.currentMapId(battle)
    local entry = mapId and encounters[mapId]
    if not entry then return nil end
    local pool, seen = {}, {}
    for _, kind in ipairs({ "grass", "water" }) do
      local slots = entry[kind] and entry[kind].slots
      for _, slot in ipairs(slots or {}) do
        local sp = slot.species
        if sp and sp ~= holderSpecies and not seen[sp] then
          seen[sp] = true
          pool[#pool + 1] = sp
        end
      end
    end
    if #pool == 0 then return nil end
    -- `battle.rng` is the engine's INCLUSIVE (lo, hi) roller
    -- (src/battle/BattleState.lua: `function(a, b) return love.math.random(a, b) end`),
    -- NOT a (battle, lo, hi) helper -- that is Gen 2's separate `battle.random(n)`.
    -- Passing the battle table as its first argument fed a table straight to
    -- love.math.random and aborted the battle with "bad argument #2 to 'random'
    -- (number expected)" the instant a wild Illusion holder rolled its disguise
    -- (Red-gameplay crash report, 2026-09-24). Every other roll in this mod is
    -- already rng(lo, hi); this one now is too.
    local rng = battle.rng
    local index = (type(rng) == "function" and rng(1, #pool)) or 1
    if index < 1 or index > #pool then index = 1 end
    return pool[index]
  end

  local function disguiseSpeciesFor(battle, battler)
    local holderMon = battler.mon
    if not holderMon then return nil end
    if battler.isPlayer then
      return partyDisguise(battle:playerPartyView(), holderMon)
    end
    if battle.kind == "trainer" and battle.enemyParty then
      return partyDisguise(battle.enemyParty, holderMon)
    end
    return wildDisguise(battle, holderMon.species)
  end

  local function displayNameOf(battle, species)
    local def = battle and battle.data and battle.data.pokemon
      and battle.data.pokemon[species]
    return def and def.name or species
  end

  -- Sets up a battler's Illusion (no stats copied -- purely cosmetic),
  -- returns true if it disguised.
  local function setupIllusion(battle, battler)
    if not (battle and battler and battler.mon) then return false end
    local species = disguiseSpeciesFor(battle, battler)
    if not species then return false end
    if species == battler.mon.species then return false end
    battler.__g9IllusionActive = true
    return setDisplay(battle, battler, species, displayNameOf(battle, species))
  end
  mod.exports.setupIllusion = setupIllusion

  local function clearIllusion(battle, who)
    if not who then return end
    who.__g9IllusionActive = nil
    local b = battlerFor(battle, who)
    if b and b ~= who then b.__g9IllusionActive = nil end
    clearDisplay(battle, who)
  end
  mod.exports.clearIllusion = clearIllusion

  -- Switch-in dispatch: Illusion first, then Imposter (Showdown fires
  -- both on switch-in; order is cosmetic for a mon that has only one).
  -- `who` may be an engine battler or a raw mon: the scene's
  -- battle.battler_switched carries the RAW mon, and without normalising here
  -- an Imposter on a scene switch-in never fired at all (battler.mon was nil).
  -- `opposingWho` is kept in the signature for the callers that pass one, but
  -- Imposter ignores it: its target is always the foe DIRECTLY OPPOSITE the
  -- user's slot (oppositeOpponentOf below), never an arbitrary/ally mon.
  local function runSwitchInAbilities(battle, who, opposingWho, opts)
    if not (battle and who) then return end
    local battler = battlerFor(battle, who)
    if not (battler and battler.mon) then return end
    local id = abilityIdOf and abilityIdOf(battler.mon)
    if id == "ILLUSION" then
      setupIllusion(battle, battler)
    elseif id == "IMPOSTER" then
      -- IMPOSTER RULE (Showdown abilities.ts:2123): transform into the foe
      -- DIRECTLY OPPOSITE this mon's slot -- never another foe, and never an
      -- ally when that slot is empty. oppositeOpponentOf asks the engine's
      -- own position seam (combat/move_targeting.lua's requestOpposite, the
      -- `g9.request_opposite` hook), which a battle scene answers from its
      -- index-aligned grid; a native battle gets its one opposing battler.
      -- nil here means "no opponent in that exact slot", so NOTHING happens.
      local opposing = oppositeOpponentOf(battle, battler)
      if opposing and opposing.mon and (opposing.mon.hp or 0) > 0
         and not battler.transformed then
        applyTransform(battle, battler, opposing)
      end
    end
  end
  mod.exports.runSwitchInAbilities = runSwitchInAbilities

  ------------------------------------------------------------------
  -- Teardown handlers (round 183). Defined outside the constructor-gated
  -- block below so they can be exported and exercised directly, and so the
  -- revert works identically whether the listener wiring ran or not.
  ------------------------------------------------------------------
  -- Every mon that could still carry a transform/illusion after a teardown:
  -- the actives, the party lists, and the scene's byMon cache (which outlives
  -- a switch -- the exact reason a switch-out revert is needed). Deduped by
  -- mon identity.
  local function revertAllMonState(battle)
    if not battle then return end
    local seen = {}
    local function revertOne(who)
      local mon = monOf(who)
      if not mon or seen[mon] then return end
      seen[mon] = true
      who.__g9IllusionActive = nil
      clearDisplay(battle, who)
      revertTransform(battle, who)
    end
    revertOne(battle.player)
    revertOne(battle.enemy)
    local actives = mod.exports.allActiveBattlers
    if actives then
      local ok, list = pcall(actives, battle)
      if ok then
        for _, b in ipairs(list or {}) do revertOne(b) end
      end
    end
    local byMon = battle.battlersByMon
    if type(byMon) == "table" then
      for _, b in pairs(byMon) do revertOne(b) end
    end
    local parties = { battle.party, battle.enemyParty, battle.playerParty }
    for p = 1, #parties do
      local party = parties[p]
      if type(party) == "table" then
        for i = 1, #party do revertOne(party[i]) end
      end
    end
  end
  mod.exports.revertAllMonState = revertAllMonState

  -- `previous` (leaving) and `battler` (arriving) may each be an engine battler
  -- or a raw mon.
  local function handleBattlerSwitched(battle, previous, battler)
    if not battle then return end
    if previous then
      clearIllusion(battle, previous)
      -- Round 183: the mon leaving the field gets its OWN stats back NOW. A
      -- native switch builds a fresh battler, but the scene REUSES the engine
      -- battler cached in battle.battlersByMon, so a transform's copy would
      -- otherwise follow the mon back in.
      revertTransform(battle, previous)
    end
    if battler then
      -- And the mon arriving starts from its own fields, never from whatever
      -- the last Transform left on a reused battler.
      revertTransform(battle, battler)
      runSwitchInAbilities(battle, battler) -- opposing is derived inside
    end
  end
  mod.exports.handleBattlerSwitched = handleBattlerSwitched

  local function handleFainted(battle, battler)
    if not (battle and battler) then return end
    clearIllusion(battle, battler)
    -- "...or they faint": a fainted mon reverts too -- its engine battler can
    -- outlive the faint in a scene battle.
    revertTransform(battle, battler)
  end
  mod.exports.handleFainted = handleFainted

  ------------------------------------------------------------------
  -- Switch-in + teardown wiring (Gen 1 constructors only).
  ------------------------------------------------------------------
  local wiredGen1 = type(rawget(BattleState, "newWild")) == "function"
    or type(rawget(BattleState, "newTrainer")) == "function"

  if wiredGen1 and not BattleState.__g9TransformWired then
    BattleState.__g9TransformWired = true

    if type(rawget(BattleState, "newWild")) == "function" then
      local vanillaNewWild = rawget(BattleState, "newWild")
      function BattleState.newWild(game, species, level, opts)
        local self = vanillaNewWild(game, species, level, opts)
        if self and not self.dead then
          runSwitchInAbilities(self, self.enemy, self.player)
          runSwitchInAbilities(self, self.player, self.enemy)
          -- Box E's own text is built in the constructor from
          -- `self.enemy.name`, so a wild disguise has to be reflected here
          -- (battle.started fires only AFTER the intro text is queued).
          if self.enemy and self.enemy.__g9IllusionActive then
            local name = self.enemy.name
            if opts and opts.hooked then
              self.introText = self:romText("_HookedMonAttackedText",
                "The hooked\n%s\nattacked!", name)
            else
              self.introText = self:romText("_WildMonAppearedText",
                "Wild %s\nappeared!", name)
            end
          end
        end
        return self
      end
    end

    if type(rawget(BattleState, "newTrainer")) == "function" then
      local vanillaNewTrainer = rawget(BattleState, "newTrainer")
      function BattleState.newTrainer(game, oppClass, partyIndex, opts)
        local self = vanillaNewTrainer(game, oppClass, partyIndex, opts)
        if self and not self.dead then
          runSwitchInAbilities(self, self.enemy, self.player)
          runSwitchInAbilities(self, self.player, self.enemy)
        end
        return self
      end
    end

    mod.events:on("battle.battler_switched", function(ev)
      handleBattlerSwitched(ev and ev.battle, ev and ev.previous, ev and ev.battler)
    end)

    mod.events:on("battle.fainted", function(ev)
      handleFainted(ev and ev.battle, ev and ev.battler)
    end)

    -- "...after battle": the whole roster reverts when the fight ends, so a
    -- mon's own base stats/types/moves/stages/sprite/name are what the next
    -- battle (or the overworld) sees. This is what makes battle.ended, not the
    -- removed battle.started hook, the cross-battle cleanup -- a battle.started
    -- sweep would wrongly undo the Imposter that newWild/newTrainer applied
    -- before battle.started fires.
    mod.events:on("battle.ended", function(ev)
      revertAllMonState(ev and ev.battle)
    end)

    -- Illusion ends on a DAMAGING hit (Showdown onDamagingHit) -- the real
    -- damaging-move pipeline is EffectRegistry.runDamaging, the one place
    -- recoil / weather / status chip does NOT go through, so the break is
    -- faithful without a source-tracking field.
    local okReg, EffectRegistry = pcall(require, "src.battle.EffectRegistry")
    if okReg and EffectRegistry and type(EffectRegistry.runDamaging) == "function"
       and not EffectRegistry.__g9IllusionBreakWrapped then
      EffectRegistry.__g9IllusionBreakWrapped = true
      local nativeRunDamaging = EffectRegistry.runDamaging
      function EffectRegistry.runDamaging(battle, ctx, record)
        local target = ctx and ctx.target
        local before = target and target.mon and target.mon.hp
        local res = nativeRunDamaging(battle, ctx, record)
        if target and target.mon and before
           and (target.mon.hp or 0) < before and target.__g9IllusionActive then
          clearIllusion(battle, target)
        end
        return res
      end
    end
  end

  local scope = wiredGen1 and "Transform + Imposter + Illusion"
    or "Transform record patch only (Gen-1 constructors unavailable on this boot)"
  mod.log:info("g9-battle-engine: modern_transform installed (" .. scope .. ")")
end
