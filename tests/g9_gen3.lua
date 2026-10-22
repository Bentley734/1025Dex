local api=dofile('tests/static_sprites.lua')
local data=dofile('sprites/data/dbk_data.lua')
local function readData(path)return dofile('sprites/'..path)end
local provider=dofile('sprites/g9_provider.lua')({},readData,data)
api.env.DATA.g9=provider;api.env.spriteBakes={}
local n=0;local function check(v,m)n=n+1;assert(v,m)end
for _,folder in ipairs({'front','front_shiny','back','back_shiny'})do
 for _,stem in ipairs({'BULBASAUR','PIKACHU','CHARIZARD','WAILORD','RAYQUAZA','NOIVERN','UNOWN_1'})do
  local rec=assert(provider.select(stem,folder));check(rec.cell.frames>0,'animated atlas source')
  local sheet=api.select('G9@'..rec.id,folder:match('^back')~=nil,folder:find('shiny')~=nil,6)
  check(sheet.g9Record and sheet.status=='local','style6 source bypasses missing old asset cache')
  check(sheet.g9Record.cell.fs==rec.cell.fs,'original frame geometry')
 end
end
check(provider.stem('DARMANITAN_ZEN')==nil,'unavailable form cannot alias imported Galar art')
check(provider.select('MEOWSTIC_female','front')~=nil,'female mapping')
check(provider.select('NOT_A_SPRITE','front')==nil,'missing art fallback')
local id=api.env.love.image.newImageData(120,40)
for frame=0,2 do for y=5,37 do for x=10,29 do id:setPixel(frame*40+x,y,1,0,0,1)end end end
local rec={variant='back',id='TEST',tuning={},cell={fs=40,frames=3,cx0=10,cx1=30,bfr=35,bfl=50}}
for gen=1,3 do
 api.env.GEN=gen
 local sheet,plan=api.bake({stem='TEST',back=true,style=6,g9Record=rec},id)
 check(#sheet.frames==3,'original frame count')
 check(sheet.contactBake.footY==50,'authored back foot row')
 check(sheet.contactBake.footX==32,'authored back body center')
 check(api.env.spriteBakes[sheet.frames[1]]==sheet.contactBake,'live image has exact HD bake')
end
local migrate=dofile('compat/sprite_options.lua');local options={enemy_sprite_style=6,player_sprite_style=6};migrate(options)
check(options.enemy_sprite_style==6 and options.player_sprite_style==6,'persist new style')
local rows=dofile('sprites/options.lua');check(rows[1].choices[7][2]==6 and rows[2].choices[7][2]==6,'independent side options')
print('PASS '..n..' G9 GEN3 source / four palettes / authored feet / live HD geometry assertions')

-- A late cached native picture must receive geometry even if baking finished first.
local f=assert(io.open('sprites/main.lua'));local source=f:read('*a');f:close()
local a=assert(source:find('    local function pendingPic(',1,true));local z=assert(source:find('    local function extendedSpecies(',a,true))
local image={setFilter=function()end,replacePixels=function()end};local contact={box={w=64,h=64},ox=0,oy=0,dw=64,dh=64}
local sheet={gen3FrameData={{}},gen3BattleLift=0,contactBake=contact}
local env=setmetatable({sheetKey=function()return 'key'end,sheets={key=sheet},DATA={},spriteBakes={},
 love={image={newImageData=function()return {}end},graphics={newImage=function()return image end}},frameIndex=function()return 1 end},{__index=_G})
local pending=assert(load(source:sub(a,z-1)..'return pendingPic','late native picture','t',env))()
local pic=assert(pending(false,false,'TEST',true,false,false));assert(env.spriteBakes[pic.image]==contact,'late native picture lost its HD geometry')
print('PASS late-created native Gen3 picture contact registration')
