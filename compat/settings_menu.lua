-- Direct OPTIONS shortcut to the engine-owned mod settings and persistence.
return function(mod)
  local generation=require('src.core.GameVersion').generation()
  local function open(game)
    if not game then return end
    local manager
    if generation==3 then
      local view=require('src.ui.game3.mod_manager')
      view.show({game=game});manager=view._mgr
    else
      manager=require('src.mods.ManagerState').new(game)
      game.stack:push(manager)
    end
    local entry=manager and manager.byId and manager.byId[mod.id or '1025dex']
    if entry then manager:openOptions(entry)end
  end
  local function append(rows,game)
    if type(rows)~='table' then return rows end
    local out={}
    for _,row in ipairs(rows)do if row.id~='1025dex:settings' then out[#out+1]=row end end
    out[#out+1]={id='1025dex:settings',label='1025DEX',text=function()return 'OPEN'end,
      value=function()return 'OPEN'end,activate=function(ctx)open(generation==3 and ctx and ctx.game or ctx or game)end}
    return out
  end
  if generation==3 then
    local rows=require('src.ui.game3.option_rows')
    local original=rows.build
    rows.build=function(ctx,...)return append(original(ctx,...),ctx and ctx.game)end
  else
    mod.hooks:wrap('ui.options.rows',function(next_,game,rows)return append(next_(game,rows),game)end)
  end
end
