# librarian-ui-scale

A mod for **Librarian: Tidy Up the Arcane Library!** that adds a **UI Scale**
slider to the game's Settings menu, so text and UI elements can be made larger
for playing on a TV (e.g. a docked Steam Deck).

Built on [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). No game files are
modified; the mod is a Lua script that runs at runtime.

## Status

- ✅ Global UI scaling works and is applied live (`UUserInterfaceSettings.ApplicationScale`).
- ✅ A `UI Scale` row (1.0×–2.0×) is injected into **Settings → Game Settings** using the game's own float-row widget.
- ✅ The chosen value is remembered between sessions.
- ⏳ Gamepad focus/navigation of the injected row is not finished yet; mouse dragging works.

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

- Open **Settings → Game Settings** and use the **UI Scale** slider.
- `1.0` is vanilla; `2.0` roughly doubles the UI.
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
