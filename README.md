# 1025Dex 1.2.44

- Rename Random encounters (all forms) to RANDOMIZER, keeping its saved option key.
- Move 1025DEX ASSETS into the 1025DEX settings submenu, before RESET DEFAULTS.
- Add KIM to both ENEMY SPRITES and PLAYER SPRITES when active KIM1025 1.7.37 or newer is installed. Menu pictures follow the player selection.
- Preserve existing sprite-choice IDs and saves. Missing KIM artwork retains matching existing artwork; removing/disabling KIM falls back to EE without erasing the saved selection.
- Decode KIM's rectangular, multirow HD atlases through its companion API, preserving front/back, normal/shiny, supported forms, frame order and original animation timing.

Validation: LuaJIT/Lua 5.3 menu, asset-manager, independent sprite selection, migration, static/EE/BW rendering and frame-clock checks; 121 real PNG/GPU KIM atlas/baker checks; existing eleven-game registry and startup regressions. Combined native GB settings checks passed. No live gameplay session was restarted.

Install KIM1025 1.7.37 alongside this release to enable KIM. Restart the game after installing.

# 1025Dex 1.2.43

Built from GitHub's latest 1.2.42 release. Centre visible Pokemon artwork in cached Gen 3 field/script pictures, including FireRed and LeafGreen starter confirmation boxes. Apply this to both ready and still-baking animation frames; retain cached Image identity and playback metadata. Battle pictures retain their ground-contact alignment.

Validation: real GPU tests of the actual cached picture provider, visible bounds, animation metadata and battle baselines; all eleven game/registry fixtures; LuaJIT compilation. Restart the game after installing.

# 1025Dex 1.2.42 - Simplified sprite controls


Updates now use a small core ZIP. Download all sprite styles, icons, and 1025

cries once from the built-in prompt or **OPTIONS > 1025DEX ASSETS**. The pack is

stored in persistent cache and reused across future code updates and saves.

Restart after installation. [Asset downloads, migration and offline setup](ASSET-DOWNLOADS.md).





Gen 3 Psychic types now reach the battle engine correctly, including Gardevoir,

Deoxys and added species/forms. Ruby/Sapphire options menus now supply missing

cache labels and values. Restart the game after replacing the mod; ability

changes are not required.



In 1025Dex's options, **ENEMY SPRITES** and **PLAYER SPRITES** independently

select ANIMATED, GEN9 STATIC, BW ROM, EE ANIMATED or EE STATIC.
Pokedex and summary artwork follow PLAYER SPRITES.
BW ROM still requires the locally imported companion pack.



**PLAYER VIEW** selects BACK, FRONT or MIRRORED FRONT (a horizontal flip).

Updates preserve existing front/mirror preferences in PLAYER VIEW. These options cover
native battles in all 11 games and custom scenes using the battle sprite hook.

Shiny palettes, gender artwork and per-source animation timing remain supported.



Validation includes both Lua 5.3 and LuaJIT, all style combinations, saved

option compatibility, native Gen 3 scope restoration and pixel-by-pixel mirrored

bakes for Gen 1-3. Restart the game after installing the update.



## 1.2.33 - National Dex Gen 3 save compatibility



Saves from [National Dex Gen 3 0.5.1](https://github.com/poooooby/national_dex_gen3)

retain all 639 added species (#387-1025) in the same native slots (Dex + 64).

That release adds base species only; it does not register Mega, Gmax or regional

forms. The prior GB National Dex form compatibility checks still apply.



The save audit found its 19 evolution-item slots (900-918) were unreadable in

1025Dex. This release recognizes them, including old Sweet/Tart Apples at

910/911. Existing 1025Dex apples remain 1002/1001, and both old apple IDs work

with the native Applin evolution flow. Bag/held numeric IDs are not rewritten.

The added items also have GB held-item definitions so Hoennto can retain their

identity; field use for those new items remains disabled in GB. Existing

Hoennto capacity and unsupported-move rules still apply.



Tests create scratch saves with the supplied source mod alone, reopen them

with 1025Dex, and check species, nicknames, OT IDs, moves, PP, personality,

IVs/EVs, native PC storage, item IDs, apple evolution, Hoennto conversion and

projection, and WildFollowers EE/G9RP sprite selection. User saves are never

used by these tests. GPU drawing is stubbed; this is a save/registry audit,

not a live graphics test. National Dex Gen 3's own optional 1025Dex detection

steps aside when both mods are present. Restart before opening an existing

save or the save editor after installing the update.



The Gen1Recomp save editor now offers all 1,025 base Pokémon and all 364

registered forms in Gen 3, including Megas, Gmax and regional variants. It

uses the same native species slots as the game. Expanded boxes remain visible

and survive editor hydration and export, including box names, wallpapers and

sparse Pokémon slots. Gen 2 registrations now resolve the native experience

curves under the National Dex API's curve names.



Saves made with **National Dex 0.35.5 + Modern Spawns 0.9.0** on Red, Blue,

Yellow, Gold, Silver and Crystal keep their Pokémon identities when switching

to 1025Dex. All base/form keys and synthetic form Dex IDs match that National

Dex release; no species renumbering or save conversion is required. Restart

with 1025Dex enabled before opening the save editor. Use 1025Dex in place of

National Dex (the existing conflict rule remains); this compatibility concerns

existing saves, not running two species registries together. Modern Spawns'

required National Dex dependency still applies if you want to run it.



Validation: real sandboxed editor boot on all eleven games using read-only local

ROM caches; 1,389 catalog identities / 364 forms checked against the supplied

National Dex; reference-mod scratch saves imported on all six GB games;

editor creation, edits, serialization, hydration and native Gen 3 PC movement;

final expanded boxes, sparse slots, names, wallpapers and legacy mirrors.

User saves are not modified by these tests. See tools/test_save_editor.py.



## Retained from 1.2.31 - Full encounter randomizer



Enable **Random encounters (all forms)** in Mods â†’ 1025Dex to give each of the

1,025 base PokÃ©mon and 364 registered alternate forms equal encounter odds.

Includes Megas, Gmax, regional forms and every other registered form, anywhere

ordinary wild encounters can occur, without generation, habitat or League gates.

The native encounter level, encounter rate and unsuccessful rolls are retained.

Visible wild providers and encounter-list APIs use the same pool. The toggle

defaults OFF; turn it off to restore the normal WILD GENS and habitat rules.

Scripted encounters, trainer battles and explicitly selected battle species

retain their existing behavior.



New default sprite style: **EE ANIMATED**. Default playback alternates

**2 loops / 2-second pause** with **3 loops / 1-second pause**.

All settings remain adjustable. Existing saved choices are preserved.



## Retained from 1.2.29 - Alternating EE playback



**EE ALT LOOPS** and **EE ALT PAUSE** set the second playback pattern. EE

ANIMATED alternates the primary loop/pause settings with the alternate ones.

For example: 4 loops, rest 2 seconds; 2 loops, rest 5 seconds; repeat.

Alternate loops allow 1â€“5 and alternate pauses allow 1â€“7 seconds. **SAME**

(the default) follows the corresponding primary setting, so either setting

can alternate independently. PokÃ©dex selection restarts the primary pattern.



**Emerald Expansion sprite credit:**

Based off RHH's pokeemerald-expansion 1.17.1 https://github.com/rh-hideout/pokeemerald-expansion/

Thank you to RHH (Rom Hacking Hideout) and the project's contributing sprite

artists. See [CREDITS.md](CREDITS.md) for all artwork and mod credits.



Use **EE PAUSE** to choose **1â€“7 seconds** of rest after playback, and

**EE LOOPS** to choose **1â€“5 complete loops** before that rest. Defaults are

2 seconds and 4 loops. SPRITE SPEED controls how quickly each loop plays.

Selecting or reopening a PokÃ©dex entry restarts EE playback immediately,

including cached entries and alternate forms. EE STATIC remains a still pose.



## Retained from 1.2.26 - Cached EE animation fix



Fixes EE sprites continuously looping when Emerald or another Gen 3 screen

caches its image before the sprite finishes loading. Cached images now receive

the EE playback metadata as frames are baked, including after option changes.

EE ANIMATED plays once every seven seconds and rests on its first pose.



## Retained from 1.2.25 - EE animation interval



**EE ANIMATED** plays its supplied frames once every **seven seconds**, then

holds the first pose until the next animation. The animation speed setting

controls playback speed. This applies to battle pictures, PokÃ©dex, summaries

and cached Gen 3 previews. Single-frame artwork stays still.



## Retained from 1.2.24 - Emerald Expansion sprite options



In **PLAYER SPRITES** or **ENEMY SPRITES**, select **EE ANIMATED** for the supplied Emerald Expansion
frames or **EE STATIC** for their first pose. Both use the project's

Emerald Expansion Sprites artwork for battles, PokÃ©dex and summary pictures,

including normal/shiny palettes, gender variants and available forms.

Sprites with one supplied frame stay still in either option. Missing EE art

keeps the matching existing artwork; female Mega Meowstic is absent from the

supplied folder. Party icons keep their separate setting.



The import preserves source pixel indices, applies the supplied palettes,

makes palette index zero transparent and rearranges vertical frame strips

into horizontal runtime sheets. EE art uses its native 64-pixel canvas and

the existing sprite size controls. ANIMATED remains the default, and existing

ANIMATED, GEN9 STATIC and BW ROM selections retain their values.



Replace the installed 1025Dex folder and restart. No save migration required.



## Retained from 1.2.23 - Rare post-League forms



After entering the Hall of Fame, all 364 shipped Mega and alternate forms

can appear as rare wild encounters at levels **55â€“70**. Forms share a

**2% combined chance**, not 2% per form. WILD GENS filters each form by its

base PokÃ©mon's generation. Aquatic forms use water and fishing encounters.



| Games | Encounter areas |

| --- | --- |

| Red, Blue, Yellow | Cerulean Cave and Victory Road |

| Gold, Silver, Crystal | Mt. Silver, Route 28, Dragon's Den B1F and Victory Road |

| FireRed, LeafGreen | Cerulean Cave, Victory Road and Sevault Canyon |

| Ruby, Sapphire, Emerald | Victory Road, Sky Pillar and Meteor Falls B1F's second room; also Artisan Cave in Emerald |



Forms retain their exact identity in battles and visible wild encounters.

The League gate is checked when encounters are generated. Replace the

installed 1025Dex folder and restart; existing saves need no migration.



## Retained from 1.2.22 - Evolution apples



Buy **Tart Apple** and **Sweet Apple** for **2,100 each** and use them from

the Bag on **Applin**: Tart Apple produces **Flapple**, Sweet Apple produces

**Appletun**. These apples do not evolve Dipplin.



| Games | Seller |

| --- | --- |

| Red, Blue, Yellow, FireRed, LeafGreen | Celadon Department Store, 4F |

| Gold, Silver, Crystal | Celadon Department Store, 4F; also Goldenrod Department Store, 4F for access before Kanto |

| Ruby, Sapphire, Emerald | Pretty Petal Flower Shop on Route 104: speak to the owner on the left |



The berry and Wailmer Pail NPCs keep their original rewards. Purchases use

the normal shops and Bag. Apples work before FireRed/LeafGreen's National

Dex unlock and remain available after a ROM reload. Replace the installed

1025Dex folder and restart; existing saves need no migration.



## Retained from 1.2.21 - Gen 3 alternate forms



Registers all 364 shipped Mega and alternate forms in FireRed, LeafGreen,

Ruby, Sapphire and Emerald. **CodeBreaker 0.7.2** adds them to its wild PokÃ©mon

picker after the 1,025 base species. Install both updated folders and restart.

Form slots preserve the base National Dex/cry identity and do not replace

base species. Forms use their supplied stats, types and compatible moves;

they skip unavailable Emerald ROM animations like other added species.



## Retained from 1.2.20 - Emerald evolution freeze fix



Fixes Applin and other added PokÃ©mon freezing at the start of evolution in

Emerald. Added species skip unavailable ROM animation scripts while retaining

their cries, selected sprite artwork, and normal evolution/cancellation flow.

All 639 added species passed completion and B-cancel regression checks.

Native PokÃ©mon retain their ROM animations. See [EVOLUTION-FIX.md](EVOLUTION-FIX.md).

Replace the installed folder and restart; no save migration is required.



## Retained from 1.2.19 - selectable battle sprite artwork



In 1025Dex's options, set **SPRITE STYLE â†’ GEN9 STATIC** to use the supplied

Generation 9 Resource Pack v3.3.8 artwork. **ANIMATED** remains the default.

Both styles work across all eleven supported games and Hoennto. Battles,

PokÃ©dex and summary pictures use the selected style; party icons retain their

separate setting. Existing saves and canonical species numbering are unchanged.



The pack contains 192Ã—192 front canvases and 288Ã—288 back canvases, plus four

96Ã—96 placeholders. These are different pixel densities of a 96Ã—96 design

canvas. BIG is the default sprite size; NORMAL and SMALL use half and a third

of that scale, fitting oversized artwork to the picture box. The retired

MAX DETAIL setting now uses BIG. All sizes and custom battle-screen scales

account for the front/back density difference.

Transparent padding does not determine the ground line. Grounded sprites stand

on it, and airborne species keep the FLOATERS setting's small hover.



Animated sheets use one scale and union bounding box across all their frames,

preserving the artist's motion without resizing or re-centring each frame.

Both styles now cancel Gen 3's ROM-specific art-padding offsets; the old

height-dependent extra lift has been removed. Native pictures, ghosts,

substitutes and battle animation offsets retain their own placement.



Normal/shiny and available female variants use the same routing. The supplied

static pack lacks some forms, including Gigantamax Blastoise: those use the

matching animated sheet's **first frame** while GEN9 STATIC is selected. This

keeps the correct form without animating or substituting an unrelated picture.

Style changes rebuild cached menu pictures too; no sprite download is needed.



Replace the installed 1025Dex folder and restart the game for this update.

See [SPRITE-VALIDATION.md](SPRITE-VALIDATION.md) for checks and limitations, and

[CREDITS.md](CREDITS.md) for the pack's artist attribution.



## Retained from 1.2.15 - all eleven games



1.2.15 adds the shared National-number API and the Game Boy visible-encounter

provider used by the new WildFollowers 3 runtime. See [SPECIES-NUMBERS.md](SPECIES-NUMBERS.md).

Existing Pokemon save IDs and registered species remain unchanged.



Requires Gen1Recomp 0.3.54 or later. Supports Red, Blue, Yellow, Gold,

Silver, Crystal, Ruby, Sapphire, FireRed, LeafGreen and Emerald. Install the

single 1025Dex folder and restart the session. Compatible with Hoennto 0.2.0.



All games register the complete 1,025-species roster with generation-specific

stats, animated sprites and exact National-number cries. Yellow retains its

native voiced Pikachu clips. PC storage holds at least 1,025 Pokemon, including

when Hoennto projects the shared collection into another cartridge. Unsupported

moves, items and eggs still follow Hoennto's reserve rules.



R/B/Y and G/S/C keep the cartridge encounter roll first: encounter rates,

time-of-day, swarm substitutions, rod restrictions and failed bites survive.

Half of successful ordinary encounters retain the exact native species/level;

the other half may use generation-selected habitat additions. Empty added pools

fall back to the successful native roll. Contest, scripted, roaming, Headbutt

and Rock Smash encounters retain their native behavior. WILD GENS selects the

added species; native Game Boy residents remain available with every setting.

Added legendary and Ultra Beast homes unlock after that cartridge's League.

Higher post-League area ceilings also unlock then; story additions respect native

area level ceilings. Ice species use icy areas.



Ruby and Sapphire read their own imported live encounter tables, rather than

borrowing Emerald's canon residents. Grass, Surf, fishing and Rock Smash use

those native species/level ranges. RSE's National Pokedex now includes 1,025

entries while retaining the Hoenn list. Existing FR/LG and Emerald rules remain.

Shellder now has a Hoenn campaign home, closing the LeafGreen + Emerald gap.



The release includes updated FR/LG, Emerald and Hoennto guides, a Ruby table

reference, and an all-games companion. Exact Game Boy/Sapphire native tables

come from the player's imported cartridge; the companion describes that live

behavior rather than presenting unverified static cartridge tables.



# New in 1.2.13: merged missing-route fixes



Retains the canon/habitat update below and merges the alternate 1.2.12 build's

nearby-route fallback for Routes 4, 9, 10, 11 and 22. The current runtime already

populates these routes; older direct policy callers now receive suitable pools

too. Generation, habitat and early-route rules still apply. The v1.2.12 encounter

guides remain applicable. Replace 1025Dex and restart the session.



# Retained from 1.2.12: canon encounters and habitat audit



Vanilla wild species remain available in their original areas and encounter

channels when their generation is selected. This includes Route 3 Jigglypuff,

Viridian Forest Pikachu, Emerald Route 119 Feebas, and FR/LG version differences.

Native encounters are protected from the campaign atlas's two-home limit.

Added residents use habitat-compatible pools, with separate freshwater and sea

additions. Bombirdier is no longer classified as a fishing encounter.



Native level ranges are shared by battles, WildFollowers and DexNav. Replace

1025Dex and restart the session. No new save format or companion update is

required. See ENCOUNTER-AUDIT.md and the rebuilt EncounterAtlas.csv. Validation

is headless; an interactive playthrough has not been run.



# Retained from 1.2.10: comparable wild attacks and three-move minimum



Every newly generated ordinary wild PokÃ©mon from **Gen4â€“9** now has **three or

four distinct, usable Gen3 moves**, including at low levels. Unsupported newer

attacks receive comparable Gen3 replacements at their original learn levels.

Only missing slots receive weak, type-oriented starter moves; these never

borrow a move scheduled for a later level. Blipbug gets **Silver Wind, Leech

Life and String Shot**, rather than the exhausted-moves Struggle fallback.

Native Gen1â€“3 wilds keep their original game-specific schedules, so early wild

Charmander still cannot receive Flamethrower before its proper level.



## Retained fixes and compatibility



All **639 added base species** now retain their proper Gen3 TM/HM permissions

through both registration passes and ROM reloads. Multi-word move IDs are

normalized correctly. Staravia can learn **HM02 Fly** and **TM40 Aerial Ace**.

The data covers all 58 original Gen3 machines in FR/LG and Emerald.



Ordinary wild battles rebuild moves after their final species/level is chosen.

Native species use their original FR/LG or Emerald progression. Added species

use a documented vanilla Gen4â€“9 level-up reference with the compatibility

replacements and starter rule above. Random bonus TMs are disabled. Existing

party moves, player-taught TMs and player level-up compatibility are preserved.

See **GEN3-MOVE-RULES.txt** for the exact wild-move rules and source data.



Update **1025DexNav to 0.1.13** as well if installed: its previews use the same

wild move data and its bonus-TM feature is disabled with 1025Dex. Current

WildFollowers 2.22.9 needs no update. Encounter-guide 1.2.8 remains accurate;

this release does not change encounter species, rarity or levels.



STATS and MOVES were legacy Gen1/2 controls, not working Game3 switches.

They are now hidden in FR/LG/Emerald. Gen3 already uses separate Sp. Atk/Sp. Def;

the existing player level-up compatibility rules continue independently of

those settings, and valid native TMs/HMs never require MOVES=ALL.



Validation uses the production registry writer and teaching checks, late

registration and reload reproduction, all 639 Ã— 58 permission combinations,

all 1,025 species at levels 1â€“100 in all three games, real wild-bridge code,

the minimum of three distinct usable moves for all added species, unchanged

native schedules/machine data, exact replacement learn levels and weak padding,

DexNav previews and standalone fallback, and existing capture checks.

These are automated checks; an interactive game playthrough was not run.



## 1.2.8 â€” First-catch return and cave balance



First catches now return from the PokÃ©dex to the normal battle UI before the

nickname question or PC transfer message. Emerald passes the caught sprite,

personality, OT and shiny state back to newer engine builds. NoNickname works

in either load order; older engine builds keep their existing flow.



Mt. Moon uses the original floor level bands: **7â€“10 on 1F, 5â€“10 on B1F,

8â€“12 on B2F**. Diglett's Cave contains **95% Diglett at levels 15â€“22** and

**5% Dugtrio at levels 29 or 31**, under every WILD GENS selection. Other cave

residents displaced by this rebalance have later homes in Rock Tunnel.

WildFollowers and 1025DexNav read these same updated pools and levels.



The separate v1.2.8 HTML encounter guides are rebuilt from the live policy for

FR/LG and Emerald, including current Ultra Beast rules. Existing evolution,

animated shiny, sprite placement and post-League encounter fixes are retained.

Replace 1025Dex and restart; the current WildFollowers 2.22.9 needs no update.



Validation: production capture-flow regression checks against 0.3.43 and the

current engine source, both games' cave pools, follower/DexNav exports,

postgame and Ultra Beast rules, animated sprites, and offline guide filters.

These are headless checks; an interactive playthrough was not run.



## 1.2.7 â€” Ultra Beast rarity



Ultra Beasts require League clear. They never appear in beginner areas. Afterward, suitable level-45+ land areas have a shared **0.1%** Ultra Beast roll; designated end-game hubs have **1%**, at levels **55â€“70**. DexNav and WildFollowers read the same live policy. Evolution and sprite fixes from v1.2.6 are retained. See CHANGELOG-1.2.7.txt for full rules.



## 1.2.6 â€” Evolution repair



Extended species' evolution rows now survive content merges and ROM reloads

in FireRed, LeafGreen and Emerald. Normal levels, level-36 trade alternatives,

held-item branches and native stone evolutions are preserved. Over-levelled

PokÃ©mon can evolve on their next level-up. See EVOLUTION-RULES.txt.



Gender, party-member and Beauty checks now use the native mon/session data.

Unavailable modern move requirements use the existing level-36 compatibility

fallback. Both Cosmoem branches remain available at level 53.



Validation: 4,572 assertions each against upstream 0.3.36 and 0.3.43 evolution

code. Covers FR/LG/Emerald, every installed base-species evolution route,

normal thresholds, registry overwrite/reload reproduction, trade/held-item

rules, Everstone, cancellation and completed evolution/Dex registration.

These are headless engine tests; an interactive playthrough was not run.



## 1.2.5 â€” Shiny rendering regression fix



Keeps the animated provider outside late Gen3Compat sprite wrappers, recognizes

Gen 3 mon shiny data in mon-aware screens, and returns mutable animated Images

so screens that cache a picture keep animating. Normal/shiny and front/back

images remain separate. Preserves the 1.2.3 battle height adjustment.



Regression checks cover the upstream late compatibility wrapper and cached

Image animation, in addition to provider routing and encounter compatibility.

In-game confirmation is still needed on the player's launcher.



## 1.2.4 â€” Animated shinies



Shiny front and back pictures now use the pack's animated shiny sheets in

FR/LG and Emerald. Normal/shiny caches stay separate, native frame requests

keep the animated replacement, and the 1.2.3 height correction is preserved.

All 1,025 base species have multi-frame shiny front/back sheets.



## 1.2.3 â€” Automatic battle sprite height



Tall sprites now move down only when the existing battle lift exceeds their

transparent headroom. The correction uses visible bounds across the whole

animation, separately for front and back art. Small sprites retain their

placement, and the images remain full-size 64Ã—64.



## 1.2.2 â€” Complete special encounter coverage



Mew gains League-gated wild homes in **Cerulean Cave 1F** and

**Seven Island Sevault Canyon** in FireRed and LeafGreen (levels 55â€“70).

All added legendary/mythical pools require defeating the Pokemon League and

respect WILD GENS. Existing native static encounters retain their own rules.

See `POSTGAME-SPAWNS.txt` for every special species and its assigned homes.

The same live pools feed 1025DexNav and WildFollowers.



# 1025Dex 1.2.1



## 1.2.1 â€” Complete special encounter coverage



Added wild homes for all 94 special species in Emerald, including legendary,

mythical and other special Pokemon from every generation. FireRed/LeafGreen

adds all 89 Gen 2-9 special species, giving every post-Gen1 Pokemon a wild home.

Gen1 FR/LG specials retain their native encounters.



New special pools unlock after clearing the Pokemon League, not merely viewing

the National Dex. Levels are 55-70. When ordinary candidates exist, specials

use a shared 1% roll followed by selection within that area's special pool.

WILD GENS applies to these pools. No added specials in early routes, fishing,

Rock Smash or ordinary fallback pools. Kyogre, Phione and Manaphy use water;

aquatic homes are Surf areas in Sevii and underwater routes in Hoenn.



Native scripted/static/roaming battles remain preserved. Ordinary distributions

and all bundled artwork/audio are unchanged. DexNav includes unlocked specials

at the correct levels, and visible pools refresh when League completion changes.

Each dungeon room caches its own special pool instead of sharing a parent's

cache. Requires gen1recomp >=0.3.36 <0.4.0. Replace both mod folders and restart.



Validation: 94 Emerald + 89 FR/LG specials at actual native encounter sources;

2,050 generation/location witnesses; 1,025 Emerald wild species and 1,020 FR/LG

wild species; all 874 post-Gen1 FR/LG species. Loader/sandbox, native Dex,

protected battles, save roundtrip, terrain, follower behavior, guide filters

and exports checked headlessly. A full in-game playthrough remains untested.



Adds the full 1,025-species National Dex to FireRed, LeafGreen and Emerald, animated PokÃ©mon

sprites, generation-selectable wild encounters, Kanto, Sevii and Hoenn encounter pools and

36 PC boxes with space for 1,080 PokÃ©mon.



**Based on national-dex by Sanjin and Tekky.**

Original mod: https://github.com/sanjinpepic/gen1recomp-national-dex



**PokÃ©mon sprite credits: Gen9 Resource Pack and its contributing artists.**

See [CREDITS.md](CREDITS.md) for attribution and included source/license notices.



## 1.2.0 â€” Emerald port



Requires gen1recomp **0.3.36 or newer in 0.3.x**. Install alongside

**WildFollowers 2.15.0** for visible wilds and party followers in Hoenn.



- All 1,025 National species use the correct Emerald internal slots. Native

  Gen 1â€“3 species keep their ROM data; new species receive Gen 3-compatible

  learnsets, evolutions, animated sprites and cries. Moves unavailable in

  Gen 3 use the existing compatibility substitutions.

- The native Emerald PokÃ©dex retains its 202-species Hoenn list and gains a

  1,025-species National list, six sort orders, color/type search, descriptions,

  animated pictures and four-digit seen/owned totals. National mode is enabled

  while the mod is active. Added entry text wraps within the native page.

- 116 native Hoenn encounter-map profiles supply separate land, Surf, fishing

  and Rock Smash pools. WILD GENS has all 17 generation selections. Later

  species receive habitat homes and appropriate evolution-level gates.

  Old Rod and Rock Smash rolls retain their native level ceiling.

- Legendary, mythical and other special species remain outside ordinary

  random pools. Native scripted and static battles are preserved.

- 36 PC boxes hold 1,080 PokÃ©mon. Native save serialization retains additions,

  including the last box and slot; existing storage metadata is preserved.

- Kanto/Sevii distributions and bundled sprite/audio bytes remain unchanged.



Validation used the actual 0.3.36 Loader/sandbox and supplied Emerald USA data:

all 1,025 slot mappings; all 3,417 Hoenn terrain/generation pools; all six native

PokÃ©dex sorts; color search; descriptions; four-digit totals; Gen 3 learnsets;

36-box save roundtrip; and dataset reload. Full in-game playthrough pending.



## Updating



Replace the previous 1025Dex folder and restart the game. If using visible wild

PokÃ©mon, use WildFollowers 2.15.0 or a compatible newer release.



Back up your save before updating. Keep expanded-storage support enabled while

boxes 15â€“36 contain PokÃ©mon; the unmodified engine supports only 14 boxes.



### Black/White ROM animations (1.2.17)



The new **BW ROM** sprite style uses native multipart battle animations extracted from a user-supplied Black/White ROM. See [BW-ROM-IMPORT.md](BW-ROM-IMPORT.md) for the local importer, installation, fallback behavior and validation. Imported graphics live in a separate private companion mod, so 1025Dex updates preserve them. No ROM or extracted cartridge graphics are shipped in this release.



## 1.2.37 — Options menu entries



OPTIONS provides 1025DEX for settings and 1025DEX ASSETS for downloads. The native Gen 3 downloader no longer depends on the legacy screen registry.



## Cry styles (1.2.38)



Select CURRENT, ANIME or SHOWDOWN under OPTIONS → 1025DEX → CRY STYLE. Download asset pack 1.1.0 through 1025DEX ASSETS. Anime covers National 1–649 and falls back to CURRENT elsewhere; Showdown covers all 1025 base species. CURRENT retains Yellow Pikachu voice behavior.



POKEAPI selects the latest numbered cries from https://github.com/PokeAPI/cries. All 1025 clips match the existing CURRENT packed audio, so asset pack 1.1.0 is reused. Unlike CURRENT, POKEAPI uses the packed Pikachu cry in Yellow. Repository license: POKEAPI-CRIES-LICENSE.txt.



## 1.2.40 — Game Boy cry reliability



ROM base-cry definitions remain intact; selected audio uses clean file definitions at playback. Pikachu is checked in all four cry styles across all supported games, including Crystal. Existing asset pack 1.1.0 is reused.

## 1.2.41 - KIM Auto size compatibility

Expose optional `ctx.spriteLayout` through `battle.mon_pic` for natural frames. It describes the complete animation union and existing ground origin, including intentional hover padding and composited shadows. KIM1025 1.7.27 uses this for its opt-in desktop AUTO player size. Sprite pixels, animation clocks, native slots, cries and downloaded asset packs are unchanged. Update both mods and restart; no new asset download is required.

## 1.2.42 - Simplified sprite controls

ENEMY SPRITES and PLAYER SPRITES directly choose their own artwork. The redundant SPRITE STYLE row and DEFAULT choices have been removed. Pokédex and summary pictures follow PLAYER SPRITES; party icons retain their own setting.

BATTLE SPRITES previously enabled/disabled custom artwork; custom artwork is now always used. ANIMATE previously froze animation on the first frame; animated styles now always animate using their existing speed and EE playback settings. Explicitly static styles remain static.

3DB FRONTAL and 3DB FLIP duplicated PLAYER VIEW and have been removed. PLAYER VIEW retains BACK, FRONT and MIRRORED FRONT. Existing saved global style and legacy front/mirror choices migrate to the corresponding independent settings; unrelated settings and KIM1025 positioning are preserved.

Restart after updating. Existing downloaded assets are reused.
