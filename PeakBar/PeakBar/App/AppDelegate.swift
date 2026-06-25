//
//  AppDelegate.swift
//  PeakBar
//
//  Creates the status bar item and starts the stats pipeline on launch.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statsManager = StatsManager()
    private let settings = SettingsStore.shared
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(statsManager: statsManager, settings: settings)
        statsManager.start()
    }
}
