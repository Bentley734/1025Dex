from pathlib import Path
import os,sys
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'.tools/python'))
from lupa.lua53 import LuaRuntime
engine=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root/'gen1recomp-0.3.54'
os.chdir(engine)
bit_setup=(root/'run_tests.py').read_text().split('lua.execute('+chr(39)*3)[1].split(chr(39)*3+')')[0]
for game in ['red','blue','yellow','gold','silver','crystal','ruby','sapphire','emerald','firered','leafgreen']:
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(bit_setup)
    lua.globals().arg=lua.table_from([str(root/'1025Dex').replace('\\','/'),game])
    lua.execute((root/'1025Dex/tests/form_encounters.lua').read_text())
