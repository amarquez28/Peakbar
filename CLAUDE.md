# PeakBar — macOS Menu Bar System Monitor

## Project Overview

A native macOS menu bar application built in Swift that displays real-time system stats
(CPU usage, GPU usage, RAM usage, CPU temp, GPU temp) directly in the menu bar. Stats are
configurable via a dropdown panel. Targets Apple Silicon Macs (M-series). Intended for
public release as a signed/notarized `.dmg` on GitHub.

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Language | Swift 5.9+ | Native, performant, best macOS API access |
| UI Framework | SwiftUI + AppKit | SwiftUI for the dropdown panel; AppKit (`NSStatusItem`) for menu bar integration |
| Data Collection | `IOKit`, `sysctl`, `host_statistics64` | Apple-approved APIs, no private frameworks |
| GPU / Thermal | `IOKit` + `SMCKit` (or direct SMC reads) | Only reliable public path for Apple Silicon thermals |
| Project Structure | Xcode project (`.xcodeproj`) | Required for code signing, entitlements, and DMG packaging |
| Minimum Target | macOS 13.0 (Ventura) | SwiftUI stability + Apple Silicon maturity |
| Distribution | Signed + Notarized `.dmg` via GitHub Releases | Clean install UX for end users |

---

## Project Structure

```
PeakBar/
├── PeakBar.xcodeproj/
├── PeakBar/
│   ├── App/
│   │   ├── PeakBarApp.swift          # @main entry, NSApplicationDelegate setup
│   │   └── AppDelegate.swift         # NSStatusItem creation, lifecycle
│   ├── MenuBar/
│   │   ├── StatusBarController.swift # Owns NSStatusItem, drives the renderer
│   │   ├── MenuBarFormatter.swift    # Formats stat values into menu bar strings
│   │   ├── MenuBarRenderer.swift     # Draws the two styles; reports their widths
│   │   └── MenuBarLayout.swift       # Width budget + fitting (see Menu Bar Width)
│   ├── Dropdown/
│   │   ├── DropdownView.swift        # SwiftUI root view for the popover
│   │   ├── StatToggleGrid.swift      # Grid of toggleable stat blocks
│   │   └── StatToggleBlock.swift     # Individual stat block with checkbox UI
│   ├── Stats/
│   │   ├── StatsManager.swift        # Orchestrates all collectors, publishes via Combine
│   │   ├── CPUMonitor.swift          # CPU usage % via host_statistics64
│   │   ├── GPUMonitor.swift          # GPU usage % via IOKit (AGXAccelerator)
│   │   ├── RAMMonitor.swift          # RAM usage via host_statistics64
│   │   ├── ThermalMonitor.swift      # CPU + GPU temps via SMC / IOKit
│   │   └── FanMonitor.swift          # Fan RPM via SMC (F<n>Ac), read-only
│   ├── Settings/
│   │   └── SettingsStore.swift       # @AppStorage-backed user preferences
│   └── Utilities/
│       ├── LaunchAtLogin.swift        # SMAppService (macOS 13+) login item helper
│       └── Extensions.swift           # Convenience extensions
├── PeakBarTests/
│   └── StatsTests.swift
├── scripts/
│   ├── build-dmg.sh                  # Creates signed + notarized DMG for release
│   └── notarize.sh                   # Wraps xcrun notarytool submit
├── .github/
│   └── workflows/
│       └── release.yml               # GitHub Actions: build → sign → notarize → upload DMG
└── CLAUDE.md
```

---

## Core Features

### Menu Bar Display
- Default visible stats: **CPU %** and **GPU %**
- Format: `CPU 10% GPU 4%` — space-separated, continuing horizontally as more stats are enabled
- Full format with all stats: `CPU 10% GPU 4% RAM 7.2GB CPU 48°C GPU 51°C`
- Refreshes every **5 seconds** via a `Timer` publisher
- Text is set directly on `NSStatusItem.button.title` (monospaced preferred via attributed string)

### Dropdown Panel (NSPopover)
- Opens on click of the status item
- Contains a grid of **stat toggle blocks**, one per available stat:
  - CPU Usage %
  - GPU Usage %
  - RAM Usage
  - CPU Temp
  - GPU Temp
  - Fan Speed (RPM)
  - Power Draw (W)
- Each block shows:
  - Stat name
  - Current live value
  - Visual selected state: **checkbox in the top-right corner** of the block (checked = visible in menu bar)
- Selected blocks get a distinct **accent-colored border** in addition to the checkmark
- Below the grid:
  - **Menu bar style** picker — Labels / Icons (see [Menu Bar Styles](#menu-bar-styles))
  - **Fit to menu bar space** toggle (default on — see [Menu Bar Width](#menu-bar-width))
  - **Launch at Login** toggle (uses `SMAppService`)
  - **Quit PeakBar** button

### Settings Persistence
All user preferences stored via `@AppStorage` (UserDefaults):

```swift
// SettingsStore.swift
@AppStorage("visibleStats") var visibleStats: [StatType] // defaults: [.cpu, .gpu]
@AppStorage("launchAtLogin") var launchAtLogin: Bool = false
```

---

## Data Collection — Apple Silicon Notes

### CPU Usage
Use `host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, ...)` to get user/system/idle
ticks. Diff consecutive samples to compute usage %.

```swift
// Pseudocode
let (user, sys, idle, nice) = getCPUTicks()
let total = user + sys + idle + nice
let used = user + sys + nice
cpuUsage = Double(used - prevUsed) / Double(total - prevTotal) * 100
```

### GPU Usage
Query `IOKit` for the `AGXAccelerator` service. On Apple Silicon, the key
`"Device Utilization %"` or `"GPU Activity(%)` is available under the IORegistry
`IOAccelerator` class.

```swift
let matching = IOServiceMatching("IOAccelerator")
// iterate services, read "Device Utilization %" property
```

> ⚠️ Apple Silicon GPU IOKit keys can vary between chip generations. Test on the
> target machine. Fall back to `0%` with a console warning if the key is absent.

### RAM Usage
`host_statistics64` with `HOST_VM_INFO64_COUNT`. Calculate:
`used = total - free - inactive` (or adjust based on desired definition).

### Temperatures (SMC)
Apple Silicon exposes thermal sensors via the **System Management Controller (SMC)**.
PeakBar opens the `AppleSMC` IOKit user client directly in a self-contained reader
(`Utilities/SMC/SMC.swift`) — no package dependency.

**SMC keys are discovered dynamically, not hardcoded.** Because sensor keys differ
between M1/M2/M3/M4 variants, `ThermalMonitor` enumerates *all* SMC keys at startup
(via the `#KEY` count + `kSMCGetKeyFromIndex` selector) and averages every key that
matches a prefix and decodes to a plausible 0–130 °C reading:

| Sensor | Key prefix | Notes |
|---|---|---|
| CPU die temp | `Tp*` | Performance-core sensors, averaged |
| GPU die temp | `Tg*` | GPU sensors, averaged |

This adapts to any Apple Silicon chip with zero per-chip configuration. If no key in
a group reads back in range, the temperature is reported as `nil` → displayed `--°C`.

Sensor value formats handled:
- `flt` — little-endian `Float32` (used by Apple Silicon).
- `sp78` — signed 7.8 fixed point, big-endian (older Macs).

> ⚠️ **Critical implementation gotcha:** the SMC request/response is a fixed **80-byte**
> C struct (`SMCKeyData_t`). Do **not** model it as a Swift `struct` — Swift reorders
> and repacks fields, producing a 76-byte layout that makes every
> `IOConnectCallStructMethod` fail with `kIOReturnBadArgument` (and all temps show
> `--`). `SMC.swift` builds a raw `[UInt8]` 80-byte buffer and reads/writes fields at
> explicit byte offsets instead.

> Verified on M3 Pro: 2294 total keys, ~80 `Tp*` + 18 `Tg*` sensors (all `flt`),
> idle averaging ≈ CPU 52 °C / GPU 38 °C.

### Fan Speed (SMC)
Read-only fan **monitoring** via the same SMC reader. `FanMonitor` probes `F<n>Ac`
(actual RPM, `flt`) for fan indices 0–7 and averages whatever responds. A reading
of 0 is kept and displayed as `Off` (Apple Silicon spins fans fully down when cool);
no `F*Ac` key at all → `nil` → `--` (fanless Macs like the MacBook Air).

> Verified on M3 Pro: `FNum = 2` fans; `F0Mn/F1Mn` ≈ 2317 RPM min, `F0Mx/F1Mx` ≈
> 6800 RPM max; idle `F0Ac/F1Ac` = 0 (fans off).

### Power Draw (SMC)
`PowerMonitor` reads total system power in watts from `PSTR` ("System Total
Power", `flt`), falling back to `PDTR` ("DC In" — reads higher while the battery
is charging). Missing keys or implausible values (≤0 or ≥1000 W) → `nil` → `--`.
Menu bar format: `PWR 32.7W` (normal), bolt SF Symbol + `33W` (compact).

> Verified on M3 Pro: `PSTR` ≈ 33 W light load; `PDTR` ≈ 67 W while charging.

### Battery (IOKit `AppleSmartBattery`)
`BatteryMonitor` reads the `AppleSmartBattery` registry entry (no SMC). Two menu
bar stats plus a dropdown info line:
- **Battery Power** — `Voltage` × `Amperage` (signed): `BAT +51.5W` charging,
  `BAT −12.4W` discharging (U+2212 minus, matches `+`).
- **Battery Time** — `AvgTimeToFull` while charging, `AvgTimeToEmpty` on battery
  (`65535` = n/a). Plugged in but not charging → `nil` → `--`.
- **Health / cycles** (dropdown only) — `BatteryData.NominalChargeCapacity` ÷
  `DesignCapacity` (matches System Settings' "Maximum Capacity"), `CycleCount` of
  `DesignCycleCount9C`.

- **Battery Temp** — not in the registry on current macOS, so it comes from
  the SMC instead: `ThermalMonitor` averages the `TB<n>T` keys (`flt`), the
  same way it averages `Tp*`/`Tg*`. Drawn with `heat.waves` because every
  thermometer variant is indistinguishable from CPU Temp's at menu bar size.

No service / no `TB*T` keys (desktop Macs) → everything `nil`.

> Verified on M3 Pro: +51 W charging on a 68 W adapter, −14.5 W on battery,
> 86 % health, 530/1000 cycles; `TB0T`–`TB2T` ≈ 29 °C idle.

> ⚠️ **Fan control is intentionally NOT implemented.** Writing fan keys
> (`F<n>Md` mode / `F<n>Tg` target) requires a root-privileged helper daemon,
> expands the security/notarization surface, is restricted by Apple on Apple
> Silicon, and a bug could defeat thermal protection. PeakBar stays read-only.

---

## Menu Bar Styles

`MenuBarStyle` (in `MenuBarRenderer.swift`) has two cases. Widths below are for
all ten stats, measured by `scripts/preview-menubar.sh`:

| Style | Looks like | 10 stats | Drawn as |
|---|---|---|---|
| `.labels` | `CPU 10% GPU 4%` | 716pt | attributed title |
| `.icons` | `[cpu]10% [gpu]4%` | 539pt | attributed title, symbols as `NSTextAttachment` |

Values are drawn at their natural width, one space apart in both styles
(`FAN Off PWR 32.7W`); in `.icons` the symbol-to-value gap is a thin space
(U+2009). Stats to the right shift a few points when a number gains a digit —
an accepted trade-off. Earlier versions padded every value to a fixed field
with figure spaces, which stopped the shifting but left wide, uneven gaps
(`FAN Off` reserved room for `9999rpm`).

The style picker is `.segmented`, which on macOS writes its binding during
SwiftUI's view update (Apple-confirmed bridging bug,
https://developer.apple.com/forums/thread/823629) and logs "Publishing changes
from within view updates" on every switch. `DropdownView.deferredStyleBinding`
applies the write on the next main-queue pass instead.

> A third `.stacked` style (symbol above value, drawn as a template `NSImage`)
> existed until 1.1.1. It was removed: at the ~9pt the menu bar's height allows
> for two rows, the glyphs clipped and looked wrong. A saved `"stacked"`
> preference migrates to `.icons`.

Run `scripts/preview-menubar.sh` after touching the renderer — it compiles
`MenuBarRenderer` + `MenuBarFormatter` standalone (no app, no asset catalog) and
writes a 3x strip of every style to `build/menubar-preview.png`. Far easier to
judge 1pt spacing changes there than in the real menu bar.

---

## Menu Bar Width

macOS does not truncate or scroll the menu bar. When the status items stop fitting
it drops entire items — and it drops *whoever* it likes, including third-party
managers such as Hidden Bar, Bartender, or Ice, whose own icon vanishing takes
every item they were hiding with it. Nothing brings a dropped item back except the
owning app re-adding it (hence "restart PeakBar to get the icon back").

Two properties keep PeakBar out of that failure mode:

1. **The item only ever grows while running.** `StatusBarController` sizes
   `statusItem.length` snugly around the current readings (+ 5pt
   `buttonPadding`, the ~4.5pt `NSStatusBarButtonCell` needs), grows it when a
   reading needs more room, and never shrinks it until the selection, style or
   attached displays change. That's a handful of resizes per session — mostly
   in the first minute as readings settle — rather than one per refresh.
   Sizing for the worst case up front was tried and left visible empty space
   at both edges. Growth is capped at `MenuBarRenderer.width`, the worst case
   computed from `MenuBarFormatter.widestSnapshot` (100 %, 9999 rpm, −999 W, …),
   which is also what the budget fitting below uses — so growing can never take
   the item past the budget. `testRenderedWidthNeverExceedsPinnedWidth`
   enforces that no reading exceeds that worst case; update `widestSnapshot`
   along with any format change.
2. **The item stays inside a width budget.** `MenuBarLayout.widthBudget()` takes
   45 % of the menu-extra region of the *narrowest* attached screen — on notched
   Macs that's `NSScreen.auxiliaryTopRightArea` (the strip right of the notch);
   otherwise ~66 % of the screen width, leaving room for the app's own menus.
   Using the narrowest screen means the width also doesn't have to change as the
   menu bar moves between displays. `MenuBarLayout.fit` degrades in the order that
   costs the user least: switch labels → icons first (which still shows every
   stat), and only then drop stats from the right. The dropdown explains what it did; the **Fit to menu bar space**
   toggle (default on) disables the whole thing.

On a display change (`didChangeScreenParametersNotification` — plugging in a
monitor, starting/stopping Sidecar) the controller re-fits and then cycles
`statusItem.isVisible`, which makes macOS re-place an item it had dropped. That's
why `autosaveName` is set: it preserves the item's position across that cycle and
across relaunches. Because `isVisible` is persisted under the autosave name, init
force-sets it to `true` so a crash mid-cycle can't leave the app with no UI.

> Measured on a 14" M3 Pro (1800pt scaled, notched): extras region 790pt →
> 355pt budget. Default two stats = 128pt labels / 107pt icons. All ten stats =
> 716pt labels / 539pt icons, so on this Mac the fitter drops trailing stats
> once roughly six are enabled.

---

## UI Design — Stat Toggle Block

```
┌─────────────────┐
│              [✓]│   ← NSButton / SwiftUI Toggle styled as checkbox, top-right
│   CPU Usage     │
│     10%         │
└─────────────────┘
  ↑ accent border when selected
```

- Unselected: standard `.background` fill, no border (or subtle gray border)
- Selected: `Color.accentColor` border (2pt), checkmark filled
- Blocks laid out in a 2-column `LazyVGrid`
- Clicking anywhere on the block toggles its state

---

## Refresh Architecture

```
Timer (5s)
  └─> StatsManager.refresh()
        ├─> CPUMonitor.sample()     → @Published cpuUsage: Double
        ├─> GPUMonitor.sample()     → @Published gpuUsage: Double
        ├─> RAMMonitor.sample()     → @Published ramUsage: Double (GB)
        ├─> ThermalMonitor.sample() → @Published cpuTemp: Double, gpuTemp: Double
        ├─> FanMonitor.sample()     → @Published fanSpeed: Double? (RPM)
        └─> StatusBarController.update(stats)
              └─> MenuBarFormatter.format(visibleStats, stats)
                    └─> NSStatusItem.button.title = "CPU 10% GPU 4%"
```

`StatsManager` is an `ObservableObject`. `DropdownView` subscribes to it so the live
values in the toggle blocks also update every 5 seconds while the panel is open.

---

## Code Signing & Distribution

### Requirements
- Apple Developer account (for signing + notarization)
- Hardened Runtime enabled
- Entitlements: none special required for IOKit/sysctl reads from a sandboxed app
  - **Disable App Sandbox** — SMC and IOKit GPU access require it. Document this
    clearly in the README for security-conscious users.

### Build for Release
```bash
# In scripts/build-dmg.sh
xcodebuild archive \
  -scheme PeakBar \
  -archivePath build/PeakBar.xcarchive \
  -configuration Release

xcodebuild -exportArchive \
  -archivePath build/PeakBar.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist   # method: developer-id

# Create DMG
create-dmg \
  --volname "PeakBar" \
  --window-size 540 380 \
  --icon-size 128 \
  --app-drop-link 380 180 \
  "build/PeakBar.dmg" \
  "build/export/PeakBar.app"
```

### Notarization
```bash
xcrun notarytool submit build/PeakBar.dmg \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

xcrun stapler staple build/PeakBar.dmg
```

### GitHub Actions (`release.yml`)
Trigger: push of a `v*` tag (e.g. `v1.0.0`)
Steps:
1. Checkout + setup Xcode
2. Import signing certificate from GitHub Secrets
3. `xcodebuild archive` + `exportArchive`
4. Create DMG via `create-dmg`
5. Notarize + staple
6. Upload DMG as GitHub Release asset

Required secrets: `SIGNING_CERTIFICATE_P12`, `CERTIFICATE_PASSWORD`, `APPLE_ID`,
`APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`

---

## Dependencies

Keep dependencies minimal. Vendor what you need rather than adding Swift packages
where possible (keeps the build simple for contributors).

| Dep | Usage | How |
|---|---|---|
| None (stdlib + IOKit + AppKit) | Core stats | Built-in |
| `create-dmg` | DMG packaging in CI | Homebrew in GH Actions runner |

If an SMC Swift library is needed, copy only the relevant files from the
[`beltex/SystemKit`](https://github.com/beltex/SystemKit) or
[`exelban/stats`](https://github.com/exelban/stats) SMC layer directly into
`Utilities/SMC/` with attribution, rather than taking a full package dependency.

---

## Known Constraints & Gotchas

1. **No App Sandbox** — Required for SMC + IOKit GPU access. Must be explicitly
   disabled in entitlements. Note in README.
2. **SMC key variance** — Temp sensor keys differ per chip. Probe a list; never
   hardcode a single key.
3. **GPU IOKit keys** — `AGXAccelerator` property names have changed across macOS
   versions. Add a version check guard and test on Ventura, Sonoma, and Sequoia.
4. **Menu bar space** — macOS never truncates the menu bar; when items don't fit it
   silently *removes whole status items*, ours or a neighbour's, and does not put
   them back. Handled by a grow-only item width + a width budget — see
   [Menu Bar Width](#menu-bar-width) below. Do not go back to a status item whose
   width changes on every refresh.
5. **`SMAppService` for login items** — Available macOS 13+. No fallback needed
   given the macOS 13 minimum target.
6. **Notarization is mandatory** — Unsigned/unnotarized apps will be blocked by
   Gatekeeper on other users' machines. Do not skip this for public releases.

---

## Out of Scope (v1)

- Network usage (can be added as a `StatType` case in v2)
- Intel Mac support
- Preferences window (all config lives in the dropdown panel)
- Sparkle auto-update (users re-download DMG from GitHub Releases)
- iOS / iPadOS companion

---

## Suggested Build Order

1. `AppDelegate` + bare `NSStatusItem` showing static text — confirm menu bar presence
2. `CPUMonitor` + wire to status item title — confirm live CPU %
3. `GPUMonitor` — confirm GPU % on your machine, nail down the IOKit key
4. `RAMMonitor`
5. `ThermalMonitor` — probe SMC keys, handle graceful fallback
6. `StatsManager` — unify all monitors under one timer + Combine pipeline
7. `MenuBarFormatter` + `SettingsStore` — configurable visible stats
8. `DropdownView` + `StatToggleGrid` + `StatToggleBlock` — full UI
9. Launch at Login + Quit button
10. Code signing, DMG script, GitHub Actions release workflow
