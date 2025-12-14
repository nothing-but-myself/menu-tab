# What's Hidden

A macOS menu bar switcher for hidden apps behind the notch.

## Project Overview

**Purpose**: A simple app switcher that helps users access menu bar icons hidden behind the MacBook notch.

**Trigger**: `Ctrl + `` (fixed hotkey, no configuration needed)

## Core Logic

```
User triggers hotkey
    └── Detect current screen (where mouse is)
            ├── Screen has notch?
            │       ├── Yes → Check for hidden apps
            │       │           ├── Has hidden apps → Show Switcher
            │       │           └── No hidden apps → Show Toast
            │       └── No → Show Toast
            └── Toast always shows on current screen
```

## Key Behaviors

1. **Switcher Display**: Only shows when there are actually hidden apps behind the notch
2. **Toast Display**: Shows on the current screen (where mouse is) with ❤️ icon and friendly message
3. **Menu Bar Position**: When switching to an app, its menu bar should ALWAYS appear on the built-in display (since only built-in displays have notches)

## Module Structure

```
Sources/WhatsHidden/
├── main.swift                 # App entry point
├── Core/
│   ├── SystemInfo.swift       # OS version, notch detection, Apple Silicon check
│   ├── Config.swift           # Configuration (if needed in future)
│   └── StatusBarIcon.swift    # Data model for menu bar icons
├── Services/
│   ├── StatusBarManager.swift # Icon discovery, activation, hidden detection
│   └── HotkeyManager.swift    # Global hotkey listener (Ctrl + `)
├── UI/
│   ├── SwitcherPanel.swift    # Cmd+Tab style switcher UI
│   ├── SwitcherController.swift # Switcher business logic
│   └── ToastPanel.swift       # Friendly toast with ❤️
└── App/
    └── AppDelegate.swift      # App lifecycle, permissions
```

## Removed Features (vs v2)

- ❌ Menu bar status item (no icon in menu bar)
- ❌ Ignore List functionality
- ❌ Hotkey configuration
- ❌ "Hidden Icons Only" toggle (now always shows only hidden icons)

## Technical Notes

### Notch Detection
- Use `safeAreaInsets` to detect notch presence
- Notch width is approximately 240px centered at top of screen

### Hidden Icon Detection
- Icon is "hidden" if it overlaps with the notch safe area
- Calculate overlap between icon frame and notch region

### Menu Bar on Built-in Display
- When activating an app, ensure focus goes to built-in display
- This keeps the menu bar visible (not hidden behind notch on external)

### Screen Detection
- Use `NSEvent.mouseLocation` to get current mouse position
- Find screen containing that point via `NSScreen.screens`

## Build & Run

```bash
swift build
swift run
```

## Hotkey

| Action | Hotkey |
|--------|--------|
| Open switcher / Next item | `Ctrl + `` |
| Previous item | `Ctrl + Shift + `` |
| Confirm selection | Release `Ctrl` |
| Cancel | `Esc` |

## Requirements

- macOS 12.0+ (Monterey)
- Accessibility permission required
- Apple Silicon Mac with notch (for full functionality)
