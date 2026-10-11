-- Older Ruby/Sapphire packs omit the shared options-menu text tables.
-- Supply only those missing labels, keeping ROM text and translations first.
return function()
  local Version = require('src.core.GameVersion')
  local Text = require('src.core.game3.rom_text')
  local Strings = require('src.core.Strings')
  if Text.__dexRseOptions then return end
  Text.__dexRseOptions = true
  local tables = {
    sOptionMenuItemsNames = {'TEXT SPEED', 'BATTLE SCENE', 'BATTLE STYLE', 'SOUND', 'BUTTON MODE', 'FRAME', 'CANCEL'},
    sTextSpeedOptions = {'SLOW', 'MID', 'FAST'},
    sBattleSceneOptions = {'ON', 'OFF'},
    sBattleStyleOptions = {'SHIFT', 'SET'},
    sSoundOptions = {'MONO', 'STEREO'},
    sButtonTypeOptions = {'NORMAL', 'LR', 'L=A'},
  }
  local labels = {gText_FrameType='TYPE ', gText_MenuOption='OPTION', gText_PickSwitchCancel='PICK / SWITCH / CANCEL'}
  for name, rows in pairs(tables) do
    for i, label in ipairs(rows) do labels[Text.key(name, i-1)] = label end
  end
  local function active()
    local version = Version.get()
    return version == 'ruby' or version == 'sapphire'
  end
  local plain, count = Text.plain, Text.count
  Text.plain = function(key, ctx)
    if active() and labels[key] and not Text.has(key) then return Strings(labels[key]) end
    return plain(key, ctx)
  end
  Text.count = function(name)
    if active() and tables[name] then
      local ok, n, m = pcall(count, name)
      if ok then return n, m end
      return #tables[name]
    end
    return count(name)
  end
end
