-- Executes the production Gen3 provider and animation clock with engine fixtures.
-- Run from the mod folder: texlua tests/shiny_animation.lua
local checks=0
local function eq(a,b,why)checks=checks+1;assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b))end
local f=assert(io.open('sprites/main.lua'));local source=f:read('*a');f:close()
local a=assert(source:find('  local function installGen3()',1,true))
local z=assert(source:find('  -- gen2 (Gold): BattleState:pic substitution',a,true))
local arm=source:sub(a,z-1)
local ca=assert(source:find('  local function frameIndex(count, frames)',1,true))
local cz=assert(source:find('\n  -- ---------------------------------------------------------------------------',ca,true))
local clock=source:sub(ca,cz-1)
local enabled,animated,tick=true,true,0
local sheets,images,lifts={},{},{ }
for _,back in ipairs({false,true})do for _,shiny in ipairs({false,true})do
 local key=(back and 'b' or 'f')..(shiny and 's' or 'n')..'/ARMAROUGE'
 images[key]={{key=key,frame=1},{key=key,frame=2}}
 lifts[images[key][1]]=shiny and 6 or 0;lifts[images[key][2]]=shiny and 6 or 0
end end
local pending=false
local function sheetKey(back,shiny,stem)return (back and 'b' or 'f')..(shiny and 's' or 'n')..'/'..stem end
local vanillaArgs
local Pokemon={frontPic=function(...)vanillaArgs={...};return {native='front'}end,
 backPic=function(...)vanillaArgs={...};return {native='back'}end,
 icon=function()end,national=function(s)return s==1 and 936 or 25 end}
local requests={}
local Ui={draw=function(fail)
 Pokemon.frontPic(1,0,false);Pokemon.backPic(1,0,false)
 if fail then error("scope fixture") end
 return "drawn",nil,7
end,battlerPic=function()return Pokemon.backPic(1,0,false)end}
package.loaded['src.core.game3.battle.ui']=Ui
local MonAnim={framePic=function(...)vanillaArgs={...};return {native='frame'}end}
package.loaded['src.core.game3.pokemon']=Pokemon
package.loaded['src.core.game3.mon_anim']=MonAnim
package.loaded['src.mods.Gen3Compat']={speciesName=function(s)return s==1 and 'ARMAROUGE' or 'UNKNOWN' end}
local env=setmetatable({GEN=0,DATA={eeFrame=function()return nil end,styleFor=function()return 3 end,playerView=function()return false,false end},sheets=sheets,gen3BattleLiftByImage=lifts,
 FRONT_BOX_GEN3={w=64,h=64},BACK_BOX_GEN3={w=64,h=64},GEN3_MAX_ART_H=64,
 mod={info=function()return nil end},sheetKey=sheetKey,
 now=function()return tick end,fpsValue=function()return 10 end,
 animateOn=function()return animated end,wantEnabled=function()return enabled end,
 resolveStem=function(name)return name=='ARMAROUGE' and name or nil end,
 getFramesFor=function(back,shiny,stem,tera,cloud,box,divisor,zoom,maxH,fill,scale,natural,battle,front,flip)
  requests[#requests+1]={back=back,battle=battle,front=front,flip=flip}
  local key=sheetKey(back,shiny,stem)
  if pending then sheets[key]=sheets[key] or {};return nil,true end
  return images[key],false
 end,
 love={image={newImageData=function()return {}end},graphics={newImage=function()return {setFilter=function()end}end}},
},{__index=_G})
local install=assert(load(clock..arm..'\nreturn installGen3','provider','t',env))()
eq(install(),true,'Gen3 installation')
for _,side in ipairs({'front','back'})do
 local provider=side=='front' and Pokemon.frontPic or Pokemon.backPic
 for _,shiny in ipairs({false,true})do
  tick=0;local one=provider(1,0,shiny,123)
  tick=.1;local two=provider(1,0,shiny,123)
  eq(one.image.frame,1,'first frame '..side);eq(two.image.frame,2,'next frame '..side)
  eq(one.image.key,(side=='back' and 'b' or 'f')..(shiny and 's' or 'n')..'/ARMAROUGE','correct palette/sheet')
  eq(one.__completeDexBattleLift,shiny and 6 or 0,'own sheet alignment')
  eq(two.__completeDexBattleLift,one.__completeDexBattleLift,'stable animated alignment')
 end
end
-- Native Gen3 draw requests must carry battle scope and player-only pose.
local originalView=env.DATA.playerView
env.DATA.playerView=function(back)return back and true or false,back and true or false end
local result,hole,last=Ui.draw()
eq(result,'drawn','scope preserves return');eq(hole,nil,'scope preserves nil return');eq(last,7,'scope preserves final return')
local enemy,player=requests[#requests-1],requests[#requests]
eq(enemy.battle,true,'enemy battle route');eq(enemy.front,false,'enemy orientation');eq(enemy.flip,false,'enemy not mirrored')
eq(player.battle,true,'player battle route');eq(player.front,true,'player front source');eq(player.flip,true,'player mirrored source')
eq(env.DATA.inGen3Battle,nil,'scope restored')
Pokemon.frontPic(1,0,false);eq(requests[#requests].battle,false,'menu route stays separate')
local ok=pcall(Ui.draw,true);eq(ok,false,'native error forwarded');eq(env.DATA.inGen3Battle,nil,'scope restored after error')
Ui.battlerPic();eq(requests[#requests].battle,true,'pre-draw snapshot battle route')
env.DATA.playerView=originalView
-- Native frame requests must keep the pack animation, not the ROM frame.
tick=0;eq(MonAnim.framePic(1,1,true).image.key,'fs/ARMAROUGE','native shiny frame override')
tick=.1;eq(MonAnim.framePic(1,1,true).image.frame,2,'native frame seam keeps animation clock')
eq(MonAnim.framePic(1,0,true).native,'frame','zero-frame native convention')
eq(MonAnim.framePic(2,1,true).native,'frame','unmanaged native frame')
-- Preview placeholders for the same species must not share normal/shiny caches.
pending=true
local normal=Pokemon.frontPic(1,0,false);local shiny=Pokemon.frontPic(1,0,true)
eq(normal~=shiny,true,'normal/shiny pending proxies isolated')
eq(Pokemon.frontPic(1,0,true),shiny,'shiny pending proxy reused')
local shinyBack=Pokemon.backPic(1,0,true);eq(shinyBack~=shiny,true,'front/back pending proxies isolated')
pending=false
sheets = {} -- pending fixture lifecycle ends; ready provider tests use fresh caches
env.sheets=sheets
animated=false;tick=.1;eq(Pokemon.frontPic(1,0,true).image.frame,1,'ANIMATE option respected');animated=true
-- Forward all native arguments if our provider is disabled or unmanaged.
enabled=false;Pokemon.frontPic(1,4,true,12345)
eq(vanillaArgs[2],4,'native form');eq(vanillaArgs[3],true,'native shiny');eq(vanillaArgs[4],12345,'native personality')
Pokemon.backPic(1,2,true);eq(vanillaArgs[3],true,'native back shiny')
local current=MonAnim.framePic;install();eq(MonAnim.framePic,current,'installation idempotent')
-- Execute the engine's actual late wrapper, which chooses a cached normal
-- PNG ahead of the animated provider. This reproduced the reported regression.
local cf=assert(io.open('tests/fixtures/gen3_compat_pics.lua'));local compat=cf:read('*a');cf:close()
local wa=assert(compat:find('local function wrapPics(P)',1,true))
local wz=assert(compat:find('\nreturn wrapPics',wa,true))
local wrappedModules={}
local compatEnv=setmetatable({wrappedModules=wrappedModules,
 spriteOverrides={front={[1]='normal.png'},back={[1]='normal-back.png'}},
 centredEntry=function(path)return {image={key=path,frame=1}}end,
 hookedEntry=function(side,species,form,entry)return entry end},{__index=_G})
local wrap=assert(load(compat:sub(wa,wz-1)..'\nreturn wrapPics','real Gen3Compat','t',compatEnv))()
enabled=true
wrap(Pokemon)
eq(Pokemon.frontPic(1,0,true).image.key,'normal.png','reproduce late compatibility override')
install();tick=0
eq(Pokemon.frontPic(1,0,true).image.key,'fs/ARMAROUGE','repair late shiny override')
tick=.1;eq(Pokemon.frontPic(1,0,true).image.frame,2,'repair late animation override')
eq(Pokemon.backPic(1,0,true).image.key,'bs/ARMAROUGE','repair late back override')
eq(Pokemon.frontSprite,Pokemon.frontPic,'front alias follows repair')
enabled=false;eq(Pokemon.frontPic(2,0,true).native,'front','late chain fallback does not recurse');enabled=true
-- A completed sheet cached by a screen must get a mutable Image too.
local key=sheetKey(false,true,'ARMAROUGE')
local pixelOne,pixelTwo={frame=1},{frame=2}
sheets[key]={gen3FrameData={pixelOne,pixelTwo},gen3BattleLift=6}
env.love.graphics.newImage=function()return {setFilter=function()end,
 replacePixels=function(self,data)self.frame=data.frame end}end
tick=0;local cached=Pokemon.frontPic(1,0,true)
eq(cached.image.frame,1,'ready cache initialized')
eq(cached.__completeDexBattleLift,6,'cached alignment metadata')
eq(Pokemon.frontPic(1,0,true),cached,'stable entry identity')
-- Use the exact production proxy-update loop, not another animation model.
local pa=assert(source:find('    for _, sheet in pairs(sheets) do\n      if type(sheet.proxies)',1,true))
local pz=assert(source:find('    evictIfNeeded()',pa,true))
local advance=assert(load(source:sub(pa,pz-1),'production proxy clock','t',env))
tick=.1;advance();eq(cached.image.frame,2,'cached image advances without provider call')
animated=false;advance();eq(cached.image.frame,1,'cached animation toggle respected');animated=true
-- Gen3 mon-aware rendering must use the engine's shiny predicate, including
-- explicit isShiny and PID/OT-derived values, instead of the old DV reader.
local sa=assert(source:find('  local function isShiny(mon)',1,true))
local sz=assert(source:find('  local function isFemale(mon)',sa,true))
local calls=0
Pokemon.isShiny=function(mon)
 calls=calls+1
 if mon.isShiny~=nil then return mon.isShiny end
 return mon.personality==0 and mon.otId==0 and mon.otSecretId==0
end
local detect=assert(load(source:sub(sa,sz-1)..'\nreturn isShiny','mon shiny seam','t',env))()
eq(detect({isShiny=true}),true,'Gen3 explicit shiny field')
eq(detect({isShiny=false,shiny=true}),false,'native explicit normal wins')
eq(detect({personality=0,otId=0,otSecretId=0}),true,'engine PID shiny detection')
eq(detect({personality=8,otId=0,otSecretId=0}),false,'engine PID normal detection')
eq(calls,4,'all Gen3 mon reads delegate to engine')
print(('PASS: %d assertions; animated shiny/normal front/back, isolated preview caches, native-frame override, native argument forwarding and stable height.'):format(checks))
