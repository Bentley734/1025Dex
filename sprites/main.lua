-- =============================================================================
-- g9-battle-sprites -- true-colour animated battle sprites for the national dex
-- =============================================================================
--
-- WHAT IT DOES
--   Replaces the enemy front pic and the player back pic in battle -- and the
--   front pic on the Pokedex entry page -- with an animated, full-colour
--   sprite sheet from the DBK "solo sprites" pack
--   (la-base-de-sky / sprites-animados-dbk-solo-sprites, folders
--   Graphics/Pokemon/{Front, Front shiny, Back, Back shiny}).
--
--   The pack ships ONE png per Pokemon: a single horizontal strip whose frames
--   butt edge to edge, left to right, frame height == sheet height.  We use that
--   sheet DIRECTLY -- nothing is ever split into per-frame .png files on disk,
--   and no per-Pokemon subfolders are created (the pack is already one file per
--   Pokemon).  Frames are cropped out of the sheet in memory, each frame is
--   resampled once to the exact battle-pic box and cached as an Image.
--
-- LOOKUP (per battle pic)
--   1. national_dex species id (+ gender + shiny) -> a DBK sheet stem
--      (data/dbk_data.lua maps every species id to its stem; unknown forms fall
--      back to their base species).
--   2. <mod>/assets/<front|front_shiny|back|back_shiny>/<STEM>.png -- the mod's
--      own assets/ folder, and the ONLY source.  A sheet that is not installed
--      there simply leaves the vanilla pic untouched: there is no network
--      access and nothing is ever written.
--
-- FORM CONVENTIONS (the part that needed care)
--   * national_dex represents every mechanically/sprite-distinct form as its
--     own species id, and the map resolves each to the pack's own stem:
--       CHARIZARD_MEGA_X -> CHARIZARD_1     RAICHU_ALOLA    -> RAICHU_1
--       CHARIZARD_GMAX   -> CHARIZARD_3     SNEASEL_HISUI   -> SNEASEL_1
--       ALCREMIE_GMAX    -> ALCREMIE_63     MEOWSTIC_FEMALE -> MEOWSTIC_1
--       BASCULEGION_FEMALE -> BASCULEGION_1 OINKOLOGNE_FEMALE -> OINKOLOGNE_1
--   * cosmetic-only forms the pack has no sheet for (e.g. every Alcremie
--     flavour except base + gmax) are not mapped and fall back to the base
--     species sheet, which is the pack's own intent (base == ALCREMIE,
--     gmax == ALCREMIE_63).
--   * a Pokemon whose *gender* picks a different sheet (ABOMASNOW_female,
--     SNEASEL_1_female, ...) uses <stem>_female when the mon is female and the
--     pack has that file (data/dbk_data.lua's `female` set).
--   * shiny mons use the *_shiny folders.
--
-- PICTURE BOXES (why the frames are baked at these exact sizes)
--   Every frame is resampled ONCE into a canvas of the on-screen size the
--   vanilla pic occupies, so the engine's own placement math lands the sprite
--   exactly where the GB drew it and the pic scale can stay 1.
--     gen1 enemy front: 7x7 tiles at (96,0)          -> 56x56 at 1x
--     gen1 player back: pokered's 32x32 pic at 2x     -> 64x64 at 1x
--     gen2 enemy front: 7x7 tile box at (96,0)        -> 56x56 at 1x
--     gen2 player back: 6x6 tile box at (16,48)       -> 48x48 at 1x
--   (src/battle/BattleState.lua documents the gen1 back as "32x32 drawn at 2x";
--   src/ui/gen2/BattleState.lua documents the gen2 boxes.)
--
-- SIZES AND ALIGNMENT (the SPRITE SIZE / GROUND ANCHOR / FLOATERS options)
--   BIG (default), NORMAL and SMALL divide the art by 1, 2 and 3.
--   Retired MAX DETAIL selections resolve to BIG. All modes fit oversized
--   artwork to the picture box and keep one transform across the animation.
--
--   The resample is ALWAYS nearest-neighbour, on a fractional grid: each
--   destination pixel takes the source pixel nearest its own centre, so hard
--   edges and the pack's exact palette survive.  (An area/box filter instead
--   blends neighbouring colours into new ones, which reads as a soft, muddy
--   smear beside the game's crisp pixel UI -- the earlier "blurry sprites"
--   complaint.)  A destination pixel whose nearest source pixel is transparent
--   borrows the nearest OPAQUE pixel it covers, so a one-pixel outline or
--   antenna is never punched out by the stride.
--
--   SMALL / NORMAL / BIG divide every sheet by one whole number (3 / 2
--   / 1), preserving proportional sizes within the available box.
--   A sheet too big to fit the box is always shrunk to fit, whatever the mode.
--
--
--   GROUND ANCHOR decides where each sprite sits vertically.
--   FEET (the default) anchors every sprite by its own FEET -- the bottom row
--   of its art -- so all grounded Pokemon stand on the SAME line however much
--   empty padding their sheet happens to carry; Zigzagoon and Wooloo, whose
--   sheets put their feet at different heights, now land their feet together.
--   It is a property of the ART, not of the pack's metrics, so it cannot drift
--   when a sheet and its metrics disagree.  A Pokemon the pack draws AIRBORNE
--   (see FLOATERS below) is instead lifted off that line by FLOAT_LIFT x its
--   own height -- a share of its size -- so a big flyer hovers higher than a
--   small one.
--   PACK uses the pack's own SpeciesMetrics data (data/dbk_metrics.lua,
--   FrontSprite/BackSprite x,y per stem): the pack anchors a sheet's UNTRIMMED
--   frame bottom-centre at a fixed base and shifts it by those values * 2
--   screen px.  We trim each sheet to its content first, so the padding the
--   metrics assume is gone and is put back with the same arithmetic
--   Essentials/DBK use; see setupFrames for the derivation.  BOX simply
--   bottom-centres every sprite in its box, with no alignment at all.
--
-- GIMMICK OVERLAYS (read live from the battle_forms mod)
--   Two optional, per-Pokemon overlays are baked INTO the frame rather than
--   drawn as a second pass, so neither costs anything per frame and neither can
--   desync from the sprite or flicker with the frame clock:
--     * TERA ART -- a Terastallized Pokemon wears a cut-crystal film tinted the
--       colour of its Tera type: a shattered pane of flat voronoi facets in a
--       chaotic mix of broad slabs and small chips -- the sites are scattered
--       freely, so no rows or columns of seams survive to read as a grid -- each
--       shard held inside a size band (chips are folded into their neighbours,
--       wide plates are split along a wavy fracture) and edged with fine dark
--       bevel seams, a chamfered rim, whole-facet specular glare and small
--       4-pointed star glints -- a solid white heart with four tapering arms
--       that soften into the facet, and nothing on the diagonals -- made only
--       of light, blended 70/30 over the sprite (the TERA TRANSPARENCY option
--       tunes the crystal's own opacity) and drawn ONLY where the
--       sprite's own pixels are opaque, so it follows the creature's real
--       silhouette instead of its square frame.
--     * DYNAMAX CLOUD -- a Dynamaxed or Gigantamaxed Pokemon wears the pack's
--       red cloud above its head, like a crown.  In a fixed picture box the
--       cloud claims a band off the top and the sheet is fitted into the rest
--       (so the cloud floats clear of the head and only a sprite tall enough to
--       have used that room up is shrunk at all); in a custom screen's natural-
--       size mode the frame simply grows upward instead.
--   Both are read from battle_forms' own describe() payload and are absent
--   (no overlay, no error) when battle_forms is missing, older, or nothing is
--   transformed.
--
-- HOW IT HOOKS IN
--   gen1: wraps src.battle.BattleState:drawPicsLayer to hand each managed
--         battler its current frame as battler.sprite (the engine's own pic
--         draw path -- faint slides, send-out grow, squish/blink all keep
--         working), forces resolveBattleScale -> 1 for managed species, and
--         marks the drawn rect true-colour (PaletteFX.markTrueColor) so the
--         SGB/GBC zone pass leaves it alone.
--   gen2: wraps src.ui.gen2.BattleState:pic to return the current frame Image
--         with trueColor = true (Gold draws a trueColor pic raw), picScale -> 1
--         for managed species, and frontAnimFrame -> nil so Crystal's own
--         animated front pics never take precedence.
--   dex:  the Pokedex does NOT draw through either battle screen -- it asks
--         src.pokemon.Sprites.path / Sprites.pic for a front-pic PATH and loads
--         that file itself, so the pokemon.sprite hook (which can only swap the
--         path string) can never hand it our in-memory frame.  gen1's
--         src.ui.DexEntryMenu:draw and gen2's src.ui.gen2.PokedexMenu:picFor are
--         therefore wrapped directly to return the current frame with
--         trueColor = true (see the dex block below).  DEX SPRITES turns it off.
--         On gen1 this is also the national dex's OWN Pokedex screen: the
--         national_dex mod patches src.ui.DexEntryMenu in memory (its
--         src/dexpage.lua) into a page strip whose page 2 is its STATS page,
--         with LEFT/RIGHT browsing 326 alternate forms.  The sheet therefore
--         follows self.formId (the form the screen is showing, not just the
--         species the entry was opened for), is applied from BOTH the draw and
--         the update wrapper (national_dex draws its STATS page from its own
--         wrapper, which can return before the class draw runs), and a form
--         with no sheet falls back to the base species'.
--   summary: the party summary shows the FRONT sheet, on every screen that
--         paints one.  The party menu's STATS action opens it as the pushed
--         screen id "SummaryMenu" (src/ui/PartyMenu.lua), so BOTH generations'
--         native SummaryMenu are wrapped (gen1 self-draws the frame, gen2 wraps
--         drawPic), and a replacement registered under that same id -- or any
--         other pushed screen that paints the mon's own front pic, e.g. the g9
--         battle engine's 256x144 modern STATS screen -- is found by a
--         screen.pushed listener and decorated the same way.  A screen under
--         the party summary's id draws into the native 160x144 picture slot on
--         both its pages; anything else is treated as a wide modern screen
--         (left box, picture page only).  The mod never disables or reproduces
--         such a screen to show its sprites on it, so national_dex's own
--         summary stats box (which wraps the native draw) still composes
--         underneath.  SUMMARY SPRITES turns them off; SUMMARY SIZE scales the
--         picture on every one of them.
--   party: the little 16x16 icon on each PARTY-list row, on BOTH generations.
--         gen1's src.ui.PartyMenu.drawIcon (a module function) and gen2's
--         src.ui.gen2.PartyMenu:drawIcon are wrapped directly.  These icons are
--         the mod's OWN art rather than a user-supplied sheet: a separate
--         "icones animados" pack (one 128x64 two-frame PNG per icon) is packed
--         into assets/icons/party_icons.png, and data/icon_data.lua maps a
--         species id (and its female variant) to an atlas cell.  Each cell is
--         already the slot's exact 16x16, so an icon is drawn as a quad over
--         the shared atlas -- no per-mon bake, just the atlas decoded once.
--         gen1 marks the icon rect true-colour for the SGB/GBC zone pass; gen2
--         draws raw in GBC mode (the engine's own trueColor rule) and still
--         reproduces the held-item marker in the icon's bottom-left tile.
--         Species the icon pack has no entry for stay vanilla, and eggs get
--         the pack's own egg icon.  PARTY ICONS turns it off.
--   A core.update hook advances frame building on a strict per-frame time
--   budget, so image work never blocks a frame and no image work ever happens
--   inside a draw call.
--
-- SECURITY / SANDBOX NOTES
--   Needs only the "engine_internals" permission (it requires the BattleState
--   modules and PaletteFX).  It reads exclusively from its own assets/ folder:
--   no network access, no cache and no write of any kind.  It never touches
--   another mod, a playthrough save, or a host path.
-- =============================================================================
return function(mod)
  -- FireRed's party screen does not use the Gen 1/2 PartyMenu or the legacy
  -- icon registry.  Its actual renderer is hooked in installGen3 below.

  -- ---------------------------------------------------------------------------
  -- Options (identical table to options.lua -- keep the two in sync)
  -- ---------------------------------------------------------------------------
  local OPTIONS = {
  {
    key = "enemy_sprite_style", label = "ENEMY SPRITES", type = "choice", default = 3,
    choices = { { "ANIMATED", 0 }, { "GEN9 STATIC", 1 }, { "BW ROM", 2 }, { "EE ANIMATED", 3 }, { "EE STATIC", 4 }, { "KIM", 5 } },
    description = "Artwork for enemy battle Pokemon. Animated styles always animate; static styles remain still.",
  },
  {
    key = "player_sprite_style", label = "PLAYER SPRITES", type = "choice", default = 3,
    choices = { { "ANIMATED", 0 }, { "GEN9 STATIC", 1 }, { "BW ROM", 2 }, { "EE ANIMATED", 3 }, { "EE STATIC", 4 }, { "KIM", 5 } },
    description = "Artwork for player battle Pokemon, Pokedex and summary pictures. Animated styles always animate; static styles remain still.",
  },
  {
    key = "player_sprite_view", label = "PLAYER VIEW", type = "choice", default = 0,
    choices = { { "BACK", 0 }, { "FRONT", 1 }, { "MIRRORED FRONT", 2 } },
    description = "Player battle pose in every game: back artwork, front artwork, or horizontally mirrored front artwork. Existing front and mirror selections are preserved when updating. Enemy artwork is never mirrored.",
  },
  {
    key = "ee_pause", label = "EE PAUSE", type = "choice", default = 2,
    choices = { { "1 SEC", 1 }, { "2 SEC", 2 }, { "3 SEC", 3 }, { "4 SEC", 4 }, { "5 SEC", 5 }, { "6 SEC", 6 }, { "7 SEC", 7 } },
    description = "Seconds to hold the first pose after EE ANIMATED finishes its selected number of loops.",
  },
  {
    key = "ee_loops", label = "EE LOOPS", type = "choice", default = 2,
    choices = { { "1", 1 }, { "2", 2 }, { "3", 3 }, { "4", 4 }, { "5", 5 } },
    description = "Number of EE animation loops before pausing. Selecting a Pokedex entry restarts playback immediately.",
  },
  {
    key = "ee_alt_pause", label = "EE ALT PAUSE", type = "choice", default = 1,
    choices = { { "SAME", 0 }, { "1 SEC", 1 }, { "2 SEC", 2 }, { "3 SEC", 3 }, { "4 SEC", 4 }, { "5 SEC", 5 }, { "6 SEC", 6 }, { "7 SEC", 7 } },
    description = "Pause after every second EE playback burst. SAME uses EE PAUSE.",
  },
  {
    key = "ee_alt_loops", label = "EE ALT LOOPS", type = "choice", default = 3,
    choices = { { "SAME", 0 }, { "1", 1 }, { "2", 2 }, { "3", 3 }, { "4", 4 }, { "5", 5 } },
    description = "Loops in every second EE playback burst. SAME uses EE LOOPS. Primary and alternate bursts repeat in turn; Pokedex selection starts with the primary burst.",
  },
  {
    key = "sprite_fps",
    label = "SPRITE SPEED",
    type = "choice",
    default = 12,
    choices = {
      { "SLOW", 6 },
      { "NORMAL", 12 },
      { "FAST", 18 },
      { "VERY FAST", 24 },
    },
    description = "Playback speed of the animated sheets (frames per second).",
  },
  {
    key = "sprite_shiny",
    label = "SHINY ART",
    type = "toggle",
    default = true,
    description = "ON (default): shiny Pokemon use the *_shiny sheets. OFF: shiny Pokemon use the normal-colour sheets.",
  },
  {
    key = "sprite_female",
    label = "FEMALE ART",
    type = "toggle",
    default = true,
    description = "ON (default): female Pokemon use their _female sheet where the pack has one. OFF: one sheet for both sexes.",
  },
  {
    key = "sprite_size",
    label = "SPRITE SIZE",
    type = "choice",
    default = 1,
    choices = {
      { "BIG", 1 },
      { "NORMAL", 2 },
      { "SMALL", 3 },
    },
    description = "BIG (default), NORMAL and SMALL divide ANIMATED, GEN9 STATIC and EE artwork by 1, 2 and 3, shrinking further only when needed to fit the picture box. BW ROM artwork fits its visible animation into the box at BIG, half that size at NORMAL and a third at SMALL. All frames share one scale and ground anchor. Existing MAX DETAIL selections now use BIG. Custom battle scenes that supply their own scale keep that scale.",
  },
  {
    key = "sprite_anchor",
    label = "GROUND ANCHOR",
    type = "choice",
    default = 0,
    choices = {
      { "FEET", 0 },
      { "PACK", 1 },
      { "BOX", 2 },
    },
    description = "FEET (default): anchor every sprite by its own FEET -- the bottom of its art -- so all grounded Pokemon stand on the SAME line however much empty padding their sheet carries (Zigzagoon and Wooloo, for example, land their feet at the same height instead of one sitting lower). A Pokemon that floats or flies is instead lifted off that line by a share of its own height, so a big flyer hovers higher than a small one (see FLOATERS). PACK: place each sprite using the offsets from the pack's own SpeciesMetrics data (data/dbk_metrics.lua), the previous default. BOX: simply bottom-centre every sprite in its picture box, with no alignment at all.",
  },
  {
    key = "sprite_float",
    label = "FLOATERS",
    type = "toggle",
    default = true,
    description = "ON (default): in FEET mode, a sprite the pack draws airborne (a flying or levitating species, see data/dbk_float.lua) is lifted off the ground line by FLOAT_LIFT x its own height, so it hovers instead of standing -- and a bigger flyer hovers higher than a smaller one. OFF: every sprite stands its feet on the line. This row does nothing in PACK or BOX mode.",
  },
  {
    key = "dex_sprites",
    label = "DEX SPRITES",
    type = "toggle",
    default = true,
    description = "ON (default): the Pokedex shows the same true-colour sheet as the battle screen (its first frame when ANIMATE is off) -- on gen1 that includes the national dex's own PokÃ©dex screen, its STATS page and its LEFT/RIGHT form browsing. OFF: the Pokedex keeps the game's own front pic.",
  },
  {
    key = "summary_sprites",
    label = "SUMMARY SPRITES",
    type = "toggle",
    default = true,
    description = "ON (default): the party SUMMARY screen shows the same true-colour animated sheet as the battle screen -- the FRONT sheet, or the *_shiny FRONT sheet for a shiny Pokemon, resolved through the same species/form/gender mapping the battle pics use. OFF: the summary keeps the game's own front pic.",
  },
  {
    key = "summary_size",
    label = "SUMMARY SIZE",
    type = "choice",
    default = 100,
    choices = {
      { "REAL SIZE", 100 },
      { "75%", 75 },
      { "50%", 50 },
      { "25%", 25 },
    },
    description = "How big the SUMMARY picture is drawn. REAL SIZE (default) is the same 1:1 front box the battle screen uses; 75% / 50% / 25% draw the very same sheet smaller inside that box (still animated, still true-colour, still the pack's art). This row applies to the SUMMARY and nothing else -- battles, the Pokedex and every custom battle screen keep the full-size picture whatever it says, so it can never change how a Pokemon looks mid-fight.",
  },
  {
    key = "party_icons",
    label = "PARTY ICONS",
    type = "toggle",
    default = true,
    description = "ON (default): the little 16x16 icon beside each Pokemon in the PARTY list is that Pokemon's own true-colour animated icon from the mod's bundled icon pack (assets/icons/party_icons.png), two frames per Pokemon, including its female form where the pack has one. Applies on both generations, wherever you can see your party (overworld, and in battle). OFF: the party list keeps the game's own two-colour icon art.",
  },
  {
    key = "g9_party_screen",
    label = "G9 PARTY SCREEN",
    type = "toggle",
    default = false,
    description = "OFF (default): the party list is the game's own 160x144 screen, with the mod's 16x16 PARTY ICONS art on it when that row is on. ON: the whole party page is redrawn from the game's OWN parts -- the same two-line rows (name, level, HP figures, HP-bar tiles, status/FNT), cursor, CANCEL row and \"Choose a POKeMON.\" box, from the tiles and fonts of whatever generation you are playing (gen 1 art on Red/Blue/Yellow, gen 2 art on Gold/Silver/Crystal), in exactly the same proportions -- but on a 640x576 page (4x the Game Boy screen, scaled to fill your window) instead of 160x144. That 4x page is what lets each Pokemon's high-resolution icon art (assets/icons/party_icons_hd.png) be drawn at its own natural size instead of being shrunk into a 16x16 slot. The action list that opens when you pick a Pokemon (STATS / SWITCH / field moves / ITEM / CANCEL) is the game's own submenu, unchanged, and anything the party menu opens (the summary, a message box) is drawn on that same larger page. Battles, the Pokedex, and the summary's own picture logic are untouched.",
  },
  {
    key = "tera_art",
    label = "TERA ART",
    type = "toggle",
    default = true,
    description = "ON (default): a Pokemon that has Terastallized wears a cut-crystal overlay tinted with its Tera type (the type's own colour) -- a shattered pane of flat angular facets in a chaotic Voronoi mix of broad slabs and small chips (randomly placed, so no two shards share a shape and no rows or columns of seams survive to read as a grid), with every shard held inside a size band -- the chipped ones are folded into their neighbours and the wide ones are split along a wavy fracture -- so the mean shard is small without any single shard shrinking to a speck or growing into one dominating plate, edged with fine dark bevel seams that carry the type's tint, inside a chamfered glowing rim, with whole-facet specular glints and small white 4-pointed star sparkles -- a solid white heart with four tapering arms that soften into the facet, and nothing on the diagonals -- made only of light, scaled with the bake so a large sheet gets a proportionally large sparkle rather than a speck -- blended 70/30 over the sprite (the TERA TRANSPARENCY row makes the crystal more or less see-through) and drawn ONLY where the sprite's own pixels are opaque: the creature's true silhouette, never the transparent margin of its frame. The sparkles are their own animation: each star blinks on and off on its own cycle, spread over the clearest, lightest facets. The whole crystal -- facets, bevels, rim and stars -- also rides the sprite's own animation, shifting with the creature's motion from frame to frame instead of staying nailed to the picture box. The state comes from battle_forms when a Pokemon is really Terastallized, or from the declaration a custom battle screen stamps on a wild RAID boss (g9-Battle-Scene announces a Tera raid but never mechanically activates the gimmick, so it hands this mod the declared type); without either (or for a type with no colour) nothing changes. OFF: Terastallized and declared-raid Pokemon keep their ordinary art.",
  },
  {
    key = "tera_transparency",
    label = "TERA TRANSPARENCY",
    type = "choice",
    default = 30,
    choices = {
      { "5%", 5 },
      { "10%", 10 },
      { "20%", 20 },
      { "30%", 30 },
      { "40%", 40 },
      { "50%", 50 },
      { "60%", 60 },
    },
    description = "How see-through the TERA ART crystal is. The percentage is how much of the Pokemon's own colours show THROUGH the crystal, and the crystal keeps the rest -- so 30% is the 70/30 crystal-over-sprite blend the effect shipped with. 5% is an almost solid gem; 60% is a sheer, glassy film. Only the opacity of the crystal layer changes: its facet pattern, colours, bevels, rim, glints and sparkles are all untouched. This row only does anything when TERA ART is on.",
  },
  {
    key = "dynamax_cloud",
    label = "DYNAMAX CLOUD",
    type = "toggle",
    default = true,
    description = "ON (default): a Pokemon that is Dynamaxed or Gigantamaxed right now wears the red Dynamax cloud above its head, like a crown. It is baked into EVERY frame of the animation (never a second draw pass, so it cannot flicker with the frame clock) and it is anchored to the sprite's own head -- sinking far enough that the puffs rest on the head instead of hovering over it -- while a fixed picture box gives the cloud its own band and fits the sheet into the rest, shrinking a sprite only as much as it must; a custom battle screen's natural-size frame simply grows upward instead. The state comes from battle_forms when a Pokemon is really Dynamaxed, or from the declaration a custom battle screen stamps on a wild RAID boss (a Dynamax/Gigantamax raid boss is announced but never mechanically activated, so the screen hands this mod the declared kind); without either (or with no gimmick active) nothing changes. OFF: Dynamaxed and declared-raid Pokemon keep their ordinary art.",
  },
  {
    key = "battle_shadows",
    label = "BATTLE SHADOWS",
    type = "toggle",
    default = true,
    description = "ON (default): every battle Pokemon casts a soft shadow on the ground line beneath it, from the same Shadow art the game uses (assets/shadow/1.png, 2.png and 3.png -- the small, medium and large contact shadows). The pack's own ShadowSize for a species picks which one AND how wide it reads -- 2/3/4 stretch it wider, -1/-2/-3 tighten it, the default 1 is the middle -- and ShadowSize 0 hides it entirely; a species' own sprite dropped in as assets/shadow/<STEM>.png (same stem as its battle sheet) overrides the generic art. The shadow is composited behind the sprite into EVERY frame of the animation, so it cannot flicker or desync from the frame clock, and it is drawn only in battle -- the Pokedex, the summary and the party list are untouched. NOTE: a custom battle screen that paints its own contact shadow (g9-Battle-Scene does, when a background is in use) will show that one as well; set this row OFF if you would rather keep only the screen's own.",
  },
}
  mod.options:define(OPTIONS)

  -- ---------------------------------------------------------------------------
  -- Constants
  -- ---------------------------------------------------------------------------
  -- On-screen pic boxes in GB pixels (see the PICTURE BOXES note up top).
  local FRONT_BOX = { w = 56, h = 56 }
  local BACK_BOX_GEN1 = { w = 64, h = 64 }   -- pokered 32x32 pic drawn at 2x
  local BACK_BOX_GEN2 = { w = 48, h = 48 }   -- pokecrystal 6x6 tile box at 1x
  local FRONT_BOX_GEN3 = { w = 64, h = 64 }  -- FireRed front and back pictures
  local BACK_BOX_GEN3 = { w = 64, h = 64 }
  -- FireRed draws the picture layer immediately above the command/HUD band.
  -- DBK sheets are taller than the original GBA art, so reserve headroom and
  -- raise the baked content or its lower half disappears behind that band.
  local GEN3_MAX_ART_H = 64
  local GEN3_SPRITE_LIFT = 0

  -- Frame building is spread across frames under this per-update time budget so
  -- a new sheet never stalls the game.  Scan rows per chunk bounds the work of
  -- one step even when a single step would blow the budget.
  local BUILD_BUDGET = 0.008
  local SCAN_ROWS = 6
  -- How many resolved sheets to keep before the least-recently-used one has its
  -- frame Images dropped (the raw png bytes are kept, so a rebuild is offline
  -- and cheap; any Image still referenced by a live battler simply stays alive
  -- until Lua collects it).
  local MAX_SHEETS = 64
  local EVICT_AGE_FRAMES = 1200
  -- Re-scan a sheet that was not found in assets/ this often, so a file copied
  -- in mid-session is picked up without a restart.
  local RECHECK_FRAMES = 900

  local GEN = 0   -- 1 or 2, set once a supported battle screen is found

  local function localFolder(back, shiny)
    if back then return shiny and "back_shiny" or "back" end
    return shiny and "front_shiny" or "front"
  end

  -- ---------------------------------------------------------------------------
  -- Generated data (species -> stem, stem existence, female stems)
  -- ---------------------------------------------------------------------------
  local function readData(rel)
    local text, err = mod:read(rel)
    if not text then return nil, err end
    local chunk, cerr = loadstring(text, "@" .. rel)
    if not chunk then return nil, cerr end
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= "table" then return nil, "bad data" end
    return value
  end

  local DATA, dataErr = readData("data/dbk_data.lua")
  if not (DATA and DATA.species and DATA.stems and DATA.female) then
    mod.log:error("g9-battle-sprites: data/dbk_data.lua is missing or invalid (%s)"
      .. " -- mod inactive", tostring(dataErr))
    return
  end

  -- Per-species alignment offsets from the pack's own SpeciesMetrics files (see
  -- data/dbk_metrics.lua).  Optional, and only read in PACK mode: without it a
  -- PACK bake simply falls back to bottom-centring.
  local METRICS = readData("data/dbk_metrics.lua")
  DATA.static = readData("data/static_data.lua") or { files = {}, aliases = {} }
  DATA.static.metrics = readData("data/static_metrics.lua") or {}
  DATA.ee = readData("data/ee_data.lua") or { files = {} }
  if not METRICS then
    mod.log:warn("g9-battle-sprites: data/dbk_metrics.lua is missing or invalid --"
      .. " PACK anchoring will fall back to bottom-centring")
  end

  -- The stems whose ART floats or flies (data/dbk_float.lua).  Optional: with
  -- no file nothing is lifted, i.e. every sprite stands its feet on the line.
  local FLOATERS = readData("data/dbk_float.lua")
  if not FLOATERS then
    mod.log:warn("g9-battle-sprites: data/dbk_float.lua is missing or invalid --"
      .. " no sprite will be lifted (reinstall the mod)")
  end

  -- ---------------------------------------------------------------------------
  -- Option accessors
  -- ---------------------------------------------------------------------------
  local function opt(key, default)
    local ok, value = pcall(mod.options.get, mod.options, key)
    if ok and value ~= nil then return value end
    return default
  end
  local function wantEnabled() return true end
  function DATA.kimPeer()
    if type(mod.find)~='function'then return nil end
    local ok,handle=pcall(mod.find,mod,'kim1025')
    local peer=ok and handle and handle.exports
    return peer and type(peer.getDexSpriteSheet)=='function'and peer or nil
  end
  function DATA.spriteStyle()
    if mod and mod.migrateSpriteOptions then mod:migrateSpriteOptions() end
    local value = tonumber(opt("player_sprite_style", -1))
    if not value or value < 0 then value = tonumber(opt("sprite_style", 3)) end
    if value==5 and not DATA.kimPeer()then return 3 end
    return (value == 1 or value == 2 or value == 3 or value == 4 or value == 5) and value or 0
  end
  function DATA.styleFor(back, battle)
    if mod and mod.migrateSpriteOptions then mod:migrateSpriteOptions() end
    if battle then
      local value = tonumber(opt(back and "player_sprite_style" or "enemy_sprite_style", -1))
      if value==5 and not DATA.kimPeer()then return 3 end
      if value and value >= 0 and value <= 5 and value == math.floor(value) then return value end
    end
    local value = tonumber(opt("sprite_style", 3))
    if battle then return (value == 1 or value == 2 or value == 3 or value == 4 or value == 5) and value or 0 end
    return DATA.spriteStyle()
  end
  function DATA.playerView(back)
    if mod and mod.migrateSpriteOptions then mod:migrateSpriteOptions() end
    if not back then return false, false end
    local view = tonumber(opt("player_sprite_view", -1))
    if view == 0 then return false, false end
    if view == 1 then return true, false end
    if view == 2 then return true, true end
    local front = opt("battle_frontal", false) ~= false
    return front, front and opt("battle_front_flip", false) ~= false
  end
  if mod and mod.exports then mod.exports.spriteStyleFor=function(side,battle)return DATA.styleFor(side=='back',battle~=false)end end
  local function animateOn(style)
    style = style or DATA.spriteStyle()
    return style ~= 1 and style ~= 4
  end
  function DATA.bwPeer()
    if type(mod.find) ~= "function" then return nil end
    local ok, handle = pcall(mod.find, mod, "1025dex-bw-sprites")
    local peer = ok and type(handle) == "table" and handle.exports
    if type(peer) == "table" and type(peer.sprite) == "function"
      and type(peer.decodeSprite) == "function" then return peer end
  end
  function DATA.bwFrame(timing, elapsed, count)
    if not timing or count < 1 then return 1 end
    local total, first = tonumber(timing.total_ticks) or 0, tonumber(timing.loop_tick) or 0
    if total <= first or first < 0 then return 1 end
    local tick = math.max(0, math.floor(elapsed * 60))
    if tick >= total then tick = first + (tick - first) % (total - first) end
    for i, duration in ipairs(timing.durations or {}) do
      if tick < duration then
        local index = (timing.indices or {})[i] or i
        return index <= count and index >= 1 and index or 1
      end
      tick = tick - duration
    end
    return 1
  end
  function DATA.eeFrame(frames, elapsed, fps, count)
    if not frames or not frames.__ee then return nil end
    if count < 2 then return 1 end
    frames.__eeStarted = frames.__eeStarted or elapsed
    local pause = math.max(1, math.min(7, tonumber(opt("ee_pause", 2)) or 2))
    local loops = math.max(1, math.min(5, math.floor(tonumber(opt("ee_loops", 2)) or 2)))
    local duration = count / math.max(1, fps)
    local alternatePause = tonumber(opt("ee_alt_pause", 1)) or 1
    local alternateLoops = tonumber(opt("ee_alt_loops", 3)) or 3
    alternatePause = alternatePause == 0 and pause or math.max(1, math.min(7, alternatePause))
    alternateLoops = alternateLoops == 0 and loops or math.max(1, math.min(5, math.floor(alternateLoops)))
    local primary = duration * loops + pause
    local alternate = duration * alternateLoops + alternatePause
    local phase = math.max(0, elapsed - frames.__eeStarted) % (primary + alternate)
    if phase >= primary then
      phase = phase - primary
      loops = alternateLoops
    end
    if phase >= duration * loops then return 1 end
    return math.floor(phase * math.max(1, fps)) % count + 1
  end
  local function wantShiny() return opt("sprite_shiny", true) ~= false end
  local function wantFemale() return opt("sprite_female", true) ~= false end
  local function dexOn() return opt("dex_sprites", true) ~= false end
  local function summaryOn() return opt("summary_sprites", true) ~= false end
  local function partyIconsOn() return opt("party_icons", true) ~= false end
  -- SUMMARY SIZE, as a multiplier on the baked front-box frame (1 = the
  -- battle screen's own size).  ONLY the two summary wrappers read this --
  -- no battle, dex or scene seam calls it -- so the row cannot touch a
  -- battle picture even by accident.
  local function summaryScale()
    local n = tonumber(opt("summary_size", 100))
    if not n then n = 100 end
    if n >= 100 then return 1 end
    if n <= 25 then return 0.25 end
    return n / 100
  end
  local function teraArtOn() return opt("tera_art", true) ~= false end
  local function dynamaxOn() return opt("dynamax_cloud", true) ~= false end
  -- The on-screen diagnostics panel is disabled outright: it was useful while
  -- the sheet loader was being brought up, but it is not something a player
  -- should be able to switch on.  The diag code stays (it is the only way to
  -- see what the mod is doing on a build with no developer console) but is
  -- dormant unless this is flipped to true in source.
  local DEBUG_PANEL_ENABLED = false
  local function debugOn() return DEBUG_PANEL_ENABLED end

  -- The pack's own render scales (Essentials/DBK Settings).  Its SpeciesMetrics
  -- x,y values are stored in half-units of these, so converting an offset back
  -- to sheet pixels divides by them (see setupFrames).
  local FRONT_SCALE = 2
  local BACK_SCALE = 3

  -- ---------------------------------------------------------------------------
  -- TERA ART (the crystal overlay for Terastallized Pokemon)
  -- ---------------------------------------------------------------------------
  -- A Terastallized Pokemon wears a cut-crystal film tinted the colour of its
  -- Tera type.  The film is baked INTO the frame (a per-type variant of the
  -- sheet, see buildOneFrame), never drawn as a second pass, so it costs
  -- nothing per frame and cannot desync from the sprite.
  --
  -- The look is CUT in code rather than painted from the pattern's own soft
  -- mosaic (which read as a blur at sprite scale): a free-scatter voronoi
  -- lattice (TERA.buildMap) shatters the box into flat facets -- freely placed
  -- sites, no grid, so nothing survives to read as a checkerboard -- each held
  -- inside a size band and each carrying
  -- one quantised brightness plate sampled from the crystal pattern
  -- (assets/tera_crystal.png); those plates become the type's colour TABLE
  -- below (deep shadow -> lifted lit plane), then bright/dark BEVEL seams, a
  -- chamfered RIM, whole-facet SPECULAR glare and 4-pointed STAR glints are
  -- laid on top, and the result is blended 70/30 with the sprite.  The blend is
  -- applied ONLY where the baked sprite pixel is
  -- opaque -- out.a = sprite.a -- which is exactly the requirement that the
  -- film respect the creature's real silhouette: a transparent pixel of the
  -- frame stays transparent, so the invisible square around a sprite is never
  -- turned into a visible crystal slab.
  --
  -- Colours: the official Scarlet/Violet type palette, with the five the user
  -- called out overridden (STELLAR = shiny silver, NORMAL = shiny white,
  -- STEEL = metallic gray, FLYING = sky blue, WATER = the chart's #2980EF) and
  -- ??? deliberately absent (an unmapped type simply draws no film).
  local TERA_TINT = {
    NORMAL   = { 1.000, 1.000, 1.000 },  -- shiny white
    FIRE     = { 0.902, 0.157, 0.161 },  -- #E62829
    FIGHTING = { 1.000, 0.502, 0.000 },  -- #FF8000
    WATER    = { 0.161, 0.502, 0.937 },  -- #2980EF (chart water)
    FLYING   = { 0.529, 0.808, 0.922 },  -- sky blue
    GRASS    = { 0.247, 0.631, 0.161 },  -- #3FA129
    POISON   = { 0.569, 0.255, 0.796 },  -- #9141CB
    ELECTRIC = { 0.980, 0.753, 0.000 },  -- #FAC000
    GROUND   = { 0.569, 0.318, 0.129 },  -- #915121
    PSYCHIC  = { 0.937, 0.255, 0.475 },  -- #EF4179
    ROCK     = { 0.686, 0.663, 0.506 },  -- #AFA981
    ICE      = { 0.239, 0.808, 0.953 },  -- #3DCEF3
    BUG      = { 0.569, 0.631, 0.098 },  -- #91A119
    DRAGON   = { 0.314, 0.376, 0.882 },  -- #5060E1
    GHOST    = { 0.439, 0.255, 0.439 },  -- #704170
    DARK     = { 0.384, 0.302, 0.306 },  -- #624D4E
    STEEL    = { 0.502, 0.522, 0.565 },  -- metallic gray
    FAIRY    = { 0.937, 0.439, 0.937 },  -- #EF70EF
    STELLAR  = { 0.776, 0.796, 0.831 },  -- shiny silver
  }
  -- The pattern's own luminance is very high-key (measured #D3..FF, a 17%
  -- swing), so feeding it in raw would tint almost uniformly and the facets
  -- would be invisible at sprite scale.  A single contrast stretch around the
  -- pattern's own measured min/max (see loadPattern) maps it onto this shade
  -- range instead, and each flat facet plane is then coloured by a straight
  -- SHADOW -> LIT ramp of the type colour:
  --   * shadow facets are the type colour at FILM_DARK x its brightness, which
  --     stays deeply saturated (a dark, gem-like core), and
  --   * lit facets are the type colour lerped FILM_LIGHT of the way to white,
  --     which lifts them without ever clipping a channel.
  -- The ramp is unclamped by construction -- a plain `tint * shade` multiply
  -- clips the blue of a WATER tint (and every channel of NORMAL) long before
  -- the top of the range, flattening exactly the light types into a washed-out
  -- wash, which is the failure this ramp exists to avoid.
  --
  -- Every crystal-film tunable lives in ONE table, on purpose: this sheet
  -- factory is an enormous function that sits right at Lua's 200-local limit,
  -- so a loose `local TERA_*` scalar per knob (plus the sampling helpers, which
  -- are stored as fields below for the same reason) is enough to stop the whole
  -- mod loading.  Adding a per-pixel knob here must therefore cost ZERO locals.
  local TERA = {
    -- The shadow -> lit ramp of the type colour (see the note above).
    FILM_DARK = 0.24,
    FILM_LIGHT = 0.45,
    -- How much of the film, vs the sprite, the finished pixel is: 0.70 = 70%
    -- crystal, 30% sprite.  Leaning on the film is what makes the facets and
    -- the glints read through a pale sprite (a 50/50 mix let a light creature's
    -- own colours wash the crystal out).
    MIX_FILM = 0.70,
    -- FACET QUANTISATION.  Each shard's brightness is sampled from the crystal
    -- asset, whose luma drifts smoothly; snapping it down to a handful of flat
    -- steps keeps neighbouring shards visually distinct instead of drifting into
    -- one another, which is what gives the "chiselled gemstone" look.  1
    -- disables quantisation.
    FACET_LEVELS = 6,
    -- FACET LATTICE: A SHATTERED PANE, NOT A GRID.  The shards are a Voronoi
    -- diagram of sites scattered freely over the padded box, rather than sites
    -- sitting on a jittered grid -- a grid leaves rows and columns of seams that
    -- survive every amount of jitter and read as a checkerboard.  FACET_SITES is
    -- how many sites there are, i.e. the overall shard DENSITY (raise it for
    -- more, smaller shards); FACET_MIX is the share of them that are CLUSTERED,
    -- and that is what gives the lattice its range of scales -- a cluster packs
    -- sites close together into chips while the space between clusters is left
    -- to a single site, which becomes a slab; FACET_MIX_RADIUS is how wide a
    -- cluster is, in units of the nominal pitch (the square root of the mean
    -- cell area).  0 for FACET_MIX scatters them evenly instead (a fine, regular
    -- grain); 1 clusters them all.  At the pack's 56px box, 180 / 0.8 / 1.4
    -- gives the reference crystal's chipped planes rather than a handful of big
    -- slabs: the mean shard lands near a third of the old jittered grid's, with
    -- the size spread (cv) roughly tripled.
    FACET_SITES = 180,
    FACET_MIX = 0.8,
    FACET_MIX_RADIUS = 1.4,
    -- THE SHARD SIZE BAND, both as multiples of the nominal cell area (the box
    -- area divided by FACET_SITES).  A raw scatter always leaves a few hairline
    -- slivers -- and a speck of a facet reads as dirt on the glass, not as a
    -- chip of it -- plus a few outsized slabs.  FACET_MIN folds every shard
    -- below it into its largest neighbour; FACET_MAX cracks every shard above it
    -- along a wavy line.  Holding both ends is what lets the MEAN shard be small
    -- (the density is high) without any individual shard shrinking to nothing.
    -- Both are relative to the nominal cell, so they follow the box: a big bake
    -- gets proportionally big shards.
    FACET_MIN = 0.3,
    FACET_MAX = 2.2,
    -- How many FACET_MAX splits may be attempted before the ceiling is left to
    -- stand.  Each split halves one shard, so the count needed grows with the
    -- shard count; this is headroom, not a cost (a split is a walk over that one
    -- shard's own pixels).
    FACET_SPLIT_GUARD = 4000,
    -- How far the FACET_MAX crack wanders as it runs, in units of the nominal
    -- pitch: 0 is a ruler-straight cut, which reads as an artificial slice, and
    -- too much reads as a drawn squiggle; ~0.35 is the low-frequency wobble of
    -- a real fracture.
    FACET_CRACK_BEND = 0.35,
    -- PATTERN COVER.  How much of the crystal pattern's own width the content
    -- box spans, as a share of the pattern.  It sets the RANGE of shard
    -- brightnesses (the shard centroids spread over this much of the pattern, so
    -- a bigger cover samples more of its light/dark variation) -- and, being a
    -- share rather than a fixed step, a small sprite and a large one show the
    -- same spread.  It is clamped so the window never runs off the pattern.
    PATTERN_COVER = 0.45,
    -- The percentile pair the sampled window's luma is stretched between (see
    -- the autocontrast note in buildOneFrame): 0.08 / 0.92 clips the darkest and
    -- brightest 8% of the window to the ramp's extremes, which is what turns a
    -- bell-shaped slice into the deep-shadow / blazing-facet spread that reads
    -- as crystal instead of grey stone.
    CONTRAST_LO = 0.10,
    CONTRAST_HI = 0.97,
    -- After that stretch the facet brightness is still a bell curve (the asset
    -- itself is low-contrast: its luma sd is only ~0.03), so the ramp would land
    -- mostly on mid-tones.  This blends the stretched luma toward a smoothstep
    -- S-curve, spreading the bell toward BOTH ends -- the difference between
    -- "grey stone" and "deep shadow next to blazing facet".  It is a blend (not
    -- a linear gain) precisely so it cannot clip into a flat plateau: a plateau
    -- would hand the whole top band to the white glint and wash the sprite out.
    -- 0 disables it, 1 is the full S-curve.
    CONTRAST_GAIN = 1.0,
    -- SPECULAR GLINT: the shard's uniform highlight -- a whole facet catching
    -- the sun, not a soft hotspot.  The response is read off the shard's SMOOTH
    -- (pre-quantisation) brightness, so it rolls on across the brightest few
    -- shards; SPEC_T0 is where it starts, SPEC_POW steepens the roll-on and
    -- SPEC_STRENGTH is how close the glare comes to white.  (Keying it off the
    -- quantised band instead floods a whole sixth of the creature with white.)
    SPEC_T0 = 0.90,
    SPEC_POW = 3.0,
    SPEC_STRENGTH = 0.6,
    -- FACET BEVEL.  A shard boundary is drawn as a lit edge on one side
    -- (SEAM_STRENGTH: how far that one-pixel line is pulled toward the seam
    -- light) and a shadowed edge on the other (SEAM_DARK: how far the opposite
    -- one-pixel line is deepened, as a fraction of its brightness).  That
    -- bright/dark pairing is what makes the surface read as physical cut crystal
    -- rather than as flat stained glass -- but the reference crystal's seams are
    -- mostly the DARK, near-black hairline with only the barest catch of light
    -- on the other side, so these are kept low: a strong lift is what turns the
    -- lattice into a white wireframe laid over the creature, which reads as
    -- unnatural lines rather than as edges of the stone.  Set SEAM_DARK to 0
    -- for a bright seam only, or SEAM_STRENGTH to 0 for shadowed edges only.
    SEAM_STRENGTH = 0.16,
    SEAM_DARK = 0.34,
    -- The colour the lit bevel is pulled toward: pure white mixed with SEAM_TINT
    -- of the Tera type's own colour (1 = the raw type colour, 0 = pure white).
    -- A little tint keeps the highlight on the crystal's own hue, so a seam
    -- never flashes a neutral white line across, say, a gold or violet stone.
    -- Only the LIT side is tinted; the shadowed side is a plain darkening of
    -- each pixel, so it keeps whatever hue its facet has.
    SEAM_TINT = 0.55,
    -- IRIDESCENCE: the crystal asset carries a faint chromatic tint in its
    -- facets; amplified, it sheens the film toward cyan/violet/gold instead of
    -- one flat hue.  The gain is on the per-channel deviation from the pattern
    -- pixel's own mean, so a neutral pixel contributes nothing.
    IRID_GAIN = 1.2,
    -- RIM LIGHT: a Fresnel-style bright edge painted over the outermost opaque
    -- pixels of the silhouette, so the creature looks lit from within and its
    -- outline glows -- the single strongest "shiny" cue at low resolution.
    -- RIM_TINT keeps a little of the Tera type's colour in the rim (1 = pure
    -- type colour, 0 = pure white); RIM_STRENGTH is how bright the edge goes.
    -- RIM_FALLOFF is how many pixels the glow takes to fade to nothing as it
    -- travels INWARD from the edge: 1 gives a hard one-pixel outline, while
    -- ~2.5 paints a short gradient that reads as an inner glow rather than a
    -- flat border (the silhouette itself is never touched -- see the pass).
    RIM_TINT = 0.35,
    RIM_STRENGTH = 0.90,
    RIM_FALLOFF = 2.5,
    -- STAR GLINTS.  The crystal reference is studded with bright FOUR-POINTED
    -- stars, and a one-pixel specular dot cannot carry that read at sprite
    -- scale -- a glint wants arms.  A pool of anchors is taken from the
    -- creature's own OPAQUE pixels, and the pool is picked toward the LIGHTEST
    -- shards and away from the bevel seams (see the anchor pick below the bake
    -- loop), so the sparkles appear all over the crystal's clearest, brightest
    -- planes.  Each anchor is stamped with a four-pointed sprite from
    -- STAR_SPRITES: {dx, dy, weight} offsets from the anchor, each blended
    -- toward white by its weight.  STAR_COUNT is how many to keep and
    -- STAR_SPACING the least distance between them as a share of the sprite's
    -- width (so they spread over the creature rather than clumping on one
    -- shine).
    --
    -- A SPARKLE IS MADE OF LIGHT, LAID OVER THE CRYSTAL.  Every weight is
    -- positive: a pixel is pulled toward white by its weight and keeps the rest
    -- of whatever facet sits under it, so the shard shows THROUGH the sparkle
    -- and the star only ever brightens.  An earlier version also deepened a ring
    -- around each star (a negative-weight halo) to separate it from the facet;
    -- on a light sky, gem or water tile that dark ring read as a dirty smudge
    -- around every glint, so the halo is gone.
    --
    -- STAR_SPRITE is which of the four sizes is stamped, counted in stamped
    -- pixels -- the footprint is what the eye reads.  All four are FOUR-POINTED
    -- STARS: a solid white heart at the centre and a bright first segment on
    -- each of the four arms, fading along a second (and, on the biggest, a
    -- third) segment, with NOTHING stamped on the diagonals.  The diagonals are
    -- what matter: filling them in is what used to round the sparkle off into a
    -- white blob, and leaving them empty lets the facet show through the gaps
    -- between the points.  1 is the smallest (a five-pixel plus), 2 the nine-
    -- pixel star and the default, 3 the thirteen-pixel, 4 the seventeen-pixel
    -- star whose tips have all but faded out.  A star is scaled with the bake's
    -- own magnification (see TERA.starsFor), so a sparkle is always the same
    -- size in the creature's own pixels.
    -- THE SPARKLES ARE THEIR OWN ANIMATION.  Instead of one fixed constellation
    -- stamped identically into every frame, each anchor is dealt a twinkle: a
    -- phase and a whole number of PULSES PER LOOP (STAR_MULT is the most it may
    -- get), both from the deterministic hash.  Its star is multiplied by a
    -- smooth pulse of that cycle, so as the sprite animates the lit stars keep
    -- changing -- blinking on and off all over the lightest facets, on a cycle
    -- of their own, rather than sitting still on the crystal.  Whole pulses per
    -- loop is what keeps the twinkle seamless when the animation wraps, and
    -- STAR_MIN is the pulse level below which a star is not stamped at all (so
    -- a nearly-dead twinkle leaves no faint grey residue on the facet).
    STAR_COUNT = 9,
    STAR_SPACING = 0.21,
    STAR_MULT = 2,
    STAR_SPRITE = 2,
    -- The pulse's shape: a sparkle is fully OFF while its pulse wave is below
    -- STAR_FLOOR, ramps up to full brightness at STAR_FULL, and holds there in
    -- between -- so each flame spends a clear stretch of the cycle blazing and a
    -- clear stretch dark, instead of hovering at half brightness all the time
    -- (which just reads as a permanently duller star).  STAR_MIN is the pulse
    -- level below which a star is not stamped at all, so a dying twinkle leaves
    -- no faint grey residue on the facet.
    STAR_FLOOR = 0.30,
    STAR_FULL = 0.75,
    STAR_MIN = 0.06,
    -- ANIMATION RIDE.  How many destination pixels the facet lattice (and every
    -- sparkle anchor with it) may be translated, as a rigid body, to follow the
    -- sprite's own motion across a sheet's frames.  The scan records each
    -- frame's content centroid and the bake shifts the whole crystal by that
    -- frame's displacement from the first frame's, so the facets travel WITH the
    -- creature instead of staying nailed to the box while it bobs underneath.
    -- It is also the width of the margin the lattice is cut with, so it must
    -- comfortably exceed the largest per-frame drift (a few pixels at native
    -- scale, times the bake's own scale).
    PAD = 12,
    STAR_SPRITES = {
      -- 1: the smallest star -- one pixel of light with a single short arm on
      -- each of its four sides.  A plus, and a quarter of the old burst.
      [1] = {
        {  0,  0, 1.00 },
        {  1,  0, 0.80 }, { -1,  0, 0.80 }, {  0,  1, 0.80 }, {  0, -1, 0.80 },
      },
      -- 2 (default): the four-pointed star -- a solid white heart, a bright
      -- first segment and a soft second on each arm, and nothing on the
      -- diagonals.  Nine pixels: the same stamp as the old compact sparkle, laid
      -- out as a star instead of a blob.
      [2] = {
        {  0,  0, 1.00 },
        {  1,  0, 0.82 }, { -1,  0, 0.82 }, {  0,  1, 0.82 }, {  0, -1, 0.82 },
        {  2,  0, 0.34 }, { -2,  0, 0.34 }, {  0,  2, 0.34 }, {  0, -2, 0.34 },
      },
      -- 3: the same star one segment longer on each arm (thirteen pixels).
      [3] = {
        {  0,  0, 1.00 },
        {  1,  0, 0.84 }, { -1,  0, 0.84 }, {  0,  1, 0.84 }, {  0, -1, 0.84 },
        {  2,  0, 0.52 }, { -2,  0, 0.52 }, {  0,  2, 0.52 }, {  0, -2, 0.52 },
        {  3,  0, 0.24 }, { -3,  0, 0.24 }, {  0,  3, 0.24 }, {  0, -3, 0.24 },
      },
      -- 4: one segment further again (seventeen pixels), its tips nearly gone.
      [4] = {
        {  0,  0, 1.00 },
        {  1,  0, 0.85 }, { -1,  0, 0.85 }, {  0,  1, 0.85 }, {  0, -1, 0.85 },
        {  2,  0, 0.58 }, { -2,  0, 0.58 }, {  0,  2, 0.58 }, {  0, -2, 0.58 },
        {  3,  0, 0.32 }, { -3,  0, 0.32 }, {  0,  3, 0.32 }, {  0, -3, 0.32 },
        {  4,  0, 0.16 }, { -4,  0, 0.16 }, {  0,  4, 0.16 }, {  0, -4, 0.16 },
      },
    },
  }

  -- ---------------------------------------------------------------------------
  -- DYNAMAX CLOUD (the red swirl above a Dynamaxed/Gigantamaxed Pokemon's head)
  -- ---------------------------------------------------------------------------
  -- A Dynamaxed or Gigantamaxed Pokemon wears the pack's own red cloud sprite
  -- above its head, like a crown.  It is baked INTO every frame (never a second
  -- draw pass), exactly like the Tera film and for the same reasons: it costs
  -- nothing per frame, cannot desync from -- or flicker with -- the frame clock,
  -- and follows the same nearest-neighbour resample as the sprite.
  --
  -- CLOUD_BAND is the share of the frame's height the cloud gets.  It is
  -- measured against the BOX in a fixed picture box (the cloud claims a band off
  -- the top and the sheet is fitted into the rest, so the cloud rides above the
  -- head and caps it without covering the face; a sprite short enough to already
  -- fit the remaining band is not shrunk at all) and against the SPRITE's own
  -- baked height in a custom screen's natural-size mode (whose canvas simply
  -- grows upward by the band, since there is no box to take it from).
  --
  -- The cloud is stored as one image with transparent margins; its content is
  -- measured once (loadCloud) and drawn anchored to the sprite's own content,
  -- so it sits over the head whatever the sheet's own padding happens to be.
  local CLOUD_BAND = 0.26
  local CLOUD_MIN_H = 5
  -- How far the cloud's bottom edge sinks BELOW the sprite's own content top.
  -- A crown rests ON the head rather than hovering above it, and this asset's
  -- lower ~40% is a thin, faint tail while its dense mass sits above that -- so
  -- sinking the whole bounding box by a fixed share of its height would leave
  -- the MASS bottom (the part the eye actually reads as "the cloud") level with
  -- the head, opening a visible gap wherever the arched mass climbs away from
  -- the head's narrow top.  So the sink is derived from the asset's own mass
  -- profile instead: CLOUD_MASS_BOT is the row (as a share of the cloud's
  -- height, measured from its bottom) at which the mass thins into that tail,
  -- and CLOUD_OVERLAP is how many pixels PAST the head the mass bottom lands,
  -- i.e. the amount the puffs overlap what they rest on.  At least one pixel
  -- always sinks.  (CLOUD_MASS_BOT is from this asset; a replacement cloud
  -- should have it re-measured -- it is the last row still holding >= ~40% of
  -- the cloud's widest row.)
  local CLOUD_MASS_BOT = 0.585
  local CLOUD_OVERLAP = 2
  local function cloudSink(h)
    local s = math.floor(h * (1 - CLOUD_MASS_BOT) + CLOUD_OVERLAP + 0.5)
    if s < 1 then s = 1 elseif s > h - 1 then s = h - 1 end
    return s
  end

  -- BIG is the default divisor (1); NORMAL and SMALL use 2 and 3.
  -- Retired MAX DETAIL (0) and missing values resolve to BIG. Preserve the
  -- older pixel-height settings through their existing divisor conversion.
  local LEGACY_SIZE_REF = FRONT_BOX.h
  local function spriteSizeMode()
    local n = tonumber(opt("sprite_size", 1))
    if not n then n = 1 end
    if n >= 8 then n = math.floor(n / LEGACY_SIZE_REF + 0.5) end
    if n < 1 then n = 1 end
    return n
  end
  -- Round half up (Lua 5.1/LuaJIT has no math.round).
  local function round(n) return math.floor(n + 0.5) end
  -- GROUND ANCHOR, as the three numeric values the option stores (0 FEET,
  -- 1 PACK, 2 BOX -- see OPTIONS).
  local ANCHOR_FEET, ANCHOR_PACK, ANCHOR_BOX = 0, 1, 2
  local function spriteAnchor()
    local n = tonumber(opt("sprite_anchor", ANCHOR_FEET))
    if not n then n = ANCHOR_FEET end
    n = math.floor(n)
    if n < ANCHOR_FEET then n = ANCHOR_FEET
    elseif n > ANCHOR_BOX then n = ANCHOR_BOX end
    return n
  end
  -- FLOATERS: in FEET mode, lift a floating sheet off the ground line.
  local function floatOn() return opt("sprite_float", true) ~= false end
  -- How far a floating sprite hovers, as a share of its own content height.
  -- FLOAT_LIFT x height, so a bigger flyer floats higher than a small one.
  -- Clamped to at least FLOAT_LIFT_MIN sheet pixels so even a tiny floater
  -- visibly lifts clear of the ground.
  local FLOAT_LIFT = 0.05
  local FLOAT_LIFT_MIN = 0.05
  -- The lift for one sheet, in SOURCE pixels (callers scale it with the bake).
  local function floatLift(stem, ch)
    if spriteAnchor() ~= ANCHOR_FEET or not floatOn() then return 0 end
    if not (FLOATERS and FLOATERS[stem]) then return 0 end
    local lift = math.floor((ch or 0) * FLOAT_LIFT + 0.5)
    if lift < FLOAT_LIFT_MIN then lift = FLOAT_LIFT_MIN end
    return lift
  end
  local function fpsValue()
    local n = tonumber(opt("sprite_fps", 12))
    if not n or n < 1 then n = 12 elseif n > 60 then n = 60 end
    return n
  end

  -- ---------------------------------------------------------------------------
  -- On-screen diagnostics (dormant -- see DEBUG_PANEL_ENABLED)
  -- ---------------------------------------------------------------------------
  -- The engine's in-game developer console is Gen 1 ONLY -- Gold exposes
  -- mod.developer but implements neither the console nor its hotkeys -- and
  -- mod.log lines go to stdout, which a player never sees.  So a mod that only
  -- logs is completely silent on exactly the build most players run.  The
  -- panel below paints a small box INTO the finished UI canvas from
  -- render.compose, so "no sheets in assets/" or "the battle screen never asked
  -- us" is readable on screen with no console at all.  It is switched off in
  -- shipped builds (DEBUG_PANEL_ENABLED = false, and there is no option row for
  -- it); flip the constant if the loader ever needs diagnosing again.
  local DIAG_MAX_EVENTS = 5
  local DIAG_MAX_CHARS = 31
  local DIAG_MAX_REASON_LINES = 3

  local diag = {
    on = false,
    lastFrame = -1,
    events = {},
    font = nil,
    fontH = 9,
    stats = { pics = 0, scene = 0, gen1 = 0, ready = 0, failed = 0, missing = 0, summary = 0, party = 0 },
    census = { front = 0, front_shiny = 0, back = 0, back_shiny = 0, shadow = 0 },
    inst = "none",
    gen = 0,
    summary = "none",
    lastResolve = nil,
    lastFail = nil,
    lastFailWhy = nil,
  }

  local function diagPush(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = tostring(fmt) end
    if #line > DIAG_MAX_CHARS then line = line:sub(1, DIAG_MAX_CHARS) end
    table.insert(diag.events, 1, line)
    while #diag.events > DIAG_MAX_EVENTS do table.remove(diag.events) end
  end

  local function diagGetFont()
    if diag.font then return diag.font, diag.fontH end
    local g = love and love.graphics
    if not g then return nil, 9 end
    local font
    if g.newFont then
      local ok, f = pcall(g.newFont, 8)
      if ok then font = f end
    end
    if not font and g.getFont then
      local ok, f = pcall(g.getFont)
      if ok then font = f end
    end
    if not font then return nil, 9 end
    diag.font = font
    if font.getHeight then
      local okH, h = pcall(font.getHeight, font)
      if okH and type(h) == "number" and h > 0 then diag.fontH = h + 1 end
    end
    return diag.font, diag.fontH
  end

  -- ---------------------------------------------------------------------------
  -- Mon inspection (works on both generations, defensively)
  -- ---------------------------------------------------------------------------
  local statsModule            -- cached require("src.pokemon.Stats"), or false
  local function shinyFromDvs(dvs)
    if statsModule == nil then
      local ok, m = pcall(require, "src.pokemon.Stats")
      statsModule = (ok and type(m) == "table") and m or false
    end
    if statsModule and statsModule.isShiny then
      local ok, shiny = pcall(statsModule.isShiny, dvs)
      if ok then return shiny and true or false end
    end
    return false
  end

  local function isShiny(mon)
    if type(mon) ~= "table" then return false end
    if GEN == 3 then
      local ok, P = pcall(require, "src.core.game3.pokemon")
      if ok and P and type(P.isShiny) == "function" then
        local success, shiny = pcall(P.isShiny, mon)
        if success then return not not shiny end
      end
      if mon.isShiny ~= nil then return not not mon.isShiny end
    end
    if mon.shiny ~= nil then return mon.shiny and true or false end
    if type(mon.dvs) == "table" then return shinyFromDvs(mon.dvs) end
    return false
  end

  local function isFemale(mon)
    if type(mon) ~= "table" then return false end
    local flag = mon.isFemale
    if type(flag) == "boolean" then return flag end
    local g = mon.gender or mon.sex
    if type(g) == "string" then
      g = g:lower()
      return g == "female" or g == "f"
    end
    return false
  end

  -- ---------------------------------------------------------------------------
  -- Species id -> DBK stem
  -- ---------------------------------------------------------------------------
  local function stripLastWord(name)
    local s = name:find("_[^_]*$")
    if not s then return nil end
    return name:sub(1, s - 1)
  end

  -- Walk the form suffix chain until a mapped, existing stem is found:
  -- KOMMO_O_TOTEM -> KOMMO_O -> KOMMOO (the pack drops underscores).
  local function baseStem(species)
    local name = species
    while true do
      name = stripLastWord(name)
      if not name then return nil end
      local stem = DATA.species[name]
      if stem and DATA.stems[stem] then return stem end
    end
  end

  -- Gen3Compat normally returns the registry key (FLABEBE), but an engine
  -- build may return the display name instead (FLABÃ©BÃ©).  Sprite data and
  -- filenames deliberately use ASCII identifiers, so fold the few accented
  -- Latin characters used by Pokemon names before trying the data table.
  -- Keep underscores because they separate form suffixes.
  DATA.canonicalSpeciesKey=assert((loadstring or load)(assert(mod:read('lib/species_key.lua'))))()
  local function canonicalSpeciesKey(species)return DATA.canonicalSpeciesKey(species)end

  -- Display names can use spaces and punctuation where registry ids use
  -- underscores (TYPE: NULL -> TYPE_NULL, HO-OH -> HO_OH, TAPU KOKO ->
  -- TAPU_KOKO).  Build an unpunctuated lookup from the authoritative sprite
  -- ids instead of maintaining a fragile list of one-off aliases.  If two ids
  -- ever collapse to different sheets, mark that spelling ambiguous.
  -- Cache this on DATA rather than adding another top-level local: this large
  -- component intentionally stays below Lua 5.1's 200-local function limit.
  local function resolveStem(species, style)
    if type(species) ~= "string" then return nil end
    if (style or DATA.spriteStyle()) == 3 or (style or DATA.spriteStyle()) == 4 then
      local overrides = DATA.ee and DATA.ee.species or {}
      local eeStem = overrides[species] or overrides[canonicalSpeciesKey(species)]
      if eeStem and DATA.stems[eeStem] then return eeStem end
    end
    local stem = DATA.species[species]
    if not (stem and DATA.stems[stem]) then
      local key = canonicalSpeciesKey(species)
      if key and key ~= species then stem = DATA.species[key] end
    end
    if not (stem and DATA.stems[stem]) and not DATA.__collapsedSpecies then
      DATA.__collapsedSpecies = {}
      for id, mapped in pairs(DATA.species) do
        local key = canonicalSpeciesKey(id)
        key = key and key:gsub("_", "") or nil
        if key then
          local old = DATA.__collapsedSpecies[key]
          if old == nil or old == mapped then
            DATA.__collapsedSpecies[key] = mapped
          else
            DATA.__collapsedSpecies[key] = false
          end
        end
      end
    end
    if not (stem and DATA.stems[stem]) then
      local key = canonicalSpeciesKey(species)
      key = key and key:gsub("_", "") or nil
      stem = key and DATA.__collapsedSpecies[key] or nil
    end
    if not (stem and DATA.stems[stem]) then stem = baseStem(species) end
    if stem and DATA.stems[stem] then return stem end
    return nil
  end

  local function femaleStem(stem, style)
    if (style or DATA.spriteStyle()) == 3 or (style or DATA.spriteStyle()) == 4 then
      local files = DATA.ee and DATA.ee.files.front or {}
      if files[stem .. "_female"] then return stem .. "_female" end
    end
    if DATA.female[stem] then return stem .. "_female" end
    return stem
  end

  -- Resolve a live mon to (stem, shiny) for the given side.
  local function monStem(mon, style)
    if type(mon) ~= "table" then return nil end
    local species = mon.species
    if type(species) == "number" then
      local ok, Compat = pcall(require, "src.mods.Gen3Compat")
      if ok and Compat and Compat.speciesName then
        species = Compat.speciesName(species)
      end
    end
    local stem = resolveStem(species, style)
    if not stem then return nil end
    if wantFemale() and isFemale(mon) then stem = femaleStem(stem, style) end
    local shiny = false
    if wantShiny() then shiny = isShiny(mon) end
    return stem, shiny
  end

  -- ---------------------------------------------------------------------------
  -- PNG -> ImageData
  -- ---------------------------------------------------------------------------
  -- A mod cannot assume any single decode route works on a given build, so a
  -- sheet is decoded through up to three of them, cheapest first:
  --
  --   A. straight from the mod's own folder with the engine's path helper --
  --      love.image.newImageData(mod.assets:path(rel)).  This is the call
  --      mod.assets:image makes and what every image-loading mod uses.
  --   B. the file bytes copied into a FileData and decoded from that
  --      (love.data.newFileData, or the 0.10 love.filesystem equivalent).  It
  --      needs no path but does need a working byte -> FileData constructor.
  --   C. love.graphics.newImage(path):getData() -- a detour through the GPU,
  --      kept as a last resort for a build with graphics but no usable image
  --      decoder.
  --
  -- Route A is tried first: it is the shortest path to a decoder and the one
  -- the engine itself blesses.  Every route's failure is reported, so the DEBUG
  -- panel can say exactly what went wrong instead of the mod simply looking
  -- dead.
  local function assetPath(rel)
    local assets = mod.assets
    if not (assets and type(assets.path) == "function") then return nil end
    local ok, full = pcall(assets.path, assets, rel)
    if ok and type(full) == "string" and full ~= "" then return full end
    return nil
  end

  local function decodeFromPath(rel)
    local img = love and love.image
    if not (img and img.newImageData) then return nil, "no love.image" end
    local full = assetPath(rel)
    if not full then return nil, "no mod.assets:path" end
    local ok, id = pcall(img.newImageData, full)
    if ok and id then return id end
    return nil, "newImageData(path): " .. tostring(ok and "nil" or id)
  end

  local function decodeFromImage(rel)
    local g = love and love.graphics
    if not (g and g.newImage) then return nil, "no love.graphics" end
    local full = assetPath(rel)
    if not full then return nil, "no mod.assets:path" end
    local ok, img = pcall(g.newImage, full)
    if not (ok and img) then
      return nil, "newImage: " .. tostring(ok and "nil" or img)
    end
    if type(img.getData) ~= "function" then return nil, "Image has no getData" end
    local okd, id = pcall(img.getData, img)
    if okd and id then return id end
    return nil, "Image:getData: " .. tostring(okd and "nil" or id)
  end

  local function decodeFromBytes(bytes, stem)
    local img = love and love.image
    if not (img and img.newImageData) then return nil, "no love.image" end
    if type(bytes) ~= "string" or #bytes == 0 then return nil, "no bytes" end
    local fd
    local dm = love and love.data
    if dm and dm.newFileData then
      local ok, res = pcall(dm.newFileData, bytes, stem .. ".png")
      if ok and res then fd = res end
    end
    if not fd then
      local fsmod = love and love.filesystem
      if fsmod and fsmod.newFileData then
        local ok, res = pcall(fsmod.newFileData, bytes, stem .. ".png")
        if ok and res then fd = res end
      end
    end
    if not fd then
      if not (dm and dm.newFileData)
        and not (love.filesystem and love.filesystem.newFileData) then
        return nil, "no FileData constructor"
      end
      return nil, "FileData not accepted"
    end
    local ok, id = pcall(img.newImageData, fd)
    if ok and id then return id end
    return nil, "newImageData(FileData): " .. tostring(ok and "nil" or id)
  end

  -- Decode one sheet through the routes above, reporting which one won (or why
  -- every available route failed).
  local function decodeSheet(sheet)
    if sheet.kimData then local data=sheet.kimData;sheet.kimData=nil;return data,'KIM' end
    if sheet.bwPeer then
      local ok, data = pcall(sheet.bwPeer.decodeSprite, sheet.bwFolder, sheet.sourceStem)
      if ok and data then return data, "BW ROM" end
      return nil, "BW ROM decode failed: " .. tostring(data)
    end
    local reasons = {}
    if sheet.rel then
      local id, why = decodeFromPath(sheet.rel)
      if id then return id, "path" end
      reasons[#reasons + 1] = "A " .. tostring(why)
    end
    -- The byte route needs the file contents; read them now and only now, so a
    -- big sheet is not held in memory when the path route already worked.
    if not sheet.bytes and sheet.rel then
      local okr, bytes = pcall(mod.read, mod, sheet.rel)
      if okr and type(bytes) == "string" and #bytes > 0 then sheet.bytes = bytes end
    end
    local idb, whyb = decodeFromBytes(sheet.bytes, sheet.stem)
    if idb then return idb, "bytes" end
    reasons[#reasons + 1] = "B " .. tostring(whyb)
    if sheet.rel then
      local idc, whyc = decodeFromImage(sheet.rel)
      if idc then return idc, "image" end
      reasons[#reasons + 1] = "C " .. tostring(whyc)
    end
    sheet.bytes = nil
    return nil, table.concat(reasons, " | ")
  end

  -- ---------------------------------------------------------------------------
  -- The crystal pattern (assets/tera_crystal.png)
  -- ---------------------------------------------------------------------------
  -- A Terastallized Pokemon's film is the pattern's own facets, colourised by
  -- the Tera type.  The pattern is decoded once, through the same routed
  -- decoders a sheet uses, and its luminance range is measured once (a strided
  -- sample is plenty -- only the two stretch endpoints are wanted, and a stride
  -- makes that a few thousand pixels instead of half a million).  A missing or
  -- unreadable pattern is not fatal: TERA ART simply does nothing, which is why
  -- this never stops the mod from loading.
  local PATTERN = nil
  local patternTried = false
  local function loadPattern()
    if PATTERN or patternTried then return PATTERN end
    patternTried = true
    local rel = "assets/tera_crystal.png"
    local id, why = decodeFromPath(rel)
    if not id then
      local okr, bytes = pcall(mod.read, mod, rel)
      if okr and type(bytes) == "string" and #bytes > 0 then
        local idb, whyb = decodeFromBytes(bytes, "tera_crystal")
        if idb then id = idb else why = whyb end
      end
    end
    if not id then
      local idc, whyc = decodeFromImage(rel)
      if idc then id = idc else why = whyc end
    end
    if not id or type(id.getDimensions) ~= "function" then
      mod.log:warn("g9-battle-sprites: assets/tera_crystal.png could not be "
        .. "read (%s) -- TERA ART will do nothing", tostring(why))
      return nil
    end
    local w, h = id:getDimensions()
    if w < 2 or h < 2 then return nil end
    local lo, hi = 1, 0
    local step = (w < 64) and 1 or 4
    for y = 0, h - 1, step do
      for x = 0, w - 1, step do
        local pr, pg, pb = id:getPixel(x, y)
        local L = (pr + pg + pb) / 3
        if L < lo then lo = L end
        if L > hi then hi = L end
      end
    end
    if hi - lo < 0.01 then lo, hi = 0, 1 end
    PATTERN = { id = id, w = w, h = h, lo = lo, span = hi - lo }
    mod.log:info("g9-battle-sprites: tera crystal pattern %dx%d ready "
      .. "(luma %.3f..%.3f)", w, h, lo, hi)
    return PATTERN
  end

  -- The Dynamax cloud sprite (assets/dynamax_cloud.png).  Decoded through the
  -- same three routes as every other asset, and its own CONTENT box is measured
  -- once (the file ships with transparent margins), so the cloud can be anchored
  -- to whatever it actually covers rather than to its padded frame.  A missing
  -- or unreadable cloud is not fatal: DYNAMAX CLOUD simply does nothing, which
  -- is why this never stops the mod from loading.
  local CLOUD = nil
  local cloudTried = false
  local function loadCloud()
    if CLOUD or cloudTried then return CLOUD end
    cloudTried = true
    local rel = "assets/dynamax_cloud.png"
    local id, why = decodeFromPath(rel)
    if not id then
      local okr, bytes = pcall(mod.read, mod, rel)
      if okr and type(bytes) == "string" and #bytes > 0 then
        local idb, whyb = decodeFromBytes(bytes, "dynamax_cloud")
        if idb then id = idb else why = whyb end
      end
    end
    if not id then
      local idc, whyc = decodeFromImage(rel)
      if idc then id = idc else why = whyc end
    end
    if not id or type(id.getDimensions) ~= "function" then
      mod.log:warn("g9-battle-sprites: assets/dynamax_cloud.png could not be "
        .. "read (%s) -- DYNAMAX CLOUD will do nothing", tostring(why))
      return nil
    end
    local w, h = id:getDimensions()
    if w < 2 or h < 2 then return nil end
    -- Exact content box: the cloud's own outline, transparent margins dropped.
    -- Every pixel is read (once per session), because a bbox is only correct if
    -- its edges are exact -- an off-by-a-stride here would clip or offset the
    -- cloud by the sampled step.
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local a = select(4, id:getPixel(x, y))
        if a and a > 0 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    if x1 < x0 or y1 < y0 then
      mod.log:warn("g9-battle-sprites: assets/dynamax_cloud.png has no opaque "
        .. "pixels -- DYNAMAX CLOUD will do nothing")
      return nil
    end
    CLOUD = { id = id, x0 = x0, y0 = y0, cw = x1 - x0 + 1, ch = y1 - y0 + 1 }
    mod.log:info("g9-battle-sprites: dynamax cloud %dx%d ready (%dx%d content)",
      w, h, CLOUD.cw, CLOUD.ch)
    return CLOUD
  end

  -- The cloud, downsampled to a destination size and cached per size.
  -- The cloud art is large (hundreds of pixels across) and is drawn only a few
  -- dozen pixels wide, so a nearest-neighbour shrink -- right for the sprite art
  -- itself, which keeps its hard pixel edges -- would skip over most of the
  -- cloud's wispy rows and columns and punch holes in it, leaving a spray of
  -- dropped pixels where a solid crown should be.  So the cloud is instead
  -- AREA-filtered: every destination pixel averages the whole block of source
  -- pixels it covers (alpha-weighted, with the average alpha as its coverage),
  -- which keeps the silhouette solid and its full extent intact.  The result
  -- depends only on the source, the content box and the destination size, so it
  -- is computed once per size and reused by every frame and every sheet.
  local function cloudScaled(c, cW, cH)
    c.scaled = c.scaled or {}
    local key = cW .. "x" .. cH
    local got = c.scaled[key]
    if got then return got end
    local px = {}
    local stepX, stepY = c.cw / cW, c.ch / cH
    local lastX, lastY = c.x0 + c.cw - 1, c.y0 + c.ch - 1
    for ty = 0, cH - 1 do
      local sy0 = c.y0 + math.floor(ty * stepY)
      local sy1 = c.y0 + math.ceil((ty + 1) * stepY) - 1
      if sy0 < c.y0 then sy0 = c.y0 end
      if sy1 > lastY then sy1 = lastY end
      for tx = 0, cW - 1 do
        local sx0 = c.x0 + math.floor(tx * stepX)
        local sx1 = c.x0 + math.ceil((tx + 1) * stepX) - 1
        if sx0 < c.x0 then sx0 = c.x0 end
        if sx1 > lastX then sx1 = lastX end
        local ar, ag, ab, aw, n = 0, 0, 0, 0, 0
        for sy = sy0, sy1 do
          for sx = sx0, sx1 do
            n = n + 1
            local r, g, bl, a = c.id:getPixel(sx, sy)
            a = a or 0
            if a > 0 then
              ar, ag, ab, aw = ar + r * a, ag + g * a, ab + bl * a, aw + a
            end
          end
        end
        local o = (ty * cW + tx) * 4
        if aw > 0 and n > 0 then
          local ca = aw / n
          if ca > 1 then ca = 1 end
          px[o + 1], px[o + 2], px[o + 3], px[o + 4] = ar / aw, ag / aw, ab / aw, ca
        else
          px[o + 1], px[o + 2], px[o + 3], px[o + 4] = 0, 0, 0, 0
        end
      end
    end
    local img = { w = cW, h = cH, px = px }
    c.scaled[key] = img
    return img
  end

  -- ---------------------------------------------------------------------------
  -- BATTLE SHADOWS (the contact shadow under every battler)
  -- ---------------------------------------------------------------------------
  -- The game's own battle screens draw no shadow at all, so the mod supplies
  -- one from the game's own shadow art (assets/shadow/1.png, 2.png and 3.png --
  -- the small, medium and large contact shadows from La Base de Sky's
  -- Graphics/Pokemon/Shadow folder).  A species is resolved in two steps, the
  -- way Essentials' own shadow_filename does it: a file named for the sheet's
  -- stem (assets/shadow/<STEM>.png) wins, and otherwise the generic art is
  -- chosen by the pack's ShadowSize -- clamped to the three files -- with
  -- ShadowSize 0 meaning "no shadow".  The pack's ShadowSprite x offset nudges
  -- the shadow sideways; its second/third values are ally/enemy y offsets and
  -- are deliberately unused, because a baked shadow is always pinned to the
  -- ground line (a floating mon's shadow belongs on the ground, not on the
  -- Pokemon).
  --
  -- The art's content box is measured once (the files carry a thin transparent
  -- rim) and the shadow is composited BEHIND the sprite by buildOneFrame --
  -- never as a second draw pass -- so it rides the animation and can never
  -- flicker with the frame clock.
  local SHADOW = (function()
  local SHADOW_W_BASE = 0.55  -- width share of the sprite at the default ShadowSize 1
  local SHADOW_W_STEP = 0.10  -- added per +1 ShadowSize (2 -> 0.65, 3 -> 0.75 ...)
  local SHADOW_W_NEG = 0.05   -- removed per -1 ShadowSize (-1 -> 0.50, -2 -> 0.45 ...)
  local SHADOW_W_MIN = 0.15
  local SHADOW_W_MAX = 1.00
  local SHADOW_CACHE = {}     -- rel -> art table, or false once it has failed
  local SHADOW_STEMS = nil    -- set of stems with a species-specific shadow file
  local function shadowStems()
    if SHADOW_STEMS then return SHADOW_STEMS end
    local set = {}
    if type(mod.list) == "function" then
      local ok, names = pcall(mod.list, mod, "assets/shadow")
      if ok and type(names) == "table" then
        for _, n in ipairs(names) do
          if type(n) == "string" and n:sub(-4):lower() == ".png" then
            set[n:sub(1, -5)] = true
          end
        end
      end
    end
    SHADOW_STEMS = set
    return set
  end

  local function shadowArtFor(rel)
    local cached = SHADOW_CACHE[rel]
    if cached ~= nil then return cached or nil end
    local id, why = decodeFromPath(rel)
    if not id then
      local okr, bytes = pcall(mod.read, mod, rel)
      if okr and type(bytes) == "string" and #bytes > 0 then
        local idb, whyb = decodeFromBytes(bytes, "shadow")
        if idb then id = idb else why = whyb end
      end
    end
    if not id then
      local idc, whyc = decodeFromImage(rel)
      if idc then id = idc else why = whyc end
    end
    local art = false
    if id and type(id.getDimensions) == "function" then
      local w, h = id:getDimensions()
      if w and h and w >= 2 and h >= 2 then
        local x0, y0, x1, y1 = w, h, -1, -1
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local a = select(4, id:getPixel(x, y))
            if a and a > 0 then
              if x < x0 then x0 = x end
              if x > x1 then x1 = x end
              if y < y0 then y0 = y end
              if y > y1 then y1 = y end
            end
          end
        end
        if x1 >= x0 and y1 >= y0 then
          art = { id = id, x0 = x0, y0 = y0, cw = x1 - x0 + 1, ch = y1 - y0 + 1 }
        end
      end
    end
    SHADOW_CACHE[rel] = art
    if not art then
      mod.log:warn("g9-battle-sprites: shadow art %s could not be read (%s)",
        rel, tostring(why))
    end
    return art or nil
  end

  -- Resolve a stem's shadow once (art + the pack's ShadowSize).  `nil` art is a
  -- valid, cached answer for "this species casts no shadow" (ShadowSize 0, or
  -- no usable art), so the lookup is paid once per sheet, never per frame.
  local SHADOW_META = {}
  local function loadShadow(stem)
    local got = SHADOW_META[stem]
    if got ~= nil then return got.art, got.size end
    local m = METRICS and METRICS[stem]
    local size = (m and m.sz) or 1
    local art = nil
    if size ~= 0 then
      if shadowStems()[stem] then
        art = shadowArtFor("assets/shadow/" .. stem .. ".png")
      end
      if not art then
        local idx = size
        if idx < 1 then idx = 1 elseif idx > 3 then idx = 3 end
        art = shadowArtFor("assets/shadow/" .. idx .. ".png")
      end
    end
    SHADOW_META[stem] = { art = art, size = size }
    return art, size
  end

  -- A shadow is composited BEHIND the sprite, in the frame's own canvas: the
  -- ground line is the canvas bottom (the anchor every battle screen draws to),
  -- so the shadow's bottom sits there and it rises into the sprite's lower body,
  -- which occludes its middle exactly as feet should.  This is an ordinary
  -- `sprite OVER shadow` composite applied per pixel after the sprite's own
  -- pixels are down: a transparent sprite pixel lets the shadow through, an
  -- opaque one keeps the art, and the art's soft edge blends.  Nothing outside
  -- the box is touched, so a shadow wider than its box is clipped like the
  -- sprite itself.
  local function stampShadow(b, out)
    local art = b.shadowArt
    if not art then return end
    local box = b.box
    local sz = b.shadowSize or 1
    local frac
    if sz >= 1 then frac = SHADOW_W_BASE + (sz - 1) * SHADOW_W_STEP
    else frac = SHADOW_W_BASE + sz * SHADOW_W_NEG end
    if frac < SHADOW_W_MIN then frac = SHADOW_W_MIN
    elseif frac > SHADOW_W_MAX then frac = SHADOW_W_MAX end
    local sW = round((b.dw or 1) * frac)
    if sW < 3 then sW = 3 end
    local s = sW / art.cw
    local sH = math.max(1, round(art.ch * s))
    -- Horizontal centre: the sprite content's own centre, plus the pack's
    -- ShadowSprite x offset converted exactly like the sprite alignment (x2
    -- screen px over the pack's render scale, then scaled with the sheet).
    local div = b.back and BACK_SCALE or FRONT_SCALE
    local shX = ((b.shadowSx or 0) * 2) / div * (b.scale or 1)
    local left = round(b.ox + (b.dw or 0) / 2 + shX - sW / 2)
    local bottom = box.h - 1
    local top = bottom - sH + 1
    local maxX = box.w - 1
    for ty = 0, sH - 1 do
      local py = top + ty
      if py >= 0 and py <= bottom then
        local sy = art.y0 + math.min(art.ch - 1, math.floor(ty / s))
        for tx = 0, sW - 1 do
          local px = left + tx
          if px >= 0 and px <= maxX then
            local sx = art.x0 + math.min(art.cw - 1, math.floor(tx / s))
            local sr, sg, sb, sa = art.id:getPixel(sx, sy)
            sa = sa or 0
            if sa > 0 then
              local er, eg, eb, ea = out:getPixel(px, py)
              ea = ea or 0
              local oa = ea + sa * (1 - ea)
              if oa > 0 then
                out:setPixel(px, py,
                  (er * ea + sr * sa * (1 - ea)) / oa,
                  (eg * ea + sg * sa * (1 - ea)) / oa,
                  (eb * ea + sb * sa * (1 - ea)) / oa,
                  oa)
              end
            end
          end
        end
      end
    end
  end

  local function shadowsOn() return opt("battle_shadows", true) ~= false end

  return { on = shadowsOn, load = loadShadow, stamp = stampShadow }
  end)()


  -- ---------------------------------------------------------------------------
  -- Tera state (read live from the battle_forms mod)
  -- ---------------------------------------------------------------------------
  -- battle_forms owns Terastallization; this mod only READS it.  Its exports
  -- answer `describe(mon, battler)`, whose payload carries `tera` -- populated
  -- only while the Pokemon is Terastallized right now -- with the live Tera type
  -- id, plus `teraType` (what it WOULD Tera into).  Only the live one paints:
  -- teraType is a property a Pokemon has whether or not it ever transforms, and
  -- a film on a Pokemon that has not Terastallized yet would simply be wrong.
  --
  -- The lookup is deliberately forgiving.  battle_forms is optional, may arrive
  -- after this mod, and may be an older build, so a missing handle, a missing
  -- export, a raised error or a missing field all answer nil (= no film) rather
  -- than breaking a battle.  The handle is cached on success only, so a mod that
  -- loads late is still picked up on the next call.
  local formsPeer = nil
  local function formsExports()
    if formsPeer then return formsPeer end
    if type(mod.find) ~= "function" then return nil end
    local ok, handle = pcall(mod.find, mod, "battle_forms")
    if ok and type(handle) == "table" and type(handle.exports) == "table" then
      formsPeer = handle.exports
    end
    return formsPeer
  end

  -- Normalise one type id into the key TERA_TINT is indexed by, or nil.  Ids
  -- arrive in more than one spelling across this ecosystem -- the national dex
  -- says "WATER", Gen 1 says "Water", and a few carry the engine's own
  -- "PSYCHIC_TYPE" -- so the lookup upper-cases and strips the engine's "_TYPE"
  -- suffix before the table is consulted.  An unmapped type (??? and any
  -- future id) draws nothing at all, which is why the table is checked here
  -- rather than letting the bake fail later.
  local function teraKeyFor(id)
    if type(id) ~= "string" or id == "" then return nil end
    local key = id:upper():gsub("_TYPE$", "")
    if not TERA_TINT[key] then return nil end
    return key
  end

  local function teraTypeOf(mon, battler)
    if not teraArtOn() then return nil end
    local exports = formsExports()
    if not (exports and type(exports.describe) == "function") then return nil end
    local ok, payload = pcall(exports.describe, mon, battler)
    if not (ok and type(payload) == "table") then return nil end
    local live = payload.tera
    if type(live) ~= "table" then return nil end
    return teraKeyFor(live.type or payload.teraType)
  end

  -- ---------------------------------------------------------------------------
  -- Dynamax state (read live from the battle_forms mod)
  -- ---------------------------------------------------------------------------
  -- battle_forms owns Dynamax and Gigantamax end to end; this mod only READS
  -- it, through the same `describe(mon, battler)` payload the Tera state comes
  -- from.  That payload carries `dynamax` -- populated ONLY while the Pokemon
  -- is Dynamaxed right now, and nil otherwise -- as { turns, form }: `form` is
  -- the Gigantamax shape's own suffix, or nil for a plain Dynamax.  Both are a
  -- real answer here (a Gigantamax IS a Dynamax with a form laid on it), so the
  -- test is simply "is `dynamax` a table", and the cloud covers both.
  --
  -- `dynamaxLevel` is deliberately NOT the test: it is a persistent per-mon
  -- property (0-10) that every Pokemon has whether or not it ever transforms,
  -- so clouding on it would put a cloud over Pokemon that never Dynamaxed.
  --
  -- The lookup is as forgiving as the Tera one and for the same reason:
  -- battle_forms is optional, may arrive after this mod, and may be an older
  -- build, so a missing handle/export, a raised error or a missing field all
  -- answer false (= no cloud) rather than breaking a draw.
  local function dynamaxOf(mon, battler)
    if not dynamaxOn() then return false end
    local exports = formsExports()
    if not (exports and type(exports.describe) == "function") then return false end
    local ok, payload = pcall(exports.describe, mon, battler)
    if not (ok and type(payload) == "table") then return false end
    return type(payload.dynamax) == "table"
  end

  -- ---------------------------------------------------------------------------
  -- Declared raid gimmick (read from the custom screen itself)
  -- ---------------------------------------------------------------------------
  -- The live state above is the only thing that paints a film for a WILD boss:
  -- battle_forms only ever ACTIVATES a gimmick on the player's side, and the
  -- scene deliberately stores a raid boss's tera type / Dynamax level without
  -- turning it on (special_boss.lua's own header says so).  A raid boss is
  -- therefore announced -- "You have found a Tera WATER Krabby raid!" -- but
  -- drawn ordinary, i.e. the announcement and the sprite disagree.
  --
  -- g9-Battle-Scene closes that gap by handing this mod the declaration it has
  -- already stamped on the battle (battle.g9BossKind = { kind, detail }),
  -- carried on the boss battler as `g9RaidGimmick` and forwarded as ctx.boss /
  -- ctx.bossGimmick.  This is a VISUAL fallback only: it never activates the
  -- gimmick, never touches the mon, and is consulted only when the live lookup
  -- found nothing -- so a real terastallized/Dynamaxed Pokemon is still painted
  -- from its live state, and a screen that sends no declaration behaves exactly
  -- as before.  Raised as nil for anything that is not a table on the boss slot.
  local function declaredGimmickOf(ctx)
    if not (type(ctx) == "table" and ctx.boss) then return nil end
    local info = ctx.bossGimmick
    if type(info) ~= "table" then return nil end
    return info
  end

  -- ---------------------------------------------------------------------------
  -- Sheet store
  -- ---------------------------------------------------------------------------
  local sheets = {}          -- key -> record
  local readyCount = 0
  local frameCounter = 0
  -- Weak keys: an evicted sheet's frame Images must be collectable even though
  -- every frame we mark was registered here.
  local ourFrames = setmetatable({}, { __mode = "k" })
  -- Stable across every frame: the union bounds are known before baking.
  -- Battle placement reads this metadata; menus still receive the same art.
  local gen3BattleLiftByImage = setmetatable({}, { __mode = "k" })

  local function sheetKey(back, shiny, stem, box, divisor, zoom, maxH, fill, scale, natural, tera, cloud, shadow, front, flip)
    local tag = box and ("@" .. box.w .. "x" .. box.h) or ""
    -- The uniform scale (divisor) and the integer zoom the screen will draw
    -- the baked box at belong in the identity too: they decide how every
    -- frame is resampled, so a sheet baked for one screen's scale must
    -- never be handed to a screen asking for another (see setupFrames).
    local div = divisor and ("d" .. divisor) or ""
    local z = (zoom and zoom ~= 1) and ("z" .. zoom) or ""
    -- An EXPLICIT field scale (see setupFrames path 0) is likewise part of
    -- the identity: a sheet baked at 2x is not the sheet a screen asking
    -- for 3.2x should be handed.
    local sc = scale and ("x" .. scale) or ""
    -- maxH (the on-screen pixels a sprite may rise above its own ground
    -- line) also changes the bake: a sheet folded to fit a short band must
    -- not be reused where there is more headroom.
    local m = maxH and ("m" .. math.floor(maxH + 0.5)) or ""
    -- fill (may the sheet grow past native to fill its box?) decides the
    -- scale too, so it is part of the identity.
    local f = fill and "F" or ""
    -- NATURAL mode (see setupFrames path 0n) bakes the sheet at exactly its
    -- own scaled size with no box at all, so a natural bake must never be
    -- handed to a caller that asked for a box, or vice versa.
    local nat = natural and "R" or ""
    -- TERA ART bakes the crystal film into the frame, so the Tera type is part
    -- of the identity: the plain sheet and each type's filmed sheet are
    -- different Images and must never be handed to one another.
    local te = tera and ("T" .. tera) or ""
    -- DYNAMAX CLOUD is likewise part of the identity: a clouded sheet is a
    -- different Image from the plain one, and must never be handed to a reader
    -- of the other.
    local cl = cloud and "D" or ""
    -- BATTLE SHADOWS is likewise part of the identity: a shadowed sheet is a
    -- different Image from the plain one (and is only ever asked for in battle,
    -- so the dex/summary keep the plain sheet for the same box).
    local sh = shadow and "H" or ""
    -- -- 3DB FRONTAL / 3DB FLIP (options) -----------------------------------
    -- A back slot asked to draw the FRONT sheet (3DB FRONTAL) is a different
    -- Image from the ordinary back sheet, and a horizontally mirrored sheet
    -- (3DB FLIP) is different again, so both are part of the identity: none of
    -- them may ever be handed to a reader of another.  "P" = front art in a
    -- back slot (the sheet's own "b" prefix still marks the SLOT, so a
    -- front-sourced player sheet reads as "bP", never colliding with a real
    -- front sheet's "f"); "Y" = mirrored across the vertical axis.
    local fr = front and "P" or ""
    local fl = flip and "Y" or ""
    return "s" .. DATA.styleFor(back, shadow) .. (back and "b" or "f") .. (shiny and "s" or "n") .. tag .. div .. z .. sc .. m .. f .. nat .. te .. cl .. sh .. fr .. fl .. "/" .. stem
  end

  -- The pic box a sheet is baked into.  `override` lets a custom battle screen
  -- name the exact pixel box it will draw the pic into (see the battle.mon_pic
  -- wrap), so its own draw becomes a 1:1 blit instead of a fractional resample.
  local function boxFor(back, override)
    if override then return override end
    if GEN == 3 then return back and BACK_BOX_GEN3 or FRONT_BOX_GEN3 end
    if not back then return FRONT_BOX end
    if GEN == 2 then return BACK_BOX_GEN2 end
    return BACK_BOX_GEN1
  end

  local function now()
    local t = love and love.timer and love.timer.getTime
    if t then
      local ok, v = pcall(t)
      if ok and v then return v end
    end
    return frameCounter / 60
  end

  -- -- shared sheet lifecycle ---------------------------------------------
  -- (declared ahead of the builder that calls them)

  local function finishFailed(sheet, why)
    -- A file that is present but unusable (corrupt, or a sheet with no opaque
    -- pixels).  Say so out loud and latch it: a sheet that silently never
    -- arrives looks exactly like the mod not working at all.
    sheet.build = nil
    sheet.bytes = nil
    sheet.status = "failed"
    diag.stats.failed = diag.stats.failed + 1
    diag.lastFail = tostring(sheet.stem)
    diag.lastFailWhy = tostring(why)
    diagPush("%s BUILD FAIL", sheet.stem)
    mod.log:warn("g9-battle-sprites: %s could not be used (%s) -- "
      .. "falling back to the vanilla pic", sheet.stem, tostring(why))
  end

  local function finishReady(sheet, how)
    sheet.status = "ready"
    sheet.lastUsed = frameCounter
    readyCount = readyCount + 1
    diag.stats.ready = diag.stats.ready + 1
    diagPush("%s READY %df", sheet.stem,
      sheet.frameCount or #(sheet.frames or {}))
    mod.log:info("g9-battle-sprites: %s ready (%d frames, %s)",
      sheet.stem, sheet.frameCount or #(sheet.frames or {}), how)
  end

  -- -- frame builder ------------------------------------------------------
  -- Building is split into small steps; stepFrames() runs a bounded number of
  -- them per core.update so a 40-frame sheet never blocks a frame.  Phase 1
  -- scans the sheet once for the union content bbox (across EVERY frame, so the
  -- sprite never jitters from frame to frame); phase 2 lays out the destination
  -- rect (setupFrames: one integer divisor + the pack's alignment offsets) and
  -- bakes each frame by NEAREST-NEIGHBOUR resampling on a whole-number grid.
  -- Two things keep the art crisp.  First, the resize is by an integer factor
  -- (setupFrames), so every destination pixel steps the same whole number of
  -- source pixels and every block stays square; a fractional factor is what
  -- makes pixel-art pixels come out uneven and eats diagonals.  Second, the
  -- sample takes the nearest source pixel rather than averaging the covered
  -- ones: a box filter turns the pack's art into a soft, muddy smear that reads
  -- as "blurry" next to the game's crisp pixel UI, whereas the nearest source
  -- pixel keeps hard edges.  A destination pixel whose nearest source pixel is
  -- transparent borrows the nearest OPAQUE pixel from the area it covers, so a
  -- one-pixel outline or antenna is never punched out by the sampling stride.

  local function beginBuild(sheet, imageData)
    local W, H = imageData:getDimensions()
    if H < 1 or W < 1 then return false end
    local count = sheet.kimRecord and sheet.kimRecord.count or math.max(1, math.floor((W + H / 2) / H))
    if sheet.static and W ~= H then return false end
    if sheet.static then count = 1 end
    local fw = math.floor(W / count)
    if fw < 1 then return false end
    -- EE STATIC selects the first pose, including matching-art fallbacks.
    if sheet.style == 4 then W, count = fw, 1 end
    -- Resolve the crystal film once, here, rather than per frame: the pattern
    -- is decoded and measured on first use, and a type with no colour (or a
    -- missing pattern) bakes a plain sheet, exactly as if TERA ART were off.
    local tera
    if sheet.tera then
      local pat = loadPattern()
      local tint = TERA_TINT[sheet.tera]
      if pat and tint then tera = { pat = pat, tint = tint } end
    end
    -- DYNAMAX CLOUD: the cloud sprite is resolved once here too (see loadCloud).
    -- A missing cloud file simply leaves the sheet plain, exactly as if DYNAMAX
    -- CLOUD were off.
    local cloud
    if sheet.cloud then
      local c = loadCloud()
      if c then cloud = c end
    end
    -- BATTLE SHADOWS: resolved once per sheet too.  Only a battle seam sets
    -- sheet.shadow (see getBattleFrames), so the dex and summary never bake a
    -- shadow even when they ask for the very same box.
    local shadowArt, shadowSize, shadowSx
    if sheet.shadow and SHADOW.on() then
      shadowArt, shadowSize = SHADOW.load(sheet.stem)
      local m = METRICS and METRICS[sheet.stem]
      shadowSx = (m and m.sx) or 0
    end
    sheet.build = {
      id = imageData, W = W, H = H,
      count = sheet.style == 1 and 1 or count, fw = fw,
      tera = tera,
      cloud = cloud,
      shadowArt = shadowArt, shadowSize = shadowSize, shadowSx = shadowSx,
      box = boxFor(sheet.back, sheet.box),
      divisor = sheet.divisor, zoom = sheet.zoom or 1,
      scale = sheet.scale,
      maxH = sheet.maxH,
      fill = sheet.fill,
      natural = sheet.natural and true or false,
      back = sheet.back, stem = sheet.stem,
      static = sheet.static,
      native = sheet.bwTiming ~= nil,
      ee = sheet.ee,
      -- Static pack fronts and backs are 2x and 3x a 96px design canvas.
      -- Use dimensions rather than side, since four placeholder PNGs are 96px.
      density = sheet.static and H / 96 or 1,
      metrics = sheet.static and DATA.static.metrics[sheet.sourceStem] or nil,
      -- 3DB FLIP (option): mirror every baked frame across its vertical axis
      -- (see buildOneFrame).  Read once per sheet here, like every other bake
      -- knob.
      flip = sheet.flip,
      phase = "scan", row = 0,
      x0 = fw, y0 = H, x1 = -1, y1 = -1,
      -- ANIMATION RIDE: per-frame content centroids, accumulated by the scan
      -- (one entry per frame) and consumed by buildOneFrame to translate the
      -- crystal with the sprite's own motion.  fdx / fdy are the offsets for the
      -- frame currently being baked.
      fcx = {}, fcy = {}, fn = {},
      fdx = 0, fdy = 0,
    }
    sheet.frames = nil
    sheet.status = "building"
    return true
  end

  local function scanChunk(b, rows)
    local id, W, fw = b.id, b.W, b.fw
    local last = math.min(b.H - 1, b.row + rows - 1)
    local x0, y0, x1, y1 = b.x0, b.y0, b.x1, b.y1
    for y = b.row, last do
      for x = 0, W - 1 do
        local a = select(4, id:getPixel(x, y))
        if a and a > 0 then
          local lx = x - math.floor(x / fw) * fw
          if lx < x0 then x0 = lx end
          if lx > x1 then x1 = lx end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
          -- ANIMATION RIDE: this pixel's own frame (the sheet is a horizontal
          -- strip) and its contribution to that frame's content centroid.  The
          -- bake turns the per-frame centroid drift into a rigid offset for the
          -- crystal, so the facets follow the creature instead of the box.
          local fi = math.floor(x / fw) + 1
          b.fcx[fi] = (b.fcx[fi] or 0) + lx
          b.fcy[fi] = (b.fcy[fi] or 0) + y
          b.fn[fi] = (b.fn[fi] or 0) + 1
        end
      end
    end
    b.row = last + 1
    b.x0, b.y0, b.x1, b.y1 = x0, y0, x1, y1
  end

  local function setupFrames(b)
    if b.x1 < b.x0 or b.y1 < b.y0 then return false end
    local cw, ch = b.x1 - b.x0 + 1, b.y1 - b.y0 + 1
    local box = b.box

    -- 0n. NATURAL mode (b.natural, set by the battle.mon_pic caller): bake the
    --     sheet at exactly b.scale x its own trimmed pixels and return an image
    --     that size -- no box, no padding around it. This is what lets a custom
    --     battle screen hand every species its OWN size (the pack's relative
    --     sizes, "normal size") instead of folding each one into the same
    --     slot-sized canvas. Only the screen's own headroom (b.maxH) can fold
    --     it back, so a sheet too tall for its band keeps its head on screen
    --     rather than being clipped.
    --     GROUND ANCHOR: the screen draws the returned image's BOTTOM EDGE on
    --     its ground line, so the bottom edge IS the anchor. A grounded sprite
    --     therefore puts its content (its feet) straight onto the line -- but a
    --     FLOATING one gets `lift` rows of transparent padding added BELOW the
    --     content, so its art hovers that far above the line (see floatLift);
    --     the height the fold is checked against includes that padding. Because
    --     the canvas IS the content there is nowhere to put a PACK metrics
    --     offset, so natural mode ignores the pack alignment.
    if b.natural then
      local scale = ((b.scale and b.scale > 0) and b.scale or 1) / (b.density or 1)
      local lift = floatLift(b.stem, ch)
      if b.maxH and (ch + lift) * scale > b.maxH then scale = b.maxH / (ch + lift) end
      if scale <= 0 then scale = 1 end
      local dw = math.max(1, round(cw * scale))
      local dh = math.max(1, round(ch * scale))
      local pad = round(lift * scale)
      -- DYNAMAX CLOUD: a natural-size frame IS its content, so there is no box
      -- to take a cloud band from -- the canvas simply grows upward by what the
      -- cloud needs ABOVE the sprite's own top (its full height minus the part
      -- that sinks onto the head, see CLOUD_SINK), and the content keeps its
      -- bottom edge (plus the floater pad, if any), so the sprite's feet stay
      -- on the ground line the screen anchors to and the cloud rides on the
      -- head.
      local grow = 0
      local cloudH = 0
      if b.cloud then
        cloudH = math.max(CLOUD_MIN_H, round(dh * CLOUD_BAND))
        grow = cloudH - cloudSink(cloudH)
      end
      b.cw, b.ch, b.dw, b.dh, b.scale = cw, ch, dw, dh, scale
      b.box = { w = dw, h = dh + grow + pad }
      b.ox, b.oy = 0, grow
      b.cloudH = cloudH
      b.cloudSink = (cloudH > 0) and cloudSink(cloudH) or 0
      b.phase = "frames"
      b.frame = 0
      return true
    end

    -- Ways a sheet's own scale can be chosen, in priority order:
    --
    -- 0n. NATURAL (b.natural, set by the battle.mon_pic caller) -- handled
    --    above, before any box math: no box, just b.scale x the sheet's own
    --    trimmed pixels, folded only against b.maxH. This is what
    --    g9-Battle-Scene uses (see its drawSprite), so every species keeps
    --    the size its art gives it instead of being folded into a slot box.
    -- 0. An EXPLICIT field scale plus a BOX (b.scale + b.box, set by an older
    --    battle.mon_pic caller): every sheet is multiplied by exactly this
    --    factor, then folded to fit the box/headroom. Kept for any screen
    --    still asking for a box; g9-Battle-Scene now sends natural instead.
    -- 1. A custom battle screen's older UNIFORM divisor scale (b.divisor):
    --    every sheet baked at 1/divisor, the same whole-number step for both
    --    teams (kept for g2-Battle-Scene forks).
    -- 1b. b.fill: the boss's own slot asks a sheet to GROW past its native
    --    size to fill the box it was given. Ordinary slots never fill, so
    --    each species keeps its own relative size.
    -- 2. BIG / NORMAL / SMALL divide the artwork by 1 / 2 / 3,
    --    fitting to the box/headroom when needed to avoid clipping.
    --
    -- Per-axis fit bounds: the content may be as wide as the box and as tall
    -- as the box, but never taller than the headroom the battle screen
    -- reported for that slot (b.maxH = the pixels from its ground line to
    -- the field's own top), so a slot in a short band folds a tall sheet
    -- instead of letting its head be clipped.
    local fitW = box.w
    local fitH = b.maxH and math.min(box.h, b.maxH) or box.h
    -- DYNAMAX CLOUD: in a fixed box the cloud claims a band off the top (see
    -- CLOUD_BAND and buildOneFrame), so the sheet is fitted into what is left --
    -- which is what keeps the cloud above the head rather than over the face.
    -- Only the part of the cloud that rides ABOVE the head has to come out of
    -- the box; the part that sinks onto the head (CLOUD_SINK) shares the room
    -- the head already uses, so the band reserved here is the cloud's height
    -- minus its sink.  A sheet short enough to fit either way is not resized at
    -- all; the band only bites on a sprite tall enough to have used that up.
    local cloudH = 0
    local cloudSinkH = 0
    if b.cloud then
      cloudH = math.max(CLOUD_MIN_H, round(box.h * CLOUD_BAND))
      if cloudH > box.h - 4 then cloudH = math.max(0, box.h - 4) end
      if cloudH > 0 then
        cloudSinkH = cloudSink(cloudH)
        fitH = math.max(4, fitH - (cloudH - cloudSinkH))
      end
    end
    local mode = spriteSizeMode()
    local scale
    if b.scale and b.scale > 0 then
      -- 0. An explicit field scale plus a box (an older battle.mon_pic
      --    caller): use it directly -- upscaling is intended -- then fold it
      --    back only as far as the box/headroom demand.
      scale = b.scale / (b.density or 1)
      if cw * scale > fitW then scale = fitW / cw end
      if ch * scale > fitH then scale = fitH / ch end
    elseif b.fill then
      -- A slot that asks its sheet to FILL (the scene's boss slot, BOSS_MUL
      -- bands tall): use the largest scale that fits both axes, upscaling a
      -- small sheet as well as shrinking a large one. A non-integer ratio
      -- (the boss's +0.6 -> 1.6x) can't be an integer zoom step, so it is one
      -- nearest-neighbour resample straight to the box.
      scale = math.min(fitW / cw, fitH / ch)
    elseif b.divisor and b.divisor >= 1 then
      local zoom = b.zoom or 1
      scale = 1 / (b.divisor * (b.density or 1))
      if cw * scale * zoom > fitW then scale = fitW / (cw * zoom) end
      if ch * scale * zoom > fitH then scale = fitH / (ch * zoom) end
    elseif b.native then
      -- ROM animation canvases include transparent OAM space and may expand
      -- for a distant pose. Size the visible union once for the whole loop;
      -- never normalize individual frames, which would erase native motion.
      -- BIG fills the slot; NORMAL/SMALL use half/a third of it.
      scale = math.min(fitW / cw, fitH / ch) / math.max(1, mode)
    else
      scale = 1 / (mode * (b.density or 1))
      if cw * scale > fitW then scale = fitW / cw end
      if ch * scale > fitH then scale = fitH / ch end
    end
    if scale > 1 and not (b.native or b.fill or (b.scale and b.scale > 0)) then scale = 1 end
    local dw = math.max(1, round(cw * scale))
    local dh = math.max(1, round(ch * scale))
    b.cw, b.ch, b.dw, b.dh = cw, ch, dw, dh
    b.scale = scale

    -- GROUND ANCHOR places the content inside the box.  FEET (the default)
    -- puts the sprite's own content bottom -- its feet -- on the box bottom, so
    -- every grounded sheet lands its feet on the same line however much padding
    -- its trim carried; a floating sheet is then raised off that line by `lift`
    -- SOURCE pixels (floatLift), a share of its own height.  PACK uses the
    -- pack's own SpeciesMetrics: it anchors a sheet's UNTRIMMED frame
    -- bottom-centre at the base and shifts it by its x,y * 2 screen px, while
    -- the frame itself is drawn at the pack's own render scale (2 front, 3
    -- back).  We trimmed the sheet to its content, so the padding those metrics
    -- take for granted is gone and has to be added back:
    --   * content bottom sits padBot rows above the frame bottom -> -padBot;
    --   * content mid-x sits (padL - padR) / 2 px off the frame mid-x, and our
    --     baseline centres the content, so - (padR - padL) / 2.
    -- `offset * 2 / renderScale` converts a metric to sheet pixels, which then
    -- shrinks with the sprite (so alignment stays proportional at any size).
    -- BOX keeps the old bottom-centre placement, no alignment at all.
    -- The result is clamped inside the box: the baked canvas IS the pic box, so
    -- anything outside it would be lost, and keeping a whole sprite (nudged to
    -- the nearest edge) reads better than clipping its head or feet.
    local baseX = (box.w - dw) / 2
    local baseY = box.h - dh
    local anchor = spriteAnchor()
    local offX, offY = 0, 0
    if anchor == ANCHOR_PACK and (b.static or METRICS) then
      local m
      if b.native or b.ee then m = nil elseif b.static then m = b.metrics else m = METRICS[b.stem] end
      if m then
        local div = b.back and BACK_SCALE or FRONT_SCALE
        local mx = b.back and m.bx or m.fx
        local my = b.back and m.by or m.fy
        local padL = b.x0
        local padR = b.fw - 1 - b.x1
        local padBot = (b.H - 1) - b.y1
        if mx then offX = (mx * 2) / div - (padR - padL) / 2 end
        if my then offY = (my * 2) / div - padBot end
      end
    elseif anchor == ANCHOR_FEET then
      offY = -floatLift(b.stem, ch)
    end
    local ox = math.floor(baseX + offX * scale)
    local oy = math.floor(baseY + offY * scale)
    if GEN == 3 then oy = oy - GEN3_SPRITE_LIFT end
    if ox < 0 then ox = 0 elseif ox > box.w - dw then ox = box.w - dw end
    if oy < 0 then oy = 0 elseif oy > box.h - dh then oy = box.h - dh end
    b.ox, b.oy = ox, oy
    -- Custom art is already anchored within its canvas. Battle placement
    -- cancels ROM-specific padding offsets instead of lifting by art height.
    b.gen3BattleLift = GEN == 3 and 0 or nil
    b.cloudH = cloudH
    b.cloudSink = cloudSinkH
    b.phase = "frames"
    b.frame = 0
    return true
  end

  -- The crystal film's per-pixel colour: the Tera type's own colour, cut into
  -- flat geometric shards, sheened by the crystal pattern's own chroma, and
  -- glinted white on the lit shards -- composited over the sprite pixel.  The
  -- caller keeps the SPRITE's alpha, so a transparent frame pixel never gets a
  -- film -- the creature's true silhouette, not the square frame, is what the
  -- crystal covers.
  --
  -- FACET LATTICE.  The film is cut into flat shards by a free-scatter VORONOI
  -- over the content box: sites scattered with no grid at all (a grid leaves
  -- rows and columns of seams behind every amount of jitter, and those read as
  -- a checkerboard), producing irregular convex polygons with dead-straight
  -- borders and ONE uniform colour each, which is what reads as cut glass.
  -- The scatter is then clamped into a size band -- tiny flakes folded into
  -- their largest neighbour, oversized plates cracked along a wavy fracture --
  -- so the shards come out at several scales without any of them vanishing or
  -- taking over the surface.  Sampling
  -- the pattern's own soft mosaic directly gave soft-edged patches instead --
  -- a shard border wants to be a straight line, not a texture contour.  Each
  -- shard's colour comes from sampling the crystal pattern at the shard's
  -- centroid, so the shard brightnesses ARE the pattern's lit-facet
  -- brightnesses (real relief, not a noise field), and neighbouring shards of
  -- similar brightness simply merge into one larger plane.
  --
  -- The lattice depends only on the content box (identical for every sheet) and
  -- the pattern, so it is built ONCE and cached in the TERA table; a sheet then
  -- only turns the shared shard brightnesses into its own type-tinted colours,
  -- and the per-pixel cost is a few table lookups.  That matters: the pack bakes
  -- a variant sheet per species per type, so a per-sheet Voronoi rebuild would
  -- dominate the whole feature.
  TERA.hash = function(n)
    -- Deterministic 0..1 hash (a Lehmer step, kept under 2^53 so it stays exact
    -- in a Lua double).  The lattice must NOT use math.random: a shard layout
    -- that shifted between frames would make the crystal crawl.
    n = math.floor(n) % 2147483647
    if n < 0 then n = n + 2147483647 end
    n = (n * 48271) % 2147483647
    n = (n * 48271) % 2147483647
    n = (n * 48271) % 2147483647
    return n / 2147483647
  end

  -- ANIMATION RIDE / FACET LATTICE PADDING.  The lattice is cut over a `pad`
  -- pixel margin all around the content box (DW x DH below) so that a frame
  -- whose creature has drifted can sample the SAME rigid lattice translated with
  -- it, instead of the crystal staying nailed to the box while the sprite bobs
  -- underneath (see the per-frame offset in buildOneFrame).  The pattern window
  -- and the facet SCALE are still measured against the real content box, so the
  -- margin changes nothing about how the crystal looks at rest -- it is travel
  -- the ride consumes, and the shards just outside the box are clipped away by
  -- the bake's own silhouette rule (the film is only ever written where the
  -- sprite's own art wrote).
  TERA.buildMap = function(pat, dw, dh, pad)
    pad = pad or 0
    local DW, DH = dw + 2 * pad, dh + 2 * pad
    local ref = math.max(1, math.max(dw, dh))
    local k = pat.w * TERA.PATTERN_COVER / ref
    local kMax = math.min(pat.w / math.max(1, dw), pat.h / math.max(1, dh))
    if k > kMax then k = kMax end
    if k < 0.01 then k = 0.01 end
    local pox = (pat.w - dw * k) / 2
    local poy = (pat.h - dh * k) / 2
    -- AUTOCONTRAST over the sampled window.  The pattern is high-key and its
    -- full range is narrow; a given cover samples only a SLICE of it, and an
    -- even narrower slice of luma.  Normalising by the pattern's GLOBAL
    -- endpoints would bunch every shard in the middle of the ramp (the muddy,
    -- low-contrast look), so the window's CONTRAST_LO / CONTRAST_HI PERCENTILES
    -- are the stretch endpoints instead: the flanks clip to the extremes and
    -- what is left spans the full dark -> bright ramp.
    local wsamp = {}
    local wstep = math.max(1, math.floor(k))
    local wx0 = math.max(0, math.floor(pox))
    local wy0 = math.max(0, math.floor(poy))
    local wx1 = math.min(pat.w - 1, math.ceil(pox + dw * k))
    local wy1 = math.min(pat.h - 1, math.ceil(poy + dh * k))
    for py = wy0, wy1, wstep do
      for px = wx0, wx1, wstep do
        local pr, pg, pb = pat.id:getPixel(px, py)
        wsamp[#wsamp + 1] = (pr + pg + pb) / 3
      end
    end
    table.sort(wsamp)
    local m = #wsamp
    local plo, pspan = 0, 1
    if m >= 8 then
      local wlo = wsamp[math.max(1, math.floor(m * TERA.CONTRAST_LO))]
      local whi = wsamp[math.min(m, math.ceil(m * TERA.CONTRAST_HI))]
      plo, pspan = wlo, whi - wlo
    elseif m >= 1 then
      plo, pspan = wsamp[1], wsamp[m] - wsamp[1]
    end
    if pspan < 0.01 then plo, pspan = 0, 1 end
    -- The shard sites, in destination pixels: a free scatter, not a grid.  A
    -- fraction FACET_MIX of them are CLUSTERED around the others, which is what
    -- yields shards at several scales (a cluster becomes a field of chips, the
    -- gap between clusters a single slab); the rest are spread evenly over the
    -- padded box.  Every value comes from TERA.hash, so the same box always cuts
    -- the same lattice -- a layout that shifted between frames would make the
    -- crystal crawl.
    local nsite = TERA.FACET_SITES
    local pitch = math.sqrt(DW * DH / nsite)
    local nbase = math.floor(nsite * (1 - TERA.FACET_MIX) + 0.5)
    if nbase < 1 then nbase = 1 elseif nbase > nsite then nbase = nsite end
    local sites = {}
    for i = 1, nbase do
      sites[i] = { TERA.hash(i * 2654435 + 11) * DW, TERA.hash(i * 40503 + 29) * DH }
    end
    for i = nbase + 1, nsite do
      local b = sites[1 + math.floor(TERA.hash(i * 9176 + 53) * nbase)]
      local a = TERA.hash(i * 3571 + 71) * 6.283185307
      local r = TERA.FACET_MIX_RADIUS * pitch * (0.25 + TERA.hash(i * 7919 + 97) * 1.3)
      sites[i] = { b[1] + math.cos(a) * r, b[2] + math.sin(a) * r }
    end
    -- Nearest site per pixel: the Voronoi cell id.
    local cell = {}
    local pxOf = {}
    local ncell = nsite
    for ty = 0, DH - 1 do
      for tx = 0, DW - 1 do
        local fx, fy = tx + 0.5, ty + 0.5
        local best, bd = 1, math.huge
        for si = 1, nsite do
          local s = sites[si]
          local dx, dy = fx - s[1], fy - s[2]
          local d = dx * dx + dy * dy
          if d < bd then bd, best = d, si end
        end
        cell[ty * DW + tx + 1] = best
      end
    end
    local nominal = DW * DH / nsite
    local minA = TERA.FACET_MIN * nominal
    local maxA = TERA.FACET_MAX * nominal
    -- TERA.rebuild: re-derive the per-shard pixel buckets and areas from the
    -- current cell map.  Every pass below walks a shard's OWN pixels through
    -- these buckets, so the size band costs the box's pixel count in total
    -- rather than rescanning the whole box once per shard.
    local area = {}
    local rebuild = function()
      pxOf, area = {}, {}
      for i = 1, DW * DH do
        local c = cell[i]
        local bucket = pxOf[c]
        if not bucket then bucket = {}; pxOf[c] = bucket end
        bucket[#bucket + 1] = i
        area[c] = #bucket
      end
    end
    -- TERA.pickNeighbour: the LARGEST of a shard's 4-neighbours, not merely the
    -- one sharing the longest edge.  Folding a sliver into the largest neighbour
    -- is what pushes the small end of the size distribution up -- the pick is by
    -- AREA, so a chip is absorbed by whichever side is already the broadest.
    local pickNeighbour = function(id)
      local tally = {}
      local bucket = pxOf[id]
      if bucket then
        for j = 1, #bucket do
          local i = bucket[j]
          local tx = (i - 1) % DW
          local ty = (i - 1 - tx) / DW
          local n
          if tx + 1 < DW then n = cell[i + 1]; if n ~= id then tally[n] = (tally[n] or 0) + 1 end end
          if tx > 0 then n = cell[i - 1]; if n ~= id then tally[n] = (tally[n] or 0) + 1 end end
          if ty + 1 < DH then n = cell[i + DW]; if n ~= id then tally[n] = (tally[n] or 0) + 1 end end
          if ty > 0 then n = cell[i - DW]; if n ~= id then tally[n] = (tally[n] or 0) + 1 end end
        end
      end
      local best, bn = nil, -1
      for n in pairs(tally) do
        local av = area[n] or 0
        if av > bn or (av == bn and best ~= nil and n < best) then bn, best = av, n end
      end
      return best
    end
    -- FACET_MIN, as a pass: fold every shard below the floor into its largest
    -- neighbour, so the scatter's hairline slivers are absorbed rather than
    -- surviving as specks of dirt on the glass.  Run twice -- once before the
    -- ceiling cracks (which is what lets the MEAN shard be small without any
    -- individual shard shrinking to nothing) and once after, because a crack can
    -- leave a sliver on one side of the cut.
    local foldSmall = function()
      rebuild()
      local remap = {}
      for id = 1, ncell do
        local a0 = area[id]
        if a0 and a0 < minA then
          local best = pickNeighbour(id)
          if best then
            remap[id] = best
            area[best] = (area[best] or 0) + a0
            area[id] = 0
          end
        end
      end
      if next(remap) then
        for i = 1, DW * DH do
          local c = cell[i]
          local hops = 0
          while remap[c] and hops < 64 do
            c = remap[c]
            hops = hops + 1
          end
          cell[i] = c
        end
      end
    end
    foldSmall()
    -- FACET_MAX.  Crack every shard above the ceiling along a wavy line through
    -- its own centroid, and keep going while any shard is still over it.  The
    -- line wanders (FACET_CRACK_BEND), because a dead-straight cut through a
    -- slab reads as an artificial slice rather than as a fracture; a cut that
    -- would leave one side empty is abandoned and the shard flagged so the
    -- search passes it by instead of spinning on it.
    if TERA.FACET_MAX > 0 then
      local noSplit = {}
      local guard = 0
      while guard < TERA.FACET_SPLIT_GUARD do
        guard = guard + 1
        local big, biggest = nil, -1
        for c = 1, ncell do
          if not noSplit[c] then
            local av = area[c]
            if av and av > biggest then biggest, big = av, c end
          end
        end
        if not big or biggest <= maxA then break end
        local bucket = pxOf[big]
        if not bucket or #bucket < 4 then
          noSplit[big] = true
        else
          local sx, sy = 0, 0
          for j = 1, #bucket do
            local i = bucket[j]
            local tx = (i - 1) % DW
            sx = sx + tx + 0.5
            sy = sy + (i - 1 - tx) / DW + 0.5
          end
          local cx, cy = sx / #bucket, sy / #bucket
          local ang = TERA.hash(big * 7919 + big + 13) * 3.141592653
          local ux, uy = math.cos(ang), math.sin(ang)
          local amp = TERA.FACET_CRACK_BEND * pitch
          local ph = TERA.hash(big * 104729 + 31) * 6.283185307
          local n1, n2 = {}, {}
          for j = 1, #bucket do
            local i = bucket[j]
            local tx = (i - 1) % DW
            local pxx, pyy = tx + 0.5 - cx, (i - 1 - tx) / DW + 0.5 - cy
            local s = pxx * ux + pyy * uy
              + amp * math.sin((pxx * -uy + pyy * ux) / (pitch * 1.4) + ph)
            if s > 0 then n1[#n1 + 1] = i else n2[#n2 + 1] = i end
          end
          if #n1 == 0 or #n2 == 0 then
            noSplit[big] = true
          else
            ncell = ncell + 1
            local nid = ncell
            for j = 1, #n1 do cell[n1[j]] = nid end
            pxOf[big], pxOf[nid] = n2, n1
            area[big], area[nid] = #n2, #n1
          end
        end
      end
    end
    foldSmall()
    nsite = ncell
    -- Each cell's pattern sample, taken at the cell's centroid.
    local csx, csy, csc = {}, {}, {}
    for i = 1, DW * DH do
      local si = cell[i]
      csx[si] = (csx[si] or 0) + (i - 1) % DW
      csy[si] = (csy[si] or 0) + math.floor((i - 1) / DW)
      csc[si] = (csc[si] or 0) + 1
    end
    local cl, cpr, cpg, cpb, cspec, seam = {}, {}, {}, {}, {}, {}
    local nlv = TERA.FACET_LEVELS - 1
    for si = 1, nsite do
      local c = csc[si]
      if c and c > 0 then
        -- The centroid is in LATTICE space, so subtract the margin to land back
        -- on the content: the pattern still spans the box, not the padding.
        local px = math.floor(pox + (csx[si] / c - pad + 0.5) * k)
        local py = math.floor(poy + (csy[si] / c - pad + 0.5) * k)
        if px < 0 then px = 0 elseif px >= pat.w then px = pat.w - 1 end
        if py < 0 then py = 0 elseif py >= pat.h then py = pat.h - 1 end
        local pr, pg, pb = pat.id:getPixel(px, py)
        cpr[si], cpg[si], cpb[si] = pr, pg, pb
        local t = ((pr + pg + pb) / 3 - plo) / pspan
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        if TERA.CONTRAST_GAIN > 0 then
          local sm = t * t * (3 - 2 * t)
          local ck = TERA.CONTRAST_GAIN
          if ck > 1 then ck = 1 end
          t = t + (sm - t) * ck
        end
        -- The gloss response keys off this SMOOTH value, so the highlight rolls
        -- on across the brightest few shards; keying it off the quantised step
        -- instead floods a whole band with white.  The shard's COLOUR uses the
        -- quantised step below, so the planes stay distinct.
        local spec = 0
        if TERA.SPEC_STRENGTH > 0 then
          spec = (t - TERA.SPEC_T0) / (1 - TERA.SPEC_T0)
          if spec < 0 then spec = 0 elseif spec > 1 then spec = 1 end
          spec = (spec ^ TERA.SPEC_POW) * TERA.SPEC_STRENGTH
        end
        if TERA.FACET_LEVELS > 1 then
          local lv = math.floor(t * TERA.FACET_LEVELS + 1e-9)
          if lv > nlv then lv = nlv elseif lv < 0 then lv = 0 end
          t = lv / nlv
        end
        cl[si] = t
        cspec[si] = spec
      else
        cl[si], cspec[si] = 0, 0
        cpr[si], cpg[si], cpb[si] = 1, 1, 1
      end
    end
    -- Shard borders.  A cut gem's edges show a BEVEL: the lit bevel on one side,
    -- the shadowed one on the other.  A pixel whose right/below neighbour is a
    -- different shard is marked 1 (the seam pass lifts it toward white); a pixel
    -- whose LEFT/ABOVE neighbour differs is marked -1 (the same pass darkens it).
    -- The bright/dark pairing along each shard boundary is most of what makes
    -- the surface read as physical cut crystal rather than as flat stained
    -- glass.  0 = an interior pixel.
    for ty = 0, DH - 1 do
      for tx = 0, DW - 1 do
        local i = ty * DW + tx + 1
        local c0 = cell[i]
        local s = 0
        if (tx + 1 < DW and cell[i + 1] ~= c0)
            or (ty + 1 < DH and cell[i + DW] ~= c0) then
          s = 1
        elseif (tx > 0 and cell[i - 1] ~= c0)
            or (ty > 0 and cell[i - DW] ~= c0) then
          s = -1
        end
        seam[i] = s
      end
    end
    return { pat = pat, dw = DW, dh = DH, pad = pad,
      boxW = dw, boxH = dh, k = k, pox = pox, poy = poy,
      plo = plo, pspan = pspan, cell = cell, nsite = nsite, cl = cl,
      cpr = cpr, cpg = cpg, cpb = cpb, cspec = cspec, seam = seam }
  end

  -- The star sprite, scaled with the bake's own nearest-neighbour magnification.
  -- A sparkle should be a constant size in the CREATURE's own pixels, so a 4x
  -- bake (a custom screen drawing at scale 4) needs a 4x star rather than a
  -- three-pixel speck that the magnification swallows up.  Each nominal
  -- STAR_SPRITES[STAR_SPRITE] entry is expanded into the `scale` x `scale` block of
  -- destination pixels it covers -- blocky arms, which is exactly the right look
  -- beside the blocky magnified sprite -- and the results are cached per scale
  -- (only a handful of scales are ever in play, and the table would otherwise be
  -- rebuilt for every sheet that bakes).
  TERA.starCache = {}
  TERA.starsFor = function(scale)
    local sprite = TERA.STAR_SPRITES[TERA.STAR_SPRITE] or TERA.STAR_SPRITES[1]
    if scale <= 1 then return sprite end
    local ckey = scale * 16 + TERA.STAR_SPRITE
    local cached = TERA.starCache[ckey]
    if cached then return cached end
    local out = {}
    for _, s in ipairs(sprite) do
      for a = 0, scale - 1 do
        for b = 0, scale - 1 do
          out[#out + 1] = { s[1] * scale + a, s[2] * scale + b, s[3] }
        end
      end
    end
    TERA.starCache[ckey] = out
    return out
  end

  -- One destination pixel of the film.  The shard it falls in supplies a flat
  -- film colour (built per sheet, see the TERA ART block in buildOneFrame) and a
  -- flat highlight; the shard border supplies a bright seam.
  local function teraPixel(b, tx, ty, sr, sg, sb)
    local map = b.map
    -- ANIMATION RIDE: the lattice is looked up at this frame's rigid offset
    -- (b.fdx / b.fdy) inside the padding, so the facets travel WITH the creature
    -- instead of staying pinned to the box while it bobs underneath.
    local i = (ty + map.pad + b.fdy) * map.dw + (tx + map.pad + b.fdx) + 1
    local ci = map.cell[i]
    local f = b.film[ci]
    -- Composite the film over the sprite: the film's share of the mix is the
    -- TERA TRANSPARENCY option's complement, resolved once per sheet in
    -- buildOneFrame and stored on the bake as b.filmMix.  The rest is the
    -- creature's own colours, which stay visible through the crystal.
    local mix = b.filmMix or TERA.MIX_FILM
    local smix = 1 - mix
    local r = sr * smix + f[1] * mix
    local g = sg * smix + f[2] * mix
    local bl = sb * smix + f[3] * mix
    -- The seam and the glint are applied to the MIXED pixel, not to the film
    -- first: mixing toward a bright film still drags the result back toward the
    -- sprite's own colour, so an earlier version's highlights came out as pale
    -- tints rather than clean light.  A seam pixel is either the lit side of the
    -- shard's bevel (map.seam == 1: lift toward white) or the shadowed side
    -- (map.seam == -1: deepen), never both.
    local seam = map.seam[i]
    if seam > 0 then
      local s = TERA.SEAM_STRENGTH
      local sl = b.seamLit
      r = r + (sl[1] - r) * s
      g = g + (sl[2] - g) * s
      bl = bl + (sl[3] - bl) * s
    elseif seam < 0 then
      local d = 1 - TERA.SEAM_DARK
      r, g, bl = r * d, g * d, bl * d
    end
    -- Specular glint: the whole shard's uniform highlight, so the facet reads
    -- as a flat polished plane catching the light.
    local spec = map.cspec[ci]
    if spec > 0 then
      r = r * (1 - spec) + spec
      g = g * (1 - spec) + spec
      bl = bl * (1 - spec) + spec
    end
    if r > 1 then r = 1 elseif r < 0 then r = 0 end
    if g > 1 then g = 1 elseif g < 0 then g = 0 end
    if bl > 1 then bl = 1 elseif bl < 0 then bl = 0 end
    return r, g, bl
  end


  DATA.centerPreview=assert(load(assert(mod:read('preview_center.lua'))))()
  local function buildOneFrame(sheet)
    local b = sheet.build
    local id, fw = b.id, b.fw
    local cw, ch, dw, dh, ox, oy = b.cw, b.ch, b.dw, b.dh, b.ox, b.oy
    local box = b.box
    local f = b.frame
    local out = love.image.newImageData(box.w, box.h)
    local baseX = f * fw + b.x0
    -- TERA ART: the film's facet lattice is shared by every sheet (the same
    -- content box, the same pattern), so it is built ONCE and cached in the
    -- TERA table -- cut with a padding margin around the box, which is exactly
    -- the travel the animation ride below consumes.  Only the type-tinted shard
    -- colours below are per sheet.
    local tera = b.tera
    if tera and not b.map then
      -- Keyed by box size, not held in a single slot: a session that shows a
      -- 56px front sprite and a 64px gen1 back sprite would otherwise rebuild
      -- the whole Voronoi on every alternation.
      local maps = TERA._maps
      if not maps then maps = {}; TERA._maps = maps end
      local ckey = dw .. "x" .. dh
      local map = maps[ckey]
      if not map or map.pat ~= tera.pat then
        map = TERA.buildMap(tera.pat, dw, dh, TERA.PAD)
        maps[ckey] = map
      end
      b.map = map
      b.plo, b.pspan = map.plo, map.pspan
      -- Turn the shared shard brightnesses into THIS sheet's type-tinted film
      -- colours.  The ramp is the type colour from a deep saturated shadow
      -- (FILM_DARK x its brightness) to a lifted lit plane (FILM_LIGHT of the
      -- way to white), plus the pattern's own faint chroma as iridescence.
      local tint = tera.tint
      local lit = TERA.FILM_LIGHT
      -- The colour the LIT side of a bevel is pulled toward (see SEAM_TINT):
      -- white carrying a little of the type's colour, so the seam highlight
      -- stays on the crystal's own hue instead of flashing a neutral white.
      local st = TERA.SEAM_TINT
      b.seamLit = { tint[1] * st + (1 - st), tint[2] * st + (1 - st),
        tint[3] * st + (1 - st) }
      local film = {}
      for si = 1, map.nsite do
        local t = map.cl[si]
        local pr, pg, pb = map.cpr[si], map.cpg[si], map.cpb[si]
        local pl = (pr + pg + pb) / 3
        local fr = tint[1] * TERA.FILM_DARK * (1 - t) + (tint[1] * (1 - lit) + lit) * t
        local fg = tint[2] * TERA.FILM_DARK * (1 - t) + (tint[2] * (1 - lit) + lit) * t
        local fb = tint[3] * TERA.FILM_DARK * (1 - t) + (tint[3] * (1 - lit) + lit) * t
        fr = fr + (pr - pl) * TERA.IRID_GAIN
        fg = fg + (pg - pl) * TERA.IRID_GAIN
        fb = fb + (pb - pl) * TERA.IRID_GAIN
        film[si] = { fr, fg, fb }
      end
      b.film = film
      -- TERA TRANSPARENCY (option): the crystal layer's own opacity, resolved
      -- once per sheet beside the film it colours (the hot per-pixel path then
      -- just reads b.filmMix).  The row is the sprite's SHARE -- how much of the
      -- creature shows through the crystal -- so the film keeps the rest; 30%
      -- reproduces the 70/30 blend the crystal shipped with.  Clamped to the
      -- offered 5..60 band so a stray value can neither erase the gem nor hide
      -- the Pokemon.
      local tr = tonumber(opt("tera_transparency", 30))
      if not tr then tr = 30 end
      if tr < 5 then tr = 5 elseif tr > 60 then tr = 60 end
      b.filmMix = 1 - tr / 100
      -- Star-glint anchors are NOT chosen here.  They must sit on the CREATURE
      -- (a shard anchor picks a pretty facet, but the sprite is opaque over only
      -- part of the box), so the first baked frame collects the creature's
      -- opaque pixels and the pick is made from those, below the bake loop --
      -- settled once per sheet, so the sparkles keep to the same facets for
      -- every frame (the facets themselves ride the animation with the creature,
      -- and each sparkle then twinkles on and off on its own cycle).
      b.glints = nil
    end
    -- ANIMATION RIDE: this frame's rigid offset for the crystal (see the padding
    -- note on buildMap).  b.map exists by now.  The scan recorded each frame's
    -- content centroid, so this frame's drift from the first one -- in
    -- destination pixels, i.e. x the sheet's own resample scale -- is how far
    -- the whole facet lattice, and every sparkle on it, is translated.  Centroid
    -- rather than bbox on purpose: a single limb moving must not drag the
    -- crystal with it, only the body's own drift should.  Clamped to the
    -- lattice's padding, which is what that margin was cut for.
    if tera and b.map then
      local nm, n0 = b.fn[f + 1], b.fn[1]
      if nm and n0 and nm > 0 and n0 > 0 then
        local ddx = round((b.fcx[f + 1] / nm - b.fcx[1] / n0) * (dw / cw))
        local ddy = round((b.fcy[f + 1] / nm - b.fcy[1] / n0) * (dh / ch))
        local lim = b.map.pad
        if ddx < -lim then ddx = -lim elseif ddx > lim then ddx = lim end
        if ddy < -lim then ddy = -lim elseif ddy > lim then ddy = lim end
        b.fdx, b.fdy = ddx, ddy
      else
        b.fdx, b.fdy = 0, 0
      end
    end
    -- One path for every sheet: the bake scales the content by `b.scale`, so
    -- destination pixel t covers source pixels [t*step, (t+1)*step) and takes
    -- the single source pixel nearest its centre.  `step` is fractional in MAX
    -- DETAIL, but the sample is still exactly one source pixel, so no colour is
    -- ever blended and edges stay hard (see the header note).  When the sampled
    -- pixel is transparent, borrow the nearest OPAQUE pixel the destination
    -- pixel covers, so a one-pixel outline or antenna is never punched out by
    -- the stride.
    local stepX = cw / dw
    local stepY = ch / dh
    -- The destination row the sprite's own content actually starts on.  The
    -- cloud is anchored to THIS, not to oy, because the pack's metrics
    -- alignment (or a sheet whose trim box keeps a transparent rim) can shift
    -- the visible content down inside oy -- anchoring to oy then leaves the
    -- cloud hovering in the gap it opened up.
    local contentTop
    for ty = 0, dh - 1 do
      local syn = b.y0 + math.min(ch - 1, math.floor((ty + 0.5) * stepY))
      local sy0 = b.y0 + math.floor(ty * stepY)
      local sy1 = b.y0 + math.min(ch, math.ceil((ty + 1) * stepY))
      for tx = 0, dw - 1 do
        local sxn = baseX + math.min(cw - 1, math.floor((tx + 0.5) * stepX))
        local cr, cg, cb, ca = id:getPixel(sxn, syn)
        if ca == 0 then
          local sx0 = baseX + math.floor(tx * stepX)
          local sx1 = baseX + math.min(cw, math.ceil((tx + 1) * stepX))
          local bestD = math.huge
          for sy = sy0, math.max(sy0, sy1 - 1) do
            for sx = sx0, math.max(sx0, sx1 - 1) do
              local pr, pg, pb, pa = id:getPixel(sx, sy)
              if pa and pa > 0 then
                local ddx, ddy = sx - sxn, sy - syn
                local dd = ddx * ddx + ddy * ddy
                if dd < bestD then bestD, cr, cg, cb, ca = dd, pr, pg, pb, pa end
              end
            end
          end
        end
        if ca and ca > 0 then
          if tera then
            cr, cg, cb = teraPixel(b, tx, ty, cr, cg, cb)
            -- First frame only: record this opaque pixel as a sparkle candidate.
            -- Only the INTERIOR of a shard qualifies (a seam-free pixel -- the
            -- crystal's "clearest" planes, not its bevel lines), and the score
            -- is the pixel's OWN baked brightness, so the sparkles end up spread
            -- over the crystal's LIGHTEST planes -- the places the eye reads as
            -- clear and bright.  The shard's lit level is only a tie-breaker:
            -- what matters is how much light that pixel actually emits, which is
            -- the film composited over the creature (a bright shard laid across a
            -- dark part of the sprite bakes dark, and a sparkle there would sit
            -- on shadow, not on the clear bright facets the star belongs on).
            if not b.glints then
              local mm = b.map
              local ii = (ty + mm.pad + b.fdy) * mm.dw + (tx + mm.pad + b.fdx) + 1
              if mm.seam[ii] == 0 then
                local ci = mm.cell[ii]
                local tsc = (cr + cg + cb) / 3 + 0.25 * mm.cl[ci]
                local cands = b.glintCands
                if not cands then cands = {} b.glintCands = cands end
                cands[#cands + 1] = { tx, ty, tsc }
              end
            end
          end
          if not contentTop then contentTop = oy + ty end
          out:setPixel(ox + tx, oy + ty, cr, cg, cb, ca)
        end
      end
    end
    -- Sparkle anchors, picked from the first frame's opaque pixels: the lightest
    -- film planes first, thinned STAR_SPACING (a share of the sprite's width)
    -- apart so they spread over the creature instead of clumping on one facet.
    -- Each anchor is stored on the sheet so every frame of the animation keeps
    -- the same facets, and each is also dealt a twinkle -- a phase and a whole
    -- number of pulses per loop, from the deterministic hash -- which the stamp
    -- pass below uses to blink it on and off (the sparkles are their own
    -- animation, running over the top of the sprite's).
    if tera and not b.glints then
      b.glints = {}
      local cands = b.glintCands
      if TERA.STAR_COUNT > 0 and cands then
        table.sort(cands, function(a, c) return a[3] > c[3] end)
        local minD = (dw * TERA.STAR_SPACING) ^ 2
        for _, c in ipairs(cands) do
          if #b.glints >= TERA.STAR_COUNT then break end
          local far = true
          for _, gg in ipairs(b.glints) do
            local ddx, ddy = c[1] - gg[1], c[2] - gg[2]
            if ddx * ddx + ddy * ddy < minD then far = false break end
          end
          if far then
            local k2 = #b.glints + 1
            -- Phase: stratified around the loop (so the lit stars are spread out
            -- in time rather than clumping by chance) plus a little hash jitter
            -- so it does not look mechanical; and a whole number of pulses per
            -- loop (1..STAR_MULT) so the twinkle is seamless when the animation
            -- wraps.
            local ph = (k2 - 1) / TERA.STAR_COUNT + TERA.hash(k2 * 9176 + 13) * 0.25
            ph = ph - math.floor(ph)
            b.glints[k2] = { c[1], c[2], ph,
              1 + math.floor(TERA.hash(k2 * 3571 + 29) * TERA.STAR_MULT) }
          end
        end
      end
      b.glintCands = nil
    end
    -- TERA RIM LIGHT: the silhouette's edge is lifted toward a near-white glow
    -- and the glow then fades INWARD over RIM_FALLOFF pixels, so the crystal
    -- reads as lit from within (a Fresnel rim plus a short inner bloom) instead
    -- of wearing a flat one-pixel sticker outline.  It runs as a SECOND pass
    -- over the baked box because it needs each pixel's distance to the edge: a
    -- cheap two-sweep CHAMFER over "how far is the nearest transparent pixel"
    -- gives that distance for the whole box at the cost of two passes, and the
    -- rim strength is then read straight off it.  It only ever rewrites pixels
    -- the bake already wrote, so the silhouette -- and every alpha -- is exactly
    -- what the plain sheet would have produced (the caller's out.a = sprite.a
    -- rule is untouched).
    if tera then
      local tint = tera.tint
      local rr = tint[1] * TERA.RIM_TINT + (1 - TERA.RIM_TINT)
      local rg = tint[2] * TERA.RIM_TINT + (1 - TERA.RIM_TINT)
      local rb = tint[3] * TERA.RIM_TINT + (1 - TERA.RIM_TINT)
      local dist = {}
      local big = dw + dh + 8
      for ty = 0, dh - 1 do
        for tx = 0, dw - 1 do
          local ca = select(4, out:getPixel(ox + tx, oy + ty)) or 0
          dist[ty * dw + tx] = (ca > 0) and big or 0
        end
      end
      for ty = 0, dh - 1 do
        for tx = 0, dw - 1 do
          local i = ty * dw + tx
          local d = dist[i]
          if d > 0 then
            if tx > 0 and dist[i - 1] + 1 < d then d = dist[i - 1] + 1 end
            if ty > 0 then
              if dist[i - dw] + 1 < d then d = dist[i - dw] + 1 end
              if tx > 0 and dist[i - dw - 1] + 1 < d then
                d = dist[i - dw - 1] + 1
              end
              if tx < dw - 1 and dist[i - dw + 1] + 1 < d then
                d = dist[i - dw + 1] + 1
              end
            end
            dist[i] = d
          end
        end
      end
      for ty = dh - 1, 0, -1 do
        for tx = dw - 1, 0, -1 do
          local i = ty * dw + tx
          local d = dist[i]
          if d > 0 then
            if tx < dw - 1 and dist[i + 1] + 1 < d then d = dist[i + 1] + 1 end
            if ty < dh - 1 then
              if dist[i + dw] + 1 < d then d = dist[i + dw] + 1 end
              if tx < dw - 1 and dist[i + dw + 1] + 1 < d then
                d = dist[i + dw + 1] + 1
              end
              if tx > 0 and dist[i + dw - 1] + 1 < d then
                d = dist[i + dw - 1] + 1
              end
            end
            dist[i] = d
          end
        end
      end
      for ty = 0, dh - 1 do
        for tx = 0, dw - 1 do
          local d = dist[ty * dw + tx]
          if d > 0 and d <= TERA.RIM_FALLOFF then
            local s = TERA.RIM_STRENGTH * (1 - (d - 1) / TERA.RIM_FALLOFF)
            if s > 0 then
              local px, py = ox + tx, oy + ty
              local cr, cg, cb, ca = out:getPixel(px, py)
              out:setPixel(px, py, cr + (rr - cr) * s, cg + (rg - cg) * s,
                cb + (rb - cb) * s, ca)
            end
          end
        end
      end
    end
    -- TERA STAR GLINTS: the four-pointed sparkles -- the single cue that makes
    -- the reference read as FLASHY rather than merely tinted.  This is the
    -- sparkles' own animation.  The anchors are the creature's own opaque pixels,
    -- settled once per sheet (see the pick below the bake loop); here each is
    -- stamped with the star sprite, whose {dx, dy, weight} offsets blend each
    -- pixel that far from the anchor TOWARD WHITE by its weight -- the sparkle
    -- is light laid over the facet, so whatever shard sits under it shows
    -- through, dimmed only by the weight.  NOTHING IS EVER DARKENED: an earlier
    -- version deepened a ring around each star to separate it from the facet,
    -- and on a light sky, gem or water tile that ring read as a dirty smudge
    -- around every glint.  Three things happen per anchor per frame: the star
    -- sprite is scaled with the bake's own magnification (TERA.starsFor, so a
    -- big bake gets a big sparkle rather than a speck), the anchor is shifted by
    -- the same rigid offset the lattice rides on (so the sparkle stays on its
    -- facet as the creature moves), and every weight is multiplied by that
    -- anchor's own twinkle -- a smooth pulse of the phase/pulses-per-loop dealt
    -- at the pick -- so the stars blink on and off all over the lightest facets
    -- as the animation plays.  As with the rim, only pixels the bake already
    -- wrote are touched, so the silhouette and every alpha stay the plain
    -- sheet's.
    if tera and b.glints then
      local stars = b.stars
      if not stars then
        local ss = round(dw / cw)
        if ss < 1 then ss = 1 end
        stars = TERA.starsFor(ss)
        b.stars = stars
      end
      local fk = f + 1
      for gi = 1, #b.glints do
        local g = b.glints[gi]
        -- A smooth pulse over this anchor's own cycle within the loop: the sine
        -- gives it a rise and a fall, and FLOOR/FULL gate it so the star has a
        -- clear ON stretch and a clear OFF stretch rather than hovering at half
        -- brightness.  A whole number of pulses per loop keeps it seamless when
        -- the animation wraps.
        local u = (fk / b.count) * g[4] + g[3]
        u = u - math.floor(u)
        local gg = (math.sin(math.pi * u) - TERA.STAR_FLOOR)
          / (TERA.STAR_FULL - TERA.STAR_FLOOR)
        if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
        local tw = gg * gg * (3 - 2 * gg)
        if tw > TERA.STAR_MIN then
          local ax, ay = g[1] + b.fdx, g[2] + b.fdy
          for _, s in ipairs(stars) do
            local gx, gy = ax + s[1], ay + s[2]
            if gx >= 0 and gy >= 0 and gx < dw and gy < dh then
              local px, py = ox + gx, oy + gy
              local cr, cg, cb, ca = out:getPixel(px, py)
              if ca and ca > 0 then
                local w = s[3] * tw
                out:setPixel(px, py, cr + (1 - cr) * w, cg + (1 - cg) * w,
                  cb + (1 - cb) * w, ca)
              end
            end
          end
        end
      end
    end
    -- BATTLE SHADOWS: the ground contact shadow, composited behind the sprite
    -- (see stampShadow).  Drawn before the cloud so both are part of this
    -- frame's own canvas.
    if b.shadowArt then SHADOW.stamp(b, out) end
    -- DYNAMAX CLOUD: composited OVER the baked sprite, so it is part of every
    -- frame of the animation rather than a second draw pass -- it cannot flicker
    -- with the frame clock and it rides the same resample.  Its bottom edge
    -- sinks CLOUD_SINK pixels past the sprite's own content top, so it caps the
    -- head (the crown reading) rather than hovering a clear pixel above it; in a
    -- fixed box the part that rides above the head has already been given its
    -- band (setupFrames), and in a short-headed box frame the cloud is simply
    -- clamped into the canvas.  The cloud is blitted from the AREA-filtered copy
    -- (cloudScaled), not sampled nearest, because it is minified many-fold; and
    -- the composite is ordinary source-over, so its soft lower edge blends into
    -- the head it rests on.
    if b.cloud and b.cloudH and b.cloudH > 0 then
      local c = b.cloud
      local cH = b.cloudH
      local cW = round(cH * c.cw / c.ch)
      if cW > box.w then cW = box.w end
      if cW < 1 then cW = 1 end
      local cX = ox + math.floor((dw - cW) / 2)
      local cY = (contentTop or oy) + (b.cloudSink or 0) - cH
      if cY < 0 then cY = 0 end
      local small = cloudScaled(c, cW, cH).px
      for ty = 0, cH - 1 do
        local py = cY + ty
        if py >= 0 and py < box.h then
          for tx = 0, cW - 1 do
            local px = cX + tx
            if px >= 0 and px < box.w then
              local o = (ty * cW + tx) * 4
              local ca = small[o + 4]
              if ca and ca > 0 then
                local cr, cg, cb = small[o + 1], small[o + 2], small[o + 3]
                local er, eg, eb, ea = out:getPixel(px, py)
                ea = ea or 0
                local oa = ca + ea * (1 - ca)
                if oa > 0 then
                  local nr = (cr * ca + (er or 0) * ea * (1 - ca)) / oa
                  local ng = (cg * ca + (eg or 0) * ea * (1 - ca)) / oa
                  local nb = (cb * ca + (eb or 0) * ea * (1 - ca)) / oa
                  if nr > 1 then nr = 1 elseif nr < 0 then nr = 0 end
                  if ng > 1 then ng = 1 elseif ng < 0 then ng = 0 end
                  if nb > 1 then nb = 1 elseif nb < 0 then nb = 0 end
                  if oa > 1 then oa = 1 end
                  out:setPixel(px, py, nr, ng, nb, oa)
                end
              end
            end
          end
        end
      end
    end
    -- 3DB FLIP (option): mirror the finished frame across its vertical axis, so
    -- a front-on PLAYER sprite (3DB FRONTAL) aims at the foe to the right
    -- instead of facing left the way the pack's front art is drawn.  Done on
    -- the WHOLE canvas, after the crystal, cloud and shadow are composited, so
    -- the sprite and everything riding it turn together and stay registered --
    -- a mirror of the sprite alone would leave the shadow and the decoration
    -- pointing the old way.  Only player-side sheets ever set b.flip
    -- (see the battle seams), so a back sheet and every foe are untouched.
    if b.flip then
      local bw, bh = box.w, box.h
      local m = love.image.newImageData(bw, bh)
      for y = 0, bh - 1 do
        for x = 0, bw - 1 do
          local r, g, bl, a = out:getPixel(bw - 1 - x, y)
          m:setPixel(x, y, r or 0, g or 0, bl or 0, a or 0)
        end
      end
      out = m
    end
    local img = love.graphics.newImage(out)
    img:setFilter("nearest", "nearest")
    sheet.frames = sheet.frames or {}
    sheet.frames.__spriteStyle = sheet.style
    sheet.frames.__bwTiming = sheet.bwTiming
    sheet.frames.__ee = sheet.ee
    -- Optional layout metadata for final-resolution scene renderers. These
    -- bounds come from the whole strip's union, before individual frames are
    -- baked, so an idle pose never changes its size or ground origin. Natural
    -- mode's bottom padding is intentional hover height, not empty feet space.
    if b.natural then
      sheet.frames.__spriteLayout = {x0=0, y0=0, x1=box.w,
        y1=b.shadowArt and box.h or b.oy+b.dh, ox=box.w/2, ground=box.h}
    end
    sheet.frames[f + 1] = img
    if GEN == 3 then
      sheet.gen3FrameData = sheet.gen3FrameData or {}
      sheet.gen3FrameData.__spriteStyle = sheet.style
      sheet.gen3FrameData.__bwTiming = sheet.bwTiming
      sheet.gen3FrameData.__ee = sheet.ee
      sheet.gen3FrameData[f + 1] = out
      sheet.gen3BattleLift = b.gen3BattleLift
    end
    if b.gen3BattleLift ~= nil then gen3BattleLiftByImage[img] = b.gen3BattleLift end
    -- FireRed's starter-choice panel keeps the `Image` it receives instead of
    -- asking Pokemon.frontPic again on every draw.  A pending sheet therefore
    -- needs a tiny mutable stand-in: copy this newly baked frame into every
    -- stand-in now, then pollAll below advances it just like the normal frame
    -- provider.  The panel sees the same Image object change underneath it,
    -- so the very first starter preview appears and animates.
    if type(sheet.proxies) == "table" then
      for _, proxy in pairs(sheet.proxies) do
        if type(proxy) == "table" and proxy.image and proxy.image.replacePixels then
          local proxyFrame = out
          -- Oak's starter-choice window is a presentation box, not a battle
          -- field: its cached proxy should centre the creature vertically
          -- instead of inheriting the battle frame's feet-on-the-ground rule.
          if proxy.center then proxyFrame=DATA.centerPreview(out)end
          proxy.data = proxy.data or {}
          -- Pending previews own a separate array until baking completes.
          -- Keep its playback metadata with the pixels, including after resets.
          proxy.data.__spriteStyle = sheet.style
          proxy.data.__ee = sheet.ee
          proxy.data.__bwTiming = sheet.bwTiming
          proxy.data[f + 1] = proxyFrame
          if proxy.pic then proxy.pic.__completeDexBattleLift = b.gen3BattleLift end
          pcall(proxy.image.replacePixels, proxy.image, proxyFrame)
          proxy.lastFrame = f + 1
        end
      end
    end
    ourFrames[img] = true
    b.frame = f + 1
    return b.frame >= b.count
  end

  -- One bounded step.  Returns true when the sheet is no longer "building".
  local function advanceBuild(sheet)
    local b = sheet.build
    if not b then return true end
    if b.phase == "scan" then
      scanChunk(b, SCAN_ROWS)
      if b.row < b.H then return false end
      if not setupFrames(b) then
        finishFailed(sheet, "sheet has no opaque pixels")
        return true
      end
      return false
    end
    if buildOneFrame(sheet) then
      sheet.build = nil
      finishReady(sheet, sheet.how or "built")
      return true
    end
    return false
  end

  local function stepBuilds()
    if next(sheets) == nil then return end
    local deadline = now() + BUILD_BUDGET
    for _, sheet in pairs(sheets) do
      if sheet.status == "building" then
        while true do
          if advanceBuild(sheet) then break end
          if now() >= deadline then return end
        end
      end
    end
  end

  -- -- sheet source: the mod's OWN assets/ folder -------------------------

  -- Move a fresh sheet onto the "needs decoding" track.  assets/ is the only
  -- source.  A sheet that is not installed there is NOT latched as dead: it
  -- stays "new" with a retryAt, so a file copied into assets/ while the game is
  -- running is picked up on the next recheck.
  local function sheetStart(sheet)
    if sheet.status ~= "new" then return end
    if sheet.retryAt and frameCounter < sheet.retryAt then return end
    local folder = localFolder(sheet.back and not sheet.front, sheet.shiny)
    local rel = "assets/" .. folder .. "/" .. sheet.stem .. ".png"
    sheet.static = false
    sheet.ee = false
    sheet.sourceStem = sheet.stem
    sheet.bwPeer, sheet.bwFolder, sheet.bwTiming = nil, nil, nil
    sheet.kimData,sheet.kimRecord=nil,nil
    if sheet.style==5 then
      local peer=DATA.kimPeer()
      if peer then
        if not DATA.kimSpecies then DATA.kimSpecies={};for species,stem in pairs(DATA.species)do if not DATA.kimSpecies[stem]then DATA.kimSpecies[stem]=species end end end
        local species=DATA.kimSpecies[sheet.stem]or sheet.stem
        if not DATA.kimDex and mod.rootRead then
          DATA.kimDex={};local roster=assert((loadstring or load)(assert(mod:rootRead('encounters/roster.lua'))))()
          for _,row in ipairs(roster)do DATA.kimDex[row.name]=row.id end
        end
        local dex=DATA.kimDex and DATA.kimDex[species]
        if sheet.stem:match('_female$')then species=(DATA.kimSpecies[sheet.stem:gsub('_female$','')]or species)..'_FEMALE'end
        dex=dex or DATA.kimDex and DATA.kimDex[species:gsub('_FEMALE$',''):gsub('_female$','')]
        local ok,data,record=pcall(peer.getDexSpriteSheet,species,sheet.back and not sheet.front and 'back'or 'front',sheet.shiny,dex)
        if ok and data and record then
          sheet.kimData,sheet.kimRecord,sheet.bwTiming=data,record,record.timing
          sheet.rel,sheet.status=nil,'local';return
        end
      end
      -- Missing KIM species/forms retain the matching existing artwork.
      local files=(DATA.ee and DATA.ee.files[folder])or {}
      if files[sheet.stem]then rel='assets/ee/'..folder..'/'..sheet.stem..'.png';sheet.ee=true end
    end
    if sheet.style == 3 or sheet.style == 4 then
      local files = (DATA.ee and DATA.ee.files[folder]) or {}
      if files[sheet.stem] then
        rel = "assets/ee/" .. folder .. "/" .. sheet.stem .. ".png"
        sheet.ee = true
      end
    end
    if sheet.style == 2 then
      local peer = DATA.bwPeer()
      if peer then
        local ok, timing = pcall(peer.sprite, folder, sheet.stem)
        if ok and type(timing) == "table" then
          sheet.bwPeer, sheet.bwFolder, sheet.bwTiming = peer, folder, timing
          sheet.rel, sheet.status = nil, "local"
          return
        end
      end
    end
    if sheet.style == 1 then
      local files = DATA.static.files[folder] or {}
      local stem = files[sheet.stem] and sheet.stem or DATA.static.aliases[sheet.stem]
      if stem and files[stem] then
        rel = "assets/static/" .. folder .. "/" .. stem .. ".png"
        sheet.static, sheet.sourceStem = true, stem
      end
    end
    local info = mod:info(rel)
    if info and info.type == "file" then
      sheet.rel = rel
      sheet.status = "local"
      return
    end
    if debugOn() and not sheet.warnedStem then
      sheet.warnedStem = true
      if DATA.stems[sheet.stem] then
        mod.log:info("g9-battle-sprites: %s is not in assets/%s/ -- vanilla "
          .. "pic in use", sheet.stem, folder)
      else
        mod.log:info("g9-battle-sprites: stem %s is not in this pack -- "
          .. "species uses the vanilla pic", sheet.stem)
      end
    end
    if not sheet.diagMissing then
      sheet.diagMissing = true
      diag.stats.missing = diag.stats.missing + 1
      diagPush("%s NO PNG", sheet.stem)
    end
    sheet.retryAt = frameCounter + RECHECK_FRAMES
  end

  local function evictIfNeeded()
    if readyCount <= MAX_SHEETS then return end
    local victim, oldest = nil, math.huge
    for _, sheet in pairs(sheets) do
      if sheet.status == "ready" and sheet.lastUsed
        and (frameCounter - sheet.lastUsed) > EVICT_AGE_FRAMES then
        if sheet.lastUsed < oldest then
          oldest = sheet.lastUsed
          victim = sheet
        end
      end
    end
    if victim then
      victim.frames = nil
      victim.gen3FrameData = nil
      victim.status = "new"
      readyCount = readyCount - 1
    end
  end

  -- SPRITE SIZE / GROUND ANCHOR / FLOATERS changes cannot be seen in
  -- already-baked frames, so every sheet is requeued when any of them changes
  -- (a cheap re-fetch from the mod's own assets/, spread over frames by the
  -- build budget).  The signature starts nil and is seeded on the first poll so
  -- a fresh session never throws away work.
  local lastSizeSig = nil
  local function sizeSig()
    local d = spriteSizeMode()
    return tostring(d)
      .. ":s" .. DATA.spriteStyle()
      .. ":e" .. DATA.styleFor(false, true) .. ":p" .. DATA.styleFor(true, true)
      .. ":" .. spriteAnchor() .. (floatOn() and "F" or "f")
      .. ":" .. (SHADOW.on() and "B" or "b")
  end

  local function pollAll()
    frameCounter = frameCounter + 1
    diag.on = debugOn()
    if next(sheets) == nil then return end

    local sig = sizeSig()
    if lastSizeSig == nil then
      lastSizeSig = sig
    elseif sig ~= lastSizeSig then
      lastSizeSig = sig
      for _, sheet in pairs(sheets) do
        if sheet.status == "ready" then readyCount = readyCount - 1 end
        sheet.status = "new"
        sheet.style = DATA.styleFor(sheet.back, sheet.shadow)
        sheet.retryAt = nil
        sheet.frames = nil
        sheet.build = nil
        sheet.gen3FrameData = nil
        sheet.gen3BattleLift = nil
        for _, proxy in pairs(sheet.proxies or {}) do
          proxy.data = {}; proxy.lastFrame = nil
        end
      end
    end

    for _, sheet in pairs(sheets) do
      if sheet.status == "local" then
        local id, why = decodeSheet(sheet)
        if id then
          sheet.bytes = nil
          sheet.how = why
          if not beginBuild(sheet, id) then
            finishFailed(sheet, "cannot lay out sheet")
          end
        else
          finishFailed(sheet, "decode failed: " .. tostring(why))
        end
      end
    end

    stepBuilds()
    -- Keep the few mutable FireRed preview Images current after the menu has
    -- cached them. Gen3 battle/menu providers share one per sheet, so cached
    -- and freshly requested pictures both advance without palette changes.
    for _, sheet in pairs(sheets) do
      if type(sheet.proxies) == "table" then
        for _, proxy in pairs(sheet.proxies) do
          local data = type(proxy) == "table" and proxy.data
          if proxy and proxy.image and proxy.image.replacePixels
            and type(data) == "table" and #data > 0 then
            local i = 1
            if animateOn(sheet.style) then
              i = data.__bwTiming and DATA.bwFrame(data.__bwTiming, now(), #data)
                or DATA.eeFrame(data, now(), fpsValue(), #data)
                or (math.floor(now() * fpsValue()) % #data + 1)
            end
            if data[i] and proxy.lastFrame ~= i then
              pcall(proxy.image.replacePixels, proxy.image, data[i])
              proxy.lastFrame = i
            end
          end
        end
      end
    end
    evictIfNeeded()
  end

  -- Returns (frames, pending). `frames` is the baked frame array once the sheet
  -- is ready (nil until then). `pending` is true while the sheet EXISTS in
  -- assets/ and is still on its way -- "local" (file found, not yet decoded)
  -- or "building" (decoding done, frames baking) -- i.e. exactly the window in
  -- which a caller must NOT fall back to the vanilla pic, because a real sheet
  -- is coming. A file that is missing ("new" after sheetStart) or unusable
  -- ("failed") reports pending = false, so vanilla is still drawn for a species
  -- this pack genuinely has no art for. Telling those two apart is what lets
  -- every wrap below suppress the vanilla pic DURING a build -- the native
  -- flash a trainer's send-out used to show for the mon's first frames --
  -- without ever hiding a mon the pack does not manage.
  --
  -- NB: getFrames has TWO return values, so call it in its own statement: the
  -- expression `stem and getFrames(...)` truncates the call to ONE value and
  -- `pending` is silently lost (which reads as "not pending" and lets the
  -- vanilla pic through). Every call site below guards the stem separately.
  local function getFrames(back, shiny, stem, boxOverride, divisor, zoom, maxH, fill, scale, natural, tera, cloud, shadow, front, flip)
    if not stem then return nil, false end
    local key = sheetKey(back, shiny, stem, boxOverride, divisor, zoom, maxH, fill, scale, natural, tera, cloud, shadow, front, flip)
    local sheet = sheets[key]
    if not sheet then
      sheet = { key = key, back = back, shiny = shiny, stem = stem,
                style = DATA.styleFor(back, shadow),
                box = boxOverride, divisor = divisor, zoom = zoom,
                maxH = maxH, fill = fill, scale = scale,
                natural = natural and true or false, tera = tera,
                cloud = cloud and true or false,
                shadow = shadow and true or false,
                front = front and true or false,
                flip = flip and true or false,
                status = "new" }
      sheets[key] = sheet
    end
    if sheet.status == "new" then sheetStart(sheet) end
    if sheet.status == "ready" then
      sheet.lastUsed = frameCounter
      return sheet.frames, false
    end
    -- Mobile portrait builds can spend several frames baking a long animated
    -- strip.  Do not keep the entire battler transparent until EVERY frame is
    -- done: as soon as the first canvas exists it is a valid static sprite.
    -- Returning the partial array lets frameIndex hold on that frame (then
    -- naturally begin animating as later frames arrive), instead of making an
    -- otherwise healthy encounter look like it has no PokÃ©mon at all.
    if sheet.status == "building" and type(sheet.frames) == "table"
      and #sheet.frames > 0 then
      sheet.lastUsed = frameCounter
      return sheet.frames, false
    end
    return nil, sheet.status == "local" or sheet.status == "building"
  end

  -- The draw-path entry point: the Tera film is a WANT, never a requirement.
  -- A Terastallized Pokemon's filmed sheet takes a moment to bake (it is a
  -- second, tinted bake of the same art), and blanking the sprite for those
  -- frames would read as a glitch -- the exact "native flash" the mod already
  -- goes out of its way to avoid.  So while the filmed sheet is still coming,
  -- the plain sheet is handed out instead and the crystal simply pops in when
  -- it is ready.  Only if the plain sheet is ALSO not ready yet is the caller
  -- told `pending`, and its existing draw-nothing-rather-than-vanilla rule
  -- applies.  (getFrames has two return values, so its calls sit in their own
  -- statements here, as everywhere else.)
  local function getFramesFor(back, shiny, stem, tera, cloud, box, divisor, zoom, maxH, fill, scale, natural, shadow, front, flip)
    if not stem then return nil, false end
    -- The filmed/clouded sheet (both, when a Pokemon somehow carries both) is
    -- the wanted one; the plain sheet is the fallback while it bakes.
    local pending = false
    if tera or cloud then
      local wf, wp = getFrames(back, shiny, stem, box, divisor, zoom, maxH, fill, scale, natural, tera, cloud, shadow, front, flip)
      if wf then return wf, false end
      pending = wp
    end
    local base, bpending = getFrames(back, shiny, stem, box, divisor, zoom, maxH, fill, scale, natural, false, false, shadow, front, flip)
    if base then return base, false end
    return nil, pending or bpending
  end

  -- The BATTLE shadowed sheet, for the three battle seams only.  Routing every
  -- battle request through here is what keeps BATTLE SHADOWS out of the dex and
  -- the summary: they call getFrames directly, without the shadow flag, so the
  -- very same front box is a distinct, shadow-free sheet for them.
  local function getBattleFrames(back, shiny, stem, tera, cloud, box, divisor, zoom, maxH, fill, scale, natural, front, flip)
    return getFramesFor(back, shiny, stem, tera, cloud, box, divisor, zoom, maxH, fill, scale, natural, true, front, flip)
  end

  -- ---------------------------------------------------------------------------
  -- Animation clock
  -- ---------------------------------------------------------------------------
  local function frameIndex(count, frames)
    if count < 1 then return 1 end
    if count == 1 or not animateOn(frames and frames.__spriteStyle) then return 1 end
    if frames and frames.__bwTiming then return DATA.bwFrame(frames.__bwTiming, now(), count) end
    local ee = DATA.eeFrame(frames, now(), fpsValue(), count)
    if ee then return ee end
    local i = math.floor(now() * fpsValue()) % count
    return i + 1
  end

  -- ---------------------------------------------------------------------------
  -- gen1 (Red/Blue/Yellow): drawPicsLayer substitution
  -- ---------------------------------------------------------------------------
  local managedSpecies = {}   -- species -> whether a frame Image is in use now

  local function ensureBattler(battler, back)
    if type(battler) ~= "table" then return end
    if not (wantEnabled() and type(battler.mon) == "table") then return end
    diag.stats.gen1 = diag.stats.gen1 + 1

    local stem, shiny = monStem(battler.mon, DATA.styleFor(back, true))
    -- The crystal film is looked up live (see teraTypeOf); nil means "no film",
    -- which is the case for a Pokemon that has not Terastallized, for an
    -- unmapped type, and for a missing battle_forms.
    local tera = teraTypeOf(battler.mon, battler)
    -- The Dynamax cloud is looked up live the same way (see dynamaxOf).
    local cloud = dynamaxOf(battler.mon, battler)
    -- 3DB FRONTAL / 3DB FLIP (options): the PLAYER side is the back slot, so
    -- this is where a front-sourced, optionally mirrored sheet is asked for.
    -- The foe (back == false) already shows front art and is never flipped.
    local front, flip = DATA.playerView(back)
    -- The call must sit in its own statement: `stem and getFrames(...)` would
    -- collapse it to a single value and drop the `pending` flag.
    local frames, pending = nil, false
    if stem then
      frames, pending = getBattleFrames(back, shiny, stem, tera, cloud,
        nil, nil, nil, nil, nil, nil, nil, front, flip)
    end
    -- Remember the vanilla pic BEFORE anything can blank it, so a later frame
    -- (or turning the mod off) can always put it back.
    if battler.__g9bsVanilla == nil and type(battler.sprite) == "string" then
      battler.__g9bsVanilla = battler.sprite
    end
    if not frames then
      if pending then
        -- The sheet is on its way. Draw NOTHING this frame rather than the
        -- vanilla pic: the sprite simply appears, already at its true size,
        -- the frame the bake finishes -- a native flash is never shown.
        battler.__g9bsFrame = nil
        battler.sprite = nil
        return
      end
      -- Not available at all (a species this pack has no sheet for, or one
      -- that failed to load): leave the vanilla pic exactly as it was.
      if battler.mon.species then managedSpecies[battler.mon.species] = false end
      if battler.__g9bsVanilla ~= nil then
        battler.sprite = battler.__g9bsVanilla
      end
      battler.__g9bsFrame = nil
      return
    end
    managedSpecies[battler.mon.species] = true
    local img = frames[frameIndex(#frames, frames)]
    battler.__g9bsFrame = img
    battler.sprite = img
    if debugOn() and battler.__g9bsLogged ~= stem then
      battler.__g9bsLogged = stem
      diag.lastResolve = tostring(battler.mon.species) .. "->" .. stem
      diagPush("%s -> %s", battler.mon.species, stem)
      mod.log:info("g9-battle-sprites: %s -> %s%s (%s)",
        tostring(battler.mon.species), stem, shiny and " [shiny]" or "",
        back and "back" or "front")
    end
  end

  local function installGen1()
    local ok, BattleState = pcall(require, "src.battle.BattleState")
    if not (ok and type(BattleState) == "table"
      and type(BattleState.drawPicsLayer) == "function") then
      return false
    end
    if BattleState.__g9BattleSprites then return true end
    BattleState.__g9BattleSprites = true
    GEN = 1

    local vanillaLayer = BattleState.drawPicsLayer
    function BattleState:drawPicsLayer(...)
      if wantEnabled() then
        ensureBattler(self.enemy, false)
        ensureBattler(self.player, true)
      end
      return vanillaLayer(self, ...)
    end

    -- Our frames are pre-baked to the on-screen box, so the pic scale is 1
    -- (the vanilla gen1 back pic is a 32x32 image drawn at 2x).
    local vanillaScale = BattleState.resolveBattleScale
    if type(vanillaScale) == "function" then
      BattleState.resolveBattleScale = function(data, side, path, species, ...)
        if wantEnabled() and species and managedSpecies[species] then
          return 1
        end
        return vanillaScale(data, side, path, species, ...)
      end
    end

    -- Full-colour opt-out for the SGB/GBC zone post-pass: mark the rect our
    -- pic occupies so it is re-blitted unshaded (the engine's own trueColor
    -- mechanism, src/render/PaletteFX.markTrueColor).  x/y already carry the
    -- shake/slide offsets, so they must NOT be added again here.
    local vanillaBattlerPic = BattleState.drawBattlerPic
    if type(vanillaBattlerPic) == "function" then
      local PFX = nil
      local PFXok = false
      function BattleState:drawBattlerPic(battler, x, y, scale, shakeX, shakeY)
        local img = type(battler) == "table" and battler.__g9bsFrame
        if img and ourFrames[img] then
          if not PFXok then
            PFXok = true
            local okP, m = pcall(require, "src.render.PaletteFX")
            PFX = okP and m or nil
          end
          if PFX and PFX.markTrueColor then
            pcall(PFX.markTrueColor, x, y,
              img:getWidth() * (scale or 1), img:getHeight() * (scale or 1))
          end
        end
        return vanillaBattlerPic(self, battler, x, y, scale, shakeX, shakeY)
      end
    end
    return true
  end

  -- ---------------------------------------------------------------------------
  -- gen3 (FireRed): substitute the shared 64x64 picture provider.
  -- FireRed's battle, PokÃ©dex, party and summary screens all resolve art through
  -- src.core.game3.pokemon.frontPic/backPic, so this one seam covers every
  -- relevant screen and preserves the engine's normal placement/animation.
  -- ---------------------------------------------------------------------------
  local function installGen3()
    local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
    if not (ok and type(Pokemon) == "table"
      and type(Pokemon.frontPic) == "function") then return false end
    if Pokemon.__g9BattleSprites then
      if Pokemon.__completeDexEnsurePics then Pokemon.__completeDexEnsurePics() end
      return true
    end
    Pokemon.__g9BattleSprites = true
    GEN = 3

    -- FireRed's PARTY, PC and summary menus call Pokemon.icon directly.  The
    -- vanilla provider only knows icon files extracted from the ROM, so every
    -- added National-Dex species returned nil here.  Feed that provider one
    -- true FireRed-size sheet per base species: two vertically stacked 32x32
    -- frames, point-sampled from the bundled 64x64 HD atlas at build time.
    -- This is deliberately below the provider rather than the content icon
    -- registry; game3 never consults that registry for these screens.
    local vanillaIcon = Pokemon.icon
    local hdPartyIcons = {}
    local missingPartyIcons = {}
    local function partyIcon(species)
      if not partyIconsOn() then return vanillaIcon(species) end
      local n = tonumber(species)
      if not n or n < 1 then return vanillaIcon(species) end
      local cached = hdPartyIcons[n]
      if cached then return cached end
      if missingPartyIcons[n] then return vanillaIcon(species) end
      local name = type(Pokemon.keyName) == "function" and Pokemon.keyName(n)
      if type(name) ~= "string" or name == "" then
        missingPartyIcons[n] = true
        return vanillaIcon(species)
      end
      local rel = "assets/icons/firered_menu/" .. name .. ".png"
      if not mod:info(rel) then
        missingPartyIcons[n] = true
        return vanillaIcon(species)
      end
      local okImage, image = pcall(mod.assets.image, mod.assets, rel)
      if not okImage or not image then
        missingPartyIcons[n] = true
        mod.log:warn("g9-battle-sprites: FireRed party icon failed for %s", name)
        return vanillaIcon(species)
      end
      local okQuads, q0, q1 = pcall(function()
        return love.graphics.newQuad(0, 0, 32, 32, 32, 64),
          love.graphics.newQuad(0, 32, 32, 32, 32, 64)
      end)
      if not okQuads then
        missingPartyIcons[n] = true
        return vanillaIcon(species)
      end
      local entry = {
        image = image, w = 32, h = 32, sheetH = 64, frames = 2,
        quads = { [0] = q0, [1] = q1 },
      }
      hdPartyIcons[n] = entry
      return entry
    end
    Pokemon.icon = partyIcon

    -- A sheet is built asynchronously.  Never send a managed post-Gen3 slot
    -- back to FireRed's ROM decoder while that build is pending: those slots
    -- do not exist in the ROM sprite table and decode as a solid red square.
    local blankPic = nil
    local function transparentPic()
      if blankPic ~= nil then return blankPic or nil end
      blankPic = false
      if not (love and love.image and love.image.newImageData
        and love.graphics and love.graphics.newImage) then return nil end
      local okData, data = pcall(love.image.newImageData, 64, 64)
      if not (okData and data) then return nil end
      local okImage, image = pcall(love.graphics.newImage, data)
      if not (okImage and image) then return nil end
      if image.setFilter then pcall(image.setFilter, image, "nearest", "nearest") end
      blankPic = { image = image, w = 64, h = 64 }
      return blankPic
    end

    -- Unlike transparentPic this is deliberately one mutable Image per sheet.
    -- The starter selector caches it once, and pollAll replaces its pixels as
    -- each frame becomes available (see buildOneFrame).  The image starts
    -- transparent only for the few build ticks before frame one is ready.
    local function pendingPic(back, shiny, stem, battle, front, flip)
      local key = sheetKey(back, shiny, stem,
        back and BACK_BOX_GEN3 or FRONT_BOX_GEN3, nil, nil, GEN3_MAX_ART_H, nil, nil, nil, nil, nil, battle, front, flip)
      local sheet = sheets[key]
      if not sheet then return nil end
      sheet.proxies = sheet.proxies or {}
      if sheet.proxies.gen3 then return sheet.proxies.gen3.pic end
      if not (love and love.image and love.image.newImageData
        and love.graphics and love.graphics.newImage) then return nil end
      local okData, data = pcall(love.image.newImageData, 64, 64)
      if not (okData and data) then return nil end
      local okImage, image = pcall(love.graphics.newImage, data)
      if not (okImage and image) then return nil end
      if image.setFilter then pcall(image.setFilter, image, "nearest", "nearest") end
      local frameData=sheet.gen3FrameData or {}
      if not battle then
        local centered={};for k,v in pairs(frameData)do centered[k]=type(k)=='number'and DATA.centerPreview(v)or v end
        frameData=centered
      end
      local proxy = { image = image, data = frameData, lastFrame = nil, center = not battle }
      proxy.pic = { image = image, w = 64, h = 64 }
      sheet.proxies.gen3 = proxy
      local i = frameIndex(#proxy.data, proxy.data)
      if proxy.data[i] and image.replacePixels then
        image:replacePixels(proxy.data[i]); proxy.lastFrame = i
      end
      proxy.pic.__completeDexBattleLift = sheet.gen3BattleLift
      return proxy.pic
    end

    local function extendedSpecies(species)
      if type(Pokemon.national) == "function" then
        local okN, national = pcall(Pokemon.national, species)
        if okN and type(national) == "number" then return national > 386 end
      end
      return type(species) == "number" and species >= 451
    end

    local function replacement(species, back, shiny)
      if not wantEnabled() then return nil, false, false end
      local okC, Compat = pcall(require, "src.mods.Gen3Compat")
      local name = okC and Compat and Compat.speciesName
        and Compat.speciesName(species) or nil
      local stem = resolveStem(name, DATA.styleFor(back, DATA.inGen3Battle))
      if not stem then return nil, false, false end
      local battle = DATA.inGen3Battle == true
      local front, flip = DATA.playerView(back and battle)
      local frames, pending = getFramesFor(back, shiny, stem, nil, false,
        back and BACK_BOX_GEN3 or FRONT_BOX_GEN3, nil, nil, GEN3_MAX_ART_H, nil, nil, nil, battle, front, flip)
      if not frames then
        -- The starter chooser caches this provider result.  Hand it a mutable
        -- placeholder while the animation bakes, rather than the shared blank
        -- image, so it can turn into frame one and keep animating in-place.
        if pending then
          local pic = pendingPic(back, shiny, stem, battle, front, flip)
          if pic then return pic, false, true end
        end
        return nil, pending, true
      end
      -- Screens may cache either the entry or its Image. Keep one animated
      -- Image per palette/side rather than a snapshot of the current frame.
      local proxy = pendingPic(back, shiny, stem, battle, front, flip)
      if proxy then return proxy, false, true end
      local image = frames[frameIndex(#frames, frames)]
      return image and { image = image, w = 64, h = 64,
        __completeDexBattleLift = gen3BattleLiftByImage[image] } or nil, false, true
    end

    local vanillaFront, vanillaBack = Pokemon.frontPic, Pokemon.backPic
    local ownedFront, ownedBack
    local firstFront, firstBack = vanillaFront, vanillaBack
    local fallingFront, fallingBack = false, false
    local function nativeFront(...)
      if fallingFront then return firstFront(...) end
      fallingFront = true
      local ok, result = pcall(vanillaFront, ...)
      fallingFront = false
      if not ok then error(result, 0) end
      return result
    end
    local function nativeBack(...)
      if fallingBack then return firstBack(...) end
      fallingBack = true
      local ok, result = pcall(vanillaBack, ...)
      fallingBack = false
      if not ok then error(result, 0) end
      return result
    end
    ownedFront = function(species, form, shiny, personality)
      local pic, pending, managed = replacement(species, false, shiny)
      if pic then return pic end
      if managed and (pending or extendedSpecies(species)) then
        return transparentPic() or nativeFront(species, form, shiny, personality)
      end
      return nativeFront(species, form, shiny, personality)or transparentPic()
    end
    Pokemon.frontPic = ownedFront
    Pokemon.frontSprite = ownedFront
    if type(vanillaBack) == "function" then
      ownedBack = function(species, form, shiny)
        local pic, pending, managed = replacement(species, true, shiny)
        if pic then return pic end
        if managed and (pending or extendedSpecies(species)) then
          return transparentPic() or nativeBack(species, form, shiny)
        end
        return nativeBack(species, form, shiny)
      end
    end
    Pokemon.backPic = ownedBack or vanillaBack
    -- Gen3Compat applies content after mod startup and can put its cached,
    -- normal PNG provider outside ours. Reclaim only these managed providers
    -- after startup/reload; preserve the late provider for unmanaged species.
    Pokemon.__completeDexEnsurePics = function()
      if Pokemon.frontPic ~= ownedFront then
        vanillaFront = Pokemon.frontPic
        Pokemon.frontPic = ownedFront
        Pokemon.frontSprite = ownedFront
      end
      if ownedBack and Pokemon.backPic ~= ownedBack then
        vanillaBack = Pokemon.backPic
        Pokemon.backPic = ownedBack
      end
    end
    -- Emerald's native mon-animation controller may request a specific ROM
    -- frame after frontPic. Keep our clock-driven animated sheet in that seam
    -- too, so a native shiny/static frame cannot overwrite the replacement.
    local okAnim, MonAnim = pcall(require, "src.core.game3.mon_anim")
    if okAnim and MonAnim and type(MonAnim.framePic) == "function"
        and not MonAnim.__completeDexAnimatedPics then
      MonAnim.__completeDexAnimatedPics = true
      local nativeFramePic = MonAnim.framePic
      MonAnim.framePic = function(species, frame, shiny, ...)
        if (tonumber(frame) or 0) ~= 0 then
          local pic, pending, managed = replacement(species, false, shiny)
          if pic then return pic end
          if managed and (pending or extendedSpecies(species)) then return transparentPic() end
        end
        return nativeFramePic(species, frame, shiny, ...)
      end
    end
    local okUi, Ui = pcall(require, "src.core.game3.battle.ui")
    if okUi and Ui and not Ui.__completeDexSpriteScope then
      Ui.__completeDexSpriteScope = true
      for _, name in ipairs({ "draw", "battlerPic", "levelUpSpriteSnapshot" }) do
        if type(Ui[name]) == "function" then
          local native = Ui[name]
          Ui[name] = function(...)
            local previous = DATA.inGen3Battle
            DATA.inGen3Battle = true
            local function pack(...) return { n = select("#", ...), ... } end
            local results = pack(pcall(native, ...))
            DATA.inGen3Battle = previous
            if not results[1] then error(results[2], 0) end
            return (unpack or table.unpack)(results, 2, results.n)
          end
        end
      end
    end
    return true
  end

  -- ---------------------------------------------------------------------------
  -- gen2 (Gold): BattleState:pic substitution
  -- ---------------------------------------------------------------------------
  local function installGen2()
    local ok, BattleState = pcall(require, "src.ui.gen2.BattleState")
    if not (ok and type(BattleState) == "table"
      and type(BattleState.pic) == "function") then
      return false
    end
    if BattleState.__g9BattleSprites then return true end
    BattleState.__g9BattleSprites = true
    GEN = 2

    local vanillaPic = BattleState.pic
    function BattleState:pic(mon, back)
      if wantEnabled() and type(mon) == "table" then
        diag.stats.pics = diag.stats.pics + 1
        local stem, shiny = monStem(mon, DATA.styleFor(back, true))
        local tera = teraTypeOf(mon, mon)
        local cloud = dynamaxOf(mon, mon)
        local frames, pending = nil, false
        if stem then
          -- 3DB FRONTAL / 3DB FLIP (options): `back` is the player's slot, so a
          -- back-side request may be re-sourced to the front sheet and mirrored
          -- (see ensureBattler for the same treatment on gen1).
          local isBack = back and true or false
          local front, flip = DATA.playerView(isBack)
          frames, pending = getBattleFrames(isBack, shiny, stem, tera, cloud,
            nil, nil, nil, nil, nil, nil, nil, front, flip)
        end
        if frames then
          managedSpecies[mon.species] = true
          if debugOn() and mon.__g9bsLogged ~= stem then
            mon.__g9bsLogged = stem
            diag.lastResolve = tostring(mon.species) .. "->" .. stem
            diagPush("%s -> %s", mon.species, stem)
            mod.log:info("g9-battle-sprites: %s -> %s%s (%s)",
              tostring(mon.species), stem, shiny and " [shiny]" or "",
              back and "back" or "front")
          end
          return frames[frameIndex(#frames, frames)], true, nil
        end
        if pending then
          -- The sheet is on its way: hand back NO image rather than the
          -- vanilla pic, so the native screen's own intro/send-out never
          -- flashes it while the pack bakes (drawPic returns early on a nil
          -- image, so nothing is drawn this frame).
          return nil, false
        end
        if mon.species then managedSpecies[mon.species] = false end
      end
      return vanillaPic(self, mon, back)
    end

    local vanillaPicScale = BattleState.picScale
    if type(vanillaPicScale) == "function" then
      function BattleState:picScale(path, mon, back)
        if wantEnabled() and type(mon) == "table"
          and managedSpecies[mon.species] then
          return 1
        end
        return vanillaPicScale(self, path, mon, back)
      end
    end

    -- Crystal draws its own animated front pics over the static one; for a
    -- species we manage, suppress that so our sheet wins the box.
    local vanillaFrontAnim = BattleState.frontAnimFrame
    if type(vanillaFrontAnim) == "function" then
      function BattleState:frontAnimFrame(mon)
        if wantEnabled() and type(mon) == "table"
          and managedSpecies[mon.species] then
          return nil
        end
        return vanillaFrontAnim(self, mon)
      end
    end
    return true
  end

  -- ---------------------------------------------------------------------------
  -- Pokedex front pic (gen1 DexEntryMenu, gen2 PokedexMenu)
  -- ---------------------------------------------------------------------------
  -- The battle seams above are not the only place a Pokemon's front pic is
  -- drawn, and the Pokedex never goes through them: gen1's DexEntryMenu asks
  -- src.pokemon.Sprites.path for the front pic's FILE PATH and loads it itself,
  -- and gen2's PokedexMenu does the same through Sprites.pic + Assets.image.
  -- The engine's own pokemon.sprite hook can only substitute that path string,
  -- so a sheet we bake in memory as an Image can never arrive through it -- the
  -- dex keeps loading the vanilla png while the battle screen shows our sheet.
  -- The fix is to wrap the dex screens' own pic accessors instead, exactly as
  -- the battle wraps do: hand them our current frame (already baked to the 7x7
  -- front box both dex screens draw into), trueColor = true, and fall through to
  -- vanilla when the pack has no sheet.  DEX SPRITES turns this off.
  --
  -- The dex has no live mon, so the sheet is chosen from the species id alone:
  -- the base front sheet, never the female or shiny variant (the entry shows the
  -- default artwork, as the cart does), and UNOWN is skipped because gen2's
  -- drawUnownPic has its own per-letter routine.
  function DATA.eeDexSelected(owner, species)
    if type(owner) ~= "table" then return end
    local key = tostring(species) .. ":" .. DATA.spriteStyle()
    if owner.__eeDexSelection == key then return end
    owner.__eeDexSelection = key
    if DATA.spriteStyle() ~= 3 then return end
    for _, sheet in pairs(sheets) do
      for _, frames in ipairs({sheet.frames or {}, sheet.gen3FrameData or {}}) do
        if frames.__ee then frames.__eeStarted = now() end
      end
      for _, proxy in pairs(sheet.proxies or {}) do
        if proxy.data and proxy.data.__ee then proxy.data.__eeStarted = now() end
      end
    end
  end
  local function dexFrame(species, owner)
    DATA.eeDexSelected(owner, species)
    if not (wantEnabled() and dexOn()) then return nil, false end
    if type(species) ~= "string" or species == "UNOWN" then return nil, false end
    local stem = resolveStem(species)
    if not stem then return nil, false end
    -- getFrames has two return values: keep the call in its own statement, or
    -- the assignment collapses it to one and drops `pending`.
    local frames, pending = nil, false
    frames, pending = getFrames(false, false, stem)
    if frames then return frames[frameIndex(#frames, frames)], false end
    return nil, pending
  end

  -- Title portraits use the same player/menu sprite style as the Pokedex.
  function DATA.installTitleSprites()
    local ok,Title=pcall(require,'src.ui.TitleState')
    if not(ok and type(Title.currentSprite)=='function')then return false end
    if Title.currentSprite==Title._1025DexTitleSprites then return true end
    local native=Title.currentSprite
    local function selected(self,...)
      local species=self.cycleSpecies and self.cycleSpecies[self.cycleIndex]
      if species then
        local stem=resolveStem(species,DATA.spriteStyle())
        if stem then
          local frames=getFrames(false,false,stem)
          if not frames then pollAll();frames=getFrames(false,false,stem)end
          if frames then return frames[frameIndex(#frames,frames)],true end
        end
      end
      return native(self,...)
    end
    Title._1025DexTitleSprites=selected;Title.currentSprite=selected
    return true
  end
  DATA.installTitleSprites()
  -- Patch the live instance too: screen factories may wrap/clone the class.
  mod.hooks:wrap('screen.render_visible',function(next,screen)
    if screen and screen.cycleSpecies and screen.cycleIndex and type(screen.currentSprite)=='function'
       and screen.currentSprite~=screen._1025DexLiveTitle then
      local native=screen.currentSprite
      screen._1025DexLiveTitle=function(self,...)
        local species=self.cycleSpecies[self.cycleIndex]
        local stem=resolveStem(species,DATA.spriteStyle())
        if stem then
          local frames=getFrames(false,false,stem)
          if not frames then pollAll();frames=getFrames(false,false,stem)end
          if frames then return frames[frameIndex(#frames,frames)],true end
        end
        return native(self,...)
      end
      screen.currentSprite=screen._1025DexLiveTitle
    end
    return next(screen)
  end)

  local function installDexGen1()
    local ok, DexEntryMenu = pcall(require, "src.ui.DexEntryMenu")
    if not (ok and type(DexEntryMenu) == "table"
      and type(DexEntryMenu.draw) == "function") then
      return false
    end
    if DexEntryMenu.__g9BattleSpritesDex then return true end
    DexEntryMenu.__g9BattleSpritesDex = true
    local vanillaDraw = DexEntryMenu.draw
    -- DexEntryMenu.new resolves the vanilla pic into self.sprite once, and the
    -- entry page spends its first PIC_DELAY frames with that pic hidden (while
    -- the cry loads) -- exactly the window our first bake lands in.  Stash the
    -- vanilla sprite the first time we touch an instance so turning DEX SPRITES
    -- off, or a species with no sheet, can always put it back.
    --
    -- This is where the NATIONAL DEX's own custom screen lands on Gen 1:
    -- national_dex patches this very class in memory (src/dexpage.lua), turning
    -- the entry into its own page strip -- the entry page, then a STATS page as
    -- page 2, then the evolution line and full movelist -- and banding it with
    -- LEFT/RIGHT form browsing that writes the selected form onto
    -- self.formId / self.formRecord.  The sheet must therefore follow the FORM
    -- the screen is showing (not just the species the entry was opened for),
    -- and must be in place on the STATS page too, which national_dex draws
    -- through its own draw wrapper -- see the update wrap at the bottom.
    local function dexSpriteId(self)
      local id = self.formId
      if type(id) == "string" and id ~= self.baseSpeciesId then return id end
      return self.species
    end

    local function applyDexSprite(self)
      if not self.__g9bsDexStash then
        self.__g9bsDexStash = true
        self.__g9bsDexSprite = self.sprite
        self.__g9bsDexTrueColor = self.spriteTrueColor
      end
      local id = dexSpriteId(self)
      local frame, pending = dexFrame(id, self)
      if not frame and not pending and id ~= self.species then
        -- A form id the pack has no sheet for falls back to the base species'
        -- sheet, exactly as the battle lookup does, rather than to vanilla.
        frame, pending = dexFrame(self.species)
      end
      if frame then
        self.sprite = frame
        self.spriteTrueColor = true
      elseif pending then
        -- The sheet is on its way: draw no pic rather than flash vanilla.
        self.sprite = nil
        self.spriteTrueColor = false
      else
        self.sprite = self.__g9bsDexSprite
        self.spriteTrueColor = self.__g9bsDexTrueColor
      end
    end

    function DexEntryMenu:draw(...)
      applyDexSprite(self)
      return vanillaDraw(self, ...)
    end

    -- national_dex draws its STATS page (page 2) from its own wrapper of this
    -- class, and on that page it returns before calling the engine's draw -- so
    -- depending on load order the draw wrap above can be skipped on exactly the
    -- page this feature most needs to reach.  Applying the sprite from update
    -- as well leaves self.sprite holding the current frame before either draw
    -- path reads it, so the entry page AND the STATS page show the sheet no
    -- matter which wrapper national_dex installed first.
    if type(DexEntryMenu.update) == "function" then
      local vanillaUpdate = DexEntryMenu.update
      function DexEntryMenu:update(...)
        vanillaUpdate(self, ...)
        applyDexSprite(self)
      end
    end
    mod.log:info("g9-battle-sprites: Pokedex front pic hooked (gen1)")
    return true
  end

  local function installDexGen2()
    local ok, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if not (ok and type(PokedexMenu) == "table"
      and type(PokedexMenu.picFor) == "function") then
      return false
    end
    if PokedexMenu.__g9BattleSpritesDex then return true end
    PokedexMenu.__g9BattleSpritesDex = true
    local vanillaPicFor = PokedexMenu.picFor
    -- picFor(species) -> image, trueColor.  Its vanilla Image is cached by path
    -- in self.picCache; we bypass that cache and hand back a baked frame with
    -- trueColor = true so drawPic blits it raw (the same box the cart's 7x7
    -- block uses, so placement/padding are unchanged).  A pending sheet returns
    -- (nil, false) -- the "draw nothing this frame" signal the battle wraps use,
    -- so vanilla never flashes while the pack bakes.
    function PokedexMenu:picFor(species)
      local frame, pending = dexFrame(species, self)
      if frame then return frame, true end
      if pending then return nil, false end
      return vanillaPicFor(self, species)
    end
    mod.log:info("g9-battle-sprites: Pokedex front pic hooked (gen2)")
    return true
  end

  -- ---------------------------------------------------------------------------
  -- Party SUMMARY front pic (gen1 SummaryMenu, gen2 SummaryMenu)
  -- ---------------------------------------------------------------------------
  -- The summary screen is the third place a mon's front pic is drawn, and like
  -- the Pokedex it never goes through a battle screen.  Both generations draw
  -- the FRONT pic there, so the same lookup the battle seams use picks the
  -- sheet: the species id (plus female and shiny) resolves to a DBK stem, and
  -- the sheet is the FRONT one, or the *_shiny FRONT one when the mon is shiny.
  -- No Tera film and no Dynamax cloud: those are battle states, and a mon on
  -- the summary screen is not in a battle.
  --
  --   gen1  src.ui.SummaryMenu.new loads the vanilla front pic once into
  --         self.sprite and :draw paints it MIRRORED into the same 7x7 box the
  --         battle enemy front uses.  We let that draw run with self.sprite
  --         hidden and paint the current frame into the very same spot
  --         ourselves (mirrored, bottom-anchored), marking the rect true-colour
  --         so the SGB pass leaves its colours alone -- exactly the mechanism
  --         the dex hook uses, but self-contained rather than handed to the
  --         engine through self.sprite.  SUMMARY SIZE scales that draw.
  --   gen2  src.ui.gen2.SummaryMenu:drawPic asks picFor(mon) for an Image and
  --         picAnimFrame() for Crystal's own animated front pic, then hands it
  --         to drawPicBlock, which recolours it to the mon's GBC palette.  We
  --         wrap drawPic outright: a managed species gets its frame drawn into
  --         the 7x7 block RAW (no GBC 4-shade remap -- the same rule the battle
  --         screen's true-colour pics follow), with the block's background
  --         filled from the mon's palette so the surrounding page still blends.
  --
  -- UNOWN is left vanilla on gen2: its pic is picked per LETTER by
  -- Unown.formSprite, which a species-id lookup cannot reproduce (the same
  -- reason the dex hook skips it).  Eggs are skipped too.  SUMMARY SPRITES
  -- turns the whole thing off.
  local function summaryStem(mon)
    if type(mon) ~= "table" then return nil end
    if mon.isEgg == true then return nil end
    if mon.species == "UNOWN" then return nil end
    local stem, shiny = monStem(mon)
    if not stem then return nil end
    return stem, shiny
  end

  local function installSummaryGen1()
    local ok, SummaryMenu = pcall(require, "src.ui.SummaryMenu")
    if not (ok and type(SummaryMenu) == "table"
      and type(SummaryMenu.draw) == "function") then
      return false
    end
    if SummaryMenu.__g9BattleSpritesSummary then return true end
    SummaryMenu.__g9BattleSpritesSummary = true
    local vanillaDraw = SummaryMenu.draw
    -- gen1's summary paints its own front pic MIRRORED into the 7x7 slot at
    -- (1,0): `draw(self.sprite, 8 + pw, max(0, 56 - ph), 0, -1, 1)` plus a
    -- PaletteFX.markTrueColor over that rect so the SGB zone pass leaves it
    -- alone.  We let the engine's draw run with self.sprite hidden and paint
    -- the managed frame into that very spot ourselves -- which is what gives
    -- SUMMARY SIZE somewhere to live, and (unlike handing the frame over
    -- through self.sprite) does not depend on the engine's own pic draw.
    local function drawFrame(frame)
      local G = love.graphics
      local pw, ph = frame:getDimensions()
      local s = summaryScale()
      local dw, dh = pw * s, ph * s
      -- Centred across the 7x7 slot, feet on the slot's bottom line, mirrored
      -- like the engine's own front pic (LoadFlippedFrontSpriteByMonIndex).
      local x = 8 + (FRONT_BOX.w - dw) / 2
      local y = math.max(0, FRONT_BOX.h - dh)
      G.setColor(1, 1, 1, 1)
      G.draw(frame, x + dw, y, 0, -s, s)
      local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
      if okP and PaletteFX and PaletteFX.markTrueColor then
        pcall(PaletteFX.markTrueColor, math.floor(x), math.floor(y),
          math.ceil(dw), math.ceil(dh))
      end
    end
    function SummaryMenu:draw(...)
      local mon = self.mon
      if not (wantEnabled() and summaryOn()) then
        -- SUMMARY SPRITES off: put the game's own pic back if we ever hid it,
        -- and leave the engine's own draw to paint it, exactly as vanilla.
        if self.__g9bsSumStash then
          self.sprite = self.__g9bsSumVanilla
          self.spriteTrueColor = self.__g9bsSumVanillaTrue
        end
        return vanillaDraw(self, ...)
      end
      -- The vanilla pic is loaded once in SummaryMenu.new; capture it before
      -- the first managed draw can hide it, so turning SUMMARY SPRITES off (or
      -- an unmapped species) always puts the game's own art back.
      if not self.__g9bsSumStash then
        self.__g9bsSumStash = true
        self.__g9bsSumVanilla = self.sprite
        self.__g9bsSumVanillaTrue = self.spriteTrueColor
      end
      local stem, shiny = summaryStem(mon)
      local frame, pending = nil, false
      if stem then
        -- getFramesFor has two return values: keep the call in its own
        -- statement, or the assignment collapses it and drops `pending`.
        local frames = nil
        frames, pending = getFramesFor(false, shiny, stem)
        if frames then frame = frames[frameIndex(#frames, frames)] end
      end
      -- Hide the engine's pic while ours is up (or still baking): the engine
      -- paints self.sprite itself, so it must see nil for the frame it must
      -- NOT paint.  Everything else the draw paints is left alone.
      local savedSprite, savedTrue = self.sprite, self.spriteTrueColor
      if frame or pending then
        self.sprite = nil
        self.spriteTrueColor = false
      end
      local r = vanillaDraw(self, ...)
      self.sprite = savedSprite
      self.spriteTrueColor = savedTrue
      if frame then
        diag.stats.summary = diag.stats.summary + 1
        -- The entry flash (whiteHold) whites the whole screen at the END of
        -- the vanilla draw; painting the frame over it would punch a hole in
        -- the fade-in, so wait it out.
        if not (self.whiteHold and self.whiteHold > 0) then drawFrame(frame) end
      end
      return r
    end
    mod.log:info("g9-battle-sprites: Summary front pic hooked (gen1)")
    return true
  end

  local function installSummaryGen2()
    local ok, SummaryMenu = pcall(require, "src.ui.gen2.SummaryMenu")
    if not (ok and type(SummaryMenu) == "table"
      and type(SummaryMenu.drawPic) == "function") then
      return false
    end
    if SummaryMenu.__g9BattleSpritesSummary then return true end
    SummaryMenu.__g9BattleSpritesSummary = true
    local okP, Palettes = pcall(require, "src.world.gen2.Palettes")
    Palettes = okP and Palettes or nil
    local okG, GbcPalette = pcall(require, "src.render.GbcPalette")
    GbcPalette = okG and GbcPalette or nil
    local vanillaDrawPic = SummaryMenu.drawPic
    -- PrepMonFrontpic's 7x7 block at hlcoord 0, 0 (56x56 at 1:1).
    local PIC_BLOCK = 7 * 8
    function SummaryMenu:drawPic()
      local mon = self.mon
      if wantEnabled() and summaryOn() then
        local stem, shiny = summaryStem(mon)
        if stem then
          local frames, pending = nil, false
          frames, pending = getFramesFor(false, shiny, stem)
          if frames then
            diag.stats.summary = diag.stats.summary + 1
            local img = frames[frameIndex(#frames, frames)]
            -- The block's own background comes from the mon's palette (as
            -- drawPicBlock fills it); the sprite itself is drawn as it is,
            -- skipping the GBC 4-shade remap whenever the game is in GBC mode
            -- -- the same rule BattleState uses for a true-colour pic.
            local colors = (Palettes and self.palettes and mon.species)
              and Palettes.monColors(self.palettes, mon.species, mon.shiny)
              or nil
            local G = love.graphics
            local blank = (GbcPalette and colors)
              and GbcPalette.color(colors, 1) or { 255, 255, 255 }
            G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
            G.rectangle("fill", 0, 0, PIC_BLOCK, PIC_BLOCK)
            G.setColor(1, 1, 1, 1)
            -- SUMMARY SIZE: REAL SIZE is the frame at 1:1 filling the block
            -- (dx = dy = 0); a smaller setting draws the same Image centred.
            -- No battle, dex or scene draw ever reads this scale.
            local s = summaryScale()
            local iw, ih = img:getDimensions()
            local dx = math.floor((PIC_BLOCK - iw * s) / 2)
            local dy = math.floor((PIC_BLOCK - ih * s) / 2)
            local function body() G.draw(img, dx, dy, 0, s, s) end
            if GbcPalette and colors and GbcPalette.available()
              and GbcPalette.mode ~= "gbc" then
              GbcPalette.with(colors, body)
            else
              body()
            end
            G.setColor(1, 1, 1, 1)
            return
          end
          if pending then return end
        end
      end
      return vanillaDrawPic(self)
    end
    mod.log:info("g9-battle-sprites: Summary front pic hooked (gen2)")
    return true
  end

  -- One boot is one generation, so install the matching dex arm only: the gen2
  -- module cannot even be required on a gen1 boot (RequireGuard throws).  The
  -- generation is passed in -- it is decided later, in the boot flow below.
  local function installDex(wantGen)
    if wantGen == 3 then
      for _, name in ipairs({"src.ui.game3.pokedex", "src.ui.game3.rse.pokedex", "src.ui.game3.rs.pokedex"}) do
        local ok, page = pcall(require, name)
        if ok and type(page) == "table" and type(page.draw) == "function" and not page.__eeDexHook then
          page.__eeDexHook = true
          local draw = page.draw
          page.draw = function(view, ...)
            local owner = type(view) == "table" and view or page
            local row = owner.list and owner.list.items and owner.list.items[owner.selected]
            local id = owner.caught and owner.caught.dexNum or row and row.dexNum or page.selectedSpecies
            DATA.eeDexSelected(owner, tostring(id) .. ":" .. tostring(owner.page))
            return draw(view, ...)
          end
          if type(page.show) == "function" then
            local show = page.show
            page.show = function(...)
              page.__eeDexSelection = nil
              return show(...)
            end
          end
        end
      end
      return "gen3"
    end
    if wantGen == 2 then
      if installDexGen2() then return "gen2" end
      if installDexGen1() then return "gen1" end
    elseif wantGen == 1 then
      if installDexGen1() then return "gen1" end
      if installDexGen2() then return "gen2" end
    else
      local g1 = installDexGen1()
      local g2 = installDexGen2()
      if g1 or g2 then
        return (g1 and "gen1" or "") .. (g2 and "+gen2" or "")
      end
    end
    return nil
  end

  -- One boot is one generation, so install the matching summary arm too (same
  -- RequireGuard reason as the dex above).
  local function installSummary(wantGen)
    if wantGen == 3 then return "gen3" end
    if wantGen == 2 then
      if installSummaryGen2() then return "gen2" end
      if installSummaryGen1() then return "gen1" end
    elseif wantGen == 1 then
      if installSummaryGen1() then return "gen1" end
      if installSummaryGen2() then return "gen2" end
    else
      local g1 = installSummaryGen1()
      local g2 = installSummaryGen2()
      if g1 or g2 then
        return (g1 and "gen1" or "") .. (g2 and "+gen2" or "")
      end
    end
    return nil
  end

  -- ---------------------------------------------------------------------------
  -- Summary screens that are PUSHED (the party summary, and any replacement)
  -- ---------------------------------------------------------------------------
  -- The party menu's STATS action opens the summary with
  -- `Screens.push(game, "SummaryMenu", mon)` (src/ui/PartyMenu.lua), so the
  -- PARTY SUMMARY -- the screen national_dex repaints the stats box of -- is
  -- exactly the screen pushed under the id "SummaryMenu", whoever supplies its
  -- class.  The builtin src.ui.SummaryMenu is covered by the wrap above, but a
  -- replacement registered under that id, or any other screen that paints a
  -- mon's front pic out of its own `self.sprite` (the concrete other case being
  -- the g9 battle engine's 256x144 modern STATS screen, which repoints the
  -- party menu's STATS item), is an ordinary pushed `Screen`, NOT a SummaryMenu
  -- subclass, so the wrap above never runs for it and the mod's sprites looked
  -- absent exactly there.
  --
  -- We do NOT touch, replace or disable such a screen: it draws in full, and we
  -- only swap the one picture it would have painted -- the same "hide the
  -- engine's pic for the length of the draw, then paint the frame into its own
  -- box" trick the native gen1 arm uses.  A `screen.pushed` listener finds the
  -- screen the moment it lands on the stack, whichever mod pushed it and
  -- however the player reached it, and wraps just that one instance's `draw`.
  -- A screen under the party summary's id draws into the native 160x144 slot on
  -- both its pages; anything else is treated as a wide modern screen (left box,
  -- picture page only).
  --
  -- Only a pushed state that carries a live mon and a draw is touched; the
  -- native SummaryMenu (both generations) and the Pokedex entry page carry a
  -- flag we check and are skipped, so no picture is ever drawn twice.  SUMMARY
  -- SPRITES and SUMMARY SIZE behave here exactly as they do on the native arm.
  local summaryScreensInstalled = false

  -- The left-hand picture area of the wide modern stats screen, in its own
  -- 256x144 UI pixels: its static pic is mirrored from x=80 with its feet on
  -- the y=56 rule (the stats box opens on the next tile row).  We paint into
  -- that same box, centred across it and bottom-anchored, like every other
  -- summary screen's front pic.
  local CUSTOM_SUMMARY_BOX = { x = 0, w = 80, bottom = 56 }
  -- The PARTY SUMMARY screen's own picture slot, in the native 160x144 UI
  -- pixels: src.ui.SummaryMenu draws it MIRRORED from x=8 (status_screen.asm:
  -- 170, LoadFlippedFrontSpriteByMonIndex) with its feet on the y=56 line.
  -- A screen pushed under the id "SummaryMenu" is this party summary -- the
  -- screen the party menu's STATS action opens, and the one national_dex
  -- repaints the stats box of -- so it gets this box even when a replacement
  -- class supplies it.
  local NATIVE_SUMMARY_BOX = { x = 8, w = 56, bottom = 56 }

  local function drawCustomSummaryFrame(frame, box)
    local G = love.graphics
    local pw, ph = frame:getDimensions()
    local s = summaryScale()
    local dw, dh = pw * s, ph * s
    local x = box.x + (box.w - dw) / 2
    local y = math.max(0, box.bottom - dh)
    G.setColor(1, 1, 1, 1)
    G.draw(frame, x + dw, y, 0, -s, s)
    local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
    if okP and PaletteFX and PaletteFX.markTrueColor then
      pcall(PaletteFX.markTrueColor, math.floor(x), math.floor(y),
        math.ceil(dw), math.ceil(dh))
    end
  end

  -- A pushed state that shows a mon's own front pic and is not one of the two
  -- native screens we already wrap.  `self.sprite` is the discriminator: on
  -- gen1 only the native SummaryMenu and the dex entry page set it, and both
  -- carry a flag we check, so nothing else can be caught by accident.
  --
  -- The one exception is the party summary itself: a screen pushed under the
  -- id "SummaryMenu" IS that screen (the party menu's STATS action opens it)
  -- whether the builtin class or a replacement supplies it, so the id alone
  -- qualifies it -- its pic may legitimately still be nil on the frame it is
  -- pushed (a screen that loads it lazily), and gating on `self.sprite` there
  -- would silently drop exactly the screen this feature exists to reach.
  local function isSummaryScreen(state)
    if type(state) ~= "table" then return false end
    if state.__g9bsSumScreen then return false end
    if type(state.mon) ~= "table" then return false end
    if type(state.draw) ~= "function" then return false end
    local mt = getmetatable and getmetatable(state)
    if type(mt) == "table"
      and (mt.__g9BattleSpritesSummary or mt.__g9BattleSpritesDex) then
      return false
    end
    if state.screenId == "SummaryMenu" then return true end
    return state.sprite ~= nil
  end

  local function decorateSummaryScreen(state)
    if not isSummaryScreen(state) then return end
    state.__g9bsSumScreen = true
    -- The party summary wears the native 160x144 picture slot and paints its
    -- front pic on BOTH pages; a wide replacement (the engine's modern stats
    -- screen) has its own left box and only a picture on page 1.  Pick the
    -- geometry from the id rather than from the shape, so a replacement class
    -- pushed under the party summary's id still lands in the right slot.
    local nativeSummary = (state.screenId == "SummaryMenu")
    local box = nativeSummary and NATIVE_SUMMARY_BOX or CUSTOM_SUMMARY_BOX
    local vanillaDraw = state.draw
    state.draw = function(self, ...)
      -- SUMMARY SPRITES off: leave the screen exactly as its author drew it.
      if not (wantEnabled() and summaryOn()) then
        return vanillaDraw(self, ...)
      end
      -- The wide modern screen's page 2 is EXP/moves (no picture); the native
      -- party summary paints its front pic on both its pages, so only the wide
      -- case is restricted to the picture page.
      if not nativeSummary and self.page ~= nil and self.page ~= 1 then
        return vanillaDraw(self, ...)
      end
      local stem, shiny = summaryStem(self.mon)
      local frame, pending = nil, false
      if stem then
        -- getFramesFor has two return values: keep the call in its own
        -- statement, or the assignment collapses it and drops `pending`.
        local frames = nil
        frames, pending = getFramesFor(false, shiny, stem)
        if frames then frame = frames[frameIndex(#frames, frames)] end
      end
      if not (frame or pending) then return vanillaDraw(self, ...) end
      -- The screen paints its own `self.sprite`; hide it for the length of the
      -- draw so the static pic is never shown under (or in place of) the frame.
      local savedSprite, savedTrue = self.sprite, self.spriteTrueColor
      self.sprite = nil
      self.spriteTrueColor = false
      local r = vanillaDraw(self, ...)
      self.sprite = savedSprite
      self.spriteTrueColor = savedTrue
      if frame then
        diag.stats.summary = diag.stats.summary + 1
        drawCustomSummaryFrame(frame, box)
      end
      return r
    end
    mod.log:info("g9-battle-sprites: custom summary screen decorated")
  end

  local function installSummaryScreens(wantGen)
    if wantGen == 3 then return true end
    -- The modern stats screen is a Gen 1 screen (the engine mod only installs
    -- it off a Gen 2 boot, and the native wrap already covers Gen 2), so only
    -- arm the listener there.  It also needs the events bus, which a very old
    -- engine may not expose -- feature-detected rather than assumed.
    if wantGen == 2 then return false end
    if summaryScreensInstalled then return true end
    if not (mod.events and type(mod.events.on) == "function") then
      return false
    end
    summaryScreensInstalled = true
    mod.events:on("screen.pushed", function(ev)
      -- A malformed/foreign state must never break the push, so the whole
      -- decoration is guarded; the worst case is one undecorated screen.
      pcall(decorateSummaryScreen, ev and ev.state)
    end)
    mod.log:info("g9-battle-sprites: pushed summary screens hooked (gen1)")
    return true
  end

  -- ---------------------------------------------------------------------------
  -- Party menu icons (the little 16x16 icon on each party-list row)
  -- ---------------------------------------------------------------------------
  -- The party list draws one small icon per slot, on BOTH generations, and --
  -- like the Pokedex and the Summary -- it does not draw through a battle
  -- screen, so it needs its own hook:
  --   * gen1: PartyMenu.drawIcon is a MODULE function
  --     (game, mon, x, y, selected, counter, forceAlt), called once per row;
  --   * gen2: PartyMenu:drawIcon(mon, px, py) paints whatever
  --     PartyMenu:iconFor(mon) returns.
  -- The engine's own icons are two-colour 16x16 art on a shared icon sheet.
  -- The mod instead ships its OWN true-colour animated icon pack: the pack's
  -- `icones animados` folder is one 128x64 PNG per icon (two 64x64 animation
  -- frames side by side), point-sampled 4:1 at build time into a 16x16
  -- two-cell run inside a single atlas (assets/icons/party_icons.png), with
  -- the cell index per icon name in data/icon_data.lua.  The pack's female
  -- variants are honoured when SPRITE FEMALE is on, and an egg uses the
  -- pack's own egg icon.  A species the pack has no icon for falls straight
  -- through to the vanilla icon.
  local ICONS = readData("data/icon_data.lua")
  if not (ICONS and type(ICONS.species) == "table"
    and type(ICONS.base) == "table") then
    mod.log:warn("g9-battle-sprites: data/icon_data.lua is missing or "
      .. "invalid -- party icons left vanilla (reinstall the mod)")
    ICONS = nil
  end

  local ICON_REL = "assets/icons/party_icons.png"
  local ICON_CELL = (ICONS and ICONS.cell) or 16
  local ICON_COLS = (ICONS and ICONS.cols) or 60
  local ICON_FRAMES = (ICONS and ICONS.frames) or 2
  local atlas, atlasFailed, atlasWarmed = nil, false, false
  local iconQuads = {}

  -- Decode the one atlas through the same three routes every other asset uses
  -- (path -> bytes -> Image:getData), once.  The ~600KB decode is deliberately
  -- warmed off the draw path (see the core.update hook below), so the first
  -- party menu does not eat a hitch mid-frame.
  local function ensureAtlas()
    if atlas or atlasFailed or not ICONS then return atlas end
    local id, why = decodeFromPath(ICON_REL)
    if not id then
      local okr, bytes = pcall(mod.read, mod, ICON_REL)
      if okr and type(bytes) == "string" and #bytes > 0 then
        local idb, whyb = decodeFromBytes(bytes, "party_icons")
        if idb then id = idb else why = whyb end
      end
    end
    if not id then
      local idc, whyc = decodeFromImage(ICON_REL)
      if idc then id = idc else why = whyc end
    end
    if not (id and type(id.getDimensions) == "function") then
      atlasFailed = true
      mod.log:warn("g9-battle-sprites: " .. ICON_REL .. " could not be read "
        .. "(%s) -- party icons left vanilla", tostring(why))
      return nil
    end
    local ok, img = pcall(love.graphics.newImage, id)
    if not (ok and img) then
      atlasFailed = true
      mod.log:warn("g9-battle-sprites: party icon atlas could not be turned "
        .. "into an Image (%s) -- party icons left vanilla",
        tostring(ok and "nil" or img))
      return nil
    end
    atlas = img
    return atlas
  end

  -- The atlas cell for a mon's icon, or nil when the pack has no icon for it.
  -- The egg uses the pack's own "000" entry (the engine's is a distinct icon,
  -- not any species').
  local function iconCell(mon)
    if not ICONS then return nil end
    if mon.isEgg == true then return ICONS.base["000"] end
    local name = ICONS.species[mon.species]
    if not name then return nil end
    if wantFemale() and isFemale(mon) and type(ICONS.female) == "table" then
      name = ICONS.female[name] or name
    end
    return ICONS.base[name]
  end

  -- The quads for one icon cell, cached: the full 16x16 frame plus the three
  -- 8x8 quadrants a held-item marker replaces the bottom-left with (gen2).
  local function quadsFor(index)
    local q = iconQuads[index]
    if q then return q end
    local G = love.graphics
    local aw, ah = atlas:getDimensions()
    local cx = (index % ICON_COLS) * ICON_CELL
    local cy = math.floor(index / ICON_COLS) * ICON_CELL
    q = {
      full = G.newQuad(cx, cy, ICON_CELL, ICON_CELL, aw, ah),
      tl = G.newQuad(cx, cy, 8, 8, aw, ah),
      tr = G.newQuad(cx + 8, cy, 8, 8, aw, ah),
      br = G.newQuad(cx + 8, cy + 8, 8, 8, aw, ah),
    }
    iconQuads[index] = q
    return q
  end

  -- Filled in by the g9 block below: which atlas to draw an icon from (and at
  -- what design scale), so the two party-icon arms can share one lookup.
  local iconArt
  local function installPartyIconsGen1()
    local ok, PartyMenu = pcall(require, "src.ui.PartyMenu")
    if not (ok and type(PartyMenu) == "table"
      and type(PartyMenu.drawIcon) == "function") then
      return false
    end
    if PartyMenu.__g9BattleSpritesIcons then return true end
    PartyMenu.__g9BattleSpritesIcons = true
    local vanillaDrawIcon = PartyMenu.drawIcon
    PartyMenu.drawIcon = function(game, mon, x, y, selected, counter, forceAlt)
      if wantEnabled() and partyIconsOn() then
        local quads, img, k = iconArt(mon)
        if quads then
          diag.stats.party = diag.stats.party + 1
          local G = love.graphics
          G.setColor(1, 1, 1, 1)
          -- `k` is atlas pixels -> design units: 1 for the 16x16 atlas, 1/4
          -- for the 64x64 one the g9 page uses.  Either way the icon lands in
          -- the one 16x16 slot this row has always had.
          G.draw(img, quads.full, x, y, 0, k, k)
          -- Full-colour opt-out for the SGB/GBC zone post-pass, exactly as the
          -- battle and summary arms do: mark the icon's rect so the zone pass
          -- re-blits it unshaded (the party menu is a UI-pass state).  The
          -- rect is in the menu's own 160x144 pixels -- the same scale(4)
          -- wrapper the rest of the menu's draw runs under takes it to the
          -- g9 page's pixels (see drawWithScaledMarks).
          local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
          if okP and PaletteFX and PaletteFX.markTrueColor then
            pcall(PaletteFX.markTrueColor, x, y, ICON_CELL, ICON_CELL)
          end
          return true
        end
      end
      return vanillaDrawIcon(game, mon, x, y, selected, counter, forceAlt)
    end
    mod.log:info("g9-battle-sprites: party menu icons hooked (gen1)")
    return true
  end

  local function installPartyIconsGen2()
    local ok, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
    if not (ok and type(PartyMenu) == "table"
      and type(PartyMenu.drawIcon) == "function") then
      return false
    end
    if PartyMenu.__g9BattleSpritesIcons then return true end
    PartyMenu.__g9BattleSpritesIcons = true
    local okG, GbcPalette = pcall(require, "src.render.GbcPalette")
    GbcPalette = okG and GbcPalette or nil
    local vanillaDrawIcon = PartyMenu.drawIcon
    function PartyMenu:drawIcon(mon, px, py)
      if wantEnabled() and partyIconsOn() then
        local q, img, k = iconArt(mon)
        if q then
          diag.stats.party = diag.stats.party + 1
          local G = love.graphics
          -- A mon carrying something does not get the icon's own bottom-left
          -- tile: the engine REPLACES that 8x8 quadrant with the held-item
          -- marker (SpawnItemIcon).  Our icon is a 16x16 atlas cell, so the
          -- same split is reproduced here rather than dropped.
          local markerRow, marker = nil, nil
          if PartyMenu.heldMarkerRow and self.heldMarkerImage then
            local okR, row = pcall(PartyMenu.heldMarkerRow, mon)
            if okR and row then
              markerRow = row
              local okM, m = pcall(self.heldMarkerImage, self)
              if okM then marker = m end
            end
          end
          local function paint()
            if marker and markerRow then
              local mw, mh = marker:getDimensions()
              -- 8x8 quadrants of a 16x16 design slot; `k` is atlas pixels ->
              -- design units (1/4 on the g9 page's 64x64 atlas).
              G.draw(img, q.tl, px, py, 0, k, k)
              G.draw(img, q.tr, px + 8, py, 0, k, k)
              G.draw(img, q.br, px + 8, py + 8, 0, k, k)
              -- The held-item marker is the engine's own 8x8 tile from the
              -- party sheet, not the pack's art: it stays at its own scale.
              G.draw(marker, G.newQuad(0, markerRow * 8, 8, 8, mw, mh),
                px, py + 8)
            else
              G.draw(img, q.full, px, py, 0, k, k)
            end
          end
          G.setColor(1, 1, 1, 1)
          local colors = self.palettes and self.palettes.partyMenu
            and self.palettes.partyMenu[1] or nil
          -- True-colour art must not go through the 4-shade GBC remap; the
          -- engine's own trueColor rule is "raw in GBC mode, shaded otherwise",
          -- so a DMG/CLASSIC player still sees icons in the screen's palette.
          if GbcPalette and colors and type(GbcPalette.available) == "function"
            and GbcPalette.available() and GbcPalette.mode ~= "gbc" then
            GbcPalette.with(colors, paint)
          else
            paint()
          end
          return
        end
      end
      return vanillaDrawIcon(self, mon, px, py)
    end
    mod.log:info("g9-battle-sprites: party menu icons hooked (gen2)")
    return true
  end

  -- One boot is one generation, so install the matching party-icon arm only
  -- (the same RequireGuard reason as the dex and summary dispatchers above).
  local function installPartyIcons(wantGen)
    if wantGen == 3 then return "gen3" end
    if wantGen == 2 then
      if installPartyIconsGen2() then return "gen2" end
      if installPartyIconsGen1() then return "gen1" end
    elseif wantGen == 1 then
      if installPartyIconsGen1() then return "gen1" end
      if installPartyIconsGen2() then return "gen2" end
    else
      local g1 = installPartyIconsGen1()
      local g2 = installPartyIconsGen2()
      if g1 or g2 then
        return (g1 and "gen1" or "") .. (g2 and "+gen2" or "")
      end
    end
    return nil
  end

  -- ---------------------------------------------------------------------------
  -- G9 party screen (opt-in -- the G9 PARTY SCREEN row)
  -- ---------------------------------------------------------------------------
  -- The party list drawn MODERN: the game's own 160x144 page, out of the game's
  -- own parts (its font, its HP-bar tiles, its cursor, its message box), laid
  -- out in exactly the native proportions -- on a 640x576 canvas, four times
  -- the Game Boy screen, so the pack's icon frames fit their slot at their
  -- natural size instead of being shrunk into 16x16.
  --
  -- WHY 4x.  The party list's icon slot is one 16x16 cell, and the pack's icon
  -- frames are 64x64, so four screen pixels per Game Boy pixel makes that slot
  -- exactly 64 screen pixels -- the frame's own size.  640x576 is also exactly
  -- the engine's own UI-surface ceiling (Renderer.MAX_UI_WIDTH/MAX_UI_HEIGHT,
  -- src/render/Renderer.lua), so no engine widening is needed; that is why the
  -- row is a fixed 4x rather than a free zoom.
  --
  -- HOW -- the menu's own draw, one scale transform larger.
  --   * gen 1: src/core/Game.lua asks the top state for the surface it wants
  --     (PartyMenu:uiSize -> Renderer:setUISize) and draws into it, so the menu
  --     asks for 640x576 and its native draw runs under scale(4,4).
  --     wantsFillScale makes that surface FILL the window instead of being
  --     integer-letterboxed down to 1x on a display that cannot hold it 2x
  --     (the same trade g9-Battle-Scene makes for its own surface).
  --   * gen 2: Game2 paints a `drawsWidescreen` screen's surround itself, so
  --     the same native drawPanel runs under a window-filling scale of the
  --     640x576 panel.  battlePanelScale answers the matching scale, which is
  --     what makes a classic screen pushed over the menu (a text box) cover the
  --     panel instead of floating small in the middle of it.
  --
  -- The ICONS come from assets/icons/party_icons_hd.png -- the pack's frames at
  -- natural 64x64, packed in the SAME order as the 16x16 atlas of PARTY ICONS,
  -- so the one data/icon_data.lua cell index addresses either.  They are drawn
  -- into the same 16x16 slot, where 16 design units x4 is 64 screen pixels --
  -- 1:1 with the art.  Every other part of the lookup (species/form/female/egg
  -- mapping, the frame clock, gen 2's held-item marker) is unchanged, and PARTY
  -- ICONS still governs whether the pack's art is used at all.
  --
  -- The ACTION LIST that opens when a Pokemon is chosen is the game's own: the
  -- native self.submenu/self.subItems state, drawn by the native drawPanel /
  -- drawSubmenu this wraps, so STATS / SWITCH / field moves / ITEM / CANCEL
  -- behave and read exactly as the game's own list does.
  local G9_SCALE = 4
  local G9_W, G9_H = 160 * G9_SCALE, 144 * G9_SCALE
  local G9_HD_REL = "assets/icons/party_icons_hd.png"
  local G9_HD_CELL = (ICONS and ICONS.hdCell) or 64
  local G9_HD_COLS = (ICONS and ICONS.hdCols) or 60
  local g9Atlas, g9AtlasFailed, g9AtlasWarmed = nil, false, false
  local g9Quads = {}

  local function g9On()
    return wantEnabled() and opt("g9_party_screen", false) ~= false
  end

  -- The high-resolution atlas, decoded through the same three routes every
  -- other asset uses (path -> bytes -> Image:getData).  It is ~1.9MB, so it is
  -- decoded only while G9 PARTY SCREEN is on, and warmed off the draw path from
  -- the core.update hook so the first party menu never pays for it mid-frame.
  local function ensureG9Atlas()
    if g9Atlas or g9AtlasFailed or not ICONS then return g9Atlas end
    local id, why = decodeFromPath(G9_HD_REL)
    if not id then
      local okr, bytes = pcall(mod.read, mod, G9_HD_REL)
      if okr and type(bytes) == "string" and #bytes > 0 then
        local idb, whyb = decodeFromBytes(bytes, "party_icons_hd")
        if idb then id = idb else why = whyb end
      end
    end
    if not id then
      local idc, whyc = decodeFromImage(G9_HD_REL)
      if idc then id = idc else why = whyc end
    end
    if not (id and type(id.getDimensions) == "function") then
      g9AtlasFailed = true
      mod.log:warn("g9-battle-sprites: " .. G9_HD_REL .. " could not be read "
        .. "(%s) -- the g9 party screen falls back to the 16x16 icons",
        tostring(why))
      return nil
    end
    local ok, img = pcall(love.graphics.newImage, id)
    if not (ok and img) then
      g9AtlasFailed = true
      mod.log:warn("g9-battle-sprites: the high-resolution icon atlas could "
        .. "not be turned into an Image (%s) -- falling back to the 16x16 icons",
        tostring(ok and "nil" or img))
      return nil
    end
    g9Atlas = img
    return g9Atlas
  end

  -- The HD cell's quads, cached: the full 64x64 frame plus the three 32x32
  -- quadrants the gen2 held-item marker replaces the bottom-left with.
  local function g9QuadsFor(index)
    local q = g9Quads[index]
    if q then return q end
    local G = love.graphics
    local aw, ah = g9Atlas:getDimensions()
    local half = G9_HD_CELL / 2
    local cx = (index % G9_HD_COLS) * G9_HD_CELL
    local cy = math.floor(index / G9_HD_COLS) * G9_HD_CELL
    q = {
      full = G.newQuad(cx, cy, G9_HD_CELL, G9_HD_CELL, aw, ah),
      tl = G.newQuad(cx, cy, half, half, aw, ah),
      tr = G.newQuad(cx + half, cy, half, half, aw, ah),
      br = G.newQuad(cx + half, cy + half, half, half, aw, ah),
    }
    g9Quads[index] = q
    return q
  end

  -- Which icon art to draw for a mon, and at what DESIGN scale: the 64x64
  -- atlas at 16 design units while the g9 screen is on (1:1 inside its 4x
  -- surface), the 16x16 atlas 1:1 otherwise.  `k` is atlas pixels -> design
  -- units.  Returns nil when the pack has no icon for this mon, so the caller
  -- falls back to the game's own icon.
  iconArt = function(mon)
    if type(mon) ~= "table" then return nil end
    local cell = iconCell(mon)
    if not cell then return nil end
    local f = frameIndex(ICON_FRAMES) - 1
    if g9On() and ensureG9Atlas() then
      return g9QuadsFor(cell + f), g9Atlas, 16 / G9_HD_CELL
    end
    if not ensureAtlas() then return nil end
    return quadsFor(cell + f), atlas, 1
  end
  -- A classic state's SGB zone list is in ITS own 160x144 pixels, so a state
  -- drawn on the g9 page hands back a list that takes the same 4x its pixels
  -- just got.  The menu's whole-screen zone, its icon column and one zone per
  -- HP-bar row all scale through here.
  local function scaleZones(zones)
    if type(zones) ~= "table" then return zones end
    local out = {}
    for i, z in ipairs(zones) do
      if type(z) == "table" then
        out[i] = {
          colors = z.colors,
          x = (z.x or 0) * G9_SCALE, y = (z.y or 0) * G9_SCALE,
          w = (z.w or 0) * G9_SCALE, h = (z.h or 0) * G9_SCALE,
        }
      end
    end
    return out
  end

  -- The method `name` on `state`, whether it is a field of its own or comes in
  -- through its class (`__index`, table or function).  Used to tell a plain
  -- classic 160x144 state from one that already composes its own width.
  local function resolveMethod(state, name)
    if type(state[name]) == "function" then return state[name] end
    local mt = getmetatable(state)
    local idx = type(mt) == "table" and mt.__index or nil
    if type(idx) == "table" then
      if type(idx[name]) == "function" then return idx[name] end
    elseif type(idx) == "function" then
      local ok, fn = pcall(idx, state, name)
      if ok and type(fn) == "function" then return fn end
    end
    return nil
  end

  -- True-colour marks a dressed state reports are in its own classic pixels
  -- (drawCustomSummaryFrame marks the summary picture that way), so during the
  -- call the marks take the same 4x its pixels just got.  Game:draw does not
  -- centre a state that declares itself wide -- it is drawn at the origin --
  -- so no mark offset is in play and only the rects need scaling.
  local function drawWithScaledMarks(vanillaDraw, self, ...)
    local okP, PFX = pcall(require, "src.render.PaletteFX")
    if not (okP and PFX and type(PFX.markTrueColor) == "function") then
      return vanillaDraw(self, ...)
    end
    local vanillaMark = PFX.markTrueColor
    PFX.markTrueColor = function(x, y, w, h)
      return vanillaMark(x * G9_SCALE, y * G9_SCALE,
        w * G9_SCALE, h * G9_SCALE)
    end
    local ok, a, b = pcall(vanillaDraw, self, ...)
    PFX.markTrueColor = vanillaMark
    if not ok then error(a, 0) end
    return a, b
  end

  -- Dress a classic 160x144 state pushed OVER the g9 party menu -- a message
  -- box, the STATS screen -- so it sits on the same 4x page instead of
  -- floating small in the middle of it.  Such a state declares itself wide
  -- with the menu's surface size, so Game:draw leaves it at the origin and the
  -- scale transform here is the whole of the placement; a state that already
  -- fills a window of its own (a wide battle, a widescreen menu) is left
  -- alone.
  local function dressClassicOverlay(state)
    if not g9On() or type(state) ~= "table" then return end
    if state.__g9bsDressed then return end
    if resolveMethod(state, "uiSize")
      or resolveMethod(state, "drawsWidescreen") then
      return
    end
    local wideFn = resolveMethod(state, "isWideBattleLayout")
    if wideFn then
      local ok, wide = pcall(wideFn, state)
      if ok and wide then return end
    end
    local vanillaDraw = resolveMethod(state, "draw")
    if not vanillaDraw then return end
    state.__g9bsDressed = true
    state.uiSize = function()
      if not g9On() then return 160, 144 end
      return G9_W, G9_H
    end
    state.isWideBattleLayout = function() return g9On() end
    state.wantsFillScale = function() return g9On() end
    local vanillaSgb = resolveMethod(state, "sgbPalettes")
    if vanillaSgb then
      -- A screen that owns its colour zones (the summary is one) reports
      -- them in its own 160x144 pixels too.
      state.sgbPalettes = function(self, game)
        local zones = vanillaSgb(self, game)
        if not g9On() then return zones end
        return scaleZones(zones)
      end
    end
    state.draw = function(self, ...)
      if not g9On() then return vanillaDraw(self, ...) end
      local G = love.graphics
      G.push()
      G.scale(G9_SCALE, G9_SCALE)
      local r = drawWithScaledMarks(vanillaDraw, self, ...)
      G.pop()
      return r
    end
  end

  -- gen 1: the menu asks Game:draw for a 640x576 surface (PartyMenu:uiSize)
  -- and its native draw runs under scale(4), so the same layout gains four
  -- screen pixels per Game Boy pixel.  Declaring itself a WIDE layout too
  -- keeps that surface while a classic state -- or a wide battle -- is pushed
  -- over or under it.  holdsUIAnchors is read as a plain FIELD by
  -- Game.uiAnchorsHeldInStack, so it is toggled with the option in the poll
  -- rather than installed once (a function there would hold anchors even with
  -- the option off).
  local g9AnchorOwner = nil
  local function installG9PartyScreenGen1()
    local ok, PartyMenu = pcall(require, "src.ui.PartyMenu")
    if not (ok and type(PartyMenu) == "table"
      and type(PartyMenu.draw) == "function") then
      return false
    end
    if PartyMenu.__g9BattleSpritesG9 then return true end
    PartyMenu.__g9BattleSpritesG9 = true
    local vanillaDraw = PartyMenu.draw
    local vanillaSgb = PartyMenu.sgbPalettes
    g9AnchorOwner = PartyMenu
    PartyMenu.uiSize = function()
      -- Off, the menu is the classic 160x144 page it always was.
      if not g9On() then return 160, 144 end
      return G9_W, G9_H
    end
    PartyMenu.isWideBattleLayout = function() return g9On() end
    PartyMenu.wantsFillScale = function() return g9On() end
    PartyMenu.draw = function(self, ...)
      if not g9On() then return vanillaDraw(self, ...) end
      local G = love.graphics
      G.push()
      G.scale(G9_SCALE, G9_SCALE)
      local r = drawWithScaledMarks(vanillaDraw, self, ...)
      G.pop()
      return r
    end
    PartyMenu.sgbPalettes = function(self, game)
      local zones = vanillaSgb and vanillaSgb(self, game) or nil
      if not g9On() then return zones end
      -- The icon column and the per-row HP-bar blocks are in 160x144 pixels
      -- like everything else the menu draws.  (The pack's own icons opt out
      -- of this pass through markTrueColor, in the draw above.)
      return scaleZones(zones)
    end
    -- One choke point covers every state pushed over the menu (StateStack:push
    -- is where screen.pushed comes from as well), and the menu is looked for
    -- ON the stack rather than assumed, so a boot where only this arm
    -- installed still dresses nothing.
    local okS, StateStack = pcall(require, "src.core.StateStack")
    if okS and type(StateStack) == "table"
      and type(StateStack.push) == "function"
      and not StateStack.__g9BattleSpritesWide then
      StateStack.__g9BattleSpritesWide = true
      local vanillaPush = StateStack.push
      StateStack.push = function(self, state, ...)
        vanillaPush(self, state, ...)
        if not g9On() then return end
        local states = self and self.states
        if type(states) ~= "table" then return end
        for i = 1, #states do
          local mt = getmetatable(states[i])
          if mt == PartyMenu
            or (type(mt) == "table" and mt.__index == PartyMenu) then
            pcall(dressClassicOverlay, state)
            return
          end
        end
      end
    end
    mod.log:info("g9-battle-sprites: g9 party screen hooked (gen1)")
    return true
  end

  -- The g9 page's display scale: it fills the window the way a fill-size
  -- battle surface does, so the panel is as large as the window allows and the
  -- icons are never shrunk.  Fractional by nature -- the same trade the
  -- BATTLE SIZE / fill surface already offers.
  local function g9FillScale(winW, winH)
    local w, h = tonumber(winW) or G9_W, tonumber(winH) or G9_H
    if w <= 0 or h <= 0 then return 1 end
    local s = math.min(w / G9_W, h / G9_H)
    if s <= 0 then s = 1 end
    return s
  end

  -- gen 2: the same 160x144 panel, on the menu's own widescreen seam.  Game2
  -- paints a `drawsWidescreen` screen's surround itself and blits a classic
  -- state pushed over it through panelBlit, which asks the screen below how
  -- big its panel is -- so answering with the matching scale is all a message
  -- box or the STATS screen needs to land on the g9 page too.
  local function installG9PartyScreenGen2()
    local ok, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
    if not (ok and type(PartyMenu) == "table"
      and type(PartyMenu.drawPanel) == "function") then
      return false
    end
    if PartyMenu.__g9BattleSpritesG9 then return true end
    PartyMenu.__g9BattleSpritesG9 = true
    local vanillaWide = PartyMenu.drawWidescreen
    PartyMenu.battlePanelScale = function(self, winW, winH)
      if not g9On() then return nil end
      return g9FillScale(winW, winH) * G9_SCALE
    end
    if type(vanillaWide) == "function" then
      PartyMenu.drawWidescreen = function(self, winW, winH)
        if not g9On() then return vanillaWide(self, winW, winH) end
        local G = love.graphics
        local Chrome = require("src.ui.gen2.Chrome")
        local scale = g9FillScale(winW, winH) * G9_SCALE
        local ox, oy = Chrome.fitOrigin(winW, winH, scale)
        Chrome.letterbox(winW, winH, 1, 1, 1)
        G.push()
        G.translate(ox, oy)
        G.scale(scale, scale)
        self:drawPanel()
        G.pop()
        return true
      end
    end
    mod.log:info("g9-battle-sprites: g9 party screen hooked (gen2)")
    return true
  end

  -- One boot is one generation, so install the matching g9 arm only (the same
  -- RequireGuard reason as the party-icon dispatcher above).  With the option
  -- off both arms are inert: every seam they touch answers the vanilla way.
  local function installG9PartyScreen(wantGen)
    if wantGen == 3 then return "native gen3" end
    if wantGen == 2 then
      if installG9PartyScreenGen2() then return "gen2" end
      if installG9PartyScreenGen1() then return "gen1" end
    elseif wantGen == 1 then
      if installG9PartyScreenGen1() then return "gen1" end
      if installG9PartyScreenGen2() then return "gen2" end
    else
      local g1 = installG9PartyScreenGen1()
      local g2 = installG9PartyScreenGen2()
      if g1 or g2 then
        return (g1 and "gen1" or "") .. (g2 and "+gen2" or "")
      end
    end
    return nil
  end

  -- ---------------------------------------------------------------------------
  -- Install + polling
  -- ---------------------------------------------------------------------------
  -- Which generation is actually booted (1 = Red/Blue/Yellow, 2 = Gold/Silver/
  -- Crystal).  src.core.GameVersion is a zero-require core module and stays
  -- loadable on both sides of the generation line, so it is the one answer
  -- that is the same whether the game is Gen 1 or Gen 2.  This matters for
  -- ASSET LOADING, not just for hooking: every frame is baked into the
  -- on-screen pic box, and the boxes genuinely differ -- gen1's back pic is
  -- pokered's 32x32 at 2x (64x64), gen2's is pokecrystal's 6x6 tile box at 1x
  -- (48x48) -- so a sheet baked for the wrong generation lands in the wrong
  -- box.  With no GameVersion (an engine older than this seam), fall back to
  -- probing both battle screens, which is how the mod answered before.
  local function currentGeneration()
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    if ok and type(GameVersion) == "table"
      and type(GameVersion.generation) == "function" then
      local gen = GameVersion.generation()
      if gen == 1 or gen == 2 or gen == 3 then return gen end
    end
    return nil
  end

  -- A boot is exactly one generation, so install the matching arm and only
  -- that one.  Besides keeping GEN honest for the asset box above, this stops
  -- a Gold boot from wrapping Gen 1's src.battle.BattleState facade, which
  -- Gen2Compat serves for compatibility but which Gold's screen never calls.
  local gen = currentGeneration()
  local gen1, gen2, gen3
  if gen == 3 then
    gen3 = installGen3()
  elseif gen == 2 then
    gen2 = installGen2()
    if not gen2 then gen1 = installGen1() end
  elseif gen == 1 then
    gen1 = installGen1()
    if not gen1 then gen2 = installGen2() end
  else
    gen1 = installGen1()
    gen2 = installGen2()
  end
  local tag = gen and (gen == 3 and "gen3" or (gen == 2 and "gen2" or "gen1"))
                or ((gen1 and "gen1" or "") .. (gen2 and "+gen2" or ""))
  if not (gen1 or gen2 or gen3) then
    mod.log:warn("g9-battle-sprites: no supported battle screen found "
      .. "(wanted src.battle.BattleState or src.ui.gen2.BattleState) -- inactive")
    diag.inst = "INACTIVE"
    return
  end
  diag.inst = tag
  diag.gen = GEN

  -- The Pokedex draws its own front pic (see the dex block above): hook the
  -- matching dex screen now that the generation is known.
  local dexTag = installDex(gen)
  if dexTag then diag.dex = dexTag
  else
    mod.log:warn("g9-battle-sprites: no Pokedex screen found -- dex front "
      .. "pics left vanilla")
  end
  local dexHooked = dexTag ~= nil

  -- The party SUMMARY screen draws its own front pic too (see the summary block
  -- above): hook the matching summary screen now the generation is known.
  local sumTag = installSummary(gen)
  if sumTag then diag.summary = sumTag
  else
    mod.log:warn("g9-battle-sprites: no Summary screen found -- summary front "
      .. "pics left vanilla")
  end
  local summaryHooked = sumTag ~= nil

  -- The engine mod's modern STATS screen REPLACES the native SummaryMenu (see
  -- the custom-summary block above), so a pushed-screen listener is what makes
  -- the summary sprites show there.  Independent of whether the native screen
  -- was found -- a build can have either, both, or neither.
  local summaryScreensHooked = installSummaryScreens(gen) and true or false
  if summaryScreensHooked then
    diag.summary = tostring(diag.summary) .. "+screens"
  end

  -- The party list's little 16x16 icons come from their own accessor on both
  -- generations (see the party-icon block above), so they need their own hook.
  local iconTag = installPartyIcons(gen)
  if iconTag then diag.party = iconTag
  else
    mod.log:warn("g9-battle-sprites: no PartyMenu screen found -- party icons "
      .. "left vanilla")
  end
  local partyHooked = iconTag ~= nil

  -- The g9 PARTY SCREEN composes that same list on a 4x page (see the g9
  -- block above).  Its draw seam is separate from the icons', so it gets its
  -- own install and its own late retry.  Installed even with the option off --
  -- every seam answers the vanilla way until it is on -- so toggling the row
  -- needs no reinstall (and the HD atlas stays undecoded either way).
  local g9Tag = installG9PartyScreen(gen)
  if g9Tag then diag.g9 = g9Tag
  else
    mod.log:warn("g9-battle-sprites: no PartyMenu screen found -- g9 party "
      .. "screen left vanilla")
  end
  local g9Hooked = g9Tag ~= nil

  if not (mod.hooks and mod.hooks.wrap) then
    mod.log:error("g9-battle-sprites: mod.hooks:wrap is unavailable -- "
      .. "frame building cannot run, so the mod is inactive")
    return
  end
  mod.hooks:wrap("core.update", function(next, game, dt)
    if gen==1 then DATA.installTitleSprites()end
    -- A screen module the engine loads LAZILY can be impossible to require at
    -- mod-boot on some builds (the require throws before that tree is wired
    -- up).  Retry the Pokedex hook from the poll until it takes, so the
    -- national dex's own entry screen is not left showing vanilla pics for a
    -- whole session over a boot-order race.
    if not dexHooked then
      local retry = installDex(gen)
      if retry then
        dexHooked = true
        diag.dex = retry
        mod.log:info("g9-battle-sprites: Pokedex screen hooked late (%s)", retry)
      end
    end
    -- Same graceful retry for the summary hook, so an early failure is a delay
    -- rather than a silent no-op.
    if not summaryHooked then
      local retry = installSummary(gen)
      if retry then
        summaryHooked = true
        diag.summary = retry
        mod.log:info("g9-battle-sprites: Summary screen hooked late (%s)", retry)
      end
    end
    -- Same graceful retry for the pushed-screen listener (a boot where the
    -- events bus is not wired yet): once it takes, the custom summary screen is
    -- covered too.
    if not summaryScreensHooked and gen ~= 2 then
      summaryScreensHooked = installSummaryScreens(gen) and true or false
    end
    -- Same graceful retry for the party-icon hook.
    if not partyHooked then
      local retry = installPartyIcons(gen)
      if retry then
        partyHooked = true
        diag.party = retry
        mod.log:info("g9-battle-sprites: party icons hooked late (%s)", retry)
      end
    end
    -- Same graceful retry for the g9 party-screen hook.
    if not g9Hooked then
      local retry = installG9PartyScreen(gen)
      if retry then
        g9Hooked = true
        diag.g9 = retry
        mod.log:info("g9-battle-sprites: g9 party screen hooked late (%s)",
          retry)
      end
    end
    -- Game.uiAnchorsHeldInStack reads PartyMenu.holdsUIAnchors as a plain
    -- field, so it has to exist only while the g9 page is on -- a method left
    -- installed would hold anchors for the vanilla menu too.
    if g9AnchorOwner then
      if g9On() then
        if not g9AnchorOwner.holdsUIAnchors then
          g9AnchorOwner.holdsUIAnchors = function() return true end
        end
      elseif g9AnchorOwner.holdsUIAnchors then
        g9AnchorOwner.holdsUIAnchors = nil
      end
    end
    -- Decode the party-icon atlas once, off the draw path: a ~600KB PNG is a
    -- visible hitch if the first party menu (often mid-battle) pays for it.
    if not atlasWarmed then
      atlasWarmed = true
      pcall(ensureAtlas)
    end
    -- The HD atlas is ~1.9MB, so it is decoded only while G9 PARTY SCREEN is
    -- on, and off the draw path like the small one: the first party menu would
    -- otherwise eat the decode on the frame it opens.
    if not g9AtlasWarmed and g9On() then
      g9AtlasWarmed = true
      pcall(ensureG9Atlas)
    end
    if gen == 3 then installGen3() end
    pollAll()
    local result = next(game, dt)
    if gen == 3 then installGen3() end
    return result
  end)

  -- ---------------------------------------------------------------------------
  -- Layout/custom battle screens: the battle.mon_pic seam
  -- ---------------------------------------------------------------------------
  -- A custom battle screen (g9-Battle-Scene, and any g2-Battle-Scene fork) does
  -- NOT draw through BattleState:drawPicsLayer or BattleState:pic.  Its
  -- battle_screen resolves each battler's pic through the pokemon.sprite hook
  -- (for the path), loads that file, and then raises battle.mon_pic with the
  -- loaded Image so an animator can swap in the current frame on the way to the
  -- screen.  A mod that only wraps the two native screens is therefore
  -- invisible in every layout battle -- the sheets are on disk, the species
  -- resolve, and nothing on screen changes.  This wrap is that second seam: the
  -- same lookup, the same frame clock, and the same fall-through to the vanilla
  -- pic when the pack has no sheet for a species.  When the pack DOES have one
  -- but it is still baking it returns `false` instead -- the screen's signal to
  -- draw nothing this frame -- so the vanilla pic is never shown in the window
  -- between a mon appearing and its frames being ready (a trainer's send-out
  -- used to flash it there).  A screen that predates the token reads `false` as
  -- "no swap" and draws the vanilla pic, i.e. exactly the old behaviour.
  -- ctx = { species, side = "front"|"back", kind = "battle", mon, battler,
  --         battle, shiny, ... } -- mon is the live battler, as on Gen 2.
  mod.hooks:wrap("battle.mon_pic", function(next, img, ctx)
    if not wantEnabled() or type(ctx) ~= "table" then return next(img, ctx) end
    diag.stats.scene = diag.stats.scene + 1
    local mon = ctx.mon
    if type(mon) ~= "table" and type(ctx.battler) == "table" then
      mon = ctx.battler.mon
    end
    if type(mon) ~= "table" then return next(img, ctx) end
    local back = ctx.side == "back"
    local stem, shiny = monStem(mon, DATA.styleFor(back, true))
    -- Tera film (see teraTypeOf): the battler is passed too, because on gen1 the
    -- live Tera state is claimed through it.  The Dynamax cloud (dynamaxOf) is
    -- read the same way.
    local tera = teraTypeOf(mon, ctx.battler)
    local cloud = dynamaxOf(mon, ctx.battler)
    -- A raid boss's gimmick, declared by the layout screen rather than live on
    -- the mon (see declaredGimmickOf).  Fill only what the live read left
    -- empty, so this can never override a real transformation.
    local declared = declaredGimmickOf(ctx)
    if declared then
      -- Same option gates as the live reads: TERA ART / DYNAMAX CLOUD off must
      -- suppress a declared film/cloud too.
      if not tera and teraArtOn() and declared.kind == "tera" then
        tera = teraKeyFor(declared.detail)
      end
      if not cloud and dynamaxOn()
          and (declared.kind == "dynamax" or declared.kind == "gigantamax") then
        cloud = true
      end
    end
    -- A layout battle screen names the exact pixel box it will draw the pic
    -- into (g9-Battle-Scene passes its own slot rect as ctx.box = {w,h}), plus
    -- the ONE scale the whole field is baked at (ctx.scale, sent by
    -- g9-Battle-Scene: the pack's NATURAL size x2 for every sprite, x2 x 1.6 =
    -- x3.2 for the boss -- the "+0.6", bosses only), the integer that screen
    -- will in turn scale the baked box by (ctx.zoom), and the pixels from that
    -- slot's ground line to the top of the field (ctx.maxH). Baking at that
    -- scale/size makes the screen's own draw a 1:1 blit instead of the
    -- fractional resample it would otherwise do -- which is where a screen on a
    -- different canvas eats the art a second time -- and the zoom is folded
    -- into the fit so an enlarged boss is never clipped by the box it is drawn
    -- out of. ctx.divisor (older forks) and ctx.fill (a sheet growing to fill
    -- its box) are still understood; ctx.scale supersedes them in
    -- g9-Battle-Scene.
    local boxOverride, divisor, zoom, maxH, fill, scale, natural
    if ctx.natural then
      -- NATURAL mode (g9-Battle-Scene): no box at all. The screen draws each
      -- sprite at its OWN size, so the mod returns an image that is exactly
      -- `scale` x the sheet's trimmed pixels (folded only to `maxH`), and the
      -- screen's blit is 1:1. This is what keeps every species' own relative
      -- size instead of folding them all into the same slot-sized box.
      natural = true
    elseif type(ctx.box) == "number" and ctx.box >= 8 then
      local n = round(ctx.box)
      boxOverride = { w = n, h = n }
    elseif type(ctx.box) == "table" then
      -- A non-square pixel box: the screen owns the exact slot rect (a grid
      -- column's width by its band's height), so both axes matter.
      local bw, bh = tonumber(ctx.box.w), tonumber(ctx.box.h)
      if bw and bh and bw >= 8 and bh >= 8 then
        boxOverride = { w = round(bw), h = round(bh) }
      end
    end
    -- The field's own scale multiplier (g9-Battle-Scene: x1 for every sprite,
    -- x1.6 for the boss). It is a straight multiplier, NOT a divisor: a value
    -- above 1 upscales on purpose. Clamp only to something sane.
    if type(ctx.scale) == "number" and ctx.scale > 0 then
      scale = ctx.scale
      if scale > 64 then scale = 64 end
    end
    if type(ctx.divisor) == "number" and ctx.divisor >= 1 then
      divisor = math.floor(ctx.divisor + 0.5)
      if divisor < 1 then divisor = 1 end
    end
    if type(ctx.zoom) == "number" and ctx.zoom > 1 then
      zoom = math.floor(ctx.zoom + 0.5)
    end
    -- The headroom a sheet may rise into before it is folded back (the
    -- screen sends the band's own height, so a huge sheet keeps its head
    -- inside its row instead of being clipped at the top of the field).
    if type(ctx.maxH) == "number" and ctx.maxH >= 8 then
      maxH = math.floor(ctx.maxH + 0.5)
    end
    -- May this sheet grow past its native size to fill the box? A shelf
    -- behaviour kept for older forks (g9-Battle-Scene now sends ctx.natural
    -- instead), true only for a boss slot.
    fill = ctx.fill and true or false
    local frames, pending = nil, false
    if stem then
      -- 3DB FRONTAL / 3DB FLIP (options): a back-side scene slot (the player's)
      -- may be re-sourced to its FRONT art and mirrored, exactly as the two
      -- native battle seams do, so a layout battle shows front-on sprites too.
      local front, flip = DATA.playerView(back)
      frames, pending = getBattleFrames(back, shiny, stem, tera, cloud,
        boxOverride, divisor, zoom, maxH, fill, scale, natural, front, flip)
    end
    if frames then
      managedSpecies[mon.species] = true
      ctx.spriteLayout = frames.__spriteLayout
      if debugOn() and mon.__g9bsLogged ~= stem then
        mon.__g9bsLogged = stem
        diag.lastResolve = tostring(mon.species) .. "->" .. stem
        diagPush("%s -> %s (scn)", mon.species, stem)
        mod.log:info("g9-battle-sprites: %s -> %s%s (%s, scene)",
          tostring(mon.species), stem, shiny and " [shiny]" or "",
          back and "back" or "front")
      end
      return frames[frameIndex(#frames, frames)]
    end
    if pending then
      -- The sheet is on its way: `false` tells the calling screen to draw
      -- NOTHING this frame (g9-Battle-Scene's drawSprite returns early on it)
      -- instead of the vanilla pic, so a layout scene's trainer send-out never
      -- flashes native art while the pack bakes. A screen that does not know
      -- the token treats a false result as "no swap" and draws the vanilla pic
      -- exactly as before, so this is safe to ship ahead of any screen update.
      return false
    end
    if mon.species then managedSpecies[mon.species] = false end
    return next(img, ctx)
  end)

  -- A load-time census of the four drop-in asset folders.  This is the one line
  -- that answers "did the mod even see my sheets?" -- a zero here means the
  -- sheets are not where the mod reads, and no amount of species resolution
  -- will find anything.
  local function assetCount(folder)
    if type(mod.list) ~= "function" then return nil end
    local ok, names = pcall(mod.list, mod, "assets/" .. folder)
    if not ok or type(names) ~= "table" then return nil end
    local n = 0
    for _, name in ipairs(names) do
      if type(name) == "string" and name:sub(-4):lower() == ".png" then
        n = n + 1
      end
    end
    return n
  end
  local cFront, cFrontS = assetCount("front"), assetCount("front_shiny")
  local cBack, cBackS = assetCount("back"), assetCount("back_shiny")
  local cShadow = assetCount("shadow")
  diag.census.front = cFront or 0
  diag.census.front_shiny = cFrontS or 0
  diag.census.back = cBack or 0
  diag.census.back_shiny = cBackS or 0
  diag.census.shadow = cShadow or 0
  if cFront ~= nil then
    mod.log:info("g9-battle-sprites: local assets -- front %d, front_shiny %d, "
      .. "back %d, back_shiny %d, shadow %d",
      cFront, cFrontS or 0, cBack or 0, cBackS or 0, cShadow or 0)
  end

  local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
  end

  -- -- the diagnostics panel ------------------------------------------------
  -- Everything below paints into the finished UI canvas.  Each diag* helper is
  -- pcall-guarded at the call site, so a diagnostics bug can never take down a
  -- frame -- the worst case is "no panel".

  local function diagBuildingCount()
    local n = 0
    for _, s in pairs(sheets) do
      if s.status == "building" then n = n + 1 end
    end
    return n
  end

  local function diagLines()
    local lines = {}
    local function add(s)
      if s == nil then return end
      s = tostring(s)
      if #s > DIAG_MAX_CHARS then s = s:sub(1, DIAG_MAX_CHARS) end
      lines[#lines + 1] = s
    end
    local c = diag.census
    local total = c.front + c.front_shiny + c.back + c.back_shiny
    add("g9-battle-sprites DIAG")
    if total == 0 then
      add("!! NO PNG IN assets/ !!")
      add("run download_assets.py")
    elseif diag.stats.ready == 0 then
      add("PNG found, 0 sheets ready")
    end
    add(("gen%s  %s"):format(tostring(diag.gen), diag.inst))
    add(("ready %d build %d fail %d"):format(
      diag.stats.ready, diagBuildingCount(), diag.stats.failed))
    add(("assets F%d S%d B%d BS%d"):format(
      c.front, c.front_shiny, c.back, c.back_shiny))
    add(("pics %d scene %d summary %d gen1 %d"):format(
      diag.stats.pics, diag.stats.scene, diag.stats.summary, diag.stats.gen1))
    if diag.stats.missing > 0 then
      add(("missing sheets %d"):format(diag.stats.missing))
    end
    if diag.lastResolve then add("last " .. diag.lastResolve) end
    if diag.lastFail then
      add("FAIL " .. diag.lastFail)
      local why = tostring(diag.lastFailWhy or "")
      for i = 1, DIAG_MAX_REASON_LINES do
        local start = (i - 1) * DIAG_MAX_CHARS + 1
        if start > #why then break end
        add(why:sub(start, start + DIAG_MAX_CHARS - 1))
      end
    end
    for i = 1, math.min(4, #diag.events) do add(diag.events[i]) end
    return lines
  end

  -- Paint the panel into `canvas` (the UI canvas handed to render.compose).
  -- White box + black text: whichever way the SGB/GBC zone pass maps the UI
  -- palette, the lightest and darkest entries stay two very different shades,
  -- so the text stays legible.  Every graphics state we touch is saved and
  -- restored so the composite that follows is byte-identical to vanilla.
  local function diagDrawCanvas(canvas)
    local g = love and love.graphics
    if not (g and canvas and g.rectangle and g.print) then return end
    local font, fh = diagGetFont()
    if not font then return end
    local lines = diagLines()
    local w = (canvas.getWidth and canvas:getWidth()) or 160
    local cap = (canvas.getHeight and canvas:getHeight()) or 144
    local h = 4 + #lines * fh
    if h > cap then h = cap end
    g.push()
    g.origin()
    local prevCanvas = g.getCanvas and g.getCanvas()
    local prevFont = g.getFont and g.getFont()
    local prevShader = g.getShader and g.getShader()
    local prevBlend = g.getBlendMode and g.getBlendMode()
    local sx, sy, sw, sh = g.getScissor and g.getScissor()
    g.setCanvas(canvas)
    if g.setScissor then g.setScissor() end
    if g.setBlendMode then g.setBlendMode("alpha") end
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 0, 0, w, h)
    g.setColor(0, 0, 0, 1)
    g.setFont(font)
    for i = 1, #lines do
      g.print(lines[i], 2, 2 + (i - 1) * fh)
    end
    g.setColor(1, 1, 1, 1)
    if prevFont then g.setFont(prevFont) else g.setFont() end
    if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
    if g.setShader then g.setShader(prevShader) end
    if prevBlend and g.setBlendMode then g.setBlendMode(prevBlend) end
    if sx and g.setScissor then g.setScissor(sx, sy, sw, sh) end
    g.pop()
  end

  -- Only registered when the panel is compiled in.  render.compose's `next` is
  -- the engine's no-op returning false (it only decides who owns the window),
  -- so returning the next value leaves the normal composite untouched.
  if DEBUG_PANEL_ENABLED then
    mod.hooks:wrap("render.compose", function(next, renderer, ctx)
      if diag.on and type(ctx) == "table" and ctx.uiCanvas
        and diag.lastFrame ~= frameCounter then
        diag.lastFrame = frameCounter
        pcall(diagDrawCanvas, ctx.uiCanvas)
      end
      return next(renderer, ctx)
    end)
  end

  mod.log:info("g9-battle-sprites: loaded (%s) -- %d species mapped, %d stems, "
    .. "%d female variants; %d local sheets",
    tag,
    count(DATA.species), count(DATA.stems), count(DATA.female),
    (cFront or 0) + (cFrontS or 0) + (cBack or 0) + (cBackS or 0))
end
