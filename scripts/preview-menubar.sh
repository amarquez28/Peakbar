#!/usr/bin/env bash
#
# Renders every menu bar style to a PNG so layout changes can be eyeballed at
# real size without launching the app (and without a Retina screenshot).
#
# The status item is only ~24pt tall and macOS gives it no room to spare, so
# spacing changes in MenuBarRenderer are much easier to judge from this strip
# than from the menu bar itself.
#
# Usage: scripts/preview-menubar.sh [output.png]
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/PeakBar/PeakBar"
out="${1:-$root/build/menubar-preview.png}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$(dirname "$out")"

# The renderer only needs these four sources — no app, no asset catalog. Custom
# symbols (the GPU glyph) fall back to their stock SF Symbol here.
swiftc -O -o "$work/preview" \
  "$root/scripts/preview/main.swift" \
  "$src/Stats/StatType.swift" \
  "$src/Stats/StatsSnapshot.swift" \
  "$src/MenuBar/MenuBarFormatter.swift" \
  "$src/MenuBar/MenuBarRenderer.swift"

"$work/preview" "$out"
echo "Wrote $out"
