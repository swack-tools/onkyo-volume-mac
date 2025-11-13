# Onkyo Volume Control for macOS

A native macOS menu bar application for controlling Onkyo/Integra receiver volume over the network using the eISCP protocol.

![Platform](https://img.shields.io/badge/platform-macOS%2013.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)

## Features

- 🔊 **Menu Bar Integration**: Clean, unobtrusive menu bar icon
- 🎚️ **Volume Slider**: Real-time volume control with visual feedback (0-100 scale)
- ⌨️ **Global Keyboard Shortcuts**: F11/F12 keys control both system and receiver volume
- 🌐 **Network Control**: Communicates with receiver via eISCP protocol over TCP
- 💾 **Persistent Settings**: Remembers receiver IP address
- ⚙️ **First-Launch Setup**: Simple dialog to configure receiver IP address
- 🎨 **Native macOS**: Adapts to light/dark mode

## Requirements

- macOS 13.0 or later
- Onkyo or Integra network-enabled receiver
- Receiver connected to the same network as your Mac
- **Accessibility permissions** (for F11/F12 global keyboard shortcuts)

## Installation

### From Source

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd onkyo-volume-mac
   ```

2. Install XcodeGen (if not already installed):
   ```bash
   brew install xcodegen
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

For F11/F12 global shortcuts to work:

1. Go to **System Settings** > **Privacy & Security** > **Accessibility**
2. Click the **+** button and add **OnkyoVolume**
3. Enable the checkbox next to the app
4. Restart the app if it was already running

## Usage

### Menu Bar Controls

Click the menu bar icon to access:

- **Volume Slider**: Drag to set exact volume level
- **Volume Up/Down Buttons**: Adjust volume in increments of 5
- **Change IP...**: Update receiver IP address
- **Quit**: Exit the application

### Keyboard Shortcuts

- **F11**: Volume Down (both system and receiver)
- **F12**: Volume Up (both system and receiver)

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

### F11/F12 keys don't work

1. Grant Accessibility permissions:
   - System Settings > Privacy & Security > Accessibility
   - Add OnkyoVolume app and enable it
2. Restart the app after granting permissions
3. Check console output for "✓ Media key monitoring enabled"
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

## Development

### Project Structure

```
OnkyoVolume/
├── OnkyoVolumeApp.swift        # @main entry point
├── AppDelegate.swift            # NSApplicationDelegate, first-launch logic
├── StatusBarController.swift   # Menu bar UI and CGEventTap keyboard monitoring
├── OnkyoClient-simple.swift    # eISCP protocol implementation
├── SettingsManager.swift        # UserDefaults persistence
└── Assets.xcassets/            # App resources

project.yml                      # XcodeGen project definition
test-eiscp.swift                 # CLI testing tool
```

### Building with XcodeGen

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project file. The generated `.xcodeproj` file is gitignored.

After modifying `project.yml`:
```bash
xcodegen generate
```

### Testing eISCP Commands

Use the included CLI test tool to debug eISCP communication:

```bash
swift test-eiscp.swift <receiver-ip>
```

This will test volume up, volume query, and setting absolute volume commands.

### Manual Testing Checklist

- [ ] First launch shows IP dialog
- [ ] IP validation rejects invalid formats
- [ ] IP persists across app restarts
- [ ] Volume slider shows current volume when menu opens
- [ ] Dragging slider changes receiver volume
- [ ] Volume up/down buttons work
- [ ] F11/F12 keys work globally (other apps focused)
- [ ] F11/F12 change both system and receiver volume
- [ ] "Change IP" updates configuration
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

The app uses `CGEventTap` with `.defaultTap` mode to intercept F11/F12 media key events at the system level. This requires:
- Accessibility permissions
- Event tap added to main run loop
- Proper handling of tap disable events

Media keys send `NSSystemDefined` events (type 14) with special key codes:
- Code 0: F12 (Volume Up)
- Code 1: F11 (Volume Down)

### Recursive Response Handling

The receiver may send multiple responses to a single query (e.g., album art data before volume data). The client uses a recursive callback pattern to read responses until finding one with the expected prefix (e.g., "MVL" for volume queries).

## License

[Add your license here]

## Credits

Built with:
- Swift 5
- AppKit
- Network framework
- CoreGraphics (CGEventTap)
- XcodeGen

## Contributing

Contributions welcome! Please feel free to submit pull requests or open issues.

---

**Bundle ID**: `com.swack-tools.onkyo-volume`
**Minimum macOS**: 13.0
