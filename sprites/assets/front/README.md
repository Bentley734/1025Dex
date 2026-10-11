# assets/front

Drop DBK **front** (enemy) sprite sheets here for the mod to load.

* File name = the pack's own stem, e.g. `ABOMASNOW.png`, `CHARIZARD_1.png`
  (mega Charizard X), `ALCREMIE_63.png` (gigantamax Alcremie),
  `ABOMASNOW_female.png`.
* One PNG per Pokemon: a horizontal frame strip (the pack's format). Do not
  split it -- the mod crops frames out in memory.
* Folder names are case-sensitive and lower-case here: `front`, `front_shiny`,
  `back`, `back_shiny`.

Anything missing here simply uses the game's vanilla pic — the mod does not
touch the network, so sheets only ever come from these four folders.

To fill this folder (and the other three), run
`python3 ../download_assets.py` from this folder.
