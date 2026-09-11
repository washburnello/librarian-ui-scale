#!/usr/bin/env bash
# Install UE4SS + the LibrarianUIScale mod into the local game install.
#
# Override GAME_ROOT if the game lives somewhere else:
#   GAME_ROOT="/path/to/Librarian Tidy Up the Arcane Library!" tools/install-dev.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_ROOT="${GAME_ROOT:-$HOME/.steam/steam/steamapps/common/Librarian Tidy Up the Arcane Library!}"
WIN64="$GAME_ROOT/Librarian/Binaries/Win64"
MOD_NAME="LibrarianUIScale"

if [[ ! -d "$WIN64" ]]; then
  echo "Game Win64 directory not found:" >&2
  echo "  $WIN64" >&2
  echo "Set GAME_ROOT=/path/to/game and re-run." >&2
  exit 1
fi

if [[ ! -f "$REPO_ROOT/ue4ss/ue4ss/UE4SS.dll" ]]; then
  echo "UE4SS runtime not found in repo. Run tools/fetch-ue4ss.sh first." >&2
  exit 1
fi

echo "==> Installing UE4SS into $WIN64"
cp -f "$REPO_ROOT/ue4ss/dwmapi.dll" "$WIN64/dwmapi.dll"
mkdir -p "$WIN64/ue4ss"
cp -rf "$REPO_ROOT/ue4ss/ue4ss/." "$WIN64/ue4ss/"
[[ -f "$REPO_ROOT/ue4ss/LICENSE" ]] && cp -f "$REPO_ROOT/ue4ss/LICENSE" "$WIN64/ue4ss/LICENSE-UE4SS"

echo "==> Installing mod '$MOD_NAME'"
mkdir -p "$WIN64/ue4ss/Mods/$MOD_NAME"
cp -rf "$REPO_ROOT/mod/$MOD_NAME/." "$WIN64/ue4ss/Mods/$MOD_NAME/"

echo "==> Enabling mod in mods.json / mods.txt"
python3 - "$WIN64/ue4ss/Mods" "$MOD_NAME" <<'PY'
import json, os, sys

mods_dir, name = sys.argv[1], sys.argv[2]

json_path = os.path.join(mods_dir, "mods.json")
data = []
if os.path.exists(json_path):
    try:
        with open(json_path) as f:
            data = json.load(f)
    except Exception:
        data = []
if not any(e.get("mod_name") == name for e in data):
    data.append({"mod_name": name, "mod_enabled": True})
with open(json_path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")

txt_path = os.path.join(mods_dir, "mods.txt")
if os.path.exists(txt_path):
    lines = open(txt_path).read().splitlines()
    if not any(l.split(":")[0].strip() == name for l in lines):
        out, inserted = [], False
        for line in lines:
            if not inserted and line.startswith(";"):
                out.append(f"{name} : 1")
                inserted = True
            out.append(line)
        if not inserted:
            out.append(f"{name} : 1")
        open(txt_path, "w").write("\n".join(out) + "\n")
PY

echo
echo "==> Done."
echo
echo "Launch the game with this Steam launch option:"
echo '    WINEDLLOVERRIDES="dwmapi=n,b" %command%'
echo
echo "Or launch directly for testing with: tools/run-game.sh"
echo "UE4SS log: $WIN64/UE4SS.log"
