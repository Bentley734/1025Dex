-- SPDX-License-Identifier: GPL-3.0-or-later
-- Fairy has no cartridge badge. Draw its real label rather than a Normal
-- badge or an out-of-bounds atlas frame. This affects summaries/dex only.
return function()
 local Font=require('src.ui.game3.frlg_font')
 local function fairy(x,y)
  local G=love.graphics;local r,g,b,a=G.getColor()
  G.setColor(0.72,0.30,0.52,1);G.rectangle('fill',x,y,32,12)
  G.setColor(1,1,1,1);Font.draw('FAIRY',x+1,y+1,{colors=Font.COLOR.NORMAL})
  G.setColor(r,g,b,a)
 end
 for _,name in ipairs({'src.ui.game3.summary_chrome','src.ui.game3.pokedex_chrome'})do
  local chrome=require(name);local draw=chrome.drawTypeBadge
  chrome.drawTypeBadge=function(id,x,y,...)
   if tonumber(id)==18 or id=='FAIRY'then return fairy(x,y)end
   return draw(id,x,y,...)
  end
 end
 local Rse=require('src.ui.game3.rse.summary_menu');local draw=Rse.draw
 Rse.draw=function(menu,...)
  local G=love.graphics;local original=G.draw
  G.draw=function(image,quad,x,y,...)
   if type(quad)=='userdata'and quad.typeOf and quad:typeOf('Quad')then
    local qx,qy,qw,qh=quad:getViewport()
    local info=(x==120 or x==160)and y==48
    local move=x==85 and y>=32 and y<=96 and menu._page~=Rse.PAGE.CONTEST_MOVES
    if qx==0 and qw==32 and qy==18*qh and(info or move)then return fairy(x,y)end
   end
   return original(image,quad,x,y,...)
  end
  local ok,err=pcall(draw,menu,...);G.draw=original
  if not ok then error(err,0)end
 end
 local RS=require('src.ui.game3.rs.summary_menu');local rsDraw=RS.draw
 RS.draw=function(...)
  local G=love.graphics;local original=G.draw
  G.draw=function(image,quad,x,y,...)
   if type(quad)=='userdata'and quad.typeOf and quad:typeOf('Quad')then
    local qx,qy,qw,qh=quad:getViewport()
    local info=(x==120 or x==160)and y==48
    local move=x==87 and y>=32 and y<=96 and RS._page~=RS.PAGE.CONTEST
    if qx==0 and qw==32 and qy==18*qh and(info or move)then return fairy(x,y)end
   end
   return original(image,quad,x,y,...)
  end
  local ok,err=pcall(rsDraw,...);G.draw=original
  if not ok then error(err,0)end
 end
end
