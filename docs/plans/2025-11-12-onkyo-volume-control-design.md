# Onkyo Volume Control - macOS Menu Bar App

**Date:** 2025-11-12
**Status:** Approved Design
**Language:** Swift (native macOS)

## Overview

A minimal macOS menu bar application for controlling Onkyo receiver volume using the eISCP (Ethernet-based Integra Serial Control Protocol) protocol. The app runs as a menu bar-only utility (no dock icon) and provides simple volume up/down controls.

## Requirements

### Functional Requirements
- Display in macOS menu bar with speaker icon
- Provide "Volume Up" and "Volume Down" menu items
- Allow user to configure receiver IP address via dialog on first launch
- Support changing IP address via "Change IP..." menu item
- Persist IP address across app restarts
- Silent success (no feedback for successful volume changes)
- Error alerts only when connection fails

### Non-Functional Requirements
- macOS 13.0+ compatibility
- Lightweight and responsive
- Native macOS design patterns
- Minimal dependencies (no external libraries)

### Explicitly Out of Scope (YAGNI)
- Volume slider
- Input switching
- Power control
- Zone management
- Multiple receiver support
- Keyboard shortcuts (may add later)
- Background service/launch at login

## Architecture

### Component Overview

```
┌─────────────────────────────────────────┐
│         macOS Menu Bar                  │
│  ┌─────────────────────────────────┐   │
│  │  [Speaker Icon]                 │   │
│  │    ├─ Volume Up                 │   │
│  │    ├─ Volume Down               │   │
│  │    ├─ ───────────               │   │
│  │    ├─ Change IP...              │   │
│  │    └─ Quit                      │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
           │
           ▼
    ┌──────────────────┐
    │  AppDelegate     │
    │  - First launch  │
    │  - Lifecycle     │
    └──────────────────┘
           │
    ┌──────┴───────────────────────┐
    │                              │
    ▼                              ▼
┌─────────────────┐      ┌──────────────────┐
│ StatusBarCtrl   │      │ SettingsManager  │
│ - Menu mgmt     │─────▶│ - IP storage     │
│ - User actions  │      │ - UserDefaults   │
└─────────────────┘      └──────────────────┘
    │
    ▼
┌─────────────────┐
│  OnkyoClient    │
│ - eISCP protocol│
│ - TCP comm      │
│ - Commands      │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Onkyo Receiver  │
│ (via eISCP)     │
│ Port 60128      │
└─────────────────┘
```

### Components

#### 1. AppDelegate
- **Responsibility:** Application lifecycle, first-launch detection
- **Key Functions:**
  - `applicationDidFinishLaunching()`: Check for saved IP, show dialog if none
  - Instantiate StatusBarController
  - Handle graceful shutdown

#### 2. StatusBarController
- **Responsibility:** Manage menu bar icon and menu items
- **Key Functions:**
  - Create NSStatusItem with speaker icon (SF Symbol: `speaker.wave.2.fill`)
  - Build menu programmatically
  - Handle menu item actions
  - Call OnkyoClient for volume commands
  - Show error alerts on connection failure

#### 3. OnkyoClient
- **Responsibility:** eISCP protocol implementation
- **Key Functions:**
  - `sendCommand(_ command: String, to host: String) async throws`
  - Build eISCP packet format
  - TCP communication on port 60128
  - Implement timeout (5 seconds)

**eISCP Protocol:**
- Commands: `MVLUP` (volume up), `MVLDOWN` (volume down)
- Packet format:
  ```
  Header: "ISCP" (4 bytes)
  Header size: 16 (4 bytes, big-endian)
  Data size: message length (4 bytes, big-endian)
  Version: 0x01 (1 byte)
  Reserved: 0x00 (3 bytes)
  Message: "!1{command}\r\n"
  ```

#### 4. SettingsManager
- **Responsibility:** Persist and retrieve settings
- **Key Functions:**
  - `getReceiverIP() -> String?`: Read from UserDefaults
  - `setReceiverIP(_ ip: String)`: Write to UserDefaults
- **Storage Key:** `"receiverIPAddress"`

## User Experience

### First Launch Flow
1. App starts
2. Check UserDefaults for saved IP
3. If no IP found:
   - Show NSAlert with text input field
   - Validate IP format (basic regex: `\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}`)
   - Save to UserDefaults on confirm
4. Display menu bar icon

### Normal Operation
1. User clicks menu bar icon
2. Menu displays with options
3. User selects "Volume Up" or "Volume Down"
4. App sends eISCP command to receiver
5. On success: silent (no feedback)
6. On error: Show NSAlert with error message

### IP Configuration
- First launch: Automatic dialog
- Change IP: Menu item → Same dialog
- Validation: Basic format check
- Persistence: UserDefaults

## Error Handling

### Error Types and Responses

| Error Type | Response |
|------------|----------|
| Connection timeout (5s) | NSAlert: "Could not connect to receiver at {IP}. Please check the IP address and ensure the receiver is powered on." |
| Connection refused | Same as timeout |
| Network unreachable | Same as timeout |
| Invalid IP format | Inline error in IP dialog, prevent save |
| Protocol error | Log only, fail silently |

### Error Handling Strategy
- **Show alerts:** Only for errors requiring user action (connection failures)
- **Silent failures:** Protocol-level issues (most receivers don't ACK volume commands)
- **Validation:** Prevent invalid input at entry point

## Data Flow

### Volume Control Sequence
```
User clicks "Volume Up"
    ↓
StatusBarController.volumeUp()
    ↓
SettingsManager.getReceiverIP() → "192.168.1.100"
    ↓
OnkyoClient.sendCommand("MVLUP", to: "192.168.1.100")
    ↓
Build eISCP packet
    ↓
Open TCP connection to 192.168.1.100:60128
    ↓
Send packet
    ↓
Close connection
    ↓
[Silent success]
```

### Error Flow
```
User clicks "Volume Up"
    ↓
OnkyoClient.sendCommand() throws
    ↓
StatusBarController catches error
    ↓
NSAlert.show("Could not connect...")
```

## Project Structure

```
OnkyoVolume/
├── OnkyoVolumeApp.swift          # @main entry point
├── AppDelegate.swift             # NSApplicationDelegate
├── StatusBarController.swift     # Menu bar management
├── OnkyoClient.swift             # eISCP implementation
├── SettingsManager.swift         # UserDefaults wrapper
├── Assets.xcassets/              # (Optional) Custom icons
├── Info.plist                    # LSUIElement = YES
└── OnkyoVolume.entitlements      # (If needed for sandboxing)
```

### Xcode Project Settings
- **Bundle Identifier:** `com.swack-tools.onkyo-volume`
- **Deployment Target:** macOS 13.0
- **Category:** Utilities
- **LSUIElement:** YES (hide dock icon)
- **Signing:** Development (local use)

## Testing Strategy

### Manual Testing Checklist
- [ ] First launch shows IP dialog
- [ ] IP validation rejects invalid formats
- [ ] IP persists across app restarts
- [ ] "Volume Up" increases receiver volume
- [ ] "Volume Down" decreases receiver volume
- [ ] "Change IP" updates saved IP
- [ ] Error alert shows when receiver offline
- [ ] Error alert shows when IP unreachable
- [ ] App quits cleanly from menu
- [ ] Icon displays correctly in light/dark mode

### Unit Testing (Optional)
- Test eISCP packet building logic
- Test IP validation regex
- Mock network layer for command testing

### Integration Testing
- Test against actual Onkyo receiver
- Various receiver models (if available)
- Different network conditions

## Future Enhancements (Not in MVP)
- Keyboard shortcuts (⌥↑ / ⌥↓)
- Launch at login
- Volume slider
- Input switching
- Power control
- Multiple receiver profiles
- Network discovery (auto-find receivers)
- Status indicator (connected/disconnected)

## Technical Decisions

### Why Swift?
- Native macOS integration
- Best performance for menu bar apps
- Access to NSStatusBar and AppKit
- Modern async/await for network operations

### Why Minimal eISCP Implementation?
- Faster development
- Fewer dependencies
- Easier to debug
- Focused scope (YAGNI)

### Why Silent Success?
- Volume change is audibly obvious
- Reduces UI clutter
- Better user experience for frequent actions

### Why UserDefaults?
- Simple single-value storage
- No need for complex configuration
- Standard macOS pattern

### Why No Keyboard Shortcuts in MVP?
- Requires global hotkey registration
- More complex permission handling
- Can add later if needed

## Dependencies
- None (only system frameworks)
  - AppKit
  - Foundation
  - Network (or standard socket APIs)

## Open Questions
- None (design approved)
