local root=assert(os.getenv('DEX_FIX_SOURCE')):gsub('\\','/')
local kim=assert(os.getenv('KIM_FIX_SOURCE')):gsub('\\','/')
local out=assert(os.getenv('MENU_FIX_OUTPUT')):gsub('\\','/')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function write(s)local f=assert(io.open(out..'/kim-result.txt','wb'));f:write(s);f:close()end
function love.load()
 local ok,err=xpcall(function()
  local checks=0;local function check(v,m)checks=checks+1;assert(v,m)end
  local records=assert(loadstring(read(kim..'/data/hd_pokemon_sprites.lua')))()
  local mod={exports={},read=function(_,p)return read(kim..'/'..p)end}
  mod._kimAssetProvider={read=function(path)
   local record
   for _,side in ipairs({'front','back'})do for _,color in ipairs({'normal','shiny'})do
    local r=records.BULBASAUR[side][color].default;if r.image==path then record=r end
   end end
   if not record then return nil end
   local w,h,count,cols=record.width,record.height,record.frames,record.columns
   local data=love.image.newImageData(w*cols,h*math.ceil(count/cols))
   for i=0,count-1 do data:setPixel((i%cols)*w,math.floor(i/cols)*h,(i+1)/count,.25,.75,1)end
   return data:encode('png'):getString()
  end}
  assert(loadstring(read(kim..'/lib/dex_sprite_provider.lua')))()(mod)
  for _,side in ipairs({'front','back'})do for _,shiny in ipairs({false,true})do
   local data,record=mod.exports.getDexSpriteSheet('BULBASAUR',side,shiny)
   check(data~=nil,'HD sheet supplied')
   local w,h=data:getDimensions();check(w==record.width*record.count and h==record.height,'rectangular frames repacked horizontally')
   for frame=0,record.count-1 do
    local r,g,b,a=data:getPixel(frame*record.width,0)
    check(math.abs(r-(frame+1)/record.count)<.005 and a==1,'frame pixel order preserved across atlas rows')
   end
   local source=read(root..'/sprites/main.lua')
   local a=assert(source:find('  local function beginBuild(',1,true));local b=assert(source:find("  -- The crystal film's per-pixel colour",a,true))
   local env=setmetatable({boxFor=function()return {w=64,h=64}end,SHADOW={on=function()return false end}},{__index=_G})
   local start=assert(loadstring(source:sub(a,b-1)..'return beginBuild'));setfenv(start,env)
   local sheet={style=5,kimRecord=record};check(start()(sheet,data),'KIM sheet enters production sprite bake')
   check(sheet.build.count==record.count and sheet.build.fw==record.width,'baker uses KIM metadata instead of square-frame estimation')
  end end
  check(mod.exports.getDexSpriteSheet('UNKNOWN','front',false)==nil,'missing art does not replace existing fallback')
  write('PASS '..checks..' real PNG/GPU KIM palette/side/frame order and production bake checks\n')
 end,debug.traceback)
 if not ok then write('FAIL '..tostring(err))end
 love.event.quit(ok and 0 or 1)
end
