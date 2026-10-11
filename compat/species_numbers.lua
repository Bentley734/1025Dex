-- Public species identity is National Dex; native save IDs remain opaque.
return function(mod)
  local roster=assert(load(assert(mod:read('encounters/roster.lua'))))()
  local function normalize(s) return tostring(s or ''):upper():gsub('[^A-Z0-9]','') end
  local byName,byNational={},{}
  for _,row in ipairs(roster) do byName[normalize(row.name)]=row.id;byNational[row.id]=row.name end
  local function valid(n)
    n=tonumber(n)
    if n and n==math.floor(n) and n>=1 and n<=1025 then return n end
  end
  local function generation() return require('src.core.GameVersion').generation() end
  local function pokemon() return require('src.core.game3.pokemon') end
  local function rows() return mod.game and mod.game.data and mod.game.data.pokemon or {} end
  local api={apiVersion=1,numbering='national',maxNational=1025}
  function api.nationalOfSpecies(id)
    if generation()==3 then
      local P=pokemon()
      if type(id)=='string' and not tonumber(id) then id=P.speciesFromName(id) end
      return id and valid(P.national(tonumber(id))) or nil
    end
    -- GB native IDs are name keys. A number here is not implicitly National.
    if type(id)~='string' then return nil end
    local row=rows()[id]
    if not row and mod.content and mod.content.pokemon then row=mod.content.pokemon:get(id) end
    if row and not row.form then return valid(row.dex) end
    return nil
  end
  function api.keyFromNational(n)
    n=valid(n);if not n then return nil end
    if generation()==3 then
      local P=pokemon();local slot=P.speciesFromNational(n)
      return slot and P.keyName(slot) or nil
    end
    for id,row in pairs(rows()) do if not row.form and row.dex==n then return id end end
    local key=byNational[n]
    local row=key and mod.content and mod.content.pokemon and mod.content.pokemon:get(key)
    if row and not row.form and row.dex==n then return key end
    -- Names with punctuation may differ between cartridge registries.
    for id,row in pairs(rows()) do if not row.form and byName[normalize(id)]==n then return id end end
  end
  function api.speciesFromNational(n)
    n=valid(n);if not n then return nil end
    if generation()==3 then return pokemon().speciesFromNational(n) end
    return api.keyFromNational(n)
  end
  mod.exports.speciesNumbers=api
end
