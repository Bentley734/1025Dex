"""Rebuild Gen3 machine, canonical, and comparable wild-move rules.

Usage: python build_gen3_move_rules.py CSV_DIRECTORY OUTPUT_DIRECTORY
PokeAPI supplies actual learn levels and modern mechanics. The bundled engine
properties use Gen3 power/PP/type, so modern buffs do not skew choices.
Only post-Gen3 wild species use substitutions and the three-move starter rule.
"""
import collections
import csv
import hashlib
import json
import sys
from pathlib import Path

csvroot, out = map(Path, sys.argv[1:3])
out.mkdir(parents=True, exist_ok=True)


def rows(name):
    with (csvroot / name).open() as f:
        yield from csv.DictReader(f)


def number(value):
    return int(value) if value else 0


versions = {int(r['id']): r['identifier'] for r in rows('version_groups.csv')}
main = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15, 16, 17, 18, 20, 21,
        22, 23, 25, 26, 27}
levels = collections.defaultdict(lambda: collections.defaultdict(list))
teach = collections.defaultdict(set)
native_machines = {int(r['move_id']) for r in rows('machines.csv')
                   if int(r['version_group_id']) in {6, 7}}
for r in rows('pokemon_moves.csv'):
    dex, ver, move, method = (int(r[k]) for k in
                             ['pokemon_id', 'version_group_id', 'move_id',
                              'pokemon_move_method_id'])
    if not 1 <= dex <= 1025 or ver not in main:
        continue
    if method == 1:
        order = int(r['order']) if r['order'] else move
        levels[dex][ver].append((int(r['level']), order, move))
    if method == 4 and move in native_machines:
        teach[dex].add(move)

moves = {int(r['id']): r for r in rows('moves.csv')}
by_name = {r['identifier']: n for n, r in moves.items()}
types = {int(r['id']): r['identifier'].upper() for r in rows('types.csv')}
species_types = collections.defaultdict(list)
for r in rows('pokemon_types.csv'):
    species_types[int(r['pokemon_id'])].append((int(r['slot']),
                                              types[int(r['type_id'])]))
meta = {int(r['move_id']): r for r in rows('move_meta.csv')}
stats = collections.defaultdict(dict)
for r in rows('move_meta_stat_changes.csv'):
    stats[int(r['move_id'])][int(r['stat_id'])] = int(r['change'])
props_path = Path(__file__).parent / 'data/gen3_move_properties.json'
props = json.loads(props_path.read_text())
native = {int(n): r for n, r in props['moves'].items()}

# Approximations for mechanics without a Gen3 equivalent. Other moves are
# ranked by type, role, effect, power and speed. Gen3 damage category is typed.
OVERRIDES = {
    'aqua-jet': 'water-gun', 'air-slash': 'aerial-ace',
    'aura-sphere': 'brick-break', 'frost-breath': 'icy-wind',
    'aqua-ring': 'recover', 'assurance': 'feint-attack',
    'aurora-veil': 'reflect', 'baby-doll-eyes': 'growl',
    'brave-bird': 'fly', 'bug-bite': 'twineedle',
    'bug-buzz': 'signal-beam', 'clear-smog': 'smog',
    'coil': 'bulk-up', 'copycat': 'mimic',
    'dazzling-gleam': 'extrasensory', 'defog': 'haze',
    'disarming-voice': 'uproar', 'double-hit': 'double-slap',
    'dragon-pulse': 'dragon-breath', 'draining-kiss': 'mega-drain',
    'echoed-voice': 'uproar', 'electric-terrain': 'charge',
    'energy-ball': 'giga-drain', 'entrainment': 'skill-swap',
    'fairy-wind': 'gust', 'final-gambit': 'self-destruct',
    'flash-cannon': 'steel-wing', 'fling': 'thief',
    'flare-blitz': 'fire-blast', 'gastro-acid': 'haze',
    'giga-impact': 'hyper-beam', 'grassy-terrain': 'ingrain',
    'heal-pulse': 'recover', 'healing-wish': 'recover',
    'heavy-slam': 'steel-wing', 'hex': 'shadow-punch',
    'hone-claws': 'focus-energy', 'hurricane': 'fly',
    'incinerate': 'ember', 'iron-head': 'steel-wing',
    'kowtow-cleave': 'crunch', 'last-resort': 'hyper-beam',
    'leafage': 'vine-whip', 'life-dew': 'recover',
    'liquidation': 'surf', 'lunge': 'signal-beam',
    'magnet-rise': 'double-team', 'misty-terrain': 'safeguard',
    'moonblast': 'psychic', 'nasty-plot': 'calm-mind',
    'night-slash': 'slash', 'noble-roar': 'growl',
    'nuzzle': 'thunder-wave', 'payback': 'bite',
    'play-nice': 'growl', 'play-rough': 'body-slam',
    'power-gem': 'rock-slide', 'psychic-fangs': 'psychic',
    'psycho-cut': 'psybeam', 'psyshock': 'extrasensory',
    'quick-guard': 'detect', 'retaliate': 'revenge',
    'roost': 'recover', 'round': 'uproar',
    'sacred-sword': 'brick-break', 'seed-bomb': 'leaf-blade',
    'shell-smash': 'growth', 'snarl': 'bite',
    'soak': 'rain-dance', 'spirit-shackle': 'shadow-ball',
    'stealth-rock': 'spikes', 'sticky-web': 'string-shot',
    'stone-edge': 'rock-slide', 'stored-power': 'confusion',
    'struggle-bug': 'silver-wind', 'sucker-punch': 'feint-attack',
    'switcheroo': 'trick', 'tailwind': 'agility',
    'toxic-spikes': 'spikes', 'u-turn': 'fury-cutter',
    'wide-guard': 'protect', 'wild-charge': 'thunderbolt',
    'work-up': 'growth', 'worry-seed': 'skill-swap',
    'zen-headbutt': 'psychic',
    # Field, ability, ally and recovery mechanics need explicit approximations;
    # sparse metadata must not accidentally select Transform/Sketch/Metronome.
    'gravity': 'sweet-scent', 'power-trick': 'psych-up',
    'power-swap': 'psych-up', 'guard-swap': 'psych-up',
    'heart-swap': 'psych-up', 'trick-room': 'scary-face',
    'wonder-room': 'light-screen', 'magic-room': 'knock-off',
    'defend-order': 'cosmic-power', 'lunar-dance': 'moonlight',
    'dark-void': 'hypnosis', 'guard-split': 'psych-up',
    'power-split': 'psych-up', 'rage-powder': 'follow-me',
    'quiver-dance': 'calm-mind', 'simple-beam': 'skill-swap',
    'after-you': 'helping-hand', 'ally-switch': 'double-team',
    'reflect-type': 'conversion-2', 'shift-gear': 'dragon-dance',
    'quash': 'scary-face', 'cotton-guard': 'iron-defense',
    'rototiller': 'growth', 'trick-or-treat': 'spite',
    'forests-curse': 'leech-seed', 'parting-shot': 'growl',
    'topsy-turvy': 'haze', 'crafty-shield': 'light-screen',
    'flower-shield': 'reflect', 'electrify': 'charge',
    'fairy-lock': 'mean-look', 'kings-shield': 'protect',
    'confide': 'growl', 'spiky-shield': 'protect',
    'aromatic-mist': 'light-screen', 'eerie-impulse': 'charm',
    'venom-drench': 'growl', 'geomancy': 'calm-mind',
    'magnetic-flux': 'charge', 'shore-up': 'recover',
    'baneful-bunker': 'protect', 'floral-healing': 'soft-boiled',
    'strength-sap': 'recover', 'laser-focus': 'focus-energy',
    'gear-up': 'howl', 'psychic-terrain': 'calm-mind',
    'speed-swap': 'agility', 'purify': 'refresh',
    'instruct': 'mirror-move', 'tearful-look': 'charm',
    'stuff-cheeks': 'iron-defense', 'no-retreat': 'bulk-up',
    'tar-shot': 'string-shot', 'magic-powder': 'conversion-2',
    'teatime': 'recycle', 'octolock': 'mean-look',
    'court-change': 'rapid-spin', 'clangorous-soul': 'dragon-dance',
    'decorate': 'helping-hand', 'obstruct': 'protect',
    'jungle-healing': 'aromatherapy', 'lunar-blessing': 'moonlight',
    'take-heart': 'calm-mind', 'silk-trap': 'protect',
    'spicy-extract': 'swagger', 'revival-blessing': 'wish',
    'doodle': 'role-play', 'fillet-away': 'dragon-dance',
    'shed-tail': 'substitute', 'tidy-up': 'dragon-dance',
    'snowscape': 'hail', 'burning-bulwark': 'protect',
    # Preserve recognizable attacking roles where raw metadata is incomplete.
    'ice-shard': 'powder-snow', 'avalanche': 'icy-wind',
    'icicle-crash': 'ice-punch', 'accelerock': 'rock-throw',
    'x-scissor': 'signal-beam', 'attack-order': 'signal-beam',
    'first-impression': 'signal-beam', 'population-bomb': 'fury-swipes',
    'triple-dive': 'waterfall', 'psyblade': 'extrasensory',
    'hyper-drill': 'hyper-fang', 'natural-gift': 'secret-power',
    'crush-grip': 'strength', 'natures-madness': 'super-fang',
    'ruination': 'super-fang', 'comeuppance': 'counter',
    'fleur-cannon': 'psychic', 'springtide-storm': 'extrasensory',
    'boomburst': 'hyper-voice', 'leaf-storm': 'leaf-blade',
    'seed-flare': 'leaf-blade', 'ice-hammer': 'ice-punch',
    'heat-crash': 'flame-wheel', 'gyro-ball': 'steel-wing',
    'grass-knot': 'giga-drain', 'brine': 'bubble-beam',
}

# Never randomly choose OHKOs, exhausted-moves fallback, fixed/variable damage,
# suicide moves, or legendary/starter signature attacks as generic substitutes.
excluded_names = {'struggle', 'aeroblast', 'blast-burn', 'doom-desire',
                  'frenzy-plant', 'hydro-cannon', 'luster-purge', 'mist-ball',
                  'psycho-boost', 'sacred-fire', 'volt-tackle',
                  'transform', 'sketch', 'metronome', 'assist', 'mirror-move'}
excluded_effects = {'OHKO', 'SELFDESTRUCT', 'DRAGON_RAGE', 'SONICBOOM',
                    'LEVEL_DAMAGE', 'PSYWAVE', 'SUPER_FANG', 'COUNTER',
                    'MIRROR_COAT', 'BIDE', 'ENDEAVOR', 'RETURN', 'FRUSTRATION',
                    'HIDDEN_POWER', 'PRESENT', 'MAGNITUDE', 'REVERSAL',
                    'LOW_KICK', 'WEATHER_BALL', 'ERUPTION', 'BEAT_UP',
                    'SPIT_UP', 'FLAIL', 'ROLLOUT', 'ROLL_OUT'}


def power(move, old=False):
    value = native[move]['power'] if old else number(moves[move]['power'])
    hits = meta.get(move, {})
    lo, hi = number(hits.get('min_hits')), number(hits.get('max_hits'))
    if lo and hi:
        value *= lo if lo == hi else 3
    return value


def distance(wanted, candidate):
    a, b = moves[wanted], moves[candidate]
    ap, bp = power(wanted), power(candidate, True)
    status = int(a['damage_class_id']) == 1
    if status != (int(b['damage_class_id']) == 1):
        return float('inf')
    # Weak modern attacks must not turn into Flamethrower/Hyper Beam at level 1.
    if not status and ap and bp > ap + 10:
        return float('inf')
    if not status and not ap and bp > 60:
        return float('inf')
    ma, mb = meta.get(wanted, {}), meta.get(candidate, {})
    score = 0
    if types[int(a['type_id'])] != native[candidate]['type']:
        score += 50 if status else 180
    if a['damage_class_id'] != b['damage_class_id']:
        score += 20
    if a['target_id'] != b['target_id']:
        score += 50 if status else 8
    if a['effect_id'] != b['effect_id']:
        score += 20
    if ma.get('meta_category_id') != mb.get('meta_category_id'):
        score += 28
    if ma.get('meta_ailment_id') != mb.get('meta_ailment_id'):
        score += 35
    for stat in stats[wanted].keys() | stats[candidate].keys():
        score += abs(stats[wanted].get(stat, 0) -
                     stats[candidate].get(stat, 0)) * 25
    score += abs(number(a['priority']) - native[candidate]['priority']) * 18
    score += abs(ap - bp) * 1.2
    wa, ca = number(a['accuracy']), native[candidate]['accuracy']
    if not status:  # Zero accuracy is the never-miss marker, not a 0% hit rate.
        wa, ca = wa or 100, ca or 100
    score += abs(wa - ca) * .25
    score += abs(number(a['pp']) - native[candidate]['pp']) * .1
    for prop in ['drain', 'healing', 'flinch_chance']:
        score += abs(number(ma.get(prop)) - number(mb.get(prop))) * .3
    if number(mb.get('drain')) < 0 <= number(ma.get('drain')):
        score += 70  # Do not introduce recoil just to match a power number.
    if native[candidate]['effect'] in {
            'ROLL_OUT', 'RAMPAGE', 'RECOIL_IF_MISS', 'HYPER_BEAM',
            'RAZOR_WIND', 'SKY_ATTACK', 'SOLAR_BEAM', 'SEMI_INVULNERABLE'}:
        score += 65  # Avoid accidental locks, charge turns, and recharge.
    if number(mb.get('max_hits')) > 1 and not number(ma.get('max_hits')):
        score += 35
    return score


replacements = {}


def substitute(move):
    if move <= 354:
        return move
    if move in replacements:
        return replacements[move]
    name = moves[move]['identifier']
    if name in OVERRIDES:
        chosen = by_name[OVERRIDES[name]]
    else:
        choices = [n for n, row in native.items()
                   if moves[n]['identifier'] not in excluded_names
                   and row['effect'] not in excluded_effects]
        chosen = min(choices, key=lambda n: (distance(move, n), n))
        assert distance(move, chosen) != float('inf'), name
    assert 1 <= chosen <= 354 and chosen != 165 and native[chosen]['pp'] > 0
    replacements[move] = chosen
    return chosen


# Only missing slots use this small, weak type-oriented reserve. A move that
# is actually scheduled for a later level cannot enter early through padding.
TYPE_STARTERS = {
    'NORMAL': ['tackle', 'growl', 'tail-whip', 'pound', 'scratch'],
    'FIGHTING': ['rock-smash', 'focus-energy', 'leer'],
    'FLYING': ['gust', 'growl', 'peck'],
    'POISON': ['poison-sting', 'acid', 'leer'],
    'GROUND': ['mud-slap', 'sand-attack', 'defense-curl'],
    'ROCK': ['rock-throw', 'harden', 'defense-curl'],
    'BUG': ['leech-life', 'string-shot', 'harden'],
    'GHOST': ['astonish', 'lick', 'spite'],
    'STEEL': ['metal-claw', 'harden', 'leer'],
    'FIRE': ['ember', 'smokescreen', 'fire-spin'],
    'WATER': ['water-gun', 'bubble', 'tail-whip'],
    'GRASS': ['absorb', 'growth', 'vine-whip'],
    'ELECTRIC': ['thunder-shock', 'charge', 'growl'],
    'PSYCHIC': ['confusion', 'meditate', 'reflect'],
    'ICE': ['powder-snow', 'mist', 'growl'],
    'DRAGON': ['twister', 'leer', 'focus-energy'],
    'DARK': ['knock-off', 'leer', 'torment'],
    'FAIRY': ['pound', 'growl', 'tail-whip'],
}


def starters(dex, learnset):
    initial = []
    for level, move in learnset:
        if level <= 1 and move not in initial:
            initial.append(move)
    initial = initial[-4:]
    if len(initial) >= 3:
        return initial, []
    future = {m for lv, m in learnset if lv > 1} - set(initial)
    choices = []
    for _, type_ in sorted(species_types[dex]):
        choices.extend(TYPE_STARTERS[type_])
    choices.extend(['tackle', 'growl', 'tail-whip', 'scratch', 'pound',
                    'focus-energy', 'harden', 'leer', 'defense-curl'])
    choices = list(dict.fromkeys(by_name[name] for name in choices))
    # If all initial moves are status, prioritize a basic attack.
    if not any(native[n]['power'] > 1 for n in initial):
        choices.sort(key=lambda n: native[n]['power'] <= 1)
    extra = []
    for move in choices:
        if move in initial or move in future:
            continue
        assert power(move, True) <= 50 and native[move]['pp'] > 0
        initial.append(move)
        extra.append(move)
        if len(initial) >= 3:
            break
    assert len(initial) >= 3, dex
    return initial, extra


def learn(dex, ver):
    return [(max(1, l), m) for l, _, m in sorted(levels[dex][ver]) if m <= 354]


def lua_list(seq):
    return '{' + ','.join(map(str, seq)) + '}'


def lua_learn(seq):
    return '{' + ','.join('{%d,%d}' % pair for pair in seq) + '}'


lines = ['-- PokeAPI-derived rules and curated Gen3 wild equivalents.',
         '-- See GEN3-MOVE-RULES.txt; wild starters apply only to added species.',
         'return { native={']
for family, preference in [('frlg', [7, 5, 6, 4, 3, 2, 1]),
                           ('rse', [6, 5, 7, 4, 3, 2, 1])]:
    lines.append(f'{family}={{')
    for dex in range(1, 387):
        ver = next(v for v in preference if levels[dex][v])
        set_ = learn(dex, ver)
        assert set_ and set_[0][0] == 1, (dex, family)
        lines.append(f'[{dex}]={lua_learn(set_)},')
    lines.append('},')
lines.append('}, extended={')
empty, late, padded = [], [], {}
substitution_rows = 0
for dex in range(387, 1026):
    ver = max(v for v in levels[dex] if v in main)
    set_ = learn(dex, ver)
    if not set_:
        empty.append(dex)
    elif set_[0][0] > 1:
        late.append(dex)
    wild = [(max(1, lv), substitute(move)) for lv, _, move
            in sorted(levels[dex][ver])]
    substitution_rows += sum(m > 354 for _, _, m in levels[dex][ver])
    reserve, extra = starters(dex, wild)
    if extra:
        padded[dex] = extra
    lines.append(f'[{dex}]={{version="{versions[ver]}",learnset={lua_learn(set_)},'
                 f'wildLearnset={lua_learn(wild)},wildStarters={lua_list(reserve)},'
                 f'tmhm={lua_list(sorted(teach[dex]))}}},')
lines.append('}}')
(out / 'gen3_moves.lua').write_text('\n'.join(lines) + '\n')
report = {
    'source': 'https://github.com/PokeAPI/pokeapi/tree/master/data/v2/csv',
    'retrieved': '2026-10-03',
    'sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
               for p in sorted(csvroot.glob('*.csv'))},
    'gen3_move_properties': {
        'source': props['source'], 'source_sha256': props['source_sha256'],
        'file_sha256': hashlib.sha256(props_path.read_bytes()).hexdigest()},
    'native_species_per_game': 386, 'added_species': 639,
    'native_machine_moves': len(native_machines),
    'added_machine_permissions': sum(len(teach[d]) for d in range(387, 1026)),
    'no_native_level_up_moves_before_substitution': empty,
    'no_native_level_1_moves_before_substitution': late,
    'substituted_level_up_rows': substitution_rows,
    'wild_replacements': {moves[m]['identifier']: {
        'source_move': m, 'gen3_move': n,
        'gen3_name': moves[n]['identifier']}
        for m, n in sorted(replacements.items())},
    'starter_padding_species': len(padded),
    'starter_padding': {str(d): moves_ for d, moves_ in padded.items()},
    'rules': ('Native Gen1-3 wild schedules and all machine permissions unchanged. '
              'Added species: latest Gen4-9 main-series level-up version; '
              'unsupported attacks replaced by comparable Gen3 attacks at the '
              'original levels. Only added wilds receive weak starter padding '
              'to reach three distinct usable moves. Padding never borrows a '
              'move scheduled at a later level. Player level-up compatibility '
              'and already-owned moves are preserved.')}
(out / 'gen3_moves_provenance.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: report[k] for k in ['added_species', 'native_machine_moves',
                                      'added_machine_permissions',
                                      'substituted_level_up_rows',
                                      'starter_padding_species']}))
