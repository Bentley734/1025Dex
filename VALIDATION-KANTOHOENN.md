# Validation

## 1.2.13 missing-route merge

Compared the supplied alternate 1.2.12 ZIP against the original 1.2.11 baseline.
Its only gameplay changes are encounterSources for Routes 4, 9, 10, 11 and 22
and habitat-matched fallback for empty selected-generation pools on those routes.
Both changes are merged; its route regression test is included unchanged.

Passing checks: 4,599 supplied route/public-API assertions covering all five
routes and all 17 generation settings; full native/habitat and public-level
audits for FR/LG/Emerald; 70,622 cave assertions; 50,512 special assertions;
305,766 Ultra Beast assertions; 65,187 legacy campaign assertions.

Compared every canon-aware native map/channel pool before and after the merge
under all 17 choices, campaign on/off and League clear on/off: 145,180 group
comparisons per Kanto edition, with identical species order, counts and area
level bands. Native level metadata is unchanged. Existing v1.2.12 encounter
guides therefore remain accurate. No interactive playthrough was performed.
Reproduce the compatibility comparison with `py -3.12 tools/check_route_merge.py`.

## 1.2.12 encounter audit

ROM-backed native metadata covers 907 FireRed, 908 LeafGreen and 696 Emerald
unique area/channel/species entries. Emerald includes extra encounter headers
and Route 119 Feebas. The supplied LeafGreen ROM is revision 1.1; extraction
locates and validates its shifted tables rather than using revision 1.0 offsets.

Production pool checks cover all 17 generation choices, both campaign and
standalone modes, native species preservation, habitat/channel compatibility,
all 1,025 species in the combined campaign, native levels in public DexNav
headers, and sampled follower selections. Existing cave balance, special and
Ultra Beast regressions also pass. See ENCOUNTER-AUDIT.md for baseline counts.
Reproduce with Python 3.12 and the workspace Lua runtime:
`py -3.12 tools/test_native_encounters.py` from the extracted mod root.
No graphical playthrough was performed.

## Historical 1.2.11 companion validation

The original user-supplied ZIPs and stock gen1recomp 0.3.51 source were the comparison baseline. Native encounter extraction used the supplied FireRed USA and Emerald USA ROMs: 132 and 124 headers respectively. Only channel-presence metadata is included; no ROM bytes are packaged.

Passing checks:
- Two-region policy: 62,074 assertions, all 1,025 species covered on ROM-backed encounter channels, 512/513 regional assignments, all 17 generation choices, postgame gates, aquatic filtering and unchanged standalone outputs.
- Visible wilds/public Dex API: 16,844 assertions including 5,400 sampled exact encounters, regional membership, chaining/DexNav header parity and same-map campaign mode cache refresh.
- WildFollowers standalone API: 103,883 assertions, 19,647 samples across FR/LG/Emerald and all 17 choices. Its existing test was corrected to recognize the upstream protected Diglett's Cave generation exception; the unmodified test also failed against the original ZIP.
- WildFollowers adjoining maps with the supplied native engine: 82 assertions.
- Existing 1025Dex cave balance: 70,622 assertions; special/postgame pools: 50,512; Ultra Beast rules: 305,472.
- Existing 1025DexNav Emerald integration: 299,135 assertions.
- KIM complete FRLG bridge and Dex ownership: 1,044 assertions, both load orders and four host OS fixtures.
- New Hoenn background resolver: 134 assertions; extracted production KIM backdrop bridge: 10 assertions, including final story/trainer overrides winning over raw map terrain and stable per-battle caching.

Full-roster pool sizes on declared native encounter channels, with postgame unlocked: Kanto mean 62.51 -> 11.32 entries (81.9% reduction); Hoenn mean 19.01 -> 8.13 (57.2% reduction). These are candidate-list sizes, not in-game spawn counts or encounter-rate measurements. Special and Ultra Beast rarity weights are unchanged.

Checks execute production Lua with mocked graphics/native runtime services where noted. No graphical session, end-to-end story playthrough, emulator comparison or actual region-switch render was performed. A supplied DexNav move test requiring an absent move-audit fixture was not counted as passing. This is a tested mod build, not a claim of complete playthrough validation.

Reproduction examples from extracted mod roots with Lua 5.4 (or compatible LuaJIT loader):
1025Dex: lua tests/kanto_hoenn.lua .
KIM1025: lua tests/hoenn_backgrounds.lua .; lua tests/hoenn_bridge.lua .
WildFollowers: lua tests/campaign_compat.lua /path/to/1025Dex .
