//
//  MenuBarRenderer.swift
//  PeakBar
//
//  Draws the menu bar content in one of two styles and reports how wide each
//  one would be. Width is the scarce resource up here (see MenuBarLayout), so
//  the styles go from most readable to most compact:
//
//    .labels   CPU 10% GPU 4%          — word labels
//    .icons    [cpu]10% [gpu]4%        — SF Symbols, value hugging its symbol
//
//  Both are attributed strings set on the button's title.
//

import AppKit

enum MenuBarStyle: String, CaseIterable, Identifiable, Codable {
    case labels
    case icons

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .labels: return "Labels"
        case .icons: return "Icons"
        }
    }

    /// Styles that are narrower than this one, widest first. Used to step down
    /// when the selection doesn't fit rather than dropping stats outright.
    var narrowerAlternatives: [MenuBarStyle] {
        switch self {
        case .labels: return [.icons]
        case .icons: return []
        }
    }
}

struct MenuBarRenderer {
    /// Height of the menu bar, injected because `NSStatusBar.system.thickness`
    /// is main-actor only and this type is used off the app too (previews).
    let barHeight: CGFloat

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private let iconPointSize: CGFloat = 11
    /// Space between a symbol and its value (U+2009 THIN SPACE, ~2pt — a full
    /// space made the pair read as two separate things).
    private let iconValueGap = "\u{2009}"

    // MARK: - Width

    /// Width of the widest content `stats` can ever produce in `style`. Used
    /// both to pick a style that fits and to pin the status item's length.
    func width(stats: [StatType], style: MenuBarStyle) -> CGFloat {
        guard !stats.isEmpty else { return 0 }
        return attributedTitle(stats: stats, snapshot: MenuBarFormatter.widestSnapshot, style: style)
            .size().width
    }

    // MARK: - Styles

    func attributedTitle(stats: [StatType], snapshot: StatsSnapshot, style: MenuBarStyle) -> NSAttributedString {
        guard style != .labels else {
            return NSAttributedString(
                string: MenuBarFormatter.format(visibleStats: stats, stats: snapshot),
                attributes: [.font: font]
            )
        }

        let result = NSMutableAttributedString()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)

        for (index, stat) in stats.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }

            if let icon = symbolImage(for: stat, config: symbolConfig) {
                let displaySize = icon.size
                let attachment = NSTextAttachment()
                attachment.image = icon
                attachment.bounds = CGRect(
                    x: 0,
                    y: (font.capHeight - displaySize.height) / 2,
                    width: displaySize.width,
                    height: displaySize.height
                )
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: iconValueGap, attributes: [.font: font]))
            } else {
                // No symbol available — fall back to a one-letter prefix.
                result.append(NSAttributedString(
                    string: String(stat.menuPrefix.prefix(1)) + " ",
                    attributes: [.font: font]
                ))
            }

            result.append(NSAttributedString(
                string: MenuBarFormatter.compactValue(for: stat, stats: snapshot),
                attributes: [.font: font]
            ))
        }
        return result
    }

    // MARK: - Symbols

    /// The icon for a stat: a custom SF Symbol from the asset catalog
    /// (`customSymbolName`) if one exists, otherwise the stock SF Symbol. Both
    /// are real symbol images, so the menu bar tints and dims them identically
    /// (light/dark menu bars, inactive-screen dimming).
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
}
