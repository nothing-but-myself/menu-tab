# MenuTab

**The App Switcher for your Menu Bar.**

A Cmd+Tab style switcher for macOS menu bar icons. Quickly access menu bar items hidden by the MacBook notch.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.7-orange)
![License](https://img.shields.io/badge/License-MIT%20with%20restrictions-green)

## Features

- 🔄 **Cmd+Tab Style Switcher** - Familiar UI for switching between menu bar icons
- 👁 **Notch Detection** - Identifies icons hidden by MacBook notch
- 🖥 **Multi-Screen Support** - Works correctly across multiple displays
- 🚫 **Ignore List** - Exclude apps you don't want in the switcher
- 👻 **Hidden Only Mode** - Focus only on icons hidden by the notch

## Installation

### Download

Download the latest `.dmg` from [Releases](../../releases), open it, and drag **MenuTab** to your Applications folder.

### Build from Source

```bash
git clone https://github.com/dongruixiao/menu-tab.git
cd menu-tab
swift build -c release
```

### First Run

1. Open MenuTab
2. Grant **Accessibility** permission when prompted:
   - System Settings → Privacy & Security → Accessibility → Enable MenuTab

## Usage

### Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl + \`` | Open switcher / Next icon |
| `Ctrl + Shift + \`` | Previous icon |
| Release `Ctrl` | Confirm selection |
| `Esc` | Cancel |

### Menu Options

Click the menu bar icon to access:

- **Hidden Icons Only** - Only show icons hidden by the notch
- **Ignore List** - Select apps to exclude from the switcher
- **Quit** - Exit MenuTab

## Requirements

- macOS 12.0 (Monterey) or later
- Accessibility permission

## How It Works

MenuTab uses the Accessibility API (`AXUIElement`) to:

1. Detect third-party menu bar icons via `AXExtrasMenuBar`
2. Determine which screen each icon is on
3. Calculate if icons are hidden by the notch using `safeAreaInsets`
4. Trigger icon actions via `AXPress` or `AXShowMenu`

## Configuration

Config file location: `~/.config/menutab/config.json`

```json
{
  "onlyShowHidden": false,
  "ignoredApps": ["com.example.app"]
}
```

## License

MIT License with Commercial Restriction. See [LICENSE](LICENSE) for details.

Personal and non-commercial use is free. Commercial use (including App Store distribution) requires permission from the author.
