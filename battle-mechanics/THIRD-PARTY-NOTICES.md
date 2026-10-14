# Third-Party Notices

## Pokemon intellectual property

Pokemon and all related names, characters, creatures, moves, items, types,
sprites, music, sound effects and other assets are the intellectual property
and/or registered trademarks of **Nintendo**, **Creatures Inc.**, **GAME FREAK
inc.** and **The Pokemon Company**.

This mod is an **unofficial, free, fan-made project** for the
[gen1recomp](https://github.com/bryanthaboi/gen1recomp) engine. It is **not**
produced, affiliated with, sponsored by, endorsed by or approved by Nintendo,
Creatures Inc., GAME FREAK inc., The Pokemon Company or any of their
subsidiaries or affiliates, and it claims no ownership of, or licence to, any
Pokemon intellectual property. The Pokemon names and other marks it reads or
displays remain the property of their owners and are used only to describe the
game data the mod operates on.

## This mod's own work

The only material this project owns is its **original source code** -- the Lua
that hooks the gen1recomp engine, written by its author. That code is licensed
under the **GNU General Public License, version 3 or later (GPL-3.0-or-later)**,
copyright (C) 2026 **tectorifter** (<https://github.com/tectorifter/>); the full
licence text ships beside this file as `LICENSE`. That grant covers this
project's own code only -- it does **not** purport to license any Pokemon data,
artwork, audio, text or other game asset, which remain their owners' property.

## Third-party material

### Pokemon Showdown

This mod's battle engine is a **derivative reimplementation of Pokemon
Showdown's battle simulator**. Its damage formula, turn order, status and
volatile handling, move sub-effects, and ability / item interaction rules are
transcribed and adapted from Pokemon Showdown's own server source, the "sim"
(<https://github.com/smogon/pokemon-showdown>) -- notably `sim/pokemon.ts`,
`sim/battle.ts` and `sim/battle-actions.ts`, and the data in
`data/moves.ts`, `data/abilities.ts`, `data/items.ts` and
`data/conditions.ts`. `combat/showdown_primitives.lua` is the clearest single
example: its damage / heal / status / volatile / stat primitives reproduce the
behaviour of `sim/pokemon.ts` and `sim/battle.ts` rather than inventing it.

Pokemon Showdown is distributed under the **MIT License**. Its copyright notice
and permission notice are retained below, as that licence requires. Nothing in
this project is claimed to be Pokemon Showdown's work; credit for the combat
formulas and mechanics belongs to Pokemon Showdown and its contributors.

```
The MIT License (MIT)

Copyright (c) 2011-2026 Guangcong Luo and other contributors http://pokemonshowdown.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## Sources and credits

- **Pokemon Showdown** -- see above; the combat formulas and mechanics are
  derivative of its sim, used under the MIT License.
- **national_dex** (<https://github.com/sanjinpepic/gen1recomp-national-dex>) --
  the optional species / move / ability / item data source read at runtime.
- **PokeAPI** (<https://github.com/PokeAPI/pokeapi>) -- the modern records this
  engine reads are PokeAPI-derived through national_dex. PokeAPI is distributed
  under the **BSD 3-Clause License**, copyright (c) 2013-2023 Paul Hallett and
  PokéAPI contributors; Pokemon and Pokemon character names are trademarks of
  Nintendo.
- **zeak6464 / Gen1Recomp-Content-Editor** -- a LÖVE-based mod / content editor
  and modkit-style workflow studied as a reference. Its development-time ROM
  roster (`tools/rom_manifest_gold.json`'s `itemOrder`, the cart's own 250 item
  ids) was used to cross-check this engine's item data. **No file from it is
  redistributed**; the repository publishes no licence of its own, so only its
  ideas and the publicly-readable ROM item order are used, with credit.
  Reference release: `content-editor-v0.1.8`
  (<https://github.com/zeak6464/Gen1Recomp-Content-Editor/releases/tag/content-editor-v0.1.8>).
- **tectorifter / Gen9Dex** (<https://github.com/tectorifter/Gen9Dex>) -- the
  upstream project this engine's boot sequence and its ability / item / combat
  subsystems were restored from (the same author as this mod).
- **gen1recomp** (<https://github.com/bryanthaboi/gen1recomp>) -- the engine this
  project builds on; its public mod API and engine behaviour are what this code
  hooks. See that repository for its own licence.
- This mod ships **no Pokemon artwork, audio or text**; it contains only Lua
  code and the documentation listed in `files.json`.
