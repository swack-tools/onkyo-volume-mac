//
//  OnkyoVolumeApp.swift
//  OnkyoVolume
//
//  Main application entry point.
//

import AppKit

@main
class OnkyoVolumeApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
