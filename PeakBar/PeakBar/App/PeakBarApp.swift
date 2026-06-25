//
//  PeakBarApp.swift
//  PeakBar
//
//  @main entry point. PeakBar is a menu-bar-only (LSUIElement) agent app, so
//  there is no WindowGroup — all lifecycle is driven through AppDelegate, which
//  owns the NSStatusItem.
//

import SwiftUI

@main
struct PeakBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible window. A Settings scene keeps SwiftUI's App protocol
        // satisfied without creating a main window or dock presence.
        Settings {
            EmptyView()
        }
    }
}
