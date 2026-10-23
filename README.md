# PeakBar

A lightweight native macOS **menu bar system monitor**. PeakBar shows real-time
CPU, GPU, RAM, temperatures, and fan speed right in your menu bar, and lets you
choose which stats to display from a simple dropdown.

```
CPU 10%  GPU 4%  RAM 7.2GB  CPU 48°C  GPU 51°C  FAN 2317rpm
```

- **Live stats** every 5 seconds: CPU %, GPU %, RAM (GB), CPU/GPU temperature, fan RPM
- **Configurable** — toggle any stat on/off from the dropdown grid
- **Three menu bar styles** — word labels, icons, or **stacked** (icon above the
  value), which fits all seven stats in less than half the width
- **Fits your menu bar** — sizes itself to the space available so macOS doesn't
  hide menu bar icons, yours or another app's
- **Tiny & native** — Swift + SwiftUI/AppKit, no background daemons, ~160 KB
- **Launch at Login** toggle
- Runs on **macOS 13 (Ventura)+**, Apple Silicon and Intel

---

## Install

PeakBar is free and **not notarized by Apple** (notarization requires a paid
Apple Developer account). Because of that, macOS Gatekeeper blocks it the first
time you open it. This is expected for free, open-source apps — here's the
one-time unblock.

1. Download **`PeakBar.dmg`** from the [latest release](../../releases/latest),
   open it, and drag **PeakBar** into **Applications**.
2. Open PeakBar once — macOS will refuse and warn you. That's fine, continue:
3. Go to **System Settings → Privacy & Security**, scroll to the bottom, and
   click **Open Anyway** next to the PeakBar message, then confirm.

PeakBar will now open normally every time.

### Prefer the terminal?

After dragging PeakBar to Applications, run this once, then open it normally:

```sh
xattr -dr com.apple.quarantine /Applications/PeakBar.app
```

This removes the download "quarantine" flag so Gatekeeper stops complaining.

---

## Why does macOS warn me?

Apple's Gatekeeper only trusts apps that are **notarized**, and notarization
requires a paid ($99/year) Apple Developer Program membership. PeakBar is a free
hobby project, so it's distributed **ad-hoc signed but un-notarized**. The app is
open source — you can read every line in this repo, or build it yourself (below).

PeakBar also runs **without the App Sandbox**. This is required to read the
low-level system sensors it reports:

- **SMC** (System Management Controller) for CPU/GPU temperatures and fan RPM
- **IOKit** for GPU utilization

PeakBar only ever **reads** these sensors. It never writes to the SMC (no fan
control) and makes no network connections.

---

## Build from source

Requires Xcode 16 or later.

```sh
git clone <this-repo-url>
cd PeakBar
open PeakBar/PeakBar.xcodeproj   # then press ⌘R in Xcode
```

Or build a DMG from the command line (free, ad-hoc signed):

```sh
brew install create-dmg
./scripts/build-dmg.sh adhoc     # -> build/PeakBar.dmg
```

Running the unit tests:

```sh
xcodebuild -scheme PeakBar -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
```

---

## Maintainer: cutting a release

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which builds the
ad-hoc DMG and publishes a GitHub Release with install instructions — no secrets
required.

```sh
git tag v1.0.0
git push origin v1.0.0
```

### Upgrading to a notarized (warning-free) release later

If you join the paid Apple Developer Program, PeakBar can ship notarized so users
get a clean double-click install with no Gatekeeper warning:

```sh
export APPLE_TEAM_ID=XXXXXXXXXX
./scripts/build-dmg.sh developer-id        # needs a Developer ID Application cert
APPLE_ID=you@example.com APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
  ./scripts/notarize.sh
```

See the comments in `scripts/build-dmg.sh`, `scripts/notarize.sh`, and
`.github/workflows/release.yml` for the required certificate and secrets.

---

## License

MIT (or your preferred license — add a `LICENSE` file).
