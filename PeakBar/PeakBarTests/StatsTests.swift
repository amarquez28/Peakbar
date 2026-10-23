//
//  StatsTests.swift
//  PeakBarTests
//
//  Unit tests for the pure formatting / selection logic (no hardware access).
//

import XCTest
@testable import PeakBar

final class StatsTests: XCTestCase {

    /// U+2007 FIGURE SPACE — the digit-width pad the formatter uses so values
    /// keep a constant width as their magnitude changes.
    private let fs = "\u{2007}"

    /// The RAM field is sized to this machine's installed memory, so the
    /// expected padding has to be derived rather than hardcoded.
    private func ram(_ value: String) -> String {
        let deficit = MenuBarFormatter.ramIntegerDigits + 2 - value.count
        return String(repeating: fs, count: max(deficit, 0)) + value
    }

    func testMenuBarFormatDefaultStats() {
        var snap = StatsSnapshot()
        snap.cpuUsage = 10.4
        snap.gpuUsage = 3.6
        let text = MenuBarFormatter.format(visibleStats: [.cpu, .gpu], stats: snap)
        XCTAssertEqual(text, "CPU \(fs)10% GPU \(fs)\(fs)4%")
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
        XCTAssertEqual(
            text,
            "CPU \(fs)10% GPU \(fs)\(fs)4% RAM \(ram("7.2"))GB CPU \(fs)48°C GPU \(fs)51°C"
        )
    }

    /// The whole point of the padding: the string can't change width as values
    /// grow, so the status item never resizes and never forces the menu bar to
    /// re-lay out (which is what makes icons disappear).
    func testFormattedWidthIsStableAcrossMagnitudes() {
        let stats: [StatType] = [.cpu, .gpu, .ram, .cpuTemp, .gpuTemp, .fan, .power]

        var low = StatsSnapshot()
        low.cpuUsage = 3; low.gpuUsage = 0; low.ramUsage = 7.2
        low.cpuTemp = 48; low.gpuTemp = 9; low.fanSpeed = 0; low.powerWatts = 8.1

        var high = StatsSnapshot()
        high.cpuUsage = 100; high.gpuUsage = 100; high.ramUsage = 7.2
        high.cpuTemp = 100; high.gpuTemp = 100; high.fanSpeed = 6800; high.powerWatts = 132.4

        XCTAssertEqual(
            MenuBarFormatter.format(visibleStats: stats, stats: low).count,
            MenuBarFormatter.format(visibleStats: stats, stats: high).count
        )
        for stat in stats {
            XCTAssertEqual(
                MenuBarFormatter.compactValue(for: stat, stats: low).count,
                MenuBarFormatter.compactValue(for: stat, stats: high).count,
                "compact width changed for \(stat)"
            )
        }
    }

    func testMenuBarFormatMissingTemperatureFallsBack() {
        var snap = StatsSnapshot()
        snap.cpuTemp = nil
        let text = MenuBarFormatter.format(visibleStats: [.cpuTemp], stats: snap)
        XCTAssertEqual(text, "CPU \(fs)--°C")
    }

    func testMenuBarFanSpeedFormatting() {
        var snap = StatsSnapshot()
        snap.fanSpeed = 2317.6
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.fan], stats: snap), "FAN 2318rpm")

        // "Off"/"--" have no "rpm" suffix, so they pad out to the same width as
        // a four-digit reading plus the unit.
        snap.fanSpeed = 0           // Apple Silicon spins fans down when cool
        XCTAssertEqual(
            MenuBarFormatter.format(visibleStats: [.fan], stats: snap),
            "FAN " + String(repeating: fs, count: 4) + "Off"
        )

        snap.fanSpeed = nil         // fanless Mac
        XCTAssertEqual(
            MenuBarFormatter.format(visibleStats: [.fan], stats: snap),
            "FAN " + String(repeating: fs, count: 5) + "--"
        )
    }

    func testMenuBarPowerFormatting() {
        var snap = StatsSnapshot()
        snap.powerWatts = 32.68
        XCTAssertEqual(MenuBarFormatter.format(visibleStats: [.power], stats: snap), "PWR \(fs)32.7W")

        snap.powerWatts = nil       // SMC key unavailable
        XCTAssertEqual(
            MenuBarFormatter.format(visibleStats: [.power], stats: snap),
            "PWR \(fs)\(fs)\(fs)--W"
        )
    }

    func testEmptySelectionShowsAppName() {
        let text = MenuBarFormatter.format(visibleStats: [], stats: StatsSnapshot())
        XCTAssertEqual(text, "PeakBar")
    }

    func testCompactValues() {
        var snap = StatsSnapshot()
        snap.cpuUsage = 10.4
        snap.ramUsage = 7.23
        snap.cpuTemp = nil
        snap.fanSpeed = 0
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .cpu, stats: snap), "\(fs)10%")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .ram, stats: snap), "\(ram("7.2"))G")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .cpuTemp, stats: snap), "\(fs)--°")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .fan, stats: snap), "\(fs)off")

        snap.fanSpeed = 2317.6
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .fan, stats: snap), "2318")

        snap.powerWatts = 32.68
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .power, stats: snap), "\(fs)33W")
        snap.powerWatts = nil
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .power, stats: snap), "\(fs)--W")
    }

    // MARK: - Menu bar fitting

    /// Stand-in for measurement, per stat: 20pt labels, 12pt icons, 6pt stacked.
    private func measure(_ stats: [StatType], _ style: MenuBarStyle) -> CGFloat {
        let perStat: CGFloat
        switch style {
        case .labels: perStat = 20
        case .icons: perStat = 12
        case .stacked: perStat = 6
        }
        return CGFloat(stats.count) * perStat
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

    func testFitStepsDownOneStyleWhenThatIsEnough() {
        // 4 stats: 80pt labels, 48pt icons — icons alone gets it under budget,
        // so it shouldn't go all the way to stacked.
        let plan = MenuBarLayout.fit(
            stats: [.cpu, .gpu, .ram, .power], style: .labels, budget: 60, measure: measure
        )
        XCTAssertEqual(plan.stats, [.cpu, .gpu, .ram, .power])
        XCTAssertEqual(plan.style, .icons)
        XCTAssertEqual(plan.forcedStyle, .icons)
        XCTAssertTrue(plan.dropped.isEmpty)
    }

    func testFitFallsAllTheWayToStackedBeforeDroppingStats() {
        // 4 stats: 80pt labels, 48pt icons, 24pt stacked.
        let plan = MenuBarLayout.fit(
            stats: [.cpu, .gpu, .ram, .power], style: .labels, budget: 30, measure: measure
        )
        XCTAssertEqual(plan.stats, [.cpu, .gpu, .ram, .power])
        XCTAssertEqual(plan.style, .stacked)
        XCTAssertEqual(plan.forcedStyle, .stacked)
        XCTAssertTrue(plan.dropped.isEmpty)
    }

    func testFitDropsTrailingStatsWhenTheNarrowestStyleIsNotEnough() {
        let plan = MenuBarLayout.fit(
            stats: [.cpu, .gpu, .ram, .power], style: .stacked, budget: 13, measure: measure
        )
        XCTAssertEqual(plan.stats, [.cpu, .gpu])
        XCTAssertEqual(plan.dropped, [.ram, .power])
        XCTAssertNil(plan.forcedStyle) // the user had already chosen stacked
    }

    func testFitAlwaysKeepsAtLeastOneStat() {
        let plan = MenuBarLayout.fit(
            stats: [.cpu, .gpu], style: .stacked, budget: 1, measure: measure
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

    /// Stacked has to be materially narrower than the one-line styles or there's
    /// no reason for it to exist.
    @MainActor
    func testStackedIsTheNarrowestStyle() {
        let renderer = MenuBarRenderer(barHeight: 24)
        let all: [StatType] = [.cpu, .gpu, .ram, .cpuTemp, .gpuTemp, .fan, .power]
        let labels = renderer.width(stats: all, style: .labels)
        let icons = renderer.width(stats: all, style: .icons)
        let stacked = renderer.width(stats: all, style: .stacked)

        XCTAssertLessThan(icons, labels)
        XCTAssertLessThan(stacked, icons)
        XCTAssertLessThan(stacked, labels / 2, "stacked should roughly halve the labels width")
    }

    /// Same invariant as the string padding, at the level that actually matters:
    /// the rendered item must not change width as values change.
    @MainActor
    func testStackedImageWidthIsStableAcrossMagnitudes() {
        let renderer = MenuBarRenderer(barHeight: 24)
        let all: [StatType] = [.cpu, .gpu, .ram, .cpuTemp, .gpuTemp, .fan, .power]

        var low = StatsSnapshot()
        low.cpuUsage = 3; low.gpuUsage = 0; low.ramUsage = 7.2
        low.cpuTemp = 48; low.gpuTemp = 9; low.fanSpeed = 0; low.powerWatts = 8.1

        var high = StatsSnapshot()
        high.cpuUsage = 100; high.gpuUsage = 100; high.ramUsage = 99.9
        high.cpuTemp = 100; high.gpuTemp = 100; high.fanSpeed = 6800; high.powerWatts = 132.4

        XCTAssertEqual(
            renderer.stackedImage(stats: all, snapshot: low).size.width,
            renderer.stackedImage(stats: all, snapshot: high).size.width
        )
        // ...and it matches the width the item was sized to.
        XCTAssertEqual(
            renderer.stackedImage(stats: all, snapshot: low).size.width,
            renderer.width(stats: all, style: .stacked)
        )
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
