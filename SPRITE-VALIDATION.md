# 1.2.16 sprite validation

- All 6,307 imported PNGs are byte-identical to the supplied static pack.
- Actual alpha bounds were tested through the production layout code in all
  three generations: 18,921 layouts. No art rectangle exceeds its picture box;
  the grounded-art baseline is consistent, and complete-canvas scaling preserves
  the pack's relative sizes rather than enlarging each silhouette to fill its box.
- Lua 5.3 and LuaJIT 2.1 compile every Lua file. Both pass 46 new source-selection,
  palette, alias, fallback, density, union-bounds and cache-reset assertions;
  17 battle-position assertions; and 50 existing shiny/animation regressions.
- A native LÖVE ImageData probe decoded actual PNGs and ran production scanning,
  layout and pixel baking for 56 combinations: front/back, normal/shiny and both
  styles for Gmax Blastoise, Cacturne, Emolga, Alolan Sandshrew, Mega Tyranitar,
  Bulbasaur and female Basculegion. Every Gen 3 result is 64×64. First, middle and
  final animated frames were exported; the representative contact sheet was
  inspected visually. This is a renderer probe, not a live battle screenshot.
- The existing all-eleven-game registry, entrypoint, encounter, cry identity and
  Hoennto 1,025-member collection projection fixtures pass after the update.

Native battle checks cover differing cartridge sprite offsets, both sides,
double battles, Transform, ghosts, substitutes and preserved animation bounce.
Static style isolates its source/palette/side caches; changing styles also clears
old mutable-image animation data. Missing static forms remain the correct form
using one frame of matching animated artwork. The pack's Ruby scripts are not used.

Live launcher battles and a full playthrough have not been run. Floating sprites
retain intentional authored motion/hover; stable union bounds do not pin each
animated frame's moving feet to a fixed line, which would remove that motion.
