//
//  MenuBarFormatter.swift
//  PeakBar
//
//  Turns a snapshot + the user's visible-stat selection into the menu bar string,
//  e.g. "CPU 10% GPU 4% RAM 7.2GB CPU 48°C GPU 51°C".
//
//  Numeric fields are left-padded to a fixed digit count with figure spaces
//  (U+2007 — the same advance as a digit), so "CPU 7%" and "CPU 100%" render at
//  identical width. Combined with the fixed `NSStatusItem.length` set by
//  StatusBarController, the item never resizes while it's running, which is what
//  keeps macOS from re-laying out (and dropping) menu bar items every refresh.
//  See MenuBarLayout for the full rationale.
//

import Foundation

enum MenuBarFormatter {
    private static let figureSpace = "\u{2007}"

    private static let percentDigits = 3 // "100"
    private static let tempDigits = 3    // "100"
    private static let rpmDigits = 4     // "9999"
    private static let wattDigits = 3    // "999"

    /// Integer digits needed for this machine's RAM, so the field is exactly as
    /// wide as it needs to be (2 on a 16 GB Mac, 3 on a 128 GB one).
    static let ramIntegerDigits: Int = {
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000
        return max(String(Int(totalGB.rounded())).count, 1)
    }()

    /// Left-pads with figure spaces so values of different magnitudes occupy the
    /// same width. `digits` counts the whole field, decimal point included.
    /// Padding is skipped for the stacked style, where each value is centred in
    /// a fixed-width column instead.
    private static func pad(_ text: String, to digits: Int, enabled: Bool = true) -> String {
        let deficit = digits - text.count
        guard enabled, deficit > 0 else { return text }
        return String(repeating: figureSpace, count: deficit) + text
    }

    static func format(visibleStats: [StatType], stats: StatsSnapshot) -> String {
        let parts: [String] = visibleStats.map { stat in
            stat.menuPrefix + " " + compactValue(for: stat, stats: stats, longUnits: true)
        }
        return parts.isEmpty ? "PeakBar" : parts.joined(separator: " ")
    }

    /// Short value string (no word label) for the icon styles, paired with the
    /// stat's SF Symbol in the menu bar. `longUnits` spells the unit out for
    /// the labels style ("7.2GB", "48°C") instead of clipping it ("7.2G", "48°").
    static func compactValue(
        for stat: StatType,
        stats: StatsSnapshot,
        longUnits: Bool = false,
        padded: Bool = true
    ) -> String {
        func pad(_ text: String, to digits: Int) -> String {
            Self.pad(text, to: digits, enabled: padded)
        }

        switch stat {
        case .cpu:
            return pad("\(Int(stats.cpuUsage.rounded()))", to: percentDigits) + "%"
        case .gpu:
            return pad("\(Int(stats.gpuUsage.rounded()))", to: percentDigits) + "%"
        case .ram:
            let value = String(format: "%.1f", stats.ramUsage)
            return pad(value, to: ramIntegerDigits + 2) + (longUnits ? "GB" : "G")
        case .cpuTemp:
            return temperature(stats.cpuTemp, longUnits: longUnits, padded: padded)
        case .gpuTemp:
            return temperature(stats.gpuTemp, longUnits: longUnits, padded: padded)
        case .fan:
            // "Off" and "--" carry no unit suffix, so they pad to the full field
            // width (digits + "rpm") rather than to the digits alone.
            let suffix = longUnits ? "rpm" : ""
            let field = rpmDigits + suffix.count
            guard let rpm = stats.fanSpeed else { return pad("--", to: field) }
            if rpm < 1 { return pad(longUnits ? "Off" : "off", to: field) }
            return pad("\(Int(rpm.rounded()))", to: rpmDigits) + suffix
        case .power:
            guard let watts = stats.powerWatts else {
                return pad("--", to: longUnits ? wattDigits + 2 : wattDigits) + "W"
            }
            return longUnits
                ? pad(String(format: "%.1f", watts), to: wattDigits + 2) + "W"
                : pad("\(Int(watts.rounded()))", to: wattDigits) + "W"
        }
    }

    private static func temperature(_ value: Double?, longUnits: Bool, padded: Bool) -> String {
        let unit = longUnits ? "°C" : "°"
        guard let value else { return pad("--", to: tempDigits, enabled: padded) + unit }
        return pad("\(Int(value.rounded()))", to: tempDigits, enabled: padded) + unit
    }

    /// A snapshot whose every field renders at its maximum width. Used to size
    /// the status item once, up front, instead of letting it grow later.
    static var widestSnapshot: StatsSnapshot {
        StatsSnapshot(
            cpuUsage: 100,
            gpuUsage: 100,
            ramUsage: Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000,
            cpuTemp: 100,
            gpuTemp: 100,
            fanSpeed: 9999,
            powerWatts: 999 // not 999.9 — that rounds to a four-digit "1000W"
        )
    }
}
