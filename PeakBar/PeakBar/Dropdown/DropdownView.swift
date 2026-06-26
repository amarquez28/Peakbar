//
//  DropdownView.swift
//  PeakBar
//
//  Root SwiftUI view for the popover: the stat toggle grid, menu bar options,
//  the update checker, and a Quit button.
//

import SwiftUI

struct DropdownView: View {
    @ObservedObject var statsManager: StatsManager
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PeakBar")
                .font(.headline)

            StatToggleGrid(statsManager: statsManager, settings: settings)

            Divider()

            Toggle("Compact menu bar", isOn: $settings.compactMode)
                .toggleStyle(.switch)
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)

            Divider()

            updateSection

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

    @ViewBuilder
    private var updateSection: some View {
        switch updateChecker.state {
        case .updateAvailable(let version, let url):
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Update available: v\(version)", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        default:
            HStack {
                Button("Check for Updates…") {
                    updateChecker.check()
                }
                Spacer()
                Text(updateStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var updateStatusText: String {
        switch updateChecker.state {
        case .checking: return "Checking…"
        case .upToDate: return "Up to date (v\(updateChecker.currentVersion))"
        case .failed(let message): return message
        default: return "v\(updateChecker.currentVersion)"
        }
    }
}
