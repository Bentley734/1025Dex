# g9-battle-sprites

True-colour, **frame-animated battle sprites** for the whole national dex,
loaded from the **DBK animated "solo sprites"** pack
(`la-base-de-sky / la-base-de-sky-plugins / sprites-animados-dbk-solo-sprites`,
folders `Graphics/Pokemon/{Front, Front shiny, Back, Back shiny}`).

It replaces the enemy **front** pic and the player **back** pic in battle with
the matching animated sheet, the **front pic on the Pokedex** entry page — on
gen1 that is the **national dex's own Pokédex screen**, its **STATS page** and
its LEFT/RIGHT **form browsing** included — the **party Summary screen's
front pic**, on the native screen (gen1 and gen2) and on any custom screen that
replaces it (e.g. the g9 battle engine's wide modern STATS screen), and the
little **16×16 icon on each party-list row** (gen1 and gen2 — from the mod's own
bundled animated icon atlas, not the sheet; see [PARTY ICONS](#party-icons-the-bundled-icon-atlas)). With the opt-in
**G9 PARTY SCREEN** row it can also redraw the **whole party page** from the
game's own parts on a 640×576 surface (4× the Game Boy screen), so the pack's
icons show at their natural 64×64 size — see [G9 PARTY SCREEN](#g9-party-screen-the-4x-page). In battle it also bakes the Tera-crystal film and the Dynamax
cloud over a transformed Pokemon and a **contact shadow** behind every battler
(see [TERA ART](#tera-art-the-crystal-film), [DYNAMAX CLOUD](#dynamax-cloud-the-crown)
and [BATTLE SHADOWS](#battle-shadows-the-contact-shadow)). Everything
else — the send-out grow, faint slide, blink/squish,
the SGB/GBC palette machinery — keeps working, because the mod hands the
engine's own draw path a normal LÖVE `Image` per frame.

## The one decision that shapes everything: use the sheet directly

Every file in the pack is **one PNG per Pokemon**, laid out as a single
horizontal strip of frames that butt edge to edge, left to right, where
`frame height == sheet height` and
`frame count == round(width / height)`.

So there is **no splitting step and no per-Pokemon subfolders**. The mod:

1. decodes the sheet once — through up to three fallback routes, since a mod
   cannot assume any one image decoder exists on a given build: the engine's own
   asset path first (`love.image.newImageData(mod.assets:path(...))`, what every
   image-loading mod uses), then the raw bytes via a `FileData`, then a
   `love.graphics.newImage(path):getData()` detour,
2. crops each frame out of it **in memory**,
3. resamples that frame **once** to the on-screen pic box — at the largest
   scale that box allows (see [Sizes and alignment](#sizes-and-alignment)) — and
   offsets it by the pack's own metrics, then caches the result.

The raw PNG stays a single file under `assets/<type>/<STEM>.png`. You copy one
`.png` per Pokemon — never a folder of frames.

## Lookup (for each battle pic)

1. **national dex species id** (+ gender + shiny) → a **DBK stem** via
   `data/dbk_data.lua`.
2. `<mod>/assets/<front|front_shiny|back|back_shiny>/<STEM>.png` — your local
   copy. **This is the only source: the mod does not touch the network.**

Stems/ids are matched exactly; a lookup that cannot resolve falls through to the
vanilla pic, so a missing sheet is never an error on screen. A sheet that
resolves nowhere is **not** latched as dead — it is retried every ~15 s, so a
file copied into `assets/` while the game is running is picked up on the next
recheck without a restart.

Fill `assets/` by hand, or with the helper script that ships in the mod (see
[Getting the sheets](#getting-the-sheets-the-helper-script)).

## Form conventions (the part that needed care)

The national dex gives every *mechanically or sprite-distinct* form its own
species id, and `data/dbk_data.lua` maps each id to **the pack's own stem**.
Examples baked into the data:

| national dex id | DBK stem | What it is |
|---|---|---|
| `CHARIZARD_MEGA_X` | `CHARIZARD_1` | Mega Charizard X |
| `CHARIZARD_MEGA_Y` | `CHARIZARD_2` | Mega Charizard Y |
| `CHARIZARD_GMAX` | `CHARIZARD_3` | Gigantamax Charizard |
| `RAICHU_ALOLA` | `RAICHU_1` | Alolan Raichu |
| `SNEASEL_HISUI` | `SNEASEL_1` | Hisuian Sneasel |
| `ALCREMIE_GMAX` | `ALCREMIE_63` | Gigantamax Alcremie |
| `MEOWSTIC_FEMALE` | `MEOWSTIC_1` | Female Meowstic |
| `BASCULEGION_FEMALE` | `BASCULEGION_1` | Female Basculegion |
| `OINKOLOGNE_FEMALE` | `OINKOLOGNE_1` | Female Oinkologne |

**Ignored forms.** Cosmetic-only forms the pack has no sheet for (e.g. every
Alcremie flavour that is not base or gigantamax) are *not* mapped; they fall
back to the base species sheet. That matches the pack's own intent — base
`ALCREMIE`, gmax `ALCREMIE_63`, everything else irrelevant.

**Base fallback.** If an id is not mapped at all (totems, story-only modes like
`PIKACHU_STARTER`, `KORAIDON`/`MIRAIDON` modes), the mod walks the `_SUFFIX`
chain off the id until it finds a mapped stem — e.g.
`KOMMO_O_TOTEM → KOMMO_O → KOMMOO` (note: the pack **drops underscores** in
species names: `MR_MIME → MRMIME`, `NIDORAN_F → NIDORANfE`,
`NIDORAN_M → NIDORANmA`).

**Female art.** Some Pokemon have a distinct `_female` sheet next to their base
one (`ABOMASNOW_female`, `SNEASEL_1_female`, `EEVEE_1_female`, ...). The
`female` set in `data/dbk_data.lua` lists the ones that exist; a female mon uses
`<stem>_female` when the set contains the **base** stem and FEMALE ART is on.

**Shiny art** uses the `*_shiny` folders when SHINY ART is on.

## Sizes and alignment

The pack draws every sheet at **one uniform scale** (Essentials/DBK's
`FRONT_BATTLER_SPRITE_SCALE = 2`, `BACK_BATTLER_SPRITE_SCALE = 3`), so a bigger
Pokemon is simply a **taller sheet**: relative sizes come straight from the
sheet's own pixel height.

**SPRITE SIZE** decides how much of a sheet's own resolution reaches the
screen. `MAX DETAIL` (0, the default) sizes each sheet on its own: a sheet that
already fits its picture box is kept **1:1** (a small Pokemon keeps every source
pixel), and a sheet that does not is shrunk **no further than it must be**, so a
big Pokemon fills the box instead of sitting at half size inside it. Relative
size is still honoured for everything that fits; sheets taller than the box all
land on the box, which is as large as the screen can show them anyway. `SMALL`
(3), `NORMAL` (2) and `BIG` (1) instead divide every sheet by that one whole
number, which keeps their relative sizes strictly proportional. Whatever the
mode, a sheet too big to fit the box is scaled back to it, so nothing is ever
clipped.

**GROUND ANCHOR** then decides the line a sprite stands on. `FEET` (the
default) is the one that makes every grounded Pokemon share a line: the pack's
sheets are **not** trimmed, so each species carries its own empty padding under
its feet — Zigzagoon's feet sit far higher up its sheet than Wooloo's — and
those padding differences must not move the Pokemon. We trim every sheet to its
content first, and `FEET` then always places that content's **bottom edge (the
feet) on the bottom of the picture**, so Zigzagoon and Wooloo land their feet
on exactly the same line however much space their sheets carried. The content is
centred horizontally at the same time. `PACK` uses the pack's own
`SpeciesMetrics` offsets (see below), and `BOX` simply bottom-centres with no
alignment at all — both kept for anyone who preferred the old look.

A Pokemon the pack draws **airborne** — a flying or levitating species — must
*not* sit its feet on that line. `FLOATERS` (on by default) lifts each of those
sheets off the ground by a share of its **own height** (35%), so a big flyer
hovers higher than a small one instead of every flyer floating at one fixed
height. The species list is `data/dbk_float.lua`; turning `FLOATERS` off puts
every sprite's feet back on the line. This only applies in `FEET` mode.

`PACK`'s arithmetic, for reference: the pack anchors a sheet's *untrimmed* frame
bottom-centre at a fixed base and shifts it by the metrics × 2 screen px. We
trim each sheet to its content first, so the padding the metrics assume is gone
and is put back with the same arithmetic Essentials/DBK use:

* the content bottom sits `padBot` rows above the frame bottom → `- padBot`;
* the content mid-x sits `(padL - padR) / 2` px off the frame mid-x, and our
  baseline centres the content → `- (padR - padL) / 2`.

`offset × 2 ÷ renderScale` converts a metric to sheet pixels, and the result
scales with the sprite, so alignment stays proportional at any SPRITE SIZE. The
final position is clamped inside the box, so nothing is ever baked off-canvas.

The battle screens do the rest: both the game's own battle screen and
`g9-Battle-Scene` draw a sprite **bottom-anchored on its slot's ground line**,
so the bottom edge of the image we hand them *is* the line the feet land on.
Keep that in mind if you fork the draw path.

**Baking always samples the nearest source pixel, never an average.** Each
destination pixel takes the single source pixel nearest its own centre. That
holds at a fractional scale too: a fractional *step* simply means neighbouring
destination pixels advance by different whole numbers of source pixels, so
every block stays square and every pixel keeps an exact colour from the pack's
palette. Hard edges and true colours are the whole point — and a box/area filter
is the one thing that destroys both, blending neighbouring colours into new ones
and reading as a soft, muddy smear beside the game's crisp pixel UI. (An earlier
build area-averaged at a fractional scale and produced exactly that: the
"blurry sprites" complaint.) A destination pixel whose nearest source pixel is
transparent borrows the nearest opaque pixel it covers, so a one-pixel outline
or antenna is never punched out by the sampling stride.

Changing SPRITE SIZE, GROUND ANCHOR or FLOATERS requeues every sheet, so the new
setting shows up in the next battle with no restart.

## Front-facing sprites (3DB FRONTAL / FLIP)

By default the player's Pokemon stands with its **back** to you (the back sheet)
while the foe shows its front — exactly what the game intends. Two rows let both
sides be drawn **front-on**:

* **3DB FRONTAL** (off by default) shows the player's Pokemon with its **front**
  sheet in place of its back sheet, so *both* Pokemon on the field are drawn
  front-on. It is a straight substitution: the back sprite is replaced by the
  frontal art with **no flip**.
* **3DB FLIP** (off by default) then mirrors that player-side front art
  **horizontally** (across its vertical axis), so a creature whose front art is
  drawn facing your left now faces **right**, toward the foe across the field.
  Only the player's side is mirrored — the foe already faces you. The flip is
  meant to be used together with 3DB FRONTAL: with 3DB FRONTAL off the player is
  showing its back sheet, and a back sprite is never mirrored, so the row does
  nothing on its own.

Both rows apply everywhere battle pics are drawn — the native gen1 and gen2
battle screens *and* every custom battle screen (`g9-Battle-Scene` and its
forks) — because all of them resolve through the same sheet factory. The mirror
is baked into **every frame** of the sheet, after the crystal, cloud and shadow
are composited, so the sprite and everything riding it turn together and stay
registered, and it can never flip mid-animation. Because the front-substituted
sheet is a distinct sheet in the cache, the player's slot keeps its own box and
ground line: the art changes, the placement does not. The Pokedex, the summary
and the party list already show front art and are untouched. Changing either row
requeues the affected sheets, so the new orientation shows up in the next battle
with no restart.

## Mod Manager options

| Row | Default | Meaning |
|---|---|---|
| **BATTLE SPRITES** | on | Master switch. Off → every pic is exactly what the game would draw. |
| **ANIMATE** | on | Play the sheet left-to-right as a loop. Off → frame 1 only. |
| **SPRITE SPEED** | NORMAL (12 fps) | Playback speed: SLOW 6 / NORMAL 12 / FAST 18 / VERY FAST 24. |
| **SHINY ART** | on | Use `*_shiny` sheets for shiny mons. |
| **FEMALE ART** | on | Use `_female` sheets where the pack has one. |
| **SPRITE SIZE** | MAX DETAIL (0) | How much of each sheet's own resolution reaches the screen: MAX DETAIL 0 = the largest scale that fits each sheet's box (1:1 wherever it fits), SMALL 3 / NORMAL 2 / BIG 1 = divide every sheet by 3/2/1 for strictly proportional sizes. See [Sizes and alignment](#sizes-and-alignment). |
| **GROUND ANCHOR** | FEET | The line a sprite stands on. **FEET** (default) puts every grounded sprite's own feet on the bottom of its picture, so all grounded Pokemon share one ground line however much empty padding their sheets carry (Zigzagoon and Wooloo land their feet at the same height). **PACK** uses the pack's own SpeciesMetrics offsets. **BOX** bottom-centres with no alignment. See [Sizes and alignment](#sizes-and-alignment). |
| **FLOATERS** | on | In FEET mode, lift a sprite the pack draws airborne (a flying/levitating species, `data/dbk_float.lua`) off the ground by 35% of its own height, so a big flyer hovers higher than a small one. Off → every sprite stands its feet on the line. No effect in PACK or BOX mode. |
| **3DB FRONTAL** | off | Show the player's Pokemon with its **front** sheet on the battle field instead of its back sheet, so both Pokemon are drawn front-on (the foe already shows its front). A straight substitution — the back sprite is replaced by the frontal art with **no flip**. Applies to the native gen1/gen2 battle screens and every custom battle screen. See [Front-facing sprites](#front-facing-sprites-3db-frontal--flip). |
| **3DB FLIP** | off | Mirror the player's own front sprite **horizontally** (across its vertical axis), so a creature whose front art faces your left now faces right, toward the foe. Player side only — the foe already faces you. Meant to be used with 3DB FRONTAL; with that row off the player shows its back sheet and this row does nothing (a back sprite is never mirrored). See [Front-facing sprites](#front-facing-sprites-3db-frontal--flip). |
| **BATTLE SHADOWS** | on | Draw a contact shadow behind each battler so it stands on the field instead of floating. A species gets its own `assets/shadow/<STEM>.png` if present, otherwise the generic small/medium/large art chosen by the pack's `ShadowSize` (`ShadowSize 0` → no shadow); width tracks `ShadowSize`. See [BATTLE SHADOWS](#battle-shadows-the-contact-shadow). Off → no shadow is baked. |
| **DEX SPRITES** | on | Show the same sheet on the Pokedex front pic (first frame when ANIMATE is off) — on gen1 that includes the national dex's own Pokédex screen, its STATS page and its form browsing. Off → the Pokedex keeps the game's own pic. |
| **SUMMARY SPRITES** | on | Show the same sheet on every party Summary screen's front pic (the native screen and any custom screen replacing it) — the FRONT sheet, or `*_shiny` FRONT for a shiny mon. Off → summaries keep the game's own pic. |
| **SUMMARY SIZE** | REAL SIZE (100) | How big the Summary picture is drawn: REAL SIZE is the battle screen's own 1:1 front box, 75% / 50% / 25% draw the very same sheet smaller inside that box (centred, still animated, still true-colour). Summary only — battles, the Pokedex and custom scenes always keep the full-size picture. |
| **PARTY ICONS** | on | Draw each party-list row's little 16×16 icon from the mod's own **bundled animated icon atlas** (two true-colour frames per Pokemon, female variant where the pack has one) on both generations, wherever the party list is drawn — overworld and in battle. Off → the party list keeps the game's own two-colour icon art. |
| **G9 PARTY SCREEN** | off | Off (default) → the party list is the game's own 160×144 screen (with the PARTY ICONS art on it when that row is on). On → the whole party page is redrawn from the game's **own** parts — the same two-line rows (name, level, HP figures, HP-bar tiles, status/FNT), cursor, CANCEL row and box — from the tiles and fonts of whichever generation you are playing, in exactly the same proportions, but on a **640×576** page (4× the Game Boy screen, scaled to fill the window). That larger page is what lets each Pokemon's **high-resolution** icon art (`assets/icons/party_icons_hd.png`, the pack's natural 64×64 frames) be drawn at its own size instead of being shrunk into a 16×16 slot. The action list that opens when you pick a Pokemon (STATS / SWITCH / field moves / ITEM / CANCEL) is the game's own submenu, unchanged. See [G9 PARTY SCREEN](#g9-party-screen-the-4x-page). |
| **TERA ART** | on | While a Pokemon is Terastallized — or is a wild Tera raid boss announced by `g9-Battle-Scene` — bake the cut-crystal film (see [TERA ART](#tera-art-the-crystal-film)) into each frame: flat angular facets in a chaotic mix of broad slabs and small chips, fine dark bevel seams that carry the type's own tint, a glowing chamfered rim and small white 4-pointed star sparkles of pure light (no dark halo) that blink on their own cycle over the lightest facets, tinted with its Tera type — and the whole crystal rides the sprite's own animation instead of staying put. The state is read live from `battle_forms`, or from the raid declaration the screen hands over. Off → frames are plain. |
| **TERA TRANSPARENCY** | 30% | How see-through the TERA ART crystal is: 5 / 10 / 20 / 30 / 40 / 50 / 60%. The figure is how much of the Pokemon's own colours show **through** the crystal, so 30% is the 70/30 crystal-over-sprite blend the effect ships with, 5% is an almost solid gem and 60% is a sheer, glassy film. Only the crystal layer's own opacity changes — its facets, colours, bevel seams, rim, glints and sparkles are untouched. Does nothing when TERA ART is off. See [TERA ART](#tera-art-the-crystal-film). |
| **DYNAMAX CLOUD** | on | While a Pokemon is Dynamaxed or Gigantamaxed — or is a wild Dynamax/Gigantamax raid boss announced by `g9-Battle-Scene` — bake the red cloud (see [DYNAMAX CLOUD](#dynamax-cloud-the-crown)) into each frame so it rests on the head like a crown. The state is read live from `battle_forms`, or from the raid declaration the screen hands over. Off → frames are plain. |

Rows are declared in `options.lua` (so a disabled mod still shows them) and
mirrored in `main.lua`, which is what gives the values their defaults.

## TERA ART (the crystal film)

A Terastallized Pokemon wears a **cut-crystal** film tinted with its own Tera
type and blended **70/30** (70% crystal — the **TERA TRANSPARENCY** row tunes the
crystal's own share) into the sprite frame. The pattern is
one of only two pieces of artwork the mod ships (`assets/tera_crystal.png`, plus
the Dynamax cloud in [DYNAMAX CLOUD](#dynamax-cloud-the-crown)); every other
pixel is your DBK sheets.

**Only the creature is covered, never its frame.** The film is not a second,
transparent draw pass over the pic box — that would tint the box's invisible
margin and show as a tinted rectangle around the creature. Instead the film is
composited into the **baked frame** at the same moment the frame is resampled,
and a destination pixel only ever receives the film when that pixel came from a
**sprite pixel with alpha > 0**. A transparent frame pixel stays exactly as
transparent as before. The upshot: the silhouette you see is the sheet's own
silhouette, and the crystal can never leak past it.

**A cut gem, built in code.** The film is not the pattern's own soft mosaic
painted straight onto the sprite — at sprite scale that reads as a blur. Instead
the crystal is *cut* into flat shards by a **free-scatter Voronoi lattice**
(`TERA.buildMap`). The sites do not sit on a grid at all: `FACET_SITES` = 180
hash-chosen points are scattered freely over the padded box, which is the only
way to be rid of the rows and columns of seams that any amount of grid jitter
leaves behind — and those rows and columns are exactly what read as a
checkerboard instead of as shattered glass. Each site's cell becomes one
irregular convex plane. The **clustering** is what gives the pane its range of
scales: `FACET_MIX` = 0.8 of the sites are placed around one of the others,
`FACET_MIX_RADIUS` = 1.4 nominal pitches away, so a cluster packs into a field of
small chips while the space between clusters is left to a single site, which
becomes a slab.

The scatter is then held inside a **size band**, both ends expressed as multiples
of the nominal cell area (box area / `FACET_SITES`). `FACET_MIN` = 0.3 folds every
shard below the floor into its **largest** 4-neighbour (`TERA.pickNeighbour` — by
area, not by longest shared edge, because it is the small end of the distribution
that needs pushing up: a chip is absorbed by whichever side is already the
broadest). `FACET_MAX` = 2.2 splits every shard above the ceiling along a wavy
line through its own centroid, repeatedly, until the biggest one is under it;
`FACET_CRACK_BEND` = 0.35 is how far that line wanders (0 is a ruler-straight cut,
which reads as an artificial slice rather than a fracture). A crack that would
leave one side empty is abandoned and the shard is flagged so the search passes
it by instead of spinning on it, and `FACET_SPLIT_GUARD` = 4000 caps the attempts
(it is headroom, not a cost: each split only walks that one shard's own pixels).
The floor pass then runs **again after** the cracks, because a crack can leave a
sliver on one side of the cut. Holding both ends is what lets the *mean* shard be
small — the density is high — without any individual shard shrinking to a speck
of dirt on the glass or growing into one dominating plate. Measured over a solid
56px box (the shard probe's interior areas, the same method the old numbers
came from): the old jittered grid gave ~18 shards of 55–132px, mean 87, cv 0.21;
this gives ~70 shards of 3–56px, mean 23, cv 0.62 — the smallest shard is about
10% of the old smallest, the largest about 40% of the old largest, and the size
spread roughly triples. Every shard carries exactly **one flat colour**, so the
surface breaks into hard-edged planes like a cut stone instead of a continuous
gradient. The lattice depends only on the box and the pattern — both identical
for every sheet — so it is built once and cached (`TERA._maps`, keyed by box size
so a 56px front sheet and a 64px gen1 back sheet do not rebuild each other); a
sheet's per-sheet cost is nil.

**Shard colour.** Each shard samples the pattern at its **centroid**, and that
window's brightness is autocontrast-stretched between the `CONTRAST_LO` (10th)
and `CONTRAST_HI` (97th) percentiles, smoothstepped (`CONTRAST_GAIN` = 1.0) and
quantised to `FACET_LEVELS` = 6 steps — six discrete brightness plates, not a
ramp. Each plate becomes the sheet's type-tinted film colour: a `FILM_DARK` 0.24
→ `FILM_LIGHT` 0.45 ramp toward white, plus `IRID_GAIN` 1.2 of extra chroma so
the crystal is more saturated than the flat type colour. `FILM_DARK` is the whole
dark end of that ramp, so it is the knob for "the dark shards are too black": it
was lifted from 0.20 to 0.24, which is exactly 20% more light in the darkest
plates (the `FILM_DARK`-weighted part of every colour) without touching the lit
end or the plate count — the histogram of a filmed sprite moves its mass up out
of the darkest bins while the mean rises only slightly, which is what a lift of
the *dark parts* alone should do.

**Bevel.** Shard boundaries are welded as a light/dark pair: the side whose
right/below neighbour is a different shard is pulled toward `b.seamLit` — the
type's colour carried `SEAM_TINT` = 0.55 of the way to white, so the highlight
stays on the crystal's own hue instead of flashing a neutral white — by
`SEAM_STRENGTH` = 0.16, and the opposite side is deepened (`SEAM_DARK` = 0.34).
That bright-edge-next-to-dark-edge pairing is most of what makes the planes read
as bevelled cut facets rather than a flat mosaic. Both halves are deliberately
much subtler than the bright white grid line an earlier version drew: at full
strength that line read as an unnatural lattice sitting on top of the sprite
rather than a crack in a stone.

**Specular.** A whole facet can catch a glare: shards whose *pre-quantisation*
brightness clears `SPEC_T0` = 0.90 light up flat to `SPEC_STRENGTH` = 0.6 of
white with a `SPEC_POW` = 3.0 falloff. It keys off the smooth value rather than
the quantised plate, so the glare lands on the genuinely brightest facets
instead of flooding a whole brightness band.

**Rim.** A chamfered rim traced from distance-to-transparent (inside the content
box) glows with `RIM_TINT` = 0.35 of the type colour at `RIM_STRENGTH` = 0.90,
fading inward over `RIM_FALLOFF` = 2.5 pixels.

**Star glints.** `STAR_COUNT` = 9 white 4-pointed stars are stamped on the
crystal. Their anchors are chosen from the creature's own **opaque pixels of the
first baked frame** (the old pattern-space picks mostly landed outside the
silhouette and never showed), and only from the **interior** of a shard (a
**seam-free** pixel — the crystal's *clearest* planes, not its bevel lines).
The score is the pixel's **own baked brightness** (the film composited over the creature, with the shard's lit level
only a tie-breaker), so the sparkles settle on the **lightest** places the eye
reads as clear and bright — not merely on the shards whose *pattern* sample was
light, which bake dark when they lie over a dark part of the creature. Anchors
are thinned `STAR_SPACING` = 0.21 of the box apart so they spread over the
creature, and a star is stamped with the bake's own magnification
(`TERA.starsFor`): a scale-1 bake gets the nominal star, a 4× bake gets a 4×
blocky star, so a sparkle is always the same size in the *creature's* pixels
rather than a speck the resample swallows. `STAR_SPRITE` picks the size in
stamped pixels — the footprint is what the eye reads. All four sizes are now the
same **shape**: a four-pointed star with a solid white heart and one tapering arm
on each of its four sides, and **nothing on the diagonals**. (An earlier star
filled its diagonals too, which at sprite scale made a round blob — it read as a
circle, not a star, however bright the centre was.) **1** is a five-pixel star:
one white pixel and four arms at 0.80. **2** — the default — is nine pixels: the
heart, arms `±1` at 0.82, and shorter arms `±2` at 0.34. **3** is thirteen pixels
(`±1` 0.84, `±2` 0.52, `±3` 0.24) and **4** seventeen (`±1` 0.85, `±2` 0.58, `±3`
0.32, `±4` 0.16). The weight is how far that pixel is pulled toward white, so the
heart is solid light while the points soften into the facet they lie on. A user
who wants them smaller again sets `STAR_SPRITE` to 1.

**A sparkle is made of light.** Every weight in every sprite is **positive**: a
stamped pixel is blended *toward white* by its weight and keeps the rest of
whatever facet sits under it, so the shard shows **through** the star, which only
ever brightens. Earlier versions also deepened a ring around each star — a
negative-weight **dark halo** whose pixels were multiplied by `1 + w` — on the
theory that a dark ring is what makes a tiny bright star legible on a light
crystal. In practice, on a light sky, gem or water tile the creature is standing
on, that ring read as a dirty smudge around every glint, so the halo is gone and
the stamp pass no longer even has a darkening branch. Verified by diffing a bake
against the same sheet baked with `STAR_COUNT` = 0: the sparkles brighten hundreds
of pixels and darken exactly none.

**The sparkles are their own animation.** The star field is not one fixed
constellation stamped identically into every frame. Each anchor is dealt, from
the deterministic hash, a **phase** and a whole number of **pulses per loop**
(1…`STAR_MULT` = 2) — whole pulses so the twinkle is seamless when the animation
wraps, and only a couple of them so the stars breathe rather than flicker. Per frame every star's weights are multiplied by a pulse of its own cycle:
the pulse is fully off while its wave is below `STAR_FLOOR` = 0.30, ramps to full
at `STAR_FULL` = 0.75, and holds in between (a clear ON stretch and a clear OFF
stretch, rather than a star that hovers at half brightness forever), and a star
below `STAR_MIN` = 0.06 is not stamped at all, so a nearly-dead twinkle leaves no
faint grey residue on the facet. The result: as the sprite animates, the lit
stars keep blinking on and off all over the lightest facets on a cycle of their
own.

**Composition.** The film, its bevel, its specular, its rim and its stars are all
baked into the frame together:

```
out.rgb = (1 - MIX_FILM) * sprite + MIX_FILM * film
out.a   = sprite.a            -- the sprite's own alpha; never the frame's box
```

with `MIX_FILM` = 0.70 by default. The **TERA TRANSPARENCY** row overrides it to
`1 - transparency/100` (5% → 0.95, 60% → 0.40), resolved once per sheet and stored
on the bake as `b.filmMix`; every other stage (bevel, specular, rim, stars) is an
affine map of the mixed pixel, so the row changes only *how much* crystal there
is, never its shape or colour. Everything is mapped in **destination box space**.

**Travelling with the sprite (ANIMATION RIDE).** The crystal is not nailed to the
picture box while the creature bobs inside it — that reads as a flat glass pane
swimming over the sprite. The scan records each frame's **content centroid**
(`b.fcx` / `b.fcy` / `b.fn`, accumulated as the sheet is read in chunks,
`scanChunk`), and when a frame is baked the whole lattice is sampled at that
frame's displacement from the first frame's centroid, converted to destination
pixels and clamped to `±PAD` (`PAD` = 12). The facets, the bevels, the rim and the
sparkle anchors all shift together as one rigid body, so the crystal *rides* the
sprite's own motion. To allow that translation without running off the pattern,
the lattice is cut over a `PAD`-pixel margin all round the content box
(`DW = dw + 2·PAD`, `DH = dh + 2·PAD`); the pattern window and facet scale are
still measured against the real content box, so the margin changes nothing at
rest — the shards just outside the box are clipped away by the silhouette rule as
usual. (Verified against the real sheet: a pure-lattice bake of PIKACHU frame 4
vs frame 0 cross-correlates at exactly the frame's content-centroid shift, with a
zero-error peak at the matching integer offset.)

**Type colours.** The full 18-type palette is in `main.lua` (`TERA_TINT`). It
follows the Scarlet/Violet type colours, with these overrides:

| Type | Colour |
|---|---|
| NORMAL | shiny white |
| WATER | `#2980EF` (the chart's water blue) |
| FLYING | sky blue |
| STEEL | metallic gray |
| STELLAR | shiny silver |

`???` is deliberately **absent** from the table: an unmapped type simply draws no
film, which is also what any future type id gets.

**Where the state comes from.** Terastallization is not this mod's; it belongs to
`battle_forms`, which this mod only **reads**. While a battler is Terastallized,
`battle_forms`' exports report the live Tera type, and the mod bakes a
**per-type variant** of that sprite sheet on the existing budgeted build path
(so a mid-battle Terastallize never stalls a frame).

**Declared raid bosses.** A *wild* Tera raid boss is the one case the live read
cannot answer. `g9-Battle-Scene`'s `special_boss.lua` stamps the boss with its
Tera type, and its opening F-box announces it ("You have found a Tera WATER
Krabby raid!"), but it deliberately never *activates* the gimmick — `battle_forms`
only ever activates on the player's side — so there was no live state for this
mod to read and the boss drew ordinary, i.e. the announcement and the sprite
disagreed. The screen now also hands the mod that declaration: it copies
`battle.g9BossKind` onto the boss battler as `g9RaidGimmick` right after the
battle screen is built, `battle_screen.lua`'s `resolveSprite` forwards it as
`ctx.boss` / `ctx.bossGimmick` on the `battle.mon_pic` seam, and this mod paints
the declared type's film when the live read found nothing. The declaration is
**visual only** — it never activates the gimmick, never touches the mon, and
carries no mechanics.

**Only a live or declared state paints** — a Pokemon that merely *has* a Tera
type does not wear the film until it actually transforms (or is a declared raid
boss). A real live state always wins over a declaration, an unmapped/absent
declared type draws nothing, and the same option gate applies: with TERA ART off
neither paints.

Everything about the lookup is forgiving, because `battle_forms` is optional and
may arrive late: a missing mod, a missing export, a raised error or a missing
field all mean "no film" rather than a broken battle. If the filmed sheet is
still baking when the battle needs it, the **plain** frame is drawn instead, so
the sprite never blanks — the crystal simply pops in a tick later.

## DYNAMAX CLOUD (the crown)

A **Dynamaxed or Gigantamaxed** Pokemon wears the pack's own red Dynamax cloud
(`assets/dynamax_cloud.png`) above its head, like a crown. It is the second
piece of artwork the mod ships; every other pixel is your DBK sheets.

**Baked into every frame, never a second draw pass.** The cloud is composited
into the **baked frame** at the same moment the frame is resampled, exactly like
the Tera film and for the same reasons: it costs nothing per frame, it can never
desync from — or flicker with — the frame clock, and every frame of the
animation carries it identically. There is no separate cloud object to keep in
sync with the animation.

**It rests ON the head, not over it.** The cloud is source-over composited, and
its **dense mass** — not its faint tail — is anchored to the row the baked
sprite's own content actually starts on, sunk a couple of pixels past it, so the
puffs overlap the head they sit on. (Anchoring to the trimmed sheet's
destination top instead would leave the cloud hovering whenever the pack's
metrics alignment, or a transparent rim in the trim box, pushed the visible
content down inside it.) Two constants, both measured from this asset, drive it:

| Constant | Value | Meaning |
|---|---|---|
| `CLOUD_BAND` | `0.26` | Share of the frame's height the cloud gets |
| `CLOUD_MASS_BOT` | `0.585` | Where the cloud's mass thins into its faint tail, from its bottom |
| `CLOUD_OVERLAP` | `2` | How many pixels past the head top the mass bottom lands |

Replacing the cloud art? Re-measure `CLOUD_MASS_BOT`: it is the last row still
holding at least ~40% of the cloud's widest row.

**Room, without moving the feet.** In a **fixed picture box** (the game's own
battle screens) the cloud claims a band off the *top* and the sheet is fitted
into what is left, so the cloud rides above the head without covering the face —
and a sheet short enough to already fit the remaining band is not shrunk at all.
Only the part of the cloud that rides *above* the head is taken out of the box;
the part that sinks onto the head shares the room the head already uses. In a
**natural-size** frame (a custom battle screen's own sizing) there is no box to
take a band from, so the canvas simply grows upward by that band and the content
keeps its bottom edge — the sprite's feet stay on the ground line the screen
anchors to.

**The cloud art is area-filtered, the sprite is not.** The cloud is a soft,
full-colour painting minified many-fold, so it is resampled with an
alpha-weighted area filter (cached per size) to avoid punching holes in it; the
sprite keeps the nearest-neighbour resample described above.

**Where the state comes from.** Dynamax is not this mod's; it belongs to
`battle_forms`, which this mod only **reads**. A live `dynamax` payload on the
battler (which is what both Dynamax *and* Gigantamax report) turns the cloud on;
only the *live* state paints, so a Pokemon that merely *can* Dynamax wears no
cloud until it does. Everything about the lookup is forgiving: a missing mod, a
missing export, a raised error or a missing field all mean "no cloud" rather
than a broken battle. If the clouded sheet is still baking when the battle needs
it, the **plain** frame is drawn instead, so the sprite never blanks.

**Declared raid bosses.** A *wild* Dynamax/Gigantamax raid boss has no live state
either (see [TERA ART](#tera-art-the-crystal-film)): `special_boss.lua` records
its kind and announces it but never mechanically activates the gimmick. The
screen hands this mod that declaration the same way, as `ctx.bossGimmick =
{ kind = "dynamax" | "gigantamax" }`, and this mod turns the cloud on from it
when the live read found nothing. The declaration is **visual only**. A real live
state still wins, and with DYNAMAX CLOUD off neither paints.

## BATTLE SHADOWS (the contact shadow)

The game's battle screens draw **no shadow** under a battler, so without one a
Pokemon looks like it is floating. This mod bakes a contact shadow **behind**
each battler — never as a second draw pass, so it rides the same frame as the
sprite and can never flicker with the frame clock.

**Where the art comes from.** The DBK solo-sprite pack ships no shadow art: its
own games squash the battler's frame into a soft, semi-transparent blob at draw
time, which the mod cannot reproduce from a single sheet. So the shadows are the
game's own small/medium/large **contact shadows** — `assets/shadow/1.png`,
`2.png` and `3.png`, taken from **La Base de Sky**'s
`Graphics/Pokemon/Shadow` folder (52×16, 72×16 and 100×20, a 30%-alpha black
blob each). The art's own content box is measured once (the files carry a thin
transparent rim) and the shadow is scaled and centred by it.

**Which shadow a species wears** is resolved the way Essentials' own
`shadow_filename` does it, in two steps:

1. a species file, `assets/shadow/<STEM>.png`, wins if it exists (drop your own
   art in per species — this is the escape hatch for a Pokemon whose shadow you
   want to draw by hand);
2. otherwise the **generic** art is picked by the pack's own `ShadowSize`, from
   `data/dbk_metrics.lua` — clamped to the three files — where **`ShadowSize 0`
   means that species casts no shadow at all**. The generic mapping is
   `1.png ← ShadowSize ≤ 1`, `2.png ← 2`, `3.png ← ≥ 3`.

**How big and where.** The shadow's **width** is a share of the sprite's own
display width that tracks `ShadowSize`: `0.55` at the default `1`, `+0.10` per
point above (`2 → 0.65`, `3 → 0.75`, …) and `−0.05` per point below
(`−1 → 0.50`, `−2 → 0.45`, …), clamped to `0.15 … 1.00`. The pack's
**ShadowSprite x** offset (`data/dbk_metrics.lua`, field `sx`) then nudges it
sideways, converted exactly like the sprite's own pack alignment (`x × 2 ÷
renderScale`, scaled with the sheet). Its **second and third** values (ally/enemy
y offsets) are deliberately ignored: a baked shadow is always pinned to the
**ground line** — the bottom of the frame the battle screen anchors to — so a
floating Pokemon's shadow correctly stays on the ground while the Pokemon hovers
above it (see FLOATERS). The composite is an ordinary `sprite OVER shadow` per
pixel, so the Pokemon's opaque pixels occlude the shadow's middle exactly as feet
should, while its transparent margin lets the shadow through.

**Scope.** The shadow is baked only for a **battle** seam (`sheet.shadow`, set by
`getBattleFrames`), so the Pokedex and Summary pictures — which share the very
same baked frame — never grow a shadow. Both the game's own battle screens and a
custom `g9-Battle-Scene` battle get it.

> **Note — double shadow.** `g9-Battle-Scene` already draws its own primitive
> ellipse shadow under a battler when a background image is present. With BATTLE
> SHADOWS on *and* a scene background up, a scene battle therefore shows both
> this shadow and the scene's. Turn BATTLE SHADOWS off if you prefer the scene's
> own primitive one.

`ShadowSize` and `ShadowSprite` are not shipped in the game's data; they are
parsed out of the pack's own PBS files by
[`tools/rebuild_dbk_metrics.mjs`](tools/rebuild_dbk_metrics.mjs) (see
[Regenerating the data](#regenerating-the-data)).

## PARTY ICONS (the bundled icon atlas)

The little **16×16 icon** on each party-list row (gen1 and gen2) does **not** come
from the DBK sheet — the engine's own party icons are a shared two-colour sheet,
and shrinking a battle sheet into a 16×16 slot would throw away the art. Instead
the mod **ships its own animated true-colour icon atlas**, built at development
time from the third-party **"icones animados"** pack:

* the pack is a folder of PNGs, one per icon, each **128×64** = two 64×64
  animation frames side by side (right frame = left frame bobbed a couple of
  pixels);
* at build time each 64×64 frame is **point-sampled 4:1** to a **16×16** cell
  (nearest neighbour, sampled at each 4×4 block's centre, so no colours are
  invented and edges stay hard);
* an icon's two frames become **two consecutive cells**, and the icons are
  packed row-major into **`assets/icons/party_icons.png`** (`cols = 60`,
  cell = 16, two frames);
* **`data/icon_data.lua`** maps `species id → icon name → cell`, plus
  `female` (base name → the pack's female variant) and the egg's `000` cell.

So, unlike every other picture here, an icon is **not baked per mon**: the mod
decodes the one atlas (once, warmed off the draw path from `core.update`) and
draws a **Quad** over it — `frameIndex(2)` picks which of the two cells, so
ANIMATE/SPRITE SPEED drive it like any other sheet. `SPRITE FEMALE` selects the
female cell where the pack has one; an egg uses the pack's own egg icon; a
species the pack has no entry for falls straight through to the game's own icon.

gen1's `PartyMenu.drawIcon` (a **module function**) is wrapped; it marks the
16×16 rect true-colour (`PaletteFX.markTrueColor`) for the SGB/GBC zone pass,
exactly like the battle and summary arms. gen2's `PartyMenu:drawIcon` is wrapped
and draws **raw in GBC mode** (the engine's own `trueColor` rule — through the
party palette shader only in DMG/CLASSIC), while still reproducing the engine's
**held-item marker** by drawing our icon's three 8×8 quadrants and the marker
tile in place of the bottom-left one. A missing or unreadable atlas is never
fatal: the mod logs one warning and every row keeps the vanilla icon.

The icon atlas is regenerated by [`tools/rebuild_icon_atlas.mjs`](tools/rebuild_icon_atlas.mjs)
— see [Regenerating the data](#regenerating-the-data). The source pack is
third-party fan art and is **not** shipped (only the two atlases built from it
are); its credits are in `manifest.json`.

## G9 PARTY SCREEN (the 4x page)

Off by default. When on, the party list is **not** a new screen: it is the
game's own party page, drawn by the game's own code from the game's own tiles
and fonts — just on a **640×576** surface instead of 160×144, with the party
menu's draw running under a `scale(4,4)` transform. Upscaling the *existing*
draw is what keeps the layout honest: the two-line rows, the name / level / HP
figures, the HP-bar tiles, the status and FNT text, the cursor, the CANCEL row
and the box all keep **exactly** the proportions the game gives them, because
they are literally the same draws. Whichever generation boots supplies its own
art — gen 1's tiles on Red/Blue/Yellow, gen 2's on Gold/Silver/Crystal. Nothing
is re-created from the mod's own artwork; the mod adds no layout of its own.

The whole point of the 4× page is the icons. `G9 PARTY SCREEN` draws from
**`assets/icons/party_icons_hd.png`** — the *same* icon pack as PARTY ICONS, but
packed at the pack's **natural 64×64** frames and in the **same order** as the
16×16 atlas, so `data/icon_data.lua`'s one cell index addresses either file
(`hdCell` / `hdCols` in that data say which). The icon still lands in the party
row's own 16×16 design slot, but on the 4× page 16 design units are 64 screen
pixels — **1:1 with the art**, so the frames are shown at full resolution with
no downsampling at all. (With the row off, or the atlas unreadable, the code
falls back to the 16×16 atlas exactly as PARTY ICONS does.) PARTY ICONS still
governs whether the pack's art is used; the species/form/female/egg mapping,
the frame clock and gen 2's held-item marker are all unchanged.

The action list that opens when you pick a Pokemon — STATS / SWITCH / field
moves / ITEM / CANCEL — is the game's own submenu (`self.submenu` /
`self.subItems`, drawn by the native `drawPanel` / `drawSubmenu` this wraps), so
it behaves and reads exactly as the game's own list does, on the same 4× page.
Anything the party menu opens on top (a summary, a message box) is drawn there
too: a classic 160×144 screen pushed over the party menu is **dressed** in place
(the mod sets its `uiSize`/widescreen answers and runs its draw under the same
4× transform, scaling its true-colour zone marks with it) rather than shrunk
back down. Battles, the Pokedex and the summary's own picture logic are
untouched.

Mechanically: gen 1's `PartyMenu` answers `uiSize` = 640×576 and
`isWideBattleLayout`/`wantsFillScale` while the row is on, and the mod wraps
`PartyMenu.draw`, `PartyMenu.sgbPalettes` (its 160×144 true-colour zones scaled
×4) and `src.core.StateStack.push` (so a screen pushed over the menu is dressed
as above); a plain `holdsUIAnchors` field is toggled from the `core.update` poll
so the engine only treats the menu as an anchor-holding screen while the page is
on. gen 2 goes through `Game2`'s widescreen path instead: the mod answers
`PartyMenu.battlePanelScale` (`g9FillScale × 4`, where `g9FillScale` is the
window-filling scale of the 640×576 panel) and wraps `PartyMenu.drawWidescreen`
to letterbox and fit that panel, which is also what makes a pushed classic
screen cover the panel instead of floating small in its middle. The high-res
atlas is ~1.9 MB, so it is decoded **only** while the row is on, and warmed off
the draw path from `core.update`. A missing atlas is never fatal: one warning
and every row uses the 16×16 art instead.

## Diagnostics (if sprites don't appear)

The on-screen diagnostics panel is **disabled in shipped builds** (there is no
option row for it, and no `render.compose` hook is installed) because it was
never meant for players to switch on. What it showed — and what is still
written to the game log (stdout) — is:

* `local assets -- front N, front_shiny N, back N, back_shiny N` at load. *All
  zeros* means the sheets are not where the mod expects — run
  `assets/download_assets.py`.
* `... is not in assets/<type>/ -- vanilla pic in use` at **info** = a species
  resolved to a stem, but that sheet file is not installed.
* `... could not be used (...)` at **warn** = a sheet is present but failed to
  decode (corrupt, partial, or an unsupported PNG), so the mod falls back to the
  vanilla pic. The parenthesised text names the decode route(s) that were tried
  and why they failed.

Sheets are decoded through up to three routes (the mod's own asset path first,
then the raw bytes, then a graphics detour); if every route fails, the first
failing reason is logged so a bad file or an unsupported PNG can be told apart
from a missing one.

If the panel is ever needed again, it is still in `main.lua`, dormant behind
`local DEBUG_PANEL_ENABLED = false` — flip the constant and it paints a white
box with black text at the top-left of the finished UI canvas (the engine's
developer console is Gen 1 only, and Gold implements it not at all).

## The `assets/` folders

```
assets/
  front/        front (enemy) sheets      e.g. ABOMASNOW.png
  front_shiny/  front shiny sheets
  back/         back (player) sheets
  back_shiny/   back shiny sheets
  icons/party_icons.png      the PARTY ICONS atlas (16x16 cells)
  icons/party_icons_hd.png   the G9 PARTY SCREEN atlas (the pack's 64x64 frames)
  tera_crystal.png    the TERA ART crystal pattern
  dynamax_cloud.png   the DYNAMAX CLOUD crown
  shadow/1.png        the BATTLE SHADOWS generic small contact shadow
  shadow/2.png        the BATTLE SHADOWS generic medium contact shadow
  shadow/3.png        the BATTLE SHADOWS generic large contact shadow
```

File name = the pack stem. One horizontal strip per file; never split it.
Each folder has its own README with the details. Anything you don't install
there simply uses the game's vanilla pic. A `shadow/<STEM>.png` file (per
species) overrides the generic `1/2/3.png` for that species.

The mod **ships no DBK sprite artwork** — those sheets are the DBK pack author's
(`la-base-de-sky`), supplied by you. The artwork in the zip is the four
generated assets above (the two party-icon atlases and the two effect assets)
plus the three generic contact-shadow files (`shadow/1.png`, `2.png`, `3.png`,
from La Base de Sky's `Graphics/Pokemon/Shadow`).

## How it hooks the engine

Which generation is booted is read from `src.core.GameVersion.generation()`
(`1` = Red/Blue/Yellow, `2` = Gold/Silver/Crystal) and **only that
generation's battle screen is wrapped**. The generation also picks the asset
**box** a sheet is baked into — a back pic is 64×64 on gen1 and 48×48 on gen2 —
so sheets always land in the box of the game actually running. If the engine
has no `GameVersion` (older than this seam), the mod falls back to probing both
screens, as before.

* **gen1** (`src.battle.BattleState`): wraps `drawPicsLayer` to set each managed
  battler's `sprite` to its current frame `Image` right before the vanilla draw,
  and forces `resolveBattleScale → 1` for managed species (our frames are already
  baked to the box size). `drawBattlerPic` is wrapped only to mark the pic rect
  **true-colour** (`PaletteFX.markTrueColor`), so the SGB/GBC zone post-pass
  re-blits it unshaded.
* **gen2** (`src.ui.gen2.BattleState`): wraps `pic(mon, back)` to return the
  current frame `Image` with `trueColor = true` (Gold draws a trueColor pic
  raw), and `picScale → 1` for managed species.
* **The Pokedex** (`src.ui.DexEntryMenu` on gen1, `src.ui.gen2.PokedexMenu` on
  gen2): the dex does **not** draw through either battle screen — it asks
  `pokemon.sprite` / `Sprites.pic` for the front pic's **path** and loads that
  file itself, so the engine's `pokemon.sprite` hook (which can only swap the
  path string) can never hand it a frame baked in memory. The mod therefore
  wraps the dex screens' own pic accessors directly: gen1's `DexEntryMenu:draw`
  stashes `self.sprite`/`self.spriteTrueColor`, swaps in the current frame with
  `spriteTrueColor = true`, and restores vanilla on the way out; gen2's
  `PokedexMenu:picFor(species)` returns `frame, true`. The dex resolves the base
  front sheet from the species id (never the female/shiny variant, since the
  entry shows the default artwork), skips `UNOWN` (gen2's `drawUnownPic` has its
  own per-letter routine), and uses the same 56×56 front box both screens draw
  into. **DEX SPRITES** turns it off.

  On **gen1 this same hook is the national dex's own Pokédex screen**. The
  `national_dex` mod patches `src.ui.DexEntryMenu` in memory (its
  `src/dexpage.lua`) into its own page strip — the entry page, then a **STATS
  page** as page 2, then the evolution line and movelist — and bands it with
  LEFT/RIGHT **form browsing** that writes the chosen form onto `self.formId`.
  Three consequences the hook handles: the sheet **follows the form** the screen
  is showing (`self.formId` when it is not the base species, else `self.species`,
  with a form that has no sheet falling back to the base species'), it is applied
  from **both** the `draw` and the `update` wrapper — `national_dex` draws its
  STATS page from its own wrapper of the class and can return before the class
  draw runs, so the draw wrap alone is skipped on exactly the page it most needs
  — and the hook is retried from the `core.update` poll so a load-order race
  cannot leave the entry showing vanilla art for a whole session.
* **The party Summary screen** (`src.ui.SummaryMenu` on gen1, `src.ui.gen2.SummaryMenu`
  on gen2): the summary draws its own front pic, so it needs its own hook. It
  shows the **FRONT** sheet, or the `*_shiny` FRONT sheet for a shiny mon,
  resolved through the same species/form/gender mapping the battle pics use (no
  Tera film or Dynamax cloud — those are battle states). gen1's `SummaryMenu:draw`
  runs with `self.sprite` hidden and then paints the frame into the engine's own
  spot itself (mirrored, bottom-anchored, with a `PaletteFX.markTrueColor` over
  it) — self-contained, so it never depends on the engine's own pic draw; gen2's
  `SummaryMenu:drawPic` draws the frame raw into the 7×7 block (skipping the GBC
  4-shade remap in GBC mode, the same true-colour rule `BattleState` uses). Both
  honor **SUMMARY SIZE**, which scales that one draw only — the battle, dex and
  scene seams never read it. `UNOWN` and eggs are left vanilla. **SUMMARY SPRITES**
  turns it off.
* **The party summary as a pushed screen** (the `screen.pushed` listener): the
  party menu's STATS action opens the summary as the pushed screen id
  `"SummaryMenu"` (`src/ui/PartyMenu.lua`), and that id **is** the party summary
  — the screen national_dex repaints the stats box of. The builtin class is
  covered by the wrap above, but a mod may REPLACE it with a class of its own
  registered under the same id, or otherwise paint the mon's own front pic from
  a pushed `Screen` that is not a `SummaryMenu` subclass (the g9 battle engine's
  wide 256×144 modern STATS screen is one). None of the wrappers above runs for
  those. Rather than disabling or reproducing such a screen, the mod listens for
  `screen.pushed` and decorates **that instance's** `draw`: the screen draws in
  full and only the one picture it would have painted is swapped for the current
  frame. A screen pushed under the party summary's id uses the native 160×144
  picture slot on **both** its pages (mirrored from x=8, feet on the y=56 rule —
  where `src.ui.SummaryMenu` and national_dex's stats-box repaint both live), so
  it is recognised by the id alone even when its pic loads lazily (nil at push);
  any other pushed pic screen is treated as a wide modern screen (its own left
  box, mirrored from x=80, picture page only). `SUMMARY SPRITES` and `SUMMARY
  SIZE` apply here exactly as on the native screen; the native `SummaryMenu`
  (both generations) and the Pokedex entry page are explicitly skipped so
  nothing is ever drawn twice. This is Gen 1 only, where a pushed replacement
  lives. It covers screen-**replacing** *summary* mods only: the national dex's
  own Pokédex STATS page is reached by the Pokedex hook above, never by this
  listener (that screen carries a different flag and `isSummaryScreen`
  explicitly skips it).
* **The party list icons** (`src.ui.PartyMenu` on gen1, `src.ui.gen2.PartyMenu`
  on gen2): each party-list row draws one small **16×16** icon, and — like the
  Pokedex and the Summary — the party menu does not draw through a battle
  screen, so it gets its own hook. The engine's icon sheet is two-colour, so the
  mod ships its own **animated true-colour icon atlas** instead: the
  `icones animados` pack (one 128×64 two-frame PNG per icon) is point-sampled
  4:1 into 16×16 cells at build time (one atlas, two consecutive cells per
  icon), and `data/icon_data.lua` maps a species id — and its female variant —
  to a cell. So an icon is just a **Quad over one decoded atlas** — no per-mon
  bake. gen1's `PartyMenu.drawIcon` (a module function) is wrapped and marks its
  16×16 rect true-colour for the SGB/GBC zone pass; gen2's
  `PartyMenu:drawIcon` is wrapped and draws raw in GBC mode (the engine's own
  `trueColor` rule) while still reproducing the game's held-item marker in the
  icon's bottom-left tile. An egg uses the pack's own egg icon; any species the
  pack has no entry for falls straight through to the game's own icon.
  **PARTY ICONS** turns it off.
* **The g9 party screen** (`src.ui.PartyMenu` on gen1, `src.ui.gen2.PartyMenu`
  on gen2, **G9 PARTY SCREEN** row): instead of a new screen, the mod asks for a
  **640×576** surface (4× the Game Boy screen) and runs the party menu's own
  draw under `scale(4,4)`, so the page is the game's own layout in the game's
  own art, merely at 4× — with the high-resolution 64×64 icon atlas 1:1 in the
  row's 16×16 design slot. gen1 answers `PartyMenu.uiSize` /
  `isWideBattleLayout` / `wantsFillScale`, wraps `PartyMenu.draw` and
  `PartyMenu.sgbPalettes` (its 160×144 true-colour zones scaled ×4), and wraps
  `StateStack.push` so a classic screen pushed over the menu is **dressed** in
  place (given the 640×576 answers and the same 4× draw, its true-colour marks
  scaled with it) rather than shrunk; a `holdsUIAnchors` field is toggled from
  the `core.update` poll. gen2 answers `PartyMenu.battlePanelScale`
  (`g9FillScale × 4`) and wraps `PartyMenu.drawWidescreen` to letterbox and fit
  the panel — which is also what centres a pushed classic screen on it. The
  native `drawPanel`/`drawSubmenu` supply the STATS / SWITCH / field-moves /
  ITEM / CANCEL list unchanged. See
  [G9 PARTY SCREEN](#g9-party-screen-the-4x-page).
* **Custom battle scenes** (the `battle.mon_pic` seam): wraps `battle.mon_pic`
  to return the current frame `Image` for managed species. The native screens
  above only cover the vanilla renderers — a replacement scene such as
  `g9-Battle-Scene` draws its own pics, resolving each one through the
  `pokemon.sprite` hook and then `battle.mon_pic`. Without this wrap the mod is
  invisible in every scene battle. It passes `(img, ctx)` through untouched for
  unmanaged species, so it composes with other pic mods. A scene may put
  `box = <pixels>` in `ctx` to name the square it will draw the pic into, or
  `box = { w, h }` to name a non-square slot rect; the
  mod then caches a second set of frames baked to exactly that size, so the
  scene's own draw is a 1:1 blit instead of a fractional resample — which is
  what stops a scene on a different canvas from eating the art a second time.
  (`g9-Battle-Scene` passes each sprite's own slot rect.) The same `ctx` may
  also carry `scale`, the field's own size MULTIPLIER applied to every sheet
  (`g9-Battle-Scene` sends the pack's NATURAL 1:1 size for every sprite, and
  1 x 1.6 = x1.6 for its bossFight boss — the "+0.6", bosses only — so a wild
  Pokemon and the same species on your team read identically and each species
  keeps its true relative size); `natural = true` is the mode it now sends
  instead of a slot box, so a sheet is baked at exactly `scale` x its own
  trimmed pixels (no folding into a shared box, which used to make every
  species the same height and width) and only `maxH` can fold it; an older
  `divisor` (one whole-number field scale, applied as 1/divisor) is still
  honoured for g2-Battle-Scene forks. `zoom` is the
  integer the scene will scale the baked box by on its way to the screen, and
  `fill` asks this slot's sheet to GROW to fill its box (a nearest-neighbour
  resample straight to the box, for a screen with no explicit `scale`).
  Finally `maxH` names the pixels from that slot's ground line up to the
  top of the field: a sheet that would rise past it is folded back
  to fit, so nothing is ever clipped at the top of the scene. A scene that sends
  none of these still works, just with the mod's native-box frames.
* **While a sheet is still baking** (its file exists in `assets/`, but it has not
  been decoded/baked yet — the sheet's `"local"`/`"building"` window) the mod
  reports "pending" rather than "no sheet", and each seam suppresses the vanilla
  pic for that window: gen1 blanks `battler.sprite` (the engine skips a nil
  sprite), gen2 returns a nil pic (the engine's `drawPic` early-returns), and the
  `battle.mon_pic` seam returns **`false`**. A scene that knows the token — such
  as `g9-Battle-Scene`, which starts the bake during the pokeball's flight — draws
  NOTHING for that frame instead of the vanilla pic, so a trainer's send-out never
  flashes native art before the pack's frames are ready. A species with no sheet
  at all (or one that fails to decode) still reports "not pending" and falls
  through to the vanilla pic exactly as before, so the token is never a permanent
  blackout. A scene that predates the token reads `false` as "no swap" and draws
  the vanilla pic, i.e. the old behaviour.
* Frame building happens in a `core.update` hook — **never** inside a draw call.
  Resolved sheets are kept in a bounded LRU (64) whose frame `Image`s are dropped
  oldest-first while the raw bytes stay.
* The on-screen **diagnostics panel** (a `render.compose` wrap) is compiled out
  in shipped builds — see [Diagnostics](#diagnostics-if-sprites-dont-appear).

Pic boxes: gen1 front **56×56**, gen1 back **64×64** (pokered's 32×32 pic at 2×),
gen2 front **56×56**, gen2 back **48×48**. Every sheet is baked into that box at
the largest scale it allows and offset by the pack's metrics (see
[Sizes and alignment](#sizes-and-alignment)), so the art keeps as much of its
own resolution as the box can hold and feet placement matches the pack.

## Permissions / dependencies

```json
"permissions": ["engine_internals"]
```

* `engine_internals` — it requires the engine's BattleState modules and PaletteFX.
  No `network` permission: the mod reads only its own `assets/` folder.

`dependencies`: `national_dex` (the species-id source this mod's form map is
built against). That is the ONLY hard dependency.

`optional_dependencies`: `g9-battle-engine` (the battle engine and its custom
modern STATS summary screen) and `g9-Battle-Scene` (the custom battle scene that
draws through the `battle.mon_pic` seam). Neither is required: with them absent
the mod still animates the native battle screens, the Pokedex and the native
SummaryMenu, and the custom-screen hooks simply stay dormant. `battle_forms`
(the live Tera and Dynamax state for [TERA ART](#tera-art-the-crystal-film) and
[DYNAMAX CLOUD](#dynamax-cloud-the-crown)) is likewise optional and feature-
detected — a live Tera/Dynamax is read from it when present, and a wild raid
boss's declared gimmick (handed over by `g9-Battle-Scene` on the `battle.mon_pic`
seam) is painted without it; with neither a live state nor a declaration, TERA
ART / DYNAMAX CLOUD draw nothing.

## Install

Download the zip from the studio's **Mod exports** row
(`⬇ g9-battle-sprites .zip`) and unzip it into the game's `mods/` folder so the
tree is `mods/g9-battle-sprites/{manifest.json,main.lua,...}`.

### Getting the sheets (the helper script)

The mod ships no artwork and never touches the network, so **you fill `assets/`
yourself**. The helper that ships in the mod fetches the DBK pack from GitLab
once, on your machine, and writes it into the exact layout the mod reads:

```
cd mods/g9-battle-sprites/assets
python3 download_assets.py            # everything missing
python3 download_assets.py --force    # re-fetch everything
python3 download_assets.py --only front,back
python3 download_assets.py --dry-run  # show the plan, fetch nothing
```

It reads `../data/dbk_data.lua` for the stem list and writes each sheet into
`front/`, `front_shiny/`, `back/`, `back_shiny/` next to itself. Standard
library only, resumable, safe to re-run. Run it whenever you want to add sheets
— the running game itself downloads nothing.

## Files

| File | Role |
|---|---|
| `manifest.json` | Mod metadata; permissions, games, options schema |
| `main.lua` | The mod: stem resolution, assets/ loading, frame baking, gen1/gen2 battle hooks, gen1/gen2 Pokedex hooks, gen1/gen2 Summary hooks, gen1/gen2 party-icon hooks, gen1/gen2 g9 party-screen hooks |
| `options.lua` | Mod Manager rows (mirrored in `main.lua`) |
| `data/dbk_data.lua` | Generated: species→stem, stem existence, female stems |
| `data/dbk_metrics.lua` | Generated: per-stem FrontSprite/BackSprite alignment offsets from the pack's SpeciesMetrics files (used by GROUND ANCHOR = PACK), plus `sz` (ShadowSize) and `sx` (ShadowSprite x) used by BATTLE SHADOWS |
| `data/dbk_float.lua` | Generated: the set of stems the pack draws airborne (used by FLOATERS) |
| `data/icon_data.lua` | Generated: species→icon name→atlas cell, female variants, egg cell |
| `mod.card` | Human-readable summary shown by launchers |
| `assets/*/README.md` | Notes for the asset folders |
| `assets/icons/party_icons.png` | The PARTY ICONS 16×16-cell atlas (bundled) |
| `assets/icons/party_icons_hd.png` | The G9 PARTY SCREEN atlas — the same icons at the pack's 64×64 frames (bundled) |
| `assets/icons/README.md` | Notes for the icon atlases |
| `assets/tera_crystal.png` | The TERA ART crystal pattern |
| `assets/dynamax_cloud.png` | The DYNAMAX CLOUD crown artwork |
| `assets/shadow/1.png` | BATTLE SHADOWS generic small contact shadow |
| `assets/shadow/2.png` | BATTLE SHADOWS generic medium contact shadow |
| `assets/shadow/3.png` | BATTLE SHADOWS generic large contact shadow |
| `assets/download_assets.py` | Helper (run by you, not the game) that fills `assets/` from the DBK mirror |
| `files.json` | Build manifest for the studio's export button (not shipped) |
| `README.md` | This document |

## Regenerating the data

`data/dbk_data.lua` is generated by joining the national dex species table to
the DBK pack's file listing. The generator script is `tools/rebuild_dbk_data.mjs`
(kept with the studio source, **not** shipped in the mod zip — see `files.json`).
It fetches all four pack folders live from GitLab and combines them with
`tools/mapping.json` (the reviewed national-dex join — species id → stem, which
carries the form decisions). When the pack gains sheets, run:

```
node tools/rebuild_dbk_data.mjs          # rewrites ../data/dbk_data.lua
```

The output is byte-stable for a given pack + mapping. A species whose stem is
not actually present in the pack is dropped, so the Lua never points at a
missing file.

`data/dbk_metrics.lua` is generated from the pack's own five SpeciesMetrics PBS
files (`pokemon_metrics.txt`, `pokemon_metrics_forms.txt`,
`pokemon_metrics_gmax.txt`, `pokemon_metrics_Gen_9_Pack.txt`,
`pokemon_metrics_female.txt`). Point the script at a folder holding those files
(or pass them explicitly):

```
node tools/rebuild_dbk_metrics.mjs /path/to/metrics-dir   # rewrites ../data/dbk_metrics.lua
```

It keys each section by the same PNG stem the sheet is stored under
(`[SPECIES,form,female]` → `SPECIES_form_female`, dropping empty parts) and drops
any stem the pack has no PNG for. Besides the `fx`/`fy`/`bx`/`by` alignment
offsets it also emits `sz` (the section's `ShadowSize`, omitted when it is the
default 1) and `sx` (the x of `ShadowSprite`), which BATTLE SHADOWS reads.

`data/dbk_float.lua` (the FLOATERS species set) is generated from the PokeAPI
`pokemon` / `pokemon_types` / `types` / `pokemon_abilities` / `abilities` CSV
tables plus `data/dbk_data.lua`'s stem list, by `tools/rebuild_dbk_float.mjs`.
A sheet is flagged airborne if it is a Flying type (minus the handful the pack
draws standing), has the Levitate ability, or is in a small curated set of
floating/airborne species the type/ability data misses (Magnemite/Porygon/Beldum
lines, Beedrill, Deoxys, Castform, Minior, the Vanillite/Klink/Solosis lines,
Comfey, Orbeetle, the airborne Paradox mons). Fetch the CSVs first, then point
the script at the folder (or pass the files explicitly):

```
node tools/rebuild_dbk_float.mjs /path/to/pokeapi-csv-dir   # rewrites ../data/dbk_float.lua
```

It keys off the same stems as `dbk_data.lua` and drops any stem the pack has no
sheet for. The output is byte-stable for a given set of CSVs plus
`dbk_data.lua`.

`assets/icons/party_icons.png`, `assets/icons/party_icons_hd.png` and
`data/icon_data.lua` (the PARTY ICONS and G9 PARTY SCREEN atlases) are generated
from the bundled `tools/icon_pack.zip` icon pack by
`tools/rebuild_icon_atlas.mjs`. It is **browser/worker** code (no Node): run it
from the editor's `execute_js` — the exact snippet is in
[`tools/README.md`](tools/README.md). The output is byte-stable for a given pack
plus `dbk_data.lua`, so rerunning it is a no-op. The tool emits **both** atlases
(the 4:1-downsampled 16×16 one, and the natural 64×64 one) in the same pass, in
the same cell order, so one `icon_data.lua` addresses either.
