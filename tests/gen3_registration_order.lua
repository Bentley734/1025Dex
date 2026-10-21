-- Native slot ownership must be assigned before compatibility tables are filled.
local callbacks,reloads={},{}
local P={_moveNames={[33]='TACKLE',[332]='AERIAL ACE'},onReload=function(fn)reloads[#reloads+1]=fn end}
local Moves={get=function()return{effect=1}end,constName=function(n)return n==332 and'AERIAL_ACE'or'TACKLE'end,
 numForName=function(id)return id=='AERIAL_ACE'and 332 or id=='TACKLE'and 33 end}
package.loaded['src.core.game3.pokemon']=P
package.loaded['src.core.game3.battle.moves']=Moves
local rows={AERIAL_ACE={id='AERIAL_ACE',index=332},TACKLE={id='TACKLE',index=33}}
local writes={}
local registry={get=function(_,id)return rows[id]end}
for _,name in ipairs({'register','patch','override'})do
 registry[name]=function(_,id,row)rows[id]=row;writes[#writes+1]={method=name,id=id,row=row}end
end
registry.remove=function(_,id)rows[id]=nil end
local modern={AERIALACE={moveId=332,name='Aerial Ace',type='FLYING',pp=20},
 TACKLE={moveId=33,name='Tackle',type='NORMAL',pp=35},
 ACCELEROCK={moveId=709,name='Accelerock',type='ROCK',pp=20}}
local types,pokemonRows={},{}
local pokemonRegistry={}
for _,method in ipairs({'register','patch','override'})do pokemonRegistry[method]=function(_,id,row)pokemonRows[id]=row end end
local mod={exports={},content={moves=registry,pokemon=pokemonRegistry,type_chart={
 get=function(_,id)return types[id]end,register=function(_,id,row)types[id]=row end}},
 events={on=function(_,id,fn)callbacks[id]=fn end}}
function mod:read(path)
 assert(path=='src/api.lua')
 return 'return function()end'
end
mod.exports.listMoves=function()return{'AERIALACE','TACKLE','ACCELEROCK'}end
mod.exports.moveById=function(id)return modern[id]end
local byId=assert(loadfile('dex/src/gen3prepare.lua'))()(mod)
assert(byId.AERIALACE==332 and byId.ACCELEROCK==709)
assert(rows.AERIAL_ACE and not rows.AERIALACE,'Native move acquired duplicate alias registration')
assert(writes[1].method=='patch'and writes[1].id=='AERIAL_ACE'and writes[1].row.id=='AERIAL_ACE')
assert(registry:get('AERIALACE')==rows.AERIAL_ACE,'Downstream modern alias lookup failed')
assert(P._moveNames[709]==nil,'Move name table changed before native registry commit')
reloads[1]();assert(P._moveNames[709]==nil,'Pre-commit reload claimed native move slot')
assert(Moves.numForName('AERIALACE')==332 and Moves.numForName('ACCELEROCK')==709)
callbacks['mods.loaded']();assert(P._moveNames[709]=='Accelerock')
P._moveNames[709]=nil;reloads[1]();assert(P._moveNames[709]=='Accelerock','Post-commit reload lost modern identity')
local supplied={id='AERIALACE',power=90}
registry:patch('AERIALACE',supplied)
assert(supplied.id=='AERIALACE','Caller record mutated')
assert(rows.AERIAL_ACE.id=='AERIAL_ACE'and rows.AERIAL_ACE.power==90)
assert(types.FAIRY.index==18 and types.FAIRY.category=='special')
local learned={learnset={{level=12,move='AERIALACE'}},tmhm={'AERIALACE','ACCELEROCK'}}
pokemonRegistry:register('FIXTURE',learned)
assert(pokemonRows.FIXTURE.learnset[1].move=='AERIAL_ACE'and pokemonRows.FIXTURE.tmhm[1]=='AERIAL_ACE')
assert(pokemonRows.FIXTURE.tmhm[2]=='ACCELEROCK'and learned.learnset[1].move=='AERIALACE',
 'Learnset alias conversion changed modern identity or caller record')
print('PASS Gen3 native move identity reuse, modern lookup, immutable records and commit-gated reload')

local events,itemRows={},{}
package.loaded['src.core.GameVersion']={generation=function()return 3 end}
local Items={_byId={},_byName={}}
function Items.installPack()Items._byId={};Items._byName={}end
function Items.ensureLoaded()end
function Items.toNumericId(id)return tonumber(id)or Items._byName[id]end
package.loaded['src.core.game3.items_data']=Items
local Evolution={itemTarget=function(_,item)return item end}
package.loaded['src.core.game3.evolution']=Evolution
package.loaded['src.ui.game3.shop_menu']={show=function(opts)return opts end}
package.loaded['src.core.game3.map']={current='OTHER'}
local itemRegistry={get=function(_,id)return itemRows[id]end}
function itemRegistry:register(id,row)itemRows[id]=row end
itemRegistry.override=itemRegistry.register
local itemMod={exports={},content={items=itemRegistry},hooks={wrap=function()end},
 events={on=function(_,name,fn)assert(name=='mods.loaded');events[#events+1]=fn end}}
assert(loadfile('apples.lua'))()(itemMod)
assert(loadfile('compat/national_gen3.lua'))()(itemMod)
assert(Items._byId[1001]==nil and Items._byId[1002]==nil and Items._byId[913]==nil,
 'Evolution item compatibility wrote native slots before registration')
Items.installPack()
assert(Items._byId[1002]==nil,'Pre-commit pack reload claimed native slots')
for _,fn in ipairs(events)do fn()end
assert(Items._byId[1001].id=='TART_APPLE'and Items._byId[1002].id=='SWEET_APPLE')
assert(Items._byId[913].id=='AUSPICIOUS_ARMOR')
assert(Items.toNumericId('SWEET_APPLE')==1002 and Items.toNumericId('TART_APPLE')==1001)
Items.installPack()
assert(Items._byId[1002].price==2100 and Items._byId[913].id=='AUSPICIOUS_ARMOR',
 'Post-commit reload lost fixed saved item identities')
assert(Evolution.itemTarget({},910)==1002 and Evolution.itemTarget({},911)==1001,
 'National apple compatibility IDs changed')
print('PASS Gen3 item commit lifecycle, pack reload, saved apple IDs and National item aliases')
