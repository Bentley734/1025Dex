-- Persistent assets live outside the replaceable mod folder. Only catalogued
-- 1025Dex paths are redirected; cartridge graphics and other mods pass through.
return function(mod)
  local Version = require('src.core.GameVersion')
  local catalog = assert(load(assert(mod:read('compat/asset_catalog.lua'))))()
  local config = assert(load(assert(mod:read('compat/asset_config.lua'))))()
  local read, info, list = mod.read, mod.info, mod.list
  local function original(relative) return relative:match('^assets/(.+)$') end
  local directories = {}
  for path in pairs(catalog) do
    local parent, name = path:match('^(.*)/([^/]+)$')
    while parent do
      directories[parent] = directories[parent] or {}
      directories[parent][name] = true
      parent, name = parent:match('^(.*)/([^/]+)$')
    end
  end
  local facade = setmetatable({generation=Version.generation()}, {__index=mod})
  function facade:read(path) return read(mod, original(path) or path) end
  function facade:info(path)
    if catalog[path] then return info(mod, original(path)) end
    if directories[path] then return info(mod, original(path)) end
    return nil
  end
  function facade:list(path)
    local out={}
    for name in pairs(directories[path] or {}) do out[#out+1]=name end
    table.sort(out);return out
  end
  config.legacyFiles = catalog
  config.expectedFiles = catalog
  local manager = assert(load(assert(read(mod,'compat/asset_download_manager.lua'))))()(facade,config)
  mod.exports.assetManager = manager
  local function key(path)
    local k='assets/'..tostring(path)
    return catalog[k] and k or nil
  end
  function mod:read(path)
    local k=key(path)
    local bytes=k and manager:read(k)
    if bytes then return bytes end
    return read(self,path)
  end
  function mod:info(path)
    local k=key(path)
    if k and manager:exists(k) then return {type='file',size=catalog[k].size} end
    return info(self,path)
  end
  function mod:list(path)
    local out,seen={},{}
    for _,name in ipairs(list(self,path) or {}) do out[#out+1]=name;seen[name]=true end
    for name in pairs(directories['assets/'..path] or {}) do
      if not seen[name] then out[#out+1]=name end
    end
    table.sort(out);return out
  end
  local image = mod.assets.image
  mod.assets.image = function(self,path)
    local k=key(path)
    local cached=k and manager:image(k)
    if cached then return cached end
    return image(self,path)
  end
  local prefix=mod.path:gsub('\\','/'):gsub('/+$','')..'/'
  local function fileData(path)
    if type(path)~='string' then return path end
    local normalized=path:gsub('\\','/')
    if normalized:sub(1,#prefix)~=prefix then return path end
    local relative=normalized:sub(#prefix+1)
    local k=key(relative)
    local bytes=k and manager:read(k)
    if bytes then return love.filesystem.newFileData(bytes,relative) end
    return path
  end
  -- Covers the engine's GB cry loader and sprite decoders, including portable
  -- installs where cache bytes have no public filesystem path.
  for _,entry in ipairs({{love.audio,'newSource'},{love.image,'newImageData'},{love.graphics,'newImage'}}) do
    local api,name=entry[1],entry[2]
    if api and type(api[name])=='function' then
      local nextFn=api[name]
      api[name]=function(path,...) return nextFn(fileData(path),...) end
    end
  end
  return manager
end
