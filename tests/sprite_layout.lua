-- Natural-frame metadata is stable across every pose and preserves hover pads.
local api=dofile('tests/static_sprites.lua')
local n=0
local function eq(a,b,m)n=n+1;assert(a==b,m..': '..tostring(a)..' ~= '..tostring(b))end
local id=api.env.love.image.newImageData(120,40)
for y=8,32 do for x=10,28 do id:setPixel(x,y,1,0,0,1)end end
for y=3,35 do for x=45,70 do id:setPixel(x,y,1,0,0,1)end end
for y=1,33 do for x=87,111 do id:setPixel(x,y,1,0,0,1)end end
for gen=1,3 do for _,hover in ipairs({0,8})do for _,flip in ipairs({false,true})do
 api.env.GEN=gen;api.env.floatLift=function()return hover end
 local sheet,plan=api.bake({stem='TEST',natural=true,scale=1,maxH=56,flip=flip},id)
 local layout=assert(sheet.frames.__spriteLayout)
 eq(layout.x0,0,'trimmed union left');eq(layout.y0,0,'trimmed union top')
 eq(layout.x1,plan.dw,'full animation width');eq(layout.y1,plan.dh,'visible union bottom')
 eq(layout.ox,plan.dw/2,'existing horizontal origin')
 eq(layout.ground,plan.dh+hover,'intentional hover ground')
 eq(#sheet.frames,3,'all animation frames still returned')
 for _,image in ipairs(sheet.frames)do
  local w,h=image.data:getDimensions()
  eq(w,layout.x1,'each pose uses union width');eq(h,layout.ground,'each pose ground unchanged')
 end
end end end
-- Fixed native slots continue supplying the exact same pixels and no layout.
local fixed=api.bake({stem='TEST'},id)
eq(fixed.frames.__spriteLayout,nil,'native frame API unchanged')
print('PASS: '..n..' natural-frame layout / pose / hover / mirror assertions')
