# Canonical species numbers — 1.2.15

National Pokédex numbers 1–1025 are the public species identity. The registered
`dex` field already uses these numbers. A native engine species ID is a different
value: Game Boy games use string keys; GBA games use cartridge slots, including
reserved entries and a nonuniform Hoenn order. Native IDs must stay intact for
existing saves and engine tables.

For example, National 399 is Bidoof, while its expanded GBA slot is 463.
Treecko is National 252 / native 277; Chimecho is National 358 / native 411.
Subtracting a constant from every GBA species ID is incorrect.

Use the public conversion service instead of game-specific offsets:

```lua
local dex = mod:find('1025dex')
local numbers = dex and dex.exports.speciesNumbers
if numbers then
  local national = numbers.nationalOfSpecies(pokemon.species)
  local nativeSpecies = numbers.speciesFromNational(399)
  local nativeKey = numbers.keyFromNational(399)
end
```

`speciesNumbers.apiVersion` is 1; `numbering` is `national`; `maxNational` is 1025.
`nationalOfSpecies` accepts a native key or GBA slot. `speciesFromNational`
returns the current game's native species value. `keyFromNational` returns a
native string key. Unavailable or invalid lookups return nil. Alternate forms
need a separate form identity; this service does not allocate extra National
numbers. Resolve again after switching cartridges; never save another game's
native slot as a portable identity.

The service reads the live registry and native lookup tables. It does not
rewrite party, PC, imported ROM or campaign data. Mods that already use National
numbers need no new numbering patch. Mods that previously treated native slots
as National numbers still need to correct that assumption once; this shared
API removes the need to maintain their own per-game offset fixes.

Visible encounter providers can also call `exports.chooseGBWildEncounter(hit,
mapId, terrain, rng)` for R/B/Y/G/S/C. `hit` is a successful native encounter
with `species` and `level`; terrain is `land` or `water`; `rng` has the
`math.random` calling convention. This applies the same habitat, generation
and League rules as 1025Dex's ordinary encounter hook. GBA providers retain
`exports.chooseWildEncounter(mapId, terrain, nativeLevel)`.
