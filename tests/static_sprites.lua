-- Execute the production source selection, scan, layout, bake and cache identity.
local checks=0
local function eq(a,b,why)checks=checks+1;assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b))end
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local source=read('sprites/main.lua')
local function block(start,ending)
  local a=assert(source:find(start,1,true));local z=assert(source:find(ending,a+1,true))
  return source:sub(a,z-1)
end
local data=dofile('sprites/data/static_data.lua');data.metrics=dofile('sprites/data/static_metrics.lua')
local style,mode,anchor=1,1,0
local actualLove=love
local unpack=unpack or table.unpack
local function imageData(w,h)
  local t={w=w,h=h,p={}}
  function t:getDimensions()return self.w,self.h end
  function t:getPixel(x,y)assert(x>=0 and y>=0 and x<self.w and y<self.h,'outside source');local p=self.p[y*self.w+x];if p then return unpack(p)end;return 0,0,0,0 end
  function t:setPixel(x,y,r,g,b,a)assert(x>=0 and y>=0 and x<self.w and y<self.h,'outside destination');self.p[y*self.w+x]={r,g,b,a}end
  return t
end
local L=actualLove or {image={newImageData=imageData}}
local env=setmetatable({DATA={static=data,spriteStyle=function()return style end,styleFor=function()return style end},GEN=3,
  FRONT_SCALE=2,BACK_SCALE=3,ANCHOR_FEET=0,ANCHOR_PACK=1,GEN3_SPRITE_LIFT=0,
  boxFor=function(_,box)return box or {w=64,h=64}end,
  round=function(n)return math.floor(n+.5)end,
  spriteSizeMode=function()return mode end,spriteAnchor=function()return anchor end,
  floatLift=function()return 0 end,
  gen3BattleLiftByImage={},ourFrames={},love={image=L.image,graphics={newImage=function(out)return {data=out,setFilter=function()end}end}},
  localFolder=function(back,shiny)return (back and 'back' or 'front')..(shiny and '_shiny' or '')end,
  mod={info=function(_,path)local f=io.open('sprites/'..path,'rb');if f then f:close();return {type='file'}end end},
  frameCounter=0,RECHECK_FRAMES=900,debugOn=function()return false end,
  diag={stats={missing=0}},diagPush=function()end,
},{__index=_G})
local chunks=block('  local function sheetKey(', '  -- The pic box')
  ..block('  local function beginBuild(', '  -- The crystal film\'s per-pixel colour')
  ..block('  local function buildOneFrame(', '  -- One bounded step.')
  ..block('  local function sheetStart(', '  local function evictIfNeeded(')
local api=assert(load(chunks..'\nreturn {key=sheetKey,start=sheetStart,begin=beginBuild,scan=scanChunk,setup=setupFrames,frame=buildOneFrame}','production sprite bake','t',env))()
env.FRONT_BOX={h=56}
env.opt=function(_,default)if mode==nil then return default end;return mode end
env.spriteSizeMode=assert(load(block('  local LEGACY_SIZE_REF','  -- Round half up')..'return spriteSizeMode','production size option','t',env))()
local function selectSheet(stem,back,shiny,override)
  local s={stem=stem,back=back,shiny=shiny,style=override or style,status='new'}
  api.start(s);return s
end
for _,back in ipairs({false,true})do for _,shiny in ipairs({false,true})do
  local s=selectSheet('CACTURNE',back,shiny)
  eq(s.static,true,'static side/palette');eq(s.status,'local','source exists')
  eq(s.rel,'assets/static/'..env.localFolder(back,shiny)..'/CACTURNE.png','correct source')
end end
eq(selectSheet('BASCULEGION_1',false,false).sourceStem,'BASCULEGION_female','form alias')
eq(selectSheet('BLASTOISE_2',false,false).static,false,'missing Gmax keeps matching animated art')
local k1=api.key(false,false,'CACTURNE');style=0
eq(selectSheet('CACTURNE',false,false).static,false,'animated option');eq(api.key(false,false,'CACTURNE')~=k1,true,'separate style caches');style=1
eq(api.key(false,true,'CACTURNE')~=k1,true,'separate shiny caches')
eq(api.key(true,false,'CACTURNE')~=k1,true,'separate back caches')
eq(selectSheet('CACTURNE_female',false,true).static,true,'female shiny art')
local function bake(s,id)
  assert(api.begin(s,id));local b=s.build
  while b.row<b.H do api.scan(b,6)end
  assert(api.setup(b));local plan={ox=b.ox,oy=b.oy,dw=b.dw,dh=b.dh,count=b.count,scale=b.scale}
  while b.frame<b.count do api.frame(s)end
  return s,plan
end
-- Synthetic identical logical artwork encoded at 2x/3x must render identically.
for _,selection in ipairs({'unset',0,1})do
if selection=='unset' then mode=nil else mode=selection end
for _,density in ipairs({1,2,3})do
  local n=96*density;local id=L.image.newImageData(n,n)
  for y=20*density,80*density-1 do for x=30*density,66*density-1 do id:setPixel(x,y,1,0,0,1)end end
  local s,plan=bake({stem='TEST',static=true},id)
  eq(plan.dw,36,'density-independent BIG width');eq(plan.dh,60,'density-independent BIG height')
  eq(plan.oy+plan.dh,64,'same ground line');eq(s.gen3BattleLift,0,'no height-dependent lift')
  eq(#s.frames,1,'static one frame')
end
end
mode=1
-- Animated union bounds keep the same transform across changing frame outlines.
local id=L.image.newImageData(120,40)
for y=5,38 do for x=9,29 do id:setPixel(x,y,0,1,0,1)end end
for y=0,38 do for x=42,70 do id:setPixel(x,y,0,1,0,1)end end
for y=7,38 do for x=88,111 do id:setPixel(x,y,0,1,0,1)end end
local s,p=bake({stem='TEST'},id)
eq(p.count,3,'animation frames');eq(#s.frames,3,'all frames baked')
eq(p.oy+p.dh,64,'union ground');eq(s.gen3BattleLift,0,'animation same baseline')
-- Execute the production cache reset, including mutable images kept by menus.
local proxy={data={1,2,3},lastFrame=3}
local old={status='ready',style=0,frames={1,2,3},gen3FrameData={1,2,3},retryAt=9999,proxies={menu=proxy}}
env.sheets={old=old};env.readyCount=1;env.lastSizeSig='old'
env.sizeSig=function()return 'new' end
local ca=assert(source:find('    local sig = sizeSig()',1,true))
local cz=assert(source:find('\n    for _, sheet in pairs(sheets) do\n      if sheet.status == "local"',ca,true))
assert(load(source:sub(ca,cz-1),'production cache reset','t',env))()
eq(old.style,1,'cached menu requeued to selected style');eq(old.retryAt,nil,'missing retry cleared')
eq(old.gen3FrameData,nil,'old animated pixels discarded');eq(#proxy.data,0,'old proxy frames cleared')
eq(proxy.lastFrame,nil,'cached image will refresh');eq(env.readyCount,0,'ready budget reset')
-- Option schema must expose the identical choice to the manager and runtime.
local options=dofile('sprites/options.lua');local row
for _,r in ipairs(options)do if r.key=='sprite_style'then row=r end end
eq(row.default,3,'EE animated default');eq(row.choices[2][2],1,'static selectable')
print(('PASS: %d sprite assertions; real inventory lookup, palettes, aliases, fallback, style caches, density and union-frame placement.'):format(checks))
return {key=api.key,bake=bake,select=selectSheet,env=env,layout=api.setup}
