-- The byteless-TM pipeline that closes the "machine route" slice of
-- national_dex_effectmodeled_test.lua's own gap: this mod's only route into
-- a learnset is level-up widening (src/moves.lua), and PokeAPI's own more
-- recent games moved a batch of effectModeled = true moves onto an egg,
-- tutor or machine route that pipeline does not model at all -- see that
-- test's own header for the full sixteen-move account. Of the three,
-- "machine" is the one with a real, proven mechanism on this engine: an item
-- carrying `machine = { kind, move, number }`, taught through the engine's
-- own game/src/inventory/ItemEffects.lua TM path -- dev/battle_forms_mod's
-- TM171 for Tera Blast is the working precedent this file generalises.
-- Tutor has no engine mechanism at all (nothing under game/src implements a
-- move-tutor NPC or menu), and the one stranded move with an egg bucket
-- (Heart Stamp, on Miltank) already has other, better routes than a Day
-- Care visit -- both stay named in KNOWN_UNREACHABLE rather than half-built
-- here. tools/build_moves.py's own module docstring has the complete
-- accounting.
--
-- data/moves/generated/machine_teach.lua (built by tools/build_moves.py's
-- select_machine_tm_candidates/assign_tm_numbers) supplies the roster: one
-- row per invented TM, `{ item, move, number, species }`. This file's own
-- job is three plain registrations per row -- the item, the tmhm patches,
-- the mart listing -- and nothing about WHICH moves get one: that decision
-- is the builder's, recomputed from the live PokeAPI cache on every rebuild,
-- which is what keeps this a general pipeline rather than a hand-picked list.
--
-- EVERY ITEM HERE IS BYTELESS ON PURPOSE. `index` is never set. Gen 1 items
-- are one save byte each, 98-233 is packed solid, and 234-255 is down to
-- three free (234-251 taken by dev/battle_forms_mod's Drives and Crystals,
-- 252 by its own TM171 -- see that mod's data/drives.lua for the full
-- accounting). This pipeline is general precisely because it does not ask
-- "which handful of these moves can we afford a byte for" -- it follows
-- dev/battle_forms_mod/data/plates.lua's own precedent instead:
-- game/src/inventory/Bag.lua keys save.inventory BY ITEM ID, never by byte
-- (`for id in pairs(save.inventory)`), so a byteless item still buys, holds
-- and teaches on this engine's own save exactly like a real one. The one
-- thing it cannot survive is a round trip through a real Game Boy .sav
-- export (game/src/save_convert/GenSave.lua indexes purely by numeric
-- `index`), which nothing this pipeline invents needs to.
--
-- GATED ON `widen` -- the MOVES=ALL option, the same gate src/moves.lua's own
-- learnset widening runs under. src/moves.lua's header states the promise
-- plainly: GEN-NATIVE (the default) leaves every learnset byte-identical to
-- a build without the option. A tmhm entry is exactly that kind of change,
-- so under GEN-NATIVE this file registers nothing at all -- not even a
-- dangling item nobody can use yet.
local M = {}

M.PRICE = 3000
M.MART_MAP = "CeladonMart4F"
M.MART_CLERK = "TEXT_CELADONMART4F_CLERK"

-- A form pseudo-record -- both baseSpecies and form set, national_dex/
-- src/api.lua's own test for one -- can never be a battler's mon.species:
-- every alternate-form transformation this project makes overrides a
-- battler's stats and types without ever touching mon.species (see
-- dev/battle_forms_mod/src/tera.lua's own header), so a tmhm entry on a
-- form record would be unreachable no matter what taught it.
-- tools/build_moves.py's own machine_species_by_slug already excludes every
-- PokeAPI id >= 10000 (the form range) for exactly this reason; this is the
-- same rule checked again at the far end, the way
-- dev/battle_forms_mod/src/terablasttm.lua's M.eligible is.
function M.eligible(record)
  if type(record) ~= "table" then return false end
  return not (record.baseSpecies and record.form)
end

-- Registers every row in `entries`, teaches the eligible species, and sells
-- the lot at Celadon Mart 4F. Returns { registered, taught } -- counts a
-- caller can log, never raises.
function M.install(mod, entries, widen, generation)
  if not widen then return { registered = 0, taught = 0 } end
  if type(entries) ~= "table" then return { registered = 0, taught = 0 } end

  local moves = mod.content and mod.content.moves
  local pokemon = mod.content and mod.content.pokemon
  local registered, taught, itemIds = 0, 0, {}

  for _, entry in ipairs(entries) do
    local moveBase = moves and type(moves.get) == "function" and moves:get(entry.move)
    -- effectModeled is checked LIVE against the merged registry rather than
    -- trusted from the build, for the identical reason
    -- dev/battle_forms_mod/src/terablasttm.lua checks moveExists live: a
    -- build missing this move (national_dex disabled entirely, or an older
    -- payload) must not register a `machine` field naming an
    -- f.id("moves") reference that cannot resolve -- the loader's own
    -- cross-reference pass fails the WHOLE load on one of those.
    local modeled = type(moveBase) == "table" and moveBase.effectModeled == true

    -- The item's own bag identity is claimed unconditionally, the same rule
    -- dev/battle_forms_mod/src/keyitems.lua's own header states for every
    -- item table in that mod: "an item a save carries has to stay nameable
    -- no matter what any gate later says." Only the fields that CLAIM
    -- something about the move -- `machine` -- are gated on the move
    -- actually being there and honestly modeled.
    local record = {
      id = entry.item, name = entry.item, price = M.PRICE,
      needsTarget = true, tossable = true,
    }
    if modeled then
      record.machine = { kind = "TM", move = entry.move, number = entry.number }
    elseif mod.log then
      mod.log:warn(
        "national_dex: %s is not a registered, effectModeled move -- %s "
          .. "registers with no machine field, so it exists in the bag but "
          .. "cannot teach anything this run", entry.move, entry.item)
    end
    mod.content.items:register(entry.item, record)
    registered = registered + 1
    itemIds[#itemIds + 1] = entry.item

    if modeled then
      for _, speciesId in ipairs(entry.species or {}) do
        local base = pokemon and type(pokemon.get) == "function"
          and pokemon:get(speciesId)
        if M.eligible(base) then
          mod.content.pokemon:patch(speciesId, {
            tmhm = { __append = { entry.move } },
          })
          taught = taught + 1
        end
      end
    end
  end

  -- Sold on the Celadon department store's stone floor, behind whatever a
  -- sibling mod already put there (a "deep" registry concatenates every
  -- mod's patch onto the same list, in whichever order the mods load --
  -- dev/battle_forms_mod/src/shop.lua's own shelf() rests on the identical
  -- fact). Only when there is at least one item to sell: an empty mart patch
  -- would still be a harmless no-op, but there is nothing to say with it.
  if generation ~= 3 and #itemIds > 0 and mod.content.text_pointers then
    mod.content.text_pointers:patch(M.MART_MAP,
      { [M.MART_CLERK] = { mart = itemIds } })
  end

  if mod.log then
    mod.log:info("national_dex: machine TMs registered=%d taught=%d",
      registered, taught)
  end
  return { registered = registered, taught = taught }
end

setmetatable(M, { __call = function(_, ...) return M.install(...) end })

return M
