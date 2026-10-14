-- Modern (Gen 3+ style) stat fields, layered ADDITIVELY alongside the
-- existing Gen-1-exact src/pokemon/Stats.lua -- nothing here replaces
-- dvs/statExp/stats.special, which stay exactly as they are today and keep
-- driving the native, non-Showdown battle engine unchanged. This module is
-- purely new fields for save persistence + GUI display (SummaryMenu page
-- 3), per the explicit user decision that stats.special is "silently
-- deprecated" going forward without touching anything that already reads
-- it.
--
-- Every Pokemon gets modern data, not just ones that have been through a
-- Showdown battle: a mon with no Showdown-native ivs/evs/nature has them
-- DERIVED from its existing Gen 1 dvs/statExp (explicit user decision).
-- Conversion is linear and applied once, then cached on the mon table --
-- same "derive on demand, idempotent after" contract as Stats.ensure.
--
-- Lives in GalarGmaxDex's own folder, not the engine tree -- loaded once
-- by main.lua into mod.exports.ModernStats (previously package.preload,
-- since removed from the mod sandbox) so every consumer (this mod's own
-- files, and SaveData.validate's wrap in save_scrub.lua) reads the same
-- singleton without needing the engine's own src/pokemon/ to carry it.
-- Keeps the engine tree byte-for-byte stock -- see save_scrub.lua's
-- header for why that split happened and what it replaces.

local ModernStats = {}

local ORDER = { "hp", "atk", "def", "spa", "spd", "spe" }
ModernStats.ORDER = ORDER

-- EV caps. Per-stat never moves (252 either way); only the TOTAL does --
-- 510 classic, 1512 when the 1512-TOTAL-EV scope covers the mon's side
-- (252 in all six). evTotalCap is pure so every enforcer (KO yields,
-- TRAIN, save scrub, trainer builds) shares one rule; the scope itself is
-- read through mod.exports.evScope (main.lua).
ModernStats.EV_PER_STAT = 252
ModernStats.EV_TOTAL = 510
ModernStats.EV_TOTAL_1512 = 1512
function ModernStats.evTotalCap(scope, side)
  if scope == "both" then return ModernStats.EV_TOTAL_1512 end
  if (scope == "enemy" or scope == "player") and scope == side then
    return ModernStats.EV_TOTAL_1512
  end
  return ModernStats.EV_TOTAL
end

-- Fresh, DV-independent modern IVs for a brand-new mon (wild encounters --
-- see wild_modern_ivs.lua) -- NOT a conversion from Gen 1 dvs/statExp the
-- way .ensure below is. .ensure is the legacy path, for a mon that
-- predates this system (e.g. loaded from an old save) and needs its
-- existing dvs/statExp converted; .initialize is for a mon that has
-- never had a DV in the first place -- whatever Pokemon.new rolled into
-- mon.dvs is discarded, never read here. Idempotent via
-- modernStatsInitialized so calling this more than once on the same mon
-- is a no-op, matching .ensure's own idempotent contract.
function ModernStats.initialize(mon)
  if type(mon) ~= "table" then return mon end
  if mon.modernStatsInitialized then return mon end

  mon.ivs = mon.ivs or {}
  mon.evs = mon.evs or {}
  for _, stat in ipairs(ORDER) do
    mon.ivs[stat] = mon.ivs[stat] or love.math.random(0, 31)
    mon.evs[stat] = 0
  end

  mon.modernStatsInitialized = true
  return mon
end

-- Third ingestion path, alongside .initialize (fresh random, wild) and
-- .ensure (DV/statExp conversion, legacy/no-provider fallback): applies
-- modern data an EXTERNAL mod supplied directly (trainer_modern_stats.lua's
-- provider API) -- gender/ability/nature plus {iv=,ev=} per stat, keyed by
-- ModernStats.ORDER. Nothing here reads mon.dvs/mon.statExp at all -- a
-- provider that hands us a spec is asserting its own numbers are
-- authoritative, not something to blend with the Gen-1 conversion.
-- Marks modernStatsInitialized too, so .initialize/.ensure both treat an
-- already-spec'd mon as done (same idempotency flag, one shared meaning:
-- "this mon's modern fields are real, don't derive/randomize over them").
--
-- spec.gender, if given, must be "male"/"female" (lowercase full word) --
-- the real native convention this engine's own Gen 2 code already uses for
-- mon.gender (src/battle/gen2/Mon.lua's Mon.gender, src/ui/gen2/BoxMenu.lua
-- reading it back), not an invented shorthand. Stored as-is, no validation
-- here -- a provider is trusted to pass the right string.
function ModernStats.applySpec(mon, spec)
  if type(mon) ~= "table" or type(spec) ~= "table" then return mon end

  mon.ivs = mon.ivs or {}
  mon.evs = mon.evs or {}
  for _, stat in ipairs(ORDER) do
    local part = spec[stat]
    mon.ivs[stat] = (type(part) == "table" and tonumber(part.iv)) or 0
    mon.evs[stat] = (type(part) == "table" and tonumber(part.ev)) or 0
  end
  if spec.gender ~= nil then mon.gender = spec.gender end
  if spec.ability ~= nil then mon.ability = spec.ability end
  if spec.nature ~= nil then mon.nature = spec.nature end

  mon.modernStatsInitialized = true
  return mon
end

-- Every real nature, 25 total -- the 20 with a stat effect (the union of
-- every name appearing in the five NATURE_* tables below, each nature
-- boosting one stat and lowering a different one) plus the 5 neutral
-- ones (no entry in any NATURE_* table, so natureMult's own `or 1.0`
-- fallback already gives them the correct no-effect multiplier -- they
-- were only ever missing from the RANDOM-PICK list, not from the stat
-- math). Explicit user list for the neutral five: Hardy, Docile,
-- Bashful, Quirky, Serious.
local NATURES = {
  "Hardy", "Docile", "Bashful", "Quirky", "Serious",
  "Modest", "Mild", "Rash", "Quiet", "Adamant", "Jolly", "Careful", "Impish",
  "Calm", "Sassy", "Gentle", "Naive", "Lax", "Naughty",
  "Lonely", "Brave", "Bold", "Timid", "Relaxed", "Hasty",
}
ModernStats.NATURES = NATURES

-- "Natures are to behave in this same manner [as abilities]: love's
-- random picks one of the defined natures." Idempotent -- a mon that
-- already has a nature (assigned, converted, or supplied by a provider)
-- is left untouched; this only ever fills a genuinely missing one.
function ModernStats.generateNature(mon)
  if type(mon) ~= "table" then return mon end
  if mon.nature == nil then
    mon.nature = NATURES[love.math.random(1, #NATURES)]
  end
  return mon
end

-- Reads a species' non-hidden abilities (slot 1 and/or slot 2) out of
-- national_dex's record shape -- { abilities = { {name=,slot=,hidden=},
-- ... } }, confirmed from that mod's own extras data. The hidden-slot
-- entry (slot 3, hidden=true) is deliberately excluded here: explicit
-- user rule, hidden abilities need an exotic item-gated activation this
-- mod doesn't implement yet, so they're never a candidate for plain
-- random generation. Returns a plain array of ability-name strings (0-2
-- entries -- some species only have one non-hidden ability at all), or
-- an empty table if national_dex is absent/disabled or has no data for
-- this species.
function ModernStats.resolveAbilities(species, nationalDexExports)
  local out = {}
  if type(nationalDexExports) ~= "table" or (nationalDexExports.apiVersion or 0) < 1
      or type(nationalDexExports.statsBySpecies) ~= "function" then
    return out
  end
  local ok, rec = pcall(nationalDexExports.statsBySpecies, species)
  if not (ok and type(rec) == "table" and type(rec.abilities) == "table") then
    return out
  end
  for _, entry in ipairs(rec.abilities) do
    if type(entry) == "table" and not entry.hidden and type(entry.name) == "string" then
      out[#out + 1] = entry.name
    end
  end
  return out
end

-- The hidden-slot ability (slot 3, hidden=true) for a species, or nil if
-- it has none / national_dex is absent -- the one entry
-- ModernStats.resolveAbilities deliberately excludes. Same national_dex
-- record shape and nil-safety contract as that function.
function ModernStats.resolveHiddenAbility(species, nationalDexExports)
  if type(nationalDexExports) ~= "table" or (nationalDexExports.apiVersion or 0) < 1
      or type(nationalDexExports.statsBySpecies) ~= "function" then
    return nil
  end
  local ok, rec = pcall(nationalDexExports.statsBySpecies, species)
  if not (ok and type(rec) == "table" and type(rec.abilities) == "table") then
    return nil
  end
  for _, entry in ipairs(rec.abilities) do
    if type(entry) == "table" and entry.hidden and type(entry.name) == "string" then
      return entry.name
    end
  end
  return nil
end

-- Public swap API -- explicit user request: "expose an api for changing
-- hidden abilities <-> to normal abilities. if used by another mod, we
-- swap them." Reachable by any mod via mod:find("g9-battle-engine")
-- .exports.ModernStats.toggleHiddenAbility(...) (main.lua already exposes
-- the whole ModernStats table, no separate wiring needed). This module
-- owns HOW the swap works; deciding WHEN it happens -- an item, a move
-- effect, a debug command -- is entirely the calling mod's own business,
-- same "own the rules, not who triggers them" split as everywhere else in
-- this mod's own combat/ files.
--
-- Currently on the hidden ability -> swaps to the species' first regular
-- ability (slot 1). Currently on any regular ability (or no ability at
-- all) -> swaps to the hidden one, if the species has one. Returns
-- (changed, newAbility): changed is false (newAbility = mon.ability,
-- unchanged) when there's genuinely nothing to swap to in that direction
-- (no hidden ability on this species, or no regular ability to fall back
-- to) -- distinguishable from "swapped" without the caller having to
-- compare the ability name itself (a species' hidden and slot-1
-- abilities are never the same real ability, so that comparison would
-- work too, but this is the honest signal rather than an inference).
function ModernStats.toggleHiddenAbility(mon, species, nationalDexExports)
  if type(mon) ~= "table" then return false, nil end
  local hidden = ModernStats.resolveHiddenAbility(species, nationalDexExports)
  if mon.ability == hidden and hidden ~= nil then
    local regular = ModernStats.resolveAbilities(species, nationalDexExports)
    if not regular[1] then return false, mon.ability end
    mon.ability = regular[1]
    return true, mon.ability
  end
  if not hidden then return false, mon.ability end
  mon.ability = hidden
  return true, mon.ability
end

-- Public swap API -- Ability Capsule's own equivalent, cycling ability
-- slot 1 <-> slot 2 specifically. A distinct, non-overlapping swap from
-- toggleHiddenAbility above (Ability Patch's own job) -- real Ability
-- Capsule never touches a mon currently on its hidden ability, and this
-- mirrors that: fails (changed=false) rather than falling back to a
-- regular ability, so a caller wanting "off hidden, onto a regular one"
-- reaches for toggleHiddenAbility instead, not this. Same (changed,
-- newAbility) return contract as toggleHiddenAbility, same "own the rules,
-- not who triggers them" split.
--
-- Also fails when the species doesn't have two distinct regular abilities
-- to cycle between (many species only ever had one) -- real Ability
-- Capsule has nothing to do there either.
function ModernStats.toggleRegularAbility(mon, species, nationalDexExports)
  if type(mon) ~= "table" then return false, nil end
  local regular = ModernStats.resolveAbilities(species, nationalDexExports)
  if not (regular[1] and regular[2]) then return false, mon.ability end
  if mon.ability ~= regular[1] and mon.ability ~= regular[2] then
    return false, mon.ability
  end
  mon.ability = (mon.ability == regular[1]) and regular[2] or regular[1]
  return true, mon.ability
end

-- "A pokemon must always have an ability, if it doesn't have one, we
-- generate it... ability 1 and 2 are picked by random, 50%/50% of having
-- either. Only 1 ability per pokemon." Idempotent, same contract as
-- generateNature -- an already-set mon.ability (assigned, converted, or
-- provider-supplied) is left alone. candidates is whatever
-- ModernStats.resolveAbilities returned for this mon's species; with 0
-- candidates (no national_dex, or nothing known for this species) there
-- is nothing real to generate from, so this is a deliberate no-op rather
-- than fabricating a placeholder name -- mon.ability stays nil, which
-- every screen that displays it already renders as "----".
function ModernStats.generateAbility(mon, candidates)
  if type(mon) ~= "table" then return mon end
  if mon.ability == nil and type(candidates) == "table" and #candidates > 0 then
    mon.ability = candidates[love.math.random(1, #candidates)]
  end
  return mon
end

-- Gen1 has no native gender concept at all (confirmed: no `gender` field
-- anywhere in src/pokemon/Pokemon.lua, matching real Gen1 cartridges), so
-- a Gen1 mon reaching this mod's Attract handler would otherwise always
-- fail the gender-compatibility check for lack of any gender to compare.
-- Tentatively GalarGmaxDex-owned 50/50 male/female, same idempotent
-- contract as generateNature/generateAbility -- explicit user decision:
-- "gender is to be 50%/50% unless specified in nat_dex... ours will be
-- tentatively owned by us for now until source of truth handles it and
-- its ratios." Replace this with a real per-species ratio lookup once
-- national_dex exposes one; until then this is the whole story. Gen2
-- already derives a real gender from its own dvs at Mon.new time (see
-- src/battle/gen2/Mon.lua's Mon.gender) and is never expected to reach
-- this function with mon.gender still nil, but the idempotent guard makes
-- calling it there harmless too.
function ModernStats.generateGender(mon)
  if type(mon) ~= "table" then return mon end
  if mon.gender == nil then
    mon.gender = love.math.random(1, 2) == 1 and "male" or "female"
  end
  return mon
end

-- national_dex's evYield uses its own full stat names (confirmed real shape
-- from a live Bulbasaur record: {attack=,defense=,hp=,spAttack=,spDefense=,
-- speed=}, only the stats a species actually yields are present -- missing
-- keys mean 0, not nil-as-error). Translated here into ModernStats.ORDER's
-- own convention so callers only ever deal with one key vocabulary.
local EV_YIELD_SOURCE = {
  hp = "hp", atk = "attack", def = "defense",
  spa = "spAttack", spd = "spDefense", spe = "speed",
}

function ModernStats.resolveEvYield(species, nationalDexExports)
  local out = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  if type(nationalDexExports) ~= "table" or (nationalDexExports.apiVersion or 0) < 1
      or type(nationalDexExports.statsBySpecies) ~= "function" then
    return out
  end
  local ok, rec = pcall(nationalDexExports.statsBySpecies, species)
  if not (ok and type(rec) == "table" and type(rec.evYield) == "table") then
    return out
  end
  for key, sourceKey in pairs(EV_YIELD_SOURCE) do
    out[key] = tonumber(rec.evYield[sourceKey]) or 0
  end
  return out
end

-- Applies a resolved yield (ModernStats.ORDER keys) to mon.evs, enforcing
-- the real EV rules -- 252 max per stat, total capped at totalCap (510
-- classic; pass ModernStats.evTotalCap(scope, side) for the 1512 game).
-- Deliberately NOT idempotent/guarded: every KO a
-- mon gains EXP from should grant its yield again, cumulative, exactly like
-- native mon.statExp already accumulates across every faint.
function ModernStats.grantEvYield(mon, yield, totalCap)
  if type(mon) ~= "table" or type(yield) ~= "table" then return mon end
  totalCap = tonumber(totalCap) or ModernStats.EV_TOTAL
  mon.evs = mon.evs or {}
  local total = 0
  for _, key in ipairs(ModernStats.ORDER) do
    total = total + (mon.evs[key] or 0)
  end
  for _, key in ipairs(ModernStats.ORDER) do
    local delta = tonumber(yield[key]) or 0
    if delta > 0 then
      local current = mon.evs[key] or 0
      local budget = totalCap - (total - current)
      local applied = math.max(0, math.min(ModernStats.EV_PER_STAT - current, math.min(budget, delta)))
      mon.evs[key] = current + applied
      total = total + applied
    end
  end
  return mon
end

-- Gen 1 dvs/statExp keys -> the modern stat key(s) each one seeds.
-- attack/defense/speed/hp convert 1:1; special seeds BOTH spa and spd
-- (explicit user decision: same source DV, same converted grade, applied
-- to both -- not split). statExp.special is the one exception that DOES
-- split, handled separately below since it's a single value dividing into
-- two EVs rather than one value copied into two IVs.
local DV_SOURCE = { hp = "hp", atk = "attack", def = "defense", spe = "speed" }

local function convertDV(dv)
  -- 0-15 -> 0-31, linear: DV 15 -> IV 31 exactly, DV 0 -> IV 0.
  return math.floor((tonumber(dv) or 0) * 31 / 15 + 0.5)
end

local function convertStatExp(exp)
  -- 0-65535 -> 0-252, linear.
  return math.floor((tonumber(exp) or 0) * 252 / 65535 + 0.5)
end

-- Gen 1 has no HP DV field of its own (macros/ram.asm derives it from the
-- low bits of the other four, src/pokemon/Stats.lua:19-20) -- reuse the
-- same derivation so a converted HP IV isn't just left at 0.
local function deriveHPDV(dvs)
  dvs = dvs or {}
  return ((dvs.attack or 0) % 2) * 8 + ((dvs.defense or 0) % 2) * 4 +
         ((dvs.speed or 0) % 2) * 2 + ((dvs.special or 0) % 2)
end

-- Nature multipliers, only for the two stats this module actually
-- computes (spa/spd) -- a mon converted from legacy data has no nature
-- (nothing in Gen 1 to derive one from) and gets the neutral 1.0
-- multiplier; a Showdown-created mon (Phase 4) carries a real nature.
local NATURE_SPA = {
  Modest = 1.1, Mild = 1.1, Rash = 1.1, Quiet = 1.1,
  Adamant = 0.9, Jolly = 0.9, Careful = 0.9, Impish = 0.9,
}
local NATURE_SPD = {
  Calm = 1.1, Careful = 1.1, Sassy = 1.1, Gentle = 1.1,
  Naive = 0.9, Lax = 0.9, Rash = 0.9, Naughty = 0.9,
}
local NATURE_ATK = {
  Lonely = 1.1, Adamant = 1.1, Naughty = 1.1, Brave = 1.1,
  Bold = 0.9, Modest = 0.9, Calm = 0.9, Timid = 0.9,
}
local NATURE_DEF = {
  Bold = 1.1, Impish = 1.1, Lax = 1.1, Relaxed = 1.1,
  Lonely = 0.9, Mild = 0.9, Gentle = 0.9, Hasty = 0.9,
}
local NATURE_SPE = {
  Timid = 1.1, Hasty = 1.1, Jolly = 1.1, Naive = 1.1,
  Brave = 0.9, Relaxed = 0.9, Quiet = 0.9, Sassy = 0.9,
}

local function natureMult(nature, statKey)
  if not nature then return 1.0 end
  if statKey == "spa" then return NATURE_SPA[nature] or 1.0 end
  if statKey == "spd" then return NATURE_SPD[nature] or 1.0 end
  if statKey == "atk" then return NATURE_ATK[nature] or 1.0 end
  if statKey == "def" then return NATURE_DEF[nature] or 1.0 end
  if statKey == "spe" then return NATURE_SPE[nature] or 1.0 end
  return 1.0
end

-- Standard Gen 3+ stat formula (bulbapedia "Statistic#Determination of
-- values"), applied only to spa/spd here -- hp/atk/def/spe keep coming
-- from the untouched Gen 1 Stats.calc.
local function calcModernStat(base, iv, ev, level, nature, statKey)
  local b = tonumber(base) or 50
  local v = math.floor((2 * b + iv + math.floor(ev / 4)) * level / 100) + 5
  return math.floor(v * natureMult(nature, statKey))
end

-- Resolves a "speciesDef" (ensure/recalcAll only ever read the .baseStats
-- field off whatever's passed as speciesDef, nothing else) preferring a
-- REAL base-stat source over this codebase's own placeholder data.
-- nationalDexExports is the national_dex mod's `mod.exports` table (a
-- caller does `local nd = mod:find("national_dex"); ... resolveBase(...,
-- nd and nd.exports)` -- ModernStats itself never calls mod:find, staying
-- a plain library with no mod-lifecycle dependency of its own) --
-- national_dex's statsBySpecies/statsByDex already carries real split
-- spAttack/spDefense per species (confirmed from its own README/
-- INSTRUCTION.md: reply.stats = {hp,attack,defense,speed,special,
-- spAttack,spDefense}), so when it's present and answers for this species,
-- its numbers win outright over fallbackDef's single Gen-1 "special".
-- fallbackDef is whatever local species table the caller already has
-- (game.data.pokemon[species], species_data.lua, a Gen 2 record) --
-- used untouched if national_dex is absent, disabled, or has never heard
-- of this species (returns nil, per its own documented contract).
function ModernStats.resolveBase(species, fallbackDef, nationalDexExports)
  if type(nationalDexExports) == "table" and (nationalDexExports.apiVersion or 0) >= 1
      and type(nationalDexExports.statsBySpecies) == "function" then
    local ok, rec = pcall(nationalDexExports.statsBySpecies, species)
    if ok and type(rec) == "table" and type(rec.stats) == "table" then
      local s = rec.stats
      return { baseStats = {
        hp = s.hp, attack = s.attack, defense = s.defense, speed = s.speed,
        spAttack = s.spAttack or s.special, spDefense = s.spDefense or s.special,
      } }
    end
  end
  return fallbackDef
end

-- Revision of the mon.stats.spa/spd DERIVATION itself (not the values).
-- Bumped whenever a change to how spa/spd are computed invalidates numbers
-- a mon already carries, so an existing save self-heals on next load
-- instead of keeping a stale figure forever. Round 187: the old .ensure
-- read the split base ONLY from speciesDef.baseStats, so a raw engine
-- record (national_dex's own layout: baseStats has the single collapsed
-- Gen-1 `special`, while the real Gen 6 split rides at the SPECIES level
-- as .spAttack/.spDefense) collapsed both special halves onto the same
-- base -- every mon that ever went through .ensure showed Sp. Atk equal to
-- Sp. Def. A mon stamped below this revision is recomputed once, from its
-- PRESERVED mon.ivs/mon.evs and the real split base.
local MODERN_STAT_REVISION = 2
ModernStats.MODERN_STAT_REVISION = MODERN_STAT_REVISION

-- Normalizes whatever a caller holds as a species' base stats into the
-- modern split shape (hp/attack/defense/speed/spAttack/spDefense +
-- `special`) that computeAll and .ensure's own formula need, regardless of
-- which of the three real record layouts it came from:
--   * ModernStats.resolveBase's own reply -- .baseStats already carries the
--     resolved split as spAttack/spDefense.
--   * a RAW engine record exactly as national_dex registers it -- .baseStats
--     has the single collapsed Gen-1 `special` and the real split lives at
--     the SPECIES level (.spAttack/.spDefense). This is what
--     game.data.pokemon[species] actually is in-game, and the layout the
--     old .ensure mishandled -- it only ever looked inside .baseStats, saw
--     one `special`, and used it for both halves.
--   * a native Gen 2 record -- .baseStats already carries specialAttack/
--     specialDefense (see national_dex's gen2shape.baseStats) and no
--     `special` at all.
-- A bare base-stat table (no .baseStats wrapper) is accepted too. The
-- collapsed `special` is the last-resort fallback for BOTH halves, so a
-- species with no real split data available (national_dex absent/disabled)
-- still computes something rather than erroring.
function ModernStats.resolveBaseStats(speciesDef)
  if type(speciesDef) ~= "table" then return nil end
  local wrapped = type(speciesDef.baseStats) == "table"
  local b = wrapped and speciesDef.baseStats or speciesDef
  local top = wrapped and speciesDef or nil
  local special = b.special or b.spAttack or b.specialAttack
    or b.spDefense or b.specialDefense
  local spa = b.spAttack or b.specialAttack
    or (top and (top.spAttack or top.specialAttack))
    or special
  local spd = b.spDefense or b.specialDefense
    or (top and (top.spDefense or top.specialDefense))
    or special
  return {
    hp = b.hp, attack = b.attack, defense = b.defense, speed = b.speed,
    special = special, spAttack = spa, spDefense = spd,
  }
end

-- Fills mon.ivs, mon.evs, mon.stats.spa, mon.stats.spd. A mon already
-- carrying a current-revision spa/spd is returned untouched, same
-- fill-only-if-missing contract as Stats.ensure; a mon whose stored
-- spa/spd predates MODERN_STAT_REVISION (any save written before round
-- 187) is recomputed once from its PRESERVED modern mon.ivs/mon.evs and
-- the real split base, so the collapsed-base values self-heal.
--
-- The split base comes from ModernStats.resolveBaseStats, NOT from
-- speciesDef.baseStats.special directly: resolution is split-aware and
-- reads the raw engine record's species-level .spAttack/.spDefense when
-- that's all the caller has (see that function's own header). A species
-- with no real split data still falls back to .special for both halves,
-- which matches the real games' own Gen 1 -> Gen 2 conversion.
--
-- The two special IVs still share one source DV (dvs.special -> both
-- mon.ivs.spa and mon.ivs.spd) because Gen 1 has exactly one Special DV --
-- that is the faithful conversion, and it is NOT why the two stats used to
-- read identical: with the base split resolved, the two formulas differ
-- whenever the species' real Sp. Atk and Sp. Def base stats differ. A mon
-- that already carries its own modern IVs (a wild one, a trainer spec)
-- keeps them untouched -- the fill loop only ever writes a nil key.
function ModernStats.ensure(speciesDef, mon)
  if type(mon) ~= "table" then return mon end

  -- Not just "is this a table" -- a mon can already carry a partially
  -- filled ivs/evs table (e.g. hp/atk/def/spe set by some earlier Gen 1
  -- path) with spa/spd still missing, which used to skip this whole
  -- block and leave mon.ivs.spa/mon.ivs.spd nil going into the
  -- calcModernStat calls below (real crash: "attempt to perform
  -- arithmetic on local 'iv' (a nil value)"). The fill loop's own body
  -- already guards each key with its own nil check, so it's safe to
  -- re-enter it whenever spa/spd specifically are still unset.
  local needIvs = type(mon.ivs) ~= "table" or mon.ivs.spa == nil or mon.ivs.spd == nil
  local needEvs = type(mon.evs) ~= "table" or mon.evs.spa == nil or mon.evs.spd == nil
  if needIvs or needEvs then
    local dvs = mon.dvs or {}
    local statExp = mon.statExp or {}
    mon.ivs = mon.ivs or {}
    mon.evs = mon.evs or {}
    for _, key in ipairs(ORDER) do
      if key == "spa" or key == "spd" then
        if mon.ivs[key] == nil then mon.ivs[key] = convertDV(dvs.special) end
      else
        local dvKey = DV_SOURCE[key]
        local dv = (key == "hp") and deriveHPDV(dvs) or dvs[dvKey]
        if mon.ivs[key] == nil then mon.ivs[key] = convertDV(dv) end
      end
    end
    if mon.evs.spa == nil or mon.evs.spd == nil then
      local totalEV = convertStatExp(statExp.special)
      local spaEV = math.floor(totalEV / 2)
      if mon.evs.spa == nil then mon.evs.spa = spaEV end
      if mon.evs.spd == nil then mon.evs.spd = totalEV - spaEV end
    end
    for _, key in ipairs({ "hp", "atk", "def", "spe" }) do
      if mon.evs[key] == nil then
        mon.evs[key] = convertStatExp(statExp[DV_SOURCE[key]])
      end
    end
  end

  if type(speciesDef) == "table" and type(speciesDef.baseStats) == "table" then
    mon.stats = mon.stats or {}
    -- Split-aware resolution -- reads the raw engine record's species-level
    -- .spAttack/.spDefense when .baseStats itself only carries the single
    -- collapsed Gen-1 `special` (see resolveBaseStats's own header). This
    -- is the round-187 fix: the old inline read of baseStats.special for
    -- both halves collapsed every mon's Sp. Atk onto its Sp. Def.
    local base = ModernStats.resolveBaseStats(speciesDef)
    local level = mon.level or 1
    -- Self-heal any value whose derivation predates MODERN_STAT_REVISION
    -- (collapsed-base era), and fill a genuinely missing one. mon.ivs /
    -- mon.evs are the PRESERVED modern values the fill block above just
    -- guaranteed, so the recomputed adv.stat stays linked to them plus the
    -- real national-dex split base. Never overwrite a battle-scoped
    -- raw-stat effect that is still in flight (Power/Guard Split capture a
    -- baseline on the mon -- see combat/modern_stat_manipulation.lua);
    -- outside battle that field is absent, and a missing value is still
    -- always filled.
    local stale = mon.g9ModernStatRevision ~= MODERN_STAT_REVISION
    local heal = stale and mon.__g9StatBaseline == nil
    if mon.stats.spa == nil or heal then
      mon.stats.spa = calcModernStat(base.spAttack, mon.ivs.spa or 0, mon.evs.spa or 0, level, mon.nature, "spa")
    end
    if mon.stats.spd == nil or heal then
      mon.stats.spd = calcModernStat(base.spDefense, mon.ivs.spd or 0, mon.evs.spd or 0, level, mon.nature, "spd")
    end
    if heal or mon.__g9StatBaseline == nil then
      mon.g9ModernStatRevision = MODERN_STAT_REVISION
    end
  end

  return mon
end

-- Standard Gen 3+ HP formula (bulbapedia "Statistic#Determination of
-- values") -- different additive term from the other five stats, no
-- nature multiplier. base 1/level<=0 guarded the same way calcModernStat
-- implicitly is (base is always a real species number in practice).
local function calcModernHP(base, iv, ev, level)
  return math.floor((2 * (base or 1) + iv + math.floor(ev / 4)) * (level or 1) / 100) + (level or 1) + 10
end

-- Pure computation, no mon mutation: given a base-stat table (any shape
-- .resolveBase can produce -- hp/attack/defense/speed plus spAttack/
-- specialAttack/special for the special split) and ivs/evs (ModernStats.
-- ORDER keys), returns {hp,attack,defense,speed,spa,spd} -- this module's
-- OWN key convention, not any one generation's native mon.stats field
-- names. .recalcAll (below) is the Gen 1 caller, writing spa/spd
-- alongside Stats.lua's original attack/defense/speed/hp names since
-- that's what Gen 1's own engine code reads; a Gen 2 caller writes these
-- same six numbers into mon.stats.specialAttack/specialDefense instead,
-- since Gen 2 already natively splits special -- see
-- gen2_modern_stats.lua. One formula, shared, regardless of which
-- generation's mon table ends up holding the result.
function ModernStats.computeAll(base, ivs, evs, level, nature)
  base = base or {}
  ivs = ivs or {}
  evs = evs or {}
  level = level or 1
  local baseSpa = base.spAttack or base.specialAttack or base.special
  local baseSpd = base.spDefense or base.specialDefense or base.special
  return {
    hp = calcModernHP(base.hp, ivs.hp or 0, evs.hp or 0, level),
    attack = calcModernStat(base.attack, ivs.atk or 0, evs.atk or 0, level, nature, "atk"),
    defense = calcModernStat(base.defense, ivs.def or 0, evs.def or 0, level, nature, "def"),
    speed = calcModernStat(base.speed, ivs.spe or 0, evs.spe or 0, level, nature, "spe"),
    spa = calcModernStat(baseSpa, ivs.spa or 0, evs.spa or 0, level, nature, "spa"),
    spd = calcModernStat(baseSpd, ivs.spd or 0, evs.spd or 0, level, nature, "spd"),
  }
end

-- Full recompute of all six stats from mon.ivs/mon.evs/mon.level/mon.nature,
-- UNCONDITIONALLY overwriting mon.stats (unlike .ensure's fill-only-if-
-- missing contract) -- for an explicit editor commit, not passive
-- derivation. attack/defense/speed/hp keep Stats.lua's original Gen-1 key
-- names since that's what the rest of the engine (Damage.lua, the battle
-- HUD, TrainerAI) reads; spa/spd use the modern keys ModernStats.ensure
-- already established. Once a mon has been through this path its
-- hp/attack/defense/speed no longer come from Stats.calc's dvs/statExp
-- formula -- an explicit, editor-triggered opt-in per mon, not a global
-- engine change (a mon nobody ever opens this editor for keeps its
-- original Gen-1-formula stats exactly as before).
--
-- mon.ivs.hp is a real, independently-set field here (0-31, whatever the
-- player last chose) -- NOT re-derived from the other four stats' DV
-- parity bits the way Gen 1's own HP DV was. That derivation only ever
-- runs once, in .ensure, to seed a first value for a mon that has never
-- had modern fields before; every recalcAll after that trusts mon.ivs.hp
-- as edited.
function ModernStats.recalcAll(speciesDef, mon)
  if type(mon) ~= "table" then return mon end
  if type(speciesDef) ~= "table" or type(speciesDef.baseStats) ~= "table" then return mon end
  mon.ivs = mon.ivs or {}
  mon.evs = mon.evs or {}
  mon.stats = mon.stats or {}
  -- Split-aware, same resolution .ensure uses -- robust whether the caller
  -- hands a ModernStats.resolveBase reply (split already in .baseStats) or
  -- a raw engine record (split at the species level). See
  -- resolveBaseStats's own header.
  local base = ModernStats.resolveBaseStats(speciesDef)
  local computed = ModernStats.computeAll(base, mon.ivs, mon.evs, mon.level, mon.nature)
  mon.stats.hp = computed.hp
  mon.stats.attack = computed.attack
  mon.stats.defense = computed.defense
  mon.stats.speed = computed.speed
  mon.stats.spa = computed.spa
  mon.stats.spd = computed.spd
  -- Authoritative write: stamp the current derivation revision so .ensure
  -- (which may see this mon later, e.g. from a screen or save scrub) never
  -- re-derives over genuinely current numbers.
  mon.g9ModernStatRevision = MODERN_STAT_REVISION
  -- And stamp the mon as MODERN-OWNED: this function is the one place that
  -- writes the whole stat block from the modern model (hp/atk/def/spe under
  -- the native names, plus spa/spd), so any mon that has been through it must
  -- NOT be silently re-typed by a native recompute (Gen 2's Mon.refreshStats
  -- rebuilds hp/atk/def/spe from dvs/statExp on every party-menu open). The
  -- Gen 2 refreshStats wrapper in stats/train_screen.lua re-applies the modern
  -- block for a modern-owned mon, which is what keeps a center-heal's modern
  -- max HP from being replaced by a DV-derived one that differs by a point --
  -- the reported "healed mon sits at max - 1" bug. Deliberately set HERE and
  -- not in .ensure(): save_scrub.lua runs .ensure on every mon in a loaded
  -- save (fill-only), which must not be treated as modern ownership.
  mon.g9ModernOwned = true
  return mon
end

return ModernStats
