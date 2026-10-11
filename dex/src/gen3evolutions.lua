-- Install the shipped evolution graph in FR/LG and Emerald's species registry.
-- Species from National #387 onward have no ROM evolution rows of their own.
local M = {}

-- Branches where a held trade item should take priority over a normal
-- level-up evolution.  Keeping this data-driven lets later trade-item
-- branches use the same native evolution.check / pokemon.evolved path.
local LEVEL_HELD_PRIORITY = {
  {
    sourceDex = 79,          -- Slowpoke
    targetDex = 199,         -- Slowking
    normalTargetDex = 80,    -- Slowbro
    minLevel = 37,
    itemKeys = {"KINGS_ROCK", "KING'S_ROCK", "KING'S ROCK", "KINGSROCK"},
    consume = true,
  },
  {
    sourceDex = 61,          -- Poliwhirl
    targetDex = 186,         -- Politoed
    minLevel = 1,
    itemKeys = {"KINGS_ROCK", "KING'S_ROCK", "KING'S ROCK", "KINGSROCK"},
    consume = true,
  },
  {
    sourceDex = 95,          -- Onix
    targetDex = 208,         -- Steelix
    minLevel = 1,
    itemKeys = {"METAL_COAT", "METAL COAT", "METALCOAT"},
    consume = true,
  },
  {
    sourceDex = 123,         -- Scyther
    targetDex = 212,         -- Scizor
    minLevel = 1,
    itemKeys = {"METAL_COAT", "METAL COAT", "METALCOAT"},
    consume = true,
  },
  {
    sourceDex = 117,         -- Seadra
    targetDex = 230,         -- Kingdra
    minLevel = 1,
    itemKeys = {"DRAGON_SCALE", "DRAGON SCALE", "DRAGONSCALE"},
    consume = true,
  },
  {
    sourceDex = 137,         -- Porygon
    targetDex = 233,         -- Porygon2
    minLevel = 1,
    itemKeys = {"UP_GRADE", "UP-GRADE", "UP GRADE", "UPGRADE"},
    consume = true,
  },
  {
    sourceDex = 366,         -- Clamperl
    targetDex = 367,         -- Huntail
    minLevel = 1,
    itemKeys = {"DEEP_SEA_TOOTH", "DEEP SEA TOOTH", "DEEPSEATOOTH"},
    consume = true,
  },
  {
    sourceDex = 366,         -- Clamperl
    targetDex = 368,         -- Gorebyss
    minLevel = 1,
    itemKeys = {"DEEP_SEA_SCALE", "DEEP SEA SCALE", "DEEPSEASCALE"},
    consume = true,
  },
}

local function decode(read, path)
  local source = assert(read(path), 'Missing evolution data: ' .. path)
  return assert(load(source, '@' .. path))()
end

local function resolveItem(itemId, keys)
  if type(itemId) ~= 'function' then return nil end
  for _, key in ipairs(keys or {}) do
    local ok, value = pcall(itemId, key)
    value = ok and tonumber(value) or nil
    if value and value > 0 then return value end
  end
  return nil
end

local function heldItemId(mon, itemId)
  local raw = mon and mon.item
  if raw == nil or tonumber(raw) == 0 then raw = mon and mon.heldItem end
  local numeric = tonumber(raw)
  if numeric then return numeric end
  if raw ~= nil and type(itemId) == 'function' then
    local ok, value = pcall(itemId, raw)
    if ok then return tonumber(value) end
  end
  return nil
end

function M.build(read, slot, itemId, moveAvailable)
  local index = decode(read, 'data/evolutions/generated/index.lua')
  local shards, rows, conditions, counts = {}, {}, {},
    {level=0, trade=0, item=0, fallback=0, held=0}
  local function record(id)
    local shard = index[id]
    if not shard then return end
    if not shards[shard] then
      shards[shard] = decode(read, ('data/evolutions/generated/%03d.lua'):format(shard))
    end
    return shards[shard][id]
  end
  for id in pairs(index) do
    local source = record(id)
    if source and not source.form and type(source.dex) == 'number' and source.dex <= 1025 then
      local from = slot(source.dex)
      if from then
        local fallback = {}
        for _, edge in ipairs(source.evolvesInto or {}) do
          local destination = record(edge.id)
          if destination and not destination.form and destination.dex == edge.dex then
            local target = slot(edge.dex)
            local chosen
            for _, method in ipairs(edge.methods or {}) do
              if method.isDefault then chosen = method; break end
            end
            chosen = chosen or (edge.methods or {})[1]
            if target and chosen then
              local method, param, guard
              if chosen.trigger == 'trade' then
                method, param = 4, 36
                counts.trade = counts.trade + 1
              elseif chosen.trigger == 'level-up' then
                param = tonumber(chosen.level)
                if param then
                  method = 4
                  if chosen.relativePhysicalStats then
                    method = ({[1]=8, [0]=9, [-1]=10})[chosen.relativePhysicalStats] or 4
                  elseif id == 'WURMPLE' then
                    method = edge.id == 'SILCOON' and 11 or 12
                  elseif id == 'NINCADA' and edge.id == 'NINJASK' then
                    method = 13
                  end
                elseif chosen.minHappiness or chosen.knownMove or chosen.minBeauty
                    or chosen.partySpecies or chosen.partyType then
                  method, param, guard = 4, 1, chosen
                end
                -- A conditional level must never evolve to the wrong branch.
                if method and (chosen.timeOfDay or chosen.gender or chosen.knownMove
                    or chosen.partySpecies or chosen.partyType or chosen.minHappiness
                    or chosen.minBeauty or chosen.heldItem or chosen.knownMoveType
                    or chosen.location or chosen.minSteps or chosen.usedMove) then
                  if chosen.heldItem or chosen.knownMoveType or chosen.location
                      or chosen.minSteps or chosen.usedMove
                      or (chosen.knownMove and moveAvailable and not moveAvailable(chosen.knownMove)) then
                    method = nil -- This action is handled by the level 36 fallback below.
                  else
                    guard = chosen
                  end
                end
                if method then counts.level = counts.level + 1 end
              elseif chosen.trigger == 'shed' then
                method, param = 14, 20
                counts.level = counts.level + 1
              elseif chosen.trigger == 'use-item' and chosen.item then
                local key = chosen.item:upper():gsub('[^A-Z0-9]+', '_')
                param = itemId and itemId(key)
                if param then method = 7; counts.item = counts.item + 1 end
              end
              if method then
                rows[from] = rows[from] or {}
                rows[from][#rows[from]+1] = {method=method,param=param,target=target}
                -- This pack represents Meowstic's two sexes with one base
                -- slot; both male and female Espurr must reach that slot.
                if id == 'ESPURR' and guard then
                  local copy = {}; for k,v in pairs(guard) do if k ~= 'gender' then copy[k]=v end end
                  guard = copy
                end
                if guard then
                  conditions[from] = conditions[from] or {}
                  conditions[from][target] = guard
                end
              else
                fallback[#fallback+1] = {method=4,param=36,target=target}
                if chosen.gender then
                  conditions[from] = conditions[from] or {}
                  conditions[from][target] = {gender=chosen.gender}
                end
              end
            end
          end
        end
        -- Sun/Moon version-exclusive branches share a level but cannot be
        -- selected by a Gen 3 cartridge version. Keep both reachable at 53,
        -- using the same attack/defense convention as other adapted branches.
        if id == 'COSMOEM' and rows[from] and #rows[from] == 2 then
          local solgaleo, lunala
          for _, entry in ipairs(rows[from]) do
            if entry.target == slot(791) then solgaleo = entry else lunala = entry end
          end
          if solgaleo and lunala then
            solgaleo.method = 8
            rows[from] = {lunala, solgaleo}
          end
        end
        if #fallback > 0 then
          rows[from] = rows[from] or {}
          -- Each level-up has one result. When two or three special evolutions
          -- share a parent, use the ROM's attack/defense split so every
          -- destination remains reachable at level 36.
          local split = #fallback == 2 and {8,4}
            or #fallback == 3 and {8,9,10}
          for i, entry in ipairs(fallback) do
            if split then entry.method = split[i] end
            if i <= 3 or #fallback == 1 then
              local rule = conditions[from] and conditions[from][entry.target]
              if rule and rule.gender then
                -- Gender-specific adapted stone branches (Gallade/Froslass)
                -- must win over the ordinary earlier/later level evolution.
                rows[from][#rows[from]+1] = entry
              else
                table.insert(rows[from], 1, entry)
              end
              counts.fallback = counts.fallback + 1
            end
          end
        end
      end
    end
  end

  -- Replace only the explicitly listed trade-item branch with a normal
  -- level row guarded by its held item. It is appended after the ordinary
  -- branch so the engine's last-matching-row behavior gives it priority.
  for _, spec in ipairs(LEVEL_HELD_PRIORITY) do
    local from = slot(spec.sourceDex)
    local target = slot(spec.targetDex)
    local normalTarget = spec.normalTargetDex and slot(spec.normalTargetDex) or nil
    local requiredItem = resolveItem(itemId, spec.itemKeys)
    if from and target and requiredItem then
      rows[from] = rows[from] or {}
      for i = #rows[from], 1, -1 do
        if rows[from][i].target == target then
          table.remove(rows[from], i)
          counts.trade = math.max(0, counts.trade - 1)
        end
      end
      rows[from][#rows[from]+1] = {
        method=4, param=spec.minLevel, target=target,
      }
      conditions[from] = conditions[from] or {}
      conditions[from][target] = {
        minLevel=spec.minLevel,
        heldItemId=requiredItem,
        consumeHeldItem=spec.consume == true,
      }
      if normalTarget then
        local normalRule = conditions[from][normalTarget] or {}
        normalRule.unlessHeldItemId = requiredItem
        conditions[from][normalTarget] = normalRule
      end
      counts.held = counts.held + 1
    end
  end
  return rows, conditions, counts
end

function M.install(mod, pokemon, slot, itemId)
  local conditions, installedRows = {}, {}
  local extraIndex, extraShards
  local function ensureGender(from)
    local meta = pokemon._speciesMeta and pokemon._speciesMeta[from]
    if meta and meta.genderRatio ~= nil then return end
    local id = pokemon.keyName(from)
    if not id then return end
    if not extraIndex then
      extraIndex = decode(function(path) return mod:read(path) end,
        'data/species/generated/extras/index.lua')
      extraShards = {}
    end
    local number = extraIndex[id]
    if not number then return end
    if not extraShards[number] then
      extraShards[number] = decode(function(path) return mod:read(path) end,
        ('data/species/generated/extras/%03d.lua'):format(number))
    end
    local extra = extraShards[number][id]
    local rate = extra and tonumber(extra.genderRate)
    if rate == nil then return end
    pokemon._speciesMeta = pokemon._speciesMeta or {}
    meta = meta or {}; pokemon._speciesMeta[from] = meta
    meta.genderRatio = rate < 0 and 255 or rate == 8 and 254
      or rate == 0 and 0 or math.floor(rate * 255 / 8)
  end
  local function moveAvailable(name)
    local wanted = name:upper():gsub('[^A-Z0-9]', '')
    for _, candidate in pairs(pokemon._moveNames or {}) do
      if tostring(candidate):upper():gsub('[^A-Z0-9]', '') == wanted then return true end
    end
    return false
  end
  local function apply()
    if not pokemon._names or not pokemon._evolutions then return end
    local generated, guards, counts = M.build(function(path) return mod:read(path) end, slot, itemId, moveAvailable)
    conditions = guards
    for from, rules in pairs(guards) do
      for _, rule in pairs(rules) do
        if rule.gender then ensureGender(from); break end
      end
    end
    for from, additions in pairs(generated) do
      local original = pokemon._evolutions[from] or {}
      local merged, targets = {}, {}
      for _, entry in ipairs(additions) do
        merged[#merged+1] = entry
        targets[entry.target] = true
      end
      for _, entry in ipairs(original) do
        if not targets[entry.target] then
          -- FRLG's own traded species obey the same level 36 rule.
          if entry.method == 5 or entry.method == 6 then
            merged[#merged+1] = {method=4,param=36,target=entry.target}
          else
            merged[#merged+1] = entry
          end
        end
      end
      pokemon._evolutions[from] = merged
      installedRows[from] = merged
    end
    -- Some ROM trade rows have no default edge in the generated graph.
    for from, original in pairs(pokemon._evolutions) do
      if not generated[from] then
        for _, entry in ipairs(original) do
          if entry.method == 5 or entry.method == 6 then
            entry.method, entry.param = 4, 36
          end
        end
      end
    end
    mod.log:info(('Game3 evolutions: %d level, %d trade at 36, %d item; %d special evolutions at 36; %d held-item level branches')
      :format(counts.level, counts.trade, counts.item, counts.fallback, counts.held))
  end
  pokemon.onReload(apply, '1025dex_firered_evolutions')
  apply()
  -- Registry merges happen after mod entry points, and Gen3Compat adds its
  -- ROM-reload writer after our onReload callback. Both can replace rows with
  -- the empty `evolutions` lists used to register extended species. Restore
  -- after the initial merge and whenever the engine reads a replaced row.
  -- Comparing row identity also handles an in-place write to the same table.
  local originalEvolutions = pokemon.evolutions
  pokemon.evolutions = function(species)
    local rows = originalEvolutions(species) -- Also loads a fresh ROM pack.
    local from = type(species) == 'table' and pokemon.speciesOf(species) or species
    if type(from) == 'string' then from = pokemon.speciesFromName(from) or tonumber(from) end
    from = tonumber(from)
    if from and installedRows[from] and rows ~= installedRows[from] then
      apply()
      rows = originalEvolutions(species)
    end
    return rows
  end
  if mod.events and mod.events.on then mod.events:on('mods.loaded', apply) end
  if mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap('evolution.check', function(nextCheck, game, mon, view, ctx)
      local from = pokemon.speciesOf and pokemon.speciesOf(mon)
        or tonumber(mon and (mon.species or mon.speciesId))
      local rules = conditions[from]
      if rules and ctx and ctx.kind == 'levelup' then
        -- The engine evaluates one evolution row at a time; prohibit a
        -- conditional row unless its own requirement is satisfied.
        local target = tonumber(view and view.speciesId)
          or (view.evolution and tonumber(view.evolution.target))
        local rule = target and rules[target]
        if rule then
          local held = heldItemId(mon, itemId)
          if rule.minLevel and (tonumber(mon.level) or 1) < rule.minLevel then return false end
          if rule.heldItemId and held ~= rule.heldItemId then return false end
          if rule.unlessHeldItemId and held == rule.unlessHeldItemId then return false end
          local friendship = pokemon.friendshipOf and pokemon.friendshipOf(mon)
          if rule.minHappiness and (not friendship or friendship < rule.minHappiness) then return false end
          local beauty = tonumber(mon.contest and mon.contest.beauty) or tonumber(mon.beauty) or 0
          if rule.minBeauty and beauty < rule.minBeauty then return false end
          if rule.gender then
            -- PokeAPI encodes female as 1 and male as 2; the engine returns F/M.
            local gender = ({[1]='F', [2]='M'})[tonumber(rule.gender)]
              or tostring(rule.gender):upper():sub(1,1)
            if pokemon.gender(from, mon.personality) ~= gender then return false end
          end
          if rule.knownMove then
            local wanted = rule.knownMove:upper():gsub('[^A-Z0-9]', '')
            local found = false
            for i=1,4 do
              local move = pokemon.moveIdAt(mon,i)
              local name = move and pokemon.moveName(move)
              if name and name:upper():gsub('[^A-Z0-9]', '') == wanted then found=true; break end
            end
            if not found then return false end
          end
          if rule.timeOfDay then
            local hour = game and game.world and game.world.hour and game.world:hour()
            if not hour then hour = tonumber(os.date('%H')) end
            if rule.timeOfDay == 'day' and (hour < 6 or hour >= 18) then return false end
            if rule.timeOfDay == 'night' and (hour >= 6 and hour < 18) then return false end
          end
          if rule.partySpecies or rule.partyType then
            local party = ctx.session and ctx.session.party or {}
            local wantedSpecies = rule.partySpecies and rule.partySpecies:upper():gsub('[^A-Z0-9]', '')
            local wantedType = rule.partyType and rule.partyType:upper()
            local found = false
            for _, member in ipairs(party) do
              local species = pokemon.speciesOf(member)
              local name = species and pokemon.keyName(species)
              if wantedSpecies and name and name:upper():gsub('[^A-Z0-9]', '') == wantedSpecies then found=true end
              if wantedType and species then
                local types = pokemon.types(species)
                -- Game3 returns a list of two numeric type IDs (Dark = 17).
                for _, value in ipairs(types) do
                  if tostring(value):upper() == wantedType or (wantedType == 'DARK' and value == 17) then found=true end
                end
              end
            end
            if not found then return false end
          end
        end
      end
      return nextCheck(game,mon,view,ctx)
    end)
  end
  if mod.events and mod.events.on then
    mod.events:on('pokemon.evolved', function(event)
      if type(event) ~= 'table' or type(event.mon) ~= 'table' then return end
      local from = tonumber(event.fromSpeciesId)
      local target = tonumber(event.toSpeciesId)
      local rule = from and target and conditions[from] and conditions[from][target]
      if not (rule and rule.consumeHeldItem and rule.heldItemId) then return end
      if heldItemId(event.mon, itemId) ~= rule.heldItemId then return end
      event.mon.item = 0
      event.mon.heldItem = 0
    end)
  end
end
return M
