//
//  StatsSnapshot.swift
//  PeakBar
//
//  One reading of every stat. Kept free of dependencies so the menu bar
//  formatting and rendering code can be exercised on its own (see
//  scripts/preview-menubar.sh).
//

import Foundation

struct StatsSnapshot {
    var cpuUsage: Double = 0      // percent
    var gpuUsage: Double = 0      // percent
    var ramUsage: Double = 0      // gigabytes
    var cpuTemp: Double? = nil    // degrees Celsius
    var gpuTemp: Double? = nil    // degrees Celsius
    var fanSpeed: Double? = nil   // RPM (averaged across fans)
    var powerWatts: Double? = nil // total system power draw (W)
}
