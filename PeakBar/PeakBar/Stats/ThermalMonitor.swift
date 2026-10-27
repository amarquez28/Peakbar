//
//  ThermalMonitor.swift
//  PeakBar
//
//  CPU and GPU die temperatures from the SMC. Apple Silicon spreads thermal
//  sensors across many keys that differ by chip generation (M1/M2/M3/M4...), so
//  instead of hardcoding keys we discover them at startup: "Tp*" are the CPU
//  performance-core sensors and "Tg*" are the GPU sensors on every Apple Silicon
//  chip. Each sample averages the valid readings. If no sensor responds in a
//  plausible range the temperature is reported as nil ("--°C").
//
//  Battery cell sensors are "TB<n>T" (TB0T–TB2T on an M3 Pro, ~29 °C idle).
//  Desktop Macs have none, so the battery temperature is nil there.
//

import Foundation

final class ThermalMonitor {
    // Discovered once, lazily, on first sample. Empty if the SMC is unavailable.
    private lazy var cpuKeys: [String] = SMC.shared.keys(matchingPrefix: "Tp")
    private lazy var gpuKeys: [String] = SMC.shared.keys(matchingPrefix: "Tg")
    private lazy var batteryKeys: [String] = SMC.shared.keys(matchingPrefix: "TB").filter { $0.hasSuffix("T") }

    /// Returns CPU, GPU and battery temperatures in degrees Celsius, or nil
    /// where no sensor responded with a plausible value.
    func sample() -> (cpu: Double?, gpu: Double?, battery: Double?) {
        (
            averageTemperature(keys: cpuKeys),
            averageTemperature(keys: gpuKeys),
            averageTemperature(keys: batteryKeys)
        )
    }

    private func averageTemperature(keys: [String]) -> Double? {
        var readings: [Double] = []
        for key in keys {
            if let temp = SMC.shared.temperature(forKey: key), temp > 0, temp < 130 {
                readings.append(temp)
            }
        }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }
}
