-- One mod identity, one options schema, ordered generation-specific components.
return function(mod)
  local Version = require('src.core.GameVersion')
  local generation = Version.generation()
  assert(generation >= 1 and generation <= 3, 'Unsupported game generation')
  if mod.cache and mod.ui and mod.content.screens then
    assert(load(assert(mod:read('compat/assets.lua')), '@1025dex/assets.lua'))()(mod)
  end
  local schema, seen = {}, {}
  local function component(folder)
    local child = setmetatable({path=mod.path .. '/' .. folder}, {__index=mod})
    function child:rootRead(relative) return mod:read(relative) end
    function child:read(relative) return mod:read(folder .. '/' .. relative) end
    function child:list(relative) return mod:list(folder .. '/' .. (relative or '')) end
    function child:info(relative) return mod:info(folder .. '/' .. relative) end
    child.assets = setmetatable({}, {__index=mod.assets})
    for _,method in ipairs({'path','image','list','info'}) do
      local name=method
      child.assets[name]=function(_,relative)
        return mod.assets[name](mod.assets,folder .. '/' .. (relative or ''))
      end
    end
    child.options = {
      define=function(_,rows)
        for _,row in ipairs(rows) do
          if not seen[row.key] then
            seen[row.key]=true; schema[#schema+1]=row
          end
        end
        return mod.options:define(schema)
      end,
      get=function(_,key) return mod.options:get(key) end,
    }
    local source=assert(child:read('main.lua'),'Missing component: '..folder)
    local entry=assert(load(source,'@'..child.path..'/main.lua'))()
    assert(type(entry)=='function','Invalid component: '..folder)
    entry(child)
  end
  assert(load(assert(mod:read('compat/save_editor.lua')), '@1025dex/save_editor.lua'))()(mod)
  assert(load(assert(mod:read('storage.lua')), '@1025dex/storage.lua'))()(mod)
  local finishApples = assert(load(assert(mod:read('apples.lua')), '@1025dex/apples.lua'))()(mod)
  assert(load(assert(mod:read('compat/national_gen3.lua')), '@1025dex/national_gen3.lua'))()(mod)
  component('dex')
  finishApples()
  component('cries')
  component('sprites')
  component('encounters')
  assert(load(assert(mod:read('compat/species_numbers.lua')), '@1025dex/species_numbers.lua'))()(mod)
  assert(load(assert(mod:read('compat/hoennto.lua')),'@1025dex/hoennto.lua'))()(mod)
  if generation == 3 then
    assert(load(assert(mod:read('compat/rse_option_text.lua')), '@1025dex/rse_option_text.lua'))()()
    assert(load(assert(mod:read('emerald.lua')), '@1025dex/emerald.lua'))()(mod)
    assert(load(assert(mod:read('compat/catch_return.lua')), '@1025dex/catch_return.lua'))()()
    assert(load(assert(mod:read('menu_world.lua')), '@menu_world.lua'))()(mod)
    -- Lift the FireRed data-card front pic clear of the lower divider.
    -- The stock page draws its 64x64 pic at (152, 24). Intercept only that
    -- draw during the entry page, leaving battle art and other pages alone.
    local Pokedex = require('src.ui.game3.pokedex')
    if (Version.get() == 'firered' or Version.get() == 'leafgreen') and type(Pokedex.draw) == 'function' then
      local originalDexDraw = Pokedex.draw
      Pokedex.draw = function(...)
        local originalDraw = love.graphics.draw
        love.graphics.draw = function(image, x, y, ...)
          if Pokedex.screen == 'data' and Pokedex.dataPage ~= 2
              and x == 152 and y == 24 then
            return originalDraw(image, x, y - 6, ...)
          end
          return originalDraw(image, x, y, ...)
        end
        local ok, result = pcall(originalDexDraw, ...)
        love.graphics.draw = originalDraw
        if not ok then error(result, 0) end
        return result
      end
    end
    assert(load(assert(mod:read('battle_position.lua')), '@battle_position.lua'))()()
  end
  mod.exports.supportedGames={'red','blue','yellow','gold','silver','crystal','ruby','sapphire','firered','leafgreen','emerald'}
  mod.log:info('1025Dex ready: 1025 cries, selectable animated/static/BW ROM sprites and WILD GENS.')
end
