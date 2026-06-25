#!/usr/bin/env bash
#
# build-dmg.sh — Build PeakBar and package it as build/PeakBar.dmg.
#
# Usage:
#   ./scripts/build-dmg.sh [adhoc|developer-id]
#
#   adhoc          (default) FREE path. Ad-hoc signs the app with no Apple
#                  Developer account. The DMG is NOT notarized, so on first
#                  launch users must bypass Gatekeeper once (see README).
#
#   developer-id   PAID path. Requires an Apple Developer Program membership and
#                  a "Developer ID Application" certificate. Exports a Developer
#                  ID-signed app ready for notarize.sh. Needs $APPLE_TEAM_ID.
#
# Optional environment:
#   CONFIGURATION  xcodebuild configuration. Default: Release
#
# Requires: Xcode command line tools, and `create-dmg` (brew install create-dmg).

set -euo pipefail

MODE="${1:-adhoc}"

# --- Resolve paths -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PROJECT="PeakBar/PeakBar.xcodeproj"
SCHEME="PeakBar"
CONFIGURATION="${CONFIGURATION:-Release}"

BUILD_DIR="${REPO_ROOT}/build"
DMG_PATH="${BUILD_DIR}/PeakBar.dmg"
DMG_STAGE="${BUILD_DIR}/dmg-stage"

# --- Preconditions -----------------------------------------------------------
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg not found. Install it with: brew install create-dmg" >&2
  exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# --- Produce PeakBar.app -----------------------------------------------------
APP_PATH=""

case "${MODE}" in
  adhoc)
    echo "==> Building (${CONFIGURATION}, ad-hoc signed, no Apple account)"
    DERIVED="${BUILD_DIR}/DerivedData"
    xcodebuild build \
      -project "${PROJECT}" \
      -scheme "${SCHEME}" \
      -configuration "${CONFIGURATION}" \
      -derivedDataPath "${DERIVED}" \
      -destination 'generic/platform=macOS' \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="-" \
      DEVELOPMENT_TEAM="" \
      PROVISIONING_PROFILE_SPECIFIER=""
    APP_PATH="${DERIVED}/Build/Products/${CONFIGURATION}/PeakBar.app"
    ;;

  developer-id)
    if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
      echo "error: developer-id mode requires APPLE_TEAM_ID to be set." >&2
      exit 1
    fi
    echo "==> Archiving (${CONFIGURATION}, Developer ID)"
    ARCHIVE_PATH="${BUILD_DIR}/PeakBar.xcarchive"
    EXPORT_DIR="${BUILD_DIR}/export"
    EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"

    cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${APPLE_TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

    xcodebuild archive \
      -project "${PROJECT}" \
      -scheme "${SCHEME}" \
      -configuration "${CONFIGURATION}" \
      -archivePath "${ARCHIVE_PATH}" \
      -destination 'generic/platform=macOS' \
      DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
      CODE_SIGN_STYLE=Automatic

    echo "==> Exporting Developer ID app"
    xcodebuild -exportArchive \
      -archivePath "${ARCHIVE_PATH}" \
      -exportPath "${EXPORT_DIR}" \
      -exportOptionsPlist "${EXPORT_OPTIONS}"
    APP_PATH="${EXPORT_DIR}/PeakBar.app"
    ;;

  *)
    echo "error: unknown mode '${MODE}'. Use 'adhoc' or 'developer-id'." >&2
    exit 1
    ;;
esac

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: expected app not found at ${APP_PATH}" >&2
  exit 1
fi

# --- Package DMG -------------------------------------------------------------
# Stage only the .app in a clean folder so the DMG doesn't pick up extra files.
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${APP_PATH}" "${DMG_STAGE}/"

echo "==> Creating DMG"
create-dmg \
  --volname "PeakBar" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "PeakBar.app" 140 180 \
  --app-drop-link 380 180 \
  "${DMG_PATH}" \
  "${DMG_STAGE}" \
  || true   # create-dmg returns non-zero if it can't set a custom volume icon; the DMG is still produced.

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "error: DMG was not created at ${DMG_PATH}" >&2
  exit 1
fi

echo "==> Done: ${DMG_PATH} (mode: ${MODE})"
