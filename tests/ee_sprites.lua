-- Run actual source selection and pixel baking for both EE styles.
local api=dofile('tests/static_sprites.lua')
api.env.DATA.ee=dofile('sprites/data/ee_data.lua')
local checks=0
local function eq(a,b,why) checks=checks+1;assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b)) end
for _,style in ipairs({3,4})do
 for _,back in ipairs({false,true})do for _,shiny in ipairs({false,true})do
  local s=api.select('BULBASAUR',back,shiny,style)
  eq(s.ee,true,'EE source');eq(s.static,false,'independent EE density')
  eq(s.rel,'assets/ee/'..api.env.localFolder(back,shiny)..'/BULBASAUR.png','EE palette/side')
 end end
 eq(api.select('CHARIZARD_1',false,false,style).ee,true,'Mega exact art')
 eq(api.select('PIKACHU_female',false,true,style).ee,true,'female shiny EE')
 local fallback=api.select('MEOWSTIC_3',false,false,style)
 if not fallback.ee then eq(fallback.rel,'assets/front/MEOWSTIC_3.png','matching fallback') end
end
-- First and second poses have different bounds; static must ignore pose two.
local id=api.env.love.image.newImageData(128,64)
for y=20,49 do for x=20,39 do id:setPixel(x,y,1,0,0,1)end end
for y=2,60 do for x=66,124 do id:setPixel(x,y,0,1,0,1)end end
for _,gen in ipairs({1,2,3})do
 api.env.GEN=gen
 local animated,ap=api.bake({stem='TEST',ee=true,style=3},id)
 local static,sp=api.bake({stem='TEST',ee=true,style=4},id)
 eq(#animated.frames,2,'animated poses');eq(#static.frames,1,'static first pose')
 eq(sp.dw,20,'static first pose width');eq(sp.dh,30,'static first pose height')
 eq(ap.oy+ap.dh,64,'animated ground');eq(sp.oy+sp.dh,64,'static ground')
end
local source=assert(io.open('sprites/main.lua')):read('*a')
local a=assert(source:find('  function DATA.spriteStyle()',1,true))
local z=assert(source:find('  function DATA.bwPeer()',a,true))
local style=3
local env=setmetatable({DATA={},opt=function(key,default)if key=='sprite_style'then return style end;return default end},{__index=_G})
local animate=assert(load(source:sub(a,z-1)..'return animateOn','EE option accessors','t',env))()
eq(env.DATA.spriteStyle(),3,'animated persisted value');eq(animate(),true,'animated enabled')
style=4;eq(env.DATA.spriteStyle(),4,'static persisted value');eq(animate(),false,'static animation disabled')
local schema=dofile('sprites/options.lua')
eq(schema[1].choices[4][1],'EE ANIMATED','manager animated label')
eq(schema[1].choices[5][1],'EE STATIC','manager static label')
eq(schema[1].choices[4][2],3,'manager animated value');eq(schema[1].choices[5][2],4,'manager static value')
local stemData=dofile('sprites/data/dbk_data.lua');stemData.ee=dofile('sprites/data/ee_data.lua')
stemData.spriteStyle=function()return style end
local stemEnv=setmetatable({DATA=stemData},{__index=_G})
local first=assert(source:find('  local function stripLastWord(',1,true))
local last=assert(source:find('  -- Resolve a live mon to',first,true))
local resolver=assert(load(source:sub(first,last-1)..'return {resolve=resolveStem,female=femaleStem}','EE form/gender identities','t',stemEnv))()
for _,selection in ipairs({3,4})do
 style=selection
 eq(resolver.resolve('DARMANITAN_GALAR_STANDARD'),'DARMANITAN_2','Galar standard exact EE identity')
 eq(resolver.resolve('DARMANITAN_GALAR_ZEN'),'DARMANITAN_3','Galar Zen exact EE identity')
 eq(resolver.resolve('DARMANITAN_ZEN'),'DARMANITAN_1','Unova Zen exact EE identity')
 eq(resolver.female('PIKACHU'),'PIKACHU_female','EE gender resolution')
end
style=0;eq(resolver.resolve('DARMANITAN_GALAR_STANDARD'),'DARMANITAN_1','existing animated lookup retained')
-- Emerald requests pendingPic before frame one: its empty proxy array is
-- separate from the arrays allocated by buildOneFrame. Test that real seam.
local proxy={data={},image={replacePixels=function()end},pic={}}
local sheet=api.bake({stem='TEST',ee=true,style=3,proxies={gen3=proxy}},id)
eq(proxy.data.__ee,true,'pending Emerald proxy receives EE clock marker')
eq(#proxy.data,2,'pending Emerald proxy receives both baked frames')
local timingStart=assert(source:find('  function DATA.eeFrame(',1,true))
local timingEnd=assert(source:find('  local function wantShiny()',timingStart,true))
local timerEnv=setmetatable({DATA={},opt=function(_,default)return default end},{__index=_G})
assert(load(source:sub(timingStart,timingEnd-1),'cached Emerald EE clock','t',timerEnv))()
eq(timerEnv.DATA.eeFrame(proxy.data,10,12,#proxy.data),1,'pending proxy starts animation')
eq(timerEnv.DATA.eeFrame(proxy.data,10.09,12,#proxy.data),2,'pending proxy second pose')
eq(timerEnv.DATA.eeFrame(proxy.data,11,12,#proxy.data),1,'pending proxy rests instead of looping')
eq(timerEnv.DATA.eeFrame(proxy.data,12.43,12,#proxy.data),2,'pending proxy repeats with new defaults')
proxy.data={};proxy.lastFrame=nil
api.bake({stem='TEST',ee=true,style=3,proxies={gen3=proxy}},id)
eq(proxy.data.__ee,true,'rebuilt proxy restores clock marker after reset')
print(('PASS: %d EE assertions; source sides, palettes, forms, gender, animation/static bounds and options.'):format(checks))
