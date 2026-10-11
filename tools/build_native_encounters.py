"""Extract National species/level metadata from locally supplied USA ROMs.

Uses the bundled engine's map identities, edition addresses and National index.
No ROM content or graphics are copied into the output.
"""
import os
import struct
import sys
from pathlib import Path

workspace = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(workspace / '.tools/lua-test'))
from lupa.luajit21 import LuaRuntime

os.chdir(workspace / 'gen1recomp-0.3.54')
output = ['-- Generated from local FireRed, LeafGreen and Emerald USA encounter tables.', 'return {']
for game, filename in [('firered', 'FireRed.gba'), ('leafgreen', 'LeafGreen.gba'), ('emerald', 'Emerald.gba'), ('ruby', 'Pokemon - Ruby Version (USA).gba')]:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'require("src.core.GameVersion").set("{game}"); V=require("src.import.gba.versions"); V.select("{game}")')
    v = lua.globals().V
    rom = (workspace / filename).read_bytes()
    u16 = lambda pos: struct.unpack_from('<H', rom, pos)[0]
    u32 = lambda pos: struct.unpack_from('<I', rom, pos)[0]
    headers = v.WILD_MON_HEADERS
    national_table = v.SPECIES_TO_NATIONAL
    if game == 'leafgreen' and rom[0xbc] == 1:
        # The supplied USA revision 1.1 has shifted data; the bundled engine
        # profile provides revision 1.0 addresses. Locate validated table data.
        reference = (workspace / 'FireRed.gba').read_bytes()
        signature = reference[0x251FEE:0x251FEE+822]
        national_table = rom.find(signature)
        assert national_table >= 0 and rom.find(signature, national_table+1) == -1
        starts = [i for i in range(0x3c0000, 0x3d0000, 4)
                  if rom[i:i+4] == reference[0x3C9CB8:0x3C9CBC]
                  and rom[i+20:i+24] == reference[0x3C9CCC:0x3C9CD0]]
        assert len(starts) == 1, starts
        headers = starts[0]
    maps = {}
    positions = []
    for index in range(512):
        pos = headers + index * 20
        if rom[pos:pos+2] == b'\xff\xff':
            break
        positions.append(pos)
    main_count = len(positions)
    if game == 'emerald':
        for _, table in v.WILD_EXTRA_HEADERS.items():
            positions.extend(table.off + i*20 for i in range(table.count))
    for pos in positions:
        group, number = rom[pos:pos+2]
        if group == number == 255:
            continue
        name = v.mapIdFor(group, number)
        assert name, (game, group, number)
        # FR/LG share canonical FR_ map identities in the engine.
        name = name.replace('LG_', 'FR_', 1)
        channels = maps.setdefault(name, {})
        for offset, terrain, count in [(4, 'land', 12), (8, 'water', 5), (12, 'rocks', 5), (16, 'fishing', 10)]:
            pointer = u32(pos + offset)
            if not pointer:
                continue
            info = pointer - 0x08000000
            if not rom[info]:
                continue
            slots = u32(info + 4) - 0x08000000
            residents = channels.setdefault(terrain, {})
            for slot in range(count):
                loc = slots + slot * 4
                species = u16(loc + 2)
                national = u16(national_table + (species - 1) * 2)
                assert 1 <= national <= 386, (game, name, species, national)
                low, high = rom[loc:loc+2]
                old = residents.get(national, (low, high))
                residents[national] = (min(low, old[0]), max(high, old[1]))
    if game in ('emerald', 'ruby'):
        pos = v.FEEBAS_WILD_MON if game == 'emerald' else v.sym('gWildFeebasRoute119Data')
        species = u16(national_table + (u16(pos+2)-1)*2)
        maps['EM_ROUTE119' if game == 'emerald' else 'RU_ROUTE119']['fishing'][species] = (rom[pos], rom[pos+1])
    output.append(f' {game}={{')
    for name, channels in sorted(maps.items()):
        output.append(f'  ["{name}"]={{')
        for terrain, residents in sorted(channels.items()):
            rows = ','.join(f'[{species}]={{{low},{high}}}' for species, (low, high) in sorted(residents.items()))
            output.append(f'   {terrain}={{{rows}}},')
        output.append('  },')
    output.append(' },')
    print(game, main_count, 'main headers', len(positions)-main_count, 'extra headers', len(maps), 'maps', sum(len(r) for c in maps.values() for r in c.values()), 'native area/channel/species entries')
output.append('}')
(workspace / '1025Dex/encounters/native.lua').write_text('\n'.join(output)+'\n', encoding='utf-8')
