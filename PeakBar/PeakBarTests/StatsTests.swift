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
        let text = MenuBarFormatter.format(visibleStats: [.cpu, .gpu], stats: snap)
        XCTAssertEqual(text, "CPU 10% GPU 4%")
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

    func testMenuBarFormatMissingTemperatureFallsBack() {
        var snap = StatsSnapshot()
        snap.cpuTemp = nil
        let text = MenuBarFormatter.format(visibleStats: [.cpuTemp], stats: snap)
        XCTAssertEqual(text, "CPU --°C")
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
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .cpu, stats: snap), "10%")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .ram, stats: snap), "7.2G")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .cpuTemp, stats: snap), "--°")
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .fan, stats: snap), "off")

        snap.fanSpeed = 2317.6
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .fan, stats: snap), "2318")

        snap.powerWatts = 32.68
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .power, stats: snap), "33W")
        snap.powerWatts = nil
        XCTAssertEqual(MenuBarFormatter.compactValue(for: .power, stats: snap), "--W")
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
