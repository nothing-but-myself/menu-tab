# MenuTab

The App Switcher for your Menu Bar.

A ⌘Tab-style switcher for macOS menu bar icons. Quickly access icons hidden by the MacBook notch.

## Download

**[⬇ Download MenuTab-v0.0.1.dmg](https://github.com/nothing-but-myself/menu-tab/releases/download/v0.0.1/MenuTab-v0.0.1.dmg)**

Or see all releases: [Releases](https://github.com/nothing-but-myself/menu-tab/releases)

## Install

1. Open the downloaded `.dmg` file
2. Drag **MenuTab** to **Applications**
3. Remove quarantine attribute (required for unsigned apps):
   ```bash
   xattr -cr /Applications/MenuTab.app
   ```
4. Open MenuTab from Applications
5. Grant **Accessibility** permission when prompted:
   - Click "Open System Settings"
   - Enable MenuTab in Privacy & Security → Accessibility

## Usage

| Shortcut | Action |
|----------|--------|
| `⌃ \`` | Open switcher / Next icon |
| `⌃ ⇧ \`` | Previous icon |
| Release `⌃` | Confirm selection |
| `Esc` | Cancel |

**Menu bar options** (click the MenuTab icon):
- **Hidden Icons Only** — Only show icons hidden by the notch
- **Ignore List** — Exclude specific apps from the switcher

## Features

- **⌘Tab-style UI** — Familiar interface for switching menu bar icons
- **Notch-aware** — Detects icons hidden behind the MacBook notch
- **Multi-display** — Works correctly across multiple screens
- **Customizable** — Ignore list and hidden-only mode

## Build from Source

```bash
git clone https://github.com/nothing-but-myself/menu-tab.git
cd menu-tab
swift build -c release
open .build/release/MenuTab
```

## Requirements

- macOS 12.0 (Monterey) or later
- Accessibility permission

## License

MIT with Commercial Restriction. See [LICENSE](LICENSE).

Free for personal use. Commercial use requires permission.
