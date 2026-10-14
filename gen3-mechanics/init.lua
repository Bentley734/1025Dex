-- SPDX-License-Identifier: GPL-3.0-or-later
-- Install the Gen 3 translation layer after the dex metadata is available.
-- Root startup invokes this after registering the dex and native move records.
return function(mod)
 local items={}
 for id,row in mod.content.items:each()do if row.index then items[row.index]=id end end
 for id,row in mod.content.pokemon:each()do
  local changed=false
  for _,evolution in ipairs(row and row.evolutions or{})do
   local item=tonumber(evolution.item)
   if item and items[item]then evolution.item=items[item];changed=true end
  end
  if changed then mod.content.pokemon:patch(id,{evolutions=row.evolutions})end
 end
 local function module(name)return assert(load(assert(mod:read('gen3-mechanics/'..name..'.lua')),'@'..mod.path..'/gen3-mechanics/'..name..'.lua'))()end
 local Moves=require('src.core.game3.battle.moves')
 local registry=module('registry')(mod.exports,Moves)
 local F=module('facade')(mod,registry,{})
 local models=module('models')(mod,registry,F)
 module('status')(models)
 for name,err in pairs(models.exports.__bootReport.failed)do error('Gen 3 mechanics startup failed: '..name..': '..tostring(err),0)end
 module('native_registry')(mod,registry,models)
 models.abilities=module('abilities')(mod,models)
 models.learnsets=module('learnsets')(mod,registry)
 module('learning')(mod,models)
 local adapters=setmetatable({},{__mode='k'})
 local transport=module('transport')(models,function(state)return adapters[state]end)
 module('execution')(mod,models,transport,adapters)
 module('residuals')(models)
 module('type_badges')()
 mod.exports.gen3BattleAdapter={registry=registry,models=models,transport=transport,adapters=adapters}
 return mod.exports.gen3BattleAdapter
end
