local api=assert(loader.exports['1025dex'])
local machines=assert(api.moveMachines)
local gen=require('src.core.GameVersion').generation()
local expected=0
for _,id in ipairs(api.listMoves())do if api.moveById(id).moveId>({165,251,354})[gen]then expected=expected+1 end end
assert(#machines.catalog==expected)
local energy
for _,row in ipairs(machines.catalog)do if row.moveId==412 then energy=row end end
assert(energy and energy.price==3000)
assert(machines.stockAt('FR_CELADON_CITY_DEPARTMENT_STORE_2F'))
assert(machines.stockAt('GoldenrodDeptStore5F'))
assert(machines.stockAt('EM_LILYCOVE_CITY_DEPARTMENT_STORE_4F'))
assert(not machines.stockAt('VIRIDIAN_MART'))
local original={'POTION',energy.item}
local expanded=machines.append(original)
assert(#original==2 and #expanded==#machines.catalog+1)
if gen==3 then
 -- Text glyph rasterization is covered by the GPU suite, not this headless test.
 local Text=require('src.core.game3.rom_text');Text.box=function(key)return key end;Text.plain=Text.box
 local P=require('src.core.game3.pokemon');local Items=require('src.core.game3.items_data')
 local Bag=require('src.core.game3.bag');local Use=require('src.core.game3.item_use')
 for _,row in ipairs(machines.catalog)do
  assert(Items.isTm(row.item)and not Items.isHm(row.item))
  assert(Items.info(row.item).price==3000 and P.moveFromTmItem(row.item)==row.moveId)
 end
 local bulb=assert(P.speciesFromName('BULBASAUR'));local karp=assert(P.speciesFromName('MAGIKARP'))
 assert(P.canLearnTmItem(bulb,energy.item));assert(not P.canLearnTmItem(karp,energy.item))
 local shadow=assert(machines.byItem.TM1708)
 assert(not P.canLearnTmItem(P.speciesFromName('MAROWAK'),shadow.item),'Form move leaked onto base species')
 assert(P.canLearnTmItem(P.speciesFromName('MAROWAK_ALOLA'),shadow.item),'Form machine permission missing')
 local mon={species=bulb,level=5,moves={33},pp={35},personality=0};P.applyStats(mon);mon.hp=mon.maxHp
 local bag=Bag.new();assert(Bag.add(bag,energy.item,2))
 local all=Bag.new();for _,row in ipairs(machines.catalog)do assert(Bag.add(all,row.item,1),'TM Case cannot hold '..row.item)end
 assert(Use.checkTmPreflight(mon,energy.item)=='ok')
 assert(Use.useTm({party={mon}},bag,energy.item,1))
 assert(mon.moves[2]==412 and mon.pp[2]==api.moveById(energy.move).pp and Bag.get(bag,energy.item)==1)
 assert(Use.checkTmPreflight(mon,energy.item)=='knows')
 local host,sidecar=Bag.splitForHost(bag,{})
 local restored=Bag.new();Bag.mergeFromHost(restored,host);Bag.restoreSidecar(restored,{quarantine=sidecar})
 assert(Bag.get(restored,energy.item)==1,'Machine lost in bag save sidecar')
 local Shop=require('src.ui.game3.shop_menu')
 local version=require('src.core.GameVersion').get()
 local hoenn=version=='ruby'or version=='sapphire'or version=='emerald'
 if hoenn then
  -- Keep the native purchase handler; omit RS scene-pack raster setup here.
  local profile=require('src.core.game3.profile').active()
  local UI=require(profile.ui.shopMenu or 'src.ui.game3.rse.shop_menu')
  UI.show=function(shop)shop._martType='NORMAL'end
 end
 local session={money=9000,bag=Bag.new(),map=hoenn and 'EM_LILYCOVE_CITY_DEPARTMENT_STORE_4F'or'FR_CELADON_CITY_DEPARTMENT_STORE_2F'}
 Shop.show{session=session,items={13}}
 assert(#Shop._items==#machines.catalog+1,'Department store omitted machine stock')
 local input={wasPressed=function(_,key)return key=='a'end}
 if hoenn then
  Shop.state='confirm';Shop.yesCursor=1;Shop._itemId=energy.item;Shop._totalCost=3000;Shop.qty=1
 else
  Shop.mode='buy_confirm';Shop.yesNoCursor=1;Shop._pending={id=energy.item,name=energy.item,price=3000};Shop.qty=1
 end
 Shop.handleInput(input)
 assert(session.money==6000 and Bag.get(session.bag,energy.item)==1,'Machine purchase failed')
 Shop.close()
 -- Native machines remain native, including reusable HMs.
 assert(P.moveFromTmItem(339)==15 and Items.isHm(339))
else
 local data=require('src.core.Data')
 local found=false;for _,id in ipairs(data.pokemon.BULBASAUR.tmhm)do if id==energy.move then found=true end end
 assert(found,'Bulbasaur machine permission missing')
 for _,id in ipairs(data.pokemon.MAGIKARP.tmhm or{})do assert(id~=energy.move)end
 for _,row in ipairs(machines.catalog)do assert(data.items[row.item].machine.move==row.move)end
 local Bag=require('src.inventory.Bag');local save={inventory={},bagOrder={}}
 assert(Bag.add(save,energy.item,2,data));assert(save.inventory[energy.item]==2)
 if gen==1 then
  local Pokemon=require('src.pokemon.Pokemon')
  local bulb=Pokemon.new(data,'BULBASAUR',5,function(a,b)return b and a or 0 end)
  local result,move=require('src.inventory.ItemEffects').use(data,save,energy.item,bulb)
  assert(result=='learn'and move==energy.move,'Native TM teaching route rejected Energy Ball')
  local clerk=data.textPointers or data.text_pointers
  if clerk and clerk.CeladonMart4F then
   local stock=clerk.CeladonMart4F.TEXT_CELADONMART4F_CLERK.mart
   local seen={}for _,id in ipairs(stock)do assert(not seen[id],'Duplicate Celadon stock');seen[id]=true end
   assert(seen[energy.item])
  end
 end
 if gen==2 then
  for _,row in ipairs(machines.catalog)do assert(Bag.add(save,row.item,1,data),'TM pocket cannot hold '..row.item)end
  assert(data.items[energy.item].pocket=='TM_HM'and data.items[energy.item].teaches==energy.move)
  local Mart=require('src.ui.gen2.MartMenu')
  local mart={game={world={map={id='GoldenrodDeptStore5F'}}},martType='STANDARD',items=data.items,marts={lists={{'POTION'}}},martId=0}
  Mart.buildEntries(mart);assert(#mart.entries==#machines.catalog+1)
  mart.game.data=data;mart.save={player={money=9000},inventory={},bagOrder={}}
  mart.qtyItem={id=energy.item,price=3000};mart.qty=1;mart.text={thanks='thanks',noMoney='noMoney'}
  mart.say=function()end;mart.playTransaction=function()end
  setmetatable(mart,{__index=Mart});mart:completePurchase(3000)
  assert(mart.save.player.money==6000 and mart.save.inventory[energy.item]==1,'Goldenrod machine purchase failed')
  mart.game.world.map.id='CherrygroveMart';Mart.buildEntries(mart);assert(#mart.entries==1)
 end
end
local noLearners=0
for _,row in ipairs(machines.catalog)do
 local found=false;for _,allowed in pairs(machines.permissions)do if allowed[row.moveId]then found=true;break end end
 if not found then noLearners=noLearners+1;print('MACHINE-NO-LEARNER',row.move,row.moveId)end
end
assert(noLearners==0,'Every machine needs a real base/form recipient')
print('MACHINES-PASS',require('src.core.GameVersion').get(),#machines.catalog,'canonical machines, compatibility, shops, bag/teaching; no learners',noLearners)
