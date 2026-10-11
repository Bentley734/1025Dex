-- The sprite mod's art on Gold's party SUMMARY (the STATUS screen), the same
-- reach src/gen2dexlist.lua already makes onto Gold's #DEX.
--
-- Gold's summary draws the CART's pic and offers no seam to change it:
-- src/ui/gen2/SummaryMenu.lua:879-889 (`picFor`) reads `def.spriteFront`
-- straight off the species record through Assets.image and raises no hook, so
-- a sprite mod cannot reach this screen from its own side either.  And
-- :906-910 runs whatever it got through GbcPalette.with(colors, body) with no
-- trueColor opt-out -- the opt-out exists only on the battle screen
-- (src/ui/gen2/BattleState.lua:631).  Those are the same two obstacles the dex
-- arm found, so this is the same answer: wrap :drawPic, and when the neighbour
-- has art for the mon, draw that instead with the palette bypassed.
--
-- Everything that is not screen-specific -- asking the neighbour, loading and
-- remembering the image, clearing the shader, fitting the art -- is
-- src/gen2dexlist.lua's M.spriteArt / M.artFor / M.unshaded / M.artPlacement,
-- handed in as `shared`.  There is ONE resolver in this mod and one set of
-- drawing rules; the two screens must never drift apart about what a sprite
-- set looks like.
--
-- Two things this file does NOT do, both deliberate:
--
--   * Stats.  Gold already prints SPCL.ATK and SPCL.DEF natively
--     (SummaryMenu.lua:100), so src/summarystats.lua's Gen 1 box has nothing
--     to add here.  This arm is art only.
--   * Eggs.  drawPanel routes an egg to drawEggPage/drawEggPic
--     (SummaryMenu.lua:1090-1097), which draws menu_gfx.eggHatch.egg and never
--     reaches :drawPic at all, so there is nothing here to guard against.

local M = {}

-- The 7x7 tile block PrepMonFrontpic lays at hlcoord 0, 0, in pixels
-- (SummaryMenu.lua:891-892, and the fill at :900).  It happens to be the same
-- 56px square Gold's dex uses, but it is measured from this screen's own draw
-- rather than borrowed: the pic sits in the top-left corner here, with the
-- No./nickname/species column starting at tile 8, so the block's ORIGIN is
-- fixed at (0, 0) where the dex's moves with the row it is drawing.
local PIC_BOX = 7 * 8
local PIC_ORIGIN_X, PIC_ORIGIN_Y = 0, 0

-- Required once, the same guard src/gen2dexlist.lua uses: a missing or
-- reshaped module means this feature does not install rather than taking the
-- mod load down, and nothing here runs at file scope, so a headless test that
-- never installs pulls no engine module in.
local function requireGen2Summary()
  local names = { "src.ui.gen2.SummaryMenu", "src.render.GbcPalette",
    "src.world.gen2.Palettes", "src.core.gen2.Unown" }
  local mods = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    mods[name] = value
  end
  return mods
end

-- Guards against a second install patching the patch: the class is
-- process-global and a reload would otherwise stack wrappers.
local installed = false

-- `generation` is handed in and never probed.  require() is NOT redirected on
-- a Gold boot -- require("src.ui.SummaryMenu") yields Gen 1's class there --
-- so the Gen 2 class is named in full above, and the one thing this must never
-- do is decide it is on Gold because a Gold-shaped method answered.
--
-- `resolveArt` is src/gen2dexlist.lua's M.spriteArt closure, already holding
-- whatever it needed of the mod API; `shared` is that module itself.
function M.install(generation, resolveArt, shared)
  if generation ~= 2 then return false end
  if installed then return false end
  if type(resolveArt) ~= "function" then return false end
  if type(shared) ~= "table" or type(shared.artFor) ~= "function"
    or type(shared.unshaded) ~= "function"
    or type(shared.artPlacement) ~= "function" then
    return false
  end
  local mods = requireGen2Summary()
  if not mods then return false end
  local SummaryMenu = mods["src.ui.gen2.SummaryMenu"]
  local GbcPalette = mods["src.render.GbcPalette"]
  local Palettes = mods["src.world.gen2.Palettes"]
  local Unown = mods["src.core.gen2.Unown"]
  if type(SummaryMenu.drawPic) ~= "function" then return false end

  -- Gold's own drawPicBlock, for one image it cannot resolve itself.
  -- Returns true when it drew, so the caller can fall back to the cart's pic
  -- on anything it could not use.
  local function drawModPic(self, mon, art)
    local G = love.graphics
    local colors = self.palettes and mon.species
      and Palettes.monColors(self.palettes, mon.species, mon.shiny) or nil

    local image = art.image
    local scale, x, y = shared.artPlacement(image:getWidth(),
      image:getHeight(), PIC_BOX, PIC_ORIGIN_X, PIC_ORIGIN_Y)
    if not scale then return false end

    -- The cart's blank square, kept as the cart paints it for BOTH kinds of
    -- art -- which is where this screen parts company with the dex arm.
    -- There, supplied art is backed with black because the #DEX panel behind
    -- it is black (PokedexMenu.lua:1446) and the palette's entry would read as
    -- a coloured card the sprite was placed on.  This panel is WHITE:
    -- Chrome.clear fills the whole 160x144 with white (Chrome.lua:30-35) and
    -- so does drawWidescreen (SummaryMenu.lua:1119-1120).  Monsters' palettes
    -- here come from Palettes.monColors, whose entry 1 is WHITE by
    -- construction (Palettes.lua:242), so the cart's own fill already IS the
    -- panel colour and reading it through GbcPalette.color keeps whatever rBGP
    -- remap is in force.  A black square instead would be a black box in the
    -- corner of a white page.
    local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
    G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
    G.rectangle("fill", PIC_ORIGIN_X, PIC_ORIGIN_Y, PIC_BOX, PIC_BOX)

    G.setColor(1, 1, 1, 1)
    local function body() G.draw(image, x, y, 0, scale, scale) end
    -- A four-shade NATIVE set is art the GBC palette is RIGHT for, and it
    -- arrives through this same seam, so the flag decides rather than the
    -- source -- drawing such a set unshaded renders it grey.
    if art.trueColor or not (colors and GbcPalette.available()) then
      shared.unshaded(body)
    else
      GbcPalette.with(colors, body)
    end
    -- drawPicBlock leaves the colour white behind it (SummaryMenu.lua:911) and
    -- the placements printed straight after depend on that.
    G.setColor(1, 1, 1, 1)
    return true
  end

  local originalDrawPic = SummaryMenu.drawPic
  function SummaryMenu:drawPic()
    local mon = self.mon
    local species = type(mon) == "table" and mon.species or nil
    if species == nil then return originalDrawPic(self) end
    -- A party Unown's page shows that mon's OWN letter: StatsScreen_PlaceFrontpic
    -- runs GetUnownLetter off wTempMonDVs before the frontpic, which is what
    -- picFor's Unown arm transcribes (SummaryMenu.lua:882-887).  The sprite
    -- sets have no letters to answer with -- the 201-a..z sheet is skipped when
    -- they are built (dev/tools/build_sets.py:779) -- so asking would trade a
    -- right letter for a generic Unown.  The cart keeps this one.
    if species == Unown.SPECIES then return originalDrawPic(self) end
    -- The live mon goes with the question: the registry reads shininess off
    -- its DVs, so a shiny gets its own art where the set has one.  It is also
    -- why the palette bypass is safe for a shiny -- the shiny colouring is in
    -- the art rather than in the palette that is being skipped.
    local art = shared.artFor(self, species, resolveArt, self.pokemon,
      self.game and self.game.data, mon)
    if not art then return originalDrawPic(self) end
    -- A failure falls back to the cart's own pic rather than leaving the block
    -- empty: this is an optional integration and the screen behind it works
    -- without it.
    local ok, drew = pcall(drawModPic, self, mon, art)
    if ok and drew then return end
    originalDrawPic(self)
  end

  installed = true
  return true
end

setmetatable(M, { __call = function(_, generation, resolveArt, shared)
  return M.install(generation, resolveArt, shared)
end })

return M
