# MenuTab

The App Switcher for your Menu Bar.

A ⌘Tab-style switcher for macOS menu bar icons. Quickly access icons hidden by the MacBook notch.

## Features

- **⌘Tab-style UI** — Familiar interface for switching menu bar icons
- **Notch-aware** — Detects icons hidden behind the MacBook notch
- **Multi-display** — Works correctly across multiple screens
- **Customizable** — Ignore list and hidden-only mode

## Install

Download `MenuTab-v0.0.1.dmg` from [Releases](../../releases), open it, drag to Applications.

Or build from source:

```bash
git clone https://github.com/nothing-but-myself/menu-tab.git
cd menu-tab
swift build -c release
```

**First run:** Grant Accessibility permission in System Settings → Privacy & Security → Accessibility.

## Usage

| Shortcut | Action |
|----------|--------|
| `⌃ \`` | Open switcher / Next |
| `⌃ ⇧ \`` | Previous |
| Release `⌃` | Confirm |
| `Esc` | Cancel |

Click the menu bar icon for options:
- **Hidden Icons Only** — Show only notch-hidden icons
- **Ignore List** — Exclude specific apps

## Config

`~/.config/menutab/config.json`

```json
{
  "onlyShowHidden": false,
  "ignoredApps": []
}
```

## Requirements

- macOS 12.0+
- Accessibility permission

## License

MIT with Commercial Restriction. See [LICENSE](LICENSE).

Free for personal use. Commercial use requires permission.
