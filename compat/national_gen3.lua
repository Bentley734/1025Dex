-- National Dex Gen 3 0.5.1 saves use fixed evolution-item slots 900..918.
-- Keep those identities readable without changing existing 1025Dex apple IDs.
return function(mod)
  local gen=require('src.core.GameVersion').generation()
  local ids={'DAWN_STONE','DUBIOUS_DISC','DUSK_STONE','ELECTIRIZER','ICE_STONE',
    'MAGMARIZER','PROTECTOR','REAPER_CLOTH','SACHET','SHINY_STONE','SWEET_APPLE',
    'TART_APPLE','WHIPPED_DREAM','AUSPICIOUS_ARMOR','BLACK_AUGURITE',
    'MALICIOUS_ARMOR','METAL_ALLOY','PEAT_BLOCK','SYRUPY_APPLE'}
  local registered={}
  for i,id in ipairs(ids) do
    local apple=id=='SWEET_APPLE' or id=='TART_APPLE'
    local key=gen==3 and apple and 'NATIONAL_DEX_'..id or id
    if not mod.content.items:get(key) then
      local row={id=key,name=id:gsub('_',' '),price=apple and 2100 or 0}
      if gen==3 then
        row.index=899+i;row.pocket='ITEMS';row.fieldUse='evo'
        row.holdEffect=0;row.holdEffectParam=0;row.battleUsage=0
        row.importance=0;row.registrability=0;row.secondaryId=0
        row.description='An evolution item.'
      else
        -- GB travel retains the held item; unsupported field use stays disabled.
        row.pocket='ITEM';row.tossable=true;row.fieldMenu='ITEMMENU_NOUSE';row.battleMenu='ITEMMENU_NOUSE'
      end
      mod.content.items:register(key,row)
    end
    registered[#registered+1]={id=id,key=key,index=899+i}
  end
  if gen~=3 then return end
  local Items=require('src.core.game3.items_data')
  -- Do not populate native slots before the loader assigns their ownership.
  local committed=false
  local function restore()
    if not committed then return end
    if not Items._byId then return end
    Items._byName=Items._byName or {}
    for _,entry in ipairs(registered) do
      local row=mod.content.items:get(entry.key)
      if row then
        Items._byId[entry.index]=row
        if entry.id~='SWEET_APPLE' and entry.id~='TART_APPLE' then
          Items._byName[entry.id]=entry.index
          Items._byName[row.name]=entry.index
          Items._byName[entry.id:gsub('_','')]=entry.index
        end
      end
    end
    for id,index in pairs({SWEET_APPLE=1002,TART_APPLE=1001}) do
      Items._byName[id]=index;Items._byName[id:gsub('_',' ')]=index
      Items._byName[id:gsub('_','')]=index
    end
  end
  local install=Items.installPack
  Items.installPack=function(...)
    local result=install(...);restore();return result
  end
  Items.ensureLoaded();restore()
  mod.events:on('mods.loaded',function()committed=true;restore()end)
  -- Consume the original bag slot, but resolve evolution using our existing
  -- apple branch. Nothing in the save is rewritten to a new numeric ID.
  local Evolution=require('src.core.game3.evolution')
  local original=Evolution.itemTarget
  Evolution.itemTarget=function(mon,item,session)
    local id=Items.toNumericId(item)
    if id==910 then item=1002 elseif id==911 then item=1001 end
    return original(mon,item,session)
  end
end
