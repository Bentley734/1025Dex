-- Additive Game Boy encounters. Roll the cartridge first so rates, time of
-- day, swarms, repel, and fishing failures retain their native behavior.
return function(mod)
  local function read(name) return assert(load(assert(mod:read(name)), '@1025dex/'..name))() end
  local Policy,roster=read('policy.lua'),read('roster.lua')
  local key='fireredGenEncounterPool'
  local choices={};for i,row in ipairs(Policy.choices)do choices[i]={row.label,tostring(i)} end
  mod.options:define({{key=key,label='WILD GENS',type='choice',default='17',choices=choices}})
  local function gameData() return mod.game and mod.game.data or require('src.core.Data') end
  local function normalize(s)return tostring(s or ''):upper():gsub('[^A-Z0-9]','')end
  local catalog,source,ids,profiles,homes
  local function refresh()
    local data=gameData()
    if profiles and catalog==data.encounters and source==data.pokemon then return data end
    catalog,source=data.encounters,data.pokemon;ids,profiles,homes={},{},{}
    for id,row in pairs(source or {})do if row.dex and not row.form then ids[row.dex]=id end end
    local function add(map,terrain,entry)
      if not entry or not entry.slots then return end
      local lo,hi=100,0;local sea=false
      local function slots(rows)
        for _,row in ipairs(rows or {})do
          if row.species then
            local level=tonumber(row.level) or 1;lo=math.min(lo,level);hi=math.max(hi,level)
            local mon=source and source[row.species];local nat=mon and mon.dex
            if nat==72 or nat==73 or nat==90 or nat==116 or nat==170 or nat==226 then sea=true end
          end
        end
      end
      if entry.slots.MORN then for _,time in ipairs({'MORN','DAY','NITE'})do slots(entry.slots[time])end else slots(entry.slots)end
      if hi==0 or (entry.rate and entry.rate<=0) then return end
      local name=normalize(map)
      local habitat=terrain=='water' and (sea and 'sea' or 'freshwater') or
        (name:find('FOREST') or name:find('ILEX') or name:find('NATIONALPARK') or name=='ROUTE28') and 'forest' or
        name:find('SAFARI') and 'safari' or (name:find('ICE') or name:find('SEAFOAM')) and 'ice' or name:find('POWERPLANT') and 'electric' or
        (name:find('POKEMONTOWER') or name:find('TINTOWER')) and 'ghost' or
        name:find('BURNED') and 'volcanic' or
        (name:find('CAVE') or name:find('TUNNEL') or name:find('MTMOON') or name:find('MTSILVER') or name:find('VICTORYROAD') or name:find('UNION') or name:find('WHIRL') or name:find('DARKCAVE')) and 'cave' or 'meadow'
      -- The late mountain and League routes can support mature additions;
      -- their cartridge species still keep their original exact levels.
      local nativeHi=hi
      if habitat=='ice' or name:find('MTSILVER') or name:find('VICTORYROAD') or name:find('CERULEANCAVE') or name:find('SAFARIZONE') or name=='ROUTE23' or name=='ROUTE26' or name=='ROUTE27' or name=='ROUTE28' then hi=math.max(hi,70) end
      local p={map=map,terrain=terrain,habitat=habitat,lo=lo,hi=hi,nativeHi=nativeHi}
      profiles[#profiles+1]=p
    end
    if require('src.core.GameVersion').generation()==1 then
      for map,row in pairs(catalog or {})do add(map,'land',row.grass);add(map,'water',row.water)end
    else
      for map,row in pairs(catalog and catalog.grass or {})do add(map,'land',row)end
      for map,row in pairs(catalog and catalog.water or {})do add(map,'water',row)end
    end
    table.sort(profiles,function(a,b)return a.map..a.terrain<b.map..b.terrain end)
    for _,mon in ipairs(roster)do
      local eligible={}
      for _,p in ipairs(profiles)do
        local habitat=(p.terrain=='water' and Policy.habitatAllows(mon,p,p.terrain)) or mon.habitat==p.habitat or
          ((mon.habitat=='forest' or mon.habitat=='meadow') and p.habitat=='safari') or
          (mon.habitat=='safari' and (p.habitat=='meadow' or p.habitat=='forest') and p.hi>=35) or
          (mon.habitat=='desert' and p.habitat=='cave' and p.hi>=40) or
          (mon.habitat=='volcanic' and p.habitat=='cave' and p.hi>=45) or
          (mon.habitat=='electric' and p.habitat=='meadow' and p.hi>=35) or
          (mon.habitat=='ghost' and p.habitat=='cave' and p.hi>=40)
        if ids[mon.id] and habitat and Policy.allows(mon,p.terrain) and (mon.gate or 1)<=p.hi
            and (p.hi>9 or (mon.stage==1 and not mon.special)) then eligible[#eligible+1]=p end
      end
      if #eligible>0 then
        local n=(mon.id*17+(mon.stage or 1)*7)%#eligible+1
        for _,p in ipairs({eligible[n],eligible[(n-1+math.floor(#eligible/2))%#eligible+1]})do
          local k=p.map..':'..p.terrain;homes[k]=homes[k] or {};homes[k][mon.id]=mon
        end
      end
    end
    return data
  end
  local function cleared()
    local save=mod.game and mod.game.save
    local hof=save and save.hallOfFame
    return type(hof)=='table' and ((tonumber(hof.count) or #hof)>0) or false
  end
  local Forms=read('forms.lua')
  local national=assert(load(assert(mod:rootRead('dex/data/species/generated/national.lua'))))()
  local forms=Forms.new(national,roster,Policy,require('src.core.GameVersion').generation(),cleared,function(id)
    return gameData().pokemon[id] and id or nil
  end)
  local randomizer=read('randomizer.lua').new(mod,national,roster,function(id)
    return gameData().pokemon[id] and id or nil
  end,function()return gameData().pokemon end)
  local function formPool(map,terrain)
    return forms:pool(map,terrain,Policy.choices[tonumber(mod.options:get(key)) or 17])
  end
  local function pool(map,terrain)
    refresh();local n=tonumber(mod.options:get(key)) or 17;local choice=Policy.choices[n] or Policy.choices[17]
    local rows={};local p
    for _,profile in ipairs(profiles)do if profile.map==map and profile.terrain==terrain then p=profile;break end end
    if p and not cleared() then local copy={};for k,v in pairs(p)do copy[k]=v end;copy.hi=p.nativeHi;p=copy end
    if p then for _,mon in pairs(homes[map..':'..terrain] or {})do
      if mon.id>=choice.first and mon.id<=choice.last and (mon.gate or 1)<=p.hi and (not mon.special and not Policy.ultraBeasts[mon.id] or cleared()) then rows[#rows+1]=mon end
    end end
    table.sort(rows,function(a,b)return a.id<b.id end)
    return rows,p
  end
  local function weight(mon)
    if mon.special or Policy.ultraBeasts[mon.id] then return 1 end
    if (mon.stage or 1)>1 and (mon.catchRate or 255)<=45 then return 5 end
    return 100
  end
  local function transform(enc,map,terrain,rng)
    if not enc or enc.roamer or enc.roaming or enc.wildScripted or enc.legendary or enc.specialWild then return enc end
    local random,randomLevel=randomizer:choose(enc.level,rng)
    if random then return {species=random.species,level=randomLevel} end
    -- Native half of the distribution remains available under every option.
    rng=rng or math.random
    local choice=Policy.choices[tonumber(mod.options:get(key)) or 17]
    local form,level=forms:choose(map,terrain,choice,rng)
    if form then return {species=form.species,level=level} end
    if rng(1,100)<=50 then return enc end
    local rows,p=pool(map,terrain);if #rows==0 then return enc end
    local total=0;for _,row in ipairs(rows)do total=total+weight(row) end
    local pick=rng(1,total);local mon=rows[#rows]
    for _,row in ipairs(rows)do pick=pick-weight(row);if pick<=0 then mon=row;break end end
    local lo=math.max(p.lo,math.min(p.hi,mon.gate or p.lo))
    if mon.special or Policy.ultraBeasts[mon.id] then lo=math.max(55,lo) end
    local level=rng(lo,math.max(lo,p.hi))
    return {species=ids[mon.id],level=level}
  end
  mod.hooks:wrap('encounter.roll',function(next_,tables,ctx)
    local enc=next_(tables,ctx)
    if ctx.kind and ctx.kind~='wild' then return enc end
    return transform(enc,ctx.mapId,ctx.terrain=='water' and 'water' or 'land',ctx.rng)
  end)
  -- Fishing keeps rod-specific native rolls. Additions use the map's water
  -- habitat only; maps without a declared water pool retain native fishing.
  mod.hooks:wrap('encounter.fishing',function(next_,rod,map,candidates,ctx)
    return transform(next_(rod,map,candidates,ctx),map,'water')
  end)
  mod.hooks:wrap('encounter.table',function(next_,dist,ctx)
    local out=next_(dist,ctx)
    if randomizer:enabled() and next(out or {}) then
      local result={};for _,row in ipairs(randomizer:pool())do result[row.species]=1 end
      if next(result) then return result end
    end
    local rows=pool(ctx.mapId,ctx.terrain=='water' and 'water' or 'land')
    local extra=formPool(ctx.mapId,ctx.terrain=='water' and 'water' or 'land')
    if #rows==0 and #extra==0 then return out end
    local result,total={},0;for id,weight in pairs(out or {})do total=total+weight;result[id]=weight end
    local sum=0;for _,mon in ipairs(rows)do sum=sum+weight(mon) end
    for _,mon in ipairs(rows)do local id=ids[mon.id];result[id]=(result[id] or 0)+total*weight(mon)/sum end
    local all=0;for _,w in pairs(result)do all=all+w end
    for _,form in ipairs(extra)do result[form.species]=(result[form.species] or 0)+all*Forms.chance/(100-Forms.chance)/#extra end
    return result
  end)
  mod.exports.encounterPoolRevision=function()return 'native-gb-habitats-2-forms' end
  mod.exports.gbEncounterAdditions=function(map,terrain)
    local rows,p=pool(map,terrain);for _,form in ipairs(formPool(map,terrain))do rows[#rows+1]=form end
    return rows,p
  end
  mod.exports.formEncounterPool=formPool
  -- Visible wild providers reuse the exact native/addition balance and levels.
  mod.exports.chooseGBWildEncounter=transform
  mod.exports.randomEncounterPool=function()return randomizer:enabled() and randomizer:pool() or {}end
  mod.log:info('Game Boy encounters: native cartridge rolls plus curated habitat homes')
end
