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

struct StatsSnapshot {
    var cpuUsage: Double = 0      // percent
    var gpuUsage: Double = 0      // percent
    var ramUsage: Double = 0      // gigabytes
    var cpuTemp: Double? = nil    // degrees Celsius
    var gpuTemp: Double? = nil    // degrees Celsius
    var fanSpeed: Double? = nil   // RPM (averaged across fans)
}

final class StatsManager: ObservableObject {
    @Published private(set) var snapshot = StatsSnapshot()

    /// Called on the main thread after every refresh. Used by the status bar.
    var onUpdate: ((StatsSnapshot) -> Void)?

    private let cpu = CPUMonitor()
    private let gpu = GPUMonitor()
    private let ram = RAMMonitor()
    private let thermal = ThermalMonitor()
    private let fan = FanMonitor()

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
        snap.fanSpeed = fan.sample()

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
        }
    }
}
