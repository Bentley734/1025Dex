"""Build independently versioned assets and a small core; never bundle ROM imports.

Keep ASSET_VERSION/ASSET_RELEASE unchanged for code-only updates so installed
users reuse the same cache. Bump them only when asset bytes change.
"""
from pathlib import Path
import argparse, hashlib, json, zipfile

ROOT=Path(__file__).resolve().parents[1]
ASSET_VERSION='1.0.0'
ASSET_RELEASE='1.2.36'
ASSET_NAME=f'1025Dex-assets-v{ASSET_VERSION}.zip'

def clean_files():
    return [p for p in sorted(ROOT.rglob('*')) if p.is_file()
            and not any(x in {'.git','__pycache__','.test-runtime'} for x in p.parts)]

def managed(path):
    rel=path.relative_to(ROOT).as_posix()
    return rel.startswith(('sprites/assets/','cries/assets/')) and path.suffix.lower() in {'.png','.ogg'}

def checksum(path):
    path.with_suffix('.sha256').write_text(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.name+'\n')

def build_core(output):
    output.mkdir(parents=True,exist_ok=True)
    assert (ROOT/'compat/asset_catalog.lua').is_file() and (ROOT/'compat/asset_config.lua').is_file()
    manifest=json.loads((ROOT/'manifest.json').read_text());version=manifest['version']
    core=output/f'1025Dex-v{version}.zip'
    with zipfile.ZipFile(core,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in clean_files():
            if not managed(p):z.write(p,'1025Dex/'+p.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(core) as z:
        assert z.testzip() is None
        assert not any(n.endswith(('.png','.ogg')) and '/sprites/assets/' in n for n in z.namelist())
        assert any('/placeholder/' in n for n in z.namelist())
    checksum(core)
    print(f'PASS core {core.name}: {core.stat().st_size:,} bytes',flush=True)
    return core

def build(output):
    output.mkdir(parents=True,exist_ok=True)
    files=clean_files();assets=[p for p in files if managed(p)]
    assert assets,'Asset source tree is missing; restore the asset pack before rebuilding it'
    catalog={'assets/'+p.relative_to(ROOT).as_posix():{'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in assets}
    pack=output/ASSET_NAME
    with zipfile.ZipFile(pack,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        z.writestr('asset-pack.json',json.dumps({'id':'1025dex_assets','version':ASSET_VERSION,'files':catalog},separators=(',',':')))
        for p in assets:z.write(p,'assets/'+p.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(pack) as z:
        assert z.testzip() is None
        assert len(z.namelist())==len(assets)+1
    (ROOT/'compat/asset_catalog.lua').write_text('return {\n'+''.join(f'  [{json.dumps(k)}] = {{size={v["size"]},sha256="{v["sha256"]}"}},\n' for k,v in catalog.items())+'}\n')
    config=f'''return {{
  packId="1025dex_assets", version="{ASSET_VERSION}", repo="Bentley734/1025Dex",
  cacheNamespace="dex_assets", screenId="1025dex:asset_manager",
  assetName="{ASSET_NAME}", assetSize={pack.stat().st_size},
  assetURL="https://github.com/Bentley734/1025Dex/releases/download/{ASSET_RELEASE}/{ASSET_NAME}",
  indexOnly=true, verifyFiles=true, allowedPrefix="assets/",
  legacyRoots={{"assets/sprites/assets", "assets/cries/assets"}}, legacyExpectedFiles={len(assets)},
}}
'''
    (ROOT/'compat/asset_config.lua').write_text(config)
    core=build_core(output)
    checksum(pack)
    print(f'PASS core {core.name}: {core.stat().st_size:,} bytes; assets {len(assets):,} files, {pack.stat().st_size:,} bytes',flush=True)
    return core,pack

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT.parent)
    parser.add_argument('--core-only',action='store_true',help='Reuse the pinned asset catalog/URL without rebuilding the immutable pack')
    args=parser.parse_args()
    build_core(args.output) if args.core_only else build(args.output)
