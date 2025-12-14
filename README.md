# What's Hidden

A simple switcher for menu bar icons hidden behind the MacBook notch.

## Download

[Download the latest release](https://github.com/nothing-but-myself/whats-hidden/releases/latest)

## Installation

1. Download `WhatsHidden.dmg` from the [Releases](https://github.com/nothing-but-myself/whats-hidden/releases) page
2. Open the DMG and drag **What's Hidden** to Applications
3. Open Terminal and run:
   ```bash
   xattr -cr /Applications/WhatsHidden.app
   ```
4. Launch the app from Applications
5. Grant Accessibility permission when prompted (required for menu bar access)

> **Note:** The `xattr` command is required because the app is not signed with an Apple Developer certificate. This removes the macOS quarantine flag that blocks unsigned apps.

## Usage

| Shortcut | Action |
|----------|--------|
| `Ctrl + \`` | Open switcher / Next icon |
| `Ctrl + Shift + \`` | Previous icon |
| Release `Ctrl` | Confirm selection |
| `Esc` | Cancel |

## How It Works

1. Press `Ctrl + \`` on any screen
2. If the current screen has a notch and there are hidden icons, the switcher appears
3. If not, you'll see a friendly message
4. Release `Ctrl` to activate the selected icon's menu

The app only shows icons that are actually hidden behind the notch. No configuration needed.

## Build from Source

```bash
git clone https://github.com/nothing-but-myself/whats-hidden.git
cd whats-hidden
swift build -c release
cp -R .build/release/WhatsHidden /Applications/WhatsHidden.app
```

## Requirements

- macOS 12.0 (Monterey) or later
- Accessibility permission
- MacBook with notch (for full functionality)

## License

MIT with Commercial Restriction. See [LICENSE](LICENSE).

Free for personal use. Commercial use requires permission.
