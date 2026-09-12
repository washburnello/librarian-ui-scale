# Distribution & modding tooling for Librarian

Research notes for how mods can be packaged and distributed for
*Librarian: Tidy Up the Arcane Library!* (app `4197610`).

## Steam Workshop: not available for this game

Workshop requires the **developer** to enable it (add a workshop depot, upload
the SDK, publish the item schema). This game does not have it:

- SteamDB app config lists no Workshop depot and no workshop-related keys.
- The local `appmanifest_4197610.acf` contains no `Workshop` entries.
- The store page has no Workshop section.

So there is nothing to "leverage" on the Workshop side unless ArtRising adds it.
Mods for this game are distributed manually (Nexus Mods currently hosts ~17, plus
GitHub), typically installed with UE4SS.

## What the community's mods actually use

- **UE4SS** is the loader for essentially all of them (Lua scripts, and sometimes
  a companion `.pak`).
- The Archipelago integration ships a `LibrarianAPHUDFix.pak` placed in
  `Librarian/Content/Paks/LogicMods/`. That is **`BPModLoaderMod`**: UE4SS's
  blueprint-mod loader. It mounts blueprint "logic mods" from `LogicMods`
  without replacing game files. This is the supported route to ship *assets*
  (new widgets, edited blueprints) as a mod.

## Tool ecosystem we could leverage

| Tool | Use |
|---|---|
| **UE4SS** | Loader + Lua API + `BPModLoaderMod`; generates UHT header dumps (already done in this repo). |
| **FModel** | Browse/export cooked assets (see the game's widgets, find the timer). |
| **retoc** | Pack/unpack IoStore (`.utoc/.ucas`) and convert Zen ↔ Legacy assets. This game is IoStore (UE 5.5). |
| **UAssetGUI / UAssetAPI** | Edit cooked asset *properties* without the editor (limited; can't restructure UMG widget trees). |
| **UnrealPak / repak** | Build `.pak` archives. |
| **UE4 Game Project Generator** | Build a modding project from UE4SS's UHT dump — a step toward proper Blueprint mods. |
| **JsonAsAsset** | Import FModel JSON exports into the editor as real assets. |

## Practical implications for us

- **Runtime Lua (current approach)** needs no editor and works for the global UI
  scale and the injected option row. Its limit is that it can't re-author the
  game's widget layouts (e.g. re-anchor the pause timer), so layout artifacts of
  global scaling can only be worked around.
- **A companion `.pak` via `BPModLoaderMod`** is the middle ground for real UI
  work: ship a new/edited widget without touching game files. Viewer/repack
  tools (FModel + retoc) can inspect and move assets, but **creating or
  restructuring UMG widget trees realistically needs the Unreal Editor** matching
  UE 5.5. UAssetGUI can tweak scalar properties, not redesign layouts.
- **Steam Workshop** would only enter the picture if the developer adds it; a mod
  cannot add Workshop support to someone else's game.
