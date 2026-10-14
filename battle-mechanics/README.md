# Bundled moves and abilities

Adapted from tectorifter/Gen9Dex release v4.8.1. This component is GPL-3.0-or-later; its LICENSE and upstream notices are retained separately from the existing dex's license. Installed and loaded through 1025Dex, with its existing read API as the only species/move/ability data owner.

Includes combat move effects, ability execution, ability assignment, and legal species move learning. Excludes graphics, animations, battle scenes, debug screens, encounters, trainer rosters, IV/EV generation, nurse replacement, boss configuration, and transformation activation or option ownership.

Gen 1 and Gen 2 only. Gen 3 continues to use its native move/ability engine. Ability descriptions include upstream's overworld-only and form-dependent abilities; those require their corresponding world/form mechanics. Single battles cannot exercise ally-only effects. See upstream per-module comments for specific interaction limitations; the import does not claim that every cartridge interaction has been reproduced.
