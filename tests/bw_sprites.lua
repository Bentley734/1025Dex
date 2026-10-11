-- Exercise production companion lookup, selection, timing and original fallback.
local source=assert(io.open('sprites/main.lua')):read('*a')
local checks=0
local function eq(a,b,why) checks=checks+1;assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b))end
local function block(a,z)
  local first=assert(source:find(a,1,true));local last=assert(source:find(z,first+1,true))
  return source:sub(first,last-1)
end
local style=2
local timing={durations={2,5,3},indices={1,3,2},loop_tick=2,total_ticks=10}
local peer={sprite=function(folder,stem)
  if folder=='front_shiny' and stem=='PIKACHU_female' then return timing end
end,decodeSprite=function(folder,stem)return {folder=folder,stem=stem}end}
local env=setmetatable({DATA={},opt=function()return style end,
  mod={find=function()return {exports=peer}end},},{__index=_G})
assert(load(block('  function DATA.spriteStyle()', '  local function wantShiny('),'BW helpers','t',env))()
eq(env.DATA.spriteStyle(),2,'BW style value');eq(env.DATA.bwPeer(),peer,'companion exports')
eq(env.DATA.bwFrame(timing,0,3),1,'first frame')
eq(env.DATA.bwFrame(timing,2/60,3),3,'duration boundary and frame map')
eq(env.DATA.bwFrame(timing,7/60,3),2,'uneven native duration')
eq(env.DATA.bwFrame(timing,10/60,3),3,'loop skips prefix')
eq(env.DATA.bwFrame(timing,18/60,3),3,'second loop')
eq(env.DATA.bwFrame(timing,2/60,1),1,'partial bake holds valid image')
eq(env.DATA.bwFrame({total_ticks=0},100,3),1,'invalid timing safe')
local bake=dofile('tests/static_sprites.lua')
bake.env.DATA.bwPeer=function()return peer end
local selected=bake.select('PIKACHU_female',false,true,2)
eq(selected.bwPeer,peer,'female shiny BW source');eq(selected.status,'local','companion is queued')
eq(selected.rel,nil,'companion owns its asset scope')
eq(selected.bwTiming,timing,'native timing retained')
local fallback=bake.select('EMOLGA',false,false,2)
eq(fallback.bwPeer,nil,'unavailable entry falls back')
eq(fallback.rel,'assets/front/EMOLGA.png','matching original art')
env.mod.find=nil;eq(env.DATA.bwPeer(),nil,'companion optional')
local options=dofile('sprites/options.lua');eq(options[1].choices[3][2],2,'manager BW option')
-- Transparent native canvas padding must not reduce the largest size. Every
-- pose shares a single union transform, preserving motion and the baseline.
for _,boxSize in ipairs({48,56,64})do
  for _,canvas in ipairs({96,160})do
    for _,mode in ipairs({0,1,2,3})do
      bake.env.spriteSizeMode=function()return mode end
      local id=bake.env.love.image.newImageData(canvas*2,canvas)
      for y=50,89 do for x=30,49 do id:setPixel(x,y,1,0,0,1)end end
      for y=55,89 do for x=canvas+32,canvas+51 do id:setPixel(x,y,1,0,0,1)end end
      local sheet,plan=bake.bake({stem='TEST',bwTiming=timing,box={w=boxSize,h=boxSize}},id)
      eq(plan.dh,math.floor(boxSize/math.max(1,mode)+.5),'native visible size, independent of blank padding')
      eq(plan.oy+plan.dh,boxSize,'native ground baseline')
      eq(#sheet.frames,2,'all native poses kept')
    end
  end
end
bake.env.spriteSizeMode=function()return 0 end
local id=bake.env.love.image.newImageData(96,96)
for y=50,89 do for x=30,49 do id:setPixel(x,y,1,0,0,1)end end
local _,explicit=bake.bake({stem='TEST',bwTiming=timing,scale=1},id)
eq(explicit.dh,40,'custom screen explicit scale retained')
print(('PASS: %d BW runtime assertions; native timing, prefix loop, gender/palette, partial build and fallback.'):format(checks))
