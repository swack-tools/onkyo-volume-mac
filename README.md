# Onkyo Volume Control for macOS

A minimal macOS menu bar application for controlling Onkyo receiver volume using the eISCP (Ethernet-based Integra Serial Control Protocol) protocol.

## Features

- 🔊 Volume up/down controls from the macOS menu bar
- ⚡ Fast, lightweight native Swift app
- 🎯 Simple, focused functionality (YAGNI principle)
- 🔒 Persistent IP configuration
- 🎨 Adapts to macOS light/dark mode

## Requirements

- macOS 13.0 or later
- Onkyo receiver with eISCP network control support
- Receiver connected to the same network as your Mac

## Installation

### Building from Source

1. Clone this repository:
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

5. Build and run the app (⌘R)

## Usage

### First Launch

On first launch, you'll be prompted to enter your Onkyo receiver's IP address:

1. Find your receiver's IP address (usually available in receiver's network settings menu)
2. Enter the IP address in the dialog (e.g., `192.168.1.100`)
3. Click "OK"

The IP address will be saved for future use.

### Daily Use

1. The app runs in your menu bar (speaker icon)
2. Click the icon to open the menu
3. Select "Volume Up" or "Volume Down"
4. The receiver volume will adjust accordingly

### Changing IP Address

If your receiver's IP address changes:

1. Click the menu bar icon
2. Select "Change IP..."
3. Enter the new IP address

### Quitting the App

Click the menu bar icon and select "Quit" (or press ⌘Q).

## How It Works

### eISCP Protocol

The app implements a minimal subset of the eISCP protocol:

- **Port:** 60128 (TCP)
- **Commands:**
  - `MVLUP` - Volume up
  - `MVLDOWN` - Volume down

Each command is sent as a properly formatted eISCP packet with:
- ISCP header
- Header size (16 bytes)
- Data size
- Version byte (0x01)
- Command string

### Architecture

```
Menu Bar Icon
    ↓
StatusBarController (UI)
    ↓
OnkyoClient (eISCP)
    ↓
TCP Connection → Receiver
```

Components:
- **OnkyoVolumeApp**: Main entry point
- **AppDelegate**: Application lifecycle, first-launch handling
- **StatusBarController**: Menu bar UI and user interaction
- **OnkyoClient**: eISCP protocol implementation
- **SettingsManager**: Persistent storage (UserDefaults)

## Configuration

Settings are stored in macOS UserDefaults:

- **Receiver IP**: `receiverIPAddress` key

To reset settings, you can delete the preference file:
```bash
defaults delete com.swack-tools.onkyo-volume
```

## Troubleshooting

### "Could not connect to receiver" error

1. **Check IP address**: Verify the receiver's IP hasn't changed
2. **Check network**: Ensure Mac and receiver are on the same network
3. **Check receiver**: Ensure receiver is powered on
4. **Check firewall**: Ensure macOS firewall allows outbound connections on port 60128

### Finding Receiver IP Address

Most Onkyo receivers display their IP address in:
- Setup → Network → Network Status
- Setup → Hardware → Network

Alternatively, check your router's DHCP client list.

### Receiver Not Responding

- Some receivers require network standby to be enabled
- Check receiver's network control settings
- Ensure eISCP/network control is enabled in receiver settings

## Development

### Project Structure

```
OnkyoVolume/
├── OnkyoVolumeApp.swift          # @main entry point
├── AppDelegate.swift             # NSApplicationDelegate
├── StatusBarController.swift     # Menu bar management
├── OnkyoClient.swift             # eISCP protocol
└── SettingsManager.swift         # Settings persistence
```

### Building with XcodeGen

The project uses XcodeGen to manage the Xcode project file. After modifying `project.yml`:

```bash
xcodegen generate
```

### Testing

Manual testing checklist:
- [ ] First launch shows IP dialog
- [ ] IP validation rejects invalid formats
- [ ] IP persists across restarts
- [ ] Volume up/down work with receiver
- [ ] "Change IP" updates configuration
- [ ] Error alerts show when receiver offline
- [ ] App quits cleanly

## Supported Receivers

This app should work with most Onkyo receivers that support eISCP network control, including:

- Onkyo TX-NR series
- Onkyo TX-RZ series
- Integra DTR series
- Integra DRX series

Refer to your receiver's manual to confirm eISCP/network control support.

## Future Enhancements

Potential features for future versions:
- [ ] Keyboard shortcuts (⌥↑ / ⌥↓)
- [ ] Launch at login option
- [ ] Volume slider
- [ ] Input switching
- [ ] Power control
- [ ] Multiple receiver profiles
- [ ] Auto-discovery via SSDP

## License

[Add your license here]

## Credits

Built with:
- Swift
- AppKit
- Network framework
- XcodeGen

## Contributing

Contributions welcome! Please feel free to submit pull requests or open issues.

---

**Note:** This is a minimal implementation focused on volume control only. For full receiver control, consider using more comprehensive applications or protocols.
