local root=arg[1];local function d(p)return assert(loadfile(root..'/encounters/'..p))()end
local P=d('policy.lua');local r=d('roster.lua');local l=d('locations.lua');for _,x in ipairs(d('hoenn_locations.lua'))do l[#l+1]=x end
local channels=d('campaign_terrains.lua');local enabled=true;local p=P.new(r,l,nil,nil,function()return enabled end,d('campaign.lua'),d('campaign_terrains.lua'))
local seen={};local sums={0,0};local maps={0,0};local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
for _,loc in ipairs(l)do for _,t in ipairs({'land','water','fishing','rocks'})do
 local native=channels[loc.map:gsub('[^%w]',''):upper()];local valid=native and native[t]
 local a,profile=p:pool(loc.map,17,t,{postgame=true});local n=0
 for _,k in ipairs({'common','rare','featured','special','ultra'})do for _,m in ipairs(a[k])do
  if valid then seen[m.id]=true;n=n+1 end
  check((a.native and a.native[m.id]) or p:campaignAtlas().regions[m.id]==(loc.hoenn and 'hoenn' or 'kanto'),'region '..m.id)
  check((a.native and a.native[m.id]) or P.allows(m,t),'terrain '..m.id)
 end end
 if n>0 then local i=loc.hoenn and 2 or 1;sums[i]=sums[i]+n;maps[i]=maps[i]+1 end
 local locked=p:pool(loc.map,17,t,{postgame=false});check(#locked.special+#locked.ultra==0,'postgame lock')
 for choice=1,17 do
  local pool=p:pool(loc.map,choice,t,{postgame=true})
  for _,k in ipairs({'common','rare','special','ultra'})do for _,m in ipairs(pool[k])do
   check(pool.residentSlots or (m.id>=P.choices[choice].first and m.id<=P.choices[choice].last),'gen range')
  end end
 end
end end
local missing={};for _,m in ipairs(r)do if not seen[m.id]then missing[#missing+1]=m.id end end
check(#missing==0,'coverage missing '..table.concat(missing,','))
local standalone=P.new(r,l)
enabled=false
for _,loc in ipairs(l)do for _,t in ipairs({'land','water','fishing','rocks'})do
 local a=p:pool(loc.map,17,t,{postgame=true});local b=standalone:pool(loc.map,17,t,{postgame=true})
 for _,k in ipairs({'common','rare','featured','special','ultra'})do
  check(#a[k]==#b[k],'standalone count')
  for i,m in ipairs(a[k])do check(m.id==b[k][i].id,'standalone species')end
 end
end end
print('Campaign checks',checks,'regional totals',p:campaignAtlas().counts.kanto,p:campaignAtlas().counts.hoenn)
print('DENSITY',sums[1]/maps[1],sums[2]/maps[2])
