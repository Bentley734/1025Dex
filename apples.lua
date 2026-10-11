-- Evolution apples use the native bag, purchase and evolution flows.
return function(mod)
  local gen = require('src.core.GameVersion').generation()
  local apples = {
    {id='TART_APPLE', name='TART APPLE', index=1001, target='FLAPPLE'},
    {id='SWEET_APPLE', name='SWEET APPLE', index=1002, target='APPLETUN'},
  }
  local function claim(reg, id, row)
    if reg:get(id) then reg:override(id,row) else reg:register(id,row) end
  end
  local function normal(id) return tostring(id or ''):upper():gsub('[^A-Z0-9]','') end
  local function ends(id, name) return normal(id):sub(-#name)==name end
  local function gbShop(game)
    local map = game and game.world and game.world.map
    local id = map and (map.id or (map.def and map.def.label))
    return ends(id,'CELADONMART4F') or ends(id,'CELADONDEPTSTORE4F')
      or (gen==2 and ends(id,'GOLDENRODDEPTSTORE4F'))
  end
  local function stock(items, numeric)
    local out, seen = {}, {}
    for _,id in ipairs(items or {}) do out[#out+1]=id;seen[id]=true end
    for _,apple in ipairs(apples) do
      local id = numeric and apple.index or apple.id
      if not seen[id] then out[#out+1]=id end
    end
    return out
  end
  for _,apple in ipairs(apples) do
    local target = apple.target
    local row = {id=apple.id,name=apple.name,price=2100}
    if gen==3 then
      row.index=apple.index; row.pocket='ITEMS'; row.fieldUse='evo'
      row.holdEffect=0; row.holdEffectParam=0; row.importance=0
      row.registrability=0; row.battleUsage=0; row.secondaryId=0
      row.description='Use on APPLIN\nto evolve into\n'..target..'.'
    else
      row.needsTarget=true; row.effect=apple.id; row.tossable=true
      row.pocket='ITEM'; row.fieldMenu='ITEMMENU_PARTY'; row.battleMenu='ITEMMENU_NOUSE'
      local effect = {needsTarget=true,field=true,battle=false,action='stone'}
      if gen==1 then
        effect.use=function(ctx)
          if not ctx.target or ctx.target.species~='APPLIN' then
            return 'failed',{'It won\'t have any effect.'}
          end
          return 'consumed',nil,{evolveTo=target}
        end
      else
        effect.use=function(ctx)
          if not ctx.mon or ctx.mon.species~='APPLIN' or ctx.mon.item=='EVERSTONE' then
            return {used=false,text="It won't have any effect."}
          end
          local entry=require('src.core.gen2.Evolution').checkMon(ctx.data,ctx.mon,{force=true,item=ctx.item})
          if not entry then return {used=false,text="It won't have any effect."} end
          return {used=true,evolution=entry}
        end
      end
      claim(mod.content.item_effects,apple.id,effect)
    end
    claim(mod.content.items,apple.id,row)
  end
  if gen==1 then
    local Effects=require('src.inventory.ItemEffects')
    local isStone=Effects.isStone
    Effects.isStone=function(id)
      return id=='TART_APPLE' or id=='SWEET_APPLE' or isStone(id)
    end
    local Shop=require('src.ui.ShopMenu')
    local original=Shop.new
    Shop.new=function(game,items,onQuit)
      return original(game,gbShop(game) and stock(items) or items,onQuit)
    end
  elseif gen==2 then
    local Shop=require('src.ui.gen2.MartMenu')
    local original=Shop.buildEntries
    Shop.buildEntries=function(self,...)
      local result=original(self,...)
      if self.martType=='STANDARD' and gbShop(self.game) then
        local seen={}; for _,row in ipairs(self.entries) do seen[row.id]=true end
        for _,apple in ipairs(apples) do
          if not seen[apple.id] then
            self.entries[#self.entries+1]={id=apple.id,name=apple.name,price=2100}
          end
        end
      end
      return result
    end
  else
    local Items=require('src.core.game3.items_data')
    local function restore()
      if not Items._byId then return end
      Items._byName=Items._byName or {}
      for _,apple in ipairs(apples) do
        local row=mod.content.items:get(apple.id)
        Items._byId[apple.index]=row
        Items._byName[apple.id]=apple.index
        Items._byName[apple.name]=apple.index
      end
    end
    local install=Items.installPack
    Items.installPack=function(...)
      local result=install(...); restore(); return result
    end
    Items.ensureLoaded();restore()
    mod.events:on('mods.loaded',restore)
    -- FRLG's National Dex gate predates these species. Purchased apples
    -- should work on Applin before the postgame unlock, like other games.
    local Evolution=require('src.core.game3.evolution')
    local P=require('src.core.game3.pokemon')
    local itemTarget=Evolution.itemTarget
    Evolution.itemTarget=function(mon,item,session)
      local result=itemTarget(mon,item,session)
      if result then return result end
      local num=Items.toNumericId(item)
      if (num==1001 or num==1002) and mon and P.speciesOf(mon)==P.speciesFromName('APPLIN') then
        local target=Evolution.targetSpecies(mon,Evolution.EVO_MODE_ITEM_USE,num)
        if target and target~=0 then return target end
      end
    end
    local Shop=require('src.ui.game3.shop_menu')
    local Map=require('src.core.game3.map')
    local original=Shop.show
    Shop.show=function(opts)
      if ends(Map.current,'CELADONCITYDEPARTMENTSTORE4F') or ends(Map.current,'CELADONDEPTSTORE4F') then
        local copy={};for k,v in pairs(opts or {}) do copy[k]=v end
        copy.items=stock(copy.items,true);opts=copy
      end
      return original(opts)
    end
    -- The owner (local id 1) only explains berries. Leave the two reward
    -- NPCs alone, including Ruby/Sapphire's differently named scripts.
    mod.hooks:wrap('world.talk',function(nextTalk,game,npc)
      local def=npc and npc.def
      local lid=npc and (npc.localId or (def and (def.localId or def.index)))
      if not ends(Map.current,'ROUTE104PRETTYPETALFLOWERSHOP') or lid~=1 then
        return nextTalk(game,npc)
      end
      local Field=require('src.core.game3.field')
      local Objects=require('src.core.game3.objects')
      Field.lock('1025dex_apples');Objects.freeze(lid);Objects.facePlayer(lid,game)
      Shop.show({items=stock({},true),session=Field._session,onClose=function()
        Objects.unfreeze(lid);Field.unlock('1025dex_apples')
      end})
    end)
  end
  mod.exports.evolutionApples={price=2100,tart='TART_APPLE',sweet='SWEET_APPLE'}
  -- The species registry must exist before patching its two item branches.
  return function()
    if gen==3 or not mod.content.pokemon:get('APPLIN') then return end
    local rows={}
    for _,evo in ipairs(mod.content.pokemon:get('APPLIN').evolutions or {}) do
      local target=evo.into or evo.species
      if target~='FLAPPLE' and target~='APPLETUN' then rows[#rows+1]=evo end
    end
    for _,apple in ipairs(apples) do
      local evo={method=gen==2 and 'EVOLVE_ITEM' or 'ITEM',item=apple.id}
      if gen==2 then evo.into=apple.target else evo.species=apple.target end
      rows[#rows+1]=evo
    end
    mod.content.pokemon:patch('APPLIN',{evolutions=rows})
  end
end
