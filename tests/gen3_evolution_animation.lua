-- Real engine animation controller and evolution state machine; ROM/UI fixtures.
local root = assert(arg[1])
local function noop() end
local P = { national=function(s) return s > 450 and s-64 or s end,
  speciesOf=function(m) return m.species end, speciesFromName=tonumber,
  name=tostring, displayMonName=function(m) return m.nickname or tostring(m.species) end,
  frontPic=function() return {} end, picSpecies=function(s) return s end, isShiny=function() return false end }
package.loaded['src.core.game3.pokemon']=P
local Data=require('src.core.game3.mon_anim_data')
Data.available=function() return true end
Data.anims=function() return nil end
Data.delay=function() return 0 end
Data.frontAnimId=function(s) if s<=450 then return 0 end end
Data.functionName=function(id) if id==0 then return 'Anim_VerticalSquish' end end
local Anim=require('src.core.game3.mon_anim')
local Task=require('src.core.game3.task')
-- Reproduce the old failure: task disappears but sprite remains busy forever.
local broken=Anim.run(Anim.newSprite(904)) -- Applin #840 +64
Anim.doFront(broken,904,true,0)
Task.update(1/60)
assert(Anim.busy(broken) and not Task.busy(), 'old Applin deadlock reproduced')
local f=assert(io.open(root..'/dex/src/gen3animations.lua'));local src=f:read('*a');f:close()
local fix=assert(load(src))();fix.install(P)
local wrapped=Anim.doFront;fix.install(P);assert(Anim.doFront==wrapped,'idempotent install')
local cries=0
for nat=387,1025 do
  for _,flag in ipairs({0,1,2,128,129}) do
    local sprite=Anim.newSprite(nat+64)
    Anim.doFront(sprite,nat+64,false,flag,{cry=function(s,pan)
      assert(s==nat+64);assert(pan==({[0]=-25,[1]=25,[2]=0})[flag%128]);cries=cries+1
    end})
    assert(Anim.done(sprite),'added species must complete: '..nat)
    Anim.doFront(sprite,nat+64,true,flag,{cry=function() error('noCry ignored') end})
  end
end
local native=Anim.newSprite(1);Anim.doFront(native,1,true,0)
assert(Anim.busy(native) and #native.tasks==1,'native ROM animation retained')
Task.clear()
for _,name in ipairs({'stack','display','frlg_font','battle_chrome','oam','rom_text','se_ids','song_ids'}) do
  local prefix=({stack=true,frlg_font=true,battle_chrome=true})[name] and 'src.ui.game3.' or 'src.core.game3.'
  package.loaded[prefix..name]={push=noop,pop=noop,destroyAll=noop,_installed=true,has=function()return true end,box=function()return ''end,nameOf=noop}
end
local opened=false
package.loaded['src.ui.game3.message']={show=function()opened=true end,close=function()opened=false end,
  isOpen=function()return opened end,isWaiting=function()return true end,advance=function()opened=false end,tick=noop,setFrame=noop}
package.loaded['src.core.game3.audio']={playCry=noop,playSong=noop,playSe=noop,stopCry=noop,playFanfare=noop}
package.loaded['src.core.game3.evolution']={apply=function(m,s)m.species=s end}
package.loaded['src.core.game3.battle.learn_move']={busy=function()return false end,movesForLevels=function()return {}end}
local Scene=require('src.ui.game3.evolution_scene')
local input={wasPressed=function(_,key)return key=='b' end,isDown=function(_,key)return key=='b' end}
for nat=387,1025 do
  for _,cancel in ipairs({false,true}) do
    local mon={species=nat+64,nickname='CRUMBS',level=36};local result
    Scene.start(mon,905,{onDone=function(r)result=r end}) -- Flapple #841 +64
    for tick=1,1600 do
      Task.update(1/60);Scene.update(1/60)
      if cancel and Scene._state=='cycle' then Scene.handleInput(input) end
      if Scene._state=='congrats' or Scene._state=='cancel' then Scene.handleInput(input) end
      if not Scene.open then break end
    end
    assert(result==(cancel and 'stopped' or 'evolved'),'scene stalled for '..nat)
    assert(mon.species==(cancel and nat+64 or 905),'species mutation incorrect')
    assert(mon.nickname=='CRUMBS','nickname lost')
  end
end
print('PASS: reproduced Applin deadlock; 639 added species complete and cancel; '..cries..' cry/pan checks; native animation retained')
