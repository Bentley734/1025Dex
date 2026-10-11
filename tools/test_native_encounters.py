"""Run production Lua policy against every extracted native encounter."""
import os
import sys
from pathlib import Path
workspace = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(workspace / '.tools/lua-test'))
from lupa.lua53 import LuaRuntime
root = workspace / '1025Dex'
os.chdir(root)
for game in ['firered', 'leafgreen', 'emerald']:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().arg = lua.table_from([str(root), game])
    lua.execute((root / 'tests/native_encounters.lua').read_text())
for name in ['kanto_route_pools.lua', 'cave_balance.lua', 'postgame_specials.lua', 'ultra_beasts.lua', 'kanto_hoenn.lua']:
    path = root / 'tests' / name
    if path.exists():
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().arg = lua.table_from([str(root)])
        lua.execute(path.read_text())
