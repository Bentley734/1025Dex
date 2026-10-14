# Gen 3 adapter validation

The adapter is enabled in normal 1025Dex startup. Canonical modern move records are registered before species learnsets. The old Starts.repair substitution path and algorithm are removed.

The production integration suite is `tests/gen3_production.lua`, run under the real 0.3.85 engine with `boot-gen3.py`. It checks 833 move dispatches and PP/presentation results for each of the five games, actual serializer/storage round-trips, Fairy damage, species/level legality, status accuracy, modern burn damage, doubles Ally Switch, Emergency Exit switching and Skill Link multi-hit. `gen3-adapter-regression` covers the eleven-game roster/schema/projection fixtures. Gen 1/2 focused runtime assertions remain covered separately.

`tests/gen3_native_animations_gpu.lua` exercises actual native GPU particle playback in both directions, loads the real impact texture and verifies original Tackle/Growl/Tail Whip script identity. The 138-frame probe draws the native impact splat with transparency. New move IDs use the engine's generic native animation when there is no cartridge script; no battle renderer or animation assets are imported.

The production suite exercises normal startup; the obsolete isolated development fixtures have been removed.

Limitations: no complete live playthrough was performed. The bundled upstream combat implementation has form/ally/item/overworld prerequisites and documented interaction limits. Smoke dispatch coverage establishes safe integration, not complete correctness of every conditional later-generation interaction.
