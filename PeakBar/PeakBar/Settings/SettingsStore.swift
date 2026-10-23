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
    private let compactModeKey = "compactMode" // pre-1.1.1, migrated to menuBarStyle
    private let menuBarStyleKey = "menuBarStyle"
    private let fitToMenuBarKey = "fitToMenuBar"

    @Published var visibleStats: [StatType] {
        didSet { defaults.set(visibleStats.map(\.rawValue), forKey: visibleStatsKey) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: launchAtLoginKey)
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    /// How the menu bar draws each stat — see MenuBarStyle. Successively
    /// narrower: word labels, SF Symbols, then symbol stacked over value.
    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: menuBarStyleKey) }
    }

    /// When on (the default), PeakBar sizes itself to the space the menu bar can
    /// actually spare and drops trailing stats rather than overflowing. Turning
    /// it off shows every selected stat, at the risk of macOS hiding menu bar
    /// icons — PeakBar's or another app's — when they no longer all fit.
    @Published var fitToMenuBar: Bool {
        didSet { defaults.set(fitToMenuBar, forKey: fitToMenuBarKey) }
    }

    private init() {
        if let raw = defaults.array(forKey: visibleStatsKey) as? [String] {
            let parsed = raw.compactMap(StatType.init(rawValue:))
            visibleStats = parsed.isEmpty ? [.cpu, .gpu] : parsed
        } else {
            visibleStats = [.cpu, .gpu] // defaults
        }
        launchAtLogin = defaults.bool(forKey: launchAtLoginKey)

        if let raw = defaults.string(forKey: menuBarStyleKey), let style = MenuBarStyle(rawValue: raw) {
            menuBarStyle = style
        } else {
            // Migrate the pre-1.1.1 `compactMode` boolean.
            menuBarStyle = defaults.bool(forKey: compactModeKey) ? .icons : .labels
        }

        // Defaults to on, so `bool(forKey:)`'s false-for-missing isn't usable.
        fitToMenuBar = defaults.object(forKey: fitToMenuBarKey) as? Bool ?? true
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
