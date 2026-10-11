"""Build the Windows GUI without bundling ROMs or sprite artwork.

Run with Python, Pillow and PyInstaller available in the build environment.
"""
from pathlib import Path
import PyInstaller.__main__

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT.parent/'.work'

if __name__ == '__main__':
    PyInstaller.__main__.run([
        '--noconfirm', '--clean', '--onefile', '--windowed',
        '--name', '1025Dex-BW-Importer',
        '--distpath', str(WORK/'windows-importer-dist'),
        '--workpath', str(WORK/'windows-importer-build'),
        '--specpath', str(WORK/'windows-importer-build'),
        '--add-data', str(ROOT/'manifest.json')+':.',
        '--add-data', str(ROOT/'tools/bw_companion.lua')+':tools',
        '--add-data', str(ROOT/'tools/bw_species.json')+':tools',
        str(ROOT/'tools/bw_importer_gui.py'),
    ])
