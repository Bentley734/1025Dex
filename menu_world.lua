-- Keep the live FireRed field visible behind ordinary menu pages.
-- The engine treats several menus as full-screen scenes: Display then skips
-- its world pass and a menu paints a 240x160 opaque backdrop. Preserve the
-- menu's own windows and content while removing only that page-wide fill.
return function(mod)
  local Stack = require('src.ui.game3.stack')
  local UiPass = require('src.ui.game3.ui_pass')
  local Display = require('src.core.game3.display')
  local gfx = love.graphics

  local menus = {
    start=true, option=true, mod_manager=true, pokedex=true,
    bag=true, party=true, summary=true, trainer=true,
    region_map=true, pc_menu=true, item_pc=true, box_storage=true,
    berry_pouch=true, tm_case=true, fame_checker=true,
    save=true, shop=true, prize_corner=true, move_relearner=true,
    hall_of_fame_pc=true,
  }
  local function menuOpen()
    local top = Stack.top()
    return top and menus[top.id] == true
  end

  local originalFullscreen = Stack.fullscreen
  Stack.fullscreen = function(...)
    if menuOpen() then return false end
    return originalFullscreen(...)
  end

  local originalUi = UiPass.drawUi
  UiPass.drawUi = function(...)
    if not menuOpen() then return originalUi(...) end
    local originalRect = gfx.rectangle
    gfx.rectangle = function(mode, x, y, w, h, ...)
      if mode == 'fill' and x == 0 and y == 0
          and w == 240 and h == 160 then
        return -- only the opaque full-page backdrop
      end
      return originalRect(mode, x, y, w, h, ...)
    end
    local ok, result = pcall(originalUi, ...)
    gfx.rectangle = originalRect
    if not ok then error(result, 0) end
    return result
  end
  -- Display caches the UI pass after its first frame. Install the wrapper
  -- there as well so an already-running save uses the same rendering path.
  if type(Display.setUiRenderer) == 'function' then
    Display.setUiRenderer(UiPass.drawUi)
  end

  local Runtime = require('src.core.game3.runtime')
  local Hud = require('src.ui.game3.hud')
  local Objects = require('src.core.game3.objects')
  local Ghosts = require('src.core.game3.ghosts')
  local TrainerSight = require('src.core.game3.trainer_sight')
  local Field = require('src.core.game3.field')
  local Battle = require('src.core.game3.battle')
  local originalUpdate = Runtime.update
  local warned = false
  Runtime.update = function(dt)
    local menuBefore = menuOpen() and Hud.isMenuOpen()
    local result = originalUpdate(dt)
    if not (menuBefore and menuOpen() and Hud.isMenuOpen()
        and Runtime.isActive() and Field.running and not Field.locked
        and not Battle.isActive()) then return result end

    -- Only tick ambient EventObjects. A full Field.update would also route
    -- menu buttons to the player, run field scripts and start encounters.
    local originalMenuOpen, originalSight = Hud.isMenuOpen, TrainerSight.check
    Hud.isMenuOpen = function() return false end
    TrainerSight.check = function() return false end
    local ok, err = pcall(function()
      Objects.update(Runtime._game)
      Ghosts.update(Runtime._game)
      Runtime.pumpRtc(Runtime._game, dt)
    end)
    Hud.isMenuOpen, TrainerSight.check = originalMenuOpen, originalSight
    if not ok and not warned then
      warned = true
      mod.log:warn('1025Dex menu NPC tick failed: %s', tostring(err))
    end
    return result
  end
end
