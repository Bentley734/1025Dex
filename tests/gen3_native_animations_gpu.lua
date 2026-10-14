local root=assert(os.getenv('GEN3_ENGINE_ROOT'));local cache=assert(os.getenv('GEN3_CACHE_ROOT'));local output=assert(os.getenv('GEN3_GPU_OUTPUT'))
local function read(path)local f=io.open(path,'rb');if not f then return end;local s=f:read('*a');f:close();return s end
local function write(path,text)local f=assert(io.open(path,'wb'));f:write(text);f:close()end
function love.load()
 local ok,err=xpcall(function()
  package.path=root..'/?.lua;'..package.path
  require('src.core.GameVersion').set('firered')
  package.loaded['src.import.CacheFs']={readActive=function(path)return require('src.import.CacheBlob').decode(path,read(cache..'/firered/'..path))end,read=function(path)return require('src.import.CacheBlob').decode(path,read(cache..'/firered/'..path))end,readAt=function(path)return require('src.import.CacheBlob').decode(path,read(cache..'/'..path))end}
  require('src.core.game3.dataset').cache=function()return{read=function(_,path)return read(cache..'/firered/'..path)end}end
  local Anim=require('src.core.game3.battle.anim');Anim.reset{headless=false}
  local nativeScripts={};for _,id in ipairs({33,45,39})do nativeScripts[id]=Anim.scriptForMove(id)end
  local G=love.graphics;local canvas=G.newCanvas(240,160);local frames=0;local drew=false
  for _,reversed in ipairs({false,true})do
   for _,id in ipairs({585,504,594})do
    Anim.reset{headless=false}
    Anim.launchMove(id,{attackerSide=reversed and'enemy'or'player',targetSide=reversed and'player'or'enemy',attackerSpecies=1,targetSpecies=7})
    for frame=1,100 do
     Anim.update(1/60);G.setCanvas(canvas);G.clear(0,0,0,0);Anim.drawParticles();G.setCanvas()
     frames=frames+1
     local data=canvas:newImageData();local nonempty=false
     for y=0,159 do for x=0,239 do local r,g,b,a=data:getPixel(x,y);if a>0 then nonempty=true end end end
     if nonempty and not drew then write(output..'/modern-impact.png',data:encode('png'):getString());drew=true end
     if not Anim.busy()then break end
    end
    assert(not Anim.busy(),'animation did not finish')
   end
  end
  assert(drew,'Native modern fallback drew no particles')
  assert(Anim._pack.tags.IMPACT.image,'Native impact texture missing')
  for id,script in pairs(nativeScripts)do assert(Anim.scriptForMove(id)==script,'native script replaced')end
  local source=assert(read(root:gsub('/engine%-0385$','/1025Dex')..'/gen3-mechanics/type_badges.lua'))
  assert(loadstring(source))()()
  G.setCanvas(canvas);G.clear(0,0,0,0);require('src.ui.game3.summary_chrome').drawTypeBadge(18,30,30);require('src.ui.game3.pokedex_chrome').drawTypeBadge(18,90,30);G.setCanvas()
  write(output..'/fairy-badges.png',canvas:newImageData():encode('png'):getString())
  write(output..'/result.txt','PASS real LOVE GPU; Fairy summary/dex labels;  '..frames..' frames; modern impact texture loaded; native Tackle/Growl/Tail Whip scripts preserved\n')
 end,debug.traceback)
 if not ok then write(output..'/result.txt','FAIL '..tostring(err))end
 love.event.quit(ok and 0 or 1)
end
