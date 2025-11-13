//
//  StatusBarController.swift
//  OnkyoVolume
//
//  Manages the macOS menu bar icon and menu items.
//

import AppKit

/// Manages the status bar item and menu
class StatusBarController: NSObject, NSMenuDelegate {

    // MARK: - Properties

    private let statusItem: NSStatusItem
    private let onkyoClient: OnkyoClientSimple
    private let settingsManager: SettingsManager
    private var volumeSlider: NSSlider?
    private var volumeLabel: NSTextField?
    private var isUpdatingSlider = false

    // MARK: - Initialization

    init(onkyoClient: OnkyoClientSimple = OnkyoClientSimple(),
         settingsManager: SettingsManager = .shared) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onkyoClient = onkyoClient
        self.settingsManager = settingsManager

        super.init()

        setupStatusItem()
        setupMenu()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        if let button = statusItem.button {
            // Use SF Symbol for speaker icon
            let image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Onkyo Volume")
            button.image = image
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Volume Slider Container
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))

        // Volume Label
        let label = NSTextField(frame: NSRect(x: 10, y: 35, width: 180, height: 20))
        label.stringValue = "Volume: --"
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .center
        sliderView.addSubview(label)
        self.volumeLabel = label

        // Volume Slider
        let slider = NSSlider(frame: NSRect(x: 10, y: 10, width: 180, height: 20))
        slider.minValue = 0
        slider.maxValue = 100
        slider.doubleValue = 50
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        sliderView.addSubview(slider)
        self.volumeSlider = slider

        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)

        // Separator
        menu.addItem(NSMenuItem.separator())

        // Volume Up
        let volumeUpItem = NSMenuItem(
            title: "Volume Up",
            action: #selector(volumeUp),
            keyEquivalent: ""
        )
        volumeUpItem.target = self
        menu.addItem(volumeUpItem)

        // Volume Down
        let volumeDownItem = NSMenuItem(
            title: "Volume Down",
            action: #selector(volumeDown),
            keyEquivalent: ""
        )
        volumeDownItem.target = self
        menu.addItem(volumeDownItem)

        // Separator
        menu.addItem(NSMenuItem.separator())

        // Change IP
        let changeIPItem = NSMenuItem(
            title: "Change IP...",
            action: #selector(changeIP),
            keyEquivalent: ""
        )
        changeIPItem.target = self
        menu.addItem(changeIPItem)

        // Separator
        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Query current volume when menu opens
        Task {
            await queryAndUpdateVolume()
        }
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard !isUpdatingSlider else { return }

        let volume = Int(sender.doubleValue)
        volumeLabel?.stringValue = "Volume: \(volume)"

        // Send volume change to receiver
        Task {
            await setVolume(volume)
        }
    }

    @objc private func volumeUp() {
        // Increment slider by 5
        guard let slider = volumeSlider else { return }
        let newVolume = min(100, Int(slider.doubleValue) + 5)
        slider.doubleValue = Double(newVolume)
        sliderChanged(slider)
    }

    @objc private func volumeDown() {
        // Decrement slider by 5
        guard let slider = volumeSlider else { return }
        let newVolume = max(0, Int(slider.doubleValue) - 5)
        slider.doubleValue = Double(newVolume)
        sliderChanged(slider)
    }

    @objc private func changeIP() {
        showIPDialog()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Private Methods

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Connection Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func queryAndUpdateVolume() async {
        guard let ip = settingsManager.getReceiverIP() else {
            return
        }

        await MainActor.run {
            volumeLabel?.stringValue = "Volume: ..."
        }

        // Try twice - first query often times out on first menu open
        for attempt in 1...2 {
            do {
                let volume = try await onkyoClient.queryVolume(from: ip)
                await MainActor.run {
                    isUpdatingSlider = true
                    volumeSlider?.doubleValue = Double(volume)
                    volumeLabel?.stringValue = "Volume: \(volume)"
                    isUpdatingSlider = false
                }
                return // Success!
            } catch {
                print("Volume query attempt \(attempt) failed: \(error)")
                if attempt == 1 {
                    // First attempt failed, try once more
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                } else {
                    // Both attempts failed - show "--"
                    await MainActor.run {
                        volumeLabel?.stringValue = "Volume: --"
                    }
                }
            }
        }
    }

    private func setVolume(_ volume: Int) async {
        guard let ip = settingsManager.getReceiverIP() else {
            return
        }

        do {
            try await onkyoClient.setVolume(volume, to: ip)
            // Silent success
        } catch {
            // Silent failure for setting too - receiver may be busy
            // User can try moving slider again if needed
        }
    }

    func showIPDialog(isFirstLaunch: Bool = false) {
        let alert = NSAlert()
        alert.messageText = isFirstLaunch ? "Welcome to Onkyo Volume Control" : "Change Receiver IP"
        alert.informativeText = "Enter the IP address of your Onkyo receiver:"
        alert.alertStyle = .informational

        // Create text field
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "192.168.1.100"

        // Pre-fill with existing IP if available
        if let existingIP = settingsManager.getReceiverIP() {
            textField.stringValue = existingIP
        }

        alert.accessoryView = textField
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        // Make text field first responder
        alert.window.initialFirstResponder = textField

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let ip = textField.stringValue.trimmingCharacters(in: .whitespaces)

            // Validate IP address
            if SettingsManager.isValidIPAddress(ip) {
                settingsManager.setReceiverIP(ip)
            } else {
                // Show validation error
                let errorAlert = NSAlert()
                errorAlert.messageText = "Invalid IP Address"
                errorAlert.informativeText = "Please enter a valid IP address (e.g., 192.168.1.100)"
                errorAlert.alertStyle = .warning
                errorAlert.addButton(withTitle: "OK")
                errorAlert.runModal()

                // Show dialog again
                showIPDialog(isFirstLaunch: isFirstLaunch)
            }
        } else if isFirstLaunch {
            // User cancelled on first launch - quit the app
            NSApplication.shared.terminate(nil)
        }
    }
}
