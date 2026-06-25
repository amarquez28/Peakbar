//
//  SettingsStore.swift
//  PeakBar
//
//  User preferences backed by UserDefaults. `visibleStats` is persisted as an
//  array of raw stat identifiers; `launchAtLogin` mirrors the SMAppService state.
//
//  Note: a bare `@AppStorage var visibleStats: [StatType]` does not compile
//  (arrays aren't directly UserDefaults-representable), so this uses an explicit
//  ObservableObject with manual persistence.
//

import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private let visibleStatsKey = "visibleStats"
    private let launchAtLoginKey = "launchAtLogin"

    @Published var visibleStats: [StatType] {
        didSet { defaults.set(visibleStats.map(\.rawValue), forKey: visibleStatsKey) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: launchAtLoginKey)
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    private init() {
        if let raw = defaults.array(forKey: visibleStatsKey) as? [String] {
            let parsed = raw.compactMap(StatType.init(rawValue:))
            visibleStats = parsed.isEmpty ? [.cpu, .gpu] : parsed
        } else {
            visibleStats = [.cpu, .gpu] // defaults
        }
        launchAtLogin = defaults.bool(forKey: launchAtLoginKey)
    }

    func isVisible(_ stat: StatType) -> Bool {
        visibleStats.contains(stat)
    }

    /// Toggles a stat's visibility, keeping the canonical StatType ordering.
    func toggle(_ stat: StatType) {
        if let index = visibleStats.firstIndex(of: stat) {
            visibleStats.remove(at: index)
        } else {
            visibleStats.append(stat)
            visibleStats.sort {
                (StatType.allCases.firstIndex(of: $0) ?? 0) < (StatType.allCases.firstIndex(of: $1) ?? 0)
            }
        }
    }
}
