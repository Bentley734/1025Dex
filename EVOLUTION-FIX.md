# Emerald added-species evolution fix

Applin's evolution could stall at “What? CRUMBS is evolving!” before the
cancel window. Emerald's native front-animation controller looked up a ROM
animation script using an extended species slot. No script existed, so the
task failed while the evolution scene continued waiting on its busy sprite.

The Gen 3 adapter now routes National species 387–1025 through the engine's
skip-front-animation path. Cries and their pan settings still play. The sprite
provider still supplies the selected artwork, and the normal evolution scene,
species change, move learning, and B-cancel window remain in use. Native
species retain their ROM animation path. The guard covers both the source
and target of an evolution, as well as other calls through `doFront`.

Run `python 1025Dex/tools/test_gen3_evolution_animation.py` from the workspace.
An optional engine directory argument tests another local engine version.
The test uses the actual engine animation controller and evolution state
machine with ROM data and UI fixtures. It first reproduces the original
failed-task/busy-sprite condition, then verifies completion and cancellation
for all 639 added species, unchanged nicknames, native animation routing,
and cry/noCry/pan behavior. It does not substitute for a graphical playthrough
with the user's save or test every species' evolution eligibility.

Replace the installed 1025Dex folder with this updated folder and restart
the game. No save migration is required.
