-- Scroll overflowing summary identifiers without shrinking or changing text data.
return function(mod)
 if require('src.core.GameVersion').generation()~=3 then return end
 local G=love.graphics;local installed={};local active;local printing=false;local clocks={};local lastMon
 local function install()
  local ok,F=pcall(require,'src.ui.game3.frlg_font');if not ok then return end
  local P=require('src.core.game3.pokemon')
  local function wrapFont(font,method,measure)
   local token=tostring(font)..method;if installed[token]then return end;installed[token]=true
   local draw=font[method];if type(draw)~='function'then return end
   font[method]=function(text,x,y,opts,...)
    if not active or printing or type(text)~='string'or not active.names[text]then return draw(text,x,y,opts,...)end
    local width=opts and opts.maxWidth
    if not width then
     local m=active.manifest
     for _,idx in ipairs({19,20})do local w=m and m.windows and m.windows[idx]
      if w and x>=w.left*8 and x<(w.left+w.width)*8 and y>=w.top*8 and y<(w.top+w.height)*8 then width=(w.left+w.width)*8-x;break end
     end
     width=width or (x<80 and 80-x or 232-x)
    end
    width=math.max(1,width);local size=measure(text,opts)or 0
    if size<=width then return draw(text,x,y,opts,...)end
    local now=love.timer.getTime();local key=text..':'..x..':'..y..':'..width
    if not clocks[key]then clocks[key]=now end
    local travel=(size-width)/14;local span=travel*2+2.4;local phase=(now-clocks[key])%span
    local offset=phase<1.2 and 0 or phase<1.2+travel and (phase-1.2)*14 or phase<2.4+travel and size-width or (span-phase)*14
    local options={};for k,v in pairs(opts or {})do if k~='maxWidth'then options[k]=v end end
    G.push('all');local ax,ay=G.transformPoint(x,y);local bx,by=G.transformPoint(x+width,y+16)
    G.intersectScissor(math.min(ax,bx),math.min(ay,by),math.abs(bx-ax),math.abs(by-ay))
    printing=true;local result={pcall(draw,text,x-math.floor(offset+.5),y,options,...)};printing=false;G.pop()
    if not result[1]then error(result[2],0)end;return (unpack or table.unpack)(result,2)
   end
  end
  wrapFont(F,'draw',F.measure)
  local okPal,Pal=pcall(require,'src.ui.game3.rse.pal_text');if okPal then wrapFont(Pal,'draw',Pal.width)end
  for _,path in ipairs({'src.ui.game3.summary_menu','src.ui.game3.rse.summary_menu','src.ui.game3.rs.summary_menu'})do
   local ok,S=pcall(require,path)
   if ok and type(S.draw)=='function'and not S._1025DexScrollingNames then
    S._1025DexScrollingNames=true;local draw=S.draw
    S.draw=function(...)
     local args={...};local base=args[1]or S
     if path=='src.ui.game3.rse.summary_menu'and not base._party then base=require('src.ui.game3.summary_menu')end
     local mon=base._party and base._party[base._cursor or 1]
     local prior=active
     if mon then
      if lastMon~=mon then clocks={};lastMon=mon end
      local species=P.name(P.speciesOf(mon))or '';local nickname=P.displayName(mon)or species
      active={names={[nickname]=true,[species]=true,['/'..species]=true}}
      if path=='src.ui.game3.rse.summary_menu'then local okK,K=pcall(require,'src.ui.game3.rse.scene_kit');if okK then active.manifest=K.manifest(S.SUB)end end
     end
     local result={pcall(draw,...)};active=prior
     if not result[1]then error(result[2],0)end;return (unpack or table.unpack)(result,2)
    end
   end
  end
 end
 install();mod.hooks:wrap('core.update',function(next,game,dt)install();return next(game,dt)end)
end
