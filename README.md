# Onkyo Volume Control for macOS

A native macOS menu bar application for controlling Onkyo/Integra receiver volume over the network using the eISCP protocol.

![Platform](https://img.shields.io/badge/platform-macOS%2013.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)

## Features

- 🎨 **Custom App Icon**: Professional minimalist speaker design with sound waves
- 🔊 **Menu Bar Integration**: Clean, unobtrusive menu bar icon
- 🎚️ **Volume Slider**: Real-time volume control with visual feedback (0-100 scale)
- ⌨️ **Global Keyboard Shortcuts**: F10/F11/F12 keys control receiver mute and volume
- 🔇 **Mute Toggle**: Quick mute/unmute from keyboard or menu
- 🚀 **Launch at Login**: Optional auto-start with macOS
- 🌐 **Network Control**: Communicates with receiver via eISCP protocol over TCP
- 💾 **Persistent Settings**: Remembers receiver IP address
- ⚙️ **First-Launch Setup**: Simple dialog to configure receiver IP address
- 🎯 **Native macOS**: Adapts to light/dark mode, follows system design

## Requirements

- macOS 13.0 or later
- Onkyo or Integra network-enabled receiver
- Receiver connected to the same network as your Mac
- **Accessibility permissions** (for F11/F12 global keyboard shortcuts)

## Installation

### From Release (Recommended)

1. Download the latest DMG from the [Releases](https://github.com/swack-tools/onkyo-volume-mac/releases) page
2. Open the DMG file
3. Drag OnkyoVolume.app to your Applications folder
4. Double-click to launch

**Note**: The app is **signed and notarized** by Apple (Developer: SWACKTECH, LLC), so it will run without security warnings.

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/swack-tools/onkyo-volume-mac.git
   cd onkyo-volume-mac
   ```

2. Install dependencies:
   ```bash
   brew install xcodegen just
   ```

3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

4. Open the project in Xcode:
   ```bash
   open OnkyoVolume.xcodeproj
   ```

5. Build and run (⌘R)

## Setup

### First Launch

1. On first launch, you'll be prompted to enter your receiver's IP address
2. Find your receiver's IP address in your router's DHCP settings or receiver's network menu
3. Enter the IP address (e.g., `192.168.1.100`)

### Granting Accessibility Permissions

For F10/F11/F12 global shortcuts to work:

1. Go to **System Settings** > **Privacy & Security** > **Accessibility**
2. Click the **+** button and add **OnkyoVolume**
3. Enable the checkbox next to the app
4. Restart the app if it was already running

## Usage

### Menu Bar Controls

Click the menu bar icon to access:

- **Volume Slider**: Drag to set exact volume level
- **Volume Up/Down Buttons**: Adjust volume in increments of 5
- **Toggle Mute**: Mute/unmute receiver audio
- **Change IP...**: Update receiver IP address
- **Launch at Login**: Toggle auto-start with macOS (shows checkmark when enabled)
- **Version Info**: Displays app version and build configuration
- **Quit**: Exit the application

### Keyboard Shortcuts

- **F10**: Mute Toggle (receiver only)
- **F11**: Volume Down (receiver only)
- **F12**: Volume Up (receiver only)

The keyboard shortcuts work globally, even when other applications are focused.

### Changing Receiver IP

Click the menu bar icon → **Change IP...** → Enter new IP address

## How It Works

### eISCP Protocol

The app uses the Ethernet-based Integra Serial Control Protocol (eISCP) to communicate with Onkyo/Integra receivers:

- **Port**: TCP 60128
- **Commands**:
  - `MVLQSTN` - Query current volume
  - `MVLUP` - Volume up
  - `MVLDOWN` - Volume down
  - `MVL{hex}` - Set absolute volume (e.g., `MVL29` sets volume to 0x29 = 41)
  - `AMT00` - Mute off (unmute)
  - `AMT01` - Mute on

Each command is sent as a properly formatted eISCP packet with:
- ISCP header (4 bytes: "ISCP")
- Header size (4 bytes: 16)
- Data size (4 bytes: message length)
- Version byte (0x01)
- Reserved bytes (3 bytes: 0x00)
- Command string

### Architecture

```
Menu Bar Icon
    ↓
StatusBarController (UI + Keyboard Monitoring)
    ↓
OnkyoClientSimple (eISCP Protocol)
    ↓
TCP Connection (port 60128) → Receiver
```

Components:
- **OnkyoVolumeApp**: Main entry point
- **AppDelegate**: Application lifecycle, first-launch handling
- **StatusBarController**: Menu bar UI and global keyboard monitoring via CGEventTap
- **OnkyoClientSimple**: eISCP protocol implementation with recursive callback pattern
- **SettingsManager**: Persistent storage via UserDefaults
- **ServiceManagement**: System login item registration for launch-at-login functionality

### Volume Scale

Volume values map 1:1 between the app and receiver display. The hex values sent via eISCP correspond directly to the volume level shown on the receiver's display.

## Configuration

Settings are stored in macOS UserDefaults under the bundle ID `com.swack-tools.onkyo-volume`:

- **Receiver IP**: `receiverIPAddress` key

To reset settings:
```bash
defaults delete com.swack-tools.onkyo-volume
```

## Troubleshooting

### Volume slider shows "--"

- Verify receiver is powered on and connected to network
- Check IP address is correct (Menu → Change IP...)
- Ensure receiver is on the same network as your Mac
- Try closing and reopening the menu

### F10/F11/F12 keys don't work

1. Grant Accessibility permissions:
   - System Settings > Privacy & Security > Accessibility
   - Add OnkyoVolume app and enable it
2. Restart the app after granting permissions
3. Check console output for "✓ Media key monitoring enabled (F10/F11/F12)"
4. If you see "❌ Failed to create event tap", remove and re-add the app in Accessibility settings

### Connection errors

- Verify firewall settings aren't blocking TCP port 60128
- Test network connectivity: `ping <receiver-ip>`
- Some receivers require being "awake" or having network standby enabled to respond to network commands
- Check receiver's network control settings (eISCP must be enabled)

### Finding Receiver IP Address

Most Onkyo receivers display their IP address in:
- Setup → Network → Network Status
- Setup → Hardware → Network

Alternatively, check your router's DHCP client list.

### Launch at Login not working

If the "Launch at Login" toggle doesn't work:
1. Check System Settings > General > Login Items
2. You should see "OnkyoVolume" listed under "Allow in the Background"
3. If the toggle fails with an error, try:
   - Fully quit and restart the app
   - Remove the app from Login Items manually, then use the toggle again
4. The toggle state reflects the system setting, not a saved preference

## Development

### Project Structure

```
OnkyoVolume/
├── OnkyoVolumeApp.swift        # @main entry point
├── AppDelegate.swift            # NSApplicationDelegate, first-launch logic
├── StatusBarController.swift   # Menu bar UI and CGEventTap keyboard monitoring
├── OnkyoClient-simple.swift    # eISCP protocol implementation
├── SettingsManager.swift        # UserDefaults persistence
├── OnkyoVolume.entitlements    # App entitlements for hardened runtime
└── Assets.xcassets/            # App resources
    └── AppIcon.appiconset/      # Custom app icon (16-1024px sizes)

project.yml                      # XcodeGen project definition
justfile                         # Build automation commands
test-eiscp.swift                 # CLI testing tool
.github/workflows/release.yml    # CI/CD for automated releases
```

### Build Automation

The project uses [just](https://github.com/casey/just) for build automation. Available commands:

```bash
# Show all available commands
just

# Generate Xcode project from project.yml
just generate

# Run tests
just test

# Build debug configuration
just build-debug

# Build release configuration
just build-release

# Create DMG package (builds first)
just package-dmg v1.0.16

# Complete release pipeline (build + package)
just release v1.0.16

# Clean build artifacts
just clean

# Clean everything including Xcode project
just clean-all
```

### Building with XcodeGen

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project file. The generated `.xcodeproj` file is gitignored.

After modifying `project.yml`:
```bash
just generate
# or
xcodegen generate
```

### Creating a Release

Releases are automated via GitHub Actions when a version tag is pushed:

1. Update version in `project.yml`:
   ```yaml
   settings:
     MARKETING_VERSION: 1.0.X
   ```

2. Regenerate project and commit:
   ```bash
   just generate
   git add project.yml
   git commit -m "Bump version to 1.0.X"
   ```

3. Create and push tag:
   ```bash
   git tag v1.0.X
   git push origin main
   git push origin v1.0.X
   ```

4. GitHub Actions will automatically:
   - Run tests
   - Build and sign the app
   - Notarize with Apple
   - Create DMG using `hdiutil`
   - Create GitHub release with DMG attached

The workflow runs on Warp's `warp-macos-15-arm64-6x` runner for fast, reliable builds.

### Testing eISCP Commands

Use the included CLI test tool to debug eISCP communication:

```bash
swift test-eiscp.swift <receiver-ip>
```

This will test volume up, volume query, and setting absolute volume commands.

### Code Signing and Notarization

For distribution, the app is signed and notarized:

**Development builds** use automatic code signing:
- Debug configuration: `CODE_SIGN_STYLE: Automatic`
- Builds locally without notarization

**Release builds** require manual code signing:
- Sign with "Developer ID Application" certificate
- Enable Hardened Runtime
- Code signing flags: `--timestamp`
- Notarize with Apple using `notarytool`

Required GitHub Secrets for automated releases:
- `BUILD_CERTIFICATE_BASE64`: Base64-encoded .p12 certificate
- `P12_PASSWORD`: Certificate password
- `KEYCHAIN_PASSWORD`: Temporary keychain password
- `NOTARIZATION_APPLE_ID`: Apple ID for notarization
- `NOTARIZATION_PASSWORD`: App-specific password
- `NOTARIZATION_TEAM_ID`: Developer team ID

The GitHub Actions workflow handles certificate import, code signing, notarization, and stapling automatically.

### Manual Testing Checklist

- [ ] App icon displays correctly in Finder, Dock (when open), and app switcher
- [ ] First launch shows IP dialog
- [ ] IP validation rejects invalid formats
- [ ] IP persists across app restarts
- [ ] Volume slider shows current volume when menu opens
- [ ] Dragging slider changes receiver volume
- [ ] Volume up/down buttons work
- [ ] Mute toggle button works in menu
- [ ] F10 key mutes/unmutes receiver
- [ ] F11/F12 keys work globally (other apps focused)
- [ ] F11/F12 change receiver volume
- [ ] "Change IP" updates configuration
- [ ] "Launch at Login" toggle shows checkmark when enabled
- [ ] "Launch at Login" actually launches app on macOS login
- [ ] Menu bar icon visible in light and dark mode
- [ ] App runs as menu bar app (no dock icon)
- [ ] App quits cleanly

## Supported Receivers

This app should work with most Onkyo and Integra receivers that support eISCP network control, including:

- Onkyo TX-NR series
- Onkyo TX-RZ series
- Integra DTR series
- Integra DRX series

Refer to your receiver's manual to confirm eISCP/network control support.

## Technical Notes

### Media Key Interception

The app uses `CGEventTap` with `.defaultTap` mode to intercept F10/F11/F12 media key events at the system level. This requires:
- Accessibility permissions
- Event tap added to main run loop with `.commonModes` for reliability
- Proper handling of tap disable events
- Hardened runtime enabled (required for notarization)

Media keys send `NSSystemDefined` events (type 14) with special key codes:
- Code 0: F12 (Volume Up)
- Code 1: F11 (Volume Down)
- Code 7: F10 (Mute Toggle)

### Launch at Login

The app uses the modern `SMAppService` API (macOS 13+) for launch-at-login functionality:
- No helper app required for main app registration
- Uses `SMAppService.mainApp.register()` and `unregister()`
- State queried directly from system (not persisted in UserDefaults)
- Users can manage in System Settings > General > Login Items
- No special entitlements needed (app-sandbox must be disabled)
- macOS shows notification when login item is added

### Recursive Response Handling

The receiver may send multiple responses to a single query (e.g., album art data before volume data). The client uses a recursive callback pattern to read responses until finding one with the expected prefix (e.g., "MVL" for volume queries).

### DMG Creation

The build system uses `hdiutil` (native macOS tool) instead of GUI-based tools for reliable DMG creation on headless CI/CD runners:
- Creates temporary folder with app and Applications symlink
- Uses `hdiutil create` with UDZO compression
- Works reliably on GitHub Actions without Finder/AppleScript dependencies
- Generated DMG includes Applications folder shortcut for easy drag-and-drop installation

## License

[Add your license here]

## Credits

Built with:
- Swift 5
- AppKit
- Network framework
- CoreGraphics (CGEventTap)
- ServiceManagement (Login Items)
- XcodeGen

## Contributing

Contributions welcome! Please feel free to submit pull requests or open issues.

---

**Bundle ID**: `com.swack-tools.onkyo-volume`
**Minimum macOS**: 13.0
