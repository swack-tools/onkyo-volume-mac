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
    private let onkyoClient: OnkyoClient
    private let settingsManager: SettingsManager
    private var volumeSlider: NSSlider?
    private var volumeLabel: NSTextField?
    private var isUpdatingSlider = false

    // MARK: - Initialization

    init(onkyoClient: OnkyoClient = OnkyoClient(),
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
        Task {
            await sendCommand(.volumeUp)
            // After a brief delay, query the new volume to update the slider
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await queryAndUpdateVolume()
        }
    }

    @objc private func volumeDown() {
        Task {
            await sendCommand(.volumeDown)
            // After a brief delay, query the new volume to update the slider
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await queryAndUpdateVolume()
        }
    }

    @objc private func changeIP() {
        showIPDialog()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Private Methods

    private func sendCommand(_ command: OnkyoClient.Command) async {
        guard let ip = settingsManager.getReceiverIP() else {
            await MainActor.run {
                showError("No receiver IP configured. Please set an IP address.")
            }
            return
        }

        do {
            try await onkyoClient.sendCommand(command, to: ip)
            // Silent success - no feedback needed
        } catch {
            await MainActor.run {
                showError("Could not connect to receiver at \(ip). Please check the IP address and ensure the receiver is powered on.")
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Connection Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func queryAndUpdateVolume() async {
        print("DEBUG: queryAndUpdateVolume() called")

        guard let ip = settingsManager.getReceiverIP() else {
            return
        }

        await MainActor.run {
            volumeLabel?.stringValue = "Volume: ..."
        }

        do {
            print("DEBUG: Starting volume query...")
            let volume = try await onkyoClient.queryVolume(from: ip)
            print("DEBUG: Got volume: \(volume)")
            await MainActor.run {
                isUpdatingSlider = true
                volumeSlider?.doubleValue = Double(volume)
                volumeLabel?.stringValue = "Volume: \(volume)"
                isUpdatingSlider = false
            }
        } catch {
            // Show error for debugging
            await MainActor.run {
                volumeLabel?.stringValue = "Volume: Error"
                showError("Volume query failed: \(error.localizedDescription)")
            }
        }
    }

    private func setVolume(_ volume: Int) async {
        guard let ip = settingsManager.getReceiverIP() else {
            await MainActor.run {
                showError("No receiver IP configured. Please set an IP address.")
            }
            return
        }

        do {
            try await onkyoClient.setVolume(volume, to: ip)
            // Silent success
        } catch {
            await MainActor.run {
                showError("Could not connect to receiver at \(ip). Please check the IP address and ensure the receiver is powered on.")
            }
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
