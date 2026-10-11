# assets/icons

Bundled art for the party screens: the little icon beside each Pokemon in the
party list, on both generations. Two atlases of the **same** icons — one small,
one at the pack's natural size — addressable by the one cell index in
[`../../data/icon_data.lua`](../../data/icon_data.lua).

* `party_icons.png` — the **PARTY ICONS** atlas: one atlas of 16×16 cells,
  **60 columns**, two consecutive cells per icon (its two animation frames).
  This is what the game's own 160×144 party list draws.
* `party_icons_hd.png` — the **G9 PARTY SCREEN** atlas: the **same icons in the
  same cell order**, but each frame kept at the pack's own **64×64** (so a cell
  is 64×64, still 60 columns, two cells per icon). The 4× party page draws these
  1:1 in the row's 16×16 design slot (16 design units × 4 = 64 screen pixels),
  so the art is shown at full resolution instead of being shrunk.

`data/icon_data.lua` holds the species → icon → cell map (plus the female
variants and the egg) **once**; its `base` cell index addresses either atlas,
and `hdCell` / `hdCols` say the HD atlas's cell size and column count. The mod
draws a cell with a Quad; nothing is baked at runtime and there is no network
access.

Both atlases are built in one pass from the third-party **"icones animados"**
icon pack (one 128×64 two-frame PNG per icon) by
[`../../tools/rebuild_icon_atlas.mjs`](../../tools/rebuild_icon_atlas.mjs) — see
[`../../tools/README.md`](../../tools/README.md) for the recipe. **Do not edit
the atlases or `data/icon_data.lua` by hand**; rerun the tool instead. The
source pack itself is *not* shipped with the mod (third-party fan art) — only
these two atlases are. Icon-art credit is in
[`../../manifest.json`](../../manifest.json).

A species the pack has no icon for simply keeps the game's own party icon, and
an egg uses the pack's `000` icon.
