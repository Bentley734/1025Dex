-- Direct OPTIONS shortcut to the engine-owned mod settings and persistence.
return function(mod)
  local generation=require('src.core.GameVersion').generation()
  local Manager=require('src.mods.ManagerState')
  Manager._1025DexMod=mod
  if not Manager._1025DexRows then
    local build=Manager.buildOptionRows;Manager._1025DexRows=build
    Manager.buildOptionRows=function(self,entry,schema)
      local owner=Manager._1025DexMod
      if entry.id~='1025dex'then return build(self,entry,schema)end
      local ok,handle=pcall(owner.find,owner,'kim1025')
      local kim=ok and handle and handle.exports and type(handle.exports.getDexSpriteSheet)=='function'
      local filtered={}
      for _,row in ipairs(schema)do
        if row.key=='enemy_sprite_style'or row.key=='player_sprite_style'then
          local copy={};for k,v in pairs(row)do copy[k]=v end;copy.choices={}
          for _,choice in ipairs(row.choices or {})do if choice[2]~=5 or kim then copy.choices[#copy.choices+1]=choice end end
          filtered[#filtered+1]=copy
        else filtered[#filtered+1]=row end
      end
      local rows=build(self,entry,filtered)
      local assets=owner.exports.assetManager
      if assets and assets.open then
        table.insert(rows,math.max(1,#rows),{id='1025dex:asset_manager',label='1025DEX ASSETS',
          value=function()return 'OPEN'end,activate=function()assets.open(self.game)end})
      end
      return rows
    end
  end
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
    for _,row in ipairs(rows)do if row.id~='1025dex:settings' and row.id~='1025dex:asset_manager' then out[#out+1]=row end end
    out[#out+1]={id='1025dex:settings',label='1025DEX',text=function()return 'OPEN'end,
      value=function()return 'OPEN'end,activate=function(ctx)open(generation==3 and ctx and ctx.game or ctx or game)end}
    return out
  end
  if generation==3 then
    local rows=require('src.ui.game3.option_rows')
    local original=rows.build
    rows.build=function(ctx,...)
      local out=append(original(ctx,...),ctx and ctx.game)
      if require('src.core.GameVersion').get()=='emerald' then
        local menu=require('src.ui.game3.rse.option_menu');local cart={}
        for _,r in ipairs(menu.CART or {})do cart[r.id]=r end
        for _,r in ipairs(out)do if cart[r.id]then r.cart=cart[r.id]end end
      end
      return out
    end
  else
    mod.hooks:wrap('ui.options.rows',function(next_,game,rows)return append(next_(game,rows),game)end)
  end
end
