//
//  StatusBarController.swift
//  PeakBar
//
//  Owns the NSStatusItem and the dropdown NSPopover. Renders the menu bar title
//  with a monospaced-digit font so the width doesn't jitter as values change.
//

import AppKit
import Combine
import SwiftUI

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let statsManager: StatsManager
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(statsManager: StatsManager, settings: SettingsStore) {
        self.statsManager = statsManager
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "PeakBar"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DropdownView(statsManager: statsManager, settings: settings)
        )

        // Update the title on each stats refresh...
        statsManager.onUpdate = { [weak self] snapshot in
            self?.updateTitle(with: snapshot)
        }
        // ...and immediately when the user changes which stats are visible.
        settings.$visibleStats
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateTitle(with: self.statsManager.snapshot)
            }
            .store(in: &cancellables)
    }

    private func updateTitle(with snapshot: StatsSnapshot) {
        let text = MenuBarFormatter.format(visibleStats: settings.visibleStats, stats: snapshot)
        statusItem.button?.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
