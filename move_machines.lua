-- SPDX-License-Identifier: GPL-3.0-or-later
-- Expanded machines use string bag identities, never scarce cartridge item bytes.
return function(mod)
 local Version=require('src.core.GameVersion')
 local generation=Version.generation()
 local api=mod.exports
 local cutoff=({165,251,354})[generation]
 local catalog,byItem,byMove,permissions,speciesPermissions={},{},{},{},{}
 local normalize=function(id)return tostring(id):upper():gsub('[^A-Z0-9]','')end
 local legacy={GRASSYGLIDE=172,LASHOUT=173,METEORBEAM=174,MISTYEXPLOSION=175,POLTERGEIST=176,SCORCHINGSANDS=177}
 -- Historical learners for moves removed from the newest species learnsets.
 -- Source: PokeAPI/api-data data/api/v2/move/{302,443,456,537}/index.json.
 local historical={
  [302]={'CACNEA','CACTURNE','MARACTUS','QUILLADIN','CHESNAUGHT'},
  [443]={'MAGNEMITE','MAGNETON','MAGNEZONE','PROBOPASS','GENESECT'},
  [456]={'VESPIQUEN'},
  [537]={'GOLEM','VENIPEDE','WHIRLIPEDE','SCOLIPEDE','GUZZLORD','GOLEM_ALOLA'},
 }
 for _,id in ipairs(api.listMoves())do
  local move=api.moveById(id)
  if move.moveId>cutoff then
   local number=legacy[normalize(id)]or(1000+move.moveId)
   local row={item='TM'..number,number=number,move=id,moveId=move.moveId,name=move.name,price=3000}
   catalog[#catalog+1]=row;byItem[row.item]=row;byMove[normalize(id)]=row
  end
 end
 table.sort(catalog,function(a,b)return a.number<b.number end)
 -- A machine grants a different acquisition route, not another species' move.
 for national=1,1025 do
  local info=api.statsByDex(national)
  if info then
   local allowed={};permissions[national]=allowed
   local function populate(record)
   local own={};speciesPermissions[record.id]=own
   local function add(rows)for _,entry in ipairs(rows or{})do
    local row=byMove[normalize(entry.move)]
    if row then allowed[row.moveId]=true;own[row.moveId]=true end
   end end
   add(record.movesFull)
   for _,rows in pairs(record.movesByMethod or{})do add(rows)end
   for number,ids in pairs(historical)do for _,id in ipairs(ids)do
    if normalize(record.id)==normalize(id)then own[number]=true;allowed[number]=true end
   end end
   end
   populate(info)
   for _,form in ipairs(info.forms or{})do populate(form)end
  end
 end
 local function append(items)
  local out,seen={},{}
  for _,id in ipairs(items or{})do out[#out+1]=id;seen[tostring(id)]=true end
  for _,row in ipairs(catalog)do if not seen[row.item]then out[#out+1]=row.item end end
  return out
 end
 local function stockAt(map)
  map=tostring(type(map)=='table'and(map.id or map.name)or map or''):lower():gsub('[^a-z0-9]','')
  return map:find('celadonmart4f',1,true)~=nil or map:find('celadondeptstore3f',1,true)~=nil
   or map:find('celadoncitydepartmentstore2f',1,true)~=nil
   or map:find('goldenroddeptstore5f',1,true)~=nil or map:find('lilycovecitydepartmentstore4f',1,true)~=nil
 end
 api.moveMachines={catalog=catalog,byItem=byItem,permissions=permissions,stockAt=stockAt,append=append}
 if generation<3 then
  -- The old six-item registration is superseded here, preserving its item IDs.
  for _,row in ipairs(catalog)do
   local value={id=row.item,name=row.item,price=row.price,needsTarget=true,tossable=true,
    machine={kind='TM',move=row.move,number=row.number}}
   if mod.content.items:get(row.item)then mod.content.items:patch(row.item,value)
   else mod.content.items:register(row.item,value)end
  end
  mod.events:on('mods.loaded',function(ctx)
   local data=ctx.data
   for id,species in pairs(data.pokemon or{})do
    if type(species)=='table'then
     local info=api.statsBySpecies(id)
     local allowed=info and speciesPermissions[info.id]
     if allowed then
      species.tmhm=species.tmhm or{};local seen={}
      for _,move in ipairs(species.tmhm)do seen[move]=true end
      for _,row in ipairs(catalog)do if allowed[row.moveId]and not seen[row.move]then species.tmhm[#species.tmhm+1]=row.move end end
     end
    end
   end
   if generation==2 then for _,row in ipairs(catalog)do
    local item=data.items[row.item]
    item.pocket='TM_HM';item.teaches=row.move;item.tmNumber=row.number;item.tmLabel=row.item
    item.fieldMenu='ITEMMENU_CURRENT';item.battleMenu='ITEMMENU_NOUSE';item.canToss=true
    item.description='Teaches '..row.name..'.'
   end end
  end)
  if generation==1 then
   mod.content.text_pointers:patch('CeladonMart4F',{TEXT_CELADONMART4F_CLERK={mart=(function()local t={}for _,r in ipairs(catalog)do t[#t+1]=r.item end return t end)()}})
  else
   local Bag=require('src.inventory.Bag');local capacity=Bag.capacity
   Bag.capacity=function(data,pocket)if pocket=='TM_HM'then return capacity(data,pocket)+#catalog end;return capacity(data,pocket)end
   local Mart=require('src.ui.gen2.MartMenu');local original=Mart.buildEntries
   Mart.buildEntries=function(self,...)
    original(self,...)
    if self.martType=='STANDARD'and stockAt(self.game and self.game.world and self.game.world.map)then
     local seen={}for _,r in ipairs(self.entries)do seen[r.id]=true end
     for _,row in ipairs(catalog)do if not seen[row.item]then self.entries[#self.entries+1]={id=row.item,name=row.item,price=row.price}end end
    end
   end
   -- Extended TM labels need room beside the native two-digit column.
   local Pack=require('src.ui.gen2.PackMenu');local drawList=Pack.drawList
   local Chrome=require('src.ui.gen2.Chrome')
   Pack.drawList=function(self,x,y,...)
    local printThrough=Chrome.printThrough
    Chrome.printThrough=function(text,px,py,...)
     if px==x-3 and tostring(text):match('^%d%d%d+')then px=px-(#tostring(text)-2)end
     return printThrough(text,px,py,...)
    end
    local ok,err=pcall(drawList,self,x,y,...);Chrome.printThrough=printThrough
    if not ok then error(err,0)end
   end
  end
 else
  local Items=require('src.core.game3.items_data')
  local P=require('src.core.game3.pokemon')
  local applyProfile=Items.applyProfile
  Items.applyProfile=function(...)
   local result=applyProfile(...);Items.CAPACITY.TM_CASE=(Items.CAPACITY.TM_CASE or 58)+#catalog;return result
  end
  Items.CAPACITY.TM_CASE=(Items.CAPACITY.TM_CASE or 58)+#catalog
  local originalInfo=Items.info
  Items.info=function(id)
   local row=byItem[tostring(id)]
   if row then return{id=row.item,name=row.item,pocket='TM_CASE',fieldUse='tm',price=row.price,
    description='Teaches '..row.name..' to a compatible Pokemon.'}end
   return originalInfo(id)
  end
  local originalMove=P.moveFromTmItem
  P.moveFromTmItem=function(id)local row=byItem[tostring(id)];if row then return row.moveId end;return originalMove(id)end
  local originalCan=P.canLearnTmItem
  P.canLearnTmItem=function(species,id)
   local row=byItem[tostring(id)]
   if not row then return originalCan(species,id)end
   local info=api.statsBySpecies(P.keyName(species))
   if not info then return false end
   return speciesPermissions[info.id]and speciesPermissions[info.id][row.moveId]==true or false
  end
  local Shop=require('src.ui.game3.shop_menu');local originalShow=Shop.show
  Shop.show=function(opts)
   if opts and stockAt(opts.session and opts.session.map)then
    local copy={}for k,v in pairs(opts)do copy[k]=v end
    copy.items=append(opts.items);opts=copy
   end
   return originalShow(opts)
  end
  -- Reuse native TM artwork without assigning a cartridge item number.
  local icons={}
  for item=289,338 do
   local move=P.battleMove(originalMove(item))
   if move and not icons[move.type]then icons[move.type]=item end
  end
  local function iconFor(id)
   local row=byItem[tostring(id)]
   if row then local move=P.battleMove(row.moveId);return icons[move and move.type]or 289 end
  end
  api.moveMachines.iconFor=iconFor
  local BagChrome=require('src.ui.game3.bag_chrome');local iconImage=BagChrome.iconImage
  BagChrome.iconImage=function(id)return iconImage(iconFor(id)or id)end
  local RseChrome=require('src.ui.game3.rse.bag_chrome');local drawIcon=RseChrome.drawItemIcon
  RseChrome.drawItemIcon=function(index,...)
   if index==nil then
    local id
    local BagMenu=package.loaded['src.ui.game3.bag_menu']
    if BagMenu and BagMenu.open then local rows=BagMenu.list();local row=rows[BagMenu.cursor];id=row and row.id end
    if not id and Shop.open then id=Shop._items[(Shop.scroll or 0)+(Shop.row or 0)+1]end
    index=iconFor(id)
   end
   return drawIcon(index,...)
  end
  local Case=require('src.ui.game3.tm_case');local Chrome=require('src.ui.game3.tm_case_chrome')
  local drawDisc=Chrome.drawDisc
  Chrome.drawDisc=function(kind,x,y,hm,...)
   local rows=Case.list();local selected=rows[Case.cursor]
   -- Native positioning divides a 58-disc rack by the printed TM number.
   -- Extended numbers identify moves; they are not physical rack slots.
   if selected and byItem[tostring(selected.id)]then x,y=24,31 end
   return drawDisc(kind,x,y,hm,...)
  end
 end
 mod.log:info('1025Dex: %d expanded move machines at regional department stores',#catalog)
end
