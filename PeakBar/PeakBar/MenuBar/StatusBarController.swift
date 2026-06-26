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
                let displaySize = iconDisplaySize(icon, isCustom: stat.compactImageName != nil, config: symbolConfig)
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

    /// Returns the compact-mode icon for a stat: a custom template image
    /// (`compactImageName`) if one exists, otherwise the SF Symbol. Custom images
    /// are scaled to match the SF Symbol height so the row stays visually even.
    private func symbolImage(for stat: StatType, config: NSImage.SymbolConfiguration) -> NSImage? {
        // Custom glyph: plain template NSImages are NOT auto-tinted in a status
        // item's attributed title (only SF Symbols are), so we explicitly paint
        // the silhouette in the menu bar's text color. The drawing handler keeps
        // it crisp at any scale, and the tint is recomputed on every refresh so
        // it follows light/dark menu bar changes.
        if let name = stat.compactImageName, let source = NSImage(named: name) {
            let tint = menuBarTextColor()
            let image = NSImage(size: source.size, flipped: false) { rect in
                source.draw(in: rect)
                tint.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            image.isTemplate = false
            return image
        }
        let symbol = NSImage(systemSymbolName: stat.symbolName, accessibilityDescription: stat.displayName)?
            .withSymbolConfiguration(config)
        symbol?.isTemplate = true
        return symbol
    }

    /// The menu bar's text color (white on a dark menu bar, black on a light
    /// one), resolved against the status item's current appearance.
    private func menuBarTextColor() -> NSColor {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        var color = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        return color
    }

    /// Display size for a compact-mode icon attachment. SF Symbols use their
    /// configured size; the custom GPU glyph is matched to the SF Symbol height,
    /// preserving its aspect ratio.
    private func iconDisplaySize(_ icon: NSImage, isCustom: Bool, config: NSImage.SymbolConfiguration) -> NSSize {
        guard isCustom else { return icon.size }
        let targetHeight = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?.size.height ?? menuFont.pointSize
        let aspect = icon.size.width / max(icon.size.height, 1)
        return NSSize(width: (targetHeight * aspect).rounded(), height: targetHeight.rounded())
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
