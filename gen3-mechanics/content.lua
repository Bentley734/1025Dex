-- SPDX-License-Identifier: GPL-3.0-or-later
-- Private execution registries. They carry effect code, not a second dex.
-- Gen 3 projection is explicit; legacy string effect IDs never enter a save.
return function()
 local function copy(value)
  if type(value)~='table'then return value end
  local result={};for key,v in pairs(value)do result[key]=copy(v)end;return result
 end
 local function merge(base,patch)
  if type(patch)~='table'then return patch end
  if patch.__replace then return copy(patch.__replace)end
  local result=copy(base or{})
  if patch.__append then
   for _,value in ipairs(patch.__append)do result[#result+1]=copy(value)end
   return result
  end
  if #patch>0 then return copy(patch)end
  for key,value in pairs(patch)do
   if type(value)=='table' then result[key]=merge(result[key],value)else result[key]=value end
  end
  return result
 end
 return function(seed)
  local rows=copy(seed or{})
  return {get=function(_,id)return rows[id]end,
   each=function()
    local keys={};for id in pairs(rows)do keys[#keys+1]=id end;table.sort(keys)
    local index=0
    return function()index=index+1;local id=keys[index];if id then return id,rows[id]end end
   end,
   register=function(_,id,row)assert(not rows[id],'Duplicate effect registration: '..id);rows[id]=copy(row)end,
   override=function(_,id,row)rows[id]=copy(row)end,
   patch=function(_,id,row)rows[id]=merge(rows[id],row)end,
   remove=function(_,id)rows[id]=nil end,
   rows=rows}
 end
end
