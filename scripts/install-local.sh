#!/usr/bin/env bash
#
# install-local.sh — Build a Release PeakBar.app (ad-hoc signed) and install it
# into /Applications, replacing any existing copy and relaunching it.
#
# This is for running PeakBar on THIS Mac. Because the app is built locally it
# is not quarantined, so it opens with no Gatekeeper warning.
#
# Requires: Xcode command line tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

DERIVED="$(mktemp -d)/dd"

echo "==> Building Release (ad-hoc)…"
xcodebuild build \
  -project PeakBar/PeakBar.xcodeproj \
  -scheme PeakBar \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  >/dev/null

APP="${DERIVED}/Build/Products/Release/PeakBar.app"
if [[ ! -d "${APP}" ]]; then
  echo "error: build did not produce ${APP}" >&2
  exit 1
fi

echo "==> Quitting any running PeakBar…"
pkill -x PeakBar 2>/dev/null || true
sleep 1

echo "==> Installing to /Applications…"
rm -rf /Applications/PeakBar.app
cp -R "${APP}" /Applications/

echo "==> Launching…"
open /Applications/PeakBar.app

echo "==> Installed and launched: /Applications/PeakBar.app"
