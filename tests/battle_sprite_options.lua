-- Production option resolution, source selection, frame clocks and pixel mirroring.
local checks=0
local function eq(a,b,why) checks=checks+1;assert(a==b,why..": "..tostring(a).." ~= "..tostring(b)) end
local f=assert(io.open("sprites/main.lua"));local source=f:read("*a");f:close()
local values={sprite_style=3}
local env=setmetatable({DATA={},opt=function(key,default) local v=values[key];if v==nil then return default end;return v end},{__index=_G})
local a=assert(source:find("  function DATA.spriteStyle()",1,true))
local z=assert(source:find("  function DATA.bwPeer()",a,true))
local animate=assert(load(source:sub(a,z-1).."return animateOn","battle options","t",env))()
for enemy=0,4 do for player=0,4 do
 values.enemy_sprite_style=enemy;values.player_sprite_style=player
 eq(env.DATA.styleFor(false,true),enemy,"enemy style")
 eq(env.DATA.styleFor(true,true),player,"player style")
 eq(env.DATA.styleFor(false,false),3,"menus retain default")
 eq(animate(enemy),enemy~=1 and enemy~=4,"enemy animation")
 eq(animate(player),player~=1 and player~=4,"player animation")
end end
values.player_sprite_style=-1;values.enemy_sprite_style=-1
for default=0,4 do values.sprite_style=default;eq(env.DATA.styleFor(true,true),default,"player follows default");eq(env.DATA.styleFor(false,true),default,"enemy follows default") end
for view=0,2 do
 values.player_sprite_view=view
 local front,flip=env.DATA.playerView(true)
 eq(front,view>0,"front choice");eq(flip,view==2,"mirror choice")
 front,flip=env.DATA.playerView(false);eq(front,false,"enemy stays front");eq(flip,false,"enemy never mirrors")
end
values.player_sprite_view=-1;values.battle_frontal=true;values.battle_front_flip=true
local front,flip=env.DATA.playerView(true);eq(front,true,"saved front");eq(flip,true,"saved mirror")
values.player_sprite_view=0;front,flip=env.DATA.playerView(true);eq(front,false,"explicit back overrides saved");eq(flip,false,"back never mirrors")
local schema=dofile("sprites/options.lua")
local oa=assert(source:find("  local OPTIONS = {",1,true));local oz=assert(source:find("mod.options:define(OPTIONS)",oa,true))
local inline=assert(load(source:sub(oa,oz-1).."return OPTIONS","inline schema","t",setmetatable({},{__index=_G})))()
local function same(a,b) if type(a)~="table" then return a==b end;if type(b)~="table" then return false end;for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
eq(same(schema,inline),true,"manager and runtime schemas identical")
local api=dofile("tests/static_sprites.lua")
api.env.DATA.styleFor=env.DATA.styleFor
values.enemy_sprite_style=1;values.player_sprite_style=3
local enemyKey=api.key(false,false,"BULBASAUR",nil,nil,nil,nil,nil,nil,nil,nil,nil,true)
local playerKey=api.key(true,false,"BULBASAUR",nil,nil,nil,nil,nil,nil,nil,nil,nil,true,true,true)
eq(enemyKey:sub(1,2),"s1","enemy cache style");eq(playerKey:sub(1,2),"s3","player cache style")
local id=api.env.love.image.newImageData(64,64)
for y=20,40 do for x=10,20 do id:setPixel(x,y,1,0,0,1)end;for x=21,30 do id:setPixel(x,y,0,1,0,1)end end
for _,gen in ipairs({1,2,3})do
 api.env.GEN=gen
 local normal=api.bake({stem="TEST",style=0,back=true,front=true},id)
 local mirror=api.bake({stem="TEST",style=0,back=true,front=true,flip=true},id)
 local n,m=normal.frames[1].data,mirror.frames[1].data
 local w,h=n:getDimensions()
 for y=0,h-1 do for x=0,w-1 do
  local nr,ng,nb,na=n:getPixel(x,y);local mr,mg,mb,ma=m:getPixel(w-1-x,y)
  eq(nr,mr,"mirror red");eq(ng,mg,"mirror green");eq(nb,mb,"mirror blue");eq(na,ma,"mirror alpha")
 end end
 eq(normal.frames.__spriteStyle,0,"frame clock style")
end
print("PASS: "..checks.." independent style, view, schema, cache and mirrored pixel assertions")
