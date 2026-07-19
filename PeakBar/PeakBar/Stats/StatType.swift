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
    case power

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
        case .power: return "Power Draw"
        }
    }

    /// Short prefix shown in the menu bar (e.g. "CPU" in "CPU 10%").
    var menuPrefix: String {
        switch self {
        case .cpu, .cpuTemp: return "CPU"
        case .gpu, .gpuTemp: return "GPU"
        case .ram: return "RAM"
        case .fan: return "FAN"
        case .power: return "PWR"
        }
    }

    /// SF Symbol used in compact menu bar mode. All available on macOS 13+.
    /// (GPU has no stock SF Symbol, so it uses `customSymbolName` instead — this
    /// value is the fallback if the custom symbol can't be loaded.)
    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .ram: return "memorychip"
        case .cpuTemp: return "thermometer"
        case .gpuTemp: return "flame"
        case .fan: return "fanblades"
        case .power: return "bolt.fill"
        }
    }

    /// Asset-catalog name of a custom SF Symbol (`.symbolset`) to use in compact
    /// mode in preference to `symbolName`. GPU uses a hand-drawn two-fan graphics
    /// card since SF Symbols has no GPU glyph. Being a real symbol (not a plain
    /// template image), it gets the same menu bar tinting/dimming as stock symbols.
    var customSymbolName: String? {
        switch self {
        case .gpu: return "GPUIcon"
        default: return nil
        }
    }
}
