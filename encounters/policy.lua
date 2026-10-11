local Policy = {}

local ULTRA_BEASTS={}
for _,id in ipairs({793,794,795,796,797,798,799,803,804,805,806}) do ULTRA_BEASTS[id]=true end
Policy.ultraBeasts=ULTRA_BEASTS
local function ordinary(mon) return not mon.special and not ULTRA_BEASTS[mon.id] end
local ULTRA_HOMES={
 "FR_VICTORY_ROAD_1F","FR_VICTORY_ROAD_2F","FR_VICTORY_ROAD_3F",
 "FR_CERULEAN_CAVE_1F","FR_CERULEAN_CAVE_2F","FR_CERULEAN_CAVE_B1F",
 "FR_SEVEN_ISLAND_SEVAULT_CANYON",
 "EM_VICTORY_ROAD_1F","EM_VICTORY_ROAD_B1F","EM_VICTORY_ROAD_B2F",
 "EM_SKY_PILLAR_1F","EM_SKY_PILLAR_3F","EM_SKY_PILLAR_5F",
 "EM_ARTISAN_CAVE_1F","EM_ARTISAN_CAVE_B1F",
}
Policy.ultraHomes=ULTRA_HOMES
function Policy.ultraLevelRange(mon,loc,endgame)
 local lo=math.max(endgame and 55 or 45,tonumber(mon.gate) or 1)
 local hi=endgame and 70 or math.min(60,tonumber(loc and loc.hi) or 60)
 return lo,math.max(lo,hi)
end


-- Aquatic bodies cannot appear on land. Water typing alone is insufficient:
-- Psyduck, Wooper, Mudkip, etc. remain valid shoreline/grass encounters.
local WATER_ONLY = {}
for _,id in ipairs({72,73,90,91,116,117,118,119,120,121,129,130,131,
  382,170,171,211,222,223,224,226,230,318,319,320,321,339,340,349,350,366,367,368,369,370,
  456,457,458,489,490,594,602,603,604,535,550,690,691,692,693,746,779,
  846,847,902,960,961,963,964,977,978}) do WATER_ONLY[id]=true end
function Policy.allows(mon, terrain)
  if terrain=='water' or terrain=='fishing' then
    return mon.habitat=='freshwater' or mon.habitat=='sea' or WATER_ONLY[mon.id]==true
  end
  return not WATER_ONLY[mon.id]
end

Policy.choices = {
  {label="GEN 1",first=1,last=151}, {label="GEN 2",first=152,last=251},
  {label="GEN 3",first=252,last=386}, {label="GEN 4",first=387,last=493},
  {label="GEN 5",first=494,last=649}, {label="GEN 6",first=650,last=721},
  {label="GEN 7",first=722,last=809}, {label="GEN 8",first=810,last=905},
  {label="GEN 9",first=906,last=1025}, {label="GEN 1-2",first=1,last=251},
  {label="GEN 1-3",first=1,last=386}, {label="GEN 1-4",first=1,last=493},
  {label="GEN 1-5",first=1,last=649}, {label="GEN 1-6",first=1,last=721},
  {label="GEN 1-7",first=1,last=809}, {label="GEN 1-8",first=1,last=905},
  {label="GEN 1-9",first=1,last=1025},
}
Policy.default = 17

-- Route 1 is deliberately a small beginner pool. These four featured
-- encounters are permanent Route 1 residents, regardless of the selected
-- National Dex generation range.
local ROUTE_1_FEATURED = { 1, 4, 7, 25 }
local ROUTE_1_FEATURED_CHANCE = 10 -- 10% total, shared equally
local ROUTE_1_RESIDENTS = { [1]=true, [4]=true, [7]=true, [25]=true }

-- Fossils were generated as ordinary entries in the original roster, which
-- made Omanyte/Omastar as common as route Pokemon. Treat them as rarities.
local FOSSIL_RARITIES = { [138]=true,[139]=true,[140]=true,[141]=true,[142]=true }

local function isRare(mon)
  if mon.special or FOSSIL_RARITIES[mon.id] then return true end
  return (tonumber(mon.stage) or 1) >= 2 and (tonumber(mon.catchRate) or 255) <= 45
end

local function earlyArea(loc)
  return (tonumber(loc and loc.hi) or 100) <= 9
end

local function safeForEarlyArea(mon, loc)
  if not earlyArea(loc) then return true end
  if ROUTE_1_RESIDENTS[mon.id] then return true end
  -- Nothing rare, evolved, fossil, legendary, or mythical before Brock.
  return not isRare(mon) and (tonumber(mon.stage) or 1) == 1
end

local function key(s)
  return tostring(s or ""):upper():gsub("UNKNOWN_DUNGEON", "CERULEAN_CAVE")
    :gsub("^SEVII_", ""):gsub("^FR_", ""):gsub("^LG_", "")
    :gsub("[^A-Z0-9]", "")
end

local function terrainProfile(loc, terrain)
  if not loc or (not loc.hoenn and not loc.nativeChannels) then return loc end
  local area=loc[terrain or "land"]
  if not area then return nil end
  local out={};for k,v in pairs(loc) do out[k]=v end
  for k,v in pairs(area) do out[k]=v end
  return out
end
local function hoennHabitat(mon,loc,terrain)
  if loc.any then return true end
  if terrain=="water" or terrain=="fishing" then
    local aquatic=({[90]='sea',[91]='sea',[131]='sea',
      [602]='freshwater',[603]='freshwater',[604]='freshwater'})[mon.id] or mon.habitat
    return aquatic==loc.habitat
  end
  return mon.habitat==loc.habitat
end
Policy.habitatAllows=hoennHabitat

-- These additions are unlocked only after the native League-clear flag.
-- FR/LG's birds and Mewtwo stay native; Mew gains League-gated wild homes.
-- Emerald and the remaining FR/LG specials keep their existing assignments.
local SPECIAL_HOMES = {
  frlg={
    water={"FR_FIVE_ISLAND_WATER_LABYRINTH","FR_SIX_ISLAND_WATER_PATH"},
    land={
      electric={"FR_CERULEAN_CAVE_1F","FR_CERULEAN_CAVE_2F"},
      ice={"FR_FOUR_ISLAND_ICEFALL_CAVE_B1F","FR_CERULEAN_CAVE_2F"},
      ghost={"FR_FIVE_ISLAND_LOST_CAVE_ROOM1","FR_FIVE_ISLAND_LOST_CAVE_ROOM10"},
      forest={"FR_SIX_ISLAND_PATTERN_BUSH","FR_THREE_ISLAND_BERRY_FOREST"},
      volcanic={"FR_MT_EMBER_RUBY_PATH_B3F","FR_MT_EMBER_SUMMIT_PATH_3F"},
      sea={"FR_SEAFOAM_ISLANDS_B4F","FR_FOUR_ISLAND_ICEFALL_CAVE_B1F"},
      freshwater={"FR_CERULEAN_CAVE_1F","FR_CERULEAN_CAVE_B1F"},
      cave={"FR_CERULEAN_CAVE_B1F","FR_MT_EMBER_RUBY_PATH_B3F"},
      meadow={"FR_CERULEAN_CAVE_2F","FR_SEVEN_ISLAND_SEVAULT_CANYON"},
      safari={"FR_CERULEAN_CAVE_2F","FR_SEVEN_ISLAND_SEVAULT_CANYON"},
    },
  },
  emerald={
    water={"EM_UNDERWATER_ROUTE124","EM_UNDERWATER_ROUTE126"},
    land={
      electric={"EM_NEW_MAUVILLE_INSIDE","EM_ARTISAN_CAVE_1F"},
      ice={"EM_SHOAL_CAVE_LOW_TIDE_ICE_ROOM","EM_ARTISAN_CAVE_B1F"},
      ghost={"EM_MT_PYRE_6F","EM_MT_PYRE_SUMMIT"},
      forest={"EM_ROUTE120","EM_SAFARI_ZONE_NORTHEAST"},
      volcanic={"EM_FIERY_PATH","EM_SEAFLOOR_CAVERN_ROOM8"},
      sea={"EM_SEAFLOOR_CAVERN_ROOM8","EM_SHOAL_CAVE_LOW_TIDE_INNER_ROOM"},
      freshwater={"EM_ROUTE120","EM_ARTISAN_CAVE_1F"},
      cave={"EM_METEOR_FALLS_STEVENS_CAVE","EM_SKY_PILLAR_5F"},
      meadow={"EM_ARTISAN_CAVE_1F","EM_SKY_PILLAR_5F"},
      safari={"EM_ARTISAN_CAVE_B1F","EM_SKY_PILLAR_3F"},
    },
  },
}
-- Species without a native FR/LG encounter can have explicit homes without
-- duplicating the birds/Mewtwo or changing existing habitat assignments.
local EXTRA_SPECIAL_HOMES = {
  frlg = {
    [151] = {land={"FR_CERULEAN_CAVE_1F", "FR_SEVEN_ISLAND_SEVAULT_CANYON"}},
  },
}
Policy.extraSpecialHomes=EXTRA_SPECIAL_HOMES
Policy.specialHomes=SPECIAL_HOMES
Policy.specialChance=100 -- one shared 1% roll when ordinary candidates exist
function Policy.specialLevelRange(mon)
  local lo=math.max(55,tonumber(mon.gate) or 1)
  return lo,math.max(lo,70)
end
local function specialAt(mon,mapId,terrain)
  if not mon.special or not Policy.allows(mon,terrain) then return false end
  local emerald=tostring(mapId):match("^EM_")~=nil
  local extra=EXTRA_SPECIAL_HOMES[emerald and "emerald" or "frlg"]
  local explicit=extra and extra[mon.id]
  if explicit then
    for _,name in ipairs(explicit[terrain] or {}) do
      if key(name)==key(mapId) then return true end
    end
    return false
  end
  if not emerald and (tonumber(mon.gen) or 1)<=1 then return false end
  local homes=SPECIAL_HOMES[emerald and "emerald" or "frlg"]
  local names=terrain=="water" and homes.water
    or terrain=="land" and homes.land[mon.habitat] or nil
  for _,name in ipairs(names or {}) do if key(name)==key(mapId) then return true end end
  return false
end

function Policy.new(roster, locations, random, progress, campaign, Atlas, channels)
  local self = {roster=roster, locations=locations, random=random or math.random, pools={}}
  self.byMap = {}
  for i,loc in ipairs(locations) do self.byMap[key(loc.map)] = i end

  function self:choice(index)
    index = tonumber(index)
    if not index or index < 1 or index > #Policy.choices or index ~= math.floor(index) then
      index = Policy.default
    end
    return Policy.choices[index], index
  end

  function self:location(mapId)
    local k = key(mapId)
    local exact = self.byMap[k]
    if exact then return exact, self.locations[exact] end
    -- Only declared dungeon families inherit a parent, longest match first.
    -- Never let Route 1 match Route 10/11 or an unknown map inherit Route 1.
    local best, length
    for i,loc in ipairs(self.locations) do
      local parent = key(loc.map)
      if loc.children and k:sub(1, #parent) == parent
          and (not length or #parent > length) then
        best, length = i, #parent
      end
    end
    if best then return best, self.locations[best] end
    return nil, nil
  end

  local function inChoice(mon, choice)
    return mon.id >= choice.first and mon.id <= choice.last
  end

  -- Ordinary homes follow the roster with the cave rebalance below.
  -- Specials have explicit separate homes
  -- and never enter early-area, fishing, Rock Smash or generic fallback pools.
  local function homeFor(mon)
    local wanted = tonumber(mon.location)
    local loc=wanted and locations[wanted]
    -- Keep displaced cave residents catchable without putting evolved,
    -- high-level species back into Mt. Moon or the protected Diglett pool.
    if loc and (loc.residentSlots or (loc.map:match('^FR_MT_MOON_') and (mon.gate or 1)>loc.hi)) then
      local map=(mon.gate or 1)<=28 and 'FR_ROCK_TUNNEL_1F' or 'FR_ROCK_TUNNEL_B1F'
      wanted=self.byMap[key(map)]
    end
    return wanted and locations[wanted] and wanted or nil
  end

  local hoennHomes={}
  for _,mon in ipairs(roster) do
    if ordinary(mon) then
      hoennHomes[mon.id]={}
      for _,terrain in ipairs({"land","water","fishing","rocks"}) do
        local eligible={}
        for i,base in ipairs(locations) do
          if base.hoenn then
            local loc=terrainProfile(base,terrain)
            if loc and Policy.allows(mon,terrain) and (mon.gate or 1)<=loc.hi
                and safeForEarlyArea(mon,loc) and hoennHabitat(mon,loc,terrain) then
              eligible[#eligible+1]=i
            end
          end
        end
        if #eligible>0 then
          local first=(mon.id*17+(mon.stage or 1)*7)%#eligible+1
          hoennHomes[mon.id][terrain]={[eligible[first]]=true,
            [eligible[(first-1+math.floor(#eligible/2))%#eligible+1]]=true}
        end
      end
    end
  end

  local atlas
  local function campaignActive(context)
    if context and context.campaign~=nil then return context.campaign==true end
    return campaign and campaign()==true or false
  end
  function self:campaignAtlas()
    if not atlas and Atlas then atlas=Atlas.new(self,channels) end
    return atlas
  end
  function self:pool(mapId, choiceIndex, terrain, context)
    if campaignActive(context) and Atlas then
      local a=self:campaignAtlas()
      local baseline,loc=self:pool(mapId,choiceIndex,terrain,{postgame=context and context.postgame,campaign=false})
      if not loc then return baseline,loc end
      return a:filter(self.locations[self:location(mapId)].map,terrain or 'land',baseline),loc
    end
    terrain=terrain or "land"
    local locIndex,base = self:location(mapId)
    local loc=terrainProfile(base,terrain)
    local choice,normalized = self:choice(choiceIndex)
    local postgame=context and context.postgame
    if postgame==nil and progress then postgame=progress() end
    postgame=postgame==true
    if not loc then
      return {common={},rare={},featured={},special={},ultra={},choice=choice},nil
    end
    local cacheKey = key(mapId) .. ":" .. locIndex .. ":" .. normalized .. ":" .. terrain .. ":" .. (postgame and 1 or 0)
    if self.pools[cacheKey] then return self.pools[cacheKey],loc end
    if terrain=='land' and loc.residentSlots then
      local common,rare,seen={},{},{}
      for _,slot in ipairs(loc.residentSlots)do
        local mon=self.roster[slot[1]]
        if mon and not seen[mon.id] then
          seen[mon.id]=true
          local list=mon.id==51 and rare or common;list[#list+1]=mon
        end
      end
      local result={common=common,rare=rare,featured={},special={},ultra={},
        residentSlots=loc.residentSlots,location=loc,choice=choice}
      self.pools[cacheKey]=result
      return result,loc
    end
    local common,rare,featured,seen = {},{},{},{}
    local function add(list,mon)
      if seen[mon.id] then return false end
      seen[mon.id]=true; list[#list+1]=mon; return true
    end
    -- Native encounters are area/channel exceptions to generated habitat,
    -- evolution gates and early-area rarity rules (e.g. Viridian Pikachu).
    for _,mon in ipairs(self.roster)do
      if loc.native and loc.native[mon.id] and inChoice(mon,choice) then
        add(isRare(mon) and rare or common,mon)
      end
    end
    for _,mon in ipairs(self.roster) do
      if Policy.allows(mon, terrain) and inChoice(mon, choice) and (tonumber(mon.gate) or 1) <= (tonumber(loc.hi) or 100) then
        local home=homeFor(mon)
        local belongs = home == locIndex
        -- Retain the incoming build's nearby-route homes for policy callers
        -- without ROM profiles. Canon-aware profiles below remain authoritative.
        for _,source in ipairs(loc.encounterSources or {})do
          if home==self.byMap[key(source)]then belongs=true;break end
        end
        if loc.nativeChannels and not loc.hoenn then
          belongs=mon.habitat==loc.habitat
        elseif loc.hoenn then
          local homes=hoennHomes[mon.id] and hoennHomes[mon.id][terrain]
          belongs=(loc.native and loc.native[mon.id]) or (homes and homes[locIndex])
        elseif loc.sevii then
          -- Additional island homes leave the original Kanto distribution intact.
          -- Aquatic pools are separate even on forest/volcano/cave maps.
          if terrain == "water" or terrain == "fishing" then
            belongs = true -- Policy.allows above already selected aquatic species.
          else
            belongs = mon.habitat == loc.habitat
          end
        end
        if ordinary(mon) and belongs
            and (not loc.nativeChannels or hoennHabitat(mon,loc,terrain))
            and safeForEarlyArea(mon, loc) then
          add(isRare(mon) and rare or common, mon)
        end
      end
    end

    if (loc.hoenn or loc.encounterSources) and #common==0 and #rare==0 then
      -- A restricted generation still gets a legal ordinary pool on every
      -- native encounter terrain. Prefer that terrain's habitat first.
      for pass=1,2 do
        for _,mon in ipairs(self.roster) do
          if ordinary(mon) and Policy.allows(mon,terrain) and inChoice(mon,choice)
              and (mon.gate or 1)<=loc.hi and safeForEarlyArea(mon,loc)
              and (pass==2 and loc.hoenn or hoennHabitat(mon,loc,terrain)) then
            add(isRare(mon) and rare or common,mon)
          end
        end
        if #common+#rare>0 or loc.nativeChannels then break end
      end
    end
    if loc.hoenn and terrain=="land" and loc.featured then
      for _,id in ipairs(loc.featured) do
        local mon=self.roster[id]
        if mon and inChoice(mon,choice) then featured[#featured+1]=mon end
      end
    end
    if terrain=="land" and key(loc.map) == "ROUTE1" then
      for _, id in ipairs(ROUTE_1_FEATURED) do
        local mon = self.roster[id]
        if mon then featured[#featured+1] = mon end
      end
    end

    local special={}
    if postgame then
      for _,mon in ipairs(self.roster) do
        if inChoice(mon,choice) and specialAt(mon,mapId,terrain) then special[#special+1]=mon end
      end
    end
    local ultra,endgame={},false
    for _,home in ipairs(ULTRA_HOMES)do if key(home)==key(mapId) then endgame=true;break end end
    -- All UBs require League clear. Outside their hubs, only level-45+
    -- habitat-matched land areas qualify; early routes/forests never do.
    if postgame and terrain=='land' and (endgame or loc.hi>=45) then
      for _,mon in ipairs(self.roster)do
        if ULTRA_BEASTS[mon.id] and inChoice(mon,choice) and Policy.allows(mon,terrain)
          and (endgame or mon.habitat==loc.habitat or loc.any) then ultra[#ultra+1]=mon end
      end
    end
    local result={common=common,rare=rare,featured=featured,special=special,ultra=ultra,
      ultraEndgame=endgame,ultraChance=endgame and 100 or 1000,location=loc,choice=choice,native=loc.native}
    self.pools[cacheKey]=result
    return result,loc
  end

  function self:choose(mapId, choiceIndex, nativeLevel, terrain, context)
    local pool,loc = self:pool(mapId, choiceIndex, terrain, context)
    if not loc then return nil end
    if pool.residentSlots then
      local total=0;for _,slot in ipairs(pool.residentSlots)do total=total+slot[3] end
      local roll=self.random(total)
      for _,slot in ipairs(pool.residentSlots)do
        roll=roll-slot[3]
        if roll<=0 then return self.roster[slot[1]],slot[2] end
      end
      return nil
    end
    if loc.hoenn and (terrain=="fishing" or terrain=="rocks") then
      local ceiling=math.max(loc.lo,tonumber(nativeLevel) or loc.lo)
      local filtered={common={},rare={},featured={},special={},ultra={},choice=pool.choice}
      for _,kind in ipairs({"common","rare","featured"}) do
        for _,mon in ipairs(pool[kind]) do
          if (pool.native and type(pool.native[mon.id])=='table' and pool.native[mon.id][1]<=ceiling)
              or (not (pool.native and type(pool.native[mon.id])=='table') and (mon.gate or 1)<=ceiling) then filtered[kind][#filtered[kind]+1]=mon end
        end
      end
      if #filtered.common+#filtered.rare+#filtered.featured==0 then
        for _,mon in ipairs(self.roster) do
          if ordinary(mon) and Policy.allows(mon,terrain) and inChoice(mon,pool.choice)
              and (mon.gate or 1)<=ceiling and safeForEarlyArea(mon,loc)
              and (not campaignActive(context) or not Atlas or self:campaignAtlas():belongs(mon,loc.hoenn) and hoennHabitat(mon,loc,terrain)) then
            filtered.common[#filtered.common+1]=mon
            if campaignActive(context) and #filtered.common>=3 then break end
          end
        end
      end
      pool=filtered
    end
    local list
    if #(pool.ultra or {})>0 and self.random(pool.ultraChance)==1 then
      list=pool.ultra
    elseif #pool.special>0 and (#pool.common+#pool.rare+#pool.featured==0 or self.random(Policy.specialChance)==1) then
      list=pool.special
    elseif #pool.featured > 0 and self.random(ROUTE_1_FEATURED_CHANCE) == 1 then
      list=pool.featured
    elseif #pool.rare > 0 and (#pool.common == 0 or self.random(20) == 1) then
      list=pool.rare
    else
      list=pool.common
    end
    if #list == 0 then return nil end
    local mon=list[self.random(#list)]
    if ULTRA_BEASTS[mon.id] then
      local lo,hi=Policy.ultraLevelRange(mon,loc,pool.ultraEndgame)
      return mon,self.random(lo,hi)
    end
    if mon.special then
      local lo,hi=Policy.specialLevelRange(mon)
      return mon,self.random(lo,hi)
    end
    if loc.native and type(loc.native[mon.id])=='table' then
      local range=loc.native[mon.id]
      return mon,math.max(range[1],math.min(tonumber(nativeLevel) or range[1],range[2]))
    end
    local level=math.max(tonumber(nativeLevel) or loc.lo,loc.lo,mon.gate)
    return mon,math.min(level,loc.hi)
  end
  return self
end

return Policy
