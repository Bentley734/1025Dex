-- National dex wiring: species data beyond the 151 the ROM describes, the
-- modern type chart that data's typing needs, and the dex-page text for the
-- new species.
--
-- Engine seams this module drives (gen1recomp src/mods/Schemas.lua):
--   * mod.content.type_chart:register(id, value) -- bare type ids are
--     records {name, category}; "ATTACKER>DEFENDER" ids are matchup rows
--     with an x10 multiplier.  The engine registers the Gen 1 chart itself
--     (src/battle/TypeChart.lua); this module only ever registers the
--     modern chart, because national-dex typing is Gen 6+ -- DARK/STEEL/
--     FAIRY cannot exist on a Gen 1 chart, and species types are validated
--     against the merged chart.
--   * mod.content.text:register(id, str) -- dex-page description text, read
--     back at game.data.text[dexEntry.text] (src/ui/DexEntryMenu.lua:115).
--   * mod.content.pokemon:register / :patch -- beyond-151 species register
--     in full; the existing 151 species are patched with their modern
--     typing only, leaving their ROM art, learnsets and dex text untouched.
--     national.register ALSO carries the 326 alternate-form species (megas,
--     gigantamax, regional variants, ...) build_national_dex.py emits
--     alongside the 874 beyond-151 species -- a form is just another
--     pokemon record in the same table, with two extra fields (`form`,
--     `baseSpecies`) the schema's :register validator passes through
--     untouched (game/src/mods/Schemas.lua, Schemas.check's spec.fields
--     branch: unknown top-level keys are only rejected when they look like
--     a typo of a real field).  A form is NEVER a new Pokedex list row --
--     see the dexSize computation below for why registering it can't
--     accidentally grow the list past the true 1025.
--   * mod.content.constants:patch -- dexSize/dexDigits, so the dex list
--     (src/ui/PokedexMenu.lua iterates 1..dexSize) and the entry-page
--     number width grow with the roster.
--
-- The registered `learnset`/`level1Moves` reference only engine-known move
-- ids (the build tool filters against the engine's generated move table) --
-- that stays true, this engine still cannot execute a move it never
-- registered.  Every record additionally carries the complete modern data
-- unfiltered: `movesFull` (the full level-up learnset, including levels this
-- engine's move table cannot resolve), `movesByMethod` (machine/egg/tutor/
-- other), `abilities`, `evYield`, `eggGroups`, `baseHappiness`,
-- `growthRateName`, `genderRate` -- passthrough extra fields the same way
-- `form`/`baseSpecies`/`spAttack`/`spDefense` already are, for a dex page or
-- a Showdown-style battle engine built on top of this mod to read.  Beyond-
-- 151 species (and every form) share a shipped placeholder pic
-- (assets/sets/placeholder/*.png): battle loads spriteFront/Back with
-- love.graphics.newImage, which throws on a missing file, so those paths
-- must always exist.
--
-- Every registration is individually guarded: one bad record must never
-- fail the whole mod load.

-- The build tool emits sprite paths relative to the mod, because the install
-- location is only known at runtime.  Nothing anchors them for us: a species
-- record's art goes out through Sprites.path, and Assets.resolve rewrites
-- only paths under the engine's generated-assets prefix, so a bare
-- "assets/..." path is looked up at the *game* root and love throws
-- "Could not open file" the moment the species enters battle.  (Spelling
-- that prefix out here would trip modkit's MK301 ROM-content gate, which
-- matches the literal substring anywhere in a .lua body.)
-- mod.assets:path is the engine's sanctioned anchor
-- (Loader.lua: mod.path .. "/" .. relative).  Idempotent, so a payload that
-- already ships anchored paths passes through untouched.
local ART_KEYS = { "spriteFront", "spriteBack" }

local function anchorArt(mod, record)
  local prefix = mod.path .. "/"
  for _, key in ipairs(ART_KEYS) do
    local rel = record[key]
    if type(rel) == "string" and rel ~= ""
      and rel:sub(1, #prefix) ~= prefix then
      record[key] = mod.assets:path(rel)
    end
  end
end

-- Two measurements the generated payload spells in its own dialect rather
-- than the engine's.  Both reach a screen only for a species the player OWNS
-- -- the entry page prints neither for one merely seen -- which is how they
-- survived this long.
--
-- `heightM` is read by that page as "this record measures in metres", and it
-- answers with the German GR./GEW. rows and a decimal comma
-- (src/ui/DexEntryMenu.lua:107-113).  There is no seam meaning "metric" in
-- any other language, and nothing in the engine's own import sets the field
-- at all, so every species this mod adds gave its size in German beside 151
-- Kanto species giving feet and pounds.  The metric pair is dropped rather
-- than translated: the imperial pair beside it is the same measurement and is
-- the one the page is built to print.
--
-- `weight` is TENTHS of a pound to the engine -- Snorlax is 10140 and the
-- page divides by ten before drawing it -- while the payload carries whole
-- pounds, so every species this mod adds weighed a tenth of what it should.
-- Folded here so one unit holds across both games; Gold's entry screen reads
-- the same field (src/gen2dexlist.lua weightWord).
local METRIC_KEYS = { "heightM", "weightKg" }

local function normaliseMeasures(record)
  local entry = record.dexEntry
  if type(entry) ~= "table" then return end
  for _, key in ipairs(METRIC_KEYS) do entry[key] = nil end
  if type(entry.weight) == "number" then
    entry.weight = math.floor(entry.weight * 10 + 0.5)
  end
end

-- One UTF-8 character.  The payload spells Pokémon and Flabébé with a real
-- é, and a budget counted in bytes would break those lines a glyph early.
local GLYPH = "[\1-\127\194-\244][\128-\191]*"

local function glyphs(text)
  local count = 0
  for _ in text:gmatch(GLYPH) do count = count + 1 end
  return count
end

local function firstGlyphs(text, count)
  if count < 1 then return "" end
  local kept, taken = {}, 0
  for glyph in text:gmatch(GLYPH) do
    taken = taken + 1
    if taken > count then break end
    kept[taken] = glyph
  end
  return table.concat(kept)
end

-- The entry page draws a description one screen row per line break and wraps
-- nothing at all (src/ui/DexEntryMenu.lua:115-122): the cart's own entries
-- arrive already broken, so that loop is a printer and not a formatter.  This
-- mod's prose arrives as one flowing sentence -- tools/build_national_dex.py
-- collapses the source's own breaks, which were measured for a different
-- screen -- and so was drawn as a single line starting at the left margin and
-- running off the right edge, with about a fifth of it on the screen.  That
-- is only visible for a species the player OWNS, because the page prints no
-- description at all for one merely seen.
--
-- Broken here, at registration, rather than in the generated data, for the
-- reason the display casing is: this page belongs to the engine and neither
-- this mod nor any other patches it, so the data it is handed is the only
-- place a fix can live.
--
-- 19 glyphs is what the row physically holds -- the text starts at x=8 on a
-- 160px screen, so the nineteenth ends exactly at the right edge -- and 7 is
-- the rows the page has (y starts at 72, steps 10, and stops once it passes
-- 132).  The cart's own entries never exceed 18 because they were written to
-- fit, which is not the same as 19 not fitting: taking the last column back
-- carries 75 more of the 1025 entries inside the page.
--
-- Prose that needs more than that ends in the font's own ellipsis, so a cut
-- reads as a cut rather than as a sentence that simply stops.
local ENTRY_COLS, ENTRY_ROWS = 19, 7
local ELLIPSIS = "…"

local function wrapEntry(text)
  if type(text) ~= "string" then return text end
  local lines, current = {}, ""
  local function flush()
    if current ~= "" then lines[#lines + 1] = current end
    current = ""
  end
  for word in text:gmatch("%S+") do
    -- A word wider than the box is cut rather than left to overhang.  Dex
    -- prose has none today; a payload rebuilt against a newer source might.
    while glyphs(word) > ENTRY_COLS do
      local head = firstGlyphs(word, ENTRY_COLS)
      flush()
      lines[#lines + 1] = head
      word = word:sub(#head + 1)
    end
    local candidate = current == "" and word or (current .. " " .. word)
    if glyphs(candidate) <= ENTRY_COLS then
      current = candidate
    else
      flush()
      current = word
    end
  end
  flush()
  if #lines > ENTRY_ROWS then
    local last = lines[ENTRY_ROWS]
    if glyphs(last) >= ENTRY_COLS then
      last = firstGlyphs(last, ENTRY_COLS - 1)
    end
    lines[ENTRY_ROWS] = (last:gsub("%s+$", "")) .. ELLIPSIS
    for index = #lines, ENTRY_ROWS + 1, -1 do lines[index] = nil end
  end
  return table.concat(lines, "\n")
end

return function(mod, chart, national, gen2shape, generation, era, display, gen3shape)
  local patched, registered, texts, skipped, charted = 0, 0, 0, 0, 0
  local firstError
  -- On Gold the same registry validates a DIFFERENT record shape and the
  -- cart has already claimed #1-251; src/gen2shape.lua carries both facts.
  local gen2 = gen2shape ~= nil and generation == 2
  local gen3 = gen3shape ~= nil and generation == 3

  local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then
      skipped = skipped + 1
      if not firstError then firstError = tostring(err) end
    end
    return ok
  end

  -- The engine registers its OWN chart before any mod runs -- Red's 15 types
  -- and their matchups on a Gen 1 cart, Gold's 19 on a Gen 2 one -- and
  -- :register throws on an id that already exists rather than quietly
  -- yielding.  Every one of those throws used to land in safe() below and be
  -- counted as a skip, so the cart's row won and the era the player picked
  -- was applied ONLY to matchups involving the types the cart had never
  -- heard of.  Ghost against Psychic stayed at Gen 1's 0x under a MODERN
  -- chart that says 2x.  :override is the seam that says "this mod's answer
  -- wins" out loud, and it is the whole reason an era option means anything.
  local function claim(registry, id, value)
    if registry:get(id) ~= nil then
      registry:override(id, value)
    else
      registry:register(id, value)
    end
  end

  if chart and not gen3 then
    if type(chart.types) == "table" then
      for id, record in pairs(chart.types) do
        safe(function() claim(mod.content.type_chart, id, record) end)
      end
    end
    if type(chart.rows) == "table" then
      for _, row in ipairs(chart.rows) do
        if safe(function()
          claim(mod.content.type_chart, row.attacker .. ">" .. row.defender,
            { multiplier = row.multiplier })
        end) then
          charted = charted + 1
        end
      end
    end
  end

  if national then
    if type(national.text) == "table" then
      for id, value in pairs(national.text) do
        if safe(function()
          mod.content.text:register(id, wrapEntry(value))
        end) then
          texts = texts + 1
        end
      end
    end
    if type(national.patch) == "table" then
      for id, partial in pairs(national.patch) do
        if safe(function() mod.content.pokemon:patch(id, gen3 and gen3shape.romPatch(partial) or partial) end) then
          patched = patched + 1
        end
      end
    end
    if type(national.register) == "table" then
      -- Gold's own roster is 251, so its dex list already starts there.
      local dexSize = gen3 and gen3shape.ROM_DEX_MAX
        or (gen2 and gen2shape.ROM_DEX_MAX or 151)
      -- national.register mixes two record shapes: the 874 beyond-151
      -- SPECIES (record.dex is their own, never-before-seen national dex
      -- number, up to 1025) and the 326 alternate-FORM records
      -- (record.dex is always their BASE species' number, which some
      -- species record here has already claimed).  Both feed the same
      -- max() below, but a form's dex can only ever repeat a number
      -- already in range 1..1025, never exceed it, so it can raise
      -- dexSize past 151 the same way a species does but can never push
      -- it past the true ceiling.  PokedexMenu.lua's list stays exactly
      -- 1025 rows even though this loop registers 1200 pokemon records.
      for id, record in pairs(national.register) do
        -- Forms are numbered far above the real roster (build_national_dex's
        -- FORM_DEX_BASE) so they can never collide with a species in
        -- PokedexMenu.lua's `byDex[def.dex] = def` lookup -- last writer wins
        -- there, and a form sharing its base's number REPLACED that base, so
        -- every species with a form printed "-----" as unseen.  They must
        -- therefore be skipped here too, or dexSize would jump to 20000+ and
        -- the list would walk twenty thousand empty rows.
        if type(record.dex) == "number" and record.dex > dexSize
          and record.form == nil then
          dexSize = record.dex
        end
        safe(function() anchorArt(mod, record) end)
        safe(function() normaliseMeasures(record) end)
        -- The cart draws PIKACHU and this payload spells its own species
        -- "Chikorita", so without this the dex reads as two games spliced
        -- together from #152 up.  Cased here rather than in the generated
        -- data because the engine's OWN screens -- the dex list, the entry
        -- page, the battle HUD, the party menu -- draw record.name directly
        -- and this mod patches none of them; a fix applied only in the
        -- screens it does patch would leave exactly those inconsistent.
        -- src/displayname.lua carries what "uppercase" is allowed to mean
        -- and why the accented names come out of it unchanged.
        if display then
          safe(function() record.name = display.upper(record.name) end)
        end
        -- On Gold #152-251 arrive with the player's cart, before any mod
        -- runs, so this mod has nothing to register for them -- only modern
        -- typing to offer, the same deal the Kanto 151 get on both games.
        -- Claiming an id the ROM import already holds is not a registration
        -- this mod is entitled to make, and their base stats are live Gen 2
        -- battle numbers rather than the collapsed Special that Gen 1 leaves
        -- this mod free to reinterpret.
        if gen2 and gen2shape.romOwned(record) then
          if safe(function()
            mod.content.pokemon:patch(id, gen2shape.romPatch(record))
          end) then
            patched = patched + 1
          end
        elseif gen3 and gen3shape.romOwned(record) then
          if safe(function()
            mod.content.pokemon:patch(id, gen3shape.romPatch(record))
          end) then
            patched = patched + 1
          end
        else
          local payload = gen3 and gen3shape.record(record)
            or (gen2 and gen2shape.record(record) or record)
          if safe(function() claim(mod.content.pokemon, id, payload) end) then
            registered = registered + 1
          end
        end
      end
      -- the dex list and its number width come from constants; both were
      -- seeded pre-merge (src/core/Data.lua seedDefaults) so patch them here
      if not gen3 then
        safe(function() mod.content.constants:patch("dexSize", dexSize) end)
        safe(function()
          mod.content.constants:patch("dexDigits",
            math.max(3, #tostring(dexSize)))
        end)
      end
    end
  end

  -- The load tally goes through mod.log rather than print: the loader
  -- prefixes it with [national_dex] and the launcher's log pane is where a
  -- player gets sent when a mod misbehaves.  A bare print reaches neither.
  mod.log:info("gen=%d chart=%s rows=%d patched=%d registered=%d text=%d "
    .. "skipped=%d", generation, chart and (era or "yes") or "none",
    charted, patched, registered, texts, skipped)
  -- Skips are the number worth surfacing -- a record the schema refused is a
  -- species the player will not find -- so they get their own line at a level
  -- that stands out, naming the first cause rather than only counting.
  if skipped > 0 then
    mod.log:warn("%d registration(s) skipped; first: %s", skipped,
      tostring(firstError))
  end
end
