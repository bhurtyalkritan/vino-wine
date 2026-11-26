#!/bin/bash
# Copies the license files of the Homebrew libraries bundled in vino-wine, lists them in LIBRARIES.txt,
# and downloads the exact source of the (L)GPL ones, which their licenses require us to offer.
# Usage: licenses.sh <file listing the bundled libraries' real paths> <licenses folder> <sources folder>
set -euo pipefail
LIST=$1
LIC=$2
SRC=$3
CELLAR=$(brew --cellar)
mkdir -p "$LIC" "$SRC"

{
    echo "Libraries bundled in vino-wine, from Homebrew. Each keeps its own license; its license files are in the folder of"
    echo "the same name next to this file. Homebrew's build recipes, including any patches they apply:"
    echo "https://github.com/Homebrew/homebrew-core/tree/HEAD/Formula"
    echo "The source of every (L)GPL library is attached to the vino-wine release it shipped in."
    echo
    printf '%-14s %-12s %-36s %s\n' Library Version License Source
    sed "s|^$CELLAR/||" "$LIST" | awk -F/ '{print $1, $2}' | sort -u | while read -r formula version; do
        mkdir -p "$LIC/$formula"
        find "$CELLAR/$formula/$version" -maxdepth 1 -type f \( -iname 'COPYING*' -o -iname 'LICEN[CS]E*' -o -iname 'NOTICE*' \) \
            -exec cp {} "$LIC/$formula/" \;
        [ -n "$(ls -A "$LIC/$formula")" ] || echo "warning: $formula has no license file; LIBRARIES.txt still names its license" >&2
        # the source of the version actually bundled: Homebrew's catalogue may already point at a newer one
        IFS=$'\t' read -r license url < <(brew info --json=v2 "$formula" | python3 -c '
import json, sys
f = json.load(sys.stdin)["formulae"][0]
installed = sys.argv[1].split("_")[0]  # 3.8.13_2 -> 3.8.13 (the _2 is a Homebrew rebuild)
url = f["urls"]["stable"]["url"].replace(f["versions"]["stable"], installed)
print(f.get("license") or "see its folder", url, sep="\t")' "$version")
        printf '%-14s %-12s %-36s %s\n' "$formula" "$version" "$license" "$url"
        if [[ $license == *GPL* ]]; then
            curl -fsSL -o "$SRC/$(basename "$url")" "$url"
        fi
    done
} > "$LIC/LIBRARIES.txt"
