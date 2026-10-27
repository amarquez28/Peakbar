//
//  StatusBarController.swift
//  PeakBar
//
//  Owns the NSStatusItem and the dropdown NSPopover, and drives MenuBarRenderer:
//    - no stats selected → the Summit template glyph
//    - .labels / .icons  → an attributed title on the button
//
//  The item's width only ever grows while running. A status item that resizes
//  every few seconds makes macOS re-lay out the whole menu bar, which is what
//  causes icons (ours, or a neighbour like Hidden Bar's arrow) to vanish on
//  narrow displays — see MenuBarLayout. But sizing for the worst case up front
//  (CPU 100%, 100°C, 9999rpm) leaves visible empty space at both edges.
//
//  So: the item starts snug around the current readings, grows (once) when a
//  reading needs more room, and never shrinks back until the selection, style,
//  or displays change. That's a handful of resizes per session, mostly in the
//  first minute. Fitting to the menu bar budget still uses the worst-case
//  width, so growing can never push the item past the budget.
//

import AppKit
import Combine
import SwiftUI

final class StatusBarController {
    /// Slack added to the measured content width so the fixed-length item
    /// doesn't clip itself. NSStatusBarButtonCell needs ~4.5pt beyond the
    /// title's own width (measured: `cellSize` minus the attributed title's
    /// width); anything more just shows up as empty space at both edges.
    private static let buttonPadding: CGFloat = 5

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let statsManager: StatsManager
    private let settings: SettingsStore
    private let renderer: MenuBarRenderer
    private let layoutState = MenuBarLayoutState.shared
    private var cancellables = Set<AnyCancellable>()
    private var plan = MenuBarLayout.Plan(stats: [], style: .labels, width: 0)
    /// Widest content shown since the last re-layout; the item's length tracks
    /// it and only ever increases. Capped by `plan.width` (the worst case).
    private var contentWidth: CGFloat = 0

    private lazy var glyphImage: NSImage? = {
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 21, height: 14) // matches the 36x24 source ratio
        return image
    }()

    init(statsManager: StatsManager, settings: SettingsStore) {
        self.statsManager = statsManager
        self.settings = settings
        self.renderer = MenuBarRenderer(barHeight: NSStatusBar.system.thickness)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Lets macOS remember our position in the bar across relaunches and
        // across the visibility toggle used to recover from a display change.
        statusItem.autosaveName = "PeakBarStatusItem"
        // Guard against a stale `false` persisted under that autosave name (a
        // crash mid-recovery would otherwise leave the app with no UI at all).
        statusItem.isVisible = true

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
        // ...and re-fit whenever a setting changes (visible stats, style).
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLayout() }
            .store(in: &cancellables)

        // Plugging in a display, starting/stopping Sidecar, or a resolution
        // change all change how much room the menu bar has.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main) // let geometry settle
            .sink { [weak self] _ in self?.handleScreenChange() }
            .store(in: &cancellables)

        applyLayout()
    }

    // MARK: - Layout

    /// Re-fits the user's selection to the available menu bar width and re-sizes
    /// the item snugly around the current readings.
    private func applyLayout() {
        let requested = settings.visibleStats
        let newPlan: MenuBarLayout.Plan

        if settings.fitToMenuBar {
            newPlan = MenuBarLayout.fit(
                stats: requested,
                style: settings.menuBarStyle,
                budget: MenuBarLayout.widthBudget(),
                measure: { [renderer] stats, style in renderer.width(stats: stats, style: style) }
            )
        } else {
            newPlan = MenuBarLayout.Plan(
                stats: requested,
                style: settings.menuBarStyle,
                width: renderer.width(stats: requested, style: settings.menuBarStyle)
            )
        }

        plan = newPlan
        if layoutState.plan != newPlan { layoutState.plan = newPlan }

        contentWidth = 0 // the only place the item may shrink
        render(statsManager.snapshot)
    }

    /// Grows the item to fit `width` of content if it doesn't already.
    private func growToFit(_ width: CGFloat) {
        // Whole points, so sub-point differences between readings don't count
        // as growth; never past the worst case the budget was checked against.
        let needed = min(width.rounded(.up), plan.width.rounded(.up))
        guard needed > contentWidth else { return }
        contentWidth = needed
        setLength(needed + Self.buttonPadding)
    }

    /// Only touches the length when it actually changes: every assignment
    /// rebuilds the item's menu bar scene (the "status-items … Variant" console
    /// lines).
    private func setLength(_ length: CGFloat) {
        if statusItem.length != length { statusItem.length = length }
    }

    /// macOS drops status items it can't fit and doesn't put them back on its
    /// own — hence "restart PeakBar to get the icon back". Re-fitting for the
    /// new screen and then cycling visibility makes the system re-place the
    /// item, which is the same thing a relaunch does, without the relaunch.
    private func handleScreenChange() {
        applyLayout()
        statusItem.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.isVisible = true
        }
    }

    // MARK: - Rendering

    private func render(_ snapshot: StatsSnapshot) {
        guard let button = statusItem.button else { return }

        guard !plan.stats.isEmpty else {
            // Default: show the app glyph, no text. Glyph-only mode has a
            // constant width already, so variableLength keeps the icon's
            // natural padding.
            setLength(NSStatusItem.variableLength)
            button.attributedTitle = NSAttributedString(string: "")
            button.image = glyphImage
            return
        }

        let title = renderer.attributedTitle(stats: plan.stats, snapshot: snapshot, style: plan.style)
        // Resize before setting the title, so a wider reading is never drawn
        // clipped into the old length.
        growToFit(title.size().width)
        button.image = nil
        button.attributedTitle = title
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
