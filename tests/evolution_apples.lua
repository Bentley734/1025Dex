local root,version=arg[1],arg[2]
local function read(path)local f=assert(io.open(root..'/1025Dex/'..path));local s=f:read('*a');f:close();return s end
love=require('tests.love_stub');loadstring=loadstring or load
local GV=require('src.core.GameVersion');GV.set(version);local gen=GV.generation()
local Schemas=require('src.mods.Schemas');local Registry=require('src.mods.Registry')
local data={items={},pokemon={APPLIN={evolutions={{method=gen==2 and 'EVOLVE_LEVEL' or 'LEVEL',level=36,species='FLAPPLE',into='FLAPPLE'},{method=gen==2 and 'EVOLVE_LEVEL' or 'LEVEL',level=36,species='DIPPLIN',into='DIPPLIN'}}}},item_effects={},gen2ItemEffects={}}
for _,row in ipairs(data.pokemon.APPLIN.evolutions)do if gen==2 then row.species=nil else row.into=nil end end
data.text={}
data.items.POTION={id='POTION',name='POTION',price=300}
local content={}
for _,name in ipairs({'items','pokemon','item_effects'}) do
 local spec=Schemas.REGISTRIES[name];local reg=Registry.new(name,spec)
 local base=data[name];reg.base=function()return base end
 local facade={}
 for _,method in ipairs({'register','override','patch'})do
  local action=method
  facade[action]=function(_,id,row)
   local ok,errors=Schemas.check(spec,name,id,row,action,gen)
   assert(ok,name..':'..id..':'..(type(errors)=='table' and table.concat(errors,';') or tostring(errors)))
   return reg[action](reg,id,row,'1025dex')
  end
 end
 facade.get=function(_,id)return reg:get(id)end
 content[name]=facade
end
local hooks,events={},{}
local mod={content=content,exports={},hooks={wrap=function(_,key,fn)hooks[key]=fn end},events={on=function(_,key,fn)events[key]=fn end}}
local Items,Shop,Map
if gen==3 then
 Items=require('src.core.game3.items_data')
 Items.installPack({items={[13]={name='POTION',pocket='ITEMS',price=300},[95]={name='FIRE STONE',pocket='ITEMS',fieldUse='evo',price=2100}},count=2})
 -- The real shop entry point runs below with only display surfaces stubbed.
 package.loaded['src.ui.game3.stack']={push=function()end,pop=function()end}
 package.loaded['src.ui.game3.money_box']={hide=function()end,update=function()end}
 package.loaded['src.ui.game3.chrome']={invalidate=function()end}
 package.loaded['src.ui.game3.rse.shop_menu']={show=function()end}
 package.loaded['src.ui.game3.rs.shop_menu']={show=function()end}
 Shop=require('src.ui.game3.shop_menu');Map=require('src.core.game3.map')
 local RomText=require('src.core.game3.rom_text')
 RomText.box=function(key)return key end
 package.loaded['src.core.game3.quest_log_recorder']={event=function()end,location=function()return 0 end}
end
local finish=assert(load(read('apples.lua')))()(mod);finish()
for _,id in ipairs({'TART_APPLE','SWEET_APPLE'})do
 data.items[id]=assert(content.items:get(id));assert(data.items[id].price==2100)
 if gen<3 then
  local effect=assert(content.item_effects:get(id));data.item_effects[id]=effect;data.gen2ItemEffects[id]=effect
 end
end
data.pokemon.APPLIN=content.pokemon:get('APPLIN')
local originalStock={'POTION'}
local game={data=data,world={map={id='CELADON_DEPT_STORE_4F'}},save={player={money=10000},bag={}}}
if gen==1 then
 -- Drive the native BUY action and its quantity/confirmation callbacks;
 -- only drawing screens are replaced, while stock, prices and bag are real.
 local Menu=require('src.ui.Menu');local orig=Menu.new
 Menu.new=function(_,rows)return {rows=rows}end
 local List=require('src.ui.ListMenu');local oldList=List.new
 List.new=function(_,_,rows,opts)return {items=rows,opts=opts,index=1}end
 local Qty=require('src.ui.QuantityBox');local oldQty=Qty.new
 Qty.new=function(_,opts)return {opts=opts}end
 local Box=require('src.render.TextBox');local oldBox=Box.new
 Box.new=function(_,text,done,opts)return {text=text,done=done,opts=opts}end
 game.save.money=10000
 game.stack={rows={},push=function(self,x)self.rows[#self.rows+1]=x end,pop=function(self)table.remove(self.rows)end,top=function(self)return self.rows[#self.rows]end}
 local shop=require('src.ui.ShopMenu').new(game,originalStock)
 shop.rows[1].onSelect();game.stack:top().opts.stay.onShown()
 local list=game.stack:top()
 assert(#list.items==4 and list.items[2].value=='TART_APPLE' and list.items[3].value=='SWEET_APPLE')
 for i=2,3 do
  local before=game.save.money
  list.opts.onChoose(list.items[i]);game.stack:top().opts.onDone(1)
  game.stack:top().opts.choice(true);assert(game.save.money==before-2100)
 end
 game.world.map.id='VIRIDIAN_MART'
 local other=require('src.ui.ShopMenu').new(game,originalStock)
 other.rows[1].onSelect();game.stack:top().opts.stay.onShown()
 assert(#game.stack:top().items==2,'unrelated mart changed')
 Menu.new=orig;List.new=oldList;Qty.new=oldQty;Box.new=oldBox
 local Effects=require('src.inventory.ItemEffects')
 for id,target in pairs({TART_APPLE='FLAPPLE',SWEET_APPLE='APPLETUN'})do
  assert(Effects.needsTarget(id,data.items[id],data))
  local used,_,extra=Effects.use(data,game.save,id,{species='APPLIN'})
  assert(used=='consumed' and extra.evolveTo==target)
  assert(Effects.use(data,game.save,id,{species='DIPPLIN'})=='failed')
  assert(Effects.use(data,game.save,id,{species='PIKACHU'})=='failed')
  assert(Effects.use(data,game.save,id,{species='APPLIN'},{})=='failed')
 end
elseif gen==2 then
 local Mart=require('src.ui.gen2.MartMenu')
 for _,map in ipairs({'CELADON_DEPT_STORE_4F','GOLDENROD_DEPT_STORE_4F'})do
  game.world.map.id=map
  local shop=Mart.new(game,{marts={lists={{'POTION'}}}})
  assert(#shop.entries==3 and shop.entries[2].id=='TART_APPLE' and shop.entries[3].id=='SWEET_APPLE')
  for i=2,3 do
   shop.qtyItem=shop.entries[i];shop.qty=1;local before=game.save.player.money
   shop:completePurchase(2100);assert(game.save.player.money==before-2100)
  end
  shop:buildEntries();assert(#shop.entries==3,'duplicate shelf after rebuilding')
 end
 game.world.map.id='VIOLET_MART';assert(#Mart.new(game,{marts={lists={{'POTION'}}}}).entries==1)
 local Effects=require('src.core.gen2.ItemEffects')
 for id,target in pairs({TART_APPLE='FLAPPLE',SWEET_APPLE='APPLETUN'})do
  assert(Effects.partyAction(id,data)=='stone')
  local result=Effects.useOnMon(id,{species='APPLIN'},data)
  assert(result.used and result.evolution.into==target)
  assert(not Effects.useOnMon(id,{species='DIPPLIN'},data).used)
  assert(not Effects.useOnMon(id,{species='APPLIN',isEgg=true},data).used)
  assert(not Effects.useOnMon(id,{species='APPLIN',item='EVERSTONE'},data).used)
 end
else
 local Bag=require('src.core.game3.bag')
 local session={version=version,money=10000,bag=Bag.new()}
 Map.current='g3:CELADON_CITY_DEPARTMENT_STORE_4F'
 Shop.show({session=session,items={13,95}})
 assert(#Shop._items==4 and Shop._items[3]==1001 and Shop._items[4]==1002)
 Map.current='g3:VIRIDIAN_CITY_MART';Shop.show({session=session,items={13}});assert(#Shop._items==1)
 local calls={}
 package.loaded['src.core.game3.field']={_session=session,lock=function(tag)calls.lock=tag end,unlock=function(tag)assert(tag==calls.lock);calls.unlocked=true end}
 package.loaded['src.core.game3.objects']={freeze=function(id)calls.frozen=id end,unfreeze=function(id)assert(id==calls.frozen);calls.unfrozen=true end,facePlayer=function()end}
 Map.current='g3:ROUTE104_PRETTY_PETAL_FLOWER_SHOP'
 local native=0;local function nextTalk()native=native+1 end
 hooks['world.talk'](nextTalk,game,{localId=2,def={}});hooks['world.talk'](nextTalk,game,{localId=3,def={}})
 assert(native==2,'reward NPCs intercepted')
 hooks['world.talk'](nextTalk,game,{localId=1,def={}})
 assert(#Shop._items==2 and Shop._items[1]==1001 and Shop._items[2]==1002)
 assert(Shop._session==session and calls.frozen==1)
 Shop.close();assert(calls.unlocked and calls.unfrozen,'shop leaves field locked')
 if version=='ruby' or version=='sapphire' or version=='emerald' then
  local Rse=assert(loadfile('src/ui/game3/rse/shop_menu.lua'))()
  for _,id in ipairs({1001,1002})do
   local before=session.money
   Shop._martType=Rse.MART_NORMAL;Shop.state='confirm';Shop.yesCursor=1
   Shop._itemId=id;Shop.qty=1;Shop._totalCost=2100
   Shop._nativeShopPolicy={plain=function(key)return key end}
   Rse.handleInput(Shop,{wasPressed=function(_,key)return key=='a'end})
   assert(session.money==before-2100 and Bag.get(session.bag,id)==1,'native Hoenn purchase failed')
  end
 end
 for id,target in pairs({TART_APPLE=905,SWEET_APPLE=906})do
  assert(Items.fieldUseKind(id)=='evo');assert(Items.pocketOf(id)=='ITEMS')
  assert(Bag.add(session.bag,id,2));assert(Bag.remove(session.bag,id,1))
 end
 if version=='firered' or version=='leafgreen' then
  Map.current='g3:CELADON_CITY_DEPARTMENT_STORE_4F';Shop.show({session=session,items={95}})
  for i=2,3 do
   local before=session.money
   Shop.mode='buy';Shop.cursor=i
   local a={wasPressed=function(_,key)return key=='a'end}
   Shop.handleInput(a);assert(Shop.mode=='buy_qty')
   Shop.handleInput(a);assert(Shop.mode=='buy_confirm')
   Shop.handleInput(a);assert(session.money==before-2100,'native purchase did not debit money')
  end
 end
 -- A fresh item ROM pack must preserve ids and metadata used by saved bags.
 Items.installPack({items={[13]={name='POTION',pocket='ITEMS',price=300}}})
 assert(Items.toNumericId('TART_APPLE')==1001 and Items.info(1002).price==2100)
 local Evos=assert(load(read('dex/src/gen3evolutions.lua')))()
 local rows=Evos.build(function(path)return read('dex/'..path)end,function(n)return n>386 and n+64 or n end,Items.toNumericId)
 local found={};for _,row in ipairs(rows[904])do if row.target==905 or row.target==906 then found[row.target]=row end end
 assert(found[905].method==7 and found[905].param==1001)
 assert(found[906].method==7 and found[906].param==1002)
 local P=require('src.core.game3.pokemon')
 P._names={[904]='APPLIN',[905]='FLAPPLE',[906]='APPLETUN',[1075]='DIPPLIN'}
 P._byName={APPLIN=904,FLAPPLE=905,APPLETUN=906,DIPPLIN=1075}
 P._evolutions=rows;P._speciesMeta={};P._battleMoves={}
 local Evolution=require('src.core.game3.evolution')
 for item,target in pairs({[1001]=905,[1002]=906})do
  assert(Evolution.itemTarget({species=904},item,session)==target,'native item target / pre-National gate')
  assert(not Evolution.itemTarget({species=1075},item,session),'Dipplin must not evolve with apples')
  assert(not Evolution.itemTarget({species=904,item=195},item,session),'Everstone must refuse')
 end
end
assert(#originalStock==1,'native stock was mutated')
print('PASS '..version..': apple registry, shop integration, item evolution and wrong-target refusal')
