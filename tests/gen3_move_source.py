"""Independent source-level checks for the generated wild compatibility data.
Run: python tests/gen3_move_source.py POKEAPI_CSV_DIRECTORY
"""
import collections
import csv
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
csvroot = Path(sys.argv[1])
data = (root / 'dex/data/species/generated/gen3_moves.lua').read_text()
report = json.loads((root / 'dex/data/species/generated/gen3_moves_provenance.json').read_text())
native = {int(n): r for n, r in json.loads((root / 'tools/data/gen3_move_properties.json').read_text())['moves'].items()}
versions = {r['identifier']: int(r['id']) for r in csv.DictReader((csvroot / 'version_groups.csv').open())}
selected = {}
for line in data.splitlines():
    match = re.match(r'\[(\d+)\]=\{version="([^"]+)"', line)
    if match:
        dex, version = int(match[1]), versions[match[2]]
        selected[dex] = (version, line)
actual = collections.defaultdict(list)
for r in csv.DictReader((csvroot / 'pokemon_moves.csv').open()):
    dex, version = int(r['pokemon_id']), int(r['version_group_id'])
    if dex in selected and version == selected[dex][0] and r['pokemon_move_method_id'] == '1':
        move = int(r['move_id'])
        actual[dex].append((int(r['level']), int(r['order']) if r['order'] else move, move))
replacements = {r['source_move']: r['gen3_move'] for r in report['wild_replacements'].values()}
assert not set(replacements.values()) & {165, 166, 118, 144}, 'no generic Struggle/Sketch/Metronome/Transform replacements'
checks = 0
for dex, (_, line) in selected.items():
    field = re.search(r'wildLearnset=\{(.*?)\},wildStarters=', line)[1]
    wild = [(int(a), int(b)) for a, b in re.findall(r'\{(\d+),(\d+)\}', field)]
    source = sorted(actual[dex])
    assert len(wild) == len(source), dex
    for (lv, move), (source_lv, _, source_move) in zip(wild, source):
        assert lv == max(1, source_lv), (dex, lv, source_lv)
        assert move == (source_move if source_move <= 354 else replacements[source_move]), (dex, move)
        assert 1 <= move <= 354 and move != 165 and native[move]['pp'] > 0, (dex, move)
        checks += 3
    initial = {m for lv, m in wild if lv <= 1}
    future = {m for lv, m in wild if lv > 1} - initial
    reserve = [int(n) for n in re.search(r'wildStarters=\{([^}]*)\}', line)[1].split(',')]
    assert len(set(reserve)) >= 3, dex
    for move in reserve:
        assert native[move]['pp'] > 0 and move != 165, (dex, move)
        if move not in initial:
            assert native[move]['power'] <= 50, (dex, move)
            assert move not in future, (dex, move, 'future move used as padding')
        checks += 3
assert len(selected) == 639
assert report['added_machine_permissions'] == 11571
print(f'PASS: {checks} primary-source learn-level / full conversion / weak padding / no future borrowing checks for all 639 added species')
