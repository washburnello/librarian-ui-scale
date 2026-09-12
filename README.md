# librarian-ui-scale

A mod for **Librarian: Tidy Up the Arcane Library!** that adds a **UI Scale**
slider to the game's Settings menu, so text and UI elements can be made larger
for playing on a TV (e.g. a docked Steam Deck).

Built on [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). No game files are
modified; the mod is a Lua script that runs at runtime.

## Status

- ✅ Global UI scaling works and is applied live (`UUserInterfaceSettings.ApplicationScale`).
- ✅ A `UI Scale` row is injected into **Settings → Game Settings** using the
  game's float row. The slider **snaps to 0.25×–3.00× in 0.25 steps**, and the
  row shows the current value (e.g. `UI Scale: 1.50x`).
- ✅ The chosen value is remembered between sessions.
- ✅ The row is re-injected if the Settings menu is closed and reopened.
- ✅ The row is registered in the game's controller-focus list so a gamepad can
  reach it (implemented and verified via the game's own navigation events, but
  not yet tried on a physical controller).

See [`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md) for how it
works.

## Install

1. Install UE4SS into the game's `Librarian/Binaries/Win64` folder
   (a pinned, known-good build is attached to each release).
2. Copy the `LibrarianUIScale` folder into `.../Binaries/Win64/ue4ss/Mods/`.
3. Enable it via `enabled.txt` (or add `LibrarianUIScale : 1` to `Mods/mods.txt`).

### Steam Deck / Linux (Proton)

UE4SS will not load unless Wine loads the bundled `dwmapi.dll`. Add this Steam
launch option:

```
WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

Then launch the game and open **Settings**. A `UE4SS.log` appearing next to
`UE4SS.dll` confirms the loader is injecting.

## Usage

- Open **Settings → Game Settings** and use the **UI Scale** slider (it snaps to
  the 0.25 steps; left/right on a controller works when the row is focused).
- `1.00x` is vanilla; the range is `0.25x`–`3.00x` in `0.25` steps.
- The row label shows the current scale.
- The value is saved to `Scripts/scale.txt` and re-applied on the next launch.

## Development

Everything is plain Lua; no Unreal Editor or asset cooking is required.

```
tools/fetch-ue4ss.sh     # download the pinned UE4SS build into ./ue4ss
tools/install-dev.sh     # install UE4SS + the mod into the local game
tools/run-game.sh        # launch the game through Proton with the DLL override
```

The mod also exposes a file-driven command channel for debugging: write a line
to `Scripts/cmd.txt` and it executes on the game thread (see
`docs/REVERSE_ENGINEERING.md`).

## License

MIT (see [`LICENSE`](LICENSE)). UE4SS is MIT-licensed; see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
