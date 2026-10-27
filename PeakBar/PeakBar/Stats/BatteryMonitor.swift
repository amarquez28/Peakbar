//
//  BatteryMonitor.swift
//  PeakBar
//
//  Battery flow, time remaining and long-term health from the AppleSmartBattery
//  IOKit service — the same registry entry `ioreg -rn AppleSmartBattery` prints.
//  No SMC access needed. Desktop Macs have no such service, so every field
//  comes back nil → displayed "--".
//
//  Keys used:
//    Voltage (mV) × Amperage (mA, signed: + charging, − discharging) → watts
//    AvgTimeToFull / AvgTimeToEmpty (minutes, 65535 = not applicable)
//    BatteryData.NominalChargeCapacity ÷ DesignCapacity → health
//      (matches System Settings' "Maximum Capacity"; FullChargeCapacity reads
//      a couple of points lower)
//    CycleCount, DesignCycleCount9C
//
//  Verified on M3 Pro: ≈ +51 W while charging on a 68 W adapter, 55 min to
//  full, 86 % health, 530 / 1000 cycles.
//

import Foundation
import IOKit

struct BatteryReading {
    /// Power into (+) or out of (−) the battery, in watts.
    var watts: Double?
    /// Minutes to full while charging, or to empty while discharging.
    var minutesRemaining: Int?
    var isCharging = false
    /// Current full-charge capacity as a fraction of design capacity, 0–1.
    var health: Double?
    var cycleCount: Int?
    var designCycleCount: Int?
}

final class BatteryMonitor {
    /// The "not applicable / still estimating" sentinel for the time keys.
    private let unknownTime = 65535

    func sample() -> BatteryReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil } // desktop Mac
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any],
              props["BatteryInstalled"] as? Bool ?? true
        else { return nil }

        var reading = BatteryReading()
        let isCharging = props["IsCharging"] as? Bool ?? false
        let onExternal = props["ExternalConnected"] as? Bool ?? false
        reading.isCharging = isCharging

        if let millivolts = int(props["Voltage"]), let milliamps = int(props["Amperage"]) {
            reading.watts = Double(millivolts) * Double(milliamps) / 1_000_000
        }

        // Plugged in but holding (optimised charging, or full) has no meaningful
        // time either way, so it stays nil.
        let timeKey = isCharging ? "AvgTimeToFull" : (onExternal ? nil : "AvgTimeToEmpty")
        if let timeKey, let minutes = int(props[timeKey]), minutes > 0, minutes < unknownTime {
            reading.minutesRemaining = minutes
        }

        let batteryData = props["BatteryData"] as? [String: Any] ?? [:]
        let design = int(props["DesignCapacity"]) ?? int(batteryData["DesignCapacity"])
        let current = int(batteryData["NominalChargeCapacity"]) ?? int(batteryData["FullChargeCapacity"])
        if let design, let current, design > 0 {
            reading.health = Double(current) / Double(design)
        }

        reading.cycleCount = int(props["CycleCount"])
        reading.designCycleCount = int(props["DesignCycleCount9C"])
        return reading
    }

    /// Reads an integer property. Amperage is a signed value that some macOS
    /// versions publish as an unsigned 64- or 32-bit bit pattern (ioreg shows
    /// discharge as 18446744073709550000), so both are folded back to signed.
    private func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.int64Value
        if raw > Int64(Int32.max), raw <= Int64(UInt32.max) {
            return Int(Int32(truncatingIfNeeded: raw))
        }
        return Int(raw)
    }
}
