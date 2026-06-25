//
//  CPUMonitor.swift
//  PeakBar
//
//  System-wide CPU usage % via host_statistics(HOST_CPU_LOAD_INFO). Usage is the
//  delta of busy ticks (user + system + nice) over total ticks between samples,
//  so the first sample after start returns 0 until a baseline exists.
//

import Foundation

final class CPUMonitor {
    private var previous: host_cpu_load_info?

    /// Returns CPU usage as a percentage in 0...100.
    func sample() -> Double {
        guard let current = Self.load() else { return 0 }
        defer { previous = current }
        guard let prev = previous else { return 0 }

        // cpu_ticks order: 0 = user, 1 = system, 2 = idle, 3 = nice.
        // Use wrapping subtraction since ticks are UInt32 counters.
        let user = Double(current.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(current.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(current.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(current.cpu_ticks.3 &- prev.cpu_ticks.3)

        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        let busy = user + system + nice
        return min(max(busy / total * 100, 0), 100)
    }

    private static func load() -> host_cpu_load_info? {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPtr, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
