from pathlib import Path
import os, sys
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'.tools/python'))
from lupa.lua53 import LuaRuntime
os.chdir(root/'1025Dex')
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('unpack=unpack or table.unpack; loadstring=loadstring or load')
lua.execute(Path('tests/ee_sprites.lua').read_text())
lua.execute(Path('tests/bw_sprites.lua').read_text())
for path in Path('.').rglob('*.lua'):
    ok,error=lua.eval('function(s)local f,e=load(s);return f~=nil,e end')(path.read_text(encoding='utf-8-sig'))
    assert ok,(path,error)
print('PASS all Lua syntax and existing Gen9/BW sprite regression checks')
