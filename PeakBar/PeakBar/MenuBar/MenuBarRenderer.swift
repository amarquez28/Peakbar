//
//  MenuBarRenderer.swift
//  PeakBar
//
//  Draws the menu bar content in one of three styles and reports how wide each
//  one would be. Width is the scarce resource up here (see MenuBarLayout), so
//  the styles form a ladder from most readable to most compact:
//
//    .labels   CPU 10% GPU 4%          — word labels, one line
//    .icons    [cpu] 10% [gpu] 4%      — SF Symbols, one line
//    .stacked  [cpu]      [gpu]        — symbol over value, two rows
//              10%        4%             roughly half the width of .icons
//
//  .labels and .icons are attributed strings set on the button's title.
//  .stacked can't be expressed as a string, so it's drawn into a template
//  NSImage — template means the menu bar tints it for light/dark exactly like
//  a real symbol.
//

import AppKit

enum MenuBarStyle: String, CaseIterable, Identifiable, Codable {
    case labels
    case icons
    case stacked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .labels: return "Labels"
        case .icons: return "Icons"
        case .stacked: return "Stacked"
        }
    }

    /// Styles that are narrower than this one, widest first. Used to step down
    /// when the selection doesn't fit rather than dropping stats outright.
    var narrowerAlternatives: [MenuBarStyle] {
        switch self {
        case .labels: return [.icons, .stacked]
        case .icons: return [.stacked]
        case .stacked: return []
        }
    }
}

struct MenuBarRenderer {
    /// Height of the menu bar, injected because `NSStatusBar.system.thickness`
    /// is main-actor only and this type is used off the app too (previews).
    let barHeight: CGFloat

    // One-line styles.
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private let iconPointSize: CGFloat = 11

    // Stacked style. Two rows have to share ~24pt of menu bar, so both are much
    // smaller than the one-line styles — semibold keeps them legible at that size.
    private let stackedValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private let stackedIconPointSize: CGFloat = 9
    /// Vertical space between the symbol and the value.
    private let stackedRowGap: CGFloat = 0
    /// Horizontal space between stat columns. Larger than the one-line gap
    /// because there's no other separator between neighbouring columns.
    private let stackedColumnGap: CGFloat = 8
    /// Kept clear at the top and bottom so nothing touches the menu bar edges.
    private let stackedVerticalInset: CGFloat = 2

    // MARK: - Width

    /// Width of the widest content `stats` can ever produce in `style`. Used
    /// both to pick a style that fits and to pin the status item's length.
    func width(stats: [StatType], style: MenuBarStyle) -> CGFloat {
        guard !stats.isEmpty else { return 0 }
        switch style {
        case .labels, .icons:
            return attributedTitle(stats: stats, snapshot: MenuBarFormatter.widestSnapshot, style: style)
                .size().width
        case .stacked:
            return stackedWidth(columns: stackedColumns(stats: stats, snapshot: MenuBarFormatter.widestSnapshot))
        }
    }

    // MARK: - One-line styles

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
                result.append(NSAttributedString(string: " ", attributes: [.font: font]))
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

    // MARK: - Stacked style

    private struct StackedColumn {
        let icon: NSImage?
        let text: NSAttributedString
        /// Fixed by the widest value this stat can ever show, so the column —
        /// and therefore the whole item — never resizes as the numbers change.
        let width: CGFloat
    }

    func stackedImage(stats: [StatType], snapshot: StatsSnapshot) -> NSImage {
        let columns = stackedColumns(stats: stats, snapshot: snapshot)
        let size = NSSize(
            width: max(stackedWidth(columns: columns), 1),
            height: max(barHeight - stackedVerticalInset * 2, 1)
        )
        let rowGap = stackedRowGap
        let columnGap = stackedColumnGap
        let valueFont = stackedValueFont

        let image = NSImage(size: size, flipped: false) { _ in
            let textHeight = valueFont.ascender - valueFont.descender
            var x: CGFloat = 0

            for column in columns {
                let iconHeight = column.icon?.size.height ?? 0
                // Centre the two rows as a block within the available height.
                let stackHeight = iconHeight + rowGap + textHeight
                let bottom = max((size.height - stackHeight) / 2, 0)

                if let icon = column.icon {
                    let iconSize = icon.size
                    icon.draw(in: NSRect(
                        x: x + (column.width - iconSize.width) / 2,
                        y: bottom + textHeight + rowGap,
                        width: iconSize.width,
                        height: iconSize.height
                    ))
                }

                let textWidth = column.text.size().width
                column.text.draw(at: NSPoint(x: x + (column.width - textWidth) / 2, y: bottom))

                x += column.width + columnGap
            }
            return true
        }
        // Template: the menu bar recolours it for light/dark like a real symbol.
        image.isTemplate = true
        return image
    }

    private func stackedColumns(stats: [StatType], snapshot: StatsSnapshot) -> [StackedColumn] {
        let config = NSImage.SymbolConfiguration(pointSize: stackedIconPointSize, weight: .semibold)
        // Values are centred under their symbol, so they're drawn unpadded — the
        // column's fixed width does the job the figure-space padding does in the
        // one-line styles.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: stackedValueFont,
            .foregroundColor: NSColor.black // alpha is all that survives in a template image
        ]

        return stats.map { stat in
            let icon = symbolImage(for: stat, config: config)
            let value = MenuBarFormatter.compactValue(for: stat, stats: snapshot, padded: false)
            let widest = MenuBarFormatter.compactValue(
                for: stat, stats: MenuBarFormatter.widestSnapshot, padded: false
            )
            let widestWidth = NSAttributedString(string: widest, attributes: attributes).size().width
            return StackedColumn(
                icon: icon,
                text: NSAttributedString(string: value, attributes: attributes),
                width: max(icon?.size.width ?? 0, widestWidth)
            )
        }
    }

    private func stackedWidth(columns: [StackedColumn]) -> CGFloat {
        guard !columns.isEmpty else { return 0 }
        return columns.reduce(0) { $0 + $1.width } + stackedColumnGap * CGFloat(columns.count - 1)
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
