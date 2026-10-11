return function(mod)
  local GameVersion=require("src.core.GameVersion")
  if GameVersion.generation() ~= 3 then
    return assert(load(assert(mod:read('gb.lua')),'@1025dex/encounters/gb.lua'))()(mod)
  end
  local function data(path)
    return assert(load(assert(mod:read(path)), "@"..path))()
  end
  local Policy=data("policy.lua")
  local locations=data("locations.lua")
  for _,loc in ipairs(data("hoenn_locations.lua")) do locations[#locations+1]=loc end
  local nativeData=data("native.lua")
  local version=GameVersion.get and GameVersion.get() or 'firered'
  local native={}
  for map,rows in pairs(nativeData[version=='leafgreen' and 'leafgreen' or 'firered'])do native[map]=rows end
  for map,rows in pairs(nativeData.emerald)do native[map]=rows end
  locations=data("native_profiles.lua").prepare(locations,native)
  local Progress=data("progress.lua")
  local Forms=data('forms.lua')
  local national=assert(load(assert(mod:rootRead('dex/data/species/generated/national.lua'))))()
  local forms=Forms.new(national,data('roster.lua'),Policy,3,Progress.postgame,function(name)
    local P=require('src.core.game3.pokemon')
    local slot=P.speciesFromName(name)
    return slot and P.keyName(slot) and slot or nil
  end)
  local randomizer=data('randomizer.lua').new(mod,national,data('roster.lua'),function(name)
    local P=require('src.core.game3.pokemon');local slot=P.speciesFromName(name)
    return slot and P.keyName(slot) and slot or nil
  end,function()return require('src.core.game3.pokemon')._names end)
  local function campaignActive()
    return mod.find and mod:find("kanto_hoenn")~=nil or false
  end
  local channels=data("campaign_terrains.lua")
  for map,rows in pairs(native)do
    local k=map:gsub('[^%w]',''):upper();channels[k]={}
    for terrain in pairs(rows)do channels[k][terrain]=true end
  end
  local policy=Policy.new(data("roster.lua"),locations,math.random,Progress.postgame,campaignActive,data("campaign.lua"),channels)
  mod.exports.encounterPoolRevision=function()
    return campaignActive() and "kanto-hoenn-3-forms" or "native-habitats-3-forms"
  end
  local OPTION_KEY="fireredGenEncounterPool"
  local active=Policy.default
  local rs=version=='ruby' or version=='sapphire'
  local rsTables
  local function policyMap(map)
    if rs and type(map)=='string' then return map:gsub('^RU_','EM_'):gsub('^SA_','EM_') end
    return map
  end
  local function refreshRs()
    if not rs then return end
    local E=require('src.core.game3.encounters')
    E.ensureLoaded()
    if rsTables==E._tables then return end
    rsTables=E._tables
    local P=require('src.core.game3.pokemon')
    local rows={}
    for map,entry in pairs(rsTables or {})do
      if type(map)=='string' and map:match('^[RS][UA]_') then
        local target=policyMap(map);rows[target]={}
        for _,terrain in ipairs({'land','water','fishing','rocks'})do
          local area=entry[terrain] or (terrain=='land' and entry.grass)
          if area and area.slots and (not area.rate or area.rate>0) then
            local residents={};rows[target][terrain]=residents
            for _,slot in ipairs(area.slots)do
              local nat=P.national(slot.species)
              if nat and nat>=1 and nat<=1025 then
                local lo=slot.minLevel or slot.level or 1;local hi=slot.maxLevel or lo
                local old=residents[nat];residents[nat]={math.min(old and old[1] or lo,lo),math.max(old and old[2] or hi,hi)}
              end
            end
          end
        end
      end
    end
    local rules=E.rules and E.rules()
    local extra=rules and rules.wildExtra and rules.wildExtra()
    local feebas=extra and extra.feebas and extra.feebas.mon
    if feebas and rows.EM_ROUTE119 and rows.EM_ROUTE119.fishing then
      local nat=P.national(feebas.species)
      rows.EM_ROUTE119.fishing[nat]={feebas.minLevel,feebas.maxLevel}
    end
    local base=data('locations.lua')
    for _,loc in ipairs(data('hoenn_locations.lua'))do
      for _,terrain in ipairs({'land','water','fishing','rocks'})do if loc[terrain] then loc[terrain].native=nil end end
      base[#base+1]=loc
    end
    local combined={};for map,entry in pairs(nativeData.firered)do combined[map]=entry end
    for map,entry in pairs(rows)do combined[map]=entry end
    local prepared=data('native_profiles.lua').prepare(base,combined)
    local liveChannels={};for map,entry in pairs(combined)do
      local k=map:gsub('[^%w]',''):upper();liveChannels[k]={}
      for terrain in pairs(entry)do liveChannels[k][terrain]=true end
    end
    policy=Policy.new(data('roster.lua'),prepared,math.random,Progress.postgame,campaignActive,data('campaign.lua'),liveChannels)
  end

  local function optionBlock(engine)
    return require("src.core.game3.options").block(engine)
  end
  local function readSelection()
    refreshRs()
    local Runtime=require("src.core.game3.runtime")
    local session=Runtime and Runtime.getSession and Runtime.getSession()
    local engine=session and session.engineOptions
    if type(engine)=="table" then
      local _,n=policy:choice(optionBlock(engine)[OPTION_KEY]); active=n
    elseif session and type(session.options)=="table" then
      local _,n=policy:choice(session.options[OPTION_KEY]); active=n
    end
    return active
  end

  local function choose(map,level,terrain)
    local random,randomLevel=randomizer:choose(level)
    if random then return random,randomLevel end
    local selection=readSelection()
    local choice=policy:choice(selection)
    local form,formLevel=forms:choose(map,terrain,choice)
    if form then return form,formLevel end
    return policy:choose(policyMap(map),selection,level,terrain)
  end
  local okRows,Rows=pcall(require,"src.ui.game3.option_rows")
  if okRows and Rows and type(Rows.build)=="function" and not Rows.__completeDexWilds then
    Rows.__completeDexWilds=true
    local original=Rows.build
    Rows.build=function(ctx)
      local rows=original(ctx)
      for i=#rows,1,-1 do if rows[i].id==OPTION_KEY then table.remove(rows,i) end end
      local opts=optionBlock(ctx.options)
      local _,n=policy:choice(opts[OPTION_KEY]); active=n; opts[OPTION_KEY]=n
      rows[#rows+1]={id=OPTION_KEY,label="WILD GENS",
        value=function(c)
          local block=optionBlock(c.options)
          local choice,index=policy:choice(block[OPTION_KEY] or active)
          active=index; return choice.label
        end,
        step=function(c,dir)
          local block=optionBlock(c.options)
          local _,current=policy:choice(block[OPTION_KEY] or active)
          local nextIndex=current+((dir and dir<0) and -1 or 1)
          if nextIndex<1 then nextIndex=#Policy.choices elseif nextIndex>#Policy.choices then nextIndex=1 end
          block[OPTION_KEY]=nextIndex; active=nextIndex
          local Runtime=require("src.core.game3.runtime")
          local session=Runtime and Runtime.getSession and Runtime.getSession()
          if session then session.options=block; session.engineOptions=c.options end
          return true
        end}
      return rows
    end
  else mod.log:warn("Game3 OPTIONS row hook unavailable") end

  -- Carry the source of the encounter with the foe, including fishing while
  -- the player is standing on land. No global "last encounter" state.
  local Encounters=require("src.core.game3.encounters")
  if not Encounters.__completeDexTerrain then
    Encounters.__completeDexTerrain=true
    local step=Encounters.onStep
    if step then
      Encounters.onStep=function(mapId,terrain,opts)
        local enc=step(mapId,terrain,opts)
        if type(enc)=="table" then
          local actual=terrain
          if not actual and opts and opts.x and opts.y and Encounters.terrainAt then
            actual=Encounters.terrainAt(opts.x,opts.y)
          end
          enc.__completeDexTerrain=actual or "land"
          enc.__completeDexMap=mapId
        end
        return enc
      end
    end
    for _,entry in ipairs({{"rollFishing","fishing"},{"rollRocks","rocks"}}) do
      local fn,terrain=entry[1],entry[2]
      local original=Encounters[fn]
      if original then
        Encounters[fn]=function(mapId, ...)
          local enc=original(mapId, ...)
          if type(enc)=="table" then
            enc.__completeDexTerrain=terrain
            enc.__completeDexMap=mapId
          end
          return enc
        end
      end
    end
  end

  local Bridge=require("src.core.game3.battle_bridge")
  if not Bridge.__completeDexWilds then
    Bridge.__completeDexWilds=true
    local original=Bridge.start
    Bridge.start=function(owner,game,foe,opts)
      -- Only replace a rolled encounter marked by our onStep/fishing/rock
      -- hooks. Scripted and legendary battles use the exact ROM species.
      if opts and opts.wild and not opts.__completeDexExact
          and not (opts.legendary or opts.wildScripted or opts.roamer
            or opts.firstBattle or opts.oldManTutorial)
          and type(foe) == "table" and foe.__completeDexTerrain
          and not (foe.legendary or foe.wildScripted or foe.roamer
            or foe.specialWild) then
        local Runtime=require("src.core.game3.runtime")
        local session=Runtime.getSession and Runtime.getSession()
        local mapId=foe.__completeDexMap or (session and session.map) or (game and game.currentMap)
        local okCatalog,Catalog=pcall(require,"src.import.gba.map_catalog")
        if okCatalog and Catalog.resolve then mapId=Catalog.resolve(mapId) end
        local level=type(foe)=="table" and tonumber(foe.level) or nil
        local terrain=type(foe)=="table" and foe.__completeDexTerrain
        if not terrain then
          local Player=require("src.core.game3.player")
          terrain=(Player and Player.surfing) and "water" or "land"
        end
        local mon,newLevel=choose(mapId,level,terrain)
        if mon then
          local Pokemon=require("src.core.game3.pokemon")
          local slot=Pokemon.speciesFromName(mon.name)
          if slot and Pokemon.keyName(slot) then
            foe={species=slot,speciesId=slot,level=newLevel,item=nil}
            if Pokemon._speciesMeta then
              Pokemon._speciesMeta[slot]=Pokemon._speciesMeta[slot] or {}
              Pokemon._speciesMeta[slot].catchRate=mon.catchRate
            end
          end
        end
      end
      -- Visible wilds and DexNav supply an exact species but may also carry
      -- explicit bonus/stale moves. Rebuild after the final species/level
      -- selection; do not change trainer parties, roaming or scripted mons.
      if opts and opts.wild and not (opts.link or opts.trainerId or opts.roamer
          or opts.wildScripted or opts.firstBattle or opts.oldManTutorial)
          and type(foe)=='table' and not (foe.roamer or foe.wildScripted)
          and type(mod.exports.vanillaWildMoves)=='function' then
        local species=foe.species or foe.speciesId or foe.id
        local moves,pp,maxPp=mod.exports.vanillaWildMoves(species,foe.level)
        if moves then
          local clean={};for k,v in pairs(foe)do clean[k]=v end
          clean.moves,clean.pp,clean.maxPp=moves,pp,maxPp;foe=clean
        end
      end
      return original(owner,game,foe,opts)
    end
  end
  -- Visible wilds must choose here instead of using a stale embedded policy.
  mod.exports.chooseWildEncounter = function(mapId, terrain, nativeLevel)
    local okCatalog,Catalog=pcall(require,"src.import.gba.map_catalog")
    if okCatalog and Catalog.resolve then mapId=Catalog.resolve(mapId) end
    local mon,level=choose(mapId,nativeLevel,terrain)
    if not mon then return nil end
    local P=require("src.core.game3.pokemon")
    local species=P.speciesFromName(mon.name)
    if not species or not P.keyName(species) then return nil end
    return mon.id,species,level,mon.catchRate
  end
  -- Live pool API: internal species IDs and levels match the battle policy.
  mod.exports.dexnavEncounters = function(mapId)
    local okCatalog,Catalog=pcall(require,"src.import.gba.map_catalog")
    if okCatalog and Catalog.resolve then mapId=Catalog.resolve(mapId) end
    refreshRs()
    if not randomizer:enabled() and not policy:location(policyMap(mapId)) then return nil end
    local native = Encounters.tableFor(mapId)
    if type(native) ~= "table" then return nil end
    local out = {}
    local P = require("src.core.game3.pokemon")
    for _, terrain in ipairs({"land", "water", "fishing", "rocks"}) do
      local area = native[terrain] or (terrain == "land" and native.grass)
      if area then
        if randomizer:enabled() then
          local slots={}
          local lo,hi
          for _,nativeSlot in ipairs(area.slots or {})do
            local minLevel=nativeSlot.minLevel or nativeSlot.level or 1
            local maxLevel=nativeSlot.maxLevel or minLevel
            lo=math.min(lo or minLevel,minLevel);hi=math.max(hi or maxLevel,maxLevel)
          end
          lo,hi=lo or 1,hi or 1
          for _,row in ipairs(randomizer:pool())do slots[#slots+1]={species=row.species,minLevel=lo,maxLevel=hi,weight=1,form=row.form}end
          out[terrain]={slots=slots}
        else
        local pool, loc = policy:pool(policyMap(mapId), readSelection(), terrain)
        local slots, seen = {}, {}
        for _, group in ipairs({pool.common, pool.rare, pool.featured, pool.special, pool.ultra}) do
          for _, mon in ipairs(group or {}) do
            local species = P.speciesFromName(mon.name)
            if species and not seen[species] then
              seen[species] = true
              local lo,hi=math.min(loc.hi,math.max(loc.lo,mon.gate or 1)),loc.hi
              if loc.native and type(loc.native[mon.id])=='table' then lo,hi=loc.native[mon.id][1],loc.native[mon.id][2] end
              if mon.special then lo,hi=Policy.specialLevelRange(mon) end
              if Policy.ultraBeasts[mon.id] then lo,hi=Policy.ultraLevelRange(mon,loc,pool.ultraEndgame) end
              local weight
              if pool.residentSlots then
                lo,hi,weight=nil,nil,0
                for _,slot in ipairs(pool.residentSlots)do if slot[1]==mon.id then
                  lo=math.min(lo or slot[2],slot[2]);hi=math.max(hi or slot[2],slot[2]);weight=weight+slot[3]
                end end
              end
              slots[#slots+1]={species=species,minLevel=lo,maxLevel=hi,weight=weight}
            end
          end
        end
        local extra=forms:pool(mapId,terrain,policy:choice(readSelection()))
        local total=0;for _,slot in ipairs(slots)do total=total+(slot.weight or 1)end
        for _,form in ipairs(extra)do
          slots[#slots+1]={species=form.species,minLevel=Forms.minLevel,maxLevel=Forms.maxLevel,
            weight=math.max(total,1)*Forms.chance/(100-Forms.chance)/#extra,form=form.form}
        end
        out[terrain] = {slots=slots}
        end
      end
    end
    return out
  end
  mod.exports.randomEncounterPool=function()return randomizer:enabled() and randomizer:pool() or {}end
  mod.exports.formEncounterPool=function(map,terrain)
    return forms:pool(map,terrain or 'land',policy:choice(readSelection()))
  end
  mod.log:info("Game3 generation selector installed: all 1025 species, immediate filtering")
end
