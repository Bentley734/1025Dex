local dex=assert(os.getenv('DEX_SOURCE')):gsub('\\','/')
local kim=assert(os.getenv('KIM_SOURCE')):gsub('\\','/')
local out=assert(os.getenv('MENU_FIX_OUTPUT')):gsub('\\','/')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function write(p,s)local f=assert(io.open(out..'/'..p,'wb'));f:write(s);f:close()end
local function compile(s,env)local f=assert(loadstring(s));if env then setfenv(f,env)end;return f()end
function love.load()
 local ok,err=xpcall(function()
  local G=love.graphics;local checks=0
  local function check(v,m)checks=checks+1;assert(v,m)end
  local center=compile(read(dex..'/sprites/preview_center.lua'))
  local function bounds(data)
   local w,h=data:getDimensions();local l,t,r,b=w,h,-1,-1
   for y=0,h-1 do for x=0,w-1 do local _,_,_,a=data:getPixel(x,y);if a>0 then l=math.min(l,x);r=math.max(r,x);t=math.min(t,y);b=math.max(b,y)end end end
   return l,t,r,b
  end
  for _,size in ipairs({{20,16},{31,27},{63,63}})do
   local data=love.image.newImageData(64,64)
   for y=64-size[2],63 do for x=1,size[1]do data:setPixel(x,y,.1,.8,.3,1)end end
   local before=data:getString();local centered=center(data)
   local l,t,r,b=bounds(centered)
   check(math.abs((l+r+1)/2-32)<=.5 and math.abs((t+b+1)/2-32)<=.5,'visible sprite centred on both axes')
   check(r-l+1==size[1]and b-t+1==size[2],'no stretching or lost pixels')
   check(data:getString()==before,'battle frame untouched')
   -- Run the actual cached-provider path for both field and battle callers.
   for _,battle in ipairs({false,true})do
    local sheet={gen3FrameData={data,data,__spriteStyle='ee'}}
    local source=read(dex..'/sprites/main.lua')
    local fn=assert(source:match('(    local function pendingPic.-)    local function extendedSpecies'))
    local env=setmetatable({sheets={key=sheet},sheetKey=function()return 'key'end,DATA={centerPreview=center},
     BACK_BOX_GEN3={},FRONT_BOX_GEN3={},frameIndex=function()return 1 end},{__index=_G})
    local pending=compile(fn..'return pendingPic',env)
    local pic=pending(false,false,'Bulbasaur',battle,false,false)
    check(pic==pending(false,false,'Bulbasaur',battle,false,false),'cached image identity retained')
    check(sheet.proxies.gen3.center==not battle,'only field preview is centred')
    check(sheet.proxies.gen3.data.__spriteStyle=='ee'and #sheet.proxies.gen3.data==2,'animation metadata and frames retained')
    local frame=sheet.proxies.gen3.data[1];local _,y0,_,y1=bounds(frame)
    check(battle and y1==63 or not battle and math.abs((y0+y1+1)/2-32)<=.5,'correct field centre/battle baseline')
   end
  end
  local data=love.image.newImageData(128,64)
  for f=0,1 do for y=46,61 do for x=8,27 do data:setPixel(f*64+x,y,.2,.7,.3,1)end end end
  local source={image=G.newImage(data),iw=128,ih=64,width=64,height=64,columns=2,count=2}
  local visible=compile(read(kim..'/lib/preview_bounds.lua'))
  local vx,vy=visible(source)
  check(18+vx==32 and 54+vy==32,'HD visible bounds centred, not transparent canvas padding')
  local old=G.newCanvas;G.newCanvas=function()error('bounds should be cached')end
  local xx,yy=visible(source);G.newCanvas=old;check(xx==vx and yy==vy,'no repeated atlas readback')
  local code=read(kim..'/lib/gen3_frlg.lua')
  local fn=assert(code:match('(  local function drawHdPreviewEntry.-)  %-%- Public final%-window'))
  local env=setmetatable({sourceFor=function()return source end,sourceQuad=function()return G.newQuad(0,0,64,64,128,64)end,
   frameFor=function()return 1 end,centerVisible=visible},{__index=_G})
  local draw=compile(fn..'return drawHdPreviewEntry',env)
  local target=G.newCanvas(256,256,{dpiscale=1});G.setCanvas(target);G.origin();G.clear(0,0,0,0)
  check(draw({rec={displayScale=1},x=16,y=16,w=64,h=64,centerVisible=true},0,0,2,2),'production KIM script preview renders')
  G.setCanvas();local l,t,r,b=bounds(target:newImageData())
  check(math.abs((l+r+1)/2-96)<=1 and math.abs((t+b+1)/2-96)<=1,'HD starter centre matches picture-box centre')
  write('starter-centered.png',target:newImageData():encode('png'):getString())
  write('starter-result.txt','PASS '..checks..' real GPU cached-provider, visible bounds, animation and battle-baseline checks\n')
 end,debug.traceback)
 if not ok then write('starter-result.txt','FAIL '..tostring(err))end
 love.event.quit(ok and 0 or 1)
end
