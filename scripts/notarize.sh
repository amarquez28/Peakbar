#!/usr/bin/env bash
#
# notarize.sh — Submit build/PeakBar.dmg to Apple's notary service and staple
# the resulting ticket so the DMG passes Gatekeeper on other Macs.
#
# Required environment:
#   APPLE_ID         Apple ID email used for notarization.
#   APPLE_TEAM_ID    10-character Apple Developer Team ID.
#   APPLE_APP_PASSWORD  App-specific password for that Apple ID
#                       (create one at https://appleid.apple.com).
#
# Optional environment:
#   DMG_PATH         Path to the DMG. Default: build/PeakBar.dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DMG_PATH="${DMG_PATH:-${REPO_ROOT}/build/PeakBar.dmg}"

for var in APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: ${var} is not set." >&2
    exit 1
  fi
done

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "error: DMG not found at ${DMG_PATH}. Run build-dmg.sh first." >&2
  exit 1
fi

echo "==> Submitting ${DMG_PATH} to the notary service (this can take a few minutes)"
xcrun notarytool submit "${DMG_PATH}" \
  --apple-id "${APPLE_ID}" \
  --team-id "${APPLE_TEAM_ID}" \
  --password "${APPLE_APP_PASSWORD}" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "${DMG_PATH}"

echo "==> Validating"
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}" || true

echo "==> Notarized: ${DMG_PATH}"
