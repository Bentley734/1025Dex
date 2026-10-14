-- Keep custom battlers out of the internal grayscale zone recoloring pass.
return function(frames)
 if require('src.core.GameVersion').generation()~=1 then return end
 local ok,B=pcall(require,'src.battle.BattleState')
 if not(ok and type(B.drawZonePass)=='function')or B._1025DexEffectPictures then return end
 B._1025DexEffectPictures=true;local G=love.graphics
 local offsets={0,0,0,0,0,1,1,1,2,2,2,2,2,1,1,1,0,0,0,0,0,-1,-1,-1,-2,-2,-2,-2,-2,-1,-1,-1}
 local pic=B.picImage;B.picImage=function(self,image,...)if frames[image]then return image end;return pic(self,image,...)end
 local layer=B.drawPicsLayer;local zones=B.drawZonePass
 B.drawPicsLayer=function(self,...)
  if not(self.grayPics and self.fx and self.fx.wavy and G.newCanvas)then return layer(self,...)end
  self._1025DexWaveArt=self._1025DexWaveArt or G.newCanvas(160,144,{dpiscale=1})
  local canvas=self._1025DexWaveArt;local original=G.draw;local previous=G.getCanvas()
  G.push('all');G.setCanvas(canvas);G.origin();G.setScissor();G.clear(0,0,0,0);G.setCanvas(previous);G.pop()
  G.draw=function(image,...)
   if frames[image]then
    G.push('all');G.setCanvas(canvas);G.setShader();G.setBlendMode('alpha','alphamultiply')
    original(image,...);G.setCanvas(previous);G.pop()
   end
   return original(image,...)
  end
  local result={pcall(layer,self,...)};G.draw=original
  if not result[1]then error(result[2],0)end;return (unpack or table.unpack)(result,2)
 end
 B.drawZonePass=function(self,source,sx,sy,...)
  local result={zones(self,source,sx,sy,...)}
  if self.fx and self.fx.wavy and self._1025DexWaveArt then
   G.push('all');G.setShader();G.setScissor(0,0,160,96);G.setColor(1,1,1,1);G.setBlendMode('alpha','premultiplied')
   self._1025DexWaveQuad=self._1025DexWaveQuad or G.newQuad(0,0,160,1,160,144)
   local quad=self._1025DexWaveQuad
   for line=0,95 do
    quad:setViewport(0,line,160,1)
    G.draw(self._1025DexWaveArt,quad,(sx or 0)+offsets[(line*2+(self.fx.wavy.phase or 0))%32+1],(sy or 0)+line)
   end
   G.pop()
  end
  return (unpack or table.unpack)(result)
 end
end
