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

    func testEmptySelectionShowsAppName() {
        let text = MenuBarFormatter.format(visibleStats: [], stats: StatsSnapshot())
        XCTAssertEqual(text, "PeakBar")
    }
}
