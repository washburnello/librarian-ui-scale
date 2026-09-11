#!/usr/bin/env bash
# Launch the game directly through Proton with the UE4SS DLL override applied,
# so it can be tested without editing Steam launch options.
#
# This does not go through Steam, so the Steam overlay/Steamworks may behave
# differently. For normal play, prefer the Steam launch option instead:
#   WINEDLLOVERRIDES="dwmapi=n,b" %command%
set -euo pipefail

GAME_ROOT="${GAME_ROOT:-$HOME/.steam/steam/steamapps/common/Librarian Tidy Up the Arcane Library!}"
PROTON_DIR="${PROTON_DIR:-$HOME/.steam/steam/steamapps/common/Proton - Experimental}"
COMPAT_DATA="${STEAM_COMPAT_DATA_PATH:-$HOME/.steam/steam/steamapps/compatdata/4197610}"

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/steam"
export STEAM_COMPAT_DATA_PATH="$COMPAT_DATA"
export WINEDLLOVERRIDES="dwmapi=n,b"

echo "Proton:    $PROTON_DIR/proton"
echo "Game:      $GAME_ROOT/Librarian.exe"
echo "Override:  WINEDLLOVERRIDES=$WINEDLLOVERRIDES"
echo

exec "$PROTON_DIR/proton" run "$GAME_ROOT/Librarian.exe" "$@"
