-- Extend Emerald's native RSE scene and retain its Hoenn numbering/layout.
return function(mod)
  local version=require("src.core.GameVersion").get()
  if version~="emerald" and version~="ruby" and version~="sapphire" then return end
  local function data(path) return assert(load(assert(mod:read(path)),"@"..mod.path.."/"..path))() end
  local Pokedex=data("compat/emerald_pokedex.lua")
  local national=data("dex/data/species/generated/national.lua")
  for _,record in pairs(national.register or {}) do
    local nat=record.dex
    if not record.form and type(nat)=="number" and nat>=387 and nat<=1025 and not Pokedex.extraEntries[nat] then
      local e=record.dexEntry or {}
      Pokedex.extraEntries[nat]={category=e.kind or "",height=math.floor((e.heightM or 0)*10+.5),
        weight=math.floor((e.weightKg or 0)*10+.5),description=national.text[ e.text ] or ""}
    end
  end
  local P=require("src.core.game3.pokemon")
  local Gfx=require("src.ui.game3.rse.pokedex_gfx")
  local List=require("src.ui.game3.rse.pokedex_list")
  local Dex=require("src.core.game3.dex")
  local colors=data("compat/pokedex_colors.lua")
  local originalManifest,manifestCache=Gfx.manifest,nil
  Gfx.manifest=function(...)
    local man=originalManifest(...)
    if man~=manifestCache then
      manifestCache=man;man.bodyColor=man.bodyColor or {}
      for nat=387,1025 do man.bodyColor[P.speciesFromNational(nat)]=colors[nat] end
    end
    return man
  end
  local originalEnabled=Dex.nationalEnabled
  Dex.nationalEnabled=function(session)
    if require("src.core.GameVersion").get()==version then return true end
    return originalEnabled(session)
  end
  local originalOrders,ordersSource,ordersCache=Gfx.orders,nil,nil
  Gfx.orders=function(...)
    local native=originalOrders(...)
    if native~=ordersSource then
      ordersSource=native;ordersCache={}
      for k,v in pairs(native) do ordersCache[k]=v end
      local numerical,alpha,weight,height={},{},{},{}
      for nat=1,1025 do numerical[nat]=nat;alpha[nat]=nat;weight[nat]=nat;height[nat]=nat end
      local function measure(nat,key) local e=P.dexEntry(P.speciesFromNational(nat)) or {};return tonumber(e[key]) or 0 end
      table.sort(alpha,function(a,b)
        local an,bn=P.name(P.speciesFromNational(a)) or "",P.name(P.speciesFromNational(b)) or ""
        return an==bn and a<b or an<bn
      end)
      table.sort(weight,function(a,b)local x,y=measure(a,"weight"),measure(b,"weight");return x==y and a<b or x<y end)
      table.sort(height,function(a,b)local x,y=measure(a,"height"),measure(b,"height");return x==y and a<b or x<y end)
      ordersCache.numerical_national=numerical;ordersCache.atoz=alpha
      ordersCache.lightest=weight;ordersCache.smallest=height
    end
    return ordersCache
  end
  local originalCreate=List.create
  List.create=function(ctx,mode,order,...)
    if not ctx.nationalEnabled or mode~=List.DEX_MODE_NATIONAL or order==List.ORDER_NUMERICAL then
      return originalCreate(ctx,mode,order,...)
    end
    local alpha=order==List.ORDER_ALPHABETICAL
    local numbers=alpha and ctx.orders.atoz
      or ((order==List.ORDER_HEAVIEST or order==List.ORDER_LIGHTEST) and ctx.orders.lightest or ctx.orders.smallest)
    local reverse=order==List.ORDER_HEAVIEST or order==List.ORDER_TALLEST
    local items,count={},0
    for n=1,#numbers do
      local nat=numbers[reverse and (#numbers-n+1) or n]
      local seen,owned=ctx.seen(nat),ctx.owned(nat)
      if alpha and seen or not alpha and owned then
        items[count]={dexNum=nat,seen=seen,owned=owned};count=count+1
      end
    end
    return {items=items,count=count}
  end
  mod.log:info("RSE native Pokedex extended: 1025 National entries; original Hoenn list retained.")
end
