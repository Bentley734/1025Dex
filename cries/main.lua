-- Complete National Dex cry pack. FireRed's ROM audio table only contains
-- Generations 1-3, and its fallback Hoenn mapping is approximate. Resolve the
-- active internal species slot back to its National number and play the asset
-- stored under that exact number instead.
return function(mod)
  if require('src.core.GameVersion').generation() < 3 then
    local source=assert(mod:rootRead('dex/data/species/generated/national.lua'))
    local national=assert(load(source,'@1025dex/cries/national.lua'))()
    local count=0
    for _,rows in ipairs({national.patch,national.register}) do
      for id,row in pairs(rows or {}) do
        local native=mod.content.pokemon:get(id)
        local number=row.dex or (native and native.dex)
        if type(number)=='number' and number>=1 and number<=1025 and not row.form then
          local rel='assets/'..number..'.ogg'
          if not mod.exports.assetManager or mod:info(rel) then
            local cry={file=mod.assets:path(rel)}
            if mod.content.cries:get(id) then mod.content.cries:override(id,cry)
            else mod.content.cries:register(id,cry) end
          end
          count=count+1
        end
      end
    end
    mod.exports.cryCount=count
    mod.log:info('Game Boy National cry pack registered; Yellow Pikachu voice retained')
    return
  end
  local Audio = require('src.core.game3.audio')
  local Pokemon = require('src.core.game3.pokemon')
  local Sample = require('src.core.game3.m4a_sample')

  local function playPackedCry(species, mode, pan)
    local national = Pokemon.national(tonumber(species))
    if not national or national < 1 or national > 1025 then
      return Audio.__completeDexCryOriginal(species, mode, pan)
    end

    local rel = 'assets/' .. tostring(national) .. '.ogg'
    local info = mod:info(rel)
    if not info or info.type ~= 'file' or not (love and love.audio and love.audio.newSource) then
      return Audio.__completeDexCryOriginal(species, mode, pan)
    end

    local requestedMode, volume = mode, nil
    if type(mode) == 'table' then
      requestedMode, volume = mode.mode, mode.volume
      if pan == nil then pan = mode.pan end
    end
    local params = Sample.cryParams(requestedMode, volume)
    local ok, source = pcall(love.audio.newSource, mod.assets:path(rel), 'static')
    if not ok or not source then
      return Audio.__completeDexCryOriginal(species, mode, pan)
    end

    Audio.stopCry()
    local voices = Sample.cryVoices(params)
    local pitch = voices[1] and voices[1].mul or 1
    if source.setPitch then pcall(source.setPitch, source, pitch) end
    if source.setVolume then
      local gain = math.max(0, math.min(1, (params.volume or 120) / 120))
      pcall(source.setVolume, source, (Audio._sfxVolume or 1) * gain)
    end
    source:play()

    local seconds = source.getDuration and source:getDuration('seconds') or 1.1
    Audio._cryParams = params
    Audio._crySlot = nil
    Audio._crySource = source
    Audio._cryUntil = (Audio._cryClock or 0) + math.max(1, seconds * 60 / math.max(0.01, pitch))
    return true
  end

  if not Audio.__completeDexCryOriginal then
    Audio.__completeDexCryOriginal = Audio.playCry
    Audio.playCry = function(species, mode, pan)
      return Audio.__completeDexCryResolver(species, mode, pan)
    end
  end
  Audio.__completeDexCryResolver = playPackedCry
  mod.exports.cryCount = 1025
  mod.exports.cryNational = function(species) return Pokemon.national(tonumber(species)) end
  mod.log:info('Game3 Complete Dex cries ready: 1-1025 exact National mapping')
end
