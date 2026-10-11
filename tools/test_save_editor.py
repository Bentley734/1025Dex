"""Headless embedded-editor integration using local imported caches (read only).
Usage: python tools/test_save_editor.py GAME [EXTRACTED_NATIONAL_DEX_ROOT]
The filesystem stages writes in memory. No user save is opened or changed.
"""
import sys,os
from pathlib import Path
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'.tools/python'))
if '--luajit' in sys.argv:
 from lupa.luajit21 import LuaRuntime
else:
 from lupa.lua53 import LuaRuntime
version=sys.argv[1] if len(sys.argv)>1 else 'red'
reference=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else root/'1025Dex/dex'
os.chdir(root/'gen1recomp-0.3.54')
gen3source='--gen3-source' in sys.argv
gen3check='--gen3-check' in sys.argv
gen3both='--gen3-both' in sys.argv
foreign='--foreign' in sys.argv or gen3source
l=LuaRuntime(unpack_returned_tuples=True)
if '--luajit' not in sys.argv: l.execute((root/'run_tests.py').read_text().split("lua.execute(" + chr(39)*3)[1].split(chr(39)*3 + ")")[0])
appdata=Path(os.environ['APPDATA'])/'pokemon-love2d'
def resolve(p):
 p=str(p)
 if p=='mods':return str(root/'.work/editor-mod-root')
 if foreign or gen3both:
  for name,folder in ([('national_dex_gen3',reference)] if gen3source or gen3both else [('national_dex',reference),('modern_spawns',reference.parent.parent/'modern_spawns-0.9.0')]):
   prefix='mods/'+name
   if p==prefix:return str(folder)
   if p.startswith(prefix+'/'):return str(folder/p[len(prefix)+1:])
 if p.startswith('mods/1025dex'):return str(root/'1025Dex'/p.removeprefix('mods/1025dex/')) if p!='mods/1025dex' else str(root/'1025Dex')
 if p.startswith('mods/'):return str(root/'.work/nonexistent')
 for candidate in [appdata/p,appdata/version/p,root/'gen1recomp-0.3.54'/p]:
  if candidate.exists():return str(candidate)
 return str(root/'.work/nonexistent')
l.globals().resolve=resolve
l.globals().isdir=lambda p:Path(p).is_dir()
l.globals().isfile=lambda p:Path(p).is_file()
l.globals().listdir=lambda p:l.table_from((['1025dex','national_dex_gen3'] if gen3both else ['national_dex_gen3'] if gen3source else ['national_dex','modern_spawns'] if foreign else ['1025dex']) if p=='mods' else sorted(x.name for x in Path(resolve(p)).iterdir()) if Path(resolve(p)).is_dir() else [])
l.globals().version=version
l.globals().foreign=foreign
l.globals().fixturePath=str(root/'.work'/(('foreign-gen3-save-' if gen3source or gen3check or gen3both else 'foreign-save-')+version+'.lua')).replace('\\','/')
l.globals().gen3source=gen3source
l.globals().gen3both=gen3both
l.globals().baseline='--baseline' in sys.argv
l.execute('''
package.path='./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua;'..package.path
love=require('tests.love_stub');loadstring=loadstring or load;local Logger=require('src.core.Logger');Logger.error=function(...) end
local files={}
if baseline then files['mods/1025dex/compat/national_gen3.lua']='return function(mod) end' end
if foreign then files['options.lua']=require('src.core.SaveData').encode({modOptions={national_dex={national_dex='on',type_chart='modern'}}}) end
love.filesystem={read=function(p)if files[p] then return files[p] end;if p:match('^options') or p=='mod_state.lua' then return nil end;local f=io.open(resolve(p),'rb');if f then local s=f:read('*a');f:close();return s end end,
getInfo=function(p)if p=='mods' then return {type='directory'} end;if files[p] then return {type='file'} end;if p:match('^options') then return nil end;local r=resolve(p);if isdir(r) then return {type='directory'} elseif isfile(r) then return {type='file'} end end,
getDirectoryItems=function(p)return listdir(p)end,write=function(p,s)files[p]=s;return true end,createDirectory=function()return true end,remove=function(p)files[p]=nil;return true end,getSaveDirectory=function()return '.' end,mount=function()return true end,unmount=function()return true end}
love.filesystem.load=function(p)local s=love.filesystem.read(p);if s then return load(s,'@'..p)end end
local GV=require('src.core.GameVersion');GV.set(version)
if gen3source then
 -- Match Game3's native bindings, which the standalone editor omits.
 local G=require('Gen');local bind=G.bindGame3Data
 G.bindGame3Data=function(D)
  bind(D);D.gen3Pokemon=require('src.core.game3.pokemon')
  D.gen3Moves=require('src.core.game3.battle.moves');D.gen3Items=require('src.core.game3.items_data')
  D.gen3Items.info(1)
 end
end
local App=require('App');App.load(not foreign and isfile(fixturePath) and fixturePath or '.work/absent-editor-save.lua',{version=version})
local S=App.getState()
print('EDITOR',version,'status',S.status,'missing',S.missingCache)
for _,m in ipairs(S.mods and S.mods:status().loaded or {})do print('LOADED',m.id)end
local errors=S.mods and S.mods:status().errors or {};print('ERROR COUNT',#errors);for i=1,math.min(3,#errors)do print('ERROR',errors[i])end
print('SPECIES',S.cat and #S.cat.species)
if not gen3source then assert(S.data.pokemon.CHARIZARD_MEGA_X,'Mega missing from editor data') end
''')



l.globals().dexRoot=str(root/'1025Dex').replace('\\','/')
l.globals().referenceRoot=str(reference).replace('\\','/')
if gen3source or gen3check or gen3both:
 l.execute((root/'1025Dex/tests/national_gen3_save.lua').read_text())
elif foreign:
 l.execute((root/'1025Dex/tests/foreign_save_fixture.lua').read_text())
else:
 l.execute((root/'1025Dex/tests/save_editor.lua').read_text(encoding='utf-8-sig'))
