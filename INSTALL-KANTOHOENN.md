# KantoHoenn companion updates

Replace 1025Dex with 1.2.13 and restart the current game session. Keep your existing Hoennto, KIM1025, WildFollowers and DexNav companions: they already read the live Dex API. No save migration is required. The v1.2.12 encounter guides still match this build's canon-aware runtime pools.

Choose WILD GENS = GEN 1-9 for the full regional distribution. The campaign atlas is active with Hoennto/KantoHoenn enabled. Native encounter preservation and habitat corrections also apply in standalone play. No ROMs or app modifications are included; use your separately imported FireRed/LeafGreen/Emerald files.

The atlas gives added residents one primary and one alternate habitat-compatible home per channel, with small local fallback pools where needed. Every canon wild species is retained on its native area/channel, independently of those regional assignments. Canon species may appear in both regions. FR/LG use their own version-specific native tables. Scripted gifts, bosses, roamers and story encounters remain controlled by the games. Legendary/mythical additions and Ultra Beasts retain their existing League-clear gates.

For narrower generation options, up to three selected-generation visitors fill an otherwise empty regional ordinary pool. This keeps those options usable. Route 1's permanent beginner encounters and Diglett's Cave's weighted native residents retain their existing exceptions.

EncounterAtlas.csv lists full-roster wild homes by game, added-species level gates and postgame requirements. Native level ranges are stored in encounters/native.lua and used by the public API. Native scripted encounters are not listed. ENCOUNTER-AUDIT.md reports the missing canon encounters restored from 1.2.11.

WildFollowers uses the same Dex selection API. Its update only invalidates and refreshes cached encounter populations when campaign mode changes; existing movement, follower presentation and spawn settings remain unchanged. DexNav uses the same live pools.

KIM uses Emerald's final, resolved battle environment ID, including trainer/story overrides, rather than FRLG environment assumptions. Grass, sea, forest and suitable caves use existing HD art. Desert/sand, underwater, freshwater ponds, mountain/volcanic/ash areas, Mt. Pyre, indoor battles, Frontier, gyms/leaders, Elite Four/champion, teams and the weather trio keep the native Emerald background when no suitable Hoenn HD scene exists. This update adds routing, not new Hoenn artwork. Turn HD BATTLE BACKGROUNDS off to use native backgrounds everywhere.

Validation is headless. Complete graphical playthroughs and live region-switch rendering have not been run. See VALIDATION-KANTOHOENN.md for the exact checks and limits.
