//
//  FanMonitor.swift
//  PeakBar
//
//  Fan speed (RPM) from the SMC. Each fan exposes an "actual RPM" key
//  F<n>Ac (F0Ac, F1Ac, ...) as a 32-bit float. We probe the first several
//  indices and average whatever responds. A reading of 0 is kept (Apple Silicon
//  spins fans fully down when cool), so the value reflects "fans are off". On a
//  fanless Mac no F*Ac key exists, so the result is nil → displayed "--".
//
//  Read-only: PeakBar never writes fan-control keys (F<n>Md / F<n>Tg), which
//  would require a privileged root helper and could defeat thermal protection.
//

import Foundation

final class FanMonitor {
    private let maxFans = 8

    /// Returns the average actual fan speed in RPM, or nil if no fan is present.
    func sample() -> Double? {
        var readings: [Double] = []
        for index in 0..<maxFans {
            if let rpm = SMC.shared.value(forKey: "F\(index)Ac"), rpm >= 0 {
                readings.append(rpm)
            }
        }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }
}
