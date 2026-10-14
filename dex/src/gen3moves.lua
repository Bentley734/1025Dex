-- Native TM/HM permissions use actual canonical moves, without substitutes.
local M={}
function M.load(_,dex)
 local P=require('src.core.game3.pokemon')
 local Moves=require('src.core.game3.battle.moves')
 local rules={extended={}}
 for national=1,1025 do
  local allowed={}
  if national<=386 then
   local species=P.speciesFromNational(national)
   for bit,number in pairs(P._tmhm and P._tmhm.machines or{})do
    if species and P.canLearnTmIndex(species,bit)then allowed[#allowed+1]=tonumber(number)end
   end
  else
   local info=dex.statsByDex(national)
   for _,row in ipairs(info and info.movesByMethod and info.movesByMethod.machine or{})do
    local number=Moves.numForName(row.move)
    if number then allowed[#allowed+1]=number end
   end
  end
  rules.extended[national]={tmhm=allowed}
 end
 return rules
end
function M.machineIds(rules,dex,names)
 local row=rules.extended[dex];local out={}
 for _,id in ipairs(row and row.tmhm or{})do
  local name=names[id]
  if name then out[#out+1]=name:upper():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')end
 end
 return out
end
function M.install(mod,P,slot,rules)
  local installed={}
  local function restore(species)
    local row=rules.extended[species and P.national(species)]
    local tm=P._tmhm
    if not row or not tm or not tm.machines or not tm.learnsets then return end
    if installed[species] and installed[species]==tm.learnsets[species] then return end
    local allowed={};for _,id in ipairs(row.tmhm)do allowed[id]=true end
    local lo,hi=0,0
    for bit,id in pairs(tm.machines)do
      if allowed[tonumber(id)]then
        if bit<32 then lo=lo+2^bit else hi=hi+2^(bit-32)end
      end
    end
    local bits={lo=lo,hi=hi};tm.learnsets[species]=bits;installed[species]=bits
  end
  local function apply()
    installed={}
    if not P._names then return end
    for dex in pairs(rules.extended)do restore(slot(dex))end
  end
  P.onReload(apply,'complete_dex_machine_permissions');apply()
  if not P.__completeDexMachines and type(P.canLearnTmIndex)=='function' then
    P.__completeDexMachines=true
    local original=P.canLearnTmIndex
    P.canLearnTmIndex=function(species,index)
      if not P._tmhm then P.install(P._cache)end
      restore(tonumber(species));return original(species,index)
    end
  end
end
return M
