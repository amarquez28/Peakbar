//
//  StatToggleGrid.swift
//  PeakBar
//
//  Two-column grid of stat toggle blocks, one per available StatType.
//

import SwiftUI

struct StatToggleGrid: View {
    @ObservedObject var statsManager: StatsManager
    @ObservedObject var settings: SettingsStore

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(StatType.allCases) { stat in
                StatToggleBlock(
                    stat: stat,
                    value: statsManager.liveValue(for: stat),
                    isSelected: settings.isVisible(stat)
                ) {
                    settings.toggle(stat)
                }
            }
        }
    }
}
