-- Real LOVE GPU probe. Run as main.lua with tests/gen3_native_animations_gpu.lua environment variables.
local root=assert(os.getenv('GEN3_ENGINE_ROOT'));local cache=assert(os.getenv('GEN3_CACHE_ROOT'));local output=assert(os.getenv('GEN3_GPU_OUTPUT'))
local function read(path)local f=io.open(path,'rb');if not f then return end;local s=f:read('*a');f:close();return s end
local function write(path,text)local f=assert(io.open(path,'wb'));f:write(text);f:close()end
function love.load()
 local ok,err=xpcall(function()
  package.path=root..'/?.lua;'..package.path
  require('src.core.GameVersion').set('firered')
  package.loaded['src.import.CacheFs']={readActive=function(path)return require('src.import.CacheBlob').decode(path,read(cache..'/firered/'..path))end,read=function(path)return require('src.import.CacheBlob').decode(path,read(cache..'/firered/'..path))end,readAt=function(path)return require('src.import.CacheBlob').decode(path,read(cache..'/'..path))end}
  require('src.core.game3.dataset').cache=function()return{read=function(_,path)return require('src.import.CacheBlob').decode(path,read(cache..'/firered/'..path))end}end
  local P=require('src.core.game3.pokemon');local cv={read=function(_,path)return require('src.import.CacheBlob').decode(path,read(cache..'/firered/'..path))end};P.install(cv)
  require('src.core.game3.battle.moves').loadRomPack(cv)
  local battleMove,moveName=P.battleMove,P.moveName
  P.battleMove=function(id)if id==412 then return{type=12,pp=10,power=90,accuracy=100,category='special'}end;return battleMove(id)end
  P.moveName=function(id)if id==412 then return 'Energy Ball'end;return moveName(id)end
  local mod={exports={listMoves=function()return{'ENERGYBALL'}end,moveById=function()return{moveId=412,name='Energy Ball'}end,statsByDex=function()end},log={info=function()end}}
  local Chrome=require('src.ui.game3.tm_case_chrome');local drawDisc=Chrome.drawDisc;local checked=false
  Chrome.drawDisc=function(kind,x,y,hm,...)assert(x==24 and y==31,'Extended disc off screen');checked=true;return drawDisc(kind,x,y,hm,...)end
  local source=assert(read(root:gsub('/engine%-0385$','/1025Dex')..'/move_machines.lua'))
  assert(loadstring(source))()(mod)
  local Bag=require('src.core.game3.bag');local bag=Bag.new();assert(Bag.add(bag,'TM1412',1))
  local Case=require('src.ui.game3.tm_case');Case.show({bag=bag},bag)
  local G=love.graphics;local canvas=G.newCanvas(240,160)
  G.setCanvas(canvas);G.clear(0,0,0,0);Case.draw();G.setCanvas()
  assert(checked,'Disc never rendered')
  assert(require('src.ui.game3.bag_chrome').iconImage('TM1412'),'Expanded TM icon missing')
  write(output..'/tm-case.png',canvas:newImageData():encode('png'):getString())
  write(output..'/result.txt','PASS real LOVE GPU: native TM Case, extended label and move details, disc inside rack, native item icon\n')
 end,debug.traceback)
 if not ok then write(output..'/result.txt','FAIL '..tostring(err))end
 love.event.quit(ok and 0 or 1)
end
