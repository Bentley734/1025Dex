-- Upstream Gen1Recomp Gen3Compat picture wrapper, regression fixture.
-- https://github.com/bryanthaboi/gen1recomp/blob/main/src/mods/Gen3Compat.lua
local function wrapPics(P)
  if not P or wrappedModules[P] then return end
  wrappedModules[P] = true
  local frontOrig, backOrig = P.frontPic, P.backPic
  if frontOrig then
    P.frontPic = function(species, form, shiny, personality)
      local sp = tonumber(species)
      local path = sp and (tonumber(form) or 0) == 0 and spriteOverrides.front[sp]
      local entry = path and centredEntry(path)
      if not entry then entry = frontOrig(species, form, shiny, personality) end
      if sp then return hookedEntry("front", sp, form, entry) end
      return entry
    end
    P.frontSprite = P.frontPic
  end
  if backOrig then
    P.backPic = function(species, form, shiny)
      local sp = tonumber(species)
      local path = sp and (tonumber(form) or 0) == 0 and spriteOverrides.back[sp]
      local entry = path and centredEntry(path)
      if not entry then entry = backOrig(species, form, shiny) end
      if sp then return hookedEntry("back", sp, form, entry) end
      return entry
    end
  end
end

return wrapPics
