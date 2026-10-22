# 1025Dex — Credits

## Original mod

**1025Dex is based on national-dex by Sanjin and Tekky.**
Thank you to both creators for the original mod and the foundation this project
was built from. The original national-dex work belongs to its creators;
1025Dex's FireRed/LeafGreen/Emerald adaptations and additions build on that work.

Original project: https://github.com/sanjinpepic/gen1recomp-national-dex

The upstream copyright notice and license are preserved in
[dex/LICENSE-national-dex.txt](dex/LICENSE-national-dex.txt).

## Pokémon sprites

### Emerald Expansion / RHH (Rom Hacking Hideout)

Based off RHH's pokeemerald-expansion 1.17.1 https://github.com/rh-hideout/pokeemerald-expansion/

Credit to **RHH (Rom Hacking Hideout)**, the creators and maintainers of
**pokeemerald-expansion**, and its contributing sprite artists. See the
[upstream contributor credits](https://github.com/rh-hideout/pokeemerald-expansion/blob/master/CREDITS.md).

The **EE ANIMATED** and **EE STATIC** choices use the user-supplied
**Emerald Expansion Sprites** folder. Credit belongs to the Pokémon Emerald
Expansion sprite contributors and original Pokémon sprite artists. These
are third-party sprites, not artwork created for 1025Dex. The supplied folder
contained no standalone artist credit list. The import records each source
image and palette in [EE-SPRITE-AUDIT.json](EE-SPRITE-AUDIT.json).

**Credit to Gen9 Resource Pack and all of its contributing sprite artists
for their Pokémon sprites.** These sprites are third-party artwork, not
original artwork created for 1025Dex.

The selectable static set is imported, without changing its PNG bytes, from
the user-supplied **Generation 9 Pack v3.3.8**, compiled by **Caruban**.
The complete supplied credit list is retained in
[sprites/assets/static/GEN9-PACK-CREDITS.txt](sprites/assets/static/GEN9-PACK-CREDITS.txt).
It credits veekun, the Smogon sprite projects and the individual Gen 6–9,
PLA and PLZA artists. Imported files are artwork and alignment metadata;
no Ruby scripts from the pack are included or executed.

The bundled sprite component also documents its DBK animated sprite-sheet
source and the “icones animados” party-icon source. Those existing source notes
are preserved in [sprites/UPSTREAM-README.md](sprites/UPSTREAM-README.md) and
[sprites/assets/icons/README.md](sprites/assets/icons/README.md).

## Data, audio and engine

- **PokeAPI and its contributors** — the Pokémon data used by national-dex.
  https://pokeapi.co
- **PokeAPI/cries**, with upstream sources Pokémon Showdown and Veekun — cry
  audio. See [cries/NOTICE.txt](cries/NOTICE.txt) and the included CC0 notice.
  https://github.com/PokeAPI/cries
- **Gen1Recomp and its contributors** — the engine this mod runs on.
  https://github.com/bryanthaboi/gen1recomp

Pokémon and its characters belong to their respective rights holders.
Attribution here does not imply endorsement by the original creators.

## Emerald compatibility

The native Emerald Pokédex adapter in `compat/emerald_pokedex.lua` is adapted
from gen1recomp 0.3.36's `src/ui/game3/rse/pokedex.lua`. The engine's GPL-3.0
license and Additional Terms are reproduced in
[compat/ENGINE-LICENSE.md](compat/ENGINE-LICENSE.md).

The extended body-color search table comes from PokéAPI's species CSV,
retrieved September 30, 2026:
https://github.com/PokeAPI/pokeapi/blob/master/data/v2/csv/pokemon_species.csv

Hoenn map profiles contain encounter metadata derived from the user's Emerald
ROM. No ROM bytes or extracted native graphics are included in either release.

## Modern moves and abilities

Combat implementation adapted from **tectorifter/Gen9Dex**, latest release **v4.8.1**, by tectorifter and its credited contributors: https://github.com/tectorifter/Gen9Dex/releases/tag/v4.8.1 . Only the battle mechanics are bundled; existing national-dex species/move/ability metadata is reused. Copyright notices and GPL-3.0-or-later terms are retained in [battle-mechanics/LICENSE](battle-mechanics/LICENSE), with [upstream credits](battle-mechanics/CREDITS.md) and [third-party notices](battle-mechanics/THIRD-PARTY-NOTICES.md). These component terms do not replace the existing national-dex license. Exact source asset and exclusions: [UPSTREAM.json](battle-mechanics/UPSTREAM.json).

Gen 3 adapter: original translation/integration code for the native 0.3.85 battle and save interfaces. poooooby/national_dex_gen3 v0.8.3 was inspected as a reference; its move/ability substitutions and assets were not imported. Adapter combat reuse follows the bundled component GPL-3.0-or-later terms.

Expanded move machines reuse the existing species/form learnsets. Historical learners for Needle Arm, Magnet Bomb, Heal Order and Steamroller were checked against PokeAPI/api-data move records on October 14, 2026: https://github.com/PokeAPI/api-data/tree/master/data/api/v2/move . Machine/shop integration is original GPL-3.0-or-later code.

## G9 GEN3 sprite option (1.5.3)

Imported from the user-supplied `g9-battle-sprites-gen3-1.5.4.zip`, from
poooooby/g9-battle-sprites-gen3, based on tectorifter's G9 sprites and the DBK
sprite pack. Original artist credits, GPL license and third-party notices are
preserved in `sprites/g9_gen3/`. Only indexed battle-art data is imported; the
standalone mod's hooks, National Dex dependency and party-icon replacements
are not installed. Existing 1025Dex forms, species and icons remain in control.
