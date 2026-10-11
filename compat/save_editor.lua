-- The embedded editor has a separate bootstrap and a legacy 14-box adapter.
-- Use its existing module instances; no editor files or saves are rewritten.
return function(mod)
  local version = require('src.core.GameVersion')
  if version.generation()==2 then
    -- The National Dex payload uses the shared API spelling, while Gold's
    -- extractor prefixes its curve ids. Alias the native curve functions.
    local curves=mod.content.growth_rates
    for _,id in ipairs({'MEDIUM_FAST','MEDIUM_SLOW','FAST','SLOW','SLIGHTLY_FAST','SLIGHTLY_SLOW'}) do
      local row=curves and curves:get('GROWTH_'..id)
      if row and not curves:get(id) then curves:register(id,row) end
    end
  end
  local ok, Gen = pcall(require, 'Gen')
  if not ok or type(Gen) ~= 'table' or type(Gen.boxCount) ~= 'function' then return end
  local Data = require('src.core.Data')
  if version.generation() ~= 3 then return end
  local P = require('src.core.game3.pokemon')
  -- Game3 normally binds these before loading mods; the editor omits them.
  Data.gen3Pokemon = Data.gen3Pokemon or P
  Data.gen3Moves = Data.gen3Moves or require('src.core.game3.battle.moves')
  Data.gen3Items = Data.gen3Items or require('src.core.game3.items_data')
  local Storage = require('src.core.game3.storage')
  local Adapter = require('Game3Adapter')
  local Copy = require('src.mods.Merge').deepCopy
  local function shallow(t)
    local out = {}; for k,v in pairs(t or {}) do out[k]=v end; return out
  end
  local function equal(a,b)
    if a==b then return true end
    if type(a)~='table' or type(b)~='table' then return false end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
  end
  local function count(save)
    local n = Storage.TOTAL_BOXES_COUNT
    for _,boxes in ipairs({save and save.storage and save.storage.boxes or {}, save and save.boxes or {}}) do
      for k in pairs(boxes) do
        if type(k)=='number' and k>=1 and k==math.floor(k) then n=math.max(n,k) end
      end
    end
    return n
  end
  if not Adapter.__completeDexStorage then
    Adapter.__completeDexStorage = true
    local originalCount = Gen.boxCount
    Gen.boxCount = function(save)
      if Gen.of(save)==3 then return count(save) end
      return originalCount(save)
    end
    Adapter.ensureStorage = function(save)
      local legacy = type(save.storage)~='table'
      local source = legacy and Storage.restore(nil,save.pc,save.pcItems or save.pc_items) or save.storage
      local storage = shallow(source)
      storage.boxes,storage.items = {}, source.items or {}
      local boxes,available = {},{}
      for b=1,count(save) do
        local box = shallow(source.boxes and source.boxes[b])
        box.name = box.name or ('BOX '..b)
        box.wallpaper = box.wallpaper or Storage.defaultWallpaper(b)
        box.mons = shallow(box.mons)
        for _,mon in pairs(box.mons) do available[#available+1]={mon=mon} end
        storage.boxes[b],boxes[b] = box,box.mons
      end
      -- Preserve legacy lists without duplicating the editor's native mirrors.
      for b,box in pairs(save.boxes or {}) do
        for s,mon in pairs(type(box)=='table' and box or {}) do
          if type(s)=='number' and type(mon)=='table' then
            local mirrored=false
            for _,entry in ipairs(available) do
              if not entry.used and equal(entry.mon,mon) then entry.used=true;mirrored=true;break end
            end
            if not mirrored then
              local tb,ts
              if boxes[b] and s>=1 and s<=Storage.IN_BOX_COUNT and s==math.floor(s) and not boxes[b][s] then tb,ts=b,s
              else
                for i=1,#boxes do
                  for j=1,Storage.IN_BOX_COUNT do
                    if not boxes[i][j] then tb,ts=i,j;break end
                  end
                  if tb then break end
                end
              end
              assert(tb,'Cannot preserve legacy box Pokemon: storage is full')
              boxes[tb][ts]=mon
            end
          end
        end
      end
      save.storage,save.boxes = storage,boxes
      storage.currentBox=math.max(1,math.min(#boxes,tonumber(storage.currentBox) or 1))
      save.currentBox=storage.currentBox
      if legacy and type(save.pc)=='table' then save.pc.mons,save.pc.items=nil,nil end
      return boxes
    end
  end
  -- Registry merge writes native runtime tables, while the editor catalog and
  -- MonOps also read Data.pokemon. Publish the same records after the merge.
  mod.events:on('mods.loaded',function()
    local registry = mod.content.pokemon
    local national = assert(load(assert(mod:read('dex/data/species/generated/national.lua'))))()
    for _,rows in ipairs({national.patch,national.register}) do
      for id in pairs(rows) do
        local row = registry:get(id)
        local slot = P.speciesFromName(id)
        if row and slot then
          row=Copy(row);row.speciesId=slot;row.species=slot
          Data.pokemon[id],Data.pokemon[slot]=row,row
        end
      end
    end
    mod.log:info('Save editor synchronized with extended species and PC storage')
  end)
end
