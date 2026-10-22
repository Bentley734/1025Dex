-- Mod Manager option schema for g9-battle-sprites.
--
-- Declared in manifest.json's "options_schema" field so the manager (and
-- native launchers reading mod_option_schemas.json) can render these rows even
-- while the mod is disabled.  main.lua calls mod.options:define() with the
-- IDENTICAL table at load time, which is what gives mod.options:get() its
-- defaults.  Keep the two copies in sync.
--
-- Row shapes: toggle { key, label, type="toggle", default=bool };
-- choice { key, label, type="choice", default=value,
--          choices={ { "LABEL", value }, ... } }.
return {
  {
    key = "enemy_sprite_style", label = "ENEMY SPRITES", type = "choice", default = 3,
    choices = { { "ANIMATED", 0 }, { "GEN9 STATIC", 1 }, { "BW ROM", 2 }, { "EE ANIMATED", 3 }, { "EE STATIC", 4 }, { "KIM", 5 }, { "G9 GEN3", 6 } },
    description = "Artwork for enemy battle Pokemon. Animated styles always animate; static styles remain still.",
  },
  {
    key = "player_sprite_style", label = "PLAYER SPRITES", type = "choice", default = 3,
    choices = { { "ANIMATED", 0 }, { "GEN9 STATIC", 1 }, { "BW ROM", 2 }, { "EE ANIMATED", 3 }, { "EE STATIC", 4 }, { "KIM", 5 }, { "G9 GEN3", 6 } },
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
    description = "BIG (default), NORMAL and SMALL divide ANIMATED, GEN9 STATIC, G9 GEN3 and EE artwork by 1, 2 and 3, shrinking further only when needed to fit the picture box. BW ROM artwork fits its visible animation into the box at BIG, half that size at NORMAL and a third at SMALL. All frames share one scale and ground anchor. Existing MAX DETAIL selections now use BIG. Custom battle scenes that supply their own scale keep that scale.",
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
