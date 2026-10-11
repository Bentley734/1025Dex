local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
local f=assert(io.open('cries/main.lua'));local code=f:read('*a');f:close()
for generation=1,3 do
 local style='original';local calls={};local schema
 local present={['assets/25.ogg']=true,['assets/1000.ogg']=true,['assets/anime/25.ogg']=true,['assets/showdown/25.mp3']=true,['assets/showdown/1000.mp3']=true}
 local invalidated=0
 local Sound={invalidate=function(key)check(key=='cry:PIKACHU','canonical cry cache invalidation');invalidated=invalidated+1 end,playCry=function(data,species,pika)
  calls[#calls+1]={species=species,pika=pika,data=data};return {native=true}
 end}
 local Audio={playCry=function()calls[#calls+1]={rom=true};return 'rom'end,stopCry=function()end,_sfxVolume=.5}
 local loaded,playing,volume,pitch
 local source={play=function()playing=true end,setVolume=function(_,v)volume=v end,setPitch=function(_,v)pitch=v end,getDuration=function()return 2 end}
 local modules={['src.core.GameVersion']={generation=function()return generation end},['src.core.Sound']=Sound,
 ['src.core.game3.audio']=Audio,['src.core.game3.pokemon']={national=function(slot)return slot==9999 and 1000 or 25 end},
 ['src.core.game3.m4a_sample']={cryParams=function(_,v)return {volume=v or 120}end,cryVoices=function()return {{mul=.8}}end}}
 local env=setmetatable({require=function(n)return assert(modules[n],n)end,love={audio={newSource=function(path)loaded=path;return source end}}},{__index=_G})
 local registry={get=function()return {dex=25}end,register=function()end,override=function()end}
 local mod={options={define=function(_,s)schema=s end,get=function()return style end},exports={},
 assets={path=function(_,p)return 'cries/'..p end},content={pokemon=registry,cries=registry},
 rootRead=function()return 'return {patch={PIKACHU={dex=25}},register={}}'end,
 info=function(_,p)return present[p] and {type='file'}end,log={info=function()end}}
 assert(load(code,'cry styles','t',env))()(mod)
 check(schema[1].key=='cryStyle' and #schema[1].choices==3,'all generations expose three styles')
 if generation<3 then
  local data={pokemon={PIKACHU={dex=25},HUGE={dex=1000}},audio={cries={}}}
  Sound.playCry(data,'PIKACHU',2);check(calls[#calls].species=='PIKACHU' and calls[#calls].pika==2,'CURRENT retains Yellow voice request')
  style='anime';Sound.playCry(data,'PIKACHU',2)
  local c=calls[#calls];check(c.species=='PIKACHU' and invalidated==1 and c.data.audio.cries[c.species].file=='cries/assets/anime/25.ogg','ANIME selects numeric voice with canonical native key')
  style='showdown';Sound.playCry(data,'PIKACHU');c=calls[#calls]
  check(c.species=='PIKACHU' and invalidated==2 and c.data.audio.cries[c.species].file=='cries/assets/showdown/25.mp3','SHOWDOWN switches immediately by invalidating previous style')
  style='anime';Sound.playCry(data,'HUGE');check(calls[#calls].species=='HUGE','missing anime falls back to current')
  check(next(data.audio.cries)==nil,'style playback leaves game cry definitions unchanged')
 else
  style='anime';Audio.playCry(25,{volume=60,mode='normal'})
  check(loaded=='cries/assets/anime/25.ogg' and playing,'native gen3 plays Anime asset')
  check(volume==.25 and pitch==.8 and Audio._cryUntil>100,'native volume pitch and completion retained')
  style='showdown';Audio.playCry(9999);check(loaded=='cries/assets/showdown/1000.mp3','expanded native slot resolves National number')
  style='anime';Audio.playCry(9999);check(loaded=='cries/assets/1000.ogg','missing anime uses current packed cry')
  present['assets/1000.ogg']=nil;check(Audio.playCry(9999)=='rom','missing packed cry falls back to native ROM')
 end
end
print('PASS '..checks..' cry style, immediate cache switch, fallback, Yellow and Gen3 mode checks')
