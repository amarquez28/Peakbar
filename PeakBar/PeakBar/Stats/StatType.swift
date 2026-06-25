//
//  StatType.swift
//  PeakBar
//
//  The set of stats PeakBar can display. Order here is the canonical display
//  order used both in the menu bar string and the dropdown grid.
//

import Foundation

enum StatType: String, CaseIterable, Identifiable, Codable {
    case cpu
    case gpu
    case ram
    case cpuTemp
    case gpuTemp
    case fan

    var id: String { rawValue }

    /// Long label shown in the dropdown toggle block.
    var displayName: String {
        switch self {
        case .cpu: return "CPU Usage"
        case .gpu: return "GPU Usage"
        case .ram: return "RAM Usage"
        case .cpuTemp: return "CPU Temp"
        case .gpuTemp: return "GPU Temp"
        case .fan: return "Fan Speed"
        }
    }

    /// Short prefix shown in the menu bar (e.g. "CPU" in "CPU 10%").
    var menuPrefix: String {
        switch self {
        case .cpu, .cpuTemp: return "CPU"
        case .gpu, .gpuTemp: return "GPU"
        case .ram: return "RAM"
        case .fan: return "FAN"
        }
    }
}
