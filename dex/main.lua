-- National dex mod: registers the 1025-species national dex (PokeAPI-derived
-- data built by tools/build_national_dex.py) and the modern type chart its
-- typing needs, entirely through the engine's content registries.
--
-- Mostly data: every registration is guarded individually
-- (src/nationaldex.lua), so one bad record can never fail the load.  Two
-- engine seams on top of that, both in-memory patches over Gen 1 menu classes
-- and both optional -- src/dexpage.lua and src/summarystats.lua, which is what
-- the manifest's engine_internals permission is for.  The generated files are
-- the mod's payload, so they ship with it (they are text data, not artwork).

-- A sibling that fails to read or compile returns nil rather than raising.
-- An assert inside a mod callback takes the whole load down with it, and every
-- caller below can degrade to something a player can still use -- so the
-- failure is reported with the file that broke and what would fix it, and the
-- load carries on.  The loader prefixes [national_dex] already.
local function compileSibling(mod, name, source)
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod zip; a "
      .. "partial extract is the usual cause", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod zip",
      name, tostring(result))
    return nil
  end
  return result
end

local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod zip; the features it "
      .. "provides are skipped", name)
    return nil
  end
  return compileSibling(mod, name, source)
end

local function loadOptionalSibling(mod, name)
  local source = mod:read(name)
  if not source then return nil end
  return compileSibling(mod, name, source)
end

return function(mod)
  local optionRows={
    { key = "national_dex", label = "NATIONAL DEX", type = "choice",
      default = "on", choices = { { "OFF", "off" }, { "ON", "on" } } },
    -- Which ERA's effectiveness chart to play with, not merely whether to
    -- add the three modern types.  Each of the three ships as its own
    -- generated table and is applied so it WINS over whatever the cart
    -- supplied; picking the era the running game already is costs nothing
    -- and changes nothing.
    { key = "type_chart", label = "TYPE CHART", type = "choice",
      default = "modern", choices = { { "GEN 1", "gen1" }, { "GEN 2", "gen2" },
                                    { "MODERN", "modern" } } },
    -- DISPLAY ONLY -- mirrors TYPE_CHART's shape but gates nothing here.
    -- Every species/form record already carries BOTH the collapsed Gen 1
    -- `baseStats.special` the engine's battle math reads (unchanged,
    -- non-negotiable) AND the raw spAttack/spDefense split (see
    -- src/nationaldex.lua's docs and dev/reports/forms_inventory.txt for
    -- the split's provenance).  This option exists so a future dex UI page
    -- can ask mod.options:get("stats") to decide whether to SHOW one
    -- Special number or two -- it must never be read anywhere that feeds
    -- a registered record or battle math.  Do not wire it into
    -- src/nationaldex.lua's registration path.
    { key = "stats", label = "STATS", type = "choice",
      default = "gen1", choices = { { "GEN 1", "gen1" }, { "MODERN", "modern" } } },
    -- LEARNSETS ONLY.  The modern move ROSTER is registered either way (see
    -- src/moves.lua for why that is the safe arrangement rather than the
    -- generous one), so this option decides one thing: whether a species is
    -- taught the modern moves it learns by level in the current games, or
    -- keeps exactly the list it has today.  GEN-NATIVE is optional and
    -- leaves every learnset byte-identical to a build without this option.
    { key = "moves", label = "MOVES", type = "choice",
      default = "all", choices = { { "GEN-NATIVE", "gen-native" },
                                          { "ALL", "all" } } },
  }
  -- Gen 3 uses the real modern adapter; there is no substitution mode.
  if require('src.core.GameVersion').generation()==3 then
    for i=#optionRows,1,-1 do
      if optionRows[i].key=='stats' then table.remove(optionRows,i)
      elseif optionRows[i].key=='moves'then optionRows[i].choices={{'ALL','all'}}end
    end
  end
  mod.options:define(optionRows)

  local nationalDex = mod.options:get("national_dex") == "on"

  -- src/displayname.lua cases a name the way the cart cases its own, and is
  -- handed to the two registration paths below for the same reason
  -- gen2shape is handed in: a mod's files load as chunks through mod:read,
  -- not through package.path, so require() cannot see a sibling of this mod.
  -- A load failure costs the casing and nothing else -- both callers treat a
  -- missing module as "leave the name as the payload spelled it", which is
  -- what every build before this one did.
  local display = loadSibling(mod, "src/displayname.lua")

  -- src/gen2shape.lua answers which generation is booting and reshapes a
  -- record for it.  Handed in rather than required from nationaldex.lua
  -- because a mod's own files load as chunks through mod:read, not through
  -- package.path -- require() cannot see a sibling of this mod.
  local gen2shape = loadSibling(mod, "src/gen2shape.lua")
  local gen3shape = loadSibling(mod, "src/gen3shape.lua")
  -- Assume Gen 1 when it could not be loaded: that is what every build before
  -- Gold did, and it is the shape the Red/Blue/Yellow records already have.
  -- Guessing 2 here would reshape records for a schema that is not running.
  local generation = gen3shape and gen3shape.generation(mod)
    or (gen2shape and gen2shape.generation(mod)) or 1

  -- FireRed's first Gen 3 runtime build exposes the mod species slot as
  -- 1..1023. The backing tables are dynamic; additions and the shipped form
  -- IDs fit in unsigned 16-bit species slots. Lift the guard before
  -- registering the national payload, so this stays a normal installable mod
  -- and never asks the player to replace or patch Gen1Recomp itself.
  if generation == 3 then
    local ok, Schemas = pcall(require, "src.mods.Schemas")
    local fields = ok and Schemas and Schemas.REGISTRIES
      and Schemas.REGISTRIES.pokemon and Schemas.REGISTRIES.pokemon.gen3Fields
    if fields and Schemas.f and Schemas.f.opt and Schemas.f.int then
      fields.index = Schemas.f.opt(Schemas.f.int(1, 65535))
    else
      mod.log:warn("FireRed species-cap compatibility shim unavailable")
    end
  end

  -- The era the cart already plays by.  Applying that same era over the top
  -- would register a few hundred rows to say what the game already says, so
  -- it is skipped -- EXCEPT with the national dex on, which needs all 18
  -- type records to exist whatever the multipliers between them are, or
  -- every species past #151 carries a type the chart cannot resolve and
  -- fails to register at all.
  local ERAS = { gen1 = true, gen2 = true, modern = true }
  local era = mod.options:get("type_chart")
  if not ERAS[era] then era = "gen1" end
  local nativeEra = generation == 2 and "gen2" or "gen1"
  local chart = (nationalDex or era ~= nativeEra)
    and loadOptionalSibling(mod,
      "data/species/generated/type_chart_" .. era .. ".lua") or nil

  local national = nationalDex
    and loadOptionalSibling(mod, "data/species/generated/national.lua") or nil
  if generation == 3 and national then
    assert(loadSibling(mod,'src/gen3prepare.lua'))(mod)
    gen3shape.install(mod, national)
  end
  if chart then
    local register = loadSibling(mod, "src/nationaldex.lua")
    -- gen2shape may be nil and nationaldex.lua reads that as "assume Gen 1";
    -- without the registration module there is nothing to run at all, and the
    -- cart's own species stay exactly as it supplied them.
    if register then
      register(mod, chart, national, gen2shape, generation, era, display, gen3shape)
    end
  end

  -- The three modern types (DARK/STEEL/FAIRY) a modern move's own `type`
  -- field can name.  src/moves.lua registers the full modern roster
  -- UNCONDITIONALLY -- see that file's own header: registration must never
  -- depend on an option, or turning MOVES back off would delete an already-
  -- learned move off a save -- but until now the only thing that ever taught
  -- the engine those three type ids was the `chart`-gated block just above,
  -- which is skipped on a totally untouched install (TYPE CHART stays at the
  -- cart's own GEN 1 and NATIONAL DEX defaults OFF, so era == nativeEra and
  -- nationalDex is false).  Every DARK/STEEL/FAIRY move in the roster -- over
  -- a hundred of them -- registered a `type` no registry actually carried,
  -- and Schemas.crossValidate turned each into a hard "unresolved reference
  -- to type_chart" load error on every single boot, listed on every mod's
  -- error page in the manager, not merely this one's.  The three records are
  -- byte-identical across every era file (only the matchup ROWS differ), so
  -- gen1's copy answers for all of them; `mod.content.type_chart:get(id)`
  -- guards against double-registering whatever `chart` above already claimed.
  local typeStubs = loadOptionalSibling(mod,
    "data/species/generated/type_chart_gen1.lua")
  if generation ~= 3 and typeStubs and type(typeStubs.types) == "table" then
    for id, record in pairs(typeStubs.types) do
      if mod.content.type_chart:get(id) == nil then
        local ok, err = pcall(function()
          mod.content.type_chart:register(id, record)
        end)
        if not ok then
          mod.log:warn("modern type stub %s failed to register (%s) -- any "
            .. "move naming it will fail to resolve", id, tostring(err))
        end
      end
    end
  end

  -- The modern move roster (src/moves.lua).  Unconditional, and ordered
  -- AFTER the species registration above for one reason: widening a learnset
  -- means reading the species record back and patching it, so every record
  -- this mod is going to supply has to be in the registry first.  The
  -- registration half does not care about the order, but running the whole
  -- module in one place keeps the two halves from drifting apart.
  --
  -- One file per generation, because a move's `effect` is a reference into
  -- `move_effects` and the two games' effect vocabularies are disjoint -- see
  -- tools/build_moves.py.  Optional like every other data sibling: a missing
  -- file costs the modern moves and nothing else.
  local widenMoves = generation ~= 3 and mod.options:get("moves") == "all"
  local movePayload = loadOptionalSibling(mod,
    "data/moves/generated/registry_gen" .. (generation == 2 and 2 or 1) .. ".lua")
  if movePayload and generation ~= 3 then
    -- Per-move FLAGS (contact, sound, punch, ...), merged onto the records
    -- the registry above already carries.  A SEPARATE payload with a separate
    -- owner: PokeAPI carries no move flags at all, so tools/build_move_flags.py
    -- imports them from the reference tools/verify_move_meta.py already trusts
    -- and writes them alone.  Merging here rather than at build time is what
    -- lets either tool be re-run without discarding the other's work.
    --
    -- Additive only: a flag never replaces a field the registry owns, and a
    -- move the reference does not name simply keeps no flags -- which is why
    -- `flags` is absent rather than empty on those, so a reader can tell "no
    -- flags" from "not asked about".  A missing file costs the flags and
    -- nothing else, like every other optional sibling here.
    local flagPayload = loadOptionalSibling(mod,
      "data/moves/generated/flags.lua")
    if type(flagPayload) == "table" and type(movePayload.moves) == "table" then
      for id, record in pairs(movePayload.moves) do
        local flags = flagPayload[id]
        if type(record) == "table" and type(flags) == "table" then
          record.flags = flags
        end
      end
    end
    local Moves = loadSibling(mod, "src/moves.lua")
    if Moves then
      Moves(mod, movePayload, generation, widenMoves, display)
    end
  end

  -- Repairing move slots an EARLIER version of this mod already wrote.
  -- src/moves.lua above stops new ones being made; a move slot is save data,
  -- so a Pokemon that already learned a move under a spelling this game does
  -- not register keeps it at 0/0 PP forever without this. See
  -- src/moverepair.lua's own header for why this is a save.loaded pass rather
  -- than the migration it looks like it should be.
  do
    local Repair = loadSibling(mod, "src/moverepair.lua")
    if Repair then
      Repair.bind({ log = mod.log })
      local function onSave(ev)
        local ok, err = pcall(function()
          local game = (ev and ev.game) or mod.game
          local save = (ev and ev.save) or (game and game.save)
          local data = game and game.data
          if save and data and data.moves then Repair.run(save, data.moves) end
        end)
        if not ok then
          mod.log:warn("national_dex: move-slot repair failed (%s) -- no slot "
            .. "was changed", tostring(err))
        end
      end
      -- Both, for the reason every save-holding module in this project binds
      -- both: `save` is replaced wholesale on NEW GAME and on CONTINUE.
      mod.events:on("save.loaded", onSave)
      mod.events:on("save.created", onSave)
    end
  end

  -- The root move_machines.lua now owns machine items for all generations,
  -- preserving the original TM172--177 identities without duplicate stock.

  -- mod.exports: the integration surface for another mod (a Showdown-style
  -- battle engine is the known first consumer) that wants the real
  -- Sp.Atk/Sp.Def split without re-parsing our generated files or
  -- re-fetching PokeAPI itself.  Read-only, always present regardless of
  -- the NATIONAL DEX/TYPE CHART/STATS options above -- it just answers nil
  -- for any species this mod never touched or that failed to register.
  mod.exports.hasSplitStats = true
  -- speciesId: any engine pokemon id, base species or alternate form
  -- (e.g. "CHARIZARD" or "CHARIZARD_MEGA_X").  Returns
  -- { spAttack = n, spDefense = n } or nil.  Guarded to keep working
  -- whichever way the split data ended up attached to the record (extra
  -- top-level fields, the route this build actually took -- see
  -- dev/reports/forms_inventory.txt -- or, if a future schema change ever
  -- forces it, a sidecar table this function would fall back to reading).
  mod.exports.splitStats = function(speciesId)
    local record = mod.content.pokemon:get(speciesId)
    if type(record) == "table"
      and type(record.spAttack) == "number"
      and type(record.spDefense) == "number" then
      return { spAttack = record.spAttack, spDefense = record.spDefense }
    end
    return nil
  end

  -- STATS page (DOWN from the entry page) and LEFT/RIGHT alternate-form
  -- browsing, patched onto the engine's DexEntryMenu in memory (never onto
  -- disk -- see src/dexpage.lua).  Unconditional: it reads whatever species
  -- record the player already opened, national-dex species and the ROM's
  -- own 151 alike, and simply has nothing to cycle through when a species
  -- has no forms registered.  Captured (rather than the usual
  -- loadSibling(...)(mod) one-liner) so its splitStats lookup can be
  -- handed to the party summary patch below -- one shared helper, not a
  -- second copy of the same field reads.
  -- Handed the generation for the same reason gen2dexlist.lua is: its
  -- neighbour seam is keyed on a Gen 1 screen id, and probing for the game
  -- from inside a file whose require()s all resolve to Gen 1 classes would
  -- only be a second, worse copy of the answer main.lua already has.
  local Dexpage = loadSibling(mod, "src/dexpage.lua")
  if Dexpage then Dexpage(mod, generation) end

  -- Hold UP or DOWN on either game's dex LISTING to scroll faster the longer
  -- it is held (src/dexscroll.lua).  Loaded before the two listing patches
  -- below because Gold's arm is handed this module: the Gen 1 arm installs
  -- itself from here, while the Gold listing's every other patch already lives
  -- in src/gen2dexlist.lua and a second wrapper of that class from a second
  -- file would only be two patches arguing over which runs first.
  --
  -- START on the Gen 1 listing cycles numerical / alphabetical / recorded
  -- (src/dexview.lua).  It rides the same constructor wrap rather than
  -- installing a second one -- the file explains which key it takes and why,
  -- and a sibling that failed to load costs the view modes while leaving the
  -- held scroll exactly as it was.  Gold is untouched by both: dexscroll's
  -- Gen 1 arm returns immediately for generation 2, so nothing here reaches
  -- Gold's #DEX, which has sort modes and a search of its own
  -- (src/gen2dexlist.lua).
  local Dexview = loadSibling(mod, "src/dexview.lua")
  local Dexscroll = loadSibling(mod, "src/dexscroll.lua")
  if Dexscroll then
    Dexscroll(mod, generation, Dexview and Dexview.apply or nil)
  end

  -- The Pokédex free-text SEARCH (Task 11).  src/dexsearch.lua is the pure
  -- query both games share -- one matcher, so "giga drain" means the same
  -- thing on Red and on Gold -- and src/searchindex.lua reads back the
  -- generated reverse index that gives the move and ability vocabularies
  -- something to answer against.  Loaded here, beside the listing patches,
  -- because both screens need it: Gen 1's own further down and Gold's inside
  -- the Gen2Dex block below.
  --
  -- src/dexsearchview.lua is loaded unconditionally too, on both boots, but
  -- only for the pure half at the top of that file (M.edit, M.MAX_LEN) --
  -- Gold shares Gen 1's typing table because which key means which character
  -- is a fact about a keyboard, not about a generation.  M.new, which is the
  -- half that reaches for love and the Gen 1 engine classes, is never called
  -- except from the Gen 1 branch below.
  local Search = loadSibling(mod, "src/dexsearch.lua")
  local Searchindex = loadSibling(mod, "src/searchindex.lua")
  local Searchview = loadSibling(mod, "src/dexsearchview.lua")
  -- Generated, like national.lua and the type charts, and allowed to be
  -- missing the same way -- but unlike them, a missing search index costs
  -- only PART of the feature rather than all of it: name and type search
  -- read the listing's own rows and need nothing from here, so they keep
  -- working.  Only the ability and move vocabularies, which have nowhere
  -- else to come from, go unanswered.
  local searchPayload = loadOptionalSibling(mod,
    "data/species/generated/search_index.lua")
  if Search and Searchindex then
    Search.useIndex(Searchindex)
  end
  if Search and not searchPayload then
    mod.log:info("data/species/generated/search_index.lua is missing -- "
      .. "Pokédex search by name and type still works, but ability and move "
      .. "terms will read as unknown until the mod zip is reinstalled; the "
      .. "payload is generated, and a partial extract is the usual cause")
  end

  -- Gen 1's SEARCH screen opens from the listing's SELECT, which
  -- src/dexview.lua's `augment` binds only once M.openSearch is set -- see
  -- that file's own comment on the seam.  Assigned onto the SAME Dexview
  -- local loaded above rather than a second load of the file: a second load
  -- compiles a second module instance with its own private `marks` table,
  -- and the SELECT mark this closure relies on would then be checked against
  -- a table no handler was ever entered into.
  if generation ~= 2 and Dexview and Search and Searchview then
    Dexview.openSearch = function(list, rows, handle)
      -- The vocabulary is built from the ROWS the listing is showing right
      -- now -- every one of them, known or not, the same way
      -- src/gen2dexsearch.lua's own beginSearch builds Gold's -- so a search
      -- result and the listing behind it are reading the same species list.
      local vocab = { names = {}, types = {}, payload = searchPayload }
      for _, row in ipairs(rows) do
        vocab.names[Search.normalise(row.name)] = true
        for _, id in ipairs(row.types or {}) do
          vocab.types[Search.normalise(id)] = true
        end
      end
      local screen = Searchview.new(list.game, {
        Search = Search,
        vocab = vocab,
        rows = rows,
        onPick = function(row) Dexview.openEntry(list, row, handle) end,
      })
      if not screen then
        if handle and handle.log then
          handle.log:info("the Pokédex search screen failed to build -- the "
            .. "engine did not hand back the font, string, naming or input "
            .. "modules it needs, so SELECT leaves the listing exactly as "
            .. "it was")
        end
        return
      end
      list.game.stack:push(screen)
    end
  end

  -- Gold draws neither of the screens above: its #DEX is its own class, sized
  -- from the cart's dex table rather than from the dexSize constant Gen 1
  -- reads, so the beyond-251 species this mod registers never reached the
  -- listing at all.  src/gen2dexlist.lua is that half -- the listing, and
  -- alternate-form browsing on Gold's entry screen -- and it is handed the
  -- generation rather than probing for it, because require() is NOT
  -- redirected on a Gold boot: every class this mod names resolves to the Gen
  -- 1 one unless it is asked for by its real Gen 2 name.  It is also handed
  -- Dexpage.buildFormList so both games decide a species' form order with the
  -- same function instead of two copies that can drift.
  --
  -- Gold's dex also draws the CART's pic and offers no seam to change it, so
  -- a sprite mod cannot reach that screen from its own side; the third
  -- argument is this mod reaching for it instead, on Gold only.  Entirely
  -- optional -- without the neighbour, or for a species it has no art for,
  -- Gold's own pic is drawn exactly as before -- which is why it is a plain
  -- mod:find closure and not a declared hard dependency.
  local Gen2Dex = loadSibling(mod, "src/gen2dexlist.lua")
  -- ONE resolver for both Gold screens, built here rather than at either call
  -- site.  It caches the neighbour's export the first time it answers, so
  -- sharing it also means the second screen never repeats that lookup.
  local spriteArt = Gen2Dex and Gen2Dex.spriteArt(
    function(id) return mod:find(id) end,
    Dexpage and Dexpage.formCandidates) or nil
  --
  -- The STATS action on Gold's entry bar is the third thing in there, and the
  -- LVL action beside it the fourth, and they are why this call takes the mod
  -- handle: their pages read the base stats, typing, abilities, evolutions and
  -- level-up learnset off mod.exports at draw time, the same surface the Gen 1
  -- page uses.  Dexpage.abilityRows goes with it, and its hidden mark with
  -- that, so both games list the same abilities in the same order and mark the
  -- hidden one the same way -- and the last argument is the rest of that same
  -- arrangement: the evolution line, the level-up section and the paginator
  -- behind LVL are Dexpage's own, so the two games' pages cannot drift apart.
  -- Gold cuts them into fourteen-row pages rather than twelve because its dex
  -- box is taller, which is why paginate takes the count.
  if Gen2Dex then
    Gen2Dex(generation, Dexpage and Dexpage.buildFormList, spriteArt, Dexscroll,
      mod, Dexpage and Dexpage.abilityRows, Dexpage and Dexpage.HIDDEN_MARK,
      Dexpage and {
        evolutionSections = Dexpage.evolutionSections,
        levelUpSection = Dexpage.levelUpSection,
        paginate = Dexpage.paginate,
      } or nil)

    -- Gold's own free-text SEARCH (src/gen2dexsearch.lua), installed onto the
    -- SAME PokedexMenu class Gen2Dex just patched above -- require() caches
    -- by module name, so asking for "src.ui.gen2.PokedexMenu" again here
    -- hands back that identical, already-patched table rather than a second
    -- one.  Resolved by its real Gen 2 name, and Gold's naming screen with
    -- it, because require() is NOT redirected on a Gold boot: the bare
    -- "src.ui.PokedexMenu"/"src.ui.NamingScreen" names would answer with Gen
    -- 1's classes even here.  Gated on generation == 2 so a Gen 1 boot never
    -- reaches for either -- src/gen2dexlist.lua only calls beginSearch once
    -- its own nationalDexSearchInstalled marker is set, and that marker
    -- exists so a Gen 1 boot can never trip it.
    if generation == 2 and Search then
      local Gen2Search = loadSibling(mod, "src/gen2dexsearch.lua")
      if Gen2Search then
        local okMenu, GoldPokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
        local okNaming, GoldNamingScreen = pcall(require, "src.ui.gen2.NamingScreen")
        if okMenu and type(GoldPokedexMenu) == "table"
          and okNaming and type(GoldNamingScreen) == "table" then
          -- shiftDown is not part of src/dexsearchview.lua's exports -- it is
          -- a three-line love.keyboard read local to that file's own screen,
          -- not pure, and not something a headless test of that file should
          -- have to pull love in behind.  Repeated here rather than widening
          -- that file's public table for this one caller.
          local function shiftDown()
            return love and love.keyboard and love.keyboard.isDown
              and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift"))
          end
          local installedSearch = Gen2Search.install(GoldPokedexMenu, {
            Search = Search,
            NamingScreen = GoldNamingScreen,
            -- Shared with Gen 1 rather than copied: which key means which
            -- character is a fact about a keyboard, not about a generation.
            edit = Searchview and Searchview.edit or nil,
            -- charFor decides whether a key is TEXT at all.  Without it the
            -- Gold field cannot tell a letter from a d-pad press, and the
            -- choice is not "consume or ignore" but "consume or hand back":
            -- a key it swallows without using is a key that never reaches
            -- Input, which is how a field ends up eating the very presses a
            -- player needs to leave it.
            charFor = Searchview and Searchview.charFor or nil,
            MAX_LEN = Searchview and Searchview.MAX_LEN or nil,
            shiftDown = shiftDown,
            describeRows = Dexview and Dexview.describe or nil,
            payload = searchPayload,
          })
          if not installedSearch then
            mod.log:info("Gold's Pokédex search screen failed to install -- "
              .. "#DEX keeps the cart's own TYPE1/TYPE2 SEARCH view")
          end
        end
      end
    end
  end

  -- Gold's party SUMMARY has the same two problems its #DEX had -- it reads
  -- the cart's spriteFront with no hook, and it shades whatever it got
  -- through the GBC palette -- so src/gen2summary.lua is the same reach onto
  -- that screen, sharing the resolver above and gen2dexlist's drawing rules
  -- rather than carrying copies.  Art only: Gold already prints SPCL.ATK and
  -- SPCL.DEF itself, so the Gen 1 stats box below has nothing to add here.
  local Gen2Summary = loadSibling(mod, "src/gen2summary.lua")
  if Gen2Summary and Gen2Dex and spriteArt then
    Gen2Summary(generation, spriteArt, Gen2Dex)
  end

  -- Party summary stats box (src/summarystats.lua): same treatment as the
  -- dex page, and unconditional for the same reason -- it reads whatever
  -- mon the player already opened the STATUS screen for.  Passed
  -- Dexpage.splitStats directly so the two screens can never disagree
  -- about which records carry the Sp.Atk/Sp.Def split.
  local Summary = loadSibling(mod, "src/summarystats.lua")
  if Summary then Summary(mod, Dexpage and Dexpage.splitStats) end

  -- The cross-mod read API (src/api.lua): statsByDex / statsBySpecies /
  -- listSpecies / formsOf, published on mod.exports for any other loaded mod
  -- to call in process.  Installed LAST so the two screens above are already
  -- wired if this ever fails, and unconditionally -- a consumer asking this
  -- mod what it knows should get an answer regardless of which display
  -- options the player happens to have set.
  local Api = loadSibling(mod, "src/api.lua")
  -- hasSplitStats/splitStats above are published whatever happens here, so a
  -- consumer that only wants the split still gets an answer.
  if Api then Api(mod) end
end
