-- Add exact ROM-backed channel profiles without moving legacy roster indices.
local M={}
local function copy(t)local out={};for k,v in pairs(t or {})do out[k]=v end;return out end
function M.prepare(locations,native)
 local out,byMap={},{}
 for i,loc in ipairs(locations)do out[i]=copy(loc);byMap[loc.map]=out[i] end
 local names={};for map in pairs(native)do names[#names+1]=map end;table.sort(names)
 for _,map in ipairs(names)do
  local loc=byMap[map]
  if not loc then
   local parent
   for _,base in ipairs(locations)do
    if base.children and map:sub(1,#base.map)==base.map and (not parent or #base.map>#parent.map)then parent=base end
   end
   local habitat=parent and parent.habitat or
    (map:find('MT_EMBER') and 'volcanic' or map:find('CAVE') and 'cave' or 'meadow')
   loc={map=map,habitat=habitat,hoenn=map:sub(1,3)=='EM_',sevii=parent and parent.sevii}
   out[#out+1]=loc;byMap[map]=loc
  end
  loc.nativeChannels=true
  for terrain,rows in pairs(native[map])do
   local profile=copy(loc[terrain]);local lo,hi=100,1
   for _,range in pairs(rows)do lo=math.min(lo,range[1]);hi=math.max(hi,range[2]) end
   profile.native=rows
   profile.lo=profile.lo or (terrain=='land' and loc.lo) or lo
   profile.hi=profile.hi or (terrain=='land' and loc.hi) or hi
   if not profile.habitat then
    if terrain=='water' or terrain=='fishing' then
     profile.habitat=(rows[72] or rows[73] or rows[90] or rows[116] or rows[320] or rows[278]) and 'sea' or 'freshwater'
    elseif terrain=='rocks' then profile.habitat='cave'
    else profile.habitat=loc.habitat end
   end
   loc[terrain]=profile
  end
  loc.lo=loc.lo or (loc.land and loc.land.lo) or 1
  loc.hi=loc.hi or (loc.land and loc.land.hi) or 100
 end
 return out
end
return M
