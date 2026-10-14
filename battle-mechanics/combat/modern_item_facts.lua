-- Item-facts foundation + ROM-vs-Showdown id bridge (item-effects plan,
-- Phase 24). This is the item counterpart to the move pipeline's Phase 0
-- audit: the one shared vocabulary every later item phase reads instead of
-- re-deriving the same id rewrites and API quirks.
--
-- PRIMARY SOURCE / CONTRACT. national_dex exposes item FACTS through its
-- own `itemFlags(id)` accessor (src/api.lua, API_VERSION 9), backed by
-- data/items/generated/flags.lua (530 keys). Its own header states the
-- contract verbatim: "FACTS, never behaviour." So this file can answer
-- "what is this item's fling power / is it a Poké Ball / is it a berry /
-- which species may use it" and can never answer "what does it DO". Every
-- behaviour stays hand-written in the combat layer, exactly as before.
--
-- THE ID MISMATCH. A Gen 2 mon carries a real ROM underscore constant on
-- `mon.item` -- "KINGS_ROCK", "SCOPE_LENS", "BLACKBELT_I", "LIGHT_BALL"
-- (confirmed against scratch/base-gen2-Battle.lua's own reads). flags.lua
-- is generated from Showdown and keys on Showdown's separator-free ids --
-- "KINGSROCK", "SCOPELENS", "BLACKBELT", "LIGHTBALL". So `itemFlags("KINGS_ROCK")`
-- returns nil for every item in the game, which is exactly the bug that
-- made Judgment / Multi-Attack / Techno Blast / Natural Gift silently do
-- nothing for an underscore id. `norm` (strip every non-alphanumeric,
-- upper-case) reconciles them: 48 of the 250 ROM ids then match, with a
-- single rename needed (BLACKBELT_I -> BLACKBELT, verified live against
-- the roster -- every other mismatch normalizes cleanly).
--
-- THE API'S BLIND SPOT IS THIS ROM'S ROSTER. flags.lua omits every item
-- Showdown tags `["True Past"]` (a data-generation choice, not an
-- oversight). Cross-checking scratch/showdown/items.ts against flags.lua
-- shows the thirteen omitted items are exactly the Gen-2-exclusive held
-- items this mod's roster is built from: the ten berries, Pink Bow,
-- Polkadot Bow and Berserk Gene. There is nothing to read for them, so
-- TRUE_PAST_FACTS below is not laziness -- it is the only possible source.
-- The values are transcribed directly from the items.ts block for each
-- item (naturalGift type/basePower, the generic 10 fling every isBerry
-- item gets, and Berserk Gene's +2 Atk), with the literal source line
-- beside each. (The berries' naturalGift TYPES look arbitrary -- Berry is
-- Poison, Gold Berry is Psychic -- because Showdown assigned them freely
-- to the Gen 2 "berry" species; they are transcribed verbatim, not
-- invented.)
--
-- Read through `mod.exports.itemFact`; never call national_dex's
-- `itemFlags` directly from combat code again.
return function(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  -- itemFlags may be absent on an older national_dex; every accessor here
  -- tolerates that (it simply falls back to the override table / nil).
  local itemFlags = nationalDex and nationalDex.exports and nationalDex.exports.itemFlags

  ------------------------------------------------------------------
  -- norm(id): the ROM -> Showdown id normalizer. Strip every character
  -- that is not a letter or digit, then upper-case. "KINGS_ROCK" ->
  -- "KINGSROCK", "POKE_BALL" -> "POKEBALL", "BERRY_JUICE" ->
  -- "BERRYJUICE", "BLACKBELT_I" -> "BLACKBELTI" (see the rename below).
  -- Returns nil for a non-string / empty id so callers never index nil.
  ------------------------------------------------------------------
  local function norm(id)
    if type(id) ~= "string" then return nil end
    local n = id:gsub("[^%w]", ""):upper()
    if n == "" then return nil end
    return n
  end

  ------------------------------------------------------------------
  -- The one rename normalization cannot express: the ROM names the
  -- Fighting-boost belt BLACKBELT_I, whose normalized form "BLACKBELTI"
  -- is not Showdown's "BLACKBELT". Every other ROM id reconciles by
  -- normalization alone (verified against the full 250-id roster).
  ------------------------------------------------------------------
  local RENAME = { BLACKBELTI = "BLACKBELT" }

  -- itemFactId(id) -> the flags.lua key for a ROM item id, or nil.
  local function itemFactId(id)
    local n = norm(id)
    if not n then return nil end
    return RENAME[n] or n
  end

  ------------------------------------------------------------------
  -- TRUE_PAST_FACTS: the thirteen items flags.lua cannot describe.
  -- Keys are the normalized ids (what itemFactId returns), so a ROM
  -- "GOLD_BERRY" / "PINK_BOW" maps here directly. Values are transcribed
  -- from scratch/showdown/items.ts; the line in the comment beside each
  -- berry is that item's own block start.
  ------------------------------------------------------------------
  local TRUE_PAST_FACTS = {
    -- Berries (all isBerry + the generic 10 fling; naturalGift per items.ts)
    BERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Poison" } },     -- items.ts:7852
    GOLDBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Psychic" } },    -- items.ts:7937
    MYSTERYBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Fighting" } },   -- items.ts:8030
    PSNCUREBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Electric" } },   -- items.ts:8119
    PRZCUREBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Fire" } },       -- items.ts:8096
    BURNTBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Ice" } },        -- items.ts:7914
    ICEBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Grass" } },      -- items.ts:7962
    BITTERBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Ground" } },     -- items.ts:7893
    MINTBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Water" } },      -- items.ts:7985
    MIRACLEBERRY = { isBerry = true, fling = { basePower = 10 },
      naturalGift = { basePower = 80, type = "Flying" } },     -- items.ts:8008
    -- The two bows: Normal moves x1.1. No fling field in Showdown, so
    -- (per Showdown's own "no fling" rule) they are left unflingable; the
    -- x1.1 BEHAVIOUR lives in modern_held_items_phase2.lua.
    PINKBOW = { truePast = true },                              -- items.ts:8070
    POLKADOTBOW = { truePast = true },                          -- items.ts:8083
    -- Berserk Gene: consumes itself on switch-in for +2 Atk and confusion.
    -- Already native here (Battle:checkBerserkGene); recorded for
    -- completeness so an auditor sees the API is not the reason it is
    -- absent.                                                -- items.ts:7877
    BERSERKGENE = { boosts = { atk = 2 } },
  }

  ------------------------------------------------------------------
  -- itemFact(id): the merged facts record for a ROM item id, or nil.
  -- Precedence is override-then-API (an override field wins; API fields
  -- fill the rest). Cached per normalized id; a cache hit of `false`
  -- means "resolved to nil" and is returned as nil. The record is the
  -- caller's to read, NOT to mutate (it may be shared), so a caller that
  -- needs to edit deep-copies first (the type-modify file already does).
  ------------------------------------------------------------------
  local cache = {}
  local function itemFact(id)
    local fid = itemFactId(id)
    if not fid then return nil end
    local cached = cache[fid]
    if cached ~= nil then return cached or nil end
    local rec = nil
    local override = TRUE_PAST_FACTS[fid]
    if override then
      rec = {}
      for k, v in pairs(override) do rec[k] = v end
    end
    if itemFlags then
      local ok, data = pcall(itemFlags, fid)
      if ok and type(data) == "table" then
        if not rec then rec = {} end
        for k, v in pairs(data) do
          if rec[k] == nil then rec[k] = v end
        end
      end
    end
    cache[fid] = rec or false
    return rec
  end

  ------------------------------------------------------------------
  -- itemFlingFacts(id) -> { basePower, status, volatileStatus } or nil.
  -- The real per-item Fling data: `fling.basePower` (the number) plus the
  -- two on-hit riders Showdown's Fling applies (Poison Barb's `psn`,
  -- King's Rock's `flinch`, Light Ball's `par`). A berry has no explicit
  -- fling field in Showdown -- it gets a flat 10 generically -- so the
  -- override table supplies that 10.
  ------------------------------------------------------------------
  local function itemFlingFacts(id)
    local rec = itemFact(id)
    local f = rec and rec.fling
    if type(f) ~= "table" then return nil end
    return {
      basePower = f.basePower,
      status = f.status,
      volatileStatus = f.volatileStatus,
    }
  end

  -- isBerryItem(id): true when the item is a Berry. Covers the ten Gen-2
  -- berries (via the override) and every modern berry the API knows.
  local function isBerryItem(id)
    local rec = itemFact(id)
    return (rec and rec.isBerry == true) or false
  end

  -- isPokeballItem(id): true for the twelve actual Poké Balls. Replaces
  -- modern_items.lua's old BALL_ITEMS table, which wrongly included
  -- LIGHT_BALL (Showdown's `lightball` is not `isPokeball`, and is in
  -- fact flingable).
  local function isPokeballItem(id)
    local rec = itemFact(id)
    return (rec and rec.isPokeball == true) or false
  end

  -- itemSpeciesMatch(id, speciesId) -> true / false / nil. Reads the
  -- API's own `itemUser` species list (Chansey for Lucky Punch,
  -- Farfetch'd for Stick, ...). nil means "no itemUser data" (API-blind
  -- or an item with no species restriction), so a caller can choose a
  -- fallback rather than treating absence as a rejection.
  local function itemSpeciesMatch(id, speciesId)
    local rec = itemFact(id)
    local users = rec and rec.itemUser
    if type(users) ~= "table" then return nil end
    local target = norm(speciesId)
    if not target then return nil end
    for _, name in ipairs(users) do
      if norm(name) == target then return true end
    end
    return false
  end

  mod.exports.itemFactId = itemFactId
  mod.exports.itemFact = itemFact
  mod.exports.itemFlingFacts = itemFlingFacts
  mod.exports.isBerryItem = isBerryItem
  mod.exports.isPokeballItem = isPokeballItem
  mod.exports.itemSpeciesMatch = itemSpeciesMatch
  mod.exports.truePastFacts = TRUE_PAST_FACTS

  mod.log:info("g9-battle-engine: modern_item_facts installed "
    .. "(ROM->Showdown item-id bridge + itemFlags accessors; %d True-Past "
    .. "overrides; itemFlags %s)", 13, itemFlags and "present" or "absent")
end
