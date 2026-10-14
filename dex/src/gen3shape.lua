-- Game3 shape adapter. National Dex carries Gen 1/2-friendly source data;
-- Game3's registry expects split Special stats and numbered species slots.
-- ROM species IDs are NOT National Dex IDs. Preserve native Gen 1-3 slots,
-- including FRLG's unused/Unown slots, and allocate additions above them.
local M = { ROM_DEX_MAX = 386 }

function M.slot(dex)
  -- Forms retain their shipped synthetic IDs (30001 onward) plus the same
  -- offset. This stays stable when more forms are added and never uses a
  -- native or base National species slot.
  if dex > 386 then return dex + 64 end
  local P = require('src.core.game3.pokemon')
  return P.speciesFromNational(dex)
end

function M.generation()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and GameVersion.generation and GameVersion.generation() == 3 then
    return 3
  end
  return nil
end

function M.romOwned(record)
  return type(record) == "table" and type(record.dex) == "number"
    and not record.form and record.dex <= M.ROM_DEX_MAX
end

function M.types(types)
  local out = {}
  for i, id in ipairs(types or { "NORMAL" }) do
    out[i] = id == "PSYCHIC_TYPE" and "PSYCHIC" or id == "CURSE_TYPE" and "MYSTERY" or id
  end
  return out
end

function M.romPatch(record)
  return { types = M.types(record.types) }
end

function M.record(source, machines)
  local entry = source.dexEntry or {}
  local h = tonumber(entry.heightM) or 0
  local w = tonumber(entry.weightKg) or 0
  local stats = source.baseStats or {}
  return {
    id = source.id, name = source.name, dex = source.dex, index = M.slot(source.dex),
    form = source.form, baseSpecies = source.baseSpecies,
    types = M.types(source.types),
    baseStats = { hp = stats.hp or 1, attack = stats.attack or 1,
      defense = stats.defense or 1, speed = stats.speed or 1,
      specialAttack = source.spAttack or stats.special or 1,
      specialDefense = source.spDefense or stats.special or 1 },
    catchRate = source.catchRate or 0, baseExp = source.baseExp or 0,
    growthRate = source.growthRate or "MEDIUM_FAST",
    learnset = source.learnset or {}, tmhm = machines or source.tmhm or {}, evolutions = {},
    dexEntry = { kind = entry.kind or "", height = math.floor(h * 10 + .5),
      weight = math.floor(w * 10 + .5) },
    -- .rgba references leave the base art path to the animated-sprite mod.
    -- A placeholder PNG override would mask that mod when Compat wraps last.
    spriteFront = 'data/generated/gba/pokemon/front/' .. tostring(M.slot(source.dex)) .. '.rgba',
    spriteBack = 'data/generated/gba/pokemon/back/' .. tostring(M.slot(source.dex)) .. '.rgba',
  }
end

function M.install(mod, national)
  local P = require('src.core.game3.pokemon')
  local Schemas = require('src.mods.Schemas')
  local Dex = require('src.core.game3.dex')
  local PokedexData = require('src.core.game3.pokedex_data')
  if not P._moveNames and P.moveName then P.moveName(1) end
  local Moves=assert(load(assert(mod:read('src/gen3moves.lua'))))()
  local moveRules=Moves.load(function(path)return mod:read(path)end,mod.exports)

  -- Gen 3's internal species slots diverge from National Dex numbers after
  -- Celebi. A caught Bidoof is slot 463, while National #463 is Lickilicky.
  -- Opaque party mons always carry an internal slot, so never reinterpret a
  -- slot that is registered in the active Game3 pack.
  if not P.__completeDexInternalIds then
    P.__completeDexInternalIds = true
    local originalSpeciesOf = P.speciesOf
    P.speciesOf = function(mon)
      local raw = mon and (mon.species or mon.speciesId or mon.id)
      local n = tonumber(raw)
      if n and n >= 1 and P.keyName(n) then return n end
      return originalSpeciesOf(mon)
    end
  end

  -- The National list is expressed as National numbers, but the Dex bitsets,
  -- party, battle and sprite registries are all keyed by internal slots.
  Dex.NATIONAL_MAX = 1025
  P.nationalPokedexNumber = P.national
  if not PokedexData.__completeDexNationalList then
    PokedexData.__completeDexNationalList = true
    local originalOrder = PokedexData.getOrderList
    PokedexData.getOrderList = function(orderKey, dex)
      if orderKey == 'numerical_national' then
        local list = {}
        for nat = 1, 1025 do
          local slot = P.speciesFromNational(nat)
          if slot then list[#list + 1] = slot end
        end
        return list
      end
      return originalOrder(orderKey, dex)
    end
    PokedexData.isNationalUnlocked = function() return true end

    local originalSeen, originalCaught = Dex.countSeen, Dex.countCaught
    Dex.countSeen = function(dex, mode)
      if tostring(mode or 'kanto'):lower() ~= 'national' then return originalSeen(dex, mode) end
      local count = 0
      for nat = 1, 1025 do
        local slot = P.speciesFromNational(nat)
        if slot and Dex.isSeen(dex, slot) then count = count + 1 end
      end
      return count
    end
    Dex.countCaught = function(dex, mode)
      if tostring(mode or 'kanto'):lower() ~= 'national' then return originalCaught(dex, mode) end
      local count = 0
      for nat = 1, 1025 do
        local slot = P.speciesFromNational(nat)
        if slot and Dex.isCaught(dex, slot) then count = count + 1 end
      end
      return count
    end
    Dex.countOwned = Dex.countCaught
  end
  local records, ops = {}, {}
  for id, source in pairs(national.register or {}) do
    if source.form or (source.dex > 386 and source.dex <= 1025) then
      -- Persist on the source too: nationaldex's later registration pass
      -- reshapes this same record and must not erase its machine list.
      local base = source.form and P.speciesFromName(source.baseSpecies)
      local baseSource = source.form and national.register[source.baseSpecies]
      local nat = (baseSource and not baseSource.form and baseSource.dex)
        or (base and P.national(base)) or source.dex
      source.tmhm=Moves.machineIds(moveRules,nat,P._moveNames)
      local row = M.record(source)
      row.name = source.name:upper()
      records[id], ops[id] = row, true
    end
  end
  local registry = {ops=ops, get=function(_,id) return records[id] end}
  local function apply()
    if not P._names then return end -- Wait for the actual ROM pack.
    -- Schemas.lua (0.3.18) caches the species-name index.  When gen3Write
    -- allocates a previously unseen slot, it accidentally caches the ID
    -- string in place of the numeric slot.  The loader's later merge then
    -- feeds that string to vanillaSprite's %d path and aborts the whole mod
    -- load.  Give it a fresh, complete names table before its first write.
    local names = {}
    for slot, name in pairs(P._names) do names[slot] = name end
    for _, row in pairs(records) do names[row.index] = row.name end
    P._names = names
    Schemas.REGISTRIES.pokemon.gen3Write(P, registry)
    P._byName = P._byName or {}
    P._national = P._national or {}
    P._national.toSpecies = P._national.toSpecies or {}
    P._national.toNational = P._national.toNational or {}
    local count = 0
    for id,row in pairs(records) do
      local slot = row.index
      P._names[slot] = row.name
      -- Match Pokemon.speciesFromName's punctuation-insensitive key format.
      P._byName[id:upper():gsub('[^A-Z0-9]','')] = slot
      P._byName[row.name:upper():gsub('[^A-Z0-9]','')] = slot
      local source = national.register[id]
      if source.form then
        local baseSource = national.register[source.baseSpecies]
        local base = P.speciesFromName(source.baseSpecies)
        local nat = (baseSource and not baseSource.form and baseSource.dex)
          or (base and P.national(base))
        P._national.toNational[slot] = nat
        -- Metadata used by spawn menus; base National-number lookup stays intact.
        P.__completeDexForms = P.__completeDexForms or {}
        P.__completeDexForms[slot] = {id=id,baseSpecies=source.baseSpecies,form=source.form}
      else
        P._national.toSpecies[row.dex] = slot
        P._national.toNational[slot] = row.dex
      end
      count = count + 1
    end
    -- All base names now resolve, including forms of newly added species.
    for slot, form in pairs(P.__completeDexForms or {}) do
      local base = P.speciesFromName(form.baseSpecies)
      local meta = base and P.speciesMeta(base)
      local own = P.speciesMeta(slot)
      if meta and own then
        for _,key in ipairs({'genderRatio','eggCycles','friendship','eggGroup1','eggGroup2'}) do
          if own[key]==nil then own[key]=meta[key] end
        end
      end
      if base and P._abilities then P._abilities[slot]=P._abilities[base] end
    end
    mod.log:info('Game3 extended species restored: ' .. count)
  end
  P.onReload(apply, 'national_dex_firered')
  apply()
  local Animations = assert(load(assert(mod:read('src/gen3animations.lua')), '@gen3animations.lua'))()
  Animations.install(P)
  local Evolutions = assert(load(assert(mod:read('src/gen3evolutions.lua')), '@gen3evolutions.lua'))()
  local ItemsData = require('src.core.game3.items_data')
  Evolutions.install(mod, P, M.slot, function(key) return ItemsData.toNumericId(key) end)
  Moves.install(mod,P,M.slot,moveRules)
end

return M
