#!/usr/bin/env bash
# Fetch the pinned, known-good UE4SS build for Librarian: Tidy Up the Arcane Library!
#
# We do not download UE4SS "experimental-latest" directly because upstream
# overwrites that release in place; a specific build can vanish. Instead we
# pull the unmodified copy bundled with Librarian-AP at a pinned commit,
# which is confirmed to load with this game (including under Proton).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/ue4ss"

# Pinned source of the bundled UE4SS build.
# Build: UE4SS_v3.0.1-946-g265115c0 (upstream commit 265115c0)
LIBRARIAN_AP_REPO="https://github.com/Str8UpWHITE64/Librarian-AP.git"
LIBRARIAN_AP_COMMIT="${LIBRARIAN_AP_COMMIT:-9ffa6d42c1936544918c75e7326768ae1e10b0de}"

EXPECTED_UE4SS_SHA="df9e6e9a2280972b1c28ce590700feacc752b447204f8baadeb95f5776957055"
EXPECTED_PROXY_SHA="598d95a170389a80ceea52d9fa208dc55fc7a652a5283e440bc19a06bc17f31e"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning Librarian-AP ($LIBRARIAN_AP_COMMIT) ..."
git clone --depth 1 --branch "$LIBRARIAN_AP_COMMIT" "$LIBRARIAN_AP_REPO" "$TMP/Librarian-AP" 2>/dev/null \
  || git clone --depth 1 "$LIBRARIAN_AP_REPO" "$TMP/Librarian-AP"

SRC="$TMP/Librarian-AP/third_party/UE4SS"
if [[ ! -f "$SRC/ue4ss/UE4SS.dll" ]]; then
  echo "UE4SS files not found in Librarian-AP checkout ($SRC)" >&2
  exit 1
fi

echo "Copying UE4SS into $DEST ..."
mkdir -p "$DEST"
cp -rf "$SRC/." "$DEST/"

echo "Verifying checksums ..."
ue4ss_sha="$(sha256sum "$DEST/ue4ss/UE4SS.dll" | awk '{print $1}')"
proxy_sha="$(sha256sum "$DEST/dwmapi.dll" | awk '{print $1}')"
[[ "$ue4ss_sha" == "$EXPECTED_UE4SS_SHA" ]] || { echo "UE4SS.dll checksum mismatch: $ue4ss_sha" >&2; exit 1; }
[[ "$proxy_sha" == "$EXPECTED_PROXY_SHA" ]] || { echo "dwmapi.dll checksum mismatch: $proxy_sha" >&2; exit 1; }

echo "OK. UE4SS $EXPECTED_UE4SS_SHA"
