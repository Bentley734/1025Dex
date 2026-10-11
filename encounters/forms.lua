-- Shared, deterministic post-League form pools. Exact form ids stay intact.
local M={chance=2,minLevel=55,maxLevel=70}
local function normal(s)return tostring(s or ''):upper():gsub('[^A-Z0-9]','')end
function M.location(map,gen)
 local n=normal(map)
 if gen==1 then return n:find('CERULEANCAVE',1,true)~=nil or n:find('UNKNOWNDUNGEON',1,true)~=nil or n:find('VICTORYROAD',1,true)~=nil end
 if gen==2 then return n:find('SILVERCAVE',1,true)~=nil or n:find('MTSILVER',1,true)~=nil or n=='ROUTE28' or n=='DRAGONSDENB1F' or n:find('VICTORYROAD',1,true)~=nil end
 return n:find('CERULEANCAVE',1,true)~=nil or n:find('VICTORYROAD',1,true)~=nil
  or n:find('SKYPILLAR',1,true)~=nil or n:find('ARTISANCAVE',1,true)~=nil
  or n:find('METEORFALLSB1F2R',1,true)~=nil or n:find('SEVAULTCANYON',1,true)~=nil
end
function M.new(national,roster,Policy,gen,cleared,resolve)
 local bases,forms={},{}
 for _,row in ipairs(roster)do bases[normal(row.name)]=row end
 for id,row in pairs(national.register or {})do
  if row.form then
   local base=bases[normal(row.baseSpecies)]
   assert(base,'Missing form base '..id)
   forms[#forms+1]={id=row.dex,name=id,displayName=row.name,form=row.form,baseDex=base.id,
    habitat=base.habitat,catchRate=row.catchRate or base.catchRate,base=base}
  end
 end
 table.sort(forms,function(a,b)return a.id<b.id end)
 local self={forms=forms}
 function self:pool(map,terrain,choice)
  if not cleared() or not M.location(map,gen) then return {} end
  choice=choice or Policy.choices[Policy.default]
  local out={}
  for _,form in ipairs(forms)do
   if form.baseDex>=choice.first and form.baseDex<=choice.last and Policy.allows(form.base,terrain) then
    local species=resolve(form.name)
    if species then
     local copy={};for k,v in pairs(form)do if k~='base' then copy[k]=v end end
     copy.species=species;copy.minLevel=M.minLevel;copy.maxLevel=M.maxLevel
     out[#out+1]=copy
    end
   end
  end
  return out
 end
 function self:choose(map,terrain,choice,rng)
  local pool=self:pool(map,terrain,choice)
  if #pool==0 then return end
  rng=rng or math.random
  if rng(1,100)>M.chance then return end
  return pool[rng(1,#pool)],rng(M.minLevel,M.maxLevel)
 end
 return self
end
return M
