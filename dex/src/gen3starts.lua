-- Rebuild modern level-up learnsets using only moves FireRed implements.
-- A post-Gen-3 move is replaced by the closest native move instead of simply
-- disappearing, so extended species keep a complete, useful progression.
local M = {}
local function key(s) return tostring(s):upper():gsub('[^A-Z0-9]', '') end

-- Cases where mechanical metadata alone cannot express the obvious Gen 3
-- counterpart (Fairy did not exist yet, and several newer moves combine two
-- effects that no older move combines).
local OVERRIDE = {
  PSYCHIC_M={'PSYCHIC','EXTRASENSORY','PSYBEAM','CONFUSION'},
  AIRSLASH={'AERIAL_ACE','WING_ATTACK','FLY'},
  AQUAJET={'WATER_GUN','BUBBLE','BUBBLEBEAM'},
  AQUARING='RECOVER', ASSURANCE={'FEINT_ATTACK','BITE'}, AURORAVEIL='REFLECT',
  BABYDOLLEYES='GROWL', BRAVEBIRD={'SKY_ATTACK','FLY','AERIAL_ACE'},
  BUGBITE={'SILVER_WIND','FURY_CUTTER','LEECH_LIFE'},
  AROMATICMIST='LIGHT_SCREEN', AFTERYOU='HELPING_HAND',
  CLEARSMOG='SMOG', COIL='BULK_UP', COPYCAT='MIMIC',
  DAZZLINGGLEAM={'PSYCHIC','EXTRASENSORY','PSYBEAM'}, DEFOG='HAZE',
  DISARMINGVOICE={'SWIFT','HYPER_VOICE','UPROAR'},
  DOUBLEHIT='DOUBLE_KICK', DRAGONPULSE='DRAGONBREATH',
  DRAININGKISS='MEGA_DRAIN', ECHOEDVOICE='UPROAR',
  ELECTRICTERRAIN={'CHARGE','LIGHT_SCREEN','THUNDER_WAVE'}, ENERGYBALL='GIGA_DRAIN',
  ENTRAINMENT='SKILL_SWAP', FAIRYWIND='GUST', FINALGAMBIT='SELFDESTRUCT',
  FLASHCANNON='STEEL_WING', FLING='THIEF',
  FLAREBLITZ='OVERHEAT', GASTROACID='HAZE', GIGAIMPACT='HYPER_BEAM',
  GRASSYTERRAIN='INGRAIN', HEALINGWISH='RECOVER', HEALPULSE='SOFTBOILED',
  HEAVYSLAM='STEEL_WING', HEX='SHADOW_BALL', HONECLAWS='BULKUP',
  HAMMERARM={'SUPERPOWER','BRICK_BREAK','SKY_UPPERCUT'},
  HURRICANE={'SKY_ATTACK','FLY','WING_ATTACK'},
  INCINERATE={'FLAME_WHEEL','EMBER','FIRE_SPIN'},
  IRONHEAD={'STEEL_WING','METEOR_MASH','METAL_CLAW'},
  KOWTOWCLEAVE='CUT',
  LASTRESORT='HYPER_BEAM', LIFEDEW='RECOVER', LIQUIDATION='SURF',
  LUNGE='SIGNAL_BEAM', MAGNETRISE='DOUBLE_TEAM', MISTYTERRAIN='SAFEGUARD',
  MOONBLAST={'PSYCHIC','EXTRASENSORY','PSYBEAM'}, NASTYPLOT='CALM_MIND',
  NIGHTSLASH={'SLASH','CRUNCH','FEINT_ATTACK'}, NOBLEROAR='GROWL',
  NUZZLE='THUNDER_WAVE', PAYBACK={'FEINT_ATTACK','BITE'},
  PLAYROUGH={'BODY_SLAM','STRENGTH','RETURN'}, POWERGEM='ROCK_SLIDE',
  PSYSHOCK='PSYCHIC', PSYCHOCUT='PSYCHIC', QUICKGUARD='DETECT',
  RETALIATE='REVENGE', ROOST='RECOVER', SACREDSWORD='BRICK_BREAK',
  ROUND={'HYPER_VOICE','UPROAR','SWIFT'},
  SEEDBOMB='LEAF_BLADE', SHELLSMASH='GROWTH', SNARL='CRUNCH',
  SOAK='RAIN_DANCE', STEALTHROCK='SPIKES', STICKYWEB='STRING_SHOT',
  STONEEDGE={'ROCK_SLIDE','ANCIENT_POWER','ROCK_THROW'},
  STRUGGLEBUG={'SIGNAL_BEAM','SILVER_WIND','LEECH_LIFE'},
  SUCKERPUNCH={'FEINT_ATTACK','BITE','KNOCK_OFF'}, SWITCHEROO='TRICK',
  TAILWIND='AGILITY',
  TOXICSPIKES='SPIKES', UTURN='FURY_CUTTER', WIDEGUARD='PROTECT',
  WILDCHARGE='THUNDERBOLT', WORKUP='GROWTH', WORRYSEED='SKILL_SWAP',
  BUGBUZZ={'SIGNAL_BEAM','SILVER_WIND','LEECH_LIFE'},
  GRAVITY='MUD_SPORT', GUARDSPLIT='PSYCH_UP', PLAYNICE='GROWL',
  ZENHEADBUTT='PSYCHIC',
}

local AUTO_EXCLUDE = {
  AEROBLAST=true, BLASTBURN=true, DOOMDESIRE=true, FRENZYPLANT=true,
  HYDROCANNON=true, LUSTERPURGE=true, MISTBALL=true, PSYCHOBOOST=true,
  SACREDFIRE=true, VOLTTACKLE=true,
}

local function loadTable(read, path)
  return assert(load(assert(read(path)), '@' .. path))()
end

local function moveData(read)
  local index = loadTable(read, 'data/moves/generated/api/index.lua')
  local shards = {}
  local function get(id)
    local number = index[id]
    if not number then return nil end
    if not shards[number] then
      shards[number] = loadTable(read,
        string.format('data/moves/generated/api/%03d.lua', number))
    end
    return shards[number][id]
  end
  return index, get
end

local function statSignature(move)
  local result = {}
  for _, row in ipairs(move and move.statChanges or {}) do
    result[#result + 1] = tostring(row.stat) .. ':' .. tostring(row.change)
  end
  table.sort(result)
  return table.concat(result, ',')
end

local function statDistance(wanted, candidate)
  local left, right, score = {}, {}, 0
  for _, row in ipairs(wanted and wanted.statChanges or {}) do
    left[row.stat] = row.change
  end
  for _, row in ipairs(candidate and candidate.statChanges or {}) do
    right[row.stat] = row.change
  end
  for stat, change in pairs(left) do
    local other = right[stat]
    if other == nil then
      score = score + 35
    elseif change * other < 0 then
      score = score + 80
    else
      score = score + math.abs(change - other) * 14
    end
  end
  for stat in pairs(right) do if left[stat] == nil then score = score + 15 end end
  return score
end

local function distance(wanted, candidate)
  if not wanted or not candidate then return math.huge end
  local ws, cs = wanted.damageClass == 'status', candidate.damageClass == 'status'
  if ws ~= cs then return math.huge end
  local score = 0
  if wanted.type ~= candidate.type then score = score + (ws and 30 or 180) end
  if wanted.damageClass ~= candidate.damageClass then score = score + 35 end
  if wanted.category ~= candidate.category then score = score + 28 end
  if wanted.target ~= candidate.target then score = score + (ws and 55 or 8) end
  if wanted.ailment ~= candidate.ailment then
    score = score + ((wanted.ailment and wanted.ailment ~= 'none') and 55 or 12)
  end
  local wantedStats, candidateStats = statSignature(wanted), statSignature(candidate)
  if wantedStats ~= candidateStats then score = score + statDistance(wanted, candidate) end
  score = score + math.abs((wanted.priority or 0) - (candidate.priority or 0)) * 18
  score = score + math.abs((wanted.power or 0) - (candidate.power or 0)) * .55
  local wa, ca = wanted.accuracy or 0, candidate.accuracy or 0
  if wa > 0 and ca > 0 then score = score + math.abs(wa - ca) * .35 end
  score = score + math.abs((wanted.pp or 0) - (candidate.pp or 0)) * .12
  score = score + math.abs((wanted.drain or 0) - (candidate.drain or 0)) * .3
  score = score + math.abs((wanted.healing or 0) - (candidate.healing or 0)) * .3
  return score
end

function M.repair(national, read, names)
  local native = {}
  for num, name in pairs(names or {}) do
    if type(num)=='number' and num>=1 and num<=354 and type(name)=='string' then
      native[key(name)] = name:upper():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')
    end
  end
  local moveIndex, getMove = moveData(read)
  local nativeMoves = {}
  for id in pairs(moveIndex) do
    local nativeId = native[key(id)]
    if nativeId and not AUTO_EXCLUDE[key(nativeId)] then
      nativeMoves[#nativeMoves + 1] = { id = nativeId, data = getMove(id) }
    end
  end
  table.sort(nativeMoves, function(a, b) return a.id < b.id end)

  local learnIndex = loadTable(read, 'data/moves/generated/learnsets/index.lua')
  local learnShards, repaired, substituted = {}, 0, 0
  local ranked = {}
  local function substitute(id, used)
    local direct = native[key(id)]
    if direct then return direct end
    local forced = OVERRIDE[id]
    if type(forced) ~= 'table' then forced = forced and { forced } or {} end
    for _, fallback in ipairs(forced) do
      fallback = native[key(fallback)]
      if fallback and (not used or not used[fallback]) then return fallback end
    end
    if not ranked[id] then
      local wanted, choices = getMove(id), {}
      for _, candidate in ipairs(nativeMoves) do
        choices[#choices + 1] = {
          id = candidate.id, score = distance(wanted, candidate.data)
        }
      end
      table.sort(choices, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.id < b.id
      end)
      ranked[id] = choices
    end
    for _, choice in ipairs(ranked[id]) do
      if not used or not used[choice.id] then return choice.id end
    end
    return (ranked[id][1] and ranked[id][1].id) or native.TACKLE or 'TACKLE'
  end

  for id, source in pairs(national.register or {}) do
    if source.form or (source.dex>386 and source.dex<=1025) then
      local number = learnIndex[id]
      if number and not learnShards[number] then
        learnShards[number] = loadTable(read,
          string.format('data/moves/generated/learnsets/%03d.lua', number))
      end
      local full = number and learnShards[number][id] or (source.form and source.learnset) or nil
      if full and #full > 0 then
        local rows, used = {}, {}
        -- Reserve canonical Gen 3 moves before choosing substitutes, so a
        -- replacement never duplicates a real move learned later in the set.
        for _, row in ipairs(full) do
          local direct = native[key(row.move)]
          if direct then used[direct] = true end
        end
        for _, row in ipairs(full) do
          local move = substitute(row.move, used)
          if not native[key(row.move)] then substituted = substituted + 1 end
          rows[#rows + 1] = { level = math.max(1, tonumber(row.level) or 1), move = move }
          used[move] = true
        end
        source.learnset = rows
        source.level1Moves = {}
        for _, row in ipairs(rows) do
          if row.level <= 1 then source.level1Moves[#source.level1Moves + 1] = row.move end
        end
        repaired = repaired + 1
      end
      if not source.learnset or #source.learnset == 0 then
        source.learnset = { { level = 1, move = native.TACKLE or 'TACKLE' } }
        source.level1Moves = { native.TACKLE or 'TACKLE' }
      end
    end
  end
  return repaired, substituted
end
return M
