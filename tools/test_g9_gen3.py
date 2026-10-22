from pathlib import Path
import os
from lupa.lua53 import LuaRuntime
from lupa.luajit21 import LuaRuntime as JitRuntime
root=Path(__file__).resolve().parents[1]
os.chdir(root)
for runtime in [LuaRuntime,JitRuntime]:
    lua=runtime()
    lua.execute('unpack=unpack or table.unpack;loadstring=loadstring or load')
    lua.execute(Path('tests/g9_gen3.lua').read_text())
print('PASS G9 Gen3 source and geometry tests on Lua 5.3 and LuaJIT')
