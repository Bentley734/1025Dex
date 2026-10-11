-- Equal odds for every registered base species and alternate-form identity.
local M={key='fullEncounterRandomizer'}
function M.new(mod,national,roster,resolve,identity)
  if mod.options then mod.options:define({{key=M.key,label='Random encounters (all forms)',type='toggle',default=false}}) end
  local candidates={}
  for _,row in ipairs(roster)do candidates[#candidates+1]={id=row.id,name=row.name,catchRate=row.catchRate}end
  for id,row in pairs(national.register or {})do
    if row.form then candidates[#candidates+1]={id=row.dex,name=id,form=row.form,catchRate=row.catchRate}end
  end
  table.sort(candidates,function(a,b)return a.id<b.id end)
  local R={}
  function R:enabled()return mod.options and mod.options:get(M.key)==true end
  function R:pool()
    local current=identity()
    if self.rows and self.identity==current and #self.rows>0 then return self.rows end
    local rows={}
    for _,row in ipairs(candidates)do
      local species=resolve(row.name)
      if species then
        local copy={};for k,v in pairs(row)do copy[k]=v end
        copy.species=species;rows[#rows+1]=copy
      end
    end
    self.rows,self.identity=rows,current
    return rows
  end
  function R:choose(level,rng)
    if not self:enabled() then return end
    local rows=self:pool();if #rows==0 then return end
    rng=rng or math.random
    return rows[rng(1,#rows)],math.max(1,math.min(100,math.floor(tonumber(level) or 1)))
  end
  return R
end
return M
