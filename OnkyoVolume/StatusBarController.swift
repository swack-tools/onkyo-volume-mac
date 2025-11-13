//
//  StatusBarController.swift
//  OnkyoVolume
//
//  Manages the macOS menu bar icon and menu items.
//

import AppKit
import CoreGraphics
import ServiceManagement

/// Manages the status bar item and menu
class StatusBarController: NSObject, NSMenuDelegate {

    // MARK: - Properties

    private let statusItem: NSStatusItem
    private let onkyoClient: OnkyoClientSimple
    private let settingsManager: SettingsManager
    private var volumeSlider: NSSlider?
    private var volumeLabel: NSTextField?
    private var isUpdatingSlider = false
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var eventTap: CFMachPort?
    private var isMuted = false

    // MARK: - Initialization

    init(onkyoClient: OnkyoClientSimple = OnkyoClientSimple(),
         settingsManager: SettingsManager = .shared) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onkyoClient = onkyoClient
        self.settingsManager = settingsManager

        super.init()

        setupStatusItem()
        setupMenu()
        setupMediaKeyMonitoring()
    }

    deinit {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
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

        // Mute Toggle
        let muteItem = NSMenuItem(
            title: "Toggle Mute",
            action: #selector(toggleMuteMenu),
            keyEquivalent: ""
        )
        muteItem.target = self
        menu.addItem(muteItem)

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

        // Launch at Login
        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        // Separator
        menu.addItem(NSMenuItem.separator())

        // Version and Build Info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        #if DEBUG
        let buildConfig = "Debug"
        #else
        let buildConfig = "Release"
        #endif

        let versionItem = NSMenuItem(
            title: "v\(version) (\(build)) - \(buildConfig)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

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

    private func setupMediaKeyMonitoring() {
        // Check for accessibility permissions (still needed for media keys)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !accessEnabled {
            print("⚠️ Accessibility permissions needed for media key control")
            print("   Grant permissions in System Settings > Privacy & Security > Accessibility")
            print("   App will retry after permissions are granted")
        }

        // Create event tap for media keys
        // NSSystemDefined = 14
        let eventMask = (1 << 14)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // Use default tap for global monitoring
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Get the StatusBarController instance
                let controller = Unmanaged<StatusBarController>.fromOpaque(refcon!).takeUnretainedValue()

                // Re-enable tap if it was disabled
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    print("⚠️ Event tap was disabled, re-enabling...")
                    if let tap = controller.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                // Check if this is a system defined event (type 14)
                if type.rawValue == 14 {
                    let nsEvent = NSEvent(cgEvent: event)

                    // Media keys are subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS)
                    if nsEvent?.subtype == .screenChanged {
                        let data = nsEvent?.data1 ?? 0
                        let keyCode = ((data & 0xFFFF0000) >> 16)
                        let keyFlags = (data & 0x0000FFFF)
                        let keyPressed = ((keyFlags & 0xFF00) >> 8) == 0xA

                        // Debug: Log all media key events
                        if keyPressed {
                            print("DEBUG: Media key detected - keyCode: \(keyCode)")
                        }

                        // Only handle key down events
                        if keyPressed {
                            switch keyCode {
                            case 7: // F10 - Mute
                                print("✓ F10 (Mute) detected")
                                controller.handleMute()

                            case 1: // F11 - Volume Down
                                print("✓ F11 (Volume Down) detected")
                                controller.handleVolumeDown()

                            case 0: // F12 - Volume Up
                                print("✓ F12 (Volume Up) detected")
                                controller.handleVolumeUp()

                            default:
                                print("DEBUG: Unhandled keyCode: \(keyCode)")
                                break
                            }
                        }
                    }
                }

                // Always pass through the event (listenOnly mode)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap")
            print("   Make sure accessibility permissions are granted")
            print("   System Settings > Privacy & Security > Accessibility")
            return
        }

        self.eventTap = eventTap

        // Add to main run loop with common modes so it works when menu is open
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("✓ Media key monitoring enabled (F10/F11/F12)")
    }

    private func handleVolumeDown() {
        guard let ip = settingsManager.getReceiverIP() else { return }
        Task {
            try? await onkyoClient.volumeDown(to: ip)
        }
    }

    private func handleVolumeUp() {
        guard let ip = settingsManager.getReceiverIP() else { return }
        Task {
            try? await onkyoClient.volumeUp(to: ip)
        }
    }

    private func handleMute() {
        Task {
            await toggleMute()
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Query current volume when menu opens
        Task {
            await queryAndUpdateVolume()
        }

        // Update Launch at Login checkmark
        if let launchItem = menu.items.first(where: { $0.title == "Launch at Login" }) {
            launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
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

    @objc private func toggleMuteMenu() {
        Task {
            await toggleMute()
        }
    }

    @objc private func changeIP() {
        showIPDialog()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let isCurrentlyEnabled = SMAppService.mainApp.status == .enabled

        do {
            if isCurrentlyEnabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login Error"
            alert.informativeText = "Could not change launch at login setting: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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

        do {
            let volume = try await onkyoClient.queryVolume(from: ip)
            await MainActor.run {
                isUpdatingSlider = true
                volumeSlider?.doubleValue = Double(volume)
                volumeLabel?.stringValue = "Volume: \(volume)"
                isUpdatingSlider = false
            }
        } catch {
            // Query failed - show "--"
            // User can close/reopen menu to retry
            await MainActor.run {
                volumeLabel?.stringValue = "Volume: --"
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

    private func toggleMute() async {
        guard let ip = settingsManager.getReceiverIP() else {
            return
        }

        // Toggle local state
        isMuted = !isMuted

        do {
            try await onkyoClient.setMute(isMuted, to: ip)
            print("✓ Mute: \(isMuted ? "ON" : "OFF")")
        } catch {
            // Revert state on failure
            isMuted = !isMuted
            print("❌ Failed to toggle mute")
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
