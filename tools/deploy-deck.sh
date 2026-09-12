#!/usr/bin/env bash
# Deploy UE4SS + the LibrarianUIScale mod to a Steam Deck over SSH.
#
# Usage:
#   tools/deploy-deck.sh                 # uses deck@steamdeck
#   DECK_HOST=user@host tools/deploy-deck.sh
#   tools/deploy-deck.sh --launch-option # also set the Steam launch option
#
# The Deck must be awake with SSH enabled (Desktop Mode, or the SSH service on).
set -euo pipefail

DECK_HOST="${DECK_HOST:-deck@steamdeck}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="/home/deck/.steam/steam/steamapps/common/Librarian Tidy Up the Arcane Library!"
WIN64="$GAME_DIR/Librarian/Binaries/Win64"
SET_LAUNCH_OPTION=0
[[ "${1:-}" == "--launch-option" ]] && SET_LAUNCH_OPTION=1

if [[ ! -f "$REPO_ROOT/ue4ss/ue4ss/UE4SS.dll" ]]; then
  echo "UE4SS not found in repo. Run tools/fetch-ue4ss.sh first." >&2
  exit 1
fi

echo "==> Checking $DECK_HOST ..."
ssh -o BatchMode=yes -o ConnectTimeout=10 "$DECK_HOST" "test -d \"$WIN64\"" \
  || { echo "Game Win64 not found on the Deck at: $WIN64" >&2; exit 1; }

# Build a self-contained payload so remote paths with spaces are not an issue.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/ue4ss/Mods"
cp -f "$REPO_ROOT/ue4ss/dwmapi.dll" "$STAGE/dwmapi.dll"
cp -rf "$REPO_ROOT/ue4ss/ue4ss/." "$STAGE/ue4ss/"
cp -rf "$REPO_ROOT/mod/LibrarianUIScale/." "$STAGE/ue4ss/Mods/LibrarianUIScale/"

echo "==> Uploading payload ..."
tar czf - -C "$STAGE" . | ssh "$DECK_HOST" "cat > /tmp/librarian-uiscale.tgz"

echo "==> Installing into the game folder ..."
# NOTE: the path contains a space and '!', so it must NOT be passed as an ssh
# argument (ssh joins args with spaces and the remote shell re-splits them).
# Embed it literally inside the single-quoted remote script instead.
ssh "$DECK_HOST" bash -s <<'REMOTE'
set -euo pipefail
WIN64='/home/deck/.steam/steam/steamapps/common/Librarian Tidy Up the Arcane Library!/Librarian/Binaries/Win64'
mkdir -p "$WIN64/ue4ss/Mods"
tar xzf /tmp/librarian-uiscale.tgz -C "$WIN64"
# Enable the mod (per-mod enabled.txt is already present; add the mods.txt line too).
MODS_DIR="$WIN64/ue4ss/Mods"
if [[ -f "$MODS_DIR/mods.txt" ]] && ! grep -q '^LibrarianUIScale' "$MODS_DIR/mods.txt"; then
  sed -i '/^;/i LibrarianUIScale : 1' "$MODS_DIR/mods.txt"
fi
echo "installed:"
ls -la "$WIN64/dwmapi.dll" "$WIN64/ue4ss/UE4SS.dll" \
       "$WIN64/ue4ss/Mods/LibrarianUIScale/Scripts/main.lua"
REMOTE

if [[ "$SET_LAUNCH_OPTION" == "1" ]]; then
  echo "==> Setting Steam launch option ..."
  if ssh "$DECK_HOST" "python3 -" < "$REPO_ROOT/tools/set-deck-launch-option.py"; then
    echo "  Launch option set."
  else
    echo "  Could not set it automatically — set it in Steam manually:"
    echo '    WINEDLLOVERRIDES="dwmapi=n,b" %command%'
  fi
fi

echo
echo "==> Done."
echo "Launch option required (set in Steam > Librarian > Properties > Launch Options):"
echo '    WINEDLLOVERRIDES="dwmapi=n,b" %command%'
echo "After launching, check /home/deck/.steam/steam/steamapps/common/Librarian Tidy Up the Arcane Library!/Librarian/Binaries/Win64/ue4ss/UE4SS.log"
