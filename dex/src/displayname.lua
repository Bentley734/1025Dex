-- How a name this mod supplies is cased before it is shown.
--
-- The cart writes every species and every move in CAPITALS, and the engine
-- draws whatever string a record carries -- so a registered record spelled
-- "Chikorita" prints beside PIKACHU and reads as a different game.  The
-- sources this mod builds from are title-cased ("Chikorita", "Aqua Jet") and
-- its form records are slugs ("squawkabilly-yellow-plumage"), so the casing
-- has to happen somewhere on the way to the screen.
--
-- It happens HERE, and here only, because the alternative -- uppercasing in
-- the generated data -- would put a display decision in a file that is also
-- this mod's data export, and would need a rebuild to change.
--
-- ASCII ONLY, deliberately.  Three separate reasons, and all of them have to
-- hold at once:
--
--   * string.upper is byte-wise.  It has no idea UTF-8 exists, so "é"
--     (0xC3 0xA9) is two bytes it walks past individually -- the same fact
--     src/dexsearch.lua's FOLD table is built around, from the other
--     direction.  Whatever it did to those bytes would be a guess about an
--     encoding it cannot see.
--   * string.upper is locale-dependent.  Under the C locale a byte >= 0x80
--     is left alone, which is the behaviour this file wants, but that is a
--     property of the locale and not a promise of the language.  The map
--     below is written out so the answer cannot change under someone else's
--     setlocale.
--   * The font has no uppercase accented glyph.  data/generated/font.lua
--     carries a lowercase "é" (code 186) and NOTHING at all for "É", and
--     Font.encode turns a character it has no tile for into a SPACE without
--     stopping.  Uppercasing Flabébé "properly" would therefore print
--     FLAB B -- two holes where the accents were.  Leaving the accent alone
--     prints FLABéBé, which is mixed-case and slightly odd, and is the
--     better of the two: every glyph in it is one the player can read.
--
-- The same reasoning covers ♀ and ♂ (font codes 245 and 239) and the curly
-- apostrophe in Sirfetch’d (code 113) -- all three are renderable, none of
-- them has a case, and all three are left exactly as they arrived.
--
-- Byte length is unchanged for every name in the payload, because only
-- a-z moves and it moves within one byte.  Nothing that fits before this
-- runs can overflow after it.

local M = {}

-- Written out rather than derived with string.upper for the locale reason
-- above: this is the whole definition of what "uppercase" means here.
local UPPER = {}
for byte = string.byte("a"), string.byte("z") do
  UPPER[string.char(byte)] = string.char(byte - 32)
end

-- The parentheses force one return value.  gsub answers the string and a
-- replacement count, and this is called in argument position -- a stray
-- count expanding at the end of a call's argument list is the bug
-- src/dexsearch.lua's normalise guards the same way.
function M.upper(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("[a-z]", UPPER))
end

return M
