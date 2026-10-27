//
//  MenuBarLayout.swift
//  PeakBar
//
//  Keeps PeakBar's status item inside the horizontal space the menu bar can
//  actually give it.
//
//  Why this exists: macOS does not truncate or scroll the menu bar. When the
//  status items don't all fit, it silently *drops whole items* — ours, or a
//  neighbour's. Apps that manage the bar by width (Hidden Bar, Bartender, Ice)
//  push items past the screen edge on purpose, so an item that keeps changing
//  width forces a full re-layout every time and makes those drops far more
//  likely. Narrow displays (a Sidecar iPad) and notched MacBooks — where extras
//  are confined to the region right of the notch — hit it first.
//

import AppKit
import Combine

enum MenuBarLayout {
    /// Share of a screen's menu-extra region PeakBar is willing to occupy. The
    /// rest is left for the system items (Control Center, Wi-Fi, battery,
    /// clock) and other third-party apps. Going over doesn't cost us a few
    /// pixels, it costs someone a whole icon — but being too strict drops stats
    /// the user asked for, so this sits just under half.
    ///
    /// Measured on a 14" M3 Pro (1800pt scaled, notched): extras region 790pt →
    /// 355pt budget. The two-stat default renders at 128pt; all seven stats need
    /// 511pt in normal mode and ~363pt compact.
    private static let budgetShare: CGFloat = 0.45
    private static let minimumBudget: CGFloat = 90
    private static let maximumBudget: CGFloat = 420

    /// Width available to menu extras on `screen`.
    @MainActor
    static func extrasRegionWidth(of screen: NSScreen) -> CGFloat {
        // Notched displays: extras live only in the area right of the notch,
        // which is much narrower than the screen itself.
        if let rightOfNotch = screen.auxiliaryTopRightArea {
            return rightOfNotch.width
        }
        // Otherwise assume the frontmost app's menu titles claim the left third.
        return screen.frame.width * 0.66
    }

    /// Budget for our status item, sized against the *narrowest* attached
    /// screen. Using the narrowest (rather than the current one) means the item
    /// stays visible on every display and its width never has to change as the
    /// menu bar moves between them — width changes are the thing that triggers
    /// the drops in the first place.
    @MainActor
    static func widthBudget() -> CGFloat {
        let regions = NSScreen.screens.map(extrasRegionWidth(of:))
        guard let narrowest = regions.min() else { return maximumBudget }
        return min(max(narrowest * budgetShare, minimumBudget), maximumBudget)
    }

    /// What we're going to draw, after fitting the user's selection to `budget`.
    struct Plan: Equatable {
        var stats: [StatType]
        var style: MenuBarStyle
        var width: CGFloat
        /// Stats the user enabled that didn't fit.
        var dropped: [StatType] = []
        /// Set when the fitter picked a narrower style than the user chose.
        var forcedStyle: MenuBarStyle?
    }

    /// Fits `stats` into `budget`, degrading in the order that costs the user
    /// the least: step down to a narrower style first (labels → icons, which
    /// still shows every stat), and only then drop stats from
    /// the right — the canonical order puts CPU/GPU first, so the ones added
    /// last go first. `measure` returns the rendered width of a candidate.
    static func fit(
        stats: [StatType],
        style: MenuBarStyle,
        budget: CGFloat,
        measure: ([StatType], MenuBarStyle) -> CGFloat
    ) -> Plan {
        var kept = stats
        var width = measure(kept, style)

        guard !kept.isEmpty else {
            return Plan(stats: kept, style: style, width: width)
        }

        var chosen = style
        var forcedStyle: MenuBarStyle?
        for narrower in style.narrowerAlternatives where width > budget {
            chosen = narrower
            forcedStyle = narrower
            width = measure(kept, chosen)
        }

        // Always keep at least one stat: an item showing nothing is worse than
        // one that's a little over budget.
        while width > budget && kept.count > 1 {
            kept.removeLast()
            width = measure(kept, chosen)
        }

        return Plan(
            stats: kept,
            style: chosen,
            width: width,
            dropped: stats.filter { !kept.contains($0) },
            forcedStyle: forcedStyle
        )
    }
}

/// The plan currently on screen, published so the dropdown can explain itself
/// when it's showing fewer stats than the user ticked.
final class MenuBarLayoutState: ObservableObject {
    static let shared = MenuBarLayoutState()

    @Published var plan = MenuBarLayout.Plan(stats: [], style: .labels, width: 0)

    private init() {}
}
