//
//  StatsManager.swift
//  PeakBar
//
//  Orchestrates the individual monitors behind a single 5-second timer and
//  publishes the latest snapshot. The status bar updates via the `onUpdate`
//  callback; the dropdown observes `snapshot` directly through Combine.
//

import Foundation
import Combine

final class StatsManager: ObservableObject {
    @Published private(set) var snapshot = StatsSnapshot()

    /// Called on the main thread after every refresh. Used by the status bar.
    var onUpdate: ((StatsSnapshot) -> Void)?

    private let cpu = CPUMonitor()
    private let gpu = GPUMonitor()
    private let ram = RAMMonitor()
    private let thermal = ThermalMonitor()
    private let fan = FanMonitor()
    private let power = PowerMonitor()
    private let battery = BatteryMonitor()

    private let interval: TimeInterval = 5
    private var timerCancellable: AnyCancellable?

    func start() {
        // Prime the CPU monitor so it has a baseline, then take a real reading
        // shortly after launch instead of waiting a full interval for non-zero data.
        _ = cpu.sample()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refresh()
        }

        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        var snap = StatsSnapshot()
        snap.cpuUsage = cpu.sample()
        snap.gpuUsage = gpu.sample()
        snap.ramUsage = ram.sample()
        let temps = thermal.sample()
        snap.cpuTemp = temps.cpu
        snap.gpuTemp = temps.gpu
        snap.batteryTemp = temps.battery
        snap.fanSpeed = fan.sample()
        snap.powerWatts = power.sample()
        if let reading = battery.sample() {
            snap.batteryWatts = reading.watts
            snap.batteryMinutes = reading.minutesRemaining
            snap.batteryCharging = reading.isCharging
            snap.batteryHealth = reading.health
            snap.batteryCycles = reading.cycleCount
            snap.batteryDesignCycles = reading.designCycleCount
        }

        snapshot = snap
        onUpdate?(snap)
    }

    /// Formatted live value for a single stat, used by the dropdown blocks.
    func liveValue(for stat: StatType) -> String {
        switch stat {
        case .cpu: return "\(Int(snapshot.cpuUsage.rounded()))%"
        case .gpu: return "\(Int(snapshot.gpuUsage.rounded()))%"
        case .ram: return String(format: "%.1f GB", snapshot.ramUsage)
        case .cpuTemp: return snapshot.cpuTemp.map { "\(Int($0.rounded()))°C" } ?? "--°C"
        case .gpuTemp: return snapshot.gpuTemp.map { "\(Int($0.rounded()))°C" } ?? "--°C"
        case .fan:
            guard let rpm = snapshot.fanSpeed else { return "--" }
            return rpm < 1 ? "Off" : "\(Int(rpm.rounded())) rpm"
        case .power:
            return snapshot.powerWatts.map { String(format: "%.1f W", $0) } ?? "-- W"
        case .battery:
            guard let watts = snapshot.batteryWatts else { return "-- W" }
            return MenuBarFormatter.signed(watts, decimals: 1) + " W"
        case .batteryTime:
            guard let minutes = snapshot.batteryMinutes else { return "--" }
            let time = MenuBarFormatter.duration(minutes)
            return snapshot.batteryCharging ? "\(time) to full" : "\(time) left"
        case .batteryTemp: return snapshot.batteryTemp.map { "\(Int($0.rounded()))°C" } ?? "--°C"
        }
    }

    /// "Battery health 86% · 530 cycles", or nil on a Mac without a battery.
    var batterySummary: String? {
        var parts: [String] = []
        if let health = snapshot.batteryHealth {
            parts.append("Battery health \(Int((health * 100).rounded()))%")
        }
        if let cycles = snapshot.batteryCycles {
            let rated = snapshot.batteryDesignCycles.map { " of \($0)" } ?? ""
            parts.append("\(cycles)\(rated) cycles")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
