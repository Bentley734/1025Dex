local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local source=read('compat/settings_menu.lua')
for generation=1,3 do
 local hooks,opened={},0
 local manager={byId={['1025dex']={id='1025dex'}},openOptions=function(_,entry)check(entry.id=='1025dex','selected correct mod');opened=opened+1 end}
 local rows={build=function()return {{id='native'},{id='1025dex:asset_manager',label='1025DEX ASSETS'}}end}
 local game={stack={push=function(_,m)check(m==manager,'legacy native settings pushed')end}}
 local view={show=function(opts)check(opts.game==game,'native game passed to manager')end,_mgr=manager}
 local modules={['src.core.GameVersion']={generation=function()return generation end},
 ['src.ui.game3.option_rows']=rows,['src.ui.game3.mod_manager']=view,['src.mods.ManagerState']={new=function(g)check(g==game,'legacy game passed');return manager end}}
 local env=setmetatable({require=function(n)return assert(modules[n],n)end},{__index=_G})
 assert(load(source,'settings','t',env))()({id='1025dex',hooks={wrap=function(_,n,f)hooks[n]=f end}})
 local out=generation==3 and rows.build({game=game}) or hooks['ui.options.rows'](function()return rows.build()end,game,{})
 check(#out==3 and out[3].label=='1025DEX','both dex settings and assets stay visible')
 out[3].activate(generation==3 and {game=game} or game)
 check(opened==1,'settings shortcut opens correct options')
end
-- Execute the actual entry-point preamble with no legacy screens registry.
local main=read('main.lua');local preamble=assert(main:match('^(.-)  local schema, seen'))
local started=0
local env=setmetatable({require=function()return {generation=function()return 3 end}end},{__index=_G})
assert(load(preamble..'end','startup','t',env))()({cache={},ui={},content={},read=function(_,p)
 check(p=='compat/assets.lua','asset bridge requested');return 'return function() _G.dexAssetsStarted=true end'
end})
check(_G.dexAssetsStarted,'Gen3 assets initialize without legacy screens');_G.dexAssetsStarted=nil
print('PASS '..checks..' settings shortcuts across generations and native asset startup checks')
