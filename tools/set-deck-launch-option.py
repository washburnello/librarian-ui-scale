#!/usr/bin/env python3
"""Set the Steam launch option for Librarian (app 4197610) on a Steam Deck.

Run over SSH on the Deck:
    ssh deck@steamdeck "python3 -" < tools/set-deck-launch-option.py

Adds or updates:
    WINEDLLOVERRIDES="dwmapi=n,b" %command%

which is required for UE4SS (the dwmapi.dll proxy) to load under Proton.
Backs up each modified localconfig.vdf first.
"""
import glob
import re
import shutil
import sys

OPTION = 'WINEDLLOVERRIDES="dwmapi=n,b" %command%'
APP_ID = "4197610"
USERDATA_GLOB = "/home/deck/.steam/steam/userdata/*/config/localconfig.vdf"


def set_option(path):
    with open(path, encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()

    m = re.search(r'"%s"\s*\{' % APP_ID, text)
    if not m:
        return None

    start = m.end()
    depth = 1
    i = start
    while i < len(text) and depth > 0:
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    if depth != 0:
        return "unbalanced braces; skipped"

    block = text[start:i - 1]
    escaped = OPTION.replace("\\", "\\\\").replace('"', '\\"')

    if re.search(r'"LaunchOptions"\s*"[^"]*"', block):
        new_block = re.sub(r'("LaunchOptions"\s*)"[^"]*"',
                           lambda mm: mm.group(1) + '"' + escaped + '"',
                           block, count=1)
    else:
        trailing = block[len(block.rstrip()):]
        new_block = (block.rstrip()
                     + '\n\t\t\t\t\t\t"LaunchOptions"\t\t"' + escaped + '"'
                     + trailing)

    new_text = text[:start] + new_block + text[i - 1:]
    if new_text == text:
        return "already set"

    shutil.copy2(path, path + ".bak-librarian-uiscale")
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(new_text)
    return "updated"


def main():
    found = False
    for path in glob.glob(USERDATA_GLOB):
        result = set_option(path)
        if result:
            found = True
            print(f"{result}: {path}")
    if not found:
        print("No localconfig.vdf with an app block for %s found." % APP_ID)
        print("Set the launch option manually in Steam.")
        sys.exit(1)


if __name__ == "__main__":
    main()
