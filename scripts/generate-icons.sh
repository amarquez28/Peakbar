#!/usr/bin/env bash
#
# generate-icons.sh — Render the app icon set and the menu bar template glyph
# from the SVG sources in design/ into the Xcode asset catalog.
#
# Requires: rsvg-convert (brew install librsvg).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DESIGN="${REPO_ROOT}/design"
ASSETS="${REPO_ROOT}/PeakBar/PeakBar/Assets.xcassets"
APPICON="${ASSETS}/AppIcon.appiconset"
MENUICON="${ASSETS}/MenuBarIcon.imageset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found. Install with: brew install librsvg" >&2
  exit 1
fi

# --- App icon: render each size directly from SVG for crispness --------------
mkdir -p "${APPICON}"
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "${size}" -h "${size}" "${DESIGN}/AppIcon.svg" -o "${APPICON}/icon_${size}.png"
done

cat > "${APPICON}/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# --- Menu bar glyph: vector PDF, rendered as a template image ----------------
mkdir -p "${MENUICON}"
rsvg-convert -f pdf "${DESIGN}/MenuBarIcon.svg" -o "${MENUICON}/MenuBarIcon.pdf"

cat > "${MENUICON}/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "filename" : "MenuBarIcon.pdf" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
JSON

# --- Custom GPU glyph for compact mode: custom SF Symbol ---------------------
# Emitted as a .symbolset (not a template imageset) so the menu bar tints and
# dims it exactly like the stock SF Symbols. The generator mirrors the geometry
# of design/GPUIcon.svg — see the constants at the top of the script.
python3 "${SCRIPT_DIR}/generate-gpu-symbol.py"

echo "Generated app icon ($(ls "${APPICON}"/*.png | wc -l | tr -d ' ') PNGs), menu bar glyph, and GPU symbol."
