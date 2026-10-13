-- Presentation pictures centre visible ink, while battle frames keep their
-- ground-contact baseline. Never mutate a shared baked battle ImageData.
return function(frame)
 local w,h=frame:getDimensions();local left,top,right,bottom=w,h,-1,-1
 for y=0,h-1 do for x=0,w-1 do
  local _,_,_,a=frame:getPixel(x,y)
  if a>0 then left=math.min(left,x);right=math.max(right,x);top=math.min(top,y);bottom=math.max(bottom,y)end
 end end
 if right<left then return frame end
 local dx=math.floor((w-(right-left+1))/2)-left
 local dy=math.floor((h-(bottom-top+1))/2)-top
 if dx==0 and dy==0 then return frame end
 local centered=love.image.newImageData(w,h)
 for y=top,bottom do for x=left,right do
  centered:setPixel(x+dx,y+dy,frame:getPixel(x,y))
 end end
 return centered
end
