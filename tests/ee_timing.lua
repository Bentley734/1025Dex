local source=assert(io.open('sprites/main.lua')):read('*a')
local pause,loops=7,1
local env=setmetatable({DATA={},opt=function(k,d)if k=='ee_pause'then return pause elseif k=='ee_loops'then return loops elseif k=='ee_alt_pause' or k=='ee_alt_loops'then return 0 end;return d end},{__index=_G})
local first=assert(source:find('  function DATA.eeFrame(',1,true))
local last=assert(source:find('  local function wantShiny()',first,true))
assert(load(source:sub(first,last-1),'EE configurable clock','t',env))()
for p=1,7 do for l=1,5 do
 pause,loops=p,l
 local frames={__ee=true}
 local duration=3/12;local cycle=duration*l+p
 assert(env.DATA.eeFrame(frames,100,12,3)==1)
 for i=0,l-1 do
  assert(env.DATA.eeFrame(frames,100+i*duration+.09,12,3)==2)
  assert(env.DATA.eeFrame(frames,100+i*duration+.18,12,3)==3)
 end
 assert(env.DATA.eeFrame(frames,100+duration*l+.01,12,3)==1)
 assert(env.DATA.eeFrame(frames,100+cycle-.01,12,3)==1)
 assert(env.DATA.eeFrame(frames,100+cycle+.09,12,3)==2)
 assert(env.DATA.eeFrame(frames,100+cycle*2+.18,12,3)==3)
end end
assert(env.DATA.eeFrame({},0,12,3)==nil)
assert(env.DATA.eeFrame(nil,0,12,3)==nil)
assert(env.DATA.eeFrame({__ee=true},0,12,1)==1)
local now=300
local frames={__ee=true,__eeStarted=100}
local proxy={data={__ee=true,__eeStarted=100}}
env.DATA.spriteStyle=function()return 3 end
env.sheets={test={frames=frames,proxies={gen3=proxy}}}
env.now=function()return now end
first=assert(source:find('  function DATA.eeDexSelected(',1,true))
last=assert(source:find('  local function dexFrame(',first,true))
assert(load(source:sub(first,last-1),'production dex selection restart','t',env))()
local owner={}
env.DATA.eeDexSelected(owner,'RALTS');assert(frames.__eeStarted==300 and proxy.data.__eeStarted==300)
now=301;env.DATA.eeDexSelected(owner,'RALTS');assert(frames.__eeStarted==300)
env.DATA.eeDexSelected(owner,'KIRLIA');assert(frames.__eeStarted==301)
now=302;env.DATA.eeDexSelected(owner,'RALTS');assert(frames.__eeStarted==302)
now=303;env.DATA.eeDexSelected({},'RALTS');assert(frames.__eeStarted==303)
local options=dofile('sprites/options.lua');local rows={};for _,r in ipairs(options)do rows[r.key]=r end
assert(#rows.ee_pause.choices==7 and #rows.ee_loops.choices==5)
print('PASS all 35 pause/loop combinations, complete pauses, repeated playback and cached Dex reselect/reopen')
local alternatePause,alternateLoops=0,0
env.opt=function(k,d)
 if k=='ee_pause'then return pause elseif k=='ee_loops'then return loops
 elseif k=='ee_alt_pause'then return alternatePause elseif k=='ee_alt_loops'then return alternateLoops end
 return d
end
local pairsChecked=0
for p=1,7 do for l=1,5 do for ap=0,7 do for al=0,5 do
 pause,loops,alternatePause,alternateLoops=p,l,ap,al
 local f={__ee=true};env.DATA.eeFrame(f,0,12,3)
 local duration=3/12;local primary=duration*l+p
 local actualLoops=al==0 and l or al;local actualPause=ap==0 and p or ap
 local pair=primary+duration*actualLoops+actualPause
 for burst=0,1 do
  local start=burst==0 and 0 or primary;local n=burst==0 and l or actualLoops
  for i=0,n-1 do
   assert(env.DATA.eeFrame(f,start+i*duration+.09,12,3)==2)
   assert(env.DATA.eeFrame(f,start+i*duration+.18,12,3)==3)
  end
  assert(env.DATA.eeFrame(f,start+n*duration+.01,12,3)==1)
 end
 assert(env.DATA.eeFrame(f,pair-.01,12,3)==1)
 assert(env.DATA.eeFrame(f,pair+.09,12,3)==2)
 assert(env.DATA.eeFrame(f,pair+primary+.18,12,3)==3)
 pairsChecked=pairsChecked+1
end end end end
assert(rows.ee_alt_pause.default==1 and #rows.ee_alt_pause.choices==8)
assert(rows.ee_alt_loops.default==3 and #rows.ee_alt_loops.choices==6)
print('PASS '..pairsChecked..' primary/alternate combinations, independent SAME settings, full pauses and repeated pairs')
