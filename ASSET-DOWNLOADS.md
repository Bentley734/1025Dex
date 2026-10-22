# Persistent 1025Dex assets

Starting with 1.2.36, updates ship a small core ZIP. Animated sprites, Gen9 static
sprites, Emerald Expansion animated/static sprites, party/menu icons, and all
1025 cries live in the separately versioned `1025Dex-assets-v1.0.0.zip`.

Install the core ZIP as usual, start a game, and choose **A DOWNLOAD** at the
first asset prompt. You can also open **1025DEX ASSETS** from the game's OPTIONS
menu in any of the 11 supported games. The screen shows download and installation
progress and reports errors with a retry option. After installation, fully
restart the game so every sprite/icon/cry cache uses the installed pack.

Assets are saved in the engine's installation-wide cache for mod ID `1025dex`,
under `dex_assets`. Replacing the mod folder or changing saves/games preserves
this cache. Code-only updates retain asset version 1.0.0 and do not download the
pack again. Leave the engine's mod cache in place when updating.

If a complete older bundled asset tree remains in your 1025Dex folder, the
manager can copy it into persistent cache without downloading it. Files are
checked against the same SHA-256 catalog used for downloads. If you remove the
old folder before updating, download the pack once instead. An incomplete old
asset tree will not be marked complete; altered local files report an error.

**B DOWNLOAD LATER** dismisses the initial prompt. Use OPTIONS to download when
ready. Until then, native cartridge art/cries and small bundled placeholders
remain available; the expanded art and cry pack requires installation.

The manager can remove cached assets after an explicit confirmation, then
download them again. Removal does not clear saves, settings, or other mods'
caches. Restart after removal. Leaving older assets in the mod folder can still
provide local artwork after the cache is removed.

The Black/White ROM companion remains a separate local import. This downloader
does not include or change imported cartridge graphics.

The asset ZIP and its checksum are also available on the 1.2.36 release page.
For offline transfer, its `assets/sprites/assets/` contents correspond to
`1025Dex/sprites/assets/`, and `assets/cries/assets/` corresponds to
`1025Dex/cries/assets/`. Copy those directories into the mod folder, then use the
manager to migrate them locally. Do not install the asset ZIP as another mod.

Maintainers: `tools/package_assets.py` builds the asset ZIP, pinned per-file
catalog/config, and a core ZIP with the heavy media excluded. Keep its asset
version and release URL unchanged for code-only updates and run it with
`--core-only`. Asset changes require
a new immutable pack version and release URL. `tools/test_assets.py` tests the
actual ZIP installer, media routing, UI, cache reuse, migration, and rejection
paths with Lua 5.3 and LuaJIT. The installer is adapted from KIM1025's persistent
asset manager.

G9 GEN3 (added in 1.5.3) is bundled separately in the core under
`sprites/g9_gen3`, using the source pack's compact indexed-color shards. It does
not change the pinned persistent asset catalog or trigger an existing-artwork
redownload.
