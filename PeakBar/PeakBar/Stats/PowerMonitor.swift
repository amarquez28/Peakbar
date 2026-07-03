//
//  PowerMonitor.swift
//  PeakBar
//
//  System power draw (watts) from the SMC. Apple Silicon exposes total system
//  power as PSTR ("System Total Power", flt). If that key is absent we fall
//  back to PDTR ("DC In" power) — note PDTR includes battery charging, so it
//  reads higher than actual consumption while charging. Neither key present
//  (or an implausible reading) → nil → displayed "--".
//
//  Verified on M3 Pro: PSTR ≈ 33 W under light load, PDTR ≈ 67 W while charging.
//

import Foundation

final class PowerMonitor {
    private let keys = ["PSTR", "PDTR"]

    /// Returns the current system power draw in watts, or nil if unavailable.
    func sample() -> Double? {
        for key in keys {
            if let watts = SMC.shared.value(forKey: key), watts > 0, watts < 1000 {
                return watts
            }
        }
        return nil
    }
}
