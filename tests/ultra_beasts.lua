local P=dofile('encounters/policy.lua');local roster=dofile('encounters/roster.lua')
local locs=dofile('encounters/locations.lua');for _,l in ipairs(dofile('encounters/hoenn_locations.lua'))do locs[#locs+1]=l end
local checks=0
local function eq(a,b,msg)checks=checks+1;assert(a==b,msg..': '..tostring(a)..' ~= '..tostring(b))end
local roll=1;local denominators={}
local policy=P.new(roster,locs,function(a,b)if b then return a end;denominators[a]=true;return math.min(roll,a) end)
for _,loc in ipairs(locs)do
 for _,terrain in ipairs({'land','water','fishing','rocks'})do
  for choice=1,17 do
   for _,cleared in ipairs({false,true})do
    local pool=policy:pool(loc.map,choice,terrain,{postgame=cleared})
    for _,group in ipairs({'common','rare','featured','special'})do
     for _,mon in ipairs(pool[group])do eq(P.ultraBeasts[mon.id],nil,'UB excluded from ordinary/special pools')end
    end
    if not cleared or terrain~='land' then eq(#pool.ultra,0,'League and terrain gates')end
    for _,mon in ipairs(pool.ultra)do
     eq(mon.id>=pool.choice.first and mon.id<=pool.choice.last,true,'generation filter')
     local lo,hi=P.ultraLevelRange(mon,pool.location,pool.ultraEndgame)
     eq(lo>=45 and hi>=lo,true,'UB minimum level')
     eq(pool.ultraChance,pool.ultraEndgame and 100 or 1000,'rarity tier')
    end
   end
  end
 end
end
for _,map in ipairs({'FR_VIRIDIAN_FOREST','FR_ROUTE1','EM_ROUTE101','EM_PETALBURG_WOODS'})do
 for _,cleared in ipairs({false,true})do eq(#policy:pool(map,17,'land',{postgame=cleared}).ultra,0,'no beginner-area UBs')end
end
for _,map in ipairs(P.ultraHomes)do
 local pool=policy:pool(map,7,'land',{postgame=true});eq(#pool.ultra,11,'all UBs reachable in each designated hub')
 roll=1;denominators={};local mon,level=policy:choose(map,7,4,'land',{postgame=true})
 eq(P.ultraBeasts[mon.id],true,'forced successful UB roll');eq(level,55,'hub minimum overrides native level four')
 eq(denominators[100],true,'hub uses 1% denominator')
 roll=2;local normal=policy:choose(map,7,4,'land',{postgame=true});eq(normal==nil or not P.ultraBeasts[normal.id],true,'failed UB roll never falls back into UBs')
end
local found=false
for _,loc in ipairs(locs)do
 local pool=policy:pool(loc.map,7,'land',{postgame=true})
 if #pool.ultra>0 and not pool.ultraEndgame then
  found=true;roll=1;denominators={}
  local mon,level=policy:choose(loc.map,7,4,'land',{postgame=true})
  eq(P.ultraBeasts[mon.id],true,'ordinary high-level area has rare UBs');eq(level,45,'ordinary UB floor')
  eq(denominators[1000],true,'ordinary area uses 0.1% denominator')
 end
end
eq(found,true,'rare ordinary-area pools exist')
print('PASS: '..checks..' Ultra Beast pool, generation, League, rarity, level and fallback assertions')
