-- Full asset-manager entry with the engine's actual singleton Gen3 stack.
-- Run from KIM: texlua tests/asset_manager_gen3.lua
local checks=0
local function eq(a,b,why)checks=checks+1;assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b))end
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local source=read('compat/asset_download_manager.lua')
for _,generation in ipairs({3,1,2})do
 local Stack=assert(loadfile((arg and arg[3]or '../gen1recomp-0.3.54')..'/src/ui/game3/stack.lua'))()
 local cache,registry,hooks,events,drawn={},{},{},{},{}
 local legacyPushes,confirms=0,0
 local legacyTextCalls=0
 local nativeTextCalls,frames=0,0
 local stackDepth=0
 local SM={ENTRIES={},cursor=1,confirm=function()confirms=confirms+1 end}
 local Rows={build=function()return {{id="native",label="NATIVE"}}end}
 local fs={newFile=function()end,getInfo=function()end,remove=function()end}
 local fetchStarted,cancelled=0,0
 local nativeWindow={template=function(x,y,w,h)eq(w,28,'Gen3 native frame width');eq(h,18,'Gen3 native frame height');return {}end,
  fill=function()end,stdFrame=function()frames=frames+1 end,
  printPx=function(text,x,y,opts)
   nativeTextCalls=nativeTextCalls+1
   eq(opts.colors.fg[1]<.2,true,'dark native glyph color')
   eq(opts.colors.fg[4],1,'opaque native glyphs')
   eq(opts.maxWidth<=240-x,true,'text stays within Gen3 screen')
   drawn[#drawn+1]=text
  end}
 local modules={['src.ui.game3.option_rows']=Rows,['src.ui.game3.window']=nativeWindow,['src.ui.game3.stack']=Stack,['src.ui.game3.start_menu']=SM,
  ['src.core.SaveData']={persistenceFs=function()return fs end},
  ['src.mods.ModUpdate']={beginFetchReleases=function()return {}end,pumpFetchReleases=function()
   return true,{{version='1.0.0',zip={url='fixture://asset.zip',size=1024}}}
  end},['src.net.Fetch']={download=function()fetchStarted=fetchStarted+1;return {}end,
   cancel=function()cancelled=cancelled+1 end,release=function()end}}
 local mod={generation=generation,content={screens={register=function(_,id,def)registry[id]=def end}},
  cache={read=function(_,key)return cache[key]end,write=function(_,key,value)cache[key]=value;return true end,
   info=function(_,key)return cache[key] and {type="file",size=#cache[key]} or nil end,delete=function(_,key)cache[key]=nil;return true end},
  info=function()return nil end,list=function()return {}end,
  log={info=function()end,error=function(_,fmt,err)error(string.format(fmt,err))end},
  hooks={wrap=function(_,name,fn)hooks[name]=fn end},events={on=function(_,name,fn)events[name]=fn end},
  ui={Font={drawBox=function()end,draw=function(text)legacyTextCalls=legacyTextCalls+1;drawn[#drawn+1]=text end},
   insertBefore=function(out,_,entry)out[#out+1]=entry;return out end,
   push=function(game,id)
    legacyPushes=legacyPushes+1
    if generation==3 then error('Gen1/2 ui.push unsupported on Gen3')end
    game.view=registry[id].new(game)
   end},
 }
 local env=setmetatable({require=function(name)if modules[name]then return modules[name]end;error(name)end,
  love={timer={getTime=function()return 0 end},graphics={
   push=function()stackDepth=stackDepth+1 end,pop=function()stackDepth=stackDepth-1 end,
   rectangle=function()end,setShader=function()end,setScissor=function()end,setBlendMode=function()end,setColor=function()end,
  }}},{__index=_G})
 local manager=assert(load(source,'production asset manager','t',env))()(mod)
 local game={stack={pop=function()end}}
 events['game.ready']({game=game})
 if generation==3 then
  eq(Stack.depth(),1,'first boot prompts for missing assets')
  Stack.top().mod.handleInput({wasPressed=function(_,key)return key=='b'end})
  eq(Stack.depth(),0,'download-later dismisses first-boot prompt')
 end
 eq(hooks['ui.start_menu.items'],nil,'no asset entry in Start')
 eq(hooks['ui.title_menu.items'],nil,'no asset entry in title')
 local entries=generation==3 and Rows.build({game=game}) or hooks['ui.options.rows'](function()return {{id='native',label='NATIVE'}}end,game,{})
 eq(#entries,1,'ASSETS removed from root OPTION rows')
 eq(type(manager.open),'function','asset manager exposes nested settings action')
 local function selectAsset()manager.open(game)end
 if generation==3 then
  eq(#Rows.build({game=game}),1,'row builder does not duplicate entries')
  selectAsset()
  eq(Stack.depth(),1,'selection opens native Gen3 layer')
  eq(legacyPushes,0,'does not call unsupported ui.push')
  local layer=Stack.top().mod
  layer.draw();eq(drawn[1],'1025Dex','screen draws')
  eq(legacyTextCalls,0,'Gen3 never calls incompatible legacy font')
  eq(nativeTextCalls>0,true,'Gen3 native font receives text')
  eq(stackDepth,0,'graphics state restored')
  for _,status in ipairs({'idle','checking','downloading','extracting','migrating','deleting','confirm_delete','delete_error','deleted','error','done'})do
   manager.state=status;drawn={};layer.draw()
   eq(drawn[1],'1025Dex',status..' visible heading')
   eq(#drawn>=4,true,status..' visible body and instructions')
   eq(stackDepth,0,status..' balanced graphics state')
  end
  manager.state='idle'
  -- Native drawing failures must not leak a graphics-state push.
  local printer=nativeWindow.printPx;nativeWindow.printPx=function()error('fixture draw failure')end
  local ok=pcall(layer.draw);eq(ok,false,'draw error propagated')
  eq(stackDepth,0,'draw failure restores graphics state');nativeWindow.printPx=printer
  layer.handleInput({wasPressed=function(_,key)return key=='a'end})
  eq(manager.state,'checking','A starts asset release check')
  layer.update(.016)
  eq(manager.state,'downloading','native update advances download')
  eq(fetchStarted,1,'download starts once')
  layer.handleInput({wasPressed=function(_,key)return key=='b'end})
  eq(cancelled,1,'B cancels live download')
  eq(Stack.depth(),0,'B removes only manager layer')
  SM.confirm();eq(confirms,1,'Start confirmation remains untouched')
  -- Installed packs expose maintenance without forcing a re-download.
  selectAsset();layer=Stack.top().mod;manager.state='done'
  eq(Stack.depth(),1,'maintenance opens')
  layer.handleInput({wasPressed=function(_,key)return key=='a'end})
  eq(manager.state,'confirm_delete','A requests deletion confirmation')
  layer.handleInput({wasPressed=function(_,key)return key=='b'end})
  eq(manager.state,'done','B cancels deletion')
  layer.handleInput({wasPressed=function(_,key)return key=='b'end})
  eq(Stack.depth(),0,'B closes installed screen')
  local asset='assets/battle/backgrounds/hd/fixture.png'
  cache['kim_assets/installed-files.txt']=asset..'\n'
  cache['kim_assets/files/'..asset]='fixture asset'
  cache['kim_assets/complete.txt']='zip:1.0.0'
  cache['unrelated.txt']='keep'
  selectAsset();layer=Stack.top().mod;manager.state='done'
  layer.handleInput({wasPressed=function(_,key)return key=='a'end})
  eq(cache['kim_assets/files/'..asset],'fixture asset','first A does not delete')
  layer.handleInput({wasPressed=function(_,key)return key=='a'end})
  eq(manager.state,'deleting','second A starts deletion')
  layer.handleInput({wasPressed=function(_,key)return key=='b'end})
  eq(Stack.depth(),1,'deletion is not interrupted')
  for i=1,100 do if manager.state=='deleting' then layer.update(.016)end end
  eq(manager.state,'deleted','deletion completes')
  eq(cache['kim_assets/files/'..asset],nil,'pack asset removed')
  eq(cache['kim_assets/complete.txt'],nil,'completion marker removed')
  eq(cache['unrelated.txt'],'keep','unrelated cache preserved')
  eq(cache['kim_assets/deferred.txt'],'1.2.0','intentional removal is deferred')
  layer.handleInput({wasPressed=function(_,key)return key=='a'end})
  eq(manager.state,'checking','removed pack can re-download')
  layer.handleInput({wasPressed=function(_,key)return key=='b'end})
  eq(Stack.depth(),0,'close re-download')
  -- Errors must be visible instead of silently doing nothing.
  mod.cache=nil;selectAsset();layer=Stack.top().mod
  layer.handleInput({wasPressed=function(_,key)return key=='a'end})
  eq(manager.state,'error','missing cache is reported')
  eq(manager.error:find('mod.cache',1,true)~=nil,true,'specific actionable error')
  layer.draw();eq(#drawn>3,true,'error screen still renders')
  layer.handleInput({wasPressed=function(_,key)return key=='b'end})
  eq(Stack.depth(),0,'close error screen')
  Stack.push('option',{}, {hideBelow=true,fullscreen=true})
  selectAsset();layer=Stack.top().mod
  eq(Stack.depth(),2,'assets opens above OPTION')
  layer.handleInput({wasPressed=function(_,key)return key=='b'end})
  eq(Stack.depth(),1,'B returns to OPTION')
  eq(Stack.top().id,'option','OPTION retained underneath')

 else
  selectAsset()
  eq(legacyPushes,1,'Gen1/2 legacy push retained')
  game.input={wasPressed=function(_,key)return key=='a'end}
  game.view:update(.016)
  eq(manager.state,'checking','Gen1/2 update routes input')
 end
end
print(('PASS: %d assertions; Gen3 menu activation, real stack, input/update/draw/close, download initiation/cancel, visible errors and Gen1/2 behavior.'):format(checks))
