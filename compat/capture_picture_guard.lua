-- Registration callbacks must not dereference a missing added-species portrait.
return function(mod)
 if require('src.core.GameVersion').generation()~=3 then return end
 local blank
 local function fallback()
  if not blank then
   local data=love.image.newImageData(64,64);local image=love.graphics.newImage(data)
   image:setFilter('nearest','nearest');if data.release then data:release()end
   blank={image=image,w=64,h=64}
  end
  return blank
 end
 local function protect(done)
  return function(...)
   local P=require('src.core.game3.pokemon');local front=P.frontPic
   P.frontPic=function(...)
    local pic=front(...)
    if type(pic)=='table'and pic.image then return pic end
    return fallback()
   end
   local result={pcall(done,...)};P.frontPic=front
   if not result[1]then error(result[2],0)end;return (unpack or table.unpack)(result,2)
  end
 end
 local function install()
  local ok,Dex=pcall(require,'src.ui.game3.pokedex')
  if not(ok and type(Dex.showRegistration)=='function')then return false end
  if Dex._1025DexCatchPictureGuard then return true end
  Dex._1025DexCatchPictureGuard=true;local show=Dex.showRegistration
  Dex.showRegistration=function(species,opts,...)
   if opts and type(opts.onDone)=='function'then
    local copy={};for k,v in pairs(opts)do copy[k]=v end
    copy.onDone=protect(opts.onDone);opts=copy
   end
   return show(species,opts,...)
  end
  return true
 end
 install()
 mod.hooks:wrap('core.update',function(next,game,dt)install();return next(game,dt)end)
end
