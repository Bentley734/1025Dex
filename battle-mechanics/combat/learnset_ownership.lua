-- Learnset ownership: national_dex is the canonical source for WHICH
-- moves a species can learn (its real, unfiltered movepool); GalarGmaxDex
-- decides which of those are actually USABLE right now, gated on its own
-- move-effect completeness. Explicit user decision, this session.
--
-- Why not just ask national_dex "is this modeled": its own gen1Effect/
-- gen2Effect/EffectModeled fields are a static snapshot computed once at
-- national_dex's OWN build time (tools/build_moves.py, not shipped) with
-- zero runtime awareness of any other mod -- confirmed by direct source
-- read, national_dex/src/api.lua:152-159's own comment: "these fields are
-- this mod's own answer". A move GalarGmaxDex fully implements today would
-- still read as unmodeled there. So: national_dex's UNFILTERED extras data
-- (movesFull/movesByMethod, real PokeAPI-derived movepool, not the
-- registered learnset/levelMoves field -- THAT field is filtered by the
-- same stale snapshot) is the canonical "can this species learn this move
-- at all" list; this file's own isUsable() is the "is it actually usable
-- right now" gate, kept as a genuinely separate step on purpose -- explicit
-- user note: national_dex will eventually expose its own generational-
-- ruleset setting, which this mod should consume then. Swapping the
-- canonical-movepool source (or intersecting it with that future setting)
-- should stay a small, local change to canonicalLearnset() below, not a
-- rewrite of the gate or the patching.
--
-- Confirmed empirically (not assumed) before writing this: movesFull/
-- movesByMethod entries' `move` field is USUALLY already the real
-- engine-spelled move id (e.g. "LIGHT_SCREEN", "GIGADRAIN",
-- "DOUBLE_EDGE" -- sampled directly from national_dex's own
-- extras/001.lua). It is NOT always: the Psychic move's extras id is
-- "PSYCHIC", while this engine registers it as PSYCHIC_M so the move
-- cannot collide with the PSYCHIC type (confirmed in the engine's own
-- source: src/battle/gen2/Ai.lua's "PSYCHIC is PSYCHIC_M", and the
-- TM_PSYCHIC_M item id). Writing the raw extras id into a learnset
-- therefore named a record the live `moves` registry does not hold --
-- Schemas.crossValidate turns that into a hard "unresolved reference to
-- moves \"PSYCHIC\"" error, and the battle builder would read the slot as
-- `moveDef and moveDef.pp or 0`, i.e. a 0/0 PP move. So every extras id is
-- reconciled against the live registry through registeredMoveId() below,
-- which is national_dex's own documented use of its replies' `strippedId`
-- field (src/api.lua: "strippedId on the reply is the separator-free
-- spelling the species extras' movesFull and movesByMethod use, for
-- reconciling the two").
--
-- Scope, explicit: level-up learnset (learnset/levelMoves/level1Moves,
-- the only fields this engine's schema actually has per species) plus
-- Gen 2's eggMoves (also a real schema field, src/mods/Schemas.lua:809).
-- TM/tutor legality has no per-species registry field in this schema at
-- all (confirmed: grepped Schemas.lua's whole pokemon field block, only
-- level1Moves/learnset/levelMoves/eggMoves exist) -- whatever gates TM
-- compatibility lives elsewhere in the engine and isn't touched here; a
-- known, stated gap, not silently assumed handled.
return function(mod, vocab)
  local GameVersion = require("src.core.GameVersion")
  local isGen2 = GameVersion.generation(GameVersion.get()) == 2

  local nd = mod.find and mod.find("national_dex")
  local ndExports = nd and nd.exports
  if not (ndExports and ndExports.statsBySpecies) then
    mod.log:warn("galar_gmax_dex: learnset_ownership: national_dex not available, learnsets left untouched")
    return { isUsable = function() return true end }
  end

  -- Completeness gate: does this mod have a REAL (non-stub) effect for
  -- this move id, read ENTIRELY off the live registry now -- no static
  -- per-move data file backing this at all anymore (moves_new.lua is
  -- gone; see main.lua's wireMovepoolSubEffects header for the full
  -- migration). main.lua's own isMoveDataComplete, not a second copy --
  -- confirmed drift bug this session: an earlier inline duplicate here
  -- missed main.lua's own exemptions entirely, which would have kept
  -- genuinely-complete moves gated out as "incomplete" forever. main.lua
  -- exports this right after wireMovepoolSubEffects runs, before this
  -- file is ever installed, so it's always set here.
  local isMoveDataComplete = mod.exports.isMoveDataComplete
    or function(liveRecord)
      return liveRecord ~= nil and liveRecord.effect ~= "NO_ADDITIONAL_EFFECT"
    end

  local ndModeledCache = {}
  mod.exports.resetMoveSupportCache=function()ndModeledCache={}end
  -- Every move is judged the SAME way now: read its live registered
  -- record (which already carries forward every field national_dex
  -- itself set, R.moves being schema-leniant about unknown fields, plus
  -- anything any file in this mod has since patched onto it -- trick_room
  -- .lua's own TRICKROOM patch, modern_combat_protect.lua's PROTECT/
  -- DETECT patches, etc.) through isMoveDataComplete. A move with no live
  -- record at all (genuinely unknown to this engine) falls back to
  -- national_dex's own per-generation modeled flag -- not authoritative
  -- for this mod's own work, but a reasonable last resort; a move unknown
  -- to every source is assumed usable rather than refused, since refusing
  -- a move nobody has an opinion about is a worse failure mode than
  -- teaching it.
  local function isUsable(moveId)
    local gaps=mod.exports.moveSupportGaps
    if gaps and gaps[moveId] then return false end
    if not mod.content.moves:get(moveId) then return false end
    if ndModeledCache[moveId] ~= nil then return ndModeledCache[moveId] end
    local liveOk, liveDef = pcall(mod.content.moves.get, mod.content.moves, moveId)
    if liveOk and liveDef and isMoveDataComplete(liveDef) then
      ndModeledCache[moveId] = true
      return true
    end
    local ok, info = pcall(ndExports.moveById, moveId)
    local modeled = true
    if ok and info then
      if info.engineMove then
        modeled = true
      else
        local flag = isGen2 and info.gen2EffectModeled or info.gen1EffectModeled
        if flag ~= nil then modeled = flag end
      end
    end
    ndModeledCache[moveId] = modeled
    return modeled
  end

  local function canonicalLevelUp(speciesId)
    local ok, stats = pcall(ndExports.statsBySpecies, speciesId)
    if not (ok and stats) then return nil end
    return stats.movesFull, stats.movesByMethod
  end

  -- Extras/dataset move id -> the id the live `moves` registry actually
  -- holds, so a learnset can never name a record that does not exist. The
  -- registry answering for the id is the common case and short-circuits;
  -- only a miss pays for the reverse map, which is built once per load and
  -- cached. Its key is national_dex's own `strippedId` for each move it
  -- carries -- the spelling the extras data uses -- and its value is the
  -- registered id, so "PSYCHIC" (extras) resolves to PSYCHIC_M (engine).
  -- A move the extras already spell the engine's way (QUICK_ATTACK,
  -- GIGADRAIN, ...) is answered by the registry directly and never reaches
  -- the map. An id neither source knows is returned unchanged: whether an
  -- unknown move is taught is isUsable()'s decision, not this function's.
  local registeredAlias
  local function registeredMoveId(moveId)
    local ok, live = pcall(mod.content.moves.get, mod.content.moves, moveId)
    if ok and live then return moveId end
    -- Gen 2 first: Gold registers the cart-owned Gen 2 moves WITH separators
    -- (METAL_CLAW, GIGA_DRAIN) while national_dex's extras spell them without
    -- (METALCLAW, GIGADRAIN), and national_dex does not carry the cart-owned
    -- moves at all (src/moves.lua skips any id whose normalised form the cart
    -- already owns) -- so the strippedId reverse map below has no entry for
    -- them and all 45 would otherwise dangle. gen2_vocab resolves a
    -- separator-only difference against the SAME live registry, so the answer
    -- is only ever an id the registry already holds. No-op on Gen 1 (an id
    -- already spelled the registry's way is returned unchanged), so the
    -- fallback is left unguarded by generation on purpose.
    if vocab then
      local fixed = vocab.moveId(moveId)
      if fixed ~= moveId then return fixed end
    end
    if registeredAlias == nil then
      registeredAlias = {}
      local listed, ids = pcall(ndExports.listMoves)
      if listed and type(ids) == "table" then
        for _, registeredId in ipairs(ids) do
          local got, record = pcall(ndExports.moveById, registeredId)
          local stripped = got and type(record) == "table" and record.strippedId
          if type(stripped) == "string" and registeredAlias[stripped] == nil then
            registeredAlias[stripped] = registeredId
          end
        end
      end
    end
    return registeredAlias[moveId] or moveId
  end

  -- listSpecies() (national_dex/src/api.lua:456-478) is the full roster
  -- enumeration -- every species/form id national_dex knows about, which
  -- is also every id main.lua's own Phase 1 already registered into
  -- mod.content.pokemon (that phase's own header: "registers every
  -- species national_dex reports"). The registry existence check below
  -- is defensive, not redundant: this file loads independently and
  -- shouldn't assume Phase 1's own ordering/success.
  local patched, skippedMoves, missingSpecies = 0, 0, 0
  local function reapplyLearnsets()
    if mod.options:get('moves')~='all' then return end
    patched, skippedMoves, missingSpecies = 0, 0, 0
    local ok, roster = pcall(ndExports.listSpecies)
    if not (ok and roster) then
      mod.log:warn("galar_gmax_dex: learnset_ownership: national_dex.listSpecies() unavailable, learnsets unchanged")
      return
    end
    -- listSpecies lists dex entries; forms are registered separately.
    roster={}
    for id in mod.content.pokemon:each()do roster[#roster+1]={id=id}end
    for _, speciesEntry in ipairs(roster) do
      local id = speciesEntry.id
      if id and mod.content.pokemon:get(id) then
        local levelUp, byMethod = canonicalLevelUp(id)
        if levelUp then
          local learnset, level1 = {}, {}
          for _, moveEntry in ipairs(levelUp) do
            local moveId = moveEntry.move and registeredMoveId(moveEntry.move)
            if moveId and isUsable(moveId) then
              -- national_dex's raw movesFull carries level=0 for moves
              -- known from the start (pre-level-1, e.g. a starter's
              -- initial moveset) -- confirmed live, a real Venusaur
              -- levelMoves[1].level==0 failed schema validation
              -- (f.int(1), min 1) on both learnset/levelMoves. Clamp to 1
              -- rather than drop: level1Moves/level1 already exists
              -- specifically to represent "known before level 1", so a
              -- clamped level=1 entry there plus the level1 list below is
              -- the schema's own answer, not a workaround invented here.
              local level = math.max(1, moveEntry.level or 1)
              learnset[#learnset + 1] = { level = level, move = moveId }
              if (moveEntry.level or 1) <= 1 then level1[#level1 + 1] = moveId end
            else
              skippedMoves = skippedMoves + 1
            end
          end
          local patch = isGen2 and { levelMoves = learnset } or { learnset = learnset, level1Moves = level1 }
          if isGen2 and byMethod and byMethod.egg then
            local eggMoves = {}
            for _, moveEntry in ipairs(byMethod.egg) do
              local moveId = moveEntry.move and registeredMoveId(moveEntry.move)
              if moveId and isUsable(moveId) then eggMoves[#eggMoves + 1] = moveId
              else skippedMoves = skippedMoves + 1 end
            end
            patch.eggMoves = eggMoves
          end
          mod.content.pokemon:patch(id, patch)
          patched = patched + 1
        end
      else
        missingSpecies = missingSpecies + 1
      end
    end
    mod.log:info("galar_gmax_dex: learnset_ownership: patched %d species from national_dex (%d not registered, skipped), gated out %d not-yet-implemented move entries",
      patched, missingSpecies, skippedMoves)
  end

  mod.exports.isMoveUsable = isUsable
  mod.exports.reapplyLearnsets = reapplyLearnsets
  mod.exports.registeredMoveId = registeredMoveId

  return { isUsable = isUsable, reapplyLearnsets = reapplyLearnsets, registeredMoveId = registeredMoveId }
end
