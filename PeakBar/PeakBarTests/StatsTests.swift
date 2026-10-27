//
//  StatsTests.swift
//  PeakBarTests
//
//  Unit tests for the pure formatting / selection logic (no hardware access).
//

import XCTest
@testable import PeakBar

final class StatsTests: XCTestCase {

    func testMenuBarFormatDefaultStats() {
        var snap = StatsSnapshot()
        snap.cpuUsage = 10.4
        snap.gpuUsage = 3.6
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.cpu, .gpu], stats: snap), "CPU 10% GPU 4%")
    }

    func testMenuBarFormatAllStats() {
        var snap = StatsSnapshot()
        snap.cpuUsage = 10
        snap.gpuUsage = 4
        snap.ramUsage = 7.23
        snap.cpuTemp = 48.2
        snap.gpuTemp = 51.0
        let text = MenuBarFormatter.format(
            visibleStats: [.cpu, .gpu, .ram, .cpuTemp, .gpuTemp],
            stats: snap
        )
        XCTAssertEqual(text, "CPU 10% GPU 4% RAM 7.2GB CPU 48°C GPU 51°C")
    }

    /// Stats are exactly one space apart — no reserved slots, so a short value
    /// like "Off" doesn't leave a hole before the next stat.
    func testStatsAreEvenlySpaced() {
        var snap = StatsSnapshot()
        snap.fanSpeed = 0
        snap.batteryTemp = 32
        XCTAssertEqual(
            MenuBarFormatter.format(visibleStats: [.fan, .batteryTemp], stats: snap),
            "FAN Off BAT 32°C"
        )
    }

    func testMenuBarFormatMissingTemperatureFallsBack() {
        var snap = StatsSnapshot()
        snap.cpuTemp = nil
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.cpuTemp], stats: snap), "CPU --°C")
    }

    func testMenuBarFanSpeedFormatting() {
        var snap = StatsSnapshot()
        snap.fanSpeed = 2317.6
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.fan], stats: snap), "FAN 2318rpm")
        snap.fanSpeed = 0           // Apple Silicon spins fans down when cool
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.fan], stats: snap), "FAN Off")
        snap.fanSpeed = nil         // fanless Mac
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.fan], stats: snap), "FAN --")
    }

    func testMenuBarPowerFormatting() {
        var snap = StatsSnapshot()
        snap.powerWatts = 32.68
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.power], stats: snap), "PWR 32.7W")
        snap.powerWatts = nil       // SMC key unavailable
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.power], stats: snap), "PWR --W")
    }

    func testMenuBarBatteryFormatting() {
        let minus = "\u{2212}"
        var snap = StatsSnapshot()
        snap.batteryWatts = 51.46       // charging
        snap.batteryMinutes = 55
        XCTAssertEqual(
            MenuBarFormatter.format(visibleStats: [.battery, .batteryTime], stats: snap),
            "BAT +51.5W BAT 0:55"
        )
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .battery, stats: snap), "+51W")

        snap.batteryWatts = -8.04       // discharging
        snap.batteryMinutes = 754
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .battery, stats: snap, longUnits: true), "\(minus)8.0W")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .batteryTime, stats: snap), "12:34")

        snap.batteryWatts = 0.01        // plugged in, holding
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .battery, stats: snap), "0W")

        snap.batteryWatts = nil         // desktop Mac
        snap.batteryMinutes = nil
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .battery, stats: snap), "--W")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .batteryTime, stats: snap), "--")

        snap.batteryTemp = 29.2
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.batteryTemp], stats: snap), "BAT 29°C")
        snap.batteryTemp = nil
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .batteryTemp, stats: snap), "--°")
    }

    func testEmptySelectionShowsAppName() {
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [], stats: StatsSnapshot()), "PeakBar")
    }

    func testCompactValues() {
        var snap = StatsSnapshot()
        snap.cpuUsage = 10.4
        snap.ramUsage = 7.23
        snap.cpuTemp = nil
        snap.fanSpeed = 0
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .cpu, stats: snap), "10%")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .ram, stats: snap), "7.2G")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .cpuTemp, stats: snap), "--°")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .fan, stats: snap), "off")
        snap.fanSpeed = 2317.6
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .fan, stats: snap), "2318")
        snap.powerWatts = 32.68
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .power, stats: snap), "33W")
    }

    // MARK: - Menu bar fitting

    /// Stand-in for measurement, per stat: 20pt labels, 12pt icons.
    private func measure(_ stats: [StatType], _ style: MenuBarStyle) -> CGFloat {
        CGFloat(stats.count) * (style == .labels ? 20 : 12)
    }

    func testFitKeepsEverythingWhenItFits() {
        let plan = MenuBarLayout.fit(
            stats: [.cpu, .gpu], style: .labels, budget: 200, measure: measure
        )
        XCTAssertEqual(plan.stats, [.cpu, .gpu])
        XCTAssertEqual(plan.style, .labels)
        XCTAssertTrue(plan.dropped.isEmpty)
        XCTAssertNil(plan.forcedStyle)
    }

    func testFitSwitchesToIconsBeforeDroppingStats() {
        // 4 stats: 80pt labels, 48pt icons.
        let plan = MenuBarLayout.fit(
            stats: [.cpu, .gpu, .ram, .power], style: .labels, budget: 60, measure: measure
        )
        XCTAssertEqual(plan.stats, [.cpu, .gpu, .ram, .power])
        XCTAssertEqual(plan.style, .icons)
        XCTAssertEqual(plan.forcedStyle, .icons)
        XCTAssertTrue(plan.dropped.isEmpty)
    }

    func testFitDropsTrailingStatsWhenIconsIsNotEnough() {
        let plan = MenuBarLayout.fit(
            stats: [.cpu, .gpu, .ram, .power], style: .icons, budget: 25, measure: measure
        )
        XCTAssertEqual(plan.stats, [.cpu, .gpu])
        XCTAssertEqual(plan.dropped, [.ram, .power])
        XCTAssertNil(plan.forcedStyle) // the user had already chosen icons
    }

    func testFitAlwaysKeepsAtLeastOneStat() {
        let plan = MenuBarLayout.fit(
            stats: [.cpu, .gpu], style: .icons, budget: 1, measure: measure
        )
        XCTAssertEqual(plan.stats, [.cpu])
        XCTAssertEqual(plan.dropped, [.gpu])
    }

    func testFitWithNoStatsIsANoOp() {
        let plan = MenuBarLayout.fit(stats: [], style: .labels, budget: 100, measure: measure)
        XCTAssertTrue(plan.stats.isEmpty)
        XCTAssertTrue(plan.dropped.isEmpty)
    }

    // MARK: - Rendering

    @MainActor
    func testIconsIsNarrowerThanLabels() {
        let renderer = MenuBarRenderer(barHeight: 24)
        let all = StatType.allCases
        XCTAssertLessThan(renderer.width(stats: all, style: .icons), renderer.width(stats: all, style: .labels))
    }

    /// The status item's length is pinned to `renderer.width` (computed from
    /// `widestSnapshot`) and never changes on a refresh, so no live reading may
    /// render wider than that — it would be clipped. Narrower is fine: the
    /// button centres the text inside the fixed-length item.
    @MainActor
    func testRenderedWidthNeverExceedsPinnedWidth() {
        let renderer = MenuBarRenderer(barHeight: 24)
        let all = StatType.allCases

        var low = StatsSnapshot()
        low.cpuUsage = 3; low.gpuUsage = 0; low.ramUsage = 7.2
        low.cpuTemp = 48; low.gpuTemp = 9; low.fanSpeed = 0; low.powerWatts = 8.1
        low.batteryWatts = 0; low.batteryMinutes = 5; low.batteryTemp = 8

        var high = StatsSnapshot()
        high.cpuUsage = 100; high.gpuUsage = 100; high.ramUsage = MenuBarFormatter.widestSnapshot.ramUsage
        high.cpuTemp = 100; high.gpuTemp = 100; high.fanSpeed = 6800; high.powerWatts = 132.4
        high.batteryWatts = -104.6; high.batteryMinutes = 754; high.batteryTemp = 100

        var charging = high
        charging.batteryWatts = 999          // "+" instead of "−"

        let missing = StatsSnapshot()        // every optional reading "--"

        for style in MenuBarStyle.allCases {
            let pinned = renderer.width(stats: all, style: style)
            for snap in [low, high, charging, missing] {
                let width = renderer.attributedTitle(stats: all, snapshot: snap, style: style).size().width
                XCTAssertLessThanOrEqual(width, pinned + 0.5, "\(style) overflows its pinned width")
            }
        }
    }

    @MainActor
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("v1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.1"))
        // Numeric (not lexical) comparison: 1.10 > 1.9
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))
    }
}
