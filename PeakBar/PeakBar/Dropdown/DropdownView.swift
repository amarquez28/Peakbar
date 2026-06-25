//
//  DropdownView.swift
//  PeakBar
//
//  Root SwiftUI view for the popover: the stat toggle grid, the Launch at Login
//  switch, and a Quit button.
//

import SwiftUI

struct DropdownView: View {
    @ObservedObject var statsManager: StatsManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PeakBar")
                .font(.headline)

            StatToggleGrid(statsManager: statsManager, settings: settings)

            Divider()

            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit PeakBar")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
