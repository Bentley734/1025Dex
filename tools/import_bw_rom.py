"""Build a private 1025Dex companion sprite mod from a user-supplied BW ROM."""
import argparse
import json
from pathlib import Path
import re
import shutil
import tempfile
import sys
from bw_formats import FormatError, palette, render_animation, rom_archive

ROOT = Path(sys._MEIPASS) if getattr(sys, 'frozen', False) else Path(__file__).resolve().parents[1]


class ImportCancelled(Exception):
    pass


def lua(value):
    if isinstance(value, dict):
        return '{' + ','.join('[' + lua(str(k)) + ']=' + lua(v) for k, v in value.items()) + '}'
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    return str(value).lower()


def species_map():
    bundled = ROOT / 'tools/bw_species.json'
    if bundled.exists():
        result = {int(k): v for k, v in json.loads(bundled.read_text()).items()}
        if set(result) != set(range(1, 650)):
            raise FormatError('Incomplete bundled National Dex mapping')
        return result
    result = {}
    for path in (ROOT / 'dex/data/evolutions/generated').glob('*.lua'):
        for line in path.read_text(encoding='utf-8').splitlines():
            match = re.match(r'  ([A-Z0-9_]+) = .*?, dex = (\d+),', line)
            if match:
                result.setdefault(int(match[2]), match[1])
    if any(n not in result for n in range(1, 650)):
        raise FormatError('Incomplete local National Dex mapping')
    stems = dict(re.findall(r'\["([A-Z0-9_]+)"\] = "([A-Za-z0-9_]+)"', (ROOT/'sprites/data/dbk_data.lua').read_text()))
    return {n: stems[result[n]] for n in range(1, 650)}


def build(rom, output, selected=None, form_map=None, animation=0, max_ticks=36000,
          progress=None, cancel=None):
    def stopped():
        if cancel is not None and cancel.is_set():
            raise ImportCancelled('Import cancelled. No companion was installed.')
    stopped()
    code, files = rom_archive(rom)
    if len(files) < 650 * 20:
        raise FormatError('Archive lacks the BW National Dex sprite blocks')
    names = species_map()
    if form_map:
        for key, stem in json.loads(Path(form_map).read_text()).items():
            block = int(key)
            if block < 650 or block * 20 + 19 >= len(files) or not re.fullmatch('[A-Z0-9_]+', stem):
                raise FormatError('Invalid extra-form block mapping')
            names[block] = stem
    if selected:
        names = {n: s for n, s in names.items() if n in selected}
    if not names:
        raise FormatError('No species selected')
    output = Path(output).resolve()
    if output == ROOT or ROOT in output.parents:
        raise FormatError('Place the private companion outside 1025Dex so updates preserve it and release packaging excludes it')
    if output.exists():
        raise FormatError(f'Output already exists: {output}. Choose a new folder to preserve your previous import.')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='bw-import-', dir=output.parent))
    inventory, report = {}, {'game_code': code, 'animation': animation, 'imported': [], 'errors': []}
    try:
        for block, stem in names.items():
            stopped()
            base = block * 20
            for side, start in [('front', 0), ('back', 9)]:
                male, female = files[base+start+2], files[base+start+3]
                variants = [(stem, male or female)]
                if female and male:
                    variants.append((stem+'_female', female))
                for target, characters in variants:
                    for shiny in (False, True):
                        stopped()
                        folder = side + ('_shiny' if shiny else '')
                        try:
                            resources = [characters] + files[base+start+4:base+start+8]
                            image, durations, prefix, indices = render_animation(resources, palette(files[base+18+int(shiny)]), animation, max_ticks)
                            dest = temporary/'assets'/folder
                            dest.mkdir(parents=True, exist_ok=True)
                            image.save(dest/(target+'.png'))
                            inventory[folder+'/'+target] = {'durations': durations, 'indices': indices, 'loop_tick': prefix, 'total_ticks': sum(durations), 'canvas': image.height}
                            report['imported'].append({'block': block, 'sprite': folder+'/'+target, 'frames': image.width//image.height, 'ticks': sum(durations)})
                        except (FormatError, KeyError) as exc:
                            report['errors'].append({'block': block, 'sprite': folder+'/'+target, 'reason': str(exc)})
            if progress:
                progress(block, len(names), stem, len(report['imported']), len(report['errors']))
            elif sys.stdout:
                print(f'{block:03} {stem}: {len(report["imported"])} sprites, {len(report["errors"])} unavailable', flush=True)
        if not inventory:
            raise FormatError('No animations decoded; output was not installed')
        (temporary/'inventory.lua').write_text('return '+lua(inventory)+'\n', encoding='utf-8')
        (temporary/'inventory.json').write_text(json.dumps(inventory), encoding='utf-8')
        shutil.copyfile(ROOT/'tools/bw_companion.lua', temporary/'main.lua')
        manifest = {'id':'1025dex-bw-sprites', 'name':'1025Dex BW ROM Sprites (local)', 'version':'1.0.0', 'api':2, 'entry':'main.lua', 'profile':'content', 'games':json.loads((ROOT/'manifest.json').read_text())['games'], 'game_version':'>=0.3.54 <0.4.0', 'category':'CONTENT', 'priority':299, 'permissions':[], 'dependencies':[], 'conflicts':[], 'description':'Private animated sprite import from your own Black/White ROM. Enable alongside 1025Dex and select BW ROM. Keep this local; no automatic updates.'}
        (temporary/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        (temporary/'IMPORT-REPORT.json').write_text(json.dumps(report, indent=2)+'\n')
        (temporary/'README.txt').write_text('LOCAL ROM IMPORT - do not publish this folder or its graphics.\nEnable this companion together with 1025Dex. Select SPRITE STYLE: BW ROM.\nSpecies/forms not imported retain their existing artwork.\nKeep this folder beside 1025Dex so updates preserve the imported sprites.\nOriginal artwork belongs to its original rights holders.\nNo ROM is copied into this mod. See IMPORT-REPORT.json for unsupported entries.\n')
        stopped()
        temporary.rename(output)
    except BaseException:
        # Only the exact temporary directory just created here is removed.
        shutil.rmtree(temporary)
        raise
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom', type=Path, help='Your local Pokemon Black or White .nds dump')
    parser.add_argument('--output', type=Path, required=True, help='New private companion mod folder (outside 1025Dex)')
    parser.add_argument('--species', help='Optional comma-separated National Dex numbers for a small preview import')
    parser.add_argument('--form-map', help='Optional JSON mapping archive block numbers >=650 to exact DBK sprite stems')
    parser.add_argument('--animation', type=int, default=0, help='NMAR sequence index (default 0, original battle sequence)')
    parser.add_argument('--max-ticks', type=int, default=36000, help='Maximum exact animation period; longer entries are reported, never silently shortened')
    args = parser.parse_args()
    try:
        selected = {int(n) for n in args.species.split(',')} if args.species else None
        report = build(args.rom, args.output, selected, args.form_map, args.animation, args.max_ticks)
    except (FormatError, OSError, ValueError) as exc:
        parser.exit(1, f'Import failed: {exc}\n')
    print(f'Created {args.output}: {len(report["imported"])} sprites; {len(report["errors"])} entries use fallback artwork.')


if __name__ == '__main__':
    main()
