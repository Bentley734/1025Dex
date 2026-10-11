from pathlib import Path
import os
import sys

workspace = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(workspace / '.tools/python'))
from lupa.lua53 import LuaRuntime

engine = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else workspace / 'gen1recomp-0.3.54'
os.chdir(engine)
lua = LuaRuntime(unpack_returned_tuples=True)
bit_setup = (workspace / 'run_tests.py').read_text().split('lua.execute(' + chr(39)*3)[1].split(chr(39)*3 + ')')[0]
lua.execute(bit_setup)
lua.globals().arg = lua.table_from([str(workspace / '1025Dex')])
lua.execute((workspace / '1025Dex/tests/gen3_evolution_animation.lua').read_text())
