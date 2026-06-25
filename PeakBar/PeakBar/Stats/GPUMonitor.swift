//
//  GPUMonitor.swift
//  PeakBar
//
//  GPU usage % via IOKit. On Apple Silicon the integrated GPU exposes a
//  "Device Utilization %" value inside the "PerformanceStatistics" dictionary
//  of the IOAccelerator service. Key names have varied across macOS versions
//  and chip generations, so we probe a couple of known names and fall back to 0.
//

import Foundation
import IOKit

final class GPUMonitor {
    /// Returns GPU utilization as a percentage in 0...100.
    func sample() -> Double {
        guard let matching = IOServiceMatching("IOAccelerator") else { return 0 }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        var utilization = 0.0
        var service = IOIteratorNext(iterator)
        var found = false

        while service != 0 {
            if let props = Self.properties(of: service),
               let perf = props["PerformanceStatistics"] as? [String: Any] {
                if let value = (perf["Device Utilization %"] ?? perf["GPU Activity(%)"]) as? Int {
                    utilization = max(utilization, Double(value))
                    found = true
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        if !found {
            NSLog("PeakBar: GPU utilization key not found on this machine; reporting 0%.")
        }
        return min(max(utilization, 0), 100)
    }

    private static func properties(of service: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return props
    }
}
