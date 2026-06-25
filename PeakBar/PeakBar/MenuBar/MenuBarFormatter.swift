//
//  MenuBarFormatter.swift
//  PeakBar
//
//  Turns a snapshot + the user's visible-stat selection into the menu bar string,
//  e.g. "CPU 10% GPU 4% RAM 7.2GB CPU 48°C GPU 51°C".
//

import Foundation

enum MenuBarFormatter {
    static func format(visibleStats: [StatType], stats: StatsSnapshot) -> String {
        let parts: [String] = visibleStats.map { stat in
            switch stat {
            case .cpu:
                return "CPU \(Int(stats.cpuUsage.rounded()))%"
            case .gpu:
                return "GPU \(Int(stats.gpuUsage.rounded()))%"
            case .ram:
                return String(format: "RAM %.1fGB", stats.ramUsage)
            case .cpuTemp:
                return "CPU " + (stats.cpuTemp.map { "\(Int($0.rounded()))°C" } ?? "--°C")
            case .gpuTemp:
                return "GPU " + (stats.gpuTemp.map { "\(Int($0.rounded()))°C" } ?? "--°C")
            case .fan:
                guard let rpm = stats.fanSpeed else { return "FAN --" }
                return rpm < 1 ? "FAN Off" : "FAN \(Int(rpm.rounded()))rpm"
            }
        }
        return parts.isEmpty ? "PeakBar" : parts.joined(separator: " ")
    }
}
