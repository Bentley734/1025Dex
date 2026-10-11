"""Package the updated mod and verify archive CRCs and unchanged asset content."""
import zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
workspace=root.parent
target=workspace/'1025Dex-v1.2.15.zip'
files=[p for p in root.rglob('*') if p.is_file() and not any(part in {'.test-runtime','__pycache__'} for part in p.parts)]
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for file in sorted(files):
        archive.write(file,file.relative_to(root).as_posix())
with zipfile.ZipFile(target) as archive, zipfile.ZipFile(workspace/'1025Dex-v1.2.11.zip') as baseline:
    assert archive.testzip() is None
    protected=0
    for name in baseline.namelist():
        if (name.startswith(('sprites/','cries/assets/','dex/')) or name.startswith('compat/')) and not name.endswith('/'):
            assert archive.read(name)==baseline.read(name),name
            protected+=1
    assert b'"version": "1.2.15"' in archive.read('manifest.json')
    assert 'compat/species_numbers.lua' in archive.namelist()
    assert 'encounters/native.lua' in archive.namelist()
    print('PASS archive CRCs;',protected,'existing asset/registry/compat files unchanged')
print(target,'bytes',target.stat().st_size)
