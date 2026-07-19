//
//  StatusBarController.swift
//  PeakBar
//
//  Owns the NSStatusItem and the dropdown NSPopover. Renders the menu bar
//  content in one of three forms depending on settings:
//    - no stats selected      → the Summit template glyph (no text)
//    - normal mode            → "CPU 10% GPU 4% ..." monospaced text
//    - compact mode           → SF Symbol + value per stat (saves width)
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

    private let menuFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private lazy var glyphImage: NSImage? = {
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 21, height: 14) // matches the 36x24 source ratio
        return image
    }()

    init(statsManager: StatsManager, settings: SettingsStore) {
        self.statsManager = statsManager
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DropdownView(statsManager: statsManager, settings: settings)
        )

        // Refresh on each stats sample...
        statsManager.onUpdate = { [weak self] snapshot in
            self?.render(snapshot)
        }
        // ...and immediately when any setting changes (visible stats, compact mode).
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.render(self.statsManager.snapshot)
            }
            .store(in: &cancellables)

        render(statsManager.snapshot)
    }

    private func render(_ snapshot: StatsSnapshot) {
        guard let button = statusItem.button else { return }

        if settings.visibleStats.isEmpty {
            // Default: show the app glyph, no text.
            button.attributedTitle = NSAttributedString(string: "")
            button.image = glyphImage
            return
        }

        button.image = nil
        button.attributedTitle = settings.compactMode
            ? compactTitle(snapshot)
            : NSAttributedString(
                string: MenuBarFormatter.format(visibleStats: settings.visibleStats, stats: snapshot),
                attributes: [.font: menuFont]
              )
    }

    /// Builds the compact menu bar string: each stat as an SF Symbol attachment
    /// followed by its value. Falls back to a one-letter prefix if a symbol
    /// can't be loaded.
    private func compactTitle(_ snapshot: StatsSnapshot) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)

        for (index, stat) in settings.visibleStats.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: [.font: menuFont]))
            }

            if let icon = symbolImage(for: stat, config: symbolConfig) {
                let displaySize = icon.size
                let attachment = NSTextAttachment()
                attachment.image = icon
                attachment.bounds = CGRect(
                    x: 0,
                    y: (menuFont.capHeight - displaySize.height) / 2,
                    width: displaySize.width,
                    height: displaySize.height
                )
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: " ", attributes: [.font: menuFont]))
            } else {
                result.append(NSAttributedString(
                    string: String(stat.menuPrefix.prefix(1)) + " ",
                    attributes: [.font: menuFont]
                ))
            }

            result.append(NSAttributedString(
                string: MenuBarFormatter.compactValue(for: stat, stats: snapshot),
                attributes: [.font: menuFont]
            ))
        }
        return result
    }

    /// Returns the compact-mode icon for a stat: a custom SF Symbol from the
    /// asset catalog (`customSymbolName`) if one exists, otherwise the stock
    /// SF Symbol. Both are real symbol images, so the menu bar tints and dims
    /// them identically (light/dark menu bars, inactive-screen dimming).
    private func symbolImage(for stat: StatType, config: NSImage.SymbolConfiguration) -> NSImage? {
        let base: NSImage?
        if let name = stat.customSymbolName, let custom = NSImage(named: name) {
            base = custom
        } else {
            base = NSImage(systemSymbolName: stat.symbolName, accessibilityDescription: stat.displayName)
        }
        let symbol = base?.withSymbolConfiguration(config) ?? base
        symbol?.isTemplate = true
        return symbol
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
