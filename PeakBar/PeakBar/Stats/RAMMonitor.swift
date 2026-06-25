//
//  RAMMonitor.swift
//  PeakBar
//
//  RAM usage in gigabytes via host_statistics64(HOST_VM_INFO64). "Used" is
//  defined as active + wired + compressed pages, which tracks Activity Monitor's
//  "Memory Used" figure closely on Apple Silicon.
//

import Foundation

final class RAMMonitor {
    /// Returns memory currently in use, in gigabytes.
    func sample() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let usedBytes = active + wired + compressed

        return usedBytes / 1_073_741_824.0 // bytes -> GiB
    }
}
