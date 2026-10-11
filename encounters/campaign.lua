-- A stable two-region atlas, derived from the existing legal habitat/level pools.
-- No gameplay RNG, save migration, or changes to standalone encounters.
local M={version='kanto-hoenn-2'}
function M.new(policy,channels)
 local atlas,regions,counts={},{},{kanto=0,hoenn=0}
 local terrains={'land','water','fishing','rocks'}
 local groups={'common','rare','featured','special','ultra'}
 local candidates={}
 for index,base in ipairs(policy.locations) do
  for _,terrain in ipairs(terrains) do
   -- Allocate only where the supplied ROM actually has this encounter channel.
   local native=channels and channels[base.map:gsub('[^%w]',''):upper()]
   local usable=not channels or (native and native[terrain])
   if usable then
    local pool=policy:pool(base.map,17,terrain,{postgame=true,campaign=false})
    local region=base.hoenn and 'hoenn' or 'kanto'
    for _,group in ipairs(groups) do for _,mon in ipairs(pool[group]) do
     local entry=candidates[mon.id] or {};candidates[mon.id]=entry
     entry[region]=entry[region] or {};entry[region][terrain]=entry[region][terrain] or {}
     local list=entry[region][terrain];local seen=false
     for _,home in ipairs(list) do if home.map==base.map then seen=true end end
     if not seen then list[#list+1]={map=base.map,hi=base.hi or 100,
       featured=group=='featured',home=mon.location==index,
       native=base[terrain] and base[terrain].native and base[terrain].native[mon.id]} end
    end end
   end
  end
 end
 for _,mon in ipairs(policy.roster) do
  local c=candidates[mon.id] or {}
  local preferred=mon.id==90 and 'hoenn' or mon.gen==1 and 'kanto' or mon.gen==3 and 'hoenn'
   or (counts.kanto<=counts.hoenn and 'kanto' or 'hoenn')
  local other=preferred=='kanto' and 'hoenn' or 'kanto'
  local region=c[preferred] and preferred or c[other] and other
  if region then
   regions[mon.id]=region;counts[region]=counts[region]+1
   for terrain,homes in pairs(c[region]) do
    table.sort(homes,function(a,b)
     if a.featured~=b.featured then return a.featured end
     if not not a.native~=not not b.native then return not not a.native end
     if a.home~=b.home then return a.home end
     -- Deterministic spread within equally suitable areas.
     local function score(s)local h=mon.id*97;for i=1,#s do h=(h*33+s:byte(i))%2147483647 end;return h end
     local x,y=score(a.map),score(b.map);return x==y and a.map<b.map or x<y
    end)
    -- One primary home and one alternate per encounter channel.
    for i=1,math.min(2,#homes) do
     local k=homes[i].map..':'..terrain;atlas[k]=atlas[k] or {};atlas[k][mon.id]=true
    end
   end
  end
 end
 return {
  regions=regions,counts=counts,
  filter=function(_,map,terrain,pool)
   local allowed=atlas[map..':'..terrain] or {};local out={}
   for k,v in pairs(pool) do out[k]=v end
   for _,group in ipairs(groups) do
    out[group]={};for _,mon in ipairs(pool[group]) do
     if allowed[mon.id] or (pool.native and pool.native[mon.id]) then out[group][#out[group]+1]=mon end
    end
   end
   -- Keep unselected neighbouring maps playable without restoring giant pools.
   if #out.common+#out.rare+#out.featured==0 then
    local hoenn=pool.location and pool.location.hoenn
    local wanted=hoenn and 'hoenn' or 'kanto'
    for _,group in ipairs({'common','rare','featured'}) do
     for _,mon in ipairs(pool[group]) do
      if regions[mon.id]==wanted and #out.common+#out.rare+#out.featured<3 then
       out[group][#out[group]+1]=mon
      end
     end
    end
   end
   -- A single-generation/range option can exclude every regional resident.
   -- Use at most three legal visitors rather than reverting to an out-of-range
   -- native species; the full 1025 campaign keeps its exclusive assignment.
   if #out.common+#out.rare+#out.featured==0 and pool.choice
      and (pool.choice.first~=1 or pool.choice.last~=1025) then
    for _,group in ipairs({'common','rare','featured'}) do
     for _,mon in ipairs(pool[group]) do
      if #out.common+#out.rare+#out.featured<3 then out[group][#out[group]+1]=mon end
     end
    end
   end
   -- Diglett's weighted native identity is intentionally retained.
   return out
  end,
  belongs=function(_,mon,hoenn)return regions[mon.id]==(hoenn and 'hoenn' or 'kanto')end,
 }
end
return M
