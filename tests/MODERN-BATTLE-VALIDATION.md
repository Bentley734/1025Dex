# Modern combat validation

`modern_battle_runtime.lua` runs after loading the full 1025Dex through the real engine mod Loader into `data`; provide Lua globals `data`, `loader`, `version`. Use a fresh Lua runtime per game. The fixture uses actual ROM-imported data and engine battle classes, not copied move/ability implementations. Its Gen 1 Berry record is explicitly a held-item-provider fixture, since Red has no native berries. No player save is written.

Validated against the installed gen1recomp update 0.3.85 and ROM-import caches for Red, Blue, Yellow, Gold, Silver and Crystal. All focused assertions pass. A separate fresh-battle sweep dispatched every one of the 833 dex moves in each game (4998 calls), with no thrown errors, guarded effect errors, event errors or failed damage-hook links. This is execution coverage, not proof of every conditional interaction; focused assertions establish actual outcomes for the named scenarios.

Full `tests/all_games.lua` schema, 1025-species roster, Hoennto projection and native encounter regressions pass across eleven games. Full compilation passes under LuaJIT 2.1 and Lua 5.3. No renderer, sprite, animation or Johnto source is changed by this release. No live playthrough was performed.
