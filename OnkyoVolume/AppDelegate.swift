//
//  AppDelegate.swift
//  OnkyoVolume
//
//  Application delegate managing lifecycle and initialization.
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusBarController: StatusBarController?
    private let settingsManager = SettingsManager.shared

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize status bar controller
        statusBarController = StatusBarController()

        // Check if this is first launch (no IP configured)
        if settingsManager.getReceiverIP() == nil {
            // Show IP configuration dialog on first launch
            statusBarController?.showIPDialog(isFirstLaunch: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
