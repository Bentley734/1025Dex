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

- **Battle-sprite art ships with the mod.** Every DBK animated
  front / back (and shiny) sheet is bundled under
  `assets/front|front_shiny|back|back_shiny`. The animation format and the
  sheets come from **La Base de Sky**'s DBK "solo sprites" pack, and the
  underlying Pokemon sprite art is the **EeveeExpo Resource Pack** (resource
  1544): Luka S.J., the Smogon X/Y, Sun/Moon, Sword/Shield and Scarlet/Violet
  Sprite Project contributors, and the many named sprite artists. The full list
  is in `CREDITS.md`.
- **Party / UI icon art ships with the mod too** (`assets/icons/party_icons.png`
  and `party_icons_hd.png`). It is community icon fan art, built from the
  "icones animados" icon pack and credited (with the icon projects named in
  `CREDITS.md`) to its authors. The pack's build input `tools/icon_pack.zip`
  is developer-only and is **not** shipped.
- **Effect / background art.** `assets/tera_crystal.png` is built from the
  "Crystal Textured Background" designed by rawpixel.com / Freepik, and the
  Dynamax cloud art reference is "Transparent Dynamax Clouds" by bearbro123 --
  both credited in `CREDITS.md`.
- **pokeemerald-expansion front pics ship with the mod**
  (`assets/atlas/dex_fronts_0.png`, shown on the Ruby/Sapphire/Emerald Pokédex). They are packed
  by `tools/build_atlas.py` from the `graphics/pokemon/` folder of **pokeemerald-expansion**
  (<https://github.com/rh-hideout/pokeemerald-expansion>, the Rom Hacking Hideout team and
  contributors): the Generation 1-3 pics are the original games' art via **pokeemerald**
  (<https://github.com/pret/pokeemerald>), and the later ones are the community sprite projects
  pokeemerald-expansion credits (listed in `CREDITS.md`). pokeemerald-expansion ships no licence
  file; the art remains its authors' and the Pokemon IP owners' property, and no ownership is
  claimed. Its back sprites are read by the build tools as framing references only and are not
  shipped.
- **La Base de Sky art** -- the `assets/egg.png` picture and the three generic
  contact shadows (`assets/shadow/1.png`, `2.png`, `3.png`) come from
  La Base de Sky's `Graphics/Pokemon/{Eggs,Shadow}` folders.
- **Generated art** -- the two icon atlases and `data/icon_data.lua` are built
  by this project's own tools from the icon pack; no ownership of any
  third-party sprite or icon art is claimed.

## Sources and credits

- **PokeAPI** (<https://github.com/PokeAPI/pokeapi>) -- `tools/rebuild_dbk_float.mjs`
  parses PokeAPI's `pokemon` / `pokemon_types` / `types` / `pokemon_abilities` /
  `abilities` CSVs to build the FLOATERS set (`data/dbk_float.lua`); PokeAPI is
  under the **BSD 3-Clause License**, copyright (c) 2013-2023 Paul Hallett and
  PokéAPI contributors. The art credits (EeveeExpo / DBK / La Base de Sky /
  "icones animados") are in `CREDITS.md`.
- **gen1recomp** (<https://github.com/bryanthaboi/gen1recomp>) -- the engine this
  project builds on; its public mod API and engine behaviour are what this code
  hooks. See that repository for its own licence.
