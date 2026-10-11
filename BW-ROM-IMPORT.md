# Black / White ROM animation importer

The **BW ROM** sprite style reads a private companion mod generated from your
own Pokemon Black or White `.nds` dump. It reconstructs the original multipart
front/back battle sequences, normal/shiny palettes and available female graphics.
It does not download a ROM or include ROM graphics in the 1025Dex release.

In 1.2.19, BIG is the default size and MAX DETAIL has been removed. Existing
MAX DETAIL selections use BIG. BW ROM's BIG size fits the visible animation into the
picture box, ignoring transparent canvas padding. NORMAL uses half that size
and SMALL a third. All frames retain one shared scale and ground anchor.
Existing imports work with this fix; there is no need to import the ROM again.

Windows users can download **BW-Sprite-Importer-Windows-v1.0.0.zip** from the
1025Dex 1.2.17 release. Extract it and double-click **1025Dex-BW-Importer.exe**.
Choose your Black or White ROM, check the suggested mods folder, and click
**Import sprites**. No Python installation or commands are needed. When finished,
restart Gen1Recomp, enable the new BW sprite companion and select **BW ROM** in
1025Dex's sprite settings. The importer preserves existing companion folders.

For the optional command-line importer, install Python 3.10 or newer and Pillow
(`py -3 -m pip install Pillow`). From the
1025Dex folder, run:

```powershell
py -3 tools/import_bw_rom.py "C:\path\Pokemon Black.nds" --output "C:\path\mods\1025Dex-BW-ROM"
```

The output must be a **new folder outside 1025Dex**, next to your installed mods.
Enable that companion and 1025Dex, then select **SPRITE STYLE → BW ROM**. Restart
the game after enabling the companion. Keep the companion installed when updating
1025Dex. Missing entries, later-generation Pokemon and forms absent from the
import retain their existing matching animated artwork. Party icon settings are
independent. The ANIMATE SPRITES toggle also applies to BW sprites; their playback
uses cartridge tick durations rather than the generic animation FPS option.

The default import covers National Dex **1–649**. A Black/White ROM has no Gen6–9,
Mega, regional or Gigantamax graphics. Extra cartridge form blocks are deliberately
not guessed: `--form-map forms.json` can explicitly map verified archive block
numbers (650 onward) to exact 1025Dex sprite stems. Do not map a base species to a
later regional form. `--species 1,25,649` creates a small preview import; `--animation`
selects an alternative NMAR sequence where present.

`IMPORT-REPORT.json` records every imported and unavailable variant. A malformed or
unsupported entry is reported and falls back; a completely failed import does not
install a companion. Existing output folders are never overwritten. The importer
reads only the local ROM filesystem/archive and leaves the ROM unchanged. Output
contains PNG strips, timing metadata and the companion entrypoint, **no ROM**.
Keep this generated artwork local; it is not part of the public source/release ZIP.

## Rendering and format provenance

The parser and compositor were independently written for this importer. External
implementations are neither bundled nor executed. Binary layout facts were checked
against [magical's sprite format notes](https://github.com/magical/pokemon-nds-sprites/blob/master/docs/pokegra.rst)
and [AnimaEngine's Nitro resource descriptions](https://github.com/KillDaWill/AnimaEngine).
Original Pokemon artwork belongs to its original rights holders.

The pipeline reads NitroFS → `/a/0/0/4` → NARC → NCGR/NCLR/NCER/NANR/NMCR/NMAR.
It applies cell translations, fixed-point scales/rotations and parent transforms,
then exports the complete NMAR sequence at 60 ticks per second. Identical frames
share texture slots; timings retain all ticks. One union canvas is used throughout
each sequence, so changing body-part bounds do not cause per-frame recentering.
1025Dex performs its normal final slot fitting and ground alignment across Gen1–3.

Development validation used a user-supplied US Black ROM: **649 base species,
2,980 front/back/gender/palette variants, zero unavailable entries**. Actual LÖVE
decoding and the production sprite bake were exercised on 48 representative
variants, and the existing all-11-game/Hoennto boot checks passed. Generated
fixtures cover decompression, invalid input, transforms, timing and union placement.
This is not a frame-by-frame comparison with a running DS emulator, and live
battles on every supported game/ROM language have not been verified.

Generated binary-fixture checks can be run without a ROM:

```powershell
py -3 tests/test_bw_formats.py
```

Black/White 2 and other DS games are rejected. This is battle-sprite import only;
it does not import gameplay, overworld followers, cries or move animations.
