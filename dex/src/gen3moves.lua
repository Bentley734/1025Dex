-- Gen3 machine permissions, comparable modern attacks, and wild starter moves.
local M={}
function M.load(read)
  return assert(load(assert(read('data/species/generated/gen3_moves.lua'))))()
end
function M.machineIds(rules,dex,names)
  local row=rules.extended[dex];local out={}
  for _,id in ipairs(row and row.tmhm or {})do
    local name=names[id]
    if name then out[#out+1]=name:upper():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')end
  end
  return out
end
function M.atLevel(set,level,ppFor)
  local moves,pp,maxPp={},{},{}
  for _,row in ipairs(set or {})do
    if row[1]>level then break end
    local duplicate=false;for _,id in ipairs(moves)do if id==row[2]then duplicate=true;break end end
    if not duplicate then
      if #moves==4 then table.remove(moves,1);table.remove(pp,1);table.remove(maxPp,1)end
      local n=ppFor(row[2]);moves[#moves+1]=row[2];pp[#pp+1]=n;maxPp[#maxPp+1]=n
    end
  end
  -- Native species retain the exhausted-moves fallback. Added species use
  -- wildAtLevel's three-move starter rule instead.
  if #moves==0 then return {165},{0},{1}end
  return moves,pp,maxPp
end
function M.wildAtLevel(row,level,ppFor)
  local moves,pp,maxPp=M.atLevel(row.wildLearnset or row.learnset,level,ppFor)
  if #moves==1 and moves[1]==165 and pp[1]==0 then moves,pp,maxPp={},{},{}end
  local used={};for _,id in ipairs(moves)do used[id]=true end
  -- Padding is only needed when the eligible progression has fewer than
  -- three different moves. Keep every eligible move and its real learn level;
  -- never borrow a strong attack from the species' later progression.
  for _,id in ipairs(row.wildStarters or {})do
    if #moves>=3 then break end
    if not used[id]then
      local n=ppFor(id);used[id]=true
      moves[#moves+1]=id;pp[#pp+1]=n;maxPp[#maxPp+1]=n
    end
  end
  return moves,pp,maxPp
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
  local Version=require('src.core.GameVersion')
  mod.exports.vanillaWildMoves=function(species,level)
    local dex=P.national(species)
    local row=rules.extended[dex]
    local family=Version.get()=='emerald' and 'rse' or 'frlg'
    local set=row and row.learnset or rules.native[family][dex]
    if not set then return nil end
    if row then return M.wildAtLevel(row,tonumber(level) or 1,P.movePp)end
    return M.atLevel(set,tonumber(level) or 1,P.movePp)
  end
end
return M
