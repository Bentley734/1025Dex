-- The engine uses these shared limits for capture spillover, PC navigation,
-- serialization and restore. Install before a save can be deserialized.
return function(mod)
  local generation=require('src.core.GameVersion').generation()
  if generation < 3 then
    if generation == 1 then
      local Boxes=require('src.pokemon.Boxes')
      Boxes.COUNT=math.max(Boxes.COUNT,math.ceil(1025/Boxes.CAPACITY))
      local ensure=Boxes.ensure
      Boxes.ensure=function(save)
        local boxes=ensure(save)
        for i=1,Boxes.COUNT do boxes[i]=boxes[i] or {} end
        return boxes
      end
    else
      local Save=require('src.core.gen2.Save')
      local Boxes=require('src.core.gen2.Boxes')
      Save.NUM_BOXES=math.max(Save.NUM_BOXES,math.ceil(1025/Save.MONS_PER_BOX))
      Boxes.NUM_BOXES=Save.NUM_BOXES
    end
    mod.log:info('PC storage expanded to hold the complete National Dex')
    return
  end
  local Storage = require('src.core.game3.storage')
  local slots = assert(tonumber(Storage.IN_BOX_COUNT), 'Missing PC slot count')
  local required = math.max(36, math.ceil(1025 / slots))
  Storage.TOTAL_BOXES_COUNT = math.max(Storage.TOTAL_BOXES_COUNT or 0, required)
  Storage.TOTAL_BOX_MONS = Storage.TOTAL_BOXES_COUNT * slots

  -- Also upgrade an already-open session (e.g. when mods load in-game).
  -- Native ensure preserves existing boxes, names, wallpapers and PC items.
  local Runtime = require('src.core.game3.runtime')
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  if session then Storage.ensure(session) end
  mod.log:info(('PC storage expanded to %d boxes / %d Pokemon')
    :format(Storage.TOTAL_BOXES_COUNT, Storage.TOTAL_BOX_MONS))
end
