-- Prefer base-species icons over the naming screen's trainer fallback.
return function(mod)
 if require('src.core.GameVersion').generation()~=3 then return end
 local P=require('src.core.game3.pokemon');local wrapped
 local function install()
 if P.icon==wrapped then return end
 local icon=P.icon
 wrapped=function(species,...)
  local entry=icon(species,...);if entry and entry.image then return entry end
  local n=tonumber(species);local seen={}
  while n and not seen[n]do
   seen[n]=true
   if n>=413 and n<=439 then n=201
   else
    local form=P.__completeDexForms and P.__completeDexForms[n]
    local base=form and form.baseSpecies
    n=base and P.speciesFromName(base)or nil
   end
   if n then entry=icon(n,...);if entry and entry.image then return entry end end
  end
  return entry
 end
 P.icon=wrapped
 end
 install()
 if mod.hooks then mod.hooks:wrap('core.update',function(next,game,dt)install();return next(game,dt)end)end
end
