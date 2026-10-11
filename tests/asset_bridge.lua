local root=arg[1]
local function file(p)local f=assert(io.open(root..'/'..p,'rb'));local s=f:read('*a');f:close();return s end
local factory=assert(load(file('compat/assets.lua')))()
local checks=0
local function eq(a,b,msg)checks=checks+1;assert(a==b,msg..': '..tostring(a)..' ~= '..tostring(b))end
local png='sprites/assets/front/BULBASAUR.png'
local cry='cries/assets/1.ogg'
local bytes={['assets/'..png]='PNG BYTES',['assets/'..cry]='OGG BYTES'}
local catalog={};for k,v in pairs(bytes) do catalog[k]={size=#v} end
local managers={}
local imageAPI={newImageData=function(p)return p end}
local audioAPI={newSource=function(p,mode)return p,mode end}
local gfx={newImage=function(p)return p end}
love={image=imageAPI,audio=audioAPI,graphics=gfx,filesystem={newFileData=function(b,n)return {bytes=b,name=n}end}}
package.loaded['src.core.GameVersion']={generation=function()return 3 end}
local manager={read=function(_,k)return bytes[k]end,exists=function(_,k)return bytes[k]~=nil end,
 image=function(_,k)return bytes[k] and 'cached image' end}
local mod={path='mods/1025Dex',exports={},assets={image=function(_,p)return 'original image:'..p end},
 read=function(_,p)
  if p=='compat/asset_catalog.lua' then return 'return fixtureCatalog' end
  if p=='compat/asset_config.lua' then return 'return {}' end
  if p=='compat/asset_download_manager.lua' then return 'return function(f,c) fixtureFacade=f;fixtureConfig=c;return fixtureManager end' end
  return 'local:'..p
 end,
 info=function(_,p)if p==png then return {type='file',size=9}end end,
 list=function()return {'local.txt'}end}
fixtureCatalog=catalog;fixtureManager=manager
factory(mod)
eq(fixtureConfig.expectedFiles,catalog,'pinned verification catalog passed')
eq(mod:read(png),'PNG BYTES','sprite bytes read from persistent cache')
eq(mod:read(cry),'OGG BYTES','cry bytes read from persistent cache')
eq(mod:read('main.lua'),'local:main.lua','code never redirected')
eq(mod:info(png).size,9,'cached sprite info')
eq(mod.assets:image(png),'cached image','icons decode from cache')
eq(mod.assets:image('other.png'),'original image:other.png','unmanaged image passthrough')
eq(imageAPI.newImageData('mods/1025Dex/'..png).bytes,'PNG BYTES','sprite decoder accepts FileData')
eq(gfx.newImage('mods\\1025Dex\\'..png:gsub('/','\\')).bytes,'PNG BYTES','Windows paths normalized')
local source,mode=audioAPI.newSource('mods/1025Dex/'..cry,'static')
eq(source.bytes,'OGG BYTES','GB and Gen3 cry loaders accept cached FileData')
eq(mode,'static','audio mode retained')
eq(audioAPI.newSource('mods/other/'..cry),'mods/other/'..cry,'other mods never redirected')
eq(imageAPI.newImageData('data/generated/native.png'),'data/generated/native.png','ROM asset passthrough')
eq(fixtureFacade:read('assets/'..png),'local:'..png,'legacy migration uses physical files')
eq(fixtureFacade:info('assets/'..png).size,9,'legacy migration detects physical assets')
bytes['assets/'..png]=nil
eq(mod:read(png),'local:'..png,'missing cache falls back to installed assets')
eq(imageAPI.newImageData('mods/1025Dex/'..png),'mods/1025Dex/'..png,'missing cache preserves original decoder input')
print('PASS asset bridge: '..checks..' cache, decoder, portable bytes, migration and isolation checks')
