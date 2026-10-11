# assets/shadow

Contact shadows for the **BATTLE SHADOWS** option.

The three bundled files are the generic battle shadows from La Base de Sky's
`Graphics/Pokemon/Shadow` folder (the same art the base game uses):

* `1.png` — small shadow, `2.png` — medium, `3.png` — large.

The pack's own `ShadowSize` metric for a species picks which file is used and
how wide it reads (see `../../data/dbk_metrics.lua`): the default `1` uses
`1.png` at the middle width, `2`/`3`/`4` stretch it wider, `-1`/`-2`/`-3`
tighten it, and `ShadowSize = 0` means "this species casts no shadow". (The
file choice is clamped to the three above, so a size of `4` still uses `3.png`,
just wider.)

## Per-species art

To give a single Pokemon its own shadow, drop a PNG here named for that
Pokemon's **sheet stem** — exactly the name its battle sheet uses:

* `CHARIZARD.png`, `CHARIZARD_1.png` (mega Charizard X), `PIKACHU_female.png`,
  `ALCREMIE_63.png` (gigantamax Alcremie) ...

A stem file wins over the generic size art. Any PNG shape works; the mod
measures the file's own opaque pixels and draws them with their bottom edge on
the ground line, centred under the Pokemon (shifted by the pack's `ShadowSprite`
x offset). Black-with-alpha art (like the three bundled files) reads best.

Everything is optional: with this folder empty **BATTLE SHADOWS** simply does
nothing, and the mod never touches the network.
