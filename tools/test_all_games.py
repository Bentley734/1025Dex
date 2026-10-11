"""Schema-backed boot smoke tests and native encounter/Hoennto regressions."""
import os,sys
from pathlib import Path
workspace=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(workspace/'.tools/lua-test'))
from lupa.lua53 import LuaRuntime
os.chdir(workspace/'gen1recomp-0.3.54')
bit_setup=(workspace/"run_tests.py").read_text().split("lua.execute(" + chr(39)*3)[1].split(chr(39)*3 + ")")[0]
for game in ['red','blue','yellow','gold','silver','crystal','ruby','sapphire','firered','leafgreen','emerald']:
    lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(bit_setup)
    lua.globals().arg=lua.table_from([str(workspace/'1025Dex'),game,str(workspace/'Hoennto')])
    lua.execute((workspace/'1025Dex/tests/all_games.lua').read_text())
