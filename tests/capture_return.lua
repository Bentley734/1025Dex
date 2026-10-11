local engine=arg[1] or '../engine-oct3';local root=arg[2] or '.';local checks=0
local function eq(a,b,msg)checks=checks+1;assert(a==b,msg..': '..tostring(a)..' ~= '..tostring(b))end
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local function extract(s,start,finish,env)
 local a=assert(s:find(start,1,true));local b=assert(s:find(finish,a+1,true))
 return assert(load(s:sub(a,b-1),'production function','t',env))()
end
package.loaded['src.core.game3.gba_fx']={}
local Pal=assert(loadfile(engine..'/src/core/game3/pal_fade.lua'))();package.loaded['src.core.game3.pal_fade']=Pal
local Stack=assert(loadfile(engine..'/src/ui/game3/stack.lua'))();package.loaded['src.ui.game3.stack']=Stack
local P={_names=true,name=function()return 'ARMAROUGE'end,national=function(n)return n-64 end,
 speciesFromNational=function(n)return n+64 end,picSpecies=function(n)return n end,isShiny=function(m)return m.shiny end,
 frontPic=function(sp,_,shiny,pid)return {image={species=sp,shiny=shiny,pid=pid}}end}
package.loaded['src.core.game3.pokemon']=P
package.loaded['src.core.game3.runtime']={getSession=function()return {dex={}}end}
for _,n in ipairs({'scene_kit','pokedex_gfx','pokedex_list','pokedex_area','pokedex_cry','mapsec'})do package.loaded['src.ui.game3.rse.'..n]={}end
package.loaded['src.ui.game3.frlg_font']={};package.loaded['src.core.game3.rom_text']={};package.loaded['src.ui.game3.rse.pokedex']={}
local R=assert(loadfile(root..'/compat/emerald_pokedex.lua'))()
local envR=setmetatable({Pokedex=R,newView=function()return {}end,pokemon=function()return P end,
 push=function(s)R.Host._s=s;Stack.push(R.ID,R.Host);return s end},{__index=_G})
extract(read(root..'/compat/emerald_pokedex.lua'),'function Pokedex.showCaughtMon(','function Pokedex.active()',envR)
local F={resetScreenState=function()end,categoryForSpecies=function()end};package.loaded['src.ui.game3.pokedex']=F
local envF=setmetatable({Pokedex=F,PokedexData={init=function()end},PokedexChrome={install=function()end},Pokemon=P,
 Dex={new=function()return {}end},Stack=Stack,play_cry=function()end},{__index=_G})
local fr=read(engine..'/src/ui/game3/pokedex.lua')
extract(fr,'function Pokedex.showRegistration(','-- pokedex_screen.c',envF)
extract(fr,'function Pokedex.close()','function Pokedex.isOpen()',envF)
local uiSource=read(engine..'/src/core/game3/battle/ui.lua')
for _,version in ipairs({'v043','current'})do
 local source=read(engine..(version=='v043' and '/v043' or '')..'/src/core/game3/battle/init.lua')
 for _,family in ipairs({'frlg','rse'})do for _,first in ipairs({true,false})do for _,pc in ipairs({true,false})do for _,shiny in ipairs({true,false})do for _,skip in ipairs({true,false})do for _,nicknameFirst in ipairs({true,false})do
  Stack.clear();local prompts,cb,gives=0,nil,0;local U={}
  U.clearCaughtDexScene=function()U._caughtDexScene=nil end
  U.askYesNo=function(_,done)eq(U._caughtDexScene,nil,'prompt restored ordinary battle UI');prompts=prompts+1;cb=done end
  if version=='current' then extract(uiSource,'function Ui.beginCaughtDexScene(','function Ui.clearCaughtDexScene()',setmetatable({Ui=U},{__index=_G}))end
  local mon={species=1001,personality=12345,otId=123,otSecretId=456,shiny=shiny,name='ARMAROUGE'}
  local B={_active=true,_phase='catching',_st={enemy={mon=mon}}}
  package.loaded['src.core.game3.battle']=B;package.loaded['src.core.game3.battle.ui']=U
  package.loaded['src.core.game3.scripting.adapters']={host=function()return {}end}
  local function installNickname()assert(loadfile('tests/fixtures/no_nickname.lua'))()({generation=3,options={define=function()end,get=function()return not skip end}})end
  if nicknameFirst then installNickname()end
  assert(loadfile(root..'/compat/catch_return.lua'))()();assert(loadfile(root..'/compat/catch_return.lua'))()()
  if not nicknameFirst then installNickname()end
  package.loaded['src.core.game3.battle.catching']={givePending=function()gives=gives+1 end}
  package.loaded['src.core.game3.storage']={pcTransferMessage=function()return 'Sent to PC'end}
  U.push=function(t)eq(t,'Sent to PC','transfer message preserved')end
  local env=setmetatable({Ui=U,Battle=B,Pokemon=P,Wally={active=function()return false end},
   BattleProfile={of=function()return {family=family}end},BattleText={get=function()return 'Give a nickname?'end}},{__index=_G})
  extract(source,'local function finish_catch_flow(','-- pokefirered/src/battle_main.c:1455',env)
  B.startPostCatchFlow({firstTimeCaught=first,mon=mon,location=pc and 'pc' or 'party',pending=pc})
  if first then
   eq(B._phase,'pokedex_reg','first catch shows entry')
   if family=='frlg' then eq(Stack.has('pokedex'),true,'FR card owns stack');F.close();eq(Stack.has('pokedex'),false,'FR card closes')
   else
    local s=R.Host._s;s.state=4;s.pal=Pal.new();s.monSprites={};R.tasks.caught(s)
    if arg[3]~='baseline' then eq(s.caught.mon.img.shiny,version=='current' and shiny or false,'shiny caught card')end
    while s.pal:fadeActive()do s.pal:updateFade()end
    R.tasks.caughtExit(s);eq(Stack.has(R.ID),false,'RSE card closes');eq(R.Host._s,nil,'RSE host released')
   end
   if version=='current' then
    eq(B._phase,'catch_dex_return','new engine handoff reached')
    if family=='rse' then eq(U._caughtDexScene.sprite.img.species,1001,'sprite handed back');eq(U._caughtDexScene.otId,123,'OT retained');eq(U._caughtDexScene.shiny,shiny,'shiny retained')end
    local n=0;while not U.updateCaughtDexScene()do n=n+1;assert(n<100,'fade hangs')end
    eq(U._caughtDexScene,nil,'caught portrait released before nickname or PC callback')
    local done=B._catchDexReturn;B._catchDexReturn=nil;done()
   end
  end
  if skip then eq(prompts,0,'No-Nickname skip retained')
  else eq(prompts,1,'exactly one nickname question');eq(B._phase,'catch_nickname_prompt','question reachable');cb(false)end
  if pc then eq(gives,1,'pending capture stored once');eq(B._phase,'catch_pc_msg','PC message reached')
  else eq(B._phase,'ending','capture finishes');eq(B._pendingEnd,'catch','outcome retained')end
  eq(U._caughtDexScene,nil,'ordinary UI restored for capture completion')
 end end end end end end
end
print('PASS: '..checks..' first/repeat capture / old/new engine / FRLG/RSE / party/PC / shiny handoff checks')
