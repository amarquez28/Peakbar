//
//  StatusBarController.swift
//  PeakBar
//
//  Owns the NSStatusItem and the dropdown NSPopover, and drives MenuBarRenderer:
//    - no stats selected → the Summit template glyph
//    - .labels / .icons  → an attributed title on the button
//    - .stacked          → a template image drawn by the renderer
//
//  The item's width is pinned (`statusItem.length`) to the widest content the
//  current selection can ever produce, and only recalculated when the selection,
//  the style, or the attached displays change — never on a stats refresh. A
//  status item that resizes every few seconds makes macOS re-lay out the whole
//  menu bar, which is what causes icons (ours, or a neighbour like Hidden Bar's
//  arrow) to vanish on narrow displays. See MenuBarLayout.
//

import AppKit
import Combine
import SwiftUI

final class StatusBarController {
    /// Slack added to the measured content width so the fixed-length item
    /// doesn't clip itself — NSStatusBarButton insets its content slightly.
    private static let buttonPadding: CGFloat = 12

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let statsManager: StatsManager
    private let settings: SettingsStore
    private let renderer: MenuBarRenderer
    private let layoutState = MenuBarLayoutState.shared
    private var cancellables = Set<AnyCancellable>()
    private var plan = MenuBarLayout.Plan(stats: [], style: .labels, width: 0)

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

    /// Re-fits the user's selection to the available menu bar width and pins the
    /// item to that width.
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

        // Glyph-only mode has a constant width already, so variableLength costs
        // nothing there and keeps the icon's natural padding.
        statusItem.length = newPlan.stats.isEmpty
            ? NSStatusItem.variableLength
            : newPlan.width + Self.buttonPadding

        render(statsManager.snapshot)
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
            // Default: show the app glyph, no text.
            button.attributedTitle = NSAttributedString(string: "")
            button.image = glyphImage
            return
        }

        switch plan.style {
        case .labels, .icons:
            button.image = nil
            button.attributedTitle = renderer.attributedTitle(
                stats: plan.stats, snapshot: snapshot, style: plan.style
            )
        case .stacked:
            button.attributedTitle = NSAttributedString(string: "")
            button.image = renderer.stackedImage(stats: plan.stats, snapshot: snapshot)
        }
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
