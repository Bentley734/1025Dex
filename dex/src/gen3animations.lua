-- Added species have sheet animations, but no Emerald ROM animation script.
local M = {}

function M.install(pokemon)
  local Anim = require('src.core.game3.mon_anim')
  if Anim.__completeDexFrontAnimations then return end
  Anim.__completeDexFrontAnimations = true
  local native = Anim.doFront
  Anim.doFront = function(sprite, species, noCry, flag, opts)
    local national = tonumber(pokemon.national(species))
    if (tonumber(species) or 0) > 450 and national and national <= 1025 then
      -- Use the engine's completed-animation path, preserving cry and pan.
      -- Do not index ROM tables with extended internal species slots.
      flag = require('bit').bor(flag or 0, Anim.SKIP_FRONT_ANIM or 0x80)
    end
    return native(sprite, species, noCry, flag, opts)
  end
end

return M
