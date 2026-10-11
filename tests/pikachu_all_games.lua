local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local engine=read('../gen1recomp-0.3.54/src/core/Sound.lua')
local modSource=read('cries/main.lua')
local checks=0
for _,game in ipairs({'red','blue','yellow','gold','silver','crystal'})do
 local style='original';local files={}
 local version={generation=function()return (game=='gold' or game=='silver' or game=='crystal') and 2 or 1 end,isYellow=function()return game=='yellow'end}
 local modules={['src.render.Assets']={register=function()end},['src.core.Logger']={warn=function()end},
 ['src.mods.Runtime']={wants=function()return false end,reportError=function()end},['bit']=require('bit'),['src.core.GameVersion']=version}
 local env=setmetatable({require=function(n)return assert(modules[n],n)end,love={audio={newSource=function(file)
  files[#files+1]=file
  return {play=function(s)s.playing=true end,stop=function(s)s.playing=false end,
  setVolume=function()end,setPitch=function()end,getDuration=function()return 1 end,isPlaying=function(s)return s.playing end}
 end}}},{__index=_G})
 local Sound=assert(load(engine,'engine Sound','t',env))();modules['src.core.Sound']=Sound
 local broken={pokemon={PIKACHU={dex=25}},audio={cries={PIKACHU={base='BASE',file='packed.ogg'},BASE={file='base.ogg'}}}}
 assert(Sound.playCry(broken,'PIKACHU',false)==nil,'old inherited file override must reproduce failure')
 local records={PIKACHU={base='BASE'},BASE={header={}}}
 local registry={get=function(_,id)return records[id]end,register=function(_,id,v)records[id]=v end,override=function()error('ROM cry definitions must not be merged with files')end}
 local mod={options={define=function()end,get=function()return style end},exports={},assets={path=function(_,p)return 'cries/'..p end},
 content={pokemon={get=function()return {dex=25}end},cries=registry},
 info=function(_,p)return {type='file'}end,rootRead=function()return 'return {patch={PIKACHU={dex=25}},register={}}'end,log={info=function()end}}
 assert(load(modSource,'production cries','t',env))()(mod)
 for _,choice in ipairs({'original','anime','showdown','pokeapi'})do
  style=choice;local src=Sound.playCry(broken,'PIKACHU',false)
  assert(src and src.playing,game..' '..choice..' must play Pikachu')
  assert(Sound.isPlaying('cry:PIKACHU') and Sound.waitFramesFor('cry:PIKACHU')>0,'native wait and cache key retained')
  checks=checks+1
 end
 assert(records.PIKACHU.base=='BASE' and records.PIKACHU.file==nil,'ROM base chain preserved')
 print('PASS Pikachu all four styles with actual Sound engine: '..game)
end
print('PASS '..checks..' actual-engine Pikachu playback and canonical wait cases')
