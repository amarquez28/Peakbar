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
    @ObservedObject private var layout = MenuBarLayoutState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PeakBar")
                .font(.headline)

            StatToggleGrid(statsManager: statsManager, settings: settings)

            if let battery = statsManager.batterySummary {
                Label(battery, systemImage: "battery.100")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Picker("Menu bar style", selection: deferredStyleBinding) {
                ForEach(MenuBarStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Fit to menu bar space", isOn: $settings.fitToMenuBar)
                .toggleStyle(.switch)
                .help("Keeps PeakBar narrow enough for the smallest connected display so macOS doesn't hide menu bar icons. Turn off to always show every selected stat.")
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)

            if !fitNotice.isEmpty {
                Label(fitNotice, systemImage: "arrow.left.and.right.square")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    /// The `.segmented` picker on macOS writes its selection back while SwiftUI
    /// is still updating the view (a known bridging bug with NSSegmentedControl
    /// — https://developer.apple.com/forums/thread/823629), which logs
    /// "Publishing changes from within view updates is not allowed" on every
    /// switch. Applying the write on the next main-queue pass sidesteps it.
    private var deferredStyleBinding: Binding<MenuBarStyle> {
        Binding(
            get: { settings.menuBarStyle },
            set: { style in
                DispatchQueue.main.async { settings.menuBarStyle = style }
            }
        )
    }

    /// Explains the gap when the menu bar is showing less than was ticked above.
    private var fitNotice: String {
        let plan = layout.plan
        var reasons: [String] = []
        if !plan.dropped.isEmpty {
            let names = plan.dropped.map(\.displayName).joined(separator: ", ")
            reasons.append("\(names) hidden")
        }
        if let forced = plan.forcedStyle {
            reasons.append("switched to \(forced.displayName.lowercased())")
        }
        guard !reasons.isEmpty else { return "" }
        return "Not enough menu bar room: " + reasons.joined(separator: ", ") + "."
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
