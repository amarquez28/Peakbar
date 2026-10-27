//
//  MenuBarFormatter.swift
//  PeakBar
//
//  Turns a snapshot + the user's visible-stat selection into the menu bar string,
//  e.g. "CPU 10% GPU 4% RAM 7.2GB CPU 48°C GPU 51°C".
//
//  Values are drawn at their natural width, one space apart, so stats to the
//  right shift slightly when a number gains a digit (CPU 9% → 10%). What must
//  never change is the *status item's* width — that's what makes macOS re-lay
//  out (and drop) menu bar items. StatusBarController pins the item's length
//  to the width of `widestSnapshot`, so live content always fits inside it
//  and the button centres it. See MenuBarLayout for the full rationale.
//
//  (Earlier versions padded every value with figure spaces to a fixed field
//  width instead. That stopped the shifting but left wide, uneven gaps —
//  "FAN Off" reserved room for "9999rpm".)
//

import Foundation

enum MenuBarFormatter {
    static func format(visibleStats: [StatType], stats: StatsSnapshot) -> String {
        let parts: [String] = visibleStats.map { stat in
            stat.menuPrefix + " " + compactValue(for: stat, stats: stats, longUnits: true)
        }
        return parts.isEmpty ? "PeakBar" : parts.joined(separator: " ")
    }

    /// Short value string (no word label) for the icon style, paired with the
    /// stat's SF Symbol in the menu bar. `longUnits` spells the unit out for
    /// the labels style ("7.2GB", "48°C") instead of clipping it ("7.2G", "48°").
    static func compactValue(for stat: StatType, stats: StatsSnapshot, longUnits: Bool = false) -> String {
        switch stat {
        case .cpu:
            return "\(Int(stats.cpuUsage.rounded()))%"
        case .gpu:
            return "\(Int(stats.gpuUsage.rounded()))%"
        case .ram:
            return String(format: "%.1f", stats.ramUsage) + (longUnits ? "GB" : "G")
        case .cpuTemp:
            return temperature(stats.cpuTemp, longUnits: longUnits)
        case .gpuTemp:
            return temperature(stats.gpuTemp, longUnits: longUnits)
        case .fan:
            guard let rpm = stats.fanSpeed else { return "--" }
            if rpm < 1 { return longUnits ? "Off" : "off" }
            return "\(Int(rpm.rounded()))" + (longUnits ? "rpm" : "")
        case .power:
            guard let watts = stats.powerWatts else { return "--W" }
            return longUnits
                ? String(format: "%.1fW", watts)
                : "\(Int(watts.rounded()))W"
        case .battery:
            guard let watts = stats.batteryWatts else { return "--W" }
            return signed(watts, decimals: longUnits ? 1 : 0) + "W"
        case .batteryTime:
            guard let minutes = stats.batteryMinutes else { return "--" }
            return duration(minutes)
        case .batteryTemp:
            return temperature(stats.batteryTemp, longUnits: longUnits)
        }
    }

    /// "+51.5" / "−12.3" — the sign says which way power is flowing — or a
    /// bare "0" when nothing is. Uses U+2212 MINUS SIGN, which matches "+" in
    /// weight and width (a hyphen is narrower).
    static func signed(_ value: Double, decimals: Int) -> String {
        let magnitude = String(format: "%.\(decimals)f", abs(value))
        guard Double(magnitude) != 0 else { return magnitude }
        return (value > 0 ? "+" : "\u{2212}") + magnitude
    }

    /// Minutes as "h:mm", capped at 99:59 so it can't outgrow the pinned width.
    static func duration(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 99 * 60 + 59)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    private static func temperature(_ value: Double?, longUnits: Bool) -> String {
        let unit = longUnits ? "°C" : "°"
        guard let value else { return "--" + unit }
        return "\(Int(value.rounded()))" + unit
    }

    /// A snapshot whose every field renders at its maximum width. Used to size
    /// the status item once, up front, so live values always fit inside it.
    static var widestSnapshot: StatsSnapshot {
        StatsSnapshot(
            cpuUsage: 100,
            gpuUsage: 100,
            ramUsage: Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000,
            cpuTemp: 100,
            gpuTemp: 100,
            fanSpeed: 9999,
            powerWatts: 999, // not 999.9 — that rounds to a four-digit "1000W"
            batteryWatts: -999,
            batteryMinutes: 99 * 60 + 59,
            batteryTemp: 100
        )
    }
}
