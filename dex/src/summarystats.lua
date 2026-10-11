-- Party summary stats box (game/src/ui/SummaryMenu.lua), patched onto the
-- engine's SummaryMenu in memory -- src/dexpage.lua is the established
-- pattern for this within this mod (plain-table class, in-memory field
-- replacement, an engine running without this mod is untouched) and this
-- file follows it.
--
-- SummaryMenu.lua's page 1 draws a bordered box at tile (0,8) 10x10
-- (Font.drawBox(0, 8, 10, 10)) holding ATTACK/DEFENSE/SPEED/SPECIAL, each
-- label on its own line with its value on the next -- eight glyph-lines for
-- four stats, in an interior a shade over 64px wide.  There is no room to
-- add SPECIAL's split without shrinking every row: two lines per stat times
-- six stats is twelve lines, and the box only has eight.  So under the
-- mod's STATS=modern option this repaints that same interior with five
-- single-line rows instead -- ATK/DEF/SPD/SP.A/SP.D, label left, value
-- right-aligned to the box's own inner edge -- leaving HP and the rest of
-- the screen (including the EXP/moves page) completely alone.  Under
-- STATS=gen1, or for a record the split never reached, this never paints
-- anything at all: originalDraw runs and nothing else touches the canvas,
-- so the vanilla screen is pixel-for-pixel what it always was.
--
-- The five values are the mon's own COMPUTED stats at its level, not base
-- stats -- ATK/DEF/SPD come straight off mon.stats (already computed by
-- Stats.calc when the mon was made or loaded), and SP.A/SP.D are produced
-- by handing that SAME Stats.calc the record's spAttack/spDefense as the
-- "special" base, through the mon's own existing special DV and stat-exp.
-- Gen 1 tracks exactly one special DV and one special stat-exp pool, and
-- both derived stats legitimately share them -- this is how Gen 2's split
-- treats an imported Gen 1 mon's single value, not a new rule invented
-- here.  This never writes the result anywhere: not to mon.stats, not to
-- the species record, not anywhere the battle engine reads.  The engine's
-- own damage maths keeps reading the collapsed baseStats.special,
-- untouched -- this box is display only.
--
-- The Sp.Atk/Sp.Def SOURCE is the record's own spAttack/spDefense fields,
-- reached through dexpage.lua's M.splitStats -- the exact function the
-- Pokédex STATS page uses, injected here by main.lua rather than
-- re-required, so the two screens share one lookup and cannot drift apart
-- on which records carry the split.
--
-- The pure logic below (statRows) takes calc and splitStats as parameters
-- instead of requiring src.pokemon.Stats/dexpage.lua itself, so it has no
-- love/engine dependency and tests/national_dex_test.lua can hand it the
-- real Stats.calc and the real dexpage.lua's splitStats and assert against
-- their actual output.

local M = {}

-- ------------------------------------------------------------- pure logic

-- Ordered { label, value } rows for `mon` (whose species/form record is
-- `def`) under the mod's STATS option, plus a second boolean return: true
-- when the five-row "modern" layout applies, false when the caller should
-- leave the screen exactly as originalDraw already left it (STATS=gen1, or
-- `def` never received the Sp.Atk/Sp.Def split).  The vanilla four rows are
-- still returned in the false case -- callers that only want the box
-- contents (tests, chiefly) do not have to branch on the boolean first.
function M.statRows(mon, def, statsMode, calc, splitStats)
  local vanilla = {
    { "ATTACK", mon.stats.attack }, { "DEFENSE", mon.stats.defense },
    { "SPEED", mon.stats.speed }, { "SPECIAL", mon.stats.special },
  }
  if statsMode ~= "modern" then return vanilla, false end
  if type(def) ~= "table" or type(def.baseStats) ~= "table" then
    return vanilla, false
  end
  local spAttack, spDefense = splitStats(def)
  if spAttack == nil or spDefense == nil then return vanilla, false end

  -- One synthetic species table, its `special` overwritten per call: calc
  -- reads baseStats.special synchronously and returns a fresh result table,
  -- so reusing this between the two calls below never lets one call see
  -- the other's base.
  local synthetic = { baseStats = {} }
  for key, value in pairs(def.baseStats) do synthetic.baseStats[key] = value end
  local dvs, statExp = mon.dvs or {}, mon.statExp
  local function special(base)
    synthetic.baseStats.special = base
    return calc(synthetic, mon.level, dvs, statExp).special
  end

  -- HP first and SPEED last: the order every game since Gen 2 prints these
  -- in, and the order the split itself implies -- the two Special rows read
  -- as a pair only when nothing is wedged between them.  Vanilla's own order
  -- (Attack, Defense, Speed, Special) is left alone above, because the four
  -- collapsed rows are the ROM's screen and not ours to reorder.
  return {
    { "HP", mon.stats.hp }, { "ATK", mon.stats.attack },
    { "DEF", mon.stats.defense }, { "SP.A", special(spAttack) },
    { "SP.D", special(spDefense) }, { "SPD", mon.stats.speed },
  }, true
end

-- ------------------------------------------------------------ engine patch

-- Same probe-before-patch shape as dexpage.lua's requireAll: a missing or
-- reshaped module means this feature quietly does not install rather than
-- taking the mod load down.  None of this runs at the top of the file, so
-- a headless test that only wants statRows never touches love or src.* at
-- all.
local function requireAll()
  local names = { "src.ui.SummaryMenu", "src.render.Font", "src.core.Strings",
    "src.pokemon.Stats" }
  local mods = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    mods[name] = value
  end
  return mods
end

-- Tile coordinates read straight off SummaryMenu.lua's own
-- `Font.drawBox(0, 8, 10, 10)` call -- if that box ever moves or resizes,
-- updating these four numbers to match is the whole fix.
local BOX_TX, BOX_TY, BOX_TW, BOX_TH = 0, 8, 10, 10

function M.install(mod, splitStats)
  if type(splitStats) ~= "function" then return false end
  local mods = requireAll()
  if not mods then return false end
  local SummaryMenu = mods["src.ui.SummaryMenu"]
  local Font = mods["src.render.Font"]
  local Strings = mods["src.core.Strings"]
  local Stats = mods["src.pokemon.Stats"]
  if type(SummaryMenu.draw) ~= "function" or type(Stats.calc) ~= "function" then
    return false
  end

  -- The box's interior, inside the one-tile border Font.drawBox draws on
  -- every side: innerRight is where a right-aligned value's last pixel
  -- belongs, innerY where the first row starts.
  local boxX, boxY = BOX_TX * 8, BOX_TY * 8
  local boxW, boxH = BOX_TW * 8, BOX_TH * 8
  local innerX, innerY = boxX + 8, boxY + 8
  local innerW, innerH = boxW - 16, boxH - 16
  local innerRight = innerX + innerW

  -- One glyph-line (8px) per row, stacked from the interior's own top.
  -- The vanilla box already proves eight glyph-lines fit this interior
  -- (four stats drawn two lines tall apiece); five single-line rows use
  -- five of those eight and leave the rest blank, rather than stretching
  -- rows out to fill height nothing asked to be filled.
  local ROW_H = 8

  local function drawModernBox(self)
    local mon = self.mon
    local def = self.game.data.pokemon[mon.species]
    local rows, modern = M.statRows(mon, def, mod.options:get("stats"),
      Stats.calc, splitStats)
    if not modern then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", innerX, innerY, innerW, innerH)
    love.graphics.setColor(0, 0, 0, 1)
    for i, row in ipairs(rows) do
      local label, text = Strings(row[1]), tostring(row[2])
      local y = innerY + (i - 1) * ROW_H
      Font.draw(label, innerX, y)
      Font.draw(text, innerRight - Font.width(text), y)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- originalDraw runs first, unconditionally and unguarded -- page 2
  -- (EXP/moves) and every gen1/unsplit case are already exactly right
  -- once it returns, and nothing below touches the canvas for them.  Only
  -- page 1 under STATS=modern with a split record gets a second, guarded
  -- pass that overpaints just the box's interior.
  local originalDraw = SummaryMenu.draw
  function SummaryMenu:draw()
    originalDraw(self)
    if self.page ~= 1 then return end
    pcall(drawModernBox, self)
  end

  return true
end

setmetatable(M, { __call = function(_, mod, splitStats) return M.install(mod, splitStats) end })

return M
