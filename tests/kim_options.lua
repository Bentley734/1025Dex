local root,kimRoot=arg[1],arg[2]
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local checks=0;local function check(v,m)checks=checks+1;assert(v,m)end
local schema=assert(load(read(root..'/sprites/options.lua')))()
local choices={};for _,row in ipairs(schema)do if row.key=='enemy_sprite_style'or row.key=='player_sprite_style'then choices[#choices+1]=row end end
check(#choices==2 and choices[1].choices[6][1]=='KIM' and choices[1].choices[6][2]==5,'KIM appended without changing saved indices')
local migrate=assert(load(read(root..'/compat/sprite_options.lua')))()
local values={player_sprite_style=5,enemy_sprite_style=4};migrate(values);check(values.player_sprite_style==5 and values.enemy_sprite_style==4,'migration retains KIM and independent enemy setting')
local installed=false;local assetsOpened=false;local received
local Manager={buildOptionRows=function(_,_,rows)
 received=rows;local out={};for _,row in ipairs(rows)do out[#out+1]={id=row.key,label=row.label}end;out[#out+1]={id='__reset'};return out
end}
local Rows={build=function()return {{id='native'},{id='1025dex:asset_manager',label='1025DEX ASSETS'}}end}
local mod={id='1025dex',exports={assetManager={open=function(game)assetsOpened=game~=nil end}},find=function()return installed and {exports={getDexSpriteSheet=function()end}}or nil end,hooks={wrap=function()end}}
local modules={['src.core.GameVersion']={generation=function()return 3 end},['src.mods.ManagerState']=Manager,['src.ui.game3.option_rows']=Rows}
local env=setmetatable({require=function(name)return assert(modules[name],name)end},{__index=_G})
assert(load(read(root..'/compat/settings_menu.lua'),'settings','t',env))()(mod)
local top=Rows.build({game={}})
check(#top==2 and top[2].label=='1025DEX','assets no longer appear beside the 1025DEX submenu')
for _,present in ipairs({false,true})do
 installed=present;local mgr={game={}}
 local rows=Manager.buildOptionRows(mgr,{id='1025dex'},choices)
 check(#received[1].choices==(present and 6 or 5),'KIM shown only with an active sprite provider')
 check(#choices[1].choices==6,'dynamic filtering does not mutate schema')
 check(rows[#rows-1].label=='1025DEX ASSETS','assets inside mod settings before RESET DEFAULTS')
 rows[#rows-1].activate();check(assetsOpened,'nested assets entry remains usable')
end
local source=read(root..'/sprites/main.lua');local DATA={}
local envStyle=setmetatable({DATA=DATA,mod=mod,opt=function(key,default)return values[key]or default end},{__index=_G})
local a=assert(source:find('  function DATA.kimPeer()',1,true));local b=assert(source:find('  function DATA.bwPeer()',a,true))
assert(load(source:sub(a,b-1),'styles','t',envStyle))()
installed=true;values.player_sprite_style=5;check(DATA.styleFor(true,true)==5 and DATA.spriteStyle()==5,'KIM selectable for player and menu pictures')
values.enemy_sprite_style=5;check(DATA.styleFor(false,true)==5,'KIM selectable independently for enemy')
installed=false;check(DATA.styleFor(false,true)==3 and DATA.spriteStyle()==3,'missing/disabled KIM safely falls back without erasing selection')
local km={exports={},read=function(_,p)return read(kimRoot..'/'..p)end,find=function()return {exports={spriteStyleFor=function(side)return side=='front'and 5 or 3 end}}end}
assert(load(read(kimRoot..'/lib/dex_sprite_provider.lua')))()(km)
check(km._kimDexSelected('front',true) and not km._kimDexSelected('back',true),'KIM respects independent sprite selections')
local patches={};love={filesystem={newFileData=function(s)return s end},image={newImageData=function(a,b)
 if type(a)=='string'then return {}end
 return {getDimensions=function()return a,b end,paste=function(_,_,x,y,sx,sy,w,h)patches[#patches+1]={x,y,sx,sy,w,h}end}
end}}
km._kimAssetProvider={read=function()return 'png' end}
local data,record=km.exports.getDexSpriteSheet('BULBASAUR','front',false)
check(data~=nil and record.count==26 and #patches==26,'KIM supplies every HD animation frame')
check(patches[7][3]==0 and patches[7][4]==record.height,'multirow atlas unpacked in correct frame order')
check(record.timing.total_ticks==78,'original animation timing retained')
patches={};check(km.exports.getDexSpriteSheet('CYNDAQUIL','front',false,155)~=nil,'National Dex names resolve numeric KIM records')
check(km.exports.getDexSpriteSheet('UNSUPPORTED_FORM','front',false)==nil,'unsupported art uses normal fallback')
check(read(root..'/encounters/randomizer.lua'):find("label='RANDOMIZER'",1,true)~=nil,'randomizer renamed without changing option key')
print('PASS '..checks..' KIM source, conditional choices, nested assets, animation and persistence checks')
